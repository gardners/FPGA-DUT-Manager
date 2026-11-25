# 0032: Video passthrough: HDMI OUT shows the selected DUT's video

Status: Open
Opened: 2026-11-25 (lead, agreed direction with owner: the KVM's monitor path)

Today HDMI OUT always shows the FPGA console. Design brief US-04/US-11: the
monitor shows the selected target's video where available, else a clear
status screen. With no frame buffer (no DDR), pass the HDMI IN pixel stream
straight to HDMI OUT in the recovered pixel clock domain when the video
target is this board's capture-capable DUT and video is locked; fall back
to the console (local 27 MHz timing) otherwise. Glitch-free clock switch
(BUFGCTRL/BUFGMUX) between the console pixel clock (and its 5x serial
clock) and the dvi2rgb recovered clocks; the DVI transmitter must re-lock /
be reset cleanly on a switch. Console auto screen choice (0029) then means:
video present -> passthrough; no video -> no-video screen; selecting ->
select screen (later: optionally overlaid on the live video).
