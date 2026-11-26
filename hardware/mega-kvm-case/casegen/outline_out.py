"""Mounting-plate outline as DXF (R12, mm) and as a KiCad board with only
Edge.Cuts (outline + holes/slots as cut-outs), for a bare PCB at JLCPCB or a
laser/CNC cut. Panel coordinates have v down; both outputs flip to y up
(DXF) / keep KiCad's y down."""
import math
import os


def _segments(p):
    """Yield ('line', x0, y0, x1, y1) / ('arc', cx, cy, r, a0, a1) / ('circle', cx, cy, r) in panel coords."""
    pts = p.outline
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        yield ('line', a[0], a[1], b[0], b[1])
    for s in p.cuts:
        if s.kind == 'circle':
            yield ('circle', s.cx, s.cy, s.r)
        elif s.kind == 'rrect':
            x0, y0, x1, y1 = s.cx - s.w / 2, s.cy - s.h / 2, s.cx + s.w / 2, s.cy + s.h / 2
            r = s.r
            yield ('line', x0 + r, y0, x1 - r, y0)
            yield ('line', x1, y0 + r, x1, y1 - r)
            yield ('line', x1 - r, y1, x0 + r, y1)
            yield ('line', x0, y1 - r, x0, y0 + r)
            if r > 1e-6:
                # corner arcs, angles in screen coordinates (v down), clockwise on screen
                yield ('arc', x1 - r, y0 + r, r, 270, 360)
                yield ('arc', x1 - r, y1 - r, r, 0, 90)
                yield ('arc', x0 + r, y1 - r, r, 90, 180)
                yield ('arc', x0 + r, y0 + r, r, 180, 270)
        else:
            for i in range(len(s.pts)):
                a, b = s.pts[i], s.pts[(i + 1) % len(s.pts)]
                yield ('line', a[0], a[1], b[0], b[1])


def write_dxf(p, path):
    H = p.bbox()[3]
    out = ['0', 'SECTION', '2', 'HEADER', '9', '$INSUNITS', '70', '4', '0', 'ENDSEC',
           '0', 'SECTION', '2', 'ENTITIES']
    for seg in _segments(p):
        if seg[0] == 'line':
            _, x0, y0, x1, y1 = seg
            out += ['0', 'LINE', '8', 'CUT', '10', '%.4f' % x0, '20', '%.4f' % (H - y0), '30', '0',
                    '11', '%.4f' % x1, '21', '%.4f' % (H - y1), '31', '0']
        elif seg[0] == 'circle':
            _, cx, cy, r = seg
            out += ['0', 'CIRCLE', '8', 'CUT', '10', '%.4f' % cx, '20', '%.4f' % (H - cy), '30', '0', '40', '%.4f' % r]
        else:
            _, cx, cy, r, a0, a1 = seg
            # screen angle a (v down) -> math angle -a (y up); CCW from -a1 to -a0
            out += ['0', 'ARC', '8', 'CUT', '10', '%.4f' % cx, '20', '%.4f' % (H - cy), '30', '0', '40', '%.4f' % r,
                    '50', '%.4f' % ((-a1) % 360), '51', '%.4f' % ((-a0) % 360)]
    out += ['0', 'ENDSEC', '0', 'EOF']
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        fh.write('\n'.join(out) + '\n')


def write_kicad(p, path, ox=30.0, oy=30.0):
    def P(x, y):
        return '%.4f %.4f' % (ox + x, oy + y)
    lines = ['(kicad_pcb', '\t(version 20240108)', '\t(generator "mega-kvm-case")', '\t(generator_version "1")',
             '\t(general', '\t\t(thickness 1.6)', '\t)', '\t(paper "A2")', '\t(layers',
             '\t\t(0 "F.Cu" signal)', '\t\t(31 "B.Cu" signal)', '\t\t(44 "Edge.Cuts" user)', '\t\t(48 "B.Fab" user)',
             '\t\t(49 "F.Fab" user)', '\t)', '\t(setup', '\t\t(pad_to_mask_clearance 0)', '\t)',
             '\t(net 0 "")']
    st = '(stroke (width 0.1) (type default)) (layer "Edge.Cuts")'
    for seg in _segments(p):
        if seg[0] == 'line':
            _, x0, y0, x1, y1 = seg
            lines.append('\t(gr_line (start %s) (end %s) %s)' % (P(x0, y0), P(x1, y1), st))
        elif seg[0] == 'circle':
            _, cx, cy, r = seg
            lines.append('\t(gr_circle (center %s) (end %s) %s (fill none))' % (P(cx, cy), P(cx + r, cy), st))
        else:
            _, cx, cy, r, a0, a1 = seg
            am = math.radians((a0 + a1) / 2)
            pt = lambda a: P(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
            lines.append('\t(gr_arc (start %s) (mid %s) (end %s) %s)' % (
                pt(a0), P(cx + r * math.cos(am), cy + r * math.sin(am)), pt(a1), st))
    lines.append(')')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
