# 0060: DUT video over the network for boards without HDMI capture (K325T)

Status: waiting for the owner's module (owner request 2026-11-27). Related:
0057 (K325T), the thumbnail/mosaic work (0034, 0038), hardweb issue 0169
(~/Projects/hardweb/issues/0169-inter-board-vlan-and-video-stream.md,
protocol docs/console_video_stream_protocol.md in that repo, "HWVS v1").

## Request (owner, 2026-11-27)

Hardweb issue 0169 describes a protocol for asking a board to stream its
video over VLAN 1650 for 1 s whenever it sees a heartbeat requesting this.
The request also says whether it wants full, half or quarter resolution, as
though the board were one of the Mimas A7 supervisors. The owner is having
the HewnWeb LLM prepare a module that can be pulled in for this, and will
say when it is there.

## Notes (lead)

* On our side: the supervisor (or dutctl) sends the 1 s REQUEST heartbeats
  for DUTs that have no HDMI capture (e.g. the K325T on DUT1), receives the
  stream, and feeds it into the same paths as the HDMI thumbnails
  (mosaic, `dutctl screenshot`).
* Hardweb 0169 currently describes text cells (80x25 char+attr) with pixel
  formats reserved; the owner's request mentions full/half/quarter
  resolution like our thumbnails. Reconcile when the module arrives.
* VLAN 1650 tagging on the host side is a host network change the owner
  makes; the supervisor's network path would need 802.1Q handling.

### 2026-11-27 owner

On hold: the HWVS description in the hardweb repo is being corrected, so
nothing is implemented yet. Meanwhile, screen text from a HewnWeb build on
the K325T can come over its UART (now wired, issue 0057).

### 2026-11-27 hardweb session (hardweb-95), settled design

HWVS is settled on their side: the HewnWeb K325T build becomes a **source in
our thumbnail relay (ADR 0005 section 10)**, byte-exact with our
tests/netproto.py, plus small extensions in fields we currently send as 0.
The exact list is in hardweb docs/hwvs_implementation.md section 7
("Extensions ... the KVM side must add"):

* request byte 6 flags: b0 targeted, b1 priority; byte 7 target machine;
* scale 3 = 1/1 (full resolution);
* requests at 2 Hz, 1 s timeout; drop, don't queue;
* our traffic onto VLAN 1650;
* accept relayed video for local slots that have no HDMI input.

**Not to be implemented until the owner says so.** Read that section
before starting.

Coordination: the hardweb session will load the K325T with
targets/qmtech-k325t/k325t.sh (on / load / off, relay channel 5 only) and
never touch the SPI flash. It prepares the 16 GB J9 card itself. Its status
page is hardweb docs/boards/qmtech_k325t_bringup.md. Its K325T top has the
UART on JP1 (B26 TX / C26 RX), in hardweb staging-20261127-k1, 5803f5f.
Both sessions now drive relay 5 and DUT1's JTAG, so check with it before
using the K325T.

### 2026-11-27 owner: implement it

* The lead no longer controls the K325T's power or JTAG; the hardweb
  session does. The lead keeps the Mimas supervisor (JTAG, LAN).
* Implement the KVM side now: move inter-board traffic onto VLAN 1650 and
  add the section 7 extensions, so that the owner can switch targets with
  the MEGA65 keyboard hot key and see video from both the MEGA65 (local
  HDMI) and the K325T (relayed).
* New: when the **selected** target has no local video, keep requesting its
  stream (targeted, priority, 1/1, 2 Hz) and show it **full-resolution in
  real time**, not just as a thumbnail.

### 2026-11-27 implemented (sub-agent, branch feature/hwvs-vlan)

Status: implemented and simulated; not yet tried on hardware. ADR 0005
section 10 and the key table carry the details.

**Machine number of DUT1.** Machine = DUT ID nibble * 2 + half (issue 0029:
P12 half 0, P13 half 1). The bench board has DIP 0x00 (DUT IDs 0x00 /
0x10), so DUT0 (MEGA65) is machine 0 and **DUT1 (K325T) is machine 1**
(hot-key digit "2"). In general DUT1 = 2 * DIP[7:4] + 1. The hardweb K325T
build needs `board_n = 1`.

1. **VLAN** (key 0x0043, u16, default 1650, 0 = untagged as before). The
   only inter-Mimas traffic today is the thumbnail relay: requests
   (broadcast), lines and "present, no source" frames to a requester. They
   carry the 802.1Q tag (TPID 0x8100, PCP 0, VID); relay frames are
   accepted only with that VID. Host-facing traffic is untagged: all UDP
   (heartbeats, MGMT, UART, JTAG/XVC, raster, DHCP, ARP, ICMP) and relay
   frames to the key 0x0041 forced MAC (`dutctl thumbs --force`).
   `dutctl thumbs --request` now needs `--vlan 1650` (or key 0x0043 = 0).
   RX: thumb_rx_tap skips the 4 tag bytes by rewinding its parse index, so
   every offset is the untagged one; frames are padded to 60 + FCS as
   before (a tagged request has 26 bytes of header and body).
2. **Request extensions**: byte 6 flags (b0 targeted, b1 priority), byte 7
   target machine, scale 3 = 1/1, requests at 2 Hz (select screen: 500 ms
   instead of 250 ms), 1 s source timeout (unchanged). Our source ignores
   requests targeted at other machines and streams only the target of a
   targeted request. **Our own source stays at 1/2 / 1/4**: a scale 3
   request is answered at 1/2 (its frames say scale 1). 1/1 from our own
   capture would need a 720-pixel thumbnail store and a full-rate sender;
   not needed for receiving the K325T. Priority (b1) is accepted; our
   sender already sends relay frames below control traffic and above
   telemetry and never queues (latest picture wins).
3. **Relayed video for local slots without a source.** New key 0x0044 HDMI
   IN owner: 0 (default, as before) the video target's DUT; 1 DUT0; 2 DUT1;
   3 none. A local machine that does not own the HDMI IN takes relayed
   frames for its machine number: thumbnails in its mosaic tile, "seen",
   no "present, no source" from us while relayed pictures arrive. With 1..3
   the HDMI IN is always captured as its owner's machine (the MEGA65 tile
   stays live while DUT1 is selected), and passthrough / raster capture
   only happen for the owner.
4. **Selected target with no local video** (video target = a local machine
   that does not own the HDMI IN, console screen auto, no selection
   pending): targeted, priority, scale 3, divisor 1 requests every 500 ms;
   the 1/1 pictures (RAW888/RLE24 per line) go into a **triple-buffered**
   DDR3 frame buffer (mem_pkg `full_addr`, 0x200000 + buffer * 0x40000,
   row stride 256 words); `full_display` (new, DDR3 arbiter port 5) scans
   the last complete picture out 1:1 in the 720x480p60 console raster
   (switches buffers only at vertical blank: never torn; a new picture
   never overwrites the buffer being shown or the last complete one). A
   576-line picture shows its centre 480 lines, a narrower one is black on
   the right. Without a complete picture in the last second the console
   shows "no video". Heartbeat byte 109 (console shown) = 4 "relayed"
   while the full view is on. Passthrough of the MEGA65 is unchanged when
   DUT0 is selected. Mosaic unchanged except that it includes relayed
   local slots.
5. **Bandwidth.** 720x480 RAW888 at 60 Hz is 62 MB/s (~500 Mb/s), within
   gigabit (125 MB/s). RX: the tap parses at line rate (1 byte/cycle); the
   writer expands one RAW888 pixel per ~2.25 clk_sys cycles (55 Mpx/s;
   the line delivers at most 41.7 Mpx/s), RLE24 runs at 4 pixels per
   word write. DDR3: ~5.2 M words/s written plus 5.2 M read by the display
   (~166 MB/s of the x16 DDR3-800's 1.6 GB/s). The tap's 2048-entry FIFO
   absorbs ~50 us of DDR3 stall at full RAW rate. So the full 60 Hz should
   be sustainable; anything the source cannot send it drops (it never
   queues), and a picture with a lost frame is simply not shown.
6. Tests: `tests/netproto.py` selftest (make test-sw: the section 7 bytes
   `01 01 4D 36 01 02 00 00` / `01 01 4D 36 03 01 03 05`, the tag, padding,
   a scale 3 frame), C vectors, tb_thumb_rx (VLAN filter, relayed local
   slot, 1/1 into the triple buffer with a partial last word), tb_thumb_tx
   (2 Hz, full-view requests, targeted requests, tag only to requesters),
   tb_full_display (new: every pixel of 720x480 and 640x576, no tearing on
   a mid-frame switch, off = no reads), tb_supervisor_core (tagged
   requests on VLAN 1650 for DUT1's machine, full view shown).

**How to test (lead).**

Prerequisites: the switch between the Mimas and the K325T must pass VLAN
1650 tagged frames (an unmanaged switch does; a managed one needs VLAN 1650
tagged on both ports). The host needs nothing (its traffic stays untagged).
Hardweb K325T build: `hwvs_video_tap` wired in, `board_n = 1`, `vlan_id =
1650`, `enable = '1'`, its MAC on the same segment, gigabit link.

Without the K325T build running (regression):
1. Load the bitstream; `scripts/hwtest.sh` must stay green (it now also
   checks keys 0x0043/0x0044 and restores 1650 / 0).
2. MEGA65 passthrough on DUT0 as before (key 0x0044 = 0, default).
3. `dutctl set BOARD_IP hdmi-owner 1` (DUT0 owns the HDMI IN). Select DUT1
   with the hot key (both SHIFTs >= 1 s or the LSHIFT/MEGA train, tap MEGA,
   then "2"): HDMI OUT shows the "no video" screen, heartbeat
   console_screen 1; on a mirror port / `tcpdump -e -i IF vlan 1650` (needs
   a port that sees broadcasts) a tagged request every 500 ms from
   02:4d:36:35:00:00 to ff:ff:ff:ff:ff:ff, body `01 01 4d 36 03 01 03 01`.
   "1" goes back to the MEGA65 (passthrough).
4. Select screen: MEGA65 tile live (it stays live while DUT1 is
   selected), DUT1 tile colour bars.

With the K325T build running:
5. Key 0x0044 = 1 as above. Select DUT1 ("2"): within ~1 s HDMI OUT shows
   the K325T's 720x480 console full-screen and live (heartbeat
   console_screen 4 = "relayed"); "1" returns to the MEGA65 passthrough.
6. Select screen: the DUT1 tile shows the K325T thumbnail (1/2, live).
7. Host screenshot of the K325T relay: `sudo dutctl thumbs IF --request
   --vlan 1650` needs the host NIC to see tagged frames; untagged
   `--force BOARD_IP` only covers this board's own capture.
8. Failure modes: no picture -> check `board_n` (= 1), VLAN, the switch,
   the K325T's `refused` (enable); heartbeat rx_bad rises with every
   relay frame (oversize for the 2 KiB RX slots, as with thumbnails).

Build (Vivado, commit e4f8df7, build id e4f8df7d): **TIMING MET, WNS
+0.143 ns, WHS +0.019 ns**; 19125 LUTs (58.7 %), 35 BRAM tiles (46.7 %),
MMCMs 5/5, PLLs 2/5. `make test` green: 35 HDL testbenches, netproto
selftest, 885 dutctl checks, 52 relay checks. Not loaded on hardware.
Bitstream: build/vivado/supervisor.bit in the feature/hwvs-vlan worktree.

### 2026-11-27 relay counters (issue 0061)

The heartbeat now carries a relay block (ADR 0005 s3d, bytes 160..187):
requests sent / full, frames heard (lines, bad, FIFO overflow, no source,
VLAN drops, > 2047 bytes, not taken), full pictures completed / shown, the
full view's state and the last frame's machine and scale; `dutctl listen`
prints them. thumb_rx_tap reads the GMII stream directly (not the MAC's
2 KiB slots), so 1/1 frames up to ~8 KB are received; the switch path must
pass jumbo frames. Details and a debugging table in issue 0061.

### 2026-11-27 lead: first end-to-end run (build 86aa5659 + HewnWeb K325T fb7a947)

The relayed full view works end to end: VLAN 1650, board_n 1 and the
switch are fine (0 VLAN drops, 0 foreign frames). Over 5 s with machine 1
selected: 10 targeted 1/1 requests sent; ~3286 good lines frames from m1
and ~919 dropped on our side (receive FIFO overflow), i.e. ~840 frames/s
(~5 pictures/s, ~5.5 MB/s) arriving, but only ~1.4 complete pictures/s
shown, because one lost frame kills a picture. Fix in progress
(feature/relay-rx-speed): RX buffering/DDR3 write rate, plus a live
line-by-line view mode.

### 2026-11-27 relay-rx-speed (sub-agent, feature/relay-rx-speed)

Requests: lead (hardware data of build 86aa5659: ~22 % of 1/1 frames lost
to receive FIFO overflow, ~1.4 complete pictures/s), owner (via hardweb
session) "the KVM display can just ignore lost rasters, but getting it to
not lose so many packets would be good", and owner suggestion: a receive
FIFO of 4-8 whole frames, plus counters showing its high-water mark and
how often the writer stalls, to confirm DDR3 contention on hardware.

**Analysis.** New `tb_relay_burst` streams 720x480 RAW888 pictures as
back-to-back 3-line 1/1 frames (6530 bytes + preamble/gap: 125 MB/s, 41.4
Mpx/s, one 16-byte word per 96 ns) through tap -> writer -> mem_arbiter ->
mem_app_bridge -> mig_ui_model, with full_display scanning 720x480p60 the
whole time and a thumbnail-capture-like writer in bank 0. mig_ui_model got
DDR3 timing (generics, default off): a command to a bank with another row
open costs 5 UI cycles (tRP + tRCD, + tWR after writes), a read/write
change 3, refresh 12 every 7.8 us. Old design (git 098d177), 2 pictures:

| model | frames lost | tap FIFO peak |
|---|---|---|
| no DRAM timing, no random stalls / with random stalls | 0 / 0 | 6 / 8 of 2048 |
| no display reads, full DRAM timing | 0 | 7 |
| display + turnaround only (row miss 0) | 0 | 24 |
| display + row miss only (turnaround 0) | 0 | 264 |
| display + row miss 5 + turnaround 3 (no random stalls) | 170 / 320 | full |
| display + full timing + random stalls | 187 / 320 (58 %) | full |

So it is **DDR3 contention, not average bandwidth** (the owner's
suspicion): all three full buffers were in DDR3 bank 1 (0x200000 +
buf * 0x40000; MIG BANK_ROW_COLUMN puts the bank in word bits 23..21), and
mem_arbiter alternated the writer and full_display **word by word**. While
the display fetches a line (180 words, ~1/3 of every line time), each
writer word is sandwiched between reads from another row of the same bank:
two turnarounds + a precharge/activate, ~160 ns per written word against
the 96 ns the link delivers one in. The writer itself (2.25 clk/pixel =
55 Mpx/s) and the 2048-entry FIFO (< 1 frame: 2164 entries per frame) left
no slack to ride that out. The real MIG (4 bank machines, normal ordering)
reorders a little, hence 22 % on hardware instead of 58 %.

**Fix.**
* `mem_pkg.full_addr`: buffer b in its own bank, word address (1 + b) *
  0x200000 (+ row * 256 + col / 4). In complete-picture mode the writer and
  the display never share a bank; this alone removes the losses in the
  model.
* `mem_arbiter` generic BURST (32 in the top): a port that keeps requesting
  keeps the grant for up to 32 words, so a change between clients (and
  its turnaround / row miss) is paid per 32 words, not per word. Needed for
  the live view (writer and display in the same bank): memory-wait time in
  the model drops from 1456 to 343 x 2.048 us over both phases.
* `thumb_rx_writer`: a RUN entry is expanded in the cycle it is taken (1
  pixel/clk = 125 Mpx/s, 3x the link), finished words with their address go
  into a 512-word FIFO which is offered to the arbiter in batches (16 words
  or 64 cycles), so its bursts stay together.
* `thumb_rx_tap` FIFO 2048 -> **16384 entries (16 BRAM36, ~7.5 whole
  frames, ~400 us of line rate with the writer stopped)**. This is the
  owner's frame FIFO in equivalent form: the tap keeps parsing at line rate
  and its 36-bit entries already carry the frame boundaries and the END
  good/bad verdict (FCS, header, overflow), so a bad frame is discarded at
  the read side (its rows never count) exactly as with a 9-bit byte FIFO
  with an end-of-frame bit, without moving the parser to clk_sys. (A byte
  FIFO is 9 bits/byte = 27 bits per RAW pixel against 36 here: 16 tiles
  would hold ~9.8 frames instead of 7.5.) Overflow already loses only the
  frame that hit it; the next frame starts clean.
* Result in the model: 320 back-to-back frames (2.1 MB, 16.7 ms, 2
  pictures) with display reads, full DRAM timing and random stalls: 0 lost,
  **tap FIFO peak 3 entries, word FIFO peak 14 of 512, writer stalls 0**;
  still 0 lost with doubled (10/6) and quadrupled (20/10) DRAM penalties.

**Live view, key 0x0045 relay-view** (ADR 0005): 0 complete pictures only
(triple buffered, never torn, as before); **1 live line by line
(default)**: a new picture is written into the buffer the display shows
(full_buf is kept), every good 1/1 frame pulses full_ev (fresh/age follow
frames, width/height the last frame), lost rows keep the previous picture.
Pixels are written as they arrive, so a frame that turns out bad (FCS) can
leave wrong pixels in its rows until they arrive again; in mode 0 they only
reach a hidden buffer. Switching modes mid-picture can show one torn /
mixed picture. Counters: rl_full_pics still counts complete pictures (all
rows of one frame number) in both modes; rl_full_swaps = buffer changes in
mode 0, and in live mode the displayed frames that had new lines since the
frame before (full_display now pulses `frame` at its vertical-blank latch).
relay_flags b6 = live. `dutctl set IP relay-view 0|1`; hwtest keytest
(restored to 1).

**Receive load counters** (heartbeat bytes 188..195, payload 180 -> 188):
rl_fifo_hwm (tap FIFO peak in the last second, entries), rl_wr_stall
(writer waiting for its word FIFO = DDR3 back-pressure, 2.048 us units),
rl_mem_wait (words offered, DDR3 port busy), rl_wf_hwm (word FIFO peak /
2), rl_fifo_aw (14). `dutctl listen`: `rx fifo peak N/16384 wf peak N stall
N wait N`; hwtest INFO "relay rx load". On hardware with the K325T
streaming: expect rl_rx_ovf flat, rl_fifo_hwm small (hundreds at most);
if rl_rx_ovf still rises, rl_fifo_hwm = 16384 and a rising rl_wr_stall
prove DDR3 is the limit.

Tests: tb_relay_burst (phase A: complete mode, 2 pictures back to back, 0
bad / 0 overflow, 2 pictures complete, buffer contents = picture 2 word by
word; phase B: live mode, picture 3 with every 7th frame left out: no
picture completes, full_ev per frame, the live buffer becomes the shown
one, its rows = picture 3 except the missing frames' rows = picture 2).
tb_thumb_rx / tb_full_display folds updated for the bank layout;
tb_supervisor_core: key 0x0045 bad value / set, live flag and receive-load
block in the heartbeat (64 good RX frames). netproto selftest (layout +
round trip of 188..195), C vectors heartbeat_rxload, mgmt_relay_view.
