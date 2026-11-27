// Per-pawn arrival history. A single late packet must not permanently increase
// visual delay; repeated gaps should be absorbed before extending prediction.
class CoopMotionBuffer extends Object transient;

var float Gaps[16], Sorted[16], LastArrival, TailGap, Pressure, LastPressure;
var int Count, Cursor;

simulated function Reset(float Now)
{
    Count=0; Cursor=0; LastArrival=Now; TailGap=0; Pressure=0; LastPressure=0;
}

simulated function Observe(float Now, bool Starved, bool RecentlyDrawn)
{
    local float Gap,Value;
    local int i,j;
    Gap=Now-LastArrival; LastArrival=Now;
    if(Gap<=0 || Gap>0.5) return;
    Gaps[Cursor]=Gap; Cursor=(Cursor+1)%16; Count=Min(16,Count+1);
    for(i=0;i<Count;++i)
    {
        Value=Gaps[i]; j=i;
        while(j>0 && Sorted[j-1]>Value) {Sorted[j]=Sorted[j-1]; --j;}
        Sorted[j]=Value;
    }
    // Second largest of a full window: ignore one exceptional stall.
    if(Count>=8) TailGap=Sorted[Max(0,Count-2)];
    if(Starved && RecentlyDrawn && Now-LastPressure>0.1)
    {
        Pressure=FMin(0.06,Pressure+0.015);
        LastPressure=Now;
    }
}

simulated function float Target(float Now, float DT, float MeanInterval, float Jitter)
{
    local float Base;
    if(Now-LastPressure>3) Pressure=FMax(0,Pressure-FClamp(DT,0,0.1)*0.005);
    Base=FClamp(MeanInterval*2+Jitter*3,0.10,0.20);
    // Preserve the existing 200 ms ceiling and 100 ms prediction limit.
    return FClamp(FMax(Base,TailGap+MeanInterval)+Pressure,0.10,0.20);
}
