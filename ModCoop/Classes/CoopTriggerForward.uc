class CoopTriggerForward extends Info;

#exec OBJ LOAD FILE="Gameplay.u"

/*
 * CoopTriggerForward
 * Purpose: map actors that only exist or only change on the server reach the clients.
 *   - Placed emitters (fire, steam, fog, rain, sparks, shields: about 800 in the campaign) have RemoteRole None and
 *     are not bNoDelete: clients delete their copies when loading the map and the server never sent them. They are sent now
 *     (DumbProxy, always relevant) and come with their class defaults.
 *   - Events that trigger them run Emitter.Trigger on the server only: the clients get the trigger with the emitter and run the
 *     native trigger of its particle emitters (script functions of actors the server sent don't run on clients).
 *   - Anti portals are kept by the clients: the clients switch their own copies.
 *   - MaterialTrigger switches materials (screens, lights), which are not actors: the clients trigger the same materials.
 *   - ViewShaker shakes the views of the server's controllers: the clients near it get the shake.
 *   One listener per tag of such actors, it hears the Trigger and UnTrigger of the event.
 * Entry points: Setup (CoopGame, when the level starts), Trigger/UnTrigger (events of the level), TriggerOnClient,
 *   TriggerTagOnClient and TriggerMaterialOnClient (CoopPlayer.ClientCoopTriggerActor, ClientCoopTriggerLocal,
 *   ClientCoopTriggerMaterial).
 * Logging: server "CoopGame: sending N placed emitters", "CoopGame: listening to the events of N map actors",
 *   "CoopGame: forwarding trigger"; client "ModCoop: trigger of the host".
 * State: Game.
 * Known limitations: emitters of the base class Emitter (particles set up in the map, 24 in the campaign), karma actors, ragdolls,
 *   projectors and matinee scenes are not sent (only their class would arrive; karma actors have no karma model on the
 *   client). Particles edited per actor in the map look like the class.
 */

var CoopGame Game;

// Server, when the level starts
static function Setup(CoopGame G)
{
	local Actor A;
	local CoopTriggerForward L;
	local int NumSent, NumHeard;
	local bool bFound;

	foreach G.AllActors(class'Actor', A)
	{
		if(IsSentToClients(A))
		{
			A.RemoteRole = ROLE_DumbProxy;
			A.bAlwaysRelevant = true;
			++NumSent;
		}

		if(A.Tag == '' || A.Tag == 'None' || A.Tag == A.Class.Name || !IsForwarded(A))
			continue;

		++NumHeard;
		bFound = false;

		foreach G.DynamicActors(class'CoopTriggerForward', L, A.Tag)
		{
			bFound = true;
			break;
		}

		if(bFound)
			continue;

		L = G.Spawn(class'CoopTriggerForward');
		L.Game = G;
		L.Tag = A.Tag;
	}

	Log("CoopGame: sending " $ NumSent $ " placed emitters to the clients");
	Log("CoopGame: listening to the events of " $ NumHeard $ " map actors that only change on the server");
}

// Placed actors the clients delete when loading the map and the server never sent, and that their class can rebuild
static function bool IsSentToClients(Actor A)
{
	if(A.RemoteRole != ROLE_None || A.bStatic || A.bNoDelete || A.bDeleteMe)
		return false;

	// Not karma actors: the clients have no karma model for them ("KInitActorDynamics: No Model")
	return A.IsA('Emitter') && A.Class != class'Emitter';
}

static function bool IsForwarded(Actor A)
{
	return A.IsA('MaterialTrigger') || A.IsA('ViewShaker') || A.IsA('Emitter') || A.IsA('AntiPortalActor');
}

event Trigger(Actor Other, Pawn EventInstigator)
{
	Forward(false);
}

event UnTrigger(Actor Other, Pawn EventInstigator)
{
	Forward(true);
}

function Forward(bool bUnTrigger)
{
	local Actor A;
	local string List, Path;
	local ViewShaker VS;
	local Controller C;
	local bool bAntiPortals;

	if(Game == None)
		return;

	foreach AllActors(class'Actor', A, Tag)
	{
		VS = ViewShaker(A);

		// HACK: the list of MaterialTrigger is read as text -- the compiler doesn't know the class as a type although Engine.u has
		// it -- check: "forwarding trigger of material" in the host's log on RAS_02A or YYY_04A
		if(A.IsA('MaterialTrigger') && !bUnTrigger)
		{
			List = A.GetPropertyText("MaterialsToTrigger");

			while(InStr(List, "'") != -1)
			{
				List = Mid(List, InStr(List, "'") + 1);
				Path = Left(List, InStr(List, "'"));
				List = Mid(List, InStr(List, "'") + 1);
				Log("CoopGame: forwarding trigger of material " $ Path $ " (" $ A $ ")");

				for(C = Level.ControllerList; C != None; C = C.nextController)
				{
					if(CoopPlayer(C) != None && !Game.IsHost(C))
						CoopPlayer(C).ClientCoopTriggerMaterial(Path);
				}
			}
		}
		else if(VS != None && !bUnTrigger)
		{
			// Same test as ViewShaker.Trigger, with the view targets of the clients on the server
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !Game.IsHost(C) && PlayerController(C).ViewTarget != None &&
				   VSize(VS.Location - PlayerController(C).ViewTarget.Location) < VS.ShakeRadius)
				{
					Log("CoopGame: forwarding the shake of " $ VS $ " to " $ C.PlayerReplicationInfo.PlayerName);
					CoopPlayer(C).ClientCoopShakeView(VS.InTime, VS.SustainTime, VS.OutTime, VS.ShakeMag, VS.ShakeRotationMag, VS.Frequency);
				}
			}
		}
		else if(Emitter(A) != None && A.RemoteRole != ROLE_None && !bUnTrigger)
		{
			Log("CoopGame: forwarding trigger of " $ A);
			Game.RememberTrigger(A);

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !Game.IsHost(C))
					CoopPlayer(C).ClientCoopTriggerActor(A);
			}
		}
		else if(A.IsA('AntiPortalActor'))
			bAntiPortals = true;
	}

	if(!bAntiPortals)
		return;

	Log("CoopGame: forwarding trigger of the anti portals " $ Tag $ " (untrigger " $ bUnTrigger $ ")");

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !Game.IsHost(C))
			CoopPlayer(C).ClientCoopTriggerLocal(Tag, bUnTrigger);
	}
}

// Client: Emitter.Trigger of an emitter the server sent (its script functions don't run on clients)
static function TriggerOnClient(Actor A)
{
	local Emitter E;
	local int i;

	E = Emitter(A);

	if(E == None)
	{
		Log("ModCoop: trigger of the host: the emitter isn't here yet");
		return;
	}

	for(i = 0; i < E.Emitters.Length; ++i)
	{
		if(E.Emitters[i] != None)
			E.Emitters[i].Trigger();
	}

	Log("ModCoop: trigger of the host: " $ E $ ", " $ E.Emitters.Length $ " particle emitters");
}

// Client: the client's own anti portals with this tag (states TriggerControl and TriggerToggle of AntiPortalActor)
static function TriggerTagOnClient(CoopPlayer PC, name EventTag, bool bUnTrigger)
{
	local Actor A;
	local int Num;

	foreach PC.AllActors(class'Actor', A, EventTag)
	{
		if(!A.IsA('AntiPortalActor'))
			continue;

		++Num;

		if(A.IsInState('TriggerControl'))
		{
			if(bUnTrigger)
				A.SetDrawType(DT_AntiPortal);
			else
				A.SetDrawType(DT_None);
		}
		else if(!bUnTrigger && A.DrawType == DT_AntiPortal)
			A.SetDrawType(DT_None);
		else if(!bUnTrigger && A.DrawType == DT_None)
			A.SetDrawType(DT_AntiPortal);
	}

	Log("ModCoop: trigger of the host: anti portals " $ EventTag $ " (untrigger " $ bUnTrigger $ "), " $ Num $ " actors");
}

static function TriggerMaterialOnClient(CoopPlayer PC, string MaterialPath)
{
	local Material M;

	M = Material(DynamicLoadObject(MaterialPath, class'Material', true));

	if(M == None)
	{
		Log("ModCoop: material of the host's trigger not found: " $ MaterialPath);
		return;
	}

	Log("ModCoop: trigger of the host: material " $ M);
	M.Trigger(PC, PC.Pawn);
}

defaultproperties
{
	RemoteRole=ROLE_None
}
