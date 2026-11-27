"""Input stage of the one-board power PCB (issue 0047 owner round 12).

Three 12 V inputs, one used at a time by automatic priority (LTC4417):
  V1 = 4 mm banana pair (25 A fuse)  > V2 = PCIe 8-pin (15 A) > V3 = Molex 4-pin (10 A).
Each input: blade fuse, then a unidirectional TVS (hot-plug spikes; a reversed
supply forward-biases it and blows the fuse).  The back-to-back P-FET pairs
feed VBUS directly on this board (no lugs, no second board).  The front-panel
illuminated rocker switches LTC4417 EN (master on/off, not the 25 A path).

Ported from the legacy input-board generator (gen_inputs.py); references are
renumbered into the 50x/5xx range so they do not clash with the main board.
"""
from parts import B5819W, FP_C1206, FP_R1206, LED_G, NFET, PFET, TVS, c, r

FUSE_FP = 'Fuse:FuseHolder_Blade_ATO_Littelfuse_FLR_178.6165'
INPUTS = [  # n, name, fuse
    (1, 'Banana 4 mm', '25A ATO'),
    (2, 'PCIe 8-pin', '15A ATO'),
    (3, 'Molex 4-pin', '10A ATO'),
]
# FET references per input: (input side, output side); banana has a third pair DNP
FETS = {1: (['Q501', 'Q502', 'Q512'], ['Q503', 'Q504', 'Q513']),
        2: (['Q505'], ['Q506']),
        3: (['Q507'], ['Q508'])}
FET_DNP = ('Q512', 'Q513')


def build(S, P, ox, oy):
    for n, label, fuse in INPUTS:
        bx, by = ox, oy + (n - 1) * 58.42
        S.box(bx, by, bx + 193.04, by + 53.34, 'Input V%d: %s, fuse %s, priority %d' % (n, label, fuse, n))
        raw = 'IN%d_RAW' % n
        vn = 'V%d' % n
        if n == 1:
            for ref, net, col, colour in (('J50', raw, 'red', '+12V'), ('J51', 'GND', 'black', 'GND')):
                S.place('Connector_Generic:Conn_01x01', ref, 'BANANA %s (%s)' % (colour, col),
                        bx + 12.7, by + (15.24 if ref == 'J50' else 33.02), {'1': net},
                        footprint='Connector:Banana_Jack_1Pin',
                        fields={'MPN': '4 mm PCB-mount banana socket, %s, 24 A (e.g. 24.243.%d, THT; '
                                       'CHECK the footprint against the chosen part)' % (col, 1 if col == 'red' else 2),
                                'LCSC': 'C7437321' if col == 'red' else 'C7437322', 'Assembly': 'THT'})
        elif n == 2:
            S.place('Connector_Generic:Conn_02x04_Counter_Clockwise', 'J52', 'PCIe 8-pin', bx + 12.7, by + 25.4,
                    {'1': raw, '2': raw, '3': raw, '4': 'GND', '5': 'GND', '6': 'GND', '7': 'GND', '8': 'GND'},
                    footprint='Connector_Molex:Molex_Mini-Fit_Jr_5566-08A_2x04_P4.20mm_Vertical',
                    fields={'MPN': 'Molex Mini-Fit Jr 8-pin vertical header with PCIe keying (45558-series '
                                   'or 39-28-1083 + check keying); pins 1-3 +12 V, 4-8 GND (sense pins grounded)',
                            'LCSC': 'TBD (JLC-stocked Mini-Fit 2x4 vertical)', 'Assembly': 'THT'})
        else:
            S.place('Connector_Generic:Conn_01x04', 'J53', 'Molex 4-pin', bx + 12.7, by + 25.4,
                    {'1': raw, '2': 'GND', '3': 'GND'}, nc=('4',),
                    footprint='mega-kvm-power:Molex_8981_PeripheralPower_1x04_P5.08mm_Vertical',
                    fields={'MPN': 'Molex 8981 4-pin male PCB header, vertical (e.g. 15-24-4048); '
                                   '1 +12 V, 2-3 GND, 4 +5 V unused', 'LCSC': 'TBD', 'Assembly': 'THT'})
        S.place('Device:Fuse', 'F%d' % n, fuse, bx + 38.1, by + 20.32, {'1': raw, '2': vn},
                footprint=FUSE_FP,
                fields={'MPN': 'Littelfuse 178.6165.0002 ATO PCB holder + ATO blade fuse %s' % fuse,
                        'LCSC': 'TBD', 'Assembly': 'THT'})
        P(TVS, 'D%d' % (500 + n), bx + 53.34, by + 20.32, {'K': vn, 'A': 'GND'}, rot=90)
        P(c('1u', '50V', FP_C1206), 'C%d' % (500 + n), bx + 63.5, by + 20.32, {'1': vn, '2': 'GND'})
        P(B5819W, 'D%d' % (503 + n), bx + 76.2, by + 15.24, {'A': vn, 'K': 'VIN_OR'}, rot=180,
          fields={'Note': 'diode-OR: master-switch supply that exists before VBUS'})
        # UV/OV divider: UV rising ~10.5 V, OV ~14.0 V (1.0 V comparators; verify vs datasheet)
        P(r('1M27'), 'R%d' % (500 + 10 * n + 0), bx + 91.44, by + 20.32, {'1': vn, '2': 'UV%d' % n})
        P(r('33k2'), 'R%d' % (500 + 10 * n + 1), bx + 99.06, by + 20.32, {'1': 'UV%d' % n, '2': 'OV%d' % n})
        P(r('100k'), 'R%d' % (500 + 10 * n + 2), bx + 106.68, by + 20.32, {'1': 'OV%d' % n, '2': 'GND'})
        qa, qb = FETS[n]
        note = {'Note': 'optional third pair, fit if the bench shows it is needed'}
        for k, q in enumerate(qa):
            P(PFET, q, bx + 121.92 + k * 10.16, by + 22.86, {'D': vn, 'S': 'VS%d' % n, 'G': 'G%d' % n},
              dnp=q in FET_DNP, fields=note if q in FET_DNP else None)
        for k, q in enumerate(qb):
            P(PFET, q, bx + 154.94 + k * 10.16, by + 22.86, {'D': 'VBUS', 'S': 'VS%d' % n, 'G': 'G%d' % n},
              dnp=q in FET_DNP, fields=note if q in FET_DNP else None)
        # soft start (owner round 5): Miller capacitor gate -> VBUS
        P(c('22n', '50V'), 'C%d' % (510 + n), bx + 185.42, by + 7.62, {'1': 'G%d' % n, '2': 'GSS%d' % n},
          fields={'Note': 'soft start: gate-drain (VBUS) Miller cap, value TBD on bench'})
        P(r('1k'), 'R%d' % (500 + 10 * n + 3), bx + 185.42, by + 40.64, {'1': 'GSS%d' % n, '2': 'VBUS'})
        S.text('%s: input side (D=V%d)   %s: output side (D=VBUS)%s' % (
            '/'.join(qa), n, '/'.join(qb),
            '   - two in parallel each side for 25 A, Q512/Q513 DNP' if n == 1 else ''),
            bx + 116.84, by + 40.64, 1.27)

    # ---------------------------------------------------------------- LTC4417
    bx, by = ox, oy + 175.26
    S.box(bx, by, bx + 193.04, by + 111.76, 'U50 LTC4417: prioritised PowerPath, V1 > V2 > V3')
    nets = {'V1': 'V1', 'V2': 'V2', 'V3': 'V3', 'VS1': 'VS1', 'VS2': 'VS2', 'VS3': 'VS3',
            'G1': 'G1', 'G2': 'G2', 'G3': 'G3', 'VOUT': 'VBUS', 'GND': 'GND', 'EN': 'EN',
            '~{SHDN}': '~{SHDN}', 'HYS': 'HYS', 'UV1': 'UV1', 'OV1': 'OV1', 'UV2': 'UV2', 'OV2': 'OV2',
            'UV3': 'UV3', 'OV3': 'OV3', '~{VALID1}': '~{VALID1}', '~{VALID2}': '~{VALID2}',
            '~{VALID3}': '~{VALID3}'}
    S.place('mega-kvm-power:LTC4417CGN', 'U50', 'LTC4417CGN', bx + 45.72, by + 50.8, nets,
            footprint='Package_SO:SSOP-24_3.9x8.7mm_P0.635mm', nc=('CAS',),
            fields={'LCSC': 'C688500 (low stock: order via JLC global sourcing / parts pre-order; '
                            'SSOP-24, no exposed pad)', 'MPN': 'ADI LTC4417CGN#PBF'})
    P(r('158k'), 'R501', bx + 101.6, by + 25.4, {'1': 'HYS', '2': 'GND'}, dnp=True,
      fields={'Note': 'DNP = internal ~30 mV hysteresis; fit to set 63 mV/RHYS (check datasheet)'})
    P(c('10u', '25V', FP_C1206), 'C504', bx + 111.76, by + 25.4, {'1': 'VBUS', '2': 'GND'})
    P(c('10u', '25V', FP_C1206), 'C505', bx + 119.38, by + 25.4, {'1': 'VBUS', '2': 'GND'})
    S.pwr_flag('VIN_OR', bx + 172.72, by + 17.78)
    S.text('Master on/off: front-panel illuminated rocker (SPST, 12 V lamp between LOAD and GND),\n'
           'wired to J54. Cable unplugged or switch off -> EN low -> VBUS off -> every output off,\n'
           'including the always-on Mimas/switch/fan group. JP2 bridges the switch for bench use.',
           bx + 2.54, by + 76.2, 1.27)
    P(r('47R'), 'R502', bx + 101.6, by + 50.8, {'1': 'VIN_OR', '2': 'SW_SUP'}, fp=FP_R1206,
      fields={'Note': 'limits lamp/short current on the front-panel cable'})
    S.place('Connector_Generic:Conn_01x03', 'J54', 'MASTER SW', bx + 129.54, by + 53.34,
            {'1': 'SW_SUP', '2': 'EN_SW', '3': 'GND'},
            footprint='Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical',
            fields={'Note': '1 SUPPLY (rocker +), 2 LOAD (rocker switched, lamp +), 3 GND (lamp -)',
                    'MPN': 'JST B3B-XH-A', 'LCSC': 'C144395 (verify)'})
    S.place('Jumper:SolderJumper_2_Open', 'JP2', 'SW bypass', bx + 119.38, by + 66.04,
            {'A': 'SW_SUP', 'B': 'EN_SW'}, footprint='Jumper:SolderJumper-2_P1.3mm_Open_RoundedPad1.0x1.5mm')
    P(r('100k'), 'R503', bx + 147.32, by + 50.8, {'1': 'EN_SW', '2': 'EN'})
    P(r('33k'), 'R504', bx + 154.94, by + 50.8, {'1': 'EN', '2': 'GND'},
      fields={'Note': 'EN = 12 V * 33/133 = 3 V on, pulled low when open'})
    P(c('100n'), 'C506', bx + 162.56, by + 50.8, {'1': 'EN', '2': 'GND'})
    P(r('100k'), 'R505', bx + 172.72, by + 50.8, {'1': 'VIN_OR', '2': '~{SHDN}'})
    P(r('33k'), 'R506', bx + 180.34, by + 50.8, {'1': '~{SHDN}', '2': 'GND'})
    P(c('1u', '50V'), 'C507', bx + 187.96, by + 50.8, {'1': 'VIN_OR', '2': 'GND'})

    # ---------------------------------------------------------------- input-selected LEDs
    bx, by = ox, oy + 292.1
    S.box(bx, by, bx + 193.04, by + 81.28, 'Input-selected LEDs (front edge), 3.3 V from the board LDO')
    for k in range(3):
        P(r('100k'), 'R%d' % (507 + k), bx + 50.8 + k * 7.62, by + 15.24,
          {'1': '+3V3', '2': '~{VALID%d}' % (k + 1)})
    P(r('680R'), 'R540', bx + 81.28, by + 15.24, {'1': '+3V3', '2': 'LA1'})
    P(LED_G, 'D507', bx + 81.28, by + 27.94, {'A': 'LA1', 'K': '~{VALID1}'}, value='green', rot=90,
      fields={'Note': 'IN1 banana selected'})
    P(r('680R'), 'R541', bx + 106.68, by + 15.24, {'1': '+3V3', '2': 'LA2'})
    P(LED_G, 'D508', bx + 106.68, by + 27.94, {'A': 'LA2', 'K': 'LK2'}, value='green', rot=90,
      fields={'Note': 'IN2 PCIe selected'})
    P(NFET, 'Q509', bx + 104.14, by + 43.18, {'D': 'LK2', 'S': '~{VALID2}', 'G': '~{VALID1}'})
    P(r('680R'), 'R542', bx + 139.7, by + 15.24, {'1': '+3V3', '2': 'LA3'})
    P(LED_G, 'D509', bx + 139.7, by + 27.94, {'A': 'LA3', 'K': 'LK3'}, value='green', rot=90,
      fields={'Note': 'IN3 Molex selected'})
    P(NFET, 'Q510', bx + 137.16, by + 43.18, {'D': 'LK3', 'S': 'LK3B', 'G': '~{VALID1}'})
    P(NFET, 'Q511', bx + 137.16, by + 58.42, {'D': 'LK3B', 'S': '~{VALID3}', 'G': '~{VALID2}'})
    S.text('~VALIDn are open drain (low = input n valid). LED2 = V2 & !V1, LED3 = V3 & !V1 & !V2.\n'
           'LEDs are dark when VBUS is off (master switch off).', bx + 2.54, by + 71.12, 1.27)
