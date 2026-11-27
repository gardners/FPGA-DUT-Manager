"""Build a placed, unrouted board from the generator netlist (run with KiCad's
Python, e.g. `flatpak run --command=python3 org.kicad.KiCad tools/pcb_build.py main`).

Footprints get their schematic symbol path, so DRC --schematic-parity checks
the board against the schematic.  Placement, outline and power polygons are
in tools/placement.py; nothing is routed (only polygons sketched).
"""
import json
import os
import re
import sys

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import placement  # noqa: E402

SYSFP = os.environ.get('KICAD_FOOTPRINT_DIR', '/app/extensions/Library/footprints')
PROJFP = os.path.join(HERE, '..', 'lib', 'mega-kvm-power.pretty')
MM = pcbnew.FromMM


def vec(x, y):
    return pcbnew.VECTOR2I(MM(x), MM(y))


def load_fp(fpid):
    lib, name = fpid.split(':')
    path = PROJFP if lib == 'mega-kvm-power' else os.path.join(SYSFP, lib + '.pretty')
    fp = pcbnew.FootprintLoad(path, name)
    if fp is None:
        raise SystemExit('footprint not found: ' + fpid)
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def add_outline(board, pts):
    for a, b in zip(pts, pts[1:] + pts[:1]):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(vec(*a))
        s.SetEnd(vec(*b))
        s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(MM(0.1))
        board.Add(s)


def add_zone(board, nets, net, layer, pts, prio=0, name=None):
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    z.SetNet(nets[net])
    z.SetAssignedPriority(prio)
    z.SetLocalClearance(MM(0.3))
    z.SetMinThickness(MM(0.25))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    if name:
        z.SetZoneName(name)
    ol = z.Outline()
    ol.NewOutline()
    for x, y in pts:
        ol.Append(MM(x), MM(y))
    board.Add(z)
    return z


def add_text(board, text, x, y, layer=pcbnew.F_SilkS, size=1.5, mirror=False):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(text)
    t.SetPosition(vec(x, y))
    t.SetLayer(layer)
    t.SetTextSize(vec(size, size))
    t.SetTextThickness(MM(size * 0.15))
    if mirror:
        t.SetMirrored(True)
    board.Add(t)


def build(which):
    cfg = placement.BOARDS[which]
    name = cfg['name']
    pdir = os.path.join(HERE, '..', name)
    parts = json.load(open(os.path.join(pdir, name + '.netlist.json')))
    board = pcbnew.BOARD()
    board.SetCopperLayerCount(2)
    ds = board.GetDesignSettings()
    ds.SetBoardThickness(MM(1.6))

    nets = {}
    for ref, p in parts.items():
        for pad, net in p['pads'].items():
            if net and net not in nets:
                ni = pcbnew.NETINFO_ITEM(board, net if net.startswith('unconnected-') else '/' + net)
                board.Add(ni)
                nets[net] = ni

    ox, oy = cfg['origin']
    missing = []
    for ref, p in sorted(parts.items()):
        if not p['footprint']:
            continue
        fp = load_fp(p['footprint'])
        fp.SetReference(ref)
        fp.SetValue(p['value'])
        fp.SetPath(pcbnew.KIID_PATH('/' + p['uuid']))
        if p.get('dnp'):
            fp.SetDNP(True)
        fp.SetExcludedFromBOM(not p.get('in_bom', True))
        for k, v in p.get('fields', {}).items():
            if k not in ('Datasheet', 'Description'):
                fp.SetField(k, v)
                fp.GetField(k).SetVisible(False)
        small = re.match(r'(Resistor_SMD:|Capacitor_SMD:|LED_SMD:|Diode_SMD:|Package_TO_SOT_SMD:|Jumper:|mega-kvm-power:MSOP)',
                         p['footprint'])
        if small:   # dense passives: reference on the fab layer, not silk
            ref_t = fp.Reference()
            ref_t.SetLayer(pcbnew.F_Fab)
        board.Add(fp)
        for pad in fp.Pads():
            net = p['pads'].get(pad.GetNumber())
            if net:
                pad.SetNet(nets[net])
        if ref not in cfg['place']:
            missing.append(ref)
            continue
        x, y, rot, side = (list(cfg['place'][ref]) + [0, 'F'])[:4]
        fp.SetPosition(vec(ox + x, oy + y))
        if side == 'B':
            fp.Flip(vec(ox + x, oy + y), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
        fp.SetOrientationDegrees(rot)
    if missing:
        raise SystemExit('no placement for: ' + ' '.join(missing))

    w, h = cfg['size']
    add_outline(board, [(ox, oy), (ox + w, oy), (ox + w, oy + h), (ox, oy + h)])
    for z in cfg['zones']:
        net, layer, pts = z[:3]
        prio = z[3] if len(z) > 3 else 0
        lay = pcbnew.F_Cu if layer == 'F' else pcbnew.B_Cu
        add_zone(board, nets, net, lay, [(ox + a, oy + b) for a, b in pts], prio)
    for net, x, y in cfg.get('vias', []):
        v = pcbnew.PCB_VIA(board)
        v.SetPosition(vec(ox + x, oy + y))
        v.SetWidth(MM(0.8))
        v.SetDrill(MM(0.4))
        v.SetNet(nets[net])
        board.Add(v)
    for t in cfg.get('texts', []):
        txt, x, y = t[:3]
        side = t[3] if len(t) > 3 else 'F'
        size = t[4] if len(t) > 4 else 1.5
        add_text(board, txt, ox + x, oy + y, pcbnew.F_SilkS if side == 'F' else pcbnew.B_SilkS,
                 size, mirror=(side == 'B'))

    board.BuildConnectivity()   # island removal needs it; without it the fill varies run to run
    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    out = os.path.join(pdir, name + '.kicad_pcb')
    board.Save(out)
    set_copper_2oz(out)
    print('wrote', out, len(parts), 'parts')


def set_copper_2oz(path):
    """Insert a 2-layer stackup with 70 um (2 oz) copper."""
    t = open(path).read()
    stack = ('(stackup\n'
             '\t\t\t(layer "F.SilkS" (type "Top Silk Screen"))\n'
             '\t\t\t(layer "F.Paste" (type "Top Solder Paste"))\n'
             '\t\t\t(layer "F.Mask" (type "Top Solder Mask") (thickness 0.01))\n'
             '\t\t\t(layer "F.Cu" (type "copper") (thickness 0.07))\n'
             '\t\t\t(layer "dielectric 1" (type "core") (thickness 1.44) (material "FR4") (epsilon_r 4.5) (loss_tangent 0.02))\n'
             '\t\t\t(layer "B.Cu" (type "copper") (thickness 0.07))\n'
             '\t\t\t(layer "B.Mask" (type "Bottom Solder Mask") (thickness 0.01))\n'
             '\t\t\t(layer "B.Paste" (type "Bottom Solder Paste"))\n'
             '\t\t\t(layer "B.SilkS" (type "Bottom Silk Screen"))\n'
             '\t\t\t(copper_finish "HAL lead-free")\n'
             '\t\t\t(dielectric_constraints no)\n'
             '\t\t)')
    if '(stackup' in t:
        t = re.sub(r'\(stackup.*?\n\t\t\)', stack, t, count=1, flags=re.S)
    else:
        t = t.replace('(setup', '(setup\n\t\t' + stack, 1)
    open(path, 'w').write(t)


if __name__ == '__main__':
    for w in sys.argv[1:] or ['main', 'inputs']:
        build(w)
