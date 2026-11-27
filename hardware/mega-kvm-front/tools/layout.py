"""Front-panel board geometry (mm). Board-local coordinates: origin = the
board's top-left corner **as seen from the front of the case** (the KiCad top
view: F side faces the panel), x to the right, y downwards.

Stack, front to back (see docs/hardware/front-panel.md):
  panel (3 mm) | 3 mm M3 spacers | this board (1.6 mm, F side towards the panel)
  | LCD spacers (~3-4 mm, set by the module's bezel height) | 1602 LCD module
The LCD bezel passes through WINDOW and touches the back of the panel.

Placement values are the *feature centre* (LED lens, switch stem, header
middle, IC centre): pcb_build.py shifts each footprint so its pad
bounding-box centre lands there.  ref: (x, y, rot, side).
"""

# Two rows (issue 0050, 2026-11-27): 140 x 66 mm, so the 3RU KVM front panel
# (0051) has room for 2 x 120 mm fans beside it (the old single-row strip
# was 227 x 36 mm). Top row: LCD + level shifter, button expander,
# connectors; bottom row: the 8 LED pairs, the LED expander, the 5 buttons.
BOARD_W = 140.0
BOARD_H = 66.0
THICK = 1.6
PANEL_GAP = 3.0       # board front face to panel back face (M3 spacers)

# 1602 module (80 x 36) on the back, flush with the board's left and top edges
LCD = {'x': 0.0, 'y': 0.0, 'w': 80.0, 'h': 36.0,
       'holes': [(2.5, 2.5), (77.5, 2.5), (2.5, 33.5), (77.5, 33.5)],
       'bezel': (4.4, 5.9, 71.2, 24.2),        # x, y, w, h of the metal frame (typical 1602A)
       'view': (7.75, 10.75, 64.5, 14.5)}      # viewing area (typical; check the module)
WINDOW = (3.5, 5.0, 76.5, 31.0)               # board cut-out for the bezel (x1, y1, x2, y2)

# bottom row: LEDs (red over green) at the left, buttons at the right
LED_X0, LED_PITCH = 12.0, 8.0
LED_Y_RED, LED_Y_GRN = 44.0, 56.0
LED_X = [LED_X0 + LED_PITCH * i for i in range(8)]

BTN_X0, BTN_PITCH, BTN_Y = 88.0, 11.5, 50.0
BUTTONS = [('SW1', 'PREV', '<'), ('SW2', 'NEXT', '>'), ('SW3', 'MODE', 'MODE'),
           ('SW4', 'SPARE1', 'A'), ('SW5', 'SPARE2', 'B')]
BTN_X = [BTN_X0 + BTN_PITCH * i for i in range(len(BUTTONS))]

PLACE = {
    # LCD side: level shifter, LCD header and VLCD jumper (headers on the back)
    'J2': (82.6, 7.8, 0, 'B'), 'JP1': (82.6, 28.2, 0, 'B'),
    'U3': (88.2, 18.0, 0), 'C3': (88.2, 14.6, 0), 'C4': (88.2, 21.4, 0),
    'R21': (85.6, 12.0, 90), 'R22': (87.3, 9.0, 90), 'R23': (91.6, 21.4, 90),
    'C6': (88.4, 25.2, 0),
    # LED expander, between the LEDs and the buttons
    'U1': (77.0, 50.0, 0), 'C1': (77.0, 56.6, 0),
    # top right: expansion header along the top edge, button expander and its
    # pull-up arrays, shield connector at the right-hand edge
    'J3': (115.0, 4.5, 90, 'B'),
    'U2': (112.0, 20.0, 90), 'C2': (104.6, 20.0, 90),
    'RN1': (105.5, 28.0, 0), 'RN2': (110.0, 28.0, 0), 'RN3': (114.5, 28.0, 0), 'RN4': (119.0, 28.0, 0),
    'J1': (134.0, 22.0, 0, 'B'), 'C5': (128.6, 17.6, 0), 'C7': (128.6, 26.4, 0),
    # mounting: LCD (M2.5, also panel screws) and M3 spacers to the panel
    'H1': (2.5, 2.5), 'H2': (77.5, 2.5), 'H3': (2.5, 33.5), 'H4': (77.5, 33.5),
    'H5': (136.5, 3.5), 'H6': (136.5, 62.5), 'H7': (3.5, 62.5), 'H8': (82.5, 62.5),
}
for i, x in enumerate(LED_X):
    PLACE['D%d' % (1 + i)] = (x, LED_Y_RED, 0)
    PLACE['D%d' % (11 + i)] = (x, LED_Y_GRN, 0)
    PLACE['R%d' % (1 + i)] = (x, LED_Y_RED + 5.6, 90)
    PLACE['R%d' % (11 + i)] = (x, LED_Y_GRN + 5.4, 90)
for (ref, _, _), x in zip(BUTTONS, BTN_X):
    PLACE[ref] = (x, BTN_Y, 0)

# Panel cut-out sizes (diameters, mm)
LED_HOLE = 3.2        # 3 mm LED lens; the 3.8 mm flange stays behind the panel
BTN_HOLE = 4.5        # K2-1102DP round stem, 3.5 mm
M25_HOLE = 2.7
M3_HOLE = 3.2
LCD_WINDOW = (6.5, 9.5, 67.0, 17.0)   # panel window x, y, w, h (viewing area + 1.25 mm)

# Master rocker: in the panel, not on this board. The case generator places
# it (hardware/mega-kvm-case config KVM 'rocker_pos': left of the fans by
# default); x/y here are only used with rocker_pos 'json' (board coordinates).
ROCKER = {'x': None, 'y': None,
          'note': 'backlit SPST rocker, 3-pin, JST XH cable to the power board; placed by the case '
                  'generator (KVM rocker_pos); cut-out per the chosen part (e.g. KCD1-type 19.2 x 13.0 mm)'}

SILK = ([(str(i + 1), x, LED_Y_RED - 5.4, 1.5) for i, x in enumerate(LED_X)] +
        [(lbl, x, BTN_Y - 6.8, 1.2) for (_, _, lbl), x in zip(BUTTONS, BTN_X)])
BACK_SILK = [('MEGA-KVM front panel v0.2 (issue 0050)', 110.0, 40.0, 1.2),
             ('J1 SHIELD: 1 GND 2 5V 3 3V3 4 SDA 5 SCL 6 INT', 120.0, 36.2, 0.8),
             ('J2 LCD: GND VCC SDA SCL', 90.0, 1.6, 0.8),
             ('J3 EXP: 1 GND 2 3V3 3-10 P1.0-P1.7', 115.0, 8.4, 0.8),
             ('JP1 VLCD: 1-2 5V / 2-3 3V3', 91.5, 34.6, 0.8)]
# Panel engraving suggestions (front view, board coordinates)
ENGRAVE = ([(str(i + 1), x, LED_Y_RED - 7.0) for i, x in enumerate(LED_X)] +
           [('PWR', LED_X0 - 6.5, LED_Y_RED), ('SEL', LED_X0 - 6.5, LED_Y_GRN)] +
           [(lbl, x, BTN_Y - 7.0) for (_, _, lbl), x in zip(BUTTONS, BTN_X)])
