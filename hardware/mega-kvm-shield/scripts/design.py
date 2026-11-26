"""MEGA-KVM link-board shield: the circuit, as data.

Every component is a dict: ref prefix, symbol, value, footprint, LCSC part,
the sheet it is drawn on, the PCB cluster it is placed in, and its pin->net
map. gen_sch.py turns this into the KiCad schematic, gen_pcb.py into the
board. Change the circuit here, then rerun `make` in this directory.

Header pin plan: HEADER_PLAN below is a PLACEHOLDER until the pin-plan
work (docs/hardware/shield-pinplan.md, branch feature/shield-pinplan,
issue 0049) fixes it; only that table needs to change.
"""

N_DUT = 4                 # DUT0..DUT3; DUT0 video = Mimas HDMI IN
HDMI_DUTS = [1, 2, 3]     # DUTs with a header HDMI receiver on the shield
REVISION = 0x01           # shield revision strapped on TCA6424A port 0

# --------------------------------------------------------------------------
# Header pin plan (PLACEHOLDER).  Keys: (header, row, column).  Rows 1-2 VIN,
# 9/15/21 VADJ 3.3 V, 3/8/14/20/24/27/30/33/40 GND, 34-39 configuration pins
# (never connected).  Column A = P, column B = N of each pair.
# Existing assignments kept (ADR 0008 am. 5, xdc): DUT0/DUT1 JTAG rows 4-7,
# DUT keyboards 16A/16B/17A, physical keyboard P12 10A/10B/11A (+11B TDO),
# header HDMI (0043) P13 rows 10-13 (D1 moved to row 18 so that the MRCC pair
# on row 12 can clock DUT3, see issue 0045 round 3), DDC P13 row 28.
# VIO/keyboard sense, HPD and +5V sense move to the TCA9535 expander.
# --------------------------------------------------------------------------
HEADER_PLAN = {
    'P12': {
        (4, 'A'): 'DUT0_TCK', (4, 'B'): 'DUT0_UART_FROM',
        (5, 'A'): 'DUT0_TDO', (5, 'B'): 'DUT0_UART_TO',
        (6, 'A'): 'DUT0_TDI', (6, 'B'): 'DUT2_TCK',
        (7, 'A'): 'DUT0_TMS', (7, 'B'): 'DUT2_TMS',
        (10, 'A'): 'PK_KIO10', (10, 'B'): 'PK_KIO9',
        (11, 'A'): 'PK_KIO8', (11, 'B'): 'PK_TDO',
        (12, 'A'): 'HDMI2_CLK_P', (12, 'B'): 'HDMI2_CLK_N',
        (13, 'A'): 'HDMI2_D0_P', (13, 'B'): 'HDMI2_D0_N',
        (16, 'A'): 'DUT0_KIO10', (16, 'B'): 'DUT0_KIO9',
        (17, 'A'): 'DUT0_KIO8', (17, 'B'): 'DUT2_TDI',
        (18, 'A'): 'HDMI2_D1_P', (18, 'B'): 'HDMI2_D1_N',
        (19, 'A'): 'HDMI2_D2_P', (19, 'B'): 'HDMI2_D2_N',
        (22, 'A'): 'DUT2_TDO', (22, 'B'): 'DUT2_UART_TO',
        (23, 'A'): 'DUT2_UART_FROM', (23, 'B'): 'DUT2_KIO8',
        (25, 'A'): 'DUT2_KIO9', (25, 'B'): 'DUT2_KIO10',
        (26, 'A'): 'HDMI2_SCL', (26, 'B'): 'HDMI2_SDA',
        (28, 'A'): 'PK_JTAGEN', (28, 'B'): 'PK_TMS',
        (29, 'A'): 'PK_TCK', (29, 'B'): 'PK_TDI',
        (31, 'A'): 'I2C_SCL', (31, 'B'): 'I2C_SDA',
        (32, 'A'): 'LINKA_TX', (32, 'B'): 'LINKA_RX',
    },
    'P13': {
        (4, 'A'): 'DUT1_TCK', (4, 'B'): 'DUT1_UART_FROM',
        (5, 'A'): 'DUT1_TDO', (5, 'B'): 'DUT1_UART_TO',
        (6, 'A'): 'DUT1_TDI', (6, 'B'): 'DUT3_TCK',
        (7, 'A'): 'DUT1_TMS', (7, 'B'): 'DUT3_TMS',
        (10, 'A'): 'HDMI1_D0_P', (10, 'B'): 'HDMI1_D0_N',
        (11, 'A'): 'HDMI1_CLK_P', (11, 'B'): 'HDMI1_CLK_N',
        (12, 'A'): 'HDMI3_CLK_P', (12, 'B'): 'HDMI3_CLK_N',
        (13, 'A'): 'HDMI1_D2_P', (13, 'B'): 'HDMI1_D2_N',
        (16, 'A'): 'DUT1_KIO10', (16, 'B'): 'DUT1_KIO9',
        (17, 'A'): 'DUT1_KIO8', (17, 'B'): 'DUT3_TDI',
        (18, 'A'): 'HDMI1_D1_P', (18, 'B'): 'HDMI1_D1_N',
        (19, 'A'): 'HDMI3_D0_P', (19, 'B'): 'HDMI3_D0_N',
        (22, 'A'): 'DUT3_TDO', (22, 'B'): 'DUT3_UART_TO',
        (23, 'A'): 'HDMI3_D1_P', (23, 'B'): 'HDMI3_D1_N',
        (25, 'A'): 'HDMI3_D2_P', (25, 'B'): 'HDMI3_D2_N',
        (26, 'A'): 'DUT3_UART_FROM', (26, 'B'): 'DUT3_KIO8',
        (28, 'A'): 'HDMI1_SCL', (28, 'B'): 'HDMI1_SDA',
        (29, 'A'): 'DUT3_KIO9', (29, 'B'): 'DUT3_KIO10',
        (31, 'A'): 'HDMI3_SCL', (31, 'B'): 'HDMI3_SDA',
        (32, 'A'): 'LINKB_TX', (32, 'B'): 'LINKB_RX',
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


def part(prefix, sym, value, fp, pins, sheet, cluster, lcsc='', dnp=False,
         descr='', mpn=''):
    p = dict(prefix=prefix, sym=sym, value=value, fp=fp, pins=dict(pins),
             sheet=sheet, cluster=cluster, lcsc=lcsc, dnp=dnp, descr=descr,
             mpn=mpn)
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
part('P', 'shield:Mimas_Header_2x40', 'P12 socket (DUT0/DUT2 side)',
     'shield:Mimas_Header_Socket_2x40', header_pins('P12'), S_HDR, 'P12',
     descr='2x40 female socket 2.54 mm, 8.5 mm, bottom side, mates Mimas P12')
part('P', 'shield:Mimas_Header_2x40', 'P13 socket (DUT1/DUT3 side)',
     'shield:Mimas_Header_Socket_2x40', header_pins('P13'), S_HDR, 'P13',
     descr='2x40 female socket 2.54 mm, 8.5 mm, bottom side, mates Mimas P13')

# 12 V input from the power board (0047 always-on output) -> header VIN
part('J', 'Connector_Generic:Conn_01x02', '12V IN',
     'Connector_JST:JST_VH_B2P-VH_1x02_P3.96mm_Vertical',
     {'1': '+12V', '2': 'GND'}, S_HDR, 'PWR', descr='JST VH 2-pin, 12 V in',
     mpn='JST B2P-VH')
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
for n in range(N_DUT):
    d = lambda x: 'DUT%d_%s' % (n, x)
    j = lambda x: 'DUT%d_JB_%s' % (n, x)
    k = lambda x: 'DUT%d_KB_%s' % (n, x)
    cj, ck = 'JTAG%d' % n, 'KBD%d' % n
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
    # J5 style 2x5 (no keyboard JTAG on DUT ports)
    part('J', 'Connector_Generic:Conn_02x05_Odd_Even', 'DUT%d KEYBOARD (J5)' % n,
         'Connector_IDC:IDC-Header_2x05_P2.54mm_Horizontal',
         {'1': 'GND', '2': k('3V3'), '3': None, '4': None, '5': None, '6': None,
          '7': None, '8': k('KIO8'), '9': k('KIO9'), '10': k('KIO10')},
         S_DUT, ck + 'J', descr='2x5 box header, right angle')
    for sig in ('KIO8', 'KIO9', 'KIO10'):
        R('47', d(sig), k(sig), S_DUT, ck)
    R('10k', k('3V3'), d('KB_SENSE'), S_DUT, ck)
    R('100k', d('KB_SENSE'), 'GND', S_DUT, ck)

# ------------------------------- I/O expanders ---------------------------
S_EXP = 'io_expanders'
# TCA6424A (0x22): P0 revision straps, P1 feature presence, P2 power control
exp24 = {'1': 'I2C_INT_N', '2': '+3V3', '3': 'EXP_RESET_N', '28': 'GND',
         '29': 'I2C_SCL', '30': 'I2C_SDA', '31': '+3V3', '32': 'GND', '33': 'GND'}
for b in range(8):
    exp24[str(4 + b)] = 'REV%d' % b
    exp24[str(12 + b)] = 'FEAT%d' % b
    exp24[str(20 + b)] = 'PWR_EN%d' % b
part('U', 'shield:TCA6424A', 'TCA6424ARGJR',
     'Package_DFN_QFN:QFN-32-1EP_5x5mm_P0.5mm_EP3.45x3.45mm', exp24, S_EXP, 'EXP',
     descr='24-bit I2C GPIO expander, addr 0x22')
C('100n', '+3V3', 'GND', S_EXP, 'EXP')
C('100n', '+3V3', 'GND', S_EXP, 'EXP')
R('10k', '+3V3', 'EXP_RESET_N', S_EXP, 'EXP')
for b in range(8):                         # revision straps: populate one of two
    up = bool(REVISION >> b & 1)
    R('10k', '+3V3', 'REV%d' % b, S_EXP, 'EXP', dnp=not up)
    R('10k', 'REV%d' % b, 'GND', S_EXP, 'EXP', dnp=up)
FEATURES = {0: True, 2: N_DUT >= 4}        # b0 HDMI capture fitted, b2 DUT3 fitted
for b in range(8):
    if b == 1:
        continue                           # b1 = power board present (live)
    up = FEATURES.get(b, False)
    R('10k', '+3V3', 'FEAT%d' % b, S_EXP, 'EXP', dnp=not up)
    R('10k', 'FEAT%d' % b, 'GND', S_EXP, 'EXP', dnp=up)
part('R', 'Device:R', '0', R0402, {'1': 'FEAT1', '2': 'PWRB_PRESENT_N'}, S_EXP, 'EXP',
     'C17168')
R('10k', '+3V3', 'PWRB_PRESENT_N', S_EXP, 'EXP')
for b in range(8):
    R('20k', 'PWR_EN%d' % b, 'GND', S_EXP, 'EXP')
# power-control header to the power board: 1x11, pin 2 removed (key)
relay = {'1': 'GND', '2': None, '11': 'PWRB_PRESENT_N'}
for b in range(8):
    relay[str(3 + b)] = 'PWR_EN%d' % b
part('J', 'Connector_Generic:Conn_01x11', 'POWER CTRL (pin 2 = key)',
     'Connector_PinHeader_2.54mm:PinHeader_1x11_P2.54mm_Vertical', relay, S_EXP,
     'RELAYJ', descr='1x11 pin header, pin 2 pulled for keying')

# TCA9535 (0x20): slow lines (sense inputs, HPD outputs)
exp16 = {'23': 'I2C_SDA', '22': 'I2C_SCL', '1': 'I2C_INT_N', '3': 'GND', '2': 'GND',
         '21': 'GND', '24': '+3V3', '12': 'GND'}
p0 = ['DUT%d_VIO_SENSE' % n for n in range(4)] + ['DUT%d_KB_SENSE' % n for n in range(4)]
p1 = ['HDMI%d_HPD_EN' % n for n in (1, 2, 3)] + ['HDMI%d_5V_SENSE' % n for n in (1, 2, 3)] \
    + ['EXP_SPARE0', 'EXP_SPARE1']
for b in range(8):
    exp16[str(4 + b)] = p0[b]
    exp16[str(13 + b)] = p1[b]
part('U', 'Interface_Expansion:TCA9535PWR', 'TCA9535PWR',
     'Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm', exp16, S_EXP, 'EXP',
     descr='16-bit I2C GPIO expander, no pull-ups, addr 0x20')
C('100n', '+3V3', 'GND', S_EXP, 'EXP')
R('100k', 'EXP_SPARE0', 'GND', S_EXP, 'EXP')
R('100k', 'EXP_SPARE1', 'GND', S_EXP, 'EXP')
# I2C bus pull-ups and the front-panel I2C header
R('2.2k', '+3V3', 'I2C_SCL', S_EXP, 'EXP')
R('2.2k', '+3V3', 'I2C_SDA', S_EXP, 'EXP')
R('10k', '+3V3', 'I2C_INT_N', S_EXP, 'EXP')
part('J', 'Connector_Generic:Conn_01x05', 'I2C (front panel)',
     'Connector_PinHeader_2.54mm:PinHeader_1x05_P2.54mm_Horizontal',
     {'1': 'GND', '2': '+3V3', '3': 'I2C_SDA', '4': 'I2C_SCL', '5': 'I2C_INT_N'},
     S_EXP, 'I2CJ', descr='1x5 right-angle header')

# ------------------------------- physical keyboard + links ---------------
S_LNK = 'keyboard_link'
pk = {'1': 'GND', '2': 'PK_3V3'}
for pin, sig in (('3', 'JTAGEN'), ('4', 'TMS'), ('5', 'TCK'), ('6', 'TDI'),
                 ('7', 'TDO'), ('8', 'KIO8'), ('9', 'KIO9'), ('10', 'KIO10')):
    pk[pin] = 'PK_J_' + sig
    R('33', 'PK_' + sig, 'PK_J_' + sig, S_LNK, 'PK')
part('J', 'Connector_Generic:Conn_02x05_Odd_Even', 'PHYSICAL KEYBOARD (J5, with JTAG)',
     'Connector_IDC:IDC-Header_2x05_P2.54mm_Horizontal', pk, S_LNK, 'PKJ',
     descr='2x5 box header, right angle')
part('F', 'Device:Polyfuse', '0.5A', 'Fuse:Fuse_1206_3216Metric',
     {'1': '+3V3', '2': 'PK_3V3'}, S_LNK, 'PK', descr='PTC 0.5 A hold, keyboard supply')
C('100n', 'PK_3V3', 'GND', S_LNK, 'PK')

for side, other in (('A', 'P12'), ('B', 'P13')):
    L = lambda x: 'LINK%s_%s' % (side, x)
    cl = 'LINK' + side
    # series resistors protect the FPGA pins on a cable
    R('100', L('TX'), L('J_TX'), S_LNK, cl)
    R('100', L('RX'), L('J_RX'), S_LNK, cl)
    part('J', 'Connector_Generic:Conn_01x03', 'LINK %s UART' % side,
         'Connector_PinHeader_2.54mm:PinHeader_1x03_P2.54mm_Vertical',
         {'1': 'GND', '2': L('J_TX'), '3': L('J_RX')}, S_LNK, cl + 'U',
         descr='1x3 header: GND, TX, RX (Dupont)')
    # side connector: 12 V pass-through + UART. A = socket, B = pins, so
    # neighbouring shields plug together; TX/RX swap between the two so a
    # straight lead also works.
    if side == 'A':
        pins = {'1': L('12V'), '2': L('J_TX'), '3': L('J_RX'), '4': 'GND'}
        fp = 'Connector_PinSocket_2.54mm:PinSocket_1x04_P2.54mm_Horizontal'
    else:
        pins = {'1': L('12V'), '2': L('J_RX'), '3': L('J_TX'), '4': 'GND'}
        fp = 'Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Horizontal'
    part('J', 'Connector_Generic:Conn_01x04', 'LINK %s (12V, UART)' % side, fp, pins,
         S_LNK, cl + 'S', descr='1x4 right angle: 12V, TX/RX, GND')
    part('F', 'Device:Polyfuse', '2A', 'Fuse:Fuse_1812_4532Metric',
         {'1': '+12V', '2': L('12V')}, S_LNK, cl, descr='PTC 2 A hold, 12 V pass-through')

SHEETS = [
    (S_HDR, 'Mimas headers, 12 V input, mounting'),
] + [('hdmi_rx_dut%d' % n, 'DUT%d HDMI input' % n) for n in HDMI_DUTS] + [
    (S_DUT, 'DUT JTAG/UART and keyboard ports'),
    (S_EXP, 'I2C expanders, revision/features, power control, I2C header'),
    (S_LNK, 'Physical keyboard and neighbour links'),
]
