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


def export():
    os.makedirs(RDIR, exist_ok=True)
    b = pcbnew.LoadBoard(PCB)
    for t in list(b.GetTracks()):
        b.Remove(t)
    ok = pcbnew.ExportSpecctraDSN(b, os.path.join(RDIR, 'front.dsn'))
    print('dsn', ok)


def mm(v):
    return round(pcbnew.ToMM(v), 4)


def imp():
    b = pcbnew.LoadBoard(PCB)
    for t in list(b.GetTracks()):
        b.Remove(t)
    if not pcbnew.ImportSpecctraSES(b, os.path.join(RDIR, 'front.ses')):
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
                           'w': mm(t.GetWidth()), 'layer': 'F' if t.GetLayer() == pcbnew.F_Cu else 'B',
                           'net': net})
    with open(os.path.join(PDIR, 'tracks.json'), 'w') as f:
        json.dump({'tracks': tracks, 'vias': vias}, f, indent=0)
    print('tracks', len(tracks), 'vias', len(vias))


if __name__ == '__main__':
    {'export': export, 'import': imp}[sys.argv[1]]()
