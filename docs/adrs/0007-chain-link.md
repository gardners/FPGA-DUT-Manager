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
   switch is down); protocol to be defined when needed.
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
