# Mimas A7 (pre-V4, V2.0/V3.0) constraints for mimas_a7_top.
# Sources: boards/mimas_a7/vendor/*.xdc (Numato), ADR 0003/0008,
# docs/cabling/dut-cable.md. All banks used here are 3.3 V.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Clock
set_property -dict {PACKAGE_PIN H4 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -period 10.000 -name clk100 [get_ports clk100]

## Ethernet RTL8211E (RGMII, PHY delays strapped off)
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports phy_rst_n]
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports phy_mdc]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports phy_mdio]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 12} [get_ports rgmii_txc]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 12} [get_ports rgmii_tx_ctl]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 12} [get_ports {rgmii_txd[0]}]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 12} [get_ports {rgmii_txd[1]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 12} [get_ports {rgmii_txd[2]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 12} [get_ports {rgmii_txd[3]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports rgmii_rxc]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports rgmii_rx_ctl]
set_property -dict {PACKAGE_PIN AB18 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[0]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[1]}]
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[2]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[3]}]
create_clock -period 8.000 -name rgmii_rxc [get_ports rgmii_rxc]

## USB UART (FTDI channel A): FTDI D0 = TXD (to FPGA), D1 = RXD (from FPGA)
set_property -dict {PACKAGE_PIN Y22 IOSTANDARD LVCMOS33} [get_ports usb_uart_rx]
set_property -dict {PACKAGE_PIN Y21 IOSTANDARD LVCMOS33} [get_ports usb_uart_tx]

## LEDs, DIP switch, push buttons
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_property -dict {PACKAGE_PIN B21 IOSTANDARD LVCMOS33} [get_ports {dip[0]}]
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS33} [get_ports {dip[1]}]
set_property -dict {PACKAGE_PIN E22 IOSTANDARD LVCMOS33} [get_ports {dip[2]}]
set_property -dict {PACKAGE_PIN D22 IOSTANDARD LVCMOS33} [get_ports {dip[3]}]
set_property -dict {PACKAGE_PIN E21 IOSTANDARD LVCMOS33} [get_ports {dip[4]}]
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS33} [get_ports {dip[5]}]
set_property -dict {PACKAGE_PIN G21 IOSTANDARD LVCMOS33} [get_ports {dip[6]}]
set_property -dict {PACKAGE_PIN G22 IOSTANDARD LVCMOS33} [get_ports {dip[7]}]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {btn[3]}]

## Seven segment (active low). Digit 4 (L4) exists on V3.0 only.
set_property -dict {PACKAGE_PIN P4 IOSTANDARD LVCMOS33} [get_ports {seg[0]}]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD LVCMOS33} [get_ports {seg[1]}]
set_property -dict {PACKAGE_PIN M3 IOSTANDARD LVCMOS33} [get_ports {seg[2]}]
set_property -dict {PACKAGE_PIN M5 IOSTANDARD LVCMOS33} [get_ports {seg[3]}]
set_property -dict {PACKAGE_PIN L5 IOSTANDARD LVCMOS33} [get_ports {seg[4]}]
set_property -dict {PACKAGE_PIN L6 IOSTANDARD LVCMOS33} [get_ports {seg[5]}]
set_property -dict {PACKAGE_PIN M6 IOSTANDARD LVCMOS33} [get_ports {seg[6]}]
set_property -dict {PACKAGE_PIN P5 IOSTANDARD LVCMOS33} [get_ports {seg[7]}]
set_property -dict {PACKAGE_PIN N3 IOSTANDARD LVCMOS33} [get_ports {seg_en[0]}]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports {seg_en[1]}]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports {seg_en[2]}]
set_property -dict {PACKAGE_PIN L4 IOSTANDARD LVCMOS33} [get_ports {seg_en[3]}]

## DUT0 on P12 (bank 15). J block rows 22-27, K block rows 28-33.
## No pulls on signals (brief section 5: minimise back-powering); sense inputs
## have PULLDOWN so an unplugged DUT reads unpowered. SLOW slew, 8 mA.
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_tck]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_tms]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_tdi]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports dut0_tdo]
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_uart_to]
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33} [get_ports dut0_uart_from]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports dut0_vio_sense]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports dut0_kio8]
set_property -dict {PACKAGE_PIN K14 IOSTANDARD LVCMOS33} [get_ports dut0_kio9]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_kio10]
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports dut0_kb_sense]

## DUT1 on P13 (bank 16), same block positions.
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_tck]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_tms]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_tdi]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports dut1_tdo]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_uart_to]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports dut1_uart_from]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports dut1_vio_sense]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports dut1_kio8]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports dut1_kio9]
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_kio10]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports dut1_kb_sense]

## HDMI OUT (bank 35, TMDS_33 via IP4776 buffer); text display, ADR 0012
set_property -dict {PACKAGE_PIN L3 IOSTANDARD TMDS_33} [get_ports hdmi_tx_clk_p]
set_property -dict {PACKAGE_PIN K3 IOSTANDARD TMDS_33} [get_ports hdmi_tx_clk_n]
set_property -dict {PACKAGE_PIN B1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[0]}]
set_property -dict {PACKAGE_PIN A1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[0]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[1]}]
set_property -dict {PACKAGE_PIN D1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[1]}]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[2]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[2]}]
