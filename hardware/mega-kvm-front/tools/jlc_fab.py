#!/usr/bin/env python3
"""JLC BOM/CPL and fab summary for the front-panel board (issue 0050).

Called by tools/fab.sh with the fab output directory and project name.
Inputs (written by fab.sh into <fab>/tmp): a per-reference schematic BOM and
two kicad-cli placement files (all placed parts, SMD only). Outputs JLC's
column formats:

  BOM: Comment, Designator, Footprint, LCSC Part #
  CPL: Designator, Mid X, Mid Y, Layer, Rotation

Rotation: KiCad's standard footprints and JLC's library models do not always
share a zero orientation. ROTATION_FIX holds the corrections for the
footprints on this board, taken from the JLCKicadTools rotation database
(github.com/matthewlai/JLCKicadTools, jlc_kicad_tools/cpl_rotations_db.csv,
fetched 2026-11-28). They are community data, not JLC's: every package is
listed in fab-summary.txt with its status, and the parts JLC shows rotated
wrongly in its placement preview must be fixed there before paying.
"""
import csv
import glob
import os
import re
import sys

# (footprint regex, added rotation in degrees, verification note)
ROTATION_FIX = [
    (r'^[RC]_0603_', 0, 'chip 0603: same zero orientation, no correction'),
    (r'^R_Array_Convex_', 90, 'JLCKicadTools db: +90; check in JLC viewer'),
    (r'^TSSOP-', 270, 'JLCKicadTools db: +270; check pin 1 in JLC viewer'),
    (r'^VSSOP-8_3.0x3.0mm', 270, 'JLCKicadTools db: +270; check in JLC viewer'),
    (r'^VSSOP-8_', 180, 'JLCKicadTools db: +180 (DCU 2.3x2 not separately '
                        'confirmed); check pin 1 in JLC viewer'),
    # THT parts, only used by the optional THT-assembly files
    (r'^LED_D3.0mm', 0, 'THT LED: check flat (cathode) side in JLC viewer'),
    (r'^PinHeader_', 0, 'THT header: symmetric apart from pin 1'),
    (r'^SW_PUSH_6mm', 0, 'THT 6x6 switch: symmetric, 4 pins'),
]


def rotation_fix(package):
    for pat, rot, note in ROTATION_FIX:
        if re.match(pat, package):
            return rot, note
    return None, 'NO RULE: check in JLC viewer'


def read_csv(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))


def natkey(ref):
    m = re.match(r'([A-Za-z]+)(\d+)', ref)
    return (m.group(1), int(m.group(2))) if m else (ref, 0)


def board_extent(gerber_dir):
    """Board outline extent (mm) from the Edge.Cuts Gerber (format 4.6)."""
    path = glob.glob(os.path.join(gerber_dir, '*Edge_Cuts.gm1'))[0]
    xs, ys = [], []
    for line in open(path):
        for m in re.finditer(r'^X(-?\d+)Y(-?\d+)', line):
            xs.append(int(m.group(1)) / 1e6)
            ys.append(int(m.group(2)) / 1e6)
    return max(xs) - min(xs), max(ys) - min(ys)


def drill_stats(gerber_dir):
    out = []
    for path in sorted(glob.glob(os.path.join(gerber_dir, '*.drl'))):
        tools, hits, cur = {}, {}, None
        for line in open(path):
            line = line.strip()
            m = re.match(r'^T(\d+)C([\d.]+)', line)
            if m:
                tools[m.group(1)] = float(m.group(2))
                continue
            m = re.match(r'^T(\d+)$', line)
            if m:
                cur = m.group(1)
                continue
            if cur and line.startswith('X'):
                hits[cur] = hits.get(cur, 0) + 1
        sizes = ', '.join('%.2f mm x%d' % (tools[t], hits.get(t, 0))
                          for t in sorted(tools, key=lambda t: tools[t]))
        out.append('%s: %s' % (os.path.basename(path), sizes or 'no holes'))
    return out


def main():
    fab, proj = sys.argv[1], sys.argv[2]
    tmp = os.path.join(fab, 'tmp')
    bom = {r['Reference']: r for r in read_csv(os.path.join(tmp, 'bom-refs.csv'))}
    pos_all = {r['Ref']: r for r in read_csv(os.path.join(tmp, 'pos-all.csv'))}
    smd = {r['Ref'] for r in read_csv(os.path.join(tmp, 'pos-smd.csv'))}

    problems = []
    for ref in smd:
        lcsc = bom.get(ref, {}).get('LCSC', '')
        if not re.match(r'^C\d+$', lcsc):
            problems.append('%s: SMT part without an LCSC number' % ref)
    for ref in pos_all:
        if ref not in bom:
            problems.append('%s: placed on the board but not in the schematic BOM' % ref)
    if problems:
        sys.exit('jlc_fab: ' + '; '.join(problems))

    def cpl_rows(refs):
        rows, notes = [], {}
        for ref in sorted(refs, key=natkey):
            p = pos_all[ref]
            fix, note = rotation_fix(p['Package'])
            notes[p['Package']] = (fix, note)
            rot = (float(p['Rot']) + (fix or 0)) % 360
            rows.append([ref, '%.4fmm' % float(p['PosX']), '%.4fmm' % float(p['PosY']),
                         'Top' if p['Side'] == 'top' else 'Bottom', '%g' % rot])
        return rows, notes

    def bom_rows(refs):
        groups = {}
        for ref in refs:
            b = bom[ref]
            fp = b['Footprint'].split(':')[-1]
            groups.setdefault((b['Value'], fp, b['LCSC']), []).append(ref)
        rows = [[v, ','.join(sorted(r, key=natkey)), fp, lcsc]
                for (v, fp, lcsc), r in groups.items()]
        return sorted(rows, key=lambda r: natkey(r[1].split(',')[0]))

    def write(name, header, rows):
        with open(os.path.join(fab, name), 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(rows)

    bom_hdr = ['Comment', 'Designator', 'Footprint', 'LCSC Part #']
    cpl_hdr = ['Designator', 'Mid X', 'Mid Y', 'Layer', 'Rotation']
    tht = set(pos_all) - smd
    cpl_smd, notes_smd = cpl_rows(smd)
    cpl_tht, notes_all = cpl_rows(pos_all)
    write('%s-bom-jlc.csv' % proj, bom_hdr, bom_rows(smd))
    write('%s-cpl-jlc.csv' % proj, cpl_hdr, cpl_smd)
    write('%s-bom-jlc-with-tht.csv' % proj, bom_hdr, bom_rows(set(pos_all)))
    write('%s-cpl-jlc-with-tht.csv' % proj, cpl_hdr, cpl_tht)

    # Everything JLC does not place in the default (SMT-only) order
    hand = []
    for ref in sorted(set(bom) - smd, key=natkey):
        b = bom[ref]
        side = pos_all[ref]['Side'] if ref in pos_all else '-'
        why = 'DNP' if b.get('DNP') else ('THT, %s side' % side)
        hand.append([ref, b['Value'], b['Footprint'].split(':')[-1], b['LCSC'], b['MPN'], why])
    write('%s-handfit.csv' % proj,
          ['Designator', 'Value', 'Footprint', 'LCSC Part #', 'MPN', 'Note'], hand)

    w, h = board_extent(os.path.join(fab, 'gerbers'))
    with open(os.path.join(fab, 'fab-summary.txt'), 'w') as f:
        f.write('Board outline: %.2f x %.2f mm\n' % (w, h))
        f.write('Gerbers: %s\n' % ', '.join(sorted(os.listdir(os.path.join(fab, 'gerbers')))))
        f.write('Drill:\n' + ''.join('  %s\n' % s for s in drill_stats(os.path.join(fab, 'gerbers'))))
        f.write('SMT parts placed by JLC: %d (%d BOM lines)\n' % (len(smd), len(bom_rows(smd))))
        f.write('THT parts (hand-fit or JLC THT option): %d; DNP: %d\n'
                % (len(tht), sum(1 for b in bom.values() if b.get('DNP'))))
        f.write('Rotation corrections applied (CPL = KiCad rotation + correction):\n')
        for pkg, (fix, note) in sorted(notes_all.items()):
            tag = 'SMT' if pkg in notes_smd else 'THT'
            f.write('  %-34s %s %+4s  %s\n' % (pkg, tag, '?' if fix is None else fix, note))
    print(open(os.path.join(fab, 'fab-summary.txt')).read(), end='')


if __name__ == '__main__':
    main()
