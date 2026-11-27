set_property SRC_FILE_INFO {cfile:/home/paul/Projects/mega65/FPGA-DUT-Manager/targets/qmtech-k325t/k325t_bringup.xdc rfile:../k325t_bringup.xdc id:1} [current_design]
set_property src_info {type:XDC file:1 line:13 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN F22 IOSTANDARD LVCMOS33} [get_ports clk50]
set_property src_info {type:XDC file:1 line:17 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports {seg_n[0]}] ;# a  J2_IO31
set_property src_info {type:XDC file:1 line:18 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports {seg_n[1]}] ;# b  J2_IO26
set_property src_info {type:XDC file:1 line:19 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports {seg_n[2]}] ;# c  J2_IO28
set_property src_info {type:XDC file:1 line:20 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports {seg_n[3]}] ;# d  J2_IO32
set_property src_info {type:XDC file:1 line:21 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports {seg_n[4]}] ;# e  J2_IO34
set_property src_info {type:XDC file:1 line:22 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports {seg_n[5]}] ;# f  J2_IO29
set_property src_info {type:XDC file:1 line:23 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {seg_n[6]}] ;# g  J2_IO25
set_property src_info {type:XDC file:1 line:24 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {seg_n[7]}] ;# dp J2_IO30
set_property src_info {type:XDC file:1 line:26 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {dig[0]}] ;# DIG_1 J2_IO33 (Q5)
set_property src_info {type:XDC file:1 line:27 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports {dig[1]}] ;# DIG_2 J2_IO27 (Q6)
set_property src_info {type:XDC file:1 line:28 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {dig[2]}] ;# DIG_3 J2_IO35 (Q7)
set_property src_info {type:XDC file:1 line:31 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[0]}] ;# D1 J2_IO40
set_property src_info {type:XDC file:1 line:32 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN A19 IOSTANDARD LVCMOS33} [get_ports {db_led_n[1]}] ;# D2 J2_IO39
set_property src_info {type:XDC file:1 line:33 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports {db_led_n[2]}] ;# D3 J2_IO38
set_property src_info {type:XDC file:1 line:34 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[3]}] ;# D4 J2_IO37
set_property src_info {type:XDC file:1 line:35 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {db_led_n[4]}] ;# D5 J2_IO36
set_property src_info {type:XDC file:1 line:37 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN J26 IOSTANDARD LVCMOS33} [get_ports {core_led_n[0]}] ;# LED2 (D2)
set_property src_info {type:XDC file:1 line:38 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN H26 IOSTANDARD LVCMOS33} [get_ports {core_led_n[1]}] ;# LED3 (D3)
set_property src_info {type:XDC file:1 line:41 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN AD21 IOSTANDARD LVCMOS33} [get_ports sw1_n] ;# SW1 J3_IO7
set_property src_info {type:XDC file:1 line:42 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN B20  IOSTANDARD LVCMOS33} [get_ports sw2_n] ;# SW2 J2_IO44
set_property src_info {type:XDC file:1 line:47 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN B26 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports uart_tx] ;# JP1-6 J2_IO57
set_property src_info {type:XDC file:1 line:48 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN C26 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports uart_rx] ;# JP1-4 J2_IO59
set_property src_info {type:XDC file:1 line:51 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN W26 IOSTANDARD LVCMOS33} [get_ports vga_hs] ;# J3_IO44 (100R)
set_property src_info {type:XDC file:1 line:52 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN W25 IOSTANDARD LVCMOS33} [get_ports vga_vs] ;# J3_IO43 (100R)
set_property src_info {type:XDC file:1 line:53 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN P23 IOSTANDARD LVCMOS33} [get_ports {vga_r[4]}] ;# J3_IO57
set_property src_info {type:XDC file:1 line:54 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN P25 IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}] ;# J3_IO56
set_property src_info {type:XDC file:1 line:55 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN N26 IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}] ;# J3_IO59
set_property src_info {type:XDC file:1 line:56 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN N23 IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}] ;# J3_IO58
set_property src_info {type:XDC file:1 line:57 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN M26 IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}] ;# J3_IO60
set_property src_info {type:XDC file:1 line:58 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports {vga_g[5]}] ;# J3_IO51
set_property src_info {type:XDC file:1 line:59 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN U25 IOSTANDARD LVCMOS33} [get_ports {vga_g[4]}] ;# J3_IO50
set_property src_info {type:XDC file:1 line:60 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN R22 IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}] ;# J3_IO53
set_property src_info {type:XDC file:1 line:61 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN T23 IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}] ;# J3_IO52
set_property src_info {type:XDC file:1 line:62 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN R23 IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}] ;# J3_IO54
set_property src_info {type:XDC file:1 line:63 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN R25 IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}] ;# J3_IO55
set_property src_info {type:XDC file:1 line:64 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN V26 IOSTANDARD LVCMOS33} [get_ports {vga_b[4]}] ;# J3_IO46
set_property src_info {type:XDC file:1 line:65 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN U26 IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}] ;# J3_IO45
set_property src_info {type:XDC file:1 line:66 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN V24 IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}] ;# J3_IO48
set_property src_info {type:XDC file:1 line:67 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN V23 IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}] ;# J3_IO47
set_property src_info {type:XDC file:1 line:68 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict {PACKAGE_PIN U24 IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}] ;# J3_IO49
