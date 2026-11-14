class CoopEndLift extends Object;

/*
 * CoopEndLift
 * Purpose: the lifts that end a level (GEO_04D, GEO_05B) wait for the whole squad. The trigger in the car starts them as soon as the
 *   host steps in and the next level loads at the top: clients and squad members were left behind (GEO_05B, checklist 2026-11-01).
 *   The trigger is held back until the host and all squad members that can walk stand on the lift; squad members the AI plays are put
 *   on it if they aren't there soon after the host. Clients aren't waited for: the lift ends in the level change, which takes everybody.
 *   The lifts inside a level (GEO_05A, GEO_05B) start with the first player: a client who came first left the host behind with no way up (GEO_05A,
 *   session 2026-11-02). IsSharedLift names them, CoopGame.CheckLiftRides brings the other players to whoever rides. Their triggers cover only a part
 *   of the car (GEO_05A Lift01: the far wall), a client stood on the car and nothing happened (session 2026-11-02): standing on the car starts them too.
 * Entry points: Setup (CoopGame, when the level starts), IsHeld (CoopExtension.TriggerIsRelevant), Check (CoopGame, every second), IsSharedLift (CoopGame).
 * Logging: "CoopGame: end lift" (found, waiting, members put on it, started), "CoopGame: shared lift".
 * State: Game, Gate, Lift, bStarted, PlayersAboardTime, NextHint, LastMissing, SharedLifts.
 * Logging also: "CoopGame: shared lift ... started" when standing on the car started it.
 * Known limitations: a table of maps. YYY_06C isn't in it: its Elevator is triggered from another room, players don't ride it. A player who
 *   is down on the way holds the lift until somebody revives them, like the start of the level holds nobody.
 */

const HINT_INTERVAL = 4.0;
const MEMBER_WAIT = 10.0;
const SHARED_LIFT_STAND = 1.5;
const START_LIFT_DELAY = 3.0;     // After every client has its pawn
const START_LIFT_MAX_HOLD = 30.0;
const START_LIFT_POLL = 0.5;

var CoopGame Game;
var Trigger Gate;
var Mover Lift;
var bool bStarted;
var float PlayersAboardTime, NextHint;
var int LastMissing;
struct SharedLift
{
	var Mover Lift;
	var Trigger Gate;
	var float StandTime;
	var bool bDone;
};

var array<SharedLift> SharedLifts;

// See ShouldHoldStartLift
var float StartLiftHoldStart, StartLiftReadyTime;
var bool bStartLiftReleased;

function Setup(CoopGame G, string MapName)
{
	local name GateEvent, LiftTag;
	local Trigger T;
	local Mover M;

	Game = G;
	FindSharedLifts(MapName);

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

// The lifts inside a level, from the map dumps. Only these: a client on any other slow mover (the droid racks of GEO_05A) must not move the host.
// Lift00 of GEO_05A isn't one: everybody starts on it with the host
function FindSharedLifts(string MapName)
{
	if(MapName ~= "GEO_05A")
	{
		AddSharedLift('Lift01', 'Lift01Lockdown');
		AddSharedLift('Lift03', 'Lift03Lockdown');
		AddSharedLift('Lift04', 'Lift04Lockdown');
	}
	else if(MapName ~= "GEO_05B")
		AddSharedLift('Lift00', 'Lift00Lockdown');
}

function AddSharedLift(name LiftTag, name GateEvent)
{
	local Mover M;
	local Trigger T;
	local int i;

	foreach Game.AllActors(class'Mover', M, LiftTag)
	{
		i = SharedLifts.Length;
		SharedLifts.Length = i + 1;
		SharedLifts[i].Lift = M;

		foreach Game.AllActors(class'Trigger', T)
		{
			if(T.Event == GateEvent)
				SharedLifts[i].Gate = T;
		}

		Log("CoopGame: shared lift " $ M $ " (" $ LiftTag $ ") gate " $ SharedLifts[i].Gate);
	}
}

function bool IsSharedLift(Mover M)
{
	local int i;

	for(i = 0; i < SharedLifts.Length; i = i + 1)
	{
		if(SharedLifts[i].Lift == M)
			return true;
	}

	return false;
}

// Once per lift: a car that has moved is left alone, standing on it at the top must not send it back
function CheckSharedLifts()
{
	local Controller C;
	local Pawn Rider;
	local int i;

	for(i = 0; i < SharedLifts.Length; i = i + 1)
	{
		if(SharedLifts[i].bDone)
			continue;

		if(SharedLifts[i].Lift.bInterpolating || SharedLifts[i].Lift.KeyNum != 0)
		{
			SharedLifts[i].bDone = true;
			continue;
		}

		Rider = None;

		for(C = Game.Level.ControllerList; C != None; C = C.nextController)
		{
			if(PlayerController(C) != None && C.Pawn != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated && C.Pawn.Base == SharedLifts[i].Lift)
				Rider = C.Pawn;
		}

		if(Rider == None || SharedLifts[i].Gate == None || !SharedLifts[i].Gate.bInitiallyActive)
		{
			SharedLifts[i].StandTime = 0;
			continue;
		}

		if(SharedLifts[i].StandTime == 0)
			SharedLifts[i].StandTime = Game.Level.TimeSeconds;

		if(Game.Level.TimeSeconds - SharedLifts[i].StandTime >= SHARED_LIFT_STAND)
		{
			Log("CoopGame: shared lift " $ SharedLifts[i].Lift $ " started by " $ Rider $ " standing on it");
			SharedLifts[i].bDone = true;
			SharedLifts[i].Gate.TriggerEvent(SharedLifts[i].Gate.Event, SharedLifts[i].Gate, Rider);
		}
	}
}

/*
 * A level that starts on a moving lift (RAS_03B: the elevator script moves the car as the level starts, PlayerStart is attached to it). A client got
 * its squad member while the car was already going down and fell off it, from its side it flew up (session 2026-11-10). The level script's
 * ACTION_MoverToKeyframe waits here until every client has its pawn, then START_LIFT_DELAY more. CoopExtension makes the script wait.
 */
function bool ShouldHoldStartLift(ACTION_MoverToKeyframe Action)
{
	local Mover M;
	local NavigationPoint N;
	local Controller C;
	local bool bStartLift, bReady;

	if(bStartLiftReleased || Action.MoverTag == '' || Action.MoverTag == 'None')
		return false;

	foreach Game.AllActors(class'Mover', M, Action.MoverTag)
	{
		if(M.KeyNum != 0 || M.bInterpolating)
			continue;

		foreach Game.AllActors(class'NavigationPoint', N)
		{
			if(PlayerStart(N) != None && N.Base == M)
				bStartLift = true;
		}
	}

	if(!bStartLift)
		return false;

	if(StartLiftHoldStart == 0)
	{
		StartLiftHoldStart = Game.Level.TimeSeconds;
		Log("CoopGame: start lift " $ Action.MoverTag $ " held until the clients stand on it");
	}

	bReady = !Game.bWaitingForClients;

	for(C = Game.Level.ControllerList; C != None && bReady; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !Game.IsHost(C) && (C.Pawn == None || C.Pawn.Health <= 0 || C.Pawn.Physics == PHYS_Falling))
			bReady = false;
	}

	if(!bReady)
		StartLiftReadyTime = 0;
	else if(StartLiftReadyTime == 0)
		StartLiftReadyTime = Game.Level.TimeSeconds;

	if((bReady && Game.Level.TimeSeconds - StartLiftReadyTime >= START_LIFT_DELAY) || Game.Level.TimeSeconds - StartLiftHoldStart >= START_LIFT_MAX_HOLD)
	{
		Log("CoopGame: start lift " $ Action.MoverTag $ " released after " $ (Game.Level.TimeSeconds - StartLiftHoldStart) $ " s, clients ready " $ bReady);
		bStartLiftReleased = true;
		return false;
	}

	return true;
}

function float StartLiftPoll()
{
	return START_LIFT_POLL;
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

	CheckSharedLifts();

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

		if(IsOnLift(C.Pawn))
			Aboard = C.Pawn;
		else
			++Missing;
	}

	// The lift carries its riders into the level change (GEO_04D Teleporter2, GEO_05B Teleporter1) and every player goes to the next
	// level wherever they stand: only the host is waited for. Waiting for every player in the small car locked the game: the host in the
	// doorway, a client couldn't get in (GEO_04D, the tester's game on 0.73, 2026-11-13)
	if(Host == None || !IsOnLift(Host.Pawn))
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
		Log("CoopGame: end lift: the host is on it, " $ Missing $ " of " $ Players $ " players and " $ Bots $ " squad members aren't");

	LastMissing = Missing;

	if(Bots > 0)
	{
		if(PlayersAboardTime == 0)
			PlayersAboardTime = Game.Level.TimeSeconds;

		if(Game.Level.TimeSeconds - PlayersAboardTime < MEMBER_WAIT)
			return;

		PutBotsOnLift(Host.Pawn, Host.Pawn);
	}

	Log("CoopGame: end lift starts with the host, " $ (Players - Missing) $ " of " $ Players $ " players on it");
	bStarted = true;
	Gate.TriggerEvent(Gate.Event, Gate, Host.Pawn);
}
