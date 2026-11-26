# Physical keyboard CPLD JTAG, normal (bodge) build: read by vivado/build.tcl
# only when SHIELD_RX = 0. pk_jtagen exists only in this build (in the shield
# build PK_JTAGEN is on I2C expander B).
## Physical keyboard CPLD JTAG (keyboard J5 pins 3-7 = P12 rows 13-11B,
## issue 0046, ADR 0014): a third JTAG engine (JTAG_REQ flags b1), tri-
## stated unless enabled (keyboard detected / lease / MGMT key 0x0061).
## Row r = GPIO_(r-5) for rows 10-13; column A = _P, column B = _N.
##   row 13 B L21 GPIO_8_N KB_JTAGEN (pin 3, driven '1' when enabled)
##   row 13 A M21 GPIO_8_P KB_TMS    (pin 4)
##   row 12 B L20 GPIO_7_N KB_TCK    (pin 5)
##   row 12 A L19 GPIO_7_P KB_TDI    (pin 6)
##   row 11 B K19 GPIO_6_N KB_TDO    (pin 7, input)
## Normal (bodge) build only: the shield build gives L19/L20/M21/L21 to
## HDMI3 and uses its own keyboard JTAG pins (shield_v1.xdc). Weak pulls hold
## the TAP quiet while tri-stated: TCK and JTAGEN low (the MEGA65 mainboard
## also holds kb_jtagen low), TMS high (TAP stays in Test-Logic-Reset).
set_property -dict {PACKAGE_PIN L21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLDOWN TRUE} [get_ports {pk_jtagen[0]}]
set_property -dict {PACKAGE_PIN M21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE}   [get_ports pk_tms]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLDOWN TRUE} [get_ports pk_tck]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE}   [get_ports pk_tdi]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports pk_tdo]
set_false_path -to   [get_ports {pk_jtagen[*] pk_tck pk_tms pk_tdi}]
set_false_path -from [get_ports pk_tdo]
