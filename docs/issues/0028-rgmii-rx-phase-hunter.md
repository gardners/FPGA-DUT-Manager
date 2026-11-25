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

## 2026-11-25 implemented (simulation)

rx_frame_observer (clk_rx) + rx_phase_hunter (clk_sys) in supervisor_core;
RX MMCM is now MMCME2_ADV with CLKOUT0_USE_FINE_PS (PSCLK = clk_sys,
17.9 ps steps, 7 per 5.625-deg position, 448 per circle). Heartbeat link
block (ADR 0005 s3a, payload 132) reports phase/eye/hunts/bad frames;
`dutctl listen` prints them. tb_rx_phase_hunter: good start (no hunt),
drift (centred, width 21), wrap-around eye, no traffic (back to origin),
reset. Hardware test pending: force a hunt by starting from a bad phase
(build with RX_PHASE_STEPS outside the eye, e.g. 40) and check it recovers.

## 2026-11-25 hardware

* Default build c4f659ae: hwcheck PASS, link block phase 0 / hunts 0 / bad 0.
* Build started outside the eye (RX_PHASE_STEPS=40, 225 deg): with
  4 frames / 100 ms per position it did **not** recover on its own (before
  DHCP only LAN background broadcasts arrive). With ~1000/s broadcast UDP
  from the host for 30 s it recovered: 1 hunt, eye 24 positions (135 deg,
  matching the build scan), settled +45 positions = 118 deg absolute
  (calibrated centre 123.75 deg), 155 bad frames; hwcheck PASS.
* Tuned to 2 frames / 1 s per position for quiet networks; re-test without
  helper traffic.
* 2 frames / 1 s: recovered **without** helper traffic (1 hunt, 52 bad
  frames, hwcheck PASS) but measured eye 10 and settled at ~73 deg: quiet
  positions inside the eye timed out as fails and split the run. Timeout
  raised to 10 s per position (fail only when truly silent).
