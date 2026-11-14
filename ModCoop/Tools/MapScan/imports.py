# imports
# Purpose: which package each class imported by a map comes from.
# Entry points: groups(path), used by clientmissing.py.
# Logging: none yet.
# State: none yet.
# Known limitations: none yet.
import struct
def groups(p):
    d=open(p,'rb').read(); pos=[0]
    def i32():
        v=struct.unpack_from('<i',d,pos[0])[0]; pos[0]+=4; return v
    def ci():
        q=pos[0]; b0=d[q]; q+=1; v=b0&0x3f; neg=b0&0x80
        if b0&0x40:
            b1=d[q]; q+=1; v|=(b1&0x7f)<<6
            if b1&0x80:
                b2=d[q]; q+=1; v|=(b2&0x7f)<<13
                if b2&0x80:
                    b3=d[q]; q+=1; v|=(b3&0x7f)<<20
        pos[0]=q; return -v if neg else v
    i32(); i32(); i32(); nc=i32(); no=i32(); ec=i32(); eo=i32(); ic=i32(); io=i32()
    pos[0]=no; names=[]
    for _ in range(nc):
        l=ci(); names.append(d[pos[0]:pos[0]+l-1].decode('latin1')); pos[0]+=l; i32()
    pos[0]=io; imps=[]
    for _ in range(ic):
        a=ci(); b=ci(); o=i32(); n=ci(); imps.append((names[b],o,names[n]))
    out={}
    for b,o,n in imps:
        if b=='Class' and o<0: out[n]=imps[-o-1][2]
    return out
