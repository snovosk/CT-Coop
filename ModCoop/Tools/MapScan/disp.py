# disp
# Purpose: finds every export whose raw data references a name, for events the text dump can't show (Dispatcher arrays, ActivationInfo structs).
#   Usage: python -I disp.py <map.ctm> <EventName>
# Entry points: the command line.
# Logging: stdout only.
# State: none yet.
# Known limitations: searches raw bytes, a short name index can match by chance. Read the hit before trusting it.
import os,sys
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import mapscan
path, want = sys.argv[1], sys.argv[2]
names, imps, exps, ref, cls, props = mapscan.load(path)
d = open(path, 'rb').read()
idx = [i for i, n in enumerate(names) if n.lower() == want.lower()]
print('name index', idx)
def enc(v):
    out = bytearray(); a = abs(v)
    b0 = a & 0x3f
    if v < 0: b0 |= 0x80
    a >>= 6
    if a: b0 |= 0x40
    out.append(b0)
    while a:
        b = a & 0x7f; a >>= 7
        if a: b |= 0x80
        out.append(b)
    return bytes(out)
for i in idx:
    pat = enc(i)
    for k, e in enumerate(exps):
        blob = d[e[3]:e[3] + e[2]]
        if pat in blob:
            print(k + 1, cls(e), e[1], [p for p in props(e) if p[0] in ('Tag', 'Event', 'Location')])
