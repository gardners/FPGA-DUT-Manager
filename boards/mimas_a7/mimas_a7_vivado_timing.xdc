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
  -group [get_clocks -include_generated_clocks rgmii_rxc]

# RGMII RX: the RTL8211E sends data edge-aligned with RXC (RXDLY strap off);
# the capture clock is the RX MMCM output shifted by RX_PHASE (rgmii_xc7).
# Allow +/-0.5 ns skew at the pins on both edges. For 0 < phase < 360 the
# default edge pairing (launch on an RXC edge, capture on the next shifted
# edge of the same sense) is the intended one; tune RX_PHASE / RX_IDELAY so
# setup and hold slack on the IDDR inputs balance.
set rgmii_in [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock rgmii_rxc -max  0.5 $rgmii_in
set_input_delay -clock rgmii_rxc -min -0.5 $rgmii_in
set_input_delay -clock rgmii_rxc -clock_fall -max  0.5 -add_delay $rgmii_in
set_input_delay -clock rgmii_rxc -clock_fall -min -0.5 -add_delay $rgmii_in

# DUT-facing and front-panel I/O are slow/asynchronous.
set_false_path -to   [get_ports {dut*_* pk_kio8 pk_kio9 led[*] seg[*] seg_en[*] usb_uart_tx phy_rst_n phy_mdc phy_mdio}]
set_false_path -from [get_ports {dut*_* pk_kio8 pk_kio9 pk_kio10 dip[*] btn[*] usb_uart_rx phy_mdio}]

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
