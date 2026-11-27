#!/usr/bin/env python3
"""Laser-cut bench plate (base + lid) for the K325T, two Mimas A7, the
XC4418 relay module and the Arduino Yun (issue 0058).

  python3 build.py            # writes out/*.svg, out/*.png, out/layout.md
  python3 build.py --no-png   # skip the PNG previews (needs inkscape)

Two layouts:
  main: one row, right to left K325T, Mimas #1, Mimas #2, relay board,
        Arduino (the owner's layout). Comes out wider than 400 mm.
  alt:  K325T, Mimas #1, Mimas #2 in the front row; the relay board (long
        side along X) and the Arduino in a rear row behind the two Mimas.
        Fits in 400 mm.

Plate coordinates: x right, p = mm behind the plate's front edge. In the
SVG the front edge is at the bottom (SVG y = depth - p), i.e. the drawing
is the plate seen from above by someone standing in front of it.
SVG conventions follow hardware/mega-kvm-case: width/height in mm,
viewBox in mm, layer "cut" = red #ff0000 0.01 mm hairlines, layer
"engrave" = black 0.2 mm lines (single-stroke text from that project's
font, so nothing depends on fonts on the laser PC).
"""
import os
import shutil
import subprocess
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'mega-kvm-case'))
from casegen import font                     # noqa: E402  (single-stroke font, reused as-is)

import boards as B                           # noqa: E402

OUT = os.path.join(HERE, 'out')

# ------------------------------------------------------------ parameters
FRONT_MARGIN = 50.0     # owner: plate extends 50 mm in front of the jack fronts
REAR_MARGIN = 50.0      # owner: ... and 50 mm behind the rearmost PCB edge
SIDE_MARGIN = 20.0      # not specified: clears the 10 mm corner holes' standoffs
FPGA_GAP = 25.0         # owner: K325T <-> Mimas #1 <-> Mimas #2
RELAY_GAP = 20.0        # not specified: Mimas #2 <-> relay board
ARDUINO_GAP = 15.0      # not specified: relay board <-> Arduino
ROW_GAP = 45.0          # alt only: Mimas rear (HDMI) edge <-> rear row (HDMI plugs + bend)
CORNER_IN = 10.0        # owner: corner holes 10 mm in from each plate corner
PLATE_HOLE = 3.2        # owner said 3 mm holes: 3.2 = M3 clearance
WIDTH_LIMIT = 400.0     # owner: rack shelf

CUT = 'fill:none;stroke:#ff0000;stroke-width:0.01'
ENG = ('fill:none;stroke:#000000;stroke-width:0.2;'
       'stroke-linecap:round;stroke-linejoin:round')


def f(x):
    s = ('%.3f' % x).rstrip('0').rstrip('.')
    return '0' if s in ('', '-0') else s


class Placed:
    def __init__(self, board, x0, p0):
        self.b, self.x0, self.p0 = board, x0, p0   # p0 = PCB front edge

    def pt(self, u, d):
        return self.x0 + u, self.p0 + d

    @property
    def x1(self):
        return self.x0 + self.b.w

    @property
    def p1(self):
        return self.p0 + self.b.d

    @property
    def front(self):
        """Frontmost point (jack front, or the PCB edge)."""
        return self.p0 + min(0.0, self.b.jack_front)


class Layout:
    def __init__(self, name, title, placed, between, width, depth):
        self.name, self.title = name, title
        self.placed, self.between = placed, between
        self.W, self.D = width, depth

    def corner_holes(self):
        c = CORNER_IN
        return [(c, c), (self.W - c, c), (c, self.D - c), (self.W - c, self.D - c)]


# ------------------------------------------------------------ layouts
def _row_right_to_left(boards_gaps, x_right, jack_line, align_pcb_to=None):
    """Place boards right to left from x_right; every jack front on
    jack_line; boards without a jack get their PCB front at align_pcb_to."""
    placed, x = [], x_right
    for board, gap_after in boards_gaps:
        x -= board.w
        if board.jack:
            p0 = jack_line - board.jack_front
        else:
            p0 = align_pcb_to
        placed.append(Placed(board, x, p0))
        x -= gap_after
    return placed


def main_layout():
    J = FRONT_MARGIN                          # jack fronts all on p = 50
    row = [(B.K325T, FPGA_GAP), (B.MIMAS1, FPGA_GAP), (B.MIMAS2, RELAY_GAP),
           (B.relay(long_along_x=False), ARDUINO_GAP), (B.YUN, 0.0)]
    span = sum(b.w for b, _ in row) + sum(g for _, g in row[:-1])
    W = span + 2 * SIDE_MARGIN
    mimas_pcb_front = J - B.MIMAS1.jack_front
    placed = _row_right_to_left(row, W - SIDE_MARGIN, J, align_pcb_to=mimas_pcb_front)
    rear = max(pl.p1 for pl in placed)
    D = rear + REAR_MARGIN
    by = {pl.b.key: pl for pl in placed}
    mid = (J + rear) / 2
    between = [((by['k325t'].x0 + by['mimas1'].x1) / 2, mid),
               ((by['mimas1'].x0 + by['mimas2'].x1) / 2, mid),
               ((by['mimas2'].x0 + by['relay'].x1) / 2, mid)]
    return Layout('main', 'Bench plate (owner layout, one row)', placed, between, W, D)


def alt_layout():
    J = FRONT_MARGIN
    row = [(B.K325T, FPGA_GAP), (B.MIMAS1, FPGA_GAP), (B.MIMAS2, 0.0)]
    span = sum(b.w for b, _ in row) + 2 * FPGA_GAP
    W = span + 2 * SIDE_MARGIN
    front = _row_right_to_left(row, W - SIDE_MARGIN, J)
    by = {pl.b.key: pl for pl in front}
    m1, m2 = by['mimas1'], by['mimas2']
    # Rear row behind the two Mimas: Arduino on the left (its RJ45 still
    # faces the front), relay board long side along X on the right.
    j2 = m1.p1 + ROW_GAP                      # Arduino jack front
    yun = Placed(B.YUN, m2.x0, j2 - B.YUN.jack_front)
    rl = B.relay(long_along_x=True)
    relay = Placed(rl, m1.x1 - rl.w, yun.p0)
    assert relay.x0 - yun.x1 >= 10.0, 'rear row does not fit behind the Mimas pair'
    placed = front + [relay, yun]
    rear = max(pl.p1 for pl in placed)
    D = rear + REAR_MARGIN
    mid = (J + max(pl.p1 for pl in front)) / 2
    between = [((by['k325t'].x0 + m1.x1) / 2, mid),
               ((m1.x0 + m2.x1) / 2, mid),
               ((m1.x0 + m2.x1) / 2, (m1.p1 + yun.front) / 2)]
    return Layout('alt', 'Bench plate (alternative, <= 400 mm)', placed, between, W, D)


# ------------------------------------------------------------ SVG
HEAD = ('<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" '
        'xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd" '
        'width="{w}mm" height="{h}mm" viewBox="0 0 {w} {h}" version="1.1">\n'
        '<title>{title}</title>\n'
        '<sodipodi:namedview inkscape:document-units="mm" pagecolor="#ffffff"/>\n')


class Sheet:
    """Collects cut and engrave geometry in plate coordinates (x, p)."""

    def __init__(self, L):
        self.L = L
        self.cut, self.eng = [], []

    def y(self, p):
        return self.L.D - p

    def poly(self, pts, closed=True):
        d = 'M ' + ' L '.join('%s,%s' % (f(x), f(self.y(p))) for x, p in pts)
        return d + (' Z' if closed else '')

    def rect(self, x0, p0, x1, p1, layer):
        (self.cut if layer == 'cut' else self.eng).append(
            '<path d="%s" style="%s"/>' % (self.poly([(x0, p0), (x1, p0), (x1, p1), (x0, p1)]),
                                           CUT if layer == 'cut' else ENG))

    def hole(self, x, p, dia):
        self.cut.append('<circle cx="%s" cy="%s" r="%s" style="%s"/>' % (
            f(x), f(self.y(p)), f(dia / 2), CUT))

    def ring(self, x, p, dia):
        self.eng.append('<circle cx="%s" cy="%s" r="%s" style="%s"/>' % (
            f(x), f(self.y(p)), f(dia / 2), ENG))

    def text(self, s, x, p, size, vertical=False, anchor='middle'):
        """Text in plate coords; font.text works in SVG (y-down) coords."""
        lines = (font.text_vertical(s, x, self.y(p), size) if vertical
                 else font.text(s, x, self.y(p), size, anchor=anchor))
        for pl in lines:
            self.eng.append('<path d="M %s" style="%s"/>' % (
                ' L '.join('%s,%s' % (f(a), f(b)) for a, b in pl), ENG))

    def arrow_front(self, x, p, size=4.0):
        """Engraved arrow pointing to the plate front (down the drawing)."""
        h = size
        self.eng.append('<path d="%s" style="%s"/>' % (
            self.poly([(x, p + 2 * h), (x, p)], closed=False), ENG))
        self.eng.append('<path d="%s" style="%s"/>' % (
            self.poly([(x - h / 2, p + h * 0.8), (x, p), (x + h / 2, p + h * 0.8)], closed=False), ENG))

    def save(self, path, title):
        out = [HEAD.format(w=f(self.L.W), h=f(self.L.D), title=escape(title)),
               '<g inkscape:groupmode="layer" inkscape:label="cut (red hairline)" id="cut">']
        out += self.cut
        out += ['</g>',
                '<g inkscape:groupmode="layer" inkscape:label="engrave (black)" id="engrave">']
        out += self.eng
        out += ['</g>', '</svg>\n']
        with open(path, 'w') as fh:
            fh.write('\n'.join(out))


def plate_common(s, L):
    s.rect(0, 0, L.W, L.D, 'cut')
    for x, p in L.corner_holes() + L.between:
        s.hole(x, p, PLATE_HOLE)


def base_sheet(L):
    s = Sheet(L)
    plate_common(s, L)
    for pl in L.placed:
        b = pl.b
        s.rect(pl.x0, pl.p0, pl.x1, pl.p1, 'eng')                 # PCB outline
        for u, d in b.holes:
            x, p = pl.pt(u, d)
            s.hole(x, p, b.hole_d)
            s.ring(x, p, 6.0)                                      # standoff footprint
        cx = pl.x0 + b.w / 2
        if b.jack:
            u0, d0, u1, d1 = b.jack
            s.rect(pl.x0 + u0, pl.p0 + d0, pl.x0 + u1, pl.p0 + d1, 'eng')
            jx = pl.x0 + (u0 + u1) / 2
            s.text('RJ45', jx, pl.p0 + (d0 + d1) / 2, 2.5)
            s.arrow_front(jx, pl.front - 10.0)                     # jack faces the front
        for size in (5.0, 3.5):
            if font.text_width(b.name, size) <= b.w - 8:
                s.text(b.name, cx, pl.p0 + b.d / 2, size)
                break
        else:
            s.text(b.name, cx, pl.p0 + b.d / 2, 5.0, vertical=True)
        for t, u, d in b.notes:
            s.text(t, pl.x0 + u, pl.p0 + d, 3.0)
    s.text('FRONT  - RJ45 JACKS THIS SIDE -  FRONT', L.W / 2, 22.0, 5.0)
    s.text('FPGA-DUT-MANAGER BENCH PLATE - BASE', L.W / 2, L.D - 25.0, 5.0)
    return s


def lid_sheet(L):
    s = Sheet(L)
    plate_common(s, L)
    s.text('FRONT', L.W / 2, 22.0, 5.0)
    s.text('FPGA-DUT-MANAGER BENCH PLATE - LID', L.W / 2, L.D - 25.0, 5.0)
    return s


# ------------------------------------------------------------ preview
COLOURS = {'k325t': '#c8e6c9', 'mimas1': '#bbdefb', 'mimas2': '#bbdefb',
           'relay': '#ffe0b2', 'yun': '#e1bee7'}


def preview(L, path):
    y = lambda p: L.D - p
    el = ['<rect x="0" y="0" width="%s" height="%s" style="fill:#f3e9d2;stroke:#ff0000;stroke-width:0.4"/>'
          % (f(L.W), f(L.D))]
    for pl in L.placed:
        b = pl.b
        el.append('<rect x="%s" y="%s" width="%s" height="%s" style="fill:%s;stroke:#333;stroke-width:0.4"/>'
                  % (f(pl.x0), f(y(pl.p1)), f(b.w), f(b.d), COLOURS[b.key]))
        if b.jack:
            u0, d0, u1, d1 = b.jack
            el.append('<rect x="%s" y="%s" width="%s" height="%s" style="fill:#999;stroke:#333;stroke-width:0.3"/>'
                      % (f(pl.x0 + u0), f(y(pl.p0 + d1)), f(u1 - u0), f(d1 - d0)))
        for u, d in b.holes:
            x, p = pl.pt(u, d)
            el.append('<circle cx="%s" cy="%s" r="1.6" style="fill:#fff;stroke:#c00;stroke-width:0.3"/>'
                      % (f(x), f(y(p))))
        el.append('<text x="%s" y="%s" style="font-family:sans-serif;font-size:6px;text-anchor:middle">%s</text>'
                  % (f(pl.x0 + b.w / 2), f(y(pl.p0 + b.d / 2)), escape(b.name)))
        el.append('<text x="%s" y="%s" style="font-family:sans-serif;font-size:4px;text-anchor:middle;fill:#555">'
                  '%s x %s</text>' % (f(pl.x0 + b.w / 2), f(y(pl.p0 + b.d / 2) + 7), f(b.w), f(b.d)))
    for x, p in L.corner_holes() + L.between:
        el.append('<circle cx="%s" cy="%s" r="1.6" style="fill:#fff;stroke:#00f;stroke-width:0.4"/>'
                  % (f(x), f(y(p))))
    el.append('<line x1="0" y1="%s" x2="%s" y2="%s" style="stroke:#888;stroke-width:0.3;stroke-dasharray:2,2"/>'
              % (f(y(FRONT_MARGIN)), f(L.W), f(y(FRONT_MARGIN))))
    el.append('<text x="%s" y="%s" style="font-family:sans-serif;font-size:7px;text-anchor:middle">'
              'FRONT (all RJ45 jacks face this way) - plate %s x %s mm%s</text>'
              % (f(L.W / 2), f(L.D - 20), f(L.W), f(L.D),
                 ' - WIDER THAN %d mm' % WIDTH_LIMIT if L.W > WIDTH_LIMIT else ''))
    with open(path, 'w') as fh:
        fh.write(HEAD.format(w=f(L.W), h=f(L.D), title=escape(L.title + ' preview'))
                 + '\n'.join(el) + '\n</svg>\n')


def png(svg, dpi=96):
    exe = shutil.which('inkscape')
    if not exe or '--no-png' in sys.argv:
        return None
    out = svg[:-4] + '.png'
    subprocess.run([exe, svg, '--export-type=png', '--export-filename=' + out,
                    '--export-dpi=%d' % dpi, '--export-background=#ffffff'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return out


# ------------------------------------------------------------ report
def table(L):
    rows = ['| Board | X left..right | Y front..rear (PCB) | Jack front Y | Size X x Y |',
            '|---|---|---|---|---|']
    for pl in sorted(L.placed, key=lambda q: -q.x0):
        jf = f(pl.front) if pl.b.jack else '-'
        rows.append('| %s | %s..%s | %s..%s | %s | %s x %s |' % (
            pl.b.name, f(pl.x0), f(pl.x1), f(pl.p0), f(pl.p1), jf, f(pl.b.w), f(pl.b.d)))
    holes = ', '.join('(%s, %s)' % (f(x), f(p)) for x, p in L.between)
    corners = ', '.join('(%s, %s)' % (f(x), f(p)) for x, p in L.corner_holes())
    return '\n'.join([
        '### %s' % L.title, '',
        '**Plate %s x %s mm (X x Y)%s.**' % (
            f(L.W), f(L.D), ' -- WIDER THAN %d mm' % WIDTH_LIMIT if L.W > WIDTH_LIMIT
            else ', fits the %d mm limit' % WIDTH_LIMIT), '',
        'Coordinates in mm from the plate\'s front-left corner (X right, Y towards the rear; '
        'in the SVG the front is at the bottom).', '',
        *rows, '',
        'Corner holes: %s. Between-board holes: %s. All Ø%s.' % (corners, holes, f(PLATE_HOLE)), ''])


def main():
    os.makedirs(OUT, exist_ok=True)
    report = ['# Bench plate layout (generated by build.py, do not edit)', '',
              'Margins: front %s (from the jack fronts), rear %s, sides %s. Gaps: K325T/Mimas %s, '
              'Mimas/Mimas %s, Mimas/relay %s, relay/Arduino %s, alt row gap %s.' % tuple(
                  f(v) for v in (FRONT_MARGIN, REAR_MARGIN, SIDE_MARGIN, FPGA_GAP, FPGA_GAP,
                                 RELAY_GAP, ARDUINO_GAP, ROW_GAP)), '']
    for L, suffix in ((main_layout(), ''), (alt_layout(), '-alt')):
        base_sheet(L).save(os.path.join(OUT, 'base%s.svg' % suffix), L.title + ' - base')
        lid_sheet(L).save(os.path.join(OUT, 'lid%s.svg' % suffix), L.title + ' - lid')
        pv = os.path.join(OUT, 'preview%s.svg' % suffix)
        preview(L, pv)
        png(pv)
        report.append(table(L))
        flag = '  ** WIDER THAN %d mm **' % WIDTH_LIMIT if L.W > WIDTH_LIMIT else ''
        print('%-5s plate %.1f x %.1f mm%s' % (L.name, L.W, L.D, flag))
    with open(os.path.join(OUT, 'layout.md'), 'w') as fh:
        fh.write('\n'.join(report))


if __name__ == '__main__':
    main()
