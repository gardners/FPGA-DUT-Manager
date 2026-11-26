# ADR 0007: Links between supervisor boards

Status: Proposed (rewritten 2026-11-27). Supersedes the original ADR 0007
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
  have only a **UART** between them, plus optionally 12 V pass-through on
  a right-angle connector.

## Decision

1. **Ethernet carries everything bulky or global**: board discovery and
   enumeration (heartbeat/DHCP, ADR 0011), selection, keyboard snapshots
   (1 ms + on change), remote video (raster lines relayed with H/V sync,
   issue 0044), thumbnails (0038), management. The boards share a gigabit
   switch (GS105) inside the unit; no board is special in hardware.
2. **Neighbour link on the shield** (issue 0045), one per board:
   * one UART, `NB_UART_TX`/`NB_UART_RX` on P12 row 23 (G17/G18), 3.3 V
     LVCMOS, 100 ohm series resistor per side connector;
   * on each side edge of the shield a 1x3 Dupont header (GND, TX, RX)
     and a 1x4 right-angle connector (12V, TX, RX, GND). Side A (P12 edge)
     is a socket, side B (P13 edge) is a pin header with TX/RX swapped, so
     two shields plug together directly or with a straight 4-way lead;
   * 12 V pass-through on pin 1 through a 2 A polyfuse per side, so one
     power-board feed can supply both Mimas of a unit.
   Both side connectors carry the same UART: with two boards per unit only
   one side is cabled. Use: low-latency hints between neighbours (e.g.
   "I am master", a fallback path when the switch is down, wake-up),
   protocol to be defined when needed.
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

## Superseded design (2026-11-25, for reference)

One port = 16 signals on two 2x5 ribbons (rows 10-14 and 16-20), down-link
on P12, up-link on P13; 14 DDR lanes forwarded decoded RGB + sync + a
sideband (audio, control) at the 27 MHz pixel clock, and a 12.5 Mbaud
control line downstream; enumeration by hop count. Dropped because the pins
went to the DUT harnesses and the shield, and Ethernet does the job without
cables (issues 0044, 0045). `docs/cabling/chain-cable.md` describes the old
cable and is obsolete.
