// Client-only presentation history. Never changes a pawn's Location/Velocity,
// physics, collision, health or the server's firing path.
class CoopProxyTrack extends CoopActorCache transient;

// Faster streams must retain enough TIME for delayed playback and recovery.
// Capacity does not change playback delay; 64 holds >1s at 50Hz instead of
// overwriting the playhead after only 300ms with the former 16 samples.
const HISTORY_SIZE = 64;
const PRESENTATION_DELAY = 0.125;
var Pawn P;
var vector BasePrePivot, Positions[64], Correction, RenderPosition;
var float Times[64];
var int First, Count, Received, Resets, Underruns;
var bool bSavedNetNotify, bStarved;
var bool bRawReceiver;
var int LastSequence, IgnoredNotifications;

// Build 139's external property expression has an 8-bit size field. Access
// larger fixed histories through scalar helpers in diagnostics instead.
simulated function vector SamplePosition(int Index) { return Positions[Index%HISTORY_SIZE]; }
simulated function float SampleTime(int Index) { return Times[Index%HISTORY_SIZE]; }
simulated function SetTestSample(int Index,float Stamp,vector Position)
{
    if(Index<0 || Index>=HISTORY_SIZE) return;
    Positions[Index]=Position; Times[Index]=Stamp;
}

simulated function Init(Pawn InPawn, float Now)
{
    P=InPawn;
    BasePrePivot=P.PrePivot;
    bSavedNetNotify=P.bNetNotify;
    P.bNetNotify=true;
    bRawReceiver=class'CoopNative'.static.InstallProxyReceiver(P);
    if(!bRawReceiver) Log("ModCoop: Raw proxy receiver unavailable for " $ P.Class $ "; using previous buffer source",'Warning');
    ResetTrack(Now);
}

simulated function Restore()
{
    if(P!=None && !P.bDeleteMe)
    {
        P.PrePivot=BasePrePivot;
        P.bNetNotify=bSavedNetNotify;
    }
    P=None;
}

simulated event Destroyed()
{
    Restore();
    Super.Destroyed();
}

simulated function ResetTrack(float Now)
{
    ResetAt(Now,P.Location);
}

simulated function ResetAt(float Now, vector Position)
{
    First=0; Count=2;
    Positions[0]=Position; Positions[1]=Position;
    Times[0]=Now-PRESENTATION_DELAY; Times[1]=Now;
    Correction=vect(0,0,0);
    RenderPosition=Position;
    ApplyVisualPosition();
    bStarved=false;
}

// Arrival timestamps use one client clock. Interpolate only between received
// positions: animation-driven movement often supplies a zero Velocity.
simulated function vector PositionAt(float AtTime)
{
    local int j, A, B;
    local float Span;
    if(AtTime<=Times[First]) return Positions[First];
    for(j=1;j<Count;++j)
    {
        A=(First+j-1)%HISTORY_SIZE; B=(First+j)%HISTORY_SIZE;
        if(AtTime<=Times[B])
        {
            Span=Times[B]-Times[A];
            if(Span<=0.00001) return Positions[B];
            return Positions[A]+(Positions[B]-Positions[A])*FClamp((AtTime-Times[A])/Span,0,1);
        }
    }
    // Hold during a missing packet rather than extrapolating through walls.
    return Positions[(First+Count-1)%HISTORY_SIZE];
}

simulated function Receive(float Now, vector Position, vector Velocity, optional int Sequence)
{
    local int Last;
    local float Gap, Distance, TeleportLimit;
    local vector Previous;
    if(P==None || P.bDeleteMe) return;
    ++Received;
    LastSequence=Sequence;
    Last=(First+Count-1)%HISTORY_SIZE;
    Gap=Now-Times[Last];
    Distance=VSize(Position-Positions[Last]);
    // Do not confuse an ordinary 150-300 unit network correction with a
    // teleport. Allow fast movers more distance in proportion to elapsed time.
    // A quiet stationary pawn may not replicate for seconds. That alone is
    // not a teleport: keep an anchor so its first step is still interpolated.
    TeleportLimit=FMax(1500, VSize(Velocity)*FMax(Gap,0)*2+300);
    if(Gap<0 || Distance>TeleportLimit)
    {
        ++Resets;
        ResetAt(Now,Position);
        return;
    }
    if(Gap>0.75)
    {
        Positions[0]=Positions[Last]; Times[0]=Now-PRESENTATION_DELAY;
        First=0; Count=1; Last=0; Gap=PRESENTATION_DELAY;
    }
    Previous=PositionAt(Now-PRESENTATION_DELAY);
    if(Gap<0.00001)
        Positions[Last]=Position;
    else
    {
        if(Count==HISTORY_SIZE) First=(First+1)%HISTORY_SIZE;
        else ++Count;
        Last=(First+Count-1)%HISTORY_SIZE;
        Positions[Last]=Position; Times[Last]=Now;
    }
    // A late packet must not snap a mesh that was holding at the end of the
    // buffer. Preserve its position and gently remove the residual correction.
    if(bStarved)
    {
        Correction+=Previous-PositionAt(Now-PRESENTATION_DELAY);
        bStarved=false;
        ++Underruns;
    }
}

simulated function Draw(float Now, float DeltaTime)
{
    if(P==None || P.bDeleteMe) return;
    // Exponential decay has the same result at any frame rate; a 125 ms frame
    // retains 25% instead of discarding the entire correction as before.
    Correction*=0.25 ** FClamp(DeltaTime/0.125,0,32);
    RenderPosition=PositionAt(Now-PRESENTATION_DELAY)+Correction;
    ApplyVisualPosition();
    bStarved=Now-PRESENTATION_DELAY>Times[(First+Count-1)%HISTORY_SIZE];
}

simulated function ApplyVisualPosition()
{
    if(P!=None && !P.bDeleteMe)
        P.PrePivot=BasePrePivot+RenderPosition-P.Location;
}
