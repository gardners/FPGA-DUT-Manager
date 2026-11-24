# 0016: HDMI/DVI transmitter on Mimas A7 under openXC7

Status: Open
Opened: 2026-11-25

27 MHz pixel clock + 135 MHz (5x) from a second MMCM; TMDS encode + 10:1 via ODDR at 135 MHz DDR (hardweb dvi_tx_simple/ddr_out_emard) or OSERDESE2. Pins in vendor XDC (TMDS_33, bank 35). Check nextpnr-xilinx support and monitor lock; DDC/HPD read-only for now.
