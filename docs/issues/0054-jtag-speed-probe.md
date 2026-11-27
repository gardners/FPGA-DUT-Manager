# 0054: Probe the maximum safe TCK on the on-board (octopus) JTAG

Status: open (owner request 2026-11-27). Related: 0051, 0053.

## Request (owner, 2026-11-27)

With DUTs on separate shelves, octopus JTAG runs over longer ribbons. Support
probing JTAG to the boards directly to work out the maximum safe JTAG speed.

## Proposal (lead)

* No HDL change is needed: every JTAG shift already carries
  `tck_half_period` (ADR 0005, in clk_sys cycles; ≥ 2, default 6 ≈ 10.4 MHz).
  TDO is synchronised by 2 flip-flops and sampled at the end of the high half
  period. The round-trip cable delay therefore eats into the high half
  period, which is what the probe measures.
* `dutctl jtag-speed IP DUT [--kbd]`, host only:
  1. start slow (half period 50, ~0.6 MHz): reset TAP, read the IDCODE, and
     count the devices (BYPASS chain length);
  2. for each faster step: N repetitions (default 200) of
     * IDCODE compares;
     * a long BYPASS shift of a random pattern, checked after the chain's
       delay;
     * a DR shift of all-zeros and all-ones (catches stuck or slow edges);
  3. the fastest step with zero errors is `f_max`. Recommend `f_max / 2` (at
     least one step of margin), store it in the per-DUT config (0053), and
     report the margin;
  4. finish by reading the IDCODE at the chosen speed.
* Works for the keyboard JTAG path too (`--kbd`, third jtag_engine).
* Results go into the hwtest report when a DUT is present.

## Notes

* Run it with the DUT idle; a configuring FPGA does not change the TAP, but
  avoid probing during a flash write.
* The test is read-only (no IR other than IDCODE/BYPASS), so it is safe on a
  running DUT.
