# mapscan
# Purpose: reads a .ctm map package: dumps its actors (class, name, simple properties) and the actions of its scripts.
#   Usage: python -I mapscan.py <map.ctm> [class filter ...] > dump.txt. seq.py reads such a dump, the other scans import load().
# Entry points: load(path), the command line.
# Logging: stdout only.
# State: none yet.
# Known limitations: arrays of structs (Dispatcher.Events, ActivationInfo) print as arr(N), disp.py finds those.
import struct,sys
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
TYPES={1:'byte',2:'int',3:'bool',4:'float',5:'obj',6:'name',7:'str',8:'cls',9:'arr',10:'struct',11:'vec',12:'rot',13:'str',14:'map',15:'farr'}

def load(path):
    d=open(path,'rb').read()
    st={'pos':0}
    def i32():
        v=struct.unpack_from('<i',d,st['pos'])[0]; st['pos']+=4; return v
    def u8():
        v=d[st['pos']]; st['pos']+=1; return v
    def ci():
        p=st['pos']; b0=d[p]; p+=1
        v=b0&0x3f; neg=b0&0x80
        if b0&0x40:
            b1=d[p]; p+=1; v|=(b1&0x7f)<<6
            if b1&0x80:
                b2=d[p]; p+=1; v|=(b2&0x7f)<<13
                if b2&0x80:
                    b3=d[p]; p+=1; v|=(b3&0x7f)<<20
                    if b3&0x80:
                        b4=d[p]; p+=1; v|=b4<<27
        st['pos']=p
        return -v if neg else v
    i32(); ver=i32()&0xffff; i32()
    nc=i32(); no=i32(); ec=i32(); eo=i32(); ic=i32(); io=i32()
    st['pos']=no; names=[]
    for _ in range(nc):
        l=ci(); s=d[st['pos']:st['pos']+l-1].decode('latin1'); st['pos']+=l; i32(); names.append(s)
    st['pos']=io; imps=[]
    for _ in range(ic):
        ci(); ci(); i32(); on=ci(); imps.append(names[on])
    st['pos']=eo; exps=[]
    for _ in range(ec):
        cl=ci(); su=ci(); i32(); pk=ci(); on=ci(); fl=i32(); sz=i32(); of=i32()
        exps.append([cl,names[on],sz,of,pk,fl,su])
    def ref(r):
        if r<0: return imps[-r-1]
        if r>0: return exps[r-1][1]+('#%d'%r)
        return 'None'
    def cls(e): return ref(e[0]).split('#')[0] if e[0] else 'Class'
    def props(e):
        out=[]
        st['pos']=e[3]; end=e[3]+e[2]
        if e[5]&0x02000000:
            node=ci(); ci(); st['pos']+=10
            if node: ci()
        try:
            while st['pos']<end:
                nm=names[ci()]
                if nm=='None': break
                info=u8(); t=info&0xf; sb=(info>>4)&7
                sn=names[ci()] if t==10 else None
                sz={0:1,1:2,2:4,3:12,4:16}.get(sb)
                if sz is None:
                    sz={5:lambda:u8(),6:lambda:struct.unpack_from('<H',d,st['pos'])[0],7:lambda:i32()}[sb]()
                    if sb==6: st['pos']+=2
                idx=0
                if info&0x80 and t!=3:
                    b=u8()
                    if b&0x80:
                        if b&0x40: idx=((b&0x3f)<<24)|(u8()<<16)|(u8()<<8)|u8()
                        else: idx=((b&0x7f)<<8)|u8()
                    else: idx=b
                p=st['pos']; v=None
                if t==3: v=bool(info&0x80); sz=0
                elif t in (5,8): v=ref(ci())
                elif t==6: v=names[ci()]
                elif t==2: v=struct.unpack_from('<i',d,p)[0]
                elif t==4: v=round(struct.unpack_from('<f',d,p)[0],2)
                elif t==1: v=d[p]
                elif t==13 or t==7:
                    l=ci(); v=d[st['pos']:st['pos']+abs(l)-1].decode('latin1','replace')
                elif t==10 and sn=='Vector': v=tuple(round(x) for x in struct.unpack_from('<3f',d,p))
                elif t==9:
                    try:
                        n=ci(); lst=[ci() for _ in range(n)]
                        if st['pos']==p+sz: v=[ref(x) for x in lst]
                        else: v='arr(%d)'%sz
                    except Exception: v='arr(%d)'%sz
                else: v='%s(%d)'%(sn or TYPES.get(t,t),sz)
                st['pos']=p+sz
                out.append((nm+('[%d]'%idx if idx else ''),v))
        except Exception as ex:
            out.append(('ERR',str(ex)))
        return out
    return names,imps,exps,ref,cls,props

if __name__=='__main__':
    names,imps,exps,ref,cls,props=load(sys.argv[1])
    for i,e in enumerate(exps):
        c=cls(e)
        if sys.argv[2:] and not any(k.lower() in c.lower() for k in sys.argv[2:]): continue
        print(i+1,c,e[1],props(e))
