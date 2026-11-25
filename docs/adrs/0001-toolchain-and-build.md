# ADR 0001: Open-source toolchain in `tools/`, Vivado-portable VHDL

Status: Accepted (2026-11-25); amended same day — **Vivado is the default bitstream flow**

## Context

No Vivado build server is available now. The Mimas A7 carries an XC7A50T-1FGG484,
which the openXC7 flow (yosys + nextpnr himbaechel/xilinx + prjxray database)
supports (`xc7a50tfgg484-1` is in prjxray-db). The project is written in VHDL;
yosys reads VHDL only through GHDL's synthesis library (ghdl-yosys-plugin).
Simulation uses nvc. The build machine is a modest laptop; the owner asked for
a single heavy job at a time.

## Decision

* `make toolchain` builds everything from pinned sources into `tools/prefix`
  (git-ignored): nvc r1.23.1, openFPGALoader v1.2.0, GHDL v6.0.0 (mcode),
  ghdl-yosys-plugin @c21051d, and the openXC7 stack (yosys v0.71,
  openXC7/nextpnr, prjxray, prjxray-db) via the openXC7
  `toolchain-sources-builder.sh` pinned at commit 791f07b. The builder's own
  `sudo apt-get` step is neutralised; `make deps` / `scripts/check-deps.sh`
  owns system packages.
* `JOBS` defaults to 1.
* Bitstream path: GHDL→yosys `synth_xilinx` → `nextpnr-himbaechel` →
  `fasm2frames` → `xc7frames2bit`. `fpga-as` (faster, needs Bazel) is an
  optional extra (`make tool-fpga-as`).
* `make jtagload` / `make flash` use `openFPGALoader -b mimas_a7` (built-in
  profile: cable `numato`, FTDI interface B, xc7a50tfgg484, SPI flash).
* VHDL stays vendor-portable: VHDL-2008 subset that both GHDL-synth and Vivado
  accept; Xilinx primitives (MMCME2, IDDR/ODDR, IDELAYE2, BUFG) only inside
  `hdl/src/platform/xc7/` wrappers with behavioural simulation models in
  `hdl/sim/`. A Vivado project script will be added for timing sign-off on the
  other machine (issue 0005).
* nvc runs all unit tests (`make test-hdl`), one testbench per entity,
  self-checking, `assert ... severity failure` on mismatch.

## Consequences

* nextpnr-xilinx timing analysis is approximate. Source-synchronous interfaces
  (RGMII, chain link, HDMI RX) are designed with generous margins and verified
  on hardware; Vivado timing is the reference when available.
* A fresh toolchain build at JOBS=1 takes on the order of hours.
* Bumping a pin requires editing `scripts/build-toolchain.sh` and this ADR.

## Amendment (2026-11-25): Vivado by default

The first Vivado bitstream (owner's build box, `make vivado`) worked on
hardware (video, DHCP) while the openXC7 build was still compiling and then
ran the laptop out of RAM. Owner decision: build with Vivado by default.

* `make bitstream` = `make vivado` (FLOW=vivado); `make jtagload`/`flash`
  load `build/vivado/supervisor.bit` unless `BIT=` is given.
* The open-source flow stays in the tree (`FLOW=openxc7`), the VHDL stays
  portable, and nvc remains the simulator. The openXC7 toolchain build is
  paused at nextpnr (issue 0001).
