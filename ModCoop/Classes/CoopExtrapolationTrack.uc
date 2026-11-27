// Buffered interpolation with a short, presentation-only dead-reckoning tail.
// Derive motion from host positions: scripted movement may report Velocity=0.
class CoopExtrapolationTrack extends CoopMeshSnapshotTrack transient;

var vector PredictedVelocity, PredictedAcceleration;
var bool bCanPredict;
var int RealSamples, PredictionFrames, PredictionCorrections;
var float PredictionSeconds, MaxPredictionError, MaxCorrection, LastPrediction;

simulated function BeginStream(float Now, float Stamp, vector Position, int Sequence)
{
    Super.BeginStream(Now,Stamp,Position,Sequence);
    RealSamples=1; bCanPredict=false;
    PredictedVelocity=vect(0,0,0); PredictedAcceleration=vect(0,0,0);
    LastPrediction=0;
}

simulated function UpdateEstimate()
{
    local int A,B,C;
    local float Dt,PreviousDt,Speed;
    local vector RecentVelocity,PreviousVelocity;
    bCanPredict=false;
    PredictedVelocity=vect(0,0,0); PredictedAcceleration=vect(0,0,0);
    // Never derive acceleration from BeginStream's synthetic warm-up anchor.
    if(RealSamples<3 || Count<3) return;
    C=(First+Count-1)%HISTORY_SIZE; B=(First+Count-2)%HISTORY_SIZE;
    A=(First+Count-3)%HISTORY_SIZE;
    Dt=Times[C]-Times[B]; PreviousDt=Times[B]-Times[A];
    if(Dt<0.008 || Dt>0.25 || PreviousDt<0.008 || PreviousDt>0.25) return;
    if(VSize(Positions[C]-Positions[B])<0.01) return; // confirmed stop
    RecentVelocity=(Positions[C]-Positions[B])/Dt;
    PreviousVelocity=(Positions[B]-Positions[A])/PreviousDt;
    Speed=VSize(RecentVelocity);
    if(Speed>1000) return; // discontinuous/scripted jump: wait for real samples
    // An observed reversal is unreliable evidence for another future turn.
    if(VSize(PreviousVelocity)>1 && (Normal(RecentVelocity) dot Normal(PreviousVelocity))<0.5) return;
    PredictedVelocity=RecentVelocity;
    if(VSize(PreviousVelocity)>1)
    {
        PredictedAcceleration=(RecentVelocity-PreviousVelocity)/((Dt+PreviousDt)*0.5);
        if(VSize(PredictedAcceleration)>1500)
            PredictedAcceleration=Normal(PredictedAcceleration)*1500;
        // A secant measures velocity at the interval midpoint, not its end.
        PredictedVelocity+=PredictedAcceleration*(Dt*0.5);
        if(VSize(PredictedVelocity)>1000) PredictedVelocity=Normal(PredictedVelocity)*1000;
    }
    bCanPredict=true;
}

simulated function vector PositionAt(float AtTime)
{
    local int Last;
    local float Ahead;
    local vector Offset;
    Last=(First+Count-1)%HISTORY_SIZE;
    if(!bStream || AtTime<=Times[Last]) return Super.PositionAt(AtTime);
    if(!bCanPredict) return Positions[Last];
    Ahead=FClamp(AtTime-Times[Last],0,0.10);
    Offset=PredictedVelocity*Ahead+PredictedAcceleration*(0.5*Ahead*Ahead);
    if(VSize(Offset)>80) Offset=Normal(Offset)*80;
    return Positions[Last]+Offset;
}

simulated function bool ReceiveSnapshot(float Now, float Stamp, vector Position, int Sequence, CoopMotionClock NewClock)
{
    local vector Before,After;
    local bool WasPredicting;
    local int OldResets,OldEpoch;
    Before=PositionAt(PlayTime);
    WasPredicting=bStream && PlayTime>Times[(First+Count-1)%HISTORY_SIZE];
    OldResets=Resets; OldEpoch=ClockEpoch;
    if(!Super.ReceiveSnapshot(Now,Stamp,Position,Sequence,NewClock)) return false;
    // BeginStream owns initialization; genuine teleports must not be blended.
    if(Resets!=OldResets || ClockEpoch!=OldEpoch || RealSamples==1 && Count==2) return true;
    ++RealSamples; UpdateEstimate();
    if(WasPredicting)
    {
        After=PositionAt(PlayTime);
        // Keep the exact previous displayed position at packet arrival. Only
        // Draw removes this residual; never move the collision pawn to match.
        Correction+=Before-After;
        MaxPredictionError=FMax(MaxPredictionError,VSize(Before-After));
        MaxCorrection=FMax(MaxCorrection,VSize(Correction));
        ++PredictionCorrections;
    }
    return true;
}

simulated function Draw(float Now, float DeltaTime)
{
    local int Last;
    local float Goal,WantedRate,Room,Advance,Step,StationaryTime,Horizon,Remove;
    if(!bStream || Clock==None) { Super.Draw(Now,DeltaTime); return; }
    if(P==None || P.bDeleteMe) return;
    Last=(First+Count-1)%HISTORY_SIZE;
    UpdateBufferDelay(Now,FClamp(DeltaTime,0,0.10));
    Goal=Clock.Estimate(Now)-Delay;
    Step=FClamp(DeltaTime,0,0.10);
    StationaryTime=StationaryTarget(Goal-Step);
    if(StationaryTime>PlayTime+0.001)
    {
        StationarySecondsSkipped+=StationaryTime-PlayTime;
        ++StationaryAdvances; PlayTime=StationaryTime; PlayRate=1;
    }
    if(bCanPredict) Horizon=0.10;
    Room=FMax(0,Times[Last]+Horizon-PlayTime);
    WantedRate=FClamp(1+(Goal-PlayTime)*2,0.90,1.10);
    WantedRate=FMin(WantedRate,Sqrt(24*FMax(0,Room-0.005)));
    PlayRate+=FClamp(WantedRate-PlayRate,-Step*12,Step*2);
    Advance=FMin(Room,Step*PlayRate);
    if(Step>0) PlayRate=Advance/Step;
    PlayTime+=Advance;
    if(PlayTime<Times[First]) { PlayTime=Times[First]; ++Resets; }
    bStarved=PlayTime>=Times[Last];
    LastPrediction=FClamp(PlayTime-Times[Last],0,Horizon);
    if(LastPrediction>0) {++PredictionFrames; PredictionSeconds+=Step;}
    // Frame-rate independent decay for small residuals, capped at 300 units/s
    // for larger corrections. No one-frame discard of a correction offset.
    Remove=FMin(VSize(Correction)*(1-0.5 ** (Step/0.06)),300*Step);
    if(VSize(Correction)>0.0001) Correction-=Normal(Correction)*Remove;
    RenderPosition=PositionAt(PlayTime)+Correction;
    LastDrawStamp=PlayTime; MaxRate=FMax(MaxRate,PlayRate);
    ApplyVisualPosition();
}
