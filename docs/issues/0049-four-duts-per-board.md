# 0049: Three or four DUTs per supervisor (FPGA, protocol, host)

Status: Open
Opened: 2026-11-27 (owner: two Mimas per unit, "bonus points for a 4th DUT")

The shield (0045) adds HDMI receivers and JTAG/UART/keyboard ports so that one
Mimas serves 3-4 DUTs.

1. **Gate build (before the shield is fabricated):** a Vivado build with the
   on-board HDMI receiver plus 3 header receivers on the planned pins
   (BUFG-clocked dvi2rgb variant, one PLL each), placed and meeting timing.
   That decides 3 or 4 DUTs per board, and fixes the pin plan the KiCad
   shield uses (`docs/hardware/shield-pinplan.md`).
2. Second I2C expander for the slow lines (HPD, +5V sense, VIO and keyboard
   sense); I2C master in the FPGA reads the shield revision and features
   at boot and selects the pin use (bodge cables vs shield).
3. Protocol and identity: DUT numbering assumes 2 per board ((dut_id & 0xF)
   * 2 + half); per-DUT endpoints, DIP ID ranges (0026), heartbeat fields,
   dutctl machine digits, the select screen (8 machines over 2 boards ->
   the 4x3 mosaic). These change together (ADR 0005 rule).
4. Capture, passthrough and thumbnails for every receiver (thumbnail
   capture per source, or muxed).

## 2026-11-27 step 1 done: pin plan and gate build (branch feature/shield-pinplan)

Pin plan: `docs/hardware/shield-pinplan.md` (per-row tables, net names,
expander bit maps); receiver constraints `boards/mimas_a7/shield_v1.xdc`.
Summary: HDMI1 = P13 clock C18/C19 (MRCC), HDMI2 = P13 clock D17/C17
(MRCC), HDMI3 = P12 clock L19/L20 (SRCC), the only three free
clock-capable pairs; DDC per receiver on FPGA pins; DUT2 on P13, DUT3,
I2C, neighbour UART and physical keyboard JTAG on P12; HPD, +5V sense,
all VIO/keyboard sense and PK_JTAGEN on expander B (TCA6416A 0x20);
revision/features/power outputs on expander A (TCA6424A 0x22). The four
freed sense pins are reused as inputs only. 3 spare pins.

FPGA side:

* dvi2rgb (third_party, changes marked): `TMDS_Clocking` generic
  `kPllBufg` = PLLE2_BASE (M = 40 at 27 MHz, VCO 1080 MHz) with BUFG 5x
  and 1x outputs instead of MMCM + BUFIO/BUFR; `kClkInBufg` feeds the PLL
  through a BUFG (PLL in any region) or over the dedicated route;
  `TMDS_Decoder` `kInvert` per lane (P/N swap on the PCB); the
  IODELAY_GROUP moved from dvi2rgb.xdc into a VHDL attribute (generic), and
  the IDELAYCTRL is optional. Needed because the first gate build failed
  DRC (PLIDC-3: one group, controllers with different resets; UTLZ-1: 6
  IDELAYCTRLs, 5 sites). Now one controller per region: HDMI1+HDMI2 share
  HDMI1's in group shd_b16_dg, HDMI3 has its own (shd_b15_dg).
* `mimas_a7_top` generic `SHIELD_RX` (0..3, default 0: the shd_* ports have
  null range and vanish, so the normal build has the same ports and
  logic). With n > 0, n header receivers (`hdmi_rx_xc7` PLL variant,
  ddc_edid each, video_meas each); `vid_src_sel` (new, tb_vid_src_sel)
  feeds the heartbeat video block from the first present source
  (on-board first), so all receivers stay in the design and a header input
  can be checked on hardware from the heartbeat. vivado/build.tcl reads
  shield_v1.xdc when VIVADO_GENERICS has SHIELD_RX=n>0.

Gate build (`VIVADO_GENERICS="SHIELD_RX=3"`, commit 8e473b8): placed,
routed, **TIMING MET WNS +0.238 / WHS +0.051 ns**; LUT 19603 (60 %), FF
23961, BRAM 32/75, PLLE2 5/5, MMCM 5/5, BUFG 21/32, IDELAYCTRL 5/5. PLLs:
HDMI1 X1Y1, HDMI2 X0Y0 (both via BUFG), HDMI3 X0Y1 (dedicated).
**Verdict: 4 DUTs per board** with three independent header receivers.
Not hardware-tested (no shield yet); `make test` green (29 HDL tests).

Open points:

* The shield bitstream is a separate build (`SHIELD_RX=3`): HDMI3's TMDS
  pins (L19/L20/M21/L21) are the bodge physical-keyboard strip's JTAG
  positions, so bodge keyboard JTAG (keyboard type 3 work, 0046) and HDMI3
  cannot be in one bitstream. On the shield, PK JTAG = H19/M20/H18/K19.
* No clocking resource is left (PLL, MMCM, IDELAYCTRL all 100 %).
* Step 2 (I2C master, expander polling, shield-mode pin use) not started;
  HPD of the header receivers is not driven yet (expander B).

### Fallback: DUT2/DUT3 sharing one PLL (owner, 2026-11-27)

Not needed if the gate build with three independent PLLs passes (above),
but designed so it can be switched to if a PLL is ever needed elsewhere
(e.g. a fifth clock for the thumbnail/genlock work, 0039):

* Each receiver keeps its own IBUFDS, IDELAYE2 and ISERDESE2 in its own
  IOBs (the 270 Mb/s data cannot be muxed in fabric). One PLLE2_ADV takes
  HDMI3's clock on CLKIN1 (dedicated route, PLL in X0Y1) and HDMI2's on
  CLKIN2 (through a BUFG), selected by CLKINSEL; its 5x/1x outputs go
  through BUFGCE so the clock is stopped, not glitched, while it re-locks.
  Both receivers' ISERDES are clocked by the shared BUFGs.
* Switch sequence (pclk/ref_clk control FSM): at the end of the frame being
  captured from A, gate the BUFGCEs off, set CLKINSEL to B, pulse PLL RST
  (>= 5 ns), wait for LOCKED, enable the BUFGCEs, wait for B's next VSYNC,
  capture one full frame, then switch back. Capture/thumbnail logic switches
  its source at those frame boundaries.
* **Keep each receiver's alignment across switches.** dvi2rgb resets the
  decoders (PhaseAlign, ChannelBond, ISERDES RST) on every lock loss; in the
  shared mode that reset must be replaced by a per-receiver "frozen" state:
  the inactive receiver's PhaseAlign holds its tap/bitslip state and its
  ISERDES is not reset (its IDELAY tap value is static in the IOB; the
  ISERDES bitslip position persists while it is not reset). Re-align only
  when the decoder reports errors (PhaseAlign AlignErrorSt / ChannelBond
  invalid) after a switch.
* **Phase repeatability:** the PLL is reset on every switch, so its output
  dividers restart aligned and, once locked, CLKFBOUT is phase-locked to the
  selected CLKIN (internal feedback, fixed path) with the CLKOUT0 (5x) and
  CLKOUT1 (1x) phases fixed relative to it. The sampling phase relative to
  each source's data is therefore the same after every lock, within the
  PLL's static phase error and jitter (about +/-0.1-0.2 ns, DS181), small
  against the 78 ps taps x the ~3 ns open eye at 270 Mb/s (3.7 ns bit). The
  1x/5x relationship being fixed also keeps the stored bitslip (word
  framing) valid, since each source's data/clock relationship is its own
  and does not change. Hardware check needed: count re-align events.

### Switch-to-first-captured-frame estimate (27 MHz, 720x480p60 / 576p50)

* PLL re-lock: PLLE2 T_LOCKMAX = 100 us (DS181), plus a few RefClk cycles of
  reset sequencing: ~0.1 ms.
* dvi2rgb phase alignment, only when the alignment was lost (first lock,
  or errors): PhaseAlign tests one IDELAY tap per run of 128 consecutive
  control tokens (kMinTknCntForBlank), i.e. about one line (hblank is
  138/144 pixels; whole lines in vblank), and bitslips after 20 failed
  taps. Worst case ~10 bitslips x 20 taps + a 32-tap eye scan = ~230 lines
  = ~7.4 ms (32 us lines); typical 1-3 ms. ChannelBond then needs one more
  blank (one line). With stored alignment this cost is ~1 line (the bond
  check), not ms.
* Wait for the next frame start of the selected input: 0..1 frame
  (unsynchronised sources), mean 0.5 frame = 8.3 ms at 60 Hz, 10 ms at 50 Hz.
* One full captured frame: 16.7 ms (60 Hz) / 20 ms (50 Hz).

So a switch costs ~0.1 ms + 0..1 frame of waiting, and a capture
(switch + one frame) about 1-2 frames, mean ~1.5 frames. Alternating A
and B frame by frame (owner's refinement, no fixed slow period), each input
is captured once per ~3 of its frames on average (between 1/2 and 1/4):
**~20 fps at 60 Hz, ~17 fps at 50 Hz per input**. A full re-alignment adds
up to ~7.4 ms (less than half a frame), so even then the first frame after
a switch is the next or the one after it (worst case ~2.5 frames = 42 ms at
60 Hz, 50 ms at 50 Hz). Only needed in select mode (thumbnails) and only
when the 5V sense says both inputs are plugged in; otherwise the PLL stays
on the one live input.

### 2026-11-27 normal build check (SHIELD_RX=0, same commit)

Default build after the dvi2rgb changes: TIMING MET, WNS +0.023 / WHS
+0.006 ns (tight; same logic as before, the IODELAY_GROUP now comes from
the VHDL attribute and the IDELAYCTRL sits in a generate, so the margin
difference is placement noise), LUT 17789, FF 20888, BRAM 32, PLLE2 2/5,
BUFG 13, IDELAYCTRL 3. Should be re-checked by the lead on the merged
build before hardware.
