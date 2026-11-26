# MEGA-KVM link-board shield and keyboard sub-board (rev A draft)

Issue 0045 (owner rounds 1-7), ADR 0007 (links between boards), pin plan
`docs/hardware/shield-pinplan.md` v1 (issue 0049). KiCad projects:
`hardware/mega-kvm-shield/` (shield) and `hardware/mega-kvm-shield/kbd-sub/`
(keyboard sub-board, two per Mimas).

Status: **schematics complete (ERC 0 on both), connectors and parts placed,
not routed** (only 12 V and the GND/3V3 planes). DRC: 0 errors on both
boards; what remains is silkscreen warnings and the unrouted nets. Not ready
for fab: see "Before fab" and "Open choices".

## How the projects are built

The KiCad files are **generated**. Edit the scripts, not the schematic.

| File | What |
|---|---|
| `scripts/design.py` | the circuit as data (both boards): header pin plan, every part (symbol, footprint, LCSC number, pin -> net), `board` = shield or kbd |
| `scripts/geometry.py` | the mechanical numbers both boards share: rear-edge slots, sub-board position, stack heights |
| `scripts/gen_sch.py` | both schematics, `lib/shield.kicad_sym`, netlists and JLCPCB BOMs (`out/`, `kbd-sub/out/`) |
| `scripts/gen_fp.py` | `lib/shield.pretty/Mimas_Header_Socket_2x40` (pads `A1..A40`, `B1..B40`) |
| `scripts/gen_pcb.py`, `gen_kbd_pcb.py` | the two boards (run inside the KiCad flatpak, they use pcbnew) |
| `Makefile` | `make` = schematics + boards + ERC + DRC + exports |

Outputs:
* `out/`: `mega-kvm-shield-schematic.pdf`, `-top.png`, `-bottom.png`, `-3d.png`,
  `-top.svg` (outline, silkscreen and the Mimas outline on User.Drawings),
  `bom-jlcpcb.csv`, `erc.rpt`, `drc.rpt`.
* `kbd-sub/out/`: `mega-kvm-kbdsub-schematic.pdf`, `-top.png`, `-3d.png`, BOM and reports.

Once someone routes a board by hand in KiCad, stop regenerating that board
(`make sch erc` is still safe, but `gen_pcb.py` would overwrite the routing).

## Arrangement (owner rounds 5-7)

Seen from the rear panel (right = towards P12), per Mimas:

```
 shield level   | JB1 DUT2 | JB1 DUT1 | HDMI1  HDMI2  HDMI3 | JB1 DUT0 | JB1 DUT3 |
 Mimas level    | J5  DUT2 | J5  DUT1 | (mDP)  OUT     IN   | J5  DUT0 | J5  DUT3 |
                |<- P13-side overhang ->|<---- Mimas 90 ---->|<- P12-side overhang ->|
```

* Each DUT is one column: its JB1 (JTAG + UART) on the shield at the panel
  edge, its J5 (keyboard) directly below on a keyboard sub-board. The JB1s
  sit beside the Mimas, next to the header pins that carry their signals
  (DUT0/DUT3 on P12, DUT1/DUT2 on P13), so the JTAG routes are short.
* The three header HDMI inputs sit on the shield above the Mimas, between
  its two rear mounting holes, above the Mimas's own HDMI OUT/IN and mDP.
  DUT0's video is the Mimas HDMI IN, below its column neighbour.
* Both J5 and JB1 are box headers with the MEGA65 pin numbering, so
  ordinary straight 12-way and 10-way IDC cables go to the MEGA65's JB1
  and J5.

### Width (owner question: two Mimas per unit)

| Layout | Per Mimas | Two Mimas |
|---|---|---|
| Single row on the shield edge: 4 x JB1 (24) + 4 x J5 (21.5) + 3 x HDMI (21), with no gaps and not counting the Mimas hole keep-outs | >= 245 mm | >= 490 mm: **does not fit** 430-445 mm, even with the GS105 in front of or behind the boards |
| Single row with the physical keyboard J5 on the rear edge too | >= 267 mm | >= 534 mm |
| **Chosen: two levels (JB1 on the shield, J5 on sub-boards), HDMIs above the Mimas** | **189.6 mm** (shield y -49.8 .. 139.8) | **~380 mm** + ~2 mm between the shields + walls (2 x 3 mm) = **~388 mm** |

So the two shields fit a 19-inch case (430-445 mm inside) with 40-55 mm to
spare. The GS105 (~94 mm) does not fit beside them as well: it goes in front
of or behind the boards, or on the mezzanine (issue 0048).

### Stack (z above the case floor, `geometry.py`)

| z (mm) | What |
|---|---|
| 0 | case floor |
| 3.0-4.6 | Mimas PCB and keyboard sub-boards (3 mm standoffs) |
| 4.6-~11 | Mimas HDMI IN/OUT, mDP; **J5 headers 4.6-13.5** |
| 15.6-17.2 | shield (8.5 mm sockets on the Mimas male headers, and on the sub-boards' 2x6 headers) |
| 17.2-~23.7 | header HDMI receptacles |
| 17.2-~26.2 | JB1 headers |

The top of the connectors is at about 26 mm. That leaves about 12 mm inside a
1RU case (about 38.5 mm inside with 3 mm panels) for plugs, fans and cable
bends.

**Conflict to handle:** the JB1 pins come through the shield's underside
right above the J5 bodies (J5 top at 13.5 mm, shield underside at 15.6 mm).
Clip the JB1 tails to <= 1.5 mm after soldering. Alternatively, use 2.5 mm
longer male pins on the sub-board and sit it 2.5 mm lower.

## Mechanics

Mimas coordinates: origin at the Mimas board's corner between the RJ45 edge
and the P13 edge, x towards the HDMI edge, y towards P12 (Numato V3
drawing). These numbers come from the drawing: **check them with calipers on a real board before fab**.

| Item | Position |
|---|---|
| Mimas board | 120 x 90 mm |
| Header row 1 centre | x = 10.41 (header body starts at 9.14); row n at 10.41 + (n-1) x 2.54 |
| P12 | column A y = 86.19, column B y = 88.73 (B on the outer edge) |
| P13 | column A y = 1.27, column B y = 3.81 (A on the outer edge) |
| Mimas holes (3.2 mm) | (5.00, 84.86), (115.0, 85.0), (4.83, 5.00), (115.0, 5.00) |
| Rear (HDMI) edge | x = 120: HDMI IN y 63.8-78.8, HDMI OUT 42.4-57.4, mDP 25.9-37.3 / 9.6-21.0 |
| Front (RJ45) edge | x = 0: RJ45 y 60.8-76.6, USB-B 40.8-52.8, S12 30.6-37.2, P2 25.2-27.7, DC jack 13.4-22.4 |

**Shield** (120 x 189.6 mm, 4 layers: signals / GND / 3V3 / signals + 12 V):

* Rear-edge slots (`geometry.SLOTS`, Mimas y):

  | Slot | y |
  |---|---|
  | DUT3 JB1 | 114.8 .. 138.8 |
  | DUT0 JB1 | 90.6 .. 114.6 |
  | HDMI3 | 60.2 .. 81.2 |
  | HDMI2 | 38.6 .. 59.6 |
  | HDMI1 | 17.0 .. 38.0 |
  | DUT1 JB1 | -24.6 .. -0.6 |
  | DUT2 JB1 | -48.8 .. -24.8 |

  The HDMI lips stand 1.5 mm proud, like the Mimas's own; the box headers
  are flush.
* Cut-out x 0-18, y 12.4-77.6 so the RJ45, USB-B, power switch S12, P2
  jumper and DC jack stay reachable.
* 8 x 3.2 mm holes: the 4 Mimas holes (11 mm standoffs) and 4 in the
  overhang corners (standoffs to the floor).
* Bottom side: only the two 2x40 Mimas sockets and the two 2x6 sub-board
  sockets.

**Keyboard sub-board** (34 x 47.8 mm, 2 layers, one design used twice):
x 86-120, y 90.8-138.6 for the P12-side board (`kbd-sub` coordinates); the
P13-side board is the same board moved by -139.4 mm in y. It sits on 3 mm
standoffs (3 holes) beside the Mimas, under the shield overhang. Its two J5
headers are centred under the JB1 above them. A 2x6 male header goes up
into a 2x6 8.5 mm socket on the shield's underside. The generator checks
that the pads line up (0.000 mm error).

| Sub-board | Slot A (lower y) | Slot B |
|---|---|---|
| P12 side | DUT0 | DUT3 |
| P13 side | DUT2 | DUT1 |

## Connectors and pinouts

### DUT JTAG/UART (MEGA65 JB1 / TE0790 pinout), 2x6 right-angle box header, on the shield, x4

| Pin | Signal | Pin | Signal |
|---|---|---|---|
| 1 | GND | 2 | GND |
| 3 | UART from DUT (MEGA65 TX) | 4 | TCK |
| 5 | n.c. (3.3 V on a TE0790) | 6 | VIO (10 k to expander B, 100 k pull-down) |
| 7 | UART to DUT (MEGA65 RX) | 8 | TDO |
| 9 | n.c. | 10 | TDI |
| 11 | n.c. | 12 | TMS |

All six signals have 47 ohm series resistors right behind the header.

### DUT keyboard (MEGA65 J5 pinout), 2x5 right-angle box header, on the sub-boards, x4

| Pin | Signal | Pin | Signal |
|---|---|---|---|
| 1 | GND | 2 | 3.3 V from the DUT (sense: 10 k on the sub-board, 100 k pull-down on the shield) |
| 3-7 | n.c. (no keyboard JTAG on DUT ports) | 8 | KIO8 (clock from DUT) |
| 9 | KIO9 (LED data from DUT) | 10 | KIO10 (key data to DUT) |

47 ohm series resistors on the sub-board.

### Sub-board link (2x6, 2.54 mm)

1, 2, 11, 12 GND. 3-6: slot A KIO8, KIO9, KIO10, KB sense. 7-10: slot B
KIO8, KIO9, KIO10, KB sense.

### Physical keyboard (master), 2x5 right-angle box header, shield front edge

J5 pinout with keyboard JTAG:

| Pin | Signal |
|---|---|
| 1 | GND |
| 2 | 3.3 V supply (VADJ through a 0.5 A polyfuse) |
| 3 | JTAGEN (expander B P0.3, 100 k pull-down) |
| 4 | TMS |
| 5 | TCK |
| 6 | TDI |
| 7 | TDO |
| 8 | KIO8 |
| 9 | KIO9 |
| 10 | KIO10 |

All signals have 33 ohm series resistors.

The owner moved the physical keyboard connector to the rear panel (round 4).
It stays at the shield's front edge, and a short straight 10-way ribbon runs
to a rear-panel IDC feed-through. Putting it on the rear edge would add
another 22 mm column on every shield (see the width table), and only the
master board needs it.

### HDMI inputs (DUT1..DUT3), type-A right angle, on the shield above the Mimas

Per input:
* 8 x 49.9 ohm to +3V3 at the receptacle;
* 2 x TPD4E05U06 (flow-through ESD);
* a PCA9306 DDC level shifter: FPGA side 4.7 k to 3.3 V, source side 47 k
  to the source's +5 V, VREF2/EN from +5 V through 200 k;
* HPD: expander B output -> 2N7002 -> AO3401A from the source's +5 V ->
  1 k -> pin 19 (100 k pull-down);
* +5V sense: 10 k / 15 k divider to expander B;
* CEC and the utility pin are unconnected.

The lane-to-pair mapping follows the pin plan. Any P/N swaps made while
routing must be reported for the `INVERT` generic.

### 12 V in, Molex Mini-Fit Jr 2-pin (5566-02A vertical), shield front

1 = +12 V, 2 = GND, from the power board (0047). It feeds rows 1-2 (both
columns) of **both** headers, the Mimas VIN: that point is after the DC
jack diode and before P2/S12/polyfuse (power-path note in issue 0045).
Also on this input: an SMBJ15A TVS, 2 x 10 uF, and the 5 V buck.

### Power control, 1x11 pin header, pin 2 removed (key): master shield only

| Pin | Signal |
|---|---|
| 1 | GND |
| 2 | key (pin pulled) |
| 3-10 | PWR_CTL0..7: expander A P2.0-7, active high, 20 k pull-downs (off at reset) |
| 11 | PRESENT: the power board pulls it to 3.3 V through 10 k when powered; 100 k pull-down here; **high = present**; read on expander B P0.7 |

### I2C (front panel, issue 0050), 1x6 right-angle header

1 GND, 2 +5 V (AP63205 12 -> 5 V buck, 2 A), 3 +3V3, 4 SDA, 5 SCL, 6 INT
(expander B INT, open drain, 10 k pull-up). The bus has 2.2 k pull-ups to
3.3 V on the shield. A 5 V PCF8574 LCD backpack needs SDA/SCL >= 3.5 V high,
so the front-panel board should level-shift (PCA9306) or use a 3.3 V-tolerant
expander.

### Neighbour UART, 1x3 Dupont header (ADR 0007)

1 GND, 2 TX, 3 RX, with 100 ohm series resistors. No 12 V pass-through
(owner round 5): each Mimas gets its own 12 V lead from the power board.

## I2C expanders (as in the pin plan)

* **A: TCA6424A @0x22.**
  * P0 = revision straps (rev A = 0x01).
  * P1 = feature straps: b0 HDMI1, b1 power header, b2 HDMI2, b3 HDMI3,
    b4 DUT2 ports, b5 DUT3 ports, b6 neighbour UART, b7 reserved.
  * P2 = PWR_CTL0..7.
  * Each strap bit has a pull-up and a pull-down footprint, and only one is
    fitted (the other is DNP in the schematic and BOM).
* **B: TCA6416A @0x20** (drawn with the pin-compatible PCAL6416A symbol).
  * P0.0-2 HDMIn_HPD_EN, P0.3 PK_JTAGEN, P0.4-6 HDMIn_5V_SENSE, P0.7 PWRB_PRESENT.
  * P1.0-3 DUTn_VIO_SENSE, P1.4-7 DUTn_KB_SENSE.

## BOM / JLCPCB

`out/bom-jlcpcb.csv` and `kbd-sub/out/bom-jlcpcb.csv` (columns: Comment,
Designator, Footprint, LCSC, MPN, Qty; DNP straps left out). Passives are
0402 JLC basic parts.

**All LCSC numbers were filled in from memory: check every one on lcsc.com
before ordering.** Lines marked `TBD` still need a part chosen:
* connectors: 2x40 and 2x6 sockets, box headers, HDMI receptacle, Mini-Fit
  Jr, pin headers;
* PCA9306DCUR, TCA6424ARGJR, TCA6416APWR, AP63205WU;
* the 4.7 uH inductor, SMBJ15A, polyfuses, 1206 10 uF/25 V, 0805 22 uF.

The through-hole sockets on the shield's underside can be hand-soldered by
JLC or fitted by us.

## Before fab (checklist)

1. Measure the Mimas on a real board: pin grid, holes, part heights under
   the shield, HDMI lip position. Check the stack: the J5 top against the
   JB1 tails (clip them).
2. **Check the TCA6424A pin numbers** in `lib/shield.kicad_sym` against TI
   SCPS193 (they were entered from memory of the RGJ pinout, including the
   exposed pad).
3. Route the boards:
   * TMDS as 100 ohm differential pairs on F.Cu over the In1 GND plane,
     with the terminations and ESD at the receptacle;
   * JB1 signals short and direct;
   * DDC, HPD and the keyboard lines are slow;
   * SMD power pins need vias to the planes.
4. Settle the open choices below, pick the LCSC parts, rerun `make`, and
   get ERC/DRC clean (silk warnings acceptable).

## Open choices for the owner

1. GS105 placement: it does not fit beside two shields (~388 mm + 94 mm).
   Put it in front of or behind the boards, or on the mezzanine.
2. Sub-boards: one per side carrying two J5 (used here: one design, fewer
   standoffs) or one per DUT.
3. JB1 tails over the J5 bodies: clip them, or use longer sub-board pins and
   drop the sub-boards 2.5 mm.
4. The HDMI receptacle part (the Amphenol 10029449 land pattern is used):
   pick an LCSC equivalent.
5. Physical keyboard: front edge plus a short ribbon to the rear panel
   (used here), or a fifth column on the rear edge (+22 mm per shield).
