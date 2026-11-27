"""Print board-local courtyard boxes (and optionally pads) of placed footprints:
flatpak run --command=python3 org.kicad.KiCad tools/fpdump.py inputs [REF ...]"""
import os
import sys

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import placement  # noqa: E402

cfg = placement.BOARDS[sys.argv[1]]
ox, oy = cfg['origin']
b = pcbnew.LoadBoard(os.path.join(HERE, '..', cfg['name'], cfg['name'] + '.kicad_pcb'))
T = pcbnew.ToMM
want = set(sys.argv[2:])
for fp in sorted(b.GetFootprints(), key=lambda f: f.GetReference()):
    ref = fp.GetReference()
    if want and ref not in want:
        continue
    side = 'B' if fp.IsFlipped() else 'F'
    cy = fp.GetCourtyard(pcbnew.B_CrtYd if fp.IsFlipped() else pcbnew.F_CrtYd).BBox()
    print('%-5s %s crtyd x %7.2f..%7.2f y %6.2f..%6.2f' % (ref, side, T(cy.GetX()) - ox, T(cy.GetRight()) - ox,
                                                          T(cy.GetY()) - oy, T(cy.GetBottom()) - oy))
    if want:
        for p in fp.Pads():
            print('      pad %s (%.2f, %.2f) %s' % (p.GetNumber(), T(p.GetPosition().x) - ox,
                                                    T(p.GetPosition().y) - oy, p.GetNetname()))
