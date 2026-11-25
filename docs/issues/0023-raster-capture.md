# 0023: Raster capture path and raster-first TX scheduling

Status: Open
Opened: 2026-11-25

Pixel-domain async FIFO into a 16 KiB raster packet ring in clk_sys with complete-packet commit and overflow drop counting; raster packets have absolute priority at frame boundaries; capture enable per DUT (off by default). System test reconstructs a frame from captured packets.
