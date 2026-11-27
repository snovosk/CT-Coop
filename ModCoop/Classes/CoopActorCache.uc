// Actor references in plain UObjects are not cleared by this engine's
// CleanupDestroyed pass. Stateful world helpers use a hidden, local actor so
// their scalar, array and struct references are cleared before physical free.
class CoopActorCache extends Info abstract;

event PostBeginPlay()
{
    Super.PostBeginPlay();
    Disable('Tick'); // Owners drive maintenance; this is reference storage.
}

defaultproperties
{
    RemoteRole=ROLE_None
    bHidden=True
    bCollideActors=False
    bBlockActors=False
    bBlockPlayers=False
    bProjTarget=False
}
