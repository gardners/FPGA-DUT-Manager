"""Rack layout (issue 0051): MEGA65 shelves, fan plates, the 3RU KVM unit.

Coordinates
  rack/unit z   height above the bottom of a unit's RU slot (mm)
  deck x        across, from the deck's left edge seen from the front
  deck y        from the deck's front edge towards the rear
A shelf: 25 x 25 battens under both deck edges (z 0..25), the 6 mm deck on
top (z 25..31), the next shelf's battens start 1RU higher (z 44.45).

Panels follow geom.py: seen from outside (decks from above, front at the
bottom), u right, v down. Decks: u = x, v = D - y. Front faces (fan plate,
KVM front): u = x + (face width - deck width) / 2, v = H - z. KVM rear
plate (seen from the rear): u = deck_w - x, v = H - z.
"""
import json
import math
import os

from . import bays as baymod
from . import font
from . import fragments as fr
from . import logos
from .geom import Circle, Panel, RRect, circle_grid, rect_pts
from .layout import Box

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def label(p, s, u, v, size, anchor='middle'):
    fr.label(p, s, u, v, size, anchor)


def dashed(p, u0, v0, u1, v1, on=6.0, off=4.0):
    L = math.hypot(u1 - u0, v1 - v0)
    n = int(L // (on + off)) + 1
    for i in range(n):
        a = i * (on + off) / L
        b = min((i * (on + off) + on) / L, 1.0)
        if a >= 1.0:
            break
        p.line([(u0 + (u1 - u0) * a, v0 + (v1 - v0) * a), (u0 + (u1 - u0) * b, v0 + (v1 - v0) * b)])


def outline_engrave(p, pts):
    p.line(list(pts) + [pts[0]])


def fan_cut(p, uc, vc, size, spec, guard, hole=6.0, pitch=7.5):
    """Fan opening (grille or plain bore) and the four screw holes."""
    if guard == 'grille':
        for c in circle_grid(uc, vc, spec['bore'] / 2, hole, pitch):
            p.cut(c)
    else:
        p.cut(Circle(uc, vc, spec['bore'] / 2))
    h = spec['pitch'] / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.cut(Circle(uc + sx * h, vc + sy * h, spec['hole_d'] / 2))


def gusset_panel(name, h, l, c, qty, title):
    """Right triangle: vertical leg h (against the plate), horizontal leg l (on/under the deck);
    the right-angle corner is chamfered by c (clears glue and the plate/deck edge)."""
    p = Panel(name, l, h, qty=qty)
    p.title = title
    p.outline = [(0, 0), (l, h), (c, h), (0, h - c)]
    return p


# ====================================================================== geometry
class Geo:
    def __init__(self, cfg, fp):
        self.cfg, self.fp = cfg, fp
        S = cfg.SHELF
        self.RU = cfg.RACK['ru']
        self.W = S['deck_w']
        self.BT = S['batten']
        self.T = cfg.PLY_T
        self.top = self.BT + self.T                         # deck top above the slot bottom
        self.clear_mid = self.RU + self.BT - self.top       # deck top -> next deck underside
        self.clear_edge = self.RU - self.top                # deck top -> next shelf's battens
        self.du = (cfg.RACK['face_width'] - self.W) / 2
        b = fp.BOARD
        self.D = S['depth'] or float(math.ceil(S['front_allow'] + b['d'] + S['rear_space']))
        # fan plate
        F = cfg.FAN_PLATE
        self.fspec = cfg.FANS[F['fan']]
        self.FH = F['ru'] * self.RU
        s = F['fan']
        n = F['count']
        pitch = s + F['gap']
        self.fans = []
        for i in range(n):
            xc = self.W / 2 + (i - (n - 1) / 2) * pitch
            where = F['stagger'][i % len(F['stagger'])]
            if where == 'low':
                z0 = F['edge']
                if S['fan_clearance'] == 'setback' and F.get('low_above_deck', True):
                    z0 = max(z0, self.top + F['deck_gap'])    # clear of the carrier's own deck: no notches
                zc = z0 + s / 2
            else:
                zc = self.FH - F['edge'] - s / 2
            self.fans.append({'i': i, 'x0': xc - s / 2, 'x1': xc + s / 2, 'xc': xc, 'zc': zc,
                              'z0': zc - s / 2, 'z1': zc + s / 2, 'where': where})
        self.nd = self.fspec['thick'] + S['notch_extra']     # notch depth
        g = F['gusset']
        self.gus = g
        # per-shelf set-back within a group, and batten front ends
        G = cfg.RACK['group']
        self.mode = S['fan_clearance']
        if self.mode == 'setback':
            need = max(self.nd, g['l'] + 2.0)
            self.setback = S['setback'] if S['setback'] is not None else need
            self.setback_need = need
            self.batten_front_other = 0.0
        else:
            self.setback = 0.0
            self.setback_need = 0.0
            self.batten_front_other = g['l'] + 2.0           # other shelves' battens start behind the gussets
        self.shelf_y0 = [0.0] + [self.setback] * (G - 1)
        # notches: fans crossing a deck whose front edge is within the fan bodies
        cross = set()
        for k in range(G):
            if self.shelf_y0[k] >= self.nd:
                continue
            dz0, dz1 = k * self.RU + self.BT, k * self.RU + self.top
            for f in self.fans:
                if f['z0'] < dz1 and dz0 < f['z1']:
                    cross.add(f['i'])
        nc = S['notch_clear']
        iv = sorted((self.fans[i]['x0'] - nc, self.fans[i]['x1'] + nc) for i in cross)
        merged = []
        for a, b2 in iv:
            if merged and a - merged[-1][1] < S['min_tongue']:
                merged[-1] = (merged[-1][0], max(merged[-1][1], b2))
            else:
                merged.append((a, b2))
        self.notches = merged
        self.cross = sorted(cross)
        self.ndeff = self.nd if merged else 0.0              # notched front band of the decks (0: none)
        # MEGA65 placement on the deck
        fl = fp.FLOPPY if S['floppy'] else None
        span = b['w'] + ((S['floppy_gap'] + fl['w']) if fl else 0.0)
        inner = self.W - 2 * self.BT
        self.bx = S['mega65_x'] if S['mega65_x'] is not None else self.BT + (inner - span) / 2
        self.by = S['front_allow']
        self.fx = (self.bx + b['w'] + S['floppy_gap'] + fl['w'] / 2) if fl else None   # floppy centre x
        self.fy = self.by                                                              # floppy front
        self.span = span


# ====================================================================== shelf parts
def shelf_deck(g):
    cfg, fp = g.cfg, g.fp
    S = cfg.SHELF
    W, D, BT = g.W, g.D, g.BT
    p = Panel('shelf-deck', W, D, qty=cfg.RACK['layout'].count('shelf'))
    p.title = 'MEGA65 shelf deck, 6 mm ply (seen from above, front at the bottom); x%d' % p.qty
    V = lambda y: D - y
    out = [(0, 0), (W, 0), (W, D)]
    for a, b in sorted(g.notches, reverse=True):
        out += [(b, D), (b, D - g.nd), (a, D - g.nd), (a, D)]
    out += [(0, D)]
    p.outline = out
    # battens (drill guide, hidden layer) and keep-out strips (etched dashed lines)
    for x0 in (0.0, W - BT):
        p.ref.append(RRect(x0 + BT / 2, D / 2, BT, D, 0))
    for x in (BT, W - BT):
        dashed(p, x, 4.0, x, D - g.ndeff - 3.0)
    for x, rot in ((BT / 2, True), (W - BT / 2, True)):
        for pl in font.text_vertical('EDGE STRIP: PARTS UNDER %.0f MM' % (g.clear_edge - S['clear_top']), x, D * 0.55, 3.0):
            p.line(pl)
    # deck -> batten screws (only where every shelf's batten is: behind the gussets)
    ys0 = max(g.batten_front_other, 0.0) + 12.0
    n = max(2, int(math.ceil((D - 12.0 - ys0) / S['screw_pitch'])) + 1)
    for x in (BT / 2, W - BT / 2):
        for i in range(n):
            y = ys0 + (D - 12.0 - ys0) * i / (n - 1)
            p.cut(Circle(x, V(y), S['screw_d'] / 2))
        for f in (1 / 3, 2 / 3):          # gusset pilot holes (used on the fan-plate shelf only)
            p.cut(Circle(x, V(g.gus['l'] * f), 1.5))
    # MEGA65 board
    b = fp.BOARD
    bx, by = g.bx, g.by
    nx0, nx1, ny = b['notch']
    bo = [(bx, V(by)), (bx + b['w'], V(by)), (bx + b['w'], V(by + b['d'])), (bx + nx1, V(by + b['d'])),
          (bx + nx1, V(by + ny)), (bx + nx0, V(by + ny)), (bx + nx0, V(by + b['d'])), (bx, V(by + b['d']))]
    outline_engrave(p, bo)
    label(p, 'MEGA65', bx + b['w'] / 2, V(by + b['d'] / 2 + 6), 6.0)
    label(p, 'MAINBOARD (TOP VIEW)', bx + b['w'] / 2, V(by + b['d'] / 2 - 4), 3.0)
    for (hx, hy) in b['holes']:
        c = Circle(bx + hx, V(by + hy), b['hole_d'] / 2)
        (p.cut if b['cut'] else p.ref.append)(c)
    # floppy
    if g.fx is not None:
        fl = fp.FLOPPY
        x0 = g.fx - fl['w'] / 2
        outline_engrave(p, rect_pts(x0, V(g.fy + fl['d']), x0 + fl['w'], V(g.fy)))
        label(p, 'FLOPPY', g.fx, V(g.fy + fl['d'] / 2 + 5), 5.0)
        label(p, 'SLOT TO THE FRONT', g.fx, V(g.fy + fl['d'] / 2 - 4), 2.5)
        for hx, hy in fl['holes']:
            c = Circle(g.fx + hx, V(g.fy + hy), fl['hole_d'] / 2)
            (p.cut if fl['cut'] else p.ref.append)(c)
    # Cart64out lying flat behind the expansion port: cart (cx, cy) -> deck (x0 + cy, tip + cx)
    c = fp.CART64OUT
    cx0 = bx + b['port_x'] - 31.0
    ct = by + c['tip_y']
    co = [(cx0 + cy, V(ct + cx)) for (cx, cy) in c['outline']]
    outline_engrave(p, co)
    label(p, 'CART64OUT', cx0 + 31.0, V(ct + 45), 3.5)
    for (hx, hy) in c['holes']:
        cc = Circle(cx0 + hy, V(ct + hx), c['hole_d'] / 2)
        (p.cut if c['cut'] else p.ref.append)(cc)
    for it in fp.EXPANSIONS['items']:
        x0, y0, x1, y1 = it['outline']
        outline_engrave(p, rect_pts(bx + x0, V(by + y1), bx + x1, V(by + y0)))
        for hx, hy in it['holes']:
            cc = Circle(bx + hx, V(by + hy), it['hole_d'] / 2)
            (p.cut if fp.EXPANSIONS['cut'] else p.ref.append)(cc)
    # cable pass-throughs, each with a pair of tie slots on both sides
    tw, th, tp = S['tie_slot']
    for (x, yr, w, h) in S['cable_slots']:
        y = D - yr
        p.cut(RRect(x, V(y), w, h, h / 2))
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.cut(RRect(x + sx * (w / 2 + 6), V(y + sy * tp / 2), th, tw, tw / 2))
    # strain-relief bar tab slots
    sb = S['strain_bar']
    for s in (-1, 1):
        p.cut(RRect(W / 2 + s * sb['tab_u'], V(D - sb['from_rear']), sb['tab_w'] + 0.2, g.T + 0.2, 0))
    label(p, 'FRONT', W / 2, V(g.ndeff + 3.5), 3.0)
    label(p, 'CABLE LOOPS / STRAIN RELIEF', W / 2, V(D - sb['from_rear'] - 9), 2.5)
    return p


def strain_bar(g):
    S = g.cfg.SHELF
    sb = S['strain_bar']
    L = g.W - 2 * g.BT - 4.0
    h, T = sb['h'], g.T
    p = Panel('strain-bar', L, h + T, qty=g.cfg.RACK['layout'].count('shelf'))
    p.title = 'shelf rear strain-relief bar (stands in the deck slots), x%d' % p.qty
    out = [(0, 0), (L, 0), (L, h)]
    for s in (1, -1):
        uc = L / 2 + s * sb['tab_u']
        out += [(uc + sb['tab_w'] / 2, h), (uc + sb['tab_w'] / 2, h + T), (uc - sb['tab_w'] / 2, h + T),
                (uc - sb['tab_w'] / 2, h)]
    out += [(0, h)]
    p.outline = out
    tw, th, tp = S['tie_slot']
    n = int((L - 20) // sb['tie_pitch']) + 1
    u0 = (L - (n - 1) * sb['tie_pitch']) / 2
    for i in range(n):
        u = u0 + i * sb['tie_pitch']
        for sx in (-1, 1):
            p.cut(RRect(u + sx * tp / 2, h * 0.55, tw, th, tw / 2))
    return p


def logo_band(g, f):
    """Free band (z0, z1) for a logo above or below fan f, whichever is taller."""
    e = g.cfg.FAN_PLATE['edge']
    above = (f['z1'] + 3.0, g.FH - e - 3.0)
    below = (e + 3.0, f['z0'] - 3.0)
    return max(above, below, key=lambda b: b[1] - b[0])


def fan_plate(g):
    cfg = g.cfg
    F = cfg.FAN_PLATE
    W, H, du = cfg.RACK['face_width'], g.FH, g.du
    groups = cfg.RACK['layout'].count('shelf') // cfg.RACK['group']
    p = Panel('fan-plate', W, H, qty=max(groups, 1))
    p.title = 'fan plate %dRU, %d x %d mm fans (seen from the front), x%d' % (F['ru'], F['count'], F['fan'], p.qty)
    p.outline = rect_pts(0, 0, W, H)
    V = lambda z: H - z
    notes = []
    for f in g.fans:
        fan_cut(p, du + f['xc'], V(f['zc']), F['fan'], g.fspec, F['guard'], F['grille_hole'], F['grille_pitch'])
    for x in (g.BT / 2, g.W - g.BT / 2):
        for z in F['batten_screws']:
            p.cut(Circle(du + x, V(z), F['screw_d'] / 2))
        for fz in (0.35, 0.7):
            p.cut(Circle(du + x, V(g.top + g.gus['h'] * fz), 1.75))
    for name, i in F['logos']:
        f = g.fans[i]
        za, zb = logo_band(g, f)
        hh = min(cfg.LOGOS[name]['h'], zb - za)
        notes.append(logos.slot(cfg, p, name, du + f['xc'], V((za + zb) / 2), min(cfg.LOGOS[name]['w'], F['fan'] - 6), hh))
    hi = [f for f in g.fans if f['where'] == 'high']
    if hi and F['text']:
        f = hi[0]
        size = min(F['text_size'], (f['z0'] - 6.0) / 2)
        label(p, F['text'], du + f['xc'], V(f['z0'] / 2 + 3.0), size)
        label(p, 'MEGA65 TEST RACK', du + f['xc'], V(f['z0'] / 2 - size / 2 - 3.0), 3.0)
    return p, notes


# ====================================================================== KVM unit
def load_front(cfg):
    path = os.path.join(HERE, cfg.KVM['front_holes'])
    if not os.path.exists(path):
        return None
    return json.load(open(path))


def build_kvm(g, boards, problems, notes):
    cfg = g.cfg
    K = cfg.KVM
    W, du, BT, top = g.W, g.du, g.BT, g.top
    H = K['ru'] * g.RU
    FW = cfg.RACK['face_width']
    fs = cfg.FANS[K['fan']]
    m = K['side_margin']
    js = load_front(cfg)
    pcb_w, pcb_h = (js['board']['w'], js['board']['h']) if js else (227.0, 36.0)
    rw, rh = cfg.FRONT['rocker']
    boxes = []
    # ---------------- front-panel layout (deck x)
    # Owner round 12: no power connectors on the front any more. Fans on the
    # left; right-hand column: display PCB at the top. 2026-11-27 (owner: 2 x
    # 120 mm fans): fans taller than the space above the deck reach down
    # through deck notches, between the front gussets; the rocker then sits
    # left of the fans and the MEGA-KVM etch and the logos under the display.
    fan_zc = H - K['fan_edge'] - K['fan'] / 2
    fan_cross_deck = fan_zc - K['fan'] / 2 < top + 1.0
    rocker_left = K['rocker_pos'] == 'left'
    x = m
    if fan_cross_deck:      # between the front gussets (against the battens' inner faces)
        x = max(x, BT + g.T + K['fan_gusset_clear'])
    if rocker_left:
        x = max(x, m + rw + 2 * K['rocker_clear'])
    fans = []
    for i in range(K['fan_count']):
        fans.append((x + K['fan'] / 2, fan_zc))
        x += K['fan'] + K['fan_gap']
    fans_end = x - K['fan_gap']
    fans_x0 = fans[0][0] - K['fan'] / 2 if fans else m
    pcb_x0 = W - m - pcb_w
    pcb_z1 = H - K['pcb_top']
    pcb_z0 = pcb_z1 - pcb_h
    right_w = pcb_w
    col_x0 = pcb_x0
    if K['rocker_pos'] == 'json' and js and js['rocker'].get('x') is not None:
        rock_x = pcb_x0 + js['rocker']['x']
        rock_z = H - K['pcb_top'] - js['rocker']['y']
    elif rocker_left:                           # in the strip left of the fans, at the fans' height
        rock_x = (m + fans_x0) / 2
        rock_z = fan_zc if fans else H / 2
    else:                                       # 'below_pcb'
        rock_x = pcb_x0 + K['rocker_dx'] + rw / 2
        rock_z = (top + 2.0 + pcb_z0 - 2.0) / 2
    width_need = fans_x0 + (fans_end - fans_x0) + 2.0 + right_w + m
    if fans_end + 2.0 > pcb_x0 + 1e-6:
        problems.append('KVM front: %d x %d mm fans (x %.0f-%.0f) and the display column (%.0f mm) need %.0f mm, '
                        'the deck is %.0f mm' % (K['fan_count'], K['fan'], fans_x0, fans_end, right_w, width_need, W))
    if rock_x - rw / 2 < 1 or rock_x + rw / 2 > W - 1 or rock_z - rh / 2 < top + 1:
        problems.append('KVM front: the rocker (deck x %.0f, z %.0f) does not fit' % (rock_x, rock_z))
    if rocker_left and fans and rock_x + rw / 2 + 1.0 > fans_x0:
        problems.append('KVM front: the rocker (deck x %.0f) runs into fan 1 (from x %.0f)' % (rock_x, fans_x0))
    kvm_notches = []                           # (x0, x1, depth); overlapping notches merged
    if fan_cross_deck:
        for xc, zc in fans:
            a, b_, nd = xc - K['fan'] / 2 - 1, xc + K['fan'] / 2 + 1, fs['thick'] + 3
            if kvm_notches and a <= kvm_notches[-1][1]:
                kvm_notches[-1] = (kvm_notches[-1][0], b_, max(nd, kvm_notches[-1][2]))
            else:
                kvm_notches.append((a, b_, nd))
            if xc - K['fan'] / 2 < BT + 1 or xc + K['fan'] / 2 > W - BT - 1:
                problems.append('KVM front: a %d mm fan reaches below the deck and over a batten' % K['fan'])
    # ---------------- front zone boxes
    for i, (xc, zc) in enumerate(fans):
        boxes.append(Box('KVM fan %d' % (i + 1), xc - K['fan'] / 2, xc + K['fan'] / 2, 0, fs['thick'],
                         zc - K['fan'] / 2, zc + K['fan'] / 2, 'fan'))
    lcd_d = cfg.FRONT['lcd']['depth']
    gap = js['board']['panel_gap'] if js else 3.0
    boxes.append(Box('front PCB + LCD', pcb_x0, pcb_x0 + pcb_w, gap, gap + 1.6 + lcd_d, pcb_z0, pcb_z1, 'front'))
    boxes.append(Box('rocker', rock_x - rw / 2, rock_x + rw / 2, 0, 22.0, rock_z - rh / 2, rock_z + rh / 2, 'front'))
    zone_d = max(b.y1 for b in boxes) + K['front_zone_extra']
    # ---------------- inside: power board at the front, GS105 beside it, bays at the rear
    G5 = cfg.GS105
    pm = boards.get('main')
    pm_w, pm_d = (pm['w'], pm['h']) if pm else (cfg.POWER_MAIN['w'], cfg.POWER_MAIN['d'])
    PM = cfg.POWER_MAIN
    px0 = K['power_x']
    y0 = max(zone_d, K['power_front'])          # power board front edge (deck y)
    yr = y0 + pm_d                              # its rear edge (DUT terminals, Mimas Mini-Fit, GS105 jack)
    pz0 = top + PM['standoff']
    pzt = pz0 + 1.6
    boxes.append(Box('power board', px0, px0 + pm_w, y0, yr, pz0, pzt + PM['tallest'], 'power'))
    # plugs and cable bends above the input connectors along the front edge (open top)
    fx = [f for r, f in (pm['fp'].items() if pm else []) if r in ('J50', 'J51', 'J52', 'J53', 'J54')]
    ix1 = max([(f['crt'][2] if f['crt'] else f['x'] + 6) for f in fx] + [94.0])
    boxes.append(Box('input plugs (from above)', px0, px0 + ix1 + 2, y0, y0 + K['plug_strip'], pzt,
                     pzt + K['plug_clear'], 'inputs'))
    gx0 = px0 + pm_w + K['power_gap']
    if gx0 + G5['w'] > W - m:
        problems.append('KVM deck: power board + GS105 (%.0f mm) wider than the deck' % (gx0 + G5['w']))
    boxes.append(Box('GS105', gx0, gx0 + G5['w'], y0, y0 + G5['d'], top, top + G5['h'], 'gs105'))
    bays = baymod.make_bays(cfg, 0.0, ztop=H - top)
    M = cfg.MIMAS
    D = float(math.ceil(max(yr, y0 + G5['d']) + K['cable_gap'] + M['rj45_plug_clear'] + M['d'] + bays[0].setback))
    # rear plate (seen from the rear): bays at the left, bulkhead + DUT power at the right,
    # i.e. at the deck's LEFT, behind the power board's DUT terminals
    Hr = H - K['rear_clear']
    bay_gap = cfg.CASE_A['bay_gap']
    bays_w = sum(b.width for b in bays) + bay_gap * (len(bays) - 1)
    rm = 3.0
    ub0 = rm
    _bk, _dp = fr.bulkhead(cfg, zc=9.5), fr.dut_power(cfg, z_rows=(31.0, 39.5))
    npw = fr.Item('bulkhead+dut_power', max(_bk.width, _dp.width),
                  lambda p, u0, V: (_bk.draw(p, u0 + (max(_bk.width, _dp.width) - _bk.width) / 2, V),
                                    _dp.draw(p, u0 + (max(_bk.width, _dp.width) - _dp.width) / 2, V)),
                  _bk.depth, (_bk.z[0], _dp.z[1]), title='Ethernet bulkhead + DUT power leads')
    u_col = W - rm - npw.width
    rear_free = u_col - (ub0 + bays_w)
    if rear_free < 2.0:
        problems.append('KVM rear: bays (%.1f) + bulkhead/DUT power (%.1f) do not fit %.0f mm' % (bays_w, npw.width, W))
    deck_holes = []
    bay_u = []
    u = ub0
    for b in bays:
        bay_u.append(u)
        for (name, a0, a1, e0, e1, z0, z1, kind, hard) in b.boxes:
            boxes.append(Box(name, W - (u + a0 - b.my_min), W - (u + a1 - b.my_min), D - e0, D - e1, top + z0, top + z1, kind, hard))
        for (a, e, r, what) in b.holes:
            deck_holes.append((W - (u + a - b.my_min), D - e, r, what))
        u += b.width + bay_gap
    if pm:
        for ref, f in pm['fp'].items():
            if ref.startswith('H'):
                deck_holes.append((px0 + f['x'], y0 + pm_d - f['y'], 1.7, 'power board'))
    # Stand-off screws over a batten need a hole drilled through the batten too. The power
    # board is placed to avoid that; the two bays (381 mm) are wider than the 375 mm
    # between the battens, so their outermost support holes land on one batten.
    over = []
    for (hx, hy, r, what) in deck_holes:
        if hx - r < BT + 0.5 or hx + r > W - BT - 0.5:
            if what == 'power board':
                problems.append('KVM deck: a %s hole at x %.1f is over a batten' % (what, hx))
            else:
                over.append(('right' if hx > W / 2 else 'left', '%s (x %.1f, y %.1f)' % (what, hx, hy)))
    if over:
        sides = sorted(set(sd for sd, _ in over))
        notes.append('KVM deck: %d bay holes are over the %s batten%s: %s. Drill them on through the batten and '
                     'use M3 x 40 screws from below' % (len(over), ' and '.join(sides), 's' if len(sides) > 1 else '',
                                                        '; '.join(t for _, t in over)))
    # cable routes (soft): DUT leads to the rear column, Mimas Mini-Fit leads, GS105 jack
    col_x0, col_x1 = W - (u_col + npw.width), W - u_col
    bay_x0 = min(bx.x0 for bx in boxes if bx.kind in ('mimas', 'shield', 'kbd'))
    term = [f for r, f in (pm['fp'].items() if pm else []) if r.startswith('J1') and len(r) == 3 and f['crt']]
    tx0 = px0 + min([f['crt'][0] for f in term] + [7.0])
    tx1 = px0 + max([f['crt'][2] for f in term] + [113.0])
    routes = [('DUT leads', tx0, tx1, yr, yr + K['cable_gap']),
              ('DUT leads to the rear', col_x0, max(col_x1, bay_x0 - 1.0), yr, D),
              ('Mimas power leads', px0 + 118.0, px0 + 145.0, yr, D - M['d']),
              ('GS105 12V lead', px0 + 144.0, gx0 + 10.0, yr - 2.0, yr + 8.0)]
    for name, xa, xb, ya, yb in routes:
        boxes.append(Box(name, xa, xb, ya, yb, top, top + 10.0, 'cable', False))
    if col_x1 > bay_x0 + 0.01:
        problems.append('KVM: the rear DUT-power column (x %.0f-%.0f) overlaps the bays (from x %.0f)' % (col_x0, col_x1, bay_x0))
    # cable-tie slots in front of and behind the GS105 (ties run front-to-back over it),
    # and tie points along the DUT lead route behind the power board
    ties = [(gx0 + G5['w'] * q, yy) for q in (0.3, 0.7) for yy in (y0 - 2.5, y0 + G5['d'] + 2.5)]
    tie_pairs = [(xc, yr + K['cable_gap'] / 2) for xc in (tx0 + 20, (tx0 + tx1) / 2, tx1 - 10)]
    # gussets under the deck against the battens' inner faces: front and rear
    gk = K['gusset']
    # each gusset starts against its batten's inner face and moves inwards until it clears the deck holes
    def clear_x(x_start, step, ya, yb):
        for i in range(40):
            xg = x_start + step * i
            if all(not (xg - g.T / 2 - r - 1.0 < hx < xg + g.T / 2 + r + 1.0 and ya - r - 1.0 < hy < yb + r + 1.0)
                   for (hx, hy, r, _) in deck_holes):
                return xg
        return None
    if gk['h'] > BT:
        problems.append('KVM gussets (%.0f mm) taller than the space under the deck (%.0f mm)' % (gk['h'], BT))
    kgus = []                                  # (x, y0, y1, front)
    for x_start, step in ((BT + g.T / 2, 1.0), (W - BT - g.T / 2, -1.0)):
        for (ya, yb, front) in ((0, gk['l'], True), (D - gk['l'], D, False)):
            xg = clear_x(x_start, step, ya, yb)
            if xg is None:
                problems.append('KVM gusset near x %.0f: no hole-free place' % x_start)
                continue
            if abs(xg - x_start) > 0.01:
                notes.append('KVM %s gusset moved %.0f mm inwards off the batten to clear deck holes' % (
                    'front' if front else 'rear', abs(xg - x_start)))
            kgus.append((xg, ya, yb, front))
            boxes.append(Box('KVM gusset', xg - g.T / 2, xg + g.T / 2, ya, yb, BT - gk['h'], BT, 'item', True, inside=False))
    # fan bodies against the parts under the deck (not in the inside-box check): gussets and battens
    under = [b for b in boxes if b.name == 'KVM gusset'] + [
        Box('left batten', 0, BT, 0, D, 0, BT), Box('right batten', W - BT, W, 0, D, 0, BT)]
    fan_under_gap = None
    for fb in [b for b in boxes if b.kind == 'fan']:
        for ub in under:
            if fb.overlaps(ub):
                problems.append('KVM front: %s collides with the %s' % (fb.name, ub.name))
            elif fb.z0 < ub.z1:
                gx = max(ub.x0 - fb.x1, fb.x0 - ub.x1)
                fan_under_gap = gx if fan_under_gap is None else min(fan_under_gap, gx)
    # ---------------- KVM deck panel
    deck = Panel('kvm-deck', W, D)
    deck.title = 'KVM deck, 6 mm ply (seen from above, front at the bottom)'
    V = lambda y: D - y
    out = [(0, 0), (W, 0), (W, D)]
    for a, b2, nd in sorted(kvm_notches, reverse=True):
        out += [(b2, D), (b2, D - nd), (a, D - nd), (a, D)]
    out += [(0, D)]
    deck.outline = out
    for x0 in (0.0, W - BT):
        deck.ref.append(RRect(x0 + BT / 2, D / 2, BT, D, 0))
    n = max(2, int(math.ceil((D - 24) / cfg.SHELF['screw_pitch'])) + 1)
    for xs in (BT / 2, W - BT / 2):
        for i in range(n):
            deck.cut(Circle(xs, V(12 + (D - 24) * i / (n - 1)), cfg.SHELF['screw_d'] / 2))
    for xg, ya, yb, front in kgus:
        for q in (1 / 3, 2 / 3):
            deck.cut(Circle(xg, V(ya + (yb - ya) * q), 1.5))
    for (hx, hy, r, what) in deck_holes:
        deck.cut(Circle(hx, V(hy), r))
    for (tx, ty) in ties:
        deck.cut(RRect(tx, V(ty), 5.0, 2.5, 1.0))
    tw_, th_, tp_ = cfg.SHELF['tie_slot']
    for (tx, ty) in tie_pairs:                  # slot pairs across the lead bundle
        for sy in (-1, 1):
            deck.cut(RRect(tx, V(ty + sy * (tp_ / 2 + 4)), th_, tw_, tw_ / 2))
    label(deck, 'POWER BOARD', px0 + pm_w / 2, V(y0 + pm_d / 2), 4.0)
    label(deck, 'INPUTS (FRONT EDGE)', px0 + 50.0, V(y0 + 14.0), 2.5)
    outline_engrave(deck, rect_pts(px0, V(yr), px0 + pm_w, V(y0)))           # placement outlines
    outline_engrave(deck, rect_pts(gx0, V(y0 + G5['d']), gx0 + G5['w'], V(y0)))
    label(deck, 'GS105', gx0 + G5['w'] / 2, V(y0 + G5['d'] / 2), 4.0)
    for bx in [b for b in boxes if b.kind == 'mimas']:
        for i in range(6):
            deck.cut(RRect(bx.x0 + 20 + i * 10, V((bx.y0 + bx.y1) / 2), 3.0, 40.0, 1.5))
    label(deck, 'MEGA-KVM DECK - FRONT', W / 2, V(zone_d / 2 + 2), 3.0)
    for b, ub in zip(bays, bay_u):
        label(deck, 'BAY %d' % (bays.index(b) + 1), W - (ub + b.width / 2), V(D - 10), 3.0)
    # ---------------- KVM front panel
    fp_ = Panel('kvm-front', FW, H)
    fp_.title = 'KVM front panel %dRU (seen from the front)' % K['ru']
    fp_.outline = rect_pts(0, 0, FW, H)
    Vf = lambda z: H - z
    for xc, zc in fans:
        fan_cut(fp_, du + xc, Vf(zc), K['fan'], fs, K['guard'], K['grille_hole'], K['grille_pitch'])
    if js:
        U = lambda xj: du + pcb_x0 + xj
        Vj = lambda yj: K['pcb_top'] + yj
        bz = js['lcd']['bezel']
        fp_.cut(RRect(U(bz['x'] + bz['w'] / 2), Vj(bz['y'] + bz['h'] / 2), bz['w'] + 0.4, bz['h'] + 0.4, 0.5))
        for h in js['holes']:
            fp_.cut(Circle(U(h['x']), Vj(h['y']), h['hole_d'] / 2))
        for l in js['leds']:
            fp_.cut(Circle(U(l['x']), Vj(l['y']), l['hole_d'] / 2))
        for bt in js['buttons']:
            fp_.cut(Circle(U(bt['x']), Vj(bt['y']), bt['hole_d'] / 2))
        for e in js['engrave']:
            label(fp_, e['text'], U(e['x']), Vj(e['y']), 2.4)
        label(fp_, 'RED = POWERED   GREEN = SELECTED', U((js['leds'][0]['x'] + js['leds'][-1]['x']) / 2), Vj(js['board']['h'] - 2.0), 1.8)
    else:
        problems.append('KVM front: %s not found, display group not drawn' % K['front_holes'])
    fp_.cut(RRect(du + rock_x, Vf(rock_z), rw, rh, 0.5))
    label(fp_, 'I', du + rock_x, Vf(rock_z + rh / 2 + 2.2), 2.0)
    label(fp_, 'O', du + rock_x, Vf(rock_z - rh / 2 - 2.2), 2.0)
    label(fp_, 'POWER', du + rock_x, Vf(rock_z - rh / 2 - 5.4), 1.8)
    # Face items in deck x / z (front view) that etching must keep off: fan frames, the
    # display PCB, the rocker with its labels, batten and gusset screws.
    keep_off = [('fan %d' % (i + 1), xc - K['fan'] / 2, zc - K['fan'] / 2, xc + K['fan'] / 2, zc + K['fan'] / 2)
                for i, (xc, zc) in enumerate(fans)]
    keep_off.append(('display PCB', pcb_x0, pcb_z0, pcb_x0 + pcb_w, pcb_z1))
    keep_off.append(('rocker', rock_x - max(rw / 2, 6.0), rock_z - rh / 2 - 7.0,
                     rock_x + max(rw / 2, 6.0), rock_z + rh / 2 + 3.5))
    for xs in (BT / 2, W - BT / 2):
        for z in cfg.FAN_PLATE['batten_screws']:
            keep_off.append(('batten screw', xs - 3, z - 3, xs + 3, z + 3))
    for xg, ya, yb, front in kgus:
        if front:
            keep_off.append(('gusset screws', xg - 3, BT - gk['h'] * 0.7 - 3, xg + 3, BT - gk['h'] * 0.3 + 3))
    etched = []                                 # (what, x0, z0, x1, z1)
    # MEGA-KVM etch and logos: 'column' = stacked under the display PCB (with the
    # rocker left of the fans); otherwise beside the rocker / in the band in front of the deck
    column = K.get('etch_pos') == 'column'
    cx0, cx1 = max(fans_end + 2.0, pcb_x0 - 4.0), W - m
    size = K['text_size']
    if column:
        ex0, ex1 = cx0, cx1
        ez1 = pcb_z0 - 3.0
        ez0 = ez1 - size - 2
    else:
        ex0 = rock_x + rw / 2 + 6.0
        ex1 = W - m
        ez0, ez1 = top + 1.0, pcb_z0 - 2.0
    while size > 5.0 and font.text_width(K['text'], size) > ex1 - ex0 - 2:
        size -= 0.5
    if column:
        tz = (ez0 + ez1) / 2
        label(fp_, K['text'], du + (ex0 + ex1) / 2, Vf(tz), size)
        tw = font.text_width(K['text'], size)
        etched.append((K['text'], (ex0 + ex1 - tw) / 2, tz - size / 2, (ex0 + ex1 + tw) / 2, tz + size / 2))
        etch_where = 'under the display PCB (deck x %.0f-%.0f), %.1f mm letters' % (ex0, ex1, size)
    elif font.text_width(K['text'], size) <= ex1 - ex0 - 2 and ez1 - ez0 > size + 4:
        label(fp_, K['text'], du + (ex0 + ex1) / 2, Vf((ez0 + ez1) / 2), size)
        etch_where = 'beside the rocker (deck x %.0f-%.0f), %.1f mm letters' % (ex0, ex1, size)
    else:
        size = K['text_size']
        label(fp_, K['text'], du + W / 2, Vf(top / 2), size)
        etch_where = 'in the band in front of the deck, %.1f mm letters' % size
    notes.append('KVM front: %s etched %s' % (K['text'], etch_where))
    for xs in (BT / 2, W - BT / 2):
        for z in cfg.FAN_PLATE['batten_screws']:
            fp_.cut(Circle(du + xs, Vf(z), cfg.FAN_PLATE['screw_d'] / 2))
    for xg, ya, yb, front in kgus:
        for z in (BT - gk['h'] * 0.7, BT - gk['h'] * 0.3):
            if front:
                fp_.cut(Circle(du + xg, Vf(z), 1.75))
    logo_notes = []
    col_logos = [nm for nm, wh in K['logos'] if wh == 'column']
    if col_logos:
        # stacked under the etch, between the panel's bottom edge band and the etch; the
        # slots stay left of the right-hand gusset/batten screws
        lx0, lx1 = cx0, min(cx1, W - BT - g.T - 4.0)
        lz1 = (etched[-1][2] if etched else pcb_z0) - 3.0
        lz0 = 2.0
        gap_l = 3.0
        hh_all = (lz1 - lz0 - gap_l * (len(col_logos) - 1)) / len(col_logos)
        z = lz1
        for name in col_logos:
            spec = cfg.LOGOS[name]
            hh = min(spec['h'], hh_all)
            lw = min(spec['w'], lx1 - lx0)
            zc = z - hh / 2
            if hh < 10 or lw < 40:
                notes.append('KVM front: no room for the %s logo slot under the display' % name)
            else:
                logo_notes.append(logos.slot(cfg, fp_, name, du + (lx0 + lx1) / 2, Vf(zc), lw, hh))
                etched.append(('%s logo' % name, (lx0 + lx1) / 2 - lw / 2, zc - hh / 2, (lx0 + lx1) / 2 + lw / 2, zc + hh / 2))
            z -= hh + gap_l
    for name, where in K['logos']:
        if where == 'column':
            continue
        spec = cfg.LOGOS[name]
        hh = min(spec['h'], top - 5.0)
        lw = spec['w']
        if where == 'left':
            x0 = BT + g.T + 8
        else:
            x1 = W - BT - g.T - 2
            x0 = x1 - lw
        if lw < 40:
            notes.append('KVM front: no room for the %s logo slot in the band' % name)
            continue
        logo_notes.append(logos.slot(cfg, fp_, name, du + x0 + lw / 2, Vf(top / 2), lw, hh))
        etched.append(('%s logo' % name, x0, top / 2 - hh / 2, x0 + lw, top / 2 + hh / 2))
    for what, a0, b0, a1, b1 in etched:
        if a0 < 0 or a1 > W or b0 < 0 or b1 > H:
            problems.append('KVM front: the %s etch runs off the face over the deck (x %.0f-%.0f, z %.0f-%.0f)' % (
                what, a0, a1, b0, b1))
        for kn, k0, kz0, k1, kz1 in keep_off:
            if a0 < k1 and k0 < a1 and b0 < kz1 and kz0 < b1:
                problems.append('KVM front: the %s etch (x %.0f-%.0f, z %.0f-%.0f) overlaps the %s' % (
                    what, a0, a1, b0, b1, kn))
    # ---------------- KVM rear plate (seen from the rear)
    rp = Panel('kvm-rear', W, Hr)
    rp.title = 'KVM rear plate (seen from the rear)'
    rp.outline = rect_pts(0, 0, W, Hr)
    Vr = lambda z: Hr - (top + z)          # z above the deck top (bay floor)
    for b, ub in zip(bays, bay_u):
        b.item.draw(rp, ub, Vr)
    npw.draw(rp, u_col, Vr)
    kb = fr.keyboard(cfg, zc=60.0)
    kb.draw(rp, W - rm - kb.width, Vr)
    vu0 = rm + 6.0
    vu1 = W - rm - kb.width - 8.0
    zv0, zv1 = 40.0, Hr - top - 15.0
    if zv1 - zv0 > 15:
        fr.vents('rear vents', vu1 - vu0, zv0, zv1, slot_w=4.0, pitch=9.0).draw(rp, vu0, Vr)
    for xs in (BT / 2, W - BT / 2):
        for z in cfg.FAN_PLATE['batten_screws']:
            rp.cut(Circle(W - xs, Hr - z, cfg.FAN_PLATE['screw_d'] / 2))
    for xg, ya, yb, front in kgus:
        for z in (BT - gk['h'] * 0.7, BT - gk['h'] * 0.3):
            if not front:
                rp.cut(Circle(W - xg, Hr - z, 1.75))
    label(rp, 'MEGA-KVM', 60, Vr(Hr - top - 6.0), 5.0)
    kg = gusset_panel('kvm-gusset', gk['h'], gk['l'], gk['chamfer'], 4, 'KVM gusset (under the deck, glued + screwed)')
    frags = [('bay%d' % (i + 1), fr.standalone(b.item, Hr, Vr)) for i, b in enumerate(bays)]
    frags.append(('kvm-rear-bulkhead-dut_power', fr.standalone(npw, Hr, Vr)))
    probs_fit = []
    return {'H': H, 'D': D, 'Hr': Hr, 'deck': deck, 'front': fp_, 'rear': rp, 'gusset': kg, 'boxes': boxes,
            'fans': fans, 'fan_cross_deck': fan_cross_deck, 'fans_x0': fans_x0, 'notches': kvm_notches,
            'fan_under_gap': fan_under_gap, 'etched': etched, 'etch_where': etch_where, 'zone_d': zone_d, 'pcb_x0': pcb_x0, 'col_x0': col_x0,
            'fans_end': fans_end, 'right_w': right_w, 'width_need': width_need, 'bays': bays, 'bays_w': bays_w,
            'rear_free': rear_free, 'frags': frags, 'logo_notes': logo_notes, 'rock': (rock_x, rock_z),
            'pcb': (pcb_x0, pcb_z0, pcb_w, pcb_h), 'pm': (px0, y0, pm_w, pm_d, pzt), 'gs': (gx0, y0),
            'col': (col_x0, col_x1), 'bay_x0': bay_x0, 'yr': yr}


# ====================================================================== group clearance check
def group_check(g):
    """Fan bodies, gussets, battens and decks of one fan-plate group."""
    cfg = g.cfg
    G = cfg.RACK['group']
    W, BT, RU, top = g.W, g.BT, g.RU, g.top
    rows = []
    items = []
    for f in g.fans:
        items.append(('fan %d (%s)' % (f['i'] + 1, f['where']),
                      Box('fan', f['x0'], f['x1'], 0, g.fspec['thick'], f['z0'], f['z1'])))
    gu = g.gus
    for x in (BT / 2, W - BT / 2):
        items.append(('gusset', Box('gusset', x - g.T / 2, x + g.T / 2, 0, gu['l'], top, top + gu['h'])))
    solids = []
    for k in range(G):
        y0 = g.shelf_y0[k]
        bf = 0.0 if k == 0 else (g.batten_front_other + y0)
        z = k * RU
        solids.append(('shelf %d batten L' % (k + 1), Box('b', 0, BT, bf, y0 + g.D, z, z + BT)))
        solids.append(('shelf %d batten R' % (k + 1), Box('b', W - BT, W, bf, y0 + g.D, z, z + BT)))
        # deck: the notched front band and the solid deck behind it
        xs = [0.0]
        for a, b in g.notches:
            xs += [a, b]
        xs.append(W)
        for i in range(0, len(xs), 2):
            if xs[i + 1] - xs[i] > 0.01:
                solids.append(('shelf %d deck' % (k + 1), Box('d', xs[i], xs[i + 1], y0, y0 + g.ndeff, z + BT, z + top)))
        solids.append(('shelf %d deck' % (k + 1), Box('d', 0, W, y0 + g.ndeff, y0 + g.D, z + BT, z + top)))
    probs = []
    for name, it in items:
        best = None
        for sn, s in solids:
            if name == 'gusset' and sn.startswith('shelf 1 '):
                continue            # it stands on the carrier's own deck/batten
            if it.overlaps(s):
                probs.append('%s collides with %s' % (name, sn))
                continue
            # clearance in the direction that separates them
            dx = max(s.x0 - it.x1, it.x0 - s.x1)
            dy = max(s.y0 - it.y1, it.y0 - s.y1)
            dz = max(s.z0 - it.z1, it.z0 - s.z1)
            c = max(dx, dy, dz)
            if best is None or c < best[0]:
                best = (c, sn, 'x' if c == dx else ('y' if c == dy else 'z'))
        rows.append((name, it, best))
    return rows, probs


# ====================================================================== drawings
def elevation(g, kv, path):
    from .svgout import Drawing
    cfg = g.cfg
    RU, W, FW = g.RU, g.W, cfg.RACK['face_width']
    lay = cfg.RACK['layout']
    slots = []
    z = 0.0
    for u in lay:
        h = kv['H'] if u == 'kvm' else RU
        slots.append((u, z, h))
        z += h
    Htot = z
    depth = cfg.RACK['depth_posts']
    m = 30.0
    side_w = depth + 260.0
    Dw = FW + side_w + 3 * m + 40
    Dh = Htot + 2 * m + 70
    d = Drawing(Dw, Dh, 'MEGA-KVM rack elevation')
    X0 = m + 20
    Zb = m + 30 + Htot             # drawing y of rack z = 0
    Y = lambda zz: Zb - zz
    d.text(m, 14, 'MEGA-KVM rack elevation (%d RU, %.1f mm): front view and side view (front at the left), 1 unit = 1 mm' % (
        round(Htot / RU), Htot), size=6, anchor='start', weight='bold')
    # ---- front view
    opening = cfg.RACK['post_opening']
    cx = X0 + FW / 2
    for s in (-1, 1):
        d.rect(cx + s * opening / 2, Y(-10), cx + s * (opening / 2 + cfg.RACK['post_flange']), Y(Htot + 10),
               fill='#bbbbbb', stroke='#555', sw=0.4)
    for i in range(int(round(Htot / RU)) + 1):
        d.line([(cx - FW / 2 - 8, Y(i * RU)), (cx - FW / 2 - 2, Y(i * RU))], sw=0.3)
        if i < round(Htot / RU):
            d.text(cx - FW / 2 - 12, Y(i * RU + RU / 2) + 1.5, str(i + 1), size=4, anchor='end')
    shelf_no = 0
    group_i = 0
    for k, (u, z0, h) in enumerate(slots):
        if u == 'kvm':
            d.rect(cx - FW / 2, Y(z0), cx + FW / 2, Y(z0 + h), fill='#e8d8a8', stroke='#333', sw=0.5)
            fr_ = cfg.FANS[cfg.KVM['fan']]['bore'] / 2
            for s in kv['front'].cuts:
                if s.kind == 'circle' and s.r < 3.5 and any(
                        math.hypot(s.cx - (g.du + fx), (kv['H'] - s.cy) - fz) < fr_ for fx, fz in kv['fans']):
                    continue                      # grille holes: drawn as the fan circle instead
                bx = s.bbox()
                d.rect(cx - FW / 2 + bx[0], Y(z0 + kv['H'] - bx[1]), cx - FW / 2 + bx[2], Y(z0 + kv['H'] - bx[3]),
                       fill='#ffffff', stroke='#c00', sw=0.25)
            for fx, fz in kv['fans']:
                d.circle(cx - FW / 2 + g.du + fx, Y(z0 + fz), cfg.FANS[cfg.KVM['fan']]['bore'] / 2, stroke='#c00', sw=0.4)
            d.text(cx, Y(z0 + 3), 'KVM UNIT %dRU on slides' % cfg.KVM['ru'], size=4)
            continue
        idx = shelf_no % cfg.RACK['group']
        if idx == 0:
            group_i += 1
            d.rect(cx - FW / 2, Y(z0), cx + FW / 2, Y(z0 + g.FH), fill='#f0e4c8', stroke='#333', sw=0.5)
            for f in g.fans:
                d.circle(cx - FW / 2 + g.du + f['xc'], Y(z0 + f['zc']), g.fspec['bore'] / 2, stroke='#c00', sw=0.5)
                d.rect(cx - FW / 2 + g.du + f['x0'], Y(z0 + f['z0']), cx - FW / 2 + g.du + f['x1'], Y(z0 + f['z1']),
                       fill='none', stroke='#888', sw=0.3, dash='2,1')
            for name, i in cfg.FAN_PLATE['logos']:
                f = g.fans[i]
                sp = cfg.LOGOS[name]
                za, zb = logo_band(g, f)
                zc = (za + zb) / 2
                d.rect(cx - FW / 2 + g.du + f['xc'] - 55, Y(z0 + zc - 12), cx - FW / 2 + g.du + f['xc'] + 55,
                       Y(z0 + zc + 12), fill='#dddddd', stroke='#333', sw=0.3)
                d.text(cx - FW / 2 + g.du + f['xc'], Y(z0 + zc) + 1.5, sp['label'] + ' logo', size=4)
            d.text(cx, Y(z0 + 8), 'FAN PLATE %d (%dRU, on shelf %d, covers shelves %d-%d)' % (
                group_i, cfg.FAN_PLATE['ru'], shelf_no + 1, shelf_no + 1, shelf_no + cfg.RACK['group']), size=4)
        shelf_no += 1
    d.text(cx, Y(Htot) - 10, 'FRONT VIEW', size=6, weight='bold')
    # ---- side view
    S0 = X0 + FW + 2 * m + 40         # drawing x of y = 0 (front post face = plate back face)
    Xs = lambda yy: S0 + yy
    d.rect(Xs(-3), Y(-10), Xs(0), Y(Htot + 10), fill='#bbbbbb', stroke='#555', sw=0.3)
    d.rect(Xs(depth), Y(-10), Xs(depth + 3), Y(Htot + 10), fill='#bbbbbb', stroke='#555', sw=0.3)
    d.text(Xs(0), Y(-10) + 8, 'front posts', size=3.5)
    d.text(Xs(depth), Y(-10) + 8, 'rear posts (%.0f: MEASURE)' % depth, size=3.5)
    shelf_no = 0
    maxD = g.D
    for k, (u, z0, h) in enumerate(slots):
        if u == 'kvm':
            D = kv['D']
            maxD = max(maxD, D)
            d.rect(Xs(0), Y(z0), Xs(D), Y(z0 + g.BT), fill='#c8a070', stroke='#333', sw=0.3)
            d.rect(Xs(0), Y(z0 + g.BT), Xs(D), Y(z0 + g.top), fill='#e8c890', stroke='#333', sw=0.3)
            d.rect(Xs(-g.T), Y(z0), Xs(0), Y(z0 + kv['H']), fill='#e8d8a8', stroke='#333', sw=0.4)
            d.rect(Xs(D), Y(z0), Xs(D + g.T), Y(z0 + kv['Hr']), fill='#e8d8a8', stroke='#333', sw=0.4)
            for b in kv['boxes']:
                if b.name.startswith(('KVM gusset',)) or not b.hard:
                    continue
                d.rect(Xs(b.y0), Y(z0 + b.z0), Xs(b.y1), Y(z0 + b.z1), fill='#9fc79f', stroke='#333', sw=0.2, opacity=0.6)
            d.text(Xs(D / 2), Y(z0 + kv['H'] - 8), 'KVM: fans + display + inputs | GS105, power | Mimas+shield bays', size=3.5)
            d.text(Xs(D + 12), Y(z0 + kv['H'] / 2), 'DUT HDMI, JTAG, KBD, 12V leads, LAN', size=3.5, anchor='start')
            continue
        idx = shelf_no % cfg.RACK['group']
        y0 = 0.0 if idx == 0 else g.setback
        bf = y0 if idx == 0 else y0 + g.batten_front_other
        d.rect(Xs(bf), Y(z0), Xs(y0 + g.D), Y(z0 + g.BT), fill='#c8a070', stroke='#333', sw=0.3)
        d.rect(Xs(y0 + (g.nd if g.notches else 0)), Y(z0 + g.BT), Xs(y0 + g.D), Y(z0 + g.top), fill='#e8c890', stroke='#333', sw=0.3)
        d.rect(Xs(y0), Y(z0 + g.BT), Xs(y0 + g.D), Y(z0 + g.top), fill='none', stroke='#333', sw=0.2, dash='1,1')
        b = g.fp.BOARD
        zb = z0 + g.top + b['standoff']
        d.rect(Xs(y0 + g.by), Y(zb), Xs(y0 + g.by + b['d']), Y(zb + 1.6), fill='#3f8f3f', stroke='#333', sw=0.2)
        d.rect(Xs(y0 + g.by), Y(zb + 1.6), Xs(y0 + g.by + b['d']), Y(zb + 1.6 + b['tallest']), fill='none', stroke='#3f8f3f', sw=0.2, dash='1,1')
        if g.fx is not None:
            fl = g.fp.FLOPPY
            d.rect(Xs(y0 + g.fy), Y(z0 + g.top + fl['spacer']), Xs(y0 + g.fy + fl['d']), Y(z0 + g.top + fl['spacer'] + fl['h']),
                   fill='none', stroke='#777', sw=0.25, dash='2,1')
        c = g.fp.CART64OUT
        d.rect(Xs(y0 + g.by + c['tip_y']), Y(zb + 0.2), Xs(y0 + g.by + c['tip_y'] + 97), Y(zb + 1.8), fill='#5f7fbf', stroke='#333', sw=0.2)
        sb = g.cfg.SHELF['strain_bar']
        d.rect(Xs(y0 + g.D - sb['from_rear'] - g.T / 2), Y(z0 + g.top), Xs(y0 + g.D - sb['from_rear'] + g.T / 2),
               Y(z0 + g.top + sb['h']), fill='#e8c890', stroke='#333', sw=0.2)
        if idx == 0:
            d.rect(Xs(-g.T), Y(z0), Xs(0), Y(z0 + g.FH), fill='#f0e4c8', stroke='#333', sw=0.4)
            for f in g.fans:
                d.rect(Xs(0), Y(z0 + f['z0']), Xs(g.fspec['thick']), Y(z0 + f['z1']), fill='#b0b0e0', stroke='#333',
                       sw=0.2, opacity=0.5)
            gu = g.gus
            d.line([(Xs(0), Y(z0 + g.top + gu['h'])), (Xs(gu['l']), Y(z0 + g.top)), (Xs(0), Y(z0 + g.top)),
                    (Xs(0), Y(z0 + g.top + gu['h']))], stroke='#a05000', sw=0.4)
        d.text(Xs(y0 + g.D + 4), Y(z0 + 18), 'shelf %d' % (shelf_no + 1), size=3.5, anchor='start')
        shelf_no += 1
    # cable loop zone
    d.rect(Xs(maxD + 30), Y(0), Xs(depth - 5), Y(Htot), fill='#ffe0e0', stroke='#c66', sw=0.3, opacity=0.5, dash='3,2')
    d.text(Xs((maxD + 30 + depth - 5) / 2), Y(Htot / 2) - 6, 'CABLE LOOP ZONE', size=5, weight='bold')
    d.text(Xs((maxD + 30 + depth - 5) / 2), Y(Htot / 2) + 2, 'slack >= slide travel', size=3.5)
    d.text(Xs((maxD + 30 + depth - 5) / 2), Y(Htot / 2) + 7, '(~%.0f mm per shelf)' % g.D, size=3.5)
    d.text(Xs(depth / 2), Y(Htot) - 10, 'SIDE VIEW (front at the left)', size=6, weight='bold')
    notes = ['Shelves: 6 mm deck on 25 x 25 battens; MEGA65 board (green), floppy (dashed), Cart64out (blue), strain bar at the rear.',
             'Fan plates (%dRU, %d x %d mm fans, staggered) screw to the front ends of the bottom shelf of each group; gusset in brown.' % (
                 cfg.FAN_PLATE['ru'], cfg.FAN_PLATE['count'], cfg.FAN_PLATE['fan']),
             'Fan clearance mode: %s.' % (('notch (decks notched %.0f mm deep; non-carrier battens start %.0f mm back)' % (g.nd, g.batten_front_other))
                                          if g.mode == 'notch' else ('setback %.0f mm' % g.setback))]
    for i, n in enumerate(notes):
        d.text(m, Dh - 22 + i * 6, n, size=3.8, anchor='start')
    d.save(path)


# ====================================================================== main entry
def build(cfg, boards, fp, log=print):
    g = Geo(cfg, fp)
    problems, notes = [], []
    deck = shelf_deck(g)
    bar = strain_bar(g)
    plate, logo_notes = fan_plate(g)
    groups = cfg.RACK['layout'].count('shelf') // cfg.RACK['group']
    gus = gusset_panel('fan-gusset', g.gus['h'], g.gus['l'], g.gus['chamfer'], 2 * max(groups, 1),
                       'fan-plate gusset (stands on the carrier deck over a batten)')
    kv = build_kvm(g, boards, problems, notes)
    rows, gprobs = group_check(g)
    problems += gprobs
    # shelf height checks
    b, fl = fp.BOARD, fp.FLOPPY
    lim = g.clear_mid - cfg.SHELF['clear_top']
    lim_e = g.clear_edge - cfg.SHELF['clear_top']
    hrows = [('MEGA65 board + tallest part', b['standoff'] + 1.6 + b['tallest'], lim, 'IEC socket, see below')]
    if g.fx is not None:
        hrows.append(('floppy drive on its spacers', fl['spacer'] + fl['h'], lim, 'rugged-case 5 mm nylon spacer'))
    hrows.append(('strain-relief bar', cfg.SHELF['strain_bar']['h'], lim, ''))
    hrows.append(('fan-plate gusset', g.gus['h'], lim, 'carrier shelf only'))
    for name, hh, L, note in hrows:
        if hh > L:
            problems.append('%s: %.1f mm tall, only %.1f mm under the next deck' % (name, hh, L))
    # tall parts vs the next shelf: its deck (between the battens) and its battens (edge strips)
    tall = []
    parts_ = [(tp['name'], g.bx + tp['x0'], g.bx + tp['x1'], b['standoff'] + 1.6 + tp['h'], tp['src'])
              for tp in getattr(fp, 'TALL_PARTS', [])]
    parts_.append(('MEGA65 board outline', g.bx, g.bx + b['w'], b['standoff'] + 1.6, 'DIM drawing'))
    if g.fx is not None:
        parts_.append(('floppy drive', g.fx - fl['w'] / 2, g.fx + fl['w'] / 2, fl['spacer'] + fl['h'],
                       'standard 3.5 in drive on 5 mm spacers'))
    for name, x0, x1, hh, src in parts_:
        under = x0 < g.BT or x1 > g.W - g.BT
        side = min(x0 - g.BT, (g.W - g.BT) - x1)            # lateral gap to the nearer batten (<0: under it)
        L = lim_e if under else lim
        tall.append((name, x0, x1, hh, g.clear_mid - hh, g.clear_edge - hh, side, under, src))
        if hh > L:
            problems.append('%s: %.1f mm above the deck %s (limit %.1f)' % (
                name, hh, 'UNDER a batten of the next shelf' if under else 'under the next deck', L))
        elif under and hh > lim_e:
            problems.append('%s reaches under a batten of the next shelf' % name)
    if g.bx < g.BT or g.bx + b['w'] > g.W - g.BT:
        problems.append('MEGA65 board outline is not inside the between-battens zone')
    # horizontal checks on the shelf
    inner = g.W - 2 * g.BT
    if g.span > inner:
        problems.append('MEGA65 board + floppy (%.1f mm) wider than the space between the battens (%.1f mm)' % (g.span, inner))
    c = fp.CART64OUT
    cart_end = g.by + c['tip_y'] + 97.0
    bar_y = g.D - cfg.SHELF['strain_bar']['from_rear'] - g.T / 2
    if cart_end > bar_y - 2:
        problems.append('Cart64out rear edge (y %.1f) reaches the strain-relief bar (y %.1f)' % (cart_end, bar_y))
    if g.notches and g.by < g.nd + 2:
        problems.append('front allowance %.0f mm < notch depth %.0f mm + 2' % (g.by, g.nd))
    if cfg.SHELF['fan_clearance'] == 'setback' and g.notches:
        problems.append('set-back mode but the shelf decks still need fan notches')
    fl_end = (g.fy + fl['d']) if g.fx is not None else 0
    for (x, yr, w, h) in cfg.SHELF['cable_slots']:
        y = g.D - yr
        sl = (x - w / 2 - 9, y - h / 2, x + w / 2 + 9, y + h / 2)
        cx0 = g.bx + b['port_x'] - 31.0
        cart = (cx0, g.by + c['tip_y'], cx0 + 62, g.by + c['tip_y'] + 97)
        brd = (g.bx, g.by, g.bx + b['w'], g.by + b['d'])
        flp = ((g.fx - fl['w'] / 2, g.fy, g.fx + fl['w'] / 2, fl_end) if g.fx is not None else None)
        for nm, r in (('Cart64out', cart), ('MEGA65 board', brd), ('floppy', flp)):
            if r and not (sl[2] <= r[0] or r[2] <= sl[0] or sl[3] <= r[1] or r[3] <= sl[1]):
                problems.append('cable slot at x %.0f overlaps the %s' % (x, nm))
        if sl[0] < g.BT or sl[2] > g.W - g.BT:
            problems.append('cable slot at x %.0f reaches over a batten' % x)
    # KVM fit check
    from . import layout
    interior = (0.0, g.W, -1.0, kv['D'], 0.0, kv['H'])   # floor 0: the input board may drop into a deck notch
    kprobs, kclear = layout.check([bx for bx in kv['boxes'] if bx.inside], interior,
                                  [('power board', 'input plugs (from above)')])   # the plugs go into the board's connectors
    problems += ['KVM: ' + p for p in kprobs]
    for (hx, hy, r) in [(s.cx, kv['D'] - s.cy, s.r) for s in kv['deck'].cuts if s.kind == 'circle' and s.r > 1.6]:
        for gb in [bx for bx in kv['boxes'] if bx.name == 'KVM gusset']:
            if gb.x0 - r < hx < gb.x1 + r and gb.y0 - r < hy < gb.y1 + r:
                problems.append('KVM deck: a hole at (%.1f, %.1f) lands on an under-deck gusset' % (hx, hy))
    parts = [deck, bar, plate, gus, kv['front'], kv['deck'], kv['rear'], kv['gusset']]
    return {'geo': g, 'kvm': kv, 'parts': parts, 'problems': problems, 'notes': notes, 'group_rows': rows,
            'heights': hrows, 'tall': tall, 'lim': lim, 'lim_e': lim_e, 'logo_notes': logo_notes + kv['logo_notes'],
            'kclear': kclear, 'cart_end': cart_end, 'bar_y': bar_y}
