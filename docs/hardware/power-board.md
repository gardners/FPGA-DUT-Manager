# MEGA-KVM power board (issue 0047)

Status: draft v0.4 (2026-11-27: **one board**, owner round 12; earlier:
round 5, round 9 and the fan control of issue 0052; **three 5 V DUT
outputs**, issue 0055, 2026-11-27). The schematic passes
ERC and the placed board passes DRC with schematic parity. Polygons are
sketched; the board is **not routed**.

KiCad 10 projects: `hardware/mega-kvm-power/`

| Path | What |
|---|---|
| `mega-kvm-power-main/` | **the power board** (one board since round 12): 3 inputs with LTC4417CGN priority selection, master-switch connector, 8 switched DUT outputs (channels 5-7 switchable to 5 V, issue 0055), the always-on group, 8 PWM fan headers with I2C fan control, temperature (horizontal, 230 x 138.5 mm, at the front of the KVM deck) |
| `mega-kvm-power-inputs/` | **legacy** (round 12): the separate input board (v0.3, 126 x 64 mm). Kept in the tree, not built or developed |
| `mega-kvm-power-inputs-lm74700/` | **legacy**: JLC-stocked fallback input board (schematic only): 3 x LM74700-Q1 ideal diodes + P-FET switches + LM339 priority logic. Its circuit still applies if the LTC4417 cannot be sourced, but it would have to be ported into the one board |
| `lib/` | project symbols (TPS259470, PMOS_TDSON8, NMOS_TDSON8, TVS_Uni, LTC4417 copy, BSP452) and footprints (TI RPW0010A, Molex 8981, MSOP-10 with 0.28 mm pads) |
| `tools/` | generators: `gen_main.py` + `input_stage.py` (the schematic), `five_volt.py` (the 5 V outputs, 0055), `placement.py` + `pcb_build.py` (board), `build_all.sh` (one board; `LEGACY=1` also rebuilds `gen_inputs.py` / `gen_inputs_lm74700.py`); helpers `check_board.sh main\|inputs` (one board + ERC/DRC), `fpdump.py` (placed courtyards/pads), `fpbbox.py` (library footprint extents) |
| `out/` | schematic PDFs, ERC/DRC reports, BOM and CPL CSVs, 3D renders (top/bottom PNG) |

The schematics and boards are **generated**. Edit the Python and run
`hardware/mega-kvm-power/tools/build_all.sh`; do not edit the
`.kicad_sch`/`.kicad_pcb` by hand until we switch to manual routing. At
that point the generator stops being the source, and this note will say so.
The labels sit on the pin ends, without wires. That is
ugly but exact; KiCad's netlist and the PCB parity check agree.

## Block diagram

```
 one board (horizontal, front of the KVM deck); inputs on the front edge, plugged from the open top
 ------------------------------------------------------------------------------------------------
 banana 4 mm --F1 25 A--TVS--V1--[Q501 Q502 (Q512) | Q503 Q504 (Q513)]--+
 PCIe 8-pin  --F2 15 A--TVS--V2--[Q505             | Q506            ]--+--VBUS--> 8 x TPS259470L (5 A) --> DUT0..7 terminals
 Molex 4-pin --F3 10 A--TVS--V3--[Q507             | Q508            ]--+    |
   pin 4 +5 V --F4 10 A--TVS--+5V--> 3 x TPS259470L (3 A) --> DUT5-7 "5V ONLY" (JST VH)
                 (LTC4417 U50: V1 > V2 > V3)                                 +--> 1 x TPS259470A (5 A) --> AON12: 2 x Mimas,
 V1/V2/V3 --diode-OR--> VIN_OR --> J54 --> front-panel rocker --> EN              GS105 barrel, 8 x BSP452 --> FAN0..7
 input-selected LEDs D507-D509 by the connectors; TMP75 0x48 on the FET copper   CTRL 1x11 from the shield, STATUS,
                                                                                 J5 I2C: TCA9548A -> 4 x EMC2302
 CTRL5-7 --1 k--> JP5-7 (shunt 1-2: 12 V eFuse EN5-7 | 2-3: 5 V eFuse EN | none: both off)
```

* **One input at a time, automatic priority:** the LTC4417 connects the
  highest-priority valid input (after 256 ms validation) through
  back-to-back P-FETs, so two PSUs never feed each other. Valid window per
  input (dividers 1.27 M / 33.2 k / 100 k, 1.000 V +-1.5 % comparators, 30 mV
  internal hysteresis, checked against the datasheet in round 13): UV drops
  out at 10.53 V and comes back at 10.85 V; OV trips at 14.03 V rising and
  clears at 13.61 V.
* **Master on/off** (owner round 4): a backlit SPST rocker on the front
  panel, on a 3-wire cable to J54 on the front edge of the board. It switches the LTC4417 EN,
  not the 25 A. The supply comes from VIN_OR, a diode-OR of the three
  fused inputs (B5819W), which exists before VBUS. LOAD goes to EN through
  100 k / 33 k (3 V). The lamp sits between LOAD and GND, so it lights from
  12 V only when the switch is on. Off, cable unplugged or switch broken
  means EN is low and VBUS is off, so **every output is off, including the
  always-on Mimas/switch/fan group**. JP2 (solder jumper) bridges the
  switch for bench use.
* **Outputs:** eFuses only, no relays (owner round 2). EN comes straight
  from the shield's 3.3 V logic (EN/UVLO threshold 1.2 V). The 20 k pull-downs
  keep every output off while the shield is unplugged, unpowered or in reset (its
  TCA6424A outputs are high-Z at reset).

## Input selection: why the LTC4417, and the fallback

**The LTC4417 is a gate controller.** It carries no load current itself. It
only drives the gates of external back-to-back P-FETs. The current rating is
set by those FETs, their copper and the fuses. Small-current figures in
its datasheet (gate drive, VALID sink, the "5 A typical" in some
parametric tables) describe the controller or ADI's example, not a
limit. Here each path is 3 mOhm BSC030P03NS3G FETs:

| Path | FETs | Current per FET | Rds(on) hot (~1.4 x 4 mOhm at Vgs ~ -6 V) | Loss per FET | Total |
|---|---|---|---|---|---|
| banana, 20 A | 2 parallel per side (4) | 10 A | ~5.6 mOhm | ~0.56 W | ~2.2 W |
| banana, 25 A (fuse) | 2 parallel per side (4) | 12.5 A | ~5.6 mOhm | ~0.88 W | ~3.5 W |
| PCIe, 15 A | 1 per side (2) | 15 A | ~5.6 mOhm | ~1.26 W | ~2.5 W |
| Molex, 10 A | 1 per side (2) | 10 A | ~5.6 mOhm | ~0.56 W | ~1.1 W |

A TDSON-8 on a few cm2 of 2 oz copper is about 40-50 K/W, so the worst
case is +35-60 K. A full 25 A is the fuse value; 20 A continuous is the
design point. For the PCIe path at a full 15 A continuous, a second FET pair would
halve the loss. The pads are cheap; add them when routing if the bench
shows it is needed.

**Third banana pair and spacing (0047 round 9):** the banana path has pads
for a third parallel pair, **Q512/Q513, DNP** by default. Fitted, the 25 A
case drops to ~8.3 A per FET, ~0.39 W each, ~2.3 W in total, spread over six
parts. On the v0.4 board every back-to-back pair is its own column, 11-14 mm
from the next (banana x = 6, 17, 28; PCIe 42; Molex 56): the output FET's
drain up on the VBUS pour, the input FET's drain down on its Vn pour, the
sources facing each other on the VSn pour. The TMP75 (0x48) sits on the VS
copper between the banana columns and the PCIe pair.

**Package:** the default part is **LTC4417CGN**, the 24-lead narrow SSOP
(ADI GN24 package, drawing 05-08-1641). It has gull-wing leads and **no
exposed pad**; only the UF (4 x 4 QFN) version has one. The pin map and
footprint were checked against the datasheet (Rev. G) in round 13: see
"LTC4417 datasheet check" below. LCSC lists C688500 (CGN) with very low stock, and the
IGN/HGN variants (C688508, C117306) at zero. Order it through **JLC global
sourcing / parts pre-order** so JLC places it like any other part; no hand
fitting.

**Soft start and gate drive** (owner round 5, reworked in round 13 to the
datasheet's Figure 8). At master-on the LTC4417 itself soft-starts the first
channel it connects: it regulates the gate so VOUT rises at about 5 V/ms
(until a channel disconnects or 32 ms pass), so about 1 mF of VBUS
capacitance charges at about 5 A. On top of that each channel has the
datasheet's slew-rate network, which matters when it switches to a
higher-voltage input: **RS** 1 k from the Gn pin to the FET gates (net GTn,
R513/R523/R533), a **BAT54WS** across RS for a fast turn-off (D510-D512,
anode at the pin), and **CS** 22 nF from the gates to VBUS (C511-C513).
Each VSn has a **CVS** 1 uF bypass to GND (C514-C516). Datasheet rules:
CS >= 10 x Crss(max) of the output FETs in parallel; CVS >= 10 x CS; and
0.79 x RS x CS (17 us here) adds to the switch-over gap, so the VBUS droop
at a change-over is about I x (2 + 8 + 17 us) / C_VBUS, ~0.5 V at 20 A into
1 mF. A bigger CS or RS lowers the inrush but deepens that droop. Values to
be set on the bench. FET SOA at master-on: about 5 A at up to 12 V for about
2.4 ms is far inside the BSC030P03NS3G 10 ms SOA (confirm on its chart).

### LTC4417 datasheet check (round 13)

Checked against ADI's LTC4417 datasheet Rev. G (`docs/datasheets/ltc4417.pdf`,
git-ignored):

| Item | Datasheet | Board before round 13 | Now |
|---|---|---|---|
| Pin map, GN-24 | 1 EN, 2 /SHDN, 3 HYS, 4 UV1, 5 OV1, 6 UV2, 7 OV2, 8 UV3, 9 OV3, 10-12 /VALID1-3, 13 GND, 14 CAS, 15 VOUT, 16 G3, 17 VS3, 18 G2, 19 VS2, 20 G1, 21 VS1, 22 V3, 23 V2, 24 V1 | same | unchanged (correct) |
| Package | GN24: 0.150 in narrow SSOP, body 8.56-8.74 x 3.81-3.99 mm, 0.635 mm pitch, no pad | `SSOP-24_3.9x8.7mm_P0.635mm` | unchanged (correct) |
| HYS | ground it for the internal 30 mV, or RHYS to GND for 63 mV/RHYS; "connect to ground when not used" | R501 DNP: **HYS floating** | R501 fitted as 0 R |
| Gate slew network | Fig. 8: RS between Gn and the gates, Schottky across RS, CS gates -> VOUT | CS + 1 k in series from the Gn pin to VBUS (the driver overpowers it, so it limited nothing) | RS, DS, CS per Fig. 8 |
| VS bypass | CVS on every VSn (0.1-1 uF in every application, >= 10 x CS) | none | 1 uF on VS1-3 |
| VOUT pin | 100 R / 10 nF filter to ride through input/output shorts (Fig. 10) | direct to VBUS | R543 100 R / C517 10 nF |
| /VALID outputs | 2 mA abs max | LEDs on 680 R from 3.3 V: up to ~2 mA | 1 k (about 1.3 mA) |
| UV/OV | 1.000 V +-1.5 %, 30 mV hysteresis, top-UV-OV-bottom string | as designed | unchanged: UV 10.53/10.85 V, OV 14.03/13.61 V |
| EN, /SHDN | thresholds 1.1 V / 0.8 V, 3 uA pull-ups, 36 V max | 3 V from 100 k / 33 k | unchanged (EN sits at 0.1 V with the switch open) |
| CAS | leave open if unused | NC | unchanged |
| V1-V3 bypass, TVS | TVS on every input; bidirectional if reverse connection must be blocked | 1 uF + unidirectional SMCJ15A | unchanged on purpose: a reversed supply forward-biases the TVS and blows the input fuse |

**JLC-stocked fallback** (`mega-kvm-power-inputs-lm74700`, schematic only,
ERC clean). Every part is leaded and stocked:

* per input: an **LM74700-Q1** (SOT-23-6, C2941042) ideal-diode controller
  with an N-FET (BSC014N04LS, 1.4 mOhm, C2760081). Inputs can never feed
  each other or back-feed. Then a P-FET high-side switch (BSC030P03NS3G).
  Two in parallel each for the banana path.
* priority logic: one TL431 2.5 V reference and two LM339 quad comparators
  (SOIC-14, C7948). Their open-collector outputs wire-AND onto
  ON1..ON3, which are pulled up from the rocker's LOAD terminal:
  ON1 = rocker & V1 ok, ON2 = rocker & V2 ok & !V1 ok,
  ON3 = rocker & V3 ok & !V1 ok & !V2 ok ("ok" = above 10.4 V).
* ONn drives a 2N7002 that pulls the P-FET gate to Vgs = -6 V through
  100 k / 100 k. A 47 nF gate-to-VBUS Miller capacitor gives the soft start
  (~1.3 V/ms). The "selected" LED sits in the same pull-down path.
* The ideal diodes make the switch-over safe: when a higher-priority input
  appears, the lower P-FET turns off slowly (soft-start RC), but neither PSU
  can feed the other.

Why the LTC4417 stays the default: one IC does UV/OV validation, the
256 ms validation timer, hysteresis, break-before-make switching and the
VALID outputs, all with fewer parts and less layout. The fallback needs about 30
more parts, and its comparators have no hysteresis or timer (add them if it
chatters). Use the fallback if JLC cannot source the LTC4417 in time. Its
connectors, fuses and TVS are the same, so the board outline would not
change.

**Why not three cascaded eFuses?** eFuses that carry 20 A or more (TI
TPS25985/TPS25984, TPS1663 with an external FET, and so on) come in QFN or
other packages with exposed power pads. Each has its own current limit and
thermal limits, and needs heavy thermal vias. Three of them plus the same
priority logic is possible, but it costs about 3 x the money, adds a few
mOhm or more per path, and makes every part a pad-only package, which the
owner wants to avoid. Over-current
protection is already done by the fuses and the per-output 5 A eFuses, so the input
path does not need a limiter.

**Hidden-pad audit** (owner round 5: no concealed or exposed pads that would
need hand-fitting): all input-path parts are leaded or TDSON-8 (which JLC
machine-places). The one exception is the **TPS259470 eFuse** (RPW, a
2 x 2 mm QFN-HR with leads under the body and no thermal pad). It is stocked
(C3662793) and machine-placed by JLC, never hand-fitted. No 5 A eFuse with
reverse blocking comes in a leaded package.

## Connectors

### Inputs (front edge of the board)

The board's origin is its rear-left corner; x runs along the 230 mm front
edge (y = 138.5 mm), from the left. All connectors are vertical, on the top
side, plugged from above through the open top of the KVM unit.

| Ref | Part | x (mm from left edge) | Pins | Rating | Fuse |
|---|---|---|---|---|---|
| J50/J51 | 4 mm PCB-mount banana sockets, red +12 V / black GND (24.243.1/.2, C7437321/C7437322, 24 A, THT) | 8.0 / 27.05 (19.05 mm pitch), centres 7.5 mm from the edge | 1 each | 24 A (20 A design point; owner round 13: the 25 A fuse is accepted) | F1 25 A ATO |
| J52 | PCIe 8-pin (Mini-Fit Jr 2x4 vertical header, PCIe keying) | 35.3-54.4 (pin 1 at 38.5) | 1-3 +12 V, 4-8 GND (sense pins tied to GND) | 150 W = 12.5 A by spec | F2 15 A ATO |
| J53 | Molex 8981 4-pin peripheral ("5.25-inch drive") male header | 57.3-80.0 (pin 1 at 61.0) | 1 +12 V, 2-3 GND, 4 **+5 V** (since 0055: the 5 V DUT outputs) | ~11 A per contact | F3 10 A ATO (12 V); **F4 10 A ATO (5 V)** |
| J54 | JST XH 3-pin to the front-panel rocker | 83-94 (pin 1 at 86.0) | 1 SUPPLY (VIN_OR via 47 R), 2 LOAD/EN_SW (lamp +), 3 GND (lamp -) | signal | - |
| D507/D508/D509 | green LEDs "IN1/IN2/IN3 selected", just behind each connector | 17.5 / 50 / 67 | - | - | - |
| D601 | green LED "5V" (Molex +5 V present after F4; 0055), beside J53 pin 4 | 78.5 | - | - | - |

The fuse holders (F1-F4) sit in a row 21 mm behind the front edge, also
reachable from above (F4, the 5 V fuse, at x 77-98). No power connector passes through the front panel.

Each input: blade fuse, then **SMCJ15A** unidirectional TVS (Vrwm 15 V,
clamp 24.4 V at 61.5 A, below the 28 V abs max of the TPS25947 and the
36 V of the LTC4417). A reversed supply forward-biases the TVS and blows
the fuse. LED logic: LED1 = /VALID1; LED2 = /VALID2 and not /VALID1;
LED3 = /VALID3 and neither of the others (Q510/Q511; Q509 for LED2). The LEDs run from the
board's 3.3 V LDO on VBUS, so they are dark when the master switch is off.

### Main board

| Ref | Pins | Notes |
|---|---|---|
| J10-J17 "DUT0-7 12V" | 1 + (OUTn), 2 - (GND) | 2-pole 5.08 mm **screw terminal** per DUT (MKDS 1,5/2-5,08 class, 13.5 A; JLC-stocked KF128/DG128 clone), for leads that end in barrel plugs (owner round 5) |
| J20/J21 "MIMAS0/1 12V" | 1 +12 V (always on), 2 GND | Molex Mini-Fit Jr 2-pin (5566-02A), 9 A, latching, polarised: goes to the shield's 12 V input, then Mimas header VIN (0045) |
| J22 "GS105 12V" | centre +12 V | CUI PJ-102AH 2.1 mm jack; needs a male-male 5.5/2.1 lead |
| J61-J63 "DUT5-7 5V ONLY" | 1 +5 V (OUT5V5-7), 2 GND | **JST VH 2-pin** vertical B2P-VH (C160315), 3.96 mm, 10 A per contact, friction-lock latch, polarised. Rear edge x 171-210 (pin 1 at x 174 / 189 / 204, y 7.5). Mates VHR-2N (C595405) + SVH-21T-P1.1 crimps (C160349, 18-22 AWG). Nothing else on the board uses VH, so a 5 V lead cannot land on a 12 V output (issue 0055) |
| JP5-JP7 "CH5-7 12V/5V" | 1 EN5-7 (12 V eFuse), 2 CSEL (CTRLn via 1 k), 3 EN5V5-7 (5 V eFuse) | 1x3 2.54 mm header (C2932698) + shunt (C100114), by J3 at x 100/105/110. See "5 V DUT outputs" |
| J30-J37 "FAN0-7" | 1 GND, 2 +12 V, 3 TACH, 4 PWM | Molex 47053-1000 4-pin PWM fan header (C240840). FAN0-1 KVM front panel, FAN2-4 shelf fan plate A, FAN5-7 plate B. 3-pin fans fit and run at full speed. See "Fans, I2C and temperature" |
| **J3 "CTRL"** | see below | from the shield's 1x11 keyed header |
| J4 "STATUS" 1x10 | 1 GND, 2-9 /FLT0-7, 10 /FLT_AON | open drain, 10 k pull-ups to the local 3.3 V (fan tach moved to I2C). /FLT5-7 = channel 5-7 fault, from whichever output (12 V or 5 V) JP5-7 selects (wire-OR, 0055) |
| J5 "I2C" 1x5 | 1 GND, 2 3V3 (only via JP1), 3 SDA, 4 SCL, 5 /INT | shield I2C bus: fan controllers (via the mux), TMP75, optional TCA9535. /INT is a wire-OR of every ALERT, 10 k pull-up (R12) |

### Control header (J3): pin order (adopted by the owner, round 5)

Single row, 2.54 mm, 11 positions. **Pin 2 is the key:** pull pin 2 out of
the header and block hole 2 of the plug. Pin 2 is off-centre, so the plug cannot go
on reversed; the middle pin (6) would not key.

| Pin | Signal | Direction (power board view) |
|---|---|---|
| 1 | GND | - |
| 2 | KEY (no pin) | - |
| 3-10 | CTRL0..CTRL7 = DUT0..DUT7 power on (active high, 3.3 V) | in, 1 k series, 20 k pull-down to GND. CTRL5-7 switch the 12 V **or** the 5 V output of their channel, as JP5-7 select (0055) |
| 11 | PRESENT | out: 3.3 V through 10 k when the power board is connected **and powered**; the shield should pull it down (100 k) |

One cable from the **master shield** drives all 8 outputs (owner round
5). The shield pin plan (`docs/hardware/shield-pinplan.md`) drives
PWR_CTL0..7 from expander A (TCA6424A at 0x22) P2.0-7. It must route them to
pins 3-10 in this order and read PRESENT on a spare expander input, with a
100 k pull-down. PRESENT is "power board present and powered", which is not the same
as the shield's own SHD_FEAT1 strap.

## Ratings and sizing

| Item | Value | Basis |
|---|---|---|
| VBUS | 12 V nominal, **25 A** max (input fuse F1), 300 W | banana input; PCIe input 15 A, Molex 10 A |
| DUT outputs | 8 x 5.0 A current limit (R_ILM = 665 R: I = 3334 / R) | TPS25947 eq. 5; 750 R (4.45 A) if UL 2367 recognition matters |
| Always-on group | 5.0 A shared, auto-retry; UVLO ~9.4 V (100 k / 14.7 k) | 2 Mimas (polyfuse 2.6 A each, ~0.5-1 A real) + GS105 (~0.5 A) + 8 x 120 mm fans (0.08-0.2 A each running, ~2 x that while starting). Running: ~2.6-4.1 A. **Master-on is the tight moment**: every fan starts at 100 % together with the Mimas boards; measure it (see the fan section) |
| Fan headers | BSP452 per header: 160 mOhm, current limit 0.7 A min / 1.5 A typ / 2.4 A max, thermal shutdown with auto-restart | a shorted fan lead is limited to <= 2.4 A, so it cannot pull the always-on group into its 5 A limit |
| Overvoltage | all 9 eFuses open above **14.8 V** (shared OVLO divider 113 k / 10 k) | the Mimas has no OVP of its own (0045 facts) |
| Inrush per output | ~0.9 V/ms (C_dVdt 2.2 nF), 0.45 A into 470 uF | TPS25947 eq. 4 |
| Overcurrent blanking | ~4 ms (C_ITIMER 4.7 nF), up to 2 x ILIM meanwhile | |
| Sum of limits | 8 x 5 + 5 = 45 A > 25 A input | the input fuse/PSU is the real total limit; MEGA65s draw far less |
| +5 V (0055) | from Molex pin 4 only, F4 **10 A**; 3 x 3.03 A limits = 9.1 A | Molex 8981 contact ~11 A; PSU 5 V lead 18 AWG; see "5 V DUT outputs" |
| 5 V outputs | 3 x 3.03 A (R_ILM 1.1 k), OVLO 5.90 V rising / 5.36 V falling (392 k / 100 k), ~0.8 V/ms (2.2 nF), ~4 ms blanking (4.7 nF), auto-retry | TPS25947 eq. 5, OVLO thresholds 1.20 V / 1.09 V |
| eFuse dissipation | 5 A x 5 A x 28-45 mOhm = 0.7-1.1 W, about 30-47 K rise (RthJA 41.7 K/W EVM) | continuous 5 A per DUT is not expected |
| Input FETs | BSC030P03NS3G, 3 mOhm; banana: 2 in parallel per side, 12.5 A each = ~0.5 W (pads for a third pair Q512/Q513, DNP); PCIe 15 A single = ~0.7 W | |
| Copper | **2 oz** both layers (stackup set in the boards) | |
| Polygon width | VBUS >= 12.5 mm on each layer at 25 A for a 10 K rise (IPC-2221, external, 70 um); >= 1 mm per 5 A output (polygons are wider) | main VBUS pour ~36 mm, joined directly to the output FETs' drains (v0.4, sketch) |
| Board-to-board | none since round 12 (one board) | |
| 3.3 V | L78L33 (30 V input, 100 mA) | FLT/tach/PWM pull-ups, PRESENT, 4 x EMC2302, mux, TMP75, 3 input LEDs: < 30 mA, ~0.25 W in the SOT-89 (the 5 V LEDs run from +5 V, not from here) |

Output discharge: the TPS25947 has no quick-output-discharge. The 4.7 k
LED resistor on each output (about 2.5 mA) bleeds an unloaded output down.
An SS34 Schottky from OUT to GND clamps negative spikes on cable unplug
or short, as TI recommends. The TPS25947 blocks reverse current, so a DUT
that is powered elsewhere cannot back-feed VBUS.

## Key parts and why (JLCPCB / LCSC)

LCSC numbers as of 2026-11-27. "JLC basic" means a library part with no extended
fee. Check stock when ordering.

| Part | Use | LCSC | Why / sourcing |
|---|---|---|---|
| TI **TPS259470ARPWR** | all 12 eFuses: 8 x 12 V DUT, 3 x 5 V DUT, always-on (auto-retry) | C3662799 (stocked, ~4k on 2026-11-27) | 5.5 A, 28 mOhm, true reverse blocking, adjustable ILIM/OVLO/dVdt, EN works with 3.3 V logic, FLT output. **Auto-retry** (owner 2026-11-27, because the latch-off TPS259470L, C3662793, showed 0 stock): a shorted DUT is retried by the eFuse itself; /FLTn pulses on every retry, so the host sees the fault and can switch CTRLn off. The L part is a drop-in (same footprint and pins) if latch-off is wanted later. |
| ADI **LTC4417CGN** | 3-input priority PowerPath (gate controller) | C688500, **0 in stock at JLC on 2026-11-27** (was ~3) | Leaded SSOP-24, no exposed pad. Order through JLC global sourcing / parts pre-order; JLC places it, no hand-fitting. The fallback board is fully stocked (see above). |
| TI **LM74700QDBVRQ1** (fallback) | ideal diode, 3 x | C2941042 (stocked) | SOT-23-6, leaded |
| Infineon **BSC014N04LS** (fallback) | ideal-diode N-FETs | C2760081 | 40 V, 1.4 mOhm, TDSON-8 |
| TI **LM339DR** + TL431 (fallback) | priority logic | C7948 / TBD | SOIC-14 / SOT-23 |
| Infineon **BSC030P03NS3G** | 8 x input P-FETs | C152375 (stocked) | -30 V, 3 mOhm, PG-TDSON-8. A VBsemi second source (C7524921, 3.2 mOhm) exists. |
| **SMCJ15A** | input TVS x 3 | C2834490 (MDD) | 1500 W, clamps below every downstream abs max. |
| SS34 / B5819W / 2N7002 | output clamps / diode-OR / LED logic | C8678 / C8598 / C8545 | JLC basic parts (verify). |
| Diodes **BAT54WS-7-F** | LTC4417 gate turn-off diodes D510-D512 (round 13) | C124205 (43.8k), $0.10 | SOD-323, 30 V Schottky. |
| **TCA9535PWR** | optional fault expander (DNP) | C130204 (extended) | 16 inputs: /FLT0-7 on P0, /FLT_AON on P1.0, **5V_PRESENT on P1.1** (0055). Address **0x24** (A2 high), clear of the shield's 0x20/0x22. |
| TI **TPS259470LRPWR** (0055) | 3 x 5 V DUT eFuses U61-U63 | C3662793 (same row as the 12 V eFuses: 11 per board) | Same part, same footprint, same stock problem (0 at JLC on 2026-11-27). |
| **SMBJ5.0A** (0055) | +5 V input TVS D600 | C2758500, ~33k in stock, $0.04 | SMB, Vrwm 5.0 V, Vbr 6.4 V min, Vc 9.2 V. |
| JST **B2P-VH(LF)(SN)** (0055) | 3 x 5 V output connectors J61-J63 | C160315, ~140k in stock, $0.06 | THT, 10 A per contact. Cable side VHR-2N (C595405, 23k) + SVH-21T-P1.1 (C160349, 306k). |
| 1x3 2.54 mm header + shunt (0055) | JP5-JP7 channel selectors | C2932698 (4.5k, $0.02) + C100114 shunt (339k, $0.01) | Shunts are loose parts, fitted at box assembly. |
| L78L33ACUTR | 3.3 V, 30 V input | TBD | Survives the TVS clamp level. (AP7381, 40 V, is not at LCSC.) |
| Microchip **EMC2302-1-AIZL-TR** | 4 x fan controller (2 fans each) | C626969, 217 in stock, $3.14 (1-9) / $2.66 (10+) | MSOP-10, no pad. 26 kHz PWM, tach per fan, watchdog to 100 %. Fixed address 0x2E, hence the mux. Extended part. |
| TI **TCA9548APWR** | I2C switch for the four EMC2302 | C130026, $0.70 (1-9) | TSSOP-24. Address 0x70. LCSC showed 2.5-9k in stock in recent snapshots; confirm. |
| Infineon **BSP452** | 8 x fan-header protection | C58074, 24k in stock, $1.53 (1-9) / $1.26 (10+) / $0.95 (100+) | SOT-223 (tab = Vbb, a visible lead, not a hidden pad). |
| TI **TMP75AIDR** | temperature, input FETs (0x48) | C30389, 4.4k, $0.29 | SOIC-8, LM75 pinout. UMW second source C5158044 (19k). |
| Molex **47053-1000** | 8 x 4-pin fan header | C240840, 21k, $0.18 | THT |
| Passives | 0603 resistors and capacitors | 10 k C25804, 100 k C25803, 4.7 k C23162, 1 k C21190, 20 k C4184, 0 R C21189, 100 R C22775, 100 n C14663; others TBD | JLC basic where possible. |
| **THT connectors** | banana sockets, ATO fuse holders (Littelfuse 178.6165), PCIe and Molex headers, screw terminals, Mini-Fit 2-pin, barrel jack, JST XH 3-pin | mostly TBD | JLC does THT assembly for stocked parts. Pick JLC-stocked equivalents when ordering. The panel-mount banana sockets (nut-fixed, through the panel) are mechanical and fitted at box assembly. |

Fuse holders: ATO blade (Littelfuse FLR 178.6165), so 10/15/25 A fuses
are cheap and easy to swap. The holder's current rating must be checked
against 25 A before ordering.

## 5 V DUT outputs (issue 0055)

Owner request (2026-11-27): three outputs for FPGA boards that take 5 V on
a DC barrel. The 5 V comes only from the Molex input; banana and PCIe carry
no 5 V, and there is no 12 V to 5 V converter (owner: "such is life").
Generator: `tools/five_volt.py`.

```
 J53 pin 4 --F4 10 A ATO--+5V--+-- D600 SMBJ5.0A, C600/C601 10 uF, D601 "5V" LED, R601/R602 -> 5V_PRESENT
 (+5V_RAW)                     +-- R604/R605 392 k / 100 k -> OVLO5 (5.90 V), shared
                               +-- U61 TPS259470L 3 A --> J61 "DUT5 5V ONLY" (JST VH)
                               +-- U62 TPS259470L 3 A --> J62 "DUT6 5V ONLY"
                               +-- U63 TPS259470L 3 A --> J63 "DUT7 5V ONLY"
 CTRLn (n = 5..7) --1 k-- CSELn = JPn pin 2;  JPn pin 1 = ENn (12 V eFuse Un+1), pin 3 = EN5Vn (5 V eFuse)
                                              each EN: 20 k to GND
```

**Source and fuse.** J53 pin 4 (+5 V of the Molex 8981 lead) goes through
its own **10 A ATO fuse F4** (the same holder and fuse as F3), independent
of the LTC4417 12 V selector. Sizing: three outputs limited to 3.03 A each
= 9.1 A, below 10 A, so the eFuses act first and F4 only clears wiring
faults (a shorted strip, a failed eFuse, 12 V on pin 4). An ATO blade
carries 110 % of its rating for at least 100 h, so 9 A is fine. Upstream limits:
the Molex 8981 contact is good for about 11 A, and a PC PSU's 5 V lead is
18 AWG (about 10 A in chassis wiring). A 7.5 A fuse would protect a thin
lead better but would blow with all three outputs near their limits.

**Protection.** An **SMBJ5.0A** unidirectional TVS (C2758500; Vrwm 5.0 V,
Vbr 6.4 V min, 9.2 V clamp at 65 A) after F4 catches hot-plug spikes. As on
the 12 V inputs, a reversed supply forward-biases it and blows F4; until
then the TPS25947 itself blocks down to -15 V (datasheet 7.3.1), and the
supply-side OVLO resistor is >= 350 k as its note 4 asks. A 12 V lead on
pin 4 (a miswired adapter) is held off by OVLO (outputs open within
1.2 us) while the TVS conducts until F4 blows; the TVS may die short doing
that, which is still safe. Slow over-voltage: OVLO opens all three 5 V
outputs at **5.90 V** rising and lets them back on below 5.36 V (ATX allows
5.25 V). The Molex connector is keyed, so a reversed lead needs a bodged
adapter. No series FET: it would add 50-100 mV and parts for a case the
eFuse already survives.

**eFuses.** **TPS259470A** (auto-retry since 2026-11-27, see the key-parts
table), the same part and footprint as the 12 V DUT eFuses; a shorted 5 V
DUT is retried by the eFuse and shows as pulses on /FLTn. Settings, with the 12 V cell values where they suit 5 V too:

| Setting | Part | Value | Why |
|---|---|---|---|
| ILIM | R612/R622/R632 1.1 k | 3334 / 1100 = **3.03 A** | the owner's "2-3 A each"; typical 5 V barrel boards draw 0.5-2 A; 3 x 3 A stays below F4. During the blanking time up to 2 x ILIM flows, so a board with large input capacitance still starts |
| OVLO | R604 392 k / R605 100 k, C602 100 nF | 5.90 V rising, 5.36 V falling | 1.20 V / 1.09 V thresholds; above the 5.25 V ATX tolerance, below what 5 V barrel boards tolerate (their regulators are usually rated 6-7 V) |
| dV/dt | 2.2 nF | ~0.8 V/ms, 0 -> 5 V in ~6 ms | 0.4 A into 470 uF, 0.8 A into 1000 uF: a barrel-jack board's bulk capacitor charges well inside the 3 A limit |
| ITIMER | 4.7 nF | ~4 ms blanking | as the 12 V cells |
| Output | SS34 to GND, 1 uF, 1 k + green LED (3 mA) | | negative-spike clamp, LED shows the output is live and bleeds an unloaded output |

**Channel selector JP5-JP7.** The shield's 8 CTRL lines all drive 12 V
outputs, so the 5 V outputs share CTRL5-7. Per channel, a **1x3 2.54 mm
header with a shunt**: CTRLn goes through the existing 1 k to the middle
pin (CSELn). Shunt on **1-2** = the 12 V output DUTn (as before), on
**2-3** = the 5 V output, **no shunt = both off**. Each EN keeps its own
20 k pull-down, so the unselected eFuse is always off.

* **Header, not a solder jumper:** DUT boards move between slots, and a
  shunt changes without tools and shows its position at a glance. A 1x3
  header also cannot select both outputs: two shunts cannot share pin 2.
  A three-pad solder jumper can, with one solder blob across all three pads.
* **No shunt = both off (chosen) rather than 12 V:** a shunt that is lost
  or never fitted turns the channel off, never on at the wrong voltage. The
  board is not built yet, so no board in the field changes behaviour; fit
  the three shunts on 1-2 (12 V) at box assembly to keep "channel n = 12 V"
  as the default. JLC cannot fit shunts: they are loose parts (C100114).
* Move a shunt only with the channel off: a shunt moved while CTRLn is high
  switches the outputs immediately (the 12 V one off, the 5 V one on).
* Only the selected eFuse can be on, and its output is on its own connector
  type: the 12 V screw terminal never carries 5 V and the VH connector
  never carries 12 V, whatever the shunt does. The selector only decides
  which connector is live.

**Connectors.** J61-J63: **JST VH 2-pin vertical** (B2P-VH, C160315):
3.96 mm pitch, 10 A per contact, polarised, with a friction-lock latch on
the housing (VHR-2N, C595405; crimps SVH-21T-P1.1, C160349, 18-22 AWG).
Nothing else on the board is a VH: the 12 V outputs are 5.08 mm screw
terminals, the Mimas feeds Mini-Fit Jr, the rocker JST XH. They sit on the
rear edge with the other DUT outputs, right of the GS105 jack (x 171-210,
15 mm pitch), silk "DUTn 5V ONLY", with "5V ONLY (JST VH): channel set by
JP5-7" under them. The owner's leads use different barrel shank lengths at
the DUT end (shorter = lower voltage).

**Status to the host.**

* **Faults:** the 5 V eFuse's /FLT is wire-ORed onto /FLTn of its channel
  (the 10 k pull-up in the 12 V cell). Only one of the pair can be enabled;
  the disabled one (EN low = UVLO) and an unpowered one (no Molex 5 V)
  leave /FLT high. So /FLT5-7 mean "channel 5-7 faulted" whichever output
  is selected, on J4 and on the optional TCA9535 P0.5-7, with no new lines.
* **5 V present:** R601 10 k / R602 20 k from +5V (3.3 V at 5 V, logic high
  above ~3.5 V) to the optional **TCA9535 U11 P1.1** (0x24, on the shield
  I2C bus via J5). The shield's own expanders have no free input and the
  1x11 CTRL cable is full (`shield-pinplan.md`), so this is the only host
  path; U11 is DNP by default. A green **"5V" LED D601** next to J53 pin 4
  shows it on the board in any case.
* **Selection readback:** U11 P1.2-P1.4 read EN5V5-7: high = channel on
  and set to 5 V. With CTRLn high, EN5Vn low means the 12 V output is live
  (or no shunt). The host cannot see the shunt while the channel is off.

**Power budget.** The 5 V outputs draw from the PSU's 5 V rail, not from
VBUS. Worst case 9.1 A (the three limits), typically 1-6 A. A channel set
to 5 V draws nothing from VBUS, so the 12 V budget does not grow. Voltage at
the DUT under load: F4 (~7 mOhm) + the B.Cu strip (~150 mm x 8 mm, 2 oz,
~5 mOhm) + the eFuse (28-45 mOhm) + the PSU lead (18 AWG, 0.5 m out and
back, ~20 mOhm) is about 32 mOhm shared plus the eFuse: **~0.4 V with all
three outputs at 3 A**, ~0.2 V with one output at 3 A, ~0.1 V at 1 A. The
lead to the DUT adds its own. eFuse loss at 3 A: 0.25-0.4 W each.

**Layout.** F4 continues the fuse row (x 77-98); J53 pin 4 reaches it on a
B.Cu strip. TVS, caps, LED and the sense divider sit right of F4 on a small
F.Cu pour; the +5V bus runs on B.Cu (y 112.5-121, then up x 161.5-169 past
H2, ~8 mm wide, about 15 A at a 10 K rise on 2 oz) to an F.Cu pour under
the 5 V eFuse row. The strips cut the B.Cu GND plane: stitch GND around
them when routing. To make room on the rear edge the fan block moved 39 mm
forward (now y 40-111). The board outline (230 x 138.5 mm), the mounting
holes and the connectors the case reads (J10-J17, J50-J54) did not move,
so the case fit is unchanged (`hardware/mega-kvm-case` rebuilt: still
"Conflicts / problems: none"; only the footprint order in its outputs
changed, so they were not committed).

### 5 V DUT outputs: open questions

1. **TPS259470L stock:** LCSC/JLC show 0 for C3662793 (the same part as
   the eight 12 V DUT eFuses, now 11 per board). Stocked alternatives in
   the family: TPS259470A (auto-retry, C3662799, ~4k) or TPS259474L
   (latch-off circuit breaker, adjustable OVLO, C2864845, ~5.9k; it has PG
   instead of /FLT, so the fault wiring would change).
2. **Fit U11 (TCA9535) by default?** It is now the only way the host sees
   5V_PRESENT, the 5 V selection and (as before) the /FLT lines.
3. **Shunt default at assembly:** 1-2 (12 V) on all three, as proposed?
4. **Rear lead holes:** the case has 8 DUT power lead holes, enough for one
   lead per channel. If both leads of a channel stay plugged in, three more
   holes are needed (`ITEMS['dut_power']` in the case config).
5. **3 A per 5 V output** enough, and is 0.2-0.4 V of drop at full load
   (from the PSU to the VH connector) acceptable for the boards in mind?

## Fans, I2C and temperature (issue 0052)

### What is on the main board

* **8 x 4-pin PWM headers** J30-J37 (Molex 47053-1000; 1 GND, 2 +12 V,
  3 TACH, 4 PWM). FAN0-1: the two 120 mm fans on the KVM front panel.
  FAN2-4: shelf fan plate A. FAN5-7: shelf fan plate B (long leads through
  the cable loops). They are fed from the **always-on group** (AON12), so the
  master rocker still switches them.
* **Per-header protection: BSP452** smart high-side switch (SOT-223). Its
  IN is tied on through 10 k from AON12.
* **PWM:** each EMC2302 PWM output drives a **2N7002 inverter**: gate with a
  100 k pull-down, drain on the fan's PWM pin with a 4.7 k pull-up to 3.3 V
  (fans have their own pull-up as well). FET off = fan PWM high = 100 %.
* **Tach:** 10 k pull-up to 3.3 V, 1 k in series into the EMC2302 TACH pin.
  The pull-up goes to the controller's own 3.3 V rail, so the datasheet rule
  "pull-up no higher than 3.6 V while the part is unpowered" holds.
* **Controllers: 4 x EMC2302-1** (2 fans each: fans 2m and 2m+1 on
  controller m) behind a **TCA9548A** I2C switch (channel m = controller m,
  4.7 k pull-ups on each used channel). Every ALERT (EMC2302, TMP75)
  wire-ORs onto /INT (J5 pin 5, R12 10 k pull-up).
* **Temperature (round 12): one TMP75 at 0x48**, on the VS copper between
  the banana FET columns and the PCIe pair, ~50 mm in front of the eFuse
  row. With the inputs on the same board one sensor is enough: the input
  FETs are the only multi-watt heat source (2-3.5 W at 20-25 A); the eFuses
  dissipate ~1 W each only at a full 5 A and have their own thermal
  shutdown, and they share the same 2 oz copper and air. The second sensor
  (0x49) and the J6/J8 cable are gone.

### Why these parts

**Controller.** Requirements: 25 kHz PWM, at least 3 independent channels
(better one per fan), tach on every fan, pad-free, JLC/LCSC stock, a free
address. Checked on LCSC/JLC (jlcsearch) on 2026-11-27:

| Part | Fans (PWM/tach) | Package | LCSC stock | Verdict |
|---|---|---|---|---|
| Microchip EMC2301 | 1/1 | MSOP-8 | C148036, ~2k | pad-free, but one fan and a fixed 0x2F |
| **Microchip EMC2302-1 / -2** | 2/2 | **MSOP-10, no pad** | C626969: 217 / C626970: 55 | **chosen (4 x -1)**; fixed 0x2E / 0x2F |
| Microchip EMC2303 / EMC2305 | 3 / 5 | QFN-12/16 with EP | 1 / 21 | exposed pad: out |
| Maxim MAX31790 | 6/6 | TQFN-28 with EP | 250 | exposed pad: out |
| onsemi ADT7473 / ADT7470 | 3/4, 4/4 | QSOP-16 | 26 / none | too few tachs, no stock |
| TI AMC6821 | 1/1 | SSOP-16 | 146 | one fan per $2.82 part |
| 8-bit MCU (CH32V003 etc.) | any | TSSOP/SOP | plenty | firmware to write and maintain: last resort, not needed |

No pad-free part covers 8 fans with 8 tachs. Four 2-channel EMC2302s do.
They have no address pins (0x2E for -1, 0x2F for -2), so a TCA9548A gives
each its own downstream bus. All four are the -1 variant, which has the
better stock. Result: **one PWM and one tach per fan**, 8 independent
channels. The "3 groups" requirement (KVM pair, plate A, plate B) is met by
writing the same duty to a group's fans.

Datasheet: Microchip DS20006532A (EMC2301/2/3/5). 26 kHz default PWM base
(within the Intel 21-28 kHz window), 0.5 % RPM accuracy, VDD 3.0-3.6 V,
TACH/SMBus pins 5 V tolerant, MSOP-10 with no exposed pad (only the QFN
variants have one).

**Power-on and failure behaviour (fans on).** The EMC2302 powers up with
Fan Setting = 00h, open-drain output and normal polarity: the pin sinks,
the 2N7002 gate stays low, the FET is off, and the fan sees PWM high =
**100 %**. The same happens when the 3.3 V is missing, the controller is
dead or missing, or the mux is stuck. The EMC2302's own watchdog (4 s
without SMBus access after power-up, or all the time if WD_EN is set)
drives "full scale". With the inverted polarity the host sets, plus the
hardware inverter, that is again 100 %. So the safe fixed duty is **100 %**
(loud but safe) until the host programs a curve. The fans spin up at full
speed for a moment at every master-on, as in a PC. (Only the QFN
EMC2303/5 can strap a lower default speed with resistors.)

### Register-level usage (host or FPGA)

I2C addresses on the shield bus (7-bit):

| Address | Device | Where |
|---|---|---|
| 0x20, 0x22 | TCA6424A expanders | shield |
| 0x24 | TCA9535 (optional, DNP) | power main board |
| 0x25, 0x26 | expanders | front panel |
| 0x27 / 0x3F | PCF8574(A) LCD backpack | front panel |
| 0x48 | TMP75, input FETs (between FETs and eFuses) | power board |
| 0x70 | TCA9548A I2C switch | power main board |
| 0x2E | 4 x EMC2302-1 behind the switch (channel m = controller m) | power main board; visible only while its channel is selected |

**Select a controller:** write one byte to 0x70: `1 << m` (m = 0..3);
write 00h to deselect all. Then talk to 0x2E. Fan `f` (0..7) is on
controller `m = f / 2`, channel `f % 2 + 1` (registers 3xh for channel 1,
4xh for channel 2).

**Initialise each controller** (after selecting it):

| Reg | Write | Meaning |
|---|---|---|
| 2Bh PWM Output Config | 03h | PWM1/PWM2 push-pull (they drive the 2N7002 gates) |
| 2Ah PWM Polarity Config | 03h | both inverted, because the 2N7002 inverts again |
| 2Dh PWM BaseF123 | 00h (default) | 26 kHz base |
| 31h / 41h PWM Divide | 01h (default) | no division: 26 kHz at the fan |
| 32h / 42h Fan Configuration 1 | 2Bh (default) | direct-setting mode (ENAG = 0); RANGE 01 = 1000 rpm minimum, tach multiplier 2; 5 edges (2-pole fan) |
| 20h Configuration | 60h | DIS_TO stays 1 (plain I2C, no SMBus timeout); **WD_EN = 1**: if the host stops touching this controller for 4 s, it drives its fans to 100 % |
| 29h Fan Interrupt Enable | 03h | stall, spin-up and drive-fail of both fans assert ALERT (/INT) |

Writing a Fan Setting register ends the one-shot power-up watchdog, so
WD_EN is set to keep the 4 s watchdog as a continuous dead-host failsafe.
The software lock (EFh) is not needed.

**Set a duty:** Fan Setting 30h (channel 1) / 40h (channel 2) = 00h..FFh
for 0..100 %. Many fans stop below ~20 %, some at 0 %.

**Read speed:** TACH Reading high byte 3Eh / 4Eh (count bits 12:5) first,
then the low byte 3Fh / 4Fh (count bits 4:0 in bits 7:3; reading the high
byte latches the low). `count = (hi << 5) | (lo >> 3)`,
`rpm = 3932160 * 2 / count` with the default RANGE (multiplier 2). Count
1FFFh (FFh, F8h) means stopped or no tach.

**Status:** Fan Status 24h (bit 7 WATCH = watchdog fired, bit 2 DVFAIL,
bit 1 FNSPIN, bit 0 FNSTL); Fan Stall Status 25h, Spin Status 26h, Drive
Fail Status 27h (bit 0 = channel 1, bit 1 = channel 2). Read them to clear
them once the condition has gone; that releases ALERT. Product ID FDh = 36h
(EMC2302), Manufacturer ID FEh = 5Dh: a presence check per channel.

**Keep-alive:** with WD_EN set, read each controller (the tach, say) at
least every 2 s. If the host or FPGA stops, all fans reach 100 % within 4 s.

**TMP75 (0x48):** temperature register 00h, two bytes, MSB first:
`t = (int16)(b0 << 8 | b1) / 256.0` deg C. Configuration 01h (default 00h:
comparator mode, ALERT active low, 9-bit; write 60h for 12-bit). T_LOW 02h /
T_HIGH 03h default to 75 / 80 deg C: ALERT pulls /INT low above T_HIGH until
the temperature falls below T_LOW. Suggested host policy: ramp the fans
with the hotter sensor from ~40 deg C, report both temperatures in the
heartbeat, and cut DUT power (CTRL lines) above ~85 deg C at the input FETs.

### Per-header protection: eFuse or PTC

Owner: "if eFuses are cheap, why not? Otherwise resettable fuses".

* **Small 12 V eFuses for 0.5-1 A** (TI TPS2595x/TPS25947x, Toshiba
  TCKE8xx and similar) come in WSON/QFN with exposed or hidden pads, or the
  0.45 mm RPW package. None at this voltage is in SOT/SOIC with JLC stock.
* The leaded equivalent is a **smart high-side switch**. Stocked at LCSC:
  Infineon **BSP452** (SOT-223, C58074, 24k in stock, 160 mOhm, current
  limit 0.7 A min / 1.5 A typ / 2.4 A max, 5-34 V, thermal shutdown with
  auto-restart), ITS4141N (SOT-223, C538473, 1.7k, 200 mOhm, 12-45 V),
  ITS4140N (C454920, 1 Ohm). The BSP452 is the best stocked and carries a
  120 mm fan (0.1-0.3 A) with margin.
* **PTC fallback:** 0.5 A hold / 1 A trip, 1206, 30 V, e.g. JK-nSMD050-30
  (C720075, 435k in stock, $0.03).

| | BSP452 | 0.5 A PTC |
|---|---|---|
| Cost per header | $1.53 (1-9), $1.26 (10+), $0.95 (100+) | $0.03 |
| Per board (8 headers) | ~$10-12 at prototype quantities | ~$0.25 |
| Hard short on a fan lead | limited to <= 2.4 A within microseconds, then thermal cycling; the rest of the always-on group never notices | ~5 A (the always-on eFuse limit) until the PTC trips, tens of ms to seconds later: the always-on eFuse hits its limit and timer and **resets both Mimas boards and the switch** |
| Stalled fan | the fan's own locked-rotor protection; the switch stays on | same |

**Choice: BSP452.** About $1.30 per header buys isolation: a pinched lead
in a shelf's cable loop cannot take down the supervisors and the network.
With a PTC the fault is still cleared, but only after the always-on group
has dropped out. SOT-223 has a visible tab, not a hidden pad, so it meets
the owner's rule. If cost matters more, a 1206 PTC in place of the switch
is a small schematic and placement change.

### Things to measure

* **Master-on inrush of the always-on group** with all 8 fans and both
  Mimas boards. If it trips the 5 A limit (auto-retry would make it a
  restart loop), either raise the always-on limit (R182; the TPS259470 goes
  to 5.5 A), or feed the fan switches from VBUS instead of AON12. They keep
  their own limit; they would lose the 14.8 V OVLO, but the TVS clamps and
  the BSP452 turns off at 34 V.
* Fan PWM edges on the 1-2 m shelf leads at 26 kHz (the 4.7 k pull-up and
  the cable capacitance give a few microseconds of rise time; fine for the
  Intel spec, check on the scope).

## Current sensing on the DUT rails (study, round 13; not on the board yet)

The owner asked (round 13) what per-DUT current measurement would cost. This
is an estimate only; nothing is on the board yet.

### The eFuse already has a current monitor

The TPS259470's **ILM pin is both the current-limit setting and an analog
load-current monitor** (TI SLVSFC9C, section 7.3.6). The pin sources
I_MON = G_IMON x I_OUT into R_ILM, so the voltage across R_ILM follows the
load current:

* G_IMON = 182 uA/A typical, 165-200 uA/A min/max (datasheet table, 0.5 A to
  5.5 A, below the current limit). With R_ILM = 665 R: **V_ILM = 0.121 V/A**,
  i.e. 36 mV at 0.3 A, 121 mV at 1 A, 0.61 V at the 5 A limit. The limit
  itself trips when V_ILM reaches about 0.61 V (I_LIM = 3334 / R_ILM), and
  during the overcurrent blanking time it can reach about 2 x that (1.2 V).
* Accuracy (datasheet Fig. 6-16, over process and temperature): about
  -8/+9 % at 0.5 A, +-6 % at 1 A, +-5 % from 2 A up. Below 0.5 A it is
  not specified, and no zero-current offset is given: expect +-10-15 % at
  0.3 A until a bench check says otherwise. R_ILM (1 %) adds to that.
* A one-point calibration per channel (a known load, e.g. 1-2 A, stored by
  the host) removes most of each part's gain error. What is left is drift
  with temperature and the curve's shape: an estimated few % at load, more
  at 0.3 A.

**Rules for using the pin** (from the datasheet and how the pin works):

1. **At most 50 pF on the ILM pin** (TI note: "sensitive to capacitive
   loading"), so no filter capacitor directly on the pin and no long
   trace before an isolating resistor.
2. **Any DC load on ILM changes the current limit**: the pin voltage is what
   the limit comparator sees. A load R_L in parallel with R_ILM raises the
   limit by R_ILM / R_L. The ADC input must look like a high impedance.
3. **Recommended interface per channel:** 10 k (0603) right at the eFuse ILM
   pin, then the trace to the ADC, then 1 nF to GND at the ADC input. The pin
   then sees R_ILM in parallel with 10 k only for edges faster than about
   10 us, which lowers V_ILM by at most 6 % on fast steps (the limit is a
   little higher for a few microseconds). At DC it sees nothing but the ADC
   input impedance through 10 k. The 1 nF is far larger than the ADC's
   sampling capacitor (a few pF), so the switched-capacitor kickback is
   absorbed there and never reaches the eFuse.
4. **Same supply:** the ADC must be powered whenever the eFuses can be on.
   An unpowered ADC clamps its inputs to its VDD through the ESD diodes,
   which would pull current out of ILM and raise the limit. Powering it
   from the power board's own +3V3 (from VBUS, like the eFuses) does this.
   Do not power it from the shield.
5. Open ILM sets the limit near zero; ILM shorted to GND is detected as a
   fault. The 10 k series resistor keeps an ADC-side short from doing that.

### Options and cost

Prices and stock from JLCPCB's parts search on 2026-11-27 (1-9 / 100+
unit price). All parts are leaded, no exposed pad. "Extended" parts add
JLC's ~$3 loading fee per part type per order.

| Option | Parts (LCSC, stock) | Resolution at R_ILM = 665 R | Accuracy, idle 0.3-1 A / load 2-5 A | Area | Added cost per board |
|---|---|---|---|---|---|
| **A: 2 x ADS1115 on the ILM pins (recommended)** | 2 x TI ADS1115IDGSR, VSSOP-10, C37593 (72k), $1.22 / $0.82; 8 x 10 k C25804 + 8 x 1 nF C1588 (basic) | 16-bit, +-1.024 V range: 31 uV = **0.26 mA** per code | set by G_IMON: ~+-10-15 % / +-6 % raw; a few % after one-point calibration. The 10 k into the ADC's MOhm-class switched-capacitor input reads about 1 % low (a fixed gain error, calibrated out with the rest) | ~100 mm2 (2 x ~25 mm2 for the ICs with decoupling, 8 x ~6 mm2 for R and C) | **~$2.5 (1-9), ~$1.7 (100+)**, plus one extended fee |
| B: 1 x ADS7828 on the ILM pins | TI ADS7828E/2K5, TSSOP-16, C701649 (3.8k), $5.04 / $3.64; same R/C (C 10-100 nF for its larger SAR sampling capacitor) | 12-bit, internal 2.5 V: 0.61 mV = **5 mA** per code (60 codes at 0.3 A) | as A, plus +-1-2 codes (+-2-3 % at 0.3 A) | ~70 mm2 | ~$5.1 / ~$3.7, one extended fee |
| (C: ADS7830, 8-bit) | ADS7830IPWR C161747 (4.7k), $1.80 / $1.08 | 9.8 mV = **81 mA** per code (under 4 codes at 0.3 A) | too coarse at idle | ~70 mm2 | ~$1.9 / ~$1.2 |
| D: shunt + INA226 per rail | 8 x TI INA226AIDGSR, VSSOP-10, C49851 (37.7k), $0.67 / $0.41; 8 x 5 mOhm 1 % 2512 shunt RLM25FEER005 C185817 (31k), $0.053 / $0.042; 8 x 100 nF | 2.5 uV = **0.5 mA** per code; also reads each rail's voltage and power | offset <= 10 uV (2 mA): ~+-2 % at 0.3 A, ~+-1.1 % at load (shunt 1 % + gain 0.1 %), no calibration needed | ~500 mm2, and the shunts sit in each 5 A output path (output pours re-laid, Kelvin sense traces) | **~$5.9 / ~$3.7**, two extended fees; 125 mW and 25 mV lost per rail at 5 A |

INA219 (C138706, SOIC-8, $0.56 at 100+) costs more than the INA226 and is
less precise; INA3221 (3 channels) has an exposed pad (QFN-16-EP), so both
were left out. The 12-bit ADS1015 (C193969) costs more than the ADS1115.

**I2C:** ADS1115 addresses are 0x48-0x4B (ADDR to GND/VDD/SDA/SCL). 0x48 is
the TMP75, so use **0x49 (ADDR = VDD) and 0x4B (ADDR = SCL)**. Both are
clear of 0x20/0x22/0x24-0x27, 0x2E, 0x3F, 0x70. They could also go behind
the TCA9548A's spare channels 4-7. INA226s would take 0x40-0x47.

**Sampling:** each ADS1115 converts one of its four inputs at a time (8 to
860 samples/s). At 128 samples/s the host gets all 8 rails about 4 times
a second. That is plenty for idle / booting / busy / near-the-limit
decisions. For short spikes, the eFuse's own /FLT and limit already act.

**Recommendation:** option A. It costs about $2 per board, takes about
100 mm2 near the eFuses, puts nothing in the power path and uses a signal
the eFuses already produce. Its accuracy is set by the eFuse's monitor gain
(+-5-9 % raw, a few % after a one-point calibration per rail). That is
enough to tell an idle MEGA65 from a busy one or a fault. If per-DUT energy to
+-1-2 % is ever needed, option D (INA226 per rail) is the upgrade: about
$2-3.5 more per board, about 5 x the area, and a re-layout of the output
paths.

## Mechanical (one board, owner round 12)

* **One board, 230 x 138.5 mm**, lying flat at the **front of the KVM
  deck** (the 3RU unit is open-top). Origin = rear-left corner; the
  front edge is y = 138.5 mm.
  * Front strip (y 80-138.5): the input stage. Connectors on the front edge
    at the left (x 2-94, see "Inputs"), fuse holders behind them, then the
    TVS/divider chains, the input FET columns (y 81-103), the LTC4417 and
    soft start (x 64-92), the LED logic and master-switch passives (x 80-110).
  * Middle (y 24-80): VBUS pour, bulk caps, 3.3 V LDO, CTRL J3 / STATUS J4 /
    I2C J5 headers, optional expander.
  * Rear edge (y 0-24): DUT0-7 screw terminals, MIMAS0/1 Mini-Fit, GS105
    barrel jack, then (0055) the three 5 V outputs J61-J63 (JST VH, x
    171-210) with their eFuses below them (y 15-36).
  * Right 60 mm (x 170-230, y 40-111, moved 39 mm forward for the 5 V
    outputs in 0055): the fan block (8 headers); fan controllers and mux at
    x 139-167, y 35-53.
  * 5 V path (0055): J53 pin 4 -> F4 (x 77-98, y 115-122) on a B.Cu strip;
    TVS, caps, LED, sense divider right of F4; the +5V bus on a B.Cu strip
    (y 112.5-121, then up x 161.5-169 past H2) to the 5 V eFuse row. The
    strips cut the B.Cu GND plane; stitch GND around them when routing.
* The DUT and always-on leads leave from the rear edge. The front edge
  should sit a few cm behind the front panel, with clear space above it for
  the PCIe/Molex plugs (vertical, ~35 mm with the cable bend) and the banana
  plugs; the case agent places it.
* The master rocker stays on the front panel, wired to J54 (JST XH 3-pin).
* No front-panel cut-outs for power any more; no 12 AWG link and no lugs.
* Mounting: eight M3 holes (H1-H8), corners plus the old 80 mm-board
  corners and a hole beside the rocker connector.
* The separate input board (v0.3, 126 x 64 mm, and the earlier 1RU
  197 x 34 mm strip) is legacy.

## Mechanical (superseded 1RU notes, kept for history)

* The input board stands vertically behind a panel. It is the rear panel per owner round
  4, but the case fit check (`hardware/mega-kvm-case/out/fit-report.md`) has no room on
  the rear beside the two DUT bays, so it may go on the right side wall. The F side
  faces out: banana pair (19 mm pitch), PCIe and Molex headers, three LEDs.
  The B side faces in: fuse holders (blade fuses replaceable with the lid
  off), TVS, FETs, LTC4417, lugs, master-switch connector.
* **Outline v0.2: 197 x 34 mm** (was 150 x 40, which hit the lid by 1.55 mm:
  the 1RU interior is 38.45 mm with a 3 mm floor and a 3 mm lid). Every part, connector
  bodies included, stays inside the 34 mm band. That leaves 4.45 mm for a
  slot or standoffs. Left to right: connectors (x 2-83) | fuse column |
  TVS + diode-OR | UV/OV dividers | FETs + LTC4417 | soft start | M4 lugs.
  The LM74700 fallback uses the same outline and connector positions; it
  has more small parts, but they fit the same 34 mm band.
* **Narrow variant (concept, not drawn):** if the inputs must sit on the
  rear next to the DUT bays (about 54 mm free), a **48 x 34 mm connector-only
  board** fits. It holds the banana pair stacked vertically (x 2-14), the PCIe
  header turned 90 degrees (about 12 x 19 mm) and the Molex header turned 90 degrees
  (about 9 x 22 mm): about 42 mm of connectors. The fuse holders, TVS, FETs
  and LTC4417 do not fit behind it. They would move onto the main board
  (about 60 x 34 mm of extra area), fed by three raw input pairs (V1/V2/V3 +
  GND, 12 AWG for the banana path) from the connector board. Say if you want
  it and I will draw it; the electrical design does not change.
* The main board lies flat near the rear. Its DUT terminals and the always-on connectors
  are on the rear edge, and the control/status/I2C headers and VBUS lugs on
  the front edge.
* (v0.2) Two M3 holes on the input board, four on the main board.

## Owner answers (round 5) and remaining questions

Answered: one control cable from the master shield; 1x11 order adopted;
screw terminals (+/-) per DUT; no hand-fitting (LTC4417 through JLC
sourcing, stocked fallback designed); soft start added; 5 A limits kept
(665 R; 750 R would keep UL 2367 recognition at 4.45 A); Mimas feed on Mini-Fit Jr
2-pin.

Still open:
0. (0055) See "5 V DUT outputs: open questions".
1. Shield 12 V input: the shield must fit the Mini-Fit Jr 2-pin mating
   header (owner says it matches; record the part on the shield BOM).
2. Gate slew values RS/CS (R513/R523/R533, C511-C513 here; C12/C22/C32 on
   the fallback): set on the bench (see "Soft start and gate drive").
3. ~~LTC4417 pinout and UV/OV/HYS~~: checked in round 13 (see "LTC4417
   datasheet check").
4. (0052) BSP452 per fan header (default) or a 0.5 A PTC (saves ~$10 per
   board, but a shorted fan lead then resets the Mimas group).
5. (0052) Measure the master-on inrush of the always-on group with 8 fans
   at 100 % and both Mimas boards (see "Things to measure").
6. (round 12) Banana sockets: PCB-mount 24 A parts (24.243.1/.2,
   C7437321/C7437322) are the stocked choice. **Owner round 13: a 25 A
   fuse with the 24 A sockets is fine** (not a commercial product; 1 A is
   within tolerance), so F1 stays 25 A. Still check their pin pattern
   against the generic `Banana_Jack_1Pin` footprint before fab.

## Not yet done

* Routing (only placement and polygons). The TI RPW0010A land pattern and the Molex
  8981 footprint were drawn from datasheet text and catalogue dimensions:
  **check both against the drawings before fab**.
* Fallback (LM74700) input stage: legacy schematic only; it would have to be
  ported into the one board if the LTC4417 cannot be sourced.
* The CPL CSVs in `out/` come from unrouted boards: for review and costing
  only.
* The MSOP-10 land pattern for the EMC2302 uses 0.28 mm pads (KiCad's
  0.35 mm pads leave 0.15 mm gaps, below the 0.2 mm 2 oz clearance): check
  against the Microchip drawing before fab.
