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
