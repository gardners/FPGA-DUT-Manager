"""Dedicated 6 V DUT outlet of the power board (issue 0055, owner round 15,
2026-11-27): a 9th output for a K325T FPGA board that prefers 6 V, needs at
least 5 V and may draw ~3 A (designed for 4 A continuous, 4.66 A limit).

Chain (all from VBUS, so it works from every input, banana included):

  VBUS --U71 TPS259470A (5 A, OVLO 14.8 V shared)--> VIN6
       --U73 TPS565201 buck (5 A, 500 kHz, 4.7 uH)--> +6V (6.0 V)
       --U72 TPS259470A (4.66 A, OVLO 6.9 V, UVLO 5.4 V)--> OUT6V --> J70 Micro-Fit 2x2

* No pad-free, JLC-stocked synchronous buck rated >= 24 V and >= 4 A exists
  (checked 2026-11-27: SY8205 / TPS54540 / LMR33640 / AOZ1284 have exposed
  pads, LMR51450 / JW5068 are QFN, the SOT-23 parts >= 24 V stop at 3 A).
  The TPS565201 (TSOT-23-6, leaded, 5 A) is rated 17 V (19 V abs max), so it
  sits behind its own eFuse U71 whose OVLO is the shared 14.8 V divider, like
  every other load on VBUS: VBUS spikes up to the 24.4 V TVS clamp never
  reach it, and a failed buck cannot short VBUS.
* Control: one line, 6V_EN, from the power board's TCA9535 U11 P1.5 (1 k,
  20 k pull-down: the expander powers up with every pin an input, so the
  outlet stays off until the host drives P1.5 high).  6V_EN switches U71 (the
  buck is unpowered while the outlet is off) and, through D730, holds U72 off.
  U72's own EN/UVLO divider closes it only once +6V is above 5.4 V.
* Readback: /FLT of U71 and U72 wire-ORed on U11 P1.6 (~FLT6V), OUT6V
  through 20 k / 20 k on U11 P1.7 (6V_PG, high above ~4.6 V).
"""
from parts import EFUSE_A, FP_C1206, LED_G, SS34, c, r

FP_RPW = EFUSE_A['fp']
FP_MICROFIT = 'Connector_Molex:Molex_Micro-Fit_3.0_43045-0400_2x02_P3.00mm_Horizontal'
FP_L = 'Inductor_SMD:L_Changjiang_FXL1040'
C10U = dict(c('10u', '50V', FP_C1206), fields={'LCSC': 'C13585', 'Voltage': '50V',
                                               'MPN': 'Samsung CL31A106KBHNNNE 10 uF 50 V X5R 1206 (JLC basic)'})
SW_DIODE = dict(lib='Device:D', fp='Diode_SMD:D_SOD-323', value='1N4148WS',
                fields={'LCSC': 'C2128', 'MPN': '1N4148WS 100 V 150 mA SOD-323 (JLC basic); silicon, not '
                                                 'Schottky: its reverse leakage into EN6O stays < 0.5 uA hot'})
C22U = dict(c('22u', '25V', FP_C1206), fields={'LCSC': 'C12891', 'Voltage': '25V',
                                               'MPN': 'Samsung CL31A226KAHNNNE 22 uF 25 V X5R 1206 (JLC basic)'})


def r01(value):
    """0.1 % resistor for the output-voltage divider."""
    return dict(r(value, '0.1%'), fields={'Tolerance': '0.1%',
                                          'LCSC': 'TBD (0603 0.1 %% thin film %s, e.g. Yageo RT0603BRD07)' % value})


def build(S, P, ox, oy):
    # ------------------------------------------------------------ control and status (U11 side)
    bx, by = ox, oy
    S.box(bx, by, bx + 92, by + 58.42, '6 V outlet control: TCA9535 U11 P1.5-P1.7 (0x24)')
    P(r('1k'), 'R700', bx + 12.7, by + 15.24, {'1': '6V_CTRL', '2': '6V_EN'},
      fields={'Note': 'from U11 P1.5 (push-pull output once the host configures it)'})
    P(r('20k'), 'R701', bx + 25.4, by + 22.86, {'1': '6V_EN', '2': 'GND'},
      fields={'Note': 'outlet off while U11 P1.5 is an input (power-on default), U11 unpowered or the shield off'})
    P(r('10k'), 'R702', bx + 38.1, by + 15.24, {'1': '+3V3', '2': '~{FLT6V}'},
      fields={'Note': '/FLT of U71 and U72 (open drain, wire-OR) -> U11 P1.6'})
    S.text('Host (I2C 0x24): write Output Port 1 (03h) bit 5 = 0 FIRST (default 1 = on!),\n'
           'then Configuration Port 1 (07h) = DFh (P1.5 output, the rest inputs).\n'
           'On: 03h bit 5 = 1.  Off: 03h bit 5 = 0.  Read Input Port 1 (01h):\n'
           'bit 5 = 6V_EN as driven, bit 6 = /FLT6V (0 = fault), bit 7 = 6V_PG (1 = outlet live).',
           bx + 2.54, by + 33.02, 1.27)

    # ------------------------------------------------------------ U71: VBUS -> VIN6 (input eFuse)
    bx = ox + 96.52
    S.box(bx, by, bx + 92, by + 58.42, 'U71: VBUS -> VIN6, buck input eFuse, 5 A, OVLO 14.8 V (shared)')
    P(EFUSE_A, 'U71', bx + 30.48, by + 20.32,
      {'IN': 'VBUS', 'EN/UVLO': '6V_EN', 'OVLO': 'OVLO', 'DVDT': 'DVDT6I', 'ITIMER': 'ITMR6I',
       'OUT': 'VIN6', '~{FLT}': '~{FLT6V}', 'ILM': 'ILM6I', 'GND': 'GND'}, nc=('AUXOFF',),
      fields={'Note': 'keeps VBUS spikes (TVS clamp up to 24.4 V) off the 17 V buck; '
                      'isolates a failed buck from VBUS; off = buck unpowered'})
    y, x, step = by + 45.72, bx + 7.62, 7.62
    P(r('665'), 'R710', x, y, {'1': 'ILM6I', '2': 'GND'}, fields={'Note': 'ILIM 5.0 A (3334/R), as the 12 V cells'})
    P(c('2n2', '50V'), 'C710', x + step, y, {'1': 'DVDT6I', '2': 'GND'})
    P(c('4n7', '50V'), 'C711', x + 2 * step, y, {'1': 'ITMR6I', '2': 'GND'})
    P(c('1u', '50V', FP_C1206), 'C712', x + 3 * step, y, {'1': 'VBUS', '2': 'GND'})
    P(c('1u', '50V', FP_C1206), 'C713', x + 4 * step, y, {'1': 'VIN6', '2': 'GND'})

    # ------------------------------------------------------------ U73: VIN6 -> +6V (buck)
    bx = ox + 193.04
    S.box(bx, by, bx + 92, by + 58.42, 'U73 TPS565201: VIN6 (10.5-14.8 V) -> +6V, 5 A, 500 kHz')
    P(dict(lib='Regulator_Switching:TPS565208', value='TPS565201DDCR',
           fp='Package_TO_SOT_SMD:TSOT-23-6',
           fields={'LCSC': 'C327676', 'MPN': 'TI TPS565201DDCR 4.5-17 V, 5 A sync buck, D-CAP2, Eco-mode, '
                                             '500 kHz, TSOT-23-6 (no pad); symbol of the TPS565208 (same pinout)'}),
      'U73', bx + 30.48, by + 22.86,
      {'VIN': 'VIN6', 'GND': 'GND', 'SW': 'SW6', 'VBST': 'BST6', 'EN': 'EN_BK', 'VFB': 'FB6'},
      fields={'Note': 'runs whenever U71 is on (EN from VIN6, starts at ~6-8 V); 1 ms internal soft start'})
    S.place('Device:L', 'L70', '4.7u', bx + 55.88, by + 17.78, {'1': 'SW6', '2': '+6V'}, footprint=FP_L,
            fields={'LCSC': 'C167230', 'MPN': 'Changjiang FXL1040-4R7-M 4.7 uH, 20 mOhm, Irms 9 A, Isat 15 A, 11.5 x 10 mm'})
    S.pwr_flag('+6V', bx + 68.58, by + 10.16)
    y = by + 45.72
    x = bx + 5.08
    step = 6.35
    P(C10U, 'C720', x, y, {'1': 'VIN6', '2': 'GND'})
    P(C10U, 'C721', x + step, y, {'1': 'VIN6', '2': 'GND'})
    P(C10U, 'C722', x + 2 * step, y, {'1': 'VIN6', '2': 'GND'},
      fields={'Note': '3 x 10 uF: ~2.3 A rms input ripple current at 4.66 A out'})
    P(c('100n'), 'C723', x + 3 * step, y, {'1': 'VIN6', '2': 'GND'})
    P(c('100n'), 'C724', bx + 45.72, by + 10.16, {'1': 'BST6', '2': 'SW6'}, fields={'Note': 'VBST - SW'})
    P(r('100k'), 'R720', x + 4 * step, y, {'1': 'VIN6', '2': 'EN_BK'})
    P(r('33k'), 'R721', x + 5 * step, y, {'1': 'EN_BK', '2': 'GND'},
      fields={'Note': 'EN 1.6 V max with REN 120-400k internal: buck starts at VIN6 ~6-8 V; '
                      'EN 3.3 V at 14.8 V'})
    P(r01('27k'), 'R722', x + 6 * step, y, {'1': '+6V', '2': 'FB6'},
      fields={'Note': 'VOUT = 0.760 V x (1 + 27k / 3.92k) = 5.995 V'})
    P(r01('3k92'), 'R723', x + 7 * step, y, {'1': 'FB6', '2': 'GND'})
    P(C22U, 'C725', x + 8 * step, y, {'1': '+6V', '2': 'GND'})
    P(C22U, 'C726', x + 9 * step, y, {'1': '+6V', '2': 'GND'})
    P(C22U, 'C727', x + 10 * step, y, {'1': '+6V', '2': 'GND'},
      fields={'Note': '3 x 22 uF (~40 uF at 6 V bias): TI range 20-68 uF; ~10 mV ripple'})

    # ------------------------------------------------------------ U72: +6V -> OUT6V (outlet eFuse)
    bx, by = ox, oy + 73.66
    S.box(bx, by, bx + 140, by + 58.42, 'U72: +6V -> J70 "DUT 6V ONLY (K325T)", 4.66 A, OVLO 6.9 V, UVLO 5.4 V')
    P(EFUSE_A, 'U72', bx + 30.48, by + 20.32,
      {'IN': '+6V', 'EN/UVLO': 'EN6O', 'OVLO': 'OVLO6', 'DVDT': 'DVDT6O', 'ITIMER': 'ITMR6O',
       'OUT': 'OUT6V', '~{FLT}': '~{FLT6V}', 'ILM': 'ILM6O', 'GND': 'GND'}, nc=('AUXOFF',),
      fields={'Note': 'opens within 1.2 us above 6.9 V (e.g. a shorted buck high-side FET)'})
    y, x, step = by + 45.72, bx + 7.62, 7.62
    P(r('715'), 'R730', x, y, {'1': 'ILM6O', '2': 'GND'},
      fields={'Note': 'ILIM 4.66 A (3334/R), +-10 %: 4.2-5.1 A; below the buck limit (5.3 A valley min, ~5.9 A average)'})
    P(c('2n2', '50V'), 'C730', x + step, y, {'1': 'DVDT6O', '2': 'GND'})
    P(c('4n7', '50V'), 'C731', x + 2 * step, y, {'1': 'ITMR6O', '2': 'GND'})
    P(r('475k'), 'R731', x + 3 * step, y, {'1': '+6V', '2': 'OVLO6'},
      fields={'Note': 'OVLO 1.20 V x 5.75 = 6.90 V rising, 6.27 V falling'})
    P(r('100k'), 'R732', x + 4 * step, y, {'1': 'OVLO6', '2': 'GND'})
    P(c('100n'), 'C732', x + 5 * step, y, {'1': 'OVLO6', '2': 'GND'})
    P(r('348k'), 'R733', x + 6 * step, y, {'1': '+6V', '2': 'EN6O'},
      fields={'Note': 'UVLO 1.20 V x 4.48 = 5.38 V rising, 4.88 V falling; high impedance so that '
                      'D730 cannot lift 6V_EN above 0.4 V through the 20 k pull-down'})
    P(r('100k'), 'R734', x + 7 * step, y, {'1': 'EN6O', '2': 'GND'})
    P(SW_DIODE, 'D730', x + 8 * step, y - 15.24, {'A': 'EN6O', 'K': '6V_EN'}, rot=0,
      fields={'Note': '6V_EN low pulls EN6O to ~0.5 V (< 1.09 V): U72 opens at once, not when +6V has decayed'})
    P(c('1u', '50V', FP_C1206), 'C733', x + 9 * step, y, {'1': '+6V', '2': 'GND'})
    P(c('1u', '50V', FP_C1206), 'C734', x + 10 * step, y, {'1': 'OUT6V', '2': 'GND'})
    # outlet
    P(SS34, 'D740', bx + 76.2, by + 15.24, {'K': 'OUT6V', 'A': 'GND'}, rot=90,
      fields={'Note': 'negative-spike clamp on OUT (TI 8.3 layout)'})
    P(r('1k'), 'R740', bx + 88.9, by + 10.16, {'1': 'OUT6V', '2': 'LED6V'},
      fields={'Note': '4 mA: "6V" LED at the outlet, also bleeds an unloaded output'})
    P(LED_G, 'D741', bx + 88.9, by + 25.4, {'A': 'LED6V', 'K': 'GND'}, rot=90,
      fields={'Note': '"6V" outlet live (by J70)'})
    P(r('20k'), 'R741', bx + 101.6, by + 10.16, {'1': 'OUT6V', '2': '6V_PG'})
    P(r('20k'), 'R742', bx + 101.6, by + 25.4, {'1': '6V_PG', '2': 'GND'},
      fields={'Note': '3.0 V at 6 V (3.45 V at 6.9 V); TCA9535 high above ~4.6 V on OUT6V; -> U11 P1.7'})
    S.place('Connector_Generic:Conn_02x02_Odd_Even', 'J70', 'DUT 6V ONLY (K325T)', bx + 124.46, by + 20.32,
            {'1': 'GND', '2': 'GND', '3': 'OUT6V', '4': 'OUT6V'}, footprint=FP_MICROFIT,
            fields={'MPN': 'Molex 43045-0400 Micro-Fit 3.0 2x2 right-angle header, 3.0 mm, 8.5 A per contact, '
                           'positive latch, polarised; pins 1-2 GND, 3-4 +6 V (two contacts per pole). '
                           'Mates 43025-0400 (C122417) + 43030-0001 crimps (C259786, 20-24 AWG)',
                    'LCSC': 'C122413', 'Assembly': 'THT',
                    'Note': 'deliberately not VH (5 V), screw terminal (12 V) or Mini-Fit Jr (Mimas 12 V)'})
    S.text('K325T outlet: 6.0 V, designed for 4 A continuous, limit 4.66 A (auto-retry).\n'
           'Off (6V_EN low): U71 open, buck unpowered, U72 open via D730.\n'
           'On: VIN6 ramps (~0.9 V/ms), buck soft-starts at VIN6 ~6-8 V, U72 closes at +6V > 5.4 V\n'
           'and ramps OUT6V at ~0.9 V/ms (0.9 A into 1000 uF).',
           bx + 2.54, by + 63.5, 1.27)
