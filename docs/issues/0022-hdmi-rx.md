# 0022: HDMI RX (27 MHz DVI) on Mimas A7

Status: Open
Opened: 2026-11-25

hdmi_rx: TMDS_33 inputs on bank 35 (vendor XDC), ISERDESE2 + IDELAYE2 per lane, bitslip word alignment on control tokens, channel deskew, TMDS decode, lock and geometry detection; HPD/EDID minimal. Only 27 MHz pixel clocks for now (owner). Testbench drives it from our dvi_tx.
