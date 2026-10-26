class CoopCommando extends PlayerCommando;

#exec OBJ LOAD FILE="CTGame.u"
#exec OBJ LOAD FILE="CTCharacters.u"

/*
 * CoopCommando
 * Pawn used by clients in a coop game. It is a regular player commando but:
 * - it does not trigger the single player events 'PlayerIncapacitated' and 'PlayerRevived' (level scripts only expect the host to do that)
 * - it is not part of the host's squad
 * - it wears the plain white armor like the host's commando: the colored armors looked like the Delta squad members, who only
 *   show up as the story brings them (e.g. GEO_05A: the player is alone, GEO_01A: before Scorch joins)
 * - like the host it gets incapacitated instead of dying (bCannotDie) so other players can revive it
 */

#exec OBJ LOAD FILE="CloneTextures.utx"

var byte     CoopSkin;        // Index into CoopSkins + 1. Zero means default skin.
var byte     AppliedCoopSkin;
var Material CoopSkins[4];

replication
{
	reliable if(bNetDirty && Role == ROLE_Authority)
		CoopSkin;
}

// PlayerCommando spawns the headlamp (also used by the visor modes) in PostBeginPlay which only runs on the server
simulated event PostNetBeginPlay()
{
	Super.PostNetBeginPlay();

	if(Role < ROLE_Authority && Flashlight == None)
	{
		Flashlight = Spawn(class'CloneHeadlamp', self);

		Log("ModCoop: Created client side headlamp for " $ self $ ": " $ Flashlight);

		if(Flashlight != None)
		{
			AttachToBone(Flashlight, 'lightAttach');
			Flashlight.SetRelativeLocation(vect(0,0,0));
			Flashlight.SetRelativeRotation(rot(0,0,0));
		}
	}
}

simulated event Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);

	if(CoopSkin != AppliedCoopSkin)
		ApplyCoopSkin();
}

simulated function ApplyCoopSkin()
{
	AppliedCoopSkin = CoopSkin;

	if(CoopSkin > 0 && CoopSkin <= ArrayCount(CoopSkins) && CoopSkins[CoopSkin - 1] != None)
		Skins[0] = CoopSkins[CoopSkin - 1];
}

function SetCoopSkin(int SkinIndex)
{
	CoopSkin = Clamp(SkinIndex, 0, ArrayCount(CoopSkins));
	ApplyCoopSkin();
}

defaultproperties
{
	CoopSkins(0)=Shader'CloneTextures.CloneTextures.CloneCommandoWhite_Shader'
	CoopSkins(1)=Shader'CloneTextures.CloneTextures.MP_CloneCommandoB_Shader'
	CoopSkins(2)=Shader'CloneTextures.CloneTextures.MP_CloneCommandoC_Shader'
	CoopSkins(3)=Shader'CloneTextures.CloneTextures.MP_CloneCommandoD_Shader'
	Event=None
	ReviveEvent=None
	bCanBeSquadMember=False
	bCannotDie=True
}
