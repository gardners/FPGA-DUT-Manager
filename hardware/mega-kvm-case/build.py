#!/usr/bin/env python3
"""Regenerate everything in out/ from config.py (issues 0048, 0051).

  python3 build.py            # or: make
  python3 build.py --no-png   # skip the PNG renders (needs inkscape)

Primary output: the rack layout (out/rack/, out/fit-report.md, issue 0051).
Options A and B (out/option-A, out/option-B, out/fit-report-options-AB.md)
are still generated but no longer developed.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from casegen import bays as baymod          # noqa: E402
from casegen import fragments as fr         # noqa: E402
from casegen import kicad, layout, nest, option_a, option_b, outline_out, svgout   # noqa: E402
from casegen import rack                    # noqa: E402
from casegen import rackreport             # noqa: E402

OUT = os.path.join(HERE, 'out')


def load_cfg():
    spec = importlib.util.spec_from_file_location('config', os.path.join(HERE, 'config.py'))
    cfg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cfg)
    return cfg


def load_boards(cfg):
    b = {}
    for key, c in (('main', cfg.POWER_MAIN), ('inputs', cfg.POWER_IN)):
        b[key] = kicad.load(os.path.join(HERE, c['pcb']))
    return b


def png(svg, dpi=150):
    exe = shutil.which('inkscape')
    if not exe or '--no-png' in sys.argv:
        return None
    out = svg[:-4] + '.png'
    subprocess.run([exe, svg, '--export-type=png', '--export-filename=' + out, '--export-dpi=%d' % dpi,
                    '--export-background=white', '--export-background-opacity=1'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    return out if os.path.exists(out) else None


def write_option(cfg, res, files):
    o = res['option']
    base = os.path.join(OUT, 'option-' + o)
    k = cfg.KERF
    for p in res['panels']:
        path = os.path.join(base, 'panels', p.name + '.svg')
        svgout.write_panel(p, path, k)
        files.append(path)
    for name, frag in res['fragments']:
        path = os.path.join(base, 'fragments', name + '.svg')
        svgout.write_panel(frag, path, k)
        files.append(path)
    # nesting
    res['sheets'] = {}
    for mat, sheet in cfg.SHEETS.items():
        sheets, too_big = nest.nest(res['panels'], sheet, cfg.SHEET_MARGIN, cfg.NEST_GAP)
        res['sheets'][mat] = (len(sheets), too_big)
        for i, sh in enumerate(sheets):
            path = os.path.join(base, 'sheets', '%s-%dx%d-%d.svg' % (mat, sheet[0], sheet[1], i + 1))
            svgout.write_sheet(sh, path, k, 'option %s, %s sheet %d of %d' % (o, mat, i + 1, len(sheets)))
            files.append(path)
        for name in too_big:
            res['problems'].append('%s sheet %dx%d: %s does not fit' % (mat, sheet[0], sheet[1], name))
    # plate
    if res.get('plate') is not None:
        p = res['plate']
        svgout.write_panel(p, os.path.join(base, 'panels', p.name + '.svg'), 0.0 if cfg.CASE_B['plate'] == 'pcb' else k)
        files.append(os.path.join(base, 'panels', p.name + '.svg'))
        outline_out.write_dxf(p, os.path.join(base, 'plate', 'mounting-plate.dxf'))
        outline_out.write_kicad(p, os.path.join(base, 'plate', 'mounting-plate.kicad_pcb'))
        files += [os.path.join(base, 'plate', 'mounting-plate.dxf'), os.path.join(base, 'plate', 'mounting-plate.kicad_pcb')]
        # steel front template: the window to open in the carcass's own front
        front = [q for q in res['panels'] if q.name == 'B-front'][0]
        bb = [c.bbox() for c in front.cuts if not (c.kind == 'circle' and c.r < 2.0 and c.cy in ())]
        u0 = min(b[0] for b in bb) - 3
        u1 = max(b[2] for b in bb) + 3
        d = svgout.Drawing(front.w + 20, front.h + 30, 'B steel front: window to cut (print 1:1)')
        d.rect(10, 10, 10 + front.w, 10 + front.h, fill='none', stroke='#000', sw=0.2, dash='2,1')
        d.rect(10 + u0, 10 + 1.0, 10 + u1, 10 + front.h - 1.0, fill='none', stroke='#000', sw=0.5)
        d.text(12, 8, 'dashed: our front panel (%.0f x %.1f); solid: open the steel front to this window '
                      '(or remove the original front); print at 100%%' % (front.w, front.h), size=3, anchor='start')
        path = os.path.join(base, 'plate', 'steel-front-template.svg')
        d.save(path)
        files.append(path)
    # fit check + top view
    probs, clear = layout.check(res['boxes'], res['interior'], res['allowed'])
    res['problems'] += probs
    res['clear'] = clear
    W, D, H = res['size']
    tv = os.path.join(base, 'topview-%s.svg' % o)
    layout.topview(tv, 'Option %s top view (%s), %.0f x %.0f x %.2f mm' % (o, cfg.VARIANT, W, D, H), W, D,
                   res['boxes'], res['walls_t'], notes=['dashed red = cable/plug allowance (soft)'] +
                   ['PROBLEM: ' + p for p in res['problems'][:8]])
    files.append(tv)
    pg = png(tv)
    if pg:
        files.append(pg)
    for mat in cfg.SHEETS:
        pass


def alternates(cfg):
    """Width/height budgets of all DUT-face variants for both options."""
    rows = []
    A, B = cfg.CASE_A, cfg.CASE_B
    t = cfg.T
    a_inside = A['width'] - 2 * t - 2 * A['margin']
    fix = [u for u, z in B['front_fix']]
    b_inside = (max(fix) - 4) - (min(fix) + 4)
    hi_a = A['height'] - 2 * t
    hi_b = B['outer'][2] - 2 * B['steel'] - B['standoff_h'] - B['plate_t']
    g = fr.front_group(cfg, hi_a)
    extras = {'input board': cfg.POWER_IN['width_override'] or cfg.POWER_IN['w'], 'bulkhead+DUT power': fr.net_and_power(cfg).width,
              'keyboard': fr.keyboard(cfg).width}
    b_extras = {'front group': g.width, 'bulkhead': fr.bulkhead(cfg).width, 'keyboard': fr.keyboard(cfg).width}
    variants = []
    sb = baymod.shield190_bay(cfg, 0)
    variants.append(('shield190 (primary, 120 x 189.6 shield + kbd sub-boards)', sb.width, sb.info['top']))
    vb = baymod.vboard_bay(cfg, 0)
    variants.append(('vboard (vertical DUT board per Mimas)', vb.width, vb.info['top']))
    w = baymod.wide_item(cfg)
    variants.append(('wide (rev A single row, 279.6)', w.width, w.z[1] - 7.0 + 4.7))
    n = baymod.narrow_item(cfg)
    variants.append(('narrow (~150, one 2x8 per DUT)', n.width, n.z[1] - 8.0 + 4.7))
    for name, bw, top in variants:
        bays = cfg.BAYS * bw + (cfg.BAYS - 1) * A['bay_gap']
        la = a_inside - bays
        fit_a = []
        rem = la - 3
        for k, v in extras.items():
            if rem >= v + 3:
                fit_a.append(k)
                rem -= v + 3
        lb = b_inside - bays - 3
        fit_b = []
        remb = lb
        for k, v in b_extras.items():
            if remb >= v + 3:
                fit_b.append(k)
                remb -= v + 3
        rows.append({'variant': name, 'bay': bw, 'bays': bays, 'a_left': la, 'a_fits': fit_a, 'b_left': lb,
                     'b_fits': fit_b, 'top': top, 'top_ok_a': top <= hi_a - 1.0, 'top_ok_b': top <= hi_b - 1.0,
                     'hi_a': hi_a, 'hi_b': hi_b})
    return rows, extras, b_extras, a_inside, b_inside


def report(cfg, ra, rb, alt, boards, files):
    rows, extras, b_extras, a_in, b_in = alt
    L = []
    w = L.append
    w('# MEGA-KVM case options A/B (no longer developed): fit report (generated by build.py, do not edit)')
    w('')
    w('Primary DUT face: `%s`. Material %.1f mm, kerf %.2f mm. Boards read from: %s.' % (
        cfg.VARIANT, cfg.T, cfg.KERF, ', '.join('%s=%s' % (k, v['src'] if v else 'NOT FOUND (config fallback)')
                                                for k, v in boards.items())))
    w('Shield numbers from: %s.' % ra['bays'][0].info['src'])
    w('')
    w('## Summary')
    w('')
    for r in (ra, rb):
        Wd, Dd, Hd = r['size']
        ok = 'fits' if not r['problems'] else '%d problem(s)' % len(r['problems'])
        w('* **Option %s**: %.1f x %.1f x %.2f mm (W x D x H): %s.' % (r['option'], Wd, Dd, Hd, ok))
    w('')
    w('## DUT-face variants (2 bays), width and height budgets')
    w('')
    w('Option A rear panel: %.1f mm inside (%.0f outer - walls - margins). Option B front panel: %.1f mm between '
      'the fixing holes. 1RU interior: A %.2f mm (floor to lid); B %.2f mm above the mounting plate.' % (
          a_in, cfg.CASE_A['width'], b_in, rows[0]['hi_a'], rows[0]['hi_b']))
    w('Extras beside the bays: A rear = %s; B front = %s (mm).' % (
        ', '.join('%s %.0f' % kv for kv in extras.items()), ', '.join('%s %.0f' % kv for kv in b_extras.items())))
    w('')
    w('| Variant | Bay | 2 bays | A rear left | A rear also fits | B front left | B front also fits | DUT connector top | 1RU A | 1RU B |')
    w('|---|---|---|---|---|---|---|---|---|---|')
    for r in rows:
        w('| %s | %.1f | %.1f | %.1f | %s | %.1f | %s | %.1f | %s | %s |' % (
            r['variant'], r['bay'], r['bays'], r['a_left'], ', '.join(r['a_fits']) or ('NONE' if r['a_left'] >= 0 else 'bays do not fit'),
            r['b_left'], ', '.join(r['b_fits']) or ('NONE' if r['b_left'] >= 0 else 'bays do not fit'), r['top'],
            'ok' if r['top_ok_a'] else 'TOO TALL', 'ok' if r['top_ok_b'] else 'TOO TALL'))
    w('')
    w('Note: the 279.6 mm single-row shield does not fit twice in a 19-inch case (559 mm > 435 mm); '
      'the vertical-board variant stacks three connector rows and needs the Mimas HDMI IN/OUT on short jumpers.')
    for r in (ra, rb):
        w('')
        w('## Option %s' % r['option'])
        w('')
        for n in r['notes']:
            w('* ' + n)
        w('* top of the Mimas/shield stack: %.1f mm above the outer bottom; interior top %.2f mm' % (
            r['stack_top'], r['interior'][5]))
        if r['option'] == 'B':
            st = cfg.CASE_B
            w('* stack: floor %.1f + carcass standoffs %.1f + plate %.1f -> plate top %.1f' % (
                st['steel'], st['standoff_h'], st['plate_t'], st['steel'] + st['standoff_h'] + st['plate_t']))
        w('* sheets: ' + '; '.join('%s %dx%d: %d sheet(s)%s' % (
            m, cfg.SHEETS[m][0], cfg.SHEETS[m][1], n, (' (does not fit: %s)' % ', '.join(tb)) if tb else '')
            for m, (n, tb) in r['sheets'].items()))
        w('')
        if r['problems']:
            w('**Problems:**')
            w('')
            for p in r['problems']:
                w('* ' + p)
            w('')
        w('| Part | nearest neighbour (same height band) | gap mm | headroom to lid mm |')
        w('|---|---|---|---|')
        for name, best, top in r['clear']:
            w('| %s | %s | %s | %.1f |' % (name, best[1] if best else '-', '%.1f' % best[0] if best else '-', top))
    w('')
    w('## Generated files')
    w('')
    for f in sorted(set(files)):
        w('* `%s`' % os.path.relpath(f, HERE))
    path = os.path.join(OUT, 'fit-report-options-AB.md')
    with open(path, 'w') as fh:
        fh.write('\n'.join(L) + '\n')
    return path


def main():
    cfg = load_cfg()
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    boards = load_boards(cfg)
    files = []
    ra = option_a.build(cfg, boards, print)
    rb = option_b.build(cfg, boards, print)
    write_option(cfg, ra, files)
    write_option(cfg, rb, files)
    # alternate bay sub-SVGs (option A rear geometry)
    hw = cfg.CASE_A['height'] - cfg.T
    V = lambda z: hw - (cfg.T + z)
    for name, item in (('vboard', baymod.vboard_bay(cfg, 0).item), ('wide', baymod.wide_item(cfg)),
                       ('narrow', baymod.narrow_item(cfg))):
        path = os.path.join(OUT, 'alternates', 'bay-%s.svg' % name)
        svgout.write_panel(fr.standalone(item, hw, V), path, cfg.KERF)
        files.append(path)
    alt = alternates(cfg)
    rp = report(cfg, ra, rb, alt, boards, files)
    rr = rackreport.write_all(cfg, boards, OUT, png, files)
    params = {k: getattr(cfg, k) for k in dir(cfg) if k.isupper()}
    with open(os.path.join(OUT, 'parameters.json'), 'w') as fh:
        json.dump(params, fh, indent=1, default=str)
    print('wrote %d files; reports %s, %s' % (len(files) + 2, os.path.relpath(rr['report'], HERE), os.path.relpath(rp, HERE)))
    print('rack: %d problem(s)' % len(rr['problems']))
    for p in rr['problems']:
        print('   ', p)
    for r in (ra, rb):
        print('option %s: %.1f x %.1f x %.2f, %d problem(s)' % ((r['option'],) + tuple(r['size']) + (len(r['problems']),)))
        for p in r['problems']:
            print('   ', p)


if __name__ == '__main__':
    main()
