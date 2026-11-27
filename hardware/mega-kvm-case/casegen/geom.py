"""2D geometry for laser-cut panels.

Panel coordinates: mm, origin at the panel's top-left corner as seen from
OUTSIDE the case (from above for base/lid/plate), u to the right, v down
(SVG convention). Shapes are kept as primitives (circle, rounded rectangle,
polygon) so that kerf compensation, SVG, DXF and KiCad output stay exact.
"""
import math


class Circle:
    kind = 'circle'

    def __init__(self, cx, cy, r):
        self.cx, self.cy, self.r = cx, cy, r

    def moved(self, f):
        x, y = f(self.cx, self.cy)
        return Circle(x, y, self.r)

    rot90 = moved

    def bbox(self):
        return (self.cx - self.r, self.cy - self.r, self.cx + self.r, self.cy + self.r)

    def kerf(self, k):          # a hole: the material is outside, so shrink
        return Circle(self.cx, self.cy, max(self.r - k / 2, 0.05))


class RRect:
    """Axis-aligned rectangle centred on (cx, cy) with corner radius r."""
    kind = 'rrect'

    def __init__(self, cx, cy, w, h, r=0.0):
        self.cx, self.cy, self.w, self.h = cx, cy, w, h
        self.r = min(r, w / 2, h / 2)

    def moved(self, f):
        x, y = f(self.cx, self.cy)
        return RRect(x, y, self.w, self.h, self.r)

    def rot90(self, f):
        x, y = f(self.cx, self.cy)
        return RRect(x, y, self.h, self.w, self.r)

    def bbox(self):
        return (self.cx - self.w / 2, self.cy - self.h / 2, self.cx + self.w / 2, self.cy + self.h / 2)

    def kerf(self, k):
        return RRect(self.cx, self.cy, max(self.w - k, 0.1), max(self.h - k, 0.1), max(self.r - k / 2, 0))


class Poly:
    """Closed polygon (list of (u, v))."""
    kind = 'poly'

    def __init__(self, pts):
        self.pts = [tuple(p) for p in pts]

    def moved(self, f):
        return Poly([f(*p) for p in self.pts])

    rot90 = moved

    def bbox(self):
        us = [p[0] for p in self.pts]
        vs = [p[1] for p in self.pts]
        return (min(us), min(vs), max(us), max(vs))

    def kerf(self, k):          # a hole: shrink
        return Poly(offset_polygon(self.pts, -k / 2))


def signed_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    return a / 2


def clean(pts, eps=1e-6):
    """Drop repeated and collinear points."""
    out = []
    for p in pts:
        if out and abs(out[-1][0] - p[0]) < eps and abs(out[-1][1] - p[1]) < eps:
            continue
        out.append(tuple(p))
    while len(out) > 1 and abs(out[0][0] - out[-1][0]) < eps and abs(out[0][1] - out[-1][1]) < eps:
        out.pop()
    changed = True
    while changed and len(out) > 3:
        changed = False
        for i in range(len(out)):
            a, b, c = out[i - 1], out[i], out[(i + 1) % len(out)]
            cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            if abs(cross) < eps:
                out.pop(i)
                changed = True
                break
    return out


def offset_polygon(pts, d):
    """Miter offset; d > 0 grows the enclosed region."""
    pts = clean(pts)
    if signed_area(pts) < 0:
        pts = pts[::-1]
    n = len(pts)
    normals = []
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        L = math.hypot(x1 - x0, y1 - y0)
        # positive shoelace orientation: the outward normal is (dy, -dx)
        normals.append(((y1 - y0) / L, -(x1 - x0) / L))
    out = []
    for i in range(n):
        n1 = normals[i - 1]
        n2 = normals[i]
        dot = n1[0] * n2[0] + n1[1] * n2[1]
        s = d / (1 + dot) if dot > -0.999 else d
        out.append((pts[i][0] + (n1[0] + n2[0]) * s, pts[i][1] + (n1[1] + n2[1]) * s))
    return out


class Panel:
    """A part, or a fragment of one when outline is None."""

    def __init__(self, name, w, h, outline=None, material='panel', qty=1, note=''):
        self.name, self.w, self.h = name, w, h
        self.outline = outline          # list of points, or None for a fragment
        self.cuts = []                  # holes / inner cut-outs
        self.engrave = []               # ('line', pts) open polylines, ('fill', pts) closed
        self.ref = []                   # reference-only shapes (hidden layer)
        self.refl = []                  # reference-only polylines (hidden layer)
        self.raw = []                   # (matrix, svg text) embedded artwork, engrave layer
        self.material, self.qty, self.note = material, qty, note
        self.title = name

    # ---- building
    def cut(self, s):
        self.cuts.append(s)
        return s

    def line(self, pts):
        self.engrave.append(('line', [tuple(p) for p in pts]))

    def fill(self, pts):
        self.engrave.append(('fill', [tuple(p) for p in pts]))

    def place(self, frag, du, dv):
        f = lambda u, v: (u + du, v + dv)
        self.cuts += [s.moved(f) for s in frag.cuts]
        self.engrave += [(k, [f(*p) for p in pts]) for k, pts in frag.engrave]
        self.ref += [s.moved(f) for s in frag.ref]
        self.refl += [[f(*p) for p in pts] for pts in frag.refl]
        self.raw += [(mat_mul((1, 0, 0, 1, du, dv), m), t) for m, t in frag.raw]

    def refline(self, pts):
        self.refl.append([tuple(p) for p in pts])

    def bbox(self):
        if self.outline:
            us = [p[0] for p in self.outline]
            vs = [p[1] for p in self.outline]
            return (min(us), min(vs), max(us), max(vs))
        return (0, 0, self.w, self.h)

    def size(self):
        b = self.bbox()
        return b[2] - b[0], b[3] - b[1]

    def transformed(self, rot, du, dv):
        """Copy rotated by 90 degrees (rot=True) and moved; used for nesting."""
        x0, y0, x1, y1 = self.bbox()
        if rot:
            H = y1 - y0
            f = lambda u, v: (H - (v - y0) + du, (u - x0) + dv)
            M = (0, 1, -1, 0, H + y0 + du, dv - x0)
        else:
            f = lambda u, v: (u - x0 + du, v - y0 + dv)
            M = (1, 0, 0, 1, du - x0, dv - y0)
        p = Panel(self.name, self.w, self.h, None, self.material, self.qty, self.note)
        p.title = self.title
        p.outline = [f(*q) for q in self.outline] if self.outline else None
        p.cuts = [s.rot90(f) for s in self.cuts] if rot else [s.moved(f) for s in self.cuts]
        p.engrave = [(k, [f(*q) for q in pts]) for k, pts in self.engrave]
        p.ref = [s.rot90(f) for s in self.ref] if rot else [s.moved(f) for s in self.ref]
        p.refl = [[f(*q) for q in pts] for pts in self.refl]
        p.raw = [(mat_mul(M, m), t) for m, t in self.raw]
        return p


def mat_mul(a, b):
    """SVG matrices (a, b, c, d, e, f): the result applies b first, then a."""
    return (a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
            a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
            a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5])


def rect_pts(u0, v0, u1, v1):
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def boxes_overlap(a, b, gap=0.0):
    return not (a[2] + gap <= b[0] or b[2] + gap <= a[0] or a[3] + gap <= b[1] or b[3] + gap <= a[1])


def circle_grid(cx, cy, radius, hole_d, pitch):
    """Hex grid of round holes inside a circle (fan grille)."""
    out = []
    row = 0
    y = -radius
    while y <= radius + 1e-9:
        off = (pitch / 2) if row % 2 else 0.0
        x = -radius - off
        while x <= radius + 1e-9:
            if math.hypot(x, y) + hole_d / 2 <= radius:
                out.append(Circle(cx + x, cy + y, hole_d / 2))
            x += pitch
        y += pitch * math.sqrt(3) / 2
        row += 1
    return out
