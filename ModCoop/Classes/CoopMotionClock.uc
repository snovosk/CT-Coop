// Client presentation clock. Packet arrival jitter never becomes sample time.
class CoopMotionClock extends Object transient;

var bool bReady;
var float Offset, LastArrival, LastStamp, Jitter;
var int LastSequence, Epoch;
var float ArrivalOffsets[16], ObservationTimes[16];
var int WindowFirst, WindowCount, FastRecoveries;
var bool bRecovering;
var float RecentFloor, MaxUpwardStep;

// Retain the low-delay floor of the last half second, rather than a minimum
// that can remain stale for minutes after a local clock discontinuity.
simulated function RememberOffset(float Now, float Sample)
{
    local int j,Index;
    while(WindowCount>0 && Now-ObservationTimes[WindowFirst]>0.5)
    {
        WindowFirst=(WindowFirst+1)%16; --WindowCount;
    }
    if(WindowCount==16) WindowFirst=(WindowFirst+1)%16;
    else ++WindowCount;
    Index=(WindowFirst+WindowCount-1)%16;
    ObservationTimes[Index]=Now; ArrivalOffsets[Index]=Sample;
    RecentFloor=Sample;
    for(j=0;j<WindowCount;++j)
        RecentFloor=FMin(RecentFloor,ArrivalOffsets[(WindowFirst+j)%16]);
}

simulated function Observe(float Now, float Stamp, int Sequence)
{
    local float ArrivalGap, ServerGap, Error,PreviousOffset,Rate;
    if(bReady && Sequence==LastSequence) return; // Other batch in the same tick.
    if(bReady && Stamp<=LastStamp) return; // Late/out-of-order unreliable packet.
    ArrivalGap=Now-LastArrival; ServerGap=Stamp-LastStamp;
    if(!bReady || ArrivalGap<0 || ArrivalGap>2)
    {
        Offset=Now-Stamp; Jitter=0; ++Epoch; bReady=true;
        WindowFirst=0; WindowCount=0; bRecovering=false;
        RememberOffset(Now,Offset);
    }
    else
    {
        RememberOffset(Now,Now-Stamp);
        PreviousOffset=Offset;
        // Require repeated, time-separated evidence: one late or bunched
        // packet must not redefine the clock. Hysteresis finishes recovery
        // instead of leaving a permanent ~60 ms error at the entry threshold.
        if(!bRecovering && RecentFloor-Offset>0.06 && WindowCount>=4 &&
            Now-ObservationTimes[WindowFirst]>=0.119)
        {
            bRecovering=true; ++FastRecoveries;
        }
        if(RecentFloor-Offset<=0.005) bRecovering=false;
        Rate=0.005; if(bRecovering) Rate=0.5;
        // Bound each adjustment even when a renderer/clock stalls. This does
        // not rewind PlayTime or reset track history/epoch. Tracks retain their
        // existing rate, prediction and position-correction limits.
        Offset=FMin(Offset+FClamp(ArrivalGap,0,0.10)*Rate,RecentFloor);
        MaxUpwardStep=FMax(MaxUpwardStep,Offset-PreviousOffset);
        Error=FMin(Abs(ArrivalGap-ServerGap),0.2);
        if(Error>Jitter) Jitter+=0.2*(Error-Jitter);
        else Jitter+=0.02*(Error-Jitter);
    }
    LastArrival=Now; LastStamp=Stamp; LastSequence=Sequence;
}

simulated function float Estimate(float Now)
{
    return Now-Offset;
}
