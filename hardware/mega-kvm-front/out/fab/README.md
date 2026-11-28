# MEGA-KVM front panel: JLCPCB fabrication package

Issue 0050. Everything here except this README is written by `make pcb-fab`
(`hardware/mega-kvm-front/tools/fab.sh` + `tools/jlc_fab.py`) from the
committed KiCad files, which it only reads. Regenerate after any board change;
the target fails if DRC or ERC finds a problem.

## Board

| | |
|---|---|
| Size | 140.00 x 66.00 mm (rectangle), plus a 73 x 26 mm internal cutout for the LCD window (in Edge.Cuts) |
| Layers | 2 copper (F.Cu, B.Cu), GND pour on both sides |
| Thickness | 1.6 mm (board setup; nothing depends on it) |
| Finish | HASL lead-free recommended (no fine-pitch parts below 0.5 mm; ENIG optional) |
| Copper | 1 oz outer |
| Min track / clearance | 0.2 mm / 0.15 mm (rules allow 0.127 mm; JLC standard is 0.127/0.127 mm) |
| Min hole / via | 0.30 mm drill, 0.60 mm pad: standard JLC 2-layer capability |
| Holes | PTH: 0.30 x70 (vias), 0.90 x32 (LEDs), 1.00 x23 (headers), 1.10 x20 (switches). NPTH: 2.70 x4 (LCD M2.5), 3.20 x4 (M3 spacers). See `fab-summary.txt` |
| Mask / silk | Any colour; component side (F) faces the panel |
| Component sides | SMT all on top (F). THT: LEDs and switches on top; J1, J2, JP1 on the bottom (B); the LCD module mounts on the bottom |

## Files

| File | Use |
|---|---|
| `mega-kvm-front-gerbers.zip` | **Upload this** as the Gerber file: 9 Gerber layers (Protel extensions) + `-PTH.drl` / `-NPTH.drl` Excellon (mm, decimal, absolute) |
| `mega-kvm-front-bom-jlc.csv` | Assembly BOM (Comment, Designator, Footprint, LCSC Part #): the 33 SMT parts, 8 lines |
| `mega-kvm-front-cpl-jlc.csv` | Assembly CPL (Designator, Mid X, Mid Y, Layer, Rotation), rotation corrected |
| `mega-kvm-front-bom-jlc-with-tht.csv`, `-cpl-jlc-with-tht.csv` | The same plus the 24 THT parts, only for the optional JLC THT assembly |
| `mega-kvm-front-handfit.csv` | What JLC does not fit in the default order (THT and DNP), with LCSC numbers for buying them |
| `gerbers/`, `drill-map/` | Unzipped Gerbers for review; drill maps (not uploaded) |
| `drc.rpt`, `erc.rpt` | DRC (schematic parity) and ERC on the files the Gerbers come from: 0 / 0 |
| `drc-refilled.rpt` | Information only: DRC after KiCad refills the pours (see below) |
| `fab-summary.txt` | Board size, holes, counts, the rotation correction per package |

The older `out/mega-kvm-front-bom.csv` / `-cpl.csv` from `build_all.sh` are
overview files, **not** for ordering: they list the THT parts and the DNP J3,
use `LCSC` instead of `LCSC Part #`, and carry no rotation corrections.

## Who fits what

JLC places (economic or standard PCBA, top side only):

| Parts | LCSC | JLC class |
|---|---|---|
| C1-C4, C7 100 nF 0603 X7R 50 V (Yageo CC0603KRX7R9BB104) | C14663 | basic |
| C5, C6 10 uF 0603 X5R 10 V (Samsung CL10A106KP8NNNC) | C19702 | basic |
| R1-R8, R11-R18 470 R 0603 1 % (UNI-ROYAL 0603WAF4700T5E) | C23179 | basic |
| R21, R22 10 k 0603 1 % (UNI-ROYAL 0603WAF1002T5E) | C25804 | basic |
| R23 200 k 0603 1 % (UNI-ROYAL 0603WAF2003T5E) | C25811 | basic |
| RN1-RN4 4 x 10 k convex 0603 array (UNI-ROYAL 4D03WGJ0103T5E) | C29718 | basic |
| U1, U2 TI TCA9535PWR, TSSOP-24 | C130204 | extended |
| U3 TI PCA9306DCUR, VSSOP-8 (DCU) | C33196 | extended |

Hand-fit (default) or JLC THT assembly (option):

| Parts | LCSC |
|---|---|
| D1-D8 Everlight 204-10SDRD/S530-A3-L, 3 mm red diffused | C84774 |
| D11-D18 Everlight 204-10SYGD/S530-E3, 3 mm yellow-green | C85161 |
| SW1-SW5 HRO K2-1102DP-L4SW-04, 6x6 mm, 9.5 mm | C136679 |
| J1 1x6 2.54 mm header (bottom) | C37208 |
| J2 1x4 2.54 mm header (bottom) | C124378 |
| JP1 1x3 2.54 mm header (bottom) + a 2.54 mm jumper shunt (not in the BOM) | C49257 |
| J3 1x10 2.54 mm header: **DNP** | (C57369) |

The LEDs sit flush on the board with their lenses in the panel holes and the
switch stems must line up with the panel, so fitting them by hand against the
panel (or a drilled template) is the safer default.

## Rotation (check in JLC's placement preview)

CPL rotation = KiCad rotation + a per-package correction from the
JLCKicadTools community database (not JLC data): 0603 chips 0, R_Array_Convex
+90, TSSOP-24 +270, VSSOP-8 (DCU 2.3 x 2 mm) +180. **Check pin 1 of U1, U2, U3
and the orientation of RN1-RN4 in JLC's placement preview** before
confirming; fix any that are wrong there (JLC's engineers also review the
placement). The VSSOP-8 DCU rule is the least certain one.

## Pour refill note

The Gerbers use the copper pours as filled by `tools/pcb_build.py` and saved
in the board, which DRC checks (0 violations). KiCad's own refill (pressing B
in the GUI, or `--refill-zones`) gives one *starved thermal* on J2 pin 1
(GND, B.Cu): a small B.Cu island hangs off that pad. It is GND either way and
the pad is also connected on F.Cu, so it is not a fabrication problem, but
do not refill and save the board before ordering without re-running
`make pcb-fab`.

## Ordering options (JLCPCB)

* PCB: 2 layers, 140 x 66 mm, FR-4 1.6 mm, HASL lead-free, 1 oz, 5 pcs
  (minimum), any mask colour. "Remove order number": either pay for it or
  let JLC place the number (the F side faces the panel behind the LCD/LEDs, so
  a printed number is not visible from outside).
* Assembly (recommended): top side, Economic PCBA, 2 or 5 boards; upload
  `-bom-jlc.csv` and `-cpl-jlc.csv`. Extended parts (TCA9535PWR, PCA9306)
  cost a loading fee each.
* Assembly alternative: Standard PCBA with THT, using the `-with-tht` files
  (JLC then fits LEDs, switches and the bottom-side headers too; more cost,
  and LED height/alignment against the panel is then JLC's).
* Buy the THT parts from `-handfit.csv` with the order (LCSC) if hand-fitting.
