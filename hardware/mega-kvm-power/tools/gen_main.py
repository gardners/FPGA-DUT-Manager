"""MEGA-KVM power board, main (horizontal) PCB: 8 switched DUT outputs and
one always-on output group, all eFuse protected, fed from VBUS (12 V) that
comes from the input board over two M4 lugs.  Issue 0047.
Input stage (round 12, one board): banana / PCIe / Molex inputs, fuses, TVS,
LTC4417 priority select with back-to-back P-FETs, master rocker (tools/input_stage.py).
Fans: 8 x 4-pin PWM headers with per-header BSP452 protection, 4 x EMC2302
behind a TCA9548A on the J5 I2C bus, TMP75 sensors.  Issue 0052.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kigen import Schematic, write_project  # noqa: E402
import input_stage  # noqa: E402
import five_volt  # noqa: E402
from parts import (B5819W, EFUSE_A, EFUSE_L, FAN_CTRL, FAN_HDR, FAN_SW, FP_C1206, FP_R1206,  # noqa: E402,F401
                   HOLE_M3, I2C_MUX, LDO, LED_G, NFET, SS34, TSENS, c, r)

NAME = 'mega-kvm-power-main'
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', NAME)

S = Schematic(NAME, 'MEGA-KVM power board - main (eFuse outputs, fans)', paper='A1', rev='0.4')


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


def efuse_cell(i, bx, by, part, en, out, flt, term, sel=None):
    """One eFuse with its passives. i = cell index (0..8). sel: the series 1 k
    goes to this net (the 12 V / 5 V selector JPn, issue 0055) instead of EN."""
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
        P(r('1k'), 'R%d' % (base + 0), x, y, {'1': en[0], '2': sel or en[1]},
          fields={'Note': 'to selector %s pin 2 (shunt 1-2 = this 12 V output)' % sel} if sel else None)
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


FP_TERM = 'TerminalBlock_Phoenix:TerminalBlock_Phoenix_MKDS-1,5-2-5.08_1x02_P5.08mm_Horizontal'

for n in range(8):
    col, row = n % 4, n // 4
    bx, by = 12.7 + col * 96.52, 15.24 + row * 66.04
    efuse_cell(n, bx, by, EFUSE_L, ('CTRL%d' % n, 'EN%d' % n), 'OUT%d' % n, '~{FLT%d}' % n,
               ('DUT%d switched 12 V, 5 A' % n + (' (or 5 V via JP%d)' % n if n in five_volt.CHANNELS else ''),),
               sel='CSEL%d' % n if n in five_volt.CHANNELS else None)
    conn(2, 'J%d' % (10 + n), bx + 76.2, by + 22.86, {'1': 'OUT%d' % n, '2': 'GND'},
         'DUT%d 12V' % n, FP_TERM,
         fields={'MPN': '2-pole 5.08 mm PCB screw terminal, MKDS 1,5/2-5,08 class (13.5 A); '
                        'pin 1 = + (OUTn), pin 2 = - (GND)',
                 'LCSC': 'TBD: JLC-stocked KF128/DG128-5.08-2P clone (THT, machine/wave assembled)'})

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
S.text('8 x 4-pin PWM fans: see the fan section below\n(FAN0-1 KVM front panel, FAN2-4 shelf plate A,\nFAN5-7 shelf plate B; issue 0052).', ax + 38.1, by + 22.86, 1.27)

# ---------------------------------------------------------------- fans (issue 0052)
# Per header: BSP452 smart high-side switch (current limit 0.7-2.4 A, thermal
# auto-restart) from the always-on group, so a shorted fan lead cannot pull the
# Mimas/GS105 group into its 5 A limit.  PWM through a 2N7002 inverter: with the
# EMC2302 unpowered, held in reset, at its power-on default or after its
# watchdog fires, the FET is off and the fan's PWM input is high = full speed.
FAN_USE = ['KVM front panel', 'KVM front panel', 'shelf plate A', 'shelf plate A', 'shelf plate A',
           'shelf plate B', 'shelf plate B', 'shelf plate B']
for k in range(8):
    col, row = k % 4, k // 4
    bx, by = 12.7 + col * 96.52, 292.1 + row * 60.96
    base = 300 + 10 * k
    S.box(bx, by, bx + 92, by + 55.88, 'FAN%d (%s): switch + PWM inverter + tach' % (k, FAN_USE[k]))
    P(FAN_SW, 'U%d' % (30 + k), bx + 22.86, by + 17.78,
      {'Vbb': 'AON12', 'IN': 'FANIN%d' % k, 'GND': 'GND', 'OUT': 'FANPWR%d' % k})
    P(r('10k'), 'R%d' % (base + 0), bx + 7.62, by + 20.32, {'1': 'AON12', '2': 'FANIN%d' % k},
      fields={'Note': 'BSP452 IN tied on (input current <= 100 uA, IN may go to Vbb)'})
    P(FAN_HDR, 'J%d' % (30 + k), bx + 50.8, by + 17.78,
      {'1': 'GND', '2': 'FANPWR%d' % k, '3': 'FTACH%d' % k, '4': 'FPWM%d' % k}, value='FAN%d' % k,
      fields={'Note': '1 GND, 2 +12 V, 3 TACH, 4 PWM (Intel 4-wire); 3-pin fans run at full speed'})
    P(NFET, 'Q%d' % (30 + k), bx + 22.86, by + 43.18, {'G': 'PWMG%d' % k, 'S': 'GND', 'D': 'FPWM%d' % k},
      fields={'Note': 'PWM inverter: EMC2302 PWM polarity must be set to inverted (reg 2Ah)'})
    P(r('100k'), 'R%d' % (base + 1), bx + 7.62, by + 43.18, {'1': 'PWMG%d' % k, '2': 'GND'},
      fields={'Note': 'gate pull-down: FET off (fan full speed) unless the EMC2302 drives push-pull high'})
    P(r('4k7'), 'R%d' % (base + 2), bx + 38.1, by + 40.64, {'1': '+3V3', '2': 'FPWM%d' % k},
      fields={'Note': 'PWM pull-up for fans without an internal one'})
    P(r('10k'), 'R%d' % (base + 3), bx + 66.04, by + 40.64, {'1': '+3V3', '2': 'FTACH%d' % k},
      fields={'Note': 'tach pull-up (open-collector tach); to 3V3 so the EMC2302 never sees > 3.6 V'})
    P(r('1k'), 'R%d' % (base + 4), bx + 78.74, by + 40.64, {'1': 'FTACH%d' % k, '2': 'TACH%d' % k},
      fields={'Note': 'series protection on the long tach lead'})

# ---------------------------------------------------------------- fan controllers, sensor (I2C, J5 bus)
bx, by = 408.94, 15.24
S.box(bx, by, bx + 172.72, by + 271.78,
      'I2C housekeeping (shield bus via J5): TCA9548A 0x70 -> 4 x EMC2302-1 (0x2E), TMP75 0x48')
mux = {'A0': 'GND', 'A1': 'GND', 'A2': 'GND', '~{RESET}': 'MUXRST', 'SDA': 'SDA', 'SCL': 'SCL',
       'VCC': '+3V3', 'GND': 'GND'}
for m in range(4):
    mux['SD%d' % m] = 'FSDA%d' % m
    mux['SC%d' % m] = 'FSCL%d' % m
S.place(I2C_MUX['lib'], 'U12', I2C_MUX['value'], bx + 30.48, by + 55.88, mux,
        footprint=I2C_MUX['fp'], nc=('SD4', 'SC4', 'SD5', 'SC5', 'SD6', 'SC6', 'SD7', 'SC7'),
        fields=dict(I2C_MUX['fields'], Note='0x70; channel m (0-3) = fan controller U14+m'))
P(c('100n'), 'C400', bx + 12.7, by + 22.86, {'1': '+3V3', '2': 'GND'})
P(r('10k'), 'R400', bx + 12.7, by + 99.06, {'1': '+3V3', '2': 'MUXRST'})
for m in range(4):
    P(r('4k7'), 'R%d' % (401 + 2 * m), bx + 55.88 + 7.62 * m, by + 99.06, {'1': '+3V3', '2': 'FSDA%d' % m})
    P(r('4k7'), 'R%d' % (402 + 2 * m), bx + 55.88 + 7.62 * m, by + 114.3, {'1': '+3V3', '2': 'FSCL%d' % m})
for m in range(4):
    ex, ey = bx + 129.54, by + 27.94 + m * 43.18
    P(FAN_CTRL, 'U%d' % (14 + m), ex, ey,
      {'SMDATA': 'FSDA%d' % m, 'SMCLK': 'FSCL%d' % m, 'VDD': '+3V3', 'GND': 'GND',
       'PWM1': 'PWMG%d' % (2 * m), 'TACH1': 'TACH%d' % (2 * m),
       'PWM2': 'PWMG%d' % (2 * m + 1), 'TACH2': 'TACH%d' % (2 * m + 1),
       'CLK': 'FCLK%d' % m, '~{ALERT}': '~{I2C_INT}'},
      fields={'Note': 'behind mux channel %d; fans %d and %d' % (m, 2 * m, 2 * m + 1)})
    P(c('100n'), 'C%d' % (401 + m), ex + 22.86, ey + 7.62, {'1': '+3V3', '2': 'GND'})
    P(r('10k'), 'R%d' % (410 + m), ex - 22.86, ey + 7.62, {'1': 'FCLK%d' % m, '2': 'GND'},
      fields={'Note': 'CLK unused (internal clock); pulled down, not tied, as it can be set to an output'})
P(TSENS, 'U13', bx + 30.48, by + 160.02,
  {'SDA': 'SDA', 'SCL': 'SCL', 'O.S.': '~{I2C_INT}', 'A0': 'GND', 'A1': 'GND', 'A2': 'GND',
   '+Vs': '+3V3', 'GND': 'GND'},
  fields={'Note': '0x48: placed between the input FETs and the eFuse row (the FETs are the '
                  'hottest parts); ALERT on /INT (default 80 C / 75 C)'})
P(c('100n'), 'C405', bx + 12.7, by + 147.32, {'1': '+3V3', '2': 'GND'})
P(r('10k'), 'R12', bx + 55.88, by + 147.32, {'1': '+3V3', '2': '~{I2C_INT}'},
  fields={'Note': '/INT pull-up: EMC2302 ALERT, TMP75 ALERT, optional TCA9535'})
S.text('Bring-up (host or FPGA), per controller m = 0..3:\n'
       '  write 0x70 <- (1 << m)            select mux channel m\n'
       '  0x2E reg 2Bh <- 03h               PWM1/2 push-pull\n'
       '  0x2E reg 2Ah <- 03h               PWM1/2 inverted (2N7002 inverts again)\n'
       '  0x2E reg 30h / 40h <- duty        fan 2m / 2m+1, 00h-FFh = 0-100 %\n'
       '  0x2E reg 20h <- 60h               keep the 4 s watchdog armed (WD_EN)\n'
       '  0x2E reg 3Eh,3Fh / 4Eh,4Fh        count = hi<<5 | lo>>3; RPM = 7864320 / count\n'
       'Power-on / no traffic / no 3V3 / watchdog expired: fans at 100 %.\n'
       'See docs/hardware/power-board.md "Fan control".', bx + 76.2, by + 205.74, 1.27)

# ---------------------------------------------------------------- power entry
bx, by = 205.74, 147.32
S.box(bx, by, bx + 92, by + 58, 'VBUS (from the input stage), 3.3 V, bulk')
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
conn(10, 'J4', bx + 66.04, by + 30.48,
     dict([('1', 'GND')] + [(str(2 + k), '~{FLT%d}' % k) for k in range(8)] +
          [('10', '~{FLT_AON}')]),
     'STATUS 1x10', 'Connector_PinHeader_2.54mm:PinHeader_1x10_P2.54mm_Vertical',
     fields={'Note': '1 GND, 2-9 /FLT0-7, 10 /FLT_AON (open drain, 10k to 3V3); '
                     'fan tach now read over I2C (EMC2302)',
             'LCSC': 'TBD (2.54 mm 1x10 header)'})

# ---------------------------------------------------------------- optional I2C expander
bx, by = 12.7, 213.36
S.box(bx, by, bx + 188.98, by + 71.12, 'Optional (DNP): TCA9535 fault expander on the shield I2C bus, addr 0x24')
ex, ey = bx + 45.72, by + 35.56
nets = {'VCC': '+3V3', 'GND': 'GND', 'SDA': 'SDA', 'SCL': 'SCL', '~{INT}': '~{I2C_INT}',
        'A0': 'EXA0', 'A1': 'EXA1', 'A2': 'EXA2', 'P10': '~{FLT_AON}'}
for k in range(8):
    nets['P0%d' % k] = '~{FLT%d}' % k
nets['P11'] = '5V_PRESENT'          # issue 0055: Molex +5 V present (divider R601/R602)
for k, n in enumerate(five_volt.CHANNELS):   # 0055: 5 V eFuse EN = channel n on and set to 5 V
    nets['P1%d' % (2 + k)] = 'EN5V%d' % n
for k in range(5, 8):
    nets['P1%d' % k] = 'EXUNUSED'
S.place('Interface_Expansion:TCA9535PWR', 'U11', 'TCA9535PWR', ex, ey, nets,
        footprint='Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm', dnp=True,
        fields={'LCSC': 'C130204', 'Note': 'DNP by default; P00-07 /FLT0-7 (5-7: 12 V or 5 V output), '
                                           'P10 /FLT_AON, P11 5V_PRESENT, P12-14 EN5V5-7'})
P(r('10k'), 'R11', bx + 83.82, by + 58.42, {'1': 'EXUNUSED', '2': 'GND'}, dnp=True,
  fields={'Note': 'unused P15-P17 held low; firmware may also set them as outputs'})
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
for k in range(8):
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

# ---------------------------------------------------------------- input stage (0047 round 12)
input_stage.build(S, P, 609.6, 15.24)

# ---------------------------------------------------------------- 5 V DUT outputs (issue 0055)
five_volt.build(S, P, 12.7, 419.1)

if __name__ == '__main__':
    os.makedirs(OUTDIR, exist_ok=True)
    S.write(OUTDIR)
    write_project(OUTDIR, NAME)
    print('wrote', OUTDIR)
