"""MEGA-KVM front-panel board (issue 0050): 16x2 I2C LCD header (via a
PCA9306), 8 red + 8 green LEDs and 5 buttons on two TCA9535 expanders, all on
the master shield's 1x6 front-panel I2C header.

Bit map, addresses and panel geometry: docs/hardware/front-panel.md.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kigen import Schematic, write_project  # noqa: E402
from parts import (HDR, HOLE_M25, HOLE_M3, LED_GRN, LED_RED, PCA9306, RN10K,  # noqa: E402
                   SW_TACT, TCA9535, c, r)

NAME = 'mega-kvm-front'
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

S = Schematic(NAME, 'MEGA-KVM front panel - LCD, DUT LEDs, buttons', paper='A3')

# Button functions on U2 P00..P04 (active low, pressed = 0)
BUTTONS = [('SW1', 'PREV'), ('SW2', 'NEXT'), ('SW3', 'MODE'), ('SW4', 'SPARE1'), ('SW5', 'SPARE2')]
ADDR_LED = 0x25   # U1: A0=1 A1=0 A2=1
ADDR_BTN = 0x26   # U2: A0=0 A1=1 A2=1


def P(part, ref, x, y, nets, value=None, dnp=False, nc=(), fields=None, rot=0):
    f = dict(part.get('fields', {}))
    f.update(fields or {})
    return S.place(part['lib'], ref, value or part['value'], x, y, nets,
                   footprint=part.get('fp', ''), dnp=dnp, nc=nc, fields=f, rot=rot)


def header(n, ref, x, y, nets, value, note, dnp=False):
    fp, lcsc = HDR[n]
    return S.place('Connector_Generic:Conn_01x%02d' % n, ref, value, x, y, nets, footprint=fp,
                   dnp=dnp, fields={'LCSC': lcsc, 'Note': note, 'JLC': 'extended (THT)'})


def addr_nets(addr):
    a = addr & 7
    return {'A0': '+3V3' if a & 1 else 'GND', 'A1': '+3V3' if a & 2 else 'GND',
            'A2': '+3V3' if a & 4 else 'GND'}


# ------------------------------------------------------------- shield + power
bx, by = 12.7, 15.24
S.box(bx, by, bx + 96.52, by + 66.04, 'J1: front-panel I2C from the master shield (cable)')
header(6, 'J1', bx + 15.24, by + 30.48,
       {'1': 'GND', '2': '+5V', '3': '+3V3', '4': 'SDA', '5': 'SCL', '6': '~{INT}'},
       'SHIELD 1x6',
       '1 GND, 2 +5V, 3 +3V3, 4 SDA, 5 SCL, 6 /INT (open drain; 2.2k bus and 10k INT pull-ups on the shield)')
S.pwr_flag('GND', bx + 30.48, by + 50.8)
S.pwr_flag('+5V', bx + 38.1, by + 50.8)
S.pwr_flag('+3V3', bx + 45.72, by + 50.8)
P(c('10u', '10V'), 'C5', bx + 60.96, by + 25.4, {'1': '+3V3', '2': 'GND'})
P(c('100n', '50V'), 'C7', bx + 71.12, by + 25.4, {'1': '+5V', '2': 'GND'})
S.text('Bus pull-ups (2.2k to 3.3 V) are on the shield: none here on the 3.3 V side.\n'
       'All logic on this board runs at 3.3 V; only the LCD (J2) may run at 5 V.',
       bx + 2.54, by + 55.88, 1.27)

# ------------------------------------------------------------- LCD (PCA9306)
bx, by = 116.84, 15.24
S.box(bx, by, bx + 147.32, by + 66.04, 'LCD: 16x2 HD44780 + PCF8574 backpack (0x27 / 0x3F), PCA9306, VLCD jumper')
P(PCA9306, 'U3', bx + 40.64, by + 33.02,
  {'GND': 'GND', 'VREF1': '+3V3', 'SCL1': 'SCL', 'SDA1': 'SDA', 'SDA2': 'LCD_SDA',
   'SCL2': 'LCD_SCL', 'VREF2': 'VREF2', 'EN': 'VREF2'})
P(c('100n', '50V'), 'C3', bx + 15.24, by + 20.32, {'1': '+3V3', '2': 'GND'})
P(r('200k'), 'R23', bx + 63.5, by + 20.32, {'1': 'VLCD', '2': 'VREF2'},
  fields={'Note': 'VREF2/EN bias (PCA9306 data sheet 8.3)'})
P(c('100n', '50V'), 'C4', bx + 71.12, by + 20.32, {'1': 'VREF2', '2': 'GND'})
S.pwr_flag('VREF2', bx + 81.28, by + 20.32)   # fed through R23 (power_in pin on U3)
P(r('10k'), 'R21', bx + 63.5, by + 48.26, {'1': 'VLCD', '2': 'LCD_SDA'},
  fields={'Note': 'LCD-side pull-up (the backpack usually adds 4.7k-10k too)'})
P(r('10k'), 'R22', bx + 71.12, by + 48.26, {'1': 'VLCD', '2': 'LCD_SCL'})
S.place('Jumper:Jumper_3_Open', 'JP1', 'VLCD 5V|3V3', bx + 96.52, by + 22.86,
        {'1': '+5V', '2': 'VLCD', '3': '+3V3'},
        footprint=HDR[3][0],
        fields={'LCSC': HDR[3][1], 'JLC': 'extended (THT)',
                'Note': '1x3 header + 2.54 mm shunt (hand-fitted): 1-2 = 5 V LCD/backpack, 2-3 = 3.3 V LCD'})
S.pwr_flag('VLCD', bx + 106.68, by + 15.24 + 5.08)
P(c('10u', '10V'), 'C6', bx + 106.68, by + 35.56, {'1': 'VLCD', '2': 'GND'})
header(4, 'J2', bx + 129.54, by + 33.02, {'1': 'GND', '2': 'VLCD', '3': 'LCD_SDA', '4': 'LCD_SCL'},
       'LCD I2C 1x4', '1 GND, 2 VCC (VLCD), 3 SDA, 4 SCL: the usual PCF8574 backpack order; '
       '4-way F-F Dupont lead to the backpack')
S.text('With VLCD = 3.3 V the PCA9306 is a plain pass switch (both sides pulled to 3.3 V): fine.\n'
       'Backpack address: PCF8574T 0x27, PCF8574AT 0x3F (A0-A2 open). Keep it off 0x20-0x26.',
       bx + 2.54, by + 55.88, 1.27)

# ------------------------------------------------------------- LED expander
bx, by = 12.7, 88.9
S.box(bx, by, bx + 401.32, by + 101.6,
      'U1 TCA9535 @0x%02X: LEDs, active low. P0.n = red "powered" DUT n, P1.n = green "selected" DUT n '
      '(panel label n+1)' % ADDR_LED)
nets = {'VCC': '+3V3', 'GND': 'GND', 'SDA': 'SDA', 'SCL': 'SCL', '~{INT}': None}
nets.update(addr_nets(ADDR_LED))
for n in range(8):
    nets['P0%d' % n] = '~{RED%d}' % (n + 1)
    nets['P1%d' % n] = '~{GRN%d}' % (n + 1)
P(TCA9535, 'U1', bx + 38.1, by + 50.8, nets,
  fields={'Note': 'I2C 0x%02X; INT unused (all outputs)' % ADDR_LED})
P(c('100n', '50V'), 'C1', bx + 15.24, by + 88.9, {'1': '+3V3', '2': 'GND'})
for n in range(8):
    x = bx + 81.28 + n * 38.1
    for row, (pre, led, rbase, dbase) in enumerate([('RED', LED_RED, 1, 1), ('GRN', LED_GRN, 11, 11)]):
        y = by + 30.48 + row * 45.72
        k = '%s%d_K' % (pre, n + 1)
        P(led, 'D%d' % (dbase + n), x, y, {'A': '+3V3', 'K': k}, rot=0,
          fields={'Panel': '%s %d (DUT%d %s)' % (pre.lower(), n + 1, n, 'powered' if row == 0 else 'selected')})
        P(r('470'), 'R%d' % (rbase + n), x + 15.24, y + 7.62, {'1': k, '2': '~{%s%d}' % (pre, n + 1)},
          fields={'Note': '~2.5 mA at 3.3 V (Vf 2.0 V)'})
S.text('LED anodes on +3V3, cathodes through 470R to the expander (sinks; output low = on).\n'
       'TCA9535 has no internal pull-ups and powers up with all pins as inputs: LEDs off until the host\n'
       'writes the output register (default 0xFF = off) and then the configuration register (0x00 = outputs).',
       bx + 81.28, by + 92.71, 1.27)

# ------------------------------------------------------------- buttons
bx, by = 12.7, 198.12
S.box(bx, by, bx + 264.16, by + 86.36,
      'U2 TCA9535 @0x%02X: buttons (active low) -> /INT to the shield; P1 on the EXP header' % ADDR_BTN)
nets = {'VCC': '+3V3', 'GND': 'GND', 'SDA': 'SDA', 'SCL': 'SCL', '~{INT}': '~{INT}'}
nets.update(addr_nets(ADDR_BTN))
for i, (ref, fn) in enumerate(BUTTONS):
    nets['P0%d' % i] = '~{BTN_%s}' % fn
for k in range(5, 8):
    nets['P0%d' % k] = 'P0%d_SP' % k
for k in range(8):
    nets['P1%d' % k] = 'EXP%d' % k
P(TCA9535, 'U2', bx + 38.1, by + 45.72, nets, fields={'Note': 'I2C 0x%02X; /INT = J1.6' % ADDR_BTN})
P(c('100n', '50V'), 'C2', bx + 15.24, by + 81.28, {'1': '+3V3', '2': 'GND'})
pulls = (['~{BTN_%s}' % fn for _, fn in BUTTONS] + ['P0%d_SP' % k for k in range(5, 8)] +
         ['EXP%d' % k for k in range(8)])
for j in range(4):
    x = bx + 81.28 + j * 20.32
    # R_Pack04: pins 1-4 one side, 8-5 the other (pin 1 pairs with pin 8)
    pin_nets = {}
    for q in range(4):
        pin_nets[str(q + 1)] = '+3V3'
        pin_nets[str(8 - q)] = pulls[4 * j + q]
    P(RN10K, 'RN%d' % (j + 1), x, by + 20.32, pin_nets,
      fields={'Note': '10k pull-ups: every U2 pin is held high (no floating inputs, no spurious /INT)'})
for i, (ref, fn) in enumerate(BUTTONS):
    P(SW_TACT, ref, bx + 81.28 + i * 20.32, by + 50.8, {'1': '~{BTN_%s}' % fn, '2': 'GND'},
      fields={'Panel': fn})
header(10, 'J3', bx + 200.66, by + 45.72,
       dict([('1', 'GND'), ('2', '+3V3')] + [(str(3 + k), 'EXP%d' % k) for k in range(8)]),
       'EXP 1x10 (DNP)', '1 GND, 2 +3V3, 3-10 U2 P1.0-P1.7 (10k pull-ups): more buttons, a rotary encoder',
       dnp=True)
S.text('Buttons pull to GND; 10k pull-ups to 3.3 V. Debounce in host software after /INT\n'
       '(/INT is shared with the shield expander B; read both input ports to clear it).',
       bx + 81.28, by + 71.12, 1.27)

# ------------------------------------------------------------- mechanics
bx, by = 284.48, 198.12
S.box(bx, by, bx + 129.54, by + 86.36, 'Mechanics (no electrical connection)')
for k in range(4):
    S.place(HOLE_M25['lib'], 'H%d' % (1 + k), 'M2.5 LCD', bx + 10.16 + k * 15.24, by + 15.24, {},
            footprint=HOLE_M25['fp'])
for k in range(4):
    S.place(HOLE_M3['lib'], 'H%d' % (5 + k), 'M3 panel', bx + 10.16 + k * 15.24, by + 30.48, {},
            footprint=HOLE_M3['fp'])
S.text('H1-H4: 1602 LCD module (75 x 31 mm), mounted on the back of this board, bezel through\n'
       'the board window to the panel; the M2.5 screws also fix the board to the panel.\n'
       'H5-H8: M3 standoffs to the panel (3 mm). The backlit master rocker is NOT on this board:\n'
       'it sits in the panel to the right and is cabled to the power input board J5 (JST XH 3).',
       bx + 2.54, by + 45.72, 1.27)

if __name__ == '__main__':
    os.makedirs(OUTDIR, exist_ok=True)
    S.write(OUTDIR)
    write_project(OUTDIR, NAME)
    print('wrote', OUTDIR)
