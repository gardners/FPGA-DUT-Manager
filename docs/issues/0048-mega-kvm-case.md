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
