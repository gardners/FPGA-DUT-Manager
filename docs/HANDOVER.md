# Handover — 2026-11-25 (laptop session → build-box session)

Read `CLAUDE.md` first (workflow, conventions, hardware facts), then this.
The previous session ran on the owner's laptop (NATed Wi-Fi, no Vivado). The
new session runs on the build box: it has Vivado and sits on the same
203.28.176.x segment as the board, so it can build, load and test directly.

## Where things are

* Branch **`feature/foundation`** (pushed) holds all integrated work. Not
  merged to `main` (owner merges after hardware confirmation).
* Minion branches (pushed by sub-agents just before the hand-off; review and
  merge into `feature/foundation` if good):
  * **`feature/mk2-keyboard`** — issue 0009: MK-II physical keyboard (I2C
    scanner adapted from mega65-core `mk2_to_mk1`, I2C expander model,
    MK-I/MK-II auto-detect wrapper `kbd_phys_host`). Not yet wired into
    `supervisor_core` (it still instantiates `kbd_mk1_host` directly).
  * **`feature/dutctl-video`** — issue 0024: raster decoder, frame
    assembler, `dutctl capture` / `dutctl video`, Python raster
    encoder/decoder in `tests/netproto.py`, vectors and C tests.
  Check each branch's issue file for its own dated status note. If a branch
  is missing, the sub-agent did not finish pushing; its worktree was on the
  laptop under `.claude/worktrees/` and is lost unless the owner copies it.
* m65 (mega65-tools) Mimas A7 JTAG support: `docs/handover/m65-mimas-a7-jtag.patch`
  (git format-patch of commit a5becdd on local branch `mimas-a7-jtag`,
  based on mega65-tools 44c63d2). Apply with `git am` on a branch of a clean
  mega65-tools checkout. The owner's main mega65-tools checkout on the laptop
  has unrelated uncommitted WIP — never touch it. Issue 0010.

## Hardware status (confirmed by the owner)

* Vivado bitstream (build id d1d384ab) loaded over JTAG: **HDMI text
  display works; DHCP lease obtained** on a gigabit switch.
* Seven-segment showed garbage → mapping fixed afterwards (7SEG_0..7 =
  G F A B DP C D E); **needs a fresh build to confirm** (issue 0013).
* Not yet verified on hardware: heartbeats/`dutctl listen`, ping, management,
  UART bridge, JTAG to a DUT, keyboard emulation, physical keyboard, buttons.

## Build / test commands on the build box

```
make test-sw                     # dutctl + relay firmware unit tests (gcc only)
make tool-nvc                    # builds nvc into tools/ (needed for HDL tests)
make test-hdl                    # all nvc testbenches (+ Python scenario checks)
make bitstream                   # = make vivado -> build/vivado/{supervisor.bit,
                                 #   timing_verdict.txt, timing.rpt, ...}
make tool-openfpgaloader         # if the board is attached to the build box
make jtagload                    # loads build/vivado/supervisor.bit (6 MHz TCK)
make dutctl && sw/dutctl/build/dutctl listen -t 5
```
`make deps` lists/installs system packages (Debian/Ubuntu). The openXC7
flow (`FLOW=openxc7`) is paused — do not build nextpnr unless asked; it is
RAM-hungry (owner's laptop ran out of RAM at JOBS=10).

The board: udev rule `scripts/setup-mimas-udev-rule.sh` (FTDI channel A =
UART `/dev/mimas-<serial>`, channel B = JTAG). Board under test has USB
serial NL4IT7JQ. DIP[3:0]/[7:4] = DUT IDs → MACs `02:4D:36:35:00:<id>`, DHCP
host names `m65dutNN`. Endpoints stay silent until DHCP succeeds.

## Work in progress: issue 0019 timing closure (top priority)

First Vivado build: **clk_sys WNS −5.233 ns** (2537 endpoints) and
**rgmii_rxc WHS −2.007 ns** (5 IDDR inputs). Details in
`docs/issues/0019-timing-closure.md`. Agreed approach (owner):

1. **`net_tx` frame builder** (`hdl/src/net/net_tx.vhd`): replace the
   `widx`-indexed byte selection (`hdr(o)`, `pf(o - hdr_len)`, DHCP
   `dhcp_byte(o)` — 20 logic levels) with a **byte-per-cycle shift
   register**: after S_CSUM load `sr(0..41) <= hdr`, `sr(42..149) <= pf`,
   then stream three segments with down-counters:
   * segment A: `hdr_len + pf_len` bytes from `sr(0)` (shift each cycle);
   * segment B: `tail_len` bytes from the tail source (UART history, JTAG
     TDO, ICMP data — all 1-cycle-latency reads — or zeros for DHCP);
     `tail_addr` starts at 0 at load and increments in the last cycle of A
     and every cycle of B, so data is valid on time;
   * segment C: remaining `sr` bytes (DHCP only).
   DHCP becomes: A = 42 header + 44 BOOTP head bytes (`pf(0..43)` =
   `dhcp_byte(0..43)`), B = 192 zero bytes, C = 64 bytes (`pf(44..107)` =
   `dhcp_byte(236..299)`: cookie + options), total 300 payload bytes —
   `pf` (108 bytes) holds exactly that.
   The existing system test (`tb_supervisor_core` + Python scenario) checks
   every frame type byte-for-byte, so it is the regression net.
2. **`net_rx` S_PARSE** (`hdl/src/net/net_rx.vhd`): split the single-cycle
   decision into registered stages (first compute match/valid flags for
   ARP/IPv4/ICMP/UDP/DHCP, ports, lengths; then decide). Same test net.
3. **RGMII RX clock** (`hdl/src/platform/xc7/rgmii_xc7.vhd`): replace
   BUFG + IDELAYE2 with an MMCM on RXC (deskew/compensated, CLKOUT +90°,
   BUFG) and IDELAY 0 / removed; keep the IDDR SAME_EDGE_PIPELINED capture.
   Update `boards/mimas_a7/mimas_a7_vivado_timing.xdc` clock names (the
   async group currently uses `get_clocks rgmii_rxc`; with an MMCM the
   capture clock becomes a generated clock — group it with rgmii_rxc).
   **Hardware note:** the current BUFG+IDELAY design *does* receive frames
   on the board, so verify the MMCM version on hardware (ping, DHCP) before
   relying on it.
4. **RGMII TX constraints**: `create_generated_clock` on `rgmii_txc`
   (source `phy/o_clk` ODDR, from the +90° clock) and `set_output_delay`
   (rise/fall, e.g. −max 1.0 / −min −0.8 — check RTL8211E datasheet) for
   `rgmii_txd[*]`, `rgmii_tx_ctl`.
5. `text_display` chars/attrs mapped to LUTRAM: add
   `attribute ram_style : string; ... of chars, attrs : signal is "block";`.
6. Rebuild with `make bitstream`, read `build/vivado/timing_verdict.txt`,
   iterate until MET, then load and re-test on hardware.

## Next issues after timing (owner-approved plan)

| Issue | What |
|---|---|
| 0020 | `scripts/hwtest.sh` smoke test (now possible: build box is on the board's segment) |
| 0022 | `hdmi_rx` 27 MHz DVI (ISERDESE2/IDELAY, bitslip, deskew, decode, lock/geometry); test with our `dvi_tx_xc7` as source |
| 0023 | raster capture: async FIFO → 16 KiB packet ring with commit → raster-first scheduler; capture enable key 0x0040; heartbeat video block (ADR 0005 §8) |
| 0024 | review/merge `feature/dutctl-video`; use its Python raster decoder in the capture system test |
| 0009 | review/merge `feature/mk2-keyboard`; switch `supervisor_core` to `kbd_phys_host` |
| 0025 | README.md |

Owner preferences recap: commit often with good messages and the
Co-Authored-By line; push freely to this repo; ADRs for decisions, dated
notes in issue files; ask only genuine design questions; don't
oversubscribe CPU/RAM; never write SPI flash before an SRAM load works.
Only 27 MHz pixel clocks matter for now. Gigabit Ethernet is assumed
(100 Mb/s is issue 0018, low priority).

The laptop session's private memory notes are folded into CLAUDE.md and this
file; nothing else is needed from the laptop.
