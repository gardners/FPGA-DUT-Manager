# 0058: Laser-cut bench plate for the K325T, two Mimas, relay board and Arduino

Status: open (owner request 2026-11-27). Related: 0057 (K325T bring-up),
0051 (rack).

## Request (owner, 2026-11-27)

An SVG laser-cut file for a 3 mm MDF plate carrying:

* the QMTECH K325T core board on its daughter board,
* two Mimas A7 boards,
* an Arduino Yun (R3),
* a Jaycar XC4418 8-channel relay module.

Layout:

* The K325T board and the first Mimas 25 mm apart; the second Mimas to the
  left of the first, also 25 mm apart.
* All Ethernet jacks face the same direction, at the same Y position.
* The relay board and the Arduino go to the left of the second Mimas. The
  relay board is turned to take the least X space, with the Arduino beside
  it.
* If the plate comes out wider than 400 mm, tell the owner: it is meant to
  sit on a rack shelf.
* 3 mm mounting holes 10 mm in from each corner of the plate, plus 3 more
  between the boards.
* The plate extends 50 mm in front of and behind the PCBs.

The owner will cut two: one as the base, one on top as a cover against
falling conductive bits. At first it lives under a MEGA65.

## Progress

### 2026-11-27: generator and first SVGs (branch feature/bench-plate)

`hardware/bench-plate/` (`make` = `python3 build.py`) writes `out/base.svg`,
`out/lid.svg`, the `-alt` pair, preview PNGs and `out/layout.md` (every
board position and hole). Cut = red 0.01 mm hairlines, engrave = black
(board outlines, names, RJ45 bodies with arrows to the front), units mm.
All jack fronts on one line 50 mm behind the plate front; holes Ø3.2
(M3 clearance for the owner's "3 mm").

* **The owner's one-row layout is 517.1 x 238.6 mm: over the 400 mm
  limit.** The boards alone span 477 mm with the requested 25 mm gaps
  (relay gap 20, Arduino gap 15, side margins 20 chosen here).
* Alternative (`base-alt.svg`/`lid-alt.svg`), **378.7 x 338.5 mm**: K325T,
  Mimas #1, Mimas #2 in the front row (jacks aligned); relay board (long
  side along X) and Arduino in a rear row behind the two Mimas, 45 mm
  behind their HDMI edge. The Arduino's RJ45 still faces the front but is
  165.5 mm further back: the one constraint it relaxes.
* Sizes: Mimas from the vendor STEP (shield docs); QMTECH daughter board
  108.71 x 134.62 mm (QMTECH XC7A100T starter-kit daughter-board manual);
  Yun 73 x 53 mm; XC4418 135 x 50 mm (Jaycar datasheet). **ASSUMED** (no
  vendor drawing found): daughter-board holes and RJ45 position (scaled from
  the manual's photo), Yun holes (Uno R3 pattern) and RJ45 position, relay
  holes (3 mm in from the corners). Measure these before cutting; they all
  live in `hardware/bench-plate/boards.py`.
* Open for the owner: which layout; MDF sheet size (both fit 600 x 900).
