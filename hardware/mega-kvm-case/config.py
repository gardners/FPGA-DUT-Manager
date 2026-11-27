"""MEGA-KVM case parameters (issue 0048). All dimensions in mm.

Edit this file and run `make` (or `python3 build.py`) to regenerate out/.
Values marked ASSUMED are estimates; MEASURE = the owner must measure
(docs/hardware/case.md has the checklist). Sources are noted per block.
"""

# ------------------------------------------------------------------ material
T = 3.0                 # sheet thickness (3 mm MDF for the test, 3 mm acrylic final)
KERF = 0.15             # laser kerf (beam width); outlines grow and holes shrink by KERF/2.
                        # Calibrate: cut a 20 mm test square, KERF = 20 - measured.
FINGER_W = 10.0         # nominal finger length (the count is rounded to an odd number)
SHEETS = {              # nesting sheets, (width, height)
    'mdf': (900.0, 600.0),       # owner's MDF test sheet 600 x 900
    'acrylic': (600.0, 400.0),   # ASSUMED acrylic section size; change to what you buy
}
SHEET_MARGIN = 5.0      # unused border on each sheet
NEST_GAP = 4.0          # gap between parts on a sheet
HOLE_EDGE_MIN = 1.5     # minimum web between a hole and the joint zone / panel edge

# ------------------------------------------------------------------ rack / reference
RU = 44.45              # 1RU height
RACK_MAX_WIDTH = 445.0  # widest body that passes between 19-inch rack posts (450 mm opening;
                        # EIA-310 equipment bodies are typically <= 17.5 in = 444.5 mm)
MEGA65_FOOTPRINT = None # (width, depth) of a MEGA65; NOT FOUND in the local repos
                        # (mega65-user-guide, mega65-rugged-case) nor by web search. Measure one.

# ------------------------------------------------------------------ boards
BAYS = 2                # Mimas boards (bays) per unit
DUTS_PER_BAY = 4

MIMAS = {               # Numato Mimas A7 V3 (docs/hardware/shield.md, issue 0045 facts)
    'w': 90.0, 'd': 120.0, 'pcb': 1.6,
    'standoff': 3.0,    # M3 standoff under the Mimas (bottom-side parts are low; ASSUMED)
    # holes in Mimas coordinates (mx along the 120 mm edge from the RJ45 edge, my across from P13)
    'holes': [(5.00, 84.86), (115.0, 85.0), (4.83, 5.00), (115.0, 5.00)],
    'hole_d': 3.4,
    'hdmi_in_my': 71.3, 'hdmi_out_my': 49.9,   # receptacle centres on the HDMI edge (mx = 120)
    'hdmi_cz': 2.9,     # HDMI opening centre above the Mimas top surface (ASSUMED)
    'rj45_my': (60.8, 76.6),
    'rj45_plug_clear': 35.0,   # RJ45 patch plug + bend in front of the RJ45 edge
}

SHIELD = {              # issue 0045 / docs/hardware/shield.md
    'stack': 11.0,      # Mimas top -> shield underside (8.5 mm sockets on the male headers)
    'pcb': 1.6,
    'tallest': 14.0,    # tallest part above the shield top (1x11 header + Dupont plug, JST VH; ASSUMED)
}

# DUT-face variants. 'shield190' is the primary one (owner rounds 5-7, lead
# 2026-11-27): rev B shield 120 x 189.6 mm per Mimas, JB1 2x6 on the shield
# beside the Mimas, J5 2x5 on keyboard sub-boards directly below, three header
# HDMIs above the Mimas's own HDMI OUT/IN. Alternates (fit report + bay
# sub-SVGs only): 'vboard' (vertical DUT connector board), 'wide' (rev A
# single-row shield, 279.6 mm), 'narrow' (~150 mm, one 2x8 per DUT).
VARIANT = 'shield190'

SHIELD190 = {           # read from the shield project when present; fallbacks below
    'geometry_py': '../mega-kvm-shield/scripts/geometry.py',
    'placement_json': '../mega-kvm-shield/out/placement.json',
    'pcb': '../mega-kvm-shield/mega-kvm-shield.kicad_pcb',
    'y_bot': -49.8, 'y_top': 139.8,
    'z_mimas_top': 4.6, 'z_shield_bot': 15.64, 'z_shield_top': 17.24,
    'support_holes': [(5.0, -44.8), (5.0, 134.8), (70.0, -44.8), (70.0, 134.8)],
    'jb1_cz': 4.5,      # JB1 opening centre above the shield top (header 17.2-26.2, shield.md)
    'hdmi_cz': 3.25,    # header HDMI opening centre above the shield top (17.2-23.7)
    'j5_cz': 4.45,      # J5 centre above the sub-board top (4.6-13.5 with 3 mm standoffs)
    'kbd_drop': 2.5,    # owner 2026-11-27: sub-boards sit lower than in shield.md (longer
                        # stacking pins); J5 and the sub-board move down by this much
    'mimas_to_panel': 0.2,   # Mimas HDMI edge -> panel inner face (HDMI lips 1.5 proud go into the hole)
}

VBOARD = {
    'width': 110.0,     # bay width on the panel (owner target 90-110)
    'height': 38.0,     # board height (owner target <= ~40; 1RU interior is 38.45 in option A)
    'behind_panel': 6.0,  # panel inner face -> board front face (box-header shroud 9 mm, flush in a 3 mm panel)
    'pcb': 1.6,
    'mimas_gap': 40.0,  # board back -> Mimas HDMI edge: short HDMI jumpers (or 0045's
                        # board-to-board link) need a bend; 15 with a direct-mate HDMI plug
    'bay_gap': 4.0,     # between adjacent bays
    'hdmi_out': [True, True],   # per bay: Mimas HDMI OUT on the panel (False saves 21.5 mm)
    'hdmi_pitch': 21.5, # overmoulded HDMI plugs are ~21 x 11 mm
    'box_pitch': 25.0,
    'row_z': {'hdmi': 7.5, 'jb1': 18.5, 'j5': 29.5},   # row centres above the interior floor
    'label_z': 36.0,    # DUT numbers above the J5 row
    'fix_holes_u': 52.5,          # M3 holes at +-u from the bay centre, at J5 row height
    'pin1': 'left-bottom',        # pin-1 marker position as seen from outside (MEASURE on a
                                  # MEGA65: J5/JB1 pin 1 must match the board orientation)
}

WIDE = {                # rev A shield (placement.json of 2026-11-27, before rounds 5-7)
    'my': (-118.7, 160.9),
    'slots': {'HDMI3J': (90.6, 111.6), 'JTAG3J': (112.2, 136.8), 'KBD3J': (137.4, 159.4),
              'JTAG0J': (56.6, 81.2), 'KBD0J': (34.0, 56.0), 'HDMI1J': (12.4, 33.4),
              'JTAG1J': (-25.2, -0.6), 'KBD1J': (-47.8, -25.8), 'HDMI2J': (-69.4, -48.4),
              'JTAG2J': (-94.6, -70.0), 'KBD2J': (-117.2, -95.2)},
}
NARROW = {              # proposal: ~150 mm shield, one combined 2x8 per DUT; HDMI2/3 on the
                        # shield underside in the overhangs (Mimas level), HDMI1 on top.
    'my': (-30.0, 120.0),
    'lower': [('HDMI', 'DUT2', -15.0), ('HDMI', 'OUT', 49.9), ('HDMI', 'DUT0', 71.3), ('HDMI', 'DUT3', 105.0)],
    'upper': [('2x8', 'DUT2', -14.5), ('HDMI', 'DUT1', 11.5), ('2x8', 'DUT1', 37.5),
              ('2x8', 'DUT0', 67.5), ('2x8', 'DUT3', 104.5)],
}

CONN = {                # panel holes (w, h, corner r) -- the part passes through or sits flush
    'HDMI': (16.5, 7.5, 1.0),     # receptacle face; the plug overmould stays outside
    '2x6': (23.3, 9.4, 0.5),      # JB1 box header shroud (2.54 x 6 + 7.6) + 0.5
    '2x5': (20.8, 9.4, 0.5),      # J5 box header shroud + 0.5
    '2x8': (28.4, 9.4, 0.5),
}

GS105 = {'w': 94.0, 'd': 100.0, 'h': 27.0}  # Netgear GS105 datasheet: 94 x 100 x 27 mm (W x D x H)

POWER_MAIN = {          # parsed from the KiCad board when present (hardware/mega-kvm-power)
    'pcb': '../mega-kvm-power/mega-kvm-power-main/mega-kvm-power-main.kicad_pcb',
    'w': 230.0, 'd': 138.5, 'standoff': 5.0, 'tallest': 25.0,  # fallback size; tallest = PCB banana sockets (ASSUMED)
    'rear_clear': 10.0, # leads on the terminal edge
}
POWER_IN = {
    'pcb': '../mega-kvm-power/mega-kvm-power-inputs/mega-kvm-power-inputs.kicad_pcb',
    'w': 150.0, 'h': 40.0,
    'width_override': None,   # e.g. 95.0 to test a narrower input board (connectors span ~87 mm)
    'behind_panel': 8.0,      # panel inner face -> board F side (banana sockets pass through both)
    'depth': 22.0,            # board + B-side parts (fuse holders, lugs)
    'banana_hole': 8.2,       # ASSUMED for 4 mm panel sockets with M8 thread; check the part
    'conn_clear': 1.0,        # added around the PCIe / Molex courtyards
    'led_hole': 3.2,          # light holes for the input-selected LEDs (or 3 mm light pipes)
}

FAN = {'size': 40.0, 'thick': 10.0, 'count': 2,       # Noctua NF-A4x10 FLX (12 V, 40 x 40 x 10)
       'hole_pitch': 32.0, 'hole_d': 3.4, 'grille_r': 18.0, 'grille_hole': 3.5, 'grille_pitch': 4.8,
       'wall_gap': 2.0}   # fan -> wall inner face (keeps a web next to the base fingers)

FRONT = {               # front panel items (issue 0050)
    'lcd': {'window': (71.6, 24.6), 'module': (80.0, 36.0), 'holes': (75.0, 31.0), 'hole_d': 2.7,
            'depth': 27.0},            # 1602 module with I2C backpack; window = bezel 71.2 x 24.2 + 0.4
    'led_d': 3.1, 'led_pitch': 6.0,    # 3 mm LEDs (or light pipes from the 0050 PCB)
    'buttons': ['PREV', 'NEXT', 'SCAN', 'FIXED', 'PIP'],
    'button_d': 7.0, 'button_pitch': 10.5,   # 7 mm panel momentary or tact-switch caps (ASSUMED)
    'rocker': (13.0, 19.2),            # KCD1-style backlit rocker, vertical (ASSUMED; check the part)
    'pcb_depth': 15.0,                 # 0050 PCB behind the LEDs/buttons
    'gap': 4.0,
}

ITEMS = {
    'bulkhead': {'hole': (16.0, 13.5), 'screws': 13.0, 'screw_d': 3.4, 'depth': 25.0},  # flanged RJ45 coupler (ASSUMED)
    'keyboard': {'hole': (20.8, 9.4), 'screws': 15.0, 'screw_d': 3.4, 'depth': 15.0},   # 2x5 box header on a small adapter PCB
    'dut_power': {'hole_d': 5.0, 'pitch': 7.5},      # 8 DC leads (screw terminals inside, barrel plugs outside)
    'recess': {'w': 60.0, 'h': 24.0, 'depth': 45.0},  # tuck-away pocket for unused DC barrel leads
}

# ------------------------------------------------------------------ option A: stand-alone 1RU box
CASE_A = {
    'height': RU,
    'width': RACK_MAX_WIDTH,      # outer width; the layout must fit inside
    'depth': None,                # None = as deep as the layout needs
    'margin': 2.0,                # inside clearance next to the walls
    'front_zone': 30.0,           # depth behind the front panel for the LCD / 0050 PCB
    'col_right_clear': 16.0,      # power board / switch column -> right wall (fans, side items)
    'lid_screws': {'front': 3, 'rear': 3, 'side': 2},  # T-slot M3 screws holding the removable lid
    'tslot': {'screw_w': 3.2, 'depth': 12.0, 'nut_w': 5.7, 'nut_t': 2.6, 'nut_depth': 7.0},
    'bay_gap': 2.0,               # between adjacent shields
    'rear_order': ['power_inputs', 'bulkhead', 'dut_power', 'keyboard', 'recess'],  # rear items by priority
    'side_spill': True,           # put what does not fit on the rear onto the right side wall
}

# ------------------------------------------------------------------ option B: gutted Cisco 3560G-48TS
CASE_B = {
    # Cisco Catalyst 3560G-48TS hardware installation guide: 1.73 x 17.5 x 16.1 in
    # = 43.9 (H) x 444.5 (W) x 409 (D) mm (the owner quoted ~378 deep: MEASURE).
    'outer': (444.5, 409.0, 43.9),
    'steel': 1.0,                 # sheet thickness of floor/walls/lid (MEASURE)
    'front_panel': (440.0, 41.9), # our front panel (w, h); placeholder, MEASURE the front opening
    'front_fix': [(5.0, 10.0), (5.0, 32.0), (435.0, 10.0), (435.0, 32.0)],  # M3 holes (u, z) placeholder
    'standoff_h': 6.0,            # height of the carcass floor's standoffs (MEASURE)
    # carcass floor standoffs (X from the inner left wall seen from the front, Y from the
    # front face), PLACEHOLDERS: MEASURE every standoff the plate can use.
    'standoffs': [(20.0, 60.0), (220.0, 60.0), (420.0, 60.0), (20.0, 230.0), (220.0, 230.0), (420.0, 230.0)],
    'standoff_hole': 3.4,
    # rear openings (MEASURE): (centre X from the inner left wall seen from the FRONT, centre
    # height above the floor, w, h); the cover plates overlap them by 'overlap'
    'iec_opening': (400.0, 20.0, 28.0, 21.0),   # IEC C14/C16 inlet cut-out (ASSUMED ~28 x 21)
    'rps_opening': (330.0, 20.0, 55.0, 22.0),   # DC / RPS input cut-out (ASSUMED)
    'cover_overlap': 6.0, 'cover_screw_d': 3.4,
    'fan_opening': (60.0, 20.0, 90.0, 40.0),    # a rear fan/vent opening for our fan plate (MEASURE)
    'plate': 'pcb',               # 'pcb' (1.6 mm FR4, DXF + KiCad Edge.Cuts) or 'laser'
    'plate_t': 1.6,
    'plate_margin': 5.0,
    'bay_gap': 2.0,
    'front_order': ['group', 'bulkhead', 'keyboard', 'dut_power'],
}

# ================================================================== RACK LAYOUT (issue 0051)
# Options A and B above are kept buildable but are no longer developed. The rack
# layout is the primary output (out/rack/, out/fit-report.md). Rack z is measured
# up from the bottom of a unit's RU slot; deck x across from the deck's left edge
# seen from the front; deck y from the deck's front edge towards the rear.

PLY_T = 6.0             # decks, plates, gussets: 6 mm ply (owner round 10)
RACK_KERF = KERF        # calibrate for the ply (20 mm test square)
RACK_SHEETS = {'ply6': (900.0, 600.0)}   # owner's 600 x 900 sheets

RACK = {
    'ru': RU,
    'post_opening': 450.0,      # between the rack posts (17.75 in)
    'face_width': 482.6,        # full 19 inch face (fan plates, KVM front)
    'post_flange': 15.9,        # face width of each post's front flange (for the drawings)
    'layout': ['shelf'] * 4 + ['kvm'] + ['shelf'] * 4,   # bottom to top (owner round 11: KVM mid-stack)
    'group': 4,                 # shelves per fan plate; the plate sits on the bottom shelf of each group
    'depth_posts': 600.0,       # front post face -> rear post face, elevation drawing only (MEASURE)
}

SHELF = {
    'deck_w': 425.0,            # 450 between posts - ~12.5 per slide (depends on the rails)
    'batten': 25.0,             # 25 x 25 mm timber battens UNDER both deck edges (not cut: drill guide)
    'front_allow': 35.0,        # deck front -> first MEGA65 part (>= fan notch depth + margin)
    'rear_space': 100.0,        # free deck behind the MEGA65 board (cartridge / Cart64out), owner
    'depth': None,              # None = front_allow + MEGA65 board depth + rear_space
    'clear_top': 1.0,           # air gap kept under the next shelf
    # Clearance for the fan bodies of a group's fan plate:
    #  'notch'   every deck has front notches, all shelves of a group sit flush;
    #            the other shelves' battens start behind the carrier's gussets.
    #  'setback' the other shelves of a group are set back on their rails by
    #            'setback' (None = the minimum); notches only where the carrier
    #            shelf's own deck meets its fans.
    'fan_clearance': 'setback',
    'setback': None,
    'notch_clear': 1.0,         # fan frame -> notch edge, sideways
    'notch_extra': 3.0,         # notch depth = fan thickness + this
    'min_tongue': 12.0,         # deck tongues narrower than this between notches are cut away
    'screw_d': 3.5,             # deck -> batten wood screw holes (countersink by hand)
    'screw_pitch': 80.0,
    'cable_slots': [            # (x centre, y centre measured from the REAR edge, w, h): pass-throughs
        (205.0, 45.0, 60.0, 18.0), (345.0, 45.0, 50.0, 18.0)],
    'tie_slot': (2.5, 5.0, 8.0),   # cable-tie slot w x h, pair spacing
    'strain_bar': {'h': 30.0, 'from_rear': 10.0, 'tab_w': 20.0, 'tab_u': 120.0, 'tie_pitch': 40.0},
    'mega65_x': None,           # board left edge (deck x); None = centre board + floppy between the battens
    'floppy': 'right',          # 'right' of the board, or None (no floppy)
    'floppy_gap': 10.0,
}

FANS = {                        # standard PC fans: size -> screw hole pitch, hole, thickness, open bore
    120: {'pitch': 105.0, 'hole_d': 4.3, 'thick': 25.0, 'bore': 116.0},
    92: {'pitch': 82.5, 'hole_d': 4.3, 'thick': 25.0, 'bore': 89.0},
    80: {'pitch': 71.5, 'hole_d': 4.3, 'thick': 25.0, 'bore': 77.0},
}

FAN_PLATE = {
    'ru': 4,                    # 1-4 RU
    'fan': 120, 'count': 3,
    'gap': 5.0,                 # between fan frames (3 x 120 + 2 x 5 = 370 < 375 between battens)
    'edge': 3.0,                # fan frame -> plate top/bottom edge
    'stagger': ['low', 'high', 'low'],
    'low_above_deck': True,     # set-back mode: 'low' fans start above the carrier shelf's deck
    'deck_gap': 2.0,            # (deck top + this), so no shelf deck needs a fan notch
    'guard': 'grille',          # 'grille' (cut finger guard) or 'open' (plain bore for wire guards)
    'grille_hole': 6.0, 'grille_pitch': 7.5,
    'batten_screws': (8.0, 17.0),   # screw heights (above the slot bottom) into each batten's front end
    'screw_d': 4.0,
    'gusset': {'h': 36.0, 'l': 90.0, 'chamfer': 6.0},   # right triangle standing on the carrier deck over each batten
    'logos': [('mega65', 0), ('mega_ev', 2)],           # logo slot above or below fan n (a 'low' fan), larger band
    'text': 'MEGA-KVM', 'text_size': 12.0,              # etched below the 'high' fan
}

KVM = {
    'ru': 3,
    # Fans: 2 x standard 120 mm PC fans (120 x 120 x 25, owner 2026-11-27). They
    # fit beside the display PCB since that became a two-row 140 x 66 mm board
    # (issue 0050; size read from panel-holes.json). 120 mm is taller than the
    # space above the deck, so the fans reach down through notches in the deck
    # front, between the front gussets ('fan_gusset_clear' from the gusset
    # faces). 'fan': 92 (the old default) still builds, top-aligned, no notch.
    'fan': 120, 'fan_count': 2, 'fan_gap': 1.0, 'fan_edge': 3.0, 'fan_gusset_clear': 2.0,
    'guard': 'grille', 'grille_hole': 5.0, 'grille_pitch': 6.5,
    'side_margin': 5.0,         # behind-panel parts -> deck edge
    'pcb_top': 3.0,             # front-panel PCB top edge below the panel top
    # rocker: 'left' (in the strip left of the fans, at the fans' centre height),
    # 'below_pcb' (under the display PCB, 'rocker_dx' from its left) or 'json'
    'rocker_pos': 'left', 'rocker_clear': 4.0,
    'rocker_dx': 20.0,
    # Power board (owner round 12, 230 x 138.5 mm, inputs on its front edge,
    # plugged from the open top): front edge 'power_front' behind the front
    # panel's back face (at least the front zone), left edge at 'power_x'.
    'power_front': 40.0, 'power_x': 25.0, 'power_gap': 8.0,  # power_x: its corner holes clear the left batten; power_gap: board -> GS105
    'plug_strip': 25.0,         # depth of the input-connector strip along the board's front edge
    'plug_clear': 40.0,         # free height above the board for the plugs and their cable bends
    'cable_gap': 15.0,          # board rear edge -> RJ45 patch zone: DUT leads run across here
    'front_holes': '../mega-kvm-front/out/panel-holes.json',
    'front_zone_extra': 4.0,
    'gusset': {'h': 24.0, 'l': 90.0, 'chamfer': 6.0},   # under the deck, against the battens' inner faces
    'rear_clear': 1.35,         # rear plate top below the unit's top
    # etch_pos 'column': MEGA-KVM etched under the display PCB, the logos stacked
    # under it ('column'); otherwise beside the rocker, logos 'left'/'right' in
    # the band in front of the deck (only with fans that clear the deck)
    'etch_pos': 'column',
    'logos': [('mega65', 'column'), ('mega_ev', 'column')],
    'text': 'MEGA-KVM', 'text_size': 10.0,
}

LOGOS = {                       # slot name -> file in logos/ and how to make it one colour
    # logos/mega65.svg = assets/mega65.svg (owner). The dark pill (#3b3b3b) has the
    # letters as holes: keep only it, as black, so the letters stay bare wood.
    'mega65': {'file': 'mega65.svg', 'keep': ['#3b3b3b'], 'w': 110.0, 'h': 24.0, 'label': 'MEGA65'},
    # M.E.G.A. e.V. logo: not found yet (owner to supply); keep=None = every fill -> black
    'mega_ev': {'file': 'mega-ev.svg', 'keep': None, 'w': 110.0, 'h': 24.0, 'label': 'M.E.G.A. E.V.'},
}

FOOTPRINT = 'mega65_footprint.py'   # MEGA65 board / floppy / Cart64out table (replaceable, with sources)
