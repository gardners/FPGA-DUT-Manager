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
