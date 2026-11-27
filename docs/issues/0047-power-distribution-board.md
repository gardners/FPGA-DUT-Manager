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

## 2026-11-27 owner answers (round 5) and lead decisions

* One control cable, from the master shield, for all 8 outputs. 1x11
  order as proposed, PRESENT high = present.
* DUT outputs: **screw terminals with a + and a - per output**, for leads
  ending in barrel plugs.
* **No hand-fitting the LTC4417.** The chosen LTC4417CGN is the leaded
  SSOP-24 (GN) package with no exposed pad (check against the datasheet). JLC
  can fit it if it is bought through their global-sourcing/parts
  pre-order. Also design a fallback that JLC stocks: three ideal-diode
  controllers (e.g. TI LM74700-Q1 or LM5050-1 with back-to-back FETs) whose
  EN pins come from simple priority logic (comparators/logic gates:
  a valid higher-priority input disables the lower ones), plus the rocker
  as a global disable.
* Inrush on master-on: add soft start (gate RC) to the input FETs.
* Current limit 5 A (owner).
* Mimas feed connector: Mini-Fit Jr 2-pin (shield side matches).

## 2026-11-27 progress: round 5 applied (agent, feature/power-board)

* DUT outputs are now 2-pole 5.08 mm screw terminals (+/-) per DUT.
  Mini-Fit Jr 2-pin for the Mimas feeds. 1x11 order as adopted. 5 A
  limits kept.
* Default input board: still the **LTC4417CGN** (leaded SSOP-24, no exposed
  pad; ordered through JLC global sourcing / pre-order, no hand-fitting).
  Soft start added: 22 nF + 1 k Miller RC from each gate to VBUS (set on the
  bench). docs/hardware/power-board.md explains that the LTC4417 is a gate
  controller: the current is set by the 3 mOhm FETs. It includes the I2R
  table at 20/25 A, the SOA note and "why not 3 eFuses".
* JLC-stocked fallback, `mega-kvm-power-inputs-lm74700` (schematic, ERC
  clean): 3 x LM74700-Q1 + BSC014N04LS ideal diodes, P-FET switches,
  LM339/TL431 priority logic (ON1 = rocker & V1, ON2 = rocker & V2 & !V1,
  ON3 = rocker & V3 & !V1 & !V2), Miller soft start, all leaded parts.
* ERC 0/0 on all three schematics; DRC 0 violations on both boards
  (unrouted connections only).

## 2026-11-27 progress: input board fits 1RU (agent)

* The case fit check showed the 150 x 40 mm input board hitting the lid (the
  interior is 38.45 mm). The input board is now **197 x 34 mm**, laid out in
  columns: connectors | fuses | TVS/OR | dividers | FETs + LTC4417 | soft
  start | lugs. DRC 0 violations (unrouted only); ERC clean on all three
  schematics. The LM74700 fallback uses the same outline.
* Narrow variant (48 x 34 mm, connectors only, with the selection electronics on the
  main board), for a rear position beside the DUT bays: written up as a concept in
  power-board.md. Not drawn unless the owner wants it.

## 2026-11-27 owner round 9: relays instead of FETs? front inputs, fans

**Owner:** the priority selector and its 20 A MOSFETs will dissipate several
watts at peak just by being on. Would 25 A relays be lower power and avoid a
hot spot in one corner? Power inputs must be on the front or rear panel
(leaning front, 0051). Fan headers with small protection, up to 8 fans
(0052).

**Lead's analysis: relays are worse at every realistic load.**

| Load | Banana path, 4 FETs (2 per side, ~5.6 mOhm hot) | 25-30 A automotive relay |
|---|---|---|
| ~12 A (8 MEGA65 at ~1 A + Mimas, GS105, fans; to be measured) | 6 A per FET: **~0.2 W each, ~0.8 W total**, spread over 4 parts | coil **1.4-1.8 W** continuously (85-100 Ohm at 12 V) + contacts and tabs ~4-6 mOhm: ~0.7 W: **~2.2 W** in one part |
| 20 A (design point) | ~0.56 W each, ~2.2 W total | coil 1.6 W + ~2 W contacts: **~3.5 W** |

A relay also brings:

* a DC arc on every break at 20 A, which wears the contacts and makes them
  hot;
* a dead gap at every input changeover, which resets all the boards (the FETs
  switch over in microseconds);
* a coil driver and a flyback diode per relay;
* no reverse-current blocking.

Latching relays remove the coil power but keep the arc and the gap, and need
a pulse driver.

**Decision (lead, pending owner veto): keep the LTC4417 + FETs.** The "hot
spot" is about +10 K at a realistic 12 A and +35-60 K at a full 20 A. To
spread it:

* place the FET pairs apart on 2 oz pours;
* add the optional third parallel pair on the banana path (pads only, fitted
  if the bench shows it is needed);
* keep the input board on stand-offs with an air gap, in the fan's airflow
  (0051).

Front panel: the 197 x 34 mm input board mounts on the 3RU front beside the
display group (0051). Fans: 8 x 4-pin PWM headers replace J23/J24, with an
I2C fan controller and a temperature sensor on J5 (0052).

## 2026-11-27 progress: round 9 applied, input board for the 3RU front (agent, feature/power-fans)

* Banana path: pads for a **third parallel FET pair (Q12/Q13, DNP)**. Each
  back-to-back pair is now its own column, 14 mm apart, with Vn / VSn / VBUS
  pours sketched (input drain on Vn, sources on VSn, output drain on VBUS).
* The input board moves behind the **3RU front panel** (0051). Height is no
  longer short there, but panel width is (2 x 120 mm fans take ~250 of the
  ~425 mm opening), so the 197 x 34 mm 1RU strip became a **126 x 64 mm
  two-tier board** (connectors/fuses/TVS on top, lugs/LTC4417/FETs below);
  connectors still face out on the F side. Note for the case work: the
  227 mm front-panel PCB does not fit beside two 120 mm fans either.
* TMP75 (0x49) on the VS1 copper, cabled to the main board (0052).
* Fans, fan control and per-header protection: see 0052. ERC/DRC clean.

## 2026-11-27 owner round 12: one board, inputs on the main PCB

**Owner:** "now that the main KVM thing is an open-top 3RU, we can just have
the power connectors on the power distribution PCB and keep life simple for
that."

Decision: **drop the separate input board.** The three inputs (banana,
PCIe 8-pin, Molex 4-pin), their fuses, the LTC4417 selector with its FET
pairs and the input-FET temperature sensor all move onto the power main
board. The plugs are reached from the open top of the KVM unit. The main
board sits at the front of the KVM deck, with the input connectors along its
front edge, so they are easy to pull when the drawer is out. No power
connectors pass through the front panel any more. The rocker stays on the
front panel, wired to the board. The input-board and LM74700 projects stay
in the tree as legacy and are no longer developed.

## 2026-11-27 progress: round 12 applied, one board (agent, feature/power-oneboard)

* The input stage is on the power board (`mega-kvm-power-main`, v0.4,
  generator `tools/input_stage.py`): banana pair, PCIe 8-pin, Molex 4-pin,
  ATO fuses, TVS, LTC4417CGN with the back-to-back FET columns (banana third
  pair Q512/Q513 DNP; columns 11-14 mm apart on their Vn/VSn pours, output
  drains straight into the VBUS pour), soft start, input-selected LEDs and the
  rocker connector J54. VBUS lugs J1/J2 are gone.
* **Outline 230 x 138.5 mm** (was 230 x 80): a 58.5 mm input strip added at
  the front. Front-edge connectors, x from the left edge: banana J50 8.0 /
  J51 27.05 (centres 7.5 mm from the edge); PCIe J52 35.3-54.4; Molex J53
  57.3-80.0; rocker J54 (XH-3) 83-94. All vertical, plugged from the open
  top; no front-panel cut-outs.
* One TMP75 (0x48) between the banana FETs and the PCIe pair is enough on
  one board (the FETs are the only multi-watt source); the 0x49 sensor and
  the J6/J8 cable are dropped.
* Banana sockets are now PCB-mount 24 A parts (24.243.1/.2, C7437321/2):
  24 A covers the 20 A design point but not the 25 A fuse; footprint to be
  checked against the part.
* The input-board projects stay as legacy: `build_all.sh` builds only the one
  board (`LEGACY=1` rebuilds the old ones); their stale outputs were removed.
* ERC 0, DRC 0 with schematic parity (unrouted only); BOM/CPL regenerated.

## 2026-11-27 owner round 13 (logged before implementation)

**Owner:**

1. Check U50's LTC4417 symbol/footprint pin map (pin numbers, names, GN-24
   SSOP) and the application circuit (gate drive, VALID, OV/UV dividers,
   CAS, hysteresis) against the datasheet (`docs/datasheets/ltc4417.pdf`,
   git-ignored). Fix anything wrong and list each discrepancy.
2. **Fuse: 25 A** with the 24 A PCB-mount banana sockets is accepted (not a
   commercial product; 1 A over is within tolerance). Default F1 = 25 A.
3. If useful, check the Mimas A7 dimensions used in the repo against the
   vendor STEP (`docs/datasheets/MimasA7_3D_1.step`).
4. Current sensing on the 8 switched DUT rails: investigate and estimate
   only, **do not add it to the board yet**. Does the TPS259470 ILM pin work
   as an analog current monitor, with what gain/accuracy, and what are the
   rules for loading/filtering it? Compare one 8-channel I2C ADC on the
   ILM pins against a shunt + INA226/INA219-class monitor per rail (LCSC
   numbers, stock, price, area, accuracy at 0.3-1 A and at load).
