# Shield v1 (issues 0045/0049): header HDMI receivers HDMI1..HDMI3 for
# DUT1..DUT3. Read by vivado/build.tcl only when SHIELD_RX > 0 (generic of
# mimas_a7_top). Pin plan, net names and the rest of the shield pins:
# docs/hardware/shield-pinplan.md. Port index i = HDMI(i+1); data lane k of
# receiver i = shd_d_*[3*i+k]. P balls are on header column A (vendor XDC:
# GPIO_n_P). TMDS_33 needs VCCO 3.3 V (banks 15/16 are fixed at 3.3 V) and
# has no internal termination: the shield has 50 ohm to 3.3 V per line.

## HDMI1 (DUT1): P13 (bank 16). Clock on IO_L13 MRCC (row 11).
set_property -dict {PACKAGE_PIN C18 IOSTANDARD TMDS_33} [get_ports {shd_clk_p[0]}]
set_property -dict {PACKAGE_PIN C19 IOSTANDARD TMDS_33} [get_ports {shd_clk_n[0]}]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD TMDS_33} [get_ports {shd_d_p[0]}]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD TMDS_33} [get_ports {shd_d_n[0]}]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD TMDS_33} [get_ports {shd_d_p[1]}]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD TMDS_33} [get_ports {shd_d_n[1]}]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD TMDS_33} [get_ports {shd_d_p[2]}]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD TMDS_33} [get_ports {shd_d_n[2]}]

## HDMI2 (DUT2): P13 (bank 16). Clock on IO_L12 MRCC (row 12).
set_property -dict {PACKAGE_PIN D17 IOSTANDARD TMDS_33} [get_ports {shd_clk_p[1]}]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD TMDS_33} [get_ports {shd_clk_n[1]}]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD TMDS_33} [get_ports {shd_d_p[3]}]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD TMDS_33} [get_ports {shd_d_n[3]}]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD TMDS_33} [get_ports {shd_d_p[4]}]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD TMDS_33} [get_ports {shd_d_n[4]}]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD TMDS_33} [get_ports {shd_d_p[5]}]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD TMDS_33} [get_ports {shd_d_n[5]}]

## HDMI3 (DUT3): P12 (bank 15). Clock on IO_L14 SRCC (row 12).
set_property -dict {PACKAGE_PIN L19 IOSTANDARD TMDS_33} [get_ports {shd_clk_p[2]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD TMDS_33} [get_ports {shd_clk_n[2]}]
set_property -dict {PACKAGE_PIN M21 IOSTANDARD TMDS_33} [get_ports {shd_d_p[6]}]
set_property -dict {PACKAGE_PIN L21 IOSTANDARD TMDS_33} [get_ports {shd_d_n[6]}]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD TMDS_33} [get_ports {shd_d_p[7]}]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD TMDS_33} [get_ports {shd_d_n[7]}]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD TMDS_33} [get_ports {shd_d_p[8]}]
set_property -dict {PACKAGE_PIN N19 IOSTANDARD TMDS_33} [get_ports {shd_d_n[8]}]

## DDC (EDID served by ddc_edid; PCA9306 level shifter on the shield
## provides the 3.3 V-side pull-ups; weak PULLUPs only stop floating)
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {shd_scl[0]}]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports {shd_sda[0]}]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {shd_scl[1]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports {shd_sda[1]}]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {shd_scl[2]}]
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports {shd_sda[2]}]

## Timing (Vivado only). 27 MHz TMDS clocks (MEGA65 modes), each async to
## everything else; the PLL-derived pixel/serial clocks follow their input.
create_clock -period 37.037 -name shd_rx_clk0 [get_ports {shd_clk_p[0]}]
create_clock -period 37.037 -name shd_rx_clk1 [get_ports {shd_clk_p[1]}]
create_clock -period 37.037 -name shd_rx_clk2 [get_ports {shd_clk_p[2]}]
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks shd_rx_clk0] \
  -group [get_clocks -include_generated_clocks shd_rx_clk1] \
  -group [get_clocks -include_generated_clocks shd_rx_clk2] \
  -group [get_clocks -include_generated_clocks {clk100 rgmii_rxc hdmi_rx_clk}]
set_false_path -to   [get_ports {shd_sda[*]}]
set_false_path -from [get_ports {shd_scl[*] shd_sda[*]}]

## Physical keyboard CPLD JTAG on the shield (issue 0046, ADR 0014;
## docs/hardware/shield-pinplan.md): HDMI3 above takes the bodge pins
## L19/L20/M21/L21. PK_JTAGEN is on I2C expander B (TCA6416A @0x20, P0.3),
## driven from supervisor_core's pk_jtag_oe once the shield I2C master exists
## (issue 0049 step 2); there is no pk_jtagen port in this build.
set_property -dict {PACKAGE_PIN H19 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLDOWN TRUE} [get_ports pk_tck]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE}   [get_ports pk_tms]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE}   [get_ports pk_tdi]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports pk_tdo]
set_false_path -to   [get_ports {pk_tck pk_tms pk_tdi}]
set_false_path -from [get_ports pk_tdo]
