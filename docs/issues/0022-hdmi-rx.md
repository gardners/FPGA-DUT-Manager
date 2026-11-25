# 0022: HDMI RX (27 MHz DVI) on Mimas A7

Status: Open
Opened: 2026-11-25

hdmi_rx: TMDS_33 inputs on bank 35 (vendor XDC), ISERDESE2 + IDELAYE2 per lane, bitslip word alignment on control tokens, channel deskew, TMDS decode, lock and geometry detection; HPD/EDID minimal. Only 27 MHz pixel clocks for now (owner). Testbench drives it from our dvi_tx.

## 2026-11-25 receiver imported and wired (untested on hardware)

* Licences checked: Digilent dvi2rgb (vivado-library ip/dvi2rgb, BSD-3 file
  headers / MIT repo) imported unmodified as third_party/digilent-dvi2rgb
  (provenance README, UPSTREAM_COMMIT). bunnie's netv2-fpga-dvi-decoder is
  GPL-3.0 and not used. **Owner: if dvi2rgb gives significant trouble, the
  project may switch to GPL and use bunnie's decoder instead.**
* platform/xc7/hdmi_rx_xc7.vhd wraps it: kClkRange 5 (>= 25 MHz, VCO 675 MHz
  at 27 MHz), no ILA, no EDID emulation (DDC released), HPD asserted;
  IDELAYCTRL reference = our 200 MHz clk_ref. Pins K4/J4, K1/J1, M1/L1,
  P2/N2 (TMDS_33), HPD G2; 27 MHz create_clock, async group.
* video_meas (vendor-neutral, tb_video_meas) measures geometry / pixel clock;
  the heartbeat video block now carries clock-present, locked, capture-
  enable, h/v total + active and pixel clock Hz.
* Next: hardware test with a MEGA65 at 27 MHz (owner: after the bigger PSU);
  then raster capture (0023).
