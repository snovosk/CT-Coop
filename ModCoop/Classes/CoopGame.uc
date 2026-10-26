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
var() config float GatherDistance;       // See CheckGather
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
var SquadMarker TestMarker;
var bool    bTestResSet;
var string  TestEvents;
var float   NextTestEvent;
var int     TestChainStage;
var vector  TestHostLocation;

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
	var bool        bMarkerEvents;  // See SyncPanelStates
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
var bool  bRemovedUplink;

// See CheckMissedEvents
struct ScriptWatch
{
	var ScriptedController SC;
	var int    LastAction;
	var name   WaitEvent;     // Event it waits for, None if it doesn't wait
	var float  WaitStart;
	var string WaitedEvents;  // Events it has waited for before: "|A|B|"
};
struct FiredEvent
{
	var name  Event;
	var float Time;
};
var array<ScriptWatch> ScriptWatches;
var array<FiredEvent>  FiredEvents;
var array<Prop>        EffectProps;         // See SyncPropEffects
var array<name>        EffectPropStates;
var array<Pawn>        HealthPawns;        // See SyncSquadHealth
var array<ScriptedController> StalledScripts; // See CheckStalledScripts
var array<int>          StalledActions;
var array<float>        StalledTimes;
var array<Pawn>        ArrivalPawns;        // See ScanArrivals
var array<Actor>       ArrivalPoints;
var array<name>        ArrivalEvents, ArrivalArmEvents, HeardEvents;
var array<byte>        ArrivalDone;
var array<Pawn>        ArrivalScanned;
var float              ArrivalRadius;
var Turret             TestTurret;
var int                TestSubStep;
var array<string>      SceneMaps;           // See InStartScene
var array<name>        SceneEndEvents;
var name               SceneEndEvent;
var vector             SceneCenter;
var bool               bSceneChecked;
var int                UplinkChecks;
var int                LastCommandoCount;   // See LogCommandos        // See RemoveUplink
var CoopPlayer         SnipePlayer;         // See StartAISnipe
var Pawn               SnipePawn;
var SquadMarker        SnipeMarker;
var ScriptedSequence   SnipeScript;
var float              SnipeStartTime, NextSnipeLog;
var bool               bSnipeInPosition, bSnipeShot;
var ScriptedSequence   SnipeShotScript;     // See FindSnipeShot
var int                SnipeShotIndex;
var name               SnipeShotEvent;
var float              SnipeEndTime;
var Inventory          SnipeLentRifle;
var array<CoopPlayer>  BreachPlayers;       // See StartAIBreach
var array<Pawn>        BreachPawns;
var SquadMarker        BreachMarker;
var float              BreachStartTime;
var array<float>       SentHealths;
var array<byte>        SentSquadMembers;
var array<TriggerLight> SyncedLights;      // See SyncTriggerLights
var array<float>        SentLightBrightness;
var float              NextLightResend;
var array<int>         SentSquadIcons;      // Order icon and marker state, see GetSquadIconState
var float              NextSquadStateResend;
var MissionObjectives  Objectives;          // See SyncObjectives
var string             SentObjectives;
var float              NextObjectivesResend;
var array<SquadMarker> ClientSnipeMarkers; // See CheckClientSnipers: 1 entry per marker, asked or done
var array<byte>        ClientSnipeStates;  // 1 = the client was asked to take the position, 2 = in position
var float              NextSnipeTrackerTime;
var bool  bWaitingForClients;    // See WaitForClients
var array<name>      HiddenTags;         // See ForwardSetHidden
var array<byte>      HiddenTagValues;
var array<name>      MarkerStateTags;    // See ForwardMarkerState
var array<Pawn>      ScriptAnimPawns;    // See ForwardScriptAnim
var float            NextScriptAnimCheck;
var array<name>      MarkerStates;
var array<name>      CollisionTags;      // See ForwardSetCollision
var array<byte>      CollisionTagFlags;
var float            NextCollisionTagResend;
var array<KarmaProp> UnblockedKarmaProps;  // See UnblockKarmaProps
var float NextKarmaResend;
var float NextClientsStatusLog;  // See LogClientsStatus
var float LevelStartTime;
var bool  bSlowStart;            // See StopWaitingForClients
var float SlowStartTime, SavedTimeDilation;        // Level.TimeSeconds when the level started for everybody (see CheckIntroPositions)
var float ClientWaitTime;        // CoopNative.GetRealTime when the waiting started
var() config float MaxClientWait;  // Seconds the start of a level waits for the clients of the last level
var SquadMarker GatherMarker;    // Door breach ordered by the host, waits until all clients playing squad members are at the door (see CheckGather)
var float NextGatherMessage;

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
	TestEvents = ParseOption(Options, "CoopTestEvent");
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

/*
 * The master server uplink checks the CD keys of clients. Several clients with the same key (one PC, or the same GOG key) were
 * kicked a few seconds after joining ("CD key in use", BADCDKEY). Coop is joined by address, so the uplink isn't needed.
 * Every level has a new uplink: removed in the first frames (Tick), the Timer was too late after a level change, the uplink checked
 * the clients the moment the level started after waiting for them and kicked 1-2 of them on every level.
 */
function RemoveUplink()
{
	local Actor A;

	if(bRemovedUplink)
		return;

	foreach AllActors(class'Actor', A)
	{
		if(A.IsA('MasterServerUplink'))
		{
			Log("CoopGame: removing " $ A $ " (CD key checks of clients)");
			A.Destroy();
			bRemovedUplink = true;
		}
	}
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

	if(IsHost(NewPlayer))
		WaitForClients(NewPlayer);
	else if(bWaitingForClients)
		CheckClientsArrived();

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

	if(SpawnClient(CP))
	{
		if(bWaitingForClients)
			CheckClientsArrived();
	}
	else
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
 * Spawns a client's commando on a free spot around a location (from which it is visible). Several spots are tried: the first one
 * may already be taken by another client (the third client of four couldn't spawn at the start of GEO_01B).
 */
function Pawn SpawnCommandoNear(vector Center, rotator Dir)
{
	local int Ring, i;
	local rotator R;
	local vector Test;
	local vector HitLocation, HitNormal;
	local Pawn P;

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

			if(!FastTrace(Test, Center) || Trace(HitLocation, HitNormal, Test - vect(0, 0, 300), Test, false) == None)
				continue;

			P = Spawn(class'CoopCommando',,, Test, Dir);

			if(P != None)
				return P;
		}
	}

	return None;
}

/*
 * Lifts (GEO_05A and GEO_04D start in one, GEO_05B ends in one): the host stands in the car, clients waited for him to get off
 * (IsHostFree) and were spawned after 30 s next to the host - at the bottom of the shaft or somewhere else. While the host rides a
 * lift (a mover that takes several seconds) clients are put into the car next to him and stand still like him until it stops.
 */
function Mover HostLift(PlayerController Host, optional bool bEvenStopped)
{
	local Mover M;
	local int i;

	if(Host == None || Host.Pawn == None || Host.Pawn.Health <= 0 || Host.Pawn.Physics != PHYS_Walking)
		return None;

	M = Mover(Host.Pawn.Base);

	if(M == None || (!M.bInterpolating && !bEvenStopped))
		return None;

	for(i = 0; i < 4; i = i + 1)
	{
		if(M.MoveTimes[i] >= 4)
			return M;
	}

	return None;
}

// A free spot on the floor of the lift car next to the host (FindSpawnLocation only finds world geometry under a spot)
function bool FindLiftSpot(Pawn HostPawn, Mover M, out vector OutLocation)
{
	local int Ring, i;
	local rotator R;
	local vector Test, HitLocation, HitNormal;

	R.Yaw = HostPawn.Rotation.Yaw;

	for(Ring = 1; Ring <= 3; ++Ring)
	{
		for(i = 0; i < 8; ++i)
		{
			R.Yaw = HostPawn.Rotation.Yaw + 32768 + (i / 2) * 8192 * (1 - 2 * (i % 2));
			Test = HostPawn.Location + vector(R) * (Ring * 60.0);

			if(!FastTrace(Test, HostPawn.Location) || Trace(HitLocation, HitNormal, Test - vect(0,0,300), Test, true) != M)
				continue;

			OutLocation = Test + vect(0,0,10);
			return true;
		}
	}

	return false;
}

/*
 * Scenes at the start of a level in which the squad stands together while their scripts play (GEO_03A: the briefing in the
 * elevator, whose car doesn't move - the walls of the shaft do; RAS_03A, YYY_04B: the briefing of the holo projector). Until the
 * event that ends it, the members stay with their scripts and everybody watches over the shoulder like on a lift (CheckLiftRides).
 */
function bool InStartScene()
{
	local int i;
	local string Map;
	local Pawn P;
	local int Num;

	if(!bSceneChecked && GetHost() != None)
	{
		bSceneChecked = true;
		GetHost().GetCurrentMapName(Map);

		for(i = 0; i < SceneMaps.Length; i = i + 1)
		{
			if(InStr(Caps(Map), Caps(SceneMaps[i])) != -1)
			{
				SceneEndEvent = SceneEndEvents[i];
				ListenForEvent(SceneEndEvent);
				Log("CoopGame: the level starts with a scene that ends with " $ SceneEndEvent);
			}
		}
	}

	if(SceneEndEvent == '' || WasHeard(SceneEndEvent) || Level.TimeSeconds - LevelStartTime > 240)
		return false;

	// The middle of the squad (once they all stand there)
	if(SceneCenter == vect(0,0,0) && GetHost() != None && GetHost().Pawn != None)
	{
		foreach DynamicActors(class'Pawn', P)
		{
			if(P.IsA('CloneCommando') && P.Health > 0 && VSize(P.Location - GetHost().Pawn.Location) < 800)
			{
				SceneCenter += P.Location;
				++Num;
			}
		}

		if(Num > 0)
			SceneCenter = SceneCenter / Num;
	}

	return true;
}

// The middle of the players and squad members on the lift car (the car's origin is often at an edge)
function vector LiftCenter(Mover M)
{
	local Pawn P;
	local vector Sum;
	local int Num;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.Base == M && P.Health > 0)
		{
			Sum += P.Location;
			++Num;
		}
	}

	if(Num == 0)
		return M.Location;

	return Sum / Num;
}

function CheckLiftRides()
{
	local PlayerController Host;
	local Controller C;
	local CoopPlayer CP;
	local Mover M;
	local vector Spot, Center;
	local bool bScene;

	Host = GetHost();
	M = HostLift(Host);
	bScene = M == None && InStartScene();

	if(M != None)
		Center = LiftCenter(M);
	else if(bScene)
		Center = SceneCenter;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None)
			continue;

		// Everybody's camera over the shoulder looks at the center of the car (also a client watching its member's scene there)
		if((M != None || bScene) && (CP.Pawn != None || (CP.WatchedMember != None && (bScene || CP.WatchedMember.Base == M))))
		{
			if(!CP.bLiftViewSent)
				Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " gets the lift view of " $ M $ ", center " $ Center);

			CP.bLiftViewSent = true;
			CP.ClientCoopLiftView(true, Center);
		}
		else if(CP.bLiftViewSent)
		{
			CP.bLiftViewSent = false;
			CP.ClientCoopLiftView(false, vect(0,0,0));
		}

		// The host stands still like the others (only the own pawn, not while a scene camera has the host)
		if(IsHost(CP))
		{
			if((M != None || bScene) && CP.Pawn != None && CP.IsInState('PlayerWalking') && !CP.IsInState('CoopLiftRide'))
			{
				Log("CoopGame: the host rides the lift " $ M);
				CP.GotoState('CoopLiftRide');
			}
			else if(M == None && !bScene && CP.IsInState('CoopLiftRide'))
			{
				Log("CoopGame: the host gets off the lift");
				CP.GotoState('PlayerWalking');
			}

			continue;
		}

		if((M == None && !bScene) || CP.Pawn == None || CP.Pawn.Health <= 0 || CP.Pawn.bIncapacitated || CP.Machine != None ||
		   !(CP.IsInState('PlayerWalking') || CP.IsInState('CoopLiftRide')))
		{
			if(CP.IsInState('CoopLiftRide'))
			{
				Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " gets off the lift");
				CP.GotoState('PlayerWalking');
				CP.ClientGotoState('PlayerWalking', '');
			}

			continue;
		}

		if(M != None && CP.Pawn.Base != M && (CP.Pawn.Physics == PHYS_Walking || VSize(CP.Pawn.Location - Host.Pawn.Location) > 600) &&
		   FindLiftSpot(Host.Pawn, M, Spot))
		{
			Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " is put on the lift " $ M $ " of the host (was on " $ CP.Pawn.Base $ " at " $ CP.Pawn.Location $ ")");
			CP.Pawn.SetLocation(Spot);
			CP.Pawn.Velocity = Host.Pawn.Velocity;
			CP.ClientSetLocation(Spot, CP.Rotation);
		}

		if(!CP.IsInState('CoopLiftRide'))
		{
			Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " stands still on the lift " $ M $ " / in the scene " $ bScene);
			CP.GotoState('CoopLiftRide');
			CP.ClientGotoState('CoopLiftRide', '');
		}
	}
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
	local vector SpawnSpot;
	local NavigationPoint StartSpot;
	local rotator SpawnRotation;
	local Pawn P;

	Host = GetHost();

	// A client that plays a squad member starts as it (e.g. the next level)
	P = FindAssignedMember(CP);

	if(P != None)
	{
		// A member that still has its entrance to play (GEO_01C: down the rope): the client watches it first (CheckIntroWatch)
		if(StartIntroWatch(CP, P))
		{
			CP.SpawnWaitStart = 0;
			return true;
		}

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
			// Already watch the squad member (over the shoulder, smoothed, see CoopPlayer.CalcWatchView)
			if(CP.WatchedMember != P)
				StartWatching(CP, P, false);

			return false;
		}

		P = None;
	}

	if(Host != None && Host.Pawn != None && !Host.Pawn.bDeleteMe)
	{
		if(CP.SpawnWaitStart == 0)
			CP.SpawnWaitStart = Level.TimeSeconds;

		// Wait until the host stands on the ground, but not forever. On a lift the client comes along at once (CheckLiftRides)
		if(!IsHostFree(Host) && HostLift(Host, true) == None && Level.TimeSeconds - CP.SpawnWaitStart < MaxSpawnWait)
		{
			Log("CoopGame: Waiting for the host to be free before spawning a client: Physics=" $ Host.Pawn.Physics $ " Base=" $ Host.Pawn.Base $ " Health=" $ Host.Pawn.Health);
			return false;
		}
		if(HostLift(Host, true) != None && FindLiftSpot(Host.Pawn, HostLift(Host, true), SpawnSpot))
			P = Spawn(class'CoopCommando',,, SpawnSpot, Host.Pawn.Rotation);

		if(P == None)
			P = SpawnCommandoNear(Host.Pawn.Location, Host.Pawn.Rotation);
	}

	if(P == None) // Fall back to the player starts
	{
		StartSpot = FindPlayerStart(CP, 1);

		if(StartSpot != None)
			P = SpawnCommandoNear(StartSpot.Location, StartSpot.Rotation);
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
	RemoveUplink();

	// Test: CoopTestRes=1280x720 changes the host's window size (HUD layout at other resolutions)
	if(!bTestResSet && ParseOption(TestOptions, "CoopTestRes") != "" && GetHost() != None)
	{
		bTestResSet = true;
		GetHost().ConsoleCommand("SETRES " $ ParseOption(TestOptions, "CoopTestRes") $ "w");
	}
	DetachClientMembers();
	EnsureClientGrenades();
	CheckAIBreach();
	CheckAISnipe();
	CheckStalledScripts();
	CheckIntroWatch();
	CheckIntroPositions();
	SyncTriggerLights();
	ResendCollisionTags();
	UnblockKarmaProps();
	CheckClientsBlocked();
	LogClientsStatus();
	CheckMissedEvents();
	CheckClientArrivals();
	CheckLiftRides();
	SyncSquadHealth();
	SyncObjectives();
	CheckClientSnipers();

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

		if(CP == None || IsHost(CP) || CP.bInBreach || CP.bIntroWatch)
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

	if(!bRemovedUplink && UplinkChecks < 300)
	{
		++UplinkChecks;
		RemoveUplink();
	}

	if(bSlowStart)
		CheckSlowStart();

	CheckScriptAnims();

	if(Level.TimeSeconds >= NextIdleStateSync)
	{
		NextIdleStateSync = Level.TimeSeconds + 0.2;
		SyncIdleStates(Level.TimeSeconds >= NextIdleStateResend);
		SyncPanelStates(Level.TimeSeconds >= NextIdleStateResend);
		SyncMapActorCollision();
		CheckDetonations();
		SyncPropEffects();
		CheckGather();

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

		/*
		 * A player who does the job of a squad marker himself (a client playing the specialist: Scorch places the charge to Fixer's
		 * door on GEO_01B) doesn't start the marker, so its events never came: the level waited for BrokenDoorDemoUnderway forever
		 * and the enemies of the next rooms were never spawned. The events are triggered as the marker would.
		 */
		if(Item.bActivating && !SentPanelStates[i].bMarkerEvents && Item.SquadMarker != None && !Item.SquadMarker.bMarkerActive &&
		   (Item.bPlayerActivated || PlayerController(Item.User) != None))
		{
			SentPanelStates[i].bMarkerEvents = true;
			Log("CoopGame: " $ Item $ " is used by a player instead of " $ Item.SquadMarker $ ", triggering its events " $ Item.SquadMarker.Event $ " " $ Item.SquadMarker.EventUnderway);

			if(Item.SquadMarker.Event != '')
				TriggerEvent(Item.SquadMarker.Event, Item.SquadMarker, UserPawn);

			if(Item.SquadMarker.EventUnderway != '')
				TriggerEvent(Item.SquadMarker.EventUnderway, Item.SquadMarker, UserPawn);
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
/*
 * Door breaches (from GEO_01C on): the host orders it as usual, but the AI can't do the maneuver with squad members played by clients.
 * The door is breached once every client playing a squad member is at the door, until then they are asked to gather.
 */
function bool IsSquadClient(Controller C)
{
	return CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None && C.Pawn.Health > 0 && InStr(string(C.Pawn.Class), "Delta") != -1;
}

function bool HasSquadClients()
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(IsSquadClient(C))
			return true;
	}

	return false;
}

// Called by CoopPlayer.Use: true if the order is handled here
function bool OrderDoorBreach(PlayerController Host, SquadMarker Marker, bool bCancel)
{
	if(Marker == None || !Marker.IsA('MarkerDoorBreach') || BreachDoor(Marker.Anchor) == None || !HasSquadClients())
		return false;

	if(bCancel || GatherMarker == Marker)
	{
		GatherMarker = None;
		Host.ClientMessage("Door breach cancelled");
		Log("CoopGame: door breach " $ Marker $ " cancelled");
		return true;
	}

	GatherMarker = Marker;
	NextGatherMessage = 0;
	Log("CoopGame: door breach " $ Marker $ " ordered, the squad gathers at " $ Marker.Anchor);
	return true;
}

function CheckGather()
{
	local Controller C;
	local int Total, Gathered;
	local string Text;

	if(GatherMarker == None)
		return;

	if(GatherMarker.Anchor == None || GatherMarker.Anchor.bDeleteMe || !GatherMarker.Anchor.IsInState('Locked') || GetHost() == None)
	{
		GatherMarker = None;
		return;
	}

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(IsSquadClient(C))
		{
			++Total;

			if(!C.Pawn.bIncapacitated && VSize(C.Pawn.Location - GatherMarker.Anchor.Location) < GatherDistance)
				++Gathered;
		}
	}

	if(Gathered < Total)
	{
		if(Level.TimeSeconds >= NextGatherMessage)
		{
			NextGatherMessage = Level.TimeSeconds + 4;
			Text = "Delta, gather at the door (" $ Gathered $ "/" $ Total $ ")";

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(PlayerController(C) != None)
					PlayerController(C).ClientMessage(Text);
			}
		}

		return;
	}

	Log("CoopGame: squad gathered at " $ GatherMarker.Anchor $ ", breaching");

	// Like in single player: the squad members of the clients go back to the AI for the breach (StartAIBreach)
	if(StartAIBreach(GatherMarker))
	{
		GatherMarker = None;
		return;
	}

	Log("CoopGame: the AI couldn't do the breach, the charge is placed at once");
	ActivateItem(GatherMarker.Anchor).User = GetHost();

	// The events the marker would trigger (see SyncPanelStates)
	if(GatherMarker.Event != '')
		TriggerEvent(GatherMarker.Event, GatherMarker, GetHost().Pawn);

	if(GatherMarker.EventUnderway != '')
		TriggerEvent(GatherMarker.EventUnderway, GatherMarker, GetHost().Pawn);

	GatherMarker.Anchor.GotoState('ChargeLocked');
	GatherMarker = None;
}

/*
 * Door breach with players: once the squad has gathered, the clients lose control, their squad members go back to the AI and the
 * squad does the breach with the single player animations (positions at the door, charge, grenade). The clients watch their member
 * over the shoulder and get it back as soon as the door blows (CheckAIBreach).
 */
function bool StartAIBreach(SquadMarker M)
{
	local PlayerController Host;
	local Controller C;
	local CoopPlayer CP;
	local Pawn P;
	local AIController AI;
	local bool bStarted;

	Host = GetHost();

	if(Host == None || Host.Pawn == None || Host.Pawn.Squad == None)
		return false;

	BreachPlayers.Length = 0;
	BreachPawns.Length = 0;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(!IsSquadClient(C) || C.Pawn.bIncapacitated || C.Pawn.ControllerClass == None)
			continue;

		CP = CoopPlayer(C);
		P = C.Pawn;
		AI = HandToAI(CP, P, Host);

		if(AI == None)
			continue;

		BreachPlayers[BreachPlayers.Length] = CP;
		BreachPawns[BreachPawns.Length] = P;
		CP.ClientCoopSetWatchFocus(M.Anchor.Location, true);
		CP.ClientMessage("Breaching the door");
		Log("CoopGame: " $ P $ " of " $ CP.PlayerReplicationInfo.PlayerName $ " goes to the AI " $ AI $ " for the breach");
	}

	BreachMarker = M;
	BreachStartTime = Level.TimeSeconds;
	bStarted = M.ExecuteMarker(Host.Pawn);
	Log("CoopGame: breach marker " $ M $ " executed: " $ bStarted $ " active=" $ M.bMarkerActive);

	if(!bStarted && !M.bMarkerActive)
	{
		EndAIBreach("the marker didn't start");
		return false;
	}

	return true;
}

function CheckAIBreach()
{
	local Actor Door;

	if(BreachMarker == None)
		return;

	Door = BreachMarker.Anchor;

	if(Door == None || Door.bDeleteMe || (!Door.IsInState('Locked') && !Door.IsInState('ChargeLocked')))
		EndAIBreach("the door blew");
	else if(Level.TimeSeconds - BreachStartTime > 8 && !BreachMarker.bMarkerActive && Door.IsInState('Locked'))
		EndAIBreach("the marker stopped");
	else if(Level.TimeSeconds - BreachStartTime > 45)
		EndAIBreach("it took too long");
}

function EndAIBreach(string Reason)
{
	local int i;
	local CoopPlayer CP;
	local Pawn P;
	local Controller AI;

	Log("CoopGame: breach over (" $ Reason $ "), the clients get their squad members back");

	for(i = 0; i < BreachPlayers.Length; i = i + 1)
		ReturnFromAI(BreachPlayers[i], BreachPawns[i]);

	BreachPlayers.Length = 0;
	BreachPawns.Length = 0;
	BreachMarker = None;
	DetachClientMembers();
}

/*
 * A scene that needs the squad member's AI (door breach, sniper): the client loses control, the member gets an AI controller of
 * its class again and joins the host's squad, the client watches over the shoulder. ReturnFromAI gives it back.
 */
function AIController HandToAI(CoopPlayer CP, Pawn P, PlayerController Host)
{
	local AIController AI;

	if(P.ControllerClass == None)
		return None;

	CP.UnPossess();
	AI = Spawn(P.ControllerClass);

	if(AI == None)
	{
		Log("CoopGame: no AI for " $ P $ ", the player keeps it");
		CP.Possess(P);
		return None;
	}

	AI.Possess(P);

	if(Host != None && Host.Pawn != None && Host.Pawn.Squad != None)
		Host.Pawn.Squad.AddToSquad(P);

	CP.bInBreach = true;
	StartWatching(CP, P, false);
	return AI;
}

function ReturnFromAI(CoopPlayer CP, Pawn P)
{
	local Controller AI;

	if(CP == None || CP.bDeleteMe)
		return;

	CP.bInBreach = false;
	CP.WatchedMember = None;
	CP.ClientCoopSetWatchFocus(vect(0,0,0), false);

	if(P == None || P.bDeleteMe || P.Health <= 0)
	{
		CP.GotoState('PlayerWalking');
		CP.ClientGotoState('PlayerWalking', '');
		CP.bBehindView = false;
		CP.ClientSetBehindView(false);
		RestartPlayer(CP);
		return;
	}

	AI = P.Controller;

	// Out of the squad while the AI still has it: CTSquadNative::RemoveAssignmentsByMember loops forever over assignments
	// (the breach) of a member whose controller isn't a CTBot (the host hung after the breach)
	if(P.Squad != None)
		P.Squad.RemoveFromSquad(P);

	if(AI != None && PlayerController(AI) == None)
	{
		AI.UnPossess();
		AI.Destroy();
	}

	CP.bCoopTakeover = true;
	CP.Possess(P);
	CP.bCoopTakeover = false;
	CP.bBehindView = false;
	CP.ClientSetBehindView(false);
	LinkPlayerAnims(P);
	P.SetWalking(false);
	P.ShouldCrouch(false);
	P.bWantsToCrouch = false;
	P.GroundSpeed = P.default.GroundSpeed;
	P.MaximumDesiredSpeed = P.default.MaximumDesiredSpeed;
	CP.ClientSetRotation(P.Rotation);
	CP.ClientSwitchToBestWeapon();
}

/*
 * The sniper scene (GEO_01C, Sun Fac's ship): Sev's script waits for the marker's EventUnderway (InSnipePosition), then for the ship
 * to take off (TakeOff) and shoots it. A client playing Sev walks to the position himself (CheckClientSnipers); the AI gets Sev only
 * for the shot: when the take off comes his level script is started at the action after that wait. When the script is past its
 * shots (or after 90 s) he gets Sev back.
 */
function bool FindSnipeShot(SquadMarker M)
{
	local ScriptedSequence Seq;
	local ACTION_WaitForEvent Wait;
	local int i, UnderwayIndex;

	SnipeShotScript = None;

	foreach AllActors(class'ScriptedSequence', Seq)
	{
		UnderwayIndex = -1;

		for(i = 0; i < Seq.Actions.Length; i = i + 1)
		{
			Wait = ACTION_WaitForEvent(Seq.Actions[i]);

			if(Wait != None && M.EventUnderway != '' && Wait.ExternalEvent == M.EventUnderway)
			{
				UnderwayIndex = i;
				break;
			}
		}

		if(UnderwayIndex == -1)
			continue;

		for(i = UnderwayIndex + 1; i + 1 < Seq.Actions.Length; i = i + 1)
		{
			Wait = ACTION_WaitForEvent(Seq.Actions[i]);

			if(Wait != None && Wait.ExternalEvent != '')
			{
				SnipeShotScript = Seq;
				SnipeShotIndex = i + 1;
				SnipeShotEvent = Wait.ExternalEvent;
				ListenForEvent(SnipeShotEvent);
				Log("CoopGame: the sniper shot of " $ M $ " comes after " $ SnipeShotEvent $ ", script " $ Seq $ " action " $ SnipeShotIndex $ " (" $ Seq.Actions[SnipeShotIndex].GetActionString() $ ")");
				return true;
			}
		}
	}

	Log("CoopGame: no script waits for " $ M.EventUnderway $ ", the client snipes himself");
	return false;
}

static function string UnderscoresToSpaces(string S)
{
	local string Result;

	while(InStr(S, "_") != -1)
	{
		Result = Result $ Left(S, InStr(S, "_")) $ " ";
		S = Mid(S, InStr(S, "_") + 1);
	}

	return Result $ S;
}

// The scripts of other actors waiting for the same event as Sev's shot (GEO_01C: Sun Fac's ship) that are still playing after it
function bool IsSnipeSceneRunning(ScriptedController SevAI)
{
	local ScriptedController Other;
	local int i;

	foreach DynamicActors(class'ScriptedController', Other)
	{
		if(Other == SevAI || Other.SequenceScript == None || !Other.IsInState('Scripting') || Other.ActionNum >= Other.SequenceScript.Actions.Length ||
		   Other.SequenceScript.Actions[Other.ActionNum] == None || Other.SequenceScript.Actions[Other.ActionNum].IsA('ACTION_WaitForEvent'))
			continue;

		for(i = 0; i < Other.ActionNum; i = i + 1)
		{
			if(ACTION_WaitForEvent(Other.SequenceScript.Actions[i]) != None && ACTION_WaitForEvent(Other.SequenceScript.Actions[i]).ExternalEvent == SnipeShotEvent)
				return true;
		}
	}

	return false;
}

function bool HasSnipeTask(CoopPlayer CP)
{
	local int i;

	// Also a moment after the scene (the camera comes back to Sev)
	if(SnipePlayer == CP || (SnipeEndTime > 0 && Level.TimeSeconds - SnipeEndTime < 30))
		return true;

	for(i = 0; i < ClientSnipeMarkers.Length; i = i + 1)
	{
		if(ClientSnipeMarkers[i] != None && ClientSnipeStates[i] != 3 && MarkerClient(ClientSnipeMarkers[i]) == CP)
			return true;
	}

	return false;
}

function bool IsConditionEnabled(name ConditionTag)
{
	local TriggeredCondition TC;

	if(ConditionTag == '')
		return false;

	foreach AllActors(class'TriggeredCondition', TC, ConditionTag)
		return TC.bEnabled;

	return false;
}

function bool StartAISnipe(CoopPlayer CP, Pawn P, SquadMarker M)
{
	local AIController AI;
	local ScriptedController SC;
	local Inventory Inv;

	if(SnipeShotScript == None || P == None)
		return false;

	// Not in the host's squad: the squad AI would make him follow the leader away from the position
	AI = HandToAI(CP, P, None);
	SC = ScriptedController(AI);

	if(SC == None)
	{
		if(AI != None)
			ReturnFromAI(CP, P);

		return false;
	}

	// Sev's script made him invulnerable at the start "to prevent the snipe event from getting screwed up", the new AI too
	SC.bGodMode = true;

	// The shot is the sniper rifle's (the AI squad member has one, the client's Sev only the blaster): lent for the scene
	SnipeLentRifle = None;

	for(Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		if(Weapon(Inv) != None && InStr(Caps(string(Inv.Class.Name)), "SNIPER") != -1)
			break;
	}

	if(Inv == None)
	{
		// The squad member's version: the player's rifle fired like an automatic in the hands of the AI
		SnipeLentRifle = P.CreateInventory("Properties.DC17mSniperCommando");

		if(SnipeLentRifle == None)
			SnipeLentRifle = P.CreateInventory("CTInventory.DC17mSniper");

		Log("CoopGame: Sev gets " $ SnipeLentRifle $ " for the scene");
	}

	for(Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		if(Weapon(Inv) != None && InStr(Caps(string(Inv.Class.Name)), "SNIPER") != -1 && Weapon(Inv).AmmoType != None && Weapon(Inv).AmmoType.HasAmmo())
		{
			Log("CoopGame: Sev takes " $ Inv.Class.Name $ " for the shot");

			// At once, without the animations (they played in the middle of the cutscene)
			if(P.Weapon != Inv)
			{
				P.PendingWeapon = Weapon(Inv);

				if(P.Weapon != None)
					P.Weapon.GotoState('');

				P.ChangedWeapon();
			}

			break;
		}
	}

	if(P.Weapon == None || InStr(Caps(string(P.PendingWeapon.Class.Name) $ string(P.Weapon.Class.Name)), "SNIPER") == -1)
	{
		for(Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
			Log("CoopGame: Sev's inventory: " $ Inv.Class $ " Ammo=" $ Weapon(Inv).AmmoType $ " " $ Weapon(Inv).AmmoType.AmmoAmount);
	}

	SC.SetNewScript(SnipeShotScript);
	SC.ActionNum = SnipeShotIndex;
	SnipeShotScript.SetActions(SC);
	SnipePlayer = CP;
	SnipePawn = P;
	SnipeMarker = M;
	SnipeScript = SnipeShotScript;
	SnipeStartTime = Level.TimeSeconds;
	bSnipeInPosition = true; // The client triggered the marker's events (CheckClientSnipers)
	bSnipeShot = false;
	CP.ClientMessage("Sev takes the shot");
	Log("CoopGame: " $ P $ " of " $ CP.PlayerReplicationInfo.PlayerName $ " goes to the AI " $ SC $ " for the shot of " $ M $ " (" $ SnipeShotEvent $ "), script " $ SnipeShotScript $ " from action " $ SnipeShotIndex);
	return true;
}

function CheckAISnipe()
{
	local ScriptedController SC, Other;
	local string Reason;

	if(SnipePawn == None)
		return;

	SC = ScriptedController(SnipePawn.Controller);

	if(SnipePawn.bDeleteMe || SnipePawn.Health <= 0)
		Reason = "Sev died";
	else if(SC == None || SC.SequenceScript != SnipeScript || SC.ActionNum >= SnipeScript.Actions.Length)
		Reason = "the script is over";
	else if(SnipeScript.Actions[SC.ActionNum] != None && (SnipeScript.Actions[SC.ActionNum].IsA('ACTION_Label') || SnipeScript.Actions[SC.ActionNum].IsA('ACTION_EndSection')) && Level.TimeSeconds - SnipeStartTime > 5)
		Reason = "the script reached " $ SnipeScript.Actions[SC.ActionNum].GetActionString();
	else if(SnipeScript.Actions[SC.ActionNum] != None && SnipeScript.Actions[SC.ActionNum].IsA('ACTION_ShootTarget') && SC.Target == None && bSnipeShot)
		Reason = "the target is gone";
	else if(Level.TimeSeconds - SnipeStartTime > 90)
		Reason = "it took too long";

	// Shooting: the action stays there after its target is gone (the ship shot down), that ends the scene
	if(SC != None && SC.Target != None && SnipeScript.Actions[SC.ActionNum] != None && SnipeScript.Actions[SC.ActionNum].IsA('ACTION_ShootTarget'))
		bSnipeShot = true;

	if(!bSnipeInPosition && SnipeMarker != None && SnipeMarker.Anchor != None && VSize(SnipePawn.Location - SnipeMarker.Anchor.Location) < 300)
	{
		bSnipeInPosition = true;
		Log("CoopGame: AI sniper in position, triggering " $ SnipeMarker.EventUnderway);

		if(SnipeMarker.EventUnderway != '')
			TriggerEvent(SnipeMarker.EventUnderway, SnipeMarker, SnipePawn);
	}

	if(Level.TimeSeconds >= NextSnipeLog)
	{
		NextSnipeLog = Level.TimeSeconds + 3;
		Log("CoopGame: AI sniper " $ SnipePawn $ " at " $ TestActionString(SnipePawn) $ " Loc=" $ SnipePawn.Location $ " Weapon=" $ SnipePawn.Weapon $ " Target=" $ SC.Target);

		// The other scripts of the scene (Sun Fac, his ship)
		foreach DynamicActors(class'ScriptedController', Other)
		{
			if(Other != SC && Other.SequenceScript != None && InStr(Caps(string(Other.SequenceScript.Tag)), "SUNFAC") != -1)
				Log("CoopGame: scene script " $ Other.SequenceScript.Tag $ " at " $ Other.ActionNum $ " " $ Other.Pawn $ " " $ Other.GetStateName());
		}
	}

	// Sev's part ends before the cutscene of the ship (its own script waits for the same take off): he stays with the AI until it
	// is over, otherwise the client got him in the middle of it
	if(Reason != "" && Reason != "Sev died" && Level.TimeSeconds - SnipeStartTime <= 90 && IsSnipeSceneRunning(SC))
		Reason = "";

	if(Reason == "")
		return;

	Log("CoopGame: sniper scene over (" $ Reason $ "), " $ SnipePlayer.PlayerReplicationInfo.PlayerName $ " gets Sev back");
	SnipeEndTime = Level.TimeSeconds;

	if(SnipeMarker != None && SnipeMarker.EventCompleted != '' && bSnipeInPosition)
		TriggerEvent(SnipeMarker.EventCompleted, SnipeMarker, SnipePawn);

	ReturnFromAI(SnipePlayer, SnipePawn);

	if(SnipeLentRifle != None && !SnipeLentRifle.bDeleteMe && SnipePawn != None)
	{
		if(SnipePawn.Weapon == SnipeLentRifle)
			SnipePawn.Weapon = None;

		SnipePawn.DeleteInventory(SnipeLentRifle);
		SnipeLentRifle.Destroy();
		SnipePlayer.ClientSwitchToBestWeapon();
	}

	SnipeLentRifle = None;
	SnipePawn = None;
	SnipePlayer = None;
	DetachClientMembers();
}

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

			if(A.DrawScale3D != A.default.DrawScale3D || A.PrePivot != A.default.PrePivot || A.Skins.Length > 0 || NeedsLookSync(A))
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

/*
 * More that the replicated copy of a map actor gets from the class defaults: the tag (GEO_03A: the shield of the jamming device was
 * "Prop" on clients, the forwarded hiding and collision by tag never found it), the ambient glow and the static lighting baked into
 * the map (StaticMeshInstance). Without the last two the shield was a flat yellow ball on clients, like the wall of GEO_01A.
 */
function bool NeedsLookSync(Actor A)
{
	return A.Tag != A.Class.Name || A.AmbientGlow != A.default.AmbientGlow || A.bUnlit != A.default.bUnlit || A.StaticMeshInstance != None;
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

		if(NeedsLookSync(A))
			CP.ClientCoopSetActorLook(A, A.Tag, A.AmbientGlow, A.bUnlit, string(A.StaticMeshInstance), A.Location.X, A.Location.Y, A.Location.Z, A.Rotation.Pitch, A.Rotation.Yaw, A.Rotation.Roll);

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

	// Not off a turret (it stays attached to it), not away from the sniper position it has to take (CheckClientSnipers)
	if(CP.Machine != None || CP.IsInState('PlayerManningTurret') || HasSnipeTask(CP))
		return false;

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
// Sev's state and the targets of his script (ACTION_ShootTarget)
function TestLogSnipe(Pawn P)
{
	local ScriptedSequence SS;
	local Actor A;
	local int i;
	local ScriptedController SC;
	local TriggeredCondition TC;
	local rotator R;

	Log("CoopTest: snipe: Marker state=" $ TestMarker.GetStateName() $ " active=" $ TestMarker.bMarkerActive $ " squad=" $ TestMarker.Squad $ " sevsquad=" $ P.Squad $ " participant=" $ TestMarker.Participants[0].Member $ " complete=" $ TestMarker.bComplete $ " SevToAnchor=" $ int(VSize(P.Location - TestMarker.Anchor.Location)));
	// Where the scripts of the scene are (every 10 seconds)
	if(TestStep % 10 == 5)
	{
		foreach DynamicActors(class'ScriptedController', SC)
		{
			if(SC.SequenceScript != None && SC.ActionNum < SC.SequenceScript.Actions.Length && SC.SequenceScript.Actions[SC.ActionNum] != None &&
			   (InStr(string(SC.SequenceScript.Tag), "SunFac") != -1 || SC.SequenceScript.IsA('ScriptedTrigger')))
				Log("CoopTest: snipe: script " $ SC.SequenceScript $ " Tag=" $ SC.SequenceScript.Tag $ " at " $ SC.ActionNum $ " " $ SC.SequenceScript.Actions[SC.ActionNum].GetActionString() $ " Pawn=" $ SC.Pawn);
		}

		foreach AllActors(class'TriggeredCondition', TC)
			Log("CoopTest: snipe: condition " $ TC.Tag $ " Enabled=" $ TC.bEnabled);
	}

	Log("CoopTest: snipe: Sev Controller=" $ P.Controller $ " State=" $ P.Controller.GetStateName() $ " Action=" $ TestActionString(P) $ " Weapon=" $ P.Weapon $
	    " Target=" $ P.Controller.Target $ " Enemy=" $ P.Controller.Enemy $ " Loc=" $ P.Location);

	foreach AllActors(class'ScriptedSequence', SS)
	{
		for(i = 0; i < SS.Actions.Length; i = i + 1)
		{
			if(ACTION_ShootTarget(SS.Actions[i]) != None)
			{
				foreach AllActors(class'Actor', A, ACTION_ShootTarget(SS.Actions[i]).TargetTag)
				{
					Log("CoopTest: snipe: " $ SS.Tag $ " action " $ i $ " target " $ A $ " (" $ A.Class $ ") Health=" $ A.GetPropertyText("Health") $ " Hidden=" $ A.bHidden $ " Loc=" $ A.Location);

					// The client playing Sev aims at the first target that is still there
					if(PlayerController(P.Controller) != None && ParseOption(TestOptions, "CoopTestShoot") != "" && !A.bHidden && A.GetPropertyText("Health") != "0")
					{
						R = rotator(A.Location - (P.Location + P.EyePosition()));
						PlayerController(P.Controller).ClientSetRotation(R);
					}
				}
			}
		}
	}
}

function Mover FindMoverByTag(name MoverTag)
{
	local Mover M;

	foreach AllActors(class'Mover', M, MoverTag)
		return M;

	return None;
}

function string TestActionString(Pawn P)
{
	local ScriptedController SC;

	SC = ScriptedController(P.Controller);

	if(SC == None || SC.SequenceScript == None || SC.ActionNum >= SC.SequenceScript.Actions.Length)
		return "none";

	return SC.ActionNum $ " " $ SC.SequenceScript.Actions[SC.ActionNum].GetActionString();
}

function string TestAnimString(Pawn P)
{
	local name Seq;
	local float Frame;

	P.GetAnimParams('', Seq, Frame);
	return Seq $ " " $ Frame;
}

function TickTest()
{
	local PlayerController Host;
	local Controller C;
	local string NextMap;
	local rotator R;
	local Pawn P, P2;
	local Projectile Proj;
	local Controller C2;
	local Actor A2;
	local int i;
	local ActivateItem A;
	local ScriptedController SC;
	local SquadMarker M;
	local Factory F;
	local Mover Mov;
	local TriggeredCondition TC;
	local ACTION_DestroyActor DA;
	local vector V, V2, HitLoc, HitNorm;
	local ScriptedSequence SS;
	local Counter Cnt;
	local Pickup Pick;
	local Turret Tur;
	local Inventory Inv;
	local string Str, Str2;

	// Test: CoopTestLag=<ms> simulates a network delay on the clients (engine command PktLag)
	if(ParseOption(TestOptions, "CoopTestLag") != "" || ParseOption(TestOptions, "CoopTestGPF") != "")
	{
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && !CoopPlayer(C).bTestLagSent && C.Pawn != None)
			{
				CoopPlayer(C).bTestLagSent = true;
				if(ParseOption(TestOptions, "CoopTestGPF") != "")
					CoopPlayer(C).ClientCoopTestLag(-1);
				else
					CoopPlayer(C).ClientCoopTestLag(int(ParseOption(TestOptions, "CoopTestLag")));
			}
		}
	}

	if(Level.TimeSeconds < TestTime)
		return;

	Host = GetHost();
	Log("CoopTest: Executing step " $ TestStep $ " of '" $ TestAction $ "'");

	if(TestAction ~= "travel")
	{
		// Travels to the next level; with CoopTestStopAt=<map> it stays there and logs where the commandos are every 3 s
		Host.GetCurrentMapName(NextMap);

		if(ParseOption(TestOptions, "CoopTestStopAt") ~= NextMap)
		{
			foreach DynamicActors(class'Pawn', P)
			{
				if(P.IsA('CloneCommando'))
					Log("CoopTest: travel: " $ TestStep $ " " $ P $ " (" $ P.Class.Name $ ") Physics=" $ P.Physics $ " Loc=" $ P.Location $ " Controller=" $ P.Controller $ " Action=" $ TestActionString(P));
			}

			foreach AllActors(class'ScriptedController', SC)
			{
				if(SC.SequenceScript != None && SC.Pawn == None && SC.ActionNum < SC.SequenceScript.Actions.Length && (SC.SequenceScript.Tag == 'BriefingSound' || SC.ActionNum > 0))
					Log("CoopTest: travel: " $ TestStep $ " script " $ SC.SequenceScript $ " (" $ SC.SequenceScript.Tag $ ") at " $ SC.ActionNum $ " " $ SC.SequenceScript.Actions[SC.ActionNum].GetActionString());
			}

			if(TestStep < 15)
			{
				TestTime = Level.TimeSeconds + 3;
				++TestStep;
				return;
			}
		}
		else if(TestStep == 0)
		{
			Host.GetNextLevel(Host.GetLevelIndex(NextMap), NextMap);
			CoopTravel(NextMap);
		}
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
			// Look at the host lying on the ground
			if(TestStep == 3)
			{
				V = Host.Pawn.Location - C.Pawn.Location;
				V.Z = 0;
				R = rotator(V);
				R.Pitch = (65536 - int(Atan(100.0, FMax(VSize(V), 50.0)) * 10430.0)) & 65535;
				C.SetRotation(R);
				C.ClientSetRotation(R);
				Log("CoopTest: clientrevive: aiming at the host " $ int(VSize(V)) $ " away, pitch " $ R.Pitch);
			}

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
			foreach AllActors(class'Actor', A2, 'SpawnControlRoom') { Log("CoopTest: door: factory " $ A2 $ " State=" $ A2.GetStateName()); break; }
			Log("CoopTest: door: Weapon=" $ C.Pawn.Weapon $ " WeaponState=" $ C.Pawn.Weapon.GetStateName() $ " Pending=" $ C.Pawn.PendingWeapon $ " Inv=" $ C.Pawn.Inventory $ " State=" $ TestPanel.GetStateName() $ " Usable=" $ TestPanel.bIsUsable $ " Activating=" $ TestPanel.bActivating $ " Fraction=" $ TestPanel.FractionComplete $ " ClientState=" $ C.GetStateName() $ " TargetType=" $ CoopPlayer(C).TargetType $ " Target=" $ CoopPlayer(C).Target);
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
	else if(TestAction ~= "scene")
	{
		// Triggers CoopTestEvent at step 0, then logs the script of squad member CoopTestMember and its watcher every 0.5 seconds
		foreach DynamicActors(class'Pawn', P2)
		{
			if(string(P2.Class) ~= ("CTCharacters.Commando" $ ParseOption(TestOptions, "CoopTestMember") $ "Delta"))
				P = P2;
		}

		// No string to name cast: actors waiting for the event have it as Tag
		if(TestStep == 0 && ParseOption(TestOptions, "CoopTestEvent") != "")
		{
			foreach AllActors(class'Actor', A2)
			{
				if(string(A2.Tag) ~= ParseOption(TestOptions, "CoopTestEvent"))
					A2.Trigger(self, Host.Pawn);
			}
		}

		if(P != None)
		{
			Log("CoopTest: scene: " $ P $ " Controller=" $ P.Controller $ " Action=" $ TestActionString(P) $ " Loc=" $ P.Location $ " Anim=" $ TestAnimString(P) $
			    " Watcher=" $ FindWatcher(P));
		}

		if(TestStep < 80)
		{
			TestTime = Level.TimeSeconds + 0.5;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "levelinfo" && TestStep == 0)
	{
		// Logs the squad markers and the scripts that wait for the squad
		foreach AllActors(class'TriggeredCondition', TC)
			Log("CoopTest: levelinfo: condition " $ TC $ " Tag=" $ TC.Tag $ " Enabled=" $ TC.bEnabled $ " Toggled=" $ TC.bToggled);

		foreach AllActors(class'SquadMarker', M)
			Log("CoopTest: levelinfo: marker " $ M.Class.Name $ " " $ M $ " Tag=" $ M.Tag $ " Event=" $ M.Event $ " Underway=" $ M.EventUnderway $ " Completed=" $ M.EventCompleted $ " Active=" $ M.bMarkerActive $ " Required=" $ M.MembersRequired $ " Anchor=" $ M.Anchor $ " Loc=" $ M.Location);

		foreach AllActors(class'Actor', A2)
		{
			if(A2.IsA('Factory') || A2.IsA('Trigger') || A2.IsA('TriggerVolume') || A2.IsA('Volume') && A2.Event != '')
				Log("CoopTest: levelinfo: actor " $ A2.Class.Name $ " " $ A2 $ " Tag=" $ A2.Tag $ " Event=" $ A2.Event $ " State=" $ A2.GetStateName() $ " Loc=" $ A2.Location);
		}

		foreach AllActors(class'ScriptedSequence', SS)
		{
			for(i = 0; i < SS.Actions.Length; i = i + 1)
			{
				if(SS.Actions[i] != None && !SS.Actions[i].IsA('ACTION_PlaySound') && !SS.Actions[i].IsA('ACTION_PlayAnim'))
					Log("CoopTest: levelinfo: " $ SS $ " Tag=" $ SS.Tag $ " " $ i $ " " $ SS.Actions[i].Class.Name $ " " $ SS.Actions[i].GetActionString());
			}
		}
	}
	else if(TestAction ~= "breach")
	{
		// GEO_01C: waits for the clients to play squad members, the host orders the door breach, then the clients come to the door one by one
		if(TestStep == 0)
		{
			i = 0;

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(IsSquadClient(C))
					++i;
			}

			foreach AllActors(class'SquadMarker', M)
			{
				if(M.IsA('MarkerDoorBreach'))
					TestMarker = M;
			}

			Log("CoopTest: breach: squad clients=" $ i $ " marker=" $ TestMarker);

			if(i < 3 || TestMarker == None)
			{
				TestTime = Level.TimeSeconds + 2;
				return;
			}

			R = TestMarker.Anchor.Rotation;
			R.Pitch = 0;
			Host.Pawn.SetLocation(TestMarker.Anchor.Location + vector(R) * 150 + vect(0,0,-40));
			Log("CoopTest: breach: order handled=" $ OrderDoorBreach(Host, TestMarker, false));
		}
		else if(TestStep % 4 == 0)
		{
			i = 0;

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(IsSquadClient(C) && VSize(C.Pawn.Location - TestMarker.Anchor.Location) >= GatherDistance)
				{
					R = TestMarker.Anchor.Rotation;
					R.Pitch = 0;
					R.Yaw += 6000 * TestStep / 4;
					C.Pawn.SetLocation(TestMarker.Anchor.Location + vector(R) * 250 + vect(0,0,-40));
					Log("CoopTest: breach: moved " $ C.PlayerReplicationInfo.PlayerName $ " to the door");
					break;
				}
			}
		}

		Log("CoopTest: breach: Gather=" $ GatherMarker $ " Door=" $ TestMarker.Anchor.GetStateName());

		if(TestStep < 30)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "assign" && TestStep == 0)
	{
		// Saving of squad assignments (see CoopConfig.SetSquadAssignment)
		class'CoopConfig'.static.SetSquadAssignment("test/A", "CTCharacters.Commando07Delta");
		class'CoopConfig'.static.SetSquadAssignment("test/B", "CTCharacters.Commando62Delta");
		class'CoopConfig'.static.SetSquadAssignment("test/C", "CTCharacters.Commando40Delta");
		Log("CoopTest: assign: " $ class'CoopConfig'.default.SquadAssignmentList $ " saved=" $ class'CoopNative'.static.ReadSavedString("ModCoop.ini", "ModCoop.Lists", "SquadAssignmentList"));
	}
	else if(TestAction ~= "snipe")
	{
		// GEO_01C: the host orders the snipe marker (step 0, repeated until it works), then Sev's script, weapon and targets are logged.
		// With CoopTestShoot=1 a client playing Sev is put on the sniper position and aimed at the target (it fires from its window).
		foreach DynamicActors(class'Pawn', P2)
		{
			if(P2.IsA('Commando07Delta'))
				P = P2;
		}

		foreach AllActors(class'SquadMarker', M)
		{
			if(M.IsA('MarkerSnipe'))
				TestMarker = M;
		}

		if(P == None || TestMarker == None)
		{
			Log("CoopTest: snipe: Sev=" $ P $ " Marker=" $ TestMarker);
			TestTime = Level.TimeSeconds + 2;
			return;
		}

		if(TestStep == 0)
		{
			Log("CoopTest: snipe: marker events underway=" $ TestMarker.EventUnderway $ " completed=" $ TestMarker.EventCompleted $ " event=" $ TestMarker.Event $ " anchor=" $ TestMarker.Anchor.Class $ " anchor tag=" $ TestMarker.Anchor.Tag $ " anchor event=" $ TestMarker.Anchor.Event);
			Log("CoopTest: snipe: marker visible=" $ TestMarker.AlwaysVisible $ " active=" $ TestMarker.bMarkerActive $ " Sev controller=" $ P.Controller $ " client=" $ MarkerClient(TestMarker));

			// CoopTestEvent=WindowDestroyed,SunFacRoomDoorOpened skips the window and the door of the strategy room, one event every
			// 6 seconds, then the level activates the marker
			if(!TestMarker.AlwaysVisible && TestEvents != "" && Level.TimeSeconds >= NextTestEvent)
			{
				NextTestEvent = Level.TimeSeconds + 6;

				if(InStr(TestEvents, ",") != -1)
				{
					NextMap = Left(TestEvents, InStr(TestEvents, ","));
					TestEvents = Mid(TestEvents, InStr(TestEvents, ",") + 1);
				}
				else
				{
					NextMap = TestEvents;
					TestEvents = "";
				}

				Log("CoopTest: snipe: triggering " $ NextMap);

				foreach AllActors(class'Actor', A2)
				{
					if(string(A2.Tag) ~= NextMap)
						A2.Trigger(self, Host.Pawn);
				}
			}

			// CoopTestChain=1 plays the level up to the marker: the window of the strategy room is shot, the door to Sun Fac breached
			if(!TestMarker.AlwaysVisible && ParseOption(TestOptions, "CoopTestChain") != "" && Level.TimeSeconds >= NextTestEvent)
			{
				for(C = Level.ControllerList; C != None; C = C.nextController)
				{
					if(PlayerController(C) != None)
						PlayerController(C).bGodMode = true;
				}

				if(TestChainStage == 0)
				{
					foreach AllActors(class'Actor', A2)
					{
						if(Prop(A2) != None && (Prop(A2).DestroyedState.Event == 'WindowDestroyed' || Prop(A2).DamagedState.Event == 'WindowDestroyed'))
						{
							Log("CoopTest: snipe: shooting " $ A2 $ " (" $ A2.Class $ ")");
							A2.TakeDamage(100000, Host.Pawn, A2.Location, vect(0,0,0), class'DamageType');
						}
					}

					TestChainStage = 1;
					NextTestEvent = Level.TimeSeconds + 20;
				}
				else if(TestChainStage == 1)
				{
					foreach AllActors(class'SquadMarker', M)
					{
						if(M.IsA('MarkerDoorBreach') && M.Anchor != None && M.Anchor.IsInState('Locked'))
						{
							Log("CoopTest: snipe: breaching " $ M.Anchor);
							ActivateItem(M.Anchor).User = Host;
							M.Anchor.GotoState('ChargeLocked');
						}
					}

					TestChainStage = 2;
				}
			}

			// Sun Fac has to wait at his ship before Sev is on the marker, otherwise he misses SunFacRunToShip (Sev is moved there at once)
			foreach DynamicActors(class'ScriptedController', SC)
			{
				// CoopTestRush=1 doesn't wait (see CheckMissedEvents)
				if(SC.SequenceScript != None && SC.SequenceScript.Tag == 'SunFacAI' && SC.ActionNum < 16 && ParseOption(TestOptions, "CoopTestRush") == "")
				{
					Log("CoopTest: snipe: Sun Fac at " $ SC.ActionNum);
					TestTime = Level.TimeSeconds + 2;
					return;
				}
			}

			if(!TestMarker.AlwaysVisible)
			{
				Log("CoopTest: snipe: Sev " $ TestActionString(P) $ " Health=" $ P.Health $ " Incap=" $ P.bIncapacitated $ " Physics=" $ P.Physics $ " Loc=" $ P.Location);
				TestTime = Level.TimeSeconds + 2;
				return;
			}

			if(PlayerController(P.Controller) != None)
			{
				if(ParseOption(TestOptions, "CoopTestShoot") != "" && TestStep == 0 && TestHostLocation == vect(0,0,0))
				{
					TestHostLocation = Host.Pawn.Location;
					P.SetLocation(TestMarker.Location + vect(0,150,60));
					Log("CoopTest: snipe: moved the client playing Sev to " $ P.Location);
				}
			}
			else
			{
				// Like a player who walked to the balcony and gives the order there
				TestHostLocation = Host.Pawn.Location;
				Host.Pawn.SetLocation(TestMarker.Location + vect(0,0,60));
				i = 0;

				foreach DynamicActors(class'Pawn', P2)
				{
					// Only Sev, the marker takes the closest member
					if(P2 == P)
					{
						P2.SetLocation(TestMarker.Location + vect(0,150,0) - vect(0,0,1) * (TestMarker.Location.Z - Host.Pawn.Location.Z));

						Log("CoopTest: snipe: moved " $ P2 $ " to " $ P2.Location);
					}
				}

				R.Yaw = 0;
				Log("CoopTest: snipe: host at " $ Host.Pawn.Location $ " anchor at " $ TestMarker.Anchor.Location);
				TestMarker.NotifyTargeted(Host);
				Log("CoopTest: snipe: ExecuteMarker=" $ TestMarker.ExecuteMarker(Host.Pawn));
			}
		}

		// The host steps back from the sniper position once the order is given
		if(TestHostLocation != vect(0,0,0) && TestMarker.IsInState('Setup'))
		{
			Host.Pawn.SetLocation(TestHostLocation);
			TestHostLocation = vect(0,0,0);
			Log("CoopTest: snipe: host moved back to " $ Host.Pawn.Location);
		}

		// The marker is disabled for a moment after the squad was moved: the order is repeated
		if(TestStep > 0 && TestStep < 30 && PlayerController(P.Controller) == None && !TestMarker.bMarkerActive && TestMarker.IsInState('Enabled'))
		{
			TestMarker.NotifyTargeted(Host);
			Log("CoopTest: snipe: ExecuteMarker again=" $ TestMarker.ExecuteMarker(Host.Pawn));
		}

		TestLogSnipe(P);

		if(TestStep < 150)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "charge")
	{
		// The first client places the charge with tag CoopTestPanelTag and detonates it (keys in its window, test script);
		// the server side state of the client is logged every 0.5 s
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None)
		{
			TestTime = Level.TimeSeconds + 1;
			return;
		}

		if(TestStep == 0)
		{
			TestPanel = None;

			foreach DynamicActors(class'ActivateItem', A)
			{
				if(string(A.Tag) ~= ParseOption(TestOptions, "CoopTestPanelTag"))
					TestPanel = A;
			}

			if(TestPanel == None)
			{
				Log("CoopTest: charge: no panel with tag " $ ParseOption(TestOptions, "CoopTestPanelTag"));
				TestAction = "";
				return;
			}

			if(TestPanel.IsInState('Disabled'))
			{
				TestPanel.bIsUsableByPlayer = true;
				TestPanel.GotoState('Unplaced');
			}

			R = TestPanel.Rotation;
			R.Pitch = 0;
			C.Pawn.SetLocation(TestPanel.Location + vector(R) * 80 + vect(0,0,-40));
			R = rotator(TestPanel.Location - C.Pawn.Location);
			R.Pitch = 0;
			C.ClientSetLocation(C.Pawn.Location, R);
			C.ClientSetRotation(R);
			C.bGodMode = true;
			Log("CoopTest: charge: " $ C.PlayerReplicationInfo.PlayerName $ " at " $ TestPanel $ " State=" $ TestPanel.GetStateName());
		}

		Log("CoopTest: charge: " $ TestStep $ " PC=" $ C.GetStateName() $ " Phys=" $ C.Pawn.Physics $ " Loc=" $ C.Pawn.Location $ " Vel=" $ int(VSize(C.Pawn.Velocity)) $ " Acc=" $ int(VSize(C.Pawn.Acceleration)) $ " Incap=" $ C.Pawn.bIncapacitated $ " Weapon=" $ C.Pawn.Weapon $ " WState=" $ C.Pawn.Weapon.GetStateName() $ " Base=" $ C.Pawn.Base $ " Panel=" $ TestPanel.GetStateName() $ " Activating=" $ TestPanel.bActivating $ " Target=" $ C.Target $ " Walking=" $ C.Pawn.bIsWalking $ " Speed=" $ C.Pawn.GroundSpeed);

		// After the explosion: what blocks players at CoopTestAt (radius 500) on the server and on the clients
		if((TestStep == 40 || TestStep == 79) && ParseOption(TestOptions, "CoopTestAt") != "")
		{
			V = vector(ParseOption(TestOptions, "CoopTestAt"));

			foreach AllActors(class'Actor', A2)
			{
				if(A2.bCollideActors && (A2.bBlockPlayers || A2.bBlockActors) && !A2.bStatic && Pawn(A2) == None && VSize(A2.Location - V) < 500)
					Log("CoopTest: probe: server " $ TestStep $ " " $ A2 $ " (" $ A2.Class $ ") Tag=" $ A2.Tag $ " State=" $ A2.GetStateName() $ " Hidden=" $ A2.bHidden $ " Role=" $ A2.RemoteRole $ " Mesh=" $ A2.StaticMesh $ " Loc=" $ A2.Location $ " Dist=" $ int(VSize(A2.Location - V)));
			}

			for(C2 = Level.ControllerList; C2 != None; C2 = C2.nextController)
			{
				if(CoopPlayer(C2) != None && !IsHost(C2))
					CoopPlayer(C2).ClientCoopProbe(V, 500, TestStep);
			}
		}

		if(TestStep < 80)
		{
			TestTime = Level.TimeSeconds + 0.5;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "goto" && TestStep <= int(ParseOption(TestOptions, "CoopTestGotoStep")))
	{
		// Moves the first client to CoopTestAt, facing CoopTestDir (the test script then walks it), after CoopTestGotoStep seconds
		if(TestStep < int(ParseOption(TestOptions, "CoopTestGotoStep")))
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None)
		{
			TestTime = Level.TimeSeconds + 1;
			return;
		}

		R = rotator(vector(ParseOption(TestOptions, "CoopTestDir")));
		C.Pawn.SetLocation(vector(ParseOption(TestOptions, "CoopTestAt")));
		C.ClientSetLocation(C.Pawn.Location, R);
		C.bGodMode = true;
		Log("CoopTest: goto: " $ C.PlayerReplicationInfo.PlayerName $ " (" $ C.Pawn.Class $ ") at " $ C.Pawn.Location);
	}
	else if(TestAction ~= "turret")
	{
		// The first client mans the nearest player turret at step 3 (as if it pressed use), fires from step 6 to 9 (CoopTestFireKey is
		// pressed by the test script), leaves at step 14; turret, weapon and projectiles are logged every second
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C != None && TestTurret == None)
		{
			foreach DynamicActors(class'Turret', Tur)
			{
				if(Tur.bPlayerUsable && Tur.Health > 0 && !Tur.IsA('AutoTurret') && Tur.NavPts.Length > 0 && (ParseOption(TestOptions, "CoopTestTurret") == "" || string(Tur.Class.Name) ~= ParseOption(TestOptions, "CoopTestTurret")) && (TestTurret == None || VSize(Tur.Location - C.Pawn.Location) < VSize(TestTurret.Location - C.Pawn.Location)))
					TestTurret = Tur;
			}

			Log("CoopTest: turret: " $ TestTurret $ " (" $ TestTurret.Class $ ")");
		}

		if(C != None && TestTurret != None)
		{
			if(TestStep == 1)
			{
				C.Pawn.SetLocation(TestTurret.NavPts[0].Location);
				C.ClientSetLocation(C.Pawn.Location, C.Pawn.Rotation);
				C.bGodMode = true;
			}

			if(TestStep == 3 || TestStep == 14)
				CoopPlayer(C).ServerCoopUseTurret(TestTurret);

			// Fire like the player (console command on the client) and turn as the client would send it
			if(TestStep == 6)
				CoopPlayer(C).ClientCoopTestCommand("HoldFire");

			if(TestStep == 7)
				CoopPlayer(C).ServerCoopTurretAim(6000, -1500);

			if(TestStep == 9)
				CoopPlayer(C).ClientCoopTestCommand("ReleaseFire");

			Log("CoopTest: turret: " $ TestStep $ " Gunner=" $ TestTurret.Gunner $ " Yaw=" $ TestTurret.Yaw $ " Pitch=" $ TestTurret.Pitch $ " State=" $ C.GetStateName() $
			    " Machine=" $ C.Machine $ " Weapon=" $ C.Pawn.Weapon.Class.Name $ " (" $ C.Pawn.Weapon.GetStateName() $ ") Ammo=" $ C.Pawn.Weapon.AmmoType.AmmoAmount $ " Hidden=" $ TestTurret.bHidden $ " PawnLoc=" $ C.Pawn.Location);

			i = 0;

			foreach DynamicActors(class'Projectile', Proj)
			{
				if(VSize(Proj.Location - TestTurret.Location) < 4000 && i < 3)
				{
					++i;
					Log("CoopTest: turret: projectile " $ Proj.Class.Name $ " at " $ Proj.Location $ " dist from turret " $ int(VSize(Proj.Location - TestTurret.Location)) $ " dir " $ Normal(Proj.Velocity) $ " Instigator=" $ Proj.Instigator);
				}
			}
		}

		// While firing: 10 checks a second for the projectiles
		if(TestStep >= 7 && TestStep <= 8 && ++TestSubStep % 10 != 0)
		{
			TestTime = Level.TimeSeconds + 0.1;
			return;
		}

		if(TestStep < 20)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "weaponpickup")
	{
		// Weapon pickups of a client: at steps 8 and 20 a pickup of CoopTestPickup (then CoopTestPickup2) is used by the first
		// client's pawn on the server; the server's view of its weapons is logged every second
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C != None && (TestStep == 8 || TestStep == 20))
		{
			if(TestStep == 8)
				Str = ParseOption(TestOptions, "CoopTestPickup");
			else
				Str = ParseOption(TestOptions, "CoopTestPickup2");

			Pick = Spawn(class<Pickup>(DynamicLoadObject(Str, class'Class')),,, C.Pawn.Location + vector(C.Pawn.Rotation) * 60);

			if(Pick != None)
				Log("CoopTest: weaponpickup: " $ Pick $ " used by " $ C.Pawn $ ": " $ Pick.PickupUsedBy(C.Pawn));
			else
				Log("CoopTest: weaponpickup: couldn't spawn " $ Str);
		}

		// CoopTestSwitch (comma separated, one per second from step 4): console commands of the client (_ for spaces), - for none
		Str = ParseOption(TestOptions, "CoopTestSwitch");

		for(i = 0; C != None && i < 30 && Str != ""; i = i + 1)
		{
			if(i == TestStep - 4)
			{
				if(InStr(Str, ",") != -1)
					Str = Left(Str, InStr(Str, ","));

				if(Str != "-")
					CoopPlayer(C).ClientCoopTestCommand(UnderscoresToSpaces(Str));

				break;
			}

			if(InStr(Str, ",") == -1)
				Str = "";
			else
				Str = Mid(Str, InStr(Str, ",") + 1);
		}

		if(C != None)
		{
			Str = "";

			for(Inv = C.Pawn.Inventory; Inv != None; Inv = Inv.Inventory)
				Str = Str $ " " $ Inv.Class.Name $ "(" $ Inv.GetStateName() $ ")";

			Log("CoopTest: weaponpickup: " $ TestStep $ " Weapon=" $ C.Pawn.Weapon.Class.Name $ " State=" $ C.Pawn.Weapon.GetStateName() $ " Pending=" $ C.Pawn.PendingWeapon.Class.Name $
			    " Tossable=" $ C.Pawn.CurrentTossableWeapon.Class.Name $ " Inv:" $ Str);
		}

		if(TestStep < 40)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "arrive")
	{
		// Arrivals (see ScanArrivals): triggers the events of CoopTestEvent (comma separated) at step 5 and of CoopTestEvent2 at
		// step 30, from step 34 every 4 s moves each client to the next point it has to arrive at; logs the counters' events
		if(TestStep == 0)
		{
			foreach AllActors(class'Counter', Cnt)
			{
				if(Cnt.Event != '')
					ListenForEvent(Cnt.Event);
			}
		}

		// The clients stand around until they are moved, the fights of the level would kill them
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				C.bGodMode = true;
		}

		if(TestStep == 5 || TestStep == 30)
		{
			if(TestStep == 5)
				Str = ParseOption(TestOptions, "CoopTestEvent");
			else
				Str = ParseOption(TestOptions, "CoopTestEvent2");

			while(Str != "")
			{
				Str2 = Str;

				if(InStr(Str, ",") != -1)
				{
					Str2 = Left(Str, InStr(Str, ","));
					Str = Mid(Str, InStr(Str, ",") + 1);
				}
				else
					Str = "";

				foreach AllActors(class'Actor', A2)
				{
					if(string(A2.Tag) ~= Str2)
						A2.Trigger(self, Host.Pawn);
				}

				Log("CoopTest: arrive: triggered " $ Str2);
			}
		}

		if(TestStep >= 34 && TestStep % 4 == 2)
		{
			for(i = 0; i < ArrivalPawns.Length; i = i + 1)
			{
				if(ArrivalDone[i] == 0 && ArrivalPawns[i] != None && ArrivalPoints[i] != None && CoopPlayer(ArrivalPawns[i].Controller) != None &&
				   WasHeard(ArrivalArmEvents[i]) && VSize(ArrivalPawns[i].Location - ArrivalPoints[i].Location) > ArrivalRadius)
				{
					ArrivalPawns[i].Controller.bGodMode = true;
					ArrivalPawns[i].SetLocation(ArrivalPoints[i].Location + vect(0,0,40));
					PlayerController(ArrivalPawns[i].Controller).ClientSetLocation(ArrivalPawns[i].Location, ArrivalPawns[i].Rotation);
					Log("CoopTest: arrive: moved " $ ArrivalPawns[i] $ " to " $ ArrivalPoints[i] $ " Dist=" $ VSize(ArrivalPawns[i].Location - ArrivalPoints[i].Location));
				}
			}
		}

		if(TestStep % 10 == 0)
		{
			for(i = 0; i < ArrivalPawns.Length; i = i + 1)
				Log("CoopTest: arrive: " $ TestStep $ " " $ ArrivalPawns[i] $ " Controller=" $ ArrivalPawns[i].Controller $ " " $ ArrivalArmEvents[i] $ "->" $ ArrivalEvents[i] $ " Heard=" $ WasHeard(ArrivalArmEvents[i]) $ " Done=" $ ArrivalDone[i]);

			foreach AllActors(class'Counter', Cnt)
				Log("CoopTest: arrive: " $ TestStep $ " " $ Cnt $ " Tag=" $ Cnt.Tag $ " Left=" $ Cnt.NumToCount $ " Event=" $ Cnt.Event);
		}

		if(TestStep < 90)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "wall")
	{
		// GEO_01B hangar: triggers CoopTestEvent (e.g. HangarDoorHacked) at step 2, moves the first client to CoopTestAt facing
		// CoopTestDir at step 4 (the script walks it), logs what blocks at CoopTestProbe on the server and the clients at steps 3 and 12
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(TestStep == 2 && ParseOption(TestOptions, "CoopTestEvent") != "")
		{
			foreach AllActors(class'Actor', A2)
			{
				if(string(A2.Tag) ~= ParseOption(TestOptions, "CoopTestEvent"))
					A2.Trigger(self, Host.Pawn);
			}

			Log("CoopTest: wall: triggered " $ ParseOption(TestOptions, "CoopTestEvent"));
		}

		if(TestStep == 4 && C != None)
		{
			R = rotator(vector(ParseOption(TestOptions, "CoopTestDir")));
			C.Pawn.SetLocation(vector(ParseOption(TestOptions, "CoopTestAt")));
			C.ClientSetLocation(C.Pawn.Location, R);
			C.bGodMode = true;
			Log("CoopTest: wall: moved " $ C.PlayerReplicationInfo.PlayerName $ " to " $ C.Pawn.Location);
		}

		if(TestStep == 3 || TestStep == 12)
		{
			V = vector(ParseOption(TestOptions, "CoopTestProbe"));

			foreach AllActors(class'Actor', A2)
			{
				if(A2.bCollideActors && (A2.bBlockPlayers || A2.bBlockActors) && Pawn(A2) == None && (VSize(A2.Location - V) < 500 || Volume(A2) != None || Mover(A2) != None))
					Log("CoopTest: probe: server " $ TestStep $ " " $ A2 $ " (" $ A2.Class $ ") Tag=" $ A2.Tag $ " State=" $ A2.GetStateName() $ " Hidden=" $ A2.bHidden $ " Role=" $ A2.RemoteRole $ " Static=" $ A2.bStatic $ " Block=" $ A2.bBlockActors $ A2.bBlockPlayers $ " Mesh=" $ A2.StaticMesh $ " Loc=" $ A2.Location $ " Dist=" $ int(VSize(A2.Location - V)));
			}

			for(C2 = Level.ControllerList; C2 != None; C2 = C2.nextController)
			{
				if(CoopPlayer(C2) != None && !IsHost(C2))
					CoopPlayer(C2).ClientCoopProbe(V, 500, TestStep);
			}
		}

		if(C != None && TestStep >= 4)
			Log("CoopTest: wall: " $ TestStep $ " server Loc=" $ C.Pawn.Location $ " Accel=" $ C.Pawn.Acceleration);

		if(TestStep < 16)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "movers")
	{
		// Movers that move (or near CoopTestAt) and all running scripts, every 2 s
		foreach AllActors(class'Mover', Mov)
		{
			if(Mov.bInterpolating || Mov.Velocity != vect(0,0,0) || TestStep == 0)
				Log("CoopTest: movers: " $ TestStep $ " " $ Mov $ " Tag=" $ Mov.Tag $ " Event=" $ Mov.Event $ " State=" $ Mov.GetStateName() $ " Key=" $ Mov.KeyNum $ "/" $ Mov.NumKeys $ " Moving=" $ Mov.bInterpolating $ " Loc=" $ Mov.Location $ " NoDelete=" $ Mov.bNoDelete $ " Static=" $ Mov.bStatic $ " Role=" $ Mov.RemoteRole);
		}

		foreach AllActors(class'Actor', A2)
		{
			if(TestStep % 10 == 0 && (A2.Tag == 'ShutoffElevatorLights' || A2.Tag == 'TriggerLightElevator' || A2.Tag == 'ElevatorLightMover' || A2.Base == FindMoverByTag('ElevatorLightMover') || A2.Owner == FindMoverByTag('ElevatorLightMover')))
				Log("CoopTest: movers: " $ TestStep $ " related " $ A2 $ " Class=" $ A2.Class $ " Tag=" $ A2.Tag $ " State=" $ A2.GetStateName() $ " Hidden=" $ A2.bHidden $ " Role=" $ A2.RemoteRole $ " Static=" $ A2.bStatic $ " Light=" $ A2.LightType $ "/" $ A2.LightBrightness $ " Base=" $ A2.Base $ " Loc=" $ A2.Location);
		}

		foreach AllActors(class'ScriptedSequence', SS)
		{
			for(i = 0; TestStep == 0 && i < SS.Actions.Length; i = i + 1)
			{
				DA = ACTION_DestroyActor(SS.Actions[i]);

				if(DA != None)
					Log("CoopTest: movers: destroy action " $ SS $ " " $ i $ " DestroyTag=" $ DA.DestroyTag);
			}
		}

		foreach AllActors(class'ScriptedController', SC)
		{
			if(SC.SequenceScript != None && SC.ActionNum < SC.SequenceScript.Actions.Length)
				Log("CoopTest: movers: " $ TestStep $ " script " $ SC $ " Pawn=" $ SC.Pawn $ " Sequence=" $ SC.SequenceScript $ " State=" $ SC.GetStateName() $ " Action " $ SC.ActionNum $ " " $ SC.SequenceScript.Actions[SC.ActionNum].GetActionString());
		}

		if(TestStep < 30)
		{
			TestTime = Level.TimeSeconds + 2;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "probe")
	{
		// Collision on the server around CoopTestAt=x,y,z: blocking actors and traces along CoopTestDir=x,y,z, every 10 s
		V = vector(ParseOption(TestOptions, "CoopTestAt"));
		V2 = Normal(vector(ParseOption(TestOptions, "CoopTestDir")));

		foreach AllActors(class'Actor', A2)
		{
			if(A2.bCollideActors && (A2.bBlockActors || A2.bBlockPlayers) && (VSize(A2.Location - V) < 600 || (Mover(A2) != None && VSize(A2.Location - V) < 2000)))
				Log("CoopTest: probe: " $ TestStep $ " " $ A2 $ " Class=" $ A2.Class $ " State=" $ A2.GetStateName() $ " Loc=" $ A2.Location $ " Dist=" $ int(VSize(A2.Location - V)) $ " Hidden=" $ A2.bHidden $ " Block=" $ A2.bBlockActors $ A2.bBlockPlayers $ " Size=" $ A2.CollisionRadius $ "/" $ A2.CollisionHeight $ " Mesh=" $ A2.StaticMesh $ " Role=" $ A2.RemoteRole);
		}

		foreach DynamicActors(class'ActivateItem', A)
		{
			if(VSize(A.Location - V) < 1500)
				Log("CoopTest: probe: " $ TestStep $ " panel " $ A $ " Tag=" $ A.Tag $ " State=" $ A.GetStateName() $ " Loc=" $ A.Location $ " Dist=" $ int(VSize(A.Location - V)));
		}

		for(i = -2; i <= 2; i = i + 1)
		{
			A2 = Trace(HitLoc, HitNorm, V + V2 * 400 + vect(0,0,30) * i, V + vect(0,0,30) * i, true, vect(20,20,0));
			Log("CoopTest: probe: " $ TestStep $ " trace height " $ (30 * i) $ " hit " $ A2 $ " at " $ HitLoc $ " dist " $ int(VSize(HitLoc - V - vect(0,0,30) * i)));
		}

		if(TestStep < 3)
		{
			TestTime = Level.TimeSeconds + 10;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "factories")
	{
		// What the factories have spawned (see CoopExtension.FactoryGenerateActor), every 10 s
		foreach DynamicActors(class'Factory', F)
			Log("CoopTest: factories: " $ TestStep $ " " $ F $ " Mode=" $ F.SpawnMode $ " State=" $ F.GetStateName() $ " Alive=" $ F.SpawnedActors.Length $ " Remaining=" $ F.RemainingItems $ " Prototype=" $ F.InternalPrototype);

		if(TestStep < 3)
		{
			TestTime = Level.TimeSeconds + 10;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "squadicons" && TestStep == 0)
	{
		// HUD icons of the squad members (see CoopHUD.DrawCoopSquad)
		for(i = 0; Host.Pawn.Squad != None && i < Host.Pawn.Squad.SquadMembers.Length; i = i + 1)
			Log("CoopTest: squadicons: " $ Host.Pawn.Squad.SquadMembers[i].Pawn $ " X=" $ Host.Pawn.Squad.SquadMembers[i].HUDIconX $ " Y=" $ Host.Pawn.Squad.SquadMembers[i].HUDIconY $ " Slot=" $ Host.Pawn.Squad.SquadMembers[i].Pawn.SquadHUDSlot);

		Log("CoopTest: squadicons: host slot=" $ Host.Pawn.SquadHUDSlot $ " leader=" $ Host.Pawn.Squad.SquadLeader);
	}
	else if(TestAction ~= "propinfo")
	{
		// Destructible props on the server and on the clients; step 2 destroys the props with CoopTestProp in their tag or name
		foreach AllActors(class'Actor', A2)
		{
			if(Prop(A2) != None)
				Log("CoopTest: propinfo: server " $ TestStep $ " " $ A2 $ " Tag=" $ A2.Tag $ " State=" $ A2.GetStateName() $ " Collide=" $ A2.bCollideActors $ A2.bBlockActors $ A2.bBlockPlayers $ " Hidden=" $ A2.bHidden $ " Mesh=" $ A2.StaticMesh $ " Role=" $ A2.RemoteRole $ " Static=" $ A2.bStatic $ " NoDelete=" $ A2.bNoDelete $ " Relevant=" $ A2.bAlwaysRelevant $ " Physics=" $ A2.Physics $ " Loc=" $ A2.Location $ " Rot=" $ A2.Rotation $
				    " Skins=" $ A2.Skins.Length $ " " $ A2.Skins[0] $ " Style=" $ A2.Style $ " Unlit=" $ A2.bUnlit $ " Glow=" $ A2.AmbientGlow $ " Zone=" $ A2.Region.Zone $ " Instance=" $ A2.StaticMeshInstance);
		}

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				CoopPlayer(C).ClientCoopDumpProps(TestStep);
		}

		// CoopTestDestroyTag: destroyed at step 1 like ACTION_DestroyActor does
		if(TestStep == 1 && ParseOption(TestOptions, "CoopTestDestroyTag") != "")
		{
			foreach AllActors(class'Actor', A2)
			{
				if(string(A2.Tag) ~= ParseOption(TestOptions, "CoopTestDestroyTag"))
					Log("CoopTest: propinfo: destroying " $ A2 $ ": " $ A2.Destroy());
			}
		}

		if(TestStep == 1 && ParseOption(TestOptions, "CoopTestProp") != "")
		{
			foreach AllActors(class'Actor', A2)
			{
				if(Prop(A2) != None && (InStr(Caps(string(A2.Tag)), Caps(ParseOption(TestOptions, "CoopTestProp"))) != -1 || InStr(Caps(string(A2)), Caps(ParseOption(TestOptions, "CoopTestProp"))) != -1))
				{
					Log("CoopTest: propinfo: destroying " $ A2);
					A2.Trigger(self, Host.Pawn);
					A2.TakeDamage(100000, Host.Pawn, A2.Location, vect(0,0,0), class'DamageType');
				}
			}
		}

		if(TestStep < 2)
		{
			TestTime = Level.TimeSeconds + 8;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "squadinfo")
	{
		// Logs the commandos of the level and their squads every 2 seconds
		foreach DynamicActors(class'Pawn', P)
		{
			if(P.IsA('CloneCommando'))
				Log("CoopTest: squadinfo: " $ TestStep $ " " $ P $ " Physics=" $ P.Physics $ " Squad=" $ P.Squad $ " HostSquad=" $ Host.Pawn.Squad $ " Controller=" $ P.Controller $ " Hidden=" $ P.bHidden $ " Health=" $ P.Health $ " Loc=" $ P.Location $ " HostLoc=" $ Host.Pawn.Location);
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
	else if(TestAction ~= "grenade")
	{
		// Logs the grenades of the first client while it throws some (right mouse button in its window)
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(TestStep == 0 && C != None && (ParseOption(TestOptions, "CoopTestNoGrenade") != "" || ParseOption(TestOptions, "CoopTestClearGrenade") != ""))
		{
			Log("CoopTest: grenade: removing the current grenade " $ C.Pawn.CurrentGrenade $ " on the server");
			C.Pawn.CurrentGrenade = None;
		}

		if(C != None)
			Log("CoopTest: grenade: server Weapon=" $ C.Pawn.Weapon $ " State=" $ C.Pawn.Weapon.GetStateName() $ " Grenade=" $ C.Pawn.CurrentGrenade);

		if(C != None && C.Pawn.CurrentGrenade != None)
		{
			i = 0;

			foreach DynamicActors(class'Projectile', Proj)
			{
				i = i + 1;
			}

			Log("CoopTest: grenade: Weapon=" $ C.Pawn.Weapon $ " State=" $ C.Pawn.Weapon.GetStateName() $ " Grenade=" $ C.Pawn.CurrentGrenade $ " Ammo=" $ C.Pawn.CurrentGrenade.AmmoType.AmmoAmount $ " Projectiles=" $ i);
		}

		if(TestStep < 120)
		{
			TestTime = Level.TimeSeconds + 0.25;
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
				// CoopTestNPC=GeonosianWarrior for another class
				if(ParseOption(TestOptions, "CoopTestNPC") != "")
					P = Spawn(class<Pawn>(DynamicLoadObject("CTCharacters." $ ParseOption(TestOptions, "CoopTestNPC"), class'Class')),,, C.Pawn.Location + vector(R) * 500 + vect(0,0,40), rotator(-vector(R)));
				else
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

	if(SC == None || SC.SequenceScript == None || SC.ActionNum >= SC.SequenceScript.Actions.Length)
		return true;

	// A watched scene is over as soon as the squad member joined: the walk to its next position is cut (see RunSkippedActions)
	if(FindWatcher(P) != None && FindAddIndex(SC, P) != -1 && SC.ActionNum > FindAddIndex(SC, P))
		return false;

	return !SC.SequenceScript.Actions[SC.ActionNum].IsA('ACTION_WaitForEvent');
}

/*
 * Diagnostics for invisible walls: a client walks on but its pawn on the server doesn't move (the client's log shows "Server corrected
 * the position" again and again). Logs what blocks the pawn on the server.
 */
function CheckClientsBlocked()
{
	local Controller C;
	local CoopPlayer CP;
	local Actor HitActor;
	local vector HitLocation, HitNormal, Dir, Extent;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || IsHost(CP) || CP.Pawn == None || CP.Pawn.bIncapacitated || CP.Pawn.Physics != PHYS_Walking)
			continue;

		Dir = CP.Pawn.Acceleration;
		Dir.Z = 0;

		if(TestAction ~= "blocked")
			Log("CoopTest: blocked: Accel=" $ CP.Pawn.Acceleration $ " Moved=" $ VSize(CP.Pawn.Location - CP.ServerBlockLocation) $ " Physics=" $ CP.Pawn.Physics);

		if(VSize(Dir) > 0 && VSize(CP.Pawn.Velocity) < 20 && VSize(CP.Pawn.Location - CP.ServerBlockLocation) < 15 && Level.TimeSeconds >= CP.NextServerBlockLog)
		{
			CP.NextServerBlockLog = Level.TimeSeconds + 3;
			Dir = Normal(Dir);
			Extent.X = CP.Pawn.CollisionRadius;
			Extent.Y = CP.Pawn.CollisionRadius;
			Extent.Z = CP.Pawn.CollisionHeight * 0.5;
			HitActor = CP.Pawn.Trace(HitLocation, HitNormal, CP.Pawn.Location + Dir * 40, CP.Pawn.Location, true, Extent);

			if(HitActor == None)
			{
				Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " is blocked on the server at " $ CP.Pawn.Location $ " moving " $ Dir $ ": nothing in front, Base=" $ CP.Pawn.Base $ " State=" $ CP.GetStateName() $ " Velocity=" $ CP.Pawn.Velocity);
				continue;
			}
			Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " is blocked on the server at " $ CP.Pawn.Location $ " moving " $ Dir $ ": hit " $ HitActor $
			    " (" $ HitActor.Class $ " Loc=" $ HitActor.Location $ " Hidden=" $ HitActor.bHidden $ " Block=" $ HitActor.bBlockActors $ HitActor.bBlockPlayers $
			    " Mesh=" $ HitActor.StaticMesh $ " State=" $ HitActor.GetStateName() $ ") Base=" $ CP.Pawn.Base $ " State=" $ CP.GetStateName() $ " Crouched=" $ CP.Pawn.bIsCrouched);
		}

		CP.ServerBlockLocation = CP.Pawn.Location;
	}
}

/*
 * Scripts switch TriggerLights on and off on the server only (TriggerLight.Tick isn't simulated). GEO_03A: the elevator's lights ride
 * on a mover that loops forever (its script can't destroy it, bNoDelete); in single player they are turned off when the elevator
 * arrives, on clients they stayed on and the elevator seemed to go on. The brightness is sent when it changes and every 10 s.
 */
function SyncTriggerLights()
{
	local TriggerLight L;
	local Controller C;
	local int i;
	local bool bResend;

	bResend = Level.TimeSeconds >= NextLightResend;

	if(bResend)
		NextLightResend = Level.TimeSeconds + 10;

	foreach DynamicActors(class'TriggerLight', L)
	{
		if(L.RemoteRole == ROLE_None)
			continue;

		for(i = 0; i < SyncedLights.Length; i = i + 1)
		{
			if(SyncedLights[i] == L)
				break;
		}

		if(i == SyncedLights.Length)
		{
			SyncedLights[i] = L;
			SentLightBrightness[i] = L.InitialBrightness;
		}

		if(!bResend && Abs(SentLightBrightness[i] - L.LightBrightness) < 1)
			continue;

		if(!bResend && L.LightBrightness == L.InitialBrightness && SentLightBrightness[i] == L.InitialBrightness)
			continue;

		if(!bResend)
			Log("CoopGame: light " $ L $ " (" $ L.Tag $ ") brightness " $ L.LightBrightness $ " sent to the clients");

		SentLightBrightness[i] = L.LightBrightness;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				CoopPlayer(C).ClientCoopSetLight(L, L.LightBrightness, L.bCorona);
		}
	}
}

/*
 * GEO_01C: the squad and the player come down on ropes at the start, the ropes are scripts of the AI and of the level. Clients
 * that got their squad member or were spawned before the level started (they load slower than the host) stayed up there and
 * had to jump down. In the first 40 seconds a client far above the host, once the host has landed, is moved to the host.
 */
function CheckIntroPositions()
{
	local PlayerController Host;
	local Controller C;
	local CoopPlayer CP;

	if(bWaitingForClients || Level.TimeSeconds - LevelStartTime > 40)
		return;

	Host = GetHost();

	if(!IsHostFree(Host))
		return;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || IsHost(CP) || CP.Pawn == None || CP.Pawn.Physics != PHYS_Walking || CP.IsInState('CoopWatching'))
			continue;

		if(CP.Pawn.Location.Z - Host.Pawn.Location.Z > 400 && TeleportToHost(CP))
			Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " was left above the host at the start of the level");
	}
}

/*
 * Entrances of squad members at the start of a level (GEO_01C: 40 and 62 come down on ropes). A member's entrance is a script of
 * the AI: a client that got the member at once (it was assigned to it on the last level) skipped it and stayed up there. Now the
 * client watches its member over the shoulder (StartWatching) until the entrance is over, then gets it.
 * An entrance: the script waits for an event and then plays an animation or changes the physics before it waits again.
 */
function bool StartIntroWatch(CoopPlayer CP, Pawn P)
{
	local ScriptedController SC;
	local int i;

	SC = ScriptedController(P.Controller);

	// The scene in the lift the level starts in (GEO_03A: the briefing in the elevator, the squad's talk animations and Scorch's
	// holo projector are their scripts): the client watches its member until the lift arrived (see CheckIntroWatch)
	if(InStartScene())
	{
		Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " watches " $ P $ " until the scene at the start of the level ends (" $ SceneEndEvent $ ")");
		CP.bIntroWatch = true;
		CP.IntroWaitIndex = 0;

		if(SC != None)
			CP.IntroWaitIndex = SC.ActionNum;

		CP.IntroWatchStart = Level.TimeSeconds;
		StartWatching(CP, P, false);
		return true;
	}

	// At the start of the level (paused while waiting for the clients) the script may be at action 0 (wait for levelstart) or already a
	// bit further (GEO_03A: a short timer before the animations of the briefing)
	if(SC == None || SC.SequenceScript == None || SC.ActionNum >= SC.SequenceScript.Actions.Length)
	{
		Log("CoopGame: no entrance for " $ P $ ": Controller=" $ P.Controller $ " Script=" $ SC.SequenceScript $ " Action=" $ SC.ActionNum $ " State=" $ P.Controller.GetStateName());
		return false;
	}

	for(i = SC.ActionNum; i < SC.SequenceScript.Actions.Length; ++i)
	{
		if(SC.SequenceScript.Actions[i] == None || (i > SC.ActionNum && SC.SequenceScript.Actions[i].IsA('ACTION_WaitForEvent')))
			break;

		if(SC.SequenceScript.Actions[i].IsA('ACTION_PlayAnim') || SC.SequenceScript.Actions[i].IsA('ACTION_SetPhysics'))
		{
			Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " watches the entrance of " $ P $ " (" $ P.Class $ ", script action " $ SC.ActionNum $ ")");
			CP.bIntroWatch = true;
			CP.IntroWaitIndex = SC.ActionNum;
			CP.IntroWatchStart = Level.TimeSeconds;
			StartWatching(CP, P, false);
			return true;
		}
	}

	return false;
}

function CheckIntroWatch()
{
	local Controller C;
	local CoopPlayer CP;
	local Pawn P;
	local ScriptedController SC;
	local string Reason;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || !CP.bIntroWatch)
			continue;

		P = CP.WatchedMember;

		if(P == None || P.bDeleteMe || P.Health <= 0)
		{
			Log("CoopGame: the member " $ CP.PlayerReplicationInfo.PlayerName $ " watched is gone, spawning the client");
			CP.bIntroWatch = false;
			CP.WatchedMember = None;
			CP.GotoState('PlayerWalking');
			CP.ClientGotoState('PlayerWalking', '');
			CP.bBehindView = false;
			CP.ClientSetBehindView(false);
			RestartPlayer(CP);
			continue;
		}

		SC = ScriptedController(P.Controller);
		Reason = "";

		// On a lift the client gets the member when the lift stops, in the scene at the start of the level when it ends
		if(((HostLift(GetHost()) != None && P.Base == HostLift(GetHost())) || InStartScene()) && Level.TimeSeconds - CP.IntroWatchStart < 240)
			continue;

		if(SC == None || !SC.IsInState('Scripting') || SC.SequenceScript == None)
			Reason = "script over";
		else if(SC.ActionNum > CP.IntroWaitIndex && !IsScriptBusy(P) && P.Physics == PHYS_Walking)
			Reason = "entrance over";
		else if(SC.ActionNum == CP.IntroWaitIndex && Level.TimeSeconds - CP.IntroWatchStart > 8 && !bWaitingForClients)
			Reason = "entrance didn't start";
		else if(Level.TimeSeconds - CP.IntroWatchStart > 90)
			Reason = "entrance took too long";

		if(Reason == "")
			continue;

		Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " gets " $ P $ " after its entrance (" $ Reason $ ", action " $ SC.ActionNum $ ", physics " $ P.Physics $ ")");
		CP.bIntroWatch = false;
		TakeOver(CP, P, false);
	}
}

// Diagnostics: the commandos on the server when their number changes (one run showed 7 models of the squad, see CoopPlayer.LogCommandos)
function LogCommandos()
{
	local Pawn P;
	local string Str;
	local int Num;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.IsA('CloneCommando') && P.Health > 0)
		{
			++Num;
			Str = Str $ " " $ P $ "(" $ P.Controller $ ")";
		}
	}

	if(Num != LastCommandoCount)
	{
		LastCommandoCount = Num;
		Log("CoopGame: Commandos: " $ Num $ ":" $ Str);
	}
}

// Diagnostics: the server side state of every client every 10 seconds (see also CoopPlayer.LogClientStatus)
function LogClientsStatus()
{
	local Controller C;
	local CoopPlayer CP;

	if(Level.TimeSeconds < NextClientsStatusLog)
		return;

	NextClientsStatusLog = Level.TimeSeconds + 10;
	LogCommandos();

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || IsHost(CP))
			continue;

		if(CP.Pawn == None)
			Log("CoopGame: Status " $ CP.PlayerReplicationInfo.PlayerName $ ": State=" $ CP.GetStateName() $ " no pawn, ViewTarget=" $ CP.ViewTarget $ " Watching=" $ CP.WatchedMember);
		else
			Log("CoopGame: Status " $ CP.PlayerReplicationInfo.PlayerName $ ": State=" $ CP.GetStateName() $ " Pawn=" $ CP.Pawn.Class.Name $ " Health=" $ CP.Pawn.Health $
			    " Incap=" $ CP.Pawn.bIncapacitated $ " Physics=" $ CP.Pawn.Physics $ " Loc=" $ CP.Pawn.Location $ " Weapon=" $ CP.Pawn.Weapon $
			    " WeaponState=" $ CP.Pawn.Weapon.GetStateName() $ " Grenade=" $ CP.Pawn.CurrentGrenade $ " Ping=" $ CP.PlayerReplicationInfo.Ping);
	}
}

function ForwardSetCollision(name ActorTag, bool bCollide, bool bBlockActors, bool bBlockPlayers)
{
	local Controller C;
	local int i;

	Log("CoopGame: script collision of " $ ActorTag $ ": Collide=" $ bCollide $ " BlockActors=" $ bBlockActors $ " BlockPlayers=" $ bBlockPlayers);

	for(i = 0; i < CollisionTags.Length; i = i + 1)
	{
		if(CollisionTags[i] == ActorTag)
			break;
	}

	CollisionTags[i] = ActorTag;
	CollisionTagFlags[i] = int(bCollide) + 2 * int(bBlockActors) + 4 * int(bBlockPlayers);

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopSetCollisionByTag(ActorTag, bCollide, bBlockActors, bBlockPlayers);
	}
}

function ForwardSetHidden(name ActorTag, bool bHidden)
{
	local Controller C;
	local int i;

	for(i = 0; i < HiddenTags.Length; i = i + 1)
	{
		if(HiddenTags[i] == ActorTag)
			break;
	}

	HiddenTags[i] = ActorTag;
	HiddenTagValues[i] = byte(bHidden);

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopSetHiddenByTag(ActorTag, bHidden);
	}
}

/*
 * Squad markers are map actors that every computer runs by itself; ACTION_GotoState of level scripts only changed them on the
 * server. GEO_04D disables the demolition marker at the start and enables it again later: on the client playing Scorch it stayed
 * disabled and the marker was gone.
 */
/*
 * Animations of level scripts (ACTION_PlayAnim) are replicated (SimAnim), but the script's controller takes the animations over
 * (bControlAnimations) and controllers aren't replicated: on the clients the NPC went on choosing its idle and moving animations
 * over the script's (GEO_03A: the squad in the elevator stood still during the briefing). The clients play the animation and keep
 * it (CoopPlayer.ClientCoopScriptAnim) until the script lets go of the animations.
 */
function ForwardScriptAnim(Pawn P, name Anim, float Rate, bool bLoop)
{
	local Controller C;
	local int i;

	if(P == None || PlayerController(P.Controller) != None)
		return;

	for(i = 0; i < ScriptAnimPawns.Length; i = i + 1)
	{
		if(ScriptAnimPawns[i] == P)
			break;
	}

	ScriptAnimPawns[i] = P;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopScriptAnim(P, Anim, Rate, bLoop);
	}
}

function CheckScriptAnims()
{
	local Controller C;
	local Pawn P;
	local int i;

	if(Level.TimeSeconds < NextScriptAnimCheck)
		return;

	NextScriptAnimCheck = Level.TimeSeconds + 0.2;

	for(i = ScriptAnimPawns.Length - 1; i >= 0; i = i - 1)
	{
		P = ScriptAnimPawns[i];

		if(P != None && !P.bDeleteMe && P.Controller != None && PlayerController(P.Controller) == None && P.Controller.bControlAnimations)
			continue;

		ScriptAnimPawns.Remove(i, 1);

		if(P == None || P.bDeleteMe)
			continue;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				CoopPlayer(C).ClientCoopEndScriptAnim(P);
		}
	}
}

function ForwardMarkerState(name MarkerTag, name NewState)
{
	local SquadMarker M;
	local Controller C;
	local int i;

	foreach AllActors(class'SquadMarker', M, MarkerTag)
		break;

	if(M == None)
		return;

	for(i = 0; i < MarkerStateTags.Length; i = i + 1)
	{
		if(MarkerStateTags[i] == MarkerTag)
			break;
	}

	MarkerStateTags[i] = MarkerTag;
	MarkerStates[i] = NewState;
	Log("CoopGame: script state of marker " $ MarkerTag $ ": " $ NewState);

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopSetMarkerState(MarkerTag, NewState);
	}
}

// Again every 10 s for clients that joined later
function ResendCollisionTags()
{
	local Controller C;
	local int i;

	if(Level.TimeSeconds < NextCollisionTagResend || (CollisionTags.Length == 0 && HiddenTags.Length == 0 && MarkerStateTags.Length == 0))
		return;

	NextCollisionTagResend = Level.TimeSeconds + 10;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) == None || IsHost(C))
			continue;

		for(i = 0; i < CollisionTags.Length; i = i + 1)
			CoopPlayer(C).ClientCoopSetCollisionByTag(CollisionTags[i], (CollisionTagFlags[i] & 1) != 0, (CollisionTagFlags[i] & 2) != 0, (CollisionTagFlags[i] & 4) != 0);

		for(i = 0; i < HiddenTags.Length; i = i + 1)
			CoopPlayer(C).ClientCoopSetHiddenByTag(HiddenTags[i], HiddenTagValues[i] != 0);

		for(i = 0; i < MarkerStateTags.Length; i = i + 1)
			CoopPlayer(C).ClientCoopSetMarkerState(MarkerStateTags[i], MarkerStates[i]);
	}
}

/*
 * Karma props (GEO_01B: the wrecks of the fighters in the hangar, shown and thrown around by the explosion) are simulated on every
 * computer by itself, their positions are not replicated. Each client had walls where its own wrecks lay and the server had its
 * walls elsewhere ("Server corrected the position" by up to 680 units at the same spots for every client). Once the physics moves
 * them they don't block players anymore, on the server and on the clients (AI still bumps into them). Sent again every 10 s for
 * clients that came later.
 */
function UnblockKarmaProps()
{
	local KarmaProp K;
	local Controller C;
	local int i;
	local bool bResend;

	foreach DynamicActors(class'KarmaProp', K)
	{
		// Only once the physics moves it: untouched props (explosive barrels) are where the map has them everywhere
		if(K.bBlockPlayers && K.Physics == PHYS_Karma && K.KIsAwake())
		{
			K.SetCollision(K.bCollideActors, K.bBlockActors, false);
			UnblockedKarmaProps[UnblockedKarmaProps.Length] = K;
			Log("CoopGame: " $ K $ " (" $ K.StaticMesh $ ") doesn't block players anymore");

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C))
					CoopPlayer(C).ClientCoopSetActorCollision(K, K.bCollideActors, K.bBlockActors, false, K.StaticMesh, K.bHidden);
			}
		}
	}

	bResend = Level.TimeSeconds >= NextKarmaResend;

	if(!bResend)
		return;

	NextKarmaResend = Level.TimeSeconds + 10;

	for(i = UnblockedKarmaProps.Length - 1; i >= 0; --i)
	{
		K = UnblockedKarmaProps[i];

		if(K == None || K.bDeleteMe)
		{
			UnblockedKarmaProps.Remove(i, 1);
			continue;
		}

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				CoopPlayer(C).ClientCoopSetActorCollision(K, K.bCollideActors, K.bBlockActors, false, K.StaticMesh, K.bHidden);
		}
	}
}

/*
 * Scripts that stand on an action that doesn't wait (a condition, a jump to a label): GEO_01C, the sniper scene, Sev's script stood
 * at "If condition TakeOff" and the mission couldn't be completed. Such scripts are continued after 2 seconds.
 */
function CheckStalledScripts()
{
	local ScriptedController SC;
	local ScriptedAction A;
	local int i;
	local bool bFound;

	foreach DynamicActors(class'ScriptedController', SC)
	{
		if(SC.SequenceScript == None || SC.ActionNum >= SC.SequenceScript.Actions.Length)
			continue;

		A = SC.SequenceScript.Actions[SC.ActionNum];

		if(A == None || !(A.IsA('ACTION_IfCondition') || A.IsA('ACTION_GotoLabel') || A.IsA('ACTION_Label') || A.IsA('ACTION_EndSection') ||
		   A.IsA('ACTION_TriggerEvent') || A.IsA('ACTION_SetHidden') || A.IsA('ACTION_SetCollision')))
			continue;

		bFound = false;

		for(i = 0; i < StalledScripts.Length; i = i + 1)
		{
			if(StalledScripts[i] == SC)
			{
				bFound = true;
				break;
			}
		}

		if(!bFound || StalledActions[i] != SC.ActionNum)
		{
			StalledScripts[i] = SC;
			StalledActions[i] = SC.ActionNum;
			StalledTimes[i] = Level.TimeSeconds;
			continue;
		}

		if(Level.TimeSeconds - StalledTimes[i] < 2)
			continue;

		Log("CoopGame: script " $ SC.SequenceScript $ " (" $ SC.SequenceScript.Tag $ ") of " $ SC.Pawn $ " stands at " $ SC.ActionNum $ " " $ A.GetActionString() $ ", continuing it");
		StalledTimes[i] = Level.TimeSeconds;
		SC.SequenceScript.SetActions(SC);
	}

	for(i = StalledScripts.Length - 1; i >= 0; i = i - 1)
	{
		if(StalledScripts[i] == None || StalledScripts[i].bDeleteMe)
		{
			StalledScripts.Remove(i, 1);
			StalledActions.Remove(i, 1);
			StalledTimes.Remove(i, 1);
		}
	}
}

/*
 * Squad members taken over from the AI have no current grenade on the server (the AI doesn't use it): the client threw the grenade
 * in its own animation, but ServerThrowGrenade found none, so no grenade flew and none was used up. Same choice as Pawn.CreateInventory.
 */
function EnsureClientGrenades()
{
	local Controller C;
	local Inventory Inv;

	// Test: CoopTestNoGrenade=1 keeps the old behavior (see the test "grenade")
	if(ParseOption(TestOptions, "CoopTestNoGrenade") != "")
		return;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) == None || C.Pawn == None || C.Pawn.CurrentGrenade != None)
			continue;

		for(Inv = C.Pawn.Inventory; Inv != None; Inv = Inv.Inventory)
		{
			if(Weapon(Inv) != None && Weapon(Inv).WeaponType == WT_Thrown)
			{
				C.Pawn.CurrentGrenade = Weapon(Inv);
				Log("CoopGame: current grenade of " $ C.PlayerReplicationInfo.PlayerName $ " was missing, now " $ Inv);
				break;
			}
		}
	}
}

// Health of the commandos and who is in the squad, for the squad icons of the clients (CoopHUD.DrawCoopSquad). Sent when it changes
// and every 5 seconds for clients that joined later.
function SyncSquadHealth()
{
	local Pawn P;
	local Controller C;
	local PlayerController Host;
	local int i;
	local byte bMember, IconX, IconY, MarkerState;
	local int Icon;
	local bool bResend;

	Host = GetHost();
	bResend = Level.TimeSeconds >= NextSquadStateResend;

	if(bResend)
		NextSquadStateResend = Level.TimeSeconds + 5;

	foreach DynamicActors(class'Pawn', P)
	{
		if(!P.IsA('CloneCommando'))
			continue;

		// The squad icons of the clients show every member, also the ones far away
		P.bAlwaysRelevant = true;

		// Squad members played by clients are not in the AI squad (see DetachClientMembers)
		bMember = 0;

		if(PlayerController(P.Controller) != None || (Host != None && Host.Pawn != None && Host.Pawn.Squad != None && P.Squad == Host.Pawn.Squad))
			bMember = 1;

		for(i = 0; i < HealthPawns.Length; i = i + 1)
		{
			if(HealthPawns[i] == P)
				break;
		}

		GetSquadIconState(P, IconX, IconY, MarkerState);
		Icon = IconX * 4096 + IconY * 256 + MarkerState;

		if(!bResend && i < HealthPawns.Length && SentHealths[i] == P.Health && SentSquadMembers[i] == bMember && SentSquadIcons[i] == Icon)
			continue;

		HealthPawns[i] = P;
		SentHealths[i] = P.Health;
		SentSquadMembers[i] = bMember;
		SentSquadIcons[i] = Icon;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != P)
				CoopPlayer(C).ClientCoopSetSquadState(P, P.Health, bMember == 1, IconX, IconY, MarkerState);
		}
	}

	for(i = HealthPawns.Length - 1; i >= 0; i = i - 1)
	{
		if(HealthPawns[i] == None || HealthPawns[i].bDeleteMe)
		{
			HealthPawns.Remove(i, 1);
			SentHealths.Remove(i, 1);
			SentSquadMembers.Remove(i, 1);
			SentSquadIcons.Remove(i, 1);
		}
	}
}

/*
 * What the helmet shows in the squad icon of a member (see Notes/HelmetHUD.md): the icon of its order and its marker.
 * MarkerState: 0 = none, 1 = on the way to its marker, 2 + n = n twelfths of the marker's action done (the timer ring).
 * The squad and the markers only exist on the server. Members played by clients have no orders, they show "form up".
 */
function GetSquadIconState(Pawn P, out byte IconX, out byte IconY, out byte MarkerState)
{
	local ActivateItem Item, A;
	local float Duration;
	local int i;

	IconX = 1;
	IconY = 4;
	MarkerState = 0;

	for(i = 0; P.Squad != None && i < P.Squad.SquadMembers.Length; i = i + 1)
	{
		if(P.Squad.SquadMembers[i].Pawn == P)
		{
			IconX = P.Squad.SquadMembers[i].HUDIconX;
			IconY = P.Squad.SquadMembers[i].HUDIconY;
			break;
		}
	}

	if(P.SquadMarker != None)
	{
		if(P.SquadMarker.bSetupPhase)
			MarkerState = 1;
		else
			Item = ActivateItem(P.SquadMarker.Anchor);
	}
	else if(PlayerController(P.Controller) != None)
	{
		// A client uses panels himself, without a marker
		foreach DynamicActors(class'ActivateItem', A)
		{
			if(A.User == P.Controller)
				Item = A;
		}
	}

	if(Item != None && Item.DurationRemaining != 0)
	{
		Duration = Item.DefaultDuration();

		if(Duration > 0)
			MarkerState = 2 + int(FClamp((Duration - Item.DurationRemaining) / Duration, 0, 1) * 12);
	}
}

// The helmet shows the current mission objective, its state only exists on the server
function SyncObjectives()
{
	local string States;
	local Controller C;
	local int i;

	if(Objectives == None)
	{
		foreach AllActors(class'MissionObjectives', Objectives)
			break;

		if(Objectives == None)
			return;

		Objectives.bAlwaysRelevant = true;
	}

	for(i = 0; i < Objectives.MissionObj.Length; i = i + 1)
		States = States $ int(Objectives.MissionObj[i].Stat);

	// Sent again every few seconds for clients that joined later
	if((States $ Objectives.CurrentObjective) == SentObjectives && Level.TimeSeconds < NextObjectivesResend)
		return;

	SentObjectives = States $ Objectives.CurrentObjective;
	NextObjectivesResend = Level.TimeSeconds + 5;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopSetObjectives(Objectives, States, Objectives.CurrentObjective);
	}
}

// Emitters aren't replicated, effects of map actors are spawned on the clients as well (see CoopExtension, SyncPropEffects)
function ForwardEffect(class<Emitter> EffectClass, vector EffectLocation, rotator EffectRotation, Actor AttachTo)
{
	local Controller C;

	if(EffectClass == None)
		return;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopSpawnEffect(EffectClass, EffectLocation, EffectRotation, AttachTo);
	}
}

// Damaged and destroyed props (explosive barrels, windows, consoles...) spawn their effects in state code on the server
function SyncPropEffects()
{
	local Prop P;
	local Emitter E;
	local int i;

	foreach DynamicActors(class'Prop', P)
	{
		for(i = 0; i < EffectProps.Length; i = i + 1)
		{
			if(EffectProps[i] == P)
				break;
		}

		if(i == EffectProps.Length)
		{
			EffectProps[i] = P;
			EffectPropStates[i] = P.GetStateName();
			continue;
		}

		if(EffectPropStates[i] == P.GetStateName())
			continue;

		EffectPropStates[i] = P.GetStateName();
		E = None;

		if(P.IsInState('PropDamaged'))
			E = P.DamagedState.SpawnedEmitter;
		else if(P.IsInState('PropDestroyed') || P.IsInState('Exploding'))
			E = P.DestroyedState.SpawnedEmitter;

		if(E != None && !E.bDeleteMe)
		{
			if(E.Base == P)
				ForwardEffect(E.Class, E.Location, E.Rotation, P);
			else
				ForwardEffect(E.Class, E.Location, E.Rotation, None);
		}
	}

	for(i = EffectProps.Length - 1; i >= 0; i = i - 1)
	{
		if(EffectProps[i] == None || EffectProps[i].bDeleteMe)
		{
			EffectProps.Remove(i, 1);
			EffectPropStates.Remove(i, 1);
		}
	}
}

// See CoopExtension: HUD changes of level scripts for every client
function ForwardObjectiveTracker(Actor A, bool bShow)
{
	local Controller C;
	local vector Loc;

	if(A != None)
		Loc = A.Location;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopObjectiveTracker(A, Loc, bShow);
	}
}

function ForwardBlinkHUD(byte Element, float BlinkTime)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopBlinkHUD(Element, BlinkTime);
	}
}

function ForwardShakeView(float InTime, float SustainTime, float OutTime, vector TranslationMag, rotator RotationMag, float Frequency)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopShakeView(InTime, SustainTime, OutTime, TranslationMag, RotationMag, Frequency);
	}
}

function ForwardScreenFade(float FadeTime, color FadeColor)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopScreenFade(FadeTime, FadeColor);
	}
}

function ForwardCriticalMessage(string Message, float Duration, color TextColor)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopCriticalMessage(Message, Duration, TextColor);
	}
}

/*
 * Snipe markers (GEO_01C: Sun Fac's ship): the AI sniper triggers EventUnderway (InSnipePosition) when it reached the position, the
 * level decides on it whether the mission succeeds. A client playing Sev can't be ordered there: he is asked to go there himself
 * when the level shows the marker, and the event is triggered once he is next to the position.
 */
function CheckClientSnipers()
{
	local SquadMarker M;
	local PlayerController PC;
	local int i;

	foreach AllActors(class'SquadMarker', M)
	{
		if(!M.IsA('MarkerSnipe') || M.Anchor == None || M.bMarkerActive || (!M.AlwaysVisible && !M.IsInState('Enabled')))
			continue;

		PC = MarkerClient(M);

		if(PC == None || PC.Pawn == None)
			continue;

		for(i = 0; i < ClientSnipeMarkers.Length; i = i + 1)
		{
			if(ClientSnipeMarkers[i] == M)
				break;
		}

		if(i == ClientSnipeMarkers.Length)
		{
			if(!M.AlwaysVisible)
				continue;

			ClientSnipeMarkers[i] = M;
			ClientSnipeStates[i] = 1;

			PC.ClientMessage("Take the sniper position");
			Log("CoopGame: " $ PC.PlayerReplicationInfo.PlayerName $ " has to take the sniper position of " $ M $ " at " $ M.Anchor $ " " $ M.Anchor.Location);
		}

		// The marker's icon isn't shown on clients: the objective tracker (ring around the crosshair with direction and distance)
		// points to the position until the client is there, sent again every 5 s in case a script changes the tracker
		if(ClientSnipeStates[i] == 1 && CoopPlayer(PC) != None && Level.TimeSeconds >= NextSnipeTrackerTime)
		{
			NextSnipeTrackerTime = Level.TimeSeconds + 5;
			CoopPlayer(PC).ClientCoopObjectiveTracker(None, M.Anchor.Location, true);
		}

		if(ClientSnipeStates[i] == 1 && VSize(PC.Pawn.Location - M.Anchor.Location) < 300)
		{
			ClientSnipeStates[i] = 2;

			if(CoopPlayer(PC) != None)
				CoopPlayer(PC).ClientCoopObjectiveTracker(None, vect(0,0,0), false);

			Log("CoopGame: " $ PC.PlayerReplicationInfo.PlayerName $ " is in the sniper position of " $ M $ ", triggering " $ M.EventUnderway);

			if(M.Event != '')
				TriggerEvent(M.Event, M, PC.Pawn);

			if(M.EventUnderway != '')
				TriggerEvent(M.EventUnderway, M, PC.Pawn);

			// The AI takes Sev just for the shot (see StartAISnipe)
			if(CoopPlayer(PC) != None && FindSnipeShot(M))
				ClientSnipeStates[i] = 4;
		}

		if(ClientSnipeStates[i] == 4 && SnipePawn == None && (WasHeard(SnipeShotEvent) || IsConditionEnabled(SnipeShotEvent)) &&
		   CoopPlayer(PC) != None && StartAISnipe(CoopPlayer(PC), PC.Pawn, M))
			ClientSnipeStates[i] = 3;
	}
}

/*
 * Arrivals of squad members (GEO_05B: the elevator, GEO_05C: the hatch and the gunship). On an event of the level each member's
 * script walks it to a point and triggers a counter, the level goes on when the counter got every member. The script of a member a
 * client plays is dropped, so the counter never got it. Now the arrival of a client is counted when its pawn reaches the point
 * its script walks to, after the event the script waited for (the last one outside of the script's conditions) was triggered.
 */
function ScanArrivals(Pawn P)
{
	local ScriptedSequence Seq;
	local ScriptedAction Action;
	local ACTION_TriggerEvent TE;
	local Actor Point;
	local name ArmEvent;
	local int i, j, n, Depth;

	ArrivalScanned[ArrivalScanned.Length] = P;

	foreach AllActors(class'ScriptedSequence', Seq, P.AIScriptTag)
	{
		Depth = 0;
		ArmEvent = '';

		for(i = 0; i < Seq.Actions.Length; i = i + 1)
		{
			Action = Seq.Actions[i];

			if(Action == None)
				continue;

			if(Action.StartsSection())
				Depth = Depth + 1;
			else if(Action.IsA('ACTION_EndSection'))
				Depth = Max(Depth - 1, 0);
			else if(Action.IsA('ACTION_WaitForEvent') && Depth == 0)
				ArmEvent = ACTION_WaitForEvent(Action).ExternalEvent;

			if(ArmEvent == '' || ACTION_MoveToPoint(Action) == None || ACTION_MoveToPoint(Action).DestinationTag == '')
				continue;

			Point = None;

			foreach AllActors(class'Actor', Point, ACTION_MoveToPoint(Action).DestinationTag)
				break;

			if(Point == None)
				continue;

			for(j = i + 1; j < Seq.Actions.Length; j = j + 1)
			{
				if(Seq.Actions[j] == None || Seq.Actions[j].IsA('ACTION_WaitForEvent') || Seq.Actions[j].IsA('ACTION_MoveToPoint'))
					break;

				TE = ACTION_TriggerEvent(Seq.Actions[j]);

				if(TE == None || !IsCounterTag(TE.Event))
					continue;

				n = ArrivalPawns.Length;
				ArrivalPawns[n] = P;
				ArrivalPoints[n] = Point;
				ArrivalEvents[n] = TE.Event;
				ArrivalArmEvents[n] = ArmEvent;
				ArrivalDone[n] = 0;
				ListenForEvent(ArmEvent);
				Log("CoopGame: arrival of " $ P $ " at " $ Point $ " triggers " $ TE.Event $ " after " $ ArmEvent);
				break;
			}
		}
	}
}

function bool IsCounterTag(name EventName)
{
	local Counter C;

	if(EventName == '')
		return false;

	foreach AllActors(class'Counter', C, EventName)
		return true;

	return false;
}

function ListenForEvent(name EventName)
{
	local CoopEventListener L;

	foreach DynamicActors(class'CoopEventListener', L, EventName)
		return;

	L = Spawn(class'CoopEventListener');
	L.Game = self;
	L.Tag = EventName;
}

function EventHeard(name EventName)
{
	local int i;

	for(i = 0; i < HeardEvents.Length; i = i + 1)
	{
		if(HeardEvents[i] == EventName)
			return;
	}

	HeardEvents[HeardEvents.Length] = EventName;
	Log("CoopGame: heard " $ EventName);
}

function bool WasHeard(name EventName)
{
	local int i;

	for(i = 0; i < HeardEvents.Length; i = i + 1)
	{
		if(HeardEvents[i] == EventName)
			return true;
	}

	return false;
}

function CheckClientArrivals()
{
	local Controller C;
	local Pawn P;
	local int i;
	local bool bScanned;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) == None || IsHost(C) || C.Pawn == None || !C.Pawn.IsA('CloneCommando') || C.Pawn.AIScriptTag == '')
			continue;

		bScanned = false;

		for(i = 0; i < ArrivalScanned.Length; i = i + 1)
		{
			if(ArrivalScanned[i] == C.Pawn)
				bScanned = true;
		}

		if(!bScanned)
			ScanArrivals(C.Pawn);
	}

	for(i = 0; i < ArrivalPawns.Length; i = i + 1)
	{
		P = ArrivalPawns[i];

		if(ArrivalDone[i] != 0 || ArrivalPoints[i] == None || !WasHeard(ArrivalArmEvents[i]))
			continue;

		// A member that died can't arrive any more (the level's own scripts count members that are down)
		if(P == None || P.bDeleteMe || P.Health <= 0)
		{
			ArrivalDone[i] = 1;
			Log("CoopGame: the member of arrival " $ ArrivalEvents[i] $ " at " $ ArrivalPoints[i] $ " is dead, triggering it");
			TriggerEvent(ArrivalEvents[i], ArrivalPoints[i], None);
			continue;
		}

		// A member the AI plays triggers it with its own script
		if(CoopPlayer(P.Controller) == None || P.bIncapacitated)
			continue;

		if(VSize(P.Location - ArrivalPoints[i].Location) > ArrivalRadius)
			continue;

		ArrivalDone[i] = 1;
		Log("CoopGame: " $ P.Controller.PlayerReplicationInfo.PlayerName $ " arrived at " $ ArrivalPoints[i] $ ", triggering " $ ArrivalEvents[i]);
		TriggerEvent(ArrivalEvents[i], ArrivalPoints[i], P);
	}
}

/*
 * Level scripts wait for events of other scripts. When players are faster than the designers expected the event comes before the
 * script waits for it and the scene stops forever (GEO_01C: Sev on the sniper position before Sun Fac reached his ship, Sun Fac
 * never got SunFacRunToShip). An event a script missed by up to 30 seconds is passed on when it starts waiting, but only the
 * first time it waits for that event (scripts that wait for the same event in a loop are left alone).
 */
function CheckMissedEvents()
{
	local ScriptedController SC;
	local ScriptedSequence Seq;
	local ACTION_WaitForEvent Wait;
	local int i, j, n;
	local bool bFound;

	for(i = FiredEvents.Length - 1; i >= 0; i = i - 1)
	{
		if(Level.TimeSeconds - FiredEvents[i].Time > 30)
			FiredEvents.Remove(i, 1);
	}

	for(i = ScriptWatches.Length - 1; i >= 0; i = i - 1)
	{
		if(ScriptWatches[i].SC == None || ScriptWatches[i].SC.bDeleteMe)
			ScriptWatches.Remove(i, 1);
	}

	foreach DynamicActors(class'ScriptedController', SC)
	{
		Seq = SC.SequenceScript;

		if(Seq == None)
			continue;

		bFound = false;

		for(i = 0; i < ScriptWatches.Length; i = i + 1)
		{
			if(ScriptWatches[i].SC == SC)
			{
				bFound = true;
				break;
			}
		}

		if(!bFound)
		{
			i = ScriptWatches.Length;
			ScriptWatches.Length = i + 1;
			ScriptWatches[i].SC = SC;
			ScriptWatches[i].LastAction = SC.ActionNum;
		}

		// Events of the actions the script went through since the last check
		if(SC.ActionNum > ScriptWatches[i].LastAction)
		{
			for(j = ScriptWatches[i].LastAction; j < SC.ActionNum && j < Seq.Actions.Length; j = j + 1)
			{
				if(ACTION_TriggerEvent(Seq.Actions[j]) != None && ACTION_TriggerEvent(Seq.Actions[j]).Event != '')
				{
					n = FiredEvents.Length;
					FiredEvents.Length = n + 1;
					FiredEvents[n].Event = ACTION_TriggerEvent(Seq.Actions[j]).Event;
					FiredEvents[n].Time = Level.TimeSeconds;
				}
			}
		}

		ScriptWatches[i].LastAction = SC.ActionNum;

		Wait = None;

		if(SC.ActionNum < Seq.Actions.Length)
			Wait = ACTION_WaitForEvent(Seq.Actions[SC.ActionNum]);

		if(Wait == None || Wait.ExternalEvent == '' || SC.CurrentAction != Wait || SC.Tag != Wait.ExternalEvent)
		{
			ScriptWatches[i].WaitEvent = '';
			continue;
		}

		if(ScriptWatches[i].WaitEvent != Wait.ExternalEvent)
		{
			ScriptWatches[i].WaitEvent = Wait.ExternalEvent;
			ScriptWatches[i].WaitStart = Level.TimeSeconds;

			if(InStr(ScriptWatches[i].WaitedEvents, "|" $ Wait.ExternalEvent $ "|") != -1)
				continue;

			ScriptWatches[i].WaitedEvents = ScriptWatches[i].WaitedEvents $ "|" $ Wait.ExternalEvent $ "|";

			for(j = 0; j < FiredEvents.Length; j = j + 1)
			{
				if(FiredEvents[j].Event == Wait.ExternalEvent)
				{
					Log("CoopGame: " $ Seq $ " (" $ Seq.Tag $ ") missed " $ Wait.ExternalEvent $ " " $ (Level.TimeSeconds - FiredEvents[j].Time) $ " seconds ago, passing it on");
					SC.Trigger(self, None);
					break;
				}
			}
		}
	}
}

/*
 * Squad members played by clients are not in the AI squad. The squad AI of the other members treats every member as a bot: the host
 * crashed in AController::Tick of Sev (GEO_04A, squad goal SearchAndDestroy) as soon as a client took over Scorch. Scripts add
 * members to the squad again (ACTION_ChangeSquadMember), so this is checked every second.
 */
function DetachClientMembers()
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(IsSquadClient(C) && C.Pawn.Squad != None)
		{
			Log("CoopGame: removing " $ C.Pawn $ " of " $ C.PlayerReplicationInfo.PlayerName $ " from the AI squad " $ C.Pawn.Squad);
			C.Pawn.Squad.RemoveFromSquad(C.Pawn);
		}
	}
}

// Before a level change so the squad members of the clients are in the squad of the next level
function AttachClientMembers(Squad S)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(IsSquadClient(C) && C.Pawn.Squad == None)
			S.AddToSquad(C.Pawn);
	}
}

// Index of the script action that adds the squad member to the squad, -1 if none
function int FindAddIndex(ScriptedController SC, Pawn P)
{
	local ACTION_ChangeSquadMember Change;
	local int i;

	for(i = 0; i < SC.SequenceScript.Actions.Length; i = i + 1)
	{
		Change = ACTION_ChangeSquadMember(SC.SequenceScript.Actions[i]);

		if(Change != None && Change.bAddMember && Change.MemberTag == P.Tag)
			return i;
	}

	return -1;
}

/*
 * The script of a squad member is dropped when a client takes it over. Events and objectives the script would still trigger before it
 * waits again (GEO_01B: Fixer triggers the shield dialog after walking to the hack panel) are triggered right away.
 */
function RunSkippedActions(Pawn P)
{
	local ScriptedController SC;
	local ScriptedAction Action;
	local int i;

	SC = ScriptedController(P.Controller);

	if(SC == None || SC.SequenceScript == None || !SC.IsInState('Scripting'))
		return;

	for(i = SC.ActionNum; i < SC.SequenceScript.Actions.Length; i = i + 1)
	{
		Action = SC.SequenceScript.Actions[i];

		if(Action == None)
			continue;

		if(Action.IsA('ACTION_WaitForEvent') || Action.IsA('ACTION_WaitForPlayer') || Action.IsA('ACTION_GotoAction') || Action.IsA('ACTION_GotoLabel') ||
		   Action.IsA('ACTION_IfCondition') || Action.IsA('ACTION_IfRandomPct') || Action.IsA('ACTION_EndSection') || Action.IsA('ACTION_ChangeScript'))
			break;

		if(Action.IsA('ACTION_TriggerEvent') || Action.IsA('ACTION_ObjectiveUpdate') || Action.IsA('ACTION_ChangeSquadMember'))
		{
			Log("CoopGame: running skipped script action of " $ P $ ": " $ Action.GetActionString());
			Action.InitActionFor(SC);
		}
	}
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

		// The camera always flies to a member that joins the squad in its scene, also for a client that played it before
		StartWatching(Best, P, true);
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

	// Over the shoulder of the squad member (see CoopPlayer.CalcWatchView). Behind view: no first person weapon and hands are drawn
	// (a door breach showed only the hands); the takeover switches back to first person
	// Replicated to the client also when it is far away (GEO_01C: up on the balcony while the level waits for the clients, the client
	// only got the member at the bottom of the rope)
	P.bAlwaysRelevant = true;
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
	local Controller C, Best;
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
			if(CoopPlayer(C).bIntroWatch || CoopPlayer(C).bInBreach)
				continue;

			if(CoopCommando(C.Pawn) != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated)
			{
				// A member with an entrance still to play (GEO_01C: the rope) is watched first
				if(!StartIntroWatch(CoopPlayer(C), P))
					TakeOver(CoopPlayer(C), P, false);

				return;
			}

			continue; // Reserved for that client
		}

		// Otherwise the closest client without a squad member, wherever it is (GEO_01C: a client that spawned on the balcony can't
		// follow the host down the rope to Scorch). The camera flies to the squad member.
		Best = None;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && CoopCommando(C.Pawn) != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated &&
			   GetAssignedClass(PlayerController(C)) == "" && (Best == None || VSize(C.Pawn.Location - P.Location) < VSize(Best.Pawn.Location - P.Location)))
				Best = C;
		}

		if(Best != None)
		{
			SetAssignment(PlayerController(Best), string(P.Class));

			// GEO_01C, a game started on this level: Scorch was taken over before his rope and his animation broke
			if(!StartIntroWatch(CoopPlayer(Best), P))
				TakeOver(CoopPlayer(Best), P, true);

			return; // One per second is enough
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
	local PlayerController Host;
	local string MemberClass;
	local Pawn P;

	MemberClass = GetAssignedClass(CP);
	Host = GetHost();

	if(MemberClass == "" || !bClientsTakeOverSquad || Host == None || Host.Pawn == None || Host.Pawn.Squad == None)
		return None;

	// Only a member that is already in the squad (e.g. busy with a script at the start of GEO_01C). One that joins later in this
	// level (Fixer on GEO_01B) is handed over in its scene (CheckSceneWatch); until then the client plays its own commando.
	foreach DynamicActors(class'Pawn', P)
	{
		if(string(P.Class) ~= MemberClass && P.Health > 0 && PlayerController(P.Controller) == None && P.Squad == Host.Pawn.Squad)
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

static function LinkPlayerAnims(Pawn P)
{
	local MeshAnimation MPSet;

	if(P.HasAnim('DC17mThrowGrenade'))
		return;

	MPSet = MeshAnimation(DynamicLoadObject("Clone.MPSet", class'MeshAnimation', true));

	if(MPSet != None)
		P.LinkAnimToMesh(MPSet, P.Mesh);

	Log("CoopGame: Linked player animations to " $ P $ ": " $ P.HasAnim('DC17mThrowGrenade'));
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
	RunSkippedActions(P);

	// The camera moves from the old view to the new pawn on the client (only when a client gets a squad member for the first time)
	if(OldPawn != None && bMoveCamera)
		CP.ClientCoopTakeoverCamera(OldPawn.Location + OldPawn.EyePosition(), CP.Rotation);

	// Out of the AI squad while the AI still has it (see EndAIBreach: RemoveFromSquad hangs for a player's member with assignments)
	if(P.Squad != None && AIController(OldAI) != None)
	{
		Log("CoopGame: removing " $ P $ " from the AI squad " $ P.Squad $ " before the takeover");
		P.Squad.RemoveFromSquad(P);
	}

	OldAI.UnPossess();
	OldAI.Destroy();

	CP.UnPossess();

	if(OldPawn != None)
		OldPawn.Destroy();

	CP.bCoopTakeover = true;
	CP.Possess(P);
	CP.bCoopTakeover = false;
	DetachClientMembers();
	CP.bBehindView = false;
	CP.ClientSetBehindView(false);

	// The single player animations of squad members have no player grenade throw ('DC17mThrowGrenade'), its notify releases the
	// grenade. The multiplayer animations have it.
	LinkPlayerAnims(P);

	// Taken over during a scripted entrance (GEO_01C: the rope, physics RootMotion): a player walks
	if(P.Physics != PHYS_Walking && P.Physics != PHYS_Falling)
		P.SetPhysics(PHYS_Falling);

	// Scripts crouch or hurt squad members (Fixer is hurt in his scene): a player starts standing and healthy
	P.ShouldCrouch(false);
	P.bWantsToCrouch = false;

	// Scripts walk squad members to their positions with an analog speed (Scorch on GEO_01A): the player moved slowly and couldn't
	// crouch until the next level
	P.SetWalking(false);
	P.bUseAnalogSpeed = P.default.bUseAnalogSpeed;
	P.bUseSpeedScaler = P.default.bUseSpeedScaler;
	P.AnalogSpeed = P.default.AnalogSpeed;
	P.MaximumDesiredSpeed = P.default.MaximumDesiredSpeed;
	P.GroundSpeed = P.default.GroundSpeed;
	P.bCanCrouch = P.default.bCanCrouch;
	P.bCanJump = P.default.bCanJump;
	P.bCanWalk = P.default.bCanWalk;
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

	// Squad members played by clients travel with the squad (see DetachClientMembers)
	if(P.Squad != None)
	{
		AttachClientMembers(P.Squad);
		P.SaveSquadTravelInfo();
	}

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

/*
 * After a level change the game is paused until the clients of the last level are back, so nobody misses the start of the level
 * (intro cutscenes start right away). Clients that don't come back within MaxClientWait seconds are not waited for.
 */
function int CountClients()
{
	local Controller C;
	local int n;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			++n;
	}

	return n;
}

function WaitForClients(PlayerController Host)
{
	// Test: CoopTestWait=<clients> waits for clients that never come (see CheckClientWaitTime)
	if(ParseOption(TestOptions, "CoopTestWait") != "")
		class'CoopConfig'.default.TravelClients = int(ParseOption(TestOptions, "CoopTestWait"));

	if(class'CoopConfig'.default.TravelClients <= CountClients() || MaxClientWait <= 0)
	{
		class'CoopConfig'.default.TravelClients = 0;
		return;
	}

	Log("CoopGame: waiting for " $ class'CoopConfig'.default.TravelClients $ " clients before the level starts");
	bWaitingForClients = true;
	ClientWaitTime = class'CoopNative'.static.GetRealTime();
	Level.Pauser = Host.PlayerReplicationInfo;
	Host.ClientMessage("Waiting for players (0/" $ class'CoopConfig'.default.TravelClients $ ")");
}

// Clients count once they have loaded the level and drawn it (CoopPlayer.ServerCoopReady) and their camera has something to show:
// their pawn or the squad member they watch. Clients that don't come in time: CheckClientWaitTime.
function CheckClientsArrived()
{
	local Controller C;
	local int n;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && CoopPlayer(C).bCoopReady &&
		   (C.Pawn != None || CoopPlayer(C).WatchedMember != None || Pawn(PlayerController(C).ViewTarget) != None))
			++n;
	}

	Broadcast(self, "Waiting for players (" $ n $ "/" $ class'CoopConfig'.default.TravelClients $ ")");
	Log("CoopGame: " $ n $ " of " $ class'CoopConfig'.default.TravelClients $ " clients see the level (" $ CountClients() $ " logged in)");

	if(n >= class'CoopConfig'.default.TravelClients)
		StopWaitingForClients();
}

// Called by CoopPlayer.PlayerCalcView of the host: nothing is ticked while the game is paused but the view is still drawn
function CheckClientWaitTime()
{
	if(class'CoopNative'.static.GetRealTime() - ClientWaitTime >= MaxClientWait)
	{
		Log("CoopGame: clients didn't come back in time, starting the level");
		StopWaitingForClients();
	}
}

function StopWaitingForClients()
{
	bWaitingForClients = false;
	class'CoopConfig'.default.TravelClients = 0;
	Level.Pauser = None;
	LevelStartTime = Level.TimeSeconds;
	Log("CoopGame: starting the level with " $ CountClients() $ " clients");

	// Nothing but the controllers is replicated while the level is paused: clients that watch the entrance of their squad member
	// get the member only now. The level runs 10 times slower until their cameras are on it (CheckSlowStart), at most 4 seconds.
	// Not slower: replication goes by the level's time too.
	if(CountWatchers() > 0)
	{
		bSlowStart = true;
		SlowStartTime = class'CoopNative'.static.GetRealTime();
		SavedTimeDilation = Level.TimeDilation;
		Level.TimeDilation = SavedTimeDilation * 0.1;
		Log("CoopGame: slow start until the clients see their squad members");
	}
}

function int CountWatchers()
{
	local Controller C;
	local int n;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && CoopPlayer(C).bIntroWatch)
			++n;
	}

	return n;
}

function CheckSlowStart()
{
	local Controller C;
	local int Waiting;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && CoopPlayer(C).bIntroWatch && !CoopPlayer(C).bWatchCameraOn)
			++Waiting;
	}

	if(Waiting > 0 && class'CoopNative'.static.GetRealTime() - SlowStartTime < 4)
		return;

	bSlowStart = false;
	Level.TimeDilation = SavedTimeDilation;
	LevelStartTime = Level.TimeSeconds;
	Log("CoopGame: normal speed after " $ (class'CoopNative'.static.GetRealTime() - SlowStartTime) $ " s, " $ Waiting $ " clients without their member's camera");
}

function CoopTravel(string URL)
{
	class'CoopConfig'.default.TravelClients = CountClients();
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
	class'CoopConfig'.default.TravelClients = CountClients();

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
	HUDType="ModCoop.CoopHUD"
	MaxCoopPlayers=4
	ClientRespawnDelay=5.0
	bClientsTakeOverSquad=True
	GatherDistance=900
	ArrivalRadius=250
	SceneMaps(0)="GEO_03A"
	SceneEndEvents(0)="Elevator"
	SceneMaps(1)="RAS_03A"
	SceneEndEvents(1)="UnlockPlayer"
	SceneMaps(2)="YYY_04B"
	SceneEndEvents(2)="UnlockPlayer"
	MaxClientWait=60
	ClientBleedOutTime=45.0
	CatchUpDistance=4000.0
	CatchUpDelay=15.0
	MaxSpawnWait=30.0
	HostReviveWaitTime=60.0
	bPrivateNetworksOnly=False
	PlayerControllerClassName="ModCoop.CoopPlayer"
	GameName="Republic Commando Coop"
}
