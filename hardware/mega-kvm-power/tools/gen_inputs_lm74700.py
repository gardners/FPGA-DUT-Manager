"""MEGA-KVM power input board, JLC-stocked FALLBACK variant (schematic only).

Same connectors, fuses and TVS as the LTC4417 board, but built from parts
that JLC/LCSC stock and that are all leaded (no exposed pads):
  per input: LM74700-Q1 (SOT-23-6) ideal-diode controller + N-FET (reverse
  blocking, so inputs never back-feed each other), then a P-FET high-side
  switch driven by simple priority logic (LM339 + TL431):
      ON1 = rocker & V1 ok
      ON2 = rocker & V2 ok & !V1 ok
      ON3 = rocker & V3 ok & !V1 ok & !V2 ok
  Open-collector comparator outputs wire-AND onto the ONn nodes, which are
  pulled up from the rocker's LOAD terminal, so the rocker is a global disable.
  Soft start: Miller capacitor on each P-FET gate.  Issue 0047 round 5.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kigen import Schematic, write_project  # noqa: E402
from parts import B5819W, FP_C1206, FP_R1206, HOLE_M3, LED_G, LUG_M4, NFET, PFET, TVS, c, r  # noqa: E402

NAME = 'mega-kvm-power-inputs-lm74700'
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', NAME)
S = Schematic(NAME, 'MEGA-KVM power inputs - fallback: LM74700 ideal diodes + priority logic', paper='A3')

NFET_PWR = dict(lib='mega-kvm-power:NMOS_TDSON8', fp='Package_SON:Infineon_PG-TDSON-8_6.15x5.15mm',
                value='BSC014N04LS', fields={'LCSC': 'C2760081', 'MPN': 'Infineon BSC014N04LS 40 V 1.4 mOhm'})
LM74700 = dict(lib='Power_Management:LM74700', fp='Package_TO_SOT_SMD:SOT-23-6', value='LM74700QDBVRQ1',
               fields={'LCSC': 'C2941042', 'MPN': 'TI LM74700QDBVRQ1 (SOT-23-6, leaded)'})
LM339 = dict(lib='Comparator:LM339', fp='Package_SO:SOIC-14_3.9x8.7mm_P1.27mm', value='LM339DR',
             fields={'LCSC': 'C7948', 'MPN': 'TI LM339DR'})
TL431 = dict(lib='Reference_Voltage:TL431DBZ', fp='Package_TO_SOT_SMD:SOT-23', value='TL431',
             fields={'LCSC': 'TBD (TL431 SOT-23, JLC basic)'})


def P(part, ref, x, y, nets, value=None, dnp=False, nc=(), fp=None, fields=None, rot=0, unit=1):
    f = dict(part.get('fields', {}))
    f.update(fields or {})
    return S.place(part['lib'], ref, value or part['value'], x, y, nets, unit=unit,
                   footprint=fp or part.get('fp', ''), dnp=dnp, nc=nc, fields=f, rot=rot)


FUSE_FP = 'Fuse:FuseHolder_Blade_ATO_Littelfuse_FLR_178.6165'
INPUTS = [(1, 'Banana 4 mm', '25A ATO'), (2, 'PCIe 8-pin', '15A ATO'), (3, 'Molex 4-pin', '10A ATO')]

for n, label, fuse in INPUTS:
    bx, by = 12.7, 15.24 + (n - 1) * 66.04
    S.box(bx, by, bx + 254, by + 60.96, 'Input V%d: %s, fuse %s, priority %d' % (n, label, fuse, n))
    raw, vn, mid = 'IN%d_RAW' % n, 'V%d' % n, 'MID%d' % n
    if n == 1:
        S.place('Connector_Generic:Conn_01x01', 'J1', 'BANANA +12V', bx + 10.16, by + 15.24, {'1': raw},
                footprint='Connector:Banana_Jack_1Pin', fields={'LCSC': 'see LTC4417 board BOM'})
        S.place('Connector_Generic:Conn_01x01', 'J2', 'BANANA GND', bx + 10.16, by + 30.48, {'1': 'GND'},
                footprint='Connector:Banana_Jack_1Pin', fields={'LCSC': 'see LTC4417 board BOM'})
    elif n == 2:
        S.place('Connector_Generic:Conn_02x04_Counter_Clockwise', 'J3', 'PCIe 8-pin', bx + 10.16, by + 25.4,
                {'1': raw, '2': raw, '3': raw, '4': 'GND', '5': 'GND', '6': 'GND', '7': 'GND', '8': 'GND'},
                footprint='Connector_Molex:Molex_Mini-Fit_Jr_5566-08A_2x04_P4.20mm_Vertical')
    else:
        S.place('Connector_Generic:Conn_01x04', 'J4', 'Molex 4-pin', bx + 10.16, by + 25.4,
                {'1': raw, '2': 'GND', '3': 'GND'}, nc=('4',),
                footprint='mega-kvm-power:Molex_8981_PeripheralPower_1x04_P5.08mm_Vertical')
    S.place('Device:Fuse', 'F%d' % n, fuse, bx + 33.02, by + 20.32, {'1': raw, '2': vn}, footprint=FUSE_FP)
    P(TVS, 'D%d' % n, bx + 45.72, by + 20.32, {'K': vn, 'A': 'GND'}, rot=90)
    P(c('1u', '50V', FP_C1206), 'C%d' % n, bx + 53.34, by + 20.32, {'1': vn, '2': 'GND'})
    P(B5819W, 'D%d' % (3 + n), bx + 63.5, by + 12.7, {'A': vn, 'K': 'VIN_OR'}, rot=180)
    S.pwr_flag(vn, bx + 53.34, by + 10.16)
    # validity sense: Vn > 10.4 V  (2.495 V * 131.6k / 31.6k)
    P(r('100k'), 'R%d' % (10 * n + 0), bx + 63.5, by + 35.56, {'1': vn, '2': 'SNS%d' % n})
    P(r('31k6'), 'R%d' % (10 * n + 1), bx + 71.12, by + 35.56, {'1': 'SNS%d' % n, '2': 'GND'})
    P(c('100n'), 'C%d' % (10 * n + 0), bx + 78.74, by + 35.56, {'1': 'SNS%d' % n, '2': 'GND'})
    # ideal diode: LM74700 + N-FET(s), source = Vn (anode), drain = MIDn (cathode)
    P(LM74700, 'U%d' % n, bx + 106.68, by + 33.02,
      {'ANODE': vn, 'CATHODE': mid, 'GATE': 'DG%d' % n, 'VCAP': 'VCAP%d' % n, 'EN': vn, 'GND': 'GND'})
    P(c('100n', '25V'), 'C%d' % (10 * n + 1), bx + 88.9, by + 38.1, {'1': 'VCAP%d' % n, '2': vn},
      fields={'Note': 'VCAP to ANODE (charge pump)'})
    qa, qb = ([12, 13], [14, 15]) if n == 1 else ([16 + 2 * (n - 2)], [17 + 2 * (n - 2)])
    for k, q in enumerate(qa):
        P(NFET_PWR, 'Q%d' % q, bx + 127 + k * 12.7, by + 22.86, {'S': vn, 'D': mid, 'G': 'DG%d' % n},
          rot=90)
    # high-side P-FET switch(es): source = MIDn, drain = VBUS
    for k, q in enumerate(qb):
        P(PFET, 'Q%d' % q, bx + 160.02 + k * 12.7, by + 22.86, {'S': mid, 'D': 'VBUS', 'G': 'PG%d' % n},
          rot=270)
    P(r('100k'), 'R%d' % (10 * n + 2), bx + 190.5, by + 20.32, {'1': mid, '2': 'PG%d' % n},
      fields={'Note': 'off by default; with R+3 gives Vgs = -6 V when on'})
    P(r('100k'), 'R%d' % (10 * n + 3), bx + 190.5, by + 35.56, {'1': 'PG%d' % n, '2': 'PD%d' % n})
    P(c('47n', '50V'), 'C%d' % (10 * n + 2), bx + 200.66, by + 20.32, {'1': 'PG%d' % n, '2': 'VBUS'},
      fields={'Note': 'soft start: Miller cap, ~60 uA / 47 nF = ~1.3 V/ms -> ~1.3 A into 1 mF'})
    P(NFET, 'Q%d' % (20 + n), bx + 200.66, by + 50.8, {'D': 'PD%d' % n, 'S': 'GND', 'G': 'ON%d' % n})
    P(r('4k7'), 'R%d' % (10 * n + 4), bx + 213.36, by + 20.32, {'1': mid, '2': 'LA%d' % n})
    P(LED_G, 'D%d' % (6 + n), bx + 213.36, by + 33.02, {'A': 'LA%d' % n, 'K': 'PD%d' % n}, rot=90,
      fields={'Note': 'IN%d selected (rear panel)' % n})
    # ON node: pulled up from the rocker LOAD terminal, 6 V at 12 V in
    P(r('100k'), 'R%d' % (10 * n + 5), bx + 228.6, by + 20.32, {'1': 'EN_SW', '2': 'ON%d' % n})
    P(r('100k'), 'R%d' % (10 * n + 6), bx + 236.22, by + 20.32, {'1': 'ON%d' % n, '2': 'GND'})
    P(c('100n'), 'C%d' % (10 * n + 3), bx + 243.84, by + 20.32, {'1': 'ON%d' % n, '2': 'GND'})
    S.text('Q%s: ideal diode (LM74700)   Q%s: P-FET switch%s' % (
        '/'.join(map(str, qa)), '/'.join(map(str, qb)), '  - two in parallel each for 25 A' if n == 1 else ''),
        bx + 116.84, by + 50.8, 1.27)

# ---------------------------------------------------------------- priority logic
bx, by = 271.78, 15.24
S.box(bx, by, bx + 132.08, by + 129.54, 'Priority logic: LM339 (open collector, wire-AND onto ONn)')
P(TL431, 'U6', bx + 15.24, by + 20.32, {'K': 'VREF', 'REF': 'VREF', 'A': 'GND'})
P(r('4k7'), 'R4', bx + 25.4, by + 12.7, {'1': 'VIN_OR', '2': 'VREF'}, fields={'Note': 'TL431 bias ~2 mA'})
comps = [  # ref, unit, +, -, out
    ('U4', 1, 'SNS1', 'VREF', 'ON1'),   # V1 not ok -> ON1 low
    ('U4', 2, 'SNS2', 'VREF', 'ON2'),   # V2 not ok -> ON2 low
    ('U4', 3, 'VREF', 'SNS1', 'ON2'),   # V1 ok     -> ON2 low
    ('U4', 4, 'SNS3', 'VREF', 'ON3'),   # V3 not ok -> ON3 low
    ('U5', 1, 'VREF', 'SNS1', 'ON3'),   # V1 ok     -> ON3 low
    ('U5', 2, 'VREF', 'SNS2', 'ON3'),   # V2 ok     -> ON3 low
]
outpin = {1: '2', 2: '1', 3: '13', 4: '14'}
for i, (ref, u, pos, neg, out) in enumerate(comps):
    P(LM339, ref, bx + 30.48 + (i % 2) * 45.72, by + 40.64 + (i // 2) * 22.86,
      {'+': pos, '-': neg, outpin[u]: out}, unit=u)
for k, u in enumerate((3, 4)):    # spare units: inputs defined, output open
    P(LM339, 'U5', bx + 30.48 + k * 45.72, by + 109.22, {'+': 'GND', '-': 'VREF'}, unit=u, nc=(outpin[u],))
for k, ref in enumerate(('U4', 'U5')):
    P(LM339, ref, bx + 101.6 + k * 15.24, by + 20.32, {'V+': 'VIN_OR', 'V-': 'GND'}, unit=5)
P(c('100n'), 'C4', bx + 124.46, by + 20.32, {'1': 'VIN_OR', '2': 'GND'})
S.text('No hysteresis on the validity comparators: the inputs are stiff supplies\n'
       'and SNSn has 100 nF. Add 1 M feedback on a dedicated comparator if it chatters.',
       bx + 2.54, by + 120.65, 1.27)

# ---------------------------------------------------------------- master switch, lugs
bx, by = 271.78, 149.86
S.box(bx, by, bx + 132.08, by + 66.04, 'Master rocker (front panel), VBUS lugs')
P(r('47R'), 'R1', bx + 12.7, by + 20.32, {'1': 'VIN_OR', '2': 'SW_SUP'}, fp=FP_R1206)
S.place('Connector_Generic:Conn_01x03', 'J5', 'MASTER SW', bx + 38.1, by + 22.86,
        {'1': 'SW_SUP', '2': 'EN_SW', '3': 'GND'},
        footprint='Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical',
        fields={'Note': '1 SUPPLY, 2 LOAD (lamp +), 3 GND (lamp -)', 'LCSC': 'C144395 (verify)'})
S.place('Jumper:SolderJumper_2_Open', 'JP1', 'SW bypass', bx + 25.4, by + 38.1, {'A': 'SW_SUP', 'B': 'EN_SW'},
        footprint='Jumper:SolderJumper-2_P1.3mm_Open_RoundedPad1.0x1.5mm')
P(c('1u', '50V'), 'C5', bx + 50.8, by + 20.32, {'1': 'VIN_OR', '2': 'GND'})
P(c('10u', '25V', FP_C1206), 'C6', bx + 58.42, by + 20.32, {'1': 'VBUS', '2': 'GND'})
P(c('10u', '25V', FP_C1206), 'C7', bx + 66.04, by + 20.32, {'1': 'VBUS', '2': 'GND'})
P(LUG_M4, 'J6', bx + 83.82, by + 15.24, {'1': 'VBUS'}, value='VBUS lug (to main)')
P(LUG_M4, 'J7', bx + 83.82, by + 27.94, {'1': 'GND'}, value='GND lug (to main)')
S.pwr_flag('GND', bx + 101.6, by + 30.48)
S.pwr_flag('VIN_OR', bx + 101.6, by + 12.7)
for k in range(2):
    S.place(HOLE_M3['lib'], 'H%d' % (1 + k), 'M3', bx + 10.16 + k * 12.7, by + 55.88, {}, footprint=HOLE_M3['fp'])

if __name__ == '__main__':
    os.makedirs(OUTDIR, exist_ok=True)
    S.write(OUTDIR)
    write_project(OUTDIR, NAME)
    print('wrote', OUTDIR)
