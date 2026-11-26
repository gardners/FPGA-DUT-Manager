"""Option B: panels and a mounting plate for a gutted Cisco Catalyst 3560G-48TS.

All connectors on the FRONT except power: the front panel carries the two
DUT bays (the Mimas HDMI edges and the shields' rear edges face the front),
the LCD / LEDs / buttons / rocker, the Ethernet bulkhead and the physical
keyboard, as far as they fit. At the rear, cover plates over the carcass's
IEC inlet and DC/RPS cut-outs carry the banana / PCIe 8-pin / Molex inputs,
and a fan plate goes over a rear vent opening. Inside, a mounting plate
(bare PCB or laser-cut) sits on the carcass floor's standoffs and carries the
Mimas boards, keyboard sub-boards and shield supports, and behind them (owner
2026-11-27) the GS105 and the power main board.
"""
from . import bays as baymod
from . import fragments as fr
from .geom import Circle, RRect, Panel, rect_pts
from .layout import Box
from .option_a import place_row


def build(cfg, boards, log):
    B = cfg.CASE_B
    W, D, H = B['outer']
    s = B['steel']
    t = cfg.T
    M = cfg.MIMAS
    G = cfg.GS105
    F = cfg.FAN
    res = {'option': 'B', 'panels': [], 'fragments': [], 'boxes': [], 'problems': [], 'notes': []}
    notes, boxes, problems = res['notes'], res['boxes'], res['problems']
    res['size'] = (W, D, H)
    zf = s
    Hi = H - 2 * s
    fpw, fph = B['front_panel']
    V = lambda z: fph - z                 # front panel: bottom edge on the carcass floor
    x_fp0 = (W - fpw) / 2                 # front panel u -> X
    lift = B['standoff_h'] + B['plate_t']  # the bays stand on the plate

    # ---------------------------------------------------------- front panel row
    bays = baymod.make_bays(cfg, lift, ztop=fph)
    group = fr.front_group(cfg, Hi)
    optional = {'group': group, 'bulkhead': fr.bulkhead(cfg), 'keyboard': fr.keyboard(cfg), 'dut_power': fr.dut_power(cfg)}
    fix_u = [u for (u, z) in B['front_fix']]
    u_lo = min(fix_u) + 4.0 if fix_u else 5.0
    u_hi = max(fix_u) - 4.0 if fix_u else fpw - 5.0
    gap = 3.0
    items = []
    u = u_lo
    bay_u = []
    for b in bays:
        items.append((b.item, u))
        bay_u.append(u)
        u += b.width + B['bay_gap']
    u += gap - B['bay_gap']
    placed, left_over, u_end = place_row([optional[k] for k in B['front_order']], u, u_hi, gap)
    items += placed
    free = u_hi - (u_end - gap if placed else u)
    notes.append('front panel: %.1f mm usable between the fixing holes; bays %.1f; %s placed; %.1f mm left' % (
        u_hi - u_lo, u - u_lo - gap, ', '.join(it.name for it, _ in placed) or 'nothing else', max(free, 0)))
    for it in left_over:
        problems.append('front panel: NO ROOM for %s (%.0f mm)' % (it.title, it.width))
    if left_over:
        notes.append('front panel: %.0f mm short for %s' % (
            sum(it.width + gap for it in left_over) - max(free, 0), ', '.join(it.name for it in left_over)))

    front = Panel('B-front', fpw, fph)
    front.title = 'B front panel (seen from outside)'
    front.outline = rect_pts(0, 0, fpw, fph)
    for it, u0 in items:
        it.draw(front, u0, V)
    for (u, z) in B['front_fix']:
        front.cut(Circle(u, V(z), 1.7))
    for c in front.cuts:
        bb = c.bbox()
        if bb[1] < cfg.HOLE_EDGE_MIN or bb[3] > fph - cfg.HOLE_EDGE_MIN:
            problems.append('front panel: a cut-out at u %.1f is within %.1f mm of the top/bottom edge'
                            % ((bb[0] + bb[2]) / 2, cfg.HOLE_EDGE_MIN))
            break

    # ---------------------------------------------------------- inside
    plate_z = zf + B['standoff_h']
    plate_top = plate_z + B['plate_t']
    X = lambda u: x_fp0 + u
    holes, mimas_rects = [], []
    for b, ub in zip(bays, bay_u):
        for (name, a0, a1, e0, e1, z0, z1, kind, hard) in b.boxes:
            boxes.append(Box(name, X(ub + a0 - b.my_min), X(ub + a1 - b.my_min), t + e0, t + e1,
                             plate_top + z0, plate_top + z1, kind, hard))
            if name.startswith('Mimas') or name.startswith('shield') or name.startswith('kbd') or name.startswith('DUT'):
                mimas_rects.append(boxes[-1])
        for (a, e, r, what) in b.holes:
            holes.append((X(ub + a - b.my_min), t + e, r, what))
    for it, u0 in placed:
        if it.depth > 0:
            boxes.append(Box(it.name, X(u0), X(u0 + it.width), t, t + it.depth, zf + it.z[0], zf + it.z[1],
                             'front' if it is group else 'item'))

    # behind the boards: GS105 and the power main board side by side
    pm = boards.get('main')
    pm_w, pm_d = (pm['w'], pm['h']) if pm else (cfg.POWER_MAIN['w'], cfg.POWER_MAIN['d'])
    y_back = max(bx.y1 for bx in mimas_rects)
    y_rj = max(bx.y1 for bx in boxes if bx.name.startswith('RJ45'))
    y_g0 = max(y_back, y_rj) + 3.0
    x_g0 = X(bay_u[0]) + 10.0
    boxes.append(Box('GS105', x_g0, x_g0 + G['w'], y_g0, y_g0 + G['d'], plate_top, plate_top + G['h'], 'gs105'))
    ties = []
    for yy in (y_g0 + G['d'] * 0.25, y_g0 + G['d'] * 0.75):
        ties += [(x_g0 - 2.5, yy), (x_g0 + G['w'] + 2.5, yy)]
    x_pm0 = x_g0 + G['w'] + 10.0
    y_pm0 = y_g0
    if x_pm0 + pm_w > W - s - 2:
        x_pm0, y_pm0 = x_g0, y_g0 + G['d'] + 6.0
    y_pm1 = y_pm0 + pm_d
    pm_z0 = plate_top + cfg.POWER_MAIN['standoff']
    boxes.append(Box('power main board', x_pm0, x_pm0 + pm_w, y_pm0, y_pm1, pm_z0, pm_z0 + 1.6 + cfg.POWER_MAIN['tallest'], 'power'))
    if pm:
        for ref, f in pm['fp'].items():
            if ref.startswith('H'):
                holes.append((x_pm0 + f['x'], y_pm1 - f['y'], 1.7, 'power main'))
    # rear: openings are given as X from the inner left wall seen from the FRONT
    xi = s + (B['iec_opening'][0] + B['rps_opening'][0]) / 2
    piw = cfg.POWER_IN['width_override'] or (boards['inputs']['w'] if boards.get('inputs') else cfg.POWER_IN['w'])
    boxes.append(Box('input board / leads', xi - piw / 2, xi + piw / 2, D - s - 30, D - s, zf, zf + cfg.POWER_IN['h'], 'inputs'))
    fo = B['fan_opening']
    boxes.append(Box('fans (rear plate)', s + fo[0] - F['count'] * 21, s + fo[0] + F['count'] * 21,
                     D - s - F['thick'] - 2, D - s, zf + fo[1] - 20, zf + fo[1] + 20, 'fan'))

    # ---------------------------------------------------------- mounting plate
    pmg = B['plate_margin']
    rects = [(bx.x0, bx.x1, bx.y0, bx.y1) for bx in mimas_rects if not bx.name.startswith('DUT')]
    rects += [(x_g0, x_g0 + G['w'], y_g0, y_g0 + G['d']), (x_pm0, x_pm0 + pm_w, y_pm0, y_pm1)]
    px0 = max(min(r[0] for r in rects) - pmg, s + 1.0)
    px1 = min(max(r[1] for r in rects) + pmg, W - s - 1.0)
    py0 = max(min(r[2] for r in rects) - pmg, t + 0.5)   # behind the front panel
    py1 = max(r[3] for r in rects) + pmg
    plate = Panel('B-plate', px1 - px0, py1 - py0)
    plate.title = 'B mounting plate (seen from above, front at the bottom)'
    plate.outline = rect_pts(0, 0, px1 - px0, py1 - py0)
    P = lambda x, y: (x - px0, py1 - y)
    for x, y, r, what in holes:
        plate.cut(Circle(*P(x, y), r))
    for x, y in ties:
        u, v = P(x, y)
        plate.cut(RRect(u, v, 2.5, 5.0, 1.0))
    used = 0
    for (x, y) in B['standoffs']:
        x = x + s
        if px0 + 4 < x < px1 - 4 and py0 + 4 < y < py1 - 4:
            plate.cut(Circle(*P(x, y), B['standoff_hole'] / 2))
            fr.label(plate, 'S', P(x, y)[0] + 4.5, P(x, y)[1], 2.0)
            used += 1
            for hx, hy, hr, what in holes:
                if ((hx - x) ** 2 + (hy - y) ** 2) ** 0.5 < hr + B['standoff_hole'] / 2 + 3:
                    problems.append('plate: carcass standoff (%.0f, %.0f) is too close to a %s hole' % (x, y, what))
            for r in rects:
                if r[0] - 3 < x < r[1] + 3 and r[2] - 3 < y < r[3] + 3:
                    notes.append('plate: carcass standoff at (%.0f, %.0f) is under a board: use a countersunk '
                                 'screw there' % (x, y))
                    break
    if used < 4:
        problems.append('plate: only %d carcass standoffs fall inside the plate (positions are placeholders: MEASURE)' % used)
    for i, bx in enumerate([b for b in mimas_rects if b.name.startswith('Mimas')]):
        fr.label(plate, 'MIMAS %d' % (i + 1), *P((bx.x0 + bx.x1) / 2, (bx.y0 + bx.y1) / 2), 4.0)
    fr.label(plate, 'GS105', *P(x_g0 + G['w'] / 2, y_g0 + G['d'] / 2), 4.0)
    fr.label(plate, 'POWER MAIN', *P(x_pm0 + pm_w / 2, y_pm0 + pm_d / 2), 4.0)
    fr.label(plate, 'FRONT', *P((px0 + px1) / 2, py0 + 4.0), 2.5)
    plate.material = 'plate'
    boxes.append(Box('mounting plate', px0, px1, py0, py1, plate_z, plate_top, 'plate', hard=False))
    for (x, y) in B['standoffs']:
        boxes.append(Box('standoff', s + x - 2.5, s + x + 2.5, y - 2.5, y + 2.5, zf, plate_z, 'standoff', hard=False))
    res['plate_origin'] = (px0, py0, px1, py1)

    # ---------------------------------------------------------- rear plates (seen from outside the rear)
    ov, sd = B['cover_overlap'], B['cover_screw_d']
    P_in = cfg.POWER_IN

    def cover(name, opening, title):
        _, zc, w, h = opening
        p = Panel(name, w + 2 * ov, h + 2 * ov)
        p.title = title
        p.outline = rect_pts(0, 0, w + 2 * ov, h + 2 * ov)
        for sx in (ov / 2, w + 1.5 * ov):
            for sy in (ov / 2, h + 1.5 * ov):
                p.cut(Circle(sx, sy, sd / 2))
        return p, w, h

    iec, w, h = cover('B-rear-iec', B['iec_opening'], 'B cover plate over the IEC inlet cut-out: banana inputs')
    pitch = 19.0
    need = pitch + P_in['banana_hole'] + 2.0
    if need > w or P_in['banana_hole'] + 2.0 > h:
        problems.append('IEC cover: the banana pair needs %.1f mm, the opening is %.1f mm wide' % (need, w))
    cu, cv = ov + w / 2, ov + h / 2
    for sx, txt in ((-1, '+12V'), (1, '0V')):
        iec.cut(Circle(cu + sx * pitch / 2, cv - 1.5, P_in['banana_hole'] / 2))
        fr.label(iec, txt, cu + sx * pitch / 2, cv + P_in['banana_hole'] / 2 + 1.0, 1.6)
    fr.label(iec, '1 BANANA 25A', cu, ov / 2 + 0.2, 1.4)

    rps, w, h = cover('B-rear-rps', B['rps_opening'], 'B cover plate over the DC/RPS cut-out: PCIe 8-pin + Molex inputs')
    pin = boards.get('inputs')
    pc = pin['fp']['J3']['crt'] if pin else (0, 0, 19.0, 12.0)
    mc = pin['fp']['J4']['crt'] if pin else (0, 0, 22.7, 9.6)
    cl = P_in['conn_clear']
    pw, ph = pc[2] - pc[0] + 2 * cl, pc[3] - pc[1] + 2 * cl
    mw, mh = mc[2] - mc[0] + 2 * cl, mc[3] - mc[1] + 2 * cl
    need = pw + mw + 3 * 2.0
    if need > w or max(ph, mh) > h:
        problems.append('RPS cover: PCIe + Molex need %.1f x %.1f mm, the opening is %.1f x %.1f' % (need, max(ph, mh), w, h))
    u0 = ov + (w - need) / 2 + 2.0
    rps.cut(RRect(u0 + pw / 2, ov + h / 2, pw, ph, 1.0))
    rps.cut(RRect(u0 + pw + 2.0 + mw / 2, ov + h / 2, mw, mh, 1.0))
    fr.label(rps, '2 PCIE 15A', u0 + pw / 2, ov / 2 + 0.2, 1.4)
    fr.label(rps, '3 MOLEX 10A', u0 + pw + 2.0 + mw / 2, ov / 2 + 0.2, 1.4)
    for i in range(3):
        rps.cut(Circle(ov + w / 2 + (i - 1) * 6.0, h + 1.5 * ov, P_in['led_hole'] / 2))
    fr.label(rps, 'IN', ov + w / 2 + 11, h + 1.5 * ov, 1.4, anchor='start')
    notes.append('rear: the input board (0047) has all three connectors on one PCB; the two carcass openings need '
                 'either panel-mount connectors on short leads to it, or an input board laid out to the measured '
                 'opening positions (IEC to RPS centre distance %.1f mm, placeholder)' % abs(
                     B['iec_opening'][0] - B['rps_opening'][0]))

    fan = Panel('B-rear-fans', fo[2] + 2 * ov, fo[3] + 2 * ov)
    fan.title = 'B fan plate over a rear vent opening (2 x 40 mm)'
    fan.outline = rect_pts(0, 0, fo[2] + 2 * ov, fo[3] + 2 * ov)
    for sx in (ov / 2, fo[2] + 1.5 * ov):
        for sy in (ov / 2, fo[3] + 1.5 * ov):
            fan.cut(Circle(sx, sy, sd / 2))
    if F['count'] * (F['size'] + 1) > fo[2] or F['size'] > fo[3] + 2 * ov - 2:
        problems.append('fan plate: %d fans do not fit the %.0f x %.0f opening' % (F['count'], fo[2], fo[3]))
    ff = fr.fan_wall(cfg, (fo[3] + 2 * ov) / 2)
    for i in range(F['count']):
        ucen = ov + fo[2] / 2 + (i - (F['count'] - 1) / 2) * (F['size'] + 1)
        ff.draw(fan, ucen - ff.width / 2, lambda z: (fo[3] + 2 * ov) - z)
    if 'dut_power' in [it.name for it in left_over]:
        notes.append('DUT power leads: no room on the front; let them out at the rear (e.g. a 16 mm grommet hole '
                     'drilled in the steel rear, or through the fan plate)')

    res['panels'] = [front, iec, rps, fan]
    res['plate'] = plate
    res['fragments'] = [('bay%d' % (i + 1), fr.standalone(b.item, fph, V)) for i, b in enumerate(bays)]
    res['fragments'].append(('front-panel', fr.standalone(group, fph, V)))
    res['interior'] = (s, W - s, t, D - s, s, H - s)
    res['allowed'] = []
    res['walls_t'] = s
    res['bays'] = bays
    res['stack_top'] = plate_top + bays[0].info['stack_top']
    res['front_items'] = [it.name for it, _ in items]
    res['left_over'] = [it.name for it in left_over]
    res['front_cut_window'] = None
    return res
