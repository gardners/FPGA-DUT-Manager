"""Generate the project-local footprints in lib/mega-kvm-power.pretty.

* Texas_RPW0010A: TPS25947xx VQFN-HR-10 2x2 mm. Pad geometry follows the
  TI RPW0010A example board layout (SLVSFC9C p.70) as read from the
  datasheet text: signal pads 0.6 x 0.25 mm on a 0.45 mm pitch at the
  outer edge (land width 2.4 mm), IN/OUT bars 0.30 x 1.75 mm.
  CHECK AGAINST THE TI DRAWING BEFORE FAB.
* Molex 8981 4-pin peripheral power header (5.08 mm pitch, 1.57 mm pins),
  vertical, e.g. Molex 15-24-4048 / TE 1-350945-0 class. CHECK HOLE SIZES AND
  PEG POSITIONS AGAINST THE CHOSEN PART.
"""
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib', 'mega-kvm-power.pretty')


def head(name, descr, smd=True):
    return ['(footprint "%s"' % name, '\t(version 20241229)', '\t(generator "pcbnew")',
            '\t(generator_version "10.0")', '\t(layer "F.Cu")', '\t(descr "%s")' % descr,
            '\t(attr %s)' % ('smd' if smd else 'through_hole'),
            '\t(property "Reference" "REF**" (at 0 -2.2 0) (layer "F.SilkS") (effects (font (size 0.8 0.8) (thickness 0.12))))',
            '\t(property "Value" "%s" (at 0 2.2 0) (layer "F.Fab") (effects (font (size 0.8 0.8) (thickness 0.12))))' % name]


def line(x1, y1, x2, y2, layer, w=0.12):
    return '\t(fp_line (start %g %g) (end %g %g) (stroke (width %g) (type solid)) (layer "%s"))' % (x1, y1, x2, y2, w, layer)


def rect(x1, y1, x2, y2, layer, w=0.05):
    return '\t(fp_rect (start %g %g) (end %g %g) (stroke (width %g) (type solid)) (fill no) (layer "%s"))' % (x1, y1, x2, y2, w, layer)


def smd(num, x, y, w, h):
    return ('\t(pad "%s" smd roundrect (at %g %g) (size %g %g) (layers "F.Cu" "F.Paste" "F.Mask") '
            '(roundrect_rratio 0.2))' % (num, x, y, w, h))


def tht(num, x, y, d, drill, shape='circle'):
    return ('\t(pad "%s" thru_hole %s (at %g %g) (size %g %g) (drill %g) (layers "*.Cu" "*.Mask"))'
            % (num, shape, x, y, d, d, drill))


def rpw():
    name = 'Texas_RPW0010A_VQFN-HR-10_2x2mm_P0.45mm'
    L = head(name, 'TI RPW0010A VQFN-HR-10 2x2 mm 0.45 mm pitch (TPS25947xx). Pads from TI example layout; verify before fab.')
    ys = [-0.675, -0.225, 0.225, 0.675]
    for i, y in enumerate(ys):           # pins 1..4 down the left side
        L.append(smd(str(i + 1), -0.9, y, 0.6, 0.25))
    for i, y in enumerate(reversed(ys)):  # pins 7..10 up the right side (10 top)
        L.append(smd(str(7 + i), 0.9, y, 0.6, 0.25))
    L.append(smd('5', -0.25, 0, 0.3, 1.75))   # IN
    L.append(smd('6', 0.25, 0, 0.3, 1.75))    # OUT
    L.append(rect(-1.0, -1.0, 1.0, 1.0, 'F.Fab', 0.1))
    L.append(rect(-1.45, -1.25, 1.45, 1.25, 'F.CrtYd'))
    L.append(line(-1.3, -1.15, -0.7, -1.15, 'F.SilkS'))
    L.append('\t(fp_circle (center -1.35 -0.95) (end -1.25 -0.95) (stroke (width 0.12) (type solid)) (fill yes) (layer "F.SilkS"))')
    L.append(')')
    return name, L


def molex8981():
    name = 'Molex_8981_PeripheralPower_1x04_P5.08mm_Vertical'
    L = head(name, 'Molex 8981-series 4-pin peripheral (5.25in drive) power header, vertical, 5.08 mm pitch. 1=+12V 2=GND 3=GND 4=+5V. Verify against chosen part.', smd=False)
    for i in range(4):
        L.append(tht(str(i + 1), i * 5.08, 0, 3.2, 2.0, 'rect' if i == 0 else 'circle'))
    # housing about 21.8 x 8.6 mm, chamfered corners on the pin-4 side marks keying
    x0, x1, y0, y1 = -3.25, 18.49, -4.3, 4.3
    L.append(rect(x0, y0, x1, y1, 'F.Fab', 0.1))
    L.append(rect(x0 - 0.5, y0 - 0.5, x1 + 0.5, y1 + 0.5, 'F.CrtYd'))
    L += [line(x0 - 0.1, y0 - 0.1, x1 + 0.1, y0 - 0.1, 'F.SilkS'), line(x0 - 0.1, y1 + 0.1, x1 + 0.1, y1 + 0.1, 'F.SilkS'),
          line(x0 - 0.1, y0 - 0.1, x0 - 0.1, y1 + 0.1, 'F.SilkS'), line(x1 + 0.1, y0 - 0.1, x1 + 0.1, y1 + 0.1, 'F.SilkS')]
    L.append('\t(fp_text user "+12V" (at 0 -5.4 0) (layer "F.SilkS") (effects (font (size 0.8 0.8) (thickness 0.12))))')
    L[6] = '\t(attr through_hole)'
    L.append(')')
    return name, L


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for fn in (rpw, molex8981):
        name, lines = fn()
        with open(os.path.join(OUT, name + '.kicad_mod'), 'w') as f:
            f.write('\n'.join(lines) + '\n')
        print('wrote', name)
