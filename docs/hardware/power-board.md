# MEGA-KVM power board (issue 0047)

Status: draft v0.1 (2026-11-27). The schematics pass ERC and the placed boards
pass DRC with schematic parity. Polygons are sketched; the boards are **not routed**.

KiCad 10 projects: `hardware/mega-kvm-power/`

| Path | What |
|---|---|
| `mega-kvm-power-main/` | main board: 8 switched DUT outputs and the always-on group (horizontal, 170 x 80 mm) |
| `mega-kvm-power-inputs/` | input board: 3 inputs, LTC4417 priority selection, master switch (vertical behind the rear panel, 150 x 40 mm) |
| `lib/` | project symbols (TPS259470, PMOS_TDSON8, TVS_Uni, LTC4417 copy) and footprints (TI RPW0010A, Molex 8981) |
| `tools/` | generators: `gen_main.py`, `gen_inputs.py` (schematics), `placement.py` + `pcb_build.py` (boards), `build_all.sh` |
| `out/` | schematic PDFs, ERC/DRC reports, BOM CSVs, 3D renders (top/bottom PNG) |

The schematics and boards are **generated**. Edit the Python and run
`hardware/mega-kvm-power/tools/build_all.sh`; do not edit the
`.kicad_sch`/`.kicad_pcb` by hand until we switch to manual routing. At
that point the generator stops being the source, and this note will say so.
The labels sit on the pin ends, without wires. That is
ugly but exact; KiCad's netlist and the PCB parity check agree.

## Block diagram

```
 rear panel                         input board (vertical)                    main board (horizontal)
 ---------                          ----------------------                    -----------------------
 banana 4 mm --F1 25 A--TVS--V1--[Q1Q2|Q3Q4]--+                               8 x TPS259470L (5 A) --> DUT0..7 terminals
 PCIe 8-pin  --F2 15 A--TVS--V2--[Q5  |Q6  ]--+--VBUS==M4 lugs/12 AWG==VBUS--+
 Molex 4-pin --F3 10 A--TVS--V3--[Q7  |Q8  ]--+   (LTC4417: V1 > V2 > V3)    1 x TPS259470A (5 A) --> 2 x Mimas feed,
                 V1/V2/V3 --diode-OR--> VIN_OR --> front-panel rocker --> EN      GS105 barrel, 2 x fan
                 input-selected LEDs (3) on the rear panel                   CTRL 1x11 from the shield, STATUS, I2C (opt.)
```

* **One input at a time, automatic priority:** the LTC4417 connects the
  highest-priority valid input (after 256 ms validation) through
  back-to-back P-FETs, so two PSUs never feed each other. Valid window per
  input: UV ~10.5 V, OV ~14.0 V (dividers 1.27 M / 33.2 k / 100 k, 1.0 V
  comparators: **check thresholds against the datasheet**).
* **Master on/off** (owner round 4): a backlit SPST rocker on the front
  panel, on a 3-wire cable to J5 of the input board. It switches the LTC4417 EN,
  not the 25 A. The supply comes from VIN_OR, a diode-OR of the three
  fused inputs (B5819W), which exists before VBUS. LOAD goes to EN through
  100 k / 33 k (3 V). The lamp sits between LOAD and GND, so it lights from
  12 V only when the switch is on. Off, cable unplugged or switch broken
  means EN is low and VBUS is off, so **every output is off, including the
  always-on Mimas/switch/fan group**. JP1 (solder jumper) bridges the
  switch for bench use.
* **Outputs:** eFuses only, no relays (owner round 2). EN comes straight
  from the shield's 3.3 V logic (EN/UVLO threshold 1.2 V). The 20 k pull-downs
  keep every output off while the shield is unplugged, unpowered or in reset (its
  TCA6424A outputs are high-Z at reset).

## Connectors

### Input board (rear panel side = F side)

| Ref | Part | Pins | Rating | Fuse |
|---|---|---|---|---|
| J1/J2 | 4 mm panel banana sockets (red +12 V, black GND), through-PCB with nut and solder lug | 1 each | >= 30 A sockets | F1 25 A ATO |
| J3 | PCIe 8-pin (Mini-Fit Jr 2x4 vertical header, PCIe keying) | 1-3 +12 V, 4-8 GND (sense pins tied to GND) | 150 W = 12.5 A by spec | F2 15 A ATO |
| J4 | Molex 8981 4-pin peripheral ("5.25-inch drive") male header | 1 +12 V, 2-3 GND, 4 +5 V **unused** | ~11 A per contact | F3 10 A ATO |
| J5 | JST XH 3-pin to the front-panel rocker | 1 SUPPLY (VIN_OR via 47 R), 2 LOAD/EN_SW (lamp +), 3 GND (lamp -) | signal | - |
| J6/J7 | M4 ring-lug pads VBUS / GND to the main board | - | 25 A with 12 AWG (or 2 x 14 AWG), keep < 30 cm | - |
| D7/D8/D9 | green LEDs "IN1/IN2/IN3 selected" (visible through the panel) | - | - | - |

Each input: blade fuse, then **SMCJ15A** unidirectional TVS (Vrwm 15 V,
clamp 24.4 V at 61.5 A, below the 28 V abs max of the TPS25947 and the
36 V of the LTC4417). A reversed supply forward-biases the TVS and blows
the fuse. LED logic: LED1 = /VALID1; LED2 = /VALID2 and not /VALID1 (Q9);
LED3 = /VALID3 and neither of the others (Q10/Q11). The LEDs run from a 3.3 V
LDO on VBUS, so they are dark when the master switch is off.

### Main board

| Ref | Pins | Notes |
|---|---|---|
| J10-J17 "DUT0-7 12V" | 1 OUTn, 2 GND | Phoenix MSTBA 2,5/2-G-5,08 + pluggable MSTB plug, 12 A; one 2-pole block per DUT |
| J20/J21 "MIMAS0/1 12V" | 1 +12 V (always on), 2 GND | Molex Mini-Fit Jr 2-pin (5566-02A), 9 A, latching, polarised: goes to the shield's 12 V input, then Mimas header VIN (0045) |
| J22 "GS105 12V" | centre +12 V | CUI PJ-102AH 2.1 mm jack; needs a male-male 5.5/2.1 lead |
| J23/J24 "FAN0/1" | 1 GND, 2 +12 V, 3 TACH | standard 3-pin fan header; R190/R191 0 R in series, fit 47-100 R to slow a fan |
| J1/J2 | VBUS / GND M4 lugs | from the input board |
| **J3 "CTRL"** | see below | from the shield's 1x11 keyed header |
| J4 "STATUS" 1x12 | 1 GND, 2-9 /FLT0-7, 10 /FLT_AON, 11-12 TACH0/1 | open drain, 10 k pull-ups to the local 3.3 V |
| J5 "I2C" 1x5 | 1 GND, 2 3V3 (only via JP1), 3 SDA, 4 SCL, 5 /INT | for the optional TCA9535 |

### Control header (J3): proposed pin order, coordinate with the shield

Single row, 2.54 mm, 11 positions. **Pin 2 is the key:** pull pin 2 out of
the header and block hole 2 of the plug. Pin 2 is off-centre, so the plug cannot go
on reversed; the middle pin (6) would not key.

| Pin | Signal | Direction (power board view) |
|---|---|---|
| 1 | GND | - |
| 2 | KEY (no pin) | - |
| 3-10 | CTRL0..CTRL7 = DUT0..DUT7 power on (active high, 3.3 V) | in, 1 k series, 20 k pull-down to GND |
| 11 | PRESENT | out: 3.3 V through 10 k when the power board is connected **and powered**; the shield should pull it down (100 k) |

The shield pin plan (`docs/hardware/shield-pinplan.md`, branch
`feature/shield-pinplan`) drives PWR_CTL0..7 from expander A (TCA6424A at
0x22) P2.0-7 and has SHD_FEAT1 = "power relay header fitted". It does not
yet define the order of the 1x11 pins or a PRESENT input. The shield
should adopt this table, or tell us its own. Note that PRESENT is "power
board present", not a shield feature strap.

## Ratings and sizing

| Item | Value | Basis |
|---|---|---|
| VBUS | 12 V nominal, **25 A** max (input fuse F1), 300 W | banana input; PCIe input 15 A, Molex 10 A |
| DUT outputs | 8 x 5.0 A current limit (R_ILM = 665 R: I = 3334 / R) | TPS25947 eq. 5; 750 R (4.45 A) if UL 2367 recognition matters |
| Always-on group | 5.0 A shared, auto-retry; UVLO ~9.4 V (100 k / 14.7 k) | 2 Mimas (polyfuse 2.6 A each, ~0.5-1 A real) + GS105 (~0.5 A) + fans (2 x 50 mA) |
| Overvoltage | all 9 eFuses open above **14.8 V** (shared OVLO divider 113 k / 10 k) | the Mimas has no OVP of its own (0045 facts) |
| Inrush per output | ~0.9 V/ms (C_dVdt 2.2 nF), 0.45 A into 470 uF | TPS25947 eq. 4 |
| Overcurrent blanking | ~4 ms (C_ITIMER 4.7 nF), up to 2 x ILIM meanwhile | |
| Sum of limits | 8 x 5 + 5 = 45 A > 25 A input | the input fuse/PSU is the real total limit; MEGA65s draw far less |
| eFuse dissipation | 5 A x 5 A x 28-45 mOhm = 0.7-1.1 W, about 30-47 K rise (RthJA 41.7 K/W EVM) | continuous 5 A per DUT is not expected |
| Input FETs | BSC030P03NS3G, 3 mOhm; banana: 2 in parallel per side, 12.5 A each = ~0.5 W; PCIe 15 A single = ~0.7 W | |
| Copper | **2 oz** both layers (stackup set in the boards) | |
| Polygon width | VBUS >= 12.5 mm on each layer at 25 A for a 10 K rise (IPC-2221, external, 70 um); >= 1 mm per 5 A output (polygons are wider) | main VBUS pour ~36 mm, input-board VBUS pour 24 mm |
| Board-to-board | 12 AWG (3.3 mm2), or 2 x 14 AWG, ring lugs on M4 | 25 A |
| 3.3 V | L78L33 (30 V input) on each board, a few mA | FLT pull-ups, PRESENT, LEDs, optional expander |

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
| TI **TPS259470LRPWR** | 8 DUT eFuses (latch-off) | C3662793 (stocked, ~6k) | 5.5 A, 28 mOhm, true reverse blocking, adjustable ILIM/OVLO/dVdt, EN works with 3.3 V logic, FLT output. Latch-off: a shorted DUT stays off until the shield toggles CTRLn and the host logs it. |
| TI **TPS259470ARPWR** | always-on eFuse (auto-retry) | TBD (same family) | Nobody toggles EN on the always-on group, so it must retry by itself. |
| ADI **LTC4417CGN** | 3-input priority PowerPath | C688500, **only ~3 in stock** | No stocked alternative at 25 A with priority and UV/OV validation. Plan: JLC global sourcing or a consigned part, or hand-fit. The QFN (LTC4417IUF, C580907) is a layout change. |
| Infineon **BSC030P03NS3G** | 8 x input P-FETs | C152375 (stocked) | -30 V, 3 mOhm, PG-TDSON-8. A VBsemi second source (C7524921, 3.2 mOhm) exists. |
| **SMCJ15A** | input TVS x 3 | C2834490 (MDD) | 1500 W, clamps below every downstream abs max. |
| SS34 / B5819W / 2N7002 | output clamps / diode-OR / LED logic | C8678 / C8598 / C8545 | JLC basic parts (verify). |
| **TCA9535PWR** | optional fault expander (DNP) | C130204 (extended) | 16 inputs: /FLT0-7 on P0, /FLT_AON on P1.0. Address **0x24** (A2 high), clear of the shield's 0x20/0x22. |
| L78L33ACUTR | 3.3 V, 30 V input | TBD | Survives the TVS clamp level. (AP7381, 40 V, is not at LCSC.) |
| Passives | 0603 resistors and capacitors | 10 k C25804, 100 k C25803, 4.7 k C23162, 1 k C21190, 20 k C4184, 100 n C14663; others TBD | JLC basic where possible. |
| **Hand-fit / THT** | banana sockets, ATO fuse holders (Littelfuse 178.6165), PCIe and Molex headers, MSTBA terminals, Mini-Fit 2-pin, fan headers, barrel jack, JST XH | mostly TBD | JLC can do THT assembly for stocked parts; the panel-mount bananas, fuse holders and high-current headers are safest hand-fitted. |

Fuse holders: ATO blade (Littelfuse FLR 178.6165), so 10/15/25 A fuses
are cheap and easy to swap. The holder's current rating must be checked
against 25 A before ordering.

## Mechanical (1RU box, issues 0048/0050)

* The input board stands vertically behind the **rear panel** (owner round
  4: all power inputs on the rear, next to the Ethernet bulkhead). The F side
  faces out: banana pair (19 mm pitch), PCIe and Molex headers, three LEDs.
  The B side faces in: fuse holders (blade fuses replaceable with the lid
  off), TVS, FETs, LTC4417, lugs, master-switch connector. Height 40 mm fits
  1RU (44.45 mm outside).
* The main board lies flat near the rear. Its DUT terminals and the always-on connectors
  are on the rear edge, and the control/status/I2C headers and VBUS lugs on
  the front edge.
* Two M3 holes on the input board, four on the main board.

## Open questions for the owner

1. **Which shield drives the 1x11 header?** There are 2 shields per unit and
   8 outputs on one header: one shield drives all 8 (say the shield of
   board 0), or we split 4+4 over two headers. The draft has one header.
2. **1x11 pin order and PRESENT:** please confirm the table above, so that the
   shield (feature/shield-pinplan) can match it and give PRESENT an
   expander input.
3. **Shield 12 V input connector:** the draft uses Mini-Fit Jr 2-pin for the
   two Mimas feeds. The shield should use the mating part (or tell us
   which connector it has).
4. **DUT output connector:** pluggable 5.08 mm terminal blocks (as asked)
   or barrel jacks on the rear panel? The MEGA65 PSU plug would then fit
   directly.
5. **LTC4417 sourcing:** OK to consign or hand-fit it? (LCSC has only a few.)
6. **Inrush at master-on:** VBUS bulk is 2 x 470 uF + ceramics. The
   LTC4417 turns the FETs on fairly fast, so a gate-to-source capacitor per
   channel (footprint to add) or less bulk may be needed. Decide on the bench.
7. **UL 2367 limit:** 665 R gives 5.0 A as asked. 750 R (4.45 A) keeps the
   TPS25947 inside its UL recognition. Which one?

## Not yet done

* Routing (only placement and polygons). The TI RPW0010A land pattern and the Molex
  8981 footprint were drawn from datasheet text and catalogue dimensions:
  **check both against the drawings before fab**.
* LTC4417 HYS resistor (R1, DNP) and UV/OV thresholds: confirm with the
  datasheet (ADI's site could not be reached from here).
