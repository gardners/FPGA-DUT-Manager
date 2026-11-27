# Bench plate (issue 0058)

Laser-cut 3 mm MDF base plate and lid carrying the QMTECH K325T (core
board on its daughter board), two Mimas A7 supervisors, the Jaycar XC4418
relay module and the Arduino Yun. The lid sits on standoffs above the
boards as a cover against falling conductive bits.

`make` (or `python3 build.py`) regenerates everything in `out/`:

| File | What |
|---|---|
| `out/base.svg`, `out/lid.svg` | owner's one-row layout (**517 mm wide**) |
| `out/base-alt.svg`, `out/lid-alt.svg` | alternative layout, 378.7 mm wide |
| `out/preview.png`, `out/preview-alt.png` | colour previews (not laser files) |
| `out/layout.md` | generated table of every board position and hole |

All numbers that may need changing are in `boards.py` (board geometry) and
at the top of `build.py` (margins, gaps, hole size).

## The owner's layout is wider than 400 mm

**The one-row layout comes out at 517.1 x 238.6 mm, which does not fit the
400 mm rack shelf.** The boards alone span 477 mm (108.7 + 25 + 90 + 25 + 90 +
20 + 50 + 15 + 53.3), so no choice of margins brings it under 400 mm.

**Alternative (`*-alt.svg`): 378.7 x 338.5 mm.** The front row is K325T,
Mimas #1 and Mimas #2 (25 mm gaps, jack fronts aligned). The relay board
(long side along X) and the Arduino sit in a rear row behind the two Mimas,
45 mm behind their HDMI edge (room for the HDMI plugs). The Arduino's RJ45
still faces the front, but **its jack is 165.5 mm behind the others**; that is
the one owner constraint the alternative gives up. The area behind the K325T
(about 110 x 100 mm) is left free, for example for a small switch or PSU.

## Conventions

* SVG in mm (`width="…mm"`, viewBox in mm), so laser software imports it
  1:1. Same conventions as `hardware/mega-kvm-case`: layer **cut** = pure red
  `#ff0000` 0.01 mm hairlines; layer **engrave** = black 0.2 mm lines. Text
  uses that project's single-stroke font (`casegen/font.py`, imported
  unchanged), so it engraves as lines and needs no fonts on the laser PC.
  There is no kerf compensation.
* Drawing = the plate seen from above, standing in front: **front at the
  bottom of the SVG**. All RJ45 jacks point to the front edge.
* Base: cut = outline, 4 corner holes, 3 between-board holes, every board's
  mounting holes. Engrave = board outlines and names, RJ45 bodies with an
  arrow towards the front, a few connector hints (P12/P13/HDMI, VGA, 7SEG,
  UART, USB), a 6 mm standoff ring round each board hole, and "FRONT".
* Lid: cut = outline + the same 4 corner + 3 between holes; engrave =
  "FRONT" and the title, so it goes on the right way round. No vent slots: they
  would let bits fall through.

## Dimensions and choices

| Parameter | Value | Source |
|---|---|---|
| Front margin | 50 mm in front of the jack fronts | owner |
| Rear margin | 50 mm behind the rearmost PCB edge | owner |
| Side margins | 20 mm | chosen (corner hole + standoff clear of the boards) |
| K325T ↔ Mimas #1 ↔ Mimas #2 | 25 mm | owner |
| Mimas #2 ↔ relay board | 20 mm | chosen |
| Relay board ↔ Arduino | 15 mm | chosen |
| Alt: Mimas rear ↔ rear row | 45 mm | chosen (HDMI plugs) |
| Corner holes | 10 mm in from each corner, Ø3.2 | owner (3 mm holes; 3.2 = M3 clearance) |
| Between-board holes | middle of each gap (K325T/M1, M1/M2, M2/relay), at mid-depth; alt: K325T/M1, M1/M2, and between the rows | owner (3 holes) |
| Jack alignment | all jack **fronts** on one line, 50 mm from the plate front | chosen (alignment rule from the owner) |
| Relay board front | in line with the Mimas PCB fronts | chosen |
| Board mounting holes | Ø3.2 | M3 |

### Boards (rotated so the RJ45 faces the front)

| Board | Plate footprint X x Y | Holes (board-local) | RJ45 | Source |
|---|---|---|---|---|
| Numato Mimas A7 (V3) | 90 x 120 (120 x 90 board) | 5 mm in from each corner, Ø3.2 | magjack 16 wide, 13.3–29.3 mm from the P12 (left) edge, 0.5 mm proud of the PCB edge, 22.3 deep | `docs/hardware/shield.md`, `hardware/mega-kvm-shield/scripts/geometry.py` (vendor STEP) |
| QMTECH daughter board (DB_FPGA, VGA/RJ45/7-seg/CP2102), K325T core on top | 108.71 x 134.62 | **ASSUMED**: 4.0 mm in from the long edges; 30.5 mm and 130.8 mm from the RJ45 edge | **ASSUMED**: centre 48 mm from the 7-seg/UART edge (left), 16 wide, 4 mm proud | Size: QMTECH XC7A100T Starter Kit daughter-board manual V01, §1.2 ([GitHub](https://github.com/ChinaQMTECH/QM_XC7A100T_STARTER_KIT)); holes and jack scaled from its top-view photo (Figure 1-1, ±1.5 mm). QMTECH publish no mechanical drawing ([DB_FPGA](https://github.com/ChinaQMTECH/DB_FPGA) has only the schematic) |
| Arduino Yun (Rev 2) | 53.34 x 68.58 (+4.4 jack) | **ASSUMED** Uno R3 pattern: (13.97, 2.54), (15.24, 50.8), (66.04, 7.62), (66.04, 35.56) from the USB edge / bottom edge | **ASSUMED** where the Uno's USB-B is (centre 38 mm from the bottom edge, so on the left when facing front), 4.4 mm proud | 73 x 53 mm overall from the [Arduino store](https://store-usa.arduino.cc/products/arduino-yun-rev-2) listing (via search snippets; the page rate-limits fetches) and [Tinkersphere](https://tinkersphere.com/shields/2565-esp8266-wifi-shield.html); Uno-shield PCB 68.58 x 53.34, so the jack overhang is 73 − 68.58. No official Yun hole drawing found |
| Jaycar XC4418 relay module | 50 x 135 (main), 135 x 50 (alt) | **ASSUMED** 3 mm in from each corner, Ø3 (cut 3.2) | none | 135 x 50 x 19 mm: [Jaycar datasheet](https://media.jaycar.com.au/product/resources/XC4418_datasheetMain_67843.pdf) |

The K325T core board (84.1 x 67.1 mm, QMTECH XC7K325T core-board manual
§2) plugs into the daughter board, so only the daughter board's footprint
matters for the plate.

**Before cutting:** measure the ASSUMED hole positions on the real
daughter board, Arduino and relay module (calipers, hole centre to the PCB
edges) and update `boards.py`, then `make`. A test cut of only the
engrave layer on paper or card, laid under the boards, is a cheap check.

## Plate size and sheet

* Main: 517.1 x 238.6 mm; alternative: 378.7 x 338.5 mm. Two of each
  (base + lid).
* Both fit a 600 x 900 mm sheet (the size used for the case project's ply):
  even two main plates side by side (517 x 477) or two alternative plates
  (379 x 677). MDF sheet size is unknown; check it against these numbers.
