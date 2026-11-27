class CoopCombatDictionary extends Object transient dependson(CoopMotionState);
var array<name> Names;
const MAX_NAMES=1024;

function int EncodeName(CoopPlayer PC,name N)
{
    local int i;
    if(N=='') return 0;
    for(i=0;i<Names.Length;++i) if(Names[i]==N) return i+1;
    if(i>=MAX_NAMES) return -1;
    Names.Length=i+1; Names[i]=N;
    PC.ClientCombatName(i+1,string(N));
    return i+1;
}
simulated function Register(int Id,string Text)
{
    if(Id<=0 || Id>MAX_NAMES || Len(Text)>128) return;
    if(Names.Length<Id) Names.Length=Id;
    Names[Id-1]=class'CoopNative'.static.CombatName(Text);
}
simulated function bool Known(int Id)
{
    return Id==0 || (Id>0 && Id<=Names.Length && Names[Id-1]!='');
}
simulated function name DecodeName(int Id)
{
    if(Id<=0 || Id>Names.Length) return '';
    return Names[Id-1];
}
function CoopMotionState.WirePose Encode(CoopPlayer PC,CoopMotionState.MotionPose S)
{
    local CoopMotionState.WirePose W;
    local int i;
    W.Position=S.Position; W.Velocity=S.Velocity; W.Facing=S.Facing;
    W.IdleState=S.IdleState; W.Flags=S.Flags; W.PhysicsMode=S.PhysicsMode;
    W.LayerCount=Min(6,Max(0,S.Animation.Count));
    for(i=0;i<W.LayerCount;++i)
    {
        W.Layers[i].SequenceId=EncodeName(PC,S.Animation.Layers[i].Sequence);
        W.Layers[i].BoneId=EncodeName(PC,S.Animation.Layers[i].Bone);
        W.Layers[i].Phase=S.Animation.Layers[i].Phase; W.Layers[i].Speed=S.Animation.Layers[i].Speed;
        W.Layers[i].EndPhase=S.Animation.Layers[i].EndPhase;
        W.Layers[i].Channel=S.Animation.Layers[i].Channel; W.Layers[i].Weight=S.Animation.Layers[i].Weight;
        W.Layers[i].Flags=S.Animation.Layers[i].Flags;
        if(W.Layers[i].SequenceId<0 || W.Layers[i].BoneId<0) W.LayerCount=0;
    }
    return W;
}
simulated function CoopMotionState.MotionPose Decode(CoopMotionState.WirePose W)
{
    local CoopMotionState.MotionPose S;
    local int i;
    S.Position=W.Position; S.Velocity=W.Velocity; S.Facing=W.Facing;
    S.IdleState=W.IdleState; S.Flags=W.Flags; S.PhysicsMode=W.PhysicsMode;
    if(W.LayerCount<0 || W.LayerCount>6) return S;
    for(i=0;i<W.LayerCount;++i)
    {
        // A name definition can be delayed behind loss. Keep motion flowing;
        // a later absolute pose recovers animation without replaying events.
        if(!Known(W.Layers[i].SequenceId) || !Known(W.Layers[i].BoneId)) return S;
        S.Animation.Layers[i].Sequence=DecodeName(W.Layers[i].SequenceId);
        S.Animation.Layers[i].Bone=DecodeName(W.Layers[i].BoneId);
        S.Animation.Layers[i].Phase=W.Layers[i].Phase; S.Animation.Layers[i].Speed=W.Layers[i].Speed;
        S.Animation.Layers[i].EndPhase=W.Layers[i].EndPhase;
        S.Animation.Layers[i].Channel=W.Layers[i].Channel; S.Animation.Layers[i].Weight=W.Layers[i].Weight;
        S.Animation.Layers[i].Flags=W.Layers[i].Flags;
    }
    S.Animation.Count=W.LayerCount;
    return S;
}
