// Present facing and locomotion at the same host time as buffered position.
// Physical pawn fields are restored before gameplay resumes after rendering.
class CoopPresentationTrack extends CoopExtrapolationTrack transient dependson(CoopMotionState);
// Flags: 1 walking, 2 crouched, 4 native locomotion, 8 measured velocity,
// 16 host has movement-animation input.
var CoopMotionState.MotionPose Poses[64], IncomingPose, DisplayPose;
var rotator RenderFacing, SavedFacing, FacingError;
var bool bPoseReady, bRenderApplied, bOwnLocomotion, bSavedPhysicsAnim;
var bool bDisablePrediction, bLinearCurves;
var bool bNativeAnimationUnavailable;
const WALKING_PHYSICS=1;
const FLYING_PHYSICS=4;
const SIMULATED_PROXY=2;
// Match the position stream's outage threshold. A short packet hole must not
// switch facing/animation back to a different timeline while position holds.
const POSE_TIMEOUT=0.75;
var float LastPoseArrival, LastAnimationTime;
var int PoseSamples, AnimationFrames, CombatFrames;
var MeshInstance VisualCombatMesh, SavedCombatMesh;
var bool bCombatApplied;
var bool DiagnosticStale,DiagnosticTornOff;

// Edge events only. Animation ownership events remain in the bounded native
// history; packet interruptions also get a text line for host/client comparison.
simulated function TraceMotionEvents(float Now)
{
    local bool Stale;
    if(P==None) return;
    Stale=bPoseReady && bStream && Now-LastPoseArrival>POSE_TIMEOUT;
    if(Stale!=DiagnosticStale)
    {
        DiagnosticStale=Stale;
        Log("CoopMotionEvent: stale=" $ Stale $ " actor=" $ P $ " class=" $ P.Class $
            " time=" $ Now $ " poseAge=" $ (Now-LastPoseArrival) $ " sequence=" $ StreamSequence $
            " ownsLocomotion=" $ bOwnLocomotion);
    }
    if(P.bTearOff!=DiagnosticTornOff)
    {
        DiagnosticTornOff=P.bTearOff;
        Log("CoopMotionEvent: tearOff=" $ P.bTearOff $ " actor=" $ P $ " class=" $ P.Class $
            " time=" $ Now $ " healthLevel=" $ P.HealthLevel $ " ownsLocomotion=" $ bOwnLocomotion);
    }
}

simulated function CoopMotionState.AnimPose AnimationAt(float AtTime)
{
    local int j,A,B;
    local CoopMotionState.AnimPose S;
    if(Count==0) return S;
    if(AtTime<=Times[First]) return Poses[First].Animation;
    for(j=1;j<Count;++j)
    {
        A=(First+j-1)%HISTORY_SIZE; B=(First+j)%HISTORY_SIZE;
        if(AtTime>Times[B]) continue;
        return class'CoopCombatAnimation'.static.Between(Poses[A].Animation,Poses[B].Animation,
            AtTime-Times[A],Times[B]-Times[A]);
    }
    A=(First+Count-1)%HISTORY_SIZE;
    return class'CoopCombatAnimation'.static.Advance(Poses[A].Animation,FClamp(AtTime-Times[A],0,0.1));
}

simulated function BeginStream(float Now, float Stamp, vector Position, int Sequence)
{
    Super.BeginStream(Now,Stamp,Position,Sequence);
    Poses[0]=IncomingPose; Poses[1]=IncomingPose;
    Poses[0].Flags=Poses[0].Flags&247; // Synthetic warm-up has no measured tangent.
    DisplayPose=IncomingPose; RenderFacing=IncomingPose.Facing;
    FacingError=rot(0,0,0);
}

simulated function SnapshotAdded(int Index) { Poses[Index]=IncomingPose; }

simulated function bool HasLateMotion(vector NextPosition)
{
    local int Last,Previous;
    if(Super.HasLateMotion(NextPosition)) return true;
    if(!bPoseReady || Count<2) return false;
    Last=(First+Count-1)%HISTORY_SIZE; Previous=(First+Count-2)%HISTORY_SIZE;
    return IncomingPose.Facing!=Poses[Last].Facing || Poses[Last].Facing!=Poses[Previous].Facing ||
        IncomingPose.IdleState!=Poses[Last].IdleState || (IncomingPose.Flags&23)!=(Poses[Last].Flags&23);
}

simulated function float StationaryTarget(float Goal)
{
    local float Target;
    local int j,Index;
    local rotator Facing;
    // A stationary pawn can still be firing, flinching or changing stance.
    // Do not skip through its animation timeline as if it were a static prop.
    if(DisplayPose.Animation.Count>0) return PlayTime;
    Target=Super.StationaryTarget(Goal);
    if(!bPoseReady || Target<=PlayTime) return Target;
    Facing=FacingAt(PlayTime);
    for(j=0;j<Count;++j)
    {
        Index=(First+j)%HISTORY_SIZE;
        if(Times[Index]<=PlayTime) continue;
        // Include the endpoint of the segment containing the target.
        if(AngleDelta(Facing.Pitch,Poses[Index].Facing.Pitch)!=0 ||
           AngleDelta(Facing.Yaw,Poses[Index].Facing.Yaw)!=0 ||
           AngleDelta(Facing.Roll,Poses[Index].Facing.Roll)!=0 ||
           Poses[Index].IdleState!=DisplayPose.IdleState ||
           (Poses[Index].Flags&23)!=(DisplayPose.Flags&23)) return PlayTime;
        if(Times[Index]>=Target) break;
    }
    return Target;
}

simulated function UpdateEstimate()
{
    Super.UpdateEstimate();
    if(bDisablePrediction) bCanPredict=false;
}

static function int AngleDelta(int A, int B)
{
    return ((B-A+32768)&65535)-32768;
}

simulated function rotator FacingAt(float AtTime)
{
    local int j,A,B;
    local float T;
    local rotator R;
    if(AtTime<=Times[First]) return Poses[First].Facing;
    for(j=1;j<Count;++j)
    {
        A=(First+j-1)%HISTORY_SIZE; B=(First+j)%HISTORY_SIZE;
        if(AtTime>Times[B]) continue;
        T=FClamp((AtTime-Times[A])/FMax(0.00001,Times[B]-Times[A]),0,1);
        R.Pitch=Poses[A].Facing.Pitch+int(AngleDelta(Poses[A].Facing.Pitch,Poses[B].Facing.Pitch)*T);
        R.Yaw=Poses[A].Facing.Yaw+int(AngleDelta(Poses[A].Facing.Yaw,Poses[B].Facing.Yaw)*T);
        R.Roll=Poses[A].Facing.Roll+int(AngleDelta(Poses[A].Facing.Roll,Poses[B].Facing.Roll)*T);
        return R;
    }
    // Never guess a future turn during packet loss.
    return Poses[(First+Count-1)%HISTORY_SIZE].Facing;
}

simulated function bool ReceivePose(float Now, float Stamp, CoopMotionState.MotionPose Pose, int Sequence, CoopMotionClock NewClock)
{
    local int OldResets,OldEpoch,Last;
    local bool WasAtEnd;
    local rotator Before,After;
    Before=FacingAt(PlayTime);
    WasAtEnd=bPoseReady && PlayTime>=Times[(First+Count-1)%HISTORY_SIZE];
    OldResets=Resets; OldEpoch=ClockEpoch;
    IncomingPose=Pose;
    if(!ReceiveSnapshot(Now,Stamp,Pose.Position,Sequence,NewClock)) return false;
    Last=(First+Count-1)%HISTORY_SIZE; Poses[Last]=Pose;
    if(WasAtEnd && Resets==OldResets && ClockEpoch==OldEpoch)
    {
        After=FacingAt(PlayTime);
        FacingError.Pitch=AngleDelta(0,FacingError.Pitch+AngleDelta(After.Pitch,Before.Pitch));
        FacingError.Yaw=AngleDelta(0,FacingError.Yaw+AngleDelta(After.Yaw,Before.Yaw));
        FacingError.Roll=AngleDelta(0,FacingError.Roll+AngleDelta(After.Roll,Before.Roll));
    }
    bPoseReady=true; LastPoseArrival=Now; ++PoseSamples;
    TraceMotionEvents(Now);
    return true;
}

// Monotone Hermite component: endpoint velocities are limited so the curve
// cannot leave the endpoint interval, including stops and direction reversals.
static function float CurveComponent(float A, float B, float VA, float VB, float Span, float T)
{
    local float D,M0,M1,Q,Scale,T2,T3;
    D=B-A;
    if(Abs(D)<0.01) return A+D*T;
    M0=VA*Span; M1=VB*Span;
    if(M0*D<=0) M0=0;
    if(M1*D<=0) M1=0;
    Q=(M0/D)*(M0/D)+(M1/D)*(M1/D);
    if(Q>9) { Scale=3/Sqrt(Q); M0*=Scale; M1*=Scale; }
    T2=T*T; T3=T2*T;
    return FClamp((2*T3-3*T2+1)*A+(T3-2*T2+T)*M0+(-2*T3+3*T2)*B+(T3-T2)*M1,FMin(A,B),FMax(A,B));
}

simulated function vector PositionAt(float AtTime)
{
    local int j,A,B;
    local float Span,T;
    local vector D,R,Linear;
    if(!bPoseReady || bLinearCurves || AtTime<=Times[First] ||
       AtTime>=Times[(First+Count-1)%HISTORY_SIZE]) return Super.PositionAt(AtTime);
    for(j=1;j<Count;++j)
    {
        A=(First+j-1)%HISTORY_SIZE; B=(First+j)%HISTORY_SIZE;
        if(AtTime>Times[B]) continue;
        Span=Times[B]-Times[A];
        if(Span<0.008 || Span>0.25 || (Poses[A].Flags&8)==0 || (Poses[B].Flags&8)==0 ||
           Poses[A].PhysicsMode!=Poses[B].PhysicsMode) return Super.PositionAt(AtTime);
        T=FClamp((AtTime-Times[A])/Span,0,1); D=Positions[B]-Positions[A];
        Linear=Positions[A]+D*T;
        if(VSize(D)<0.01) return Linear;
        // Sharp corners keep straight interpolation rather than cut a corner.
        if((VSize(Poses[A].Velocity)>1 && (Normal(Poses[A].Velocity) dot Normal(D))<0.8) ||
           (VSize(Poses[B].Velocity)>1 && (Normal(Poses[B].Velocity) dot Normal(D))<0.8)) return Linear;
        R.X=CurveComponent(Positions[A].X,Positions[B].X,Poses[A].Velocity.X,Poses[B].Velocity.X,Span,T);
        R.Y=CurveComponent(Positions[A].Y,Positions[B].Y,Poses[A].Velocity.Y,Poses[B].Velocity.Y,Span,T);
        R.Z=CurveComponent(Positions[A].Z,Positions[B].Z,Poses[A].Velocity.Z,Poses[B].Velocity.Z,Span,T);
        if(VSize(R-Linear)>24) return Linear;
        return R;
    }
    return Super.PositionAt(AtTime);
}

simulated function int DecayAngle(int Angle, float DT)
{
    local float Remove;
    Remove=FMin(Abs(Angle)*(1-0.5 ** (DT/0.06)),131072*DT);
    if(Angle<0) return Min(0,Angle+Max(1,int(Remove)));
    if(Angle>0) return Max(0,Angle-Max(1,int(Remove)));
    return 0;
}

simulated function Draw(float Now, float DeltaTime)
{
    local int j,Index;
    local float DT;
    TraceMotionEvents(Now);
    EndRender();
    Super.Draw(Now,DeltaTime);
    if(!bPoseReady || !bStream || Now-LastPoseArrival>POSE_TIMEOUT) { ReleaseLocomotion(); return; }
    Index=First;
    for(j=1;j<Count;++j)
    {
        if(Times[(First+j)%HISTORY_SIZE]>PlayTime) break;
        Index=(First+j)%HISTORY_SIZE;
    }
    DisplayPose=Poses[Index];
    DisplayPose.Animation=AnimationAt(PlayTime);
    RenderFacing=FacingAt(PlayTime);
    DT=FClamp(DeltaTime,0,0.1);
    FacingError.Pitch=DecayAngle(FacingError.Pitch,DT);
    FacingError.Yaw=DecayAngle(FacingError.Yaw,DT);
    FacingError.Roll=DecayAngle(FacingError.Roll,DT);
    RenderFacing+=FacingError;
    // Derivative of the displayed path, excluding correction offsets: a
    // network correction must not make a stationary enemy run in place.
    DisplayPose.Velocity=(PositionAt(PlayTime+0.005)-PositionAt(PlayTime-0.005))*100*PlayRate;
    if(VSize(DisplayPose.Velocity)>1000) DisplayPose.Velocity=Normal(DisplayPose.Velocity)*1000;
    if(!CanDriveLocomotion()) ReleaseLocomotion();
}

simulated function bool CanDriveLocomotion()
{
    return P!=None && !P.bDeleteMe && P.Health>0 && !P.bIncapacitated && P.Controller==None &&
        (DisplayPose.Flags&4)!=0 &&
        (P.Physics==WALKING_PHYSICS || P.Physics==FLYING_PHYSICS) &&
        (DisplayPose.PhysicsMode==WALKING_PHYSICS || DisplayPose.PhysicsMode==FLYING_PHYSICS);
}

simulated function ReleaseLocomotion()
{
    if(bOwnLocomotion)
    if(bOwnLocomotion && P!=None && !P.bDeleteMe)
    {
        P.bPhysicsAnimUpdate=bSavedPhysicsAnim;
    }
    bOwnLocomotion=false;
}

simulated function vector LocomotionVelocity()
{
    if((DisplayPose.Flags&16)==0) return vect(0,0,0);
    return DisplayPose.Velocity;
}

simulated function BeginRender(float Now, float DT)
{
    EndRender();
    if(!bPoseReady || !bStream || Now-LastPoseArrival>POSE_TIMEOUT || P==None || P.bDeleteMe ||
       P.Health<=0 || P.bHidden || P.Role!=SIMULATED_PROXY) return;
    SavedFacing=P.Rotation;
    bRenderApplied=class'CoopNative'.static.SetProxyRenderFacing(P,RenderFacing);
    if(!bRenderApplied) { ReleaseLocomotion(); return; }
    if(DisplayPose.Animation.Count>0 && P.Controller==None)
    {
        ReleaseLocomotion();
        ApplyVisualPosition();
        SavedCombatMesh=P.MeshInstance;
        VisualCombatMesh=class'CoopNative'.static.BeginCombatPose(P,VisualCombatMesh,DisplayPose.Animation,DT);
        bCombatApplied=VisualCombatMesh!=None && P.MeshInstance==VisualCombatMesh;
        if(bCombatApplied) { ++AnimationFrames; ++CombatFrames; return; }
        SavedCombatMesh=None;
    }
    // Take ownership only after the render callback actually runs. If the
    // native hook is unavailable, the engine keeps its normal animation path.
    if(CanDriveLocomotion() && !bOwnLocomotion && !bNativeAnimationUnavailable && P.bPhysicsAnimUpdate)
    {
        bSavedPhysicsAnim=P.bPhysicsAnimUpdate;
        bOwnLocomotion=true;
        P.bPhysicsAnimUpdate=false;
    }
    ApplyVisualPosition(); // Bottom alignment uses the displayed orientation.
    if(bOwnLocomotion && CanDriveLocomotion() && LastAnimationTime!=Now)
    {
        if(class'CoopNative'.static.UpdateProxyLocomotion(P,LocomotionVelocity(),DisplayPose.IdleState,
            DisplayPose.Flags,FClamp(DT,0,0.1))) ++AnimationFrames;
        else { bNativeAnimationUnavailable=true; ReleaseLocomotion(); }
        LastAnimationTime=Now;
    }
}

simulated function EndRender()
{
    if(bCombatApplied) class'CoopNative'.static.EndCombatPose(P,SavedCombatMesh,VisualCombatMesh);
    bCombatApplied=false; SavedCombatMesh=None;
    if(bRenderApplied && P!=None && !P.bDeleteMe)
        class'CoopNative'.static.SetProxyRenderFacing(P,SavedFacing);
    bRenderApplied=false;
    if(P!=None && !P.bDeleteMe) ApplyVisualPosition();
}

simulated function Restore()
{
    // A death can tear the pawn off and prune this track before Draw runs.
    // Observe the final replicated state while P still identifies that pawn.
    if(P!=None && !P.bDeleteMe && P.Level!=None)
        TraceMotionEvents(P.Level.TimeSeconds);
    EndRender(); ReleaseLocomotion();
    VisualCombatMesh=None;
    Super.Restore();
}
