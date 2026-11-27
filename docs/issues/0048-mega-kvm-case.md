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

## 2026-11-27 owner (round 5b)

* Option B rear panel: the power inputs fit into the 3560's existing
  **IEC inlet cut-out and DC/RPS input cut-out** (custom plate(s) over those
  openings).
* DUT connectors are native JB1 2x6 + J5 2x5 per DUT on a vertical DUT
  connector board per Mimas (0045), so the panel cut-outs are two rows of
  box headers plus the HDMI row, per bay.

## 2026-11-27 progress: parametric case generator (agent, branch feature/case)

* `hardware/mega-kvm-case/`: Python 3 generator (standard library only; `make`
  regenerates `out/`). Write-up, parameters, assembly, laser notes and
  measurement checklist: `docs/hardware/case.md`; numbers:
  `out/fit-report.md`.
* Output: Inkscape SVGs in mm (red 0.01 mm hairline = cut, black = engrave,
  single-stroke font), one per panel, sub-SVGs per Mimas bay, front-panel
  group and rear power block, nested MDF 900 x 600 and acrylic sheets,
  top-view fit drawings (SVG + PNG); option B mounting plate also as DXF and
  a KiCad Edge.Cuts board (KiCad 10 DRC clean).
* Primary DUT face = the rev B shield (189.6 mm per Mimas, J5 on keyboard
  sub-boards, `kbd_drop` parameter 2.5 mm), read from the shield project.
  Alternates in the report: vertical DUT board (110 mm), rev A single row
  (279.6 mm: two do not fit 19 inch), ~150 mm 2x8.
* **Option A** (445 x 272 x 44.45, finger joints, lid on M3 T-slots, GS105 +
  power main board on the Mimas RJ45 side, 2 x NF-A4x10 on the left wall in
  base/lid slots) fits, except that the **input board is 40 mm tall vs 38.45 mm
  inside** (make it <= 36 mm). The rear has 53.8 mm free beside the two bays:
  only the Ethernet bulkhead + 8 DUT power lead holes fit there; the power
  inputs and the keyboard feed-through go on the right side wall near the
  rear. No room for the DC-lead recess.
* **Option B** (3560G-48TS, 444.5 x 409 x 43.9 per Cisco's guide): the front panel
  holds the two bays + bulkhead, but **not the LCD/LED/button/rocker group,
  keyboard and DUT power (238 mm short)**. IEC/RPS cover plates, fan plate
  and mounting plate are generated; all carcass numbers are placeholders
  (checklist in case.md).

## 2026-11-27 owner round 9: rack shelves replace options A and B

The owner is dropping the Cisco carcass for now and the single 1RU box.
New layout: a ~3RU KVM unit with 120 mm quiet fans, plus one sliding
plywood shelf per MEGA65 on old server rails, up to ~11RU in all.
Tracked in **0051**. Options A and B stay in the generator but are no longer
developed. The generator is retargeted to the KVM unit and the shelves.
