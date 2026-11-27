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
    # VBUS bulk, 3.3 V
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
# Issue 0055: the block moved 39 mm towards the front (rows from y 40) so that
# the three 5 V DUT outputs fit on the rear edge at x 160-204.
# Cell: 4-pin header, BSP452 (tab = AON12) to its right, then a row with the
# 2N7002 PWM inverter and the five resistors.
FAN_CELLS = []
for k in range(8):
    ox, oy = 171 + 27 * (k // 4), 40 + 18.5 * (k % 4)
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
})
for m in range(4):
    MAIN['U%d' % (14 + m)] = (156, 37 + 4.5 * m, 0)
    MAIN['C%d' % (401 + m)] = (162, 37 + 4.5 * m, 0)
    MAIN['R%d' % (410 + m)] = (166, 37 + 4.5 * m, 0)
for i in range(8):
    MAIN['R%d' % (401 + i)] = (148.6 + 2.4 * (i % 2), 37.5 + 3.5 * (i // 2), 90)

# Input stage (0047 owner round 12): a 58.5 mm strip added at the front
# (y 80-138.5). Rows, back to front: output FETs (drain up into the VBUS pour) |
# VSn pours | input FETs (drain down onto the Vn pours) | TVS, input cap,
# OR diode, UV/OV divider per input | ATO fuse holders | LEDs | connectors on the
# front edge, plugged vertically from the open top. FET columns 11-14 mm apart:
# banana x 6/17/28 (28 = third pair, DNP), PCIe x 42, Molex x 56. The LTC4417,
# soft start, rocker connector and LED logic sit to the right of them.
FET_OUT_ROT, FET_IN_ROT = 90, 270
for x, qi, qo in ((6, 'Q501', 'Q503'), (17, 'Q502', 'Q504'), (28, 'Q512', 'Q513'),
                  (42, 'Q505', 'Q506'), (56, 'Q507', 'Q508')):
    MAIN[qo] = (x, 85, FET_OUT_ROT)
    MAIN[qi] = (x, 99, FET_IN_ROT)
for n, xb in ((1, 1), (2, 26), (3, 51)):          # per-input chain over its fuse
    MAIN['D%d' % (500 + n)] = (xb + 6, 109, 0)        # TVS
    MAIN['C%d' % (500 + n)] = (xb + 13.5, 109, 90)    # 1u input cap
    MAIN['D%d' % (503 + n)] = (xb + 16.5, 109, 90)    # OR diode
    for k in range(3):
        MAIN['R%d' % (500 + 10 * n + k)] = (xb + 19.5 + 2 * k, 109, 90)
    MAIN['F%d' % n] = (xb + 5, 117.5, 0)
MAIN.update({
    # front edge: banana pair (19.05 mm), PCIe 2x4, Molex 4-pin, rocker cable
    'J50': (8, 131), 'J51': (27.05, 131), 'J52': (38.5, 127.5), 'J53': (61, 131),
    'J54': (86, 132),
    'D507': (17.5, 123.6), 'D508': (50, 123.6), 'D509': (67, 123.6),
    # LTC4417, decoupling, HYS, soft start
    'U50': (70, 92, 0), 'R501': (64.2, 92, 90),
    'C504': (68, 83.5, 0), 'C505': (74, 83.5, 0),
    # master switch passives and bypass jumper by the rocker connector
    'R502': (84, 125, 0), 'R503': (89, 125, 0), 'R504': (92.5, 125, 0), 'C506': (96, 125, 0),
    'R505': (99.5, 125, 0), 'R506': (103, 125, 0), 'C507': (106.5, 125, 0), 'JP2': (97.5, 129.5, 0),
    # input-selected LED logic
    'R507': (84, 110, 90), 'R508': (86.5, 110, 90), 'R509': (89, 110, 90),
    'R540': (91.5, 110, 90), 'R541': (94, 110, 90), 'R542': (96.5, 110, 90),
    'Q509': (85, 104.5, 0), 'Q510': (90, 104.5, 0), 'Q511': (95, 104.5, 0),   # moved for F4 (0055)
    # the one temperature sensor: between the banana FETs and the PCIe pair, on the VS copper
    'U13': (35, 92, 90), 'C405': (35, 98.5, 90),
    'H7': (112, 134), 'H8': (226.5, 134),
})
for n in (1, 2, 3):        # gate drive (datasheet Fig. 8): CS, RS, DS per channel
    MAIN['C%d' % (510 + n)] = (78 + 5 * (n - 1), 92, 90)
    MAIN['R%d' % (500 + 10 * n + 3)] = (80.5 + 5 * (n - 1), 92, 90)
    MAIN['D%d' % (509 + n)] = (79.25 + 5 * (n - 1), 96.8, 90)
# CVS bypass (VSn -> GND) on each VS pour, between the FET rows
MAIN.update({'C514': (11.5, 92, 90), 'C515': (47, 92, 90), 'C516': (60, 92, 90),
             # LTC4417 VOUT pin RC filter (datasheet Fig. 10) by U50
             'R543': (76, 89, 90), 'C517': (78, 86.2, 90)})

# 5 V DUT outputs (issue 0055). Input: F4 continues the fuse row behind J53
# (its pin 1 picks up J53 pin 4 on a B.Cu strip), TVS / caps / LED / sense
# right of it, then the +5V bus on a B.Cu strip (y 112.5-121, then up x
# 161.5-169, passing H2) to the 5 V eFuse row on the rear edge, x 170-213,
# right of the GS105 jack. Cells at 15 mm pitch: JST VH connector on the edge,
# eFuse below it.
CELLS5 = {}
MAIN.update({
    'F4': (81, 117.5, 0), 'D600': (102.5, 117, 0), 'C600': (108.5, 117, 90),
    'R603': (112, 117, 90), 'D601': (78.5, 124.2, 0), 'R601': (114.5, 117, 90), 'R602': (117, 117, 90),
    'R604': (214.5, 28.5, 0), 'R605': (217.7, 28.5, 0), 'C602': (220.9, 28.5, 0), 'C601': (216, 33, 0),
})
for k, n in enumerate((5, 6, 7)):
    cx = 171 + 15 * k
    base = 610 + 10 * k
    CELLS5[n] = cx
    MAIN['J%d' % (61 + k)] = (cx + 3, 7.5, 0)
    MAIN['U%d' % (61 + k)] = (cx + 2.5, 24, 90)
    MAIN['D%d' % base] = (cx + 5, 17, 0)
    MAIN['D%d' % (base + 1)] = (cx + 10.5, 21.5, 90)
    MAIN['R%d' % (base + 4)] = (cx + 10.5, 17.5, 90)
    for i, ref in enumerate(['R%d' % (base + 1), 'R%d' % (base + 2), 'C%d' % base, 'C%d' % (base + 1)]):
        MAIN[ref] = (cx + 1 + (i % 3) * 3.2, 28.5 + (i // 3) * 2.2, 0)
    MAIN['C%d' % (base + 2)] = (cx + 1.5, 34, 0)
    MAIN['C%d' % (base + 3)] = (cx + 5, 20.6, 0)
    # channel selector by the CTRL header J3: pin 1 (rear) = 12 V, pin 3 (front) = 5 V
    MAIN['JP%d' % n] = (100 + 5 * k, 63, 0)

BOARDS = {
    'main': {
        'name': 'mega-kvm-power-main',
        'origin': (100, 100),
        'size': (230, 138.5),
        'place': MAIN,
        'zones': [
            ('GND', 'B', [(0.5, 0.5), (229.5, 0.5), (229.5, 138), (0.5, 138)]),
            ('VBUS', 'F', [(1, 24.1), (143, 24.1), (143, 60), (80, 60), (80, 85.6), (1, 85.6)]),
            # input stage pours (F): VSn between the FET rows, Vn from the input FETs
            # down over each input's TVS/cap/OR/divider chain to its fuse
            ('VS1', 'F', [(1, 86), (34, 86), (34, 97.6), (1, 97.6)]),
            ('VS2', 'F', [(34.5, 86), (49, 86), (49, 97.6), (34.5, 97.6)]),
            ('VS3', 'F', [(49.5, 86), (62, 86), (62, 97.6), (49.5, 97.6)]),
            ('V1', 'F', [(1, 98), (34, 98), (34, 104.8), (25.5, 104.8), (25.5, 113.5), (1, 113.5)]),
            ('V2', 'F', [(34.5, 98), (49, 98), (49, 104.8), (50.5, 104.8), (50.5, 113.5), (26, 113.5),
                         (26, 105.2), (34.5, 105.2)]),
            ('V3', 'F', [(49.5, 98), (62, 98), (62, 104.8), (76, 104.8), (76, 113.5), (51, 113.5),
                         (51, 105.2), (49.5, 105.2)]),
            ('AON12', 'F', [(118.5, 1), (158, 1), (158, 38), (229, 38), (229, 113), (170, 113),
                            (170, 61), (146, 61), (146, 23.9), (118.5, 23.9)]),
            # 5 V (issue 0055): J53 pin 4 -> F4 pin 1 and F4 pin 2 -> eFuse row on B.Cu strips
            # (they cut the B.Cu GND plane; stitch GND around them when routing),
            # F.Cu pours at the TVS/caps and under the 5 V eFuse row
            ('+5V_RAW', 'B', [(74.5, 115.5), (86, 115.5), (86, 121.5), (78.5, 121.5), (78.5, 133.5),
                              (74.5, 133.5)], 1),
            ('+5V', 'B', [(88.5, 112.5), (161.5, 112.5), (161.5, 34), (169, 34), (169, 121), (88.5, 121)], 1),
            ('+5V', 'F', [(88.5, 112.5), (119, 112.5), (119, 123.3), (88.5, 123.3)]),
            ('+5V', 'F', [(169.6, 24.1), (222.5, 24.1), (222.5, 37), (169.6, 37), (169.6, 35.9),
                          (161.5, 35.9), (161.5, 34), (169.6, 34)]),
        ] + [('OUT5V%d' % n, 'F', [(cx - 1.4, 1), (cx + 11.4, 1), (cx + 11.4, 23.9), (cx - 1.4, 23.9)])
             for n, cx in CELLS5.items()] + [('OUT%d' % n, 'F', [(8.6 + n * 13.5, 1), (21.4 + n * 13.5, 1),
                                 (21.4 + n * 13.5, 23.9), (8.6 + n * 13.5, 23.9)]) for n in range(8)],
        'texts': [('MEGA-KVM power v0.4 (one board)  2 oz Cu  VBUS 12 V 25 A', 50, 50, 'F', 1.5),
                  ('IN1 BANANA 25A', 17.5, 137.3, 'F', 0.8), ('IN2 PCIe 15A', 46, 137.3, 'F', 0.8),
                  ('IN3 MOLEX 10A (+5V: F4)', 69, 137.3, 'F', 0.8), ('ROCKER', 88.5, 137.3, 'F', 0.8),
                  ('5V', 75.3, 124.2, 'F', 0.8),
                  ('JP5-7: 1-2 = 12V, 2-3 = 5V, none = off', 105, 57.8, 'F', 0.8),
                  ('12V', 96.4, 63, 'F', 0.8), ('5V', 96.4, 68.1, 'F', 0.8),
                  ('5V ONLY (JST VH): channel set by JP5-7', 182, 39.0, 'F', 0.8),
                  ('DUT0', 10.5, 21, 'F', 1.0), ('DUT7', 105, 21, 'F', 1.0),
                  ('MIMAS / GS105 (always on)', 140, 32, 'F', 1.0),
                  ('CTRL: 1 GND 2 KEY 3-10 CH0-7 11 PRESENT', 104, 78.5, 'F', 0.8),
                  ('FANS 1 GND 2 +12V 3 TACH 4 PWM', 186, 116.5, 'F', 0.8)]
                 + [('DUT%d 5V ONLY' % n, cx + 5, 14.2, 'F', 0.9) for n, cx in CELLS5.items()]
                 + [('FAN%d %s' % (k, ['KVM', 'KVM', 'A', 'A', 'A', 'B', 'B', 'B'][k]),
                     FAN_CELLS[k][0] + 7.6, FAN_CELLS[k][1] + 9.4, 'F', 0.8) for k in range(8)],
    },
}

# ------------------------------------------------------------------ input board
# 126 x 64 mm (v0.3), standing vertically behind the 3RU KVM front panel (issue
# 0051 round 10). The old 197 x 34 mm strip was sized for a 1RU rear panel;
# on the 3RU front, width is the scarce dimension (2 x 120 mm fans + display
# group), height is not. F side faces the panel: connectors and LEDs. B side
# (inside): everything else. Two tiers:
#   top    (y 0-34):  connectors (F) with LED logic, LDO, rocker J5 and the
#                     master-switch passives behind them (B) | fuses | TVS,
#                     caps, OR diodes | UV/OV dividers | V1 riser (x 111-126)
#   bottom (y 34-64): lugs | LTC4417, temp cable J8, soft start | FET columns:
#                     PCIe, Molex, banana x 3 (third pair DNP). Each column is
#                     a back-to-back pair, input FET on top (drain on the Vn
#                     pour), output FET below (drain on the VBUS strip),
#                     sources facing each other on the VSn pour; columns 14 mm
#                     apart so the heat spreads (0047 round 9).
INP = {
    # F side: connectors and input-selected LEDs
    'J1': (9.5, 11.5), 'J2': (9.5, 30.55), 'J3': (19.5, 4.5), 'J4': (41.5, 7.5),
    'D7': (17, 15), 'D8': (26, 15), 'D9': (48, 15),
    # B side behind the connectors: LED logic, LDO, rocker connector, master passives
    'R7': (18, 17, 90, 'B'), 'R8': (20.5, 17, 90, 'B'), 'R9': (23, 17, 90, 'B'),
    'R40': (25.5, 17, 90, 'B'), 'R41': (28, 17, 90, 'B'), 'R42': (30.5, 17, 90, 'B'),
    'Q9': (19, 22.5, 0, 'B'), 'Q10': (24, 22.5, 0, 'B'), 'Q11': (29, 22.5, 0, 'B'),
    'U2': (35, 22.5, 0, 'B'), 'C8': (41, 22.5, 90, 'B'), 'C9': (43.5, 22.5, 90, 'B'),
    'J5': (49, 21, 0, 'B'), 'JP1': (47, 28.5, 0, 'B'),
    'R2': (19, 28.5, 0, 'B'), 'R3': (24, 28.5, 0, 'B'), 'R4': (27.5, 28.5, 0, 'B'), 'C6': (31, 28.5, 0, 'B'),
    'R5': (34.5, 28.5, 0, 'B'), 'R6': (38, 28.5, 0, 'B'), 'C7': (41.5, 28.5, 0, 'B'),
    # fuses (rotated so the fused side faces right, towards the TVS)
    'F1': (64.5, 6, 0, 'B'), 'F2': (64.5, 16, 0, 'B'), 'F3': (64.5, 26, 0, 'B'),
    # TVS, input caps, diode-OR
    'D1': (88, 5, 0, 'B'), 'D2': (88, 15, 0, 'B'), 'D3': (88, 25, 0, 'B'),
    'C1': (96, 5, 90, 'B'), 'C2': (96, 15, 90, 'B'), 'C3': (96, 25, 90, 'B'),
    'D4': (99.8, 5, 90, 'B'), 'D5': (99.8, 15, 90, 'B'), 'D6': (99.8, 25, 90, 'B'),
    # bottom tier
    'J7': (9, 45), 'J6': (9, 57.5),
    'U1': (24, 50, 0, 'B'), 'R1': (16.5, 50, 90, 'B'),
    'J8': (36, 37.8, 0, 'B'),
    'C4': (33, 58.5, 0, 'B'), 'C5': (39, 58.5, 0, 'B'),
    'U3': (95, 48, 90, 'B'), 'C14': (95, 55.5, 90, 'B'),
    'H1': (3.5, 3.5), 'H2': (122.5, 60.5), 'H3': (122.5, 3.5),
}
FET_IN_ROT, FET_OUT_ROT = 90, 270
for x, qi, qo in ((54, 'Q5', 'Q6'), (68, 'Q7', 'Q8'), (88, 'Q1', 'Q3'), (102, 'Q2', 'Q4'), (116, 'Q12', 'Q13')):
    INP[qi] = (x, 40, FET_IN_ROT, 'B')
    INP[qo] = (x, 56, FET_OUT_ROT, 'B')
for n in (1, 2, 3):        # UV/OV dividers
    for k in range(3):
        INP['R%d' % (10 * n + k)] = (103.5 + k * 2.5, 5 + 10 * (n - 1), 90, 'B')
for n in (1, 2, 3):        # soft-start RC between the LTC4417 and the FETs
    INP['C%d' % (10 + n)] = (32 + 5 * (n - 1), 47.5, 90, 'B')
    INP['R%d' % (10 * n + 3)] = (34.5 + 5 * (n - 1), 47.5, 90, 'B')

BOARDS['inputs'] = {
    'name': 'mega-kvm-power-inputs',
    'origin': (100, 100),
    'size': (126, 64),
    'place': INP,
    'zones': [
        ('GND', 'F', [(0.5, 0.5), (125.5, 0.5), (125.5, 63.5), (0.5, 63.5)]),
        # banana: V1 riser from the TVS/fuse column down the right edge, then
        # along the top of the three banana input FETs
        ('V1', 'B', [(110.5, 0.5), (125.5, 0.5), (125.5, 41.4), (82, 41.4), (82, 34), (110.5, 34)]),
        ('VS1', 'B', [(82, 41.8), (121, 41.8), (121, 54.2), (82, 54.2)]),
        ('V2', 'B', [(49, 34), (59.5, 34), (59.5, 41.4), (49, 41.4)]),
        ('VS2', 'B', [(49, 41.8), (59.5, 41.8), (59.5, 54.2), (49, 54.2)]),
        ('V3', 'B', [(63, 34), (73.5, 34), (73.5, 41.4), (63, 41.4)]),
        ('VS3', 'B', [(63, 41.8), (73.5, 41.8), (73.5, 54.2), (63, 54.2)]),
        ('VBUS', 'B', [(1, 54.6), (125.5, 54.6), (125.5, 63.5), (1, 63.5)]),
    ],
    'texts': [('IN1 BANANA 25A', 9.5, 21.0, 'F', 1.0), ('IN2 PCIe 15A', 26, 18.5, 'F', 1.0),
              ('IN3 MOLEX 10A', 48, 18.5, 'F', 1.0), ('MEGA-KVM power inputs v0.3', 62, 62.3, 'B', 1.0)],
}
