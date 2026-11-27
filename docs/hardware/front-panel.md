# MEGA-KVM front-panel board (issue 0050)

Status: draft v0.1 (2026-11-27). The schematic passes ERC (0 messages). The
placed board passes DRC with schematic parity: 0 violations, 0 parity
issues, 132 unconnected pads. The board is **not routed**; GND is poured on
both layers.

KiCad 10 project: `hardware/mega-kvm-front/`

| Path | What |
|---|---|
| `mega-kvm-front.kicad_sch` / `.kicad_pcb` | generated schematic and placed board (140 x 66 mm, two rows, 2 layers, 1.6 mm) |
| `tools/gen_front.py` | schematic generator (`kigen.py`/`sexp.py` copied from the power board) |
| `tools/parts.py` | parts, footprints and LCSC numbers |
| `tools/layout.py` | **all geometry**: board, LCD, LED/button positions, panel cut-out sizes, engraving |
| `tools/pcb_build.py` | builds the board in pcbnew and writes `out/panel-holes.json` |
| `tools/route.py` | optional Freerouting round trip (DSN out, SES in, saved as `tracks.json`) |
| `tools/build_all.sh` | regenerate everything: ERC, DRC, PDF, BOM, CPL, renders, panel file |
| `out/` | `erc.rpt`, `drc.rpt`, schematic PDF, `mega-kvm-front-bom.csv` (JLC), `-cpl.csv`, front/back/3D PNG, front SVG, **`panel-holes.json`** |

As with the power board, the schematic and board are generated. Edit the
Python and run `hardware/mega-kvm-front/tools/build_all.sh`.

## Concept

```
 front of case                                                           inside
   |  panel 3 mm  | 3 mm gap |  board 1.6 | ~3-4 mm |  1602 LCD module  | backpack
   |              |  M3      |  F side -> |  M2.5   |  bezel forward    |
   |              |  spacers |  panel     |  spacers|                   |
   |  <-- LED lens (5.3 mm high, 0.7 mm below the panel front)
   |  <-- button stem (9.5 mm high, 3.5 mm proud of the panel)
   |  <-- LCD bezel: passes through the board window, touches the panel back
```

* The board stands vertically **3.0 mm behind the panel** on M3 spacers,
  with the F (component) side facing the panel. All SMD parts are on the F
  side and are no taller than 1.2 mm (TSSOP). The THT headers sit on the B
  side, pointing into the case.
* **LCD:** a standard 80 x 36 mm 1602 module with its PCF8574 backpack
  (chosen part: **Jaycar QP5521 + XC3706**, see "LCD part" below) is
  screwed to the **back** of the board (4 x M2.5, 75 x 31 mm pattern). Its
  bezel (71.2 x 24.2 mm) passes through a 73 x 26 mm window in the board and
  rests against the back of the panel. Board-to-module spacer =
  bezel height above the module PCB - 4.6 mm (about 3-4 mm for usual
  modules: **measure the module**). The four M2.5 screws run through the
  panel as well, so they also hold the left end of the board.
* **LEDs:** 3 mm THT, seated flush on the board (as JLC fits them). The
  lens top is 5.3 mm above the board, so it sits inside a 3.2 mm panel
  hole, 0.7 mm below the front surface. The 3.8 mm flange stays behind the
  panel. No light pipes are needed.
* **Buttons:** 6 x 6 mm THT tactile switches with a 9.5 mm round stem
  (3.5 mm diameter), 3.5 mm proud of the panel, through 4.5 mm holes. Other
  heights in the same family (LCSC): 8.5 mm C136680, 10 mm C136678, 10.5 mm
  C136677, 12 mm C136675, 13 mm C136674.
* **Master rocker:** in the panel, **not on this board**; the case generator
  places it (KVM: left of the fans). It is cabled to the power input board J5 (JST XH 3-way: supply,
  load/lamp +, lamp -), see `power-board.md`.
* **Two rows, 140 x 66 mm** (2026-11-27; was a 227 x 36 mm strip): it sits
  beside 2 x 120 mm fans on the 3RU KVM front panel (issue 0051). Top row:
  the LCD (80 mm) with the PCA9306, J2 and JP1 beside it, then the button
  expander U2 with its pull-up arrays, J3 along the top edge and J1 at the
  right-hand edge. Bottom row: the 8 LED columns (8 mm pitch), the LED
  expander U1, the 5 buttons (11.5 mm pitch). It no longer fits a 1RU case.

## Connectors (B side)

**J1, to the shield's front-panel header** (1x6, 2.54 mm; a 6-way F-F
Dupont cable, pin n to pin n):

| Pin | Signal |
|---|---|
| 1 | GND |
| 2 | +5V (shield AP63205 buck), LCD only (via JP1) |
| 3 | +3V3, for all logic and LEDs |
| 4 | SDA (3.3 V; 2.2 k pull-ups on the shield) |
| 5 | SCL |
| 6 | /INT: U2 /INT, open drain; shares the shield's 10 k-pulled expander-B INT line |

**J2, LCD backpack** (1x4, standard backpack order; a 4-way F-F Dupont
lead): 1 GND, 2 VCC (= VLCD), 3 SDA, 4 SCL, all on the LCD side of the
PCA9306.

**JP1, VLCD** (1x3 + shunt, hand-fitted): 1-2 = **5 V** (the usual 5 V
backpack/LCD), 2-3 = **3.3 V** (3.3 V LCD). With 3.3 V the PCA9306 is a
plain pass switch (both sides pulled to 3.3 V), which is fine. R21/R22 are
the LCD-side pull-ups (10 k to VLCD). R23/C4 bias VREF2/EN from VLCD, as in
the data sheet.

**J3, EXP** (1x10, **DNP**): 1 GND, 2 +3V3, 3-10 = U2 P1.0-P1.7 (10 k
pull-ups). It can take more buttons or a rotary encoder later without a
new board.

Pin positions (board coordinates, front view; the headers are on the
back, so seen from behind x is mirrored): J1 pin 1 (134.0, 28.35) to pin 6
(134.0, 15.65); J2 pin 1 (82.6, 11.61) to pin 4 (82.6, 3.99); JP1 pin 1
(82.6, 30.74), pin 3 (82.6, 25.66); J3 pin 1 (126.43, 4.5) to pin 10
(103.57, 4.5).

## I2C addresses (shield front-panel bus)

| Address | Device | Where |
|---|---|---|
| 0x20 | TCA6416A (expander B) | shield |
| 0x22 | TCA6424A (expander A) | shield |
| 0x24 | TCA9535 (optional fault expander) | power board (DNP) |
| **0x25** | **TCA9535 U1: LEDs** (A0=1, A1=0, A2=1) | front panel |
| **0x26** | **TCA9535 U2: buttons** (A0=0, A1=1, A2=1) | front panel |
| 0x27 or 0x3F | PCF8574T / PCF8574AT LCD backpack (A0-A2 open = default) | LCD module |

0x21 and 0x23 (the shield expanders' other ADDR settings) stay free. If a
backpack has been strapped to an address between 0x20 and 0x26, restore it
to 0x27.

## Expander bit map

TCA9535 registers: 0/1 input port 0/1, 2/3 output port 0/1 (reset 0xFF),
4/5 polarity, 6/7 configuration (reset 0xFF = all inputs). It has **no
internal pull-ups**. On this board every input has an external pull-up and
every LED pin idles off.

**U1 @0x25, LEDs, active low** (output 0 = LED on). Initialise by writing
output 0xFF/0xFF first, then configuration 0x00/0x00. DUT n is panel label
n+1.

| Bit | Port 0 (red = DUT powered) | Port 1 (green = DUT selected) |
|---|---|---|
| 0 | D1, label "1", DUT0 | D11, label "1", DUT0 |
| 1 | D2, "2", DUT1 | D12, "2", DUT1 |
| 2 | D3, "3", DUT2 | D13, "3", DUT2 |
| 3 | D4, "4", DUT3 | D14, "4", DUT3 |
| 4 | D5, "5", DUT4 | D15, "5", DUT4 |
| 5 | D6, "6", DUT5 | D16, "6", DUT5 |
| 6 | D7, "7", DUT6 | D17, "7", DUT6 |
| 7 | D8, "8", DUT7 | D18, "8", DUT7 |

So `red = ~powered_mask`, `green = ~(1 << selected)`. U1 /INT is not
connected.

LED current: anode on +3V3, cathode through 470 R to the expander, about
2.5 mA each (Vf about 2.0 V); 40 mA with all 16 on. Change R1-R18 for a
different brightness (1 k for about 1.2 mA).

**U2 @0x26, buttons, active low** (input 0 = pressed). Leave it all inputs
(reset state). /INT goes low on any input change and clears when the input
port is read.

| Bit | Port 0 | Port 1 |
|---|---|---|
| 0 | SW1 **PREV** (input select previous) | EXP J3.3 |
| 1 | SW2 **NEXT** (input select next) | EXP J3.4 |
| 2 | SW3 **MODE** (cycle scan / fixed / PIP) | EXP J3.5 |
| 3 | SW4 **SPARE1** ("A") | EXP J3.6 |
| 4 | SW5 **SPARE2** ("B") | EXP J3.7 |
| 5 | unused (10 k pull-up) | EXP J3.8 |
| 6 | unused (10 k pull-up) | EXP J3.9 |
| 7 | unused (10 k pull-up) | EXP J3.10 |

/INT is shared with the shield's expander B. On an interrupt, the host reads
both U2 input ports (and expander B's) and debounces in software, e.g. by
re-reading 20 ms later. There are no RC filters on the buttons.

## Panel geometry (for the case generator)

Machine-readable: **`hardware/mega-kvm-front/out/panel-holes.json`**,
written by `pcb_build.py` from the placed footprints (pad-centre of each
LED/switch), so it always matches the board.

Coordinates are in mm, relative to the **board origin = the board's
top-left corner as seen from the front of the case**: x to the right, y
downwards. The board is 140 x 66 mm. Place the origin in the panel where the
board should sit (the KVM case generator puts its top edge 3 mm below the
panel top, at the right).

**LCD**

| Feature | x | y | w | h | Note |
|---|---|---|---|---|---|
| Panel window | 6.25 | 9.75 | 67.5 | 16.5 | centre (40.0, 18.0); viewing area + 1.25 mm |
| Viewing area | 7.5 | 11.0 | 65.0 | 14.0 | Jaycar QP5521 listing ("screen 65.0 x 14.0") |
| Bezel (behind the panel) | 4.4 | 5.9 | 71.2 | 24.2 | typical 1602A frame |
| Module PCB | 0 | 0 | 80 | 36 | on the back of the board |
| Board window (cut-out) | 3.5 | 5.0 | 73.0 | 26.0 | |

Viewing-area position and bezel size vary between makers. **Check against
the actual module before cutting acrylic.**

**LCD part** (owner round 13, 2026-11-27: no LCD bought yet, use a cheap
Jaycar one):

| Item | Part | From Jaycar's listing / manual | Typical (not stated by Jaycar: MEASURE) |
|---|---|---|---|
| LCD | **Jaycar QP5521** 16x2 white on blue | HD44780-compatible, 5 V, 4.5 mA max without backlight, 16-pin 0.1" SIL header, 4 mounting holes, screen 65.0 x 14.0 mm, same module as the XC4454 LCD shield, "suits XC3706" | outline 80 x 36, holes 75 x 31 (M2.5, 2.5 mm from the edges), bezel 71.2 x 24.2, module PCB + bezel ~10 mm |
| I2C backpack | **Jaycar XC3706** I2C port expander | PCF8574 ("FC-113" board), solders onto the LCD's 16-pin header, contrast pot, backlight jumper, address solder bridges A0-A2, **default 0x27**, 4-pin header **GND VCC SDA SCL**, 50 x 25 x 10 mm | |

The XC3706 header order (GND, VCC, SDA, SCL, from its manual) is the same as
J2 (1 GND, 2 VCC, 3 SDA, 4 SCL): a straight 4-way F-F Dupont lead, no board
change. JP1 stays at 1-2 (5 V): the QP5521 is a 5 V module. Sources: Jaycar
XC3706 manual (via nowraelectronics.com.au/product/catalog/4059), Jaycar
QP5521 listing; jaycar.com.au itself refuses automated fetches, so the
module outline was not read from a Jaycar drawing.

**Holes**

| Ref | x | y | Panel hole | Use |
|---|---|---|---|---|
| H1 | 2.5 | 2.5 | 2.7 (M2.5) | LCD screw: panel, 3 mm spacer, board, LCD spacer, module, nut |
| H2 | 77.5 | 2.5 | 2.7 | same |
| H3 | 2.5 | 33.5 | 2.7 | same |
| H4 | 77.5 | 33.5 | 2.7 | same |
| H5 | 136.5 | 3.5 | 3.2 (M3) | 3 mm spacer, board to panel (top right) |
| H6 | 136.5 | 62.5 | 3.2 | same (bottom right) |
| H7 | 3.5 | 62.5 | 3.2 | same (bottom left) |
| H8 | 82.5 | 62.5 | 3.2 | same (bottom, between the LEDs and the buttons) |

Countersink the panel side if flush heads are wanted.

**LEDs** (panel hole 3.2 mm; red row y = 44.0, green row y = 56.0)

| Label | DUT | x | Red (powered) | Green (selected) |
|---|---|---|---|---|
| 1 | 0 | 12.0 | D1 (12.0, 44.0) | D11 (12.0, 56.0) |
| 2 | 1 | 20.0 | D2 | D12 |
| 3 | 2 | 28.0 | D3 | D13 |
| 4 | 3 | 36.0 | D4 | D14 |
| 5 | 4 | 44.0 | D5 | D15 |
| 6 | 5 | 52.0 | D6 | D16 |
| 7 | 6 | 60.0 | D7 | D17 |
| 8 | 7 | 68.0 | D8 | D18 |

**Buttons** (panel hole 4.5 mm, all at y = 50.0)

| Ref | Function | x | Engraving suggestion |
|---|---|---|---|
| SW1 | PREV | 88.0 | `<` |
| SW2 | NEXT | 99.5 | `>` |
| SW3 | MODE | 111.0 | `MODE` |
| SW4 | SPARE1 | 122.5 | `A` |
| SW5 | SPARE2 | 134.0 | `B` |

**Engraving** (suggested text centres): digits "1".."8" at (LED x, 37.0);
"PWR" at (5.5, 44.0) and "SEL" at (5.5, 56.0); button labels at
(button x, 43.0). The board's silkscreen carries the same digits and
labels for assembly, but it is hidden behind the panel.

**Master rocker** (off-board): placed by the case generator, not in
board coordinates (`rocker` x/y in panel-holes.json are null). On the KVM
front it sits in the strip left of the two 120 mm fans. The cut-out depends
on the part: KCD1-type about 19.2 x 13.0 mm, KCD3-type about 30 x 22 mm.
The 3-wire JST XH lead runs to the power board.

## Parts (JLCPCB assembly)

All parts have an LCSC number (in the `LCSC` field and in
`out/mega-kvm-front-bom.csv`). There are **no exposed-pad or fine-pitch
leadless parts**: the smallest is the PCA9306 VSSOP-8 at 0.5 mm pitch. SMD
parts are all on the F side. THT parts (LEDs, switches, headers) use JLC
THT assembly or are easy to hand-solder.

| Refs | Part | LCSC | JLC |
|---|---|---|---|
| U1, U2 | TI TCA9535PWR, TSSOP-24 | C130204 | extended |
| U3 | TI PCA9306DCUR, VSSOP-8 | C33196 | extended |
| D1-D8 | Everlight 204-10SDRD/S530-A3-L, 3 mm red diffused | C84774 | extended THT |
| D11-D18 | Everlight 204-10SYGD/S530-E3, 3 mm yellow-green diffused | C85161 | extended THT |
| SW1-SW5 | HRO K2-1102DP-L4SW-04, 6x6 THT, 9.5 mm stem | C136679 | extended THT (about 1000 in stock) |
| R1-R18 | 470 R 0603 | C23179 | basic |
| R21, R22 / R23 | 10 k / 200 k 0603 | C25804 / C25811 | basic |
| RN1-RN4 | 4 x 10 k array 0603x4 | C29718 | basic |
| C1-C4, C7 / C5, C6 | 100 n / 10 u 0603 | C14663 / C19702 | basic |
| J1 / J2 / JP1 / J3 | 1x6 / 1x4 / 1x3 / 1x10 (DNP) 2.54 mm headers | C37208 / C124378 / C49257 / C57369 | extended THT |

Not on the BOM: the 1602 LCD module with PCF8574 backpack (Jaycar QP5521 +
XC3706), a 2.54 mm shunt
for JP1, the 6-way and 4-way Dupont leads, 4 x M2.5 screws with spacers, and
4 x M3 x 3 mm spacers with screws.

The CPL (`out/mega-kvm-front-cpl.csv`) is KiCad's position export with JLC
column names. Check rotations in JLC's preview (TSSOP/VSSOP pin 1 and the
array) before ordering.

## Open choices

1. **Routing:** not done. `tools/route.py` exports a Specctra DSN for
   Freerouting and re-imports the session as `tracks.json`. That step
   needs Freerouting to be run by the owner, or the board routed by hand
   in KiCad. It is a simple 2-layer job (about 60 nets, 0.25 mm tracks).
2. **LCD module dimensions:** Jaycar QP5521 + XC3706 chosen (2026-11-27);
   the outline, hole pattern, bezel height (sets the spacer) and the
   viewing-area position must still be measured on the purchased module.
3. **Green LED colour:** C85161 is yellow-green (573 nm). It has a Vf
   matched to the red, so it runs well from 3.3 V. A "pure" InGaN green
   (Vf about 3 V) would be dim from 3.3 V through 470 R.
4. **Button height** follows the 3 mm panel gap. If the case uses a
   different gap or panel thickness, pick another K2-1102DP height (listed
   above) and change `PANEL_GAP` in `layout.py`.
5. **Bicolour option:** one red/green common-cathode 3 mm LED per DUT
   (e.g. C183838) would halve the panel holes. Not used, since the owner
   asked for separate red and green LEDs.
6. **Board size:** 140 x 66 mm (two rows). The KVM front allows up to
   about 144 mm beside 2 x 120 mm fans; the LED pitch (8 mm) and the button
   pitch (11.5 mm) leave room to tighten if needed.
