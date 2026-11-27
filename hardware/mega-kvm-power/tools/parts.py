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
LCSC_R = {'0R': 'C21189', '100R': 'C22775', '10k': 'C25804', '100k': 'C25803', '4k7': 'C23162', '1k': 'C21190', '20k': 'C4184'}
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
BAT54WS = dict(lib='Device:D_Schottky', fp='Diode_SMD:D_SOD-323', value='BAT54WS',
               fields={'LCSC': 'C124205', 'MPN': 'Diodes BAT54WS-7-F 30 V 0.2 A Schottky SOD-323'})
LDO = dict(lib='Regulator_Linear:L78L33_SOT89', fp='Package_TO_SOT_SMD:SOT-89-3', value='L78L33ACUTR',
           fields={'LCSC': 'TBD (78L33 SOT-89, 30 V in)', 'MPN': 'ST L78L33ACUTR'})
TVS = dict(lib='mega-kvm-power:TVS_Uni', fp='Diode_SMD:D_SMC', value='SMCJ15A',
           fields={'LCSC': 'C2834490', 'MPN': 'MDD SMCJ15A 1500 W, Vrwm 15 V, Vc 24.4 V'})
TVS5 = dict(lib='mega-kvm-power:TVS_Uni', fp='Diode_SMD:D_SMB', value='SMBJ5.0A',
            fields={'LCSC': 'C2758500', 'MPN': 'SMBJ5.0A 600 W, Vrwm 5.0 V, Vbr 6.4 V min, Vc 9.2 V (issue 0055)'})
PFET = dict(lib='mega-kvm-power:PMOS_TDSON8', fp='Package_SON:Infineon_PG-TDSON-8_6.15x5.15mm',
            value='BSC030P03NS3G', fields={'LCSC': 'C152375', 'MPN': 'Infineon BSC030P03NS3G -30 V 3 mOhm'})
NFET = dict(lib='Transistor_FET:2N7002', fp='Package_TO_SOT_SMD:SOT-23', value='2N7002',
            fields={'LCSC': 'C8545'})
LUG_M4 = dict(lib='Connector_Generic:Conn_01x01', fp='MountingHole:MountingHole_4.3mm_M4_Pad_Via',
              value='M4 lug', fields={'LCSC': 'n/a (ring terminal + M4 screw/nut)', 'Assembly': 'hand'})
HOLE_M3 = dict(lib='Mechanical:MountingHole', fp='MountingHole:MountingHole_3.2mm_M3', value='M3')

# ---- fans, I2C housekeeping and temperature (issue 0052). LCSC numbers, stock
# and prices looked up 2026-11-27 (jlcsearch / LCSC); all leaded, no exposed pad.
FAN_SW = dict(lib='mega-kvm-power:BSP452', fp='Package_TO_SOT_SMD:SOT-223', value='BSP452',
              fields={'LCSC': 'C58074', 'MPN': 'Infineon BSP452 smart high-side switch, 160 mOhm, '
                                                 'current limit 0.7-2.4 A, thermal auto-restart, SOT-223'})
FAN_CTRL = dict(lib='Driver_Motor:EMC2302-x-AIZL', fp='mega-kvm-power:MSOP-10_3x3mm_P0.5mm_Pad0.28',
                value='EMC2302-1-AIZL-TR',
                fields={'LCSC': 'C626969', 'MPN': 'Microchip EMC2302-1-AIZL-TR, 2-ch 26 kHz PWM fan controller, '
                                                  'SMBus 0x2E, MSOP-10 (no pad)'})
I2C_MUX = dict(lib='Interface_Expansion:TCA9548APWR', fp='Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm',
               value='TCA9548APWR', fields={'LCSC': 'C130026', 'MPN': 'TI TCA9548APWR 8-ch I2C switch, TSSOP-24'})
TSENS = dict(lib='Sensor_Temperature:LM75B', fp='Package_SO:SOIC-8_3.9x4.9mm_P1.27mm', value='TMP75AIDR',
             fields={'LCSC': 'C30389', 'MPN': 'TI TMP75AIDR (LM75 pinout, 0x48-0x4F), SOIC-8'})
FAN_HDR = dict(lib='Connector_Generic:Conn_01x04', fp='Connector:FanPinHeader_1x04_P2.54mm_Vertical',
               value='FAN', fields={'LCSC': 'C240840', 'MPN': 'Molex 47053-1000 4-pin PWM fan header'})
XH5 = dict(lib='Connector_Generic:Conn_01x05', fp='Connector_JST:JST_XH_B5B-XH-A_1x05_P2.50mm_Vertical',
           value='XH-5', fields={'LCSC': 'C157991', 'MPN': 'JST B5B-XH-A(LF)(SN)'})
