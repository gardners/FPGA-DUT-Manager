# 0015: 80x25 text fallback display over HDMI

Status: In progress
Opened: 2026-11-25

Implement ADR 0012: text_rx_tap fast path (UDP 6508 straight into BRAM in clk_rx), char/attr/palette memories, text renderer (from hardweb text_console), 720x576p50 timing, TMDS/DVI output on the Mimas HDMI OUT, dutctl text command to push screens. Depends on 0016.
