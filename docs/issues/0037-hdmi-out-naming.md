# 0037: HDMI OUT identity: SPD InfoFrame, then the monitor's EDID

Status: Open
Opened: 2026-11-25 (owner: "Both, but start with 1")

1. Send an SPD InfoFrame (CTA-861 Source Product Description, vendor "MEGA65",
   product "MEGA KVM" plus the connected machine) on HDMI OUT. This needs
   the transmitter to send HDMI data islands (preamble, guard bands, TERC4,
   BCH ECC) on the console path. Passthrough (DVI from the source) gets
   them too if practical. Otherwise SPD is sent on the console only.
   Monitors that ignore SPD must be unaffected.
2. Later: read the downstream monitor's EDID over HDMI OUT DDC (I2C
   master), report its name and modes to the host, and optionally pass it
   on to HDMI IN (US-09).

## 2026-11-25 part 1 implemented (sub-agent, branch `feature/hdmi-spd`)

* New `hdl/src/video/hdmi_framer.vhd` in front of the existing Tyto
  `hdmi_tx_encoder` channels (which already had TERC4, guard band and control
  encodings). `dvi_tx_xc7` gets `generic HDMI` (default false: unchanged pure
  DVI, as `tb_dvi_tx` uses it); `mimas_a7_top` has `HDMI_OUT : boolean :=
  true` (set false for the pure-DVI fall-back) and `CON_VIC : natural := 3`.
* Stream delayed 10 chars (+1 register) so the video preamble (CTL 1000, 8
  chars) and video guard band (2 chars) go before every DE rise.
* One packet per data island (so channel-0 bit 3 "first char" is unambiguous):
  AVI after the DE fall of active line 2, SPD after line 3, each once per frame
  (frame = VS edge, either polarity). Island = 4 control + 8 preamble (CTL
  1010) + 2 guard + 32 TERC4 + 2 guard; only sent when the previous hblank was
  >= 64 chars (720x480 has 138), so a short-blank source gets no islands
  rather than a broken line.
* BCH ECC: LFSR (reversed poly 0x83) while the packet shifts out, same form
  as mega65-core `vga_to_hdmi.vhdl` `bch_ecc_1/2` (used as a cross-check only;
  the framer is new code, LGPL-2.1-or-later).
* AVI v2: RGB, A0=1 (AFD = picture), **underscanned** (S=10, so TVs that
  overscan CE formats should not crop), **IT content** (ITC=1, CN=graphics:
  "PC/game" processing), **full-range RGB** (Q=10), VIC 3 (720x480p60
  16:9; the monitor previously chose the aspect itself, 16:9 keeps a
  full-width picture; `CON_VIC => 2` for 4:3).
* SPD v1: vendor `MEGA65`, product `MEGA KVM` + ` Mnn` (0-based machine
  number, two digits, of the video target when it is one of this board's
  DUTs: `supervisor_core` now exports `vid_machine`/`vid_machine_ok`), source
  information 0x09 (PC general).
* Passthrough: islands are inserted too (same framer, it runs in whichever
  clock the TX uses). VIC comes from the measured HDMI IN geometry: 720x480
  -> 3, 720x576 -> 18, else 0 (no VIC).
* Tests: `tb_hdmi_tx` decodes the TMDS lanes and checks the period structure
  (control period >= 12, preamble exactly 8, guard bands), every line has
  exactly H_ACTIVE unchanged pixels, TERC4, channel-0 bit 3, ECC, checksum;
  `tests/scenarios/tb_hdmi_tx.py` re-checks the ECC by polynomial division
  (G = x^8+x^7+x^6+1) and the AVI/SPD fields, with the SPD machine changed
  during the run (M03, none, M27). `make test` green (22 HDL tbs).

**Caveat: HDMI OUT -> HDMI IN self-loop.** dvi2rgb (Digilent) treats every
non-control TMDS char as video: the 2 video guard band chars would make the
looped-back lines 722 pixels wide (first two pixels a fixed colour) and each
data island adds a short DE run on lines 2 and 3. `video_meas` would then
report 722 wide and `hwtest.sh` (requires 720x480, captures) would fail on
the self-loop. Same limitation applies to any real HDMI source (a MEGA65 in
HDMI mode with audio) on HDMI IN. Options: build with `HDMI_OUT => false`
for self-loop tests, or make the RX HDMI-aware (expose the per-channel
control/guard decode from dvi2rgb and drop guard bands and islands from DE);
that is RX work outside this item.

## 2026-11-25 Vivado (sub-agent)

Build 7282eba (HDMI_OUT = true): **TIMING MET, WNS 0.219 ns, WHS 0.023 ns**.
Bitstream in the worktree at `build/bits/supervisor-7282eba*.bit` (not loaded;
the lead tests on hardware). To check on the monitor: the input/source info
OSD should name the source "MEGA65 / MEGA KVM M<nn>" (or "MEGA KVM"), and the
picture should be unchanged (full range, no overscan, 16:9).
