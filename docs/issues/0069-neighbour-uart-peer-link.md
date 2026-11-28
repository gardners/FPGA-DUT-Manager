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

## Progress 2026-11-28 (sub-agent, branch feature/neighbour-link)

Phase 1 implemented, not yet tested on hardware:

* `hdl/src/net/neighbour_link.vhd` (inside `supervisor_core`): 1 Mbaud
  8N1, HELLO every 100 ms, peer counts as present for 350 ms after its
  last HELLO, role rule, counters. The protocol is in the ADR 0007
  section "Neighbour link protocol" (frame `A5 5A type len16 payload
  CRC-16/CCITT-FALSE`, HELLO v1 = 28 bytes). `nb_status.primary` is the
  hook for 0044. No other behaviour changes; the seven-segment display is
  unchanged. The link is always on: TX is always driven and idles high,
  with no enable key.
* Pins: `nb_uart_tx` G17 (LVCMOS33, 8 mA, SLOW), `nb_uart_rx` G18
  (PULLUP), both in `mimas_a7.xdc`, so they apply to the normal and the
  shield build alike.
* Heartbeat neighbour block, bytes 208..235 (ADR 0005 s3f, payload 228).
  `dutctl listen` prints `nb <role> peer B<n> (...) rx/tx [err ...]`;
  `--kv` adds `has_nb nb_flags nb_role nb_peer_dip nb_peer_b nb_peer_role
  nb_peer_dna nb_peer_build nb_rx_frames nb_crc_errs nb_uart_errs
  nb_fmt_errs nb_tx_frames nb_peer_seq`.
* Tests:
  * `tb_neighbour_link`, two instances cross-connected: HELLO exchange,
    presence timeout, B clash, DNA tiebreak, and injected frames (bad
    CRC, truncated frame, garbage then a good HELLO, unknown type, short
    HELLO, break, bad magic). The HELLO bytes are checked with
    netproto.py.
  * `tb_supervisor_core` now has a peer instance.
  * netproto selftest, and the dutctl vector `heartbeat_nb`.
  * `make test`: 42 HDL testbenches, 991 dutctl checks and 52 relay
    checks, all passing.
* Vivado build 7305e7d3: WNS +0.226 ns, WHS +0.030 ns, LUTs 66.8 %.

Hardware test plan (lead):
1. One board, link open: `dutctl listen` shows `nb standalone (no peer)`,
   rx 0, no errors, tx counting up about 10 per second.
2. Two boards wired as in the table above, with different B: both see
   the peer as present, the lower B is `primary` and the other
   `secondary`. Peer B, DNA and build match the other board's
   heartbeat, error counters stay 0, rx counts up about 10 per second.
3. Pull one RX jumper: that board shows `(peer B<n> lost)` and goes
   standalone within about 0.35 s. The other board shows
   `NOT-HEARD-BY-PEER ROLE-MISMATCH`. Reconnect: back to
   primary/secondary within about 0.1 s.
4. Optional: same B on both boards gives `B-CLASH` with the lower DNA
   primary. One board's TX jumpered to its own RX gives `LOOPBACK` and
   standalone.
