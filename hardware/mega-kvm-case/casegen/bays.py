"""DUT bays: one per Mimas. A bay is the panel fragment with that Mimas's
DUT connectors plus the 3D geometry behind it (for the base/plate holes and
the fit check).

Bay-local coordinates: a = Mimas y (across the panel, towards P12 = right as
seen from outside), e = distance inwards from the panel's inner face,
z = height above the bay floor (the surface the Mimas standoffs stand on).

Variants:
  shield190  primary: rev B shield, 120 x 189.6 mm (owner rounds 5-7), JB1
             on the shield beside the Mimas, J5 on keyboard sub-boards below,
             three header HDMIs above the Mimas's own HDMI OUT/IN.
             Numbers from hardware/mega-kvm-shield (placement.json, geometry.py).
  vboard     alternate: vertical DUT connector board per Mimas (HDMI / JB1 / J5 rows).
  wide       alternate: rev A single-row shield, 279.6 mm.
  narrow     alternate: ~150 mm shield, one combined 2x8 per DUT.
"""
import json
import os
import runpy

from . import fragments as fr
from .geom import Circle

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Bay:
    def __init__(self, item, my_min, setback, boxes, holes, info):
        self.item, self.my_min, self.setback = item, my_min, setback
        self.boxes = boxes      # (name, a0, a1, e0, e1, z0, z1, kind, hard)
        self.holes = holes      # (a, e, r, what) for the floor / plate
        self.info = info        # dict of numbers for the report

    @property
    def width(self):
        return self.item.width


def shield_geometry(cfg):
    S = cfg.SHIELD190
    g = {}
    path = os.path.join(HERE, S['geometry_py'])
    if os.path.exists(path):
        g = runpy.run_path(path)
    slots = {}
    jp = os.path.join(HERE, S['placement_json'])
    if os.path.exists(jp):
        slots = json.load(open(jp))['rear_slots']
    elif 'SLOTS' in g:
        slots = {k: list(v) for k, v in g['SLOTS'].items()}
    geo = {
        'slots': slots,
        'y_bot': g.get('Y_BOT', S['y_bot']), 'y_top': g.get('Y_TOP', S['y_top']),
        'z_mimas_top': g.get('Z_MIMAS_TOP', S['z_mimas_top']),
        'z_shield_bot': g.get('Z_SHIELD_BOT', S['z_shield_bot']),
        'z_shield_top': g.get('Z_SHIELD_TOP', S['z_shield_top']),
        'standoff': g.get('STANDOFF', cfg.MIMAS['standoff']),
        'kbd': (g.get('KBD_X0', 86.0), g.get('KBD_X1', 120.0), g.get('KBD_Y0', 90.8), g.get('KBD_Y1', 138.6)),
        'kbd_dy': g.get('KBD_DY', -139.4),
        'kbd_holes': g.get('KBD_HOLES', [(89.0, 94.3), (89.0, 135.1), (100.0, 114.7)]),
        'src': 'geometry.py + placement.json' if g and slots else 'config fallback',
    }
    # shield support holes from the shield board (KiCad x = 30 + mx, y = 200 - my)
    from . import kicad
    sb = kicad.load(os.path.join(HERE, S['pcb']))
    sup = []
    if sb:
        for ref, f in sb['fp'].items():
            if ref.startswith('H'):
                mx, my = f['x'] + sb['ox'] - 30.0, 200.0 - (f['y'] + sb['oy'])
                if not (0 <= my <= 90):
                    sup.append((round(mx, 2), round(my, 2)))
    geo['support'] = sorted(sup) or S['support_holes']
    return geo


def shield190_bay(cfg, bay, z0=0.0, ztop=None):
    geo = shield_geometry(cfg)
    S = cfg.SHIELD190
    M = cfg.MIMAS
    my0, my1 = geo['y_bot'], geo['y_top']
    W = my1 - my0
    n0 = bay * cfg.DUTS_PER_BAY + 1
    zt, zm = geo['z_shield_top'], geo['z_mimas_top']
    z_jb1 = zt + S['jb1_cz']
    z_hdmi = zt + S['hdmi_cz']
    z_j5 = zm + S['j5_cz'] - S['kbd_drop']
    z_mh = zm + M['hdmi_cz']
    j6, j5, hd = cfg.CONN['2x6'], cfg.CONN['2x5'], cfg.CONN['HDMI']
    pin1 = cfg.VBOARD['pin1']

    def draw(p, u0, V):
        Vb = lambda z: V(z + z0)
        U = lambda my: u0 + (my - my0)
        for ref, (a, b) in sorted(geo['slots'].items()):
            kind = ref.rstrip('J0123456789')
            k = int(ref[len(kind)])
            n = n0 + k
            u = U((a + b) / 2)
            if kind == 'JTAG':
                fr.rect_hole(p, u, Vb(z_jb1), j6, j6[2])
                fr.pin1_mark(p, u - j6[0] / 2, u + j6[0] / 2, Vb(z_jb1), j6[1], pin1)
                fr.label(p, '%d JTAG' % n, u, Vb(z_jb1 + j6[1] / 2 + 1.7), 1.8)
                fr.rect_hole(p, u, Vb(z_j5), j5, j5[2])     # J5 on the sub-board, directly below
                fr.pin1_mark(p, u - j5[0] / 2, u + j5[0] / 2, Vb(z_j5), j5[1], pin1)
                fr.label(p, '%d KBD' % n, u, Vb((z_j5 + j5[1] / 2 + z_jb1 - j6[1] / 2) / 2), 1.4)
            elif kind == 'HDMI':
                fr.rect_hole(p, u, Vb(z_hdmi), hd, hd[2])
                fr.label(p, '%d HDMI' % n, u, Vb(z_jb1 + j6[1] / 2 + 1.7), 1.8)
        for txt, my in (('OUT', M['hdmi_out_my']), ('%d HDMI' % n0, M['hdmi_in_my'])):
            fr.rect_hole(p, U(my), Vb(z_mh), hd, hd[2])
            fr.label(p, txt, U(my), Vb(z_mh + hd[1] / 2 + 1.5), 1.4)
        if z_lab + 1.0 + z0 <= (ztop if ztop is not None else 1e9) - 0.8:
            fr.label(p, 'BAY %d   DUT %d-%d' % (bay + 1, n0, n0 + 3), U(45.0), Vb(z_lab), 2.0)
    z_lab = z_jb1 + j6[1] / 2 + 6.2
    top = z_jb1 + j6[1] / 2 + 3.0
    item = fr.Item('bay%d' % (bay + 1), W, draw, 0.0, (z0, z0 + top),
                   title='bay %d (DUT %d-%d), 189.6 mm shield' % (bay + 1, n0, n0 + 3))
    sb = S['mimas_to_panel']
    stack_top = zt + cfg.SHIELD['tallest']
    kx0, kx1, ky0, ky1 = geo['kbd']
    boxes = [
        ('Mimas %d' % (bay + 1), 0.0, M['w'], sb, sb + M['d'], 0.0, geo['z_shield_bot'], 'mimas', True),
        ('shield %d' % (bay + 1), my0, my1, sb, sb + M['d'], geo['z_shield_bot'], stack_top, 'shield', True),
        ('kbd sub %dA' % (bay + 1), ky0, ky1, sb + (M['d'] - kx1), sb + (M['d'] - kx0), 0.0, zm - S['kbd_drop'] + 8.9, 'kbd', True),
        ('kbd sub %dB' % (bay + 1), ky0 + geo['kbd_dy'], ky1 + geo['kbd_dy'], sb + (M['d'] - kx1), sb + (M['d'] - kx0),
         0.0, zm - S['kbd_drop'] + 8.9, 'kbd', True),
        ('RJ45 patch %d' % (bay + 1), M['rj45_my'][0], M['rj45_my'][1], sb + M['d'], sb + M['d'] + M['rj45_plug_clear'],
         0.0, 20.0, 'cable', False),
    ]
    holes = [(my, sb + (M['d'] - mx), M['hole_d'] / 2, 'Mimas') for (mx, my) in M['holes']]
    holes += [(my, sb + (M['d'] - mx), 1.7, 'kbd sub') for (mx, my) in geo['kbd_holes']]
    holes += [(my + geo['kbd_dy'], sb + (M['d'] - mx), 1.7, 'kbd sub') for (mx, my) in geo['kbd_holes']]
    holes += [(my, sb + (M['d'] - mx), 1.7, 'shield support') for (mx, my) in geo['support']]
    info = {'width': W, 'top': z_jb1 + j6[1] / 2, 'stack_top': stack_top, 'z': {'JB1': z_jb1, 'HDMI(shield)': z_hdmi, 'J5': z_j5,
                                                                    'HDMI(Mimas)': z_mh}, 'src': geo['src']}
    return Bay(item, my0, sb, boxes, holes, info)


def vboard_bay(cfg, bay, z0=0.0):
    """Alternate: vertical DUT connector board, rows HDMI / JB1 2x6 / J5 2x5."""
    vb = cfg.VBOARD
    M = cfg.MIMAS
    W = vb['width']
    n0 = bay * cfg.DUTS_PER_BAY + 1
    rz = vb['row_z']
    hd, j6, j5 = cfg.CONN['HDMI'], cfg.CONN['2x6'], cfg.CONN['2x5']
    out_on = vb['hdmi_out'][bay] if bay < len(vb['hdmi_out']) else True

    def draw(p, u0, V):
        Vb = lambda z: V(z + z0)
        uc = u0 + W / 2
        hdmi = (['OUT'] if out_on else []) + [str(n0 + k) for k in range(cfg.DUTS_PER_BAY)]
        for i, name in enumerate(hdmi):
            u = uc + (i - (len(hdmi) - 1) / 2) * vb['hdmi_pitch']
            fr.rect_hole(p, u, Vb(rz['hdmi']), hd, hd[2])
            fr.label(p, name, u, Vb(rz['hdmi'] - hd[1] / 2 - 1.6), 1.6)
        for k in range(cfg.DUTS_PER_BAY):
            u = uc + (k - (cfg.DUTS_PER_BAY - 1) / 2) * vb['box_pitch']
            for conn, z in ((j6, rz['jb1']), (j5, rz['j5'])):
                fr.rect_hole(p, u, Vb(z), conn, conn[2])
                fr.pin1_mark(p, u - conn[0] / 2, u + conn[0] / 2, Vb(z), conn[1], vb['pin1'])
            fr.label(p, str(n0 + k), u, Vb(vb['label_z']), 2.2)
        for s in (-1, 1):
            p.cut(Circle(uc + s * vb['fix_holes_u'], Vb(rz['j5']), 1.7))
    item = fr.Item('bay%d' % (bay + 1), W, draw, 0.0, (z0, z0 + vb['label_z'] + 1.2),
                   title='bay %d (DUT %d-%d), vertical DUT board' % (bay + 1, n0, n0 + 3))
    my_min = (M['w'] - W) / 2
    sb = vb['behind_panel'] + vb['pcb'] + vb['mimas_gap']
    stack_top = cfg.MIMAS['standoff'] + M['pcb'] + cfg.SHIELD['stack'] + cfg.SHIELD['pcb'] + cfg.SHIELD['tallest']
    boxes = [
        ('DUT board %d' % (bay + 1), my_min, my_min + W, vb['behind_panel'], vb['behind_panel'] + vb['pcb'], 0.0,
         vb['height'], 'vboard', True),
        ('Mimas %d + shield' % (bay + 1), 0.0, M['w'], sb, sb + M['d'], 0.0, stack_top, 'mimas', True),
        ('HDMI jumpers %d' % (bay + 1), 0.0, M['w'], vb['behind_panel'] + vb['pcb'], sb, 0.0, 20.0, 'cable', False),
        ('RJ45 patch %d' % (bay + 1), M['rj45_my'][0], M['rj45_my'][1], sb + M['d'], sb + M['d'] + M['rj45_plug_clear'],
         0.0, 20.0, 'cable', False),
    ]
    holes = [(my, sb + (M['d'] - mx), M['hole_d'] / 2, 'Mimas') for (mx, my) in M['holes']]
    info = {'width': W, 'top': rz['j5'] + j5[1] / 2, 'stack_top': stack_top, 'z': dict(rz), 'src': 'config VBOARD'}
    return Bay(item, my_min, sb, boxes, holes, info)


def _alt_z(cfg):
    m = cfg.MIMAS
    mt = m['standoff'] + m['pcb']
    st = mt + cfg.SHIELD['stack'] + cfg.SHIELD['pcb']
    return {'mimas_hdmi': mt + m['hdmi_cz'], 'shield_hdmi': st + 3.25, 'shield_box': st + 4.5,
            'under_hdmi': st - cfg.SHIELD['pcb'] - 3.25}


def wide_item(cfg, z0=0.0):
    """Alternate: rev A single-row shield (279.6 mm)."""
    my0, my1 = cfg.WIDE['my']
    z = _alt_z(cfg)
    kinds = {'HDMI': ('HDMI', z['shield_hdmi']), 'JTAG': ('2x6', z['shield_box']), 'KBD': ('2x5', z['shield_box'])}

    def draw(p, u0, V):
        Vb = lambda zz: V(zz + z0)
        for ref, (a, b) in cfg.WIDE['slots'].items():
            kind = ref.rstrip('J0123456789')
            ck, zz = kinds[kind]
            u = u0 + (a + b) / 2 - my0
            fr.rect_hole(p, u, Vb(zz), cfg.CONN[ck], cfg.CONN[ck][2])
            fr.label(p, '%s %s' % (kind, ref[len(kind)]), u, Vb(zz + cfg.CONN[ck][1] / 2 + 2.0), 1.6)
        for name, my in (('IN 0', cfg.MIMAS['hdmi_in_my']), ('OUT', cfg.MIMAS['hdmi_out_my'])):
            fr.rect_hole(p, u0 + my - my0, Vb(z['mimas_hdmi']), cfg.CONN['HDMI'], 1.0)
            fr.label(p, name, u0 + my - my0, Vb(z['mimas_hdmi'] + 5.5), 1.6)
    return fr.Item('bay-wide', my1 - my0, draw, 0.0, (z0, z0 + z['shield_box'] + 7.0),
                   title='alternate: rev A 279.6 mm single-row shield bay')


def narrow_item(cfg, z0=0.0):
    my0, my1 = cfg.NARROW['my']
    z = _alt_z(cfg)

    def draw(p, u0, V):
        Vb = lambda zz: V(zz + z0)
        for kind, dut, my in cfg.NARROW['lower']:
            zz = z['mimas_hdmi'] if dut in ('OUT', 'DUT0') else z['under_hdmi']
            fr.rect_hole(p, u0 + my - my0, Vb(zz), cfg.CONN['HDMI'], 1.0)
            fr.label(p, dut, u0 + my - my0, Vb(zz - 5.5), 1.6)
        for kind, dut, my in cfg.NARROW['upper']:
            zz = z['shield_hdmi'] if kind == 'HDMI' else z['shield_box']
            fr.rect_hole(p, u0 + my - my0, Vb(zz), cfg.CONN[kind], cfg.CONN[kind][2])
            fr.label(p, dut, u0 + my - my0, Vb(zz + 6.5), 1.6)
    return fr.Item('bay-narrow', my1 - my0, draw, 0.0, (z0, z0 + z['shield_box'] + 8.0),
                   title='alternate: ~150 mm shield bay (2x8 per DUT)')


def make_bays(cfg, z0=0.0, variant=None, ztop=None):
    v = variant or cfg.VARIANT
    if v == 'shield190':
        return [shield190_bay(cfg, b, z0, ztop) for b in range(cfg.BAYS)]
    if v == 'vboard':
        return [vboard_bay(cfg, b, z0) for b in range(cfg.BAYS)]
    raise ValueError('VARIANT must be shield190 or vboard for full case generation (wide/narrow: fit report only)')
