# 0067: Drive UART TX low when the DUT is known to be powered off

Status: in progress (owner, 2026-11-28). Supersedes the open-drain (+kick)
UART TX proposal (handover 2026-11-28). Related: 0056, 0057.

## Owner (2026-11-28)

"My decision is none of those: It's bring UART TX low _when the DUT is
known to be powered off_. Super simple. Backwards compatible."

## Design

"Known powered off" = the states in which `dut_out_gate` already forces
every output off whatever the sense says:

* out-policy 2 (key 0x0060; `dutctl relay … POWER n OFF` sets it before
  cutting power, issue 0056), or
* the shield power-off hold (the supervisor switched the DUT's CTRL bit
  off itself, key 0x0062).

In those states UART TXD is now driven **low** instead of tri-stated.
Everything else is unchanged: powered (or policy 1) -> push-pull UART as
before; merely *sensed* unpowered under policy 0 -> still tri-state (a
low sense can also be an unwired VIO row on a powered DUT, which a
driven-low TX would hold in UART break). KIO10 and JTAG unchanged (JTAG
idles low already, 0056).

Why low rather than Z: a defined level on the DUT's RX instead of a
floating input, and no drive high into a dead rail by construction.
Backwards compatible: only the forced-off states change, and those
carried no UART traffic.

## 2026-11-28 lead: built

Commit 6f2fdc9, build **6f2fdc94**: TIMING MET, WNS +0.137 ns, WHS +0.022
ns. `make test` green: 38 HDL testbenches (tb_dut_out_gate checks tx_low
in every state), 917 dutctl checks, 52 relay checks. CLAUDE.md and ADR
0005 (key 0x0060) updated. Hardware check next (coordinated with the
hardweb session, which uses DUT1's UART).
