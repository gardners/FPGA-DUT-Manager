# 0034: DDR3 memory subsystem (frame store)

Status: Open
Opened: 2026-11-25 (owner request: "a controller for the DDR3 memory")

Owner decision 2026-11-25: use the Mimas A7's DDR3 (MT41J128M16, 256 MiB,
16-bit, bank 34, pins in `boards/mimas_a7/vendor/numato-mimas-a7-v3.0.xdc`)
as a frame store for low-resolution thumbnails (0035, 0036). This amends the
brief's "no DDR3 in the baseline": the baseline features (capture,
passthrough, console, JTAG/UART/keyboard) must keep working if DDR3 fails to
calibrate; thumbnail features then degrade (colour bars / frown).

Scope:
* A DDR3 controller behind the `hdl/src/mem/mem_pkg.vhd` port contract
  (clk_sys 125 MHz side, 128-bit words, valid/ready, in-order reads).
  Default choice: Xilinx MIG 7-series generated from Tcl in the Vivado
  build (most likely to calibrate first time on this board), wrapped in
  `hdl/src/platform/xc7/ddr3_xc7.vhd`; LiteDRAM is the fallback if MIG
  is impractical. Reuse the existing 200 MHz `clk_ref`/IDELAYCTRL where
  possible; mind MMCM/PLL placement (dvi2rgb owns the X1Y1 MMCM).
* A round-robin arbiter for N client ports (`mem_req_arr_t`), with a clock
  crossing to the controller's UI clock.
* `hdl/sim/mem_model.vhd` is the behavioural model clients test against.
* A built-in memory self-test (pattern write/read over a region) and
  status in the heartbeat: calibrated, self-test pass/fail, error count.
  This is the first hardware check.

## Progress 2026-11-25 (sub-agent, branch `feature/ddr3`)

* Decision recorded in ADR 0013: MIG 7-series v4.2 from Numato's Mimas A7
  `mig.prj` (400 MHz, 200 MHz sys clock = our `clk_ref`), native UI port,
  generated inside `vivado/build.tcl`; LiteDRAM not needed.
* New: `common/async_fifo`, `mem/mem_arbiter` (N-port round robin),
  `mem/mem_app_bridge` (clk_sys <-> UI clock, ready='0' until calibrated),
  `mem/mem_selftest` (1 MiB at the top of memory, DM test included),
  `platform/xc7/ddr3_xc7` (MIG + bridge); wired in `mimas_a7_top` with
  `MEM_PORTS = 1` (port 0 = self-test). Clients for 0035/0036 add ports
  after it.
* Heartbeat memory block (ADR 0005 s3b, bytes 140..151, payload 144),
  shown by `dutctl listen` ("ddr3 ok (1024 KiB tested)" / "ddr3 FAIL ..." /
  "ddr3 UNCALIBRATED"; `--kv` has `mem_*` keys).
* `tb_mem_subsys`: arbiter + self-test + 2 random clients on `mem_model`;
  through the bridge on a behavioural MIG UI model (100 MHz, random
  stalls); with a stuck DQ bit (self-test fails, flags DQ5, exact error
  count); and with a controller that never calibrates (nothing accepted,
  nothing hangs). `make test` green (22 HDL testbenches, 151 C checks).
* Vivado build e9083a2f (first try): **TIMING MET, WNS 0.221 ns, WHS
  0.023 ns** (all clocks incl. the MIG's; clk_sys <-> MIG UI clock async).
  MMCM 5/5 (MIG's LOCed in X1Y0, no placer conflict), PLL 2/5, LUT 15065
  (46 %, was 9913), FF 17431 (27 %), BRAM 20.5/75, IOB 138, XADC 1 (MIG
  temperature). DRC: only the usual MIG warnings (DQS IBUFDS without load,
  PLL CLKOUT3 buffer type).
* `scripts/hwtest.sh` gained a check "hb dutN ddr3 self-test" (mem_flags
  must have calibrated + done + pass = 13).
* Hardware check (lead): load the build; `dutctl listen` should show
  `ddr3 ok (1024 KiB tested)` within a second of configuration (`--kv`:
  `mem_flags=13 mem_errors=0 mem_dq_fail=0 mem_first_err=4294967295`).
  `ddr3 UNCALIBRATED` = MIG did not calibrate; `ddr3 FAIL` lists the bad
  DQ lines. Either way the baseline (DHCP, ping, console, passthrough,
  JTAG/UART/keyboard) must be unaffected: run `scripts/hwtest.sh`.

## 2026-11-25 hardware (lead)

Merged into feature/foundation (c2b6d91; mosaic reader on DDR3 arbiter port 1, ddr_ok = calibrated). Build c2b6d912: TIMING MET, WNS 0.134 ns. On the board: DDR3 calibrated, self-test 1024 KiB / 0 errors on both endpoints; hwtest 63/0; the select screen (forced via key 0x0035 = 3) captured over the HDMI self-loop shows the 2x2 layout with colour bars for machines 0 and 1 (seen, nothing fresh until 0035) and frowns for the empty slots. Recorded as known-good.
