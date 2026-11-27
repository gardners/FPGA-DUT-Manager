import pcbnew, sys
SYS = '/app/extensions/Library/footprints'
for fid in sys.argv[1:]:
    lib, name = fid.split(':')
    fp = pcbnew.FootprintLoad(SYS + '/' + lib + '.pretty', name)
    cy = fp.GetCourtyard(pcbnew.F_CrtYd).BBox()
    T = pcbnew.ToMM
    pads = ' '.join('%s(%.2f,%.2f)' % (p.GetNumber(), T(p.GetPosition().x), T(p.GetPosition().y)) for p in fp.Pads())
    print(name, 'crtyd x %.2f..%.2f y %.2f..%.2f' % (T(cy.GetX()), T(cy.GetRight()), T(cy.GetY()), T(cy.GetBottom())), pads)
