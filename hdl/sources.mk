# Synthesis source list (dependency order) for the Mimas A7 bitstream.
HDL_SRC := $(REPO)/hdl/src
SYNTH_TOP := mimas_a7_top
SYNTH_SOURCES := \
	$(HDL_SRC)/common/common_pkg.vhd \
	$(HDL_SRC)/common/sync_bit.vhd \
	$(HDL_SRC)/common/dpram.vhd \
	$(HDL_SRC)/proto/proto_pkg.vhd \
	$(HDL_SRC)/net/net_pkg.vhd \
	$(HDL_SRC)/uart/uart_tx.vhd \
	$(HDL_SRC)/uart/uart_rx.vhd \
	$(HDL_SRC)/uart/uart_bridge.vhd \
	$(HDL_SRC)/jtag/jtag_engine.vhd \
	$(HDL_SRC)/kbd/kbd_mk1_device.vhd \
	$(HDL_SRC)/eth/eth_mac_rx.vhd \
	$(HDL_SRC)/eth/eth_mac_tx.vhd \
	$(HDL_SRC)/net/net_rx.vhd \
	$(HDL_SRC)/net/net_tx.vhd \
	$(HDL_SRC)/top/supervisor_core.vhd \
	$(HDL_SRC)/platform/xc7/xc7_prims_pkg.vhd \
	$(HDL_SRC)/platform/xc7/clocks_xc7.vhd \
	$(HDL_SRC)/platform/xc7/rgmii_xc7.vhd \
	$(HDL_SRC)/top/mimas_a7_top.vhd
