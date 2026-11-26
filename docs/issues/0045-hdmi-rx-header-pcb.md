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

## 2026-11-27 owner decisions (round 3)

* **Two Mimas boards per unit**, one non-staggered shield each. Aim for
  **4 DUTs per board** (8 per unit); 3 is acceptable.
* The DUT keyboard connectors carry no keyboard JTAG (KIO8/9/10, GND and
  3.3 V sense only), to save space and pins.
* Neighbour link: just a UART (TX/RX/GND), on a 3-pin Dupont header. Or, if
  the shield is wider than 90 mm anyway, a right-angle connector between
  adjacent shields that also passes 12 V through.
* The shield may be wider than 90 mm if the rear connectors need it.
* Lead plan for 4 DUTs (pins are tight): move slow signals to a second
  I2C expander: HDMI HPD out and +5V sense, DUT VIO sense and keyboard
  3.3 V sense (the tri-state gating then reacts within about 1 ms, which the
  series resistors make harmless). Budget: I2C 2 + keyboard JTAG 4-5 + UART
  2 + DUT1 HDMI/DDC 10 + DUT2 19 + DUT3 19 = 56-57 of 55 + 4 freed sense
  pins, so about 2-3 spare. Three header receivers need 3 clock-capable
  pairs (P13 C18/C19 and D17/C17, P12 L19/L20) and all 3 free PLLs, but only
  one CMT per bank: so the receivers must be BUFG-clocked (not
  BUFIO/BUFR), or move an MMCM. **The gate build (issue 0049) decides 3 vs
  4.**

## 2026-11-27 owner decisions (round 4)

* The physical keyboard connector now goes to the **rear** panel too (the
  front has only the LCD, LEDs, buttons and rocker, issue 0050). The shield's
  physical keyboard header can stay at the front edge if a short cable takes
  it to the rear, or move to the rear edge, whichever is cleaner.
* **Fabrication: JLCPCB PCB and assembly.** Prefer LCSC/JLC basic parts,
  then extended parts. Note the LCSC number per BOM line; flag anything JLC
  can't source.

## 2026-11-27 progress: KiCad shield rev A draft (branch feature/shield-pcb)

* `hardware/mega-kvm-shield/`: generated KiCad 10 project (scripts in
  `scripts/`, `make` regenerates and checks). Schematic complete for
  4 DUTs on the v1 pin plan (`shield-pinplan.md`): 3 header HDMI inputs
  (49.9 ohm terminations, TPD4E05U06, PCA9306 DDC, FET HPD, +5V sense),
  4 JB1 + 4 J5 DUT ports with 47 ohm series and VIO/keyboard sense,
  physical keyboard with JTAG, TCA6424A + TCA6416A, keyed 1x11 power
  header, I2C header, neighbour link (UART + 12 V pass-through), 12 V in
  to both headers' VIN. **ERC: 0 violations.**
* Board: outline, cut-out (RJ45/USB/S12/P2/DC jack), 8 holes, sockets on
  the measured Mimas grid, all rear connectors flush, parts clustered,
  GND/3V3 planes, 12 V tracks. Signals not routed. **DRC: 0 errors**
  (silk warnings, unrouted nets). Renders, SVG, schematic PDF and a
  JLCPCB BOM in `out/`. Write-up: `docs/hardware/shield.md`.
* Physical keyboard: stays at the shield's front edge, short ribbon to the
  rear panel (rear edge full).
* **Problem for the owner:** a single row of rear connectors for 4 DUTs
  needs ~280 mm of edge (board 120 x 280 mm); two shields do not fit a
  19-inch rack. Proposed: a vertical rear connector board (2-3 rows of
  connectors, ~110-125 mm per Mimas). See shield.md "Open choices".
* Before fab: verify Mimas dimensions, TCA6424A pin numbers, LCSC numbers.
* ADR 0007 rewritten (links between boards: Ethernet + neighbour UART).

## 2026-11-27 pin plan for the shield (issue 0049 step 1)

`docs/hardware/shield-pinplan.md` (branch `feature/shield-pinplan`) is
the pin plan for the KiCad shield: per-row tables with ball, bank, pair, CC
type, current use, shield use and net name, plus the two expander bit maps.
Changes against the plans above:

* The second receiver is **HDMI1** on P13 rows 10-13/18 (clock C18/C19 row
  11; D0 row 10, D1 row 13, D2 row 18), not rows 8-14 only: row 12
  (D17/C17, the other free MRCC pair) is HDMI2's clock. HDMI2 = P13 rows
  12/19/23/25, HDMI3 = P12 rows 12/13/18/19 (clock L19/L20 SRCC).
* DDC per receiver on FPGA pins (HDMI1 C13/B13, HDMI2 D14/D15, HDMI3
  H13/G13); HPD and +5V sense go to I2C expander B (TCA6416A, 0x20)
  instead of FPGA pins; so do VIO and keyboard 3V3 sense of all four DUTs
  and PK_JTAGEN. Expander A = TCA6424A at 0x22 (revision, features, 8
  power-control outputs).
* The rows 28-30 2x3 socket of the 2026-11-26 decision is superseded (those
  pins now carry DUT2/DUT3 JTAG and the DDC lines).

## 2026-11-27 owner answers (round 5) and lead decisions

* **DUT connectors stay native:** per DUT a JB1-style 2x6 and a J5-style 2x5
  box header with the same layout and pin-1 orientation as on the MEGA65
  board, so plain straight 12- and 10-way IDC cables can be bought.
* Width therefore has to be solved in height (lead decision): a **vertical
  DUT connector board** per Mimas on the panel side, joined to the shield
  by right-angle board-to-board connectors. Rows: JB1 x4, J5 x4, plus the
  header HDMI receptacles (on the vertical board, or on the shield edge if
  the stack-up allows). Target about 90-110 mm per Mimas and <= ~40 mm
  height (1RU).
* **Only the master shield drives the power board** (all 8 outputs, one
  1x11 cable). 1x11 order (shared with 0047): 1 GND, 2 key, 3-10 CTRL0-7
  active high, 11 PRESENT (power board pulls it to 3.3 V through 10 k when
  powered; the shield has a weak pull-down; high = present).
* Shield 12 V input: Molex Mini-Fit Jr 2-pin (matches the power board).

## 2026-11-27 owner (round 6): stacked per-DUT connectors

Each DUT's two connectors sit **one above the other**:
* **JTAG (JB1 2x6) on the shield**, at the panel edge, on the best signal
  paths (shortest routes from the FPGA header pins);
* **keyboard (J5 2x5) on a small sub-board below the shield's overhang**,
  beside the Mimas (the space next to the Mimas under the overhang is
  free), directly below its DUT's JB1. It connects to the shield by a
  vertical board-to-board header (slow signals: KIO8/9/10, GND, 3.3 V sense).
The header HDMI receptacles stay on the shield level; the Mimas's own HDMI
IN/OUT are at Mimas level.
