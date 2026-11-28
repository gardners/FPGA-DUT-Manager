# Vivado batch build of the test_dut bitstream (issue 0068) for a second
# Mimas A7 wired to the supervisor's DUT0 port. On the build box:
#   make bitstream-test-dut
# Outputs build/vivado-test-dut/ (VIVADO_OUT overrides): test_dut.bit,
# timing.rpt, utilization.rpt, drc.rpt, timing_verdict.txt, build_id.txt,
# vivado.log. The build id (git short hash, as for the supervisor) is
# passed as the BUILD_ID generic and shown in every status line.
set repo [file normalize [file dirname [info script]]/..]
set out  $repo/build/vivado-test-dut
if {[info exists ::env(VIVADO_OUT)] && $::env(VIVADO_OUT) ne ""} { set out [file normalize $::env(VIVADO_OUT)] }
file mkdir $out

set fh [open $repo/hdl/test_dut_sources.mk r]
set mk [read $fh]
close $fh
set srcs {}
foreach tok [regexp -all -inline {\$\(HDL_SRC\)/[^\s\\]+\.vhdl?} $mk] {
  regsub {\$\(HDL_SRC\)} $tok $repo/hdl/src tok
  lappend srcs $tok
}

set gid [string trim [exec git -C $repo rev-parse --short=8 HEAD]]
set fh [open $out/build_id.txt w]
puts $fh $gid
close $fh

create_project -in_memory -part xc7a50tfgg484-1
read_vhdl -vhdl2008 $srcs
read_xdc $repo/boards/mimas_a7/test_dut.xdc
synth_design -top test_dut_top -generic "BUILD_ID=32'h$gid"
opt_design
place_design
route_design
report_timing_summary -file $out/timing.rpt
report_drc -file $out/drc.rpt
report_utilization -file $out/utilization.rpt
write_bitstream -force $out/test_dut.bit

set wns [get_property SLACK [get_timing_paths -setup -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -hold  -max_paths 1]]
set verdict [expr {($wns ne "" && $wns >= 0 && $whs ne "" && $whs >= 0) ? "MET" : "NOT MET"}]
set msg "TIMING $verdict: WNS $wns ns, WHS $whs ns; build $gid (details in timing.rpt)"
puts "\n*** $msg ***\n"
set fh [open $out/timing_verdict.txt w]
puts $fh $msg
close $fh
