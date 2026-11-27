"""5 V DUT outputs of the power board (issue 0055, owner request 2026-11-27).

Source: +5 V from the Molex 8981 input J53 pin 4 (until now unused), through
its own 10 A ATO fuse F4 and a unidirectional TVS (SMBJ5.0A), independent of
the LTC4417 12 V selector.  A reversed supply forward-biases the TVS and blows
F4; the eFuses themselves block down to -15 V meanwhile (TPS25947 7.3.1).
No 5 V on the banana or PCIe inputs and no 12 V -> 5 V converter (owner).

Three outputs, one per shared channel 5/6/7: TPS259470L (latch-off, the same
part as the 12 V DUT eFuses) with ILIM 3.0 A, OVLO 5.9 V (shared divider,
392 k / 100 k: >= 350 k on the supply side per TPS25947 note 4 for reverse
polarity), the same dV/dt and ITIMER as the 12 V cells.

Channel selector JP5-JP7 (3-pin 2.54 mm header + shunt): CTRLn -> 1 k -> CSELn
(pin 2).  Shunt 1-2 = the 12 V output DUTn (EN n), shunt 2-3 = the 5 V output
(EN5Vn).  Each EN has its own 20 k pull-down, so the unselected one is off and
with no shunt both are off.  /FLT of the 5 V eFuse is wire-ORed onto /FLTn:
only the selected one can be on, so /FLTn is "channel n faulted" either way.
"""
from parts import (EFUSE_L, FP_C1206, LED_G, SS34, TVS5, c, r)

CHANNELS = (5, 6, 7)
RILM5 = '1k1'     # ILIM = 3334 / 1100 = 3.03 A (TPS25947 eq. 5)
CDVDT = '2n2'     # ~0.8 V/ms at 5 V: 0 -> 5 V in ~6 ms, 0.4 A into 470 uF
CITIMER = '4n7'   # ~4 ms overcurrent blanking, as the 12 V cells
FUSE_FP = 'Fuse:FuseHolder_Blade_ATO_Littelfuse_FLR_178.6165'
FP_VH2 = 'Connector_JST:JST_VH_B2P-VH_1x02_P3.96mm_Vertical'


def cell_refs(n):
    """References of the 5 V cell for channel n (5..7)."""
    base = 610 + 10 * (n - 5)
    return base, 'U%d' % (61 + n - 5), 'J%d' % (61 + n - 5), 'JP%d' % n


def build(S, P, ox, oy):
    # ------------------------------------------------------------ input: J53 pin 4 -> F4 -> +5V
    bx, by = ox, oy
    S.box(bx, by, bx + 188.98, by + 58.42,
          '+5 V input: Molex J53 pin 4 -> F4 10 A -> TVS -> +5V (not via the LTC4417; issue 0055)')
    S.text('J53 pin 4 (+5V_RAW) is placed in the input stage (Input V3: Molex 4-pin).', bx + 2.54, by + 7.62, 1.27)
    S.place('Device:Fuse', 'F4', '10A ATO', bx + 20.32, by + 20.32, {'1': '+5V_RAW', '2': '+5V'},
            footprint=FUSE_FP,
            fields={'MPN': 'Littelfuse 178.6165.0002 ATO PCB holder + ATO blade fuse 10 A (same as F3)',
                    'LCSC': 'TBD', 'Assembly': 'THT',
                    'Note': '3 x 3 A eFuse limits = 9 A < 10 A; Molex contact ~11 A; 18 AWG PSU lead'})
    S.pwr_flag('+5V', bx + 30.48, by + 12.7)
    P(TVS5, 'D600', bx + 35.56, by + 20.32, {'K': '+5V', 'A': 'GND'}, rot=90,
      fields={'Note': 'reverse polarity: forward-biased, blows F4; 12 V on pin 4: clamps and blows F4'})
    P(c('10u', '25V', FP_C1206), 'C600', bx + 45.72, by + 20.32, {'1': '+5V', '2': 'GND'})
    P(c('10u', '25V', FP_C1206), 'C601', bx + 53.34, by + 20.32, {'1': '+5V', '2': 'GND'},
      fields={'Note': 'at the 5 V eFuse row'})
    # 5 V present: LED by the fuse, divider to the optional TCA9535 (P1.1)
    P(r('1k'), 'R603', bx + 66.04, by + 15.24, {'1': '+5V', '2': 'LED5V'})
    P(LED_G, 'D601', bx + 66.04, by + 30.48, {'A': 'LED5V', 'K': 'GND'}, rot=90,
      fields={'Note': '"5V" present (Molex +5 V after F4); dark = no 5 V (banana/PCIe only, or F4 blown)'})
    P(r('10k'), 'R601', bx + 78.74, by + 15.24, {'1': '+5V', '2': '5V_PRESENT'})
    P(r('20k'), 'R602', bx + 78.74, by + 30.48, {'1': '5V_PRESENT', '2': 'GND'},
      fields={'Note': '3.3 V at 5 V; logic high above ~3.5 V on +5V; to TCA9535 U11 P1.1 (optional)'})
    # shared OVLO for the three 5 V eFuses: 1.20 V * (392k + 100k) / 100k = 5.90 V rising, 5.36 V falling
    P(r('392k'), 'R604', bx + 99.06, by + 15.24, {'1': '+5V', '2': 'OVLO5'},
      fields={'Note': 'OVLO 5.90 V rising / 5.36 V falling; >= 350k from the supply (reverse polarity)'})
    P(r('100k'), 'R605', bx + 99.06, by + 30.48, {'1': 'OVLO5', '2': 'GND'})
    P(c('100n'), 'C602', bx + 109.22, by + 30.48, {'1': 'OVLO5', '2': 'GND'})
    S.text('Banana/PCIe-only operation: no 5 V, the 5 V eFuses are unpowered (FLT open = no fault),\n'
           'D601 is dark and 5V_PRESENT reads low (U11 P1.1, if fitted).\n'
           'Master switch off: the shield is unpowered, CTRL5-7 are pulled low, every output is off.',
           bx + 2.54, by + 45.72, 1.27)

    # ------------------------------------------------------------ three cells
    for k, n in enumerate(CHANNELS):
        base, u, j, jp = cell_refs(n)
        cx, cy = ox + k * 96.52, oy + 63.5
        S.box(cx, cy, cx + 92, cy + 76.2, '%s: DUT%d 5 V ONLY, 3 A (shares CTRL%d with the 12 V output)' % (u, n, n))
        out, en = 'OUT5V%d' % n, 'EN5V%d' % n
        # selector
        S.place('Connector_Generic:Conn_01x03', jp, 'CH%d 12V|5V' % n, cx + 12.7, cy + 15.24,
                {'1': 'EN%d' % n, '2': 'CSEL%d' % n, '3': en},
                footprint='Connector_PinHeader_2.54mm:PinHeader_1x03_P2.54mm_Vertical',
                fields={'MPN': '2.54 mm 1x3 pin header + 2.54 mm shunt (jumper cap)',
                        'LCSC': 'C2932698 (1x3 2.54 mm header); shunt C100114 fitted at box assembly',
                        'Note': 'shunt 1-2 = DUT%d 12 V, 2-3 = DUT%d 5 V, none = both off' % (n, n)})
        ux, uy = cx + 45.72, cy + 22.86
        P(EFUSE_L, u, ux, uy, {'IN': '+5V', 'EN/UVLO': en, 'OVLO': 'OVLO5', 'DVDT': 'DVDT5V%d' % n,
                               'ITIMER': 'ITMR5V%d' % n, 'OUT': out, '~{FLT}': '~{FLT%d}' % n,
                               'ILM': 'ILM5V%d' % n, 'GND': 'GND'}, nc=('AUXOFF',),
          fields={'Note': '/FLT wire-ORed with the 12 V eFuse of channel %d (pull-up in that cell)' % n})
        y = cy + 50.8
        x = cx + 7.62
        step = 7.62
        P(r('20k'), 'R%d' % (base + 1), x, y, {'1': en, '2': 'GND'},
          fields={'Note': 'EN pull-down: off when not selected, no shunt, or shield off'})
        P(r(RILM5), 'R%d' % (base + 2), x + step, y, {'1': 'ILM5V%d' % n, '2': 'GND'},
          fields={'Note': 'ILIM 3.03 A (3334/R)'})
        P(c(CDVDT, '50V'), 'C%d' % (base + 0), x + 2 * step, y, {'1': 'DVDT5V%d' % n, '2': 'GND'})
        P(c(CITIMER, '50V'), 'C%d' % (base + 1), x + 3 * step, y, {'1': 'ITMR5V%d' % n, '2': 'GND'})
        P(c('1u', '50V', FP_C1206), 'C%d' % (base + 2), x + 4 * step, y, {'1': '+5V', '2': 'GND'})
        P(c('1u', '50V', FP_C1206), 'C%d' % (base + 3), x + 5 * step, y, {'1': out, '2': 'GND'})
        P(r('1k'), 'R%d' % (base + 4), x + 6 * step, y, {'1': out, '2': 'LED5V%d' % n},
          fields={'Note': '3 mA: output-on LED and bleeder'})
        P(LED_G, 'D%d' % (base + 1), x + 7 * step + 2.54, y + 7.62, {'A': 'LED5V%d' % n, 'K': 'GND'}, rot=90)
        P(SS34, 'D%d' % (base + 0), cx + 66.04, cy + 15.24, {'K': out, 'A': 'GND'}, rot=90,
          fields={'Note': 'negative-spike clamp on OUT (TI 8.3 layout)'})
        S.place('Connector_Generic:Conn_01x02', j, 'DUT%d 5V ONLY' % n, cx + 81.28, cy + 22.86,
                {'1': out, '2': 'GND'}, footprint=FP_VH2,
                fields={'MPN': 'JST B2P-VH(LF)(SN) 2-pin 3.96 mm vertical, 10 A, friction lock, polarised; '
                               'mates VHR-2N + SVH-21T-P1.1; pin 1 = +5 V, pin 2 = GND',
                        'LCSC': 'C160315', 'Assembly': 'THT',
                        'Note': 'deliberately not a screw terminal or Mini-Fit: a 5 V lead cannot land on a 12 V output'})
