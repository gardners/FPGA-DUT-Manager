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
