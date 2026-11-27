# microSD probe design (issue 0057): QMTECH XC7K325T + DB_FPGA V04.
# Pin map: docs/hardware/qmtech-k325t.md. The J11 weak pull (PULLTYPE) is set
# by build_sdprobe.tcl, one bitstream per pull (up / down / none).

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE [current_design]

set_property -dict {PACKAGE_PIN F22 IOSTANDARD LVCMOS33} [get_ports clk50]
create_clock -period 20.000 -name clk50 [get_ports clk50]

# 7-segment display, LEDs, SW1 (as in k325t_bringup.xdc)
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports {seg_n[0]}]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports {seg_n[1]}]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports {seg_n[2]}]
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports {seg_n[3]}]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports {seg_n[4]}]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports {seg_n[5]}]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {seg_n[6]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {seg_n[7]}]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {dig[0]}]
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports {dig[1]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {dig[2]}]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[0]}]
set_property -dict {PACKAGE_PIN A19 IOSTANDARD LVCMOS33} [get_ports {db_led_n[1]}]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports {db_led_n[2]}]
set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[3]}]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[4]}]
set_property -dict {PACKAGE_PIN J26 IOSTANDARD LVCMOS33} [get_ports {core_led_n[0]}]
set_property -dict {PACKAGE_PIN H26 IOSTANDARD LVCMOS33} [get_ports {core_led_n[1]}]
set_property -dict {PACKAGE_PIN AD21 IOSTANDARD LVCMOS33} [get_ports sw1_n] ;# SW1 J3_IO7

# UART on JP1 (pin 6 TX, pin 4 RX), same as the bring-up design
set_property -dict {PACKAGE_PIN B26 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports uart_tx] ;# JP1-6
set_property -dict {PACKAGE_PIN C26 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports uart_rx] ;# JP1-4

# PMOD J11 top row pins 1-4 (bidirectional; low drive so a pin tied to a
# rail, or fighting the card's DO in a wrong assignment, only sees a few mA)
# and bottom row pins 7-10 (inputs only)
set_property -dict {PACKAGE_PIN A8  IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports {j11[0]}] ;# J11-1 J2_IO7
set_property -dict {PACKAGE_PIN B9  IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports {j11[1]}] ;# J11-2 J2_IO9
set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports {j11[2]}] ;# J11-3 J2_IO11
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports {j11[3]}] ;# J11-4 J2_IO13
set_property -dict {PACKAGE_PIN A9  IOSTANDARD LVCMOS33} [get_ports {j11b[0]}] ;# J11-7 J2_IO8
set_property -dict {PACKAGE_PIN C9  IOSTANDARD LVCMOS33} [get_ports {j11b[1]}] ;# J11-8 J2_IO10
set_property -dict {PACKAGE_PIN B10 IOSTANDARD LVCMOS33} [get_ports {j11b[2]}] ;# J11-9 J2_IO12
set_property -dict {PACKAGE_PIN E10 IOSTANDARD LVCMOS33} [get_ports {j11b[3]}] ;# J11-10 J2_IO14

# Daughter-board microSD J9 (DB schematic; 4.7k pull-ups R68-R74 on all 7 lines)
set_property -dict {PACKAGE_PIN AE21 IOSTANDARD LVCMOS33} [get_ports sd_cd] ;# J9-9 CD, J3_IO8
set_property -dict {PACKAGE_PIN AE22 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports {sd_dat[1]}] ;# J9-8 DAT1, J3_IO9
set_property -dict {PACKAGE_PIN AF22 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports {sd_dat[0]}] ;# J9-7 DAT0, J3_IO10
set_property -dict {PACKAGE_PIN AE23 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports sd_clk]     ;# J9-5 CLK, J3_IO11
set_property -dict {PACKAGE_PIN AF23 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports sd_cmd]     ;# J9-3 CMD, J3_IO12
set_property -dict {PACKAGE_PIN V21  IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports {sd_dat[3]}] ;# J9-2 CD/DAT3, J3_IO13
set_property -dict {PACKAGE_PIN W21  IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports {sd_dat[2]}] ;# J9-1 DAT2, J3_IO14

# Slow I/O (250 kHz SPI, human-facing outputs): no timing paths of interest.
set_false_path -to [get_ports {seg_n[*] dig[*] db_led_n[*] core_led_n[*] uart_tx j11[*] sd_clk sd_cmd sd_dat[*]}]
set_false_path -from [get_ports {sw1_n uart_rx j11[*] j11b[*] sd_clk sd_cmd sd_dat[*] sd_cd}]
