class CoopSight extends Object;

/*
 * CoopSight
 * Purpose: LineOfSightTrigger fires when the player looks at something. The engine does that test for the local player only (its header says
 *   so), so a client standing in front of a cell or a gate didn't count and the level waited for the host (YYY_01D, YYY_01E, RAS_02B). The same
 *   test for the clients, on the server, with the view they send in ServerMove.
 * Entry points: Setup (CoopGame, when the level starts), Check (CoopGame.Tick, every 0.2 seconds).
 * Logging: "CoopGame: sight trigger" (found, with its values), "CoopGame: <player> sees <trigger>, triggering <event>".
 * State: Sights.
 * Known limitations: Trace only tests the world, a line through an actor that blocks the view passes.
 */

const DEGREES_TO_RADIANS = 0.0174533;
const TARGET_TOLERANCE = 64.0;

struct Sight
{
	var Actor Trigger;
	var Actor Seen;
	var float MaxDist;
	var float MinDot;
};

var CoopGame Game;
var array<Sight> Sights;

// HACK: properties read by name -- UCC stops with "Unrecognized member" on the fields of LineOfSightTrigger against the game's Engine.u -- the
// "sight trigger" log line shows the values, a distance of 0 or Seen=None means this stopped working
function Setup(CoopGame G)
{
	local LineOfSightTrigger T;
	local Actor A;
	local string SeenTag;
	local int n;

	Game = G;

	foreach G.AllActors(class'LineOfSightTrigger', T)
	{
		if(T.Event == '')
			continue;

		n = Sights.Length;
		Sights.Length = n + 1;
		Sights[n].Trigger = T;
		Sights[n].MaxDist = float(T.GetPropertyText("MaxViewDist"));
		Sights[n].MinDot = Cos(float(T.GetPropertyText("MaxViewAngle")) * DEGREES_TO_RADIANS);
		SeenTag = T.GetPropertyText("SeenActorTag");

		foreach G.AllActors(class'Actor', A)
		{
			if(string(A.Tag) ~= SeenTag)
			{
				Sights[n].Seen = A;
				break;
			}
		}

		Log("CoopGame: sight trigger " $ T $ " event " $ T.Event $ " seen " $ Sights[n].Seen $ " distance " $ Sights[n].MaxDist $ " dot " $ Sights[n].MinDot);
	}
}

function Check()
{
	local Controller C;
	local Actor T;
	local int i;

	for(i = Sights.Length - 1; i >= 0; i = i - 1)
	{
		T = Sights[i].Trigger;

		if(T == None || T.GetPropertyText("bTriggered") ~= "True")
		{
			Sights.Remove(i, 1);
			continue;
		}

		if(T.GetPropertyText("bEnabled") ~= "False" || Sights[i].Seen == None)
			continue;

		for(C = Game.Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !Game.IsHost(C) && C.Pawn != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated && Sees(C, i))
			{
				Log("CoopGame: " $ C.PlayerReplicationInfo.PlayerName $ " sees " $ T $ ", triggering " $ T.Event);
				T.SetPropertyText("bTriggered", "True");
				T.TriggerEvent(T.Event, T, C.Pawn);
				break;
			}
		}
	}
}

function bool Sees(Controller C, int i)
{
	local vector Eye, ToActor, HitLocation, HitNormal;

	Eye = C.Pawn.Location + C.Pawn.EyePosition();
	ToActor = Sights[i].Seen.Location - Eye;

	if(VSize(ToActor) > Sights[i].MaxDist || (vector(C.Rotation) dot Normal(ToActor)) < Sights[i].MinDot)
		return false;

	// The screens the maps use as targets stand in a window or against a wall, the line ends on them or right in front of them
	return Game.Trace(HitLocation, HitNormal, Sights[i].Seen.Location, Eye, false) == None || VSize(HitLocation - Sights[i].Seen.Location) <= TARGET_TOLERANCE;
}
