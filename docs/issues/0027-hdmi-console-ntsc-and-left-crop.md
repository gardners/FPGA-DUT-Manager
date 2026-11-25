# 0027: HDMI console: switch to 720x480p60; left ~2.5 characters cut off

Status: Done (2026-11-25)
Opened: 2026-11-25

Owner hardware feedback (2026-11-25, build da7897a1):

1. The leftmost ~2.5 characters (~22 px) of the 80x25 console are not
   visible on the monitor.
2. Use NTSC 60 Hz (720x480p60, CEA-861 mode 2/3: 858 x 525 total,
   H FP 16 / sync 62 / BP 60, V FP 9 / sync 6 / BP 30, negative syncs,
   27.000 MHz — same pixel clock as now) instead of 720x576p50, so the
   400-line text area fills more of the screen (TOP = 40 instead of 88).

Notes on (1): `text_display` delays DE/HS/VS by 5 clocks, matching its
5-stage pixel pipeline, so the image is not shifted inside the DE window.
80 columns x 9 px = 720 = the whole active width with `LEFT = 0`, so any
overscan or left-edge mis-sampling by the monitor eats text. Check after the
mode change (monitor's own "fit/1:1" setting, and measure the visible edge
with a test pattern: column markers every 8 px). If the monitor really
loses the edge, options: 8-px cells (640 px wide, centred, LEFT = 40) or a
narrower box-drawing-free mode. Video capture (0022/0023) concerns DUT
video, not this console — only the console timing changes.

## 2026-11-25 hardware + fix

480p60 confirmed (owner). Still ~1.5 cells hidden on the left: SD "720"
modes have only ~704 px of picture (BT.601), the monitor hides the edges.
Owner decision: keep 9-px cells, shift right. Top level now uses
`text_display` LEFT = 18 (2 cells); columns 78-79 fall outside DE, so ~78
columns are visible, which is fine.

## 2026-11-25 closed

480p60, LEFT 15 confirmed by the owner.
