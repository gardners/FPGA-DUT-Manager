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

## Progress

### 2026-11-27 (sub-agent, branch feature/dutctl-jtag)

`dutctl jtag-speed IP [DUT] | NAME [--kbd] [--reps N] [--save] [--from H]
[--to H] [--tolerate N] [-v]` implemented in host software
(`sw/dutctl/src/jtagspeed.c` + `main.c`). Each probe is one 3608-bit
JTAG_REQ: TLR, a 256-bit IDCODE window (compared bit for bit with the slow
reference), all IRs to ones (BYPASS), then a 2048-bit xorshift pattern
(new seed per probe), 512 zeros and 512 ones in Shift-DR, checked against
the chain length found at the slowest step; it ends in TLR. Steps 50, 40,
32, 24, 20, 16, 12, 10, 8, 7, 6, 5, 4, 3, 2. f_max is the fastest step
reached without a failure on the way; the recommendation is the next swept
step at least twice as slow (f_max / 2), checked once more, and `--save`
writes `tck_half` (`kbd_tck_half` with `--kbd`) into the 0053 config. The
xvc and jtag-idcode commands use the saved value. Unit tests run the probe
against a simulated multi-device TAP chain (IDCODE and bypass-only
devices), with late-TDO and single-bit fault injection.

**Hardware, keyboard CPLD path** (`203.28.176.86 --kbd`, IDCODE 0x012ba043,
board build c73c7b23; 1000 probes per step):

| half | MHz | failing probes / 1000 |
|---|---|---|
| 50 ... 10 | 1.25 ... 6.25 | 12-19 |
| 8 | 7.81 | 150-175 (three runs) |
| 7 ... 4 | 8.93 ... 15.6 | 10-19 |
| 3 | 20.8 | 0 (three runs) |
| 2 | 31.25 | 1000 (everything wrong) |

* There is an **error floor at every TCK**, including the slowest, so the
  strict rule recommends nothing. Every wrong bit seen (`-v`, about 40
  examined) is an **isolated 1 read back as 0**: expected `...010...`,
  received `...000...`. Runs of ones (the 512-bit all-1 segment, 0 errors in
  512k bits) and zeros are never hit. With ~256 isolated ones per probe, that
  is about 6e-5 per isolated 1, independent of TCK, except that half 8 is
  ~10x worse and half 3 is clean. That pattern (rate depends on the TCK
  period, but not monotonically) looks like interference/beat with some
  other periodic signal on the keyboard cable or a pulse-shaping effect on
  TDI or TDO, not a timing limit. With BYPASS alone the test cannot tell TDI
  from TDO; the IDCODE window (only ~5 isolated ones) rarely fails.
* The real timing limit lies between half 3 (20.8 MHz, clean) and half 2
  (31.25 MHz, total failure), so the existing keyboard default (half 32,
  ~2 MHz) has a wide timing margin, but the floor means long shifts (CPLD
  programming) will occasionally see a corrupted bit at any speed. Worth a
  look together with 0046 (pin-3 / long cable): a scope on TDI/TDO at
  half 8, or the same sweep with the keyboard protocol idle.
* `--tolerate N` lets a step pass with N failing probes, for a
  recommendation regardless (e.g. `--tolerate 30 --reps 1000` gives f_max
  half 10, recommended 20 = 3.1 MHz because of the half-8 dip).
* No DUT is attached to the octopus ports here (both endpoints report the
  target unpowered), so the DUT path is untested on hardware.

### 2026-11-27 owner (round 13)

* The keyboard cable is currently about 0.75 m long. The owner would not be
  surprised if zero errors needs TCK below 6 MHz.
* Lead: the measured floor (about 6e-5 per isolated 1) is the same at
  0.6 MHz as at 15 MHz, and half 3 (20.8 MHz) was clean, so a slower TCK
  alone is not expected to remove it; it does not behave like a timing limit
  set by the cable length. Next step is a scope on TDI/TDO at half 8, and a
  sweep with the keyboard protocol idle.
