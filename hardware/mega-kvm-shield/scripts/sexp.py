"""Minimal s-expression reader/writer for KiCad files."""
import re

_TOK = re.compile(r'\s*(?:(\()|(\))|("(?:[^"\\]|\\.)*")|([^\s()"]+))', re.S)


class Sym(str):
    """An unquoted atom."""


def parse(text):
    stack = [[]]
    pos = 0
    while True:
        m = _TOK.match(text, pos)
        if not m:
            break
        pos = m.end()
        lp, rp, s, a = m.groups()
        if lp:
            stack.append([])
        elif rp:
            x = stack.pop()
            stack[-1].append(x)
        elif s is not None:
            stack[-1].append(re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s[1:-1], flags=re.S))
        elif a is not None:
            stack[-1].append(Sym(a))
    return stack[0][0]


def q(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def dump(x, ind=0):
    if isinstance(x, list):
        if not x:
            return '()'
        simple = all(not isinstance(e, list) for e in x)
        if simple:
            return '(' + ' '.join(dump(e) for e in x) + ')'
        out = '(' + dump(x[0])
        for e in x[1:]:
            if isinstance(e, list):
                out += '\n' + '\t' * (ind + 1) + dump(e, ind + 1)
            else:
                out += ' ' + dump(e)
        return out + '\n' + '\t' * ind + ')'
    if isinstance(x, Sym):
        return str(x)
    if isinstance(x, bool):
        return 'yes' if x else 'no'
    if isinstance(x, float):
        s = ('%.4f' % x).rstrip('0').rstrip('.')
        return s if s not in ('-0', '') else '0'
    if isinstance(x, int):
        return str(x)
    return q(x)


def find(x, key):
    for e in x:
        if isinstance(e, list) and e and e[0] == key:
            return e
    return None


def findall(x, key):
    return [e for e in x if isinstance(e, list) and e and e[0] == key]
