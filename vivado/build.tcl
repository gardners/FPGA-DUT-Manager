# Vivado batch build (issue 0005). On a machine with Vivado and a checkout:
#   make vivado            (uses scripts/vivado_wrapper from mega65-core)
# Needs nothing from tools/. Outputs build/vivado/: supervisor.bit,
# timing.rpt, utilization.rpt, drc.rpt, vivado.log.
set repo [file normalize [file dirname [info script]]/..]
# VIVADO_OUT overrides the output directory; VIVADO_GENERICS passes top-level
# generics, e.g. "RX_PHASE_STEPS=40" (space-separated NAME=VALUE).
set out  $repo/build/vivado
if {[info exists ::env(VIVADO_OUT)] && $::env(VIVADO_OUT) ne ""} { set out [file normalize $::env(VIVADO_OUT)] }
set gen {}
if {[info exists ::env(VIVADO_GENERICS)]} { set gen $::env(VIVADO_GENERICS) }
file mkdir $out

# Source list: parse hdl/sources.mk so both flows use the same files.
set fh [open $repo/hdl/sources.mk r]
set mk [read $fh]
close $fh
set srcs {}
foreach tok [regexp -all -inline {\$\((?:HDL_SRC|REPO)\)/[^\s\\]+\.vhdl?} $mk] {
  regsub {\$\(HDL_SRC\)} $tok $repo/hdl/src tok
  regsub {\$\(REPO\)} $tok $repo tok
  lappend srcs $tok
}

# build id package (same as the Makefile generates)
set gid [string trim [exec git -C $repo rev-parse --short=8 HEAD]]
set fh [open $out/build_id_pkg.vhd w]
puts $fh "library ieee;\nuse ieee.std_logic_1164.all;\npackage build_id_pkg is\n  constant BUILD_ID : std_logic_vector(31 downto 0) := x\"$gid\";\nend package;"
close $fh

create_project -in_memory -part xc7a50tfgg484-1
read_vhdl -vhdl2008 [concat [list $out/build_id_pkg.vhd] $srcs]
read_xdc $repo/boards/mimas_a7/mimas_a7.xdc
read_xdc $repo/boards/mimas_a7/mimas_a7_vivado_timing.xdc
set sargs [list -top mimas_a7_top]
foreach g $gen { lappend sargs -generic $g }
synth_design {*}$sargs
opt_design
place_design
route_design
report_timing_summary -file $out/timing.rpt
report_timing -setup -max_paths 40 -nworst 1 -unique_pins -sort_by slack -file $out/timing_paths.rpt
report_drc -file $out/drc.rpt
report_clock_interaction -file $out/clock_interaction.rpt
report_utilization -file $out/utilization.rpt
write_bitstream -force $out/supervisor.bit

# One-line verdict (also in timing_verdict.txt): worst setup/hold slack over
# all paths except the RGMII RX IDDR inputs, which are calibrated on hardware
# (issue 0019: the static model is far more pessimistic than a real board);
# their static slack is reported alongside for information.
proc worst {kind} {
  set w ""
  foreach p [get_timing_paths -$kind -max_paths 200 -nworst 1] {
    if {[string match "phy/g_rx*" [get_property NAME [get_property ENDPOINT_PIN $p]]]} continue
    set s [get_property SLACK $p]
    if {$w eq "" || $s < $w} { set w $s }
  }
  return $w
}
set wns [worst setup]
set whs [worst hold]
set rxp [get_pins -hier -filter {NAME =~ phy/g_rx*.id/D}]
set rxs [get_property SLACK [get_timing_paths -setup -max_paths 1 -to $rxp]]
set rxh [get_property SLACK [get_timing_paths -hold  -max_paths 1 -to $rxp]]
set verdict [expr {($wns ne "" && $wns >= 0 && $whs ne "" && $whs >= 0) ? "MET" : "NOT MET"}]
set msg "TIMING $verdict: WNS $wns ns, WHS $whs ns; RGMII RX static setup $rxs / hold $rxh ns (hardware-calibrated) (details in timing.rpt)"
puts "\n*** $msg ***\n"
set fh [open $out/timing_verdict.txt w]
puts $fh $msg
close $fh
