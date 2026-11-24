# ADR 0007: Supervisor chain link

Status: Proposed (2026-11-25). Owner agreed to decoded video + audio + control
lane on 3.3 V LVCMOS (design brief O-11).

## Context

* Header banks are fixed at 3.3 V (ADR 0003): LVCMOS33 only, no LVDS_25.
* Video is 720×576@50 / 720×480@60, 27 MHz pixel clock, RGB888 + DE/HS/VS
  = 27 bits per pixel.
* Clock-capable pins exist only in header rows 4–19; rows 22–33 have none.
* Cables must avoid VIN (rows 1–2), VADJ (rows 9, 15, 21) and config pins.

## Decision

One **port** = 16 signals carried by **two identical 2x5 ribbons**
("CHAIN-A" = header rows 10–14, "CHAIN-B" = rows 16–20; each 8 signals + 2 GND).
Every node has a **down-link port on P12** (towards higher node numbers) and an
**up-link port on P13** (towards the master). A link is a straight ribbon pair
from node *n* P12 rows 10–20 to node *n+1* P13 rows 10–20, so the same pin
position is an output on one board and an input on the other.

| Port pin | Row/col | P12 ball (down-link, node n) | P13 ball (up-link, node n+1) | Direction (n ← n+1) |
|---|---|---|---|---|
| VCLK | A11 | K18 (MRCC) | C18 | n+1 → n forwarded 27 MHz clock |
| VD0..VD13 | other 14 signals | | | n+1 → n, DDR, 28 bits/pixel |
| CTL_DN | B19 | N19 | B16 | n → n+1 control (async serial) |

(Full per-pin table in `docs/cabling/chain-cable.md`.)

* **Forward (towards master)**: 14 DDR lanes at the pixel clock = 28 bits per
  pixel: 24 RGB + DE + HS + VS + 1 **sideband** bit. The sideband is a 27 Mb/s
  serial stream (framed, CRC-8) carrying audio samples, the upstream control
  records (topology replies, DUT LED state, link status) and training state.
  The receiver uses IDDR clocked by VCLK through BUFG/BUFR; clock centred by a
  90° MMCM phase shift on the receiving side (configurable, trained).
* **Backward (away from master)**: CTL_DN, 8N1-style async serial at 12.5 Mbaud,
  oversampled ×10 in `clk_sys`: keyboard snapshot, video/keyboard selection +
  epoch, LED commands, enumeration token. CRC-8 per frame; ~1 kHz full-state
  frames; stale epochs rejected.
* **Presence**: CTL_DN idles high when driven; the up-link receiver enables a
  weak pull-down, so "no neighbour" (steady low) is distinguishable from
  "neighbour present but not training" (high/garbage). The node whose up-link
  sees no neighbour is the master.
* **Training**: on link-up the sender emits a known pattern; the receiver
  learns per-lane inversion (cheap XOR) and picks the IDDR phase. Lane order is
  fixed by the cable (no lane-swap tolerance).
* When idle/not selected, VD lanes carry blanking with DE=0 and the sideband
  keeps running, so the link stays trained.
* Enumeration: master emits `ENUM(hop=0)` on CTL_DN; each node takes
  `index = hop+1`, forwards `hop+1`, and returns `{index, dna, caps}` records
  upstream in the sideband, appending downstream records. Max 4 hops; loops
  impossible on a point-to-point line.

## Consequences

* 54 Mb/s per lane over ribbon is modest; verify cable length on hardware.
* Raw TMDS symbol forwarding (preserving HDMI data islands) is rejected for now:
  it needs 270 Mb/s lanes with real deskew, ISERDES/OSERDES on every hop, and
  more nextpnr risk. Audio is carried as PCM in the sideband and re-emitted by
  the master's HDMI TX (phase 4).
* Both headers' rows 3–8 and 22–33 remain free for DUT/peripheral cables
  (ADR 0008).
