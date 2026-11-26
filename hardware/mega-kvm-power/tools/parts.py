"""Shared part definitions: lib_id, footprint and sourcing fields.

LCSC numbers marked in BOM_NOTES were looked up on 2026-11-27 or are the
usual JLCPCB basic parts; re-check stock when ordering.
"""

FP_R = 'Resistor_SMD:R_0603_1608Metric'
FP_R1206 = 'Resistor_SMD:R_1206_3216Metric'
FP_C = 'Capacitor_SMD:C_0603_1608Metric'
FP_C1206 = 'Capacitor_SMD:C_1206_3216Metric'
FP_LED = 'LED_SMD:LED_0603_1608Metric'

# value -> LCSC (JLC basic unless noted)
LCSC_R = {'10k': 'C25804', '100k': 'C25803', '4k7': 'C23162', '1k': 'C21190', '20k': 'C4184'}
LCSC_C = {'100n': 'C14663'}


def r(value, tol='1%'):
    return dict(lib='Device:R', fp=FP_R, value=value,
                fields={'LCSC': LCSC_R.get(value, 'TBD (%s, JLC basic if stocked)' % tol), 'Tolerance': tol})


def c(value, volt='25V', fp=FP_C):
    return dict(lib='Device:C', fp=fp, value=value,
                fields={'LCSC': LCSC_C.get(value, 'TBD (X7R %s)' % volt), 'Voltage': volt})


EFUSE_L = dict(lib='mega-kvm-power:TPS259470', fp='mega-kvm-power:Texas_RPW0010A_VQFN-HR-10_2x2mm_P0.45mm',
               value='TPS259470LRPWR', fields={'LCSC': 'C3662793', 'MPN': 'TI TPS259470LRPWR'})
EFUSE_A = dict(lib='mega-kvm-power:TPS259470', fp='mega-kvm-power:Texas_RPW0010A_VQFN-HR-10_2x2mm_P0.45mm',
               value='TPS259470ARPWR', fields={'LCSC': 'TBD (C3662793 is the L variant)', 'MPN': 'TI TPS259470ARPWR'})
LED_G = dict(lib='Device:LED', fp=FP_LED, value='green', fields={'LCSC': 'TBD (0603 green, JLC basic)'})
LED_R = dict(lib='Device:LED', fp=FP_LED, value='red', fields={'LCSC': 'TBD (0603 red, JLC basic)'})
SS34 = dict(lib='Device:D_Schottky', fp='Diode_SMD:D_SMA', value='SS34',
            fields={'LCSC': 'C8678', 'MPN': 'SS34 40 V 3 A SMA'})
B5819W = dict(lib='Device:D_Schottky', fp='Diode_SMD:D_SOD-123', value='B5819W',
              fields={'LCSC': 'C8598', 'MPN': 'B5819W 40 V 1 A SOD-123'})
LDO = dict(lib='Regulator_Linear:L78L33_SOT89', fp='Package_TO_SOT_SMD:SOT-89-3', value='L78L33ACUTR',
           fields={'LCSC': 'TBD (78L33 SOT-89, 30 V in)', 'MPN': 'ST L78L33ACUTR'})
TVS = dict(lib='mega-kvm-power:TVS_Uni', fp='Diode_SMD:D_SMC', value='SMCJ15A',
           fields={'LCSC': 'C2834490', 'MPN': 'MDD SMCJ15A 1500 W, Vrwm 15 V, Vc 24.4 V'})
PFET = dict(lib='mega-kvm-power:PMOS_TDSON8', fp='Package_SON:Infineon_PG-TDSON-8_6.15x5.15mm',
            value='BSC030P03NS3G', fields={'LCSC': 'C152375', 'MPN': 'Infineon BSC030P03NS3G -30 V 3 mOhm'})
NFET = dict(lib='Transistor_FET:2N7002', fp='Package_TO_SOT_SMD:SOT-23', value='2N7002',
            fields={'LCSC': 'C8545'})
LUG_M4 = dict(lib='Connector_Generic:Conn_01x01', fp='MountingHole:MountingHole_4.3mm_M4_Pad_Via',
              value='M4 lug', fields={'LCSC': 'n/a (ring terminal + M4 screw/nut)', 'Assembly': 'hand'})
HOLE_M3 = dict(lib='Mechanical:MountingHole', fp='MountingHole:MountingHole_3.2mm_M3', value='M3')
