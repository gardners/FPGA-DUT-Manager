# Vivado-only timing constraints (nextpnr-xilinx's XDC parser does not take
# these, so they are kept out of mimas_a7.xdc). Read by vivado/build.tcl.

# Clock domains (ADR 0004/0012). Crossings are toggles, 2-FF synchronisers,
# dual-clock RAMs/FIFOs or quasi-static configuration, so the groups are
# async. The clk_ref group includes the DDR3 MIG clocks generated from it
# (memory, PHY and the 100 MHz UI clock; issue 0034), which meet clk_sys
# only through mem_app_bridge's async FIFOs and synchronisers.
set clk_sys  [get_clocks -of_objects [get_pins clk/mmcm/CLKOUT0]]
set clk_tx90 [get_clocks -of_objects [get_pins clk/mmcm/CLKOUT1]]
set clk_ref  [get_clocks -of_objects [get_pins clk/mmcm/CLKOUT2]]
set clk_pix  [get_clocks -of_objects [get_pins vclk/mmcm/CLKOUT0]]
set clk_pix5 [get_clocks -of_objects [get_pins vclk/mmcm/CLKOUT1]]
# HDMI IN: 27 MHz TMDS clock (MEGA65 modes, issue 0022); dvi2rgb's MMCM
# derives the pixel and 5x serial clocks from it.
create_clock -period 37.037 -name hdmi_rx_clk [get_ports hdmi_rx_clk_p]
# HDMI OUT passthrough (issue 0032): the TX clocks are BUFGCTRL muxes of the
# console pair (clk_pix/clk_pix5) and a PLL on the recovered pixel clock
# (auto-derived from hdmi_rx_clk, so in its group). Vivado propagates both
# through the muxes; the console->TX and HDMI IN->TX paths are timed inside
# each group, the cross pairings (only possible during a switch, with the TX
# in reset) are cut by these groups.
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks hdmi_rx_clk] \
  -group [list $clk_sys $clk_tx90] \
  -group [get_clocks -include_generated_clocks -of_objects [get_pins clk/mmcm/CLKOUT2]] \
  -group [list $clk_pix $clk_pix5] \
  -group [get_clocks -include_generated_clocks rgmii_rxc]

# RGMII RX (issue 0019): the RX sample phase was calibrated on hardware
# (scan: eye ~56..191 deg, centre ~124 deg, ~3 ns wide). Vivado's model of the
# same capture is ~1.7 ns off in position and far more pessimistic in width
# (slow-max vs fast-min corners), so a datasheet-style +/-0.5 ns window never
# meets even though the board has ~1.5 ns margin each side. These delays
# describe the *measured* data timing at the pins instead: data changes
# 1.75 ns +/- 0.2 ns before the RXC edge. That puts the model's centre on the
# calibrated phase (~+0.37 ns setup and hold at 123.75 deg) so the router does
# not chase paths it cannot change (IDDRs sit in the ILOGIC tiles). Re-derive
# if RX_PHASE_STEPS or the RX path changes: shift both values together.
set rgmii_in [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock rgmii_rxc -max -1.55 $rgmii_in
set_input_delay -clock rgmii_rxc -min -1.95 $rgmii_in
set_input_delay -clock rgmii_rxc -clock_fall -max -1.55 -add_delay $rgmii_in
set_input_delay -clock rgmii_rxc -clock_fall -min -1.95 -add_delay $rgmii_in

# DUT-facing and front-panel I/O are slow/asynchronous.
set_false_path -to   [get_ports {dut*_* pk_kio8 pk_kio9 pk_jtagen pk_tck pk_tms pk_tdi led[*] seg[*] seg_en[*] usb_uart_tx phy_rst_n phy_mdc phy_mdio hdmi_rx_hpa}]
set_false_path -from [get_ports {dut*_* pk_kio8 pk_kio9 pk_kio10 pk_tdo dip[*] btn[*] usb_uart_rx phy_mdio}]
# HDMI IN DDC (I2C, <= 400 kHz; synchronised and filtered in ddc_edid)
set_false_path -to   [get_ports hdmi_rx_sda]
set_false_path -from [get_ports {hdmi_rx_scl hdmi_rx_sda}]

# RGMII TX (issue 0019): TXC is forwarded by an ODDR clocked from clk_tx90
# (+90 deg), TXD/TX_CTL by ODDRs on clk_sys, so data is centred on TXC as the
# RTL8211E needs with TXDLY strapped off. PHY input requirements (RGMII v2.0
# without internal delay): setup >= 1.0 ns, hold >= 0.8 ns at the pins.
create_generated_clock -name rgmii_txc -source [get_pins phy/o_clk/C] \
  -multiply_by 1 [get_ports rgmii_txc]
set rgmii_out [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -clock rgmii_txc -max  1.0 $rgmii_out
set_output_delay -clock rgmii_txc -min -0.8 $rgmii_out
set_output_delay -clock rgmii_txc -clock_fall -max  1.0 -add_delay $rgmii_out
set_output_delay -clock rgmii_txc -clock_fall -min -0.8 -add_delay $rgmii_out

# RGMII RX is DDR: the IDDR rising edge captures data launched on RXC rising,
# the falling edge data launched on RXC falling. Exclude the cross-edge
# pairings Vivado would otherwise pick for a shifted capture clock
# (UG903 centre-aligned DDR source-synchronous template).
set rx_cap [get_clocks -of_objects [get_pins phy/rmmcm/CLKOUT0]]
set_false_path -setup -rise_from [get_clocks rgmii_rxc] -fall_to $rx_cap
set_false_path -setup -fall_from [get_clocks rgmii_rxc] -rise_to $rx_cap
set_false_path -hold  -rise_from [get_clocks rgmii_rxc] -rise_to $rx_cap
set_false_path -hold  -fall_from [get_clocks rgmii_rxc] -fall_to $rx_cap

# Device DNA (issue 0007): DNA_PORT is clocked at clk_sys/16 from a register
# and sampled half a DNA clock away from its edges; read once at start-up.
set_false_path -through [get_pins dnar/dp/DOUT]
set_false_path -to [get_pins {dnar/dp/CLK dnar/dp/READ dnar/dp/SHIFT}]
