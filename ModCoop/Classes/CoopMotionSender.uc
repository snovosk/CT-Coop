// Per-guest, bounded unreliable snapshot stream. Only client-known pawns can
// subscribe; requests carry no coordinates and cannot move an actor.
class CoopMotionSender extends CoopActorCache transient dependson(CoopMotionState);

struct Interest
{
    var Pawn P;
    var float Expires, Sent, MovingUntil, ObservedAt, Score, VelocityInterval;
    var vector Observed, MeasuredVelocity, SecantVelocity;
    var rotator ObservedFacing;
    var bool bMeasured;
    var float Due, Interval;
    var float CombatUntil, AnimationTime;
    var byte ObservedIdle;
    var bool ObservedCrouch;
    var Weapon ObservedWeapon;
    var int ObservedFireCount, CombatLayerMask;
    var CoopMotionState.AnimPose Animation;
};
var array<Interest> Entries;
var CoopPlayer PC;
var float NextPulse;
var int Sequence, SentSnapshots, SentBatches, MaxPulseSnapshots;
var int LateSnapshots, ReportSnapshots, DeferredFrames;
var float MaxSendGap, NextReport, SnapshotCredit, CreditTime;
var int FastSnapshots;
var float MaxFastGap;

static function bool CombatSequence(name Sequence)
{
    local string S;
    S=Caps(string(Sequence));
    return InStr(S,"FIRE")>=0 || InStr(S,"SHOOT")>=0 || InStr(S,"RELOAD")>=0 ||
        InStr(S,"IMPACT")>=0 || InStr(S,"PAIN")>=0 || InStr(S,"HIT")>=0 ||
        InStr(S,"THROW")>=0 || InStr(S,"ATTACK")>=0 || InStr(S,"MELEE")>=0;
}

static function float UpdateInterval(float Distance,bool Moving,bool Combat,bool Fast)
{
    if(Distance>3500)
    {
        if(Moving || (Fast && Combat)) return 0.08;
        return 0.16;
    }
    if(Moving || (Fast && Combat))
    {
        if(Fast) return 0.02;
        return 0.04;
    }
    return 0.08;
}

// Read the pose once per completed frame and reuse it if this pawn is sent.
// Breathing/idle loops alone never promote a stationary actor to combat rate.
function ObserveCombat(int Index,float Now)
{
    local Pawn P;
    local CoopMotionState.AnimPose A;
    local int j,Bit;
    local bool Active;
    P=Entries[Index].P;
    Active=(P.Controller!=None && (P.Controller.bFire!=0 || P.Controller.bAltFire!=0)) ||
        (P.LastHitLocalTime>0 && Now-P.LastHitLocalTime<0.35) ||
        P.bIsCrouched!=Entries[Index].ObservedCrouch || P.CurrentIdleState!=Entries[Index].ObservedIdle;
    if(P.Weapon!=None)
    {
        if(P.Weapon==Entries[Index].ObservedWeapon && P.Weapon.FireCount!=Entries[Index].ObservedFireCount) Active=true;
        Entries[Index].ObservedFireCount=P.Weapon.FireCount;
        if(P.Weapon.IsInState('NormalFire') || P.Weapon.IsInState('Reloading')) Active=true;
    }
    Entries[Index].ObservedWeapon=P.Weapon;
    Entries[Index].ObservedCrouch=P.bIsCrouched; Entries[Index].ObservedIdle=P.CurrentIdleState;
    class'CoopNative'.static.ReadCombatPose(P,A);
    for(j=0;j<A.Count;++j)
    {
        Bit=1<<j;
        if(j>=Entries[Index].Animation.Count || A.Layers[j].Sequence!=Entries[Index].Animation.Layers[j].Sequence)
        {
            Entries[Index].CombatLayerMask=Entries[Index].CombatLayerMask & ~Bit;
            if(CombatSequence(A.Layers[j].Sequence)) Entries[Index].CombatLayerMask=Entries[Index].CombatLayerMask | Bit;
        }
        if((Entries[Index].CombatLayerMask & Bit)!=0 && A.Layers[j].Weight>0 && A.Layers[j].Speed>0 &&
           ((A.Layers[j].Flags & 1)!=0 || A.Layers[j].Phase<A.Layers[j].EndPhase-0.001)) Active=true;
    }
    Entries[Index].Animation=A; Entries[Index].AnimationTime=Now;
    if(Active) Entries[Index].CombatUntil=Now+0.35;
}

static function vector EndpointVelocity(vector Recent, vector Previous, float DT, float PreviousDT)
{
    local vector Acceleration,Result;
    if(DT<0.008 || DT>0.25 || PreviousDT<0.008 || PreviousDT>0.25 || VSize(Recent)<0.01 ||
       (VSize(Previous)>1 && (Normal(Recent) dot Normal(Previous))<0.5)) return Recent;
    Acceleration=(Recent-Previous)/((DT+PreviousDT)*0.5);
    if(VSize(Acceleration)>1500) Acceleration=Normal(Acceleration)*1500;
    Result=Recent+Acceleration*(DT*0.5);
    if(VSize(Result)>1000) Result=Normal(Result)*1000;
    return Result;
}

function bool Eligible(Pawn P)
{
    local Actor Viewer;
    if(PC==None || P==None || P.bDeleteMe || P.Level!=PC.Level || P==PC.Pawn ||
       P.Health<=0 || P.bHidden || P.RemoteRole<ROLE_SimulatedProxy || P.DrawType!=DT_Mesh ||
       (P.Base!=None && !P.Base.bStatic && !P.Base.IsA('LevelInfo'))) return false;
    Viewer=PC.Pawn;
    if(Viewer==None) Viewer=PC.ViewTarget;
    return Viewer!=None && VSize(P.Location-Viewer.Location)<6000;
}

function Subscribe(Pawn P)
{
    local int i;
    if(!Eligible(P)) return;
    for(i=0;i<Entries.Length;++i) if(Entries[i].P==P) break;
    if(i==Entries.Length)
    {
        if(i>=64) return;
        Entries.Length=i+1; Entries[i].P=P;
        Entries[i].Observed=P.Location; Entries[i].MovingUntil=PC.Level.TimeSeconds+0.5;
        Entries[i].ObservedAt=PC.Level.TimeSeconds; Entries[i].ObservedFacing=P.Rotation;
        Entries[i].Sent=-1;
        Entries[i].Due=PC.Level.TimeSeconds;
    }
    Entries[i].Expires=PC.Level.TimeSeconds+3;
}

function CoopMotionState.MotionPose PoseFor(Pawn P)
{
    local CoopMotionState.MotionPose S;
    local int i;
    if(P==None) return S;
    S.Position=P.Location; S.Facing=P.Rotation; S.IdleState=P.CurrentIdleState; S.PhysicsMode=P.Physics;
    if(P.bIsWalking) S.Flags=S.Flags|1;
    if(P.bIsCrouched) S.Flags=S.Flags|2;
    if(P.bPhysicsAnimUpdate && (P.Controller==None || !P.Controller.bControlAnimations)) S.Flags=S.Flags|4;
    // A scripted position change can intentionally retain a standing pose.
    // Do not invent walking on the client while the host's damage mesh is idle.
    if(VSize(P.Velocity)>1 || VSize(P.Acceleration)>0.01) S.Flags=S.Flags|16;
    for(i=0;i<Entries.Length;++i)
        if(Entries[i].P==P)
        {
            S.Velocity=Entries[i].MeasuredVelocity;
            if(Entries[i].bMeasured) S.Flags=S.Flags|8;
            break;
        }
    if(i<Entries.Length && Entries[i].AnimationTime==PC.Level.TimeSeconds && class'CoopConfig'.default.bFastCombatUpdates)
        S.Animation=Entries[i].Animation;
    else class'CoopNative'.static.ReadCombatPose(P,S.Animation);
    return S;
}

function Update(float Now)
{
    local int i,j,Best,n,Group,Total;
    local float Interval,BestScore,Distance,DT,PreviousDT,CreditLimit;
    local vector Eye,Forward,PreviousVelocity;
    local bool WasMeasured;
    local Pawn Batch[2];
    local Actor Viewer;
    if(PC==None || PC.bDeleteMe) {Entries.Length=0;return;}
    // Lifetime maintenance must run even when the stream cannot send. Actor
    // storage makes already-freed targets None before this pass examines them.
    for(i=Entries.Length-1;i>=0;--i)
        if(Entries[i].Expires<Now || !Eligible(Entries[i].P)) Entries.Remove(i,1);
    Interval=PC.RequestedCoopNetRate;
    if(Interval<=0) Interval=class'CoopConfig'.default.NetClientRate;
    // Reserve at least half the configured connection budget for native actor
    // replication and reliable gameplay. A smoother must not starve AI/damage.
    CreditLimit=2048;
    if(class'CoopConfig'.default.bFastCombatUpdates) CreditLimit=4096;
    if(CreditTime==0 || Now<CreditTime) SnapshotCredit=512;
    else SnapshotCredit=FMin(CreditLimit,SnapshotCredit+FMax(0,Now-CreditTime)*Interval*0.5);
    CreditTime=Now;
    if(SnapshotCredit<384) { ++DeferredFrames; return; }
    // Check the engine's real connection budget as well as our own limit.
    // IsNetReady can reject unreliable RPCs when frame credit is exhausted.
    if(!class'CoopNative'.static.CanSendCombatFrame(PC)) { ++DeferredFrames; return; }
    Viewer=PC.Pawn; if(Viewer==None) Viewer=PC.ViewTarget;
    if(Viewer==None) return;
    Eye=Viewer.Location; Forward=vector(PC.Rotation);
    for(i=Entries.Length-1;i>=0;--i)
    {
        if(Entries[i].Expires<Now || !Eligible(Entries[i].P)) { Entries.Remove(i,1); continue; }
        DT=Now-Entries[i].ObservedAt;
        WasMeasured=Entries[i].bMeasured; PreviousDT=Entries[i].VelocityInterval;
        PreviousVelocity=Entries[i].SecantVelocity;
        Entries[i].bMeasured=DT>=0.008 && DT<=0.25;
        Entries[i].MeasuredVelocity=vect(0,0,0);
        if(Entries[i].bMeasured)
        {
            Entries[i].MeasuredVelocity=(Entries[i].P.Location-Entries[i].Observed)/DT;
            if(VSize(Entries[i].MeasuredVelocity)>1000) Entries[i].bMeasured=false;
        }
        // A positional difference measures velocity at the interval midpoint.
        // Hermite tangents belong at the endpoint; account for bounded local
        // acceleration without mixing future samples into an existing curve.
        Entries[i].SecantVelocity=Entries[i].MeasuredVelocity; Entries[i].VelocityInterval=DT;
        if(Entries[i].bMeasured && WasMeasured)
            Entries[i].MeasuredVelocity=EndpointVelocity(Entries[i].MeasuredVelocity,PreviousVelocity,DT,PreviousDT);
        if(VSize(Entries[i].P.Location-Entries[i].Observed)>0.25 || Entries[i].P.Rotation!=Entries[i].ObservedFacing)
            Entries[i].MovingUntil=Now+0.5;
        Entries[i].Observed=Entries[i].P.Location;
        Entries[i].ObservedAt=Now; Entries[i].ObservedFacing=Entries[i].P.Rotation;
        Distance=VSize(Entries[i].P.Location-Eye);
        if(class'CoopConfig'.default.bFastCombatUpdates) ObserveCombat(i,Now);
        Interval=UpdateInterval(Distance,Entries[i].MovingUntil>=Now,Entries[i].CombatUntil>=Now,
            class'CoopConfig'.default.bFastCombatUpdates);
        Entries[i].Score=0;
        // A pawn becoming active must not retain its old idle deadline.
        if(Interval<Entries[i].Interval) Entries[i].Due=FMin(Entries[i].Due,Now);
        Entries[i].Interval=Interval;
        if(Now+0.001>=Entries[i].Due)
        {
            Entries[i].Score=1+FMax(0,Now-Entries[i].Due)/Interval;
            if(Distance<2500 && (Entries[i].P.Location-Eye) dot Forward>0) Entries[i].Score+=0.25;
            // Age wins over view preference: offscreen actors cannot starve.
            if(Now-Entries[i].Due>=Interval*2) Entries[i].Score+=8;
        }
        Entries[i].Interval=Interval;
    }
    if(Sequence>=1073741823) Sequence=0;
    ++Sequence;
    // Small pairs fit the engine's bunch limit. Allow several when bandwidth
    // is available so a crowded scene does not fall to two pawns per frame.
    // Nearby active actors target 20 ms; true idle and distant actors stay
    // slower. Actual host frames and the unchanged connection budget bound it.
    for(Group=0;Group<8;++Group)
    {
        if(SnapshotCredit<384 || !class'CoopNative'.static.CanSendCombatFrame(PC))
        { ++DeferredFrames; break; }
        n=0;
        for(j=0;j<2;++j)
        {
            Best=-1; BestScore=0;
            for(i=0;i<Entries.Length;++i)
            {
                if(Entries[i].Score>BestScore) {Best=i; BestScore=Entries[i].Score;}
            }
            if(Best<0) break;
            Batch[n]=Entries[Best].P; ++n;
            if(Entries[Best].Sent>=0)
            {
                MaxSendGap=FMax(MaxSendGap,Now-Entries[Best].Sent);
                if(Entries[Best].Interval<0.03) MaxFastGap=FMax(MaxFastGap,Now-Entries[Best].Sent);
                if(Now-Entries[Best].Sent>Entries[Best].Interval*1.75) ++LateSnapshots;
            }
            ++ReportSnapshots;
            if(Entries[Best].Interval<0.03) ++FastSnapshots;
            Entries[Best].Sent=Now;
            // Keep a cadence tied to deadlines instead of accumulating a
            // frame's lateness after every send. Never send catch-up bursts.
            Entries[Best].Due+=Entries[Best].Interval;
            if(Entries[Best].Due<=Now) Entries[Best].Due=Now+Entries[Best].Interval;
            Entries[Best].Score=0;
        }
        if(n==0) break;
        if(n==1) Batch[1]=None;
        PC.SendCombatPair(Sequence,Now,Batch[0],Batch[1]);
        SnapshotCredit=FMax(0,SnapshotCredit-PC.LastCombatPacketBytes);
        SentSnapshots+=n; Total+=n; ++SentBatches;
    }
    MaxPulseSnapshots=Max(MaxPulseSnapshots,Total);
    if(NextReport==0) NextReport=Now+5;
    if(Now>=NextReport)
    {
        Log("CoopSendTiming: peer=" $ PC.PlayerReplicationInfo.PlayerName $ " entries=" $ Entries.Length $
            " sent=" $ ReportSnapshots $ " deferred=" $ DeferredFrames $ " late=" $ LateSnapshots $ " maxGapMs=" $ (MaxSendGap*1000) $
            " fast=" $ FastSnapshots $ " fastMaxGapMs=" $ (MaxFastGap*1000));
        NextReport=Now+5; ReportSnapshots=0; LateSnapshots=0; MaxSendGap=0; DeferredFrames=0;
        FastSnapshots=0; MaxFastGap=0;
    }
}
