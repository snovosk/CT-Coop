// Variable-size ASCII transport avoids sending six empty fixed-array layers.
// At most 160 ASCII bytes per pawn, 72 for the common one-layer pose.
// Position/velocity/rotation retain full precision; phase error <= 1/65535.
struct FCombatWireLayer
{
    INT SequenceId,BoneId;
    FLOAT Phase,Speed,EndPhase;
    BYTE Channel,Weight,Flags,Reserved;
};
struct FCombatWire
{
    FVector Position,Velocity;
    FRotator Facing;
    BYTE IdleState,Flags,PhysicsMode,Pad;
    INT LayerCount;
    FCombatWireLayer Layers[6];
};
static_assert(sizeof(FCombatWire)==188,"combat wire struct");
static const char CombatAlphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static void CombatPut16(BYTE*& P,INT V) { *P++=(BYTE)V; *P++=(BYTE)(V>>8); }
static INT CombatGet16(const BYTE*& P) { INT V=P[0]+(P[1]<<8); P+=2; return V; }
static INT CombatSix(char C)
{
    if(C>='A' && C<='Z') return C-'A';
    if(C>='a' && C<='z') return C-'a'+26;
    if(C>='0' && C<='9') return C-'0'+52;
    if(C=='+') return 62;
    if(C=='/') return 63;
    return -1;
}
void UCoopNative::execPackCombatWire(FFrame& Stack,void* Result)
{
    P_GET_STRUCT(FCombatWire,W);
    P_FINISH;
    FString& Out=*static_cast<FString*>(Result); Out=TEXT("");
    if(W.LayerCount<0 || W.LayerCount>6) return;
    BYTE Raw[118]; appMemcpy(Raw,&W,36);
    BYTE* P=Raw+36; *P++=W.IdleState; *P++=W.Flags; *P++=W.PhysicsMode; *P++=(BYTE)W.LayerCount;
    for(INT i=0;i<W.LayerCount;++i)
    {
        FCombatWireLayer& L=W.Layers[i];
        if(L.SequenceId<=0 || L.SequenceId>1024 || L.BoneId<0 || L.BoneId>1024 ||
           !(L.Phase>=0 && L.Phase<=1) || !(L.Speed>=0 && L.Speed<=32) || !(L.EndPhase>=0 && L.EndPhase<=1)) return;
        CombatPut16(P,L.SequenceId); CombatPut16(P,L.BoneId);
        CombatPut16(P,appRound(L.Phase*65535)); CombatPut16(P,appRound(L.Speed*(65535.f/32)));
        CombatPut16(P,appRound(L.EndPhase*65535)); *P++=L.Channel; *P++=L.Weight; *P++=L.Flags;
    }
    INT N=P-Raw,J=0; char Text[161];
    for(INT i=0;i<N;i+=3)
    {
        DWORD V=(Raw[i]<<16) | (i+1<N ? Raw[i+1]<<8 : 0) | (i+2<N ? Raw[i+2] : 0);
        Text[J++]=CombatAlphabet[(V>>18)&63]; Text[J++]=CombatAlphabet[(V>>12)&63];
        Text[J++]=i+1<N ? CombatAlphabet[(V>>6)&63] : '='; Text[J++]=i+2<N ? CombatAlphabet[V&63] : '=';
    }
    Text[J]=0; Out=Text;
}
void UCoopNative::execUnpackCombatWire(FFrame& Stack,void* Result)
{
    P_GET_STR(Text);
    P_GET_STRUCT_REF(FCombatWire,W);
    P_FINISH;
    appMemzero(W,sizeof(*W)); *static_cast<UBOOL*>(Result)=0;
    if(Text.Len()<56 || Text.Len()>160 || Text.Len()%4) return;
    BYTE Raw[120]; INT N=0;
    for(INT i=0;i<Text.Len();i+=4)
    {
        INT A=CombatSix((*Text)[i]),B=CombatSix((*Text)[i+1]);
        INT C=(*Text)[i+2]=='=' ? 0 : CombatSix((*Text)[i+2]);
        INT D=(*Text)[i+3]=='=' ? 0 : CombatSix((*Text)[i+3]);
        if(A<0 || B<0 || C<0 || D<0 || (((*Text)[i+2]=='=' || (*Text)[i+3]=='=') && i+4!=Text.Len()) ||
           ((*Text)[i+2]=='=' && (*Text)[i+3]!='=')) return;
        DWORD V=(A<<18)|(B<<12)|(C<<6)|D;
        Raw[N++]=(BYTE)(V>>16);
        if((*Text)[i+2]!='=') Raw[N++]=(BYTE)(V>>8);
        if((*Text)[i+3]!='=') Raw[N++]=(BYTE)V;
    }
    if(N<40 || Raw[39]>6 || N!=40+Raw[39]*13) return;
    appMemcpy(W,Raw,36); W->IdleState=Raw[36]; W->Flags=Raw[37]; W->PhysicsMode=Raw[38]; W->LayerCount=Raw[39];
    for(INT i=0;i<6;++i)
    {
        FLOAT V=((FLOAT*)W)[i];
        if(!(V>=-100000000.f && V<=100000000.f)) return;
    }
    const BYTE* P=Raw+40;
    for(INT i=0;i<W->LayerCount;++i)
    {
        FCombatWireLayer& L=W->Layers[i];
        L.SequenceId=CombatGet16(P); L.BoneId=CombatGet16(P);
        L.Phase=CombatGet16(P)/65535.f; L.Speed=CombatGet16(P)*(32.f/65535); L.EndPhase=CombatGet16(P)/65535.f;
        L.Channel=*P++; L.Weight=*P++; L.Flags=*P++;
        if(L.SequenceId<=0 || L.SequenceId>1024 || L.BoneId>1024 || L.Channel>127) return;
    }
    *static_cast<UBOOL*>(Result)=1;
}
