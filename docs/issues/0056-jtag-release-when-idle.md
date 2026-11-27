# 0056: Release (tri-state) DUT JTAG outputs when idle

Status: proposed (owner question 2026-11-27). Related: 0054, 0055,
docs/cabling/dut-cable.md section 4.

## Question (owner, 2026-11-27)

"When you finish a JTAG transaction, do you tri-state all pins again? Just
thinking back to what looked like back-powering over JTAG before."

## Current behaviour (lead, from the HDL)

No. `jtag_engine` drives `jtag_oe <= powered`: TCK, TMS and TDI are driven
for as long as the DUT's power sense (VIO or the keyboard cable's 3.3 V)
reads high, with or without a transaction. Between transactions TCK is low
and TMS/TDI hold their last bit (TMS usually '1' after a return to
Test-Logic-Reset). `out-policy` (key 0x0060) does not affect JTAG.

Risk: when the DUT is switched off, a high TMS/TDI back-feeds its 3V3
through the input clamp diodes (8 mA drive, no series resistor on the bench
leads). If that holds the DUT rail above the sense threshold, the sense keeps
reading powered and the outputs keep driving: a self-sustaining back-power
state, which may explain what the owner saw earlier.

## Proposal

* Drive TCK/TMS/TDI only from the start of a transaction until a hold time
  after its end (an output lease, default ~1 s, so a Vivado XVC session
  keeps a steady TAP between shifts); tri-state otherwise. Before releasing,
  park TCK low; at re-drive, start with TCK low and TMS/TDI at their last
  values. The DUT's own pull-ups (7-series TMS/TDI) hold the TAP in a safe
  state while released; TCK edges with TMS high only move it towards
  Test-Logic-Reset.
* Keep the power sense as an additional condition (never drive an
  unpowered DUT), and check it with the outputs released, so our own drive
  cannot hold it up.
* Same for the physical keyboard JTAG engine (it already has a lease, key
  0x0061 auto).
* Possibly a key for the lease length (0 = old behaviour, always driven
  while powered).

## 2026-11-27 owner: do it ("let's burn that down")

Revised plan (lead), simpler than releasing the pins on a timer:

1. **Park TMS and TDI low after every transaction** (TCK is already low).
   No TCK edge happens, so the TAP state is unchanged (TMS/TDI are only
   sampled on TCK edges); XVC sessions keep working. Low outputs cannot
   back-feed an unpowered DUT, and nothing holds its rail up, so the sense
   drops and the existing tri-state takes over. A powered DUT only sees its
   own TMS/TDI pull-ups' ~0.1-0.3 mA into our low outputs. Releasing on a
   timer instead would risk a TCK edge when the line floats to the DUT's
   pull level, which could move the TAP mid-session.
2. **`out-policy` 2 (force off) also forces the JTAG outputs off** (today
   it only covers UART and keyboard), so the host can switch a DUT's
   outputs off before it cuts that DUT's power.
3. **UART to DUT and KIO10 also idle high** and back-feed the same way.
   When the supervisor itself switches a DUT's power (shield power-ctl key
   0x0062, bit n = 0), it forces that DUT's outputs off at the same moment.
   For the relay path, `dutctl relay ... power N off` sets out-policy 2 on
   the DUT mapped to relay channel N in duts.conf first, and `on` restores
   out-policy 0 after switching on.
4. Applies to all three jtag_engines (DUT0, DUT1, keyboard CPLD).

## 2026-11-27 implementation started (sub-agent, branch `feature/no-backfeed`)

Scope: points 1-4 above: TMS/TDI parked low after every transaction in
`jtag_engine` (all three engines), out-policy 2 also gates JTAG, a
power-off hook on the shield CTRL bits (bit n -> DUT n, n = 0..1, matching
the power board's "CTRLn = DUTn power on" labelling), and the `dutctl relay
... power N on|off` hooks via duts.conf. Testbenches, ADR 0005 key text and
`docs/cabling/dut-cable.md` follow.
