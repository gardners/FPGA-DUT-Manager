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
