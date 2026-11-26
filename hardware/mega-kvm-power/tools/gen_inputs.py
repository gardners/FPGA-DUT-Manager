"""MEGA-KVM power board, input (vertical, rear-panel) PCB.

Three 12 V inputs, one used at a time by automatic priority (LTC4417):
  V1 = 4 mm banana sockets (25 A fuse)  > V2 = PCIe 8-pin (15 A) > V3 = Molex 4-pin (10 A).
Each input: blade fuse, then a unidirectional TVS (hot-plug spikes; a reversed
supply forward-biases it and blows the fuse).  Output VBUS goes to the main
board over two M4 lugs.  A front-panel illuminated rocker switches LTC4417 EN
(master on/off, not the 25 A path).  Issue 0047.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kigen import Schematic, write_project  # noqa: E402
from parts import B5819W, FP_C1206, FP_R1206, HOLE_M3, LDO, LED_G, LUG_M4, NFET, PFET, TVS, c, r  # noqa: E402

NAME = 'mega-kvm-power-inputs'
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', NAME)

S = Schematic(NAME, 'MEGA-KVM power board - inputs (LTC4417 priority select)', paper='A3')


def P(part, ref, x, y, nets, value=None, dnp=False, nc=(), fp=None, fields=None, rot=0):
    f = dict(part.get('fields', {}))
    f.update(fields or {})
    return S.place(part['lib'], ref, value or part['value'], x, y, nets,
                   footprint=fp or part.get('fp', ''), dnp=dnp, nc=nc, fields=f, rot=rot)


FUSE_FP = 'Fuse:FuseHolder_Blade_ATO_Littelfuse_FLR_178.6165'
INPUTS = [
    # n, name, fuse, connector
    (1, 'Banana 4 mm', '25A ATO', 'banana'),
    (2, 'PCIe 8-pin', '15A ATO', 'pcie'),
    (3, 'Molex 4-pin', '10A ATO', 'molex'),
]

for n, label, fuse, kind in INPUTS:
    bx, by = 12.7, 15.24 + (n - 1) * 58.42
    S.box(bx, by, bx + 193.04, by + 53.34, 'Input V%d: %s, fuse %s, priority %d' % (n, label, fuse, n))
    raw = 'IN%d_RAW' % n
    vn = 'V%d' % n
    if kind == 'banana':
        S.place('Connector_Generic:Conn_01x01', 'J1', 'BANANA +12V (red)', bx + 12.7, by + 15.24, {'1': raw},
                footprint='Connector:Banana_Jack_1Pin',
                fields={'MPN': '4 mm panel socket >=30 A, red, through-PCB with nut + solder lug '
                               '(e.g. Staubli/Multi-Contact or Cliff, choose at order)',
                        'LCSC': 'hand-fit', 'Assembly': 'hand'})
        S.place('Connector_Generic:Conn_01x01', 'J2', 'BANANA GND (black)', bx + 12.7, by + 33.02, {'1': 'GND'},
                footprint='Connector:Banana_Jack_1Pin',
                fields={'MPN': '4 mm panel socket >=30 A, black', 'LCSC': 'hand-fit', 'Assembly': 'hand'})
    elif kind == 'pcie':
        S.place('Connector_Generic:Conn_02x04_Counter_Clockwise', 'J3', 'PCIe 8-pin', bx + 12.7, by + 25.4,
                {'1': raw, '2': raw, '3': raw, '4': 'GND', '5': 'GND', '6': 'GND', '7': 'GND', '8': 'GND'},
                footprint='Connector_Molex:Molex_Mini-Fit_Jr_5566-08A_2x04_P4.20mm_Vertical',
                fields={'MPN': 'Molex Mini-Fit Jr 8-pin vertical header with PCIe keying (45558-series '
                               'or 39-28-1083 + check keying); pins 1-3 +12 V, 4-8 GND (sense pins grounded)',
                        'LCSC': 'TBD / hand-fit', 'Assembly': 'THT'})
    else:
        S.place('Connector_Generic:Conn_01x04', 'J4', 'Molex 4-pin', bx + 12.7, by + 25.4,
                {'1': raw, '2': 'GND', '3': 'GND'}, nc=('4',),
                footprint='mega-kvm-power:Molex_8981_PeripheralPower_1x04_P5.08mm_Vertical',
                fields={'MPN': 'Molex 8981 4-pin male PCB header, vertical (e.g. 15-24-4048); '
                               '1 +12 V, 2-3 GND, 4 +5 V unused', 'LCSC': 'TBD / hand-fit', 'Assembly': 'THT'})
    S.place('Device:Fuse', 'F%d' % n, fuse, bx + 38.1, by + 20.32, {'1': raw, '2': vn},
            footprint=FUSE_FP,
            fields={'MPN': 'Littelfuse 178.6165.0002 ATO PCB holder + ATO blade fuse %s' % fuse,
                    'LCSC': 'TBD / hand-fit', 'Assembly': 'THT'})
    P(TVS, 'D%d' % n, bx + 53.34, by + 20.32, {'K': vn, 'A': 'GND'}, rot=90)
    P(c('1u', '50V', FP_C1206), 'C%d' % n, bx + 63.5, by + 20.32, {'1': vn, '2': 'GND'})
    P(B5819W, 'D%d' % (3 + n), bx + 76.2, by + 15.24, {'A': vn, 'K': 'VIN_OR'}, rot=180,
      fields={'Note': 'diode-OR: master-switch supply that exists before VBUS'})
    # UV/OV divider: UV rising ~10.5 V, OV ~14.0 V (1.0 V comparators; verify vs datasheet)
    P(r('1M27'), 'R%d' % (10 * n + 0), bx + 91.44, by + 20.32, {'1': vn, '2': 'UV%d' % n})
    P(r('33k2'), 'R%d' % (10 * n + 1), bx + 99.06, by + 20.32, {'1': 'UV%d' % n, '2': 'OV%d' % n})
    P(r('100k'), 'R%d' % (10 * n + 2), bx + 106.68, by + 20.32, {'1': 'OV%d' % n, '2': 'GND'})
    # back-to-back PFETs, common source VSn
    qa, qb = ([1, 2], [3, 4]) if n == 1 else ([2 * n + 1], [2 * n + 2])
    for k, q in enumerate(qa):
        P(PFET, 'Q%d' % q, bx + 127 + k * 15.24, by + 22.86, {'D': vn, 'S': 'VS%d' % n, 'G': 'G%d' % n})
    for k, q in enumerate(qb):
        P(PFET, 'Q%d' % q, bx + 160.02 + k * 15.24, by + 22.86, {'D': 'VBUS', 'S': 'VS%d' % n, 'G': 'G%d' % n})
    S.text('Q%s: input side (D=V%d)   Q%s: output side (D=VBUS)%s' % (
        '/'.join(map(str, qa)), n, '/'.join(map(str, qb)),
        '   - two in parallel each side for 25 A' if n == 1 else ''), bx + 116.84, by + 40.64, 1.27)

# ---------------------------------------------------------------- LTC4417
bx, by = 210.82, 15.24
S.box(bx, by, bx + 193.04, by + 111.76, 'U1 LTC4417: prioritised PowerPath, V1 > V2 > V3')
nets = {'V1': 'V1', 'V2': 'V2', 'V3': 'V3', 'VS1': 'VS1', 'VS2': 'VS2', 'VS3': 'VS3',
        'G1': 'G1', 'G2': 'G2', 'G3': 'G3', 'VOUT': 'VBUS', 'GND': 'GND', 'EN': 'EN',
        '~{SHDN}': '~{SHDN}', 'HYS': 'HYS', 'UV1': 'UV1', 'OV1': 'OV1', 'UV2': 'UV2', 'OV2': 'OV2',
        'UV3': 'UV3', 'OV3': 'OV3', '~{VALID1}': '~{VALID1}', '~{VALID2}': '~{VALID2}',
        '~{VALID3}': '~{VALID3}'}
S.place('mega-kvm-power:LTC4417CGN', 'U1', 'LTC4417CGN', bx + 45.72, by + 50.8, nets,
        footprint='Package_SO:SSOP-24_3.9x8.7mm_P0.635mm', nc=('CAS',),
        fields={'LCSC': 'C688500 (LCSC stock very low: consign or hand-fit; LTC4417IUF C580907 is the QFN)',
                'MPN': 'ADI LTC4417CGN#PBF'})
P(r('158k'), 'R1', bx + 101.6, by + 25.4, {'1': 'HYS', '2': 'GND'}, dnp=True,
  fields={'Note': 'DNP = internal ~30 mV hysteresis; fit to set 63 mV/RHYS (check datasheet)'})
P(c('10u', '25V', FP_C1206), 'C4', bx + 111.76, by + 25.4, {'1': 'VBUS', '2': 'GND'})
P(c('10u', '25V', FP_C1206), 'C5', bx + 119.38, by + 25.4, {'1': 'VBUS', '2': 'GND'})
P(LUG_M4, 'J6', bx + 139.7, by + 20.32, {'1': 'VBUS'}, value='VBUS lug (to main)')
P(LUG_M4, 'J7', bx + 139.7, by + 33.02, {'1': 'GND'}, value='GND lug (to main)')
S.pwr_flag('VBUS', bx + 157.48, by + 17.78)
S.pwr_flag('GND', bx + 157.48, by + 35.56)
S.pwr_flag('VIN_OR', bx + 172.72, by + 17.78)

# master switch: illuminated SPST rocker on the front panel, 3-terminal type
# (supply, load, lamp-ground). Closed -> EN high -> LTC4417 connects the best input.
S.text('Master on/off: front-panel illuminated rocker (SPST, 12 V lamp between LOAD and GND).\n'
       'Cable unplugged or switch off -> EN pulled low -> VBUS off -> every output off,\n'
       'including the always-on Mimas/switch/fan group. The lamp lights from VIN_OR when on.\n'
       'JP1 bridges the switch for bench use.', bx + 2.54, by + 76.2, 1.27)
P(r('47R'), 'R2', bx + 101.6, by + 50.8, {'1': 'VIN_OR', '2': 'SW_SUP'}, fp=FP_R1206,
  fields={'Note': 'limits lamp/short current on the front-panel cable'})
S.place('Connector_Generic:Conn_01x03', 'J5', 'MASTER SW', bx + 129.54, by + 53.34,
        {'1': 'SW_SUP', '2': 'EN_SW', '3': 'GND'},
        footprint='Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical',
        fields={'Note': '1 SUPPLY (rocker +), 2 LOAD (rocker switched, lamp +), 3 GND (lamp -)',
                'MPN': 'JST B3B-XH-A', 'LCSC': 'C144395 (verify)'})
S.place('Jumper:SolderJumper_2_Open', 'JP1', 'SW bypass', bx + 119.38, by + 66.04,
        {'A': 'SW_SUP', 'B': 'EN_SW'}, footprint='Jumper:SolderJumper-2_P1.3mm_Open_RoundedPad1.0x1.5mm')
P(r('100k'), 'R3', bx + 147.32, by + 50.8, {'1': 'EN_SW', '2': 'EN'})
P(r('33k'), 'R4', bx + 154.94, by + 50.8, {'1': 'EN', '2': 'GND'},
  fields={'Note': 'EN = 12 V * 33/133 = 3 V on, pulled low when open'})
P(c('100n'), 'C6', bx + 162.56, by + 50.8, {'1': 'EN', '2': 'GND'})
P(r('100k'), 'R5', bx + 172.72, by + 50.8, {'1': 'VIN_OR', '2': '~{SHDN}'})
P(r('33k'), 'R6', bx + 180.34, by + 50.8, {'1': '~{SHDN}', '2': 'GND'})
P(c('1u', '50V'), 'C7', bx + 187.96, by + 50.8, {'1': 'VIN_OR', '2': 'GND'})

# ---------------------------------------------------------------- input-selected LEDs
bx, by = 210.82, 132.08
S.box(bx, by, bx + 193.04, by + 93.98, 'Input-selected LEDs (rear panel), 3.3 V from VBUS')
P(LDO, 'U2', bx + 22.86, by + 15.24, {'IN': 'VBUS', 'OUT': '+3V3', 'GND': 'GND'})
P(c('1u', '50V'), 'C8', bx + 10.16, by + 25.4, {'1': 'VBUS', '2': 'GND'})
P(c('1u', '16V'), 'C9', bx + 35.56, by + 25.4, {'1': '+3V3', '2': 'GND'})
for k in range(3):
    P(r('100k'), 'R%d' % (7 + k), bx + 50.8 + k * 7.62, by + 15.24, {'1': '+3V3', '2': '~{VALID%d}' % (k + 1)})
# LED1: V1 valid (it always wins)
P(r('680R'), 'R40', bx + 81.28, by + 15.24, {'1': '+3V3', '2': 'LA1'})
P(LED_G, 'D7', bx + 81.28, by + 27.94, {'A': 'LA1', 'K': '~{VALID1}'}, value='green', rot=90,
  fields={'Note': 'IN1 banana selected'})
# LED2: V2 valid and V1 not valid
P(r('680R'), 'R41', bx + 106.68, by + 15.24, {'1': '+3V3', '2': 'LA2'})
P(LED_G, 'D8', bx + 106.68, by + 27.94, {'A': 'LA2', 'K': 'LK2'}, value='green', rot=90,
  fields={'Note': 'IN2 PCIe selected'})
P(NFET, 'Q9', bx + 104.14, by + 43.18, {'D': 'LK2', 'S': '~{VALID2}', 'G': '~{VALID1}'})
# LED3: V3 valid, V1 and V2 not valid
P(r('680R'), 'R42', bx + 139.7, by + 15.24, {'1': '+3V3', '2': 'LA3'})
P(LED_G, 'D9', bx + 139.7, by + 27.94, {'A': 'LA3', 'K': 'LK3'}, value='green', rot=90,
  fields={'Note': 'IN3 Molex selected'})
P(NFET, 'Q10', bx + 137.16, by + 43.18, {'D': 'LK3', 'S': 'LK3B', 'G': '~{VALID1}'})
P(NFET, 'Q11', bx + 137.16, by + 58.42, {'D': 'LK3B', 'S': '~{VALID3}', 'G': '~{VALID2}'})
S.text('~VALIDn are open drain (low = input n valid). The selected input is the highest-priority\n'
       'valid one, so LED2 = V2 & !V1, LED3 = V3 & !V1 & !V2. LEDs are dark when VBUS is off\n'
       '(master switch off). Q9-Q11 gates see at most 3.3 V.', bx + 2.54, by + 73.66, 1.27)

for k in range(2):
    S.place(HOLE_M3['lib'], 'H%d' % (1 + k), 'M3', 22.86 + k * 12.7, 195.58, {}, footprint=HOLE_M3['fp'])

S.text('Fuse ratings: banana 25 A (4 mm sockets ~30 A), PCIe 8-pin 15 A (150 W = 12.5 A spec),\n'
       'Molex 4-pin 10 A (one 12 V pin, ~11 A contact). One input at a time: no back-feed\n'
       'between PSUs. TVS SMCJ15A: Vrwm 15 V, clamp 24.4 V < 28 V TPS25947 / 36 V LTC4417.\n'
       'FETs BSC030P03NS3G 3 mOhm: at 25 A, 2 parallel per side = ~0.5 W each.',
       12.7, 205.74, 1.5)

if __name__ == '__main__':
    os.makedirs(OUTDIR, exist_ok=True)
    S.write(OUTDIR)
    write_project(OUTDIR, NAME)
    print('wrote', OUTDIR)
