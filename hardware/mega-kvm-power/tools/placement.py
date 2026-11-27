"""Board outlines, footprint placement and power polygons (mm, board-local
coordinates; y grows towards the front of the box for the main board and
downwards on the input board).  ref: (x, y, rotation, side)."""

# ------------------------------------------------------------------ main board
# 170 x 80 mm, horizontal. Top edge (y = 0) faces the rear panel: DUT
# terminals and the always-on connectors sit there; the VBUS lugs, control and
# status headers along the front edge.
MAIN = {}
for n in range(8):
    cx = 10 + n * 13.5
    base = 100 + 10 * n
    MAIN['J%d' % (10 + n)] = (cx + 5.08, 7, 180)
    MAIN['U%d' % (n + 1)] = (cx + 2.5, 24, 90)
    MAIN['D%d' % base] = (cx + 5, 17, 0)
    MAIN['D%d' % (base + 1)] = (cx + 10.5, 21.5, 90)
    MAIN['R%d' % (base + 4)] = (cx + 10.5, 17.5, 90)
    small = ['R%d' % (base + 0), 'R%d' % (base + 1), 'R%d' % (base + 2), 'C%d' % (base + 0),
             'C%d' % (base + 1), 'R%d' % (base + 3)]
    for k, ref in enumerate(small):
        MAIN[ref] = (cx + (k % 3) * 3.2, 28.5 + (k // 3) * 2.2, 0)
    MAIN['C%d' % (base + 2)] = (cx + 0.5, 34, 0)     # input 1u 1206
    MAIN['C%d' % (base + 3)] = (cx + 5, 20.6, 0)  # output 1u 1206
# always-on cell (index 8)
cx = 122
MAIN.update({'U9': (cx + 2.5, 24, 90), 'D180': (cx + 5, 17, 0), 'D181': (cx + 10.5, 21.5, 90),
             'R184': (cx + 10.5, 17.5, 90), 'C182': (cx + 0.5, 34, 0), 'C183': (cx + 5, 20.6, 0)})
for k, ref in enumerate(['R180', 'R181', 'R182', 'C180', 'C181', 'R183']):
    MAIN[ref] = (cx + (k % 3) * 3.2, 28.5 + (k // 3) * 2.2, 0)
MAIN.update({
    'J20': (121, 4.5, 90), 'J21': (134, 4.5, 90),
    'J22': (151, 14.5, 180),
    # VBUS entry
    'J1': (12, 69), 'J2': (27, 69),
    'C1': (43, 70), 'C2': (58, 70), 'C3': (68, 64, 90),
    'U10': (75, 70), 'C4': (70, 74), 'C5': (80, 74),
    'R1': (84, 64), 'D1': (88, 64),
    'R2': (36, 57), 'R3': (39.5, 57), 'R6': (95, 57), 'C6': (43, 57),
    # control / status / I2C along the front edge
    'J3': (92, 75, 90), 'R4': (89, 69, 90),
    'J4': (122, 75, 90),
    'J5': (150, 70, 90), 'JP1': (163, 62),
    'U11': (140, 63), 'C7': (147, 58, 90),
    'R5': (130, 55, 90), 'R7': (133, 55, 90), 'R8': (136, 55, 90),
    'R9': (150, 62, 90), 'R10': (153, 62, 90), 'R11': (130, 67, 90),
    'H1': (3.5, 40), 'H2': (166.5, 30), 'H3': (3.5, 76.5), 'H4': (166.5, 76.5),
    'H5': (226.5, 9), 'H6': (226.5, 67),
})
# R6 is the expander A0 strap (moved next to the expander)
MAIN['R6'] = (133, 67, 90)

# Fan block (issue 0052): the board grows from 170 to 230 mm; the new 60 mm on
# the right holds 8 fan cells (2 columns x 4 rows) on the always-on pour.
# Cell: 4-pin header, BSP452 (tab = AON12) to its right, then a row with the
# 2N7002 PWM inverter and the five resistors.
FAN_CELLS = []
for k in range(8):
    ox, oy = 171 + 27 * (k // 4), 1 + 18.5 * (k % 4)
    FAN_CELLS.append((ox, oy))
    base = 300 + 10 * k
    MAIN['J%d' % (30 + k)] = (ox + 3, oy + 4.5, 0)
    MAIN['U%d' % (30 + k)] = (ox + 20, oy + 5, 0)
    MAIN['Q%d' % (30 + k)] = (ox + 3, oy + 12.5, 0)
    for i in range(5):
        MAIN['R%d' % (base + i)] = (ox + 7 + 2.5 * i, oy + 12.5, 90)
# controllers, mux and sensor in the space the old 3-pin fan headers used
MAIN.update({
    'U12': (143, 41, 0), 'C400': (143, 47.5, 0), 'R400': (143, 50.5, 0), 'R12': (146, 53, 0),
    'U13': (100, 45, 0), 'C405': (100, 50, 0),
    'J6': (204, 76, 0),
})
for m in range(4):
    MAIN['U%d' % (14 + m)] = (156, 37 + 4.5 * m, 0)
    MAIN['C%d' % (401 + m)] = (162, 37 + 4.5 * m, 0)
    MAIN['R%d' % (410 + m)] = (166, 37 + 4.5 * m, 0)
for i in range(8):
    MAIN['R%d' % (401 + i)] = (148.6 + 2.4 * (i % 2), 37.5 + 3.5 * (i // 2), 90)

BOARDS = {
    'main': {
        'name': 'mega-kvm-power-main',
        'origin': (100, 100),
        'size': (230, 80),
        'place': MAIN,
        'zones': [
            ('GND', 'B', [(0.5, 0.5), (229.5, 0.5), (229.5, 79.5), (0.5, 79.5)]),
            ('VBUS', 'F', [(1, 24.1), (143, 24.1), (143, 60), (64, 60), (64, 79), (1, 79)]),
            ('AON12', 'F', [(118.5, 1), (229, 1), (229, 72), (170, 72), (170, 61), (146, 61),
                            (146, 23.9), (118.5, 23.9)]),
        ] + [('OUT%d' % n, 'F', [(8.6 + n * 13.5, 1), (21.4 + n * 13.5, 1),
                                 (21.4 + n * 13.5, 23.9), (8.6 + n * 13.5, 23.9)]) for n in range(8)],
        'texts': [('MEGA-KVM power main v0.3  2 oz Cu  VBUS 12 V 25 A', 50, 50, 'F', 1.5),
                  ('DUT0', 10.5, 21, 'F', 1.0), ('DUT7', 105, 21, 'F', 1.0),
                  ('MIMAS / GS105 (always on)', 140, 32, 'F', 1.0),
                  ('CTRL: 1 GND 2 KEY 3-10 CH0-7 11 PRESENT', 92, 66.5, 'F', 0.8),
                  ('VBUS', 12, 61.5, 'F', 1.2), ('GND', 27, 61.5, 'F', 1.2),
                  ('FANS 1 GND 2 +12V 3 TACH 4 PWM', 186, 77.5, 'F', 0.8),
                  ('J6 TEMP I2C to input board', 188, 75.8, 'F', 0.8)]
                 + [('FAN%d %s' % (k, ['KVM', 'KVM', 'A', 'A', 'A', 'B', 'B', 'B'][k]),
                     FAN_CELLS[k][0] + 7.6, FAN_CELLS[k][1] + 9.4, 'F', 0.8) for k in range(8)],
    },
}

# ------------------------------------------------------------------ input board
# 197 x 34 mm, vertical (1RU interior is 38.45 mm; case fit report on
# feature/case). F side faces out (connectors and LEDs; every connector body
# stays inside the 34 mm band); B side (inside the box): fuses, TVS, FETs,
# LTC4417, lugs. Columns, left to right: connectors | fuses | TVS + OR diodes |
# UV/OV dividers | FETs + LTC4417 | soft start | lugs.
INP = {
    # F side: connectors (x 2..83) and input-selected LEDs
    'J1': (9, 14), 'J2': (28, 14), 'J3': (40, 12), 'J4': (64, 15),
    'D7': (18, 29), 'D8': (48, 29), 'D9': (72, 29),
    # B side under the connectors, clear of their THT pads
    'R7': (4, 27, 90, 'B'), 'R8': (6.5, 27, 90, 'B'), 'R9': (9, 27, 90, 'B'),
    'R40': (4, 31, 90, 'B'), 'R41': (6.5, 31, 90, 'B'), 'R42': (9, 31, 90, 'B'),
    'Q9': (15, 29, 0, 'B'), 'Q10': (21, 29, 0, 'B'), 'Q11': (27, 29, 0, 'B'),
    'U2': (44, 28, 0, 'B'), 'C8': (38, 28, 90, 'B'), 'C9': (50, 28, 90, 'B'),
    'J5': (60, 28, 0, 'B'), 'JP1': (78, 28, 0, 'B'),
    # fuses (column) with the master-switch passives below
    'F1': (88, 5, 0, 'B'), 'F2': (88, 15, 0, 'B'), 'F3': (88, 25, 0, 'B'),
    'R2': (86, 31.5, 0, 'B'), 'R3': (90, 31.5, 0, 'B'), 'R4': (93, 31.5, 0, 'B'), 'C6': (96, 31.5, 0, 'B'),
    'R5': (99, 31.5, 0, 'B'), 'R6': (102, 31.5, 0, 'B'), 'C7': (105, 31.5, 0, 'B'),
    # TVS, input caps, diode-OR
    'D1': (114, 5, 0, 'B'), 'D2': (114, 15, 0, 'B'), 'D3': (114, 25, 0, 'B'),
    'C1': (122, 4, 90, 'B'), 'C2': (122, 14, 90, 'B'), 'C3': (122, 24, 90, 'B'),
    'D4': (126, 4, 90, 'B'), 'D5': (126, 14, 90, 'B'), 'D6': (126, 24, 90, 'B'),
    # FETs: input side x 140/148, output side x 159/167
    'Q1': (140, 6, 0, 'B'), 'Q2': (148, 6, 0, 'B'), 'Q5': (140, 16, 0, 'B'), 'Q7': (148, 16, 0, 'B'),
    'Q3': (159, 6, 0, 'B'), 'Q4': (167, 6, 0, 'B'), 'Q6': (159, 16, 0, 'B'), 'Q8': (167, 16, 0, 'B'),
    'U1': (150, 28, 90, 'B'), 'R1': (141, 28, 90, 'B'),
    'C4': (176, 28, 90, 'B'), 'C5': (178.5, 28, 90, 'B'),
    'J6': (186, 9), 'J7': (186, 25),
    'H1': (3.5, 3.5), 'H2': (193.5, 30.5),
}
for n in (1, 2, 3):        # UV/OV dividers
    for k in range(3):
        INP['R%d' % (10 * n + k)] = (130 + k * 2.5, 4 + 10 * (n - 1), 90, 'B')
for n in (1, 2, 3):        # soft-start RC next to the output-side FETs
    INP['C%d' % (10 + n)] = (157 + 5 * (n - 1), 28, 90, 'B')
    INP['R%d' % (10 * n + 3)] = (159.5 + 5 * (n - 1), 28, 90, 'B')

BOARDS['inputs'] = {
    'name': 'mega-kvm-power-inputs',
    'origin': (100, 100),
    'size': (197, 34),
    'place': INP,
    'zones': [
        ('GND', 'F', [(0.5, 0.5), (196.5, 0.5), (196.5, 33.5), (0.5, 33.5)]),
        ('VBUS', 'B', [(155, 0.5), (196.5, 0.5), (196.5, 21.5), (155, 21.5)]),
    ],
    'texts': [('IN1 BANANA 25A', 18, 32.3, 'F', 1.0), ('IN2 PCIe 15A', 48, 32.3, 'F', 1.0),
              ('IN3 MOLEX 10A', 72, 32.3, 'F', 1.0), ('MEGA-KVM power inputs v0.2', 160, 32.3, 'B', 1.0)],
}

