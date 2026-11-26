"""Shared mechanical numbers for the shield and the keyboard sub-board
(Mimas coordinates, mm: origin at the Mimas corner between the RJ45 edge and
the P13 edge, x towards the HDMI edge, y towards P12)."""

MIMAS_W, MIMAS_H = 120.0, 90.0
REAR = MIMAS_W

# Rear-edge slots (y0, y1). Shield level: JB1 in the overhangs beside the
# Mimas (round 6: shortest JTAG routes, keyboard J5 directly below on the
# sub-boards), header HDMIs above the Mimas between its two rear holes.
JB1_LEN, JB1_GAP = 24.0, 0.2
HDMI_LEN, HDMI_GAP = 21.0, 0.6
P12_START, P13_START = 90.6, -0.6      # clear of the Mimas board edge/sockets
SLOTS = {
    'JTAG0J': (P12_START, P12_START + JB1_LEN),
    'JTAG3J': (P12_START + JB1_LEN + JB1_GAP, P12_START + 2 * JB1_LEN + JB1_GAP),
    'JTAG1J': (P13_START - JB1_LEN, P13_START),
    'JTAG2J': (P13_START - 2 * JB1_LEN - JB1_GAP, P13_START - JB1_LEN - JB1_GAP),
    'HDMI3J': (81.2 - HDMI_LEN, 81.2),
    'HDMI2J': (81.2 - 2 * HDMI_LEN - HDMI_GAP, 81.2 - HDMI_LEN - HDMI_GAP),
    'HDMI1J': (81.2 - 3 * HDMI_LEN - 2 * HDMI_GAP, 81.2 - 2 * HDMI_LEN - 2 * HDMI_GAP),
}
Y_TOP = round(SLOTS['JTAG3J'][1] + 1.0, 1)
Y_BOT = round(SLOTS['JTAG2J'][0] - 1.0, 1)

# Keyboard sub-board, P12-side instance; the P13-side instance is the same
# board moved by KBD_DY (slot A = lower y: P12 A=DUT0 B=DUT3, P13 A=DUT2 B=DUT1).
KBD_X0, KBD_X1 = 86.0, REAR
KBD_Y0, KBD_Y1 = 90.8, Y_TOP - 1.2
KBD_DY = SLOTS['JTAG2J'][0] - SLOTS['JTAG0J'][0]
KBD_J5 = {'A': sum(SLOTS['JTAG0J']) / 2, 'B': sum(SLOTS['JTAG3J']) / 2}   # J5 centres = JB1 centres
KBD_B2B = (90.0, (KBD_Y0 + KBD_Y1) / 2)          # 2x6 header centre
KBD_HOLES = [(89.0, KBD_Y0 + 3.5), (89.0, KBD_Y1 - 3.5), (100.0, (KBD_Y0 + KBD_Y1) / 2)]

# Stack (z above the case floor), for docs and checks
STANDOFF = 3.0                 # Mimas and sub-board standoffs
PCB = 1.6
HDR_STACK = 2.54 + 8.5         # male header plastic + 8.5 mm female socket
Z_MIMAS_TOP = STANDOFF + PCB
Z_SHIELD_BOT = Z_MIMAS_TOP + HDR_STACK
Z_SHIELD_TOP = Z_SHIELD_BOT + PCB
