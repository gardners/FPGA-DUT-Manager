# Vivado-only timing constraints (nextpnr-xilinx's XDC parser does not take
# these, so they are kept out of mimas_a7.xdc). Read by vivado/build.tcl.

# Clock domains (ADR 0004/0012). Crossings are toggles, 2-FF synchronisers,
# dual-clock RAMs or quasi-static configuration, so the groups are async.
set clk_sys  [get_clocks -of_objects [get_pins clk/mmcm/CLKOUT0]]
set clk_tx90 [get_clocks -of_objects [get_pins clk/mmcm/CLKOUT1]]
set clk_ref  [get_clocks -of_objects [get_pins clk/mmcm/CLKOUT2]]
set clk_pix  [get_clocks -of_objects [get_pins vclk/mmcm/CLKOUT0]]
set clk_pix5 [get_clocks -of_objects [get_pins vclk/mmcm/CLKOUT1]]
set_clock_groups -asynchronous \
  -group [list $clk_sys $clk_tx90] \
  -group $clk_ref \
  -group [list $clk_pix $clk_pix5] \
  -group [get_clocks rgmii_rxc]

# RGMII RX: the RTL8211E sends data edge-aligned with RXC (RXDLY strap off);
# IDELAYE2 adds ~2 ns. Allow +/-0.5 ns skew at the pins on both edges.
set rgmii_in [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock rgmii_rxc -max  0.5 $rgmii_in
set_input_delay -clock rgmii_rxc -min -0.5 $rgmii_in
set_input_delay -clock rgmii_rxc -clock_fall -max  0.5 -add_delay $rgmii_in
set_input_delay -clock rgmii_rxc -clock_fall -min -0.5 -add_delay $rgmii_in

# DUT-facing and front-panel I/O are slow/asynchronous.
set_false_path -to   [get_ports {dut*_* led[*] seg[*] seg_en[*] usb_uart_tx phy_rst_n phy_mdc phy_mdio}]
set_false_path -from [get_ports {dut*_* dip[*] btn[*] usb_uart_rx phy_mdio}]
