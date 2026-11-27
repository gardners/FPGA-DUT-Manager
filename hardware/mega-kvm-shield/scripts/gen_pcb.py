#!/usr/bin/env python3
"""Generate the shield PCB (outline, holes, cut-out, connector placement,
part clusters, power planes, 12 V tracks) from out/netlist.json.

Run inside the KiCad flatpak (needs pcbnew):
  flatpak run --command=python3 org.kicad.KiCad gen_pcb.py

Coordinates: "Mimas coordinates" (mx, my) in mm follow the Numato V3
drawing: origin at the Mimas board's bottom-left corner (RJ45 edge, P13
edge), x towards the HDMI edge, y towards P12. KiCad x = X0 + mx,
KiCad y = Y0 - my.
"""
import json
import os
import sys

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
NAME = 'mega-kvm-shield'
STDLIB = '/app/extensions/Library/footprints/'
X0, Y0 = 30.0, 200.0
MM = pcbnew.FromMM

# ---------------------------------------------------------------- geometry
MIMAS_W, MIMAS_H = 120.0, 90.0
HOLE_KEEPOUT = 3.8                    # screw head radius + clearance along the edge
REAR = MIMAS_W                        # rear edge = Mimas HDMI edge

# Mimas pin grid, holes and front cut-out (RJ45, USB-B, S12, P2, DC jack):
# geometry.py, checked against the vendor STEP
from geometry import SLOTS, Y_TOP, Y_BOT, KBD_DY, KBD_B2B  # noqa: E402
from geometry import ROW1_X, P12_A_Y, P13_A_Y, MIMAS_HOLES, NOTCHES, MIMAS_TALL  # noqa: E402


def K(mx, my):
    return pcbnew.VECTOR2I(MM(X0 + mx), MM(Y0 - my))


def tomimas(v):
    return pcbnew.ToMM(v.x) - X0, Y0 - pcbnew.ToMM(v.y)


# ---------------------------------------------------------------- helpers
board = pcbnew.BOARD()
board.SetCopperLayerCount(4)
ds = board.GetDesignSettings()
nets = {}


def net(name):
    if name not in nets:
        n = pcbnew.NETINFO_ITEM(board, name)
        board.Add(n)
        nets[name] = n
    return nets[name]


def load_fp(fpid):
    lib, name = fpid.split(':')
    path = os.path.join(PROJ, 'lib', 'shield.pretty') if lib == 'shield' else STDLIB + lib + '.pretty'
    fp = pcbnew.FootprintLoad(path, name)
    if fp is None:
        sys.exit('footprint not found: ' + fpid)
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def crt(fp):
    fp.BuildCourtyardCaches()
    for layer in (pcbnew.F_CrtYd, pcbnew.B_CrtYd):
        c = fp.GetCourtyard(layer)
        if c.OutlineCount():
            b = c.BBox()
            return [pcbnew.ToMM(b.GetLeft()), pcbnew.ToMM(b.GetTop()),
                    pcbnew.ToMM(b.GetRight()), pcbnew.ToMM(b.GetBottom())]
    b = fp.GetBoundingBox(False)
    return [pcbnew.ToMM(b.GetLeft()), pcbnew.ToMM(b.GetTop()),
            pcbnew.ToMM(b.GetRight()), pcbnew.ToMM(b.GetBottom())]


def pad_centroid(fp):
    ps = [p.GetPosition() for p in fp.Pads()]
    return (sum(pcbnew.ToMM(p.x) for p in ps) / len(ps), sum(pcbnew.ToMM(p.y) for p in ps) / len(ps))


def orient_facing(fp, direction, bottom=False):
    """Rotate (and flip) so the side away from the pads faces 'direction'
    (KiCad frame: '+x', '-x', '+y', '-y')."""
    if bottom:
        fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
    best = None
    for rot in (0, 90, 180, 270):
        fp.SetOrientationDegrees(rot)
        c = crt(fp)
        cx, cy = (c[0] + c[2]) / 2, (c[1] + c[3]) / 2
        px, py = pad_centroid(fp)
        v = {'+x': cx - px, '-x': px - cx, '+y': cy - py, '-y': py - cy}[direction]
        if best is None or v > best[0]:
            best = (v, rot)
    fp.SetOrientationDegrees(best[1])


def move_crt(fp, **kw):
    """Translate so courtyard edges land on given KiCad coordinates
    (keys: left, right, top, bottom, cx, cy in mm)."""
    c = crt(fp)
    dx = dy = 0.0
    if 'left' in kw:
        dx = kw['left'] - c[0]
    if 'right' in kw:
        dx = kw['right'] - c[2]
    if 'cx' in kw:
        dx = kw['cx'] - (c[0] + c[2]) / 2
    if 'top' in kw:
        dy = kw['top'] - c[1]
    if 'bottom' in kw:
        dy = kw['bottom'] - c[3]
    if 'cy' in kw:
        dy = kw['cy'] - (c[1] + c[3]) / 2
    fp.Move(pcbnew.VECTOR2I(MM(dx), MM(dy)))


def add_text(txt, mx, my, size=1.5, rot=0, layer=pcbnew.F_SilkS, bold=True):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(txt)
    t.SetPosition(K(mx, my))
    t.SetLayer(layer)
    t.SetTextSize(pcbnew.VECTOR2I(MM(size), MM(size)))
    t.SetTextThickness(MM(size * (0.2 if bold else 0.15)))
    t.SetTextAngleDegrees(rot)
    if layer in (pcbnew.B_SilkS,):
        t.SetMirrored(True)
    board.Add(t)
    return t


def seg(layer, pts, width=0.1, closed=False):
    pts = list(pts) + ([pts[0]] if closed else [])
    for a, b in zip(pts, pts[1:]):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(K(*a))
        s.SetEnd(K(*b))
        s.SetLayer(layer)
        s.SetWidth(MM(width))
        board.Add(s)


def rect_m(layer, x0, y0, x1, y1, width=0.1):
    seg(layer, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], width, closed=True)


# ---------------------------------------------------------------- parts
nl = json.load(open(os.path.join(PROJ, 'out', 'netlist.json')))
fps = {}
by_cluster = {}
for ref, p in sorted(nl.items()):
    fp = load_fp(p['fp'])
    fp.SetReference(ref)
    fp.SetValue(p['value'])
    if p['dnp']:
        fp.SetDNP(True)
        fp.SetExcludedFromBOM(True)
        fp.SetExcludedFromPosFiles(True)
    for pad in fp.Pads():
        n = p['pads'].get(pad.GetNumber())
        if n:
            pad.SetNet(net(n))
    if p['lcsc']:
        f = pcbnew.PCB_FIELD(fp, 0, 'LCSC')  # id ignored by recent KiCad
        f.SetText(p['lcsc'])
        f.SetVisible(False)
        f.SetLayer(pcbnew.F_Fab)
        try:
            fp.AddField(f)
        except Exception:
            pass
    if ref[0] in 'RCQUDF':
        fp.Reference().SetLayer(pcbnew.F_Fab)
    board.Add(fp)
    fps[ref] = fp
    by_cluster.setdefault(p['cluster'], []).append(ref)


def only(cluster):
    refs = by_cluster.get(cluster, [])
    assert len(refs) == 1, (cluster, refs)
    return fps[refs[0]]


# Mimas header sockets (pads at the Mimas pins)
for cl, ay in (('P12', P12_A_Y), ('P13', P13_A_Y)):
    fp = only(cl)
    fp.SetPosition(K(ROW1_X, ay))
    fp.SetOrientationDegrees(0)

# rear edge connectors (shield top side)
placed_slots = {}
for cl, (y0, y1) in SLOTS.items():
    if cl not in by_cluster:
        continue
    kind = cl.rstrip('0123456789J')
    fp = only(cl)
    orient_facing(fp, '+x')
    over = 1.54 if kind == 'HDMI' else 0.0
    move_crt(fp, right=X0 + REAR + over, cy=Y0 - (y0 + y1) / 2)
    placed_slots[cl] = (y0, y1)

# board-to-board sockets for the keyboard sub-boards (shield bottom side):
# pad n must sit exactly above pad n of the sub-board's 2x6 header
def kbd_header_pads(dy):
    h = load_fp('Connector_PinHeader_2.54mm:PinHeader_2x06_P2.54mm_Vertical')
    h.SetOrientationDegrees(0)
    h.SetPosition(K(0, 0))
    c = crt(h)
    h.Move(pcbnew.VECTOR2I(MM(X0 + KBD_B2B[0] - (c[0] + c[2]) / 2),
                           MM(Y0 - (KBD_B2B[1] + dy) - (c[1] + c[3]) / 2)))
    return {p.GetNumber(): p.GetPosition() for p in h.Pads()}


def match_pads(fp, target, bottom):
    if bottom:
        fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
    for rot in (0, 90, 180, 270):
        fp.SetOrientationDegrees(rot)
        pads = {p.GetNumber(): p.GetPosition() for p in fp.Pads()}
        d = target['1'] - pads['1']
        fp.Move(d)
        pads = {p.GetNumber(): p.GetPosition() for p in fp.Pads()}
        if all(abs(pads[k].x - target[k].x) < 1000 and abs(pads[k].y - target[k].y) < 1000
               for k in ('2', '3', '12')):
            return
    sys.exit('cannot match pads of ' + fp.GetReference())


for side, dy in (('P12', 0.0), ('P13', KBD_DY)):
    match_pads(only('B2B' + side), kbd_header_pads(dy), True)

# Front and side connectors
fp = only('PKJ')                       # physical keyboard: front edge, P12 overhang
orient_facing(fp, '-x')
move_crt(fp, left=X0 + 0.0, cy=Y0 - (MIMAS_H + 13.0))
fp = only('I2CJ')                      # I2C (+5 V) to the front panel
orient_facing(fp, '-x')
move_crt(fp, left=X0 - 6.0, cy=Y0 - (MIMAS_H + 32.5))
fp = only('LINKU')                     # neighbour UART, 3-pin Dupont
fp.SetOrientationDegrees(90)
move_crt(fp, cx=X0 + 40.0, cy=Y0 - (Y_BOT + 4.0))
pwrj = [r for r in by_cluster['PWR'] if r.startswith('J')][0]
fp = fps[pwrj]                         # 12 V in (Mini-Fit Jr), front of the P13 overhang
fp.SetOrientationDegrees(90)
move_crt(fp, left=X0 + 2.0, cy=Y0 - (-12.0))
fp = only('RELAYJ')                    # power control header, along the front of the P13 overhang
fp.SetOrientationDegrees(90)
move_crt(fp, left=X0 + 2.0, cy=Y0 - (-33.0))

# holes: Mimas holes + overhang supports (front and rear-ish corners)
holes = sorted([r for r in nl if r.startswith('H')], key=lambda r: int(r[1:]))
support = [(5.0, Y_TOP - 5.0), (70.0, Y_TOP - 5.0), (5.0, Y_BOT + 5.0), (70.0, Y_BOT + 5.0)]
for ref, (mx, my) in zip(holes, MIMAS_HOLES + support):
    fps[ref].SetPosition(K(mx, my))

# ---------------------------------------------------------------- clusters
occupied = []


def box_of(fp):
    c = crt(fp)
    return c


for f in fps.values():
    if f.GetReference()[0] in 'JPH' or f.GetReference() in ():
        occupied.append(crt(f))


def free(c):
    for o in occupied:
        if c[0] < o[2] and c[2] > o[0] and c[1] < o[3] and c[3] > o[1]:
            return False
    # inside board and out of the notch
    mx0, my1 = c[0] - X0, Y0 - c[1]
    mx1, my0 = c[2] - X0, Y0 - c[3]
    if mx0 < 0.5 or mx1 > REAR - 0.5 or my1 > Y_TOP - 0.5 or my0 < Y_BOT + 0.5:
        return False
    for (_, ny0, nx1, ny1) in NOTCHES:
        if mx0 < nx1 + 0.5 and my1 > ny0 - 0.5 and my0 < ny1 + 0.5:
            return False
    for hx, hy in MIMAS_HOLES + support:
        if mx0 < hx + 3.5 and mx1 > hx - 3.5 and my0 < hy + 3.5 and my1 > hy - 3.5:
            return False
    return True


def pack(cluster, region, step=0.5):
    """Place a cluster's parts in region (mx0, my0, mx1, my1), scanning
    from the rear edge inwards, rows along y."""
    refs = sorted(by_cluster.get(cluster, []),
                  key=lambda r: -(crt(fps[r])[2] - crt(fps[r])[0]) * (crt(fps[r])[3] - crt(fps[r])[1]))
    mx0, my0, mx1, my1 = region
    for r in refs:
        f = fps[r]
        f.SetOrientationDegrees(0)
        c = crt(f)
        M = 0.4                       # spacing between courtyards
        w, h = c[2] - c[0] + 2 * M, c[3] - c[1] + 2 * M
        done = False
        x = mx1 - w
        while x >= mx0 and not done:
            y = my1
            while y - h >= my0:
                cand = [X0 + x, Y0 - y, X0 + x + w, Y0 - y + h]
                if free(cand):
                    move_crt(f, left=cand[0] + M, top=cand[1] + M)
                    occupied.append(crt(f))
                    done = True
                    break
                y -= step
            x -= step
        if not done:
            print('WARNING: no room for', r, 'in', cluster, region)
            move_crt(f, left=X0 + mx0, top=Y0 - my0 + 2)


def slot_region(cl, depth=32.0):
    y0, y1 = placed_slots[cl + 'J']
    return (REAR - depth, y0, REAR, y1)


for cl in ('HDMI1', 'HDMI2', 'HDMI3'):
    if cl + 'J' in placed_slots:
        y0, y1 = placed_slots[cl + 'J']
        pack(cl, (REAR - 40, y0 - 6, REAR, y1 + 6))
for n in range(4):
    for kind in ('JTAG', 'KBD'):
        cl = '%s%d' % (kind, n)
        if cl + 'J' in placed_slots:
            pack(cl, slot_region(cl, 36))
pack('EXP', (22.0, 40.0, 80.0, 82.0))
pack('PWR', (14.0, -30.0, 40.0, -1.0))
pack('PK', (16.0, MIMAS_H + 1, 45.0, Y_TOP - 1))
pack('BUCK', (45.0, MIMAS_H + 1, 80.0, Y_TOP - 1))
pack('LINK', (30.0, Y_BOT + 1, 60.0, Y_BOT + 20))
pack('MISC', (22.0, 20.0, 70.0, 40.0))

# ---------------------------------------------------------------- outline
(_, N0Y0, N0X1, N0Y1), (_, N1Y0, N1X1, N1Y1) = NOTCHES
assert N0Y0 < N1Y0 < N1Y1 == N0Y1 and N1X1 > N0X1    # main cut-out + RJ45 step at its P12 end
outline = [(0, Y_TOP), (REAR, Y_TOP), (REAR, Y_BOT), (0, Y_BOT), (0, N0Y0),
           (N0X1, N0Y0), (N0X1, N1Y0), (N1X1, N1Y0), (N1X1, N1Y1), (0, N1Y1)]
seg(pcbnew.Edge_Cuts, outline, 0.1, closed=True)

# Mimas outline and its edge connectors on User.Drawings (reference only)
U = pcbnew.Dwgs_User
rect_m(U, 0, 0, MIMAS_W, MIMAS_H, 0.15)
# (vendor STEP vertex bounding boxes, 2026-11-27; the HDMIs are flush with x = 120 there)
tall = [MIMAS_TALL[k][:4] + ('Mimas ' + k if k == 'RJ45' else k,) for k in ('RJ45', 'USB-B', 'S12', 'DC jack')]
for (x0, y0, x1, y1, t) in tall + [(4.83, 24.81, 12.45, 28.06, 'P2'),
                            (110.8, 63.2, 120.0, 79.4, 'Mimas HDMI IN (DUT0)'),
                            (110.8, 41.8, 120.0, 58.0, 'Mimas HDMI OUT'),
                            (107.3, 25.94, 119.94, 37.34, 'mDP OUT'), (107.3, 9.61, 119.94, 21.01, 'mDP IN'),
                            (74, 15, 97, 44.1, 'Mimas SW1 + LD0-7'), (35.86, 64.24, 65.86, 78.25, '7-seg')]:
    rect_m(U, x0, y0, x1, y1, 0.1)
    add_text(t, (x0 + x1) / 2, (y0 + y1) / 2, 1.0, 0, U, False)
add_text('Mimas A7 V3 outline (User.Drawings)', 60, 45, 1.5, 0, U, False)
from geometry import KBD_X0, KBD_X1, KBD_Y0, KBD_Y1  # noqa: E402
for dy in (0.0, KBD_DY):
    rect_m(U, KBD_X0, KBD_Y0 + dy, KBD_X1, KBD_Y1 + dy, 0.15)
    add_text('keyboard sub-board (Mimas level)', (KBD_X0 + KBD_X1) / 2, KBD_Y0 + dy + 3, 1.0, 0, U, False)

# ---------------------------------------------------------------- silkscreen
LBL = {'HDMI': 'DUT%s HDMI IN', 'JTAG': 'DUT%s JTAG/UART'}
for cl, (y0, y1) in placed_slots.items():
    kind = cl.rstrip('0123456789J')
    n = cl[len(kind):-1]
    depth = 12.5 if kind == 'HDMI' else 16.5
    add_text(LBL[kind] % n, REAR - depth - 1.5, (y0 + y1) / 2, 1.2, 90)
add_text('PHYSICAL KEYBOARD (J5 + JTAG)', 18.0, MIMAS_H + 13.0, 1.2, 90)
add_text('I2C: GND 5V 3V3 SDA SCL INT', 13.0, MIMAS_H + 32.5, 1.0, 90)
add_text('NEIGHBOUR UART: GND TX RX', 40.0, Y_BOT + 9.0, 1.0, 0)
for side, dy in (('P12', 0.0), ('P13', KBD_DY)):
    add_text('KBD SUB-BOARD (under)', KBD_B2B[0] - 5.0, KBD_B2B[1] + dy, 1.0, 90)
add_text('MEGA-KVM shield rev A (draft) - issue 0045', 45.0, 30.0, 1.5, 0)
add_text('Mimas RJ45 / USB / S12 / P2 / DC jack cut-out', 9.0, 45.0, 1.0, 90)
add_text('P12', ROW1_X - 5, P12_A_Y - 4.5, 1.5, 0)
add_text('P13', ROW1_X - 5, P13_A_Y + 7.0, 1.5, 0)

# ---------------------------------------------------------------- planes
def zone(layer, netname, prio=0):
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    z.SetNet(net(netname))
    z.SetAssignedPriority(prio)
    z.SetLocalClearance(MM(0.3))
    z.SetMinThickness(MM(0.2))
    z.SetThermalReliefGap(MM(0.4))
    z.SetThermalReliefSpokeWidth(MM(0.4))
    o = z.Outline()
    o.NewOutline()
    for (mx, my) in outline:
        o.Append(MM(X0 + mx), MM(Y0 - my))
    board.Add(z)
    return z


zone(pcbnew.In1_Cu, 'GND')
zone(pcbnew.In2_Cu, '+3V3')

# ---------------------------------------------------------------- 12 V tracks
def track(a, b, netname, width=1.5, layer=pcbnew.F_Cu):
    t = pcbnew.PCB_TRACK(board)
    t.SetStart(a)
    t.SetEnd(b)
    t.SetWidth(MM(width))
    t.SetLayer(layer)
    t.SetNet(net(netname))
    board.Add(t)


def padpos(ref, num):
    for p in fps[ref].Pads():
        if p.GetNumber() == num:
            return p.GetPosition()
    raise KeyError((ref, num))


p12 = by_cluster['P12'][0]
p13 = by_cluster['P13'][0]
vin = padpos(pwrj, '1')
# P13 VIN (rows 1-2): short hop from the 12 V connector
a = padpos(p13, 'A1')
track(vin, pcbnew.VECTOR2I(vin.x, a.y + MM(3.0)), '+12V')
track(pcbnew.VECTOR2I(vin.x, a.y + MM(3.0)), pcbnew.VECTOR2I(a.x, a.y + MM(3.0)), '+12V')
track(pcbnew.VECTOR2I(a.x, a.y + MM(3.0)), a, '+12V')
for r in ('A1', 'A2'):
    pass
track(padpos(p13, 'A1'), padpos(p13, 'A2'), '+12V', 1.0)
track(padpos(p13, 'A1'), padpos(p13, 'B1'), '+12V', 1.0)
track(padpos(p13, 'B1'), padpos(p13, 'B2'), '+12V', 1.0)
track(padpos(p13, 'A2'), padpos(p13, 'B2'), '+12V', 1.0)
# P12 VIN: up behind the cut-out on the bottom layer
# (it steps out around the RJ45 part of the cut-out: >= 3 mm from every cut edge)
route = [(ROW1_X, 9.0), (N0X1 + 3.0, 9.0), (N0X1 + 3.0, N1Y0 - 3.0), (N1X1 + 3.0, N1Y0 - 3.0),
         (N1X1 + 3.0, 81.0), (ROW1_X, 81.0)]
track(padpos(p13, 'B1'), K(*route[0]), '+12V', 1.5, pcbnew.B_Cu)
for u, v in zip(route, route[1:]):
    track(K(*u), K(*v), '+12V', 1.5, pcbnew.B_Cu)
track(K(*route[-1]), padpos(p12, 'A1'), '+12V', 1.5, pcbnew.B_Cu)
track(padpos(p12, 'A1'), padpos(p12, 'A2'), '+12V', 1.0)
track(padpos(p12, 'A1'), padpos(p12, 'B1'), '+12V', 1.0)
track(padpos(p12, 'B1'), padpos(p12, 'B2'), '+12V', 1.0)
track(padpos(p12, 'A2'), padpos(p12, 'B2'), '+12V', 1.0)

ds.SetBoardThickness(MM(1.6))
ds.m_MinClearance = MM(0.1)
nc = ds.m_NetSettings.GetDefaultNetclass()
nc.SetClearance(MM(0.127))
nc.SetTrackWidth(MM(0.2))
out = os.path.join(PROJ, NAME + '.kicad_pcb')
board.SetFileName(out)
filler = pcbnew.ZONE_FILLER(board)
filler.Fill(board.Zones())
pcbnew.SaveBoard(out, board)
print('shield %.1f x %.1f mm (Mimas y %.1f .. %.1f)' % (REAR, Y_TOP - Y_BOT, Y_BOT, Y_TOP))
for cl, (y0, y1) in sorted(placed_slots.items(), key=lambda kv: -kv[1][1]):
    print('  rear %-7s Mimas y %7.2f .. %7.2f' % (cl, y0, y1))
json.dump({'board_mm': [REAR, Y_TOP - Y_BOT], 'y_top': Y_TOP, 'y_bot': Y_BOT,
           'rear_slots': placed_slots}, open(os.path.join(PROJ, 'out', 'placement.json'), 'w'), indent=1)
