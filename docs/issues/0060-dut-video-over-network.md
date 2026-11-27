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
