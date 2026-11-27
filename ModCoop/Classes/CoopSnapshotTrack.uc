// Timestamped presentation only. Native physics and weapon collision are untouched.
class CoopSnapshotTrack extends CoopProxyTrack transient;

var CoopMotionClock Clock;
var bool bStream;
var float LastArrival, PlayTime, PlayRate, Delay, MeanInterval, NextInterest;
var int StreamSequence, StreamReceived, Rejected, ClockEpoch, Recoveries;
var float LastDrawStamp, MaxRate;
var int StationaryAdvances;
var float StationarySecondsSkipped;
var transient CoopMotionBuffer ArrivalBuffer;
var float LastDrawTime;

simulated function BeginStream(float Now, float Stamp, vector Position, int Sequence)
{
    First=0; Count=2;
    // Preserve the currently drawn position while the new timeline warms up.
    Positions[0]=RenderPosition; Positions[1]=Position;
    Times[0]=Stamp-0.125; Times[1]=Stamp;
    PlayTime=Times[0]; PlayRate=1; Delay=0.125; MeanInterval=0.04;
    Correction=vect(0,0,0); bStarved=false; bStream=true;
    LastArrival=Now; StreamSequence=Sequence; ClockEpoch=Clock.Epoch;
    if(ArrivalBuffer==None) ArrivalBuffer=new class'CoopMotionBuffer';
    ArrivalBuffer.Reset(Now);
}

simulated function bool ReceiveSnapshot(float Now, float Stamp, vector Position, int Sequence, CoopMotionClock NewClock)
{
    local int Last;
    local float Gap, Distance;
    Clock=NewClock;
    if(P==None || P.bDeleteMe || Clock==None || !Clock.bReady) return false;
    if(!bStream || ClockEpoch!=Clock.Epoch)
    {
        BeginStream(Now,Stamp,Position,Sequence);
        ++StreamReceived; ++Received;
        return true;
    }
    Last=(First+Count-1)%HISTORY_SIZE;
    Gap=Stamp-Times[Last]; Distance=VSize(Position-Positions[Last]);
    if(Gap<=0 || (Sequence<=StreamSequence && !(StreamSequence>1000000000 && Sequence<1000)))
    { ++Rejected; return false; }
    // Genuine teleports and a long outage explicitly resynchronize. Ordinary
    // packet gaps never become an exponentially decaying positional catch-up.
    if(Distance>1500 || Gap>0.75)
    {
        ++Resets; RenderPosition=Position;
        BeginStream(Now,Stamp,Position,Sequence); ApplyVisualPosition();
        ++StreamReceived; ++Received;
        return true;
    }
    // Idle anchors are real samples too. Match the buffer to their cadence,
    // rather than continuing to assume the earlier 40 ms moving interval.
    if(Gap<0.25) MeanInterval+=0.1*(Gap-MeanInterval);
    if(ArrivalBuffer!=None) ArrivalBuffer.Observe(Now,bStarved && HasLateMotion(Position),Now-LastDrawTime<0.1);
    if(Count==HISTORY_SIZE) First=(First+1)%HISTORY_SIZE;
    else ++Count;
    Last=(First+Count-1)%HISTORY_SIZE;
    Positions[Last]=Position; Times[Last]=Stamp;
    SnapshotAdded(Last);
    if(bStarved) { ++Recoveries; ++Underruns; }
    LastArrival=Now; StreamSequence=Sequence;
    ++StreamReceived; ++Received;
    return true;
}

simulated function SnapshotAdded(int Index) {}

simulated function bool HasLateMotion(vector NextPosition)
{
    local int Last,Previous;
    if(Count<2) return false;
    Last=(First+Count-1)%HISTORY_SIZE; Previous=(First+Count-2)%HISTORY_SIZE;
    return VSize(NextPosition-Positions[Last])>0.05 || VSize(Positions[Last]-Positions[Previous])>0.05;
}

simulated function UpdateBufferDelay(float Now,float DT)
{
    local float Wanted,Increase;
    LastDrawTime=Now;
    Wanted=FClamp(MeanInterval*2+Clock.Jitter*3,0.10,0.20);
    Increase=0.03;
    if(ArrivalBuffer!=None)
    {
        Wanted=ArrivalBuffer.Target(Now,DT,MeanInterval,Clock.Jitter);
        if(ArrivalBuffer.Pressure>0) Increase=0.06;
    }
    Delay+=FClamp(Wanted-Delay,-DT*0.02,DT*Increase);
}

simulated function Receive(float Now, vector Position, vector Velocity, optional int Sequence)
{
    if(bStream && Now-LastArrival<0.75) return;
    if(bStream)
    {
        bStream=false;
        Super.ResetAt(Now,RenderPosition);
    }
    Super.Receive(Now,Position,Velocity,Sequence);
}

// Advance only through a received, completely stationary path. Checking every
// intermediate sample prevents an out-and-back movement from being skipped
// just because its endpoints happen to coincide. Never extrapolate into time
// for which no host position has arrived.
simulated function float StationaryTarget(float Goal)
{
    local int j,Index;
    local float Target;
    local vector Anchor;
    if(Goal<=PlayTime || Count<2 || PlayTime<Times[First]) return PlayTime;
    Goal=FMin(Goal,Times[(First+Count-1)%HISTORY_SIZE]);
    Anchor=PositionAt(PlayTime); Target=PlayTime;
    for(j=0;j<Count;++j)
    {
        Index=(First+j)%HISTORY_SIZE;
        if(Times[Index]<=PlayTime) continue;
        if(Times[Index]>Goal) break;
        if(VSize(Positions[Index]-Anchor)>0.01) return Target;
        Target=Times[Index];
    }
    if(VSize(PositionAt(Goal)-Anchor)<=0.01) Target=Goal;
    return Target;
}

simulated function Draw(float Now, float DeltaTime)
{
    local int Last;
    local float Goal, WantedRate, Room, Advance, Step, StationaryTime;
    if(!bStream || Clock==None) { Super.Draw(Now,DeltaTime); return; }
    if(P==None || P.bDeleteMe) return;
    Last=(First+Count-1)%HISTORY_SIZE;
    UpdateBufferDelay(Now,FClamp(DeltaTime,0,0.10));
    Goal=FMin(Clock.Estimate(Now)-Delay,Times[Last]-0.015);
    Step=FClamp(DeltaTime,0,0.10);
    StationaryTime=StationaryTarget(Goal-Step);
    if(StationaryTime>PlayTime+0.001)
    {
        StationarySecondsSkipped+=StationaryTime-PlayTime;
        ++StationaryAdvances;
        PlayTime=StationaryTime; PlayRate=1;
    }
    Room=FMax(0,Times[Last]-PlayTime);
    WantedRate=FClamp(1+(Goal-PlayTime)*2,0.90,1.10);
    // Brake before the last sample instead of running off the buffer edge.
    WantedRate=FMin(WantedRate,Sqrt(24*FMax(0,Room-0.005)));
    // Bound acceleration as well as speed on recovery (no one-frame rush).
    PlayRate+=FClamp(WantedRate-PlayRate,-Step*12,Step*2);
    Advance=FMin(Room,Step*PlayRate);
    // If the buffer actually ended, restart from the rate that was displayed,
    // not the faster requested rate hidden behind the end-of-history clamp.
    if(Step>0) PlayRate=Advance/Step;
    PlayTime+=Advance;
    if(PlayTime<Times[First])
    {
        // A stalled renderer cannot retain an unbounded history.
        PlayTime=Times[First]; ++Resets;
    }
    bStarved=Room<=0.001;
    RenderPosition=PositionAt(PlayTime);
    LastDrawStamp=PlayTime; MaxRate=FMax(MaxRate,PlayRate);
    ApplyVisualPosition();
}
