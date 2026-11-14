# seq
# Purpose: prints level scripts with their actions, from a dump of mapscan.py.
#   Usage: python -I seq.py <dump.txt> <tag or name regex>
# Entry points: the command line.
# Logging: stdout only.
# State: none yet.
# Known limitations: none yet.
import sys, re
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
lines = open(sys.argv[1], encoding='utf-8', errors='replace').read().split('\n')
byidx = {}
for l in lines:
    m = re.match(r'(\d+) (\S+) (\S+) (.*)$', l)
    if m:
        byidx[int(m.group(1))] = (m.group(2), m.group(3), m.group(4))
pat = re.compile(sys.argv[2])
for i, (cls, name, props) in byidx.items():
    if cls != 'ScriptedSequence' and cls != 'ScriptedTrigger':
        continue
    tag = re.search(r"\('Tag', '([^']*)'\)", props)
    tag = tag.group(1) if tag else ''
    if not (pat.search(tag) or pat.search(name)):
        continue
    print('==', name, 'Tag=' + tag)
    acts = re.search(r"\('Actions', \[([^\]]*)\]", props)
    if not acts:
        continue
    for n, a in enumerate(re.findall(r"'([^']*)'", acts.group(1))):
        k = int(a.split('#')[1])
        c, nm, p = byidx.get(k, ('?', a, ''))
        print('  %2d %s %s' % (n, c, p[:200]))
