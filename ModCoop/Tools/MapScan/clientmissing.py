# clientmissing
# Purpose: placed actors that clients delete when loading a map and the server never sends (not static, not bNoDelete, RemoteRole None).
#   Usage: python -I clientmissing.py
# Entry points: the command line.
# Logging: stdout only.
# State: none yet.
# Known limitations: classes that are in neither the sources nor GROUP are skipped.
import sys,os,collections
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import mapscan, classtree as T, imports
from paths import campaign_maps
GROUP={'KarmaPropProperties':'KarmaProp','AnimPropProperties':'AnimProp','MarkerProperties':'ActivateItem','Properties':'Actor'}
tot=collections.Counter(); maps=collections.defaultdict(set)
for p in campaign_maps():
    m=os.path.basename(p)[:-4]
    names,imps,exps,ref,cls,props=mapscan.load(p)
    grp=imports.groups(p)
    for i,e in enumerate(exps,1):
        c=cls(e)
        if c in('Class','Model','Polys','BspNode','ReachSpec','StaticMeshInstance','Level','LevelSummary','Brush') or c.startswith('ACTION_'): continue
        base=c if c in T.parent else GROUP.get(grp.get(c,''))
        if base is None:
            continue
        if 'Actor' not in T.chain(base): continue
        try: d=dict(props(e))
        except Exception: d={}
        st=str(d.get('bStatic',T.get(base,'bStatic')))=='True'
        nd=str(d.get('bNoDelete',T.get(base,'bNoDelete')))=='True'
        rr=str(d.get('RemoteRole',T.get(base,'RemoteRole')))
        if st or nd: continue
        if rr not in('ROLE_None','0'): continue
        tot[c]+=1; maps[c].add(m)
for c,n in sorted(tot.items(),key=lambda kv:-kv[1]):
    print('%-28s %-22s %5d  %s'%(c,'/'.join(T.chain(c if c in T.parent else 'Actor')[1:3]),n,' '.join(sorted(maps[c]))[:150]))
