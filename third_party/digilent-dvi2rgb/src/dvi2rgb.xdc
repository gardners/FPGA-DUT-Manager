### Clock constraints ###
# Constrain TMDS clock in the top-level project. Constraining it here, even if overridden in the top-level project
# results in [DRC 23-20] Rule violation (PDRC-34) for the maximum MMCM VCO frequency.
# create_clock -period 6.060 [get_ports TMDS_Clk_p]

### I/O constraints ###
# FPGA-DUT-Manager change (issue 0049): the IODELAY_GROUP of the data
# channel IDELAYE2 cells and the IDELAYCTRL is now a VHDL attribute
# (generic kIodelayGroup, default dvi2rgb_iodelay_grp), so several
# receivers can use separate groups.

### Asynchronous clock domain crossings ###
set_false_path -through [get_pins -filter {NAME =~ */*SyncAsync*/oSyncStages*/PRE || NAME =~ */*SyncAsync*/oSyncStages*/CLR} -hier]
set_false_path -through [get_pins -filter {NAME =~ */*SyncAsync*/oSyncStages_reg[0]/D} -hier]
set_false_path -through [get_pins -filter {NAME =~ */*SyncBase*/iIn_q*/PRE || NAME =~ */*SyncBase*/iIn_q*/CLR} -hier]
