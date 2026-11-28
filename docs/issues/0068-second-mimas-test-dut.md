# 0068: Second Mimas A7 as a test DUT on the supervisor's DUT0 port

Status: superseded as the plan for Mimas #2 by 0069 (owner, 2026-11-28: same supervisor image + crossover neighbour UART). The test_dut image stays as an optional bench tool (`make bitstream-test-dut`).
the same board becomes supervisor B = 1 once it has Ethernet), 0056/0067
(outputs off / TX low), 0054 (JTAG), ADR 0008, docs/cabling/dut-cable.md.

## Owner (2026-11-28)

"I have a 2nd Mimas Board I can connect to the DUT framework, but I need
to organise the gig ethernet cabling to be able to give it network. But I
should be able to put it on USB JTAG for you, and when you tell me the
pins to connect between the two boards on the headers, I can do that."

## Plan (lead)

Until it has Ethernet, Mimas #2 is a **test DUT** with a bitstream of its
own (`test_dut`), wired to the supervisor's DUT0 port. That gives a DUT
whose behaviour we know exactly, without the MEGA65: UART both ways, JTAG
through the supervisor's jtag_engine/XVC to a soft TAP in #2's fabric,
VIO sense / out-policy, and a **readback of the supervisor's TX line
level** (proves 0067's low-when-off on hardware).

Wiring: P12 rows 3-7, both columns, **straight** P12 -> P12 (two strips of
5 jumpers, A->A and B->B). Same balls on both boards; #2 uses each pin in
the opposite direction:

| P12 row | col | supervisor (DUT0 port) | Mimas #2 (test_dut) |
|---|---|---|---|
| 3 | A, B | GND | GND |
| 4 | B | J21 UART from DUT (in) | J21 UART TX (out) |
| 5 | B | K22 UART to DUT (out) | K22 UART RX (in) |
| 6 | B | G20 VIO sense (in, pulldown) | G20 "powered" (out, driven high) |
| 7 | B | H19 spare | H19 spare (unconnected in logic) |
| 4 | A | J20 TCK (out) | J20 TCK (in) |
| 5 | A | K21 TDO (in) | K21 TDO (out) |
| 6 | A | H20 TDI (out) | H20 TDI (in) |
| 7 | A | J19 TMS (out) | J19 TMS (in) |

#2 drives "powered" on G20 directly (3.3 V LVCMOS, 4 mA): no resistor
needed (both boards 3.3 V; the supervisor input has only a pulldown).
Both boards on their own DC jacks; #2 on USB for JTAG (FTDI serial needed
for loads: check-board refuses ambiguity). The MEGA65's JTAG/UART harness
must be off DUT0 rows 3-7 meanwhile.

## 2026-11-28 agent: test_dut bitstream built (branch feature/test-dut)

**What.** `hdl/src/testdut/`: `test_dut_top` (100 MHz board clock, no
MMCM, no CPU), `testdut_uart` (echo + status line), `jtag_tap_soft`
(IEEE 1149.1 TAP in fabric). Own XDC `boards/mimas_a7/test_dut.xdc`
(DUT0 balls, directions reversed; LVCMOS33, outputs DRIVE 8 SLEW SLOW, no
pulls; H19 an input without pull), own source list
`hdl/test_dut_sources.mk`, own script `vivado/build_test_dut.tcl`.
`make bitstream` is unchanged. Testbenches `tb_jtag_tap_soft`,
`tb_testdut_uart`, `tb_test_dut_top`.

**Build.** `make bitstream-test-dut` -> `build/vivado-test-dut/test_dut.bit`
(`VIVADO_OUT` overrides; `build_id.txt`, `timing_verdict.txt`, reports
alongside). Build **3ad9d342** (commit 3ad9d34): `TIMING MET: WNS 3.147
ns, WHS 0.042 ns`; 816 LUTs, 755 FFs, 0.5 BRAM. The build id is the
`BUILD_ID` generic (git short hash) and appears in every status line.
Load (lead only): `make jtagload BIT=build/vivado-test-dut/test_dut.bit
FTDI_SERIAL=<Mimas #2's serial>`.

**Pins.** J21 UART TX out, K22 UART RX in, G20 "powered" out (driven 1;
**DIP switch 0 reading 1 drives it 0**, to exercise the supervisor's
sense), J20 TCK / J19 TMS / H20 TDI in, K21 TDO out (driven always, 0 when
not shifting), H19 spare in. The DUT UART TX is mirrored onto Mimas #2's
own USB UART (FTDI channel A, Y21), so it can also be watched there.

**UART.** 2 Mbaud 8N1 (supervisor default, ADR 0005 key 0x0010 /
`DEFAULT_BAUD_INC`; here NCO 0x051EB852 at 100 MHz). Every byte received is
echoed (512-byte FIFO; overflow counted as drop). Once per second, never
interleaved with echo bytes (it waits until the echo FIFO is empty):

    TESTDUT v1 build 3ad9d342 up 00000012 rx 00000005 tx 00001385 rxline 1 lowms 00000000 ferr 00000000 drop 00000000\r\n

115 bytes, decimal 8-digit counters (saturating): up = seconds since
configuration, rx/tx = bytes received/sent (tx counts echo and status
bytes before this line), rxline = level of K22 (the supervisor's TX) at
the start of the line, lowms = ms K22 has been continuously low (0 while
high), ferr = UART framing errors (a line held low counts exactly one),
drop = echo bytes lost.

The supervisor's UART RX keeps working whatever out-policy says:
`supervisor_core` connects `urx(i)` (= the `dutN_uart_from` pins, ungated)
straight to `uart_bridge`'s `uart_rx`; `dut_out_gate` only gates TXD
(and drives it low in the known-off states, 0067), KIO10 and JTAG. So with
out-policy 2 the status lines still arrive at the supervisor.

**JTAG.** IR length 4, Capture-IR 0101. Opcodes: 0001 IDCODE (selected in
Test-Logic-Reset), 0010 USERDR (32-bit read/write: Capture-DR loads the
stored value, Update-DR stores what was shifted in), 1111 BYPASS, every
other opcode (incl. 0000) BYPASS. **IDCODE 0x7E57D001** ("7E57 D001",
version 7, part 0xE57D, manufacturer field 0 = no real JEDEC vendor, LSB 1).
No TRST; the TAP starts in Test-Logic-Reset. TCK/TMS/TDI are 2-flop
synchronised into the 100 MHz clock and TCK edges detected there (rising:
state + TMS/TDI sample; falling: TDO and the Update actions), rather than
clocking the TAP from TCK on a BUFG: J20 is not a clock-capable pin, the
supervisor's TCK is at most 31.25 MHz (half 2) and 10.4 MHz by default
(half 6), and one clock domain keeps the design and its testbench simple.
TDO follows a falling edge after 30-40 ns, and jtag_engine samples TDO
through its own synchroniser at the end of the next high phase. Supported:
**half >= 5 (12.5 MHz) with margin; half 4 (15.6 MHz) passes in simulation
with no margin; half <= 3 fails.** dutctl's default half 6 is fine. The
testbench runs at half 6 and 5 with supervisor-like TDO sampling.

**LEDs.** 0 heartbeat (1 Hz), 1 K22 level, 2 K22 continuously low >= 10
ms, 3 byte received, 4 byte sent, 5 TCK activity (3-5 stretched ~50 ms),
6 TAP not in Test-Logic-Reset, 7 G20 "powered" level.
**7-segment:** `tdut` normally; `r Lo` while K22 has been low >= 10 ms;
digit 1's decimal point blinks with the heartbeat, digit 4's shows H19.

**Hardware test plan (lead).** Supervisor on its known-good bitstream,
Mimas #2 on its own DC jack and USB, jumpers P12 rows 3-7 straight (two
strips, A->A, B->B), MEGA65 harness off DUT0.

1. Load: `make jtagload BIT=build/vivado-test-dut/test_dut.bit
   FTDI_SERIAL=<#2>` (never the supervisor's serial). #2 shows `tdut`,
   LED 0 blinks, LED 7 on, LED 1 on (supervisor TX idles high: DUT0 is
   sensed powered via G20).
2. UART: `dutctl uart 203.28.176.86` -> one status line per second with
   `build 3ad9d342`, `rxline 1 lowms 00000000`, `up` counting. Type
   characters: they are echoed, the next line's `rx` grows by the count,
   LEDs 3/4 flash. `drop 00000000`, `ferr 00000000`.
3. Sense: (optional) DIP 0 on #2 -> G20 low, LED 7 off; the supervisor
   reports DUT0 unpowered and (policy 0) tri-states TX, so K22 floats
   (rxline undefined) and JTAG answers unpowered. DIP 0 back off.
4. JTAG IDCODE: `dutctl jtag-idcode 203.28.176.86 0` -> 0x7E57D001
   (LED 5 flashes, LED 6 on while the TAP is out of reset).
5. Speed: `dutctl jtag-speed 203.28.176.86 0` -> expect f_max around half
   4-5 (12.5-15.6 MHz); do not `--save` anything below half 5.
6. XVC scan: `dutctl xvc 203.28.176.86 0` then e.g.
   `openFPGALoader -c xvc-client --port 2542 --detect` (IDCODE 0x7E57D001,
   IR length 4; unknown device is expected), or urjtag/openocd over XVC
   (`jtag newtap testdut tap -irlen 4 -expected-id 0x7e57d001`): IR scan
   reads 0101; with IR 0010, a 32-bit DR scan of 0xA5C30F12 followed by a
   second scan returns 0xA5C30F12; with IR 1111 the DR is 1 bit (data
   delayed by one bit, first bit 0).
7. 0067 (TX low when known off): `dutctl mgmt 203.28.176.86 0x0060 02`
   -> #2: LED 1 off, after 10 ms LED 2 on and `r Lo`; the status lines
   (still received by the supervisor) show `rxline 0`, `lowms` growing by
   ~1000 per line, `ferr` +1; `jtag-idcode` answers unpowered.
   `dutctl mgmt 203.28.176.86 0x0060 00` -> `rxline 1 lowms 00000000`,
   `tdut`, ferr stays at its new value, echo works again.
