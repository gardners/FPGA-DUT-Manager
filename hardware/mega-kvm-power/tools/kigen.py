"""Small KiCad 10 schematic generator.

Symbols are placed on a grid and every pin is connected by a local label
placed exactly on the pin end (no wires), unless the pin is marked no-connect.
The generator also writes a JSON netlist (reference -> footprint, value,
pad -> net) that tools/pcb_build.py uses to build the board in pcbnew.
"""
import copy
import json
import os
import uuid as _uuid

from sexp import Q, dump, find, find_all, parse

SYSLIB = os.environ.get(
    'KICAD_SYMBOL_DIR',
    '/var/lib/flatpak/runtime/org.kicad.KiCad.Library.Symbols/x86_64/stable/active/files/symbols')
HERE = os.path.dirname(os.path.abspath(__file__))
PROJLIB = os.path.join(HERE, '..', 'lib')

_NS = _uuid.UUID('6d2b7b8e-0b7e-4c1e-9a52-4b8f0f6a0047')


def uid(*parts):
    """Deterministic UUIDs so regenerating gives stable files."""
    return str(_uuid.uuid5(_NS, '/'.join(str(p) for p in parts)))


class Libs:
    def __init__(self):
        self.cache = {}

    def _load(self, lib):
        if lib not in self.cache:
            p = os.path.join(PROJLIB, lib + '.kicad_sym')
            if not os.path.exists(p):
                p = os.path.join(SYSLIB, lib + '.kicad_sym')
            tree = parse(open(p).read())
            self.cache[lib] = {s[1]: s for s in find_all(tree, 'symbol')}
        return self.cache[lib]

    def get(self, lib_id):
        lib, name = lib_id.split(':')
        syms = self._load(lib)
        s = copy.deepcopy(syms[name])
        ext = find(s, 'extends')
        if ext:
            parent = self.get(lib + ':' + ext[1])
            # child overrides properties; body comes from parent
            props = {p[1]: p for p in find_all(s, 'property')}
            out = [x for x in parent if not (isinstance(x, list) and x and x[0] == 'property')]
            pprops = find_all(parent, 'property')
            merged = [props.get(p[1], p) for p in pprops]
            merged += [p for k, p in props.items() if k not in {q[1] for q in pprops}]
            # rename sub-symbols
            pname = parent[1].split(':')[-1]
            res = []
            for x in out:
                if isinstance(x, list) and x and x[0] == 'symbol':
                    x = copy.deepcopy(x)
                    x[1] = Q(x[1].replace(pname, name, 1))
                res.append(x)
            res[1] = Q(name)
            idx = 2
            for p in merged:
                res.insert(idx, p)
                idx += 1
            s = res
        s[1] = Q(name)
        return s

    def embedded(self, lib_id):
        s = self.get(lib_id)
        s = copy.deepcopy(s)
        s[1] = Q(lib_id)
        return s

    def pins(self, lib_id, unit=1):
        s = self.get(lib_id)
        name = lib_id.split(':')[1]
        pins = []
        for sub in find_all(s, 'symbol'):
            tail = sub[1][len(name) + 1:].split('_')
            if len(tail) != 2:
                continue
            u, b = int(tail[0]), int(tail[1])
            if u not in (0, unit) or b not in (0, 1):
                continue
            for p in find_all(sub, 'pin'):
                at = find(p, 'at')
                num = find(p, 'number')[1]
                nm = find(p, 'name')[1]
                pins.append({'num': str(num), 'name': str(nm), 'type': p[1],
                             'x': float(at[1]), 'y': float(at[2]),
                             'ang': int(float(at[3])) if len(at) > 3 else 0})
        return pins


def _font(size=1.27):
    return ['font', ['size', size, size]]


def _prop(name, value, x, y, hide=False, ang=0, justify=None):
    eff = ['effects', _font()]
    if justify:
        eff.append(['justify', justify])
    if hide:
        eff.append(['hide', 'yes'])
    return ['property', Q(name), Q(value), ['at', x, y, ang], eff]


class Schematic:
    def __init__(self, name, title, paper='A2', rev='0.1', date='2026-11-27'):
        self.name = name
        self.title = title
        self.paper = paper
        self.rev = rev
        self.date = date
        self.libs = Libs()
        self.items = []
        self.lib_ids = []
        self.root = uid(name, 'root')
        self.parts = {}
        self.comments = []
        self.labels_at = set()
        self.pwr_n = 0

    def place(self, lib_id, ref, value, x, y, nets, footprint='', unit=1,
              dnp=False, fields=None, nc=(), rot=0, in_bom=None):
        """nets: pin number (or pin name) -> net name. Pins not mentioned must
        be listed in nc (no-connect) or an error is raised."""
        if in_bom is None:
            in_bom = not (ref.startswith('#') or footprint.startswith(('MountingHole:', 'Jumper:')))
        if lib_id not in self.lib_ids:
            self.lib_ids.append(lib_id)
        pins = self.libs.pins(lib_id, unit)
        sid = uid(self.name, ref, unit)
        sym = ['symbol', ['lib_id', Q(lib_id)], ['at', x, y, rot], ['unit', unit],
               ['exclude_from_sim', 'no'], ['in_bom', 'yes' if (in_bom if in_bom is not None else not ref.startswith('#')) else 'no'],
               ['on_board', 'no' if ref.startswith('#') else 'yes'],
               ['dnp', 'yes' if dnp else 'no'], ['uuid', Q(sid)]]
        angs = {p['ang'] for p in pins}
        if 0 in angs and 180 in angs and len(pins) > 3 and rot == 0:
            top = max(p['y'] for p in pins) + 3.81
            sym.append(_prop('Reference', ref, x, y - top - 2.54, hide=ref.startswith('#')))
            sym.append(_prop('Value', value, x, y - top))
        else:
            sym.append(_prop('Reference', ref, x + 2.54, y - 1.27, hide=ref.startswith('#'), justify='left'))
            sym.append(_prop('Value', value, x + 2.54, y + 1.27, justify='left'))
        sym.append(_prop('Footprint', footprint, x, y, hide=True))
        sym.append(_prop('Datasheet', (fields or {}).get('Datasheet', ''), x, y, hide=True))
        sym.append(_prop('Description', (fields or {}).get('Description', ''), x, y, hide=True))
        for k, v in (fields or {}).items():
            if k in ('Datasheet', 'Description'):
                continue
            sym.append(_prop(k, v, x, y, hide=True))
        seen_num = set()
        padnets = {}
        used = set()
        for p in pins:
            if p['num'] in seen_num:
                continue
            seen_num.add(p['num'])
            sym.append(['pin', Q(p['num']), ['uuid', Q(uid(sid, 'pin', p['num']))]])
            key = p['num'] if p['num'] in nets else (p['name'] if p['name'] in nets else None)
            # rotate pin position
            px, py = p['x'], p['y']
            ang = p['ang']
            for _ in range((rot // 90) % 4):
                px, py = -py, px
                ang = (ang + 90) % 360
            sx, sy = round(x + px, 4), round(y - py, 4)
            if key is not None:
                used.add(key)
                net = nets[key]
                padnets[p['num']] = net
                if net is None:
                    padnets[p['num']] = 'unconnected-(%s-%s-Pad%s)' % (ref, p['name'], p['num'])
                    self._nc(sx, sy)
                else:
                    self._label(net, sx, sy, (ang + 180) % 360)
            elif p['num'] in nc or p['name'] in nc or '*' in nc:
                padnets[p['num']] = 'unconnected-(%s-%s-Pad%s)' % (ref, p['name'], p['num'])
                self._nc(sx, sy)
            else:
                raise ValueError('%s pin %s (%s) unconnected' % (ref, p['num'], p['name']))
        missing = set(nets) - used
        if missing:
            raise ValueError('%s: unknown pins %s' % (ref, missing))
        sym.append(['instances', ['project', Q(self.name),
                                  ['path', Q('/' + self.root), ['reference', Q(ref)], ['unit', unit]]]])
        self.items.append(sym)
        if not ref.startswith('#'):
            part = self.parts.setdefault(ref, {'footprint': footprint, 'value': value,
                                               'uuid': sid, 'pads': {}, 'dnp': dnp,
                                               'in_bom': in_bom if in_bom is not None else True,
                                               'fields': fields or {}})
            part['pads'].update(padnets)
        return sid

    def _label(self, net, x, y, ang):
        key = (net, x, y)
        if key in self.labels_at:
            return
        self.labels_at.add(key)
        just = 'left' if ang in (0, 90) else 'right'
        self.items.append(['label', Q(net), ['at', x, y, ang],
                           ['effects', _font(1.0), ['justify', just, 'bottom']],
                           ['uuid', Q(uid(self.name, 'lbl', net, x, y))]])

    def _nc(self, x, y):
        self.items.append(['no_connect', ['at', x, y], ['uuid', Q(uid(self.name, 'nc', x, y))]])

    def pwr_flag(self, net, x, y):
        self.pwr_n += 1
        self.place('power:PWR_FLAG', '#FLG%02d' % self.pwr_n, 'PWR_FLAG', x, y, {'1': net})

    def text(self, s, x, y, size=1.5):
        self.items.append(['text', Q(s), ['exclude_from_sim', 'no'], ['at', x, y, 0],
                           ['effects', _font(size), ['justify', 'left', 'top']],
                           ['uuid', Q(uid(self.name, 'txt', x, y, s[:20]))]])

    def box(self, x1, y1, x2, y2, title=None):
        self.items.append(['rectangle', ['start', x1, y1], ['end', x2, y2],
                           ['stroke', ['width', 0.2], ['type', 'dash']], ['fill', ['type', 'none']],
                           ['uuid', Q(uid(self.name, 'box', x1, y1))]])
        if title:
            self.text(title, x1 + 1.27, y1 + 1.27, size=2.0)

    def write(self, outdir):
        tree = ['kicad_sch', ['version', 20250114], ['generator', Q('eeschema')],
                ['generator_version', Q('10.0')], ['uuid', Q(self.root)], ['paper', Q(self.paper)],
                ['title_block', ['title', Q(self.title)], ['date', Q(self.date)], ['rev', Q(self.rev)],
                 ['company', Q('FPGA-DUT-Manager / MEGA-KVM')],
                 ['comment', 1, Q('Generated by tools/gen_*.py - edit the generator, not this file')]]]
        tree.append(['lib_symbols'] + [self.libs.embedded(l) for l in self.lib_ids])
        tree += self.items
        tree.append(['sheet_instances', ['path', Q('/'), ['page', Q('1')]]])
        tree.append(['embedded_fonts', 'no'])
        with open(os.path.join(outdir, self.name + '.kicad_sch'), 'w') as f:
            f.write(dump(tree) + '\n')
        with open(os.path.join(outdir, self.name + '.netlist.json'), 'w') as f:
            json.dump(self.parts, f, indent=1, sort_keys=True)


def write_project(outdir, name):
    pro = {
        "board": {"design_settings": {"defaults": {"copper_line_width": 0.2},
                                       "rules": {"min_clearance": 0.2, "min_track_width": 0.2,
                                                 "min_via_diameter": 0.6, "min_through_hole_diameter": 0.3}}},
        "meta": {"filename": name + ".kicad_pro", "version": 3},
        "net_settings": {"classes": [
            {"name": "Default", "clearance": 0.2, "track_width": 0.25, "via_diameter": 0.6, "via_drill": 0.3},
            {"name": "Power", "clearance": 0.3, "track_width": 2.0, "via_diameter": 0.8, "via_drill": 0.4}],
            "meta": {"version": 4}},
        "erc": {"rule_severities": {"lib_symbol_issues": "ignore", "lib_symbol_mismatch": "ignore",
                                    "footprint_link_issues": "ignore"}},
        "schematic": {"meta": {"version": 1}},
        "sheets": [[uid(name, 'root'), "Root"]],
    }
    with open(os.path.join(outdir, name + '.kicad_pro'), 'w') as f:
        json.dump(pro, f, indent=2)
    with open(os.path.join(outdir, 'sym-lib-table'), 'w') as f:
        f.write('(sym_lib_table\n  (version 7)\n  (lib (name "mega-kvm-power")(type "KiCad")'
                '(uri "${KIPRJMOD}/../lib/mega-kvm-power.kicad_sym")(options "")(descr "MEGA-KVM power board parts"))\n)\n')
    with open(os.path.join(outdir, 'fp-lib-table'), 'w') as f:
        f.write('(fp_lib_table\n  (version 7)\n  (lib (name "mega-kvm-power")(type "KiCad")'
                '(uri "${KIPRJMOD}/../lib/mega-kvm-power.pretty")(options "")(descr "MEGA-KVM power board footprints"))\n)\n')
