# 0045: Small HDMI-capture PCB that plugs straight onto the header

Status: Open (design)
Opened: 2026-11-26 (owner request)

A small board for the second HDMI receiver (0043) that plugs straight onto
the Mimas header and carries everything the receiver needs. Ideally its
HDMI socket faces the **same way as the Mimas's own HDMI connectors**, so
all cables plug in from one side. If the geometry won't allow that, a short
panel-mount (bulkhead) HDMI extension cable from the PCB to the board edge
is acceptable.

## Header footprint

A 2x7 female socket on **P13 rows 8-14**:

| Row | A | B | Use |
|---|---|---|---|
| 8 | GND | GND | ground |
| 9 | VADJ 3.3 V | VADJ 3.3 V | termination and logic supply |
| 10 | F18 | E18 | TMDS D0 (IO_L15) |
| 11 | C18 | C19 | TMDS clock (IO_L13 MRCC) |
| 12 | D17 | C17 | TMDS D1 (IO_L12 MRCC) |
| 13 | B20 | A20 | TMDS D2 (IO_L16) |
| 14 | GND | GND | ground |

(Which P/N goes to which HDMI pin is chosen for routing; the FPGA can invert
lanes. Check the column A/B = P/N assignment against the vendor XDC; ADR 0008
amendment 5 puts odd cable pins on column B.)

Don't extend the socket over row 15 or 16+: row 15 is VADJ, and rows 16-22
carry the DUT1 keyboard harness. The PCB's outline must leave the row 4-7
JTAG/UART strip and the rows 16-20 keyboard strip pluggable.

## What's on the board

* An HDMI type-A receptacle (right-angle, or vertical, depending on the
  facing).
* **Termination:** 8 x 50 ohm to 3.3 V (row 9), placed close to the socket
  pins (TMDS_33 inputs have no internal termination).
* **ESD** on the TMDS lines, low capacitance (e.g. TPD4E05U06 or the IP4776
  family the Mimas uses, if it suits a sink).
* **DDC/EDID with no extra FPGA pins:** a 24C02 EEPROM on the HDMI DDC
  lines, powered from the source's +5 V (HDMI pin 18), with the EDID
  programmed once. It holds the same 256 bytes as `edid_pkg`; dutctl could
  generate the image. Option: also bring SCL/SDA to pads, so a later version
  can serve the EDID from the FPGA through spare pins (level shifter
  needed, since the source pulls DDC to 5 V).
* **HPD:** 1 k from HDMI pin 18 (+5 V) to HPD (pin 19), the standard trick
  for a sink that is always ready. Option: a jumper or FPGA-controlled FET
  for re-plugging later.
* **Layout:** 4 layers, 100 ohm differential pairs, lanes matched within the
  PCB, all as short as possible. Ground stitching around the pairs.
* Optional: an LED on +5 V from the source.

## To find out first

1. **Geometry:** measure the Mimas: where P13 rows 8-14 are relative to the
   HDMI IN/OUT sockets, what is underneath and next to them (the DDR3 and
   any parts on the top side), and the height. Decide the socket facing, or
   fall back to the bulkhead cable.
2. **Electrical:** do the P13 traces have series resistors or stubs? Check
   in the Mimas V3 schematic and layout.
3. **Before the PCB:** a bench prototype (HDMI breakout + resistors on a
   2x7 socket) to check that the FPGA side (0043) locks, then KiCad.

Deliverables: KiCad project under `hardware/hdmi-rx-header/`, a BOM, and an
assembly note in `docs/cabling/`.

## 2026-11-26 owner decision: FPGA serves the EDID, no EEPROM

The FPGA spoofs the EDID (a second `ddc_edid` instance, host-settable
later), for flexibility. The PCB therefore needs 4 more slow FPGA pins:
SCL, SDA, HPD control and +5V sense. The 2x7 on rows 8-14 has none spare,
so:

* **Second small socket: P13 rows 28-30 (2x3)**: 28 A/B and 29 A/B = SCL,
  SDA, HPD, 5V-sense; row 30 GND. These rows are spare (ADR 0008
  amendment 2). One rigid PCB spanning rows 8-30 (~58 mm) must clear the
  DUT1 keyboard jumpers on rows 16-22 (cut-out or enough standoff
  height); otherwise a short 4-wire lead from the PCB to rows 28-30.
* **DDC level shifting:** PCA9306 (or 2 x BSS138). The source side is pulled up
  to the source's +5 V, the FPGA side to 3.3 V (row 9).
* **HPD:** an FPGA-controlled FET pulls HDMI pin 19 up to +5 V through 1 k.
  The FPGA can then re-assert hot-plug after changing the EDID.
* **+5V sense:** divider (e.g. 10 k / 15 k) from HDMI pin 18 to an FPGA
  input: "source connected".
* Keep pads for an optional 24C02 footprint unpopulated (fallback only).
