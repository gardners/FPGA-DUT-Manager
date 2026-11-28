# 0068: Second Mimas A7 as a test DUT on the supervisor's DUT0 port

Status: in progress (owner, 2026-11-28). Related: 0044 (cross-board KVM:
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
| 6 | B | G20 VIO sense (in, pulldown) | G20 "powered" (out, high via ~1k... see below) |
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
