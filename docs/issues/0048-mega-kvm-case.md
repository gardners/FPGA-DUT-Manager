# 0048: Laser-cut case for the MEGA-KVM

Status: Open (design; questions to owner 2026-11-27)
Opened: 2026-11-27 (owner request)

* Laser-cut from **3 mm MDF** for prototyping and **3 mm acrylic** for the
  final version, with engraved "MEGA-KVM" markings and connector labels.
* Holds the Mimas boards with their shields (0045) and the power board
  (0047). Above them, a **mezzanine shelf** for a cheap gigabit switch, with
  a cut-out to pass the Ethernet patch leads through, so the internal links
  are hidden.
* **DUT face:** HDMI in/out, JTAG and keyboard connectors flush on one side
  (0045 lines them up).
* **Opposite face:** the physical keyboard connector(s), the power inputs
  (0047, possibly a vertical PCB), and a bulkhead / back-to-back RJ45 to
  patch the switch to the outside.
* LEDs and possibly an I2C LCD panel on one side (on the shields' I2C bus).
* Output: parametric source (e.g. OpenSCAD or a Python generator) producing
  DXF/SVG per panel, with tab-and-slot or finger joints; kerf as a parameter.

## 2026-11-27 owner answers

* Footprint like the MEGA65 itself, **no wider than a 19-inch rack**, ideally
  **1RU (44.45 mm) tall**. Four Mimas boards side by side (HDMI edges at
  the back, 4 x 90 mm) plus a **Netgear GS105** on the same level.
* **Rear:** power inputs, all HDMI and other DUT (MEGA65) connectors, the
  Ethernet bulkhead, and if there's room a recess where unused DC barrel
  leads can be tucked away.
* **Front (the Mimas RJ45 side):** physical keyboard connector, LEDs (per
  DUT: red = powered, green = selected) and a 16x2 I2C LCD (a 40x2 is fine
  if similar in price; 32x2 is not a common size).
* **Thermal:** about 10-15 W continuous (4 Mimas + switch + eFuses), so plan
  for vents and probably a 40 mm 12 V fan.
* Files: Inkscape-compatible SVG, **pure red hairlines = cut, black =
  etch/engrave**. MDF test sheet 600 x 900 mm; acrylic in smaller sections.

## 2026-11-27 owner decisions (round 3)

Two Mimas boards (with shields, possibly wider than 90 mm), the GS105 on
the same level, the power board, quiet 40 mm fans with space for them. Per
DUT LEDs for 8 DUTs.

## 2026-11-27 owner decisions (round 4)

* **Rear panel:** power inputs, the Ethernet bulkhead, and all HDMI and
  other DUT connectors. The physical keyboard connector goes to the rear
  as well (lead assumption, since the front now holds only the panel
  items below).
* **Front panel:** the LCD, the LEDs, a few momentary buttons (input
  selection; mode: scan / fixed / PIP), and a master on/off rocker switch
  with backlight. Front-panel PCB: issue 0050.

## 2026-11-27 owner (round 5)

* The master rocker switches **everything** off, including the Mimas boards,
  the network switch and the fans (power board 0047 already does this: the
  rocker gates the LTC4417 enable for all inputs).
* Start the case now, **assuming 1RU**. The SVG generation is parameterised,
  with sub-SVGs per Mimas bay and for the front panel (markings, holes,
  cut-outs), composed into full sheets.
* **Option B (owner deciding within a day or two):** gut a used 1RU rack
  switch (e.g. Cisco Catalyst 3560G-48TS, about $35) and reuse its metal
  carcass. **All connectors on the front except power.** Make:
  * a custom front panel (laser-cut, replacing the switch's front);
  * a rear power-input panel;
  * a mounting plate: a bare PCB (or a laser-cut plate) with holes matching the
    carcass floor's existing standoffs and the Mimas/power/GS105 holes,
    covering only as much as needed.
  The parametric generator should support both: the stand-alone laser-cut
  case (A) and the carcass panels and plate (B).
