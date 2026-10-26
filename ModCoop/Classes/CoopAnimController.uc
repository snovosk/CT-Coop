class CoopAnimController extends Controller;

// Client only: stands in for the script controller of an NPC while its script plays an animation (see CoopPlayer.ClientCoopScriptAnim).
// Pawn.ChangeAnimation leaves the animations alone when the controller has bControlAnimations, like on the server.

defaultproperties
{
	bControlAnimations=True
	RemoteRole=ROLE_None
}
