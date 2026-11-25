# 0028: Self-calibrating RGMII RX phase (FCS-driven hunter)

Status: Open
Opened: 2026-11-25

Owner idea (2026-11-25): watch live traffic; when frames appear but fail
FCS (3 in a row), move the sample point; once 3 in a row are good, stop
hunting for a while so thermal drift can still be followed.

Hardware scan (issue 0019) found a ~3 ns eye (56..191 deg) centred near
124 deg; the fixed default is now step 22 (123.75 deg). The hunter makes
each board find and keep its own centre.

Plan (lead's refinements):

* Actuator: MMCM dynamic phase shift (MMCME2_ADV PSEN/PSINCDEC/PSDONE,
  ~17.9 ps per step, wraps through 360 deg) rather than IDELAY (only 31 x
  78 ps = 2.4 ns, less than one eye, and no wrap).
* "Frame seen" = RX_CTL high for >= 64 RXC cycles (works even when the
  phase is so wrong that preamble/SFD decode fails); verdict = FCS ok/bad.
* HUNT: visit ~64 positions round the circle (coarse step 5.625 deg), a
  few frames each, record pass/fail; settle in the middle of the longest
  passing run (wrap-aware). Nibble-swapped positions fail FCS and drop out.
* TRACK: stay put; 3 consecutive bad frames -> re-hunt. Optional periodic
  re-centre (e.g. every 60 s, costing a few frames) to follow drift.
* Report phase, eye width (passing run length), FCS error and re-hunt
  counters in the heartbeat (ADR 0005 + proto_pkg + dutproto.h + netproto.py).
* Testbench: RGMII PHY model with configurable skew and a phase-shift
  model of the MMCM; check convergence to the centre and re-hunt on error.

## 2026-11-25 owner decision: activation

* Power-up phase = the calibrated default (step 22, 123.75 deg).
* The hunter is **only** activated by 3 consecutive frames with FCS errors
  (no periodic re-centring). It then runs one complete scan of all phase
  positions and settles in the middle of the longest passing run, then
  goes back to watching.
