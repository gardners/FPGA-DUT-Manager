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
