class CoopDoorHold extends Object;

/*
 * CoopDoorHold
 * Purpose: a door that closes behind the host for good (RAS_01B, Mover13). In single player the player passing Trigger4 ends the scene, the door
 *   closes and ScriptedTrigger1 destroys the only trigger that opens it: a client still on the near side was locked out. The user's decision
 *   (2026-11-10, changed 2026-11-12): the door closes behind the host as in single player, no countdown (HOLD_TIME 0: the 10 s countdown
 *   started when the berserkers were already there). Who didn't make it is caught with the berserkers, and once they are all dead the door
 *   works again: it opens for a player who comes up to it. No teleport.
 * Entry points: Setup (CoopGame, when the level starts), Check (CoopGame.Timer, once a second is enough), IsHeld (CoopExtension.TriggerIsRelevant),
 *   ShouldDeferFactoryStop and ShouldDeferDestroy (CoopExtension, hooks of ACTION_StopFactorySpawning and ACTION_DestroyActor).
 * Logging: "CoopGame: door hold" armed, started, host behind, side (each player, at closing), closing N stragglers, trap release (reason), done.
 * State: Stage (source of truth for the whole sequence), Game, Gate, Door, HoldEnd, ClearStart, TrapStart, NextHint, bDoorTriggered,
 *   bFactoryDeferred, bDestroyDeferred. Server only, nothing is saved or replicated, clients only get messages and the pointer.
 * Known limitations: a table of maps. A player outside NearMin/NearMax on the wrong side at closing isn't a straggler and has to die to get back.
 *   The door crushes (MoverEncroachType 2): a player who stands in the doorway through all of DOOR_CLEAR_WAIT dies and respawns by the host.
 *   The pointer replaces a tracker the level has shown to clients, and hiding it hides that one too. Which pawn counts as an enemy is a class name.
 */

const HOLD_TIME = 0.0;   // Was 10 s with a countdown (the user, 2026-11-12: first the enemies, then the door)
const HINT_INTERVAL = 2.0;
const DOOR_CLEAR_WAIT = 3.0;
const DOORWAY_RADIUS = 160.0;   // Mover's default CollisionRadius, the door itself is about this wide
const DOORWAY_HEIGHT = 200.0;
const DOOR_OPEN_RADIUS = 384.0; // Trigger10's radius: how close a player has to come for the door to open again
const ENEMY_RADIUS = 4000.0;    // Berserkers this close to the door belong to the trap, also while they are still on their way
const TRAP_EMPTY_WAIT = 20.0;   // A trap that never saw a berserker opens after this

const MSG_DOOR_WAITING = "HURRY! THE DOOR IS ABOUT TO CLOSE";
const MSG_DOOR_OPEN = "THE DOOR WORKS AGAIN";
const MSG_DOOR_TRAP = "DOOR CLOSED: KILL THE BERSERKERS TO OPEN IT";

// HUD.ConsoleColor: the color of the game's own system messages
const HINT_R = 153;
const HINT_G = 216;
const HINT_B = 253;

enum EDoorHoldStage
{
	DH_Idle,      // Waiting for the host to touch the gate
	DH_Hold,      // Countdown, the door is kept open
	DH_Clearing,  // At zero, waiting for the doorway to clear
	DH_Trap,      // Door closed with stragglers on the near side
	DH_OpenWay,   // Door open again, waiting for stragglers to leave
	DH_Done
};

var CoopGame Game;
var EDoorHoldStage Stage;
var Trigger Gate;
var Mover Door;
var vector DoorPoint, NearMin, NearMax;
var float ExcludeBelowY, ExcludeAboveX;   // The strip of NearMin/NearMax that lies beyond the door
var name DeferredFactoryTag, DeferredDestroyTag, SpareEvent;
var float HoldEnd, ClearStart, TrapStart, NextHint;
var bool bDoorTriggered;                  // Our own count is on the door (Mover.numTriggerEvents), see KeepDoorOpen
var bool bHostBehindLogged;
var bool bEnemiesSeen;                    // The trap has seen its berserkers (CheckTrap)
var bool bFactoryDeferred, bDestroyDeferred;

function Setup(CoopGame G)
{
	local PlayerController Host;
	local string Map;
	local name GateEvent, DoorTag;
	local Trigger T;
	local Mover M;

	Game = G;
	Host = G.GetHost();

	if(Host == None)
		return;

	Host.GetCurrentMapName(Map);

	if(Map ~= "RAS_01B")
	{
		GateEvent = 'Killemall';
		DoorTag = 'OpenSezMe';
		DoorPoint = vect(-2241,6988,-895);
		NearMin = vect(-5950,6800,-950);
		NearMax = vect(-2050,7620,-370);
		ExcludeBelowY = 6988;
		ExcludeAboveX = -2600;
		DeferredFactoryTag = 'comintagetchafool';
		DeferredDestroyTag = 'Dick';
		SpareEvent = 'comintagetchafool2';
	}
	else
		return;

	foreach G.AllActors(class'Trigger', T)
	{
		if(T.Event == GateEvent)
			Gate = T;
	}

	// The tag is shared with a far-away door (Mover14) and a factory, so the event itself can't be used to open this one
	foreach G.AllActors(class'Mover', M, DoorTag)
	{
		if(Door == None || VSize(M.Location - DoorPoint) < VSize(Door.Location - DoorPoint))
			Door = M;
	}

	if(Door == None)
		Gate = None;

	Log("CoopGame: door hold armed on " $ Map $ ": gate " $ Gate $ " door " $ Door $ " at " $ DoorPoint);
}

function bool HasClients()
{
	local Controller C;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) != None && !Game.IsHost(C))
			return true;
	}

	return false;
}

function bool InNearBox(vector L)
{
	if(L.X < NearMin.X || L.X > NearMax.X || L.Y < NearMin.Y || L.Y > NearMax.Y || L.Z < NearMin.Z || L.Z > NearMax.Z)
		return false;

	return L.Y >= ExcludeBelowY || L.X <= ExcludeAboveX;
}

// Dead counts as not past: closing now would decide the trap without knowing where the host comes back
function bool IsHostPast(Pawn HostPawn)
{
	return HostPawn != None && HostPawn.Health > 0 && !InNearBox(HostPawn.Location);
}

// The gate stays held after it has fired: Trigger.Touch would send the event a second time
function bool IsHeld(Trigger T, Actor Other)
{
	if(Gate == None || T != Gate)
		return false;

	if(Stage != DH_Idle)
		return true;

	if(!HasClients())
		return false;

	// A client who gets here first starts nothing, the hold counts from the host
	if(Pawn(Other) != None && Game.IsHost(Pawn(Other).Controller))
		StartHold(Pawn(Other));

	return true;
}

function StartHold(Pawn HostPawn)
{
	Stage = DH_Hold;
	HoldEnd = Game.Level.TimeSeconds + HOLD_TIME;
	NextHint = 0;
	Log("CoopGame: door hold started by " $ HostPawn $ " at " $ HostPawn.Location $ ", door " $ Door $ " closes in " $ HOLD_TIME);
}

/*
 * The factory stops at closing as in single player: it respawns its berserkers for as long as it runs (counter trandodie went past 10 in
 * the test), so a trap with it running could never be won. The berserkers already in the room are the trap.
 */
function bool ShouldDeferFactoryStop(name FactoryTag)
{
	return false;
}

function bool ShouldDeferDestroy(name DestroyTag)
{
	if(DestroyTag != DeferredDestroyTag || !IsTrapRunning())
		return false;

	bDestroyDeferred = true;
	return true;
}

function bool IsTrapRunning()
{
	return Stage == DH_Trap || Stage == DH_OpenWay;
}

// DeltaTime isn't used: deadlines are in Level.TimeSeconds, which stops with the pause at the start of a level
function Check(float DeltaTime)
{
	local PlayerController Host;
	local Pawn HostPawn;

	if(Stage == DH_Idle || Stage == DH_Done)
		return;

	Host = Game.GetHost();

	if(Host != None)
		HostPawn = Host.Pawn;

	if(Stage == DH_Hold)
		CheckHold(HostPawn);
	else if(Stage == DH_Clearing)
		CheckClearing(HostPawn);
	else if(Stage == DH_Trap)
		CheckTrap(HostPawn);
	else if(Stage == DH_OpenWay)
		CheckOpenWay(HostPawn);
}

function CheckHold(Pawn HostPawn)
{
	local float TimeLeft;

	if(HasClients())
		KeepDoorOpen(HostPawn);
	else if(Game.Level.TimeSeconds < HoldEnd)
	{
		Log("CoopGame: door hold: all clients left, not waiting any longer");
		HoldEnd = Game.Level.TimeSeconds;
	}

	TimeLeft = HoldEnd - Game.Level.TimeSeconds;

	if(TimeLeft > 0)
	{
		if(IsHintDue())
			SendHint("HURRY! DOOR CLOSES IN " $ int(TimeLeft + 0.5) $ " SEC", true);

		return;
	}

	// Closing now would lock the host out too: Trigger10 is gone as soon as the gate fires
	if(!IsHostPast(HostPawn))
	{
		if(!bHostBehindLogged)
			Log("CoopGame: door hold host behind: " $ HostPawn $ " is not past the door, the timer waits");

		bHostBehindLogged = true;

		if(IsHintDue())
			SendHint(MSG_DOOR_WAITING, true);

		return;
	}

	bHostBehindLogged = false;
	Stage = DH_Clearing;
	ClearStart = Game.Level.TimeSeconds;
	CheckClearing(HostPawn);
}

// The door crushes what is under it (MoverEncroachType 2)
function CheckClearing(Pawn HostPawn)
{
	if(!IsHostPast(HostPawn))
	{
		Stage = DH_Hold;
		return;
	}

	if(IsDoorwayOccupied() && Game.Level.TimeSeconds - ClearStart < DOOR_CLEAR_WAIT)
		return;

	CloseAndFire(HostPawn);
}

function bool IsDoorwayOccupied()
{
	local Pawn P;
	local vector D;

	foreach Game.DynamicActors(class'Pawn', P)
	{
		D = P.Location - DoorPoint;

		if(P.Health > 0 && Abs(D.Z) < DOORWAY_HEIGHT)
		{
			D.Z = 0;

			if(VSize(D) < DOORWAY_RADIUS)
				return true;
		}
	}

	return false;
}

function CloseAndFire(Pawn HostPawn)
{
	local int Stragglers;

	LogSides();
	Stragglers = CountStragglers();
	Log("CoopGame: door hold closing " $ Stragglers $ " stragglers, door " $ Door $ " at " $ Door.Location $ " host " $ HostPawn $ " at " $ HostPawn.Location);
	HidePointer();
	CloseDoor();

	// Before the gate fires: the hooks of ScriptedTrigger1's actions read the stage
	if(Stragglers > 0)
	{
		Stage = DH_Trap;
		TrapStart = Game.Level.TimeSeconds;
		SendHint(MSG_DOOR_TRAP, false);
	}
	else
		Stage = DH_Done;

	Gate.TriggerEvent(Gate.Event, Gate, HostPawn);

	if(Stragglers > 0)
		Gate.TriggerEvent(SpareEvent, Gate, HostPawn);    // PawnFactory14 may be used up by now, this way somebody is in the trap
	else
		Log("CoopGame: door hold done: nobody was left behind");
}

function CheckTrap(Pawn HostPawn)
{
	local int Enemies;

	if(CountStragglers() == 0)
	{
		Log("CoopGame: door hold trap release (no stragglers left), door stays closed");
		FinishHold();
		return;
	}

	// Without the countdown the door closes before the berserkers have come (the first test: released after 1 s): they count on
	// their way, and the door waits for them to come and die
	Enemies = CountEnemies();

	if(Enemies > 0 && !bEnemiesSeen)
	{
		bEnemiesSeen = true;
		Log("CoopGame: door hold trap: " $ Enemies $ " berserkers");
	}

	if(Enemies == 0 && (bEnemiesSeen || Game.Level.TimeSeconds - TrapStart >= TRAP_EMPTY_WAIT))
		OpenTrap("no berserkers left, seen " $ bEnemiesSeen, HostPawn);
}

function OpenTrap(string Reason, Pawn HostPawn)
{
	Log("CoopGame: door hold trap release (" $ Reason $ ") after " $ (Game.Level.TimeSeconds - TrapStart) $ " s, door " $ Door);
	Stage = DH_OpenWay;
	NextHint = 0;
	SendHint(MSG_DOOR_OPEN, false);
	CheckOpenWay(HostPawn);
}

// The door is a door again: open while a living player is near it, closed otherwise, like Trigger10 did
function CheckOpenWay(Pawn HostPawn)
{
	if(CountStragglers() == 0)
	{
		CloseDoor();
		FinishHold();
		return;
	}

	if(IsPlayerNearDoor())
		KeepDoorOpen(HostPawn);
	else if(bDoorTriggered && !IsDoorwayOccupied())
		CloseDoor();
}

function bool IsPlayerNearDoor()
{
	local Controller C;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) != None && C.Pawn != None && C.Pawn.Health > 0 && VSize(C.Pawn.Location - DoorPoint) < DOOR_OPEN_RADIUS)
			return true;
	}

	return false;
}

// What ScriptedTrigger1 asked for while somebody was still in the trap. Same work as the actions: [6] has PermanentlyDisableFactory
function FinishHold()
{
	local Factory F;
	local Actor A;

	Stage = DH_Done;

	if(bFactoryDeferred)
	{
		foreach Game.AllActors(class'Factory', F, DeferredFactoryTag)
			F.GotoState('');
	}

	if(bDestroyDeferred)
	{
		foreach Game.AllActors(class'Actor', A, DeferredDestroyTag)
			A.Destroy();
	}

	Log("CoopGame: door hold done: stopped factories " $ bFactoryDeferred $ ", destroyed " $ DeferredDestroyTag $ " " $ bDestroyDeferred);
}

// One count of ours keeps the door open through Trigger10's touches and untouches. Those can still get the count to zero, hence the repeat
function KeepDoorOpen(Pawn HostPawn)
{
	if(bDoorTriggered && (Door.KeyNum != 0 || Door.bInterpolating))
		return;

	bDoorTriggered = true;
	Door.Trigger(Gate, HostPawn);
}

// Forced: the close normally comes from Trigger10's UnTrigger, and the trigger may be destroyed while it is touched, which may never send it
function CloseDoor()
{
	Door.numTriggerEvents = 0;
	bDoorTriggered = false;

	if(Door.KeyNum != 0 || Door.bInterpolating)
		Door.GotoState('TriggerControl', 'Close');
}

// Living players on the near side, the host isn't one of them: everybody else respawns by the host
function int CountStragglers()
{
	local Controller C;
	local int Count;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) != None && !Game.IsHost(C) && C.Pawn != None && C.Pawn.Health > 0 && InNearBox(C.Pawn.Location))
			++Count;
	}

	return Count;
}

// NOT VERIFIED: the class isn't in the exported scripts, only in the map's factories -- the log line of the release shows the count, "no berserkers left" right after closing means the name is wrong
function int CountEnemies()
{
	local Pawn P;
	local int Count;

	foreach Game.DynamicActors(class'Pawn', P)
	{
		if(P.Health > 0 && P.IsA('TrandoshanSlaverBerserker') && (InNearBox(P.Location) || VSize(P.Location - DoorPoint) < ENEMY_RADIUS))
			++Count;
	}

	return Count;
}

function LogSides()
{
	local Controller C;
	local string Side;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) == None)
			continue;

		if(C.Pawn == None || C.Pawn.Health <= 0)
			Side = "no living pawn";
		else if(InNearBox(C.Pawn.Location))
			Side = "near side";
		else
			Side = "past the door";

		Log("CoopGame: door hold side: " $ PlayerController(C).PlayerReplicationInfo.PlayerName $ " " $ Side $ " pawn " $ C.Pawn);
	}
}

function bool IsHintDue()
{
	if(Game.Level.TimeSeconds < NextHint)
		return false;

	NextHint = Game.Level.TimeSeconds + HINT_INTERVAL;
	return true;
}

// The pointer goes with every hint so that a client who joined or respawned during the hold gets it too
function SendHint(string Hint, bool bPointer)
{
	local Controller C;
	local PlayerController PC;
	local color HintColor;

	HintColor.R = HINT_R;
	HintColor.G = HINT_G;
	HintColor.B = HINT_B;
	HintColor.A = 255;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		PC = PlayerController(C);

		if(PC != None && PC.myHUD != None && Viewport(PC.Player) != None)
			PC.myHUD.AddCriticalMessage(Hint, HINT_INTERVAL, HintColor);
		else if(CoopPlayer(C) != None)
		{
			CoopPlayer(C).ClientCoopCriticalMessage(Hint, HINT_INTERVAL, HintColor);

			if(bPointer)
				Game.SetTrackerOverride(CoopPlayer(C), true, DoorPoint);
		}
	}
}

function HidePointer()
{
	local Controller C;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !Game.IsHost(C))
			Game.SetTrackerOverride(CoopPlayer(C), false);
	}
}
