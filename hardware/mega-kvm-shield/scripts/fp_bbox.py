#!/usr/bin/env python3
"""Print bounding box, courtyard and first pads of library footprints.

Run inside the KiCad flatpak:
  flatpak run --command=python3 org.kicad.KiCad fp_bbox.py Lib:Name ...
"""
import sys
import pcbnew

LIB = '/app/extensions/Library/footprints/'


def mm(v):
    return round(pcbnew.ToMM(v), 2)


for spec in sys.argv[1:]:
    lib, name = spec.split(':')
    fp = pcbnew.FootprintLoad(LIB + lib + '.pretty', name)
    if fp is None:
        print('missing', spec)
        continue
    bb = fp.GetBoundingBox(False)
    print(spec, 'bbox x', mm(bb.GetLeft()), mm(bb.GetRight()),
          'y', mm(bb.GetTop()), mm(bb.GetBottom()))
    cy = fp.GetCourtyard(pcbnew.F_CrtYd)
    if cy.OutlineCount():
        c = cy.BBox()
        print('  crtyd x', mm(c.GetLeft()), mm(c.GetRight()),
              'y', mm(c.GetTop()), mm(c.GetBottom()))
    pads = [(p.GetNumber(), mm(p.GetPosition().x), mm(p.GetPosition().y))
            for p in fp.Pads()]
    print('  pads', pads[:4], '...', pads[-3:], len(pads))
