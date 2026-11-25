# 0042: `dutctl screenshot`: one-shot screen capture to PNG

Status: Implemented, checked on hardware (2026-11-25)
Opened: 2026-11-25 (owner request)

Taking a screenshot today means several manual steps: point the video
target's capture destination at this host (keys 0x0003/0x0004), enable
capture (0x0040), run `dutctl video`, then restore the settings. Add:

    dutctl screenshot TARGET [-o FILE.png|.ppm] [--screen auto|editable|novideo|select]
                             [--timeout S]

* TARGET is an endpoint IP, or one of the digits the console's select
  screen shows (1-9 then 0, which is machine 0..9; owner's "bonus"). A
  digit is resolved by listening to heartbeats (machine = dut_id low nibble
  * 2 + DUT index), across all boards.
* Capture comes only from the board's HDMI video target DUT. If the
  machine is not one, report that clearly instead of hanging.
* Sets this host's IP/MAC as the unicast destination (never broadcast),
  enables capture, waits for one complete frame, writes PNG (or PPM by
  extension), then restores capture off and the previous destination.
  This also restores on SIGINT and on errors.
* `--screen` optionally forces the console screen (key 0x0035) for the
  shot and restores auto afterwards.

## Owner additions (2026-11-25)

1. TARGET is optional: with none, heartbeats are heard and the one machine
   that can be captured (its board's video target, HDMI capture capability,
   video locked) is used; if several can, they are listed with their console
   digits; none is reported as such.
2. Default output `mega65-screenshot-NNNNNN.png` in the current directory,
   lowest free number from 000000, created with `O_CREAT|O_EXCL` (never
   overwrites). `-o` overrides.
3. `dutctl -S [TARGET] [options]` is an alias (m65's `-S`).

## Progress

* 2026-11-25: implemented on `feature/dutctl-screenshot`.
  * `sw/dutctl/src/pngwrite.c`: PNG encoder (8-bit RGB, filter byte 0 per
    row, zlib with stored deflate blocks, CRC-32, Adler-32), no library.
  * `sw/dutctl/src/screenshot.c`: pure target logic. Machine =
    (dut_id & 0x0F) * 2 + (dut_id >> 4 & 1), the same as supervisor_core's
    m0 = id0(3:0)&'0', m1 = id1(3:0)&'1'; digit d -> machine (d + 9) % 10;
    board video target = `selected` hi nibble if < 2 (supervisor_core
    `sel_vid < 2`); sibling endpoint by DNA + boot id; capturable list.
  * `cmd_screenshot` in `main.c`. The management protocol cannot read keys,
    so capture enable (0x0040) is restored to its state from the heartbeat
    (video_flags b2), 0x0003/0x0004 go back to broadcast (the documented
    default) and 0x0035 goes back to auto only if `--screen` forced it.
    Restore runs on success (before writing the file), errors, timeouts,
    SIGINT/SIGTERM/SIGHUP and `exit()` (atexit). The source IP comes from a
    connected UDP socket's `getsockname`, the interface from `getifaddrs`
    and the MAC from `/sys/class/net/IF/address`. Broadcast, multicast and
    zero targets and MACs are refused.
  * `mgmt_set` now seeds its cmd_id once per process and increments it.
    Before, consecutive sets in the same second reused one cmd_id, which the
    FPGA acks as a duplicate without applying.
  * Tests (`make test-sw`): CRC/Adler reference values; a structure, CRC,
    stored-block and Adler check of encoded PNGs (3x2, and 720x480 = 16
    blocks); a Python zlib (+ PIL if present) decode of the 720x480 test
    PNG (`sw/dutctl/tests/check_png.py`); digit <-> machine, dut_id ->
    machine, and video target / sibling / capturable selection.
  * Hardware (board 203.28.176.86/.87, dut1 = video target). Its HDMI IN
    currently shows a HewnWeb status screen, not the self-loop, so
    `--screen` does not change the picture.
    `dutctl screenshot 2 -o shot-m1.png --screen select` gave 720x480,
    frame 719400. `dutctl -S` (no target) twice gave
    `mega65-screenshot-000000.png` and `-000001.png`.
    `screenshot 203.28.176.87 -o x.ppm` worked. `screenshot 1` gave
    "machine 0 (console 1, dut0 203.28.176.86) is not its board's video
    target; the video target on that board is machine 1 (console 2, dut1
    203.28.176.87)", exit 1. SIGINT during capture gave exit 130, with the
    settings restored. `--timeout 0.3 --screen select` gave the timeout
    message, with the settings restored. After every run, heartbeats were
    addressed to 255.255.255.255 again (checked with IP_PKTINFO), the
    capture flag was as before and the console screen was back to
    passthrough. PIL opens the PNGs as 720x480 RGB.
