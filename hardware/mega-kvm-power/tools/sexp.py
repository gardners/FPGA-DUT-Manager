"""Minimal S-expression reader/writer for KiCad files.

Atoms are kept as Python str; quoted strings are wrapped in Q so that they
are written back quoted. Lists are Python lists.
"""


class Q(str):
    """A quoted string atom."""


def parse(text):
    pos = 0
    n = len(text)
    stack = [[]]
    while pos < n:
        c = text[pos]
        if c in ' \t\r\n':
            pos += 1
        elif c == '(':
            stack.append([])
            pos += 1
        elif c == ')':
            done = stack.pop()
            stack[-1].append(done)
            pos += 1
        elif c == '"':
            pos += 1
            buf = []
            while True:
                c = text[pos]
                if c == '\\':
                    nxt = text[pos + 1]
                    buf.append({'n': '\n', 't': '\t'}.get(nxt, nxt))
                    pos += 2
                elif c == '"':
                    pos += 1
                    break
                else:
                    buf.append(c)
                    pos += 1
            stack[-1].append(Q(''.join(buf)))
        else:
            start = pos
            while pos < n and text[pos] not in ' \t\r\n()':
                pos += 1
            stack[-1].append(text[start:pos])
    return stack[0][0] if len(stack[0]) == 1 else stack[0]


def _atom(a):
    if isinstance(a, Q):
        return '"' + a.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(a, float):
        s = ('%.4f' % a).rstrip('0').rstrip('.')
        return '0' if s in ('-0', '') else s
    return str(a)


def dump(e, indent=0):
    if not isinstance(e, list):
        return _atom(e)
    if all(not isinstance(x, list) for x in e):
        return '(' + ' '.join(_atom(x) for x in e) + ')'
    pad = '\t' * (indent + 1)
    head = []
    rest = []
    for x in e:
        if not rest and not isinstance(x, list):
            head.append(_atom(x))
        else:
            rest.append(x)
    out = '(' + ' '.join(head)
    for x in rest:
        out += '\n' + pad + dump(x, indent + 1)
    out += '\n' + '\t' * indent + ')'
    return out


def find(e, key):
    """First child list whose head is key."""
    for x in e:
        if isinstance(x, list) and x and x[0] == key:
            return x
    return None


def find_all(e, key):
    return [x for x in e if isinstance(x, list) and x and x[0] == key]
