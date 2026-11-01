class CoopEndLift extends Object;

/*
 * CoopEndLift
 * Purpose: the lifts that end a level (GEO_04D, GEO_05B) wait for the whole squad. The trigger in the car starts them as soon as the
 *   host steps in and the next level loads at the top: clients and squad members were left behind (GEO_05B, checklist 2026-11-01).
 *   The trigger is held back until all players and all squad members that can walk stand on the lift. Players who are missing get a
 *   hint with their number; squad members the AI plays are put on the lift if they aren't there soon after the last player.
 * Entry points: Setup (CoopGame, when the level starts), IsHeld (CoopExtension.TriggerIsRelevant), Check (CoopGame, every second).
 * Logging: "CoopGame: end lift" (found, waiting, members put on it, started).
 * State: Game, Gate, Lift, bStarted, PlayersAboardTime, NextHint, LastMissing.
 * Known limitations: a table of maps. YYY_06C isn't in it: its Elevator is triggered from another room, players don't ride it. A player who
 *   is down on the way holds the lift until somebody revives them, like the start of the level holds nobody.
 */

const HINT_INTERVAL = 4.0;
const MEMBER_WAIT = 10.0;

var CoopGame Game;
var Trigger Gate;
var Mover Lift;
var bool bStarted;
var float PlayersAboardTime, NextHint;
var int LastMissing;

function Setup(CoopGame G, string MapName)
{
	local name GateEvent, LiftTag;
	local Trigger T;
	local Mover M;

	Game = G;

	if(MapName ~= "GEO_05B")
	{
		GateEvent = 'StartElevator';
		LiftTag = 'Elevator';
	}
	else if(MapName ~= "GEO_04D")
	{
		GateEvent = 'ElevatorLockdown';
		LiftTag = 'StartLift';
	}
	else
		return;

	foreach G.AllActors(class'Trigger', T)
	{
		if(T.Event == GateEvent)
			Gate = T;
	}

	foreach G.AllActors(class'Mover', M, LiftTag)
		Lift = M;

	if(Gate == None || Lift == None)
		Gate = None;

	Log("CoopGame: end lift " $ Lift $ " held by " $ Gate);
}

function bool IsHeld(Trigger T)
{
	return T == Gate && !bStarted;
}

function bool IsOnLift(Pawn P)
{
	return P != None && P.Base == Lift;
}

// A squad member the AI plays, standing. One that is down or dead doesn't hold the lift (the level's own scripts count them as arrived)
function bool IsWalkingBot(Pawn P, Pawn HostPawn)
{
	return P.IsA('CloneCommando') && P.Health > 0 && !P.bIncapacitated && PlayerController(P.Controller) == None && HostPawn != None && P.Squad == HostPawn.Squad;
}

function PutBotsOnLift(Pawn HostPawn, Pawn Aboard)
{
	local Pawn P;
	local vector Spot;

	foreach Game.DynamicActors(class'Pawn', P)
	{
		if(IsWalkingBot(P, HostPawn) && !IsOnLift(P) && Game.FindLiftSpot(Aboard, Lift, Spot))
		{
			Log("CoopGame: end lift: putting " $ P $ " on it");
			P.SetLocation(Spot);
		}
	}
}

function Check()
{
	local Controller C;
	local PlayerController Host;
	local Pawn P, Aboard;
	local int Missing, Bots, Players;
	local bool bHostSeen;
	local string Hint;
	local color HintColor;

	// Squad members in formation walk off again, the lift doesn't wait for that (GEO_04D)
	if(bStarted)
	{
		Host = Game.GetHost();

		if(Host != None && IsOnLift(Host.Pawn))
			PutBotsOnLift(Host.Pawn, Host.Pawn);

		return;
	}

	// Trigger.OtherTriggerTurnsOn: until then the members are on their way (GEO_05B: the counter MemberArrived)
	if(Gate == None || !Gate.bInitiallyActive)
		return;

	Host = Game.GetHost();

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) == None)
			continue;

		++Players;
		bHostSeen = bHostSeen || C == Host;

		if(IsOnLift(C.Pawn))
			Aboard = C.Pawn;
		else
			++Missing;
	}

	// Nobody has come to the lift yet
	if(Aboard == None || !bHostSeen)
	{
		PlayersAboardTime = 0;
		return;
	}

	foreach Game.DynamicActors(class'Pawn', P)
	{
		if(IsWalkingBot(P, Host.Pawn) && !IsOnLift(P))
			++Bots;
	}

	if(Missing != LastMissing)
		Log("CoopGame: end lift waits for " $ Missing $ " of " $ Players $ " players and " $ Bots $ " squad members");

	LastMissing = Missing;

	if(Missing > 0)
	{
		PlayersAboardTime = 0;

		if(Game.Level.TimeSeconds >= NextHint)
		{
			NextHint = Game.Level.TimeSeconds + HINT_INTERVAL;
			Hint = "The lift is waiting for " $ Missing $ " more player(s)";
			HintColor.R = 255;
			HintColor.G = 255;
			HintColor.B = 255;
			HintColor.A = 255;

			for(C = Game.Level.ControllerList; C != None; C = C.nextController)
			{
				if(PlayerController(C) != None && PlayerController(C).myHUD != None && Viewport(PlayerController(C).Player) != None)
					PlayerController(C).myHUD.AddCriticalMessage(Hint, HINT_INTERVAL, HintColor);
				else if(CoopPlayer(C) != None)
					CoopPlayer(C).ClientCoopCriticalMessage(Hint, HINT_INTERVAL, HintColor);
			}
		}

		return;
	}

	if(Bots > 0)
	{
		if(PlayersAboardTime == 0)
			PlayersAboardTime = Game.Level.TimeSeconds;

		if(Game.Level.TimeSeconds - PlayersAboardTime < MEMBER_WAIT)
			return;

		PutBotsOnLift(Host.Pawn, Aboard);
	}

	Log("CoopGame: end lift starts with all " $ Players $ " players");
	bStarted = true;
	Gate.TriggerEvent(Gate.Event, Gate, Host.Pawn);
}
