class CoopCombatAnimation extends Object abstract dependson(CoopMotionState);

static function float AdvancePhase(CoopMotionState.AnimLayer L, float DT)
{
    local float P;
    P=L.Phase+FMax(0,L.Speed)*FClamp(DT,0,0.25);
    if((L.Flags&1)!=0) return P-int(P);
    return FClamp(P,0,L.EndPhase);
}

static function CoopMotionState.AnimPose Advance(CoopMotionState.AnimPose A, float DT)
{
    local int i;
    for(i=0;i<A.Count && i<6;++i) A.Layers[i].Phase=AdvancePhase(A.Layers[i],DT);
    return A;
}

static function CoopMotionState.AnimPose Between(CoopMotionState.AnimPose A, CoopMotionState.AnimPose B, float DT, float Span)
{
    local int i,j;
    local float T,Delta,Phase;
    local CoopMotionState.AnimPose R;
    if(Span<=0 || DT>=Span) return B;
    if(DT<=0) return A;
    T=FClamp(DT/Span,0,1); R=Advance(A,DT);
    for(i=0;i<A.Count && i<6;++i)
    {
        for(j=0;j<B.Count && j<6;++j)
        {
            if(A.Layers[i].Bone!=B.Layers[j].Bone || A.Layers[i].Channel!=B.Layers[j].Channel ||
               A.Layers[i].Sequence!=B.Layers[j].Sequence || A.Layers[i].Flags!=B.Layers[j].Flags) continue;
            Delta=B.Layers[j].Phase-A.Layers[i].Phase;
            if((A.Layers[i].Flags&1)!=0 && Delta<0) Delta+=1;
            // A nonlooping shot/hit restarting is a new event. Do not scrub
            // the previous shot backwards or invent an intermediate pose.
            if(Delta<0 || Span>0.25) break;
            Phase=A.Layers[i].Phase+Delta*T;
            if((A.Layers[i].Flags&1)!=0) Phase-=int(Phase);
            R.Layers[i].Phase=Phase;
            R.Layers[i].Weight=byte(float(A.Layers[i].Weight)+(float(B.Layers[j].Weight)-A.Layers[i].Weight)*T);
            break;
        }
    }
    return R;
}
