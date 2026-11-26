"""Load KiCad library symbols (flattening 'extends') and report pins."""
import os
import copy
from sexp import parse, find, findall, Sym

SYMDIRS = ['/usr/share/kicad/symbols', '/app/extensions/Library/symbols']
_cache = {}


def _lib(name, extra=None):
    if name in _cache:
        return _cache[name]
    paths = [extra] if extra else []
    paths += [os.path.join(d, name + '.kicad_sym') for d in SYMDIRS]
    for p in paths:
        if p and os.path.exists(p):
            tree = parse(open(p).read())
            syms = {e[1]: e for e in findall(tree, 'symbol')}
            _cache[name] = syms
            return syms
    raise FileNotFoundError(name)


def load(libid, local_path=None):
    """Return a flattened symbol s-expr named 'lib:name'."""
    lib, name = libid.split(':')
    syms = _lib(lib, local_path if lib == 'shield' else None)
    s = copy.deepcopy(syms[name])
    ext = find(s, 'extends')
    if ext:
        parent = load(lib + ':' + ext[1], local_path)
        base = copy.deepcopy(parent)
        # child properties override the parent's
        props = {p[1]: p for p in findall(s, 'property')}
        out = []
        for e in base:
            if isinstance(e, list) and e and e[0] == 'property' and e[1] in props:
                out.append(props.pop(e[1]))
            elif isinstance(e, list) and e and e[0] == 'symbol':
                sub = copy.deepcopy(e)
                sub[1] = sub[1].replace(ext[1], name, 1)
                out.append(sub)
            else:
                out.append(e)
        # insert remaining child-only properties after the last property
        idx = max(i for i, e in enumerate(out) if isinstance(e, list) and e and e[0] == 'property')
        for p in props.values():
            idx += 1
            out.insert(idx, p)
        s = out
    s[1] = libid
    return s


def pins(sym):
    """List of (number, name, x, y, angle, length, etype) in symbol units (y up)."""
    res = []

    def walk(x, unit):
        for e in x:
            if isinstance(e, list) and e:
                if e[0] == 'symbol':
                    parts = e[1].rsplit('_', 2)
                    u = int(parts[-2]) if len(parts) >= 3 and parts[-2].isdigit() else 0
                    walk(e, u)
                elif e[0] == 'pin':
                    at = find(e, 'at')
                    ln = find(e, 'length')
                    nm = find(e, 'name')[1]
                    num = find(e, 'number')[1]
                    res.append(dict(num=num, name=nm, x=float(at[1]), y=float(at[2]),
                                    ang=float(at[3]) if len(at) > 3 else 0.0,
                                    len=float(ln[1]), etype=str(e[1]), unit=unit,
                                    hidden=any(isinstance(z, Sym) and z == 'hide' for z in e)
                                    or bool(find(e, 'hide'))))
    walk(sym, 0)
    return res


if __name__ == '__main__':
    import sys
    for a in sys.argv[1:]:
        s = load(a)
        fp = [p for p in findall(s, 'property') if p[1] == 'Footprint']
        print('==', a, fp[0][2] if fp else '')
        for p in pins(s):
            print('  %4s %-12s %7.2f %7.2f %4d %s u%d%s' % (p['num'], p['name'], p['x'], p['y'], p['ang'], p['etype'], p['unit'], ' H' if p['hidden'] else ''))
