# classtree
# Purpose: class parents and default RemoteRole, bNoDelete, bStatic, bAlwaysRelevant from the UnrealScript sources.
# Entry points: parent, get(), chain(), triggerclass(), used by clientmissing.py.
# Logging: none yet.
# State: parent, defs, hasTrigger, filled on import.
# Known limitations: needs the exported game sources next to ModCoop in Code.
import os,re,glob
from paths import CODE
parent={}; defs={}; hasTrigger={}
for f in glob.glob(CODE+'/*/Classes/*.uc'):
    if '/ModCoop/' in f.replace('\\','/'): continue
    t=open(f,encoding='latin1').read()
    m=re.search(r'^\s*class\s+(\w+)\s+extends\s+(\w+)',t,re.M|re.I)
    if not m: continue
    c=m.group(1); parent[c]=m.group(2)
    d={}
    dp=t[t.lower().rfind('defaultproperties'):] if 'defaultproperties' in t.lower() else ''
    for k in ('RemoteRole','bNoDelete','bStatic','bAlwaysRelevant','bHidden'):
        mm=re.search(r'^\s*'+k+r'\s*=\s*(\S+)',dp,re.M|re.I)
        if mm: d[k]=mm.group(1)
    defs[c]=d
    hasTrigger[c]=bool(re.search(r'^\s*(simulated\s+)?(event|function)\s+Trigger\s*\(',t,re.M|re.I))
def get(c,k):
    while c:
        if c in defs and k in defs[c]: return defs[c][k]
        c=parent.get(c)
    return None
def chain(c):
    out=[]
    while c: out.append(c); c=parent.get(c)
    return out
def triggerclass(c):
    for x in chain(c):
        if hasTrigger.get(x): return x
    return None
