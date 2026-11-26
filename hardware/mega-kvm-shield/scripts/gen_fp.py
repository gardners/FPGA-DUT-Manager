#!/usr/bin/env python3
"""Project footprints (lib/shield.pretty).

Mimas_Header_Socket_2x40: the shield side of a Mimas A7 V3 2x40 header.
Pads are named like the schematic symbol: A1..A40, B1..B40. Row n is at
x = (n-1)*2.54, column A at y = 0, column B at y = -2.54 (seen from the top
of the shield, which is how both P12 and P13 appear on the Numato drawing:
B row above A row). The female socket itself sits on the shield's BOTTOM
side, so body/courtyard are drawn on the B.* layers; the footprint stays
on the front so the pad positions read the same as the drawing.
Rows 34-39 keep their pads (alignment) but are never connected.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'lib', 'shield.pretty')
P = 2.54


def line(x1, y1, x2, y2, layer, w=0.12):
    return ('  (fp_line (start %.3f %.3f) (end %.3f %.3f) (stroke (width %.2f) (type solid)) '
            '(layer "%s"))\n' % (x1, y1, x2, y2, w, layer))


def rect(x1, y1, x2, y2, layer, w=0.12):
    return ('  (fp_rect (start %.3f %.3f) (end %.3f %.3f) (stroke (width %.2f) (type solid)) '
            '(fill no) (layer "%s"))\n' % (x1, y1, x2, y2, w, layer))


def text(t, x, y, layer, size=1.0, kind='user'):
    mirror = ' (justify mirror)' if layer.startswith('B.') else ''
    return ('  (fp_text %s "%s" (at %.3f %.3f) (layer "%s") (effects (font (size %.2f %.2f) '
            '(thickness %.2f))%s))\n' % (kind, t, x, y, layer, size, size, size * 0.15, mirror))


def socket():
    n = 40
    x0, x1 = -P / 2, (n - 1) * P + P / 2
    y0, y1 = -P - P / 2, P / 2
    s = '(footprint "Mimas_Header_Socket_2x40"\n  (version 20241229)\n  (generator "gen_fp.py")\n'
    s += '  (layer "F.Cu")\n'
    s += ('  (descr "Numato Mimas A7 V3 P12/P13 mate: 2x40 female socket 2.54 mm on the shield '
          'bottom side. Pads A<row>/B<row>. Rows 34-39 = FPGA config pins: never connect.")\n')
    s += '  (tags "Mimas A7 header socket 2x40")\n'
    s += ('  (property "Reference" "REF**" (at %.3f %.3f 0) (layer "F.SilkS") '
          '(effects (font (size 1.2 1.2) (thickness 0.18))))\n' % (-4.5, -1.27))
    s += ('  (property "Value" "Mimas_Header_Socket_2x40" (at %.3f %.3f 0) (layer "F.Fab") '
          '(effects (font (size 1 1) (thickness 0.15))))\n' % (n * P / 2, 2.6))
    s += '  (attr through_hole)\n'
    s += rect(x0, y0, x1, y1, 'B.SilkS')
    s += rect(x0, y0, x1, y1, 'B.Fab', 0.1)
    s += rect(x0 - 0.25, y0 - 0.25, x1 + 0.25, y1 + 0.25, 'B.CrtYd', 0.05)
    s += rect(x0 - 0.25, y0 - 0.25, x1 + 0.25, y1 + 0.25, 'F.CrtYd', 0.05)
    s += rect(x0, y0, x1, y1, 'F.Fab', 0.1)
    # top-side silk: outline ends, row numbers, config keep-out marker
    s += line(x0, y0, x0, y1, 'F.SilkS')
    s += line(x1, y0, x1, y1, 'F.SilkS')
    for r in (1, 10, 20, 30, 40):
        s += text(str(r), (r - 1) * P, -P - 2.3, 'F.SilkS', 0.8)
    s += text('A', -2.2, 0, 'F.SilkS', 0.8)
    s += text('B', -2.2, -P, 'F.SilkS', 0.8)
    s += rect(33 * P - P / 2 + 0.1, y0 + 0.1, 38 * P + P / 2 - 0.1, y1 - 0.1, 'F.Fab', 0.1)
    s += text('34-39 NC', 35.5 * P, 2.6, 'F.SilkS', 0.8)
    for r in range(1, n + 1):
        for col, y in (('A', 0.0), ('B', -P)):
            shape = 'rect' if (r == 1 and col == 'A') else 'circle'
            s += ('  (pad "%s%d" thru_hole %s (at %.3f %.3f) (size 1.7 1.7) (drill 1.0) '
                  '(layers "*.Cu" "*.Mask"))\n' % (col, r, shape, (r - 1) * P, y))
    s += ')\n'
    return s


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, 'Mimas_Header_Socket_2x40.kicad_mod'), 'w') as f:
        f.write(socket())
    print('wrote', OUT)
