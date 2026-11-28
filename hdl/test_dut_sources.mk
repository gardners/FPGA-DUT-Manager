# Synthesis source list (dependency order) for the test_dut bitstream
# (issue 0068), parsed by vivado/build_test_dut.tcl.
TEST_DUT_TOP := test_dut_top
TEST_DUT_SOURCES := \
	$(HDL_SRC)/common/dpram.vhd \
	$(HDL_SRC)/uart/uart_tx.vhd \
	$(HDL_SRC)/uart/uart_rx.vhd \
	$(HDL_SRC)/testdut/jtag_tap_soft.vhd \
	$(HDL_SRC)/testdut/testdut_uart.vhd \
	$(HDL_SRC)/testdut/test_dut_top.vhd
