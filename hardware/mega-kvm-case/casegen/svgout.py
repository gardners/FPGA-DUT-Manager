"""SVG writers.

Laser files: Inkscape-compatible, width/height in mm, viewBox in mm.
Layer "cut": pure red (#ff0000) hairlines (0.01 mm), no fill, nothing else.
Layer "engrave": black (#000000) lines (and fills).
Layer "reference": hidden (display:none), blue; for fragments and notes,
never cut or engraved (delete or leave hidden).
"""
import os
from xml.sax.saxutils import escape

from .geom import offset_polygon

CUT = 'fill:none;stroke:#ff0000;stroke-width:0.01'
ENG = 'fill:none;stroke:#000000;stroke-width:0.2;stroke-linecap:round;stroke-linejoin:round'
ENG_FILL = 'fill:#000000;stroke:none'
REF = 'fill:none;stroke:#0000ff;stroke-width:0.2;stroke-dasharray:1,1'

HEAD = ('<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" '
        'xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd" '
        'width="{w:.3f}mm" height="{h:.3f}mm" viewBox="0 0 {w:.3f} {h:.3f}" version="1.1">\n'
        '<title>{title}</title>\n'
        '<sodipodi:namedview inkscape:document-units="mm" pagecolor="#ffffff"/>\n')


def f(x):
    s = '%.4f' % x
    s = s.rstrip('0').rstrip('.')
    return s if s not in ('-0', '') else '0'


def poly_d(pts, closed=True):
    d = 'M ' + ' L '.join('%s,%s' % (f(x), f(y)) for x, y in pts)
    return d + (' Z' if closed else '')


def rrect_d(s):
    x0, y0 = s.cx - s.w / 2, s.cy - s.h / 2
    x1, y1 = s.cx + s.w / 2, s.cy + s.h / 2
    r = s.r
    if r <= 1e-6:
        return poly_d([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    a = 'A %s,%s 0 0 1 ' % (f(r), f(r))
    return ('M %s,%s L %s,%s %s%s,%s L %s,%s %s%s,%s L %s,%s %s%s,%s L %s,%s %s%s,%s Z' % (
        f(x0 + r), f(y0), f(x1 - r), f(y0), a, f(x1), f(y0 + r), f(x1), f(y1 - r), a, f(x1 - r), f(y1),
        f(x0 + r), f(y1), a, f(x0), f(y1 - r), f(x0), f(y0 + r), a, f(x0 + r), f(y0)))


def shape_el(s, style):
    if s.kind == 'circle':
        return '<circle cx="%s" cy="%s" r="%s" style="%s"/>' % (f(s.cx), f(s.cy), f(s.r), style)
    if s.kind == 'rrect':
        return '<path d="%s" style="%s"/>' % (rrect_d(s), style)
    return '<path d="%s" style="%s"/>' % (poly_d(s.pts), style)


def panel_layers(p, kerf, ident=''):
    """SVG fragments (cut, engrave, ref) for one panel."""
    cut, eng, ref = [], [], []
    if p.outline:
        out = offset_polygon(p.outline, kerf / 2) if kerf else p.outline
        cut.append('<path d="%s" style="%s"/>' % (poly_d(out), CUT))
    for s in p.cuts:
        cut.append(shape_el(s.kerf(kerf) if kerf else s, CUT))
    for kind, pts in p.engrave:
        if kind == 'fill':
            eng.append('<path d="%s" style="%s"/>' % (poly_d(pts), ENG_FILL))
        else:
            eng.append('<path d="%s" style="%s"/>' % (poly_d(pts, closed=False), ENG))
    for s in p.ref:
        ref.append(shape_el(s, REF))
    return cut, eng, ref


def layered(cut, eng, ref, ident):
    out = ['<g inkscape:groupmode="layer" inkscape:label="cut (red hairline)" id="cut%s">' % ident]
    out += cut
    out.append('</g>')
    out.append('<g inkscape:groupmode="layer" inkscape:label="engrave (black)" id="engrave%s">' % ident)
    out += eng
    out.append('</g>')
    if ref:
        out.append('<g inkscape:groupmode="layer" inkscape:label="reference (hidden, do not cut)" '
                   'id="ref%s" style="display:none">' % ident)
        out += ref
        out.append('</g>')
    return out


def write_panel(p, path, kerf, margin=2.0):
    """One panel (or fragment) in its own file, moved by 'margin'."""
    x0, y0, x1, y1 = p.bbox()
    q = p.transformed(False, margin, margin)
    w, h = x1 - x0 + 2 * margin, y1 - y0 + 2 * margin
    cut, eng, ref = panel_layers(q, kerf)
    if not p.outline:
        from .geom import RRect
        ref.append(_ref_rect(margin, margin, x1 - x0, y1 - y0))
    body = [HEAD.format(w=w, h=h, title=escape(p.title))]
    body += layered(cut, eng, ref, '')
    body.append('</svg>\n')
    _write(path, body)


def _ref_rect(u, v, w, h):
    return '<path d="%s" style="%s"/>' % (poly_d([(u, v), (u + w, v), (u + w, v + h), (u, v + h)]), REF)


def write_sheet(sheet, path, kerf, title):
    """sheet: dict(w, h, items=[(panel_transformed)])"""
    W, H = sheet['w'], sheet['h']
    cut, eng, ref = [], [], []
    for p in sheet['items']:
        c, e, r = panel_layers(p, kerf)
        cut += c
        eng += e
        ref += r
    ref.append(_ref_rect(0, 0, W, H))
    body = [HEAD.format(w=W, h=H, title=escape(title))]
    body += layered(cut, eng, ref, '')
    body.append('</svg>\n')
    _write(path, body)


def _write(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        fh.write('\n'.join(lines))


# ------------------------------------------------------------ drawings
class Drawing:
    """Colour drawing (top views); not a laser file."""

    def __init__(self, w, h, title, scale_note=''):
        self.w, self.h, self.title = w, h, title
        self.els = []

    def rect(self, x0, y0, x1, y1, fill='#ddd', stroke='#333', sw=0.4, opacity=1.0, dash=None):
        st = 'fill:%s;fill-opacity:%s;stroke:%s;stroke-width:%s' % (fill, opacity, stroke, sw)
        if dash:
            st += ';stroke-dasharray:%s' % dash
        self.els.append('<rect x="%s" y="%s" width="%s" height="%s" style="%s"/>' % (
            f(min(x0, x1)), f(min(y0, y1)), f(abs(x1 - x0)), f(abs(y1 - y0)), st))

    def circle(self, x, y, r, fill='none', stroke='#333', sw=0.3):
        self.els.append('<circle cx="%s" cy="%s" r="%s" style="fill:%s;stroke:%s;stroke-width:%s"/>' % (
            f(x), f(y), f(r), fill, stroke, sw))

    def line(self, pts, stroke='#333', sw=0.3, dash=None):
        st = 'fill:none;stroke:%s;stroke-width:%s' % (stroke, sw)
        if dash:
            st += ';stroke-dasharray:%s' % dash
        self.els.append('<path d="%s" style="%s"/>' % (poly_d(pts, closed=False), st))

    def text(self, x, y, s, size=3.0, fill='#000', anchor='middle', weight='normal'):
        self.els.append('<text x="%s" y="%s" style="font-family:sans-serif;font-size:%spx;fill:%s;'
                        'text-anchor:%s;font-weight:%s">%s</text>' % (f(x), f(y), f(size), fill, anchor,
                                                                       weight, escape(s)))

    def save(self, path):
        body = [HEAD.format(w=self.w, h=self.h, title=escape(self.title)),
                '<rect x="0" y="0" width="%s" height="%s" style="fill:#ffffff"/>' % (f(self.w), f(self.h))]
        body += self.els
        body.append('</svg>\n')
        _write(path, body)
