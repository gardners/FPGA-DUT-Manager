# MEGA-KVM power board (issue 0047)

Status: draft v0.3 (2026-11-27: owner round 5, 0047 round 9 and the fan
control of issue 0052 applied). The schematics pass ERC and the placed boards
pass DRC with schematic parity. Polygons are sketched; the boards are **not
routed**.

KiCad 10 projects: `hardware/mega-kvm-power/`

| Path | What |
|---|---|
| `mega-kvm-power-main/` | main board: 8 switched DUT outputs, the always-on group, 8 PWM fan headers with I2C fan control and temperature (horizontal, 230 x 80 mm) |
| `mega-kvm-power-inputs/` | input board, **default**: 3 inputs, LTC4417CGN priority selection, master switch, FET temperature sensor (vertical behind the 3RU front panel, 126 x 64 mm) |
| `mega-kvm-power-inputs-lm74700/` | input board, **JLC-stocked fallback** (schematic only): 3 x LM74700-Q1 ideal diodes + P-FET switches + LM339 priority logic |
| `lib/` | project symbols (TPS259470, PMOS_TDSON8, NMOS_TDSON8, TVS_Uni, LTC4417 copy, BSP452) and footprints (TI RPW0010A, Molex 8981, MSOP-10 with 0.28 mm pads) |
| `tools/` | generators: `gen_main.py`, `gen_inputs.py`, `gen_inputs_lm74700.py` (schematics), `placement.py` + `pcb_build.py` (boards), `build_all.sh`; helpers `check_board.sh main\|inputs` (one board + ERC/DRC), `fpdump.py` (placed courtyards/pads), `fpbbox.py` (library footprint extents) |
| `out/` | schematic PDFs, ERC/DRC reports, BOM and CPL CSVs, 3D renders (top/bottom PNG) |

The schematics and boards are **generated**. Edit the Python and run
`hardware/mega-kvm-power/tools/build_all.sh`; do not edit the
`.kicad_sch`/`.kicad_pcb` by hand until we switch to manual routing. At
that point the generator stops being the source, and this note will say so.
The labels sit on the pin ends, without wires. That is
ugly but exact; KiCad's netlist and the PCB parity check agree.

## Block diagram

```
 front panel (3RU)                  input board (vertical)                    main board (horizontal)
 -----------------                  ----------------------                    -----------------------
 banana 4 mm --F1 25 A--TVS--V1--[Q1Q2(Q12)|Q3Q4(Q13)]--+                     8 x TPS259470L (5 A) --> DUT0..7 terminals
 PCIe 8-pin  --F2 15 A--TVS--V2--[Q5       |Q6       ]--+--VBUS==M4 lugs==VBUS--+
 Molex 4-pin --F3 10 A--TVS--V3--[Q7       |Q8       ]--+  (LTC4417: V1>V2>V3) 1 x TPS259470A (5 A) --> AON12: 2 x Mimas feed,
                 V1/V2/V3 --diode-OR--> VIN_OR --> front-panel rocker --> EN      GS105 barrel, 8 x BSP452 --> FAN0..7
                 input-selected LEDs (3) on the panel; TMP75 0x49 --J8==J6--  CTRL 1x11 from the shield, STATUS,
                                                                              J5 I2C: TCA9548A -> 4 x EMC2302, TMP75 0x48
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
for a third parallel pair, **Q12/Q13, DNP** by default. Fitted, the 25 A
case drops to ~8.3 A per FET, ~0.39 W each, ~2.3 W in total, spread over six
parts. On the v0.3 input board every back-to-back pair is its own column,
14 mm from the next: the input FET's drain on the Vn pour (top), the output
FET's drain on the VBUS strip (bottom), the sources facing each other on
the VSn pour. The input board's TMP75 (0x49) sits on the VS1 copper between
the banana columns.

**Package:** the default part is **LTC4417CGN**, the 24-lead narrow SSOP
(ADI GN24 package, drawing 05-08-1641). It has gull-wing leads and **no
exposed pad**; only the UF (4 x 4 QFN) version has one. The full ADI
datasheet could not be downloaded from here, so please confirm the pin
diagram once. LCSC lists C688500 (CGN) with very low stock, and the
IGN/HGN variants (C688508, C117306) at zero. Order it through **JLC global
sourcing / parts pre-order** so JLC places it like any other part; no hand
fitting.

**Soft start at master-on** (owner round 5): each channel has 22 nF + 1 k
from the gate to VBUS (C11-C13, R13/R23/R33). This Miller capacitor limits
the dV/dt of VBUS while the gate driver pulls the gate down, so about 1 mF of
VBUS capacitance charges at roughly 1 A. The value is set on the bench,
because the LTC4417 gate pull-down current is not in hand. FET SOA: about
1 A at up to 12 V for about 12 ms (about 70 mJ, about 12 W at the start)
should be a small fraction of the 10 ms SOA of a 100 A-class TDSON FET.
Confirm against the BSC030P03NS3G SOA chart.

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
connectors, fuses, TVS and lugs are the same, so the board outline does not
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

### Input board (panel side = F side)

| Ref | Part | Pins | Rating | Fuse |
|---|---|---|---|---|
| J1/J2 | 4 mm panel banana sockets (red +12 V, black GND), through-PCB with nut and solder lug | 1 each | >= 30 A sockets | F1 25 A ATO |
| J3 | PCIe 8-pin (Mini-Fit Jr 2x4 vertical header, PCIe keying) | 1-3 +12 V, 4-8 GND (sense pins tied to GND) | 150 W = 12.5 A by spec | F2 15 A ATO |
| J4 | Molex 8981 4-pin peripheral ("5.25-inch drive") male header | 1 +12 V, 2-3 GND, 4 +5 V **unused** | ~11 A per contact | F3 10 A ATO |
| J5 | JST XH 3-pin to the front-panel rocker | 1 SUPPLY (VIN_OR via 47 R), 2 LOAD/EN_SW (lamp +), 3 GND (lamp -) | signal | - |
| J6/J7 | M4 ring-lug pads VBUS / GND to the main board | - | 25 A with 12 AWG (or 2 x 14 AWG), keep < 30 cm | - |
| D7/D8/D9 | green LEDs "IN1/IN2/IN3 selected" (visible through the panel) | - | - | - |
| J8 | JST XH 5-pin (B side) to main J6 | 1 GND, 2 3V3 (from main), 3 SDA, 4 SCL, 5 /ALERT | signal | - |

Each input: blade fuse, then **SMCJ15A** unidirectional TVS (Vrwm 15 V,
clamp 24.4 V at 61.5 A, below the 28 V abs max of the TPS25947 and the
36 V of the LTC4417). A reversed supply forward-biases the TVS and blows
the fuse. LED logic: LED1 = /VALID1; LED2 = /VALID2 and not /VALID1 (Q9);
LED3 = /VALID3 and neither of the others (Q10/Q11). The LEDs run from a 3.3 V
LDO on VBUS, so they are dark when the master switch is off.

### Main board

| Ref | Pins | Notes |
|---|---|---|
| J10-J17 "DUT0-7 12V" | 1 + (OUTn), 2 - (GND) | 2-pole 5.08 mm **screw terminal** per DUT (MKDS 1,5/2-5,08 class, 13.5 A; JLC-stocked KF128/DG128 clone), for leads that end in barrel plugs (owner round 5) |
| J20/J21 "MIMAS0/1 12V" | 1 +12 V (always on), 2 GND | Molex Mini-Fit Jr 2-pin (5566-02A), 9 A, latching, polarised: goes to the shield's 12 V input, then Mimas header VIN (0045) |
| J22 "GS105 12V" | centre +12 V | CUI PJ-102AH 2.1 mm jack; needs a male-male 5.5/2.1 lead |
| J30-J37 "FAN0-7" | 1 GND, 2 +12 V, 3 TACH, 4 PWM | Molex 47053-1000 4-pin PWM fan header (C240840). FAN0-1 KVM front panel, FAN2-4 shelf fan plate A, FAN5-7 plate B. 3-pin fans fit and run at full speed. See "Fans, I2C and temperature" |
| J1/J2 | VBUS / GND M4 lugs | from the input board |
| **J3 "CTRL"** | see below | from the shield's 1x11 keyed header |
| J4 "STATUS" 1x10 | 1 GND, 2-9 /FLT0-7, 10 /FLT_AON | open drain, 10 k pull-ups to the local 3.3 V (fan tach moved to I2C) |
| J5 "I2C" 1x5 | 1 GND, 2 3V3 (only via JP1), 3 SDA, 4 SCL, 5 /INT | shield I2C bus: fan controllers (via the mux), TMP75 x 2, optional TCA9535. /INT is a wire-OR of every ALERT, 10 k pull-up (R12) |
| J6 "TEMP I2C" | 1 GND, 2 3V3, 3 SDA, 4 SCL, 5 /INT | JST XH 5-pin to the input board's J8 (its TMP75 at 0x49) |

### Control header (J3): pin order (adopted by the owner, round 5)

Single row, 2.54 mm, 11 positions. **Pin 2 is the key:** pull pin 2 out of
the header and block hole 2 of the plug. Pin 2 is off-centre, so the plug cannot go
on reversed; the middle pin (6) would not key.

| Pin | Signal | Direction (power board view) |
|---|---|---|
| 1 | GND | - |
| 2 | KEY (no pin) | - |
| 3-10 | CTRL0..CTRL7 = DUT0..DUT7 power on (active high, 3.3 V) | in, 1 k series, 20 k pull-down to GND |
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
| eFuse dissipation | 5 A x 5 A x 28-45 mOhm = 0.7-1.1 W, about 30-47 K rise (RthJA 41.7 K/W EVM) | continuous 5 A per DUT is not expected |
| Input FETs | BSC030P03NS3G, 3 mOhm; banana: 2 in parallel per side, 12.5 A each = ~0.5 W (pads for a third pair, DNP); PCIe 15 A single = ~0.7 W | |
| Copper | **2 oz** both layers (stackup set in the boards) | |
| Polygon width | VBUS >= 12.5 mm on each layer at 25 A for a 10 K rise (IPC-2221, external, 70 um); >= 1 mm per 5 A output (polygons are wider) | main VBUS pour ~36 mm; input-board VBUS strip 9 mm on B plus routing (v0.3, sketch) |
| Board-to-board | 12 AWG (3.3 mm2), or 2 x 14 AWG, ring lugs on M4 | 25 A |
| 3.3 V | L78L33 (30 V input, 100 mA) on each board | main: FLT/tach/PWM pull-ups, PRESENT, 4 x EMC2302, mux, TMP75 x 2 (the input-board sensor is fed from the main board over J6/J8): < 25 mA, ~0.2 W in the SOT-89 |

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
| ADI **LTC4417CGN** | 3-input priority PowerPath (gate controller) | C688500, **only ~3 in stock** | Leaded SSOP-24, no exposed pad. Order through JLC global sourcing / parts pre-order; JLC places it, no hand-fitting. The fallback board is fully stocked (see above). |
| TI **LM74700QDBVRQ1** (fallback) | ideal diode, 3 x | C2941042 (stocked) | SOT-23-6, leaded |
| Infineon **BSC014N04LS** (fallback) | ideal-diode N-FETs | C2760081 | 40 V, 1.4 mOhm, TDSON-8 |
| TI **LM339DR** + TL431 (fallback) | priority logic | C7948 / TBD | SOIC-14 / SOT-23 |
| Infineon **BSC030P03NS3G** | 8 x input P-FETs | C152375 (stocked) | -30 V, 3 mOhm, PG-TDSON-8. A VBsemi second source (C7524921, 3.2 mOhm) exists. |
| **SMCJ15A** | input TVS x 3 | C2834490 (MDD) | 1500 W, clamps below every downstream abs max. |
| SS34 / B5819W / 2N7002 | output clamps / diode-OR / LED logic | C8678 / C8598 / C8545 | JLC basic parts (verify). |
| **TCA9535PWR** | optional fault expander (DNP) | C130204 (extended) | 16 inputs: /FLT0-7 on P0, /FLT_AON on P1.0. Address **0x24** (A2 high), clear of the shield's 0x20/0x22. |
| L78L33ACUTR | 3.3 V, 30 V input | TBD | Survives the TVS clamp level. (AP7381, 40 V, is not at LCSC.) |
| Microchip **EMC2302-1-AIZL-TR** | 4 x fan controller (2 fans each) | C626969, 217 in stock, $3.14 (1-9) / $2.66 (10+) | MSOP-10, no pad. 26 kHz PWM, tach per fan, watchdog to 100 %. Fixed address 0x2E, hence the mux. Extended part. |
| TI **TCA9548APWR** | I2C switch for the four EMC2302 | C130026, $0.70 (1-9) | TSSOP-24. Address 0x70. LCSC showed 2.5-9k in stock in recent snapshots; confirm. |
| Infineon **BSP452** | 8 x fan-header protection | C58074, 24k in stock, $1.53 (1-9) / $1.26 (10+) / $0.95 (100+) | SOT-223 (tab = Vbb, a visible lead, not a hidden pad). |
| TI **TMP75AIDR** | temperature, main (0x48) and input board (0x49) | C30389, 4.4k, $0.29 | SOIC-8, LM75 pinout. UMW second source C5158044 (19k). |
| Molex **47053-1000** | 8 x 4-pin fan header | C240840, 21k, $0.18 | THT |
| JST **B5B-XH-A** | J6/J8 temperature-sensor cable | C157991, 55k, $0.10 | THT |
| Passives | 0603 resistors and capacitors | 10 k C25804, 100 k C25803, 4.7 k C23162, 1 k C21190, 20 k C4184, 100 n C14663; others TBD | JLC basic where possible. |
| **THT connectors** | banana sockets, ATO fuse holders (Littelfuse 178.6165), PCIe and Molex headers, screw terminals, Mini-Fit 2-pin, barrel jack, JST XH 3-pin | mostly TBD | JLC does THT assembly for stocked parts. Pick JLC-stocked equivalents when ordering. The panel-mount banana sockets (nut-fixed, through the panel) are mechanical and fitted at box assembly. |

Fuse holders: ATO blade (Littelfuse FLR 178.6165), so 10/15/25 A fuses
are cheap and easy to swap. The holder's current rating must be checked
against 25 A before ordering.

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
  4.7 k pull-ups on each used channel). Every ALERT (EMC2302, both TMP75)
  wire-ORs onto /INT (J5 pin 5, R12 10 k pull-up).
* **Temperature:** TMP75 **0x48** on the main board among the eFuses, and
  TMP75 **0x49** on the input board between the banana FET columns, on the
  cable from J6 (main) to J8 (input), JST XH 5-pin: GND, 3V3, SDA, SCL,
  /ALERT. The FETs are on the input board, and the main board lies ~30 cm
  away on the deck, so the input board does need its own sensor; this cable
  carries it. The sensor is powered from the main board's 3.3 V, not from the
  input board's LED LDO.

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
| 0x48 | TMP75, eFuse area | power main board |
| 0x49 | TMP75, input FETs | power input board |
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

**TMP75 (0x48, 0x49):** temperature register 00h, two bytes, MSB first:
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

## Mechanical (3RU KVM, issues 0050/0051)

* The **input board** stands vertically behind the **3RU KVM front panel**
  (0051 round 10), F side to the panel: banana pair (stacked, 19.05 mm
  pitch), PCIe and Molex headers, three LEDs. The connectors face out
  through panel cut-outs. The B side faces in: fuse holders, TVS, FETs,
  LTC4417, lugs, rocker connector J5, sensor connector J8. Fuses are changed
  with the unit pulled out on its rails.
* **Outline v0.3: 126 x 64 mm** (was 197 x 34 mm for the 1RU rear panel).
  On the 3RU front, height is plentiful (~133 mm) but width is not: the
  opening between the slides is about 425 mm and two 120 mm fans take about
  250 mm of it, which leaves about 175 mm for the display group, the rocker
  and the inputs. A 197 mm strip would not fit. Two tiers: top =
  connectors | fuses | TVS, caps, OR diodes | dividers | V1 riser; bottom =
  lugs | LTC4417, J8, soft start | FET columns (PCIe, Molex, banana x 3).
  Three M3 holes. The LM74700 fallback would use the same outline.
* **For the owner / case work:** the front-panel PCB (0050) is 227 mm wide,
  so it does not fit beside two 120 mm fans in a 425 mm opening either. The
  3RU panel layout needs a decision (for example the display board and the
  input board stacked in the ~175 mm column, which needs a narrower display
  board; or the fans placed differently). The input board is now small
  enough for any of these.
* The **main board** (230 x 80 mm) lies flat on the KVM deck. The DUT
  terminals and the always-on connectors are on the rear edge. The fan block
  is the right-hand 60 mm (vertical headers; leads go to the front panel and
  the cable loops). The VBUS lugs, the control/status/I2C headers and J6
  are on the front edge, towards the input board. Keep the 12 AWG link
  under 30 cm.
* Mounting: three M3 holes on the input board, six on the main board.

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
1. Shield 12 V input: the shield must fit the Mini-Fit Jr 2-pin mating
   header (owner says it matches; record the part on the shield BOM).
2. Soft-start capacitor values (C11-C13 here, C12/C22/C32 on the
   fallback): set on the bench.
3. LTC4417: confirm the GN pinout and UV/OV/HYS values against the ADI
   datasheet (it could not be fetched here).
4. (0052) BSP452 per fan header (default) or a 0.5 A PTC (saves ~$10 per
   board, but a shorted fan lead then resets the Mimas group).
5. (0052) Measure the master-on inrush of the always-on group with 8 fans
   at 100 % and both Mimas boards (see "Things to measure").
6. (0051/0050) 3RU front-panel layout: the 227 mm display board does not
   fit beside two 120 mm fans; the 126 x 64 mm input board does.

## Not yet done

* Routing (only placement and polygons). The TI RPW0010A land pattern and the Molex
  8981 footprint were drawn from datasheet text and catalogue dimensions:
  **check both against the drawings before fab**.
* LTC4417 HYS resistor (R1, DNP) and UV/OV thresholds: confirm with the
  datasheet (ADI's site could not be reached from here).
* Fallback board: schematic only (no placement). Its footprints are all
  standard library parts, so it can be placed in the same outline when it
  is needed. It has the same TMP75 + J8 as the default input board.
* The CPL CSVs in `out/` come from unrouted boards: for review and costing
  only.
* The MSOP-10 land pattern for the EMC2302 uses 0.28 mm pads (KiCad's
  0.35 mm pads leave 0.15 mm gaps, below the 0.2 mm 2 oz clearance): check
  against the Microchip drawing before fab.
