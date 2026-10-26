class CoopEventListener extends Info;

// Tells CoopGame that an event of the level was triggered (see CoopGame.ScanArrivals)

var CoopGame Game;

event Trigger(Actor Other, Pawn EventInstigator)
{
	if(Game != None)
		Game.EventHeard(Tag);
}
