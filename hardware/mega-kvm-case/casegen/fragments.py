"""Panel fragments: groups of cut-outs and engraving that the composer places
on the front/rear/side panels (and writes as their own sub-SVGs).

Each Item draws onto a panel at a left edge u0, with V(z) mapping a height
above the interior floor (mm) to the panel's v coordinate. 'width' is the
panel width it takes, 'depth' how far it reaches into the case behind the
panel and 'z' its vertical extent above the floor (for the fit checks).
"""
from . import font
from .geom import Circle, RRect, Panel


class Item:
    def __init__(self, name, width, draw, depth, z, title=None, info=''):
        self.name, self.width, self.draw, self.depth, self.z = name, width, draw, depth, z
        self.title = title or name
        self.info = info


def label(p, s, u, v, size, anchor='middle'):
    for pl in font.text(s, u, v, size, anchor):
        p.line(pl)


def rect_hole(p, uc, vc, wh, r=0.5):
    w, h = wh[0], wh[1]
    p.cut(RRect(uc, vc, w, h, r))


def pin1_mark(p, hole_u0, hole_u1, vc, h, where, size=1.2):
    """Small engraved triangle beside a box header's pin 1."""
    side, row = where.split('-')
    u = hole_u0 - 0.9 if side == 'left' else hole_u1 + 0.9
    v = vc + h / 2 - size / 2 - 0.3 if row == 'bottom' else vc - h / 2 + size / 2 + 0.3
    s = size / 2
    p.fill([(u - s, v + s), (u + s, v + s), (u, v - s)])


# ------------------------------------------------------------------ front panel group (0050)
def front_group(cfg, interior_h, with_rocker=True):
    F = cfg.FRONT
    lcd_w = F['lcd']['module'][0] + 2.0
    led_cols = 8
    led_block = 6.4 + led_cols * F['led_pitch']
    rocker_w = F['rocker'][0] + 5.0 if with_rocker else 0.0
    gap = F['gap']
    W = lcd_w + gap + led_block + ((gap + rocker_w) if with_rocker else 0.0)
    zc = interior_h / 2

    def draw(p, u0, V):
        # LCD
        uc = u0 + lcd_w / 2
        ww, wh = F['lcd']['window']
        p.cut(RRect(uc, V(zc), ww, wh, 0.5))
        hx, hy = F['lcd']['holes']
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.cut(Circle(uc + sx * hx / 2, V(zc + sy * hy / 2), F['lcd']['hole_d'] / 2))
        # LEDs: red row = powered, green row = selected
        ul = u0 + lcd_w + gap
        cols0 = ul + 6.4 + F['led_pitch'] / 2
        for i in range(led_cols):
            u = cols0 + i * F['led_pitch']
            label(p, str(i + 1), u, V(zc + 13.5), 2.0)
            p.cut(Circle(u, V(zc + 8.5), F['led_d'] / 2))
            p.cut(Circle(u, V(zc + 2.5), F['led_d'] / 2))
        label(p, 'PWR', ul + 2.8, V(zc + 8.5), 1.6)
        label(p, 'SEL', ul + 2.8, V(zc + 2.5), 1.6)
        label(p, 'RED', ul + 2.8, V(zc + 6.2), 1.0)
        label(p, 'GRN', ul + 2.8, V(zc + 0.2), 1.0)
        # buttons
        nb = len(F['buttons'])
        bc = ul + 6.4 + led_cols * F['led_pitch'] / 2
        for j, name in enumerate(F['buttons']):
            u = bc + (j - (nb - 1) / 2) * F['button_pitch']
            p.cut(Circle(u, V(zc - 6.5), F['button_d'] / 2))
            label(p, name, u, V(zc - 12.3), 1.6)
        # group marks: INPUT over the first two, MODE over the rest
        u_a = bc + (0 - (nb - 1) / 2) * F['button_pitch']
        u_b = bc + (1 - (nb - 1) / 2) * F['button_pitch']
        p.line([(u_a - 4, V(zc - 15.2)), (u_b + 4, V(zc - 15.2))])
        if nb > 2:
            u_c = bc + (2 - (nb - 1) / 2) * F['button_pitch']
            u_d = bc + (nb - 1 - (nb - 1) / 2) * F['button_pitch']
            p.line([(u_c - 4, V(zc - 15.2)), (u_d + 4, V(zc - 15.2))])
        # rocker
        if with_rocker:
            ur = ul + led_block + gap + rocker_w / 2
            rw, rh = F['rocker']
            p.cut(RRect(ur, V(zc), rw, rh, 0.5))
            label(p, 'I', ur, V(zc + rh / 2 + 2.2), 2.0)
            label(p, 'O', ur, V(zc - rh / 2 - 2.2), 2.0)
            label(p, 'POWER', ur, V(zc - rh / 2 - 5.4), 1.4)
    return Item('front-group', W, draw, F['lcd']['depth'], (zc - 18.0, zc + 18.0),
                title='front panel: LCD, LEDs (red = powered, green = selected), buttons, rocker')


def rocker_only(cfg, interior_h):
    F = cfg.FRONT
    zc = interior_h / 2
    rw, rh = F['rocker']

    def draw(p, u0, V):
        ur = u0 + (rw + 5) / 2
        p.cut(RRect(ur, V(zc), rw, rh, 0.5))
        label(p, 'I', ur, V(zc + rh / 2 + 2.2), 2.0)
        label(p, 'O', ur, V(zc - rh / 2 - 2.2), 2.0)
        label(p, 'POWER', ur, V(zc - rh / 2 - 5.4), 1.4)
    return Item('rocker', rw + 5, draw, 20.0, (zc - rh / 2, zc + rh / 2))


def logo(cfg, interior_h, size=9.0, sub='8-DUT MEGA65 TEST KVM'):
    w = font.text_width('MEGA-KVM', size) + 4.0
    zc = interior_h / 2

    def draw(p, u0, V):
        label(p, 'MEGA-KVM', u0 + w / 2, V(zc + 3.0), size)
        if sub:
            label(p, sub, u0 + w / 2, V(zc - 6.5), 2.2)
    return Item('logo', w, draw, 0.0, (zc - 8, zc + 8))


def vents(name, width, z0, z1, slot_w=2.5, pitch=6.0):
    def draw(p, u0, V):
        n = int((width - 2) // pitch)
        if n < 1:
            return
        start = u0 + (width - (n - 1) * pitch) / 2
        for i in range(n):
            p.cut(RRect(start + i * pitch, (V(z0) + V(z1)) / 2, slot_w, abs(V(z1) - V(z0)), slot_w / 2))
    return Item(name, width, draw, 0.0, (z0, z1))


# ------------------------------------------------------------------ rear / misc items
def bulkhead(cfg, zc=9.5):
    b = cfg.ITEMS['bulkhead']
    w = 2 * b['screws'] + 8.0

    def draw(p, u0, V):
        uc = u0 + w / 2
        p.cut(RRect(uc, V(zc), b['hole'][0], b['hole'][1], 0.8))
        for s in (-1, 1):
            p.cut(Circle(uc + s * b['screws'], V(zc), b['screw_d'] / 2))
        label(p, 'LAN', uc, V(zc + b['hole'][1] / 2 + 2.5), 2.0)
    return Item('bulkhead', w, draw, b['depth'], (zc - 8, zc + 8), title='Ethernet bulkhead (RJ45 coupler)')


def keyboard(cfg, zc=18.0):
    k = cfg.ITEMS['keyboard']
    w = 2 * k['screws'] + 6.0

    def draw(p, u0, V):
        uc = u0 + w / 2
        p.cut(RRect(uc, V(zc), k['hole'][0], k['hole'][1], 0.5))
        pin1_mark(p, uc - k['hole'][0] / 2, uc + k['hole'][0] / 2, V(zc), k['hole'][1], cfg.VBOARD['pin1'])
        for s in (-1, 1):
            p.cut(Circle(uc + s * k['screws'], V(zc), k['screw_d'] / 2))
        label(p, 'KEYBOARD', uc, V(zc + 8.0), 2.0)
    return Item('keyboard', w, draw, k['depth'], (zc - 6, zc + 10), title='physical keyboard feed-through (2x5)')


def dut_power(cfg, z_rows=(25.0, 32.5)):
    """8 DUT 12 V lead holes in two rows of 4, plus the extra leads in
    ITEMS['dut_power']['extra'] (e.g. the 6 V outlet, issue 0055) in a third
    row above them (same width, so the column next to the bays does not grow)."""
    d = cfg.ITEMS['dut_power']
    extra = d.get('extra', [])[:4]
    w = 4 * d['pitch'] + 4.0
    zs = list(z_rows) + ([z_rows[-1] + (z_rows[1] - z_rows[0])] if extra else [])

    def draw(p, u0, V):
        for r, z in enumerate(z_rows):
            for i in range(4):
                u = u0 + 2.0 + d['pitch'] * (i + 0.5)
                p.cut(Circle(u, V(z), d['hole_d'] / 2))
                label(p, str(r * 4 + i + 1), u, V(z - d['hole_d'] / 2 - 1.1), 1.2)
        for i, name in enumerate(extra):
            u = u0 + 2.0 + d['pitch'] * (i + 0.5)
            p.cut(Circle(u, V(zs[-1]), d['hole_d'] / 2))
            label(p, name, u, V(zs[-1] - d['hole_d'] / 2 - 1.1), 1.2)
        label(p, 'DUT 12V' + (' / ' + ' '.join(extra) if extra else ''), u0 + w / 2,
              V(zs[-1] + d['hole_d'] / 2 + 1.6), 1.6)
    return Item('dut_power', w, draw, 5.0, (zs[0] - 5, zs[-1] + 5),
                title='DUT power leads (%d)' % (8 + len(extra)))


def net_and_power(cfg):
    """Bulkhead (low) with the 8 DUT power lead holes above it, in one column."""
    b, d = bulkhead(cfg, zc=9.5), dut_power(cfg)
    w = max(b.width, d.width)

    def draw(p, u0, V):
        b.draw(p, u0 + (w - b.width) / 2, V)
        d.draw(p, u0 + (w - d.width) / 2, V)
    return Item('bulkhead+dut_power', w, draw, b.depth, (b.z[0], d.z[1]), title='Ethernet bulkhead + DUT power leads')


def recess(cfg, zc=13.0):
    r = cfg.ITEMS['recess']
    w = r['w'] + 6

    def draw(p, u0, V):
        p.cut(RRect(u0 + w / 2, V(zc), r['w'], r['h'], 3.0))
        label(p, 'DC LEADS', u0 + w / 2, V(zc + r['h'] / 2 + 2.2), 1.8)
    return Item('recess', w, draw, r['depth'], (zc - r['h'] / 2, zc + r['h'] / 2), title='DC lead tuck-away pocket')


def power_inputs(cfg, board, bottom_z=0.0, title_z=None):
    """Rear-panel cut-outs for the vertical input board (0047), from its KiCad file.
    Board y (from its top edge) maps to height: z = bottom_z + h - y."""
    P = cfg.POWER_IN
    bw = P['width_override'] or (board['w'] if board else P['w'])
    bh = board['h'] if board else P['h']
    fp = board['fp'] if board else {}
    zof = lambda y: bottom_z + bh - y
    # LED light holes that would run into a connector cut-out are left out (reported)
    cl = P['conn_clear']
    rects = [(fp[r]['crt'][0] - cl, fp[r]['crt'][1] - cl, fp[r]['crt'][2] + cl, fp[r]['crt'][3] + cl)
             for r in ('J3', 'J4') if r in fp and fp[r]['crt']]
    rl = P['led_hole'] / 2 + 1.5        # hole radius + minimum web
    skipped = [r for r in ('D7', 'D8', 'D9') if r in fp and any(
        a - rl < fp[r]['x'] < c + rl and b - rl < fp[r]['y'] < d + rl for (a, b, c, d) in rects)]
    stacked = bool(fp) and abs(fp['J1']['x'] - fp['J2']['x']) < 5.0

    def draw(p, u0, V):
        if not fp:
            label(p, 'INPUT BOARD NOT FOUND', u0 + bw / 2, V(20), 2.0)
            return
        for ref, txt in (('J1', '+12V'), ('J2', '0V')):
            f = fp[ref]
            p.cut(Circle(u0 + f['x'], V(zof(f['y'])), P['banana_hole'] / 2))
            label(p, txt, u0 + f['x'], V(zof(f['y']) - P['banana_hole'] / 2 - 2.0), 1.8)
        j1, j2 = fp['J1'], fp['J2']
        if stacked:         # v0.3 board: bananas one above the other; title under the lower one
            jl = j1 if j1['y'] > j2['y'] else j2
            label(p, '1 BANANA 25A', u0 + jl['x'] + 4.0, V(zof(jl['y']) - P['banana_hole'] / 2 - 5.5), 1.8)
        else:
            label(p, '1 BANANA 25A', u0 + (j1['x'] + j2['x']) / 2, V(zof(j1['y']) + 9.5), 1.8)
        for ref, txt in (('J3', '2 PCIE 8P 15A'), ('J4', '3 MOLEX 10A')):
            c = fp[ref]['crt']
            cl = P['conn_clear']
            uc = u0 + (c[0] + c[2]) / 2
            vc = V(zof((c[1] + c[3]) / 2))
            p.cut(RRect(uc, vc, c[2] - c[0] + 2 * cl, c[3] - c[1] + 2 * cl, 1.0))
            label(p, txt, uc, V(zof(c[1]) + cl + 2.6), 1.6)
        for ref, txt in (('D7', '1'), ('D8', '2'), ('D9', '3')):
            if ref in fp and ref not in skipped:
                f = fp[ref]
                p.cut(Circle(u0 + f['x'], V(zof(f['y'])), P['led_hole'] / 2))
        for ref in sorted(r for r in fp if r[0] == 'H' and r[1:].isdigit()):
            if ref in fp:
                f = fp[ref]
                p.cut(Circle(u0 + f['x'], V(zof(f['y'])), 1.7))
        label(p, '12V IN  1 > 2 > 3', u0 + 45, V(zof(0) - 3.2 if title_z is None else title_z), 1.8)
    it = Item('power_inputs', bw, draw, P['behind_panel'] + P['depth'], (bottom_z, bottom_z + bh),
              title='rear power inputs (input board 0047)')
    it.skipped_leds = skipped
    return it


def fan_wall(cfg, zc):
    F = cfg.FAN
    w = F['size'] + 4

    def draw(p, u0, V):
        uc = u0 + w / 2
        from .geom import circle_grid
        r = min(F['grille_r'], zc - 0.5, F['size'] / 2 - 1)
        for c in circle_grid(uc, V(zc), r, F['grille_hole'], F['grille_pitch']):
            p.cut(c)
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.cut(Circle(uc + sx * F['hole_pitch'] / 2, V(zc + sy * F['hole_pitch'] / 2), F['hole_d'] / 2))
    return Item('fan', w, draw, F['thick'] + F['wall_gap'], (zc - F['size'] / 2, zc + F['size'] / 2))


def standalone(item, panel_h, V_of, name=None):
    """A fragment Panel (no outline) holding just this item, for its own SVG."""
    p = Panel(name or item.name, item.width, panel_h)
    p.title = item.title
    item.draw(p, 0.0, V_of)
    return p
