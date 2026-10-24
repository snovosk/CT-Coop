class CoopGame extends CTGameInfoSP config(ModCoop);

#exec OBJ LOAD FILE="CTGame.u"
#exec OBJ LOAD FILE="CTCharacters.u"
#exec OBJ LOAD FILE="Gameplay.u"

/*
 * CoopGame
 * Host-authoritative campaign coop on a listen server.
 * - The host plays exactly like in single player and keeps the Delta squad.
 * - Clients spawn as additional commandos next to the host, respawn there after dying and follow the host on level changes.
 * - Progress only exists on the host. The engine can't save on a listen server so the checkpoint is the beginning of the current level.
 * Uses native UE2 replication only. The single player level scripts run on the server as usual.
 */

var() config int   MaxCoopPlayers;        // Including the host
var() config float ClientRespawnDelay;    // Seconds before a dead client respawns next to the host
var() config float ClientBleedOutTime;    // Seconds an incapacitated client can wait for a revive before he bleeds out and respawns
var() config bool  bPrivateNetworksOnly;  // Only accept clients from LAN/VPN address ranges
var() config float CatchUpDistance;       // Clients further away from the host are moved to him after CatchUpDelay seconds (0 disables it)
var() config float CatchUpDelay;
var() config float HostReviveWaitTime;    // Seconds a downed host waits for a client to revive him when the whole squad is down (0 = single player behavior)
var() config bool  bClientsTakeOverSquad; // Clients take over squad members (see CheckSquadTakeover)
var() config float TakeOverDistance;
var() config float MaxSpawnWait;          // Seconds a client waits for the host to be free (see IsHostFree) before it is spawned anyway

var CoopFixes Fixes;
var int       NextCoopSkin;
var bool      bCheckedLevel;
var float     HostDownTime;       // Level.TimeSeconds when the host's bleed out was delayed, zero if not waiting
var bool      bAllowHostBleedOut;

// Developer test automation, only active with ?CoopTest=<action> in the URL (see DEVLOG.md)
var string    TestAction;
var float     TestTime;
var int       TestStep;
var ActivateItem TestPanel;
var Pawn      TestPawn;
var bool      bTestPanelHost;
var byte      TestPanelType;
var string    TestOptions;

var array<Pawn> IncapacitatedPawns; // Pawns the clients were told are incapacitated (see SyncIncapacitated)

// See SyncIdleStates
struct SentIdleState
{
	var Pawn P;
	var byte State;
};
var array<SentIdleState> SentIdleStates;
var array<Actor> SyncedMapActors; // See MakeMapActorsRelevant

// See SyncPanelStates
struct SentPanelState
{
	var ActivateItem Item;
	var byte Flags;
	var byte ItemType;
	var Pawn User;
};
var array<SentPanelState> SentPanelStates;

// See SyncMapActorCollision
struct CollisionState
{
	var Actor A;
	var byte Flags;
	var StaticMesh Mesh;
};
var array<CollisionState> CollisionActors;
var float NextIdleStateSync;
var float NextIdleStateResend;

const GAME_CLASS = "ModCoop.CoopGame";

event InitGame(string Options, out string Error)
{
	Super.InitGame(Options, Error);

	// Clients need ModCoop to resolve CoopPlayer and CoopCommando. This normally already happened before the server started listening
	// (CoopHostMenu or CoopExtension). Adding it now only helps for the next level change.
	if(!class'CoopNative'.static.HasServerPackage("ModCoop"))
	{
		Warn("ModCoop is not a server package. Clients won't be able to join until the next level change. Start the coop server from the menu or the host batch file");
		class'CoopNative'.static.AddServerPackage("ModCoop");
	}

	// MaxPlayers is a globalconfig variable of GameInfo. It is only changed in memory and never saved here.
	MaxPlayers = Clamp(GetIntOption(Options, "MaxPlayers", MaxCoopPlayers), 1, 4);
	bPauseable = false;
	bAdminCanPause = false;

	// Drop clients that crashed or lost the connection faster than the System.ini default of 120 seconds
	class'CoopNative'.static.SetNetTimeouts(class'CoopConfig'.default.ServerTimeout, class'CoopConfig'.default.ServerTimeout);
	class'CoopNative'.static.SetNetRates(class'CoopConfig'.default.NetClientRate, class'CoopConfig'.default.NetTickRate);

	TestAction = ParseOption(Options, "CoopTest");
	TestOptions = Options;
	bTestPanelHost = ParseOption(Options, "CoopTestHost") != "";
	TestPanelType = 7; // ActivateItem.AIT_BactaDispenser

	if(ParseOption(Options, "CoopTestPanel") != "")
		TestPanelType = byte(ParseOption(Options, "CoopTestPanel"));
	TestTime = float(ParseOption(Options, "CoopTestDelay"));

	if(TestTime <= 0)
		TestTime = 60;

	Log("CoopGame initialized: MaxPlayers=" $ MaxPlayers $ " NetMode=" $ Level.NetMode);
}

function PostBeginPlay()
{
	local Actor A;

	Super.PostBeginPlay();
	InitFixes();
	SetTimer(1.0, true);

	if(class'CoopConfig'.default.bDebugLog)
	{
		foreach AllActors(class'Actor', A)
		{
			if((A.default.bStatic || A.default.bNoDelete) && !A.bStatic && !A.bNoDelete && A.RemoteRole != ROLE_None)
				Log("CoopDebug: Replicated actor of static class: " $ A $ " Class=" $ A.Class $ " RemoteRole=" $ A.RemoteRole $ " bAlwaysRelevant=" $ A.bAlwaysRelevant);
		}
	}
}

event PostLoadBeginPlay()
{
	Super.PostLoadBeginPlay();
	InitFixes();
	SetTimer(1.0, true);
}

function InitFixes()
{
	if(Fixes == None)
	{
		Fixes = new class'CoopFixes';
		Fixes.Init(self);
	}
}

event Destroyed()
{
	if(Fixes != None)
	{
		Fixes.Deinit();
		Fixes = None;
	}

	Super.Destroyed();
}

/*
 * Login
 */

static function bool IsPrivateAddress(string Address)
{
	local int A, B;
	local int Dot;

	Dot = InStr(Address, ".");

	if(Dot == -1)
		return false;

	A = int(Left(Address, Dot));
	Address = Mid(Address, Dot + 1);
	Dot = InStr(Address, ".");
	B = int(Left(Address, Dot));

	return A == 10 ||                          // LAN, ZeroTier
	       A == 127 ||                         // Loopback
	       (A == 172 && B >= 16 && B <= 31) || // LAN, ZeroTier
	       (A == 192 && B == 168) ||           // LAN
	       A == 25 || A == 26 ||               // Hamachi, Radmin VPN
	       (A == 100 && B >= 64 && B <= 127);  // CGNAT range used by Tailscale
}

event PreLogin(string Options, string Address, out string Error, out string FailCode)
{
	local string ClientVersion;

	class'CoopNative'.static.ReleaseAllCDKeys(); // See Timer
	Super.PreLogin(Options, Address, Error, FailCode);

	ClientVersion = ParseOption(Options, "CoopVersion");
	Log("CoopGame: Login from " $ Address $ " ModCoop version '" $ ClientVersion $ "' (host: " $ class'CoopConfig'.static.Version() $ ")" $ " Error='" $ Error $ "'");

	// Clients that connect without the option (old versions, plain 'open <ip>' or level changes) are not checked here
	if(Error == "" && ClientVersion != "" && ClientVersion != class'CoopConfig'.static.Version())
		Error = "ModCoop version mismatch: the host has " $ class'CoopConfig'.static.Version() $ ", you have " $ ClientVersion $ ". Both players need the same archive.";

	if(Error == "" && bPrivateNetworksOnly && !IsPrivateAddress(Address))
	{
		Log("CoopGame: Rejected " $ Address $ " (bPrivateNetworksOnly)");
		Error = "This coop server only accepts LAN/VPN addresses";
	}
}

event PostLogin(PlayerController NewPlayer)
{
	Super.PostLogin(NewPlayer);

	// Otherwise a second game instance on the same PC is rejected because of the duplicate CD key
	class'CoopNative'.static.ReleaseAllCDKeys();

	if(!IsHost(NewPlayer))
	{
		Log("CoopGame: Client joined: " $ NewPlayer.PlayerReplicationInfo.PlayerName);
		Broadcast(self, NewPlayer.PlayerReplicationInfo.PlayerName $ " joined the squad");
	}
}

function Logout(Controller Exiting)
{
	if(PlayerController(Exiting) != None && !IsHost(PlayerController(Exiting)))
	{
		Broadcast(self, Exiting.PlayerReplicationInfo.PlayerName $ " left the squad");

		// Remove the pawn so it doesn't stand around without a player
		if(Exiting.Pawn != None)
			Exiting.Pawn.Destroy();
	}

	Super.Logout(Exiting);
}

/*
 * Spawning
 */

function bool IsHost(Controller C)
{
	return PlayerController(C) != None && Viewport(PlayerController(C).Player) != None;
}

function PlayerController GetHost()
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(IsHost(C))
			return PlayerController(C);
	}

	return None;
}

function RestartPlayer(Controller aPlayer)
{
	local CoopPlayer CP;

	CP = CoopPlayer(aPlayer);

	if(CP == None || IsHost(CP))
	{
		Super.RestartPlayer(aPlayer);
		return;
	}

	if(CP.Pawn != None && !CP.Pawn.bDeleteMe && CP.Pawn.Health > 0)
		return; // Already alive

	if(!SpawnClient(CP))
	{
		// Try again from the timer (e.g. the host is still loading or there is no free space right now)
		Log("CoopGame: Can't spawn client " $ CP.PlayerReplicationInfo.PlayerName $ " right now, retrying");
		CP.DeadTime = Level.TimeSeconds;
	}
}

// Finds a free spot around a location from which the location is visible
function bool FindSpawnLocation(vector Center, rotator Dir, out vector OutLocation)
{
	local int Ring, i;
	local rotator R;
	local vector Test;
	local vector HitLocation, HitNormal;

	Dir.Pitch = 0;
	Dir.Roll = 0;

	for(Ring = 1; Ring <= 4; ++Ring)
	{
		for(i = 0; i < 8; ++i)
		{
			// Prefer the spots behind the host
			R = Dir;
			R.Yaw += 32768 + (i / 2) * 8192 * (1 - 2 * (i % 2));
			Test = Center + vector(R) * (Ring * 100.0);

			if(!FastTrace(Test, Center))
				continue;

			// Make sure there is ground below the spot
			if(Trace(HitLocation, HitNormal, Test - vect(0, 0, 300), Test, false) == None)
				continue;

			OutLocation = Test;
			return true;
		}
	}

	return false;
}

/*
 * False while the host is moved by a level script, e.g. riding a gunship during an intro or being interpolated during a cutscene.
 * Clients are not spawned/moved next to the host at that time since they would be left behind in mid air.
 */
function bool IsHostFree(PlayerController Host)
{
	local Pawn P;

	if(Host == None || Host.Pawn == None || Host.Pawn.bDeleteMe || Host.Pawn.Health <= 0 || Host.Pawn.bIncapacitated)
		return false;

	P = Host.Pawn;

	if(P.Physics != PHYS_Walking)
		return false;

	return P.Base == None || P.Base.bWorldGeometry || P.Base.bStatic;
}

function bool SpawnClient(CoopPlayer CP)
{
	local PlayerController Host;
	local NavigationPoint StartSpot;
	local vector SpawnLocation;
	local rotator SpawnRotation;
	local Pawn P;

	Host = GetHost();

	// A client that plays a squad member starts as it (e.g. the next level)
	P = FindAssignedMember(CP);

	if(P != None)
	{
		TakeOver(CP, P, false);
		CP.SpawnWaitStart = 0;
		return true;
	}

	// The squad member is in the level but not free yet (e.g. a script at the start of the level): wait for it a while
	// instead of showing the client its own commando for a moment
	P = FindAssignedMemberInLevel(CP);

	if(P != None)
	{
		if(CP.SpawnWaitStart == 0)
			CP.SpawnWaitStart = Level.TimeSeconds;

		if(Level.TimeSeconds - CP.SpawnWaitStart < MaxSpawnWait)
		{
			// Already look through the squad member's eyes
			if(CP.ViewTarget != P)
			{
				CP.SetViewTarget(P);
				CP.ClientSetViewTarget(P);
				CP.bBehindView = false;
				CP.ClientSetBehindView(false);
			}

			return false;
		}

		P = None;
	}

	if(Host != None && Host.Pawn != None && !Host.Pawn.bDeleteMe)
	{
		if(CP.SpawnWaitStart == 0)
			CP.SpawnWaitStart = Level.TimeSeconds;

		// Wait until the host stands on the ground, but not forever
		if(!IsHostFree(Host) && Level.TimeSeconds - CP.SpawnWaitStart < MaxSpawnWait)
		{
			Log("CoopGame: Waiting for the host to be free before spawning a client: Physics=" $ Host.Pawn.Physics $ " Base=" $ Host.Pawn.Base $ " Health=" $ Host.Pawn.Health);
			return false;
		}
		SpawnRotation = Host.Pawn.Rotation;

		if(FindSpawnLocation(Host.Pawn.Location, SpawnRotation, SpawnLocation))
			P = Spawn(class'CoopCommando',,, SpawnLocation, SpawnRotation);
	}

	if(P == None) // Fall back to the player starts
	{
		StartSpot = FindPlayerStart(CP, 1);

		if(StartSpot != None && FindSpawnLocation(StartSpot.Location, StartSpot.Rotation, SpawnLocation))
			P = Spawn(class'CoopCommando',,, SpawnLocation, StartSpot.Rotation);
	}

	if(P == None)
		return false;

	SpawnRotation = P.Rotation;
	SpawnRotation.Pitch = 0;
	SpawnRotation.Roll = 0;

	P.SetTeamIndex(1); // Player friendly team
	CP.Possess(P);
	CP.PawnClass = P.Class;
	CP.ClientSetRotation(SpawnRotation);
	SetPlayerDefaults(P);
	P.AddDefaultInventory();

	if(CoopCommando(P).CoopSkin == 0)
	{
		NextCoopSkin = NextCoopSkin % 4 + 1;
		CoopCommando(P).SetCoopSkin(NextCoopSkin);
	}

	CP.IncapacitatedTime = 0;
	CP.DeadTime = 0;
	CP.SpawnWaitStart = 0;

	Log("CoopGame: Spawned " $ CP.PlayerReplicationInfo.PlayerName $ " at " $ P.Location);

	return true;
}

/*
 * Periodic server side bookkeeping
 */

function Timer()
{
	local Controller C;
	local CoopPlayer CP;

	InitFixes();
	CleanUpOrphans();

	if(!bCheckedLevel)
		CheckLevel();

	if(HostDownTime != 0)
		CheckHostDown();

	if(TestAction != "")
		TickTest();

	SyncIncapacitated();
	CheckSceneWatch();
	CheckSquadTakeover();

	if(class'CoopConfig'.default.bDebugLog)
		LogPawns();

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || IsHost(CP))
			continue;

		if(CP.Pawn == None || CP.Pawn.bDeleteMe || (CP.Pawn.Health <= 0 && !CP.Pawn.bIncapacitated))
		{
			// Dead: respawn after a short delay
			if(CP.DeadTime == 0)
				CP.DeadTime = Level.TimeSeconds;
			else if(Level.TimeSeconds - CP.DeadTime >= ClientRespawnDelay)
				RestartPlayer(CP);
		}
		else if(CP.Pawn.bIncapacitated)
		{
			// Incapacitated: the squad doesn't revive clients so they bleed out after a while unless another player revives them
			if(CP.IncapacitatedTime == 0)
			{
				CP.IncapacitatedTime = Level.TimeSeconds;
				CP.ClientCoopMessage("You are down! Wait for another player to revive you.");
			}
			else if(!CP.Pawn.bBeingRevivedByPlayer && Level.TimeSeconds - CP.IncapacitatedTime >= ClientBleedOutTime)
			{
				CP.IncapacitatedTime = 0;
				CP.Pawn.BleedOut();
			}
		}
		else
		{
			CP.IncapacitatedTime = 0;
			CP.DeadTime = 0;
			CheckCatchUp(CP);
		}

		SendMapActorDisplay(CP);

		// After a takeover the new inventory may arrive on the client after it tried to switch to it (see TakeOver)
		if(CP.Pawn != None && CoopCommando(CP.Pawn) == None && CP.Pawn.Weapon == None && CP.Pawn.Health > 0 && !CP.Pawn.bIncapacitated &&
		   Level.TimeSeconds - CP.TakeoverTime < 10)
			CP.ClientSwitchToBestWeapon();
	}
}

/*
 * The native replication of pawns doesn't send bIncapacitated to clients (the script replication block of Pawn has no effect).
 * Clients therefore never saw anybody as incapacitated and could not revive the host or squad members with the bacta healer.
 * The state is sent to the clients through their controllers instead. Incapacitated pawns are sent again every second so
 * clients that joined later or for which the pawn only just became relevant get it too.
 */
function SyncIncapacitated()
{
	local Pawn P;
	local int i;

	for(i = IncapacitatedPawns.Length - 1; i >= 0; --i)
	{
		P = IncapacitatedPawns[i];

		if(P == None || P.bDeleteMe || !P.bIncapacitated)
		{
			if(P != None && !P.bDeleteMe)
				SendIncapacitated(P, false);

			IncapacitatedPawns.Remove(i, 1);
		}
	}

	foreach DynamicActors(class'Pawn', P)
	{
		if(!P.bIncapacitated)
			continue;

		for(i = 0; i < IncapacitatedPawns.Length; ++i)
		{
			if(IncapacitatedPawns[i] == P)
				break;
		}

		if(i == IncapacitatedPawns.Length)
			IncapacitatedPawns[i] = P;

		SendIncapacitated(P, true);
	}
}

/*
 * The AI sets the stance of its pawn (CurrentIdleState: relaxed, alert, berserk, on a turret...) on the server. It is not replicated
 * and it selects the breathe, walk and run animations: on clients every NPC stayed in its default stance, e.g. droids walked around
 * relaxed with lowered weapons in the middle of a fight. Changes are sent to the clients and everything again every few seconds
 * for clients that joined later or for which a pawn only just became relevant.
 */
event Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);

	if(Level.TimeSeconds >= NextIdleStateSync)
	{
		NextIdleStateSync = Level.TimeSeconds + 0.2;
		SyncIdleStates(Level.TimeSeconds >= NextIdleStateResend);
		SyncPanelStates(Level.TimeSeconds >= NextIdleStateResend);
		SyncMapActorCollision();
		CheckDetonations();

		if(Level.TimeSeconds >= NextIdleStateResend)
			NextIdleStateResend = Level.TimeSeconds + 3.0;
	}
}

function SyncIdleStates(bool bResendAll)
{
	local Pawn P;
	local int i;
	local Controller C;
	local bool bHasClient;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
		{
			bHasClient = true;
			break;
		}
	}

	for(i = SentIdleStates.Length - 1; i >= 0; --i)
	{
		if(SentIdleStates[i].P == None || SentIdleStates[i].P.bDeleteMe)
			SentIdleStates.Remove(i, 1);
	}

	if(!bHasClient)
		return;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.Controller == None || PlayerController(P.Controller) != None || P.Health <= 0)
			continue;

		for(i = 0; i < SentIdleStates.Length; ++i)
		{
			if(SentIdleStates[i].P == P)
				break;
		}

		if(i == SentIdleStates.Length)
		{
			SentIdleStates.Length = i + 1;
			SentIdleStates[i].P = P;
			SentIdleStates[i].State = P.default.CurrentIdleState;
		}

		if(SentIdleStates[i].State != P.CurrentIdleState || bResendAll)
		{
			SentIdleStates[i].State = P.CurrentIdleState;

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C))
					CoopPlayer(C).ClientCoopSetIdleState(P, P.CurrentIdleState);
			}
		}
	}
}

/*
 * Scripts enable and disable panels (state code of ActivateItem subclasses, e.g. a hack door gets usable when the squad reaches it)
 * only on the server. Their flags are not replicated: a client's copy kept its initial state and the client could not use panels
 * that became usable later (or tried to use finished ones). Changes are sent like the idle states (SyncIdleStates).
 */
function SyncPanelStates(bool bResendAll)
{
	local ActivateItem Item;
	local int i;
	local byte Flags;
	local Controller C;
	local Pawn UserPawn;

	foreach DynamicActors(class'ActivateItem', Item)
	{
		if(Item.RemoteRole == ROLE_None)
			continue;

		Flags = 0;

		if(Item.bIsUsable)
			Flags = Flags | 1;

		if(Item.bIsUsableByPlayer)
			Flags = Flags | 2;

		if(Item.bActivating)
			Flags = Flags | 4;

		if(Item.bActivated)
			Flags = Flags | 8;

		if(Item.bPlayerActivated)
			Flags = Flags | 16;

		if(Item.User != None)
			UserPawn = Item.User.Pawn;
		else
			UserPawn = None;

		for(i = 0; i < SentPanelStates.Length; ++i)
		{
			if(SentPanelStates[i].Item == Item)
				break;
		}

		if(i == SentPanelStates.Length)
		{
			SentPanelStates.Length = i + 1;
			SentPanelStates[i].Item = Item;
			SentPanelStates[i].Flags = 255; // Always send the first time
		}

		// E.g. an armed demolition charge becomes a plunger (AIT_Plunger) for the player that placed it
		// Progress bars and timers while something is being set up or counts down
		if(Item.bActivating || (Item.bActivated && Item.DurationRemaining > 0))
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C))
					CoopPlayer(C).ClientCoopSetPanelProgress(Item, Item.FractionComplete, Item.DurationRemaining, Item.ElapseSetupTime);
			}
		}

		if(SentPanelStates[i].Flags != Flags || SentPanelStates[i].ItemType != Item.ActivateItemType || SentPanelStates[i].User != UserPawn || bResendAll)
		{
			SentPanelStates[i].Flags = Flags;
			SentPanelStates[i].ItemType = Item.ActivateItemType;
			SentPanelStates[i].User = UserPawn;

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C))
					CoopPlayer(C).ClientCoopSetPanelState(Item, Flags, Item.ActivateItemType, UserPawn);
			}
		}
	}
}

// See CoopPlayer.ServerCoopStartHandSignal
function CheckDetonations()
{
	local Controller C;
	local CoopPlayer CP;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP != None && CP.PendingDetonation != None && Level.TimeSeconds >= CP.DetonationTime)
		{
			if(!CP.PendingDetonation.bDeleteMe && CP.PendingDetonation.ActivateItemType == AIT_Plunger)
				CP.PendingDetonation.GotoState('Explode');

			CP.PendingDetonation = None;
		}
	}
}

/*
 * Destroyed props switch off their collision and change their mesh on the server (Prop.PropDestroyed). The replicated flags don't
 * update the collision on clients: they bumped into invisible walls where objects had been. Changes are sent to the clients which
 * apply them properly (SetCollision, SetStaticMesh).
 */
function SyncMapActorCollision()
{
	local int i;
	local byte Flags;
	local Actor A;
	local Controller C;

	for(i = 0; i < CollisionActors.Length; ++i)
	{
		A = CollisionActors[i].A;

		if(A == None || A.bDeleteMe)
			continue;

		Flags = 0;

		if(A.bCollideActors)
			Flags = Flags | 1;

		if(A.bBlockActors)
			Flags = Flags | 2;

		if(A.bBlockPlayers)
			Flags = Flags | 4;

		if(A.bHidden)
			Flags = Flags | 8;

		if(Flags == CollisionActors[i].Flags && A.StaticMesh == CollisionActors[i].Mesh)
			continue;

		// The first time only remember the state: clients get the initial state with the actor itself
		if(CollisionActors[i].Flags == 255)
		{
			CollisionActors[i].Flags = Flags;
			CollisionActors[i].Mesh = A.StaticMesh;
			continue;
		}

		CollisionActors[i].Flags = Flags;
		CollisionActors[i].Mesh = A.StaticMesh;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				CoopPlayer(C).ClientCoopSetActorCollision(A, A.bCollideActors, A.bBlockActors, A.bBlockPlayers, A.StaticMesh, A.bHidden);
		}
	}
}

function SendIncapacitated(Pawn P, bool bIncapacitated)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopSetIncapacitated(P, bIncapacitated);
	}
}

function bool HasLivingClient()
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated)
			return true;
	}

	return false;
}

// Called from CoopFixes when a pawn is about to bleed out
function bool ShouldDelayHostBleedOut(Pawn P)
{
	local PlayerController Host;

	Host = GetHost();

	if(bAllowHostBleedOut || HostReviveWaitTime <= 0 || Host == None || P != Host.Pawn || !P.bIncapacitated || !HasLivingClient())
		return false;

	if(HostDownTime == 0)
	{
		HostDownTime = Level.TimeSeconds;
		Log("CoopGame: Host is down, waiting for a client to revive him");
		Broadcast(self, "The host is down! Revive him: look at him and hold USE.");
	}

	return Level.TimeSeconds - HostDownTime < HostReviveWaitTime;
}

function CheckHostDown()
{
	local PlayerController Host;

	Host = GetHost();

	if(Host == None || Host.Pawn == None || !Host.Pawn.bIncapacitated)
	{
		HostDownTime = 0; // Revived
		return;
	}

	if(!HasLivingClient() || Level.TimeSeconds - HostDownTime >= HostReviveWaitTime)
	{
		Log("CoopGame: Nobody revived the host");
		HostDownTime = 0;
		bAllowHostBleedOut = true;
		Host.Pawn.BleedOut();
		bAllowHostBleedOut = false;
	}
}

// Leaves levels that can't be played in coop (see SkipBriefing)
/*
 * Dynamic static meshes placed in the map (e.g. gun positions and other objects that are destroyed or shown by scripts) are
 * replicated, so clients delete their own copies when loading the map. The server only sends an actor while it considers it
 * relevant, which for these is a visibility trace to the actor's origin. The origin of large meshes is often inside other geometry:
 * clients saw objects appear late or not at all. They are made always relevant.
 * DrawScale3D, PrePivot and Skins are not replicated: a client created these from the class defaults and e.g. a gun position had
 * a completely different shape. The actors that need it are remembered and sent to the clients (SendMapActorDisplay).
 * Panels (ActivateItem: bacta dispensers, hack terminals, demolition spots) lose the links that are only set up on the server when
 * the map starts (their SquadMarker and the marker's Anchor, NavPts, the list of bacta dispensers): clients could not use them.
 */
function MakeMapActorsRelevant()
{
	local Actor A;
	local ActivateItem Item;
	local int Num, i;

	foreach AllActors(class'Actor', A)
	{
		if(A.DrawType == DT_StaticMesh && !A.bStatic && !A.bOnlyRelevantToOwner && A.RemoteRole != ROLE_None && Pawn(A) == None && A.Owner == None)
		{
			if(!A.bAlwaysRelevant)
			{
				A.bAlwaysRelevant = true;
				++Num;
			}

			i = CollisionActors.Length;
			CollisionActors.Length = i + 1;
			CollisionActors[i].A = A;
			CollisionActors[i].Flags = 255; // Not known yet (see SyncMapActorCollision)
			CollisionActors[i].Mesh = A.StaticMesh;

			if(A.DrawScale3D != A.default.DrawScale3D || A.PrePivot != A.default.PrePivot || A.Skins.Length > 0)
				SyncedMapActors[SyncedMapActors.Length] = A;
		}
	}

	foreach AllActors(class'ActivateItem', Item)
	{
		if(Item.RemoteRole == ROLE_None || Item.bStatic)
			continue;

		if(!Item.bAlwaysRelevant)
		{
			Item.bAlwaysRelevant = true;
			++Num;
		}

		for(i = 0; i < SyncedMapActors.Length; ++i)
		{
			if(SyncedMapActors[i] == Item)
				break;
		}

		if(i == SyncedMapActors.Length)
			SyncedMapActors[i] = Item;
	}

	Log("CoopGame: Made " $ Num $ " map actors always relevant, " $ SyncedMapActors.Length $ " are sent to clients (display properties, panel links)");
}

// Called every second: sends up to 30 of SyncedMapActors to the client, ten passes over all of them once the client has a pawn
// (unreliable, sent while the client is still loading or before an actor exists on the client the call is lost or A is None)
function SendMapActorDisplay(CoopPlayer CP)
{
	local int i;
	local Actor A;
	local Material Skin0, Skin1;
	local ActivateItem Item;
	local NavigationPoint N0, N1;

	if(CP.Pawn == None || CP.DisplaySyncPasses >= 10 || SyncedMapActors.Length == 0)
		return;

	for(i = 0; i < 30; ++i)
	{
		if(CP.DisplaySyncIndex >= SyncedMapActors.Length)
		{
			CP.DisplaySyncIndex = 0;
			++CP.DisplaySyncPasses;
			return;
		}

		A = SyncedMapActors[CP.DisplaySyncIndex++];

		if(A == None || A.bDeleteMe)
			continue;

		Skin0 = None;
		Skin1 = None;

		if(A.Skins.Length > 0)
			Skin0 = A.Skins[0];

		if(A.Skins.Length > 1)
			Skin1 = A.Skins[1];

		if(A.DrawScale3D != A.default.DrawScale3D || A.PrePivot != A.default.PrePivot || A.Skins.Length > 0)
			CP.ClientCoopSetActorDisplay(A, A.DrawScale3D.X, A.DrawScale3D.Y, A.DrawScale3D.Z, A.PrePivot, Skin0, Skin1);

		Item = ActivateItem(A);

		if(Item != None)
		{
			N0 = None;
			N1 = None;

			if(Item.NavPts.Length > 0)
				N0 = Item.NavPts[0];

			if(Item.NavPts.Length > 1)
				N1 = Item.NavPts[1];

			CP.ClientCoopSetPanelLinks(Item, Item.SquadMarker, N0, N1, Item.bIsUsableByPlayer);
		}
	}
}

function CheckLevel()
{
	local PlayerController Host;
	local string Map;

	Host = GetHost();

	if(Host == None)
		return;

	bCheckedLevel = true;
	MakeMapActorsRelevant();
	Host.GetCurrentMapName(Map);

	if(SkipBriefing(Map) != Map)
		CoopTravel(Map);
}

// Moves a client that got separated from the host (usually by a level script that only moves the host) next to the host
function CheckCatchUp(CoopPlayer CP)
{
	local PlayerController Host;

	if(CatchUpDistance <= 0)
		return;

	Host = GetHost();

	if(!IsHostFree(Host) || VSize(CP.Pawn.Location - Host.Pawn.Location) < CatchUpDistance)
	{
		CP.FarFromHostTime = 0;
		return;
	}

	if(CP.FarFromHostTime == 0)
	{
		CP.FarFromHostTime = Level.TimeSeconds;
		return;
	}

	if(Level.TimeSeconds - CP.FarFromHostTime >= CatchUpDelay)
	{
		CP.FarFromHostTime = 0;

		if(TeleportToHost(CP))
			CP.ClientCoopMessage("You were moved to the host because you got separated.");
	}
}

function bool TeleportToHost(CoopPlayer CP)
{
	local PlayerController Host;
	local vector NewLocation;
	local rotator NewRotation;

	Host = GetHost();

	if(CP.Pawn == None || CP.Pawn.bIncapacitated || !IsHostFree(Host))
		return false;

	NewRotation = Host.Pawn.Rotation;
	NewRotation.Pitch = 0;
	NewRotation.Roll = 0;

	if(!FindSpawnLocation(Host.Pawn.Location, NewRotation, NewLocation) || !CP.Pawn.SetLocation(NewLocation))
		return false;

	CP.Pawn.Velocity = vect(0,0,0);
	CP.Pawn.SetPhysics(PHYS_Falling);
	CP.ClientSetLocation(NewLocation, NewRotation);
	Log("CoopGame: Moved " $ CP.PlayerReplicationInfo.PlayerName $ " to the host");

	return true;
}

function LogPawns()
{
	local Pawn P;
	local int Num;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.Health > 0)
			++Num;

		if(P.IsHumanControlled() || P.Squad != None)
			Log("CoopDebug: Server " $ P.Class.Name $ " " $ P.Location $ " Health=" $ P.Health $ " Incap=" $ P.bIncapacitated);
	}

	Log("CoopDebug: Server living pawns=" $ Num);
}

// Developer test automation. The timer runs once per second.
function TickTest()
{
	local PlayerController Host;
	local Controller C;
	local string NextMap;
	local rotator R;
	local Pawn P, P2;
	local Controller C2;
	local Actor A2;
	local int i;
	local ActivateItem A;

	if(Level.TimeSeconds < TestTime)
		return;

	Host = GetHost();
	Log("CoopTest: Executing step " $ TestStep $ " of '" $ TestAction $ "'");

	if(TestAction ~= "travel" && TestStep == 0)
	{
		Host.GetCurrentMapName(NextMap);
		Host.GetNextLevel(Host.GetLevelIndex(NextMap), NextMap);
		CoopTravel(NextMap);
	}
	else if(TestAction ~= "restart" && TestStep == 0)
	{
		CoopRestartLevel();
	}
	else if(TestAction ~= "checkpoint")
	{
		if(TestStep == 0)
		{
			Log("CoopTest: Host reloads the checkpoint");
			Host.Reload();
		}
	}
	else if(TestAction ~= "clientdeath" && TestStep == 0)
	{
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				Log("CoopTest: Killing " $ C.PlayerReplicationInfo.PlayerName);
				C.Pawn.Died(None, class'DamageBleedOut', C.Pawn.Location);
			}
		}
	}
	else if(TestAction ~= "revive")
	{
		// Checks that the host can revive an incapacitated client: 0 = move client to host, 1 = incapacitate, 2 = look at client and press use, 3 = check
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None || Host == None || Host.Pawn == None)
		{
			Log("CoopTest: revive: no client or host pawn");
			TestAction = "";
			return;
		}

		if(TestStep == 0)
		{
			TeleportToHost(CoopPlayer(C));
		}
		else if(TestStep == 1)
		{
			Log("CoopTest: Incapacitating " $ C.PlayerReplicationInfo.PlayerName $ " Distance=" $ VSize(C.Pawn.Location - Host.Pawn.Location));
			C.Pawn.TakeDamage(1000, None, C.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
		}
		else if(TestStep == 2)
		{
			Host.SetRotation(rotator(C.Pawn.Location - vect(0,0,60) - (Host.Pawn.Location + Host.Pawn.EyePosition())));
			Log("CoopTest: Client incapacitated=" $ C.Pawn.bIncapacitated $ " Host TargetType=" $ Host.TargetType $ " Target=" $ Host.Target);
			Host.Use();
		}
		else if(TestStep < 15)
		{
			Host.SetRotation(rotator(C.Pawn.Location - vect(0,0,60) - (Host.Pawn.Location + Host.Pawn.EyePosition())));
			Log("CoopTest: Reviving: Host state=" $ Host.GetStateName() $ " TargetType=" $ Host.TargetType $ " Client incapacitated=" $ C.Pawn.bIncapacitated);
			Host.bUse = true; // Simulate holding the use key

			if(!Host.IsInState('UsingItem'))
				Host.Use();

			if(!C.Pawn.bIncapacitated)
			{
				Log("CoopTest: revive SUCCEEDED");
				Host.StopUse();
				TestAction = "";
			}
		}
		else
		{
			Log("CoopTest: revive FAILED");
			Host.StopUse();
			TestAction = "";
		}

		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return;
	}
	else if(TestAction ~= "jump")
	{
		// Clients jump in front of the host so the animation of a remote player can be watched in the host's window
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				if(TestStep == 0)
				{
					// In front of the host, far enough to see the whole model
					R = Host.Pawn.Rotation;
					R.Pitch = 0;
					C.Pawn.SetLocation(Host.Pawn.Location + vector(R) * 400);
					C.Pawn.SetPhysics(PHYS_Falling);
				}

				Host.SetRotation(rotator(C.Pawn.Location - (Host.Pawn.Location + Host.Pawn.EyePosition())));

				if(TestStep > 0 && C.Pawn.Physics == PHYS_Walking)
				{
					Log("CoopTest: Jump " $ C.Pawn);
					C.Pawn.DoJump(false);
				}
			}
		}

		if(TestStep < 8)
		{
			TestTime = Level.TimeSeconds + 2;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "hostjump")
	{
		// The host jumps in front of a client so the animation of a simulated proxy can be watched in the client's window
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				if(TestStep == 0)
				{
					// Same spot as in the jump test which is known to be free
					R = Host.Pawn.Rotation;
					R.Pitch = 0;
					C.Pawn.SetLocation(Host.Pawn.Location + vector(R) * 400);
					C.Pawn.SetPhysics(PHYS_Falling);
				}

				R = rotator(Host.Pawn.Location - C.Pawn.Location);
				R.Pitch = 0;
				C.ClientSetRotation(R);
				if(P != None)
					Host.SetRotation(rotator(P.Location - Host.Pawn.Location));

				if(TestStep > 0 && Host.Pawn.Physics == PHYS_Walking)
				{
					Log("CoopTest: Jump " $ Host.Pawn);
					Host.Pawn.DoJump(false);
				}

				break;
			}
		}

		if(TestStep < 8)
		{
			TestTime = Level.TimeSeconds + 2;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "clientrevive")
	{
		// The client revives the incapacitated host. Looking at the host and pressing use has to be done in the client window (test script).
		// 0 = move client to host, 1 = incapacitate host, 2..31 = check every second
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None || Host == None || Host.Pawn == None)
		{
			Log("CoopTest: clientrevive: no client or host pawn");
			TestAction = "";
			return;
		}

		if(TestStep == 0)
		{
			TeleportToHost(CoopPlayer(C));
		}
		else if(TestStep == 1)
		{
			Log("CoopTest: Incapacitating host Distance=" $ VSize(C.Pawn.Location - Host.Pawn.Location));
			// The squad would revive the host itself
			foreach DynamicActors(class'Pawn', P)
			{
				if(P != Host.Pawn && P != C.Pawn && P.Squad != None && P.Squad == Host.Pawn.Squad)
				{
					P.TakeDamage(1000, None, P.Location, vect(0,0,0), class'CTDamageBallistic');
					Log("CoopTest: Squad member " $ P $ " incapacitated=" $ P.bIncapacitated $ " Health=" $ P.Health);
				}
			}
			Host.Pawn.TakeDamage(1000, None, Host.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
		}
		else if(TestStep < 32)
		{

			Log("CoopTest: clientrevive: Host incapacitated=" $ Host.Pawn.bIncapacitated $ " Health=" $ Host.Pawn.Health $
			    " Client state=" $ C.GetStateName() $ " TargetType=" $ CoopPlayer(C).TargetType $ " Target=" $ CoopPlayer(C).Target $
			    " Weapon=" $ C.Pawn.Weapon $ " WeaponState=" $ C.Pawn.Weapon.GetStateName());

			if(TestStep > 2 && !Host.Pawn.bIncapacitated)
			{
				Log("CoopTest: clientrevive SUCCEEDED");
				TestAction = "";
			}
		}
		else
		{
			Log("CoopTest: clientrevive FAILED");
			TestAction = "";
		}

		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return;
	}
	else if(TestAction ~= "panel")
	{
		// The client uses the nearest bacta dispenser (or TestPanelType). The use key has to be held in the client window (test script).
		// 0 = hurt the client and move it in front of the panel, 1..20 = log health and panel state every second
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(bTestPanelHost)
			C = Host;

		if(C == None)
			return;

		if(TestStep == 0)
		{
			TestPanel = None;

			foreach DynamicActors(class'ActivateItem', A)
				Log("CoopTest: panel: available " $ A $ " Type=" $ A.ActivateItemType $ " Usable=" $ A.bIsUsable $ " ByPlayer=" $ A.bIsUsableByPlayer $ " State=" $ A.GetStateName() $ " at " $ A.Location);

			foreach DynamicActors(class'ActivateItem', A)
			{
				if(A.ActivateItemType == TestPanelType && A.bIsUsable && (TestPanel == None || VSize(A.Location - C.Pawn.Location) < VSize(TestPanel.Location - C.Pawn.Location)))
					TestPanel = A;
			}

			if(TestPanel == None && ParseOption(TestOptions, "CoopTestForce") != "")
			{
				// Doors are only usable once a script unlocks them
				foreach DynamicActors(class'ActivateItem', A)
				{
					if(A.ActivateItemType == TestPanelType && (TestPanel == None || VSize(A.Location - C.Pawn.Location) < VSize(TestPanel.Location - C.Pawn.Location)))
						TestPanel = A;
				}

				if(TestPanel != None)
				{
					TestPanel.bIsUsableByPlayer = true;
					if(ParseOption(TestOptions, "CoopTestForce") ~= "Unplaced")
						TestPanel.GotoState('Unplaced');
					else
						TestPanel.GotoState('Locked');
					Log("CoopTest: panel: forced " $ TestPanel $ " into state " $ TestPanel.GetStateName() $ " Usable=" $ TestPanel.bIsUsable);
				}
			}

			if(TestPanel == None)
			{
				Log("CoopTest: panel: no usable panel of type " $ TestPanelType);
				TestAction = "";
				return;
			}

			if(TestPanelType == 7)
				C.Pawn.Health = 40;

			C.bGodMode = true;
			R = TestPanel.Rotation;
			R.Pitch = 0;
			C.Pawn.SetLocation(TestPanel.Location + vector(R) * 70 + vect(0,0,20));
			R = rotator(TestPanel.Location - C.Pawn.Location);
			R.Pitch = 0;
			C.ClientSetRotation(R);

			if(C == Host)
				C.SetRotation(R);

			Log("CoopTest: panel: " $ TestPanel $ " at " $ TestPanel.Location $ " client at " $ C.Pawn.Location);
		}
		else
		{
			Log("CoopTest: panel: Health=" $ C.Pawn.Health $ " ClientState=" $ C.GetStateName() $ " TargetType=" $ CoopPlayer(C).TargetType $ " Target=" $ CoopPlayer(C).Target $ " Weapon=" $ C.Pawn.Weapon $ " HandSignalTarget=" $ CoopPlayer(C).HandSignalTarget $ " Activating=" $ TestPanel.bActivating $ " Used=" $ TestPanel.bUsed $ " PanelState=" $ TestPanel.GetStateName() $ " Fraction=" $ TestPanel.FractionComplete);
		}

		if(TestStep < 20)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "pickup")
	{
		// GEO_01A: host and client go to the wounded squad member, the host revives him (holds use), then the takeover should happen
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(TestStep == 0)
		{
			foreach DynamicActors(class'Pawn', P2)
			{
				if(P2.IsA('CloneCommando') && PlayerController(P2.Controller) == None && P2.Squad == None)
					P = P2;
			}

			if(P == None || C == None)
			{
				Log("CoopTest: pickup: no squad member to pick up");
				TestAction = "";
				return;
			}

			TestPawn = P;
			R = P.Rotation;
			R.Pitch = 0;
			C.Pawn.SetLocation(P.Location - vector(R) * 140 + vect(0,0,60));

			// The host walks into the trigger of the intro scene, later into the one that adds the squad member to the squad
			foreach AllActors(class'Actor', A2)
			{
				if(A2.IsA('Trigger') && string(A2.Event) ~= "62Intro")
				{
					Host.Pawn.SetLocation(A2.Location + vect(0,0,20));
					Log("CoopTest: pickup: host moved into " $ A2 $ " Event=" $ A2.Event);
				}
			}
			Log("CoopTest: pickup: " $ P $ " incapacitated=" $ P.bIncapacitated $ " Controller=" $ P.Controller.Class $ " State=" $ P.Controller.GetStateName() $ " PawnState=" $ P.GetStateName() $ " Tag=" $ P.Tag $ " Event=" $ P.Event);

			foreach AllActors(class'Actor', A2)
			{
				if((A2.IsA('Triggers') || A2.IsA('Volume') || A2.IsA('ScriptedSequence') || A2.IsA('AIScript')) && VSize(A2.Location - P.Location) < 3000)
					Log("CoopTest: pickup: near " $ A2.Class.Name $ " " $ A2 $ " Tag=" $ A2.Tag $ " Event=" $ A2.Event $ " Dist=" $ int(VSize(A2.Location - P.Location)) $ " Loc=" $ A2.Location);
			}
		}
		else if(TestStep < 40)
		{
			// Events of the script of squad member 62 in the order the player would cause them
			if(TestStep == 6)
			{
				Log("CoopTest: pickup: event DialogBehindBunker");
				TriggerEvent('DialogBehindBunker', self, Host.Pawn);
			}
			else if(TestStep == 32 && ParseOption(TestOptions, "CoopTestNext") != "")
			{
				Log("CoopTest: pickup: travel to " $ ParseOption(TestOptions, "CoopTestNext"));
				CoopTravel(ParseOption(TestOptions, "CoopTestNext"));
			}
			else if(TestStep == 16)
			{
				Log("CoopTest: pickup: event Add62ToSquad");
				TriggerEvent('Add62ToSquad', self, Host.Pawn);

				// The client "reaches the checkpoint": next to the squad member
				R = TestPawn.Rotation;
				R.Pitch = 0;
				C.Pawn.SetLocation(TestPawn.Location + vector(R) * 250 + vect(0,0,10));
			}

			if(ScriptedController(TestPawn.Controller) != None && ScriptedController(TestPawn.Controller).SequenceScript != None)
			{
				Log("CoopTest: pickup: script " $ ScriptedController(TestPawn.Controller).SequenceScript $ " ActionNum=" $ ScriptedController(TestPawn.Controller).ActionNum $ " Current=" $ ScriptedController(TestPawn.Controller).CurrentAction);

				if(TestStep == 1 || TestStep == 14)
				{
					for(i = 0; i < ScriptedController(TestPawn.Controller).SequenceScript.Actions.Length; ++i)
						Log("CoopTest: pickup: action " $ i $ " " $ ScriptedController(TestPawn.Controller).SequenceScript.Actions[i].GetActionString());
				}
			}

			Log("CoopTest: pickup: Squad=" $ TestPawn.Squad $ " Incap=" $ TestPawn.bIncapacitated $ " Controller=" $ TestPawn.Controller $ " HostTarget=" $ Host.TargetType $ " ClientPawn=" $ C.Pawn $ " ClientDist=" $ VSize(C.Pawn.Location - TestPawn.Location) $ " CanTake=" $ CanBeTakenOver(TestPawn, Host.Pawn) $ " AIState=" $ TestPawn.Controller.GetStateName() $ " AIClass=" $ TestPawn.Controller.Class $ " Hidden=" $ TestPawn.bHidden $ " Trace=" $ FastTrace(TestPawn.Location, C.Pawn.Location + C.Pawn.EyePosition()) $ " ClientIsCoop=" $ (CoopCommando(C.Pawn) != None));
		}

		if(TestStep < 40)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "door")
	{
		// GEO_01B: the client playing Scorch blows up the door to Fixer himself (use key in his window), the other client should watch Fixer's scene
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && C.Pawn != None && C.Pawn.IsA('Commando62Delta'))
				break;
		}

		if(TestStep == 0)
		{
			foreach DynamicActors(class'ActivateItem', A)
			{
				if(A.Tag == 'DemolitionChargeBrokenDoor')
					TestPanel = A;
			}

			if(C == None || TestPanel == None)
			{
				// The client may still wait for Scorch
				Log("CoopTest: door: no Scorch client (" $ C $ ") or no charge (" $ TestPanel $ ")");
				TestTime = Level.TimeSeconds + 2;
				return;
			}

			R = TestPanel.Rotation;
			R.Pitch = 0;
			C.Pawn.SetLocation(TestPanel.Location + vector(R) * 80 + vect(0,0,-60));
			R = rotator(TestPanel.Location - C.Pawn.Location);
			R.Pitch = 0;
			C.ClientSetRotation(R);
			Log("CoopTest: door: moved " $ C.PlayerReplicationInfo.PlayerName $ " to " $ C.Pawn.Location);
			C.bGodMode = true;
			Host.Pawn.SetLocation(TestPanel.Location + vector(TestPanel.Rotation) * 300 + vect(0,0,-60));

			for(C2 = Level.ControllerList; C2 != None; C2 = C2.nextController)
			{
				if(CoopPlayer(C2) != None && C2 != C && !IsHost(C2) && C2.Pawn != None)
					C2.Pawn.SetLocation(TestPanel.Location + vector(TestPanel.Rotation) * 400 + vect(0,0,-60));
			}

			Log("CoopTest: door: " $ TestPanel $ " State=" $ TestPanel.GetStateName() $ " Usable=" $ TestPanel.bIsUsable $ " ByPlayer=" $ TestPanel.bIsUsableByPlayer $ " Ammo=" $ TestPanel.AmmunitionRequired $ " Scorch=" $ C.PlayerReplicationInfo.PlayerName);
		}
		else if(C != None)
		{
			Log("CoopTest: door: State=" $ TestPanel.GetStateName() $ " Usable=" $ TestPanel.bIsUsable $ " Activating=" $ TestPanel.bActivating $ " Fraction=" $ TestPanel.FractionComplete $ " ClientState=" $ C.GetStateName() $ " TargetType=" $ CoopPlayer(C).TargetType $ " Target=" $ CoopPlayer(C).Target);
		}

		if(TestStep < 60)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "memberinfo" && TestStep == 0)
	{
		// Logs the script of a squad member (CoopTestMember=40 for Commando40Delta), the triggers and panels around it
		foreach DynamicActors(class'Pawn', P2)
		{
			if(string(P2.Class) ~= ("CTCharacters.Commando" $ ParseOption(TestOptions, "CoopTestMember") $ "Delta"))
				P = P2;
		}

		if(P == None)
		{
			Log("CoopTest: memberinfo: not found");
			TestAction = "";
			return;
		}

		Log("CoopTest: memberinfo: " $ P $ " Squad=" $ P.Squad $ " Controller=" $ P.Controller.Class $ " State=" $ P.Controller.GetStateName() $ " Loc=" $ P.Location $ " HostLoc=" $ Host.Pawn.Location);

		if(ScriptedController(P.Controller) != None && ScriptedController(P.Controller).SequenceScript != None)
		{
			for(i = 0; i < ScriptedController(P.Controller).SequenceScript.Actions.Length; ++i)
				Log("CoopTest: memberinfo: action " $ i $ " " $ ScriptedController(P.Controller).SequenceScript.Actions[i].GetActionString());
		}

		foreach AllActors(class'Actor', A2)
		{
			if((A2.IsA('Trigger') || A2.IsA('ActivateItem') || A2.IsA('SquadMarker')) && VSize(A2.Location - P.Location) < 2500)
				Log("CoopTest: memberinfo: near " $ A2.Class.Name $ " " $ A2 $ " Tag=" $ A2.Tag $ " Event=" $ A2.Event $ " Dist=" $ int(VSize(A2.Location - P.Location)) $ " Loc=" $ A2.Location);
		}
	}
	else if(TestAction ~= "squadinfo")
	{
		// Logs the commandos of the level and their squads every 2 seconds
		foreach DynamicActors(class'Pawn', P)
		{
			if(P.IsA('CloneCommando') && PlayerController(P.Controller) == None)
				Log("CoopTest: squadinfo: " $ P $ " Squad=" $ P.Squad $ " HostSquad=" $ Host.Pawn.Squad $ " Controller=" $ P.Controller $ " Hidden=" $ P.bHidden $ " Health=" $ P.Health $ " Loc=" $ P.Location $ " HostLoc=" $ Host.Pawn.Location);
		}

		if(TestStep < 60)
		{
			TestTime = Level.TimeSeconds + 2;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "takeover")
	{
		// Prototype: the client takes over a squad member, then the host gives squad orders. 0 = take over, 1..40 = orders and logs
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None)
			return;

		if(TestStep == 0)
		{
			P = None;

			foreach DynamicActors(class'Pawn', P2)
			{
				if(CanBeTakenOver(P2, Host.Pawn) && (P == None || VSize(P2.Location - C.Pawn.Location) < VSize(P.Location - C.Pawn.Location)))
					P = P2;
			}

			if(P == None)
			{
				Log("CoopTest: takeover: no squad member");
				TestAction = "";
				return;
			}

			TakeOver(CoopPlayer(C), P, true);
		}
		else
		{
			switch(TestStep % 8)
			{
			case 2: CTPlayer(Host).SetStanceOffensive(); Log("CoopTest: takeover: order offensive"); break;
			case 4: CTPlayer(Host).SetStanceDefensive(); Log("CoopTest: takeover: order defensive"); break;
			case 6: CTPlayer(Host).SquadRecall(); Log("CoopTest: takeover: order recall"); break;
			case 0: CTPlayer(Host).SetStanceHold(); Log("CoopTest: takeover: order hold"); break;
			}

			Log("CoopTest: takeover: Pawn=" $ C.Pawn $ " Controller=" $ C.Pawn.Controller $ " State=" $ C.GetStateName() $ " Health=" $ C.Pawn.Health $
			    " Squad=" $ C.Pawn.Squad $ " Members=" $ Host.Pawn.Squad.CountAliveMembers() $ " Weapon=" $ C.Pawn.Weapon $ " Loc=" $ C.Pawn.Location);
		}

		if(TestStep < 40)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "npc" && TestStep == 0)
	{
		// Spawns a battle droid in front of the client (animations and rotation of AI on clients)
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				// To the side so the host doesn't block the view
				R = C.Pawn.Rotation;
				R.Pitch = 0;
				R.Yaw += 8192;
				P = Spawn(class<Pawn>(DynamicLoadObject("CTCharacters.BattleDroid", class'Class')),,, C.Pawn.Location + vector(R) * 500 + vect(0,0,40), rotator(-vector(R)));

				if(P != None && P.Controller == None && P.ControllerClass != None)
				{
					P.Controller = Spawn(P.ControllerClass);
					P.Controller.Possess(P);
				}

				if(P != None && P.Controller != None)
					P.Controller.SetEnemy(C.Pawn);

				C.ClientSetRotation(R);
				Log("CoopTest: npc: spawned " $ P $ " Controller=" $ P.Controller);
			}
		}
	}
	else if(TestAction ~= "squadwalk")
	{
		// The host moves away so the squad runs after him in front of the client (animations of AI on clients)
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C != None && Host.Pawn != None && TestStep == 0)
		{
			R = C.Pawn.Rotation;
			R.Pitch = 0;
			Host.Pawn.SetLocation(C.Pawn.Location + vector(R) * 700);
			Log("CoopTest: squadwalk: moved host");
		}

		if(TestStep < 1)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "hostdown")
	{
		// Simulates the whole squad being down: the host is incapacitated and the game tries to make him bleed out
		if(TestStep == 0)
		{
			Host.Pawn.TakeDamage(1000, None, Host.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
			TestTime = Level.TimeSeconds + 3;
			++TestStep;
			return;
		}
		else if(TestStep == 1)
		{
			Log("CoopTest: Host incapacitated=" $ Host.Pawn.bIncapacitated $ ", calling BleedOut");
			Host.Pawn.BleedOut();
			Log("CoopTest: After BleedOut: Host health=" $ Host.Pawn.Health $ " incapacitated=" $ Host.Pawn.bIncapacitated);
		}
	}
	else if(TestAction ~= "clientincap" && TestStep == 0)
	{
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				Log("CoopTest: Incapacitating " $ C.PlayerReplicationInfo.PlayerName);
				C.Pawn.TakeDamage(1000, None, C.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
			}
		}
	}

	TestAction = "";
}

/*
 * Clients play members of Delta squad. When a squad member joins the host's squad (e.g. GEO_01A: the host revives the first one),
 * the first client without a squad member that comes close to it takes it over: the client's camera moves over to the squad
 * member and the client controls it from then on. The host keeps his own commando. One squad member per client.
 */
function bool CanBeTakenOver(Pawn P, Pawn HostPawn)
{
	return P != HostPawn && HostPawn.Squad != None && P.Squad == HostPawn.Squad && P.Health > 0 && !P.bIncapacitated &&
	       P.Controller != None && PlayerController(P.Controller) == None && !IsScriptBusy(P) && !P.bHidden;
}

/*
 * A squad member is busy while a script moves or animates it. A script that only waits for an event (e.g. GEO_01B: Fixer waits
 * for the shield to be hacked, which is his own job when a client plays him) doesn't count.
 */
function bool IsScriptBusy(Pawn P)
{
	local ScriptedController SC;

	if(!P.Controller.IsInState('Scripting'))
		return false;

	SC = ScriptedController(P.Controller);

	return SC == None || SC.SequenceScript == None || SC.ActionNum >= SC.SequenceScript.Actions.Length ||
	       !SC.SequenceScript.Actions[SC.ActionNum].IsA('ACTION_WaitForEvent');
}

/*
 * Scenes in which a squad member joins (GEO_01B: Fixer behind the door Scorch blows up): the script waits for an event, plays the
 * scene and adds the squad member (ACTION_ChangeSquadMember). While the scene plays, the client that will play the squad member
 * (the one that played it before, otherwise the closest client without one) already watches it through its eyes with its own
 * controls locked (CoopPlayer.CoopWatching). When the scene is over CheckSquadTakeover hands it over and the old pawn disappears.
 */
function CheckSceneWatch()
{
	local PlayerController Host;
	local Controller C;
	local CoopPlayer CP, Best;
	local Pawn P;
	local ScriptedController SC;
	local ACTION_ChangeSquadMember Change;
	local int i, AddIndex, WaitIndex;
	local bool bFirstTime;

	Host = GetHost();

	if(!bClientsTakeOverSquad || Host == None || Host.Pawn == None)
		return;

	foreach DynamicActors(class'Pawn', P)
	{
		SC = ScriptedController(P.Controller);

		if(SC == None || PlayerController(P.Controller) != None || P == Host.Pawn || SC.SequenceScript == None || !SC.IsInState('Scripting') ||
		   !P.IsA('CloneCommando') || FindWatcher(P) != None)
			continue;

		AddIndex = -1;
		WaitIndex = -1;

		for(i = 0; i < SC.SequenceScript.Actions.Length; ++i)
		{
			Change = ACTION_ChangeSquadMember(SC.SequenceScript.Actions[i]);

			if(Change != None && Change.bAddMember && Change.MemberTag == P.Tag)
			{
				AddIndex = i;
				break;
			}

			if(SC.SequenceScript.Actions[i].IsA('ACTION_WaitForEvent'))
				WaitIndex = i;
		}

		// Only while the scene before the squad member joins plays
		if(AddIndex == -1 || SC.ActionNum <= WaitIndex || SC.ActionNum > AddIndex)
			continue;

		Best = CoopPlayer(FindAssignedPlayer(P));
		bFirstTime = Best == None;

		if(bFirstTime)
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				CP = CoopPlayer(C);

				if(CP != None && !IsHost(CP) && CoopCommando(CP.Pawn) != None && CP.WatchedMember == None && GetAssignedClass(CP) == "" &&
				   (Best == None || VSize(CP.Pawn.Location - P.Location) < VSize(Best.Pawn.Location - P.Location)))
					Best = CP;
			}

			if(Best == None)
				continue;

			SetAssignment(Best, string(P.Class));
		}

		StartWatching(Best, P, bFirstTime);
	}
}

function CoopPlayer FindWatcher(Pawn P)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && CoopPlayer(C).WatchedMember == P)
			return CoopPlayer(C);
	}

	return None;
}

function StartWatching(CoopPlayer CP, Pawn P, bool bMoveCamera)
{
	Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " watches the scene of " $ P $ " (" $ P.Class $ ")");

	if(bMoveCamera && CP.Pawn != None)
		CP.ClientCoopTakeoverCamera(CP.Pawn.Location + CP.Pawn.EyePosition(), CP.Rotation);

	// From behind: the squad member's eyes often look at a wall during its scene
	CP.WatchedMember = P;
	CP.SetViewTarget(P);
	CP.ClientSetViewTarget(P);
	CP.bBehindView = true;
	CP.ClientSetBehindView(true);
	CP.GotoState('CoopWatching');
	CP.ClientGotoState('CoopWatching', '');

	if(bMoveCamera)
		Broadcast(self, CP.PlayerReplicationInfo.PlayerName $ " joined Delta squad");
}

function CheckSquadTakeover()
{
	local PlayerController Host;
	local Controller C;
	local Pawn P;

	if(!bClientsTakeOverSquad)
		return;

	Host = GetHost();

	if(Host == None || Host.Pawn == None || Host.Pawn.Squad == None)
		return;

	foreach DynamicActors(class'Pawn', P)
	{
		if(!CanBeTakenOver(P, Host.Pawn))
			continue;

		// A client that already played this squad member gets it back right away, wherever it is
		C = FindAssignedPlayer(P);

		if(C != None)
		{
			if(CoopCommando(C.Pawn) != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated)
			{
				TakeOver(CoopPlayer(C), P, false);
				return;
			}

			continue; // Reserved for that client
		}

		// Otherwise the first client without a squad member that reaches it
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && CoopCommando(C.Pawn) != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated &&
			   GetAssignedClass(PlayerController(C)) == "" &&
			   VSize(C.Pawn.Location - P.Location) < TakeOverDistance && FastTrace(P.Location, C.Pawn.Location + C.Pawn.EyePosition()))
			{
				SetAssignment(PlayerController(C), string(P.Class));
				TakeOver(CoopPlayer(C), P, true);
				return; // One per second is enough
			}
		}
	}
}

/*
 * The AI controller of the squad member is destroyed like when a squad member dies, the client's own pawn is removed.
 */
/*
 * Squad markers are done by the specialist of the squad: demolition by 62 (Scorch), hacking by 40 (Fixer), sniping by 07 (Sev).
 * If a client plays the specialist the host can't order it (the AI can't do it for him), the client has to do it himself.
 */
static function string MarkerSpecialist(Actor Marker)
{
	if(Marker == None)
		return "";

	if(Marker.IsA('MarkerDemolition') || Marker.IsA('MarkerDoorBreach') || Marker.IsA('MarkerSetProximityMine') || Marker.IsA('MarkerAntiArmor'))
		return "CTCharacters.Commando62Delta";

	if(Marker.IsA('MarkerHackDoor') || Marker.IsA('MarkerHackTerminal') || Marker.IsA('MarkerDisarmTrap'))
		return "CTCharacters.Commando40Delta";

	if(Marker.IsA('MarkerSnipe'))
		return "CTCharacters.Commando07Delta";

	return "";
}

// The client that plays the specialist for this marker, None if the AI does it
function PlayerController MarkerClient(Actor Marker)
{
	local string MemberClass;
	local Controller C;

	MemberClass = MarkerSpecialist(Marker);

	if(MemberClass == "")
		return None;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None && string(C.Pawn.Class) ~= MemberClass)
			return PlayerController(C);
	}

	return None;
}

// Identifies a client across levels and sessions: IP address (without port) and name (two clients on one PC share the address)
function string PlayerKey(PlayerController PC)
{
	local string Address;

	Address = PC.GetPlayerNetworkAddress();

	if(InStr(Address, ":") != -1)
		Address = Left(Address, InStr(Address, ":"));

	return Address $ "/" $ PC.PlayerReplicationInfo.PlayerName;
}

// Which client plays which squad member is saved in CoopConfig.SquadAssignmentList
function string GetAssignedClass(PlayerController PC)
{
	return class'CoopConfig'.static.GetSquadAssignment(PlayerKey(PC));
}

function SetAssignment(PlayerController PC, string MemberClass)
{
	class'CoopConfig'.static.SetSquadAssignment(PlayerKey(PC), MemberClass);
	Log("CoopGame: " $ PlayerKey(PC) $ " plays " $ MemberClass $ " from now on");
}

// The connected client that played this squad member before, None if there is none
function PlayerController FindAssignedPlayer(Pawn P)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && GetAssignedClass(PlayerController(C)) ~= string(P.Class))
			return PlayerController(C);
	}

	return None;
}

// The squad member the client played before if it is in the level, even if it is not free yet
function Pawn FindAssignedMemberInLevel(CoopPlayer CP)
{
	local string MemberClass;
	local Pawn P;

	MemberClass = GetAssignedClass(CP);

	if(MemberClass == "" || !bClientsTakeOverSquad)
		return None;

	foreach DynamicActors(class'Pawn', P)
	{
		if(string(P.Class) ~= MemberClass && P.Health > 0 && PlayerController(P.Controller) == None)
			return P;
	}

	return None;
}

// The squad member a (re)spawning client played before, if it is there and free
function Pawn FindAssignedMember(CoopPlayer CP)
{
	local PlayerController Host;
	local string MemberClass;
	local Pawn P;

	MemberClass = GetAssignedClass(CP);
	Host = GetHost();

	if(MemberClass == "" || Host == None || Host.Pawn == None || !bClientsTakeOverSquad)
		return None;

	foreach DynamicActors(class'Pawn', P)
	{
		if(string(P.Class) ~= MemberClass && CanBeTakenOver(P, Host.Pawn))
			return P;
	}

	return None;
}

function TakeOver(CoopPlayer CP, Pawn P, bool bMoveCamera)
{
	local Pawn OldPawn;
	local Controller OldAI;
	local Inventory Inv;
	local int i;

	OldPawn = CP.Pawn;
	OldAI = P.Controller;
	CP.WatchedMember = None;
	Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " takes over " $ P $ " (" $ P.Class $ ") from " $ OldAI);

	// The camera moves from the old view to the new pawn on the client (only when a client gets a squad member for the first time)
	if(OldPawn != None && bMoveCamera)
		CP.ClientCoopTakeoverCamera(OldPawn.Location + OldPawn.EyePosition(), CP.Rotation);

	OldAI.UnPossess();
	OldAI.Destroy();

	CP.UnPossess();

	if(OldPawn != None)
		OldPawn.Destroy();

	CP.bCoopTakeover = true;
	CP.Possess(P);
	CP.bCoopTakeover = false;
	CP.bBehindView = false;
	CP.ClientSetBehindView(false);

	// Scripts crouch or hurt squad members (Fixer is hurt in his scene): a player starts standing and healthy
	P.ShouldCrouch(false);
	P.bWantsToCrouch = false;
	P.Health = Max(P.Health, P.default.Health);
	CP.ClientSetRotation(P.Rotation);
	CP.IncapacitatedTime = 0;
	CP.DeadTime = 0;
	CP.TakeoverTime = Level.TimeSeconds;

	// The AI's weapons have no first person view and it lacks the bacta healer and hand signals: player equipment instead
	while(P.Inventory != None)
	{
		Inv = P.Inventory;
		P.DeleteInventory(Inv);
		Inv.Destroy();
	}

	P.Weapon = None;
	P.PendingWeapon = None;

	for(i = 0; i < ArrayCount(class'PlayerCommando'.default.RequiredEquipment); ++i)
	{
		if(class'PlayerCommando'.default.RequiredEquipment[i] != "")
			P.CreateInventory(class'PlayerCommando'.default.RequiredEquipment[i]);
	}

	if(P.Inventory != None)
		P.Inventory.OwnerEvent('LoadOut');

	CP.ClientSwitchToBestWeapon();

	if(bMoveCamera)
		Broadcast(self, CP.PlayerReplicationInfo.PlayerName $ " joined Delta squad");
	Log("CoopGame: Takeover done: Pawn=" $ CP.Pawn $ " Squad=" $ P.Squad $ " Weapon=" $ P.Weapon $ " Inventory=" $ P.Inventory);
}

// After loading a save game the controllers and pawns of the clients from the time of saving still exist but have no connection anymore
function CleanUpOrphans()
{
	local Controller C, Next;
	local CoopCommando P;

	for(C = Level.ControllerList; C != None; C = Next)
	{
		Next = C.nextController;

		if(CoopPlayer(C) != None && PlayerController(C).Player == None)
		{
			Log("CoopGame: Removing orphaned client controller " $ C);

			if(C.Pawn != None)
				C.Pawn.Destroy();

			C.Destroy();
		}
	}

	foreach DynamicActors(class'CoopCommando', P)
	{
		if(P.Controller == None && !P.bIncapacitated && P.Health > 0)
		{
			Log("CoopGame: Removing orphaned client pawn " $ P);
			P.Destroy();
		}
	}
}

/*
 * Travel
 * All level changes must use server travel so that the clients follow the host.
 */

function string MakeCoopURL(string URL)
{
	if(InStr(Caps(URL), "?GAME=") == -1)
		URL = URL $ "?game=" $ GAME_CLASS;

	if(InStr(Caps(URL), "?LISTEN") == -1)
		URL = URL $ "?listen";

	if(InStr(Caps(URL), "?MAXPLAYERS=") == -1)
		URL = URL $ "?MaxPlayers=" $ MaxPlayers;

	return URL;
}

// Prepares the host's pawn for travel the same way the single player level change does
function PrepareHostForTravel()
{
	local PlayerController Host;
	local PlayerCommando P;

	Host = GetHost();

	if(Host == None)
		return;

	P = PlayerCommando(Host.Pawn);

	if(P == None)
		return;

	if(P.Squad != None)
		P.SaveSquadTravelInfo();

	// PlayerCommando.TravelPostAccept sets this stance on the squad of the next level. It is None if there was no squad in the current level.
	if(P.CurrentStance == None)
		P.CurrentStance = class'StanceFormUp';
}

/*
 * Briefing levels crash network clients while the level starts (the process exits during BeginPlay without an error message).
 * They don't contain gameplay so coop skips them and goes to the next level of the campaign.
 */
function string SkipBriefing(string URL)
{
	local PlayerController Host;
	local string Map, Options, NextMap;
	local int i;

	Map = URL;
	i = InStr(Map, "?");

	if(i != -1)
	{
		Options = Mid(Map, i);
		Map = Left(Map, i);
	}

	if(InStr(Caps(Map), "BRIEFING") == -1)
		return URL;

	Host = GetHost();

	if(Host == None)
		return URL;

	Host.GetNextLevel(Host.GetLevelIndex(Map), NextMap);

	if(NextMap == "" || Host.GetLevelIndex(NextMap) == -1)
		return URL;

	Log("CoopGame: Skipping briefing " $ Map $ " -> " $ NextMap);

	return NextMap $ Options;
}

function CoopTravel(string URL)
{
	URL = SkipBriefing(URL);
	PrepareHostForTravel();
	Log("CoopGame: Traveling to " $ URL);
	Level.ServerTravel(MakeCoopURL(URL), true);
}

// Coop "checkpoint": restarts the current level for everybody (see CoopPlayer.AutoSave)
function CoopRestartLevel()
{
	local PlayerController Host;
	local string Map;

	Host = GetHost();

	if(Host != None)
		Host.GetCurrentMapName(Map);

	if(Map == "")
	{
		Log("CoopGame: Restarting level");
		Level.ServerTravel("?restart", false);
		return;
	}

	Broadcast(self, "Restarting the level...");
	Log("CoopGame: Restarting level " $ Map);
	Level.ServerTravel(MakeCoopURL(Map), false);
}

/*
 * Same as GameInfo.ProcessServerTravel but clients never travel with their items. Their pawns get the default inventory on the new
 * level anyway and a client without a pawn (e.g. still waiting to spawn) crashes while exporting its travel items.
 */
function ProcessServerTravel(string URL, bool bItems)
{
	local PlayerController P, LocalPlayer;
	local string ClientURL, S;

	ClientURL = ExpandRelativeURL(URL);
	ClientURL = ClientURL $ ConsoleCommand("XLIVE CLIENT_TRAVEL");

	BaseMutator.ServerTraveling(ClientURL, bItems);
	EndLogging("mapchange");
	Log("CoopGame: ProcessServerTravel: " $ ClientURL);

	foreach DynamicActors(class'PlayerController', P)
	{
		if(NetConnection(P.Player) != None)
		{
			S = ClientURL;

			if(P.PlayerReplicationInfo != None && P.PlayerReplicationInfo.Team != None)
				S = S $ "?Team=" $ P.PlayerReplicationInfo.Team.TeamIndex;

			P.ClientTravel(S, TRAVEL_Relative, false);
		}
		else
		{
			LocalPlayer = P;
			P.PreClientTravel();
		}
	}

	if(Level.NetMode == NM_ListenServer && LocalPlayer != None)
	{
		Level.NextURL = Level.NextURL
		              $ "?Team=" $ LocalPlayer.GetDefaultURL("Team")
		              $ "?Name=" $ LocalPlayer.GetDefaultURL("Name")
		              $ "?Class=" $ LocalPlayer.GetDefaultURL("Class")
		              $ "?Character=" $ LocalPlayer.GetDefaultURL("Character");
	}
}

function SendPlayer(PlayerController aPlayer, string URL)
{
	CoopTravel(URL);
}

defaultproperties
{
	MaxCoopPlayers=4
	ClientRespawnDelay=5.0
	bClientsTakeOverSquad=True
	TakeOverDistance=500
	ClientBleedOutTime=45.0
	CatchUpDistance=4000.0
	CatchUpDelay=15.0
	MaxSpawnWait=30.0
	HostReviveWaitTime=60.0
	bPrivateNetworksOnly=False
	PlayerControllerClassName="ModCoop.CoopPlayer"
	GameName="Republic Commando Coop"
}
