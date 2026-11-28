# Mimas A7 (pre-V4, V3.0) constraints for test_dut_top (issue 0068): a
# second Mimas acting as a test DUT on the supervisor's DUT0 port, wired by
# straight jumpers P12 rows 3-7 -> P12 rows 3-7. Same balls as the
# supervisor's DUT0 port (mimas_a7.xdc), each in the opposite direction.
# Clock, LEDs, DIP and 7-segment as in mimas_a7.xdc. All banks 3.3 V.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Clock
set_property -dict {PACKAGE_PIN H4 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -period 10.000 -name clk100 [get_ports clk100]

## USB UART (FTDI channel A, D1 = RXD from the FPGA): mirror of the DUT UART TX
set_property -dict {PACKAGE_PIN Y21 IOSTANDARD LVCMOS33} [get_ports usb_uart_tx]

## LEDs, DIP switch
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

## Seven segment (active low; seg[0..7] = segments G, F, A, B, DP, C, D, E;
## digit 4 / seg_en[3] on V3.0 only)
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

## DUT side of P12 rows 4-7 (bank 15). No pulls (the supervisor side has a
## PULLDOWN on G20 only); outputs SLOW slew, 8 mA as on the supervisor.
##   row 4 B J21 UART TX out    row 4 A J20 TCK in
##   row 5 B K22 UART RX in     row 5 A K21 TDO out
##   row 6 B G20 powered out    row 6 A H20 TDI in
##   row 7 B H19 spare in       row 7 A J19 TMS in
set_property -dict {PACKAGE_PIN J21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut_uart_tx]
set_property -dict {PACKAGE_PIN K22 IOSTANDARD LVCMOS33} [get_ports dut_uart_rx]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut_powered]
set_property -dict {PACKAGE_PIN H19 IOSTANDARD LVCMOS33} [get_ports dut_spare]
set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33} [get_ports dut_tck]
set_property -dict {PACKAGE_PIN K21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dut_tdo]
set_property -dict {PACKAGE_PIN H20 IOSTANDARD LVCMOS33} [get_ports dut_tdi]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports dut_tms]

## All DUT pins and the DIP switch are asynchronous to clk100 (2-flop
## synchronisers in the design); outputs drive slow external logic.
set_false_path -from [get_ports {dut_uart_rx dut_tck dut_tms dut_tdi dut_spare dip[*]}]
set_false_path -to [get_ports {dut_uart_tx dut_tdo dut_powered usb_uart_tx led[*] seg[*] seg_en[*]}]
