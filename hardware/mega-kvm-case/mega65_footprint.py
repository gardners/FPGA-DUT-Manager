"""MEGA65 shelf footprint table (issue 0051). Replace freely; build.py reads it.

Every block names its source. Coordinates in mm, as seen from ABOVE:
x to the right, y from the board's FRONT edge towards the rear (the rear
edge carries HDMI/USB/Ethernet and the horizontal expansion (cartridge) port).
'cut': True = the holes are cut in the deck; False = drawn only in the hidden
reference layer (unknown/placeholder data never ends up as real holes).
"""

# ---------------------------------------------------------------- MEGA65 mainboard
# Source 1: mega65r6 DIM-TE0765-06.PDF (Trenz, 1:1 dimension drawing, top view):
#   board 214.0 x 118.0 mm; expansion-port notch in the rear edge x 26.0-85.0,
#   down to y 99.5. Mounting holes read from the drawing's dimension list and
#   checked against the plotted holes (150 dpi render).
# Source 2: mega65-rugged-case lower-deck3-laser-cut.svg ("M3x15 ... HEX6.3 ...
#   MEGA65 main board"): six holes at (135.5, 163.5) (237.5, 163.5) (339.5, 163.5)
#   (162.5, 251.5) (237.5, 251.5) (338.5, 251.5) in its sheet = board (5, 93)
#   (107, 93) (209, 93) (32, 5) (107, 5) (208, 5) relative to a board left edge
#   at sheet x 130.5. Agrees with source 1 to <= 0.8 mm (rear-right hole: DIM
#   y 93.8, rugged case 93.0; front row: DIM 4.88, rugged 5.0).
BOARD = {
    'source': 'mega65r6 DIM-TE0765-06.PDF, cross-checked with mega65-rugged-case lower-deck3',
    'cut': True,
    'w': 214.0, 'd': 118.0,
    'notch': (26.0, 85.0, 99.5),           # expansion-port notch: x0, x1, y of its bottom
    'hole_d': 3.4,                          # M3 (rugged case uses 3.0 for a tight fit)
    'holes': [(5.0, 93.0), (107.0, 93.0), (208.8, 93.8),
              (32.0, 4.88), (107.0, 4.88), (208.2, 4.88)],
    'standoff': 6.3,                        # HEX6.3 spacers (rugged case assembly.md)
    'tallest': 15.0,                        # ASSUMED tallest part above the PCB (DB9/HDMI/USB); MEASURE
    'port_x': 55.5,                         # expansion port centre (middle of the notch)
}

# ---------------------------------------------------------------- 3.5 inch floppy drive
# Source: mega65-rugged-case lower-deck2-laser-cut.svg ("12mm M3 screw + 5mm
# nylon spacer ... screws into bottom of floppy drive"): holes (157.5, 14)
# (227.5, 14) (157.5, 108) (227.5, 108) = 70 mm across x 94 mm along the drive.
# The holes' offset from the drive's front bezel is NOT in either source:
# ASSUMED 30 mm (MEASURE on the drive). Drive outline: standard 101.6 x 147 x 25.4.
FLOPPY = {
    'source': 'mega65-rugged-case lower-deck2 (hole pattern); front offset ASSUMED',
    'cut': True,
    'w': 101.6, 'd': 147.0, 'h': 25.4, 'spacer': 5.0,
    'hole_d': 3.4,
    'holes': [(-35.0, 30.0), (35.0, 30.0), (-35.0, 124.0), (35.0, 124.0)],   # (x from the drive centre, y from its front)
}

# ---------------------------------------------------------------- Cart64out Rev.1 breakout
# Source: svenpetersen1965/C64---Cart64out, Rev. 1/Eagle/Cart64out_v1_noFrame.brd,
# cross-checked against Rev. 1/dxf/Cart64out_v1.dxf (layer 20 outline, layer 20/21
# circles): 4 x drill 3.302 mm at (16, 4) (16, 58) (71, 4) (71, 58); outline
# x 0..97, y 0..62, card-edge tongue x 0..12 at y 2..60 (the body is 85 x 62).
# Board x runs from the tongue tip towards the rear when plugged into the
# MEGA65's horizontal expansion port. The insertion depth comes from the
# rugged case: its single breakout support hole (lower-deck3 (213.05, 94.5) =
# board (82.5, 162.0)) is Cart64out hole (71, 58), so the tongue tip sits at
# board y 91.0 (8.5 mm into the port notch).
CART64OUT = {
    'source': 'Cart64out Rev.1 Eagle .brd + DXF; insertion from mega65-rugged-case lower-deck3',
    'cut': True,
    'outline': [(12, 0), (97, 0), (97, 62), (12, 62), (12, 60), (0, 60), (0, 2), (12, 2)],
    'holes': [(16.0, 4.0), (16.0, 58.0), (71.0, 4.0), (71.0, 58.0)],
    'hole_d': 3.3,
    'tip_y': 91.0,                          # tongue tip, board y
    'standoff': None,                       # height to the port's card slot: MEASURE
}

# ---------------------------------------------------------------- official expansions
# PLACEHOLDER: no drawings yet (owner chasing). Each entry: name, outline
# (x0, y0, x1, y1) in board coordinates, holes [(x, y)], hole_d.
EXPANSIONS = {
    'source': 'PLACEHOLDER (no data)',
    'cut': False,
    'items': [],
}
