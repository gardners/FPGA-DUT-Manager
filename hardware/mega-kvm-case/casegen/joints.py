"""Finger-joint outlines for rectangular box panels.

A panel is W x H (nominal, outer dimensions in its plane). Each edge gets
a spec:
  ('plain',)                     straight edge
  ('plain', notches)             straight, with T-slot notches [(s_centre, width, depth)]
  ('fingers', 'A' | 'B', t)      fingers of depth t (material thickness)

Two mating edges have the same length, hence the same finger count, and
opposite phases: 'A' has fingers (material out to the nominal line) at both
ends, 'B' has gaps there. The corner cubes then come out consistently:
the base owns the bottom corners (A on all its edges), the walls' bottom
edges are B; at the vertical corners the front/rear are A, the sides B.
"""
from .geom import clean


def finger_count(L, fw):
    n = max(3, int(round(L / fw)))
    if n % 2 == 0:
        n += 1
    return n


def edge_points(L, spec, fw):
    """Edge-local points (s along the edge, d = inset towards the inside)."""
    kind = spec[0]
    if kind == 'plain':
        pts = [(0.0, 0.0)]
        for (c, w, depth) in sorted(spec[1] if len(spec) > 1 else []):
            pts += [(c - w / 2, 0.0), (c - w / 2, depth), (c + w / 2, depth), (c + w / 2, 0.0)]
        pts.append((L, 0.0))
        return pts
    phase, t = spec[1], spec[2]
    n = finger_count(L, fw)
    pts = []
    for i in range(n):
        out = (i % 2 == 0) == (phase == 'A')
        d = 0.0 if out else t
        s0, s1 = L * i / n, L * (i + 1) / n
        pts += [(s0, d), (s1, d)]
    return pts


def outline(W, H, top, right, bottom, left, fw):
    """Closed outline (panel coordinates, v down) of a W x H panel."""
    edges = [
        ((0.0, 0.0), (1, 0), (0, 1), W, top),
        ((W, 0.0), (0, 1), (-1, 0), H, right),
        ((W, H), (-1, 0), (0, -1), W, bottom),
        ((0.0, H), (0, -1), (1, 0), H, left),
    ]
    local = [edge_points(L, spec, fw) for (_, _, _, L, spec) in edges]
    for k in range(4):
        prev_last = local[k - 1][-1][1]
        next_first = local[(k + 1) % 4][0][1]
        L = edges[k][3]
        local[k][0] = (prev_last, local[k][0][1])
        local[k][-1] = (L - next_first, local[k][-1][1])
    pts = []
    for (P0, u, v, L, spec), lp in zip(edges, local):
        for s, d in lp:
            pts.append((P0[0] + u[0] * s + v[0] * d, P0[1] + u[1] * s + v[1] * d))
    return clean(pts)


def tslot_nut_holes(edge, s, W, H, cfg):
    """Rectangular nut pocket for a T-slot notch on 'top' or 'bottom' edge at
    position s. Returns (cx, cy, w, h)."""
    nut_w, nut_t, depth = cfg['nut_w'], cfg['nut_t'], cfg['nut_depth']
    if edge == 'top':
        return (s, depth, nut_w, nut_t)
    if edge == 'bottom':
        return (W - s, H - depth, nut_w, nut_t)
    raise ValueError(edge)
