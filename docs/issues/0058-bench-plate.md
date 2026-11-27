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
