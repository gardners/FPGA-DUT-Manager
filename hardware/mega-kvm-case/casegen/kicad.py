"""Read board outlines and connector positions from .kicad_pcb files.

Deliberately small: regexes over the s-expression text, enough for
footprint position/rotation/side, courtyard bounding box and the Edge.Cuts
bounding box. Coordinates are returned relative to the Edge.Cuts top-left
corner (x right, y down, as in KiCad's top view).
"""
import math
import os
import re


def load(path):
    if not os.path.exists(path):
        return None
    t = open(path).read()
    xs, ys = [], []
    for m in re.finditer(r'\(gr_(?:line|rect|arc)\s*\((?:start) ([-\d.]+) ([-\d.]+)\)\s*(?:\(mid [-\d.]+ [-\d.]+\)\s*)?'
                         r'\(end ([-\d.]+) ([-\d.]+)\)(.*?)\(layer "Edge\.Cuts"\)', t, re.S):
        if 'gr_' in m.group(5):
            continue
        xs += [float(m.group(1)), float(m.group(3))]
        ys += [float(m.group(2)), float(m.group(4))]
    if not xs:
        return None
    ox, oy = min(xs), min(ys)
    board = {'w': max(xs) - ox, 'h': max(ys) - oy, 'fp': {}, 'src': os.path.basename(path), 'ox': ox, 'oy': oy}
    for m in re.finditer(r'\n\t\(footprint "([^"]+)"(.*?)\n\t\)', t, re.S):
        name, body = m.groups()
        at = re.search(r'\n\t\t\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)', body)
        ref = re.search(r'\(property "Reference" "([^"]+)"', body).group(1)
        layer = re.search(r'\(layer "([^"]+)"\)', body).group(1)
        x0, y0 = float(at.group(1)), float(at.group(2))
        rot = math.radians(float(at.group(3) or 0))
        pts = []
        for g in re.finditer(r'\(fp_(?:line|rect|poly)(.*?)\(layer "[FB]\.CrtYd"\)', body, re.S):
            for p in re.finditer(r'\((?:start|end|xy) ([-\d.]+) ([-\d.]+)\)', g.group(1)):
                px, py = float(p.group(1)), float(p.group(2))
                pts.append((x0 + px * math.cos(rot) + py * math.sin(rot),
                            y0 - px * math.sin(rot) + py * math.cos(rot)))
        crt = None
        if pts:
            crt = (min(p[0] for p in pts) - ox, min(p[1] for p in pts) - oy,
                   max(p[0] for p in pts) - ox, max(p[1] for p in pts) - oy)
        board['fp'][ref] = {'name': name, 'x': x0 - ox, 'y': y0 - oy, 'rot': math.degrees(rot),
                            'side': layer[0], 'crt': crt}
    return board
