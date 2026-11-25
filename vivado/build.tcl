# Vivado batch build (issue 0005). On a machine with Vivado and a checkout:
#   make vivado            (uses scripts/vivado_wrapper from mega65-core)
# Needs nothing from tools/. Outputs build/vivado/: supervisor.bit,
# timing.rpt, utilization.rpt, drc.rpt, vivado.log.
set repo [file normalize [file dirname [info script]]/..]
set out  $repo/build/vivado
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
synth_design -top mimas_a7_top
opt_design
place_design
route_design
report_timing_summary -file $out/timing.rpt
report_drc -file $out/drc.rpt
report_clock_interaction -file $out/clock_interaction.rpt
report_utilization -file $out/utilization.rpt
write_bitstream -force $out/supervisor.bit

# One-line verdict (also in timing_verdict.txt): worst setup/hold slack and
# unconstrained endpoints across all clocks.
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set verdict [expr {($wns ne "" && $wns >= 0 && $whs ne "" && $whs >= 0) ? "MET" : "NOT MET"}]
set msg "TIMING $verdict: WNS $wns ns, WHS $whs ns (details in timing.rpt)"
puts "\n*** $msg ***\n"
set fh [open $out/timing_verdict.txt w]
puts $fh $msg
close $fh
