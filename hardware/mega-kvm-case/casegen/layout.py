"""3D boxes for the fit check and the top-view drawing.

Case coordinates: X across (left to right seen from the front), Y depth
(front face = 0, towards the rear), Z up from the outer bottom.
"""
from .svgout import Drawing

COLOURS = {
    'mimas': '#7fbf7f', 'shield': '#a0d0a0', 'vboard': '#3f8f3f', 'gs105': '#8fa8d8', 'power': '#e0a060',
    'inputs': '#d08040', 'fan': '#b0b0e0', 'front': '#d8c070', 'item': '#c0c0c0', 'cable': '#ffe0e0',
    'plate': '#f4f0d0', 'standoff': '#606060', 'kbd': '#5faf9f',
}


class Box:
    def __init__(self, name, x0, x1, y0, y1, z0, z1, kind='item', hard=True, note='', inside=True):
        self.name = name
        self.x0, self.x1 = min(x0, x1), max(x0, x1)
        self.y0, self.y1 = min(y0, y1), max(y0, y1)
        self.z0, self.z1 = min(z0, z1), max(z0, z1)
        self.kind, self.hard, self.note, self.inside = kind, hard, note, inside

    def xy_gap(self, o):
        dx = max(o.x0 - self.x1, self.x0 - o.x1, 0.0)
        dy = max(o.y0 - self.y1, self.y0 - o.y1, 0.0)
        if dx > 0 and dy > 0:
            return (dx * dx + dy * dy) ** 0.5
        return max(dx, dy)

    def overlaps(self, o):
        return (self.x0 < o.x1 - 1e-6 and o.x0 < self.x1 - 1e-6 and self.y0 < o.y1 - 1e-6 and o.y0 < self.y1 - 1e-6
                and self.z0 < o.z1 - 1e-6 and o.z0 < self.z1 - 1e-6)

    def z_overlap(self, o):
        return self.z0 < o.z1 and o.z0 < self.z1


def check(boxes, interior, allowed=()):
    """Return (problems, clearances). interior = (x0, x1, y0, y1, z0, z1)."""
    problems, clear = [], []
    X0, X1, Y0, Y1, Z0, Z1 = interior
    for b in boxes:
        if not b.inside:
            continue
        over = []
        if b.x0 < X0 - 1e-6: over.append('left wall by %.1f' % (X0 - b.x0))
        if b.x1 > X1 + 1e-6: over.append('right wall by %.1f' % (b.x1 - X1))
        if b.y0 < Y0 - 1e-6: over.append('front by %.1f' % (Y0 - b.y0))
        if b.y1 > Y1 + 1e-6: over.append('rear by %.1f' % (b.y1 - Y1))
        if b.z0 < Z0 - 1e-6: over.append('floor by %.1f' % (Z0 - b.z0))
        if b.z1 > Z1 + 1e-6: over.append('lid/top by %.2f' % (b.z1 - Z1))
        if over:
            problems.append('%s exceeds the interior: %s' % (b.name, ', '.join(over)))
    hard = [b for b in boxes if b.hard]
    for i, a in enumerate(hard):
        for b in hard[i + 1:]:
            if (a.name, b.name) in allowed or (b.name, a.name) in allowed:
                continue
            if a.overlaps(b):
                problems.append('COLLISION: %s and %s' % (a.name, b.name))
    for a in hard:
        best = None
        for b in hard:
            if b is a or not a.z_overlap(b) or (a.name, b.name) in allowed or (b.name, a.name) in allowed:
                continue
            g = a.xy_gap(b)
            if best is None or g < best[0]:
                best = (g, b.name)
        top = Z1 - a.z1
        clear.append((a.name, best, top))
    return problems, clear


def topview(path, title, W, D, boxes, walls_t, extra=None, notes=()):
    m = 15.0
    d = Drawing(W + 2 * m, D + 2 * m + 12 + 4.5 * len(notes), title)
    # Y grows to the rear; draw with the front at the bottom
    tx = lambda x: m + x
    ty = lambda y: m + D - y
    d.rect(tx(0), ty(0), tx(W), ty(D), fill='#f8f8f8', stroke='#000', sw=0.6)
    if walls_t:
        d.rect(tx(walls_t), ty(walls_t), tx(W - walls_t), ty(D - walls_t), fill='none', stroke='#888', sw=0.3)
    for b in sorted(boxes, key=lambda b: (b.hard, b.z0)):
        col = COLOURS.get(b.kind, '#ccc')
        d.rect(tx(b.x0), ty(b.y0), tx(b.x1), ty(b.y1), fill=col, stroke='#333' if b.hard else '#c66',
               sw=0.3, opacity=0.75 if b.hard else 0.5, dash=None if b.hard else '2,1')
        size = 2.6 if (b.x1 - b.x0) > 40 else 1.8
        d.text(tx((b.x0 + b.x1) / 2), ty((b.y0 + b.y1) / 2) + 1, b.name, size=size)
    if extra:
        extra(d, tx, ty)
    d.text(tx(W / 2), ty(-6), 'FRONT', size=4, weight='bold')
    d.text(tx(W / 2), ty(D) - 4, 'REAR', size=4, weight='bold')
    d.text(m, 8, title, size=4, anchor='start', weight='bold')
    y = m + D + 18
    for n in notes:
        d.text(m, y, n, size=3, anchor='start')
        y += 4.5
    d.save(path)
