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

## 2026-11-27 owner answers

* **eFuses do the switching** (no relays).
* **One input at a time,** but not by jumper: either a switch on the input
  side, or automatic priority. Lead proposal: LTC4417 (3 inputs = banana,
  PCIe 8-pin, Molex; prioritised PowerPath with external PFETs, up to 36 V),
  with a fuse per input sized for that input.
* Extra 12 V barrel output for the **Netgear GS105** switch. The Mimas boards
  are fed through header VIN on the shields (0045 facts) instead of their
  DC jacks.
* Outputs to DUTs: with 3 DUTs per board, 4 boards = 12 DUTs. See the
  question on control (1x11 parallel header vs I2C).

## 2026-11-27 owner decisions (round 3)

* 2 Mimas per unit, so **8 switched DUT outputs** (matches the 8 control
  lines on the shield's 1x11 keyed header). **5 A eFuse per DUT** (e.g.
  TPS25947, 5.5 A max; current limit set by resistor).
* **Always-on outputs** (no switching): 2 x Mimas (12 V into the shields'
  power connector -> header VIN), the GS105 switch (12 V barrel), and the
  fans. Shared eFuse, about 5 A.
* Input selection: LTC4417 automatic priority, banana > PCIe 8-pin > Molex;
  fuse and TVS per input.
* Quiet fans only (e.g. Noctua NF-A4x10 12 V class, 10 mm thick, fits 1RU).

## 2026-11-27 owner decisions (round 4)

* **Master on/off:** a backlit rocker on the front panel. It switches a
  control signal, not the 20 A (e.g. disables all LTC4417 inputs, or an
  enable to a main high-side switch), so a small cheap rocker will do. The
  backlight runs from 12 V when on.
* **Fabrication:** JLCPCB PCB and assembly. Prefer LCSC/JLC basic parts,
  then extended parts. Note the LCSC number per BOM line; flag anything
  JLC can't source (hand-solder or consigned).

## 2026-11-27 progress (agent, branch feature/power-board)

* KiCad 10 projects under `hardware/mega-kvm-power/`: **main** (170 x 80
  mm: 8 x TPS259470L 5 A switched outputs + TPS259470A 5 A always-on group
  for 2 Mimas, GS105 and 2 fans) and **inputs** (150 x 40 mm vertical
  rear-panel board: banana 25 A > PCIe 8-pin 15 A > Molex 4-pin 10 A, blade
  fuse + SMCJ15A per input, LTC4417 + 8 x BSC030P03NS3G, input-selected
  LEDs). Interconnect: VBUS/GND M4 lugs, 12 AWG.
* Round-4 items: the master rocker (front panel, 3-wire JST XH to the input
  board) switches LTC4417 EN from a diode-OR of the inputs. Lamp from 12 V
  when on. Off or unplugged turns everything off, including the always-on
  group. JLC/LCSC numbers are in the BOM. LTC4417 is short at LCSC
  (consign/hand-fit); bananas, fuse holders and high-current headers are
  hand-fit.
* Generated from Python (`tools/build_all.sh`). ERC 0/0 on both. DRC with
  schematic parity: 0 violations on both; only the unrouted connections
  remain (polygons sketched, routing not started).
* Proposed 1x11 order: 1 GND, 2 key (no pin), 3-10 CTRL0-7, 11 PRESENT
  (3.3 V via 10 k when the power board is powered). Details, ratings, BOM and
  open questions in `docs/hardware/power-board.md`.
