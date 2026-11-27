# Non-project Vivado build of the K325T bring-up design.
# vivado -mode batch -source build.tcl -tclargs <outdir>
set here [file dirname [file normalize [info script]]]
set out [lindex $argv 0]
if {$out eq ""} { set out $here/build }
file mkdir $out

set_part xc7k325tffg676-1
read_vhdl -vhdl2008 $here/hdl/k325t_bringup.vhd
read_xdc $here/k325t_bringup.xdc
synth_design -top k325t_bringup -part xc7k325tffg676-1
opt_design
place_design
route_design
report_timing_summary -file $out/timing.rpt
report_utilization -file $out/util.rpt
write_bitstream -force $out/k325t_bringup.bit
