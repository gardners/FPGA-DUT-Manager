"""Print the pins of library symbols: python3 pins.py Lib:Name ..."""
import sys

from kigen import Libs

L = Libs()
for lid in sys.argv[1:]:
    s = L.get(lid)
    fp = [p for p in s if isinstance(p, list) and p[:2] == ['property', 'Footprint']]
    print(lid, fp[0][2] if fp else '')
    for p in L.pins(lid):
        print('   %4s %-12s %-14s (%g, %g) %d' % (p['num'], p['name'], p['type'], p['x'], p['y'], p['ang']))
