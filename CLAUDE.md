# FPGA-DUT-Manager — working notes for Claude

Networked supervisors for MEGA65 (later HewnWeb) test hardware, built on
pre-V4 Numato Mimas A7 boards (XC7A50T-1FGG484). Start with
`docs/design-brief-v0.5.md`, then `docs/adrs/0000-index.md`.

## How we work

* **Branches**: feature branches (`feature/<topic>`); merge to `main` only
  after the owner confirms it works (tests + hardware where relevant).
  Pushing to GitHub (`origin`, gardners/FPGA-DUT-Manager) is allowed.
* **Commit often**, with descriptive messages (what and why), ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
* **Decisions** go in `docs/adrs/NNNN-short-title.md` (+ index in
  `0000-index.md`). **Open questions / work items** go in
  `docs/issues/NNNN-short-description.md`; append dated progress notes rather
  than rewriting history.
* The owner reviews ADRs but wants implementation to proceed assuming
  approval. Ask the owner only about design problems that genuinely need their
  input (hardware facts, trade-offs with real consequences).
* **Background work is fine**, including parallel compiles and sub-agents
  where appropriate — but don't oversubscribe CPU *or RAM* (JOBS=10 nextpnr
  compiles ran the laptop out of memory). `JOBS` defaults to
  min(nproc/2, available GB/3).
* **Bitstreams currently come from Vivado** on the owner's build box
  (`make vivado`, then `make jtagload BIT=...` here). The openXC7 toolchain
  build is paused at nextpnr by owner decision; nvc/openFPGALoader/yosys/
  prjxray are built.
* Hardware-facing actions on the attached board (JTAG load, flash) are fine
  for bring-up; never write the SPI flash before an SRAM load has been shown
  to work (brief §12).

## Layout

| Path | What |
|---|---|
| `Makefile` | `deps`, `toolchain`, `test`, `bitstream`, `jtagload`, `flash`, `detect`, `dutctl` |
| `scripts/` | toolchain build, test runner, udev rule, board discovery |
| `tools/` | built toolchain (git-ignored): nvc, GHDL, yosys+ghdl plugin, nextpnr-himbaechel, prjxray, openFPGALoader |
| `hdl/src/` | VHDL-2008, vendor-neutral except `platform/xc7/` |
| `hdl/tb/` | nvc testbenches `tb_*.vhd`; optional Python hook `tests/scenarios/tb_*.py` (gen/check) |
| `hdl/sim_files.txt` | ordered simulation source list; `hdl/sources.mk` = synthesis list |
| `boards/mimas_a7/` | XDC (+ vendor XDCs for reference); boards are V3.0 (4 digits) |
| `sw/dutctl/` | Linux CLI in C (protocol codec, UART merge, XVC proxy, relay client) |
| `firmware/relay-controller/` | Arduino Uno/Nano sketch for the Jaycar XC4418 relays |
| `tests/netproto.py` | **reference encoder/decoder** for the wire protocol; generates vectors for both VHDL and C tests |
| `third_party/` | imported upstream code with provenance (`UPSTREAM_COMMIT`, licences) |

## Conventions

* Wire protocol changes touch three places together: ADR 0005,
  `hdl/src/proto/proto_pkg.vhd`, `sw/dutctl/include/dutproto.h`, plus
  `tests/netproto.py`. All multi-byte fields big-endian, explicit offsets.
* Xilinx primitives only via `hdl/src/platform/xc7/xc7_prims_pkg.vhd`
  component declarations (works for GHDL/yosys and Vivado).
* Every new entity gets an nvc testbench; system behaviour is checked by
  `tb_supervisor_core` + its Python scenario. `make test` runs HDL, C and
  firmware tests.
* Keep the FPGA lean: complete-state snapshots, no retransmission logic, no
  soft CPU, no DDR3. Policy lives in host software.
* DUT-facing outputs are tri-stated unless the DUT is sensed powered.

## Hardware facts worth remembering

* USB 2a19:1009 = FT2232H: channel A = UART (`/dev/mimas-<serial>` after
  `scripts/setup-mimas-udev-rule.sh`), channel B = JTAG (ADBUS6 buffer OE
  active low). openFPGALoader `-b mimas_a7`, TCK ≤ 6 MHz (30 MHz fails).
* RTL8211E RGMII with PHY delays strapped off; header banks fixed at 3.3 V;
  header rows 1–2 are raw VIN and P13 rows 34–39 are FPGA config pins —
  never run a full-width cable.
* MEGA65 keyboard: emulate MK-I towards DUTs (`kbd_mk1_device`), verified
  against mega65-core's own host decoder.
* Related repos: `~/Projects/mega65/mega65-core` (LGPL),
  `~/Projects/mega65/mega65-keyboard-cpld`, `~/Projects/mega65/mega65-tools`
  (m65; Mimas JTAG patch on branch `mimas-a7-jtag` in worktree
  `~/Projects/mega65/mega65-tools-mimas` — owner has uncommitted WIP in the
  main checkout, do not touch it), `~/Projects/hardweb` (owner's code, reuse
  permitted: DHCP, text console, DVI).
