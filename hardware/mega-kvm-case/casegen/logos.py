"""Logo etch slots (issue 0051).

A slot reads logos/<file>.svg when present and embeds it, scaled to fit the
slot and centred, as a single-colour (black) etch. Logos are never redrawn
by the generator: without a file the slot is a labelled placeholder box in
the hidden reference layer, so nothing is etched by accident.
"""
import os
import re

from . import font
from .geom import RRect

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _attrs(s):
    return dict(re.findall(r'([\w:-]+)="([^"]*)"', s))


def load(spec):
    """Return (viewBox (x, y, w, h), inner SVG text in black) or None."""
    path = os.path.join(HERE, 'logos', spec['file'])
    if not os.path.exists(path):
        return None
    t = open(path, encoding='utf-8', errors='replace').read()
    m = re.search(r'<svg\b([^>]*)>(.*)</svg>', t, re.S)
    if not m:
        return None
    a = _attrs(m.group(1))
    if 'viewBox' in a:
        vb = tuple(float(x) for x in re.split(r'[ ,]+', a['viewBox'].strip()))
    else:
        num = lambda s: float(re.match(r'[-\d.]+', s).group(0))
        vb = (0.0, 0.0, num(a['width']), num(a['height']))
    inner = m.group(2)
    inner = re.sub(r'<metadata.*?</metadata>|<sodipodi:namedview.*?(/>|</sodipodi:namedview>)', '', inner, flags=re.S)
    keep = [k.lower() for k in (spec.get('keep') or [])]
    if keep:
        def drop(mm):
            el = mm.group(0)
            fm = re.search(r'fill\s*[:=]\s*"?\s*(#[0-9a-fA-F]{3,8})', el)
            return el if fm and fm.group(1).lower()[:7] in keep else ''
        inner = re.sub(r'<(path|rect|circle|ellipse|polygon)\b[^>]*?/>', drop, inner, flags=re.S)
    # every colour -> black; strip ids (several copies may share a sheet)
    inner = re.sub(r'#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?\b|#[0-9a-fA-F]{3}\b', '#000000', inner)
    inner = re.sub(r'\sid="[^"]*"', '', inner)
    return vb, inner


def slot(cfg, p, name, uc, vc, w=None, h=None):
    """Place logo slot 'name' centred on (uc, vc). Returns a note for the report."""
    spec = cfg.LOGOS[name]
    w = w or spec['w']
    h = h or spec['h']
    got = load(spec)
    if got is None:
        p.ref.append(RRect(uc, vc, w, h, 2.0))
        for pl in font.text(spec['label'] + ' LOGO', uc, vc - 3.0, 4.0):
            p.refline(pl)
        for pl in font.text('PLACEHOLDER: ADD LOGOS/' + spec['file'].upper(), uc, vc + 4.0, 2.2):
            p.refline(pl)
        return '%s: placeholder box %.0f x %.0f (no logos/%s)' % (name, w, h, spec['file'])
    (vx, vy, vw, vh), inner = got
    s = min(w / vw, h / vh)
    dw, dh = vw * s, vh * s
    u0, v0 = uc - dw / 2, vc - dh / 2
    p.raw.append(((s, 0, 0, s, u0 - vx * s, v0 - vy * s), inner))
    p.ref.append(RRect(uc, vc, w, h, 2.0))
    return '%s: logos/%s etched at %.1f x %.1f mm' % (name, spec['file'], dw, dh)
