"""Part definitions for the front-panel board: lib_id, footprint, LCSC.

LCSC numbers checked against the JLCPCB parts search on 2026-11-27
('basic' = JLC basic part, no extended-part fee). Re-check stock when ordering.
No part has an exposed pad; the THT parts (LEDs, switches, headers) are
JLC THT assembly (or hand-fitted: all on 2.54 mm / large pads).
"""

FP_R = 'Resistor_SMD:R_0603_1608Metric'
FP_C = 'Capacitor_SMD:C_0603_1608Metric'

LCSC_R = {'10k': 'C25804', '470': 'C23179', '200k': 'C25811', '4k7': 'C23162'}  # all basic
LCSC_C = {'100n': 'C14663', '10u': 'C19702'}                                     # basic


def r(value):
    return dict(lib='Device:R', fp=FP_R, value=value,
                fields={'LCSC': LCSC_R[value], 'Tolerance': '1%', 'JLC': 'basic'})


def c(value, volt):
    return dict(lib='Device:C', fp=FP_C, value=value,
                fields={'LCSC': LCSC_C[value], 'Voltage': volt, 'JLC': 'basic'})


RN10K = dict(lib='Device:R_Pack04', fp='Resistor_SMD:R_Array_Convex_4x0603', value='4x10k',
             fields={'LCSC': 'C29718', 'MPN': 'UNI-ROYAL 4D03WGJ0103T5E', 'JLC': 'basic'})
TCA9535 = dict(lib='Interface_Expansion:TCA9535PWR', fp='Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm',
               value='TCA9535PWR', fields={'LCSC': 'C130204', 'MPN': 'TI TCA9535PWR', 'JLC': 'extended'})
PCA9306 = dict(lib='Interface:PCA9306DC', fp='Package_SO:VSSOP-8_2.3x2mm_P0.5mm',
               value='PCA9306DCUR', fields={'LCSC': 'C33196', 'MPN': 'TI PCA9306DCUR', 'JLC': 'extended'})
LED_RED = dict(lib='Device:LED', fp='LED_THT:LED_D3.0mm', value='red 3mm',
               fields={'LCSC': 'C84774', 'MPN': 'Everlight 204-10SDRD/S530-A3-L (3 mm red diffused, 2.0 V)',
                       'JLC': 'extended (THT)'})
LED_GRN = dict(lib='Device:LED', fp='LED_THT:LED_D3.0mm', value='green 3mm',
               fields={'LCSC': 'C85161', 'MPN': 'Everlight 204-10SYGD/S530-E3 (3 mm yellow-green diffused, 2.0 V)',
                       'JLC': 'extended (THT)'})
SW_TACT = dict(lib='Switch:SW_Push', fp='Button_Switch_THT:SW_PUSH_6mm_H9.5mm', value='6x6 H9.5',
               fields={'LCSC': 'C136679', 'MPN': 'HRO K2-1102DP-L4SW-04 (6x6 mm THT, 9.5 mm, round stem)',
                       'JLC': 'extended (THT)'})
HDR = {
    3: ('Connector_PinHeader_2.54mm:PinHeader_1x03_P2.54mm_Vertical', 'C49257'),
    4: ('Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical', 'C124378'),
    6: ('Connector_PinHeader_2.54mm:PinHeader_1x06_P2.54mm_Vertical', 'C37208'),
    10: ('Connector_PinHeader_2.54mm:PinHeader_1x10_P2.54mm_Vertical', 'C57369'),
}
HOLE_M25 = dict(lib='Mechanical:MountingHole', fp='MountingHole:MountingHole_2.7mm_M2.5', value='M2.5')
HOLE_M3 = dict(lib='Mechanical:MountingHole', fp='MountingHole:MountingHole_3.2mm_M3', value='M3')
