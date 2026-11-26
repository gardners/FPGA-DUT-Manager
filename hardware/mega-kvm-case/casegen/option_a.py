"""Option A: stand-alone laser-cut 1RU box with finger joints.

Panels: base (fingers on all edges), front, rear, left and right walls
(fingers to the base and at the vertical corners), and a removable plain
lid held by M3 T-slot screws in the walls' top edges.

Rear = DUT face (the two bays, flush with the shields' rear edges), plus
whatever fits beside them: power inputs, Ethernet bulkhead + DUT power
leads, physical keyboard. What does not fit goes onto the right side wall
near the rear. Front = LCD / LEDs / buttons / rocker (0050) and the logo.
Inside, seen from above with the front at the bottom: the bays against the
rear wall; the GS105 and the power main board on the Mimas RJ45 side
(owner 2026-11-27: the switch sits on the RJ45 side of the boards); fans on
the left wall at the front; the front-panel group at the front right.
"""
from . import bays as baymod
from . import fragments as fr
from . import joints
from .geom import Circle, RRect, Panel, rect_pts
from .layout import Box


def place_row(items, u_start, u_end, gap):
    placed, left = [], []
    u = u_start
    for it in items:
        if u + it.width <= u_end + 1e-6:
            placed.append((it, u))
            u += it.width + gap
        else:
            left.append(it)
    return placed, left, u


def find_tslot(panel, u_nominal, depth, halfw, lo, hi):
    """Nearest u to u_nominal where a T-slot (notch + nut pocket) clears the cut-outs."""
    def clear(u):
        if u - halfw < lo or u + halfw > hi:
            return False
        for s in panel.cuts:
            b = s.bbox()
            if b[1] < depth + 2 and b[0] < u + halfw + 1.5 and b[2] > u - halfw - 1.5:
                return False
        return True
    for k in range(0, 400):
        for u in (u_nominal + k * 0.5, u_nominal - k * 0.5):
            if clear(u):
                return u
    return None


def build(cfg, boards, log):
    t = cfg.T
    A = cfg.CASE_A
    H, W = A['height'], A['width']
    hw = H - t                       # wall height (the lid sits on top)
    Hi = H - 2 * t                   # interior height
    zf = t                           # interior floor (outer z)
    V = lambda z: hw - (zf + z)      # wall panels: height above the floor -> v
    mg = A['margin']
    M = cfg.MIMAS
    G = cfg.GS105
    F = cfg.FAN
    res = {'option': 'A', 'panels': [], 'fragments': [], 'boxes': [], 'problems': [], 'notes': []}
    notes, boxes, problems = res['notes'], res['boxes'], res['problems']

    # ---------------------------------------------------------- rear panel row (seen from outside)
    bays = baymod.make_bays(cfg, 0.0, ztop=Hi)
    bay_gap = A['bay_gap']
    bays_w = sum(b.width for b in bays) + bay_gap * (len(bays) - 1)
    power = fr.power_inputs(cfg, boards.get('inputs'), bottom_z=0.0)
    u_lo, u_hi = t + mg, W - t - mg
    u_bays = u_hi - bays_w
    gap = 3.0
    if u_bays < u_lo:
        problems.append('rear panel: the %d bays need %.1f mm, only %.1f inside' % (len(bays), bays_w, u_hi - u_lo))
    optional = {'power_inputs': power,
                'bulkhead': fr.net_and_power(cfg) if 'dut_power' in A['rear_order'] else fr.bulkhead(cfg),
                'dut_power': None, 'keyboard': fr.keyboard(cfg), 'recess': fr.recess(cfg)}
    order = [optional[k] for k in A['rear_order'] if optional.get(k) is not None]
    placed, spill, u_end = place_row(order, u_lo, u_bays - gap, gap)
    rear_items = list(placed)
    bay_u = []
    u = u_bays
    for b in bays:
        rear_items.append((b.item, u))
        bay_u.append(u)
        u += b.width + bay_gap
    free_rear = (u_bays - gap) - (u_end - gap if placed else u_lo)
    notes.append('rear panel: bays %.1f mm (%d x %.1f + gap); beside them %s; %.1f mm left over' % (
        bays_w, len(bays), bays[0].width, ', '.join(it.title for it, _ in placed) or 'nothing', max(free_rear, 0)))
    for it in spill:
        notes.append('rear panel: no room for %s (%.0f mm) -> %s' % (
            it.title, it.width, 'right side wall' if A['side_spill'] else 'NOT PLACED'))

    # ---------------------------------------------------------- front row and the RJ45-side zone
    group = fr.front_group(cfg, Hi)
    logo = fr.logo(cfg, Hi)
    side_d = max([it.depth for it in spill] + [0.0]) if A['side_spill'] else 0.0
    u_g = W - t - mg - group.width
    x_fan0 = t + F['wall_gap']
    x_g0 = x_fan0 + F['thick'] + 3.0
    pm = boards.get('main')
    pm_w, pm_d = (pm['w'], pm['h']) if pm else (cfg.POWER_MAIN['w'], cfg.POWER_MAIN['d'])
    y_g0 = t + 3.0
    x_pm0 = x_g0 + G['w'] + 6.0
    x_pm1 = x_pm0 + pm_w
    over_group = x_pm1 > u_g
    y_pm0 = t + (group.depth + 3.0 if over_group else 3.0)
    yf = max(y_g0 + G['d'], y_pm0 + pm_d)
    sb = bays[0].setback
    D_need = yf + M['rj45_plug_clear'] + M['d'] + sb + t
    # side wall items need room between the front group and the rear-strip items
    rear_depth = max([it.depth for it, _ in placed] + [0.0])
    # the tuck-away recess is optional ("if space"): it never makes the box deeper
    must = [it for it in spill if it.name != 'recess']
    side_len = sum(it.width + 3.0 for it in must) if A['side_spill'] else 0.0
    D_side = t + group.depth + 3.0 + side_len + rear_depth + 3.0 + t
    D = A['depth'] or max(D_need, D_side)
    D = float(round(D + 0.49))
    res['size'] = (W, D, H)
    notes.append('depth %d mm: front zone %.0f (GS105 %.0f deep, power board %.0f behind the %.0f mm front group) + '
                 'RJ45 patch %.0f + Mimas %.0f; side-wall items need %.0f' % (
                     D, yf - t, G['d'], pm_d, group.depth, M['rj45_plug_clear'], M['d'], D_side))

    Xr = lambda u: W - u            # rear-view u -> X
    base_holes = []
    mimas_rects = []
    for b, ub in zip(bays, bay_u):
        for (name, a0, a1, e0, e1, z0, z1, kind, hard) in b.boxes:
            boxes.append(Box(name, Xr(ub + a0 - b.my_min), Xr(ub + a1 - b.my_min), D - t - e0, D - t - e1,
                             zf + z0, zf + z1, kind, hard))
            if name.startswith('Mimas'):
                mimas_rects.append(boxes[-1])
        for (a, e, r, what) in b.holes:
            base_holes.append((Xr(ub + a - b.my_min), D - t - e, r, what))
    for it, u0 in placed:
        boxes.append(Box('input board' if it is power else it.name, Xr(u0), Xr(u0 + it.width), D - t - it.depth, D - t,
                         zf + it.z[0], zf + it.z[1], 'inputs' if it is power else 'item'))

    # GS105, power main board, front group
    boxes.append(Box('GS105', x_g0, x_g0 + G['w'], y_g0, y_g0 + G['d'], zf, zf + G['h'], 'gs105'))
    ties = []
    for yy in (y_g0 + G['d'] * 0.25, y_g0 + G['d'] * 0.75):
        ties += [(x_g0 - 2.5, yy), (x_g0 + G['w'] + 2.5, yy)]
    pm_z0 = zf + cfg.POWER_MAIN['standoff']
    y_pm1 = y_pm0 + pm_d
    boxes.append(Box('power main board', x_pm0, x_pm1, y_pm0, y_pm1, pm_z0, pm_z0 + 1.6 + cfg.POWER_MAIN['tallest'], 'power'))
    if pm:
        # the terminal edge (KiCad y = 0) faces the Mimas boards / rear
        for ref, f in pm['fp'].items():
            if ref.startswith('H'):
                base_holes.append((x_pm0 + f['x'], y_pm1 - f['y'], 1.7, 'power main'))
    boxes.append(Box('front panel group', u_g, u_g + group.width, t, t + group.depth, zf + group.z[0], zf + group.z[1], 'front'))
    front_items = [(logo, x_g0 + 2.0), (group, u_g)]
    vent_u0 = x_g0 + 2.0 + logo.width + 6.0
    vent_w = u_g - 6.0 - vent_u0
    if vent_w > 20:
        front_items.append((fr.vents('front vents', vent_w, 6.0, Hi - 6.0), vent_u0))

    # right wall: spilled rear items, from the rear strip forwards
    right_items = []
    y_hi = D - t - rear_depth - 3.0
    y_lo = t + group.depth + 3.0
    u = y_hi
    if A['side_spill'] and spill:
        for it in spill:
            u0 = u - it.width
            if it.name == 'recess' and u0 < y_lo:
                notes.append('no room for the DC-lead recess on the right wall either (needs %.0f mm, %.0f left): '
                             'not placed' % (it.width, u - y_lo))
                continue
            right_items.append((it, u0))
            nm = ('input board' if it is power else it.name) + ' (side)'
            if it is power:
                boxes.append(Box(nm, W - t - it.depth, W - t, u0, u0 + it.width, zf + it.z[0], zf + it.z[1], 'inputs'))
            else:
                boxes.append(Box(nm, W - t - it.depth, W - t, u0, u0 + it.width, zf + it.z[0], zf + it.z[1], 'item'))
            u = u0 - 3.0
        if u + 3.0 < y_lo:
            problems.append('right wall: the side items do not fit between the front group and the rear')
    if u - 3.0 - y_lo > 20:
        right_items.append((fr.vents('right vents', u - 3.0 - y_lo, 6.0, Hi - 6.0), y_lo))

    # left wall: fans at the front (in front of the bays)
    fan_zc = Hi / 2
    fan_items = []
    for i in range(F['count']):
        fan = fr.fan_wall(cfg, fan_zc)
        y0 = t + 3.0 + i * (fan.width + 4.0)
        fan_items.append((fan, y0))
        boxes.append(Box('fan %d' % (i + 1), x_fan0, x_fan0 + F['thick'], y0 + 2, y0 + 2 + F['size'],
                         zf + fan_zc - F['size'] / 2, zf + fan_zc + F['size'] / 2, 'fan', inside=False))
    left_items = [(fan, D - (y0 + fan.width)) for fan, y0 in fan_items]   # left wall u = D - Y
    lv_u0 = D - (fan_items[-1][1] + fan_items[-1][0].width) + 0.0
    if F['size'] > Hi:
        notes.append('fans: %.0f mm > %.2f mm interior, so they sit in slots in the base and the lid (%.2f mm into each)'
                     % (F['size'], Hi, (F['size'] - Hi) / 2))
    if Hi < cfg.FRONT['lcd']['module'][1]:
        problems.append('LCD module %.0f mm taller than the %.2f mm interior' % (cfg.FRONT['lcd']['module'][1], Hi))

    # ---------------------------------------------------------- panels
    fw = cfg.FINGER_W
    TS = A['tslot']

    def wall(name, width, phase, items, n_screws, title):
        p = Panel(name, width, hw)
        p.title = title
        for it, u0 in items:
            it.draw(p, u0, V)
        notches, nuts = [], []
        for i in range(n_screws):
            un = width * (i + 0.5) / n_screws
            us = find_tslot(p, un, TS['depth'], TS['nut_w'] / 2, t + 6, width - t - 6)
            if us is None:
                problems.append('%s: no room for T-slot %d' % (name, i + 1))
                continue
            notches.append((us, TS['screw_w'], TS['depth']))
            nuts.append(us)
        p.outline = joints.outline(width, hw, ('plain', notches), ('fingers', phase, t), ('fingers', 'B', t),
                                   ('fingers', phase, t), fw)
        for us in nuts:
            p.cut(RRect(us, TS['nut_depth'], TS['nut_w'], TS['nut_t'], 0))
        p.tslots = nuts
        side_in = 0.0 if phase == 'A' else t
        for s in p.cuts:
            b = s.bbox()
            if b[0] < t + cfg.HOLE_EDGE_MIN - 1e-6 or b[2] > width - t - cfg.HOLE_EDGE_MIN + 1e-6 \
                    or b[3] > hw - t - 0.8 + 1e-6 or b[1] < 0.5:
                problems.append('%s: a cut-out at u %.1f-%.1f v %.1f-%.1f is in or near the joint zone'
                                % (name, b[0], b[2], b[1], b[3]))
                break
        return p

    rear = wall('A-rear', W, 'A', rear_items, A['lid_screws']['rear'], 'A rear panel (seen from outside)')
    front = wall('A-front', W, 'A', front_items, A['lid_screws']['front'], 'A front panel (seen from outside)')
    right = wall('A-right', D, 'B', right_items, A['lid_screws']['side'], 'A right side (seen from outside, rear at the right)')
    lv_w = D - t - 8 - lv_u0 - 120
    li = list(left_items)
    if lv_w > 20:
        li.append((fr.vents('left vents', lv_w, 6.0, Hi - 6.0), lv_u0 + 4))
    left = wall('A-left', D, 'B', li, A['lid_screws']['side'], 'A left side (seen from outside, front at the right)')

    # base, seen from above (inside): u = X, v = D - Y
    base = Panel('A-base', W, D)
    base.title = 'A base (seen from above, inside face; front at the bottom)'
    base.outline = joints.outline(W, D, ('fingers', 'A', t), ('fingers', 'A', t), ('fingers', 'A', t), ('fingers', 'A', t), fw)
    for x, y, r, _ in base_holes:
        base.cut(Circle(x, D - y, r))
    for x, y in ties:
        base.cut(RRect(x, D - y, 2.5, 5.0, 1.0))
    fan_slots = [RRect(x_fan0 + F['thick'] / 2, D - (y0 + 2 + F['size'] / 2), F['thick'] + 1.0, F['size'] + 1.0, 0.5)
                 for fan, y0 in fan_items]
    if F['size'] > Hi:
        for s in fan_slots:
            base.cut(s)
    for bx in mimas_rects:              # intake slots under each Mimas
        for i in range(6):
            base.cut(RRect(bx.x0 + 20 + i * 10, D - (bx.y0 + bx.y1) / 2, 3.0, 40.0, 1.5))
    fr.label(base, 'MEGA-KVM BASE - INSIDE FACE UP - FRONT', W / 2, D - 12, 3.0)

    # lid, seen from above (outside): u = X, v = D - Y
    lid = Panel('A-lid', W, D)
    lid.title = 'A lid (seen from above; front at the bottom)'
    lid.outline = rect_pts(0, 0, W, D)
    for us in front.tslots:
        lid.cut(Circle(us, D - t / 2, 1.7))
    for us in rear.tslots:
        lid.cut(Circle(W - us, t / 2, 1.7))
    for us in right.tslots:
        lid.cut(Circle(W - t / 2, D - us, 1.7))
    for us in left.tslots:
        lid.cut(Circle(t / 2, us, 1.7))
    if F['size'] > Hi:
        for s in fan_slots:
            lid.cut(s)
    for bx in mimas_rects:
        for i in range(7):
            lid.cut(RRect(bx.x0 + 15 + i * 10, D - (bx.y0 + bx.y1) / 2, 3.0, 60.0, 1.5))
    fr.label(lid, 'MEGA-KVM', W * 0.66, D - (y_g0 + 45), 16.0)
    fr.label(lid, 'MEGA65 TEST KVM - 8 DUTS', W * 0.66, D - (y_g0 + 45) + 14, 4.0)
    for i, (b, ub) in enumerate(zip(bays, bay_u)):
        fr.label(lid, 'BAY %d  DUT %d-%d' % (i + 1, i * 4 + 1, i * 4 + 4), W - (ub + b.width / 2), 10.0, 3.0)

    res['panels'] = [base, lid, front, rear, left, right]
    res['fragments'] = [('bay%d' % (i + 1), fr.standalone(b.item, hw, V)) for i, b in enumerate(bays)]
    res['fragments'].append(('front-panel', fr.standalone(group, hw, V)))
    res['fragments'].append(('rear-power', fr.standalone(power, hw, V)))
    for it, _ in placed:
        if it is not power:
            res['fragments'].append(('rear-' + it.name.replace('+', '-'), fr.standalone(it, hw, V)))
    res['interior'] = (t, W - t, t, D - t, t, H - t)
    res['allowed'] = []
    res['walls_t'] = t
    res['spill'] = [it.name for it in spill]
    res['rear_free'] = free_rear
    res['bays'] = bays
    res['stack_top'] = zf + bays[0].info['stack_top']
    return res
