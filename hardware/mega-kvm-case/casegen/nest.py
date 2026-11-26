"""Nesting of panels onto sheets: bottom-left placement of bounding boxes
(candidate points at the corners of parts already placed, both
orientations). Simple and deterministic; good enough for a dozen parts."""


def nest(panels, sheet, margin, gap):
    SW, SH = sheet
    parts = []
    for p in panels:
        parts += [p] * p.qty
    parts.sort(key=lambda p: -(p.size()[0] * p.size()[1]))
    sheets, too_big = [], []

    def fits(rects, x, y, w, h):
        if x + w > SW - margin + 1e-6 or y + h > SH - margin + 1e-6:
            return False
        for (a, b, c, d) in rects:
            if x < c + gap - 1e-6 and a < x + w + gap - 1e-6 and y < d + gap - 1e-6 and b < y + h + gap - 1e-6:
                return False
        return True

    def try_sheet(sh, p):
        w0, h0 = p.size()
        best = None
        cands = [(margin, margin)] + [(r[2] + gap, r[1]) for r in sh['rects']] + [(r[0], r[3] + gap) for r in sh['rects']] \
            + [(margin, r[3] + gap) for r in sh['rects']] + [(r[2] + gap, margin) for r in sh['rects']]
        for rot, (w, h) in ((False, (w0, h0)), (True, (h0, w0))):
            for (x, y) in cands:
                if fits(sh['rects'], x, y, w, h):
                    key = (y + h, x)
                    if best is None or key < best[0]:
                        best = (key, rot, x, y, w, h)
        if best:
            _, rot, x, y, w, h = best
            sh['rects'].append((x, y, x + w, y + h))
            sh['items'].append(p.transformed(rot, x, y))
            return True
        return False

    for p in parts:
        w, h = p.size()
        if not ((w <= SW - 2 * margin and h <= SH - 2 * margin) or (h <= SW - 2 * margin and w <= SH - 2 * margin)):
            too_big.append(p.name)
            continue
        if not any(try_sheet(sh, p) for sh in sheets):
            sh = {'w': SW, 'h': SH, 'rects': [], 'items': []}
            sheets.append(sh)
            try_sheet(sh, p)
    return sheets, too_big
