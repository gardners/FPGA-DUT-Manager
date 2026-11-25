# 0042: `dutctl screenshot`: one-shot screen capture to PNG

Status: Open
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
