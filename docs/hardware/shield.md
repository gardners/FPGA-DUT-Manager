# MEGA-KVM link-board shield (rev A draft)

Issue 0045, ADR 0007 (links between boards), pin plan
`docs/hardware/shield-pinplan.md` v1 (branch `feature/shield-pinplan`,
issue 0049). KiCad project: `hardware/mega-kvm-shield/`.

Status: **schematic complete (ERC clean), connectors placed, not routed.**
Not ready for fabrication: see "Before fab" and "Open choices" below.

## How the project is built

The KiCad files are **generated**; edit the scripts, not the schematic:

| File | What |
|---|---|
| `scripts/design.py` | the circuit as data: header pin plan, every part (symbol, footprint, LCSC number, pin -> net) |
| `scripts/gen_sch.py` | writes the root sheet + 6 sub-sheets, `lib/shield.kicad_sym`, `out/netlist.json`, `out/bom-jlcpcb.csv` |
| `scripts/gen_fp.py` | `lib/shield.pretty/Mimas_Header_Socket_2x40` (pads `A1..A40`, `B1..B40`) |
| `scripts/gen_pcb.py` | the board (run inside the KiCad flatpak, uses pcbnew) |
| `Makefile` | `make` = sch + pcb + ERC + DRC + exports into `out/` |

Outputs in `hardware/mega-kvm-shield/out/`: `mega-kvm-shield-schematic.pdf`,
`mega-kvm-shield-top.png`, `-bottom.png`, `-3d.png`, `mega-kvm-shield-top.svg`,
`bom-jlcpcb.csv`, `erc.rpt`, `drc.rpt`, `placement.json`.

Once the board gets routed by hand in KiCad, stop regenerating the PCB
(`make sch erc` stays safe; `gen_pcb.py` would overwrite the routing).

## Mechanics

All positions in "Mimas coordinates": origin at the Mimas board's corner
between the RJ45 edge and the P13 edge, x towards the HDMI edge, y towards
P12 (Numato V3 drawing). Taken from the Numato drawing (`MimasA7V3.0-pd.png`);
**check with calipers on a real board before fab**.

| Item | Position |
|---|---|
| Mimas board | 120 x 90 mm |
| Header row 1 centre | x = 10.41 (header body starts at 9.14); row n at 10.41 + (n-1) x 2.54 |
| P12 | column A y = 86.19, column B y = 88.73 (B on the outer edge) |
| P13 | column A y = 1.27, column B y = 3.81 (A on the outer edge) |
| Mimas holes (3.2 mm) | (5.00, 84.86), (115.0, 85.0), (4.83, 5.00), (115.0, 5.00) |
| Rear (HDMI) edge | x = 120: HDMI IN y 63.8-78.8, HDMI OUT 42.4-57.4, mDP 25.9-37.3 / 9.6-21.0 |
| Front (RJ45) edge | x = 0: RJ45 y 60.8-76.6, USB-B 40.8-52.8, S12 30.6-37.2, P2 25.2-27.7, DC jack 13.4-22.4 |

Shield:

* **Outline 120 x 279.6 mm** (Mimas y -118.7 .. 160.9): the shield overhangs
  the Mimas on both long sides; the rear edge is flush with the Mimas HDMI
  edge (HDMI receptacle lips 1.5 mm proud, like the Mimas's own).
* Cut-out x 0-18, y 12.4-77.6 over the RJ45, USB-B, power switch S12, P2
  power-select jumper and DC jack (all stay reachable).
* 8 x 3.2 mm holes: the 4 Mimas holes (M3 standoffs, 11 mm) and 4 support
  holes in the overhangs (standoffs to the case floor; the overhangs carry
  connectors that get plugged and unplugged).
* Stack height: 8.5 mm female sockets on the Mimas's male headers put the
  shield's underside about 11 mm above the Mimas top. The shield has no
  parts on its underside except the two sockets. Parts on the Mimas under
  the shield must stay below 11 mm (the tall ones, RJ45/USB-B/DC jack, are
  in the cut-out).
* 4 layers: F.Cu signals, In1 GND plane, In2 +3V3 plane, B.Cu signals/12 V.

### Rear edge (DUT side), from the P12 side to the P13 side

| Mimas y | Connector | Notes |
|---|---|---|
| 137.4 .. 159.4 | DUT3 KEYBOARD (J5) | overhang |
| 112.2 .. 136.8 | DUT3 JTAG/UART (JB1) | overhang |
| 90.6 .. 111.6 | DUT3 HDMI IN | overhang (HDMI3 is on P12) |
| (81.2 .. 88.8) | Mimas hole (115, 85) | screw head keep-out |
| 56.6 .. 81.2 | DUT0 JTAG/UART | above the Mimas HDMI IN (DUT0 video) |
| 34.0 .. 56.0 | DUT0 KEYBOARD | above the Mimas HDMI OUT |
| 12.4 .. 33.4 | DUT1 HDMI IN | above the mDP connectors |
| (1.2 .. 8.8) | Mimas hole (115, 5) | |
| -25.2 .. -0.6 | DUT1 JTAG/UART | overhang |
| -47.8 .. -25.8 | DUT1 KEYBOARD | overhang |
| -69.4 .. -48.4 | DUT2 HDMI IN | overhang (HDMI2 is on P13) |
| -94.6 .. -70.0 | DUT2 JTAG/UART | overhang |
| -117.2 .. -95.2 | DUT2 KEYBOARD | overhang |

The rear panel then has two bands: the Mimas's own HDMI IN/OUT low down,
the shield's connectors about 12 mm higher. Slot widths allow for the
plugs: HDMI 21 mm (overmoulded plug), 2x6 box header 24.6 mm, 2x5 22 mm.

### Front edge and sides

* Physical keyboard (J5 + JTAG, 2x5 box header, right angle) at the front
  edge in the P12 overhang, with the I2C header next to it. The owner moved
  the physical keyboard to the **rear panel** (round 4): it stays at the
  shield's front edge and a short straight 10-way ribbon takes it to a
  rear-panel IDC feed-through, because the rear edge is already full (one
  more slot = +22 mm on an already too wide board, see open choice 1).
  It is only needed on the master board.
* 12 V in (JST VH 2-pin) and the keyed power-control header (1x11) at the
  front of the P13 overhang, towards the power board.
* Link A (P12-side edge): 1x4 right-angle socket + 1x3 header. Link B
  (P13-side edge): 1x4 right-angle pin header + 1x3 header.

## Connectors and pinouts

### DUT JTAG/UART (JB1 / TE0790 pinout), 2x6 box header, x4

| Pin | Signal | Pin | Signal |
|---|---|---|---|
| 1 | GND | 2 | GND |
| 3 | UART from DUT (MEGA65 TX) | 4 | TCK |
| 5 | n.c. (3.3 V on a TE0790) | 6 | VIO (sense via 10 k to expander B) |
| 7 | UART to DUT (MEGA65 RX) | 8 | TDO |
| 9 | n.c. | 10 | TDI |
| 11 | n.c. | 12 | TMS |

47 ohm series resistors on all six signals; VIO through 10 k with 100 k
pull-down to expander B (`DUTn_VIO_SENSE`). A straight 12-way ribbon goes
to the MEGA65's JB1 (TE0790 removed).

### DUT keyboard (MEGA65 J5 pinout), 2x5 box header, x4

| Pin | Signal | Pin | Signal |
|---|---|---|---|
| 1 | GND | 2 | 3.3 V from the DUT (sense, 10 k to expander B) |
| 3-7 | n.c. (no keyboard JTAG on DUT ports) | 8 | KIO8 (clock from DUT) |
| 9 | KIO9 (LED data from DUT) | 10 | KIO10 (key data to DUT) |

47 ohm series on KIO8/9/10. Straight 10-way ribbon to the MEGA65's J5.

### Physical keyboard, 2x5 box header (master only)

J5 pinout with keyboard JTAG: 1 GND, 2 3.3 V **supply** (from VADJ through a
0.5 A polyfuse), 3 JTAGEN (expander B P0.3, 100 k pull-down), 4 TMS, 5 TCK,
6 TDI, 7 TDO, 8 KIO8, 9 KIO9, 10 KIO10; 33 ohm series on all signals.

### HDMI inputs (DUT1..DUT3), type-A right angle

Per input: 8 x 49.9 ohm to +3V3 at the receptacle; 2 x TPD4E05U06
(flow-through ESD); PCA9306 DDC level shifter (FPGA side 4.7 k to 3.3 V,
source side 47 k to the source's +5 V, VREF2/EN from +5 V through 200 k);
HPD: expander B output -> 2N7002 -> AO3401A from the source's +5 V -> 1 k
-> pin 19 (100 k pull-down); +5V sense 10 k / 15 k to expander B. CEC and
utility pins unconnected. Lane-to-pair mapping as in the pin plan; P/N
swaps made during routing must be reported for the `INVERT` generic.

### 12 V in, JST VH 2-pin

1 = +12 V, 2 = GND, from the power board's always-on output (0047).
Feeds rows 1-2 (both columns) of **both** headers (Mimas VIN, after the DC
jack diode, before P2/S12/polyfuse: issue 0045 power-path note), an SMBJ15A
TVS and 2 x 10 uF, and the two link connectors through 2 A polyfuses.

### Power control, 1x11 pin header, pin 2 removed (key)

| Pin | Signal |
|---|---|
| 1 | GND |
| 2 | key (pin pulled, plug the matching socket hole) |
| 3-10 | PWR_CTL0..7: expander A P2.0-7, active high, 20 k pull-downs |
| 11 | PWRB_PRESENT_N: 10 k pull-up on the shield, the power board ties it to GND; read on expander B P0.7 |

### I2C (front panel, issue 0050), 1x5 right-angle header

1 GND, 2 +3V3, 3 SDA, 4 SCL, 5 INT (expander B INT, open drain, 10 k
pull-up; the front panel may also pull it low). 2.2 k bus pull-ups on the
shield. Note: many 16x2 I2C LCD backpacks want 5 V; the front panel board
needs to cope with 3.3 V (or the shield gets a 5 V option, open choice).

### Neighbour link

1x3 header: 1 GND, 2 TX, 3 RX. 1x4 right angle: side A (socket) 1 12V,
2 TX, 3 RX, 4 GND; side B (pins) 1 12V, 2 RX, 3 TX, 4 GND. ADR 0007.

## I2C expanders (as in the pin plan)

* **A: TCA6424A @0x22.** P0 = revision straps (rev A = 0x01), P1 = feature
  straps (b0 HDMI1, b1 power header, b2 HDMI2, b3 HDMI3, b4 DUT2 ports,
  b5 DUT3 ports, b6 neighbour UART, b7 reserved), P2 = PWR_CTL0..7. Each
  strap bit has a pull-up and a pull-down footprint; exactly one is
  fitted (the other is DNP in the schematic and the BOM).
* **B: TCA6416A @0x20.** P0.0-2 HDMIn_HPD_EN, P0.3 PK_JTAGEN, P0.4-6
  HDMIn_5V_SENSE, P0.7 PWRB_PRESENT_N; P1.0-3 DUTn_VIO_SENSE, P1.4-7
  DUTn_KB_SENSE.
* Both RESET pins share a 10 k pull-up; INT pins have 10 k pull-ups and
  are not wired to the FPGA (pin plan).

## BOM / JLCPCB

`out/bom-jlcpcb.csv` (Comment, Designator, Footprint, LCSC, MPN, Qty;
DNP straps excluded). Passives are 0402 JLC basic parts. **All LCSC
numbers were filled in from memory and must be checked on lcsc.com before
ordering**; lines marked `TBD` still need a part chosen: connectors (2x40
sockets, box headers, HDMI receptacle, JST VH, pin headers), PCA9306DCUR,
TCA6424ARGJR, TCA6416APWR, SMBJ15A, polyfuses, 1206 10 uF/25 V. The 2x40
sockets are through-hole on the bottom side: JLC can hand-solder them, or
fit them ourselves.

## Before fab (checklist)

1. Check the Mimas dimensions above on a real board (header pitch line,
   hole positions, height of parts under the shield, HDMI lip position).
2. **TCA6424A pin numbers** in `lib/shield.kicad_sym` were entered from
   memory of the RGJ pinout: check against TI SCPS193 (and the exposed pad).
3. Route: TMDS as 100 ohm differential pairs on F.Cu over the In1 GND
   plane, terminations and ESD at the receptacle, short stubs; DDC/HPD and
   the DUT signals are slow. SMD power pins need vias to the planes.
4. Choose the open items below, pick LCSC parts, rerun `make`, ERC/DRC
   clean (silk warnings acceptable).

## Open choices for the owner

1. **Width.** One row of rear connectors for 4 DUTs (3 HDMI + 4 JB1 + 4 J5)
   needs ~280 mm of edge; two shields side by side need ~560 mm, more than
   a 19-inch rack (~430 mm inside). Options:
   * a **rear connector board**: a vertical PCB on the rear panel with the
     connectors in a 2-3 row grid (JB1 row, J5 row, HDMI row), joined to
     the shield by a right-angle board-to-board header; ~110-125 mm per
     Mimas, so two fit with room for the GS105;
   * 3 DUTs per board (drop DUT2 or DUT3 slots): ~210 mm per shield, still
     too wide for two;
   * a 2U case with connectors on two shield levels; or one Mimas per 1U.
   This draft keeps the single row so the electrical design can be
   reviewed; the slots are generated, so moving to a rear board changes
   only `gen_pcb.py` and adds a connector between the boards.
2. Box headers (keyed, used here) vs unshrouded right-angle headers: barely
   narrower, because the IDC plugs set the spacing.
3. HDMI receptacle part (Amphenol 10029449 footprint used; pick an LCSC
   equivalent with the same land pattern).
4. 12 V input connector (JST VH used; alternatives: Molex Mini-Fit, screw
   terminal) and whether the link's 12 V pass-through is wanted at all.
5. I2C header supply for the front panel: 3.3 V only, or add 5 V.
6. Neighbour link connector family (2.54 mm right-angle socket/pins used).
