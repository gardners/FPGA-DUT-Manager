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

## 2026-11-27 owner: scope grows to a full "link board" (shield)

The PCB becomes a shield on the Mimas, covering more than the second
HDMI input:

* the second HDMI input (FPGA-served EDID);
* labelled MEGA65 keyboard (J5-style 2x5) and JTAG/UART (JB1-style 2x6)
  headers for **both** DUTs (P12 = DUT0, P13 = DUT1);
* the labelled physical keyboard header, coming out on the **opposite** side
  (the Ethernet side);
* the link to the neighbouring board (ADR 0007 to be rewritten);
* a 24-bit I2C IO expander, read by the FPGA:
  * 8 bits board/link revision;
  * 8 bits feature presence (b0 second HDMI capture, b1 power relays, ...);
  * 8 relay control outputs to a header (GND + 8 lines, with pull-downs);
* an I2C header on the same bus (for the LCD, the power board, ...);
* 3 mm mounting holes on the Mimas holes; cut-outs so that the RJ45, USB-B,
  power switch and DC jack stay reachable.
* All DUT-facing connectors (HDMI, JTAG, keyboard) flush with the Mimas's
  HDMI side, so a box can have one connector face.

Pin rule (owner): keep the current assignments and route the new
functions to the unused pins. Repack the pins when the PCB exists, using the
revision byte to tell the FPGA which layout it is on.
KiCad project with schematic and connector placement (lead plus agent).
Open questions: see the lead's message of 2026-11-27 (geometry, link
content, power through the header).

## 2026-11-27 Mimas A7 V3 facts (Numato drawing + V3.1 schematic)

Sources: https://numato.com/wp-content/uploads/2018/06/MimasA7V3.0-pd.png
(mechanical), https://numato.com/wp-content/uploads/2018/06/MimasA7_V3.1_Sch.pdf
(sheet 13 power), https://numato.com/docs/mimas-artix-7-fpga-development-board-with-ddr-sdram-and-gigabit-ethernet/

* Board **120 x 90 mm**, 4 x 3.2 mm holes about 5 mm in from the
  corners (exact offsets on the drawing: 9.14/5.14 mm on the P12/RJ45
  corner, 5.00/5.00 on the HDMI corners).
* **P12 runs along one 120 mm edge and P13 along the other**, row 1 (VIN) at
  the RJ45 end, row 40 at the HDMI end; 101.6 mm between rows 1 and 40.
* Short edge 1 (left): RJ45 (J5), USB-B (J3), power switch S12, P2 power-select
  header, DC jack J1. Short edge 2 (right): HDMI IN (P4), HDMI OUT (P6),
  mini-DP OUT (P11), mini-DP IN (P9).
* **Power path:** J1 -> D2 (SS24 Schottky) -> **VIN** = header rows 1-2 ->
  P2 (EXT) -> S12 switch -> L12 -> F2 polyfuse 1812L260 (2.6 A) -> VCC12V0 ->
  regulators (TPS53319 3.3 V, TPS54325 1.0 V and VADJ 3.3 V with a 3 A
  fuse). So feeding 12 V into header VIN is safe: it still passes P2, the
  power switch and the polyfuse, and D2 stops it back-feeding the DC jack.
  Numato specifies 5-12 V in. There is no overvoltage protection, so
  the feed must come from the regulated/eFused 12 V of 0047.

## 2026-11-27 owner answers

* **A third DUT per board:** a third HDMI IN, a TE0790/JB1 JTAG+UART header
  and a keyboard header on the shield. Pin budget (lead): 55 header
  signals free; second HDMI 8 + EDID 4, I2C 2, physical keyboard JTAG 5,
  neighbour UARTs 4, third DUT (HDMI 8 + EDID 4 + JTAG/UART 7 + keyboard 4)
  = 46, so about 9 spare. The third receiver's clock goes on the P12
  GPIO_7 SRCC pair (L19/L20), so the keyboard JTAG moves off it. **Gate
  before fab:** a Vivado build with all three receivers on the planned pins
  must place (one PLL each; 3 PLLs are free) and meet timing.
* **Relay header:** 1x11 single row with one pin removed for keying.
* **Shields:** the owner first proposed staggered shields (one straddling
  P13 of board n and P12 of board n+1), then preferred **non-staggered**
  (one shield per board, width stays ~90 mm per board), with bulk data and
  enumeration over Ethernet and only a **neighbour-to-neighbour UART**
  between adjacent shields. The Ethernet switch stays.
* Power the Mimas through header VIN from the power board (see above), so
  the DC jack isn't needed in the box.
