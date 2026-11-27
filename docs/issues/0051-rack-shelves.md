# 0051: Rack layout: a KVM unit plus one sliding shelf per MEGA65

Status: open (owner request 2026-11-27). Supersedes case options A and B in
0048. The Cisco carcass is dropped for now.

## Request (owner, 2026-11-27)

* Laser-cut plywood in a full-height 19 inch rack. Prototype in MDF; final
  in 3 mm ply (6 mm where needed). No metal CNC available.
* Airflow mostly front to rear; large, quiet fans on the front or the rear.
* **KVM unit**: as tall as cheap quiet PC case fans need (~3RU). The display
  group is a solid strip and the rest of the front stays open for air.
* **Power inputs on the front or rear panel, leaning front**: easy to unplug
  when the drawer slides out, or if something is about to catch fire.
* **Each MEGA65 on its own sliding shelf** on rack rails (the owner has a
  pile of old server rails). Each shelf is a 3 or 6 mm ply sheet with beading
  rails along the edges to fix the rail inner members. About 1RU per shelf;
  "1RU - 3 mm should be thick enough for a MEGA65 board and whatever else".
  Up to about **11RU** in all (KVM 3RU + 8 x 1RU shelves).
* Each shelf deck has the **MEGA65 case boss holes** (board, floppy drive,
  official expansions) and about **100 mm free behind the board** for a
  cartridge or peripherals on stand-offs. Include the holes for the
  **Cart64out Rev.1** C64 expansion-port breakout (svenpetersen1965).
* Cut-outs to pass cables down where direct JTAG adaptors are not used.
* Separate shelves mean that most DUTs will use **USB JTAG** (signal
  integrity over length). The octopus JTAG must still be supported, with a
  probe for the maximum safe TCK (issue 0054). dutctl gets per-DUT JTAG
  configuration and USB adaptor discovery (issue 0053).
* Fans: 12 V PWM control and up to 8 fan headers with small protection on the
  power board (issue 0052).
* The owner will supply MEGA65 PCB and case drawings (or photos with a ruler).

## Is plywood dangerous? (lead's assessment, 2026-11-27)

Low risk, as long as these hold:

1. **No mains inside the wood.** Use a closed, certified 12 V supply (an ATX
   PSU or a metal-cased brick) outside the shelves or in its own metal case.
   Only fused 12 V enters the plywood. This removes most of the real risk.
2. **Every 12 V path is fused where it enters** (already true: input fuses
   per connector on the input board, 5 A eFuses per DUT, the 5 A always-on
   group). The weak spot is the cable between the PSU and our fuse: an ATX
   12 V rail can deliver 40 A or more into a fault before its OCP trips. Use
   connector-rated cables (PCIe 8-pin and Molex are fine) and no
   home-made thin leads on that side.
3. **Heat sources stand off the wood**: the power boards on ≥ 5 mm stand-offs
   with an air gap, nothing above 60-70 °C touching ply (ply chars well above
   200 °C; normal electronics never get near that). The input FETs reach
   about +35-60 K over ambient at 20 A (0047), so they need air gaps, not
   insulation.
4. **Screw terminals are the most likely hot joint**: use bootlace ferrules on
   the DUT leads and re-torque once after a few days. Stranded wire clamped
   bare in a screw terminal loosens.
5. **Dust**: open front and rear plus fans pull dust in. Fit a filter on the
   intake side and clean it. Dust on hot parts is the usual cause of wooden
   electronics enclosures getting scorched.
6. Optional: a temperature sensor on the power main board, read over its I2C
   (next to the fan controller, 0052), lets the supervisor switch the DUTs
   off on over-temperature. Cheap insurance; proposed for 0052.

The rack itself is steel, which contains a fire better than an open bench.
A front-panel power inlet plus the master rocker gives a fast way to kill
everything.

## Numbers that shape the design

| Item | Value | Note |
|---|---|---|
| 1RU / 2RU / 3RU | 44.45 / 88.9 / 133.35 mm | shelves stack with no gap |
| Fan in 2RU | 80 mm max | 88.9 - two 3 mm decks leaves ~83 mm |
| Fan in 3RU | **120 mm** | ~127 mm free; 120 mm fans are the quietest common size (100 mm fans are rare) |
| Width between the rack posts | 450 mm (17.75 in) | rail slides take ~12-13 mm per side, so the shelf body is about 425-430 mm; depends on the rail model |
| 1RU shelf clear height | ~44.45 - 3 (deck) - ~1 (clearance) ≈ 40 mm | beading and rail sit beside the deck, not under it |
| MEGA65 depth + 100 mm rear space | TBD + 100 mm | owner to supply MEGA65 PCB drawings |
| Cart64out Rev.1 board | 86 x 62 mm, plus the 11 mm card-edge tongue (J1) | from `Rev. 1/Eagle/Cart64out_v1_noFrame.brd` |
| Cart64out Rev.1 holes | 4 x Ø3.3 mm at (16, 4), (16, 58), (71, 4), (71, 58) mm | Eagle board coordinates: a 55 x 54 mm rectangle. Check against `Rev. 1/dxf/Cart64out_v1.dxf` before cutting |

## Critique and open points

1. **Cartridge height vs 1RU.** As I understand it, the MEGA65's expansion port
   faces up, so a cartridge stands vertically, and a Cart64out plugged
   directly in stands about 62 mm plus the cartridge. Neither fits in 40 mm.
   Options:
   * (a) an expansion-port extension cable (Sven also has a
     *C64-Expansion-Port-Extension* design) to a Cart64out lying flat in the
     100 mm rear area; the cartridge in its J3 still stands up, so that
     shelf needs 2-3RU;
   * (b) a **per-shelf pitch parameter** (1, 2 or 3RU), with taller shelves
     for the DUTs that carry cartridges. Proposed: (b), with (a) as the
     mounting style.
2. **Cable service loops.** A shelf sliding out 500-700 mm drags its HDMI,
   power lead, keyboard ribbon and USB JTAG cable. Either the shelf is
   unplugged before sliding (simple), or every cable needs ~700 mm of slack
   in a loop at the rear, with a strain-relief bar on the shelf. HDMI and
   ribbons flexed every time wear out; Mini-Fit/barrel plugs pulled loose
   are a fire risk (point 4 above). Proposed: a rear strain-relief bar per
   shelf, cable loops sized for full extension, and a "shelf out = DUT off"
   habit, since the supervisor can switch DUT power remotely anyway.
3. **3 mm ply deck stiffness.** A 425 mm span carried only at the edges bends
   when a floppy drive and a cartridge are fitted and a hand pushes on it.
   The edge beading stiffens the sides only. Add a front and a rear batten
   (a closed frame), or use 6 mm. Fix boards with M3 bolts and nuts or
   bolted-through brass stand-offs, not wood screws into 3 mm ply.
4. **Old server rails differ** in length, inner-member hole pattern and
   height. The shelf generator takes the rail as a parameter set (inner
   member length, hole positions, height, side clearance). Please measure
   the rail models you plan to use (or photograph them with a ruler).
5. **Shelf cooling.** MEGA65 boards are passive in their own closed case, so
   open shelves are no worse. But a horizontal board 1RU under the next
   deck traps its heat (convection is blocked). A small front-to-rear
   flow fixes it. Either the KVM's fans are the only ones (then the
   shelves rely on room airflow), or some of the 8 fan headers (0052) drive
   a fan per shelf or a fan wall at the rear of the rack. **Question below.**
6. **USB JTAG count.** 8 DUT adaptors (TE0790 or similar) plus 2 Mimas
   FTDI = 10 USB devices. They need a powered USB hub on the rack. It could
   run from an always-on 12 V output if the hub takes 12 V; otherwise it
   needs its own supply. The hub's place goes in the layout.
7. **Keyboard emulation ribbons to the shelves.** The MK-I protocol from the
   Mimas J5 headers to each DUT is slow and should be fine over 0.5-1.5 m of
   ribbon. Verify once on the longest run (the hwtest keyboard check covers
   it).
8. **Front power inputs.** The 197 x 34 mm input board (0047) fits on the
   3RU front beside the display group. The 3RU front has 133 mm of height,
   so the display strip, the input board and a 120 mm fan grille sit side by
   side. The DUT leads, HDMI and ribbons stay at the rear.

## Questions for the owner

* Q1: 3RU KVM with 120 mm fans (recommended), or 2RU with 80 mm fans?
* Q2: does the KVM unit also slide on rails, or bolt to the rack posts with
  ply rack ears (6 mm minimum, best with a steel angle behind)?
* Q3: are the 8 fan headers for the KVM only, or also for shelf fans or a
  rear fan wall?
* Q4: how many shelves need cartridge height (2-3RU)?
* Q5: unplug before sliding, or full-extension cable loops?
* Q6: rail measurements, MEGA65 PCB/case drawings (owner chasing).

## Plan

* Retarget the case generator (`hardware/mega-kvm-case`) as
  `rack` output: KVM unit (3RU), shelf generator (pitch, rail model, MEGA65
  boss set, rear area with Cart64out holes, cable cut-outs, strain-relief
  bar), all as sub-SVGs on 600 x 900 sheets. Keep options A/B in the tree
  but no longer develop them.
* The KVM unit reuses the shield, keyboard sub-boards, power boards and front
  panel unchanged.
