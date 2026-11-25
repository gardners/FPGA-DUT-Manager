# 0040: HDMI-aware receive: strip guard bands and data islands from DE

Status: Open
Opened: 2026-11-25 (lead; found by the 0037 agent)

Digilent dvi2rgb treats every character that is not a control character as
video. An HDMI source (not DVI) therefore corrupts our measurement,
capture and thumbnails: each active line gains its 2 leading guard-band
characters (722 pixels), and data islands (InfoFrames, audio packets) look
like short runs of extra pixels in the blanking. A real MEGA65 sends HDMI
with audio by default, so this matters for the very first real source, not
just for our own SPD output (0037) on the self-loop.

Fix: classify the received 10-bit characters (all three channels, at the
dvi2rgb decoder input):
* video guard band: ch0/ch2 0b1011001100, ch1 0b0100110011, after a video
  preamble;
* data-island preamble, its guard bands and the TERC4 period.
Only real video characters may drive DE. Report "HDMI mode seen" and
"audio packets seen" in the video status. Later: parse the source's
AVI and SPD InfoFrames, so the host can learn the source name and VIC.
Must keep the 720x480 self-loop (now HDMI with SPD/AVI) measuring exactly
720x480.

## 2026-11-25 implemented (sub-agent, branch `feature/hdmi-rx-aware`)

Based on `feature/hdmi-spd` (0037) with `origin/feature/foundation` merged.

* `hdl/src/video/hdmi_rx_period.vhd` (new): classifies from dvi2rgb's
  registered per-channel decode (pVde, C0/C1 of channels 0-2; no raw
  characters needed): a control run ending in >= 4 chars of CTL 1000 is a
  video preamble -> next 2 chars (video guard band) are not video; CTL 1010
  is a data-island preamble -> nothing is video until the next control
  token (leading guard, TERC4 packets, trailing guard). Any other control
  period (DVI, CTL 0000) is followed by video exactly as before, so DVI
  sources are unaffected. Combinational on the decoder registers, so DE
  timing relative to pixels and syncs is unchanged.
* HSYNC/VSYNC inside islands: upstream holds the last control value while
  channel 0 sends TERC4, which moved the HSYNC leading edge to the end of
  any island spanning it (ours do; audio islands from a MEGA65 would on many
  lines). dvi2rgb's 8b decode of the 16 TERC4 chars is one-to-one, so the
  classifier takes HS/VS from the TERC4 bits there.
* `third_party/digilent-dvi2rgb/src/dvi2rgb.vhd`: generic `kHdmiAware`
  (default false = upstream), outputs `vid_pHdmi`, `vid_pIsland`; the change
  is marked in the source and listed in the README. `hdmi_rx_xc7` enables it.
* Heartbeat byte 108 `video_flags`: **b3 HDMI mode seen** (video or island
  preambles), **b4 data islands seen**, each over the last two frames
  (published every 4 VSYNC edges) and only while locked. b3 was documented as
  "DVI (no data islands seen)" but never implemented (always 0), so it was
  redefined rather than taking a new bit. ADR 0005, `proto_pkg` (`VF_*`),
  `dutproto.h` (`DP_VF_*`), `netproto.py` (`VF_*`) and `dutctl listen`
  (`video locked 720x480 ... HDMI+islands` / `DVI`) changed together; no new
  bytes.
* Test `tb_hdmi_rx_period`: our HDMI TX (0037: guard bands, AVI + SPD
  islands) and a DVI TX at 720x480p60 through a model of dvi2rgb's decode
  stage, then `hdmi_rx_period` and `video_meas`: both measure exactly
  720x480 of 858x525, every pixel passed is the transmitted one, HSYNC
  period is a constant 858, flags 1/1 for HDMI and 0/0 for DVI; the
  unfiltered DE measures 722 (the bug). `make test` green (23 HDL tbs,
  145 dutctl, 27 relay_core).
* Not done (optional item 4): capturing the source's SPD strings and AVI VIC.
  The classifier knows when a packet starts (char after the leading guard),
  so a later parser can take channel 0 bit 2 / channels 1-2 nibbles from
  the TERC4 decode the same way as HS/VS.

## 2026-11-25 Vivado (sub-agent)

Build c103a3a (HDMI OUT with SPD/AVI + HDMI-aware RX): **TIMING MET, WNS
0.192 ns, WHS 0.017 ns**. Bitstream `build/bits/supervisor-c103a3a7.bit` in
the agent worktree; not loaded. On the self-loop expect `dutctl listen` to
show `video locked 720x480 of 858x525 ... HDMI+islands` and hwtest's 720x480
checks to pass again.
