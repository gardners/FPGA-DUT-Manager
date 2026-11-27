# MEGA-KVM case (issues 0048, 0051)

Status: **rack layout v0.2 (2026-11-27, issue 0051)** is the primary output:
one sliding 6 mm ply shelf per MEGA65, a 4RU fan plate per group of four
shelves, and a 3RU KVM unit on slides, 11RU in all (4 shelves, KVM, 4
shelves). The single-box options A and B (below, "Options A and B") still
generate but are no longer developed.

## Rack layout (issue 0051)

`make` in `hardware/mega-kvm-case` writes `out/rack/` and
`out/fit-report.md`. The fit report lists conflicts first, then heights, widths,
fan clearances, the KVM fit and the sheet count.

### Parts (`out/rack/parts/`, nested on `out/rack/sheets/ply6-900x600-N.svg`)

| Part | Size (mm) | Qty | What |
|---|---|---|---|
| `shelf-deck` | 424.6 x 253 | 8 | Common deck, plain rectangle (set-back mode: **no fan notches**). Batten outlines are in the hidden reference layer (drill guide, not cut). Dashed etched lines mark the 25 mm edge strips (parts there < 12 mm, under the next shelf's battens). Holes: MEGA65 board (6), floppy (4), Cart64out (4), deck-to-batten screws, gusset pilots, two cable pass-throughs with tie slots, two strain-bar slots. |
| `strain-bar` | 371 x 36 | 8 | Stands in the deck's rear slots (30 mm tall); cable-tie slot pairs every 40 mm. |
| `fan-plate` | 482.6 x 177.8 | 2 | 4RU (`FAN_PLATE['ru']`, 1-4). 3 x 120 mm fans at 125 mm pitch, staggered low/high/low (centres 93 / 114.8 mm above the plate bottom: the low fans start 2 mm above the carrier's deck top, so no deck needs a notch), cut grille or plain bore (`guard`). Screws into the carrier shelf's batten ends and two gussets. MEGA65 logo under fan 1, M.E.G.A. e.V. logo under fan 3 (the larger free band), "MEGA-KVM" under fan 2. |
| `fan-gusset` | 90 x 36 | 4 | Stands on the carrier deck over each batten. |
| `kvm-front` | 482.6 x 133.35 | 1 | No power connectors (owner round 12). Master rocker at the far left (wired to J54 on the power board), then 2 x 120 mm fans (owner 2026-11-27; they reach down through a deck notch). Right-hand column: the 140 x 66 mm 0050 display PCB from `mega-kvm-front/out/panel-holes.json` at the top (PCB 3 mm behind the panel), the "MEGA-KVM" etch (10 mm letters) under it, then the MEGA65 and M.E.G.A. e.V. logos. |
| `kvm-deck` | 424.6 x 349 | 1 | One front notch (x 32-275, 28 mm deep) for its own 2 x 120 mm front fans. The 230 x 138.5 mm power board at the front (x 25-255, front edge 40 mm behind the panel, inputs along its front edge, plugged from the open top), the GS105 beside it (x 263-357), and the two bays at the rear (x 40.8-422). Holes: the board's eight M3 holes, Mimas, keyboard sub-board and shield-support holes, GS105 tie slots, tie-slot pairs for the DUT lead bundle, vents under the Mimas boards. The board and GS105 outlines are etched. |
| `kvm-rear` | 424.6 x 132 | 1 | Seen from the rear: the two bay cut-outs at the left (sub-SVGs `out/rack/fragments/bay1.svg`, `bay2.svg`). At the right (= the deck's left, behind the power board's DUT terminals): the Ethernet bulkhead + 8 DUT power lead holes, with the keyboard feed-through above them. Vent slots fill the rest. |
| `kvm-gusset` | 90 x 24 | 4 | Under the KVM deck, front and rear, against the battens' inner faces (moved inwards where a deck hole is in the way). |

Not cut: 25 x 25 mm timber battens, 2 per shelf and 2 for the KVM, all full
length. **Set-back mode** (owner round 13, `SHELF['fan_clearance'] =
'setback'`): the bottom (carrier) shelf of each group carries the fan plate
at its front; the three other shelves of the group are mounted **92 mm
further back on their rails** (clear of the 25 mm fan bodies and the 90 mm
gussets), so no shelf deck has notches. (`'notch'` mode, flush shelves with
notched decks and shortened battens, still builds.) Drawings: `out/rack/rack-elevation.svg/.png` (front and side
view, cable-loop zone), `out/rack/kvm-topview.svg/.png`, and
`out/rack/preview/*.png` (renders with the reference layer visible).

### Data sources

* `mega65_footprint.py` is the replaceable table of MEGA65 board, floppy,
  Cart64out and expansion holes, each with its source. MEGA65 r6 board
  214 x 118 mm with 6 holes, from the Trenz drawing
  `mega65r6/DIM-TE0765-06.PDF`, cross-checked against
  `mega65-rugged-case/lower-deck3` (within 0.8 mm). Floppy: 70 x 94 mm hole
  pattern from `lower-deck2` (offset from the bezel assumed 30 mm). Cart64out
  Rev.1: Eagle board = DXF, holes Ø3.3 at (16,4) (16,58) (71,4) (71,58).
  Its insertion depth comes from the rugged case's breakout support hole.
  Official expansions: no data, so nothing is cut.
* `mega65_footprint.TALL_PARTS`: the MEGA65's tall parts with their board
  positions (from the DIM drawing) and heights: **IEC serial 6-pin DIN socket
  21.1 mm above the PCB** (owner: assume it is the tallest part; the MEGA65
  schematics name J6 "IEC - 1541 style Diskdrive" without a part number, so
  the height is the Same Sky SDS-60J datasheet's for a standard right-angle
  6-pin DIN, 20 W x 21.1 H x 15.5 D), the power switch (~17 mm, owner), VGA,
  RJ45 and the two joystick DB9s (typical heights, ASSUMED).
* `logos/` (provenance in `logos/README.md`): `mega65.svg` (= `assets/mega65.svg`),
  etched as one colour (the dark pill only, letters bare); `mega-ev.svg`, the
  M.E.G.A. e.V. logo rebuilt as clean vectors (block grid + outlined text) from
  https://www.m-e-g-a.org/wp-content/uploads/2012/06/mlogo.png (a real 200 x 52 px
  PNG, kept as `logos/src/mlogo.png`) by `tools/make_mega_ev_logo.py`.
* `RAILS`: server slides **12.7 mm (1/2 in) per side, ASSUMED** (owner to
  measure); deck width = 450 - 2 x 12.7 = 424.6 mm.

### Parameters (`config.py`, rack block)

`PLY_T`, `RACK_KERF`, `RACK_SHEETS`; `RACK` (layout list bottom-to-top,
group size, post opening, face width, rack depth for the drawing); `SHELF`
(deck width from `RAILS`, batten, front allowance, rear space, `fan_clearance` =
`notch` or `setback` with `setback`, notch clearances, cable slots, tie
slots, strain bar, MEGA65 x position, floppy side); `FANS` (120/92/80 mm
hole pitch and bore); `FAN_PLATE` (RU, fan size/count/gap, stagger, guard,
screws, gusset, logo slots, text); `KVM` (RU, fan size/count, margins,
rocker position, gussets, logos); `LOGOS`; `FOOTPRINT`. `FAN_PLATE`
`low_above_deck` / `deck_gap` lift the low fans clear of the carrier deck in
set-back mode.

### Fit results (2026-11-27)

* No conflicts in the default configuration.
* Heights: deck top to next deck 38.45 mm, to the next battens 13.45 mm.
  The drawers have no top: the next shelf's deck and battens are the top.
  MEGA65 on 6.3 mm hexes + IEC socket (21.1 mm) = **29.0 mm above the deck:
  9.5 mm below the next deck**; power switch 24.9 mm (13.6 mm margin); floppy
  on 5 mm spacers 30.4 mm (8.1 mm); gussets 36 mm (all under 37.45). The whole
  board (deck x 49.5-263.5) and the floppy (x 273.5-375.1) stay **between the
  battens** (24.5 mm from either batten's inner edge), so no tall part is under
  a batten (owner: keep the board off the battens; the report flags any part
  over 13.45 mm under one).
* Widths: deck 424.6, 374.6 between the battens; board + 10 + floppy = 325.6 mm.
  Fans span x 27.3-397.3, between the battens of the shelves above.
* Fan plate (set-back mode): the low fans start 2 mm above the carrier's deck
  (z 33-153), the high fan at z 54.8-174.8; the other shelves of the group sit
  92 mm back, so the fans and gussets clear their battens by 2 mm (y).
* **KVM (owner round 12, one power board, 2026-11-27):** no input board and no power
  cut-outs on the front. The power board (230 x 138.5 mm, read from its KiCad
  file) lies flat at the front of the deck: its front edge is 40 mm behind the front
  panel, its corner holes clear the left batten, and 40 mm of free height is kept
  above its front 25 mm strip for the plugs (55.8 mm left to the next unit above).
  The DUT leads leave the terminals on its rear edge and cross a 15 mm cable gap to
  the bulkhead/DUT-power column at the rear left (x 3-37). The Mimas Mini-Fit leads
  run back to the bays, and the GS105 jack lead runs sideways to the switch (routes are
  dashed in `out/rack/kvm-topview.png`). Deck depth: 40 + 138.5 + 15 + 35 (RJ45
  patch) + 120 (Mimas) = **349 mm**. The 381 mm of bays are wider than the 375 mm
  between the battens, so three outer bay holes (keyboard sub-board, two shield
  supports) land on the right batten: drill them through and use M3 x 40 screws.
* **KVM fans: 2 x standard 120 mm PC fans** (owner, 2026-11-27). They fit
  since the display PCB became a two-row 140 x 66 mm board (issue 0050): fans at
  x 33-274, display at x 280-420 (421 of 424.6 mm). A 120 mm fan is taller than the
  space above the deck, so the fans reach 20.6 mm below the deck top through one
  notch in the deck front (x 32-275, 28 mm deep), 2 mm clear of the front gussets;
  the generator checks the fan bodies against the gussets and battens. The rocker
  sits in the strip left of the fans (`rocker_pos: 'left'`); the MEGA-KVM etch
  and the MEGA65 / M.E.G.A. e.V. logo slots are stacked under the display
  (`etch_pos` / logos `'column'`), each checked against the fans, PCB, rocker
  and screw holes. `KVM['fan']=92` with `rocker_pos: 'below_pcb'` still builds.
* KVM rear: the bays (381.2 mm) and the bulkhead/DUT power column leave 3.8 mm.

# Options A and B (issue 0048, no longer developed)

Status: **generator v0.1 (2026-11-27)**. Their report is
`out/fit-report-options-AB.md`. Option A (stand-alone laser-cut
1RU box) is complete apart from one open hardware item (the 40 mm input
board). Option B (gutted Cisco Catalyst 3560G-48TS) generates, but the
front panel is too narrow for everything (see "Fit results"), and every
carcass dimension is a placeholder until measured.

Generator: `hardware/mega-kvm-case/`. It uses Python 3 with the standard library only; Inkscape is optional, for the PNGs.

```
cd hardware/mega-kvm-case
make            # regenerate out/ (make nopng: no Inkscape needed)
```

Edit `config.py` and run `make` again. `out/` is wiped on every run, so do
not edit files there. Open `out/fit-report.md` first: it lists sizes,
problems, clearances and the variant comparison.

## What it reads

| Source | Used for |
|---|---|
| `hardware/mega-kvm-shield/scripts/geometry.py`, `out/placement.json` | rear-edge slots, keyboard sub-board position and holes, stack heights (rev B shield, 120 x 189.6 mm) |
| `hardware/mega-kvm-shield/mega-kvm-shield.kicad_pcb` | the shield's 4 support holes in the overhangs |
| `hardware/mega-kvm-power/*/...kicad_pcb` | power board outlines, mounting holes, the input board's connector courtyards (cut-outs), LEDs |
| `config.py` | everything else (Mimas facts from 0045, GS105, fans, front panel parts, carcass) |

If a source file is missing, the config fallbacks are used, and the report
says which source was used.

## Output (`hardware/mega-kvm-case/out/`)

| Path | What |
|---|---|
| `option-A/panels/A-{base,lid,front,rear,left,right}.svg` | one file per part |
| `option-A/fragments/bay1.svg`, `bay2.svg` | each Mimas bay's DUT cut-outs and labels (sub-SVG) |
| `option-A/fragments/front-panel.svg` | LCD, 8 x red/green LEDs with labels, 5 buttons, rocker |
| `option-A/fragments/rear-power.svg`, `rear-bulkhead-dut_power.svg` | power inputs (from the input board's KiCad file); Ethernet bulkhead + 8 DUT power lead holes |
| `option-A/sheets/mdf-900x600-N.svg`, `acrylic-600x400-N.svg` | parts nested onto sheets |
| `option-A/topview-A.svg/.png` | top-view fit drawing |
| `option-B/panels/B-front.svg`, `B-rear-iec.svg`, `B-rear-rps.svg`, `B-rear-fans.svg`, `B-plate.svg` | front panel, cover plates for the IEC inlet and the DC/RPS cut-out, fan plate, mounting plate |
| `option-B/plate/mounting-plate.dxf`, `mounting-plate.kicad_pcb` | plate outline + holes: DXF (R12, mm) and a KiCad board with Edge.Cuts only (opens in KiCad 10, DRC clean) for a bare PCB |
| `option-B/plate/steel-front-template.svg` | 1:1 print: the window to open in the carcass's own steel front |
| `option-B/fragments/...`, `option-B/topview-B.*` | as for A |
| `alternates/bay-{vboard,wide,narrow}.svg` | bay cut-outs of the alternate DUT faces |
| `fit-report.md`, `parameters.json` | generated report; all parameters as used |

### Laser file conventions

* Inkscape-compatible SVG; `width`/`height` in mm, `viewBox` in mm (1 user unit = 1 mm).
* Layer **cut**: pure red `#ff0000`, 0.01 mm hairline, no fill, and nothing else.
* Layer **engrave**: black `#000000`. Text is drawn as single-stroke lines in
  the generator's own vector font, so the laser PC needs no fonts.
  Engrave them as lines (score). The small pin-1 triangles are filled.
* Layer **reference**: hidden (`display:none`), blue dashed outlines of
  fragments and sheets. It is never cut; delete it or leave it hidden.
* Panels are drawn as seen from **outside** (the base: seen from above,
  the inside face; it carries only holes and a small orientation label).
* **Kerf** (`KERF`, default 0.15 mm): part outlines grow by kerf/2 and holes
  shrink by kerf/2, so finger joints come out to size. Calibrate it: cut a
  20 mm square and set `KERF = 20 - measured`.

### Laser settings note

Settings depend on the machine. As a starting point for 3 mm MDF on a 40-60 W CO2
laser: cut at about 10-15 mm/s, 70-90 % power, one pass (two on a weak
tube), air assist on; engrave the lines at about 100-200 mm/s, 15-25 %
power. For 3 mm cast acrylic, cut slower with less air (for a polished
edge) and engrave with the masking paper removed. Test-cut a corner joint
and one connector cut-out before the full sheet. MDF smoke stains: mask the
visible faces or clean them afterwards.

## Parameters (`config.py`)

* Material: `T` (3 mm), `KERF`, `FINGER_W`, `SHEETS` (MDF 900 x 600; acrylic
  600 x 400 is an assumption, set it to the real sheet size), nest gap/margins.
* Rack: `RACK_MAX_WIDTH` 445 mm (EIA 19-inch body), `RU` 44.45.
* Boards: `BAYS` (2), `MIMAS` (Numato V3 facts from 0045, standoff 3 mm),
  `SHIELD` (stack, tallest part on top), `SHIELD190` (primary bay, incl.
  **`kbd_drop`**: how much lower the keyboard sub-boards sit than in
  shield.md, default 2.5 mm, owner 2026-11-27), `VBOARD`/`WIDE`/`NARROW`
  (alternates), `CONN` (panel holes per connector type), `GS105`,
  `POWER_MAIN`, `POWER_IN` (incl. `width_override` to test a narrower input
  board), `FAN`, `FRONT` (LCD window/holes, LED/button sizes and pitch,
  button names, rocker cut-out), `ITEMS` (bulkhead, keyboard feed-through,
  DUT power lead holes, DC-lead recess).
* `CASE_A`: outer width (445), depth (`None` = as needed), margins, T-slot
  sizes, number of lid screws, rear-item priority, side-wall spill.
* `CASE_B`: carcass outer size, steel thickness, front panel size and
  fixing holes, floor standoff height and positions, rear openings, fan
  opening, plate type/thickness/margin, front-item priority.

## Option A: stand-alone laser-cut 1RU box

445 x 272 x 44.45 mm (W x D x H), 3 mm walls. One MDF 900 x 600 sheet, or 2
acrylic 600 x 400 sheets.

* **Base** with fingers on all four edges; walls with fingers to the base and
  at the vertical corners (front/rear own the corner fingers). The **lid** is
  a plain plate held by 10 M3 screws into T-slots (M3 nut in a slot in
  the wall's top edge), so it comes off for fuses and cabling. The generator
  moves each T-slot sideways until it clears every cut-out.
* **Rear (DUT face)**: the two bays (2 x 189.6 + 2 mm), flush with the
  shields' rear edges. Shield level: JB1 2x6 x 4 per bay + the 3 header
  HDMI; Mimas level: J5 2x5 x 4 per bay (keyboard sub-boards) + the
  Mimas's own HDMI OUT and IN (= DUT n video). Labels: `n JTAG`, `n KBD`,
  `n HDMI`, `OUT`, `BAY 1 DUT 1-4`, with global DUT numbers 1-8
  (DUTk of bay b = 4b + k + 1). A pin-1 triangle is engraved next to every box
  header; its corner is `VBOARD['pin1']`. Beside the bays: the Ethernet
  bulkhead with the 8 DUT power lead holes above it.
* **Right side wall, rear part**: the power inputs (input board, 0047)
  and the physical keyboard feed-through. They do not fit on the rear
  (53.8 mm free there). The panel's labels give the priority order: `1 BANANA 25A`, `2 PCIE 8P 15A`, `3 MOLEX 10A`, `+12V`/`0V`, plus input LED light holes.
* **Front**: engraved logo "MEGA-KVM", vent slots, then the 0050 group:
  1602 LCD window (71.6 x 24.6) with 4 M2.5 holes; 8 columns of LEDs
  (`1`..`8`, top row `PWR`/RED = powered, bottom row `SEL`/GRN = selected);
  buttons `PREV` `NEXT` (input) and `SCAN` `FIXED` `PIP` (mode); backlit rocker
  (`I`/`O`, `POWER`).
* **Inside** (top view): the bays against the rear wall; the GS105 and the
  power main board on the Mimas RJ45 side (owner 2026-11-27), with 35 mm left
  for the patch leads; 2 x Noctua NF-A4x10 on the left wall at the front,
  exhausting through grilles. They are 40 mm tall against a 38.45 mm interior, so they
  sit in slots in the base and the lid. Intake: vent slots in the front,
  the base and the lid over each Mimas, and the right wall.
* The **base** has holes for: Mimas (4 per bay), keyboard sub-boards (3 each),
  shield overhang supports (4 per bay), power main board (4), cable-tie
  slots for the GS105, fan slots. The **lid** has the T-slot screw holes,
  fan slots, vents over the Mimas boards, engraved logo and bay labels.

Assembly: glue (MDF: wood glue; acrylic: solvent cement) the base and the four walls;
fit the boards on M3 standoffs (3 mm for Mimas and sub-boards, longer for the
shield supports, 5 mm for the power main board), the input board on standoffs
to its wall (bananas go through wall and board), the vertical connectors
through their cut-outs, the fans with screws through the grilles, the GS105
with two cable ties; the lid last with 10 M3 x 12 screws and nuts.

## Option B: gutted Cisco Catalyst 3560G-48TS

Carcass 444.5 x 409 x 43.9 mm (Cisco hardware installation guide:
1.73 x 17.5 x 16.1 in; the owner quoted ~378 mm deep, so measure it).

* **Front panel** (440 x 41.9 placeholder): the two bays (the Mimas HDMI edge
  faces the front) and the Ethernet bulkhead. The 0050 group, the keyboard
  feed-through and the DUT power leads **do not fit** (see Fit results).
* **Rear**: cover plates over the **IEC inlet** cut-out (banana pair) and the
  **DC/RPS** cut-out (PCIe 8-pin + Molex + 3 LED holes), screw holes in
  the overlap; a fan plate (2 x 40 mm) over a rear vent opening.
* **Mounting plate** (bare PCB, 1.6 mm, or laser-cut): only the area under the
  Mimas boards, keyboard sub-boards, shield supports, GS105 and power main
  board (behind the boards, owner 2026-11-27), on the carcass floor's
  standoffs. Holes: Mimas, sub-boards, shield supports, power main, GS105
  cable-tie slots, carcass standoffs (`S`). Also emitted as DXF and as
  a KiCad board with Edge.Cuts only.

## Fit results (generated 2026-11-27, `out/fit-report-options-AB.md`)

| Variant (2 bays) | Bay | A rear: also fits | B front: also fits | 1RU height |
|---|---|---|---|---|
| **shield190 (primary)** | 189.6 | bulkhead + DUT power (53.8 mm left) | bulkhead only (37.8 mm left): **no LCD group** | ok (connectors to 26.4 mm; stack 34.2 of 41.45 in A) |
| vboard (vertical DUT board) | 110 | input board, bulkhead + DUT power | front group | A ok; B too tall above a 7.6 mm plate stack |
| wide (rev A, 279.6) | 279.6 | **bays do not fit** (561 > 435 mm) | do not fit | - |
| narrow (~150, 2x8) | 150 | bulkhead + DUT power, keyboard | bulkhead, keyboard | ok |

Findings:

1. **Option A fits**, with one exception: the input board (0047) is
   **40 mm tall, but the interior is 38.45 mm**. It needs to be <= 36 mm tall, or
   the lid needs a slot. The rear panel has 53.8 mm left beside the bays,
   but the three input connectors alone span ~87 mm side by side. The power
   inputs therefore sit on the right side wall near the rear, together with the
   keyboard feed-through. Getting them back onto the rear panel, as the owner
   asked, would need the connectors stacked vertically on a narrow (<= ~50 mm)
   board.
2. There is **no room for the DC-lead tuck-away recess** in option A (it needs
   66 mm of wall, and 16 mm are left on the right wall). It is generated
   only when it fits.
3. **Option B front panel**: two 189.6 mm bays leave 37.8 mm. The LCD/LED/
   button/rocker group (162 mm), the keyboard feed-through (36 mm) and the
   DUT power holes (34 mm) are missing (238 mm short). Choices: put the 0050
   group somewhere else (on the lid, or on a 1U blank panel above or below
   in the rack), use the narrower vertical-board variant for B (110 mm bays
   leave 197 mm: room for the group), or let the DUT power leads and
   keyboard out at the rear.
4. B: the 28 mm IEC opening placeholder is too narrow for a 19 mm-pitch banana
   pair with 8.2 mm holes (29.2 mm needed). Use sockets that need a
   6.5 mm hole, or measure the real opening.
5. The input board has all three inputs on one PCB, but the 3560's
   IEC and RPS openings are separate. In B they need panel-mount connectors
   on short leads, or an input board laid out to the measured openings.
6. Fans: the 40 mm fans go 0.77 mm into the base and the lid in option A
   (through slots). In B they fit (41.9 mm inside).

## Assumptions

* MEGA65 footprint: **not found** in the local repos (mega65-user-guide,
  mega65-rugged-case) or by a web search, so the case is not sized to it.
  Option A is 445 x 272 mm. Measure a MEGA65 if the footprint matters.
* GS105 94 x 100 x 27 mm (Netgear datasheet), held with cable ties
  (its wall-mount slot spacing is not known).
* Cisco 3560G-48TS: 43.9 x 444.5 x 409 mm (Cisco install guide). Every
  internal dimension is a placeholder.
* Connector cut-outs: HDMI 16.5 x 7.5 (receptacle face; the plug overmould stays
  outside), 2x6 box header 23.3 x 9.4, 2x5 20.8 x 9.4, PCIe/Molex = KiCad
  courtyard + 1 mm, 4 mm banana sockets 8.2 mm hole, 1602 LCD bezel 71.2 x 24.2
  with M2.5 holes on 75 x 31, 3 mm LEDs, 7 mm buttons, rocker 13 x 19.2
  (KCD1 class), RJ45 coupler 16 x 13.5 with M3 ears at +-13 mm, keyboard
  adapter 2x5 + M3 at +-15 mm. Check each against the parts bought.
* Stack (A): 3 mm base, Mimas on 3 mm standoffs, shield.md heights;
  tallest shield part 14 mm above the shield; power main board on 5 mm
  standoffs with 16 mm parts; the LCD module 36 mm tall (2.45 mm spare).

## Measurement checklist

Option B (before cutting anything for it):

1. Outer and inner size of the carcass (W x D x H), steel thickness of the floor,
   walls and lid; how the lid closes (the inside height under any lid ribs).
2. Front: the size of the opening once the original front is removed, or the flat
   area of the steel front; how a panel can be fixed (tabs, screw holes),
   to set `front_panel` and `front_fix`.
3. Floor standoffs: X (from the inner left wall, seen from the front) and Y
   (from the front face) of **every** standoff, thread, height above the floor,
   to set `standoffs` and `standoff_h`.
4. Rear: position (X from the inner left wall seen from the front, centre
   height above the floor) and size of the **IEC inlet** cut-out and of the
   **DC/RPS** cut-out, and the screw holes around them, to set
   `iec_opening`, `rps_opening` and `cover_overlap`.
5. Rear vent/fan openings (for the fan plate), and where the original fans were.
6. Anything on the floor that the plate must clear (ribs, PEM nuts, ground studs).

Both options:

7. Mimas A7 (calipers): hole positions, HDMI receptacle opening height above
   the PCB (`MIMAS['hdmi_cz']`), parts under the shield.
8. Real parts: banana socket hole, rocker cut-out, button hole, RJ45 coupler,
   LCD module (bezel and holes), PCIe/Molex plug outlines.
9. Pin-1 orientation of J5 and JB1 on a MEGA65, to set `VBOARD['pin1']` (default
   `left-bottom`).
10. Laser kerf for each material (`KERF`).

## Not done yet

* No living hinge or rack ears. For a 19-inch rack, add ears (2 x 18 mm,
  M6 at 465 mm centres) or use a rack shelf.
* The DC-lead recess pocket pieces are not generated (there is no room in either option).
* The 0050 front-panel PCB outline isn't known yet: the LED/button positions
  are the panel's. The PCB must follow them (or the other way round, once
  it exists).
