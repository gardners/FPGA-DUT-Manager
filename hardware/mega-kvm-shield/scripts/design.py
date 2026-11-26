"""MEGA-KVM link-board shield: the circuit, as data.

Every component is a dict: ref prefix, symbol, value, footprint, LCSC part,
the sheet it is drawn on, the PCB cluster it is placed in, and its pin->net
map. gen_sch.py turns this into the KiCad schematic, gen_pcb.py into the
board. Change the circuit here, then rerun `make` in this directory.

Header pin plan and expander bit maps: docs/hardware/shield-pinplan.md v1
(issue 0049 gate build passed, 4 DUTs). Net names follow that document;
the Mimas VADJ_3V3 rows are the +3V3 power net here.
"""

N_DUT = 4                 # DUT0..DUT3; DUT0 video = Mimas HDMI IN
HDMI_DUTS = [1, 2, 3]     # DUTs with a header HDMI receiver on the shield
REVISION = 0x01           # shield revision strapped on TCA6424A port 0

# --------------------------------------------------------------------------
# Header pin plan, shield-pinplan.md v1. Keys: (row, column). Rows 1-2 VIN,
# 9/15/21 VADJ 3.3 V, 3/8/14/20/24/27/30/33/40 GND, 34-39 configuration pins
# (never connected). Column A = P, column B = N of each pair. Spares are
# left unconnected (no pad net).
# --------------------------------------------------------------------------
HEADER_PLAN = {
    'P12': {
        (4, 'A'): 'DUT0_TCK', (4, 'B'): 'DUT0_UART_FROM',
        (5, 'A'): 'DUT0_TDO', (5, 'B'): 'DUT0_UART_TO',
        (6, 'A'): 'DUT0_TDI', (6, 'B'): 'DUT3_TDO',
        (7, 'A'): 'DUT0_TMS', (7, 'B'): 'PK_TCK',
        (10, 'A'): 'PK_KIO10', (10, 'B'): 'PK_KIO9',
        (11, 'A'): 'PK_KIO8', (11, 'B'): 'PK_TDO',
        (12, 'A'): 'HDMI3_CLK_P', (12, 'B'): 'HDMI3_CLK_N',
        (13, 'A'): 'HDMI3_D0_P', (13, 'B'): 'HDMI3_D0_N',
        (16, 'A'): 'DUT0_KIO10', (16, 'B'): 'DUT0_KIO9',
        (17, 'A'): 'DUT0_KIO8', (17, 'B'): 'PK_TMS',
        (18, 'A'): 'HDMI3_D1_P', (18, 'B'): 'HDMI3_D1_N',
        (19, 'A'): 'HDMI3_D2_P', (19, 'B'): 'HDMI3_D2_N',
        (22, 'A'): None, (22, 'B'): 'PK_TDI',          # 22A = SP_P12_H17
        (23, 'A'): 'NB_UART_TX', (23, 'B'): 'NB_UART_RX',
        (25, 'A'): 'I2C_SCL', (25, 'B'): 'I2C_SDA',
        (26, 'A'): 'DUT3_KIO10', (26, 'B'): 'DUT3_KIO9',
        (28, 'A'): 'DUT3_TCK', (28, 'B'): 'DUT3_UART_FROM',
        (29, 'A'): 'DUT3_TDI', (29, 'B'): 'DUT3_UART_TO',
        (31, 'A'): 'DUT3_TMS', (31, 'B'): 'DUT3_KIO8',
        (32, 'A'): 'HDMI3_SCL', (32, 'B'): 'HDMI3_SDA',
    },
    'P13': {
        (4, 'A'): 'DUT1_TCK', (4, 'B'): 'DUT1_UART_FROM',
        (5, 'A'): 'DUT1_TDO', (5, 'B'): 'DUT1_UART_TO',
        (6, 'A'): 'DUT1_TDI', (6, 'B'): 'DUT2_TDO',
        (7, 'A'): 'DUT1_TMS', (7, 'B'): None,           # SP_P13_B22
        (10, 'A'): 'HDMI1_D0_P', (10, 'B'): 'HDMI1_D0_N',
        (11, 'A'): 'HDMI1_CLK_P', (11, 'B'): 'HDMI1_CLK_N',
        (12, 'A'): 'HDMI2_CLK_P', (12, 'B'): 'HDMI2_CLK_N',
        (13, 'A'): 'HDMI1_D1_P', (13, 'B'): 'HDMI1_D1_N',
        (16, 'A'): 'DUT1_KIO10', (16, 'B'): 'DUT1_KIO9',
        (17, 'A'): 'DUT1_KIO8', (17, 'B'): None,         # SP_P13_A19
        (18, 'A'): 'HDMI1_D2_P', (18, 'B'): 'HDMI1_D2_N',
        (19, 'A'): 'HDMI2_D0_P', (19, 'B'): 'HDMI2_D0_N',
        (22, 'A'): 'DUT2_KIO9', (22, 'B'): 'DUT2_KIO10',
        (23, 'A'): 'HDMI2_D1_P', (23, 'B'): 'HDMI2_D1_N',
        (25, 'A'): 'HDMI2_D2_P', (25, 'B'): 'HDMI2_D2_N',
        (26, 'A'): 'HDMI1_SCL', (26, 'B'): 'HDMI1_SDA',
        (28, 'A'): 'HDMI2_SCL', (28, 'B'): 'HDMI2_SDA',
        (29, 'A'): 'DUT2_TCK', (29, 'B'): 'DUT2_UART_FROM',
        (31, 'A'): 'DUT2_TDI', (31, 'B'): 'DUT2_UART_TO',
        (32, 'A'): 'DUT2_TMS', (32, 'B'): 'DUT2_KIO8',
    },
}

ROW_VIN = (1, 2)
ROW_VADJ = (9, 15, 21)
ROW_GND = (3, 8, 14, 20, 24, 27, 30, 33, 40)
ROW_CFG = (34, 35, 36, 37, 38, 39)

# --------------------------------------------------------------------------
# Part catalogue: symbol, footprint, LCSC number ('' = to be chosen; see
# docs/hardware/shield.md BOM notes).  JLC basic parts preferred.
# --------------------------------------------------------------------------
R0402 = 'Resistor_SMD:R_0402_1005Metric'
C0402 = 'Capacitor_SMD:C_0402_1005Metric'
LCSC_R = {  # 0402 1 % thick film, JLC basic parts
    '33': 'C25105', '47': 'C25118', '49.9': 'C25120', '1k': 'C11702',
    '2.2k': 'C25879', '4.7k': 'C25900', '10k': 'C25744', '15k': 'C25756',
    '20k': 'C25765', '47k': 'C25792', '100k': 'C25741', '200k': 'C25811',
    '100': 'C25076',
}

parts = []
BOARD = ['shield']          # board the next parts belong to


def part(prefix, sym, value, fp, pins, sheet, cluster, lcsc='', dnp=False,
         descr='', mpn=''):
    p = dict(prefix=prefix, sym=sym, value=value, fp=fp, pins=dict(pins),
             sheet=sheet, cluster=cluster, lcsc=lcsc, dnp=dnp, descr=descr,
             mpn=mpn, board=BOARD[0])
    parts.append(p)
    return p


def R(value, a, b, sheet, cluster, dnp=False):
    return part('R', 'Device:R', value, R0402, {'1': a, '2': b}, sheet, cluster,
                LCSC_R.get(value, ''), dnp)


def C(value, a, b, sheet, cluster, fp=C0402, lcsc=None):
    if lcsc is None:
        lcsc = {'100n': 'C1525', '10u': 'C15850'}.get(value, '')
    return part('C', 'Device:C', value, fp, {'1': a, '2': b}, sheet, cluster, lcsc)


def flag(net, sheet, cluster='MISC'):
    return part('#FLG', 'power:PWR_FLAG', 'PWR_FLAG', '', {'1': net}, sheet, cluster)


# ------------------------------- headers ---------------------------------
def header_pins(h):
    pins = {}
    plan = HEADER_PLAN[h]
    for row in range(1, 41):
        for col in 'AB':
            n = '%s%d' % (col, row)
            if row in ROW_VIN:
                pins[n] = '+12V'
            elif row in ROW_VADJ:
                pins[n] = '+3V3'
            elif row in ROW_GND:
                pins[n] = 'GND'
            elif row in ROW_CFG:
                pins[n] = None            # never connect (FPGA config pins)
            else:
                pins[n] = plan.get((row, col))  # None = spare, no connect
    return pins


S_HDR = 'mimas_headers'
part('P', 'shield:Mimas_Header_2x40', 'P12 socket (DUT0/DUT3 side)',
     'shield:Mimas_Header_Socket_2x40', header_pins('P12'), S_HDR, 'P12',
     descr='2x40 female socket 2.54 mm, 8.5 mm, bottom side, mates Mimas P12')
part('P', 'shield:Mimas_Header_2x40', 'P13 socket (DUT1/DUT2 side)',
     'shield:Mimas_Header_Socket_2x40', header_pins('P13'), S_HDR, 'P13',
     descr='2x40 female socket 2.54 mm, 8.5 mm, bottom side, mates Mimas P13')

# 12 V input from the power board (0047 always-on output) -> header VIN
part('J', 'Connector_Generic:Conn_01x02', '12V IN',
     'Connector_Molex:Molex_Mini-Fit_Jr_5566-02A_2x01_P4.20mm_Vertical',
     {'1': '+12V', '2': 'GND'}, S_HDR, 'PWR', descr='Molex Mini-Fit Jr 2-pin vertical, 12 V in',
     mpn='Molex 5566-02A (39-30-1020 class)')
part('D', 'Device:D_TVS', 'SMBJ15A', 'Diode_SMD:D_SMB',
     {'1': '+12V', '2': 'GND'}, S_HDR, 'PWR', descr='TVS 15 V standoff')
C('10u', '+12V', 'GND', S_HDR, 'PWR', fp='Capacitor_SMD:C_1206_3216Metric', lcsc='')
C('10u', '+12V', 'GND', S_HDR, 'PWR', fp='Capacitor_SMD:C_1206_3216Metric', lcsc='')
C('10u', '+3V3', 'GND', S_HDR, 'EXP', fp='Capacitor_SMD:C_0805_2012Metric')
flag('+12V', S_HDR)
flag('+3V3', S_HDR)
flag('GND', S_HDR)
for i in range(8):
    part('H', 'Mechanical:MountingHole', 'M3', 'MountingHole:MountingHole_3.2mm_M3',
         {}, S_HDR, 'HOLE%d' % i)

# ------------------------------- HDMI inputs -----------------------------
for n in HDMI_DUTS:
    s = 'hdmi_rx_dut%d' % n
    cl = 'HDMI%d' % n
    p5 = 'HDMI%d_5V' % n
    nm = lambda x: 'HDMI%d_%s' % (n, x)
    part('J', 'Connector:HDMI_A', 'DUT%d HDMI IN' % n,
         'Connector_Video:HDMI_A_Amphenol_10029449-x01xLF_Horizontal',
         {'1': nm('D2_P'), '3': nm('D2_N'), '4': nm('D1_P'), '6': nm('D1_N'),
          '7': nm('D0_P'), '9': nm('D0_N'), '10': nm('CLK_P'), '12': nm('CLK_N'),
          '13': None, '14': None, '15': nm('DDC_SCL'), '16': nm('DDC_SDA'),
          '19': nm('HPD'), '18': p5, '2': 'GND', '5': 'GND', '8': 'GND',
          '11': 'GND', '17': 'GND', 'SH': 'GND'}, s, cl + 'J',
         descr='HDMI type A receptacle, right angle', mpn='Amphenol 10029449-111RLF')
    # 50 ohm termination to 3.3 V (TMDS_33 has no internal termination)
    for lane in ('D0', 'D1', 'D2', 'CLK'):
        for pol in 'PN':
            R('49.9', '+3V3', nm('%s_%s' % (lane, pol)), s, cl)
    # low-capacitance ESD, flow-through
    part('U', 'Power_Protection:TPD4E05U06DQA', 'TPD4E05U06',
         'Package_SON:USON-10_2.5x1.0mm_P0.5mm',
         {'1': nm('D2_P'), '2': nm('D2_N'), '4': nm('D1_P'), '5': nm('D1_N'),
          '3': 'GND', '8': 'GND', '6': None, '7': None, '9': None, '10': None},
         s, cl, lcsc='C138714')
    part('U', 'Power_Protection:TPD4E05U06DQA', 'TPD4E05U06',
         'Package_SON:USON-10_2.5x1.0mm_P0.5mm',
         {'1': nm('D0_P'), '2': nm('D0_N'), '4': nm('CLK_P'), '5': nm('CLK_N'),
          '3': 'GND', '8': 'GND', '6': None, '7': None, '9': None, '10': None},
         s, cl, lcsc='C138714')
    # DDC level shifter: FPGA side 3.3 V, source side the source's +5 V
    part('U', 'Interface:PCA9306DC', 'PCA9306DCUR', 'Package_SO:VSSOP-8_2.3x2mm_P0.5mm',
         {'1': 'GND', '2': '+3V3', '3': nm('SCL'), '4': nm('SDA'),
          '5': nm('DDC_SDA'), '6': nm('DDC_SCL'), '7': nm('VREF2'),
          '8': nm('VREF2')}, s, cl)
    R('200k', p5, nm('VREF2'), s, cl)
    C('100n', nm('VREF2'), 'GND', s, cl)
    C('100n', '+3V3', 'GND', s, cl)
    R('4.7k', '+3V3', nm('SCL'), s, cl)
    R('4.7k', '+3V3', nm('SDA'), s, cl)
    R('47k', p5, nm('DDC_SCL'), s, cl)
    R('47k', p5, nm('DDC_SDA'), s, cl)
    # HPD: expander output -> NMOS -> PMOS high side from +5 V -> 1 k -> pin 19
    part('Q', 'Transistor_FET:BSS84', 'AO3401A', 'Package_TO_SOT_SMD:SOT-23',
         {'1': nm('HPD_G'), '2': p5, '3': nm('HPD_SW')}, s, cl, lcsc='C15127',
         descr='P-MOSFET (AO3401A pin-compatible with BSS84 symbol: G1 S2 D3)')
    part('Q', 'Transistor_FET:2N7002', '2N7002', 'Package_TO_SOT_SMD:SOT-23',
         {'1': nm('HPD_EN'), '2': 'GND', '3': nm('HPD_G')}, s, cl, lcsc='C8545')
    R('100k', p5, nm('HPD_G'), s, cl)
    R('100k', nm('HPD_EN'), 'GND', s, cl)
    R('1k', nm('HPD_SW'), nm('HPD'), s, cl)
    R('100k', nm('HPD'), 'GND', s, cl)
    # +5V (source connected) sense, 5 V -> 3.0 V
    R('10k', p5, nm('5V_SENSE'), s, cl)
    R('15k', nm('5V_SENSE'), 'GND', s, cl)
    C('100n', p5, 'GND', s, cl)
    flag(p5, s)
    flag(nm('VREF2'), s)

# ------------------------------- DUT ports -------------------------------
S_DUT = 'dut_ports'
# Round 6 (owner): per DUT the JB1 2x6 sits on the shield at the panel edge
# (shortest JTAG routes); its J5 2x5 sits directly below on a keyboard
# sub-board under the shield overhang beside the Mimas. One sub-board per
# side carries two J5 (slot A = lower Mimas y, slot B = higher), joined to
# the shield by a 2x6 board-to-board header (KIO8/9/10 + 3.3 V sense per DUT).
# One identical sub-board design on both sides (translated, not mirrored).
KBD_SIDES = {'P12': {'A': 0, 'B': 3}, 'P13': {'A': 2, 'B': 1}}
B2B_PINS = {'1': 'GND', '2': 'GND', '3': 'A_KIO8', '4': 'A_KIO9', '5': 'A_KIO10',
            '6': 'A_KB_SENSE', '7': 'B_KIO8', '8': 'B_KIO9', '9': 'B_KIO10',
            '10': 'B_KB_SENSE', '11': 'GND', '12': 'GND'}
for n in range(N_DUT):
    d = lambda x: 'DUT%d_%s' % (n, x)
    j = lambda x: 'DUT%d_JB_%s' % (n, x)
    cj = 'JTAG%d' % n
    # JB1 / TE0790 style 2x6, MEGA65 pin numbering
    part('J', 'Connector_Generic:Conn_02x06_Odd_Even', 'DUT%d JTAG+UART (JB1)' % n,
         'Connector_IDC:IDC-Header_2x06_P2.54mm_Horizontal',
         {'1': 'GND', '2': 'GND', '3': j('UART_FROM'), '4': j('TCK'), '5': None,
          '6': j('VIO'), '7': j('UART_TO'), '8': j('TDO'), '9': None,
          '10': j('TDI'), '11': None, '12': j('TMS')}, S_DUT, cj + 'J',
         descr='2x6 box header, right angle')
    for sig in ('UART_FROM', 'TCK', 'UART_TO', 'TDO', 'TDI', 'TMS'):
        R('47', d(sig), j(sig), S_DUT, cj)
    R('10k', j('VIO'), d('VIO_SENSE'), S_DUT, cj)
    R('100k', d('VIO_SENSE'), 'GND', S_DUT, cj)
    R('100k', d('KB_SENSE'), 'GND', S_DUT, cj)
for side, slots in KBD_SIDES.items():
    m = {}
    for k, v in B2B_PINS.items():
        if v == 'GND':
            m[k] = 'GND'
        else:
            slot, sig = v.split('_', 1)
            m[k] = 'DUT%d_%s' % (slots[slot], sig)
    part('J', 'Connector_Generic:Conn_02x06_Odd_Even', 'KBD SUB %s (B2B)' % side,
         'Connector_PinSocket_2.54mm:PinSocket_2x06_P2.54mm_Vertical', m, S_DUT,
         'B2B' + side, descr='2x6 female socket 2.54 mm, 11 mm tall, shield bottom side')

# ------------------------------- keyboard sub-board ----------------------
BOARD[0] = 'kbd'
S_KBD = 'kbd_sub'
part('J', 'Connector_Generic:Conn_02x06_Odd_Even', 'B2B to shield',
     'Connector_PinHeader_2.54mm:PinHeader_2x06_P2.54mm_Vertical', B2B_PINS, S_KBD,
     'B2B', descr='2x6 male header 2.54 mm, standard 2.54 mm plastic (into an 11 mm socket)')
for slot in 'AB':
    k = lambda x: '%s_J_%s' % (slot, x)
    part('J', 'Connector_Generic:Conn_02x05_Odd_Even', 'KEYBOARD %s (J5)' % slot,
         'Connector_IDC:IDC-Header_2x05_P2.54mm_Horizontal',
         {'1': 'GND', '2': k('3V3'), '3': None, '4': None, '5': None, '6': None,
          '7': None, '8': k('KIO8'), '9': k('KIO9'), '10': k('KIO10')},
         S_KBD, 'KBD' + slot + 'J', descr='2x5 box header, right angle')
    for sig in ('KIO8', 'KIO9', 'KIO10'):
        R('47', '%s_%s' % (slot, sig), k(sig), S_KBD, 'KBD' + slot)
    R('10k', k('3V3'), '%s_KB_SENSE' % slot, S_KBD, 'KBD' + slot)
flag('GND', S_KBD)
for i in range(3):
    part('H', 'Mechanical:MountingHole', 'M3', 'MountingHole:MountingHole_3.2mm_M3',
         {}, S_KBD, 'HOLE%d' % i)
BOARD[0] = 'shield'
KBD_SHEETS = [(S_KBD, 'Keyboard sub-board: 2 x J5 (DUT keyboards)')]

# ------------------------------- I/O expanders ---------------------------
S_EXP = 'io_expanders'
# Expander A, TCA6424A @0x22: P0 revision straps, P1 feature straps,
# P2 power-control outputs (shield-pinplan.md "I2C expanders")
exp24 = {'1': 'EXPA_INT_N', '2': '+3V3', '3': 'EXP_RESET_N', '28': 'GND',
         '29': 'I2C_SCL', '30': 'I2C_SDA', '31': '+3V3', '32': 'GND', '33': 'GND'}
for b in range(8):
    exp24[str(4 + b)] = 'SHD_REV%d' % b
    exp24[str(12 + b)] = 'SHD_FEAT%d' % b
    exp24[str(20 + b)] = 'PWR_CTL%d' % b
part('U', 'shield:TCA6424A', 'TCA6424ARGJR',
     'Package_DFN_QFN:QFN-32-1EP_5x5mm_P0.5mm_EP3.45x3.45mm', exp24, S_EXP, 'EXP',
     descr='24-bit I2C GPIO expander A, addr 0x22')
C('100n', '+3V3', 'GND', S_EXP, 'EXP')
C('100n', '+3V3', 'GND', S_EXP, 'EXP')
R('10k', '+3V3', 'EXP_RESET_N', S_EXP, 'EXP')
R('10k', '+3V3', 'EXPA_INT_N', S_EXP, 'EXP')


def strap(netname, high):
    """Two footprints per strap bit, exactly one populated."""
    R('10k', '+3V3', netname, S_EXP, 'EXP', dnp=not high)
    R('10k', netname, 'GND', S_EXP, 'EXP', dnp=high)


for b in range(8):
    strap('SHD_REV%d' % b, bool(REVISION >> b & 1))
# b0 HDMI1, b1 power header, b2 HDMI2, b3 HDMI3, b4 DUT2 ports, b5 DUT3
# ports, b6 neighbour UART, b7 reserved
FEATURES = [1 in HDMI_DUTS, True, 2 in HDMI_DUTS, 3 in HDMI_DUTS,
            N_DUT > 2, N_DUT > 3, True, False]
for b in range(8):
    strap('SHD_FEAT%d' % b, FEATURES[b])
for b in range(8):
    R('20k', 'PWR_CTL%d' % b, 'GND', S_EXP, 'EXP')
# power-control header to the power board: 1x11, pin 2 removed (key)
relay = {'1': 'GND', '2': None, '11': 'PWRB_PRESENT'}
for b in range(8):
    relay[str(3 + b)] = 'PWR_CTL%d' % b
part('J', 'Connector_Generic:Conn_01x11', 'POWER CTRL (pin 2 = key)',
     'Connector_PinHeader_2.54mm:PinHeader_1x11_P2.54mm_Vertical', relay, S_EXP,
     'RELAYJ', descr='1x11 pin header, pin 2 pulled for keying')
# PRESENT: the power board pulls it to 3.3 V through 10 k; weak pull-down here
R('100k', 'PWRB_PRESENT', 'GND', S_EXP, 'EXP')

# Expander B, TCA6416A @0x20 (PCAL6416A symbol, same pinout): slow lines
expb_p0 = ['HDMI1_HPD_EN', 'HDMI2_HPD_EN', 'HDMI3_HPD_EN', 'PK_JTAGEN',
           'HDMI1_5V_SENSE', 'HDMI2_5V_SENSE', 'HDMI3_5V_SENSE', 'PWRB_PRESENT']
expb_p1 = ['DUT%d_VIO_SENSE' % n for n in range(4)] + ['DUT%d_KB_SENSE' % n for n in range(4)]
exp16 = {'22': 'I2C_SCL', '23': 'I2C_SDA', '1': 'EXPB_INT_N', '3': 'EXP_RESET_N',
         '21': 'GND', '2': '+3V3', '24': '+3V3', '12': 'GND'}
for b in range(8):
    exp16[str(4 + b)] = expb_p0[b]
    exp16[str(13 + b)] = expb_p1[b]
part('U', 'Interface_Expansion:PCAL6416APW', 'TCA6416APWR',
     'Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm', exp16, S_EXP, 'EXP',
     descr='16-bit I2C GPIO expander B, addr 0x20 (TI TCA6416A)')
C('100n', '+3V3', 'GND', S_EXP, 'EXP')
C('100n', '+3V3', 'GND', S_EXP, 'EXP')
R('10k', '+3V3', 'EXPB_INT_N', S_EXP, 'EXP')
# I2C bus pull-ups and the front-panel I2C header (issue 0050)
R('2.2k', '+3V3', 'I2C_SCL', S_EXP, 'EXP')
R('2.2k', '+3V3', 'I2C_SDA', S_EXP, 'EXP')
part('J', 'Connector_Generic:Conn_01x06', 'I2C (front panel)',
     'Connector_PinHeader_2.54mm:PinHeader_1x06_P2.54mm_Horizontal',
     {'1': 'GND', '2': '+5V', '3': '+3V3', '4': 'I2C_SDA', '5': 'I2C_SCL', '6': 'EXPB_INT_N'},
     S_EXP, 'I2CJ', descr='1x6 right-angle header: GND 5V 3V3 SDA SCL INT')

# ------------------------------- physical keyboard + links ---------------
S_LNK = 'keyboard_link'
pk = {'1': 'GND', '2': 'PK_3V3'}
for pin, sig in (('3', 'JTAGEN'), ('4', 'TMS'), ('5', 'TCK'), ('6', 'TDI'),
                 ('7', 'TDO'), ('8', 'KIO8'), ('9', 'KIO9'), ('10', 'KIO10')):
    pk[pin] = 'PK_J_' + sig
    R('33', 'PK_' + sig, 'PK_J_' + sig, S_LNK, 'PK')
R('100k', 'PK_JTAGEN', 'GND', S_LNK, 'PK')
part('J', 'Connector_Generic:Conn_02x05_Odd_Even', 'PHYSICAL KEYBOARD (J5, with JTAG)',
     'Connector_IDC:IDC-Header_2x05_P2.54mm_Horizontal', pk, S_LNK, 'PKJ',
     descr='2x5 box header, right angle')
part('F', 'Device:Polyfuse', '0.5A', 'Fuse:Fuse_1206_3216Metric',
     {'1': '+3V3', '2': 'PK_3V3'}, S_LNK, 'PK', descr='PTC 0.5 A hold, keyboard supply')
C('100n', 'PK_3V3', 'GND', S_LNK, 'PK')

# Neighbour link (ADR 0007): one UART, plain 3-pin Dupont header
# (GND, TX, RX), 100 ohm series. No 12 V pass-through (owner round 5).
R('100', 'NB_UART_TX', 'NB_J_TX', S_LNK, 'LINK')
R('100', 'NB_UART_RX', 'NB_J_RX', S_LNK, 'LINK')
part('J', 'Connector_Generic:Conn_01x03', 'NEIGHBOUR UART',
     'Connector_PinHeader_2.54mm:PinHeader_1x03_P2.54mm_Vertical',
     {'1': 'GND', '2': 'NB_J_TX', '3': 'NB_J_RX'}, S_LNK, 'LINKU',
     descr='1x3 header: GND, TX, RX (Dupont)')

# 12 V -> 5 V buck for the front-panel I2C header (LCD backpacks need 5 V)
part('U', 'Regulator_Switching:AP63205WU', 'AP63205WU', 'Package_TO_SOT_SMD:TSOT-23-6',
     {'3': '+12V', '2': '+12V', '4': 'GND', '5': 'BUCK_SW', '6': 'BUCK_BST', '1': '+5V'},
     S_LNK, 'BUCK', descr='2 A sync buck, fixed 5 V, 3.8-32 V in')
C('10u', '+12V', 'GND', S_LNK, 'BUCK', fp='Capacitor_SMD:C_1206_3216Metric', lcsc='')
C('100n', '+12V', 'GND', S_LNK, 'BUCK')
C('100n', 'BUCK_BST', 'BUCK_SW', S_LNK, 'BUCK')
part('L', 'Device:L', '4.7u', 'Inductor_SMD:L_Changjiang_FXL0530',
     {'1': 'BUCK_SW', '2': '+5V'}, S_LNK, 'BUCK', descr='4.7 uH >= 1.5 A, 5x5 mm')
C('22u', '+5V', 'GND', S_LNK, 'BUCK', fp='Capacitor_SMD:C_0805_2012Metric', lcsc='')
C('22u', '+5V', 'GND', S_LNK, 'BUCK', fp='Capacitor_SMD:C_0805_2012Metric', lcsc='')
flag('+5V', S_LNK)

SHEETS = [
    (S_HDR, 'Mimas headers, 12 V input, mounting'),
] + [('hdmi_rx_dut%d' % n, 'DUT%d HDMI input' % n) for n in HDMI_DUTS] + [
    (S_DUT, 'DUT JTAG/UART ports, keyboard sub-board sockets'),
    (S_EXP, 'I2C expanders, revision/features, power control, I2C header'),
    (S_LNK, 'Physical keyboard, neighbour UART, 5 V buck'),
]
