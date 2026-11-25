# 0001: Toolchain build from fresh checkout

Status: In progress
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
