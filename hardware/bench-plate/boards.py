"""Board footprints for the bench plate (issue 0058).

Every board is described in *plan-local* coordinates, already rotated so
its Ethernet jack faces the front of the plate:

  u = mm to the right of the board footprint's left edge (plate X),
  d = mm behind the board's front PCB edge (towards the rear).

So d < 0 means "in front of the PCB edge" (a jack that overhangs it).
Numbers marked ASSUMED are estimates: measure the real board before
cutting (they are all in this file, nothing else needs changing).
See README.md for the sources.
"""
from dataclasses import dataclass, field


@dataclass
class Board:
    key: str
    name: str                 # engraved label (upper case, single-stroke font)
    w: float                  # footprint width along plate X (mm)
    d: float                  # footprint depth along plate Y (mm)
    holes: list               # [(u, d)] mounting hole centres
    hole_d: float = 3.2       # cut diameter on the base plate
    jack: tuple = None        # RJ45 body (u0, d0, u1, d1); d0 = jack front
    notes: list = field(default_factory=list)   # [(text, u, d)] small engraved hints

    @property
    def jack_front(self):
        """d of the jack front (<= 0 when it overhangs the PCB edge)."""
        return self.jack[1] if self.jack else 0.0


# --- Numato Mimas A7 (pre-V4, V3.0), 120 x 90 mm ---------------------------
# Mimas coordinates (docs/hardware/shield.md, hardware/mega-kvm-shield/
# scripts/geometry.py, checked against the vendor STEP): origin at the
# corner between the RJ45 edge and the P13 edge, mx towards the HDMI edge,
# my towards P12, seen from above (KiCad y = Y0 - my). Rotated 90 deg CCW
# so the RJ45 edge (mx = 0) is at the front: u = 90 - my, d = mx.
# P12 is then on the left, P13 on the right.
def _mimas(key, name):
    return Board(
        key=key, name=name, w=90.0, d=120.0,
        holes=[(90 - my, mx) for (mx, my) in
               [(5.0, 85.0), (115.0, 85.0), (5.0, 5.0), (115.0, 5.0)]],
        # magjack body my 60.7-76.7, mx -0.5..21.8 (0.5 mm proud of the edge)
        jack=(90 - 76.7, -0.5, 90 - 60.7, 21.8),
        notes=[('P12', 7.0, 60.0), ('P13', 83.0, 60.0), ('HDMI', 45.0, 114.0)])


MIMAS1 = _mimas('mimas1', 'MIMAS A7 #1')
MIMAS2 = _mimas('mimas2', 'MIMAS A7 #2')

# --- QMTECH daughter board (DB_FPGA, carries the XC7K325T core board) ------
# Size 108.71 x 134.62 mm: QMTECH XC7A100T Starter Kit daughter-board user
# manual V01, section 1.2 (github.com/ChinaQMTECH/QM_XC7A100T_STARTER_KIT and
# github.com/ChinaQMTECH/DB_FPGA/Example_Setups). The RJ45, VGA and microSD
# are on one 108.71 mm edge; 7-seg + mini-USB UART on the 134.62 mm edge
# next to it. QMTECH publish no mechanical drawing: hole and RJ45 positions
# are ASSUMED, scaled from the manual's top-view photo (Figure 1-1,
# +-1.5 mm). Photo frame: a = from the RJ45 edge (0..134.62), b = from the
# 7-seg edge (0..108.71); rotated so the RJ45 edge is at the front and the
# 7-seg edge on the left: u = b, d = a.
_DB_HOLES_AB = [(30.5, 4.0), (30.5, 104.7), (130.8, 4.0), (130.8, 104.7)]   # ASSUMED
K325T = Board(
    key='k325t', name='QMTECH K325T + DB', w=108.71, d=134.62,
    holes=[(b, a) for (a, b) in _DB_HOLES_AB],
    jack=(40.0, -4.0, 56.0, 17.0),     # ASSUMED: centre 48 from the 7-seg edge, ~4 mm proud
    notes=[('VGA', 86.0, 8.0), ('7SEG', 12.0, 104.0), ('UART', 16.0, 124.0)])

# --- Arduino Yun (Rev 2), 73 x 53 mm -------------------------------------
# 73 x 53 mm overall: Arduino store / docs (store-usa.arduino.cc/products/
# arduino-yun-rev-2). The Yun keeps the Uno/Leonardo shield layout on a
# 68.58 x 53.34 mm PCB, so the RJ45 is taken to stand 73 - 68.58 = 4.4 mm
# proud of the USB edge (ASSUMED). Holes: Uno R3 pattern (Arduino Uno R3
# drawing, x from the USB edge, y from the edge opposite the digital header)
# -- ASSUMED for the Yun, no official Yun drawing found. RJ45 ASSUMED where the
# Uno's USB-B sits (upper half of the USB edge, centre y = 38).
# Rotated so the USB/RJ45 edge is at the front: u = 53.34 - y, d = x.
_UNO_HOLES = [(13.97, 2.54), (15.24, 50.8), (66.04, 7.62), (66.04, 35.56)]
YUN = Board(
    key='yun', name='ARDUINO YUN', w=53.34, d=68.58,
    holes=[(53.34 - y, x) for (x, y) in _UNO_HOLES],
    jack=(53.34 - 46.0, -4.4, 53.34 - 30.0, 17.0),   # ASSUMED
    notes=[('USB', 40.0, 8.0)])

# --- Jaycar XC4418 8-channel relay module, 135 x 50 mm ----------------------
# 135 (L) x 50 (W) x 19 (H) mm: Jaycar XC4418 datasheet
# (media.jaycar.com.au/product/resources/XC4418_datasheetMain_67843.pdf).
# Holes ASSUMED: 4 x 3 mm, 3 mm in from each corner (usual for these
# modules; not in the datasheet). Two orientations: long side along Y
# (main layout, least X) or along X (alternative layout, rear row).
_RELAY_L, _RELAY_W, _RELAY_IN = 135.0, 50.0, 3.0


def relay(long_along_x=False):
    w, d = (_RELAY_L, _RELAY_W) if long_along_x else (_RELAY_W, _RELAY_L)
    i = _RELAY_IN
    return Board(key='relay', name='XC4418 RELAYS', w=w, d=d,
                 holes=[(i, i), (w - i, i), (i, d - i), (w - i, d - i)])
