"""Autoroute helper (optional): Specctra round trip through Freerouting.

  KPY=(flatpak run --command=python3 org.kicad.KiCad)
  $KPY tools/route.py export          # board -> route/front.dsn
  java -jar freerouting-1.9.0.jar -de route/front.dsn -do route/front.ses -mp 40
  $KPY tools/route.py import          # route/front.ses -> tracks.json
  tools/build_all.sh                  # rebuilds the board with tracks.json

tracks.json holds the tracks and vias in board coordinates, so the board
stays fully generated: delete tracks.json to get an unrouted board again.
"""
import json
import os
import sys

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
PDIR = os.path.join(HERE, '..')
PCB = os.path.join(PDIR, 'mega-kvm-front.kicad_pcb')
RDIR = os.path.join(PDIR, 'route')
ORIGIN = (100.0, 100.0)
# Freerouting necks tracks down at fine-pitch pads (to 0.125-0.187 mm);
# the board rule is 0.2 mm, so widen them back (DRC checks the clearance).
MIN_W = 0.2


def export():
    os.makedirs(RDIR, exist_ok=True)
    b = pcbnew.LoadBoard(PCB)
    for t in list(b.GetTracks()):
        b.Remove(t)
    # Without the pours GND is exported as an ordinary net, so Freerouting
    # routes it: a pour cut up by tracks on both layers otherwise leaves GND
    # islands. The pours are added back (and refilled) by pcb_build.py.
    for z in list(b.Zones()):
        if not z.GetIsRuleArea():
            b.Remove(z)
    dsn = os.path.join(RDIR, 'front.dsn')
    ok = pcbnew.ExportSpecctraDSN(b, dsn)
    shrink_boundary(dsn, EDGE_INSET_UM)
    safe_names(dsn)
    # Route with 0.175 mm instead of 0.15 mm, so that widening the necked
    # tracks back to MIN_W on import keeps the 0.15 mm board clearance.
    txt = open(dsn).read().replace('(clearance 150)', '(clearance 175)')
    open(dsn, 'w').write(txt)
    print('dsn', ok)


# Freerouting only keeps its normal clearance (0.15 mm) from the outline;
# the board rule is 0.5 mm copper-to-edge. Shrink the routing boundary.
EDGE_INSET_UM = 400


# Freerouting 2.x loses wires on nets whose names need quoting (KiCad's
# active-low "~{X}" names): route with plain names, map back on import.
NETMAP = os.path.join(RDIR, 'netmap.json')


def safe_names(path):
    import re
    txt = open(path).read()
    # The header's (string_quote ") would pair with the first real quote.
    cut = txt.index('(structure')
    head, txt = txt[:cut], txt[cut:]
    names = sorted(set(re.findall(r'"([^"\n]*)"', txt)))
    names = [n for n in names if '{' in n or '~' in n or '(' in n]
    m = {n: 'QN%03d' % i for i, n in enumerate(names)}
    for n, k in m.items():
        txt = txt.replace('"%s"' % n, k)
    open(path, 'w').write(head + txt)
    json.dump(m, open(NETMAP, 'w'), indent=0)


def restore_names(src, dst):
    import re
    m = json.load(open(NETMAP)) if os.path.exists(NETMAP) else {}
    back = {k: n for n, k in m.items()}
    txt = open(src).read()
    txt = re.sub(r'\bQN\d{3}\b', lambda x: '"%s"' % back[x.group(0)], txt)
    open(dst, 'w').write(txt)


def shrink_boundary(path, inset):
    import re
    txt = open(path).read()
    m = re.search(r'\(boundary\s*\(path pcb 0([^)]*)\)', txt)
    nums = [float(v) for v in m.group(1).split()]
    xs, ys = nums[0::2], nums[1::2]
    x0, x1, y0, y1 = min(xs) + inset, max(xs) - inset, min(ys) + inset, max(ys) - inset
    pts = [(x1, y0), (x0, y0), (x0, y1), (x1, y1), (x1, y0)]
    path_txt = ' '.join('%g %g' % p for p in pts)
    txt = txt[:m.start(1)] + '  ' + path_txt + txt[m.end(1):]
    open(path, 'w').write(txt)


def mm(v):
    return round(pcbnew.ToMM(v), 4)


def imp():
    b = pcbnew.LoadBoard(PCB)
    for t in list(b.GetTracks()):
        b.Remove(t)
    ses = os.path.join(RDIR, 'front-names.ses')
    restore_names(os.path.join(RDIR, 'front.ses'), ses)
    if not pcbnew.ImportSpecctraSES(b, ses):
        raise SystemExit('SES import failed')
    tracks, vias = [], []
    for t in b.GetTracks():
        net = t.GetNetname().lstrip('/')
        if t.GetClass() == 'PCB_VIA':
            vias.append({'at': [mm(t.GetPosition().x) - ORIGIN[0], mm(t.GetPosition().y) - ORIGIN[1]],
                         'd': mm(t.GetWidth(pcbnew.F_Cu)), 'drill': mm(t.GetDrill()), 'net': net})
        else:
            tracks.append({'a': [mm(t.GetStart().x) - ORIGIN[0], mm(t.GetStart().y) - ORIGIN[1]],
                           'b': [mm(t.GetEnd().x) - ORIGIN[0], mm(t.GetEnd().y) - ORIGIN[1]],
                           'w': max(mm(t.GetWidth()), MIN_W), 'layer': 'F' if t.GetLayer() == pcbnew.F_Cu else 'B',
                           'net': net})
    with open(os.path.join(PDIR, 'tracks.json'), 'w') as f:
        json.dump({'tracks': tracks, 'vias': vias}, f, indent=0)
    print('tracks', len(tracks), 'vias', len(vias))


if __name__ == '__main__':
    {'export': export, 'import': imp}[sys.argv[1]]()
