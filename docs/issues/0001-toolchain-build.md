# 0001: Toolchain build from fresh checkout

Status: Paused (see 2026-11-25 note)
Opened: 2026-11-25

Build pinned toolchain via `make toolchain` (ADR 0001). Record wall time and any patches needed. Done when `make bitstream` produces a .bit from a clean clone.

## 2026-11-25 progress

* JOBS=1 was far too slow (yosys with bundled slang ~5% per 40 min); slang
  and yosys unit tests are now disabled and JOBS defaults to nproc.
* Synthesis-only check with the system yosys 0.55 + GHDL plugin: the whole
  design elaborates and maps. `-abc9` aborts inside ABC with that old yosys
  (re-check with the pinned v0.71); without it: ~14k LUT, 8.4k FF, 13 BRAM
  (10 RAMB18 + 3 RAMB36), 2 MMCM, 5 IDELAYE2, 10 ODDR, 4 OBUFDS. Only
  benign BRAM port-resize warnings.

## 2026-11-25 paused

JOBS=10 nextpnr compilation exhausted the laptop's RAM. Owner: Vivado on the
build box now produces working bitstreams, so the openXC7 build is stopped at
nextpnr. Built and usable: nvc, openFPGALoader, yosys, prjxray. The openXC7
step is now split into yosys / prjxray / nextpnr stages (each with its own
stamp) and JOBS defaults to min(nproc/2, available GB/3). Resume later with
`make toolchain` (runs nextpnr, ghdl, ghdl-plugin, chipdb).
Status: Paused.
