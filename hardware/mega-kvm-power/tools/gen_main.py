"""MEGA-KVM power board, main (horizontal) PCB: 8 switched DUT outputs and
one always-on output group, all eFuse protected, fed from VBUS (12 V) that
comes from the input board over two M4 lugs.  Issue 0047.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kigen import Schematic, write_project  # noqa: E402
from parts import (B5819W, EFUSE_A, EFUSE_L, FP_C1206, FP_R1206, HOLE_M3, LDO, LED_G,  # noqa: E402,F401
                   LUG_M4, SS34, c, r)

NAME = 'mega-kvm-power-main'
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', NAME)

S = Schematic(NAME, 'MEGA-KVM power board - main (eFuse outputs)', paper='A3')


def P(part, ref, x, y, nets, value=None, dnp=False, nc=(), fp=None, fields=None, rot=0):
    f = dict(part.get('fields', {}))
    f.update(fields or {})
    return S.place(part['lib'], ref, value or part['value'], x, y, nets,
                   footprint=fp or part.get('fp', ''), dnp=dnp, nc=nc, fields=f, rot=rot)


def conn(n, ref, x, y, nets, value, fp, fields=None):
    lib = 'Connector_Generic:Conn_01x%02d' % n
    return S.place(lib, ref, value, x, y, nets, footprint=fp, fields=fields or {})


# ---------------------------------------------------------------- eFuse cells
RILM = '665'     # ILIM = 3334 / RILM = 5.0 A   (TPS25947 eq. 5)
CDVDT = '2n2'    # SR = 2000 pF / C = ~0.9 V/ms -> 0.45 A into 470 uF
CITIMER = '4n7'  # blanking = C * 1.51 V / 1.8 uA = ~4 ms


def efuse_cell(i, bx, by, part, en, out, flt, term):
    """One eFuse with its passives. i = cell index (0..8)."""
    base = 100 + 10 * i
    u = 'U%d' % (i + 1)
    S.box(bx, by, bx + 92, by + 58, '%s: %s' % (u, term[0]))
    ux, uy = bx + 30.48, by + 20.32
    P(part, u, ux, uy, {'IN': 'VBUS', 'EN/UVLO': en[1], 'OVLO': 'OVLO', 'DVDT': 'DVDT%d' % i,
                        'ITIMER': 'ITMR%d' % i, 'OUT': out, '~{FLT}': flt, 'ILM': 'ILM%d' % i,
                        'GND': 'GND'}, nc=('AUXOFF',))
    y = by + 45.72
    x = bx + 7.62
    step = 7.62
    if en[0] is not None:            # logic-controlled: series R + 20k pull-down
        P(r('1k'), 'R%d' % (base + 0), x, y, {'1': en[0], '2': en[1]})
        P(r('20k'), 'R%d' % (base + 1), x + step, y, {'1': en[1], '2': 'GND'})
    else:                            # always-on: UVLO divider from VBUS (~9.4 V rising)
        P(r('100k'), 'R%d' % (base + 0), x, y, {'1': 'VBUS', '2': en[1]})
        P(r('14k7'), 'R%d' % (base + 1), x + step, y, {'1': en[1], '2': 'GND'})
    P(r(RILM), 'R%d' % (base + 2), x + 2 * step, y, {'1': 'ILM%d' % i, '2': 'GND'},
      fields={'Note': 'ILIM 5.0 A (3334/R); 750R = 4.45 A for UL 2367'})
    P(c(CDVDT, '50V'), 'C%d' % (base + 0), x + 3 * step, y, {'1': 'DVDT%d' % i, '2': 'GND'})
    P(c(CITIMER, '50V'), 'C%d' % (base + 1), x + 4 * step, y, {'1': 'ITMR%d' % i, '2': 'GND'})
    P(r('10k'), 'R%d' % (base + 3), x + 5 * step, y, {'1': '+3V3', '2': flt})
    P(c('1u', '50V', FP_C1206), 'C%d' % (base + 2), x + 6 * step, y, {'1': 'VBUS', '2': 'GND'})
    P(c('1u', '50V', FP_C1206), 'C%d' % (base + 3), x + 7 * step, y, {'1': out, '2': 'GND'})
    P(r('4k7'), 'R%d' % (base + 4), x + 8 * step, y, {'1': out, '2': 'LED%d' % i})
    P(LED_G, 'D%d' % (base + 1), x + 9 * step + 2.54, y + 7.62, {'A': 'LED%d' % i, 'K': 'GND'}, rot=90)
    P(SS34, 'D%d' % (base + 0), bx + 60.96, by + 12.7, {'K': out, 'A': 'GND'}, rot=90,
      fields={'Note': 'negative-spike clamp on OUT (TI 8.3 layout)'})
    return ux, uy


CH_TERM = 'PhoenixContact:MSTBA_2,5/2-G-5,08'
FP_TERM = 'Connector_Phoenix_MSTB:PhoenixContact_MSTBA_2,5_2-G-5,08_1x02_P5.08mm_Horizontal'

for n in range(8):
    col, row = n % 4, n // 4
    bx, by = 12.7 + col * 96.52, 15.24 + row * 66.04
    efuse_cell(n, bx, by, EFUSE_L, ('CTRL%d' % n, 'EN%d' % n), 'OUT%d' % n, '~{FLT%d}' % n,
               ('DUT%d switched 12 V, 5 A' % n,))
    conn(2, 'J%d' % (10 + n), bx + 76.2, by + 22.86, {'1': 'OUT%d' % n, '2': 'GND'},
         'DUT%d 12V' % n, FP_TERM,
         fields={'MPN': 'Phoenix MSTBA 2,5/2-G-5,08 (1757242) + MSTB 2,5/2-ST-5,08 plug, 12 A',
                 'LCSC': 'TBD (or hand-fit)'})

# Always-on cell
bx, by = 12.7, 147.32
efuse_cell(8, bx, by, EFUSE_A, (None, 'EN_AON'), 'AON12', '~{FLT_AON}', ('Always-on 12 V, 5 A shared',))
S.box(bx + 96.52, by, bx + 96.52 + 92, by + 58, 'Always-on loads (Mimas x2, GS105, fans)')
ax = bx + 96.52
FP_MF2 = 'Connector_Molex:Molex_Mini-Fit_Jr_5566-02A_2x01_P4.20mm_Vertical'
for k in range(2):
    conn(2, 'J%d' % (20 + k), ax + 15.24 + k * 22.86, by + 15.24, {'1': 'AON12', '2': 'GND'},
         'MIMAS%d 12V' % k, FP_MF2,
         fields={'MPN': 'Molex 39-28-1023 (5566-02A) Mini-Fit Jr 2-pin vertical, 9 A',
                 'LCSC': 'TBD', 'Note': 'to shield power input -> Mimas header VIN (issue 0045)'})
S.place('Connector:Barrel_Jack_Switch', 'J22', 'GS105 12V', ax + 7.62, by + 35.56,
        {'1': 'AON12', '2': 'GND', '3': 'GND'},
        footprint='Connector_BarrelJack:BarrelJack_CUI_PJ-102AH_Horizontal',
        fields={'MPN': 'CUI PJ-102AH 2.1 mm, 2.5 A', 'LCSC': 'TBD',
                'Note': 'male-male 5.5/2.1 lead to the Netgear GS105'})
for k in range(2):
    fx = ax + 38.1 + k * 27.94
    P(r('0R'), 'R%d' % (190 + k), fx, by + 30.48, {'1': 'AON12', '2': 'FANPWR%d' % k}, fp=FP_R1206,
      fields={'Note': '0R; fit ~47-100R (1 W) to slow a fan for silence'})
    conn(3, 'J%d' % (23 + k), fx + 12.7, by + 40.64, {'1': 'GND', '2': 'FANPWR%d' % k, '3': 'TACH%d' % k},
         'FAN%d' % k, 'Connector:FanPinHeader_1x03_P2.54mm_Vertical',
         fields={'MPN': 'Molex 47053-1000 KK fan header 3-pin', 'LCSC': 'TBD',
                 'Note': 'Noctua NF-A4x10 FLX 12 V (50 mA)'})
    P(r('10k'), 'R%d' % (192 + k), fx, by + 48.26, {'1': '+3V3', '2': 'TACH%d' % k})

# ---------------------------------------------------------------- power entry
bx, by = 205.74, 147.32
S.box(bx, by, bx + 92, by + 58, 'VBUS entry (from input board), 3.3 V, bulk')
P(LUG_M4, 'J1', bx + 10.16, by + 15.24, {'1': 'VBUS'}, value='VBUS lug')
P(LUG_M4, 'J2', bx + 10.16, by + 25.4, {'1': 'GND'}, value='GND lug')
S.pwr_flag('VBUS', bx + 22.86, by + 12.7)
S.pwr_flag('GND', bx + 22.86, by + 27.94)
for k in range(2):
    S.place('Device:C_Polarized', 'C%d' % (1 + k), '470u 25V', bx + 33.02 + k * 7.62, by + 20.32,
            {'1': 'VBUS', '2': 'GND'}, footprint='Capacitor_SMD:CP_Elec_10x10',
            fields={'Value2': '470uF 25V low-ESR', 'LCSC': 'TBD (470uF 25V 10x10 SMD)'})
P(c('10u', '25V', FP_C1206), 'C3', bx + 48.26, by + 20.32, {'1': 'VBUS', '2': 'GND'})
P(LDO, 'U10', bx + 66.04, by + 17.78, {'IN': 'VBUS', 'OUT': '+3V3', 'GND': 'GND'})
P(c('1u', '50V'), 'C4', bx + 55.88, by + 27.94, {'1': 'VBUS', '2': 'GND'})
P(c('1u', '16V'), 'C5', bx + 78.74, by + 27.94, {'1': '+3V3', '2': 'GND'})
P(r('4k7'), 'R1', bx + 10.16, by + 43.18, {'1': 'VBUS', '2': 'LEDVB'})
P(LED_G, 'D1', bx + 17.78, by + 50.8, {'A': 'LEDVB', 'K': 'GND'}, rot=90)
# shared OVLO divider: 1.2 V * (113k + 10k) / 10k = 14.8 V
P(r('113k'), 'R2', bx + 35.56, by + 43.18, {'1': 'VBUS', '2': 'OVLO'},
  fields={'Note': 'OVLO 14.8 V shared by all 9 eFuses'})
P(r('10k'), 'R3', bx + 43.18, by + 43.18, {'1': 'OVLO', '2': 'GND'})
P(c('100n'), 'C6', bx + 50.8, by + 43.18, {'1': 'OVLO', '2': 'GND'})
S.text('VBUS 12 V nominal, 25 A max (input fuse). Sum of DUT limits (8 x 5 A + 5 A)\n'
       'exceeds the input: the input fuse/PSU is the total limit.', bx + 2.54, by + 53.34, 1.27)

# ---------------------------------------------------------------- control header + status
bx, by = 302.26, 147.32
S.box(bx, by, bx + 92, by + 58, 'Control from shield (1x11, pin 2 = key), fault/status')
conn(11, 'J3', bx + 15.24, by + 27.94,
     dict([('1', 'GND'), ('2', None)] + [(str(3 + k), 'CTRL%d' % k) for k in range(8)] + [('11', 'PRESENT')]),
     'CTRL 1x11 key2', 'Connector_PinHeader_2.54mm:PinHeader_1x11_P2.54mm_Vertical',
     fields={'Note': '1 GND, 2 KEY (pin removed / plug hole blocked), 3-10 CTRL0-7 active high, 11 PRESENT',
             'LCSC': 'TBD (2.54 mm 1x11 header)'})
P(r('10k'), 'R4', bx + 30.48, by + 15.24, {'1': '+3V3', '2': 'PRESENT'},
  fields={'Note': 'PRESENT high = power board connected and powered; shield should pull down (100k)'})
conn(12, 'J4', bx + 66.04, by + 30.48,
     dict([('1', 'GND')] + [(str(2 + k), '~{FLT%d}' % k) for k in range(8)] +
          [('10', '~{FLT_AON}'), ('11', 'TACH0'), ('12', 'TACH1')]),
     'STATUS 1x12', 'Connector_PinHeader_2.54mm:PinHeader_1x12_P2.54mm_Vertical',
     fields={'Note': '1 GND, 2-9 /FLT0-7, 10 /FLT_AON (open drain, 10k to 3V3), 11-12 fan tach',
             'LCSC': 'TBD (2.54 mm 1x12 header)'})

# ---------------------------------------------------------------- optional I2C expander
bx, by = 12.7, 213.36
S.box(bx, by, bx + 188.98, by + 71.12, 'Optional (DNP): TCA9535 fault expander on the shield I2C bus, addr 0x24')
ex, ey = bx + 45.72, by + 35.56
nets = {'VCC': '+3V3', 'GND': 'GND', 'SDA': 'SDA', 'SCL': 'SCL', '~{INT}': '~{I2C_INT}',
        'A0': 'EXA0', 'A1': 'EXA1', 'A2': 'EXA2', 'P10': '~{FLT_AON}'}
for k in range(8):
    nets['P0%d' % k] = '~{FLT%d}' % k
for k in range(1, 8):
    nets['P1%d' % k] = 'EXUNUSED'
S.place('Interface_Expansion:TCA9535PWR', 'U11', 'TCA9535PWR', ex, ey, nets,
        footprint='Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm', dnp=True,
        fields={'LCSC': 'C130204', 'Note': 'DNP by default; P00-07 /FLT0-7, P10 /FLT_AON'})
P(r('10k'), 'R11', bx + 83.82, by + 58.42, {'1': 'EXUNUSED', '2': 'GND'}, dnp=True,
  fields={'Note': 'unused P11-P17 held low; firmware may also set them as outputs'})
P(c('100n'), 'C7', bx + 83.82, by + 15.24, {'1': '+3V3', '2': 'GND'}, dnp=True)
for k, (net, to) in enumerate([('EXA0', 'GND'), ('EXA1', 'GND'), ('EXA2', '+3V3')]):
    a, b = ('1', '2') if to == 'GND' else ('2', '1')
    P(r('10k'), 'R%d' % (5 + k), bx + 101.6 + k * 7.62, by + 22.86, {a: net, b: to}, dnp=True)
for k, net in enumerate(['SDA', 'SCL', '~{I2C_INT}']):
    P(r('4k7' if k < 2 else '10k'), 'R%d' % (8 + k), bx + 101.6 + k * 7.62, by + 48.26,
      {'1': '3V3_I2C', '2': net}, dnp=True,
      fields={'Note': 'DNP: the shield normally provides the I2C pull-ups'})
conn(5, 'J5', bx + 152.4, by + 30.48, {'1': 'GND', '2': '3V3_I2C', '3': 'SDA', '4': 'SCL', '5': '~{I2C_INT}'},
     'I2C 1x5', 'Connector_PinHeader_2.54mm:PinHeader_1x05_P2.54mm_Vertical',
     fields={'Note': '1 GND, 2 3V3 (via JP1), 3 SDA, 4 SCL, 5 /INT', 'LCSC': 'TBD'})
S.place('Jumper:SolderJumper_2_Open', 'JP1', '3V3 to I2C hdr', bx + 139.7, by + 58.42,
        {'A': '+3V3', 'B': '3V3_I2C'},
        footprint='Jumper:SolderJumper-2_P1.3mm_Open_RoundedPad1.0x1.5mm',
        fields={'Note': 'open: board does not drive the shield 3V3; close for pull-ups from this board'})
S.pwr_flag('3V3_I2C', bx + 152.4, by + 58.42)

# mounting holes
for k in range(4):
    S.place(HOLE_M3['lib'], 'H%d' % (1 + k), 'M3', 213.36 + 7.62 + k * 12.7, 271.78, {},
            footprint=HOLE_M3['fp'])

S.text('Notes\n'
       '* eFuse = TPS259470L (latch-off): a DUT short latches until the shield toggles CTRLn.\n'
       '  Always-on = TPS259470A (auto-retry). EN/UVLO threshold 1.2 V: 3.3 V logic drives it directly.\n'
       '* 20k pull-downs: everything off when the shield is unplugged, unpowered or in reset.\n'
       '* Reverse current blocked (back-to-back FETs inside the eFuse). OVLO 14.8 V cuts all outputs.\n'
       '* No quick-output-discharge in TPS25947: the LED + 4k7 (2.5 mA) bleeds an unloaded output.\n'
       '* Copper: 2 oz both layers. VBUS and OUTn are polygons; see docs/hardware/power-board.md.',
       213.36, 215.9, 1.5)

if __name__ == '__main__':
    os.makedirs(OUTDIR, exist_ok=True)
    S.write(OUTDIR)
    write_project(OUTDIR, NAME)
    print('wrote', OUTDIR)
