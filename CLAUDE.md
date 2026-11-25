# FPGA-DUT-Manager — working notes for Claude

Networked supervisors for MEGA65 (later HewnWeb) test hardware, built on
pre-V4 Numato Mimas A7 boards (XC7A50T-1FGG484). Start with
`docs/design-brief-v0.5.md`, then `docs/adrs/0000-index.md`, and
`docs/HANDOVER.md` for the current state of work.

## How we work

* **Branches**: feature branches (`feature/<topic>`). Pushing to GitHub
  (`origin`, gardners/FPGA-DUT-Manager) is allowed.
* **`main` = last known-good** (owner, 2026-11-25): whenever a bitstream has
  been verified on hardware (owner-confirmed, or checked here over the
  network), fast-forward `main` to the commit it was built from
  (`git push origin <commit>:main`), copy the `.bit` into `bits/`, point
  `bits/known-good.bit` at it and add a row to `bits/README.md`. Keep doing
  this as work progresses; never put unverified commits on `main`.
* **Commit often**, with descriptive messages (what and why), ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
* **Decisions** go in `docs/adrs/NNNN-short-title.md` (+ index in
  `0000-index.md`). **Open questions / work items** go in
  `docs/issues/NNNN-short-description.md`; append dated progress notes rather
  than rewriting history.
* **Log every non-trivial owner request as an issue before implementing
  it** (owner, 2026-11-25), then append dated progress notes as it lands.
* The owner reviews ADRs but wants implementation to proceed assuming
  approval. Ask the owner only about design problems that genuinely need their
  input (hardware facts, trade-offs with real consequences).
* **The lead session supervises; sub-agents do the parallel work** (owner,
  2026-11-25). Split independent work items (issues) across sub-agents in
  their own git worktrees and branches (`feature/<topic>`), keep the lead for
  coordination, integration (merging their branches into
  `feature/foundation`), hardware testing and the high-level picture with
  the owner. Give each agent: the issue, the files it owns, the conventions
  (tests, commits, protocol-change rule) and what it must not touch.
  Only the lead loads bitstreams onto the board and fast-forwards `main`;
  agents may run Vivado builds in their own worktree (`VIVADO_OUT`), at most
  ~4 builds at once on the build box (about 3 GB RAM each).
* **Background work is fine**, including parallel compiles — but don't
  oversubscribe CPU *or RAM* (JOBS=10 nextpnr compiles ran the laptop out of
  memory). `JOBS` defaults to min(nproc/2, available GB/3).
* **Bitstreams come from Vivado by default** (owner decision, ADR 0001
  amendment): the owner runs `make bitstream` (= `make vivado`) on the build
  box; load here with `make jtagload BIT=...`. `FLOW=openxc7` keeps the
  open-source flow available. The openXC7 toolchain
  build is paused at nextpnr by owner decision; nvc/openFPGALoader/yosys/
  prjxray are built.
* **Build bitstreams early** (owner, 2026-11-25): a Vivado build takes only a
  few minutes on the build box, so as soon as an HDL change compiles, start
  `make bitstream` in the background **and run `make test` at the same
  time** — do not wait for the simulations to finish before building. It
  gives timing feedback and lets hardware testing start sooner; the tests
  must still be green before the build is loaded as known-good or merged.
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
* **Power the Mimas from the DC barrel jack, not USB alone** (2026-11-25):
  on USB power the full design browns out a few seconds after configuration
  (about when the gigabit link comes up): DONE drops, the FPGA reloads from
  SPI flash and goes dead; JTAG readbacks also fail intermittently. If a
  loaded design "dies" after a few seconds, check the power first.
* ModemManager probes new ttyUSB ports; on FTDI channel B that wiggles JTAG.
  `scripts/setup-mimas-udev-rule.sh` makes MM ignore the board and keeps
  ftdi_sio off channel B (installed on the build box).
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
