# 0047: Our own power distribution / relay board

Status: Open (design; questions to owner 2026-11-27)
Opened: 2026-11-27 (owner request)

Replaces the Jaycar XC4418 8-relay module (ADR 0009) with a board designed
for the MEGA-KVM box.

## Requirements (owner)

* **12 V DC in, 20 A or more**, from several input types, each fused for what
  it can deliver:
  * Molex 4-pin "5.25-inch floppy" power (8981): 12 V pin, about 10 A fuse;
  * PCIe/GPU 8-pin from a modern PSU: three 12 V pins, 150 W, so about 12.5 A
    and a 15 A fuse;
  * banana sockets (4 mm), 20-25 A fuse.
  The inputs may sit on a separate vertical PCB so that they are reachable
  from the side of the box.
* **8 switched outputs** on screw or clip terminals, each through a **3 A
  eFuse**.
* **4 DC outputs for the Mimas boards**, sharing one **5 A eFuse**. Or feed
  the Mimas boards through P12/P13 if that is safe: then 0045 gets a power
  header.
* Controlled by the shield's relay header (0045): 3.3 V logic. Level
  conversion to whatever switches the relays. Active high or low, as
  designed; the lead proposes active high with pull-downs, so that
  everything is off when the controller is unpowered or reset.

## Design notes (lead)

* **Several inputs at once** need ideal-diode OR-ing (e.g. LM5050/LTC4359
  plus MOSFETs per input). Otherwise two PSUs feed each other. The cheaper
  alternative is "one input at a time" by jumper.
* **The eFuse can do the switching.** A TPS25947-class part (2.7-23 V,
  ~5 A, adjustable current limit, EN pin works with 3.3 V logic, soft
  start, fault output) per channel replaces relay + driver + level shifter.
  It is silent and limits inrush into the DUTs' input capacitors. Downside:
  no galvanic isolation and µA leakage when off. Owner to choose:
  mechanical relays + eFuse, or eFuse only.
* Busbars/thick copour (2 oz), and 20 A means wide polygons, input
  connectors rated for it, and terminals rated for 3 A per output.
* Optional: an I2C expander or INA-class current monitor per channel on the
  shield's I2C bus (heartbeat could report DUT current).
