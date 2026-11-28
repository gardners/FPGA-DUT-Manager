# 0069: Neighbour UART between two supervisors (same image, peer/role detection)

Status: in progress (owner, 2026-11-28). Related: ADR 0007 (neighbour link:
P12 row 23, G17 TX / G18 RX), 0044 (cross-board KVM over Ethernet), 0068
(test-DUT image: superseded as the plan for Mimas #2, kept as an optional
bench tool), shield pin plan.

## Owner (2026-11-28)

"Both boards talk to DUTs using the same pins. The only difference is the
pins the Mimas board uses to talk to its peer: And we can just make that a
cross-over UART, right? The video all goes via the ethernet [...] It's
arguably _easier_ to adapt the primary image to support this, than to make
a separate one."

So Mimas #2 is a **second supervisor running the same image** (its own
DUTs on its own DUT pins; DIP sets its IDs, board number B = DIP[7:4]),
linked to #1 by the ADR 0007 neighbour UART. The lead had wrongly planned
#2 as a fake DUT (0068).

## Wiring (bench, no shield yet): 3 jumpers, crossed

| #1 P12 | #2 P12 | Signal |
|---|---|---|
| row 23 A (G17, NB TX out) | row 23 B (G18, NB RX in) | #1 -> #2 |
| row 23 B (G18, NB RX in) | row 23 A (G17, NB TX out) | #2 -> #1 |
| row 24 A or B (GND) | row 24 A or B (GND) | ground |

Row 23 is free on the bench pin map; row 24 is a ground row. Never a
full-width cable (rows 1-2 are raw VIN).

## Phase 1 (this issue)

Neighbour UART in the supervisor image: periodic HELLO both ways (board
DNA, B = DIP[7:4], build id, a role claim), peer presence/role/board
number/build in the heartbeat, role rule (lower B is primary; equal B ->
lower DNA; no peer heard -> standalone). Outputs: NB TX idles high only
while the link is enabled; harmless if unconnected (RX with a pull-up so
an open link reads idle). Phase 2 (owner question): tunnel host traffic
through the peer while a board has no Ethernet.
