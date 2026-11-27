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

### 2026-11-27 owner questions / plan (sub-agent, branch feature/kbd-jtag-si)

Owner asks about the keyboard-path error floor: (a) did we stop the
keyboard protocol while doing JTAG, to reduce cross-talk? (**No**: the
physical keyboard host keeps scanning on the same ribbon during keyboard
JTAG.) (b) Does de-bouncing (majority-voting) the TDO bit fix it?

Plan: two board-wide diagnostic MGMT keys, so the lead can A/B test on
hardware (protocol rule: ADR 0005, proto_pkg, dutproto.h, netproto.py):

* **0x0063 kbd JTAG quiet** (1 byte): 0 as now (default); 1 pause the
  physical keyboard host while the keyboard JTAG engine is busy (from
  admission until done, plus a few-µs guard before the first TCK edge and
  after the last): lines to the keyboard static at idle levels, matrix
  frozen (no key events to the DUTs), detection (pk_present) held, clean
  resume; 2 host stopped entirely (keyboard JTAG then needs key 0x0061 = 1).
* **0x0064 JTAG TDO sampling** (1 byte, all three engines): 0 single sample
  at the end of the high half period (default); 1 majority of 3 over the
  last three clk_sys cycles of the high half (half ≥ 4); 2 majority of 5
  (half ≥ 6); smaller half periods fall back.

### 2026-11-27 keys 0x0063 / 0x0064 implemented (sub-agent, feature/kbd-jtag-si)

* **0x0063 kbd JTAG quiet** (`dutctl set IP kbd-jtag-quiet N`): 1 = from
  admission of a keyboard JTAG_REQ until 4 µs after its last TCK edge
  `kbd_phys_host` is paused. The active protocol runs on to a clean point
  and stops with static lines: MK-I in the sync phase (KIO8 held high = a
  long sync, which only restarts the keyboard's frame; up to one frame,
  ~450 µs, to get there), MK-II between I2C transactions (bus released,
  ≤ ~200 µs), type 3 between pairs (KIO9 idle high, ≤ 10 µs). The
  engine's first TCK edge waits until the host has been paused for 4 µs
  (start anyway after 4 ms). Detection, re-probe and type-3 loss timers
  stand still, so the keyboard type (pk_present) is kept; the reported
  matrix is frozen and the first frame after the resume is dropped (it may
  span the pause). 2 = host stopped: no keyboard reported (keys released,
  heartbeat phys_type 0), lines static; keyboard JTAG then needs
  `kbd-jtag 1` (the auto lease follows detection). Leaving 2 restarts
  detection (type-3 probe first). Caveat: a type-3 keyboard keeps sending
  on KIO10 for 100 ms after our last pair, so quiet 1 does not silence
  KIO10 for type 3 (the owner's keyboard is MK-I: KIO10 is static during
  the MK-I sync).
* **0x0064 JTAG TDO sampling** (`dutctl set IP jtag-tdo-vote N`, all three
  engines, latched per request): 0 single sample (default); 1 majority of
  the last 3 clk_sys cycles of the high half (half ≥ 4); 2 majority of the
  last 5 (half ≥ 6; half 4–5 uses 3; < 4 single).
* Tests: tb_jtag_engine (1- and 2-cycle TDO glitches at the sample point:
  seen with 0, 1-cycle rejected with 1 and 2, 2-cycle rejected with 2;
  fallbacks; start_ok wait), tb_kbd_phys_host (pause in MK-II, MK-I with
  keys changed during the pause, type 3; stop/restart), core scenario
  (bad values, keyboard IDCODE with quiet 1 + vote 2 and with quiet 2,
  DUT0 IDCODE with vote 2 at half 6). `make test` green. Vivado build 921fed47: TIMING MET, WNS +0.105 ns, WHS +0.008 ns, 18505 LUTs; bitstream `build/bits/supervisor-921fed47.bit` in this worktree.

**To run on hardware** (lead; IP = the master's endpoint):

```
dutctl set IP kbd-jtag 1
# A: baseline (as before)
dutctl set IP kbd-jtag-quiet 0; dutctl set IP jtag-tdo-vote 0
dutctl jtag-speed IP --kbd --reps 1000 -v
# B: keyboard scan paused during each keyboard JTAG transaction
dutctl set IP kbd-jtag-quiet 1
dutctl jtag-speed IP --kbd --reps 1000 -v
# C: keyboard scan stopped entirely
dutctl set IP kbd-jtag-quiet 2
dutctl jtag-speed IP --kbd --reps 1000 -v
# D/E: TDO majority voting, keyboard scan running
dutctl set IP kbd-jtag-quiet 0
dutctl set IP jtag-tdo-vote 1; dutctl jtag-speed IP --kbd --reps 1000 --to 4 -v
dutctl set IP jtag-tdo-vote 2; dutctl jtag-speed IP --kbd --reps 1000 --to 6 -v
# restore
dutctl set IP jtag-tdo-vote 0; dutctl set IP kbd-jtag-quiet 0; dutctl set IP kbd-jtag 0
```

Reading: if B/C remove the floor, it is cross-talk from the keyboard
protocol (KIO8 clock at 312.5 kHz / KIO9 LED data) onto TDI/TDO; if D/E
remove it, the corruption is a short glitch on TDO near the sample point;
if neither, it is on TDI (the TAP shifts a wrong bit in) or longer than
5 cycles (40 ns). Check that the keyboard still works after B and C.

### 2026-11-27 lead: hardware A/B on build 921fed47

MK-I keyboard, ~0.75 m cable, `jtag-speed --kbd --reps 1000` (3608 bits per
probe), failing probes per 1000:

| run | keys | half 50 ... 4 | half 3 |
|---|---|---|---|
| A | quiet 0, vote 0 (old behaviour) | 8-23 at every step | 4 |
| B | quiet 1 (scan paused during JTAG) | 0 at every step | 0 |
| C | quiet 2 (scan stopped) | 0 at every step | 0 |
| D | vote 1 (majority of 3) | 11-23 | - |
| E | vote 2 (majority of 5) | 7-29 | - |
| F | quiet 2 + vote 2 | 0 | - |

Half 2 (31.25 MHz) fails completely in every mode (the timing limit).
10000 probes with quiet 1 at half 32, 8 and 3: 0 errors each (3.6e7 bits).
The keyboard is still detected (MK-I) after the runs.

Conclusion: the error floor is **cross-talk from the keyboard scan** onto
the JTAG lines; voting does not help, so the corruption reaches the CPLD
(TDI or TCK), not our TDO sampling. Key 0x0063 now defaults to 1 (pause).
The keyboard is frozen for the length of each keyboard JTAG request (plus
up to ~0.45 ms on MK-I to reach the sync phase), which is harmless. TDO
voting stays available, default off.

### 2026-11-27 lead: first DUT-port JTAG on hardware

Owner wired a 6-pin JTAG lead (docs/cabling/dut-cable.md section 4) from P13
rows 3-7 (DUT1) to an FPGA board on relay channel 5: `dutctl jtag-idcode
203.28.176.87` read **IDCODE 0x13636093** (XC7A200T, rev 1). The board
turned out to be an Artix-7 200T board, not the intended K325T, but this is
the first IDCODE read through a DUT port (build 618e7266): the DUT1 path
(TCK/TMS/TDI out, TDO in, power sense) works.
* Later the same day, with the K325T fitted: `dutctl jtag-idcode
  203.28.176.87` read **IDCODE 0x43651093** (XC7K325T, rev 4), relay
  channel 5 on, then off again.
* K325T mated on its daughter board (after a no-3.3 V episode that cleared
  by itself, probably a solder whisker bridging header pins): relay 5 on,
  `jtag-idcode 203.28.176.87` -> 0x43651093, relay 5 off. Working.
