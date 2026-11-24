# 0002: Confirm FPGA IDCODE and JTAG over FTDI channel B

Status: Open
Opened: 2026-11-25

Run `make detect` (openFPGALoader -b mimas_a7). Expect XC7A50T IDCODE 0x0362C093. Then SRAM-load a blinky. Do not touch flash until SRAM programming works (brief §12). Board under test: USB serial NL4IT7JQ.

## 2026-11-25 result

`openFPGALoader -b mimas_a7 --detect` at the profile default 30 MHz returned a
corrupt IDCODE 0x03408007. At 6 MHz and 1 MHz: **idcode 0x0362c093, xc7a50t,
irlength 6** — FPGA confirmed. Makefile now defaults `JTAG_FREQ=6000000`.
Remaining: SRAM-load a test bitstream.
