# QMTECH XC7K325T-1FFG676C core board + QMTECH daughter board (DB_FPGA V04).
# Pin map and sources: docs/hardware/qmtech-k325t.md. Daughter-board net
# "J2_IOn" sits on core-board U5 pin n-2, "J3_IOn" on U4 pin n-2.
# All header pins are HR banks 12-16 at 3.3 V.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
# Unused pins high-Z without pulls (Vivado's default is a pull-down).
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE [current_design]

# 50 MHz oscillator (bank 14)
set_property -dict {PACKAGE_PIN F22 IOSTANDARD LVCMOS33} [get_ports clk50]
create_clock -period 20.000 -name clk50 [get_ports clk50]

# 7-segment display U3 (common anode; segments active low through 330R)
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports {seg_n[0]}] ;# a  J2_IO31
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports {seg_n[1]}] ;# b  J2_IO26
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports {seg_n[2]}] ;# c  J2_IO28
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports {seg_n[3]}] ;# d  J2_IO32
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports {seg_n[4]}] ;# e  J2_IO34
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports {seg_n[5]}] ;# f  J2_IO29
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {seg_n[6]}] ;# g  J2_IO25
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {seg_n[7]}] ;# dp J2_IO30
# digit selects: S9014 NPN high-side drivers, active high
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {dig[0]}] ;# DIG_1 J2_IO33 (Q5)
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports {dig[1]}] ;# DIG_2 J2_IO27 (Q6)
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {dig[2]}] ;# DIG_3 J2_IO35 (Q7)

# Daughter-board LEDs D1-D5 (active low, 1k to 3V3)
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[0]}] ;# D1 J2_IO40
set_property -dict {PACKAGE_PIN A19 IOSTANDARD LVCMOS33} [get_ports {db_led_n[1]}] ;# D2 J2_IO39
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports {db_led_n[2]}] ;# D3 J2_IO38
set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[3]}] ;# D4 J2_IO37
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[4]}] ;# D5 J2_IO36
# Core-board LEDs (active low, bank 14)
set_property -dict {PACKAGE_PIN J26 IOSTANDARD LVCMOS33} [get_ports {core_led_n[0]}] ;# LED2 (D2)
set_property -dict {PACKAGE_PIN H26 IOSTANDARD LVCMOS33} [get_ports {core_led_n[1]}] ;# LED3 (D3)

# Daughter-board buttons (active low, 4.7k pull-ups to 3V3)
set_property -dict {PACKAGE_PIN AD21 IOSTANDARD LVCMOS33} [get_ports sw1_n] ;# SW1 J3_IO7
set_property -dict {PACKAGE_PIN B20  IOSTANDARD LVCMOS33} [get_ports sw2_n] ;# SW2 J2_IO44

# UART to the supervisor on daughter-board JP1 (owner 2026-11-27: J10/J11 are
# kept for PMOD microSD adapters). JP1 pin 6 = TX out, pin 4 = RX in (4.7k
# pull-up R64 on the board); GND on JP1 pin 2.
set_property -dict {PACKAGE_PIN B26 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports uart_tx] ;# JP1-6 J2_IO57
set_property -dict {PACKAGE_PIN C26 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports uart_rx] ;# JP1-4 J2_IO59

# VGA (resistor DAC; bit weights inferred from the resistor networks, MSB = 1k)
set_property -dict {PACKAGE_PIN W26 IOSTANDARD LVCMOS33} [get_ports vga_hs] ;# J3_IO44 (100R)
set_property -dict {PACKAGE_PIN W25 IOSTANDARD LVCMOS33} [get_ports vga_vs] ;# J3_IO43 (100R)
set_property -dict {PACKAGE_PIN P23 IOSTANDARD LVCMOS33} [get_ports {vga_r[4]}] ;# J3_IO57
set_property -dict {PACKAGE_PIN P25 IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}] ;# J3_IO56
set_property -dict {PACKAGE_PIN N26 IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}] ;# J3_IO59
set_property -dict {PACKAGE_PIN N23 IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}] ;# J3_IO58
set_property -dict {PACKAGE_PIN M26 IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}] ;# J3_IO60
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports {vga_g[5]}] ;# J3_IO51
set_property -dict {PACKAGE_PIN U25 IOSTANDARD LVCMOS33} [get_ports {vga_g[4]}] ;# J3_IO50
set_property -dict {PACKAGE_PIN R22 IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}] ;# J3_IO53
set_property -dict {PACKAGE_PIN T23 IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}] ;# J3_IO52
set_property -dict {PACKAGE_PIN R23 IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}] ;# J3_IO54
set_property -dict {PACKAGE_PIN R25 IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}] ;# J3_IO55
set_property -dict {PACKAGE_PIN V26 IOSTANDARD LVCMOS33} [get_ports {vga_b[4]}] ;# J3_IO46
set_property -dict {PACKAGE_PIN U26 IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}] ;# J3_IO45
set_property -dict {PACKAGE_PIN V24 IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}] ;# J3_IO48
set_property -dict {PACKAGE_PIN V23 IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}] ;# J3_IO47
set_property -dict {PACKAGE_PIN U24 IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}] ;# J3_IO49

# Slow, human-facing outputs: no timing paths of interest.
set_false_path -to [get_ports {seg_n[*] dig[*] db_led_n[*] core_led_n[*] uart_tx vga_*}]
set_false_path -from [get_ports {sw1_n sw2_n uart_rx}]
