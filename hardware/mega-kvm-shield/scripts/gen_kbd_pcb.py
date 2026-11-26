#!/usr/bin/env python3
"""Generate the keyboard sub-board PCB (kbd-sub/mega-kvm-kbdsub.kicad_pcb).

Two per Mimas, one under each shield overhang, at Mimas level: two J5-style
2x5 right-angle box headers flush with the rear edge, directly below the
shield's JB1 headers, and a 2x6 male header up to a socket on the shield's
underside. Coordinates are the P12-side instance in Mimas coordinates (see
geometry.py); the P13-side instance is the same board moved by KBD_DY.

Run inside the KiCad flatpak:
  flatpak run --command=python3 org.kicad.KiCad gen_kbd_pcb.py
"""
import json
import os
import sys

import pcbnew

from geometry import (REAR, KBD_X0, KBD_X1, KBD_Y0, KBD_Y1, KBD_J5, KBD_B2B,
                      KBD_HOLES)

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(os.path.dirname(HERE), 'kbd-sub')
NAME = 'mega-kvm-kbdsub'
STDLIB = '/app/extensions/Library/footprints/'
X0, Y0 = 30.0, 200.0            # same mapping as gen_pcb.py
MM = pcbnew.FromMM


def K(mx, my):
    return pcbnew.VECTOR2I(MM(X0 + mx), MM(Y0 - my))


board = pcbnew.BOARD()
board.SetCopperLayerCount(2)
nets = {}


def net(name):
    if name not in nets:
        n = pcbnew.NETINFO_ITEM(board, name)
        board.Add(n)
        nets[name] = n
    return nets[name]


def load_fp(fpid):
    lib, name = fpid.split(':')
    fp = pcbnew.FootprintLoad(STDLIB + lib + '.pretty', name)
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


def move_crt(fp, **kw):
    c = crt(fp)
    dx = dy = 0.0
    if 'right' in kw:
        dx = kw['right'] - c[2]
    if 'left' in kw:
        dx = kw['left'] - c[0]
    if 'cx' in kw:
        dx = kw['cx'] - (c[0] + c[2]) / 2
    if 'top' in kw:
        dy = kw['top'] - c[1]
    if 'cy' in kw:
        dy = kw['cy'] - (c[1] + c[3]) / 2
    fp.Move(pcbnew.VECTOR2I(MM(dx), MM(dy)))


def add_text(txt, mx, my, size=1.2, rot=0, layer=pcbnew.F_SilkS):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(txt)
    t.SetPosition(K(mx, my))
    t.SetLayer(layer)
    t.SetTextSize(pcbnew.VECTOR2I(MM(size), MM(size)))
    t.SetTextThickness(MM(size * 0.18))
    t.SetTextAngleDegrees(rot)
    if layer == pcbnew.B_SilkS:
        t.SetMirrored(True)
    board.Add(t)


nl = json.load(open(os.path.join(PROJ, 'out', 'netlist.json')))
fps, by_cluster = {}, {}
for ref, p in sorted(nl.items()):
    fp = load_fp(p['fp'])
    fp.SetReference(ref)
    fp.SetValue(p['value'])
    for pad in fp.Pads():
        n = p['pads'].get(pad.GetNumber())
        if n:
            pad.SetNet(net(n))
    if ref[0] == 'R':
        fp.Reference().SetLayer(pcbnew.F_Fab)
    board.Add(fp)
    fps[ref] = fp
    by_cluster.setdefault(p['cluster'], []).append(ref)


def only(cl):
    (r,) = by_cluster[cl]
    return fps[r]


# B2B header: same placement rule as gen_pcb.kbd_header_pads()
h = only('B2B')
h.SetOrientationDegrees(0)
h.SetPosition(K(0, 0))
move_crt(h, cx=X0 + KBD_B2B[0], cy=Y0 - KBD_B2B[1])
for slot, yc in KBD_J5.items():
    fp = only('KBD%sJ' % slot)
    fp.SetOrientationDegrees(0)          # shroud opening faces +x (rear)
    move_crt(fp, right=X0 + REAR, cy=Y0 - yc)
holes = sorted([r for r in nl if r.startswith('H')], key=lambda r: int(r[1:]))
for ref, (mx, my) in zip(holes, KBD_HOLES):
    fps[ref].SetPosition(K(mx, my))

# series resistors in a column between the B2B header and each J5
occupied = [crt(f) for r, f in fps.items() if r[0] in 'JH']
for slot, yc in KBD_J5.items():
    refs = sorted(by_cluster['KBD' + slot], key=lambda r: int(r[1:]))
    x, y = 96.5, yc + 4.0
    for r in refs:
        f = fps[r]
        f.SetOrientationDegrees(90)
        move_crt(f, cx=X0 + x, cy=Y0 - y)
        y -= 2.2

# outline
pts = [(KBD_X0, KBD_Y0), (KBD_X1, KBD_Y0), (KBD_X1, KBD_Y1), (KBD_X0, KBD_Y1)]
for a, b in zip(pts, pts[1:] + pts[:1]):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(K(*a))
    s.SetEnd(K(*b))
    s.SetLayer(pcbnew.Edge_Cuts)
    s.SetWidth(MM(0.1))
    board.Add(s)

z = pcbnew.ZONE(board)
z.SetLayer(pcbnew.B_Cu)
z.SetNet(net('GND'))
z.SetLocalClearance(MM(0.3))
z.SetMinThickness(MM(0.2))
o = z.Outline()
o.NewOutline()
for (mx, my) in pts:
    o.Append(MM(X0 + mx), MM(Y0 - my))
board.Add(z)

for slot, yc in KBD_J5.items():
    add_text('KEYBOARD %s' % slot, 101.5, yc, 1.2, 90)
B = pcbnew.B_SilkS
add_text('A: DUT0 (P12 side) / DUT2 (P13 side)', 108.0, KBD_J5['A'], 1.0, 90, B)
add_text('B: DUT3 (P12 side) / DUT1 (P13 side)', 108.0, KBD_J5['B'], 1.0, 90, B)
add_text('MEGA-KVM keyboard sub-board rev A', 96.0, (KBD_Y0 + KBD_Y1) / 2, 1.0, 90, B)

ds = board.GetDesignSettings()
ds.SetBoardThickness(MM(1.6))
out = os.path.join(PROJ, NAME + '.kicad_pcb')
board.SetFileName(out)
pcbnew.ZONE_FILLER(board).Fill(board.Zones())
pcbnew.SaveBoard(out, board)
print('kbd sub-board %.1f x %.1f mm' % (KBD_X1 - KBD_X0, KBD_Y1 - KBD_Y0))
