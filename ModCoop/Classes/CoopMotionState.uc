class CoopMotionState extends Object abstract;

// Absolute, self-contained animation samples. No animation notifications are
// replayed by the visual mesh; damage and weapon events remain authoritative.
struct AnimLayer
{
    var name Sequence, Bone;
    var float Phase, Speed, EndPhase;
    var byte Channel, Weight, Flags, Reserved;
};
struct AnimPose
{
    var int Count;
    var AnimLayer Layers[6];
};
struct MotionPose
{
    var vector Position, Velocity;
    var rotator Facing;
    var byte IdleState, Flags, PhysicsMode;
    var AnimPose Animation;
};

// Mesh animation names are not necessarily in Unreal's network package name
// table (native animation selection synthesizes some names at runtime). Use a
// bounded per-connection dictionary instead of letting an unknown FName drop
// the whole movement RPC.
struct WireLayer
{
    var int SequenceId, BoneId;
    var float Phase, Speed, EndPhase;
    var byte Channel, Weight, Flags, Reserved;
};
struct WirePose
{
    var vector Position, Velocity;
    var rotator Facing;
    var byte IdleState, Flags, PhysicsMode;
    var int LayerCount;
    var WireLayer Layers[6];
};
