# Non-project Vivado build of the microSD probe (issue 0057).
# vivado -mode batch -source build_sdprobe.tcl -tclargs <outdir> [up|down|none]
# J11 pins 1-4 and 7-10 get the FPGA weak pull named by the 2nd argument
# (default up); output <outdir>/k325t_sdprobe_<pull>.bit
set here [file dirname [file normalize [info script]]]
set out [lindex $argv 0]
if {$out eq ""} { set out $here/build }
set pull [lindex $argv 1]
if {$pull eq ""} { set pull up }
array set sel {none 0 up 1 down 2}
array set ptype {up PULLUP down PULLDOWN}
file mkdir $out

set_part xc7k325tffg676-1
read_vhdl -vhdl2008 $here/hdl/k325t_sdprobe.vhd
read_xdc $here/k325t_sdprobe.xdc
synth_design -top k325t_sdprobe -part xc7k325tffg676-1 -generic PULL_SEL=$sel($pull)
if {$pull ne "none"} {
  set_property PULLTYPE $ptype($pull) [get_ports {j11[*] j11b[*]}]
}
opt_design
place_design
route_design
report_timing_summary -file $out/timing_sdprobe_$pull.rpt
report_utilization -file $out/util_sdprobe_$pull.rpt
report_drc -file $out/drc_sdprobe_$pull.rpt
write_bitstream -force $out/k325t_sdprobe_$pull.bit
