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

## Neighbour link (issue 0069, ADR 0007 point 2; shield pin plan NB_UART_TX /
## NB_UART_RX): crossover UART to the unit's other supervisor on P12 row 23
## (A = G17 GPIO_14_P TX out, B = G18 GPIO_14_N RX in; GND on row 24). Same
## pins in the normal and the shield build. Board-to-board only (both boards
## are powered together), so TX is always driven (idle high); the RX PULLUP
## makes an open link read idle.
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports nb_uart_tx]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports nb_uart_rx]

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

## Seven segment (active low, common anode). seg[0..7] = 7SEG_0..7, which the
## V3.1 schematic wires to segments G, F, A, B, DP, C, D, E (not a..g!).
## Digit 4 (L4) exists on V3.0 only.
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

## DUT0 on P12 (bank 15), DUT1 on P13 (bank 16), same positions (ADR 0008
## amendment 2, owner 2026-11-25: bodge-friendly jumper strips, see
## docs/cabling/dut-cable.md). Rows: 3 GND, 4-7 GPIO_1-4 (P13: 21-24),
## 22/23/25/26 GPIO_13/14/15/16 (P13: 33-36); P in column A, N in column B.
##   JTAG+UART = rows 3-7 both columns = MEGA65 JB1 rows 1,2,4,5,6 (skip 5/6)
##   (amendment 5: cable odd pins / pin 1 on column B, even pins on column A)
##   keyboard  = rows 20 down to 16, both columns = MEGA65 J5 2x5 in order,
##               reversed (amendment 4/5): row 20 GND (J5 1/2), 19-17B J5 3-7
##               keyboard JTAG on unused pins, 17A KIO8, 16B KIO9, 16A KIO10;
##               J5 pin 2 (3V3) by its own jumper to row 22 A (sense input)
## No pulls on signals (brief section 5: minimise back-powering); sense inputs
## have PULLDOWN so an unplugged DUT reads unpowered. SLOW slew, 8 mA.
set_property -dict {PACKAGE_PIN J21 IOSTANDARD LVCMOS33} [get_ports dut0_uart_from]
set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_tck]
set_property -dict {PACKAGE_PIN K22 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_uart_to]
set_property -dict {PACKAGE_PIN K21 IOSTANDARD LVCMOS33} [get_ports dut0_tdo]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports dut0_vio_sense]
set_property -dict {PACKAGE_PIN H20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_tdi]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_tms]
set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVCMOS33} [get_ports dut0_kio8]
set_property -dict {PACKAGE_PIN M22 IOSTANDARD LVCMOS33} [get_ports dut0_kio9]
set_property -dict {PACKAGE_PIN N22 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut0_kio10]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports dut0_kb_sense]

set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports dut1_uart_from]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_tck]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_uart_to]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports dut1_tdo]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports dut1_vio_sense]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_tdi]
set_property -dict {PACKAGE_PIN C22 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_tms]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports dut1_kio8]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports dut1_kio9]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut1_kio10]
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports dut1_kb_sense]

## HDMI OUT (bank 35, TMDS_33 via IP4776 buffer); text display, ADR 0012
set_property -dict {PACKAGE_PIN L3 IOSTANDARD TMDS_33} [get_ports hdmi_tx_clk_p]
set_property -dict {PACKAGE_PIN K3 IOSTANDARD TMDS_33} [get_ports hdmi_tx_clk_n]
set_property -dict {PACKAGE_PIN B1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[0]}]
set_property -dict {PACKAGE_PIN A1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[0]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[1]}]
set_property -dict {PACKAGE_PIN D1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[1]}]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[2]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[2]}]

## Physical keyboard (master's own MEGA65 keyboard): P12 rows 14 down to 10,
## both columns, = the keyboard's 2x5 connector in order (ADR 0008 am. 4):
##   row 14 GND (pin 1); pin 2 (3.3 V supply) by its own jumper to row 15 A
##   rows 13-11B keyboard JTAG pins 3-7 (keyboard CPLD JTAG: pk_jtag_bodge.xdc)
##   row 11 A K18 GPIO_6_P KIO8 (pin 8)
##   row 10 B H22 GPIO_5_N KIO9 (pin 9), A J22 GPIO_5_P KIO10 (pin 10)
## MK-I (push-pull clock/data) or MK-II (I2C SDA/SCL, open drain), auto-
## detected by kbd_phys_host (issue 0009). The MK-II PCB has 1k pull-ups
## (R13/R14); the weak PULLUPs here only stop an empty port from floating
## (the keyboard is powered from the supervisor side, so no back-powering).
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports pk_kio8]
set_property -dict {PACKAGE_PIN H22 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports pk_kio9]
set_property -dict {PACKAGE_PIN J22 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports pk_kio10]

## Physical keyboard CPLD JTAG (issue 0046, ADR 0014): pins depend on the
## build, so they are not here: pk_jtag_bodge.xdc (normal build, the J5
## harness on P12 rows 13-11 B) or shield_v1.xdc (shield, SHIELD_RX > 0).

## HDMI IN (bank 35, TMDS_33 via IP4776; DVI sink, issue 0022). HPD
## asserted. DDC (issue 0033): EDID at 0x50, SDA open drain, SCL input only.
## The source supplies the DDC pull-ups (HDMI: 1.5-2 k to +5 V on its side
## of the IP4776 level shifter); the weak PULLUPs only stop an unplugged
## input from floating.
set_property -dict {PACKAGE_PIN K4 IOSTANDARD TMDS_33} [get_ports hdmi_rx_clk_p]
set_property -dict {PACKAGE_PIN J4 IOSTANDARD TMDS_33} [get_ports hdmi_rx_clk_n]
set_property -dict {PACKAGE_PIN K1 IOSTANDARD TMDS_33} [get_ports {hdmi_rx_p[0]}]
set_property -dict {PACKAGE_PIN J1 IOSTANDARD TMDS_33} [get_ports {hdmi_rx_n[0]}]
set_property -dict {PACKAGE_PIN M1 IOSTANDARD TMDS_33} [get_ports {hdmi_rx_p[1]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD TMDS_33} [get_ports {hdmi_rx_n[1]}]
set_property -dict {PACKAGE_PIN P2 IOSTANDARD TMDS_33} [get_ports {hdmi_rx_p[2]}]
set_property -dict {PACKAGE_PIN N2 IOSTANDARD TMDS_33} [get_ports {hdmi_rx_n[2]}]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports hdmi_rx_hpa]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports hdmi_rx_scl]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports hdmi_rx_sda]
