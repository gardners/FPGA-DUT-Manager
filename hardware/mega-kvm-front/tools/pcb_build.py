"""Build the placed front-panel board from the generator netlist and write the
panel-hole file for the case generator.  Run with KiCad's Python:
  flatpak run --command=python3 org.kicad.KiCad tools/pcb_build.py

Footprints carry their schematic symbol path (DRC --schematic-parity works).
Placement is in tools/layout.py (feature centres).  GND is poured on both
layers; signal tracks come from tools/route.py (optional) or by hand.
"""
import json
import os
import re
import sys

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import layout as L  # noqa: E402

NAME = 'mega-kvm-front'
PDIR = os.path.join(HERE, '..')
SYSFP = os.environ.get('KICAD_FOOTPRINT_DIR', '/app/extensions/Library/footprints')
MM = pcbnew.FromMM
ORIGIN = (100.0, 100.0)   # board top-left in KiCad page coordinates


def vec(x, y):
    return pcbnew.VECTOR2I(MM(ORIGIN[0] + x), MM(ORIGIN[1] + y))


def load_fp(fpid):
    lib, name = fpid.split(':')
    fp = pcbnew.FootprintLoad(os.path.join(SYSFP, lib + '.pretty'), name)
    if fp is None:
        raise SystemExit('footprint not found: ' + fpid)
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def seg(board, a, b, layer=pcbnew.Edge_Cuts, w=0.1):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(vec(*a))
    s.SetEnd(vec(*b))
    s.SetLayer(layer)
    s.SetWidth(MM(w))
    board.Add(s)


def rect(board, x1, y1, x2, y2, layer=pcbnew.Edge_Cuts, w=0.1):
    pts = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)]
    for a, b in zip(pts, pts[1:] + pts[:1]):
        seg(board, a, b, layer, w)


def circle(board, x, y, d, layer, w=0.1):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_CIRCLE)
    s.SetCenter(vec(x, y))
    s.SetEnd(vec(x + d / 2, y))
    s.SetLayer(layer)
    s.SetWidth(MM(w))
    board.Add(s)


def text(board, s, x, y, layer=pcbnew.F_SilkS, size=1.5, mirror=False):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(s)
    t.SetPosition(vec(x, y))
    t.SetLayer(layer)
    t.SetTextSize(pcbnew.VECTOR2I(MM(size), MM(size)))
    t.SetTextThickness(MM(max(0.15, size * 0.15)))
    if mirror:
        t.SetMirrored(True)
    board.Add(t)


def add_zone(board, net, layer, pts, prio=0):
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    z.SetNet(net)
    z.SetAssignedPriority(prio)
    z.SetLocalClearance(MM(0.3))
    z.SetMinThickness(MM(0.25))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
    z.SetThermalReliefGap(MM(0.4))
    z.SetThermalReliefSpokeWidth(MM(0.4))
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    ol = z.Outline()
    ol.NewOutline()
    for x, y in pts:
        ol.Append(MM(ORIGIN[0] + x), MM(ORIGIN[1] + y))
    board.Add(z)


def pad_centre(fp):
    """Pad bounding-box centre (mm, page coordinates)."""
    xs, ys = [], []
    for p in fp.Pads():
        bb = p.GetBoundingBox()
        xs += [bb.GetLeft(), bb.GetRight()]
        ys += [bb.GetTop(), bb.GetBottom()]
    return pcbnew.ToMM((min(xs) + max(xs)) // 2), pcbnew.ToMM((min(ys) + max(ys)) // 2)


def board_xy(fp):
    cx, cy = pad_centre(fp) if len(fp.Pads()) else (pcbnew.ToMM(fp.GetPosition().x),
                                                     pcbnew.ToMM(fp.GetPosition().y))
    return round(cx - ORIGIN[0], 3), round(cy - ORIGIN[1], 3)


def build():
    parts = json.load(open(os.path.join(PDIR, NAME + '.netlist.json')))
    board = pcbnew.BOARD()
    board.SetCopperLayerCount(2)
    board.GetDesignSettings().SetBoardThickness(MM(L.THICK))

    nets = {}
    for p in parts.values():
        for net in p['pads'].values():
            if net and net not in nets:
                ni = pcbnew.NETINFO_ITEM(board, net if net.startswith('unconnected-') else '/' + net)
                board.Add(ni)
                nets[net] = ni

    fps = {}
    missing = [r for r in parts if parts[r]['footprint'] and r not in L.PLACE]
    if missing:
        raise SystemExit('no placement for: ' + ' '.join(missing))
    for ref, p in sorted(parts.items()):
        if not p['footprint']:
            continue
        fp = load_fp(p['footprint'])
        fp.SetReference(ref)
        fp.SetValue(p['value'])
        fp.SetPath(pcbnew.KIID_PATH('/' + p['uuid']))
        fp.SetDNP(bool(p.get('dnp')))
        fp.SetExcludedFromBOM(not p.get('in_bom', True))
        for k, v in p.get('fields', {}).items():
            if k not in ('Datasheet', 'Description'):
                fp.SetField(k, v)
                fp.GetField(k).SetVisible(False)
        if re.match(r'(Resistor_SMD|Capacitor_SMD|LED_THT|Button_Switch_THT|Package_SO|MountingHole):', p['footprint']):
            fp.Reference().SetLayer(pcbnew.F_Fab)     # dense / panel-facing: refs on fab only
        fp.Value().SetVisible(False)
        board.Add(fp)
        for pad in fp.Pads():
            net = p['pads'].get(pad.GetNumber())
            if net:
                pad.SetNet(nets[net])
        x, y, rot, side = (list(L.PLACE[ref]) + [0, 'F'])[:4]
        fp.SetPosition(vec(x, y))
        if side == 'B':
            fp.Flip(vec(x, y), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
        fp.SetOrientationDegrees(rot)
        if len(fp.Pads()):
            cx, cy = pad_centre(fp)
            fp.Move(pcbnew.VECTOR2I(MM(ORIGIN[0] + x - cx), MM(ORIGIN[1] + y - cy)))
        if side == 'B':   # back-side headers: reference on B.Fab, labels come from BACK_SILK
            fp.Reference().SetLayer(pcbnew.B_Fab)
        fps[ref] = fp

    # outline + LCD bezel window
    rect(board, 0, 0, L.BOARD_W, L.BOARD_H)
    rect(board, *L.WINDOW)
    # LCD module and rocker outlines for reference (fab / user layers)
    lx, ly, lw, lh = L.LCD['x'], L.LCD['y'], L.LCD['w'], L.LCD['h']
    rect(board, lx, ly, lx + lw, ly + lh, pcbnew.B_Fab, 0.12)
    bx, by, bw, bh = L.LCD['bezel']
    rect(board, bx, by, bx + bw, by + bh, pcbnew.B_Fab, 0.12)
    text(board, '1602 LCD module (on the back, bezel through the window)', 40, 3.6, pcbnew.B_Fab, 1.0, True)
    wx, wy, ww, wh = L.LCD_WINDOW
    rect(board, wx, wy, wx + ww, wy + wh, pcbnew.Dwgs_User, 0.1)
    text(board, 'panel window', wx + ww / 2, wy + wh / 2, pcbnew.Dwgs_User, 1.5)
    text(board, 'ROCKER (panel, off-board) ->', L.BOARD_W - 30, 1.6, pcbnew.Dwgs_User, 1.0)

    gnd = nets['GND']
    full = [(0.3, 0.3), (L.BOARD_W - 0.3, 0.3), (L.BOARD_W - 0.3, L.BOARD_H - 0.3), (0.3, L.BOARD_H - 0.3)]
    add_zone(board, gnd, pcbnew.F_Cu, full)
    add_zone(board, gnd, pcbnew.B_Cu, full)

    for s, x, y, size in L.SILK:
        text(board, s, x, y, pcbnew.F_SilkS, size)
    for s, x, y, size in L.BACK_SILK:
        text(board, s, x, y, pcbnew.B_SilkS, size, True)

    out = os.path.join(PDIR, NAME + '.kicad_pcb')
    route = os.path.join(HERE, '..', 'tracks.json')
    if os.path.exists(route):
        add_tracks(board, nets, json.load(open(route)))
    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    board.Save(out)
    print('wrote', out, len(fps), 'footprints')
    write_panel(fps)


def add_tracks(board, nets, data):
    """Tracks/vias saved by tools/route.py (board coordinates)."""
    for t in data.get('tracks', []):
        tr = pcbnew.PCB_TRACK(board)
        tr.SetStart(vec(*t['a']))
        tr.SetEnd(vec(*t['b']))
        tr.SetWidth(MM(t['w']))
        tr.SetLayer(pcbnew.F_Cu if t['layer'] == 'F' else pcbnew.B_Cu)
        tr.SetNet(nets[t['net']])
        board.Add(tr)
    for v in data.get('vias', []):
        via = pcbnew.PCB_VIA(board)
        via.SetPosition(vec(*v['at']))
        via.SetWidth(MM(v['d']))
        via.SetDrill(MM(v['drill']))
        via.SetNet(nets[v['net']])
        board.Add(via)


def write_panel(fps):
    """Panel features in board coordinates (front view), for the case generator."""
    leds = []
    for i in range(8):
        for colour, ref in (('red', 'D%d' % (1 + i)), ('green', 'D%d' % (11 + i))):
            x, y = board_xy(fps[ref])
            leds.append({'ref': ref, 'label': str(i + 1), 'dut': i, 'colour': colour,
                         'function': 'powered' if colour == 'red' else 'selected',
                         'x': x, 'y': y, 'hole_d': L.LED_HOLE})
    buttons = []
    for ref, fn, lbl in L.BUTTONS:
        x, y = board_xy(fps[ref])
        buttons.append({'ref': ref, 'function': fn, 'engrave': lbl, 'x': x, 'y': y, 'hole_d': L.BTN_HOLE})
    holes = []
    for k in range(1, 9):
        ref = 'H%d' % k
        x, y = board_xy(fps[ref])
        holes.append({'ref': ref, 'x': x, 'y': y,
                      'hole_d': L.M25_HOLE if k <= 4 else L.M3_HOLE,
                      'use': 'LCD M2.5 screw (panel - 3 mm spacer - board - LCD spacer - module)' if k <= 4
                      else 'M3, 3 mm spacer board-to-panel'})
    wx, wy, ww, wh = L.LCD_WINDOW
    d = {
        'units': 'mm',
        'origin': 'board top-left corner seen from the front of the case; x right, y down',
        'board': {'w': L.BOARD_W, 'h': L.BOARD_H, 'thickness': L.THICK,
                  'panel_gap': L.PANEL_GAP,
                  'window': dict(zip(('x1', 'y1', 'x2', 'y2'), L.WINDOW))},
        'lcd': {'module': {'x': L.LCD['x'], 'y': L.LCD['y'], 'w': L.LCD['w'], 'h': L.LCD['h']},
                'panel_window': {'x': wx, 'y': wy, 'w': ww, 'h': wh,
                                 'cx': wx + ww / 2, 'cy': wy + wh / 2},
                'bezel': dict(zip(('x', 'y', 'w', 'h'), L.LCD['bezel'])),
                'viewing_area': dict(zip(('x', 'y', 'w', 'h'), L.LCD['view']))},
        'leds': leds,
        'buttons': buttons,
        'holes': holes,
        'rocker': L.ROCKER,
        'engrave': [{'text': s, 'x': x, 'y': y} for s, x, y in L.ENGRAVE],
    }
    out = os.path.join(PDIR, 'out', 'panel-holes.json')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w') as f:
        json.dump(d, f, indent=1)
    print('wrote', out)


if __name__ == '__main__':
    build()
