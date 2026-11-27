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

## 2026-11-27 owner answers (round 10)

* **Cartridges:** the MEGA65 cartridge port is **horizontal**, so cartridges
  and the Cart64out lie flat in the 100 mm rear space. 1RU is the normal
  pitch; taller gaps are a rack re-arrangement only. No pitch parameter
  needed beyond the 1RU default.
* **Cables:** **cable loops** with enough length for full extension (the
  owner's default). Simple mitigations are welcome: a rear strain-relief bar
  or tie point per shelf.
* **Deck: 6 mm ply**, 1RU pitch. **Edges: 25 x 25 mm timber battens** down
  both sides, which the slider rails screw to (the rails are a hodge-podge,
  so no rail-specific hole patterns).
* **Shelf cooling:** MEGA65s make very little heat (no FPGA heatsink). Later.
* **USB hub:** outside this project's scope, but agreed it is needed.
* **KVM unit: 3RU, on slide rails** (no ply rack ears). A **vertical 3RU front
  panel** carries the LCD and front-panel PCB, **two 120 mm fans**, the power
  input board and the rocker. It is the part that holds the front together.
  Etched artwork: the MEGA65 and M.E.G.A. e.V. logos plus the MEGA-KVM
  marking.
* **Shelf fan plates:** a MEGA65 shelf can carry a **1RU-4RU tall front plate**
  with fan holes. In practice one shelf in each group of 4 carries a 4RU
  plate with **3 x 120 mm fans, staggered in height** (a 120 mm fan is less
  than 4RU = 177.8 mm, so staggering spreads the airflow over all four
  shelves). To reach the other three shelves of the group, pull that drawer
  out first. The plate also gives the rack a front.
* Fan count: 2 (KVM) + 2 x 3 (two shelf groups) = **8**, matching the 8
  headers in 0052. The shelf fans run on leads through the cable loops.

### Consequences (lead)

* **Height budget:** next deck bottom is 44.45 - 6 = **38.45 mm** above this
  deck's top in the middle. Along each edge the next shelf's battens take
  25 mm, leaving ~13 mm. Tall parts (floppy drive ~26 mm, DB9 stacks) keep
  clear of the 25 mm edge strips.
* **Width budget:** ~450 mm between the rack posts, minus ~12-13 mm per slide,
  gives a ~425 mm deck. Full height (38 mm) is only available **between the
  battens: ~375 mm**. Whether the MEGA65 board and the floppy fit side by
  side in that width depends on the MEGA65 drawings. If not, the floppy goes
  in front of or behind the board.
* **Fan plate geometry:** the plate is 6 mm ply, bolted to the front edge of
  its shelf with two gussets (it is a cantilever 4RU tall carrying ~0.5 kg of
  fans). It can be **482.6 mm wide** (full 19 inch face, sitting in front of
  the rack posts, which also acts as the drawer stop). The other three shelves
  of the group stop ~35 mm short at the front (6 mm plate + 25 mm fan +
  clearance), so the plate clears them. Fan holes: 3 x 120 mm on 105 mm
  hole spacing, ~390 mm total width, alternating high/low (for example
  centres at 1.3RU and 2.7RU from the plate bottom). Finger guards are
  etched/cut grilles in the ply, or wire guards.
* **KVM front panel:** 3RU x 482.6 mm, carrying:
  * the display group (LCD, LEDs, buttons, rocker);
  * the 197 x 34 mm input board;
  * 2 x 120 mm fan cut-outs;
  * the logos.

  The KVM's other parts are the 6 mm deck with battens, the Mimas/shield
  bays, the power main board and the GS105, plus a rear plate for HDMI, DUT
  ribbons and Ethernet.
* **Logos:** official vector artwork is needed (not redrawn from memory). The
  owner supplies SVGs of the MEGA65 and M.E.G.A. e.V. logos. They are
  converted to single-colour etch layers (black) by the generator.

## 2026-11-27 owner answers (round 11)

* **Battens go under the deck**, not on top. The deck top stays flat full
  width; low parts may run over the edge strips. Tall parts still keep
  clear of the strip under the next shelf's battens (care needed).
* **All shelves use the same deck**, with cut-outs that clear the fan bodies
  of a fan plate. The fan plate screws into the front ends of its shelf's
  battens (with gussets). Alternatively the other three shelves of a group
  are simply set back on their rails for clearance. Either works ("many
  peelers, one cat"). The generator supports both: fan notches in the
  common deck plus a set-back parameter.
* **The KVM sits in the middle** of the stack (4 shelves, KVM, 4 shelves) to
  minimise cable lengths.
* The owner organises the logos (SVG) and the MEGA65 PCB/case drawings.
* Owner-facing blockers are tracked in `docs/OWNER-TODO.md`.

## 2026-11-27 progress: rack case generator (agent, branch feature/rack-case)

* `hardware/mega-kvm-case` now generates the rack layout (`out/rack/`,
  `out/fit-report.md`; write-up in `docs/hardware/case.md`). Options A/B
  still build (`out/fit-report-options-AB.md`).
* Parts (6 mm ply, nested on 3 sheets of 900 x 600): common shelf deck
  425 x 253 (x8), strain-relief bar (x8), 4RU fan plate with 3 x 120 mm fans
  staggered low/high/low (x2), fan gussets (x4), KVM front / deck / rear
  plate and 4 KVM gussets. Rack elevation (front + side, cable-loop zone)
  and a KVM top view.
* MEGA65 data (lead message, owner's sources): r6 board 214 x 118 mm, 6
  holes from the Trenz drawing `DIM-TE0765-06.PDF`, agreeing with
  `mega65-rugged-case` lower-deck3 within 0.8 mm; floppy hole pattern
  70 x 94 from lower-deck2; Cart64out holes from its Eagle board, identical
  in the DXF (outline 97 x 62 including a 12 mm tongue; the body is 85 mm, not 86).
  The Cart64out insertion depth comes from the rugged case's breakout support
  hole. All in `mega65_footprint.py`, with sources noted there.
* Fan clearance: with 3 fans at 125 mm pitch the notches merge into one
  28 mm deep notch (x 26.5-398.5) on every deck. The gussets (36 x 90 mm)
  stand on the carrier deck over the battens, so in notch mode the
  battens of the other three shelves of each group start 92 mm behind the
  deck front. `SHELF['fan_clearance']='setback'` is the alternative
  (minimum set-back 92 mm with these gussets).
* **Conflict for the owner:** 2 x 120 mm KVM fans do not fit beside the
  227 mm display PCB and the 197 mm input board (about 480 mm needed behind a
  425 mm deck). Default 2 x 92 mm (fits, keeps the 8 fan headers); 1 x 120 mm
  also fits.
* MEGA65 logo etched from `assets/mega65.svg` (copied to
  `hardware/mega-kvm-case/logos/`); the M.E.G.A. e.V. slot is a placeholder in
  the hidden reference layer until `logos/mega-ev.svg` exists.

## 2026-11-27 progress: KVM front for the 126 x 64 mm input board (agent, branch feature/rack-case-2)

* On foundation, the v0.3 input board (126 x 64 mm, was 197 x 34) collided
  with the display PCB. New KVM front layout: 2 x 92 mm fans on the left.
  The right-hand 227 mm column has the display PCB at the top (z 94.4-130.4,
  3 mm from the panel top) and the input board stacked under it (z
  26.4-90.4, 4 mm gap). The input board drops 4.6 mm below the deck top into
  a 33 mm deep notch in the KVM deck (x 191-321, between the under-deck
  gussets). The rocker and the MEGA-KVM etch (9.5 mm letters) sit to its
  right. The right-hand logo slot in the band below is shortened to clear
  the input board. Fit report: 0 conflicts.
* 2 x 120 mm fans: still no. The limit is now the 227 mm display PCB
  (about 480 mm needed in a 425 mm deck). They would fit with a display
  board of at most 172 mm wide, with the input board stacked under it as now.
* Finding for the power board: LEDs D7-D9 on the input board are less than a
  1.5 mm web from the PCIe/Molex panel cut-outs, so the panel gives them no
  separate window (they show at the cut-out edges). Moving them about 3 mm
  down would give them their own windows. The generator now also cuts the
  board's third mounting hole (H3), and labels the stacked banana pair
  under the 0V socket.

## 2026-11-27 owner round 12: no input board on the KVM front

The power inputs move onto the power main board (0047 round 12) and are
reached from the open top. The KVM front panel loses the input-board
cut-outs and keeps the display group, the rocker, the fans and the etching.
The main board goes at the front of the KVM deck.

## 2026-11-27 progress: KVM re-fit for the single power board (agent, branch feature/rack-case-3)

* The KVM front has no power cut-outs any more (owner round 12): fans on
  the left (2 x 92 mm, unchanged), the display PCB at the top right, the
  master rocker under it, and the MEGA-KVM etch (10 mm) beside the rocker.
  The deck notch for the old input board is gone.
* The 230 x 138.5 mm power board is read from its KiCad file. It lies at
  the front of the KVM deck: x 25-255 (its corner holes clear the left
  batten), front edge 40 mm behind the front panel. A checked 40 mm free
  height sits above its front 25 mm strip for the input plugs from the
  open top, with 55.8 mm left to the next unit above. The GS105 is beside
  it (x 263-357). The bays sit at the rear right, and the bulkhead/DUT-power
  column at the rear left (rear plate seen from the rear: bays left, column
  right), directly behind the DUT terminals. Cable routes (DUT leads across
  a 15 mm gap and along the left strip, Mimas Mini-Fit leads, GS105 jack)
  are drawn in the KVM top view. Tie-slot pairs hold the DUT bundle.
* Deck depth 349 mm (was 291): 40 + 138.5 + 15 + 35 RJ45 patch + 120
  Mimas. That still leaves about 250 mm for the cable loops in a 600 mm rack
  (rack depth to be measured).
* 2 x 120 mm fans: still no. The display PCB alone limits it (about 480 mm
  needed in 425 mm; it would work with a display board of at most 172 mm).
* New check: deck holes over a batten. The power board avoids them. The
  381 mm of bays are wider than the 375 mm between the battens, so three outer
  bay holes land on the right batten: drill through, M3 x 40 (noted in the
  report). Fit report: 0 conflicts.

## 2026-11-27 owner: 120 mm fans

Owner: "92mm fans? I thought we were using cheap and easily available 120mm
ones? Whatever the common standard PC ones are." The KVM front gets **2 x
standard 120 mm PC fans** (120 x 120 x 25, 105 mm pitch).

Plan (agent, branch `feature/front-2row`): the display PCB (0050) is
re-laid out in two rows, about 140 mm wide, so that it fits beside the two
fans. `KVM` in config.py: `'fan': 120, 'fan_count': 2`; the display board
size comes from panel-holes.json as before. 120 mm fans are taller than the
space above the KVM deck, so they reach down through notches in the deck
front, between the battens and clear of the front gussets; the logos and
the MEGA-KVM etch move into the right-hand column with the display and the
rocker. Fit report must stay at "Conflicts / problems: none".

## 2026-11-27 progress: 2 x 120 mm KVM fans (agent, branch feature/front-2row)

* `KVM`: `'fan': 120, 'fan_count': 2`. The display PCB (now 140 x 66 mm,
  read from panel-holes.json) leaves room: fans x 33-274, display x 280-420
  (421 of 425 mm).
* 3RU panel layout (front view, deck x): master rocker at x 19 (in the strip
  left of the fans, at the fans' centre height, `rocker_pos: 'left'`), fans
  z 10.4-130.4, display PCB top right (z 64.4-130.4), the MEGA-KVM etch
  (10 mm) under it, then the MEGA65 logo (x 278-388, z 26-47) and the
  M.E.G.A. e.V. slot (z 2-23, still a placeholder: no logos/mega-ev.svg).
  New check: every etch is tested against the fans, PCB, rocker and screw
  holes.
* The fans reach 20.6 mm below the deck top through one notch in the deck
  front (x 32-275, 28 mm deep), 2 mm clear of the front gussets and battens
  (new check of the fan bodies against the under-deck parts). Fan bodies end
  25 mm behind the panel; the power board starts at 40 mm.
* Fit report: **Conflicts / problems: none**. The old 2 x 92 mm layout
  (`'fan': 92, 'rocker_pos': 'below_pcb'`, logos 'left'/'right') still builds.

## 2026-11-27 owner answers (round 13)

1. **M.E.G.A. e.V. logo**: use
   https://www.m-e-g-a.org/wp-content/uploads/2012/06/mlogo.png (owner: not
   really a PNG despite the name). Convert to a clean vector
   `logos/mega-ev.svg` for laser etching; use it on the KVM front and the fan
   plates instead of the placeholder.
2. **MEGA65 tallest part**: assume the IEC serial (6-pin DIN) socket is the
   tallest part. Find its height in the MEGA65 PCB sources (else a standard
   right-angle DIN socket, stated as assumed); check it, and the other tall
   connectors, against the next shelf's battens (13.45 mm above the deck)
   as well as the 38.45 mm between the decks. The drawers have no top: the
   next shelf's deck/battens are effectively the top.
3. **Rails**: assume standard server slides, ~12.7 mm (1/2 in) per side,
   ASSUMED until the owner measures them.
4. **Fan plate clearance**: **set-back mode**: the other shelves of a group
   are mounted further back on their rails; no fan cut-outs in the shelf
   decks. (The KVM deck's notch for its own front fans is a separate matter.)
5. **LCD**: the owner has none yet; use a cheap Jaycar 16x2 module, ideally
   with an I2C backpack matching the front board's I2C LCD header (0050).

Plan (agent, branch `feature/rack-case-4`): implement 1-4 in the case
generator, the LCD part in 0050 / the front board generator.

## 2026-11-27 owner follow-up: keep the MEGA65 off the battens

Owner: "Basically don't put the MEGA65 mainboard flush over [the battens of
the shelf above] if you can help it. The power switch sits about 17 mm above
the PCB along that left edge." Add the power switch (~17 mm above the PCB,
board left edge) as a tall part; keep the board outline inside the
between-battens zone (full 38 mm height); the fit report flags any part over
13.45 mm under a batten.
