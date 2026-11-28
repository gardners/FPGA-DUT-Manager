# ADR 0007: Links between supervisor boards

Status: Proposed (rewritten 2026-11-27; amended 2026-11-28: neighbour
link protocol, issue 0069). Supersedes the original ADR 0007
"Supervisor chain link: decoded video, 16 lanes, two 2x5 ribbons"
(2026-11-25), which is kept in summary below for the record.

## Context

* The ribbon chain (16 LVCMOS lanes per direction on header rows 10-20)
  never got built, and its pins are gone: the bench harnesses took rows
  10-22 (ADR 0008 amendments 3-5), and the shield pin plan
  (`docs/hardware/shield-pinplan.md` v1, issue 0049) uses 77 of the 80
  header signals for 4 DUTs per board.
* Owner decisions 2026-11-26/27 (issues 0044, 0045): KVM between boards
  runs over **Ethernet** (keyboard snapshots and live raster lines, no
  frame buffer); boards are discovered on the LAN; a unit is **two Mimas
  boards**, each with its own non-staggered shield; neighbouring shields
  have only a **UART** between them (a 12 V pass-through was considered
  and dropped in round 5).

## Decision

1. **Ethernet carries everything bulky or global**: board discovery and
   enumeration (heartbeat/DHCP, ADR 0011), selection, keyboard snapshots
   (1 ms + on change), remote video (raster lines relayed with H/V sync,
   issue 0044), thumbnails (0038), management. The boards share a gigabit
   switch (GS105) inside the unit; no board is special in hardware.
2. **Neighbour link on the shield** (issue 0045), one per board: one UART,
   `NB_UART_TX`/`NB_UART_RX` on P12 row 23 (G17/G18), 3.3 V LVCMOS, on a
   1x3 Dupont header (GND, TX, RX) with 100 ohm series resistors. Owner
   round 5: no 12 V pass-through and no right-angle side connector (each
   Mimas gets its own 12 V lead from the power board, on a Mini-Fit Jr).
   With two boards per unit there is exactly one neighbour. Use: low-latency
   hints between neighbours (e.g. "I am master", a fallback path when the
   switch is down). Both boards run the **same supervisor image** (issue
   0069); on the bench (no shield) the link is three crossed jumpers
   (row 23 A to row 23 B both ways, GND on row 24). Protocol: section
   "Neighbour link protocol" below.
3. **No chain clock/video lanes.** If Ethernet latency ever proves too
   high, the fallback is a faster Ethernet path, not a ribbon.

## Consequences

* Header pins: 2 for the neighbour UART instead of 32 for a chain port.
* Remote video depends on the switch's bandwidth (one 480p/576p stream,
  ~500 Mb/s raw, fits a gigabit link); the master's HDMI OUT follows the
  remote board's relayed sync (0044).
* More than two boards per unit: the single UART cannot serve two cabled
  neighbours (two TX outputs would meet on RX); a future shield revision
  would need a second UART pair (no spare pairs on v1 apart from 3 single
  spares).

## Neighbour link protocol (amendment 2026-11-28, issue 0069)

**Physical.** UART 8N1, LSB first, idle high, **1 Mbaud** (NCO increment
0x020C49BA at 125 MHz, 125 clocks per bit, exact to 1e-8). Why 1 Mbaud:
fast enough for phase 2 (tunnelled control traffic, ~100 kB/s) and a HELLO
takes 0.35 ms; slow enough for unshielded Dupont jumpers or the shield's
100 ohm series resistors with SLEW SLOW / 8 mA drivers (bit time 1 us vs.
edges of a few ns, no termination needed); and a standard USB-UART (FT232,
CP2102) can sniff it. TX (G17) is always driven; RX (G18) has a PULLUP, so
an open link reads idle and counts nothing.

**Frame** (all multi-byte fields big-endian):

| Off | Size | Field |
|---|---|---|
| 0 | 2 | sync `A5 5A` |
| 2 | 1 | type: 0x01 HELLO; 0x02-0xFF reserved (phase 2) |
| 3 | 2 | len: payload bytes, 0..1600 |
| 5 | len | payload |
| 5+len | 2 | CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection, no final xor; check value 0x29B1 for "123456789") over type, len and payload |

A frame's bytes are sent back to back. The receiver hunts for `A5 5A`
(`A5 A5 5A` also syncs), and drops the frame and hunts again on: a length
above 1600 or outside the type's range (format error), a UART framing
error, a CRC mismatch (CRC error), or more than 32 bit times without a
byte mid-frame (format error). So garbage costs at most the frame it hides
in: after a bogus header the byte timeout (the 100 ms HELLO gaps) resyncs.
Frames of an unknown type with a good CRC are counted and ignored, so new
types never confuse old images.

**HELLO** (type 0x01, len 28 in version 1; receivers accept 26..64 and use
the first 26 bytes, so later versions may append fields):

| Off | Size | Field |
|---|---|---|
| 0 | 2 | magic `0x4E42` ("NB") |
| 2 | 1 | version (1); 0 is invalid |
| 3 | 1 | DIP switches (board number B = bits 7..4) |
| 4 | 1 | role claim: 0 standalone, 1 primary, 2 secondary |
| 5 | 1 | flags: b0 the sender hears a peer, b1 B clash, b2 loopback |
| 6 | 8 | board DNA (57 bits, as heartbeat bytes 20..27) |
| 14 | 4 | build_id |
| 18 | 4 | boot_id (as the heartbeat; fixed once Ethernet has seen a frame) |
| 22 | 4 | seq: +1 per HELLO from 0 at configuration (x 100 ms = uptime) |
| 26 | 2 | reserved, 0 |

Sent every **100 ms**. The peer is **present** while a valid HELLO (good
CRC, magic, version >= 1) with a DNA different from ours arrived in the
last **350 ms**, i.e. it is lost after ~3 missed HELLOs. A HELLO carrying
our own DNA sets *loopback* and never makes a peer present.

**Role rule.** No peer: standalone. Peer present: the board with the lower
B (DIP[7:4]) is **primary**, the other secondary; equal B is a
configuration error ("B clash", flagged in the heartbeat and the HELLO):
the lower DNA is primary. Both ends apply the rule to the same data, so
they agree whenever both directions work; a one-way link shows as a role
mismatch (heartbeat nb_flags b6) and "peer does not hear us" (b4 clear).
Phase 1 only reports the role (heartbeat neighbour block, ADR 0005 section
3f); `nb_status.primary` in `supervisor_core` is the hook for issue 0044.

**Phase 2 (not implemented).** Tunnelling host traffic through the peer
while a board has no Ethernet adds frame types (e.g. 0x10 tunnelled
Ethernet frame, payload = the frame without preamble/FCS, len <= 1600;
0x11 flow control/credit); the framing, CRC and resync stay as above.
At 1 Mbaud the tunnel carries ~90 kB/s: heartbeats, management and UART
snapshots, not video.

## Superseded design (2026-11-25, for reference)

One port = 16 signals on two 2x5 ribbons (rows 10-14 and 16-20), down-link
on P12, up-link on P13; 14 DDR lanes forwarded decoded RGB + sync + a
sideband (audio, control) at the 27 MHz pixel clock, and a 12.5 Mbaud
control line downstream; enumeration by hop count. Dropped because the pins
went to the DUT harnesses and the shield, and Ethernet does the job without
cables (issues 0044, 0045). `docs/cabling/chain-cable.md` describes the old
cable and is obsolete.
