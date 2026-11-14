# memberevents
# Purpose: events that only the scripts of Delta squad members trigger, where in the script, and who waits for them.
#   A client taking a member drops that script, so these events are the ones that can stop a level.
#   Usage: python -I memberevents.py [map name ...]
# Entry points: the command line.
# Logging: stdout only.
# State: none yet.
# Known limitations: none yet.
import sys,os,collections
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import mapscan
from paths import campaign_maps
MEM=('Commando07Delta','Commando40Delta','Commando62Delta','Commando38Delta')
GATES=('ACTION_WaitForEvent','ACTION_WaitForPlayer','ACTION_IfCondition','ACTION_IfRandomPct','ACTION_GotoLabel','ACTION_GotoAction','ACTION_EndSection','ACTION_ChangeScript')
def enc(v):
    out=bytearray(); a=abs(v); b0=a&0x3f
    if v<0: b0|=0x80
    a>>=6
    if a: b0|=0x40
    out.append(b0)
    while a:
        b=a&0x7f; a>>=7
        if a: b|=0x80
        out.append(b)
    return bytes(out)
for path in campaign_maps():
    m=os.path.basename(path)[:-4]
    if sys.argv[1:] and m not in sys.argv[1:]: continue
    names,imps,exps,ref,cls,props=mapscan.load(path)
    raw=open(path,'rb').read()
    P={}
    def pr(i):
        if i not in P: P[i]=dict(props(exps[i-1]))
        return P[i]
    idx=lambda r:int(r.split('#')[1]) if isinstance(r,str) and '#' in r else 0
    scripts={}
    memtags={}
    for i,e in enumerate(exps,1):
        if cls(e) in MEM:
            t=pr(i).get('AIScriptTag')
            if t: memtags[t]=cls(e)
    owner={}
    for i,e in enumerate(exps,1):
        c=cls(e)
        if c.endswith('Sequence') or c.endswith('Script') or c=='ScriptedTrigger':
            p=pr(i)
            if isinstance(p.get('Actions'),list):
                scripts[i]=p
                for a in p['Actions']:
                    if idx(a): owner[idx(a)]=i
    fired=collections.defaultdict(set)   # event -> scripts that trigger it
    for i,e in enumerate(exps,1):
        if cls(e)=='ACTION_TriggerEvent' and i in owner:
            ev=pr(i).get('Event')
            if ev: fired[ev].add(owner[i])
    def otherrefs(ev):
        # Raw references to a name outside ACTION_TriggerEvent, ACTION_WaitForEvent and the listener itself
        ids=[k for k,n in enumerate(names) if n==ev]
        res=[]
        for k in ids:
            pat=enc(k)
            for j,e in enumerate(exps,1):
                c=cls(e)
                if c in('ACTION_TriggerEvent','ACTION_WaitForEvent'): continue
                if pat in raw[e[3]:e[3]+e[2]]:
                    p=pr(j)
                    if p.get('Tag')==ev: continue
                    res.append('%s %s'%(c,e[1]))
        return res
    def listeners(ev):
        res=[]
        for j,e in enumerate(exps,1):
            c=cls(e)
            if c=='ACTION_WaitForEvent' and pr(j).get('ExternalEvent')==ev and j in owner:
                o=scripts[owner[j]]; res.append('wait in %s(%s)'%(exps[owner[j]-1][1],o.get('Tag','')))
            elif c!='ACTION_TriggerEvent' and not c.startswith('ACTION_') and pr(j).get('Tag')==ev and j not in scripts:
                res.append('%s %s'%(c,e[1]))
            elif c=='TriggeredCondition' and pr(j).get('Tag')==ev:
                res.append('condition')
        return res
    out=[]
    for si,p in scripts.items():
        tag=p.get('Tag','')
        if tag not in memtags: continue
        gates=0; gate='start'; lastmove=''
        for a in p['Actions']:
            ai=idx(a)
            if not ai: continue
            c=cls(exps[ai-1]); q=pr(ai)
            if c in GATES:
                gates+=1
                gate=c.replace('ACTION_','')+(':'+str(q.get('ExternalEvent')) if c=='ACTION_WaitForEvent' else '')
                lastmove=''
            if c=='ACTION_MoveToPoint': lastmove=str(q.get('DestinationTag'))
            if c=='ACTION_TriggerEvent' and q.get('Event'):
                ev=q['Event']
                others=[s for s in fired[ev] if scripts[s].get('Tag','') not in memtags]
                orefs=otherrefs(ev)
                lis=listeners(ev)
                if others or orefs or not lis: continue
                out.append('  %s #%d after %s%s: %s -> %s'%(memtags[tag],gates,gate,(' move '+lastmove) if lastmove else '',ev,'; '.join(lis)))
    if out:
        print('==',m); print('\n'.join(out))
