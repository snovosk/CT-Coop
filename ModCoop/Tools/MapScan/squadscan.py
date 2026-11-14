# squadscan
# Purpose: everything in the campaign maps that counts squad members or players: triggers, counters, conditions.
#   Usage: python -I squadscan.py [map name ...]
# Entry points: the command line.
# Logging: stdout only.
# State: none yet.
# Known limitations: none yet.
import sys,os,collections
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import mapscan
from paths import campaign_maps
TT=['Player','Pawn','Class','Any','Shoot','HumanPlayer','Use','SquadMember']
want=set(sys.argv[1:])
for path in campaign_maps():
    m=os.path.basename(path)[:-4]
    if want and m not in want: continue
    names,imps,exps,ref,cls,props=mapscan.load(path)
    P={}
    def pr(i):
        if i not in P: P[i]=dict(props(exps[i-1]))
        return P[i]
    idx=lambda r:int(r.split('#')[1]) if isinstance(r,str) and '#' in r else 0
    # Who fires each event: actors with Event, TriggerEvent actions (owner script)
    firers=collections.defaultdict(list)
    owner={}
    for i,e in enumerate(exps,1):
        c=cls(e)
        p=pr(i) if (c.endswith('Sequence') or c.endswith('Script') or c=='ScriptedTrigger' or 'Trigger' in c or c in('Counter','Dispatcher') or c.startswith('Marker')) else None
        if p is None: continue
        if isinstance(p.get('Actions'),list):
            for a in p['Actions']:
                ai=idx(a)
                if ai: owner[ai]=(c,e[1],p.get('Tag',''))
        if p.get('Event') and not c.startswith('ACTION_'):
            firers[p['Event']].append('%s %s(type %s)'%(c,e[1],TT[p['TriggerType']] if 'TriggerType' in p and isinstance(p['TriggerType'],int) and p['TriggerType']<8 else ('Player' if 'Trigger'==c else '-')))
    for i,e in enumerate(exps,1):
        if cls(e)=='ACTION_TriggerEvent':
            ev=pr(i).get('Event'); o=owner.get(i)
            if ev and o: firers[ev].append('script %s %s'%(o[0],o[1]))
    out=[]
    for i,e in enumerate(exps,1):
        c=cls(e)
        if c in('Trigger','TeamTrigger') or c.endswith('Trigger') and c not in('ScriptedTrigger','IMuseTrigger','TriggerLight','TimedTrigger'):
            p=pr(i); t=p.get('TriggerType',0)
            tn=TT[t] if isinstance(t,int) and t<8 else t
            if tn in('SquadMember','Class','Pawn','HumanPlayer'):
                out.append('  TRIGGER %s %s type=%s class=%s tag=%s -> %s once=%s'%(c,e[1],tn,p.get('ClassProximityType',''),p.get('Tag',''),p.get('Event',''),p.get('bTriggerOnceOnly','')))
        elif c=='Counter':
            p=pr(i); tag=p.get('Tag','')
            out.append('  COUNTER %s tag=%s num=%s -> %s  fed by: %s'%(e[1],tag,p.get('NumToCount',2),p.get('Event',''),'; '.join(firers.get(tag,['?']))))
        elif c in('ACTION_WaitForPlayer','ACTION_MoveToPlayer','ACTION_IfCondition'):
            o=owner.get(i)
            out.append('  %s in %s  %s'%(c,o[1] if o else '?',{k:v for k,v in pr(i).items() if k in('Distance','TriggeredConditionTag','T')}))
        elif c=='TriggeredCondition':
            p=pr(i); out.append('  CONDITION %s tag=%s %s'%(e[1],p.get('Tag',''),{k:v for k,v in p.items() if k.startswith('b')}))
    if out:
        print('==',m); print('\n'.join(out))
