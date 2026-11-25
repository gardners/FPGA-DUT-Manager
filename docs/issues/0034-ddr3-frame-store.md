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
