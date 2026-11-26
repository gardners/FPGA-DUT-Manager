#!/usr/bin/env python3
"""Generate the KiCad schematic (root + sub-sheets), the project symbol
library, a netlist JSON for gen_pcb.py and a JLCPCB BOM from design.py.

Every symbol pin gets a short wire stub ending in a label (local label for
nets on one sheet, global label for nets shared between sheets) or a power
symbol; unused pins get a no-connect flag.
"""
import csv
import json
import os
import uuid as uuidlib
from collections import defaultdict, OrderedDict

import design
import symlib
from sexp import Sym, dump, find, findall

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
NAME = 'mega-kvm-shield'
LIBSYM = os.path.join(PROJ, 'lib', 'shield.kicad_sym')
POWER_NETS = {'GND': 'power:GND', '+3V3': 'power:+3V3', '+12V': 'power:+12V', '+5V': 'power:+5V'}
G = 2.54
NS = uuidlib.UUID('6f1d3c1e-7a51-4d0e-9a55-6d2b3e1f0a45')


def U(*key):
    """Deterministic UUID so regenerating gives stable files."""
    return str(uuidlib.uuid5(NS, '/'.join(str(k) for k in key)))


def font(size=1.27):
    return [Sym('effects'), [Sym('font'), [Sym('size'), size, size]]]


# --------------------------------------------------------------------------
# Project-specific symbols
# --------------------------------------------------------------------------
def pin(etype, x, y, ang, num, name, length=G, hide_name=False):
    p = [Sym('pin'), Sym(etype), Sym('line'), [Sym('at'), x, y, ang],
         [Sym('length'), length],
         [Sym('name'), name, font()], [Sym('number'), num, font()]]
    return p


def prop(k, v, x=0.0, y=0.0, hide=False, ang=0):
    e = font()
    if hide:
        e.append([Sym('hide'), Sym('yes')])
    return [Sym('property'), k, v, [Sym('at'), x, y, ang], e]


def mksym(name, ref, value, fp, descr, rect, pins_):
    body = [Sym('symbol'), name + '_0_1',
            [Sym('rectangle'), [Sym('start'), rect[0], rect[1]], [Sym('end'), rect[2], rect[3]],
             [Sym('stroke'), [Sym('width'), 0.254], [Sym('type'), Sym('default')]],
             [Sym('fill'), [Sym('type'), Sym('background')]]]]
    pinsym = [Sym('symbol'), name + '_1_1'] + pins_
    return [Sym('symbol'), name, [Sym('pin_names'), [Sym('offset'), 1.016]],
            [Sym('exclude_from_sim'), Sym('no')], [Sym('in_bom'), Sym('yes')],
            [Sym('on_board'), Sym('yes')],
            prop('Reference', ref, rect[0], rect[1] + 1.27),
            prop('Value', value, rect[0], rect[3] - 1.27),
            prop('Footprint', fp, 0, 0, True),
            prop('Datasheet', '', 0, 0, True),
            prop('Description', descr, 0, 0, True),
            body, pinsym]


def custom_symbols():
    syms = []
    # Mimas A7 header as seen by the shield: rows 1..40, columns A/B
    ps = []
    for n in range(1, 41):
        y = (20 - n) * G
        ps.append(pin('passive', -12.7, y, 0, 'A%d' % n, 'A%d' % n))
        ps.append(pin('passive', 12.7, y, 180, 'B%d' % n, 'B%d' % n))
    syms.append(mksym('Mimas_Header_2x40', 'P', 'Mimas_Header_2x40',
                      'shield:Mimas_Header_Socket_2x40',
                      'Numato Mimas A7 V3 2x40 GPIO header (P12/P13), row n column A/B',
                      (-10.16, 21 * G, 10.16, -20 * G - G), ps))
    # TCA6424A, RGJ (VQFN-32) -- pin numbers to be checked against SCPS193
    ps = []
    left = [('30', 'SDA', 'bidirectional'), ('29', 'SCL', 'input'),
            ('1', '~{INT}', 'open_collector'), ('3', '~{RESET}', 'input'),
            ('28', 'ADDR', 'input')]
    for i, (num, nm, t) in enumerate(left):
        ps.append(pin(t, -15.24, (13 - i) * G, 0, num, nm))
    ps.append(pin('power_in', -2.54, 17 * G, 270, '2', 'VCCI'))
    ps.append(pin('power_in', 2.54, 17 * G, 270, '31', 'VCCP'))
    ps.append(pin('power_in', -2.54, -17 * G, 90, '32', 'GND'))
    ps.append(pin('power_in', 2.54, -17 * G, 90, '33', 'EP'))
    y = 14
    for port in range(3):
        for b in range(8):
            ps.append(pin('bidirectional', 15.24, y * G, 180, str(4 + port * 8 + b),
                          'P%d%d' % (port, b)))
            y -= 1
        y -= 1
    syms.append(mksym('TCA6424A', 'U', 'TCA6424A',
                      'Package_DFN_QFN:QFN-32-1EP_5x5mm_P0.5mm_EP3.45x3.45mm',
                      '24-bit I2C I/O expander (TI TCA6424A, RGJ)',
                      (-12.7, 16 * G, 12.7, -16 * G), ps))
    return syms


def write_symlib(syms):
    os.makedirs(os.path.dirname(LIBSYM), exist_ok=True)
    lib = [Sym('kicad_symbol_lib'), [Sym('version'), 20241209],
           [Sym('generator'), 'gen_sch.py'], [Sym('generator_version'), '1']] + syms
    with open(LIBSYM, 'w') as f:
        f.write(dump(lib) + '\n')


# --------------------------------------------------------------------------
def main(board, PROJ, NAME, SHEETS, notes):
    parts = [p for p in design.parts if p['board'] == board]
    # references
    counters = defaultdict(int)
    for p in parts:
        counters[p['prefix']] += 1
        p['ref'] = '%s%d' % (p['prefix'], counters[p['prefix']])
        if p['prefix'] == '#FLG':
            p['ref'] = '#FLG%02d' % counters[p['prefix']]

    # which sheets use which net
    net_sheets = defaultdict(set)
    net_pins = defaultdict(list)
    for p in parts:
        for pn, net in p['pins'].items():
            if net:
                net_sheets[net].add(p['sheet'])
                net_pins[net].append((p['ref'], pn))
    for net, lst in sorted(net_pins.items()):
        if len(lst) < 2 and net not in POWER_NETS:
            print('WARNING single-pin net', net, lst)

    libsyms = OrderedDict()

    def getsym(libid):
        if libid not in libsyms:
            libsyms[libid] = symlib.load(libid, LIBSYM)
        return libsyms[libid]

    root_uuid = U('root', board)
    sheet_uuids = {s: U('sheet', s) for s, _ in SHEETS}
    pwr_count = [0]
    sheet_files = {}
    netlist = {}

    for page, (sname, stitle) in enumerate(SHEETS, start=2):
        sp = [p for p in parts if p['sheet'] == sname]
        items = []
        used = set()
        path = '/%s/%s' % (root_uuid, sheet_uuids[sname])

        # layout: shelf packing, clusters kept together
        cells = []
        for p in sp:
            s = getsym(p['sym'])
            pl = [q for q in symlib.pins(s) if q['unit'] in (0, 1)]
            xs = [q['x'] for q in pl] or [0]
            ys = [-q['y'] for q in pl] or [0]
            ml = mr = mt = mb = 4.0
            for q in pl:
                net = p['pins'].get(q['num'])
                ln = 3 * G + (len(net) * 1.1 + 4 if net and net not in POWER_NETS else 5)
                a = int(q['ang']) % 360
                if a == 0:
                    ml = max(ml, ln)
                elif a == 180:
                    mr = max(mr, ln)
                elif a == 90:
                    mb = max(mb, ln)
                else:
                    mt = max(mt, ln)
            x0, x1 = min(xs) - ml, max(xs) + mr
            y0, y1 = min(ys) - mt, max(ys) + mb
            x0 = min(x0, -8)
            x1 = max(x1, 8)
            cells.append((p, s, pl, x0, x1, y0, y1))
        total = sum((c[4] - c[3]) * (c[6] - c[5]) for c in cells)
        for paper, (pw, ph) in (('A3', (420, 297)), ('A2', (594, 420)),
                                ('A1', (841, 594)), ('A0', (1189, 841))):
            if total * 1.6 < (pw - 40) * (ph - 60):
                ok = True
                x, y, rowh = 20.0, 30.0, 0.0
                pos = []
                for c in cells:
                    w, h = c[4] - c[3], c[6] - c[5]
                    if x + w > pw - 20:
                        x, y, rowh = 20.0, y + rowh + 2, 0.0
                    pos.append((x - c[3], y - c[5]))
                    x += w + 2
                    rowh = max(rowh, h)
                if y + rowh < ph - 40:
                    break
        snap = lambda v: round(v / G) * G
        for (p, s, pl, *_), (ox, oy) in zip(cells, pos):
            X, Y = snap(ox), snap(oy)
            props = []
            for pr in findall(s, 'property'):
                k, v = pr[1], pr[2]
                at = find(pr, 'at')
                hide = any(isinstance(e, list) and e and e[0] == 'hide' for e in find(pr, 'effects') or []) \
                    or any(e == 'hide' for e in (find(pr, 'effects') or []))
                if k == 'Reference':
                    v = p['ref']
                elif k == 'Value':
                    v = p['value']
                elif k == 'Footprint':
                    v = p['fp']
                elif k == 'Description' and p['descr']:
                    v = p['descr']
                props.append(prop(k, v, X + float(at[1]), Y - float(at[2]), hide,
                                  float(at[3]) if len(at) > 3 else 0))
            if p['lcsc']:
                props.append(prop('LCSC', p['lcsc'], X, Y, True))
            if p['mpn']:
                props.append(prop('MPN', p['mpn'], X, Y, True))
            is_pwr = p['sym'].startswith('power:')
            inst = [Sym('symbol'), [Sym('lib_id'), p['sym']], [Sym('at'), X, Y, 0],
                    [Sym('unit'), 1], [Sym('exclude_from_sim'), Sym('no')],
                    [Sym('in_bom'), Sym('no') if is_pwr else Sym('yes')],
                    [Sym('on_board'), Sym('no') if is_pwr else Sym('yes')],
                    [Sym('dnp'), Sym('yes') if p['dnp'] else Sym('no')],
                    [Sym('uuid'), U('sym', p['ref'])]] + props
            for q in pl:
                inst.append([Sym('pin'), q['num'], [Sym('uuid'), U('pin', p['ref'], q['num'], q['x'], q['y'])]])
            inst.append([Sym('instances'), [Sym('project'), NAME,
                         [Sym('path'), path, [Sym('reference'), p['ref']], [Sym('unit'), 1]]]])
            items.append(inst)
            if p['prefix'] != '#FLG':
                netlist[p['ref']] = dict(fp=p['fp'], value=p['value'], cluster=p['cluster'],
                                         dnp=p['dnp'], lcsc=p['lcsc'], mpn=p['mpn'],
                                         descr=p['descr'], sheet=sname,
                                         pads={k: v for k, v in p['pins'].items() if v})
            # pin stubs + labels
            seen_pos = set()
            for q in pl:
                px, py = X + q['x'], Y - q['y']
                if (px, py) in seen_pos:
                    continue          # stacked (hidden) pins share a stub
                seen_pos.add((px, py))
                net = p['pins'].get(q['num'], 'UNDEFINED')
                if net == 'UNDEFINED':
                    raise SystemExit('pin %s of %s (%s) not in design' % (q['num'], p['ref'], p['sym']))
                if net is None:
                    items.append([Sym('no_connect'), [Sym('at'), px, py], [Sym('uuid'), U('nc', p['ref'], q['num'])]])
                    continue
                a = int(q['ang']) % 360
                dx, dy = {0: (-1, 0), 180: (1, 0), 90: (0, 1), 270: (0, -1)}[a]
                L = 2 * G
                ex, ey = px + dx * L, py + dy * L
                items.append([Sym('wire'), [Sym('pts'), [Sym('xy'), px, py], [Sym('xy'), ex, ey]],
                              [Sym('stroke'), [Sym('width'), 0], [Sym('type'), Sym('default')]],
                              [Sym('uuid'), U('w', p['ref'], q['num'])]])
                if net in POWER_NETS:
                    pwr_count[0] += 1
                    ref = '#PWR%03d' % pwr_count[0]
                    libid = POWER_NETS[net]
                    ps = getsym(libid)
                    if net == 'GND':
                        rot = {(0, 1): 0, (0, -1): 180, (1, 0): 90, (-1, 0): 270}[(dx, dy)]
                    else:
                        rot = {(0, -1): 0, (0, 1): 180, (1, 0): 270, (-1, 0): 90}[(dx, dy)]
                    pinst = [Sym('symbol'), [Sym('lib_id'), libid], [Sym('at'), ex, ey, rot],
                             [Sym('unit'), 1], [Sym('exclude_from_sim'), Sym('no')],
                             [Sym('in_bom'), Sym('yes')], [Sym('on_board'), Sym('yes')],
                             [Sym('dnp'), Sym('no')], [Sym('uuid'), U('pwr', ref)],
                             prop('Reference', ref, ex, ey, True),
                             prop('Value', net, ex, ey + (3 if net == 'GND' else -3)),
                             prop('Footprint', '', ex, ey, True),
                             prop('Datasheet', '', ex, ey, True),
                             [Sym('pin'), '1', [Sym('uuid'), U('pwrpin', ref)]],
                             [Sym('instances'), [Sym('project'), NAME,
                              [Sym('path'), path, [Sym('reference'), ref], [Sym('unit'), 1]]]]]
                    items.append(pinst)
                    continue
                ang = {(-1, 0): 180, (1, 0): 0, (0, 1): 270, (0, -1): 90}[(dx, dy)]
                just = Sym('right') if ang in (180, 270) else Sym('left')
                if len(net_sheets[net]) > 1:
                    items.append([Sym('global_label'), net, [Sym('shape'), Sym('bidirectional')],
                                  [Sym('at'), ex, ey, ang], [Sym('fields_autoplaced'), Sym('yes')],
                                  [Sym('effects'), [Sym('font'), [Sym('size'), 1.27, 1.27]], [Sym('justify'), just]],
                                  [Sym('uuid'), U('gl', p['ref'], q['num'])],
                                  [Sym('property'), 'Intersheetrefs', '${INTERSHEET_REFS}',
                                   [Sym('at'), ex, ey, ang],
                                   [Sym('effects'), [Sym('font'), [Sym('size'), 1.27, 1.27]], [Sym('hide'), Sym('yes')]]]])
                else:
                    items.append([Sym('label'), net, [Sym('at'), ex, ey, ang],
                                  [Sym('effects'), [Sym('font'), [Sym('size'), 1.27, 1.27]],
                                   [Sym('justify'), just, Sym('bottom')]],
                                  [Sym('uuid'), U('l', p['ref'], q['num'])]])
            used.add(p['sym'])
        # power symbols used
        pw = {POWER_NETS[n] for n in POWER_NETS if any(
            n in p['pins'].values() for p in sp)}
        used |= pw
        items.append([Sym('text'), stitle + ' -- generated by scripts/gen_sch.py from scripts/design.py; edit those, not this file.',
                      [Sym('exclude_from_sim'), Sym('no')], [Sym('at'), 20, 18, 0],
                      [Sym('effects'), [Sym('font'), [Sym('size'), 2.5, 2.5]], [Sym('justify'), Sym('left'), Sym('bottom')]],
                      [Sym('uuid'), U('title', sname)]])
        doc = [Sym('kicad_sch'), [Sym('version'), 20250114], [Sym('generator'), 'eeschema'],
               [Sym('generator_version'), '9.0'], [Sym('uuid'), U('file', sname)],
               [Sym('paper'), paper],
               [Sym('title_block'), [Sym('title'), 'MEGA-KVM %s: %s' % ('shield' if board == 'shield' else 'keyboard sub-board', stitle)],
                [Sym('date'), '2026-11-27'], [Sym('rev'), 'A (draft)'],
                [Sym('company'), 'FPGA-DUT-Manager / MEGA65'],
                [Sym('comment'), 1, 'Issue 0045; pin plan placeholder until docs/hardware/shield-pinplan.md']],
               [Sym('lib_symbols')] + [libsyms[k] for k in libsyms if k in used]] + items
        doc.append([Sym('embedded_fonts'), Sym('no')])
        sheet_files[sname] = (paper, doc)
        with open(os.path.join(PROJ, sname + '.kicad_sch'), 'w') as f:
            f.write(dump(doc) + '\n')

    # root sheet
    items = []
    x, y = 25.4, 40.64
    for page, (sname, stitle) in enumerate(SHEETS, start=2):
        w, h = 76.2, 20.32
        items.append([Sym('sheet'), [Sym('at'), x, y], [Sym('size'), w, h],
                      [Sym('exclude_from_sim'), Sym('no')], [Sym('in_bom'), Sym('yes')],
                      [Sym('on_board'), Sym('yes')], [Sym('dnp'), Sym('no')],
                      [Sym('fields_autoplaced'), Sym('yes')],
                      [Sym('stroke'), [Sym('width'), 0.1524], [Sym('type'), Sym('solid')]],
                      [Sym('fill'), [Sym('color'), 0, 0, 0, 0.0]],
                      [Sym('uuid'), sheet_uuids[sname]],
                      [Sym('property'), 'Sheetname', stitle, [Sym('at'), x, y - 0.7, 0],
                       [Sym('effects'), [Sym('font'), [Sym('size'), 1.27, 1.27]], [Sym('justify'), Sym('left'), Sym('bottom')]]],
                      [Sym('property'), 'Sheetfile', sname + '.kicad_sch', [Sym('at'), x, y + h + 0.6, 0],
                       [Sym('effects'), [Sym('font'), [Sym('size'), 1.27, 1.27]], [Sym('justify'), Sym('left'), Sym('top')]]],
                      [Sym('instances'), [Sym('project'), NAME, [Sym('path'), '/' + root_uuid, [Sym('page'), str(page)]]]]])
        x += 96.52
        if x > 300:
            x, y = 25.4, y + 33.02
    items.append([Sym('text'), notes, [Sym('exclude_from_sim'), Sym('no')], [Sym('at'), 25.4, 140, 0],
                  [Sym('effects'), [Sym('font'), [Sym('size'), 1.6, 1.6]], [Sym('justify'), Sym('left'), Sym('top')]],
                  [Sym('uuid'), U('rootnotes')]])
    root = [Sym('kicad_sch'), [Sym('version'), 20250114], [Sym('generator'), 'eeschema'],
            [Sym('generator_version'), '9.0'], [Sym('uuid'), root_uuid], [Sym('paper'), 'A3'],
            [Sym('title_block'), [Sym('title'), 'MEGA-KVM link-board shield (Mimas A7 V3)' if board == 'shield' else 'MEGA-KVM keyboard sub-board (2 x J5)'],
             [Sym('date'), '2026-11-27'], [Sym('rev'), 'A (draft)'],
             [Sym('company'), 'FPGA-DUT-Manager / MEGA65'],
             [Sym('comment'), 1, 'Issue 0045, ADR 0007; docs/hardware/shield.md']],
            [Sym('lib_symbols')]] + items + [
        [Sym('sheet_instances'), [Sym('path'), '/', [Sym('page'), '1']]],
        [Sym('embedded_fonts'), Sym('no')]]
    with open(os.path.join(PROJ, NAME + '.kicad_sch'), 'w') as f:
        f.write(dump(root) + '\n')

    os.makedirs(os.path.join(PROJ, 'out'), exist_ok=True)
    with open(os.path.join(PROJ, 'out', 'netlist.json'), 'w') as f:
        json.dump(netlist, f, indent=1, sort_keys=True)
    # JLCPCB BOM (populated parts only)
    groups = OrderedDict()
    for ref, p in netlist.items():
        if p['dnp'] or p['fp'].startswith('MountingHole'):
            continue
        key = (p['value'], p['fp'], p['lcsc'], p['mpn'])
        groups.setdefault(key, []).append(ref)
    os.makedirs(os.path.join(PROJ, 'out'), exist_ok=True)
    with open(os.path.join(PROJ, 'out', 'bom-jlcpcb.csv'), 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['Comment', 'Designator', 'Footprint', 'LCSC Part #', 'MPN', 'Qty'])
        for (val, fp, lcsc, mpn), refs in sorted(groups.items(), key=lambda kv: kv[1][0]):
            refs.sort(key=lambda r: (r.rstrip('0123456789'), int(r[len(r.rstrip('0123456789')):] or 0)))
            w.writerow([val, ','.join(refs), fp.split(':')[-1], lcsc or 'TBD', mpn, len(refs)])
    print('parts', len(netlist), 'nets', len(net_pins), 'power symbols', pwr_count[0])


if __name__ == '__main__':
    write_symlib(custom_symbols())
    symlib._cache.pop('shield', None)
    main('shield', os.path.dirname(HERE), 'mega-kvm-shield', design.SHEETS,
         open(os.path.join(HERE, 'root_notes.txt')).read().strip())
    main('kbd', os.path.join(os.path.dirname(HERE), 'kbd-sub'), 'mega-kvm-kbdsub',
         design.KBD_SHEETS, open(os.path.join(HERE, 'kbd_notes.txt')).read().strip())
