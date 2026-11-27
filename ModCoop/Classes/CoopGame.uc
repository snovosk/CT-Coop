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

const MAP_ACTORS_PER_SECOND = 40;
var CoopFixes Fixes;
var bool      bCheckedLevel;
var bool      bLoadedFromSave;   // See PostLoadBeginPlay, AfterSaveLoaded
var bool      bTravelling;       // ProcessServerTravel ran: the level is going, its players leave with it (IsQuietLeave)
var bool      bQuietLeave;       // The player leaving now does so for a level change or a load: no message (Logout, BroadcastLocalized)
const CHECKPOINT_SAVE = "CoopCheckpoint";
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
var Pawn        TestDownPawn, TestReviver;  // ?CoopTest=clientdown
var vector      TestDownLoc;
var bool    bTestResSet;
var string  TestEvents;
var string  TestCauses;
var float   NextTestOrderStep, TestOrderTime;
var int     TestOrderStage;
var bool    bTestBreachOrdered, bTestBreachDone;
var float   NextTestCause;
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
var ScriptedAction LastMusicActions[3]; // Last PlayMusic, SetImuseState, SetBattleMusicMulti, for clients that join later (see SendLastMusic)
var float LastMusicTimes[3];
var array<Actor> TriggeredActors; // Emitters triggered on the server, in order, for clients that join later (see SendLastTriggers)
var array<float> TriggeredTimes;
var Pawn TestTarget;
var float NextSnipeOrderLog; // See CheckAISnipeOrders

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
var array<name>        DeferredEvents;      // See RunSkippedActions
var array<name>        DeferredFires;       // The event to trigger for each entry of DeferredEvents
var array<Pawn>        DeferredPawns;
var array<name>        MissableEvents;      // See ListenForMissableEvents
var bool               bListenedForMissable;
var name               MissionFailEvent;    // See CheckMissionFailed
var float              MissionFailTime;
var Turret             TestTurret;
var vector             TestEliteLast;     // Test elite: see TestEliteTick
var name               TestEventName;     // Test elite: the event it triggers
var int                TestWalkerUp;      // Test walker: the step at which BigLift had the walker up
var bool               bTestTargetSpawned;
var int                TestUseStep;
var int                TestSubStep;
var Mover              LastRideLift;        // See HostLift
var float              LastRideMoveTime, LastRideSeenTime;
var bool               bRidersHidden;       // See HideRiders
var PlayerController   RideLeader;          // See CheckLiftRides: the player the others are brought to
var float              RideEndTime;         // See RidersApart
var float              RideOverTime;        // See CheckLiftRides: when the last ride ended, clients are let go with the host
var Mover              PinnedLift;          // See PinRideLift
var Mover.EMoverEncroachType PinnedEncroach;
const RIDE_GHOST_TIME = 10.0;
const RIDE_RELEASE_WAIT = 15.0;  // Longest wait of the clients for the host's briefing after a ride (CheckLiftRides)
const RIDE_APART_DISTANCE = 100.0;
var array<Actor>       RideHiddenActors;
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
var float              NextTrackerResend;  // See SyncObjectiveTracker
var MissionObjectives  Objectives;          // See SyncObjectives
var string             SentObjectives;
var float              NextObjectivesResend;
var array<SquadMarker> ClientSnipeMarkers; // See CheckClientSnipers: 1 entry per marker, asked or done
var array<byte>        ClientSnipeStates;  // 1 = the client was asked to take the position, 2 = in position
var float              NextSnipeTrackerTime;
var bool  bWaitingForClients;    // See WaitForClients
var SquadMarker StuckMarker;         // See CheckStuckBreachMarkers
var float StuckMarkerTime;
var SquadMarker LastActiveSnipeMarker; // See CheckAISnipeOrders
var float NextSnipeOrderHint;       // See HintSnipeOrder
var CoopSevIntro SevIntro;         // See CoopSevIntro
var CoopEndLift EndLift;           // See CoopEndLift
var CoopSpaceWalk SpaceWalk;       // See CoopSpaceWalk
var CoopDoorHold DoorHold;         // See CoopDoorHold
var CoopCheckpointReturn CheckpointReturn; // See CoopCheckpointReturn
var CoopCaptiveTakeover CaptiveTakeover;   // See CoopCaptiveTakeover
var bool bRespawningHost;          // See CheckSquadDown: the host gets a new pawn instead of the game's "load the last save"
var CoopSight Sight;               // See CoopSight
var CoopLobby Lobby;               // Only on the map of the lobby, see CoopLobby
var string EndLiftMap;
var float ClientsReadyTime;        // See CheckClientWaitTime
var array<name>      HiddenTags;         // See ForwardSetHidden
var array<byte>      HiddenTagValues;
var array<name>      MarkerStateTags;    // See ForwardMarkerState
var array<Pawn>      ScriptAnimPawns;    // See ForwardScriptAnim
var array<name>      ScriptAnimNames;
var array<float>     ScriptAnimRates;
var array<byte>      ScriptAnimLoops;
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
var int   HostBleedOutRequests;          // See CountHostBleedOutRequest
var bool  bHostSquadSoundsSaved;
var CTSquadNative SavedSoundSquad;
var Sound SavedSquadIncapSound, SavedSquadDeathSound;

// See CheckStaleBeams
struct BeamWatch
{
	var Emitter E;
	var LaserWeaponAmmo Ammo;
	var float LastFired;
	var float NextLog;
};
var array<BeamWatch> BeamWatches;
var int BeamLogLines;

const HOST_BLEEDOUT_LOG_LINES = 20;
const REVIVE_GRACE = 30.0;          // Seconds a client being revived may stay down past ClientBleedOutTime (IsBeingRevived)
const BEAM_STALE_TIME = 2.0;
const BEAM_LOG_INTERVAL = 10.0;
const BEAM_LOG_LINES = 20;
const STUCK_MARKER_TIME = 5.0;
const MISSION_FAIL_DELAY = 8.0;      // Long enough for the fade and the host's death in the level's script
const SNIPE_ORDER_HINT_INTERVAL = 8.0;
const SNIPE_ORDER_HINT_TIME = 6.0;
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

	if(ParseOption(Options, "CoopFixedSquad") != "")
		class'CoopConfig'.default.bFixedSquad = true;

	if(class'CoopConfig'.default.bFixedSquad)
		Log("CoopGame: fixed squad, every client only plays its assigned squad member");

	// MaxPlayers is a globalconfig variable of GameInfo. It is only changed in memory and never saved here.
	MaxPlayers = Clamp(GetIntOption(Options, "MaxPlayers", MaxCoopPlayers), 1, 4);
	bPauseable = false;
	bAdminCanPause = false;

	// Drop clients that crashed or lost the connection faster than the System.ini default of 120 seconds
	class'CoopNative'.static.SetNetTimeouts(class'CoopConfig'.default.ServerTimeout, class'CoopConfig'.default.ServerTimeout);
	class'CoopNative'.static.SetNetRates(class'CoopConfig'.default.NetClientRate, class'CoopConfig'.default.NetTickRate);

	// The options stay in the URL of the next levels, the map tells it
	if(Left(Caps(string(Level)), 8) == "MPCUSTOM")
	{
		Lobby = new class'CoopLobby';
		Lobby.Setup(self, ParseOption(Options, "CoopLobbyLevel"));

		if(int(ParseOption(Options, "CoopLobbySave")) != 0)
			Lobby.PickSave(int(ParseOption(Options, "CoopLobbySave")));

		// Steam friends find this game through the relay. Without Steam the relay just ends.
		class'CoopNative'.static.StartRelay("host");
	}

	InitHelpers();

	// A new level or a restart: the checkpoint save of the level before doesn't apply. A loaded save doesn't come through here
	class'CoopConfig'.default.CheckpointSaveLevel = "";

	TestAction = ParseOption(Options, "CoopTest");
	TestOptions = Options;
	TestEvents = ParseOption(Options, "CoopTestEvent");
	TestCauses = ParseOption(Options, "CoopTestCause");
	NextTestCause = float(ParseOption(Options, "CoopTestCauseEvery"));
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

/*
 * The helpers made with new aren't in a save (Reports/2026-11-10-save/RESEARCH.md): None after a load, and CoopGame.Tick crashed the host.
 * Made here for InitGame and again after a load.
 */
function InitHelpers()
{
	SevIntro = new class'CoopSevIntro';
	SevIntro.Setup(self);
	// Here, not with the level's other helpers: a level saves its first checkpoint (CoopPlayer.AutoSave) before those exist
	CheckpointReturn = new class'CoopCheckpointReturn';
	CheckpointReturn.Setup(self);
	// The lift a level starts on is held from the first script tick (CoopEndLift.ShouldHoldStartLift), CheckLevel sets up the rest later
	EndLift = new class'CoopEndLift';
	EndLift.Game = self;
	SpaceWalk = new class'CoopSpaceWalk';
	SpaceWalk.Setup(self);
}

// A checkpoint save was loaded (see LoadSavedCheckpoint): the level is as it was then, the mod's helpers start again
event PostLoadBeginPlay()
{
	Super.PostLoadBeginPlay();
	InitFixes();
	InitHelpers();
	bCheckedLevel = false;
	bLoadedFromSave = true;
	// The engine spawns a new uplink after the load, the save says the old one was removed: a client got BADCDKEY (test 2026-11-11)
	bRemovedUplink = false;
	RemoveUplink();

	// The save counts the players it had: with 3 clients the host's own login was refused as a full server and the game quit
	// (__SERVERFULL__, test 2026-11-11). Counted again in AfterSaveLoaded
	if(class'CoopConfig'.default.bLoadingSave)
	{
		Log("CoopGame: checkpoint save: " $ NumPlayers $ " players in the save, counted again");
		NumPlayers = 0;
		NumInvitedPlayers = 0;

		// The next level change went to 0.0.0.0/<map> as a client and never happened (RAS_03C, 2026-11-11, CoopNative.FixLoadedLevelURL)
		Log("CoopGame: save loaded, level URL was " $ class'CoopNative'.static.FixLoadedLevelURL(self));

		// Before any client connects (they wait for the level): the network numbers the save's objects like the clean map the clients load
		Log("CoopGame: save " $ class'CoopConfig'.default.LoadingSaveName $ ": remap for clients: " $
		    class'CoopNative'.static.RemapSavedLevel(self, class'CoopConfig'.default.LoadingSaveName));
	}

	Log("CoopGame: checkpoint save loaded, helpers made again, level package " $ class'CoopNative'.static.LevelPackageText(self));
	SetTimer(1.0, true);
}

/*
 * First timer after a load, the host has his viewport again. The clients' controllers came back from the save without a connection: they go,
 * a client's own commando with them, a squad member it played gets its AI back and goes to the client again when it logs in (CheckSquadTakeover).
 * The level waits for the clients like at a level change.
 */
function AfterSaveLoaded(PlayerController Host)
{
	local Controller C, Next;
	local Pawn P;
	local Controller AI;
	local bool bFromSave;

	// PostLoadBeginPlay also runs for a level loaded from its map
	bFromSave = class'CoopConfig'.default.bLoadingSave;
	class'CoopConfig'.default.bLoadingSave = false;
	class'CoopConfig'.default.LoadingSaveMap = "";

	if(bFromSave)
	{
		CheckpointReturn.TakePersisted(Host.PlayerReplicationInfo.PlayerName);
		Log("CoopGame: save loaded, " $ TestEnemyText());
	}

	for(C = Level.ControllerList; C != None; C = Next)
	{
		Next = C.nextController;

		if(PlayerController(C) == None || C == Host || PlayerController(C).Player != None)
			continue;

		P = C.Pawn;
		Log("CoopGame: checkpoint save: player " $ C.PlayerReplicationInfo.PlayerName $ " of the save has no connection, pawn " $ P);

		if(P != None)
		{
			C.UnPossess();

			if(CoopCommando(P) != None)
				P.Destroy();
			else if(P.ControllerClass != None)
			{
				AI = Spawn(P.ControllerClass);

				if(AI != None)
					AI.Possess(P);

				Log("CoopGame: checkpoint save: " $ P $ " back to the AI " $ AI);
			}
		}

		C.Destroy();
	}

	// The engine drops the clients' controllers of the save before this: their squad members are left without one
	foreach DynamicActors(class'Pawn', P)
	{
		if(bFromSave && P.IsA('CloneCommando') && CoopCommando(P) == None && P != Host.Pawn && P.Health > 0 && P.ControllerClass != None &&
		   (P.Controller == None || (PlayerController(P.Controller) != None && PlayerController(P.Controller).Player == None)))
		{
			if(P.Controller != None)
				P.Controller.UnPossess();

			AI = Spawn(P.ControllerClass);

			if(AI != None)
				AI.Possess(P);

			Log("CoopGame: checkpoint save: " $ P $ " had no controller, now the AI " $ AI $ ", squad " $ P.Squad);
		}
	}

	// Their logouts counted down from the save's number (see PostLoadBeginPlay)
	NumPlayers = 0;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) != None && PlayerController(C).Player != None && !C.bDeleteMe && !C.PlayerReplicationInfo.bOnlySpectator)
			++NumPlayers;
	}

	WaitForClients(Host);
}

// See CoopPlayer.AutoSave: a level's checkpoint saves the whole level on the host (UGameEngine::SaveGame, CoopNative.EngineSaveGame)
function SaveCheckpoint()
{
	local string Result, Map;

	CheckpointReturn.Remember();

	if(!CheckpointReturn.HasPoint() || GetHost() == None)
		return;

	// The save has the clients' squad members in the squad, so they go to their AI and back to the clients after a load (AfterSaveLoaded).
	// Nothing ticks between the two: the squad AI never runs with a client's member in it (see DetachClientMembers)
	if(GetHost().Pawn != None && GetHost().Pawn.Squad != None)
		AttachClientMembers(GetHost().Pawn.Squad);

	Result = class'CoopNative'.static.EngineSaveGame(CHECKPOINT_SAVE);
	DetachClientMembers();
	GetHost().GetCurrentMapName(Map);

	if(InStr(Result, "called ok") != -1 && InStr(Result, CHECKPOINT_SAVE $ ".cts") != -1)
	{
		class'CoopConfig'.default.CheckpointSaveLevel = Map;
		CheckpointReturn.Persist();
	}
	else
		class'CoopConfig'.default.CheckpointSaveLevel = "";

	Log("CoopGame: checkpoint save of " $ Map $ ": " $ Result);
}

/*
 * Why the host can't save now, "" if he can. The user's rule (2026-11-11): not while a player is down, nor during a scene, the briefing or a
 * level change: a save there would come back in that state.
 */
function string SaveBlocker()
{
	local PlayerController Host;
	local Controller C;

	Host = GetHost();

	if(Host == None || Host.Pawn == None || Level.NextURL != "" || bWaitingForClients || Lobby != None)
		return "CAN'T SAVE NOW";

	if(Host.bBriefing || Host.ViewTarget != Host.Pawn || IsSpaceWalkRunning())
		return "CAN'T SAVE DURING A SCENE";

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) == None)
			continue;

		if(C.Pawn == None || C.Pawn.Health <= 0 || C.Pawn.bIncapacitated)
			return "CAN'T SAVE WHILE A PLAYER IS DOWN";

		if(CoopPlayer(C) != None && (CoopPlayer(C).bIntroWatch || C.IsInState('CoopWatching')))
			return "CAN'T SAVE DURING A SCENE";
	}

	return "";
}

// SAVE GAME of the host's pause menu (CoopSaveMenu): the level and every player into a slot (CoopSaveSlots). "" when saved, else why not
function string SaveToSlot(int Slot)
{
	local CoopCheckpointReturn Snapshot;
	local string Result, Map, Reason;
	local int i;

	Reason = SaveBlocker();

	if(Reason != "")
	{
		Log("CoopGame: save slot " $ Slot $ " refused: " $ Reason);
		return Reason;
	}

	// Its own snapshot: the level's checkpoint stays what it was
	Snapshot = new class'CoopCheckpointReturn';
	Snapshot.Setup(self);
	Snapshot.RememberAll();
	GetHost().GetCurrentMapName(Map);

	// Like SaveCheckpoint: the clients' squad members are in the squad while the level is written
	if(GetHost().Pawn.Squad != None)
		AttachClientMembers(GetHost().Pawn.Squad);

	Result = class'CoopNative'.static.EngineSaveGame(class'CoopSaveSlots'.static.SaveName(Slot));
	DetachClientMembers();
	Log("CoopGame: save slot " $ Slot $ " of " $ Map $ ": " $ Result);

	if(InStr(Result, "called ok") == -1 || InStr(Result, class'CoopSaveSlots'.static.SaveName(Slot) $ ".cts") == -1)
		return "SAVING FAILED";

	class'CoopSaveSlots'.static.Write(Slot, "Map", Map);
	class'CoopSaveSlots'.static.Write(Slot, "Time", class'CoopSaveSlots'.static.TimeText(Level));
	class'CoopSaveSlots'.static.Write(Slot, "Build", class'CoopNative'.static.ModPackageGuid());
	class'CoopSaveSlots'.static.Write(Slot, "Players", string(Snapshot.Saved.Length));

	for(i = 0; i < Snapshot.Saved.Length; ++i)
	{
		class'CoopSaveSlots'.static.Write(Slot, "Player" $ i, Snapshot.EncodePlayer(i));
		Log("CoopGame: save slot " $ Slot $ ": " $ Snapshot.EncodePlayer(i));
	}

	Broadcast(self, "Game saved: " $ class'CoopSaveSlots'.static.Describe(Slot));

	return "";
}

// The lobby starts the game from a slot (CoopLobby.CheckStart): the host loads its save, the clients its map
function LoadSlotFromLobby(int Slot)
{
	local string Map;

	Map = class'CoopSaveSlots'.static.Read(Slot, "Map");
	class'CoopCheckpointReturn'.static.PersistSlot(Slot);
	class'CoopConfig'.default.bLoadingSave = true;
	class'CoopConfig'.default.LoadingSaveName = class'CoopSaveSlots'.static.SaveName(Slot);
	class'CoopConfig'.default.LoadingSaveMap = Map;
	class'CoopConfig'.default.CheckpointSaveLevel = "";
	class'CoopConfig'.default.TravelClients = CountClients();
	Log("CoopGame: save slot " $ Slot $ ": loading " $ Map $ " with " $ CountClients() $ " clients");
	Level.ServerTravel("?load=" $ class'CoopSaveSlots'.static.SaveName(Slot), false);
}

// True: the level is being loaded from the checkpoint save. The clients get the clean map (ProcessServerTravel)
function bool LoadSavedCheckpoint()
{
	local string Map;

	if(GetHost() == None || Level.NextURL != "")
		return false;

	GetHost().GetCurrentMapName(Map);

	if(class'CoopConfig'.default.CheckpointSaveLevel == "" || !(class'CoopConfig'.default.CheckpointSaveLevel ~= Map))
		return false;

	// Clients load the clean map and get the save's state by replication: the host numbers the save's objects like the map (AfterSaveLoaded)
	class'CoopConfig'.default.TravelClients = CountClients();
	Broadcast(self, "Loading the checkpoint...");
	Log("CoopGame: loading the checkpoint save of " $ Map);
	class'CoopConfig'.default.bLoadingSave = true;
	class'CoopConfig'.default.LoadingSaveName = CHECKPOINT_SAVE;
	class'CoopConfig'.default.LoadingSaveMap = Map;
	Level.ServerTravel("?load=" $ CHECKPOINT_SAVE, false);

	return true;
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

/*
 * A player of the lobby's session (CoopConfig.SessionPlayers), also under the name MakeNameUnique gave it ("Name_2"): a client coming
 * back while its old connection is still there gets one, keeps it (ClientCoopKeepName) and was refused at the next level change, the
 * host waited a minute and started without it (YYY_01D, the user's game 2026-11-14).
 */
function bool IsSessionPlayer(string PlayerName)
{
	local string Players;
	local int i;

	Players = class'CoopConfig'.default.SessionPlayers;
	PlayerName = class'CoopSaveSlots'.static.CleanName(PlayerName);

	if(InStr(Players, "|" $ PlayerName $ "|") != -1)
		return true;

	// "_" and 2 to 9 at the end, as MakeNameUnique adds it
	i = Len(PlayerName) - 2;

	return i > 0 && Mid(PlayerName, i, 1) == "_" && int(Mid(PlayerName, i + 1)) >= 2 && InStr(Players, "|" $ Left(PlayerName, i) $ "|") != -1;
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

	// The user's rule (2026-11-11): who plays is decided in the lobby. Once its game runs only its players can come back (a crash, a lost
	// connection). Games not started from a lobby (tests) are open as before
	if(Error == "" && Lobby == None && class'CoopConfig'.default.SessionPlayers != "" && !IsSessionPlayer(ParseOption(Options, "Name")))
	{
		Log("CoopGame: Rejected " $ ParseOption(Options, "Name") $ ": not a player of this session (" $ class'CoopConfig'.default.SessionPlayers $ ")");
		Error = "This co-op game has already started. New players join in the lobby before the game starts.";
	}

	if(Error == "" && bPrivateNetworksOnly && !IsPrivateAddress(Address))
	{
		Log("CoopGame: Rejected " $ Address $ " (bPrivateNetworksOnly)");
		Error = "This coop server only accepts LAN/VPN addresses";
	}
}

event PostLogin(PlayerController NewPlayer)
{
	Super.PostLogin(NewPlayer);

	// Music and emitter triggers from before this moment are sent when the client has its pawn (SendLastMusic, SendLastTriggers)
	if(CoopPlayer(NewPlayer) != None)
	{
		CoopPlayer(NewPlayer).LoginTime = Level.TimeSeconds;
		ResetMoveClock(NewPlayer, "login");
	}

	// Otherwise a second game instance on the same PC is rejected because of the duplicate CD key
	class'CoopNative'.static.ReleaseAllCDKeys();

	MakeNameUnique(NewPlayer);

	if(Lobby != None && CoopPlayer(NewPlayer) != None)
		Lobby.PlayerJoined(CoopPlayer(NewPlayer));

	if(IsHost(NewPlayer))
		WaitForClients(NewPlayer);
	else if(bWaitingForClients)
		CheckClientsArrived();

	if(!IsHost(NewPlayer))
	{
		Log("CoopGame: Client joined: " $ NewPlayer.PlayerReplicationInfo.PlayerName);

		if(!IsQuietArrival(NewPlayer.PlayerReplicationInfo, false))
			Broadcast(self, NewPlayer.PlayerReplicationInfo.PlayerName $ " joined the squad");
	}
}

function ReturnToAI(Controller Exiting)
{
	local Pawn P;
	local Controller AI;

	P = Exiting.Pawn;
	Exiting.UnPossess();
	AI = Spawn(P.ControllerClass);

	if(AI != None)
		AI.Possess(P);

	Log("CoopGame: save loaded: " $ P $ " of " $ Exiting.PlayerReplicationInfo.PlayerName $ " back to the AI " $ AI);
}

/*
 * Leaving and arriving are announced only when a player really leaves or comes (the user, 2026-11-11): the button, a lost connection, a new
 * player. A level change, a checkpoint or a save drop every client and bring it back, and that said "left the squad", "left the game",
 * "joined the squad", "entered the game" every time. Quiet: the old level is changing (Level.NextURL), a save is loading, controllers of a
 * save without a connection are removed (CleanUpOrphans), and the arrival of a player who changed level with the host (TravelPlayers).
 */
function bool IsQuietLeave()
{
	// Level.NextURL is cleared before the old level's players are logged out: they still said "left" (test 2026-11-12)
	return bQuietLeave || bTravelling || Level.NextURL != "" || class'CoopConfig'.default.bLoadingSave;
}

function bool IsQuietArrival(PlayerReplicationInfo PRI, bool bForget)
{
	local string Key;

	if(PRI == None)
		return false;

	Key = "|" $ class'CoopSaveSlots'.static.CleanName(PRI.PlayerName) $ "|";

	if(InStr(class'CoopConfig'.default.TravelPlayers, Key) == -1)
		return false;

	if(bForget)
		class'CoopConfig'.default.TravelPlayers = Repl1(class'CoopConfig'.default.TravelPlayers, Key, "|");

	return true;
}

// The first occurrence of Find replaced (no Repl in this engine)
function string Repl1(string Text, string Find, string With)
{
	local int i;

	i = InStr(Text, Find);

	if(i == -1)
		return Text;

	return Left(Text, i) $ With $ Mid(Text, i + Len(Find));
}

event BroadcastLocalized(Actor Sender, class<LocalMessage> Message, optional int Switch, optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2, optional Object OptionalObject)
{
	// GameMessage 1 "entered the game", 4 "left the game"
	if(Message == GameMessageClass && ((Switch == 4 && IsQuietLeave()) || (Switch == 1 && IsQuietArrival(RelatedPRI_1, true))))
	{
		Log("CoopGame: message " $ Switch $ " of " $ RelatedPRI_1.PlayerName $ " not shown (level change or load)");
		return;
	}

	Super.BroadcastLocalized(Sender, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
}

function Logout(Controller Exiting)
{
	if(PlayerController(Exiting) != None && !IsHost(PlayerController(Exiting)))
	{
		Log("CoopGame: " $ Exiting.PlayerReplicationInfo.PlayerName $ " leaves, announced: " $ !IsQuietLeave());

		if(!IsQuietLeave())
			Broadcast(self, Exiting.PlayerReplicationInfo.PlayerName $ " left the squad");

		// A loaded save drops the clients' controllers (see AfterSaveLoaded): a squad member they played goes back to its AI and to the client
		// again when it is back (CheckSquadTakeover)
		if(class'CoopConfig'.default.bLoadingSave && Exiting.Pawn != None && CoopCommando(Exiting.Pawn) == None && Exiting.Pawn.ControllerClass != None)
			ReturnToAI(Exiting);
		// Remove the pawn so it doesn't stand around without a player
		else if(Exiting.Pawn != None)
			Exiting.Pawn.Destroy();
	}

	Super.Logout(Exiting);
}

/*
 * Spawning
 */

/*
 * A new inventory (spawn, takeover) reached the client one item at a time and every weapon was brought up as it arrived, followed by
 * a switch to the best one (and that again every second until the server had a weapon): the clients' weapons jerked and were drawn
 * again and again while the level loaded. The client ignores these switches (CoopPlayer.ClientCoopWeaponsQuiet) and brings up the
 * rifle once, the server sets the same weapon.
 */
function EquipQuietly(CoopPlayer CP, Pawn P)
{
	local Weapon W;
	local class<Weapon> RifleClass;

	RifleClass = class<Weapon>(DynamicLoadObject(class'PlayerCommando'.default.RequiredEquipment[0], class'Class', true));

	if(RifleClass != None)
		W = Weapon(P.FindInventoryType(RifleClass));

	if(W != None && P.Weapon != W)
	{
		P.PendingWeapon = W;
		P.ChangedWeapon();
	}

	if(W != None)
		CP.ClientCoopWeaponsQuiet(false, W.Class);
	else
		CP.ClientCoopWeaponsQuiet(false, None);

	Log("CoopGame: equipped " $ P $ " of " $ CP.PlayerReplicationInfo.PlayerName $ " with " $ P.Weapon $ " (client brings up " $ RifleClass $ ")");
}

/*
 * Clients got the player's default equipment on every level (spawn and takeover), the host keeps what the level and the previous
 * levels gave him (picked up weapons travel with the player). Weapons of the host that the client lacks are added, not the turret's.
 */
function GiveHostWeapons(Pawn P)
{
	local PlayerController Host;
	local Inventory Inv;
	local Weapon W;
	local string Added;

	Host = GetHost();

	if(Host == None || Host.Pawn == None || P == None || P == Host.Pawn)
		return;

	for(Inv = Host.Pawn.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		W = Weapon(Inv);

		if(W == None || W.WeaponType == WT_Turret || W == SnipeLentRifle || P.FindInventoryType(W.Class) != None)
			continue;

		P.CreateInventory(string(W.Class));

		if(P.FindInventoryType(W.Class) != None)
			Added = Added $ " " $ W.Class.Name;
		else
			Added = Added $ " (" $ W.Class.Name $ " failed)";
	}

	if(Added != "")
		Log("CoopGame: weapons of the host added to " $ P $ ":" $ Added);
}

// Two weapons of one class in an inventory (session 2026-11-02: a client saw two sets, the source isn't known yet). The one in the hands stays
function RemoveDuplicateWeapons(Pawn P)
{
	local Inventory A, B, Next;

	for(A = P.Inventory; A != None; A = A.Inventory)
	{
		if(Weapon(A) == None)
			continue;

		for(B = A.Inventory; B != None; B = Next)
		{
			Next = B.Inventory;

			if(B.Class == A.Class && B != P.Weapon && B != P.PendingWeapon)
			{
				Log("CoopGame: duplicate weapon " $ B.Class.Name $ " of " $ P $ " removed");
				P.DeleteInventory(B);
				B.Destroy();
			}
		}
	}
}

// Test: a client on Lift01 (GEO_05A), away from its trigger, starts the lift, the host is brought to it, invisible for the client until they stand apart
function TestHostLift(PlayerController Host)
{
	local Controller C;
	local Trigger T, Gate;
	local Mover M, Lift;

	foreach AllActors(class'Trigger', T)
	{
		if(T.Event == 'Lift01Lockdown')
			Gate = T;
	}

	foreach AllActors(class'Mover', M, 'Lift01')
		Lift = M;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			break;
	}

	if(Gate == None || Lift == None || C == None)
	{
		Log("CoopTest: hostlift: gate " $ Gate $ " lift " $ Lift $ " client " $ C);
		return;
	}

	if(TestStep == 0)
	{
		C.Pawn.SetLocation(Lift.Location + vect(0,-10,210));
		C.ClientSetLocation(C.Pawn.Location, C.Pawn.Rotation);
	}

	Log("CoopTest: hostlift: " $ TestStep $ " lift Z=" $ Lift.Location.Z $ " moving=" $ Lift.bInterpolating $ " client base=" $ C.Pawn.Base $ " Z=" $ C.Pawn.Location.Z $ " host base=" $ Host.Pawn.Base $ " Z=" $ Host.Pawn.Location.Z);
}

// Test: every player stands 220 units from the closest free turret and looks at it, the target has to be TGT_MountTurret
function TestTurretNear(PlayerController Host)
{
	local Controller C;
	local Turret T, Best;
	local vector Offset;
	local rotator R;
	local int i;

	foreach AllActors(class'Turret', T)
	{
		if(!T.IsA('AutoTurret') && (T.Gunner == None || T.Gunner.Health <= 0) && (Best == None || VSize(T.Location - Host.Pawn.Location) < VSize(Best.Location - Host.Pawn.Location)))
			Best = T;
	}

	if(Best == None)
	{
		Log("CoopTest: turretnear: no turret");
		return;
	}

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) == None || C.Pawn == None)
			continue;

		if(TestStep == 0)
		{
			Offset = vect(220,0,0) >> Best.Rotation;
			Offset.Z = 40;

			if(i == 1)
				Offset.Y = Offset.Y + 60;

			Best.SquadMarker = None;
			C.Pawn.SetLocation(Best.Location + Offset);
			R = rotator(Best.Location - C.Pawn.Location);
			C.SetRotation(R);
			C.Pawn.SetRotation(R);
			PlayerController(C).ClientSetRotation(R);

			if(!IsHost(C))
				PlayerController(C).ClientSetLocation(C.Pawn.Location, R);

			i = i + 1;
		}

		// The client's rotation comes back from its moves, it has to turn on its side
		if(!IsHost(C) && TestStep > 0 && TestStep < 4)
			PlayerController(C).ClientSetRotation(rotator(Best.Location - C.Pawn.Location));

		Log("CoopTest: turretnear: " $ TestStep $ " " $ C $ " " $ Best $ " dist " $ VSize(Best.Location - C.Pawn.Location) $ " Target=" $ PlayerController(C).Target $ " TargetType=" $ PlayerController(C).TargetType $ " state " $ C.GetStateName() $ " dot " $ (Normal(Best.Location - C.Pawn.Location) dot vector(C.Rotation)) $ " free " $ FastTrace(Best.Location, C.Pawn.Location + C.Pawn.EyePosition()) $ " available " $ Best.IsAvailableFor(C.Pawn));
	}
}

/*
 * Test walker (RAS_04C): see TickTest. Its own function: TickTest is at the size limit of a function's code. True while it runs.
 */
/*
 * Test snipeorder (RAS_03A, a client bound to Sev): the host aims at the sniper position CoopTestTag (default BridgeMarker) and presses
 * Use like the player; an AI member has to take it like in single player (SnipeNeedsClient). The host keeps looking at the position,
 * screenshots on "snipeorder: shot <stage>". True while it runs.
 */
function bool TestSnipeOrder(PlayerController Host)
{
	local SquadMarker M, Found;
	local Controller C;
	local Actor A;
	local vector V;
	local rotator R;
	local int i;
	local string MarkerTag;

	MarkerTag = ParseOption(TestOptions, "CoopTestTag");

	if(MarkerTag == "")
		MarkerTag = "BridgeMarker";

	foreach AllActors(class'SquadMarker', M)
	{
		if(M.IsA('MarkerSnipe') && string(M.Tag) ~= MarkerTag && M.Anchor != None && (Found == None || VSize(M.Anchor.Location - Host.Pawn.Location) < VSize(Found.Anchor.Location - Host.Pawn.Location)))
			Found = M;
	}

	if(Found == None || Host.Pawn == None)
	{
		Log("CoopTest: snipeorder: no sniper position " $ MarkerTag);
		return false;
	}

	if(TestStep == 0)
	{
		Host.bGodMode = true;
		V = Found.Anchor.Location + vect(0,0,1) * 40 - vector(Found.Anchor.Rotation) * 350;

		if(!Host.Pawn.SetLocation(V) && FindSpawnLocation(V, rotator(Found.Anchor.Location - V), V))
			Host.Pawn.SetLocation(V);

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				C.bGodMode = true;

				if(FindSpawnLocation(Host.Pawn.Location, Host.Rotation, V) && C.Pawn.SetLocation(V))
					C.ClientSetLocation(V, C.Rotation);
			}
		}

		Log("CoopTest: snipeorder: " $ Found $ " state " $ Found.GetStateName() $ " anchor " $ Found.Anchor $ ", host at " $ int(VSize(Host.Pawn.Location - Found.Anchor.Location)) $ " client of Sev " $ MarkerClient(Found));
	}

	// Looking at the position all the time: at its anchor until the order, then where the members go
	R = rotator(Found.Anchor.Location - (Host.Pawn.Location + Host.Pawn.EyePosition()));
	Host.SetRotation(R);
	Host.Pawn.Acceleration = vect(0,0,0);

	// The client (Sev) watches too: on a level that starts an act the host's window keeps the act's intro screen open
	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			PlayerController(C).ClientSetRotation(rotator(Found.Anchor.Location - (C.Pawn.Location + C.Pawn.EyePosition())));
	}

	if(TestStep == 3)
		Log("CoopTest: snipeorder: shot before");

	// Flashlights and accessories on pawns and their owners, on the server and the client (CTPlayer.SelectTargetType crash)
	if(TestStep == 2 || TestStep == 20)
	{
		foreach AllActors(class'Actor', A)
		{
			if((A.IsA('Flashlight') || A.IsA('Accessory')) && Pawn(A.Base) != None)
				Log("CoopTest: attached: server " $ A.Class.Name $ " on " $ A.Base.Class.Name $ " Owner=" $ A.Owner $ " RemoteRole=" $ A.RemoteRole $ " Collide=" $ A.bCollideActors $ " ZeroTrace=" $ A.bBlockZeroExtentTraces);
		}

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				CoopPlayer(C).ClientCoopTestCommand("AttachedLog");
		}
	}

	if(TestStep == 4)
	{
		Log("CoopTest: snipeorder: host Target=" $ Host.Target $ " TargetType=" $ Host.TargetType $ " TargetMarker=" $ Host.TargetMarker);

		// The crosshair on the position's hologram, as when the player aims at it (the test can't aim at the icon itself)
		if(Host.TargetMarker != Found)
		{
			Host.Target = Found.Anchor;
			Host.TargetMarker = Found;
			Host.TargetType = TGT_Marker;
			Log("CoopTest: snipeorder: the host's target set to " $ Found);
		}

		CoopPlayer(Host).Use();
	}

	for(i = 0; i < 3; i = i + 1)
	{
		if(Found.Participants[i].Member != None)
			Log("CoopTest: snipeorder: " $ TestStep $ " participant " $ Found.Participants[i].Member.Class.Name $ " " $ int(VSize(Found.Participants[i].Member.Location - Found.Anchor.Location)) $ " from the position");
	}

	Log("CoopTest: snipeorder: " $ TestStep $ " " $ Found $ " state " $ Found.GetStateName() $ " active " $ Found.bMarkerActive $ " complete " $ Found.bComplete);

	if(TestStep == 7)
		Log("CoopTest: snipeorder: shot ordered");

	if(TestStep == 18)
		Log("CoopTest: snipeorder: shot taken");

	if(TestStep < 24)
	{
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return true;
	}

	return false;
}

/*
 * Test accessory: the first client aims at the closest armour piece of another pawn, steps 2-6 without CoopPlayer.CheckAccessoryOwners
 * (the target crash of CTPlayer.SelectTargetType, "Caught a crash" in the client's log), steps 8-12 with it. True while it runs.
 */
function bool TestAccessory(PlayerController Host)
{
	local Controller C;
	local Pawn P;
	local vector V;
	local int i;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			break;
	}

	if(C == None)
		return false;

	if(TestStep == 0)
	{
		Host.bGodMode = true;
		C.bGodMode = true;

		// Next to Fixer, who stands still for the test
		foreach DynamicActors(class'Pawn', P)
		{
			if(P.IsA('Commando40Delta') && P.Controller != None && P.Controller != C)
			{
				P.Controller.GotoState('');
				P.Velocity = vect(0,0,0);
				P.Acceleration = vect(0,0,0);
				P.SetPhysics(PHYS_None); // Test only: the AI kept walking off

				for(i = 0; i < 8; i = i + 1)
				{
					V = P.Location + (vect(160,0,0) >> rot(0,8192,0) * i);

					if(FastTrace(V, P.Location) && C.Pawn.SetLocation(V))
					{
						C.ClientSetLocation(V, rotator(P.Location - V));
						break;
					}
				}

				Log("CoopTest: accessory: client " $ int(VSize(C.Pawn.Location - P.Location)) $ " from " $ P);
			}
		}
	}

	if(TestStep == 1)
		CoopPlayer(C).ClientCoopTestCommand("AccessoryFix 0");

	if(TestStep == 7)
		CoopPlayer(C).ClientCoopTestCommand("AccessoryFix 1");

	if((TestStep >= 2 && TestStep <= 6) || (TestStep >= 9 && TestStep <= 13))
		CoopPlayer(C).ClientCoopTestCommand("AimAccessory");

	if(TestStep < 14)
	{
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return true;
	}

	return false;
}

/*
 * Test aapickup (GEO_04D, a client bound to Scorch): the client takes the anti-armor pickup first (put right on it), the host comes to its
 * trigger later, then to the rock pile. The scripts of the anti-armor talk (ScriptedTrigger77) and of the rocks (ScriptedTrigger7) and the
 * demolition marker are logged every second: the tester's game stood at the rocks (2026-11-13). True while it runs.
 */
function bool TestAAPickup(PlayerController Host)
{
	local Controller C;
	local ScriptedController SC;
	local Pickup Pick;
	local SquadMarker M;
	local string Text;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			break;
	}

	if(C == None)
		return false;

	if(TestStep == 0)
	{
		Host.bGodMode = true;
		C.bGodMode = true;
	}

	foreach DynamicActors(class'Pickup', Pick)
	{
		if(Pick.Tag == 'DC17mAntiArmorWeaponPickup00')
			break;
	}

	if(TestStep == 2 && Pick != None)
	{
		C.Pawn.SetLocation(Pick.Location + vect(0,0,60));
		C.ClientSetLocation(C.Pawn.Location, C.Rotation);
		Log("CoopTest: aapickup: client put on the pickup " $ Pick $ " at " $ C.Pawn.Location);
	}

	// CoopTestClientUse=<step>: the client presses Use on it (as the player does, standing on it)
	if(TestStep == ParseOptionInt("CoopTestClientUse", -1))
		CoopPlayer(C).ClientCoopTestCommand("UseLooked");

	if(TestStep == ParseOptionInt("CoopTestHostAA", 8))
		Host.Pawn.SetLocation(vect(5877,1511,20160));

	if(TestStep == 30)
		Host.Pawn.SetLocation(vect(-402,2766,20676));

	if(TestStep == 34)
		Host.Pawn.SetLocation(vect(5062,1639,20160));

	// Scorch is the client: the charge on the rocks is his to place (MarkerSpecialist), then he blows it
	if(TestStep == 40)
	{
		C.Pawn.SetLocation(vect(4427,982,20167) + vect(0,120,60));
		C.ClientSetLocation(C.Pawn.Location, rotator(vect(4427,982,20167) - C.Pawn.Location));
	}

	if(TestStep == 42)
		CoopPlayer(C).ClientCoopTestCommand("UsePanel DemolitionCharge00");

	if(TestStep == 54)
		CoopPlayer(C).ClientCoopTestCommand("Detonate");

	Text = "CoopTest: aapickup: " $ TestStep $ " pickup " $ Pick $ " rocks " $ CountTagged('Rock00') + CountTagged('Rock01') + CountTagged('Rock02');

	foreach AllActors(class'ScriptedController', SC)
	{
		if(SC.SequenceScript != None && (SC.SequenceScript.Name == 'ScriptedTrigger77' || SC.SequenceScript.Name == 'ScriptedTrigger7'))
			Text = Text $ ", " $ SC.SequenceScript.Name $ " at " $ SC.ActionNum;
	}

	foreach AllActors(class'SquadMarker', M)
	{
		if(M.Tag == 'MarkerDemolition00')
			Text = Text $ ", " $ M $ " " $ M.GetStateName();
	}

	Log(Text);

	if(TestStep < 64)
	{
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return true;
	}

	return false;
}

/*
 * Test elite: the Elite Geonosian of GEO_03C's entrance (default) or any pawn tagged CoopTestTag. The host stands CoopTestAt or 900 east
 * of CoopTestLook (the place to look at), the clients next to him; the events of CoopTestTrigger (comma separated, default
 * EliteIntro,EliteIntroBegin) go one every 2 s from step 6. The pawn, its invulnerability and the barrel it has to blow (BoomTarget) are
 * logged every half second: the tester saw the Elite fly up to the ceiling and stay there, hard to kill (0.73, 2026-11-13).
 * Screenshots on "elite: shot". True while it runs.
 */
function bool TestElite(PlayerController Host)
{
	local Pawn P, Found;
	local Controller C;
	local Actor A, Barrel;
	local vector V, Look;
	local string TagText, Events;
	local int i;

	TagText = ParseOption(TestOptions, "CoopTestTag");

	if(TagText == "")
		TagText = "EliteLeadership";

	Look = vect(-436,-36479,826);

	if(ParseOption(TestOptions, "CoopTestLook") != "")
		Look = vector(ParseOption(TestOptions, "CoopTestLook"));

	foreach DynamicActors(class'Pawn', P)
	{
		if(string(P.Tag) ~= TagText && P.Health > 0)
			Found = P;
	}

	foreach AllActors(class'Actor', A, 'BoomTarget')
		Barrel = A;

	if(Host.Pawn == None)
		return false;

	if(TestStep == 0)
	{
		Host.bGodMode = true;
		V = Look + vect(900,0,0);

		if(ParseOption(TestOptions, "CoopTestAt") != "")
			V = vector(ParseOption(TestOptions, "CoopTestAt"));

		if(!Host.Pawn.SetLocation(V) && FindSpawnLocation(V, rotator(Look - V), V))
			Host.Pawn.SetLocation(V);

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				C.bGodMode = true;

				if(FindSpawnLocation(Host.Pawn.Location, Host.Rotation, V) && C.Pawn.SetLocation(V))
					C.ClientSetLocation(V, rotator(Look - V));
			}
		}

		Log("CoopTest: elite: host at " $ Host.Pawn.Location $ ", " $ int(VSize(Look - Host.Pawn.Location)) $ " from the place to look at");
	}

	if(Found != None)
		Look = Found.Location;

	Host.SetRotation(rotator(Look - (Host.Pawn.Location + Host.Pawn.EyePosition())));
	Host.Pawn.Acceleration = vect(0,0,0);

	Events = ParseOption(TestOptions, "CoopTestTrigger");

	if(Events == "")
		Events = "EliteIntro,EliteIntroBegin";

	// The k-th event of the list at step 6 + 4k
	if(TestStep >= 6 && (TestStep - 6) % 4 == 0)
	{
		for(i = 0; i < (TestStep - 6) / 4 && Events != ""; ++i)
		{
			if(InStr(Events, ",") == -1)
				Events = "";
			else
				Events = Mid(Events, InStr(Events, ",") + 1);
		}

		if(InStr(Events, ",") != -1)
			Events = Left(Events, InStr(Events, ","));

		if(Events != "")
		{
			// No string to name cast: a name property set by text
			SetPropertyText("TestEventName", Events);
			Log("CoopTest: elite: triggering " $ TestEventName);
			TriggerEvent(TestEventName, Host.Pawn, Host.Pawn);
		}
	}

	if(TestStep == 16 || TestStep == 30 || TestStep == 50)
		Log("CoopTest: elite: shot " $ TestStep);

	if(Found != None)
		Log("CoopTest: elite: " $ TestStep $ " " $ Found $ " Loc=" $ Found.Location $ " Physics=" $ Found.Physics $ " CollideWorld=" $ Found.bCollideWorld $ " Health=" $ Found.Health $ " Invulnerable=" $ Found.GetPropertyText("bInvulnerable") $ " God=" $ Found.Controller.bGodMode $ " Controller=" $ Found.Controller $ " State=" $ Found.Controller.GetStateName() $ " Enemy=" $ Found.Controller.Enemy $ " MoveTarget=" $ Found.Controller.MoveTarget $ " Destination=" $ Found.Controller.Destination $ " Focus=" $ Found.Controller.Focus $ " SeesHost=" $ Found.Controller.LineOfSightTo(Host.Pawn) $ " Weapon=" $ Found.Weapon $ " Ammo=" $ Found.Weapon.AmmoType $ " Barrel=" $ Barrel $ " " $ Barrel.GetPropertyText("Health") $ " Above=" $ int(Found.Location.Z - Host.Pawn.Location.Z) $ " Dilation=" $ Level.TimeDilation $ " AirSpeed=" $ Found.AirSpeed $ " Speed=" $ int(VSize(Found.Velocity)) $ " Anchor=" $ Found.Anchor);
	else
		Log("CoopTest: elite: " $ TestStep $ " no " $ TagText $ " yet, Barrel=" $ Barrel);

	// The route of the scripted flight, 10 times a second until step 40 (CoopTestFine=1)
	if(Found != None && ParseOption(TestOptions, "CoopTestFine") != "")
		Log("CoopTest: elite route: " $ TestStep $ " t=" $ Level.TimeSeconds $ " z=" $ int(Found.Location.Z) $ " Phys=" $ Found.Physics $ " MoveTarget=" $ Found.Controller.MoveTarget $ " Dest=" $ Found.Controller.Destination $ " Vel=" $ Found.Velocity $ " Accel=" $ Found.Acceleration $ " Anchor=" $ Found.Anchor $ " Script=" $ ScriptedController(Found.Controller).ActionNum $ " Base=" $ Found.Base);

	if(TestStep < 80)
	{
		TestTime = Level.TimeSeconds + 0.5;

		if(Found != None && ParseOption(TestOptions, "CoopTestFine") != "" && TestStep < 40)
			TestTime = Level.TimeSeconds + 0.1;

		++TestStep;
		return true;
	}

	return false;
}

// Test elite with CoopTestFine: the pawn every frame from 40 to 46 s, its animation and how far it moved
function TestEliteTick(float DeltaTime)
{
	local Pawn P;
	local name Seq;
	local float Frame;

	if(Level.TimeSeconds < 40 || Level.TimeSeconds > 46)
		return;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.Tag == 'EliteLeadership' && P.Health > 0)
		{
			P.GetAnimParams('', Seq, Frame);
			Log("CoopTest: elite frame t=" $ Level.TimeSeconds $ " dt=" $ DeltaTime $ " z=" $ int(P.Location.Z) $ " moved=" $ int(VSize(P.Location - TestEliteLast)) $ " anim=" $ Seq $ " " $ Frame $ " Phys=" $ P.Physics $ " Vel=" $ int(VSize(P.Velocity)) $ " CtrlAnim=" $ P.Controller.bControlAnimations $ " Weapon=" $ P.Weapon.GetStateName() $ " Target=" $ P.Controller.Target $ " Focus=" $ P.Controller.Focus $ " Rot=" $ P.Rotation);
			TestEliteLast = P.Location;
		}
	}
}

function int CountTagged(name ActorTag)
{
	local Actor A;
	local int n;

	foreach AllActors(class'Actor', A, ActorTag)
	{
		if(!A.bDeleteMe && !A.bHidden)
			++n;
	}

	return n;
}

function int ParseOptionInt(string Option, int Otherwise)
{
	if(ParseOption(TestOptions, Option) == "")
		return Otherwise;

	return int(ParseOption(TestOptions, Option));
}

function bool TestWalker(PlayerController Host)
{
	local Controller C;
	local Mover Mov;
	local Turret Tur;
	local Projectile Proj;
	local Actor A2;
	local vector V;
	local int i;

	// RAS_04C: the level's own script brings the walker up on BigLift (events AtRearOfHangar, MoveBigLift). Then the first client
	// stands on the cannon's place, turns to it and presses Use as the player does. The lift on the server and on the client every second.
	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			break;
	}

	Mov = FindMoverByTag('BigLift');

	if(TestTurret == None)
	{
		foreach AllActors(class'Turret', Tur)
		{
			if(Tur.IsA('ATTEWalkerCannon'))
				TestTurret = Tur;
		}
	}

	if(C == None || Mov == None || TestTurret == None || TestTurret.NavPts.Length == 0)
	{
		Log("CoopTest: walker: missing client " $ C $ " lift " $ Mov $ " cannon " $ TestTurret);
		return true;
	}

	if(TestStep == 0)
	{
		Host.bGodMode = true;
		C.bGodMode = true;
	}

	if(TestStep == 14)
		TriggerEvent('AtRearOfHangar', Host.Pawn, Host.Pawn);

	if(TestStep == 34)
		TriggerEvent('MoveBigLift', Host.Pawn, Host.Pawn);

	if(TestWalkerUp == 0 && TestStep > 34 && Mov.KeyNum == 4 && !Mov.bInterpolating)
	{
		TestWalkerUp = TestStep;
		Log("CoopTest: walker: the walker is up at step " $ TestStep);
	}

	if(TestWalkerUp > 0)
	{
		if(TestStep == TestWalkerUp + 2)
		{
			C.Pawn.SetLocation(TestTurret.NavPts[0].Location + vect(0,0,20));
			C.ClientSetLocation(C.Pawn.Location, rotator(TestTurret.Location - C.Pawn.Location));

			// The host watches from behind the client, on the lift (CoopTestWatchFrom=x,y,z offset from the cannon's place to stand),
			// on a free spot near there: the walker and the lift's railings are in the way of a fixed point
			V = TestTurret.NavPts[0].Location + vect(0,700,40);

			if(ParseOption(TestOptions, "CoopTestWatchFrom") != "")
				V = TestTurret.NavPts[0].Location + vector(ParseOption(TestOptions, "CoopTestWatchFrom"));

			if(!Host.Pawn.SetLocation(V) && FindSpawnLocation(V, rotator(TestTurret.Location - V), V))
				Host.Pawn.SetLocation(V);

			Log("CoopTest: walker: host at " $ Host.Pawn.Location $ ", " $ int(VSize(Host.Pawn.Location - TestTurret.Location)) $ " from the cannon");
		}

		// Looking at the cannon, the shots are taken by Shot.ps1 on "walker: shot <stage>"
		if(TestStep > TestWalkerUp + 2)
		{
			Host.SetRotation(rotator(TestTurret.Location + vect(0,0,150) - (Host.Pawn.Location + Host.Pawn.EyePosition())));
			Host.Pawn.Acceleration = vect(0,0,0);
		}

		if(TestStep == TestWalkerUp + 5)
			Log("CoopTest: walker: shot before");

		if(TestStep == TestWalkerUp + 8)
			Log("CoopTest: walker: shot mounted");

		if(TestStep == TestWalkerUp + 11)
			Log("CoopTest: walker: shot firing");

		if(TestStep == TestWalkerUp + 26)
			Log("CoopTest: walker: shot after");

		// The client's rotation comes back from its moves, it has to turn on its side
		if(TestStep > TestWalkerUp + 2 && TestStep < TestWalkerUp + 6)
			C.ClientSetRotation(rotator(TestTurret.Location - C.Pawn.Location));

		if(TestStep == TestWalkerUp + 6)
		{
			Log("CoopTest: walker: server " $ class'CoopPlayer'.static.TurretCollision(TestTurret));
			CoopPlayer(C).ClientCoopTestCommand("UseLooked");
		}

		// A droid where the client looks (as in test turret), then fire from the cannon as the player does (console command on the client)
		if(TestStep == TestWalkerUp + 8 && !bTestTargetSpawned)
		{
			bTestTargetSpawned = true;
			// On the line of the crosshair, as CoopTurretFire builds it
			V = TestTurret.Location + C.Pawn.EyePosition();
			V.Z += TestTurret.TurretHeight;
			V += vector(class'CoopPlayer'.static.TurretView(TestTurret, TestTurret.Yaw, TestTurret.Pitch)) * 900;
			TestTarget = Spawn(class<Pawn>(DynamicLoadObject("CTCharacters.BattleDroid", class'Class')),,, V);
			Log("CoopTest: walker: target " $ TestTarget $ " at " $ V);

			if(TestTarget != None)
				TestTarget.SetPhysics(PHYS_None);
		}

		if(TestStep == TestWalkerUp + 9)
			CoopPlayer(C).ClientCoopTestCommand("HoldFire");

		if(TestStep == TestWalkerUp + 10)
			Log("CoopTest: walker: firing");

		if(TestStep >= TestWalkerUp + 8 && TestStep <= TestWalkerUp + 16)
		{
			if(TestTarget != None)
				Log("CoopTest: walker: target health " $ TestStep $ " " $ TestTarget.Health);
			else if(bTestTargetSpawned)
				Log("CoopTest: walker: target gone " $ TestStep);
		}

		if(TestStep == TestWalkerUp + 14)
			CoopPlayer(C).ClientCoopTestCommand("ReleaseFire");

		if(TestStep >= TestWalkerUp + 9 && TestStep <= TestWalkerUp + 16)
		{
			i = 0;

			foreach DynamicActors(class'Projectile', Proj)
			{
				// ATTEWalkerProj flies 6000 units a second
				if(Proj.IsA('ATTEWalkerProj') && i < 3)
				{
					++i;
					Log("CoopTest: walker: projectile " $ Proj.Class.Name $ " at " $ Proj.Location $ " dist " $ int(VSize(Proj.Location - TestTurret.Location)) $ " Instigator=" $ Proj.Instigator);
				}
			}

			Log("CoopTest: walker: weapon " $ C.Pawn.Weapon.Class.Name $ " (" $ C.Pawn.Weapon.GetStateName() $ ") Ammo=" $ C.Pawn.Weapon.AmmoType.AmmoAmount $ " Yaw=" $ TestTurret.Yaw $ " Pitch=" $ TestTurret.Pitch);
		}

		// The level's end of the scene: the walker is disabled (the gunner is let go) and the lift goes down
		if(TestStep == TestWalkerUp + 18)
			TriggerEvent('LowerLift', Host.Pawn, Host.Pawn);
	}

	Log("CoopTest: walker: " $ TestStep $ " server lift Key=" $ Mov.KeyNum $ " Stop=" $ Mov.ScriptTriggeredKeyframe $ " Moving=" $ Mov.bInterpolating $ " Loc=" $ Mov.Location $ " client " $ C.GetStateName() $ " Loc=" $ C.Pawn.Location $ " Base=" $ C.Pawn.Base $ " cannon Gunner=" $ TestTurret.Gunner $ " State=" $ TestTurret.GetStateName() $ " Loc=" $ TestTurret.Location);
	CoopPlayer(C).ClientCoopTestCommand("MoverLog BigLift");

	if(TestStep % 5 == 0)
	{
		foreach DynamicActors(class'Actor', A2)
		{
			if(A2.Base == Mov || A2.Tag == 'Walker')
				Log("CoopTest: walker: " $ TestStep $ " server on it " $ A2 $ " (" $ A2.Class.Name $ ") Base=" $ A2.Base $ " Loc=" $ A2.Location $ " Rel=" $ A2.RelativeLocation $ " Physics=" $ A2.Physics $ " CollideWorld=" $ A2.bCollideWorld $ " Collide=" $ A2.bCollideActors $ " RemoteRole=" $ A2.RemoteRole $ " Static=" $ A2.bStatic);
		}
	}

	if(TestStep < 130 || (TestWalkerUp > 0 && TestStep < TestWalkerUp + 60))
	{
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return true;
	}

	return false;
}

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

/*
 * The commando of a client on a turret: Turret.ManTurret starts the gunner's pose, then the turret's weapon (WeaponAttachment,
 * Pawn.PlayBreathe) put ActionBreathe on it: it stood behind the turret as if running (session 2026-11-01). Single player never shows
 * the player's gunner. The pose is kept on the server, the other players get it with the pawn's animation.
 */
/*
 * Bots that walk without anything to look at keep Focus on their own pawn. In single player they still turn into the direction they
 * walk, in a network game the rotation stays as it was until they stop: they walked sideways and backwards (GEO_04D: 9 of 10 samples
 * within 30 degrees standalone, 0 of 14 as a listen server, same level and test `facing`). Which native code differs isn't known.
 * Bots looking at something (an enemy) strafe as they should, scripts decide their own turning.
 */
function TurnBotsToMove(float DeltaTime)
{
	local Controller C;
	local Pawn P;
	local rotator R;
	local int Delta;
	local float MaxTurn;

	if(Level.NetMode == NM_Standalone)
		return;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		P = C.Pawn;

		if(P == None || P != C.Focus || !C.IsA('CTBot') || P.Physics != PHYS_Walking || VSize(P.Velocity) < 60 || P.IsA('Turret'))
			continue;

		R = P.Rotation;
		Delta = (rotator(P.Velocity).Yaw - R.Yaw) & 65535;

		if(Delta > 32768)
			Delta -= 65536;

		MaxTurn = P.RotationRate.Yaw * DeltaTime;
		R.Yaw += FClamp(Delta, -MaxTurn, MaxTurn);
		P.SetRotation(R);
	}
}

function KeepGunnerPoses()
{
	local Controller C;
	local Turret T;
	local name Seq, Pose;
	local float Frame;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
		{
			CoopPlayer(C).TraceWeapons();
		}

		if(CoopPlayer(C) == None || IsHost(C) || C.Pawn == None || !C.IsInState('PlayerManningTurret'))
			continue;

		T = Turret(C.Machine);

		if(T == None || T.Gunner != C.Pawn)
			continue;

		Pose = 'TurretStandBreathe';

		if(T.SitToUse)
			Pose = 'TurretSitBreathe';

		C.Pawn.GetAnimParams('', Seq, Frame);

		if(Seq != Pose)
			C.Pawn.LoopAnim(Pose);
	}
}

/*
 * A client whose commando died or went down on a turret (GEO_04A, the gunship cannon, sessions 2026-11-01): the server kept the
 * controller in PlayerManningTurret and the turret kept the dead gunner, also after the respawn (the new commando was stuck in the
 * turret state). The turret is released like Turret.LeaveTurret does, without the dead pawn, and the controller leaves the state
 * (its EndState tells the client).
 */
function ReleaseTurretOfDeadGunner(CoopPlayer CP)
{
	local Turret T;
	local Pawn P;
	local Inventory Inv;

	if(!CP.IsInState('PlayerManningTurret'))
		return;

	T = Turret(CP.Machine);

	if(CP.Pawn != None && !CP.Pawn.bDeleteMe && CP.Pawn.Health > 0 && !CP.Pawn.bIncapacitated && T != None && T.Gunner == CP.Pawn)
		return;

	Log("CoopGame: the commando of " $ CP.PlayerReplicationInfo.PlayerName $ " on " $ T $ " is gone or down (" $ CP.Pawn $ "), releasing the turret");

	// The commando itself, like Turret.LeaveTurret: collision back (without it the body fell through the floor), at the turret's place
	// to stand, without the turret's first person weapon
	P = CP.Pawn;

	if(T != None && P != None && !P.bDeleteMe)
	{
		P.bCollideWorld = true;
		P.SetCollision(true, true, true);
		P.bPhysicsAnimUpdate = true;

		if(T.NavPts.Length > 0 && T.NavPts[0] != None)
			P.SetLocation(T.NavPts[0].Location);

		P.SetPhysics(PHYS_Falling);
		Inv = P.FindInventoryType(T.FPWeaponClass);

		if(Inv != None)
		{
			P.DeleteInventory(Inv);
			P.SwitchToLastWeapon();
		}

		if(P.Weapon != None && P.Weapon.ThirdPersonActor != None)
			P.Weapon.ThirdPersonActor.bHidden = false;
	}

	if(T != None && (T.Gunner == None || T.Gunner.bDeleteMe || T.Gunner.Health <= 0 || T.Gunner.bIncapacitated || T.Gunner != CP.Pawn))
	{
		T.StopFiring();
		T.Gunner = None;
		T.Controller = None;
		T.TeamIndex = 0;
		T.bIsAuto = false;
		T.bHidden = false;
		T.SetCollision(true, true, true);
		T.GotoState('Resetting');
		TriggerEvent(T.ReleaseEvent, T, None);
	}

	CP.GotoState('PlayerWalking');
	CP.Machine = None;
}

function RestartPlayer(Controller aPlayer)
{
	local CoopPlayer CP;

	// Nobody plays in the lobby, its menu is closed when a player gets a pawn
	if(Lobby != None)
		return;

	CP = CoopPlayer(aPlayer);

	if(CP == None || IsHost(CP))
	{
		Super.RestartPlayer(aPlayer);
		return;
	}

	ReleaseTurretOfDeadGunner(CP);

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

	// Standing on the car is enough: the host falls for a moment when the lift starts (the lift view went off right away)
	if(Host == None || Host.Pawn == None || Host.Pawn.Health <= 0 || (Host.Pawn.Physics != PHYS_Walking && Mover(Host.Pawn.Base) == None))
		return None;

	M = Mover(Host.Pawn.Base);

	// A client only counts on the lifts inside a level, see CoopEndLift.FindSharedLifts
	if(M != None && !IsHost(Host) && (EndLift == None || !EndLift.IsSharedLift(M)))
		return None;

	if(M == None)
		return None;

	// GEO_05A: the lift stops for a moment between its keyframes, that isn't the end of the ride
	if(M.bInterpolating)
	{
		LastRideLift = M;
		LastRideMoveTime = Level.TimeSeconds;
	}
	else if(!bEvenStopped && !(M == LastRideLift && Level.TimeSeconds - LastRideMoveTime < 2.5))
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

/*
 * Riding a lift together (CheckLiftRides): the players' commandos stand on the same spot, so they don't block each other and every
 * computer only draws its own player's commando. The server hides the clients' commandos (replicated), each client shows its own
 * again and hides the host's (CoopPlayer.ClientCoopHideRiders).
 */
function HideRiders(bool bHide)
{
	local Controller C;
	local Pawn P;

	if(bHide == bRidersHidden)
		return;

	bRidersHidden = bHide;
	Log("CoopGame: players on the lift hidden from each other: " $ bHide);

	if(!bHide)
		ShowHiddenParts(RideHiddenActors);

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) == None || C.Pawn == None)
			continue;

		P = C.Pawn;

		if(!IsHost(C) && bHide)
			HidePawnParts(P, RideHiddenActors);

		if(bHide)
			P.SetCollision(P.bCollideActors, false, false);
		else
			P.SetCollision(P.bCollideActors, P.default.bBlockActors, P.default.bBlockPlayers);

		if(!IsHost(C))
		{
			Log("CoopGame: hiding riders " $ bHide $ " for " $ C.PlayerReplicationInfo.PlayerName);
			CoopPlayer(C).bHideRidersSent = bHide;
			CoopPlayer(C).ClientCoopHideRiders(bHide);
		}
	}
}

// After a ride everybody walks off the shared spot as usual: invisible and without collision until the players stand apart (at most RIDE_GHOST_TIME)
function bool RidersApart()
{
	local Controller A, B;

	if(Level.TimeSeconds - RideEndTime > RIDE_GHOST_TIME)
		return true;

	for(A = Level.ControllerList; A != None; A = A.nextController)
	{
		if(CoopPlayer(A) == None || A.Pawn == None)
			continue;

		for(B = A.nextController; B != None; B = B.nextController)
		{
			if(CoopPlayer(B) != None && B.Pawn != None && VSize(A.Pawn.Location - B.Pawn.Location) < RIDE_APART_DISTANCE)
				return false;
		}
	}

	return true;
}

/*
 * GEO_05C starts on a lift with every member on its own spot, a client playing a member stands there: nothing to hide, nobody to move (user, session
 * 2026-11-02). A moment without a base (the lift starts) doesn't count as leaving. Not on the lifts everybody is brought to (CoopEndLift.IsSharedLift).
 */
function bool StaysOnCar(CoopPlayer CP, Mover M)
{
	if(EndLift != None && EndLift.IsSharedLift(M))
		return false;

	if(CP.Pawn.Base == M)
		CP.LastOnCarTime = Level.TimeSeconds;

	return CP.LastOnCarTime > 0 && Level.TimeSeconds - CP.LastOnCarTime < 2.5;
}

function FaceLiftCenter(CoopPlayer CP, vector Center)
{
	local rotator R;

	if(CP.Pawn == None || VSize(Center - CP.Pawn.Location) < 30)
		return;

	R = rotator(Center - CP.Pawn.Location);
	R.Pitch = 0;
	R.Roll = 0;
	CP.SetRotation(R);
	CP.ClientSetRotation(R);
}

// The commando and everything attached to it (third person weapon, headlamp, gear): parts of it were still seen on some frames.
// What gets hidden is remembered in List, only that is shown again (some attached actors are always hidden).
static function HidePawnParts(Pawn P, out array<Actor> List)
{
	local int i;

	HideForRide(P, List);

	if(P.Weapon != None)
		HideForRide(P.Weapon.ThirdPersonActor, List);

	for(i = 0; i < P.Attached.Length; i = i + 1)
		HideForRide(P.Attached[i], List);
}

static function HideForRide(Actor A, out array<Actor> List)
{
	if(A == None || A.bHidden)
		return;

	A.bHidden = true;
	List[List.Length] = A;
}

static function ShowHiddenParts(out array<Actor> List)
{
	local int i;

	for(i = 0; i < List.Length; i = i + 1)
	{
		if(List[i] != None && !List[i].bDeleteMe)
			List[i].bHidden = false;
	}

	List.Length = 0;
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

/*
 * A lift with players on it goes to its keyframe whatever is in the way. Movers return when they run into a pawn (ME_ReturnWhenEncroach,
 * the default): GEO_05A's start lift turned back just under the top in all three tries of the tester's game on 0.73 (2026-11-13), with
 * the players in it. In single player the briefing holds the player still for the ride; here a pawn could get in the car's way. Put back
 * when the ride is over.
 */
function PinRideLift(Mover M)
{
	if(M == PinnedLift)
		return;

	if(PinnedLift != None)
	{
		PinnedLift.MoverEncroachType = PinnedEncroach;
		Log("CoopGame: lift " $ PinnedLift $ " turns back on encroachment again (" $ PinnedLift.MoverEncroachType $ ")");
	}

	PinnedLift = M;

	if(M == None)
		return;

	PinnedEncroach = M.MoverEncroachType;
	M.MoverEncroachType = ME_IgnoreWhenEncroach;
	Log("CoopGame: lift " $ M $ " keeps going with the riders (encroachment was " $ PinnedEncroach $ ")");
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
	M = HostLift(RideLeader);

	// The host first, then the first client on a lift of the table: the one who rides takes the others along
	if(M == None)
	{
		M = HostLift(Host);

		if(M != None)
			RideLeader = Host;
	}

	for(C = Level.ControllerList; C != None && M == None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
		{
			M = HostLift(PlayerController(C));

			if(M != None)
			{
				RideLeader = PlayerController(C);
				Log("CoopGame: " $ RideLeader.PlayerReplicationInfo.PlayerName $ " rides " $ M $ " first, the others come along");
			}
		}
	}

	// Short gaps (the leader in the air for a moment, a stop at a keyframe) don't end the ride
	if(M != None)
		LastRideSeenTime = Level.TimeSeconds;
	else if(LastRideLift != None && RideLeader != None && Level.TimeSeconds - LastRideSeenTime < 2.5 && RideLeader.Pawn != None && VSize(RideLeader.Pawn.Location - LastRideLift.Location) < 2000)
		M = LastRideLift;

	bScene = M == None && InStartScene();
	PinRideLift(M);

	// The ride is over for everybody at the same moment: clients wait while the host is still held by the level's briefing (the car's
	// script lets him go at the top: GEO_05A Lift00Release). Clients walked off while the host couldn't move (the user, 2026-11-15)
	if(M != None || bScene)
		RideOverTime = 0;
	else if(RideOverTime == 0)
		RideOverTime = Level.TimeSeconds;

	if(M == None && bRidersHidden)
	{
		if(RideEndTime == 0)
		{
			RideEndTime = Level.TimeSeconds;
			Log("CoopGame: the ride is over: lift " $ LastRideLift $ " moving " $ LastRideLift.bInterpolating $ " " $ (Level.TimeSeconds - LastRideMoveTime) $ " s ago");
		}

		if(RidersApart())
		{
			Log("CoopGame: the riders stand apart after " $ (Level.TimeSeconds - RideEndTime) $ " s");
			HideRiders(false);
			RideEndTime = 0;
		}
	}
	else if(M != None)
		RideEndTime = 0;

	if(M == None)
		RideLeader = None;

	if(M != None)
		Center = LiftCenter(M);
	else if(bScene)
		Center = SceneCenter;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None)
			continue;

		// Lift: first person, turned to the middle of the car once (FaceLiftCenter); a start scene: everybody's camera over the
		// shoulder looks at the middle of the squad (also a client watching its member's scene there)
		if(M != None && CP.Pawn != None && !CP.bLiftFaced)
		{
			CP.bLiftFaced = true;
			FaceLiftCenter(CP, Center);
		}
		else if(M == None)
			CP.bLiftFaced = false;

		if(bScene && (CP.Pawn != None || CP.WatchedMember != None))
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

			// Not to his own place: the host off the car was "put back" where he stood, every second, while the car went down (GEO_05A)
			if(M != None && RideLeader != CP && CP.Pawn != None && CP.Pawn.Health > 0 && !CP.Pawn.bIncapacitated && CP.Machine == None && (CP.Pawn.Base != M || VSize(CP.Pawn.Location - RideLeader.Pawn.Location) > 60))
			{
				if(!bRidersHidden)
					HideRiders(true);

				Log("CoopGame: the host is put on the lift " $ M $ " at " $ RideLeader.PlayerReplicationInfo.PlayerName $ " (was on " $ CP.Pawn.Base $ " at " $ CP.Pawn.Location $ ")");
				CP.Pawn.SetCollision(CP.Pawn.bCollideActors, false, false);
				CP.Pawn.SetLocation(RideLeader.Pawn.Location);
				CP.Pawn.Velocity = RideLeader.Pawn.Velocity;
			}

			continue;
		}

		if((M == None && !bScene) || CP.Pawn == None || CP.Pawn.Health <= 0 || CP.Pawn.bIncapacitated || CP.Machine != None ||
		   !(CP.IsInState('PlayerWalking') || CP.IsInState('CoopLiftRide')))
		{
			// Held until the host can move too (see RideOverTime above), at most RIDE_RELEASE_WAIT
			if(CP.IsInState('CoopLiftRide') && M == None && !bScene && CP.Pawn != None && CP.Pawn.Health > 0 && !CP.Pawn.bIncapacitated &&
			   Host != None && Host.Pawn != None && Host.IsInState('Briefing') && Level.TimeSeconds - RideOverTime < RIDE_RELEASE_WAIT)
				continue;

			if(CP.IsInState('CoopLiftRide'))
			{
				Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " gets off the lift, " $ (Level.TimeSeconds - RideOverTime) $ " s after the ride");
				CP.GotoState('PlayerWalking');
				CP.ClientGotoState('PlayerWalking', '');
			}

			continue;
		}

		// The car is small: everybody stands where the first rider stands, the players don't block each other and each one only sees their
		// own commando (HideRiders); next to the host the clients were put into the walls of the shaft
		if(M != None && !StaysOnCar(CP, M) && (CP.Pawn.Base != M || VSize(CP.Pawn.Location - RideLeader.Pawn.Location) > 60))
		{
			if(!bRidersHidden)
				HideRiders(true);

			Spot = RideLeader.Pawn.Location;
			Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " is put on the lift " $ M $ " at " $ RideLeader.PlayerReplicationInfo.PlayerName $ " (was on " $ CP.Pawn.Base $ " at " $ CP.Pawn.Location $ ")");
			CP.Pawn.SetCollision(CP.Pawn.bCollideActors, false, false);
			CP.Pawn.SetLocation(Spot);
			CP.Pawn.Velocity = RideLeader.Pawn.Velocity;
			CP.ClientSetLocation(Spot, CP.Rotation);
		}

		// A client that came later (spawned in the car): hidden and told like the others
		if(bRidersHidden && !CP.bHideRidersSent)
		{
			CP.bHideRidersSent = true;
			Log("CoopGame: hiding riders for " $ CP.PlayerReplicationInfo.PlayerName $ " (came later)");
			HidePawnParts(CP.Pawn, RideHiddenActors);

			CP.Pawn.SetCollision(CP.Pawn.bCollideActors, false, false);
			CP.ClientCoopHideRiders(true);
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

// RAS_01A: the host floats to the ship by an animation for 20 seconds, next to him there is only open space (a client fell 1800 units)
function bool IsSpaceWalkRunning()
{
	return IsMap("RAS_01A") && !WasHeard('DropshipAnimProp');
}

function bool SpawnClient(CoopPlayer CP)
{
	local PlayerController Host;
	local vector SpawnSpot;
	local NavigationPoint StartSpot;
	local rotator SpawnRotation;
	local Pawn P;
	local bool bFlyer;

	Host = GetHost();

	// A client that plays a squad member starts as it (e.g. the next level)
	P = FindAssignedMember(CP);

	// A member picked in the lobby that joins in a scene later in this level (GEO_01B: Fixer is in the squad until his script starts): the
	// client plays its own commando until then, and the camera flies from it to the member (CheckSceneWatch)
	if(P != None && ((JoinsLater(P) && !SevIntro.IsSev(P)) || IsCaptiveAtStart(P)))
	{
		Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " starts with a temporary commando, " $ P $ " joins later");
		P = None;
	}

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

	if(P != None && ((JoinsLater(P) && !SevIntro.IsSev(P)) || IsCaptiveAtStart(P)))
		P = None;

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

		if(SpaceWalk.IsRunning())
			P = SpaceWalk.SpawnFlyer(Host, CP);

		bFlyer = P != None;

		// Wait until the host stands on the ground, but not forever. On a lift the client comes along at once (CheckLiftRides).
		// A flyer doesn't wait: it is what the wait for the space walk is a fallback for.
		if(P == None && (!IsHostFree(Host) || IsSpaceWalkRunning()) && HostLift(Host, true) == None && Level.TimeSeconds - CP.SpawnWaitStart < MaxSpawnWait)
		{
			Log("CoopGame: Waiting for the host to be free before spawning a client: Physics=" $ Host.Pawn.Physics $ " Base=" $ Host.Pawn.Base $ " Health=" $ Host.Pawn.Health);
			return false;
		}
		if(P == None && HostLift(Host, true) != None && FindLiftSpot(Host.Pawn, HostLift(Host, true), SpawnSpot))
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
	CP.ClientCoopWeaponsQuiet(true, None);
	P.AddDefaultInventory();
	GiveHostWeapons(P);
	EquipQuietly(CP, P);

	if(bFlyer)
		SpaceWalk.StartFlight(CP, P);

	// The white armor of the host for every client (see CoopCommando)
	if(CoopCommando(P).CoopSkin == 0)
		CoopCommando(P).SetCoopSkin(1);

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

	if(bLoadedFromSave && GetHost() != None)
	{
		bLoadedFromSave = false;
		AfterSaveLoaded(GetHost());
	}

	// Clients of a loaded save back at their saved place (CoopCheckpointReturn.RememberLeftPawn)
	if(CheckpointReturn != None && CheckpointReturn.HasWaiting())
	{
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				CheckpointReturn.RestoreRejoined(PlayerController(C));
		}
	}

	// Test: CoopTestRes=1280x720 changes the host's window size (HUD layout at other resolutions)
	if(!bTestResSet && ParseOption(TestOptions, "CoopTestRes") != "" && GetHost() != None)
	{
		bTestResSet = true;
		GetHost().ConsoleCommand("SETRES " $ TestResText(ParseOption(TestOptions, "CoopTestRes")));
	}
	DetachClientMembers();
	EnsureClientGrenades();
	CheckAIBreach();
	CheckStuckBreachMarkers();
	CheckAISnipe();
	CheckStalledScripts();
	CheckIntroWatch();
	CheckIntroPositions();
	SyncTriggerLights();
	ResendCollisionTags();
	UnblockKarmaProps();
	CheckClientsBlocked();
	LogClientsStatus();
	ListenForMissableEvents();
	CheckMissedEvents();
	CheckMissionFailed();

	CheckClientArrivals();
	if(Lobby != None)
		Lobby.Refresh();
	if(EndLift != None)
		EndLift.Check();
	if(DoorHold != None)
		DoorHold.Check(1.0);
	CheckStaleBeams();
	CheckServerStuckFire();
	HideWatchingPawns();
	KeepGunnerPoses();
	CheckLiftRides();
	SyncSquadHealth();
	SyncObjectives();
	SyncObjectiveTracker();
	CheckClientSnipers();
	CheckAISnipeOrders();

	if(!bCheckedLevel)
		CheckLevel();

	CheckSquadDown();

	if(HostDownTime != 0)
		CheckHostDown();

	CheckTestCauses();
	CheckTestSnipeOrder();

	if(TestAction != "")
		TickTest();

	SyncIncapacitated();
	CheckSceneWatch();
	CheckSquadTakeover();

	if(CaptiveTakeover != None)
		CaptiveTakeover.Check();

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
			else if(!CP.Pawn.IsInState('Reviving') && Level.TimeSeconds - CP.IncapacitatedTime >= ClientBleedOutTime && (CaptiveTakeover == None || !CaptiveTakeover.IsCaptive(CP.Pawn)) &&
			        (!IsBeingRevived(CP.Pawn) || Level.TimeSeconds - CP.IncapacitatedTime >= ClientBleedOutTime + REVIVE_GRACE))
			{
				CP.IncapacitatedTime = 0;
				BleedOutClient(CP);
			}
		}
		else
		{
			CP.IncapacitatedTime = 0;
			CP.DeadTime = 0;
			CheckCatchUp(CP);
		}

		ReleaseTurretOfDeadGunner(CP);

		SendMapActorDisplay(CP);
		SendLastMusic(CP);
		SendLastTriggers(CP);

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

// Capture motion after host simulation, before the native replication pass.
function CaptureCompletedFrame()
{
    local Controller MotionController;
    local CoopPlayer MotionPlayer;
    if(Level.NetMode!=NM_ListenServer || Lobby!=None || bWaitingForClients) return;
    for(MotionController=Level.ControllerList;MotionController!=None;MotionController=MotionController.nextController)
    {
        MotionPlayer=CoopPlayer(MotionController);
        if(MotionPlayer!=None)
        {
            MotionPlayer.EnsureCoopConnectionRate();
            if(MotionPlayer.SnapshotSender!=None) MotionPlayer.SnapshotSender.Update(Level.TimeSeconds);
        }
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
	if(!class'CoopNative'.static.HasCompletedFrameCapture()) CaptureCompletedFrame();
	TurnBotsToMove(DeltaTime);

	if(TestAction ~= "elite" && ParseOption(TestOptions, "CoopTestFine") != "")
		TestEliteTick(DeltaTime);
	Super.Tick(DeltaTime);

	if(!bRemovedUplink && UplinkChecks < 300)
	{
		++UplinkChecks;
		RemoveUplink();
	}

	if(bSlowStart)
		CheckSlowStart();

	CheckScriptAnims();
	SpaceWalk.Check(DeltaTime);
	TickClientPawns();

	if(HostBleedOutRequests > 0 && GetHost() != None && GetHost().Pawn != None)
		MuteHostSquadSounds(CTSquadNative(GetHost().Pawn.Squad));

	if(Level.TimeSeconds >= NextIdleStateSync)
	{
		NextIdleStateSync = Level.TimeSeconds + 0.2;
		SyncIdleStates(Level.TimeSeconds >= NextIdleStateResend);
		SyncPanelStates(Level.TimeSeconds >= NextIdleStateResend);
		SyncMarkerVisibility(Level.TimeSeconds >= NextIdleStateResend);
		SyncMapActorCollision();
		CheckDetonations();
		SyncPropEffects();
		CheckGather();

		if(Sight != None)
			Sight.Check();

		if(Level.TimeSeconds >= NextIdleStateResend)
			NextIdleStateResend = Level.TimeSeconds + 3.0;
	}
}

/*
 * A client's moves carry its own level time, and the server drops every move not later than the last one it took
 * (PlayerController.ServerMove, CurrentTimeStamp). After a save or checkpoint was loaded the client's controller on the server had the
 * last move time of the save (34.77 in the test), the client's clock started again at 0: every move was dropped until the client's
 * time passed it. The server's copy stood where the load put it, falling, while the client walked on its own screen (the user's game
 * 2026-11-14, RAS_01C: 100 s and more). A new connection starts the clock again.
 */
function ResetMoveClock(PlayerController PC, string Reason)
{
	if(PC == None || IsHost(PC))
		return;

	if(PC.CurrentTimeStamp > 0)
		Log("CoopGame: move clock of " $ PC.PlayerReplicationInfo.PlayerName $ " was " $ PC.CurrentTimeStamp $ ", reset (" $ Reason $ ")");

	PC.CurrentTimeStamp = 0;
	PC.ServerTimeStamp = 0;
	PC.ResetTimeMargin();
}

// The map of a travel URL: "RAS_02C.ctm?game=...#PlayerStart" is RAS_02C, for the client's loading screen
function string TravelMapName(string URL)
{
	if(InStr(URL, "?") != -1)
		URL = Left(URL, InStr(URL, "?"));

	if(InStr(URL, "#") != -1)
		URL = Left(URL, InStr(URL, "#"));

	if(Right(URL, 4) ~= ".ctm")
		URL = Left(URL, Len(URL) - 4);

	return URL;
}

/*
 * Somebody is reviving this pawn: a player (the native flag, CTPlayer.UsingItem) or a squad member working on its revive marker. The
 * flag alone counted only players: Sev revived a client's Fixer, the client bled out in the middle of it (the user's game 2026-11-12,
 * RAS_02D: "use active marker ... members=Commando07Delta0", then "Bleed out").
 */
function bool IsBeingRevived(Pawn P)
{
	local SquadMarker M;
	local Pawn Other;

	if(P == None)
		return false;

	if(P.bBeingRevivedByPlayer)
		return true;

	if(CloneCommando(P) == None || CloneCommando(P).ReviveMarker == None)
		return false;

	M = CloneCommando(P).ReviveMarker;

	if(M.bMarkerActive && M.TotalParticipants > 0)
		return true;

	foreach DynamicActors(class'Pawn', Other)
	{
		if(Other != P && Other.SquadMarker == M && Other.Health > 0 && !Other.bIncapacitated)
			return true;
	}

	return false;
}

/*
 * A client nobody revived in time gets up again as the same squad member, next to the host, with full health (the user's choice,
 * 2026-11-12). Before, the member died and the client got a new commando: the dead body stayed and the squad had two of him (two Fixers),
 * and the client's camera flew off as the body fell. Without a free spot or a host: the old way.
 */
function BleedOutClient(CoopPlayer CP)
{
	local PlayerController Host;
	local Pawn P;
	local vector Spot;
	local rotator Dir;

	P = CP.Pawn;
	Host = GetHost();

	if(Host == None || Host.Pawn == None || Host.Pawn.Health <= 0 || Host.Pawn.bIncapacitated || !FindSpawnLocation(Host.Pawn.Location, Host.Pawn.Rotation, Spot))
	{
		Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " bleeds out, no place next to the host");
		P.BleedOut();
		return;
	}

	// As CoopCheckpointReturn.RestorePlayer: GotoState skips the get-up animation, whose end would set half health later
	P.Revive();
	P.GotoState('');
	P.Health = P.MaxHealth;

	if(!P.SetLocation(Spot))
	{
		Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " got up where he lay, the spot " $ Spot $ " was refused");
		Spot = P.Location;
	}

	Dir = rotator(Host.Pawn.Location - Spot);
	Dir.Pitch = 0;
	Dir.Roll = 0;
	P.Velocity = vect(0,0,0);
	P.Acceleration = vect(0,0,0);
	P.SetPhysics(PHYS_Falling);
	P.SetRotation(Dir);
	CP.SetRotation(Dir);
	CP.ClientSetLocation(P.Location, Dir);
	P.ChangeAnimation();
	CP.ClientCoopMessage("Nobody revived you in time: back with the squad");
	Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " not revived in time, gets up as " $ P.Class.Name $ " next to the host at " $ P.Location $ " health " $ P.Health);
}

/*
 * Every frame, for the clients' pawns on the server:
 * - the hands are parked as soon as the client has changed away from them (CoopPlayer.ParkServerHands);
 * - a client down or dead stops. It sends no moves in CtrlIncapacitated, and the server kept moving its pawn with the last
 *   acceleration: the client went down at -2114,158 moving (0.42,-0.91), the host saw him 850 uu further that way (the user's game
 *   2026-11-12, RAS_02D). The client itself lay still and was moved there once revived.
 */
function TickClientPawns()
{
	local Controller C;
	local Pawn P;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) == None || IsHost(C) || C.Pawn == None)
			continue;

		CoopPlayer(C).ParkServerHands();
		P = C.Pawn;

		if((P.bIncapacitated || P.Health <= 0) && (P.Acceleration != vect(0,0,0) || (P.Physics == PHYS_Walking && P.Velocity != vect(0,0,0))))
		{
			P.Acceleration = vect(0,0,0);

			if(P.Physics == PHYS_Walking)
				P.Velocity = vect(0,0,0);
		}
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

/*
 * Server, owner of the state: which squad marker icons each client sees (RAS_01C: all consoles showed as sliceable on clients).
 * The server's bHidden is no use for this, it follows what the host looks at, and the marker's state isn't replicated. The rule is computed
 * here per marker and per client and goes out on a change, with a full resend for clients that didn't have the actor yet.
 * bHidden also reaches the clients by plain replication, so a change of the server's value counts as a change: it would overwrite the client's.
 * Using a panel by hand doesn't depend on this (the panel path, CoopExtension.ActivateItemHasRequiredInventory).
 * The rule (the user, 2026-11-12): every client sees every marker that can be used now, as the host does, whatever member it plays.
 * Before, a client saw only its own member's specialty and the others only up close, as the use prompt.
 */
function SyncMarkerVisibility(bool bResendAll)
{
	local SquadMarker M;
	local Controller C;
	local CoopPlayer CP;
	local bool bHasClient, bAvailable, bShown;
	local int i;
	local byte Flags;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
		{
			bHasClient = true;
			break;
		}
	}

	if(!bHasClient)
		return;

	foreach AllActors(class'SquadMarker', M)
	{
		bAvailable = MarkerIsAvailable(M);

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			CP = CoopPlayer(C);

			if(CP == None || IsHost(C))
				continue;

			bShown = bAvailable;
			Flags = 0;

			if(bShown)
				Flags = Flags | 1;

			if(M.bHidden)
				Flags = Flags | 2;

			for(i = 0; i < CP.SentMarkers.Length; ++i)
			{
				if(CP.SentMarkers[i] == M)
					break;
			}

			if(i == CP.SentMarkers.Length)
			{
				CP.SentMarkers.Length = i + 1;
				CP.SentMarkers[i] = M;
				CP.SentMarkerFlags[i] = 255; // Always send the first time
			}

			if(CP.SentMarkerFlags[i] == Flags && !bResendAll)
				continue;

			if(CP.SentMarkerFlags[i] == 255 || (CP.SentMarkerFlags[i] & 1) != (Flags & 1))
				Log("CoopGame: marker shown M=" $ M $ " client=" $ CP.PlayerReplicationInfo.PlayerName $ " shown=" $ bShown);

			CP.SentMarkerFlags[i] = Flags;
			CP.ClientCoopSetMarkerShown(M, bShown, M.Anchor);
		}
	}
}

// bDisabledByAlternate is read by name: fields of Engine's native classes are not always accepted by the compiler (see CoopSight)
function bool MarkerIsAvailable(SquadMarker M)
{
	if(!M.IsInState('Enabled') || M.GetPropertyText("bDisabledByAlternate") ~= "True")
		return false;

	return ActivateItem(M.Anchor) == None || ActivateItem(M.Anchor).bIsUsable;
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

/*
 * A door breach marker can stay active after the door blew (state Executed, complete, the slot of the client's member empty, not in every run), with
 * the AI members still on it. The game then refuses every other order (MU_Occupied): Sev couldn't be sent to the sniper position on GEO_01C and
 * the mission failed (logs of a tester and of the user 2026-11-02). Why only sometimes isn't known. A marker like that is cancelled after
 * STUCK_MARKER_TIME, a normal one is over by then. Only door breaches: a sniper or a turret marker stays active on purpose.
 */
function CheckStuckBreachMarkers()
{
	local SquadMarker M, Found;

	foreach AllActors(class'SquadMarker', M)
	{
		if(M != BreachMarker && M.IsA('MarkerDoorBreach') && M.bMarkerActive && M.bComplete && M.IsInState('Executed'))
		{
			Found = M;
			break;
		}
	}

	if(Found != StuckMarker)
	{
		StuckMarker = Found;
		StuckMarkerTime = Level.TimeSeconds;
		return;
	}

	if(StuckMarker != None && Level.TimeSeconds - StuckMarkerTime >= STUCK_MARKER_TIME)
	{
		Log("CoopGame: door breach " $ StuckMarker $ " is over but keeps the squad, cancelling it: " $ StuckMarker.CancelMarker(None) $ ", active now " $ StuckMarker.bMarkerActive);

		// The cancel makes it Enabled again: the host could order the breach of the blown door once more
		if(GatherMarker == StuckMarker)
			GatherMarker = None;

		StuckMarker.GotoState('Disabled');
		StuckMarker = None;
	}
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

/*
 * The AI controller of a squad member a player takes (takeover, end of a breach or of the AI's snipe) is destroyed. The squad marker
 * it took part in (the door breach) kept the bot as a participant: when the marker finished later (MemberKilled -> FinishMarker ->
 * RemoveParticipant -> CTBot::ReserveNode) it used the destroyed bot, a garbage pointer: host crash in NavigationPoint.ReleaseNode,
 * Engine.dll+0x16D8D0, after the breach on GEO_01C and GEO_03D (sessions 2026-10-31). The member leaves the marker like a member that
 * is killed, the bot releases its node and clears its goal queues, all while it still has the pawn.
 */
function RetireAI(Controller AI, Pawn P)
{
	local CTBot Bot;

	if(AI == None || AI.bDeleteMe)
		return;

	Bot = CTBot(AI);

	if(P != None && P.SquadMarker != None)
	{
		Log("CoopGame: " $ P $ " leaves the marker " $ P.SquadMarker $ " before it goes to a player");
		P.SquadMarker.MemberKilled(P, None, None);
		P.SquadMarker = None;
	}

	if(Bot != None)
	{
		if(Bot.ReservedNode != None)
		{
			Log("CoopGame: " $ Bot $ " releases its path node " $ Bot.ReservedNode $ " before " $ P $ " goes to a player");
			Bot.ReservedNode.ReleaseNode(P);
			Bot.ReservedNode = None;
		}

		if(Bot.ReflexGoals != None)
			Bot.ReflexGoals.Clear();

		if(Bot.GestureGoals != None)
			Bot.GestureGoals.Clear();

		if(Bot.SquadGoals != None)
			Bot.SquadGoals.Clear();

		if(Bot.ScriptedGoals != None)
			Bot.ScriptedGoals.Clear();

		if(Bot.MainGoals != None)
			Bot.MainGoals.Clear();
	}

	AI.UnPossess();
	AI.Destroy();
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
		RetireAI(AI, P);

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

		// The server's bHidden of a marker depends on what the host looks at: see SyncMarkerVisibility
		if(SquadMarker(A) != None)
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
		if(CoopPlayer(C) != None && !IsHost(C) && IsUp(C.Pawn))
			return true;
	}

	return false;
}

/*
 * Up, or getting up: Pawn.Revive starts the state Reviving, which plays the get-up animation and clears bIncapacitated only at its end.
 * Counted as down, a player revived a moment before the last one fell made the squad "down" and the checkpoint loaded (the user's game
 * 2026-11-14, RAS_02C, twice).
 */
function bool IsUp(Pawn P)
{
	return P != None && !P.bDeleteMe && P.Health > 0 && (!P.bIncapacitated || P.IsInState('Reviving'));
}

// Called from CoopFixes when a pawn is about to bleed out
function bool ShouldDelayHostBleedOut(Pawn P)
{
	local PlayerController Host;
	local bool bDelay;

	Host = GetHost();

	if(bAllowHostBleedOut || HostReviveWaitTime <= 0 || Host == None || P != Host.Pawn || !P.bIncapacitated)
		return false;

	// The whole squad is down: CheckHostDown takes everybody back to the checkpoint on the next Timer, without one the level restarts as before
	if(!HasLivingClient())
	{
		if(!CheckpointReturn.HasPoint())
			return false;

		CountHostBleedOutRequest(P);

		return true;
	}

	if(HostDownTime == 0)
	{
		HostDownTime = Level.TimeSeconds;
		Log("CoopGame: Host is down, waiting for a client to revive him");
		Broadcast(self, "The host is down! Revive him: look at him and hold USE.");
	}

	CountHostBleedOutRequest(P);
	bDelay = Level.TimeSeconds - HostDownTime < HostReviveWaitTime;

	// This request is the real bleed-out: it goes on with its sounds, CheckHostDown may come after it
	if(!bDelay)
		RestoreHostSquadSounds();

	return bDelay;
}

/*
 * Doubled "commander is down" voice (RAS_01A, RAS_01C). Hypothesis, not proven: the native squad keeps asking for BleedOut while the request is
 * swallowed for up to HostReviveWaitTime, and plays SquadIncapSound again each time. The marker shows the requests with what the squad plays then.
 * The first request keeps its sound, the later ones find none. The scenario hostdown calls BleedOut itself once, it counts as a request here.
 */
function CountHostBleedOutRequest(Pawn P)
{
	local CTSquadNative HostSquad;

	++HostBleedOutRequests;
	HostSquad = CTSquadNative(P.Squad);

	if(HostBleedOutRequests <= HOST_BLEEDOUT_LOG_LINES)
	{
		if(HostSquad != None)
			Log("CoopGame: host bleed-out request " $ HostBleedOutRequests $ " t=" $ (Level.TimeSeconds - HostDownTime) $ " IncapSound=" $ HostSquad.SquadIncapSound $ " CurrentSound=" $ HostSquad.GetPropertyText("CurrentSound") $ " SoundID=" $ HostSquad.GetPropertyText("CurrentSoundID") $ " VoiceLines=" $ Left(HostSquad.GetPropertyText("VoiceLines"), 200));
		else
			Log("CoopGame: host bleed-out request " $ HostBleedOutRequests $ " t=" $ (Level.TimeSeconds - HostDownTime) $ " without a squad");
	}

	if(HostBleedOutRequests >= 2)
		MuteHostSquadSounds(HostSquad);
}

// Called from Tick too: native may play the sound before or after asking for BleedOut, so the first pass keeps its one play and the next frame has none
function MuteHostSquadSounds(CTSquadNative HostSquad)
{
	if(bHostSquadSoundsSaved || HostSquad == None)
		return;

	bHostSquadSoundsSaved = true;
	SavedSoundSquad = HostSquad;
	SavedSquadIncapSound = HostSquad.SquadIncapSound;
	SavedSquadDeathSound = HostSquad.SquadDeathSound;
	HostSquad.SquadIncapSound = None;
	HostSquad.SquadDeathSound = None;
}

function RestoreHostSquadSounds()
{
	HostBleedOutRequests = 0;

	if(!bHostSquadSoundsSaved)
		return;

	bHostSquadSoundsSaved = false;

	if(SavedSoundSquad != None)
	{
		SavedSoundSquad.SquadIncapSound = SavedSquadIncapSound;
		SavedSoundSquad.SquadDeathSound = SavedSquadDeathSound;
	}

	SavedSoundSquad = None;
}

/*
 * Observation only: the user also saw bolts freeze after a dash or an attack charge of a living droid, where the ammo's Tick should hide the beam.
 * Logs a remote beam that is still drawn while its ammo hasn't fired for a while or is gone. See CoopExtension.RemoveRemoteBeam.
 */
function CheckStaleBeams()
{
	local LaserWeaponAmmo Ammo;
	local Emitter E;
	local Actor BeamOwner;
	local int i;

	foreach DynamicActors(class'LaserWeaponAmmo', Ammo)
	{
		E = Ammo.RemoteTracerEmitter;

		if(E == None || E.bDeleteMe)
			continue;

		for(i = 0; i < BeamWatches.Length; ++i)
		{
			if(BeamWatches[i].E == E)
				break;
		}

		if(i == BeamWatches.Length)
		{
			BeamWatches.Length = i + 1;
			BeamWatches[i].E = E;
			BeamWatches[i].Ammo = Ammo;
			BeamWatches[i].LastFired = Level.TimeSeconds;
		}

		if(Ammo.bNeedTracer || Ammo.bClientNeedTracer)
			BeamWatches[i].LastFired = Level.TimeSeconds;
	}

	for(i = BeamWatches.Length - 1; i >= 0; --i)
	{
		E = BeamWatches[i].E;

		if(E == None || E.bDeleteMe)
		{
			BeamWatches.Remove(i, 1);
			continue;
		}

		if(E.bHidden || Level.TimeSeconds - BeamWatches[i].LastFired <= BEAM_STALE_TIME || Level.TimeSeconds < BeamWatches[i].NextLog || BeamLogLines >= BEAM_LOG_LINES)
			continue;

		BeamWatches[i].NextLog = Level.TimeSeconds + BEAM_LOG_INTERVAL;
		++BeamLogLines;
		BeamOwner = None;

		if(BeamWatches[i].Ammo != None)
			BeamOwner = BeamWatches[i].Ammo.Owner;

		Log("CoopGame: beam still shown E=" $ E $ " owner=" $ BeamOwner $ " base=" $ E.Base $ " hidden=" $ E.bHidden $ " age=" $ (Level.TimeSeconds - BeamWatches[i].LastFired));
	}
}

// Host and every client down, nobody left to revive anybody: back to the checkpoint. Without one the game goes on as before (the level restarts)
function CheckSquadDown()
{
	local PlayerController Host;
	local bool bHostDead;

	Host = GetHost();

	if(Host == None || !CheckpointReturn.HasPoint() || Level.NextURL != "")
		return;

	// With nobody left to revive him the host dies at once instead of going down, and the game then waits in the pause menu
	bHostDead = Host.Pawn == None || Host.Pawn.bDeleteMe || (Host.Pawn.Health <= 0 && !Host.Pawn.bIncapacitated);

	if(!bHostDead && (IsUp(Host.Pawn) || HasLivingClient()))
		return;

	Log("CoopGame: checkpoint: the squad is down, host dead " $ bHostDead);
	HostDownTime = 0;
	RestoreHostSquadSounds();

	if(LoadSavedCheckpoint())
		return;

	if(bHostDead)
	{
		CheckpointReturn.MoveClientsBack(Host);
		bRespawningHost = true;
		RestartPlayer(Host);
		bRespawningHost = false;
	}

	if(CheckpointReturn.Load())
	{
		Host.SetPause(false);
		Host.MenuClose();
	}
	else
		CoopRestartLevel();
}

function CheckHostDown()
{
	local PlayerController Host;

	Host = GetHost();

	if(Host == None || Host.Pawn == None || !Host.Pawn.bIncapacitated || IsUp(Host.Pawn))
	{
		HostDownTime = 0; // Revived, also while getting up
		RestoreHostSquadSounds();
		return;
	}

	if(!HasLivingClient() || Level.TimeSeconds - HostDownTime >= HostReviveWaitTime)
	{
		Log("CoopGame: Nobody revived the host");
		HostDownTime = 0;
		RestoreHostSquadSounds();

		if(LoadSavedCheckpoint() || CheckpointReturn.Load())
			return;

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
	local Turret Tur;
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

	// Turrets with a squad marker or places to stand (GEO_03C, the sonic turret): their links (see CoopPlayer.ClientCoopSetMarkerLink)
	foreach AllActors(class'Turret', Tur)
	{
		// All turrets that are turned: clients drop the rotation of a turret (see CoopPlayer.RotateMapActor)
		if((Tur.SquadMarker == None && (!Tur.bPlayerUsable || Tur.NavPts.Length == 0) && Tur.Rotation == rot(0,0,0)) || Tur.RemoteRole == ROLE_None || Tur.bStatic)
			continue;

		if(!Tur.bAlwaysRelevant)
		{
			Tur.bAlwaysRelevant = true;
			++Num;
		}

		SyncedMapActors[SyncedMapActors.Length] = Tur;
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
	return Turret(A) != None || A.Tag != A.Class.Name || A.AmbientGlow != A.default.AmbientGlow || A.bUnlit != A.default.bUnlit || A.StaticMeshInstance != None || A.bHidden != A.default.bHidden;
}

/*
 * Called every second: sends the display, look and panel links of SyncedMapActors to the client, 40 actors a second (10 showed the GEO_01C window late), starting 0.5 s
 * after it has a pawn. Reliable with the actor's index: a client that doesn't have the actor yet asks for it again
 * (ServerCoopMapActorMissing, up to 10 times). The unreliable passes of 0.61 were lost while the level started (the window of
 * GEO_01C, the bunker of GEO_01A and the base of the GEO_03A shield stayed wrong on the clients, session 2026-10-31).
 */
function SendMapActorDisplay(CoopPlayer CP)
{
	local int n, i;

	if(CP.Pawn == None || SyncedMapActors.Length == 0)
		return;

	if(CP.DisplaySyncStart == 0)
	{
		CP.DisplaySyncStart = Level.TimeSeconds + 0.5;
		SendMoverStops('', CP);
		return;
	}

	if(Level.TimeSeconds < CP.DisplaySyncStart)
		return;

	for(n = 0; n < MAP_ACTORS_PER_SECOND && CP.DisplaySyncIndex < SyncedMapActors.Length; ++n)
		SendMapActorTo(CP, CP.DisplaySyncIndex++);

	while(n < MAP_ACTORS_PER_SECOND && CP.DisplayResend.Length > 0)
	{
		i = CP.DisplayResend[0];
		CP.DisplayResend.Remove(0, 1);
		SendMapActorTo(CP, i);
		++n;
	}
}

function QueueMapActorResend(CoopPlayer CP, int Index)
{
	local int i;

	if(Index < 0 || Index >= SyncedMapActors.Length)
		return;

	if(CP.DisplayResendCount.Length < SyncedMapActors.Length)
		CP.DisplayResendCount.Length = SyncedMapActors.Length;

	if(CP.DisplayResendCount[Index] >= 10)
		return;

	CP.DisplayResendCount[Index] = CP.DisplayResendCount[Index] + 1;

	if(CP.DisplayResendCount[Index] == 10)
		Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " still doesn't have " $ SyncedMapActors[Index] $ ", giving up its display");

	for(i = 0; i < CP.DisplayResend.Length; ++i)
	{
		if(CP.DisplayResend[i] == Index)
			return;
	}

	CP.DisplayResend[CP.DisplayResend.Length] = Index;
}

function SendMapActorTo(CoopPlayer CP, int Index)
{
	local Actor A;
	local Material Skin0, Skin1;
	local ActivateItem Item;
	local NavigationPoint N0, N1;

	A = SyncedMapActors[Index];

	if(A == None || A.bDeleteMe)
		return;

	Skin0 = None;
	Skin1 = None;

	if(A.Skins.Length > 0)
		Skin0 = A.Skins[0];

	if(A.Skins.Length > 1)
		Skin1 = A.Skins[1];

	if(A.DrawScale3D != A.default.DrawScale3D || A.PrePivot != A.default.PrePivot || A.Skins.Length > 0)
		CP.ClientCoopSetActorDisplay(Index, A, A.DrawScale3D.X, A.DrawScale3D.Y, A.DrawScale3D.Z, A.PrePivot, Skin0, Skin1);

	if(NeedsLookSync(A))
		CP.ClientCoopSetActorLook(Index, A, A.Tag, A.AmbientGlow, A.bUnlit, A.bHidden, string(A.StaticMeshInstance), A.Location.X, A.Location.Y, A.Location.Z, A.Rotation.Pitch, A.Rotation.Yaw, A.Rotation.Roll);

	if(Turret(A) != None)
	{
		N0 = None;
		N1 = None;

		if(A.NavPts.Length > 0)
			N0 = A.NavPts[0];

		if(A.NavPts.Length > 1)
			N1 = A.NavPts[1];

		CP.ClientCoopSetMarkerLink(Index, A, A.SquadMarker, N0, N1);
	}

	Item = ActivateItem(A);

	if(Item != None)
	{
		N0 = None;
		N1 = None;

		if(Item.NavPts.Length > 0)
			N0 = Item.NavPts[0];

		if(Item.NavPts.Length > 1)
			N1 = Item.NavPts[1];

		CP.ClientCoopSetPanelLinks(Index, Item, Item.SquadMarker, N0, N1, Item.bIsUsableByPlayer);
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
	Log("CoopGame: level package " $ class'CoopNative'.static.LevelPackageText(self));
	MakeMapActorsRelevant();
	class'CoopTriggerForward'.static.Setup(self);
	if(EndLift == None)
		EndLift = new class'CoopEndLift';

	GetHost().GetCurrentMapName(EndLiftMap);
	EndLift.Setup(self, EndLiftMap);
	DoorHold = new class'CoopDoorHold';
	DoorHold.Setup(self);
	CaptiveTakeover = new class'CoopCaptiveTakeover';
	CaptiveTakeover.Setup(self);
	Sight = new class'CoopSight';
	Sight.Setup(self);
	ListenToLevelRules();
	ListenToSnipeMarkers();
	Host.GetCurrentMapName(Map);

	if(SkipBriefing(Map) != Map)
		CoopTravel(Map);
}

// Moves a client that got separated from the host (usually by a level script that only moves the host) next to the host
function CheckCatchUp(CoopPlayer CP)
{
	local PlayerController Host;

	if(CatchUpDistance <= 0 || ParseOption(TestOptions, "CoopTestNoCatchUp") != "")
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

// Research: what a loaded save holds and whether it still serves the network
function LogLoadedGame()
{
	local Controller C;
	local Pawn P;

	Log("CoopTest: engineload: loaded, NetMode " $ Level.NetMode $ " map " $ Level.Title $ " helpers " $ EndLift $ " " $ CheckpointReturn $ " " $ DoorHold);

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) != None)
			Log("CoopTest: engineload: player " $ C $ " (" $ C.Class.Name $ ") name " $ C.PlayerReplicationInfo.PlayerName $ " connection " $ PlayerController(C).Player $ " pawn " $ C.Pawn $ " state " $ C.GetStateName());
	}

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.IsA('CloneCommando'))
			Log("CoopTest: engineload: commando " $ P $ " (" $ P.Class.Name $ ") controller " $ P.Controller $ " health " $ P.Health $ " at " $ P.Location);
	}
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

/*
 * The keyframe where a mover moved by ACTION_MoverToKeyframe stops (Mover.ScriptTriggeredKeyframe) is set on the server only. A client's
 * copy chains on to the next keyframe (Mover.KeyFrameReached) and the server never corrects it: RAS_04C BigLift stopped at key 4 with the
 * walker on the server and went on to key 5, 512 units lower, on the client, which stood under the walker and couldn't reach its cannon
 * (the user's game 2026-11-14). Sent for the movers with MoverTag after the action (CoopExtension.MoverToKeyframeInitActionFor), and for
 * every mover a script has moved to a client that comes in (MoverTag None, see SendMapActorDisplay).
 */
function SendMoverStops(name MoverTag, optional CoopPlayer Only)
{
	local Mover M;
	local Controller C;

	foreach AllActors(class'Mover', M)
	{
		if((MoverTag != '' && M.Tag != MoverTag) || (MoverTag == '' && M.ScriptTriggeredKeyframe == M.default.ScriptTriggeredKeyframe))
			continue;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && (Only == None || C == Only))
				CoopPlayer(C).ClientCoopMoverStop(M, M.ScriptTriggeredKeyframe);
		}

		if(MoverTag != '')
			Log("CoopGame: " $ M $ " (" $ M.Tag $ ") stops at key " $ M.ScriptTriggeredKeyframe $ ", now at " $ M.KeyNum $ ", sent to the clients");
	}
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

// Test: a window size for SETRES, "1280x720" windowed, "1920x1080f" full screen
function string TestResText(string Res)
{
	if(Right(Res, 1) ~= "f" || Right(Res, 1) ~= "w")
		return Res;

	return Res $ "w";
}

// Test: the living enemies, for checking a loaded save on the host and the clients (see CoopPlayer.ClientCoopTestCommand "PawnLog")
function string TestEnemyText()
{
	local Pawn P;
	local int Count;
	local string Text;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.Health > 0 && !P.IsA('CloneCommando'))
		{
			++Count;
			Text = Text $ " " $ P.Class.Name $ "@" $ int(P.Location.X) $ "," $ int(P.Location.Y);
		}
	}

	return Count $ " living enemies:" $ Text;
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
	local CoopPauseMenu TestPauseMenu;
	local Checkpoint TestCheckpoint;
	local string TestLoadURL;
	local Pawn TestTrapPawn;
	local Inventory TestInv;
	local string TestText;
	local Trigger HoldGate;
	local NavigationPoint HoldNav, ClientNav, NavIt;
	local ScriptedSequence SS;
	local Counter Cnt;
	local Pickup Pick;
	local PathNode FacingNode;
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
		else if(TestStep == 0 && ParseOption(TestOptions, "CoopTestSaveFirst") != "")
		{
			// CoopTestSaveFirst=1: a checkpoint save of this level first (the level time has to be over 20 s, CoopCheckpointReturn.Remember).
			// Its places must not be used on the next level (CoopCheckpointReturn.Setup)
			Host.AutoSave();
			TestTime = Level.TimeSeconds + 3;
			++TestStep;
			return;
		}
		else if(TestStep == 0 || (TestStep == 1 && ParseOption(TestOptions, "CoopTestSaveFirst") != ""))
		{
			Host.GetNextLevel(Host.GetLevelIndex(NextMap), NextMap);
			CoopTravel(NextMap);
		}
	}
	else if(TestAction ~= "enginesave" && TestStep == 0)
	{
		// Research (DEVLOG "Required before 0.8"): does the engine write a save on a listen server
		Log("CoopTest: enginesave: NetMode " $ Level.NetMode $ ", " $ class'CoopNative'.static.EngineSaveGame("CoopTest"));
	}
	else if(TestAction ~= "engineload")
	{
		// Research: save, then load that save by a server travel. The loaded game has this test in its state again: the default var stops the loop
		if(class'CoopConfig'.default.bTestSaveLoaded)
		{
			if(TestStep == 0)
			{
				LogLoadedGame();
				TestTime = Level.TimeSeconds + 8;
				++TestStep;
				return;
			}

			LogLoadedGame();
		}
		else if(TestStep == 0)
		{
			Log("CoopTest: engineload: saving: " $ class'CoopNative'.static.EngineSaveGame("CoopTest"));
			TestTime = Level.TimeSeconds + 4;
			++TestStep;
			return;
		}
		else
		{
			class'CoopConfig'.default.bTestSaveLoaded = true;

			// A '?' can't be in a test option: CoopTestLoadListen=1 adds ?listen
			TestLoadURL = "?load=CoopTest";

			if(ParseOption(TestOptions, "CoopTestLoadListen") != "")
				TestLoadURL = TestLoadURL $ "?listen";

			Log("CoopTest: engineload: loading by " $ TestLoadURL);
			Level.ServerTravel(TestLoadURL, false);
		}
	}
	else if(TestAction ~= "captive")
	{
		// See CoopCaptiveTakeover. RAS_02D: InACell puts Scorch down in the cell (no string to name cast), then the host walks up to him
		if(TestStep == 0)
		{
			TriggerEvent('InACell', Host, Host.Pawn);
			Log("CoopTest: captive: sent InACell");
			TestTime = Level.TimeSeconds + 4;
			++TestStep;
			return;
		}

		if(TestStep == 1)
		{
			foreach DynamicActors(class'Pawn', TestTrapPawn)
			{
				if(TestTrapPawn.IsA('CloneCommando') && TestTrapPawn.bIncapacitated && PlayerController(TestTrapPawn.Controller) == None)
					break;
			}

			if(TestTrapPawn != None && FindSpawnLocation(TestTrapPawn.Location, Host.Pawn.Rotation, V))
				Log("CoopTest: captive: " $ TestTrapPawn $ " down at " $ TestTrapPawn.Location $ ", host moved " $ Host.Pawn.SetLocation(V) $ " to " $ Host.Pawn.Location);
			else
				Log("CoopTest: captive: nobody down, " $ TestTrapPawn);

			Host.bGodMode = true;
			TestTime = Level.TimeSeconds + 55;
			++TestStep;
			return;
		}

		foreach DynamicActors(class'Pawn', TestTrapPawn)
		{
			if(TestTrapPawn.IsA('CloneCommando') && PlayerController(TestTrapPawn.Controller) != None && !IsHost(TestTrapPawn.Controller))
				Log("CoopTest: captive: after 55 s " $ TestTrapPawn $ " of " $ TestTrapPawn.Controller.PlayerReplicationInfo.PlayerName $ " incap " $ TestTrapPawn.bIncapacitated $ " health " $ TestTrapPawn.Health);
		}
	}
	else if(TestAction ~= "checkpointreturn")
	{
		// A real Checkpoint actor, then everybody is hurt and moved. CoopTestSquadDown=1: everybody goes down instead of the host pressing the button
		if(TestStep == 0)
		{
			foreach AllActors(class'Checkpoint', TestCheckpoint)
			{
				if(TestCheckpoint.Tag != 'CheckpointStart')
					break;
			}

			// Values a fresh commando doesn't have, to tell a restored state from a new one: 150 health, 77 rounds
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(PlayerController(C) == None || C.Pawn == None || class'CoopConfig'.default.bTestSaveLoaded)
					continue;

				C.Pawn.Health = 150;

				for(TestInv = C.Pawn.Inventory; TestInv != None; TestInv = TestInv.Inventory)
				{
					if(Ammunition(TestInv) != None && TestInv.IsA('DC17mBlasterAmmo'))
						Ammunition(TestInv).AmmoAmount = 77;
				}
			}

			TestCheckpoint.Trigger(Host, Host.Pawn);
			Log("CoopTest: checkpointreturn: triggered " $ TestCheckpoint);
			TestTime = Level.TimeSeconds + 3;
			++TestStep;
			return;
		}

		if(TestStep == 1)
		{
			// A loaded checkpoint save has this test at this step again: only the result is logged then
			if(class'CoopConfig'.default.bTestSaveLoaded)
			{
				Log("CoopTest: checkpointreturn: back from the save, " $ TestEnemyText());
				++class'CoopConfig'.default.TestLoads;

				// CoopTestReload=1: this level was loaded from the save and saved again at step 0, now loaded by the menu's button
				if(ParseOption(TestOptions, "CoopTestReload") != "" && class'CoopConfig'.default.TestLoads < 2)
				{
					foreach DynamicActors(class'Pawn', P)
					{
						if(P.Health > 0 && !P.IsA('CloneCommando') && P.Controller != None && PlayerController(P.Controller) == None)
							P.TakeDamage(10000, Host.Pawn, P.Location, vect(0,0,0), class'CTDamageBallistic');
					}

					Log("CoopTest: checkpointreturn: killed again, " $ TestEnemyText() $ ", loading by the button");
					CoopLoadCheckpoint();
					TestTime = Level.TimeSeconds + 60;
					return;
				}

				TestStep = 3;
				TestTime = Level.TimeSeconds + 20;
				return;
			}

			class'CoopConfig'.default.bTestSaveLoaded = true;

			// The world has to come back too: every enemy is killed after the checkpoint, the save brings them back
			Log("CoopTest: checkpointreturn: before killing, " $ TestEnemyText());

			foreach DynamicActors(class'Pawn', P)
			{
				if(P.Health > 0 && !P.IsA('CloneCommando') && P.Controller != None && PlayerController(P.Controller) == None)
					P.TakeDamage(10000, Host.Pawn, P.Location, vect(0,0,0), class'CTDamageBallistic');
			}

			Log("CoopTest: checkpointreturn: after killing, " $ TestEnemyText());

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(PlayerController(C) == None || C.Pawn == None)
					continue;

				V = C.Pawn.Location;
				Log("CoopTest: checkpointreturn: " $ C.PlayerReplicationInfo.PlayerName $ " stood at " $ V $ ", moved: " $ (C.Pawn.SetLocation(V + vect(300,0,0)) || C.Pawn.SetLocation(V - vect(300,0,0)) || C.Pawn.SetLocation(V + vect(0,300,0)) || C.Pawn.SetLocation(V - vect(0,300,0)) || C.Pawn.SetLocation(V + vect(150,0,0)) || C.Pawn.SetLocation(V - vect(150,0,0)) || C.Pawn.SetLocation(V - vect(0,150,0))) $ " to " $ C.Pawn.Location);

				if(!IsHost(C))
					PlayerController(C).ClientSetLocation(C.Pawn.Location, C.Rotation);

				// Spent ammunition has to come back as it was, not refilled
				for(TestInv = C.Pawn.Inventory; TestInv != None; TestInv = TestInv.Inventory)
				{
					if(Ammunition(TestInv) != None)
						Ammunition(TestInv).AmmoAmount = 3;
				}

				if(ParseOption(TestOptions, "CoopTestSquadDown") != "")
					C.Pawn.TakeDamage(1000, None, C.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
				else
					C.Pawn.Health = 40;
			}

			TestTime = Level.TimeSeconds + 5;
			++TestStep;
			return;
		}

		if(TestStep == 2)
		{
			if(ParseOption(TestOptions, "CoopTestSquadDown") == "")
				CoopLoadCheckpoint();
			else
				Log("CoopTest: checkpointreturn: host pawn " $ Host.Pawn $ " incap " $ (Host.Pawn != None && Host.Pawn.bIncapacitated) $ " state " $ Host.GetStateName());

			TestTime = Level.TimeSeconds + 4;
			++TestStep;
			return;
		}

		if(TestStep == 3)
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(PlayerController(C) == None || C.Pawn == None)
					continue;

				TestText = "";

				for(TestInv = C.Pawn.Inventory; TestInv != None; TestInv = TestInv.Inventory)
				{
					if(Ammunition(TestInv) != None)
						TestText = TestText $ " " $ TestInv.Class.Name $ "=" $ Ammunition(TestInv).AmmoAmount;
				}

				if(!IsHost(C) && CoopPlayer(C) != None)
					CoopPlayer(C).ClientCoopTestCommand("PawnLog");

				Log("CoopTest: checkpointreturn: after: " $ C.PlayerReplicationInfo.PlayerName $ " at " $ C.Pawn.Location $ " health " $ C.Pawn.Health $ " shields " $ C.Pawn.Shields $ " incap " $ C.Pawn.bIncapacitated $ " state " $ C.GetStateName() $ " ammo" $ TestText);
			}

			// CoopTestTravelAfter=1: the next level from the loaded one (the user's game: it never came, 2026-11-11)
			if(ParseOption(TestOptions, "CoopTestTravelAfter") != "" && class'CoopConfig'.default.TestLoads > 0)
			{
				class'CoopConfig'.default.TestLoads = -100;
				Host.GetCurrentMapName(NextMap);
				Host.GetNextLevel(Host.GetLevelIndex(NextMap), NextMap);
				Log("CoopTest: checkpointreturn: travelling from the loaded level to " $ NextMap);
				CoopTravel(NextMap);
			}
		}
	}
	else if(TestAction ~= "loadcheckpoint")
	{
		// The real menu of the host. Its button is pressed by calling what the "yes" of the question calls
		if(TestStep == 0)
		{
			Host.ShowMenu();
			Log("CoopTest: loadcheckpoint: opened the pause menu");
			TestTime = Level.TimeSeconds + 5;
			++TestStep;
			return;
		}

		if(TestStep == 1)
		{
			foreach AllActors(class'CoopPauseMenu', TestPauseMenu)
				break;

			Log("CoopTest: loadcheckpoint: menu " $ TestPauseMenu);

			if(TestPauseMenu != None)
				TestPauseMenu.ConfirmLoadCheckpoint();

			++TestStep;
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

			// CoopTestClients: how many clients play squad members (3 when not given)
			if(i < Max(1, int(ParseOption(TestOptions, "CoopTestClients"))) || (ParseOption(TestOptions, "CoopTestClients") == "" && i < 3) || TestMarker == None)
			{
				TestTime = Level.TimeSeconds + 2;
				return;
			}

			R = TestMarker.Anchor.Rotation;
			R.Pitch = 0;
			Host.Pawn.SetLocation(TestMarker.Anchor.Location + vector(R) * 150 + vect(0,0,-40));

			// The AI members too, so that the breach can be done
			i = 0;

			foreach DynamicActors(class'Pawn', P2)
			{
				if(P2 != Host.Pawn && P2.Squad != None && P2.Squad == Host.Pawn.Squad && PlayerController(P2.Controller) == None)
				{
					R.Yaw += 9000;
					P2.SetLocation(TestMarker.Anchor.Location + vector(R) * 250 + vect(0,0,-40));
					++i;
				}
			}

			Log("CoopTest: breach: moved " $ i $ " AI members to the door, order handled=" $ OrderDoorBreach(Host, TestMarker, false));
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
		// The host can't die meanwhile: the squad down loaded the checkpoint in the middle of the test (run 2026-11-14)
		Host.bGodMode = true;

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

		// CoopTestUseFirst=<name of a panel>: the client uses that panel first, like the first charge of GEO_04A
		if(ParseOption(TestOptions, "CoopTestUseFirst") != "" && TestUseStep < 24)
		{
			if(TestUseStep == 0)
			{
				foreach DynamicActors(class'ActivateItem', A)
				{
					if(string(A.Name) ~= ParseOption(TestOptions, "CoopTestUseFirst"))
						TestPanel = A;
				}

				if(TestPanel.IsInState('Disabled'))
				{
					TestPanel.bIsUsableByPlayer = true;
					TestPanel.GotoState('Unplaced');
				}

				R = TestPanel.Rotation;
				R.Pitch = 0;
				C.Pawn.SetLocation(TestPanel.Location + vector(R) * 80 + vect(0,0,-40));
				Host.Pawn.SetLocation(TestPanel.Location + vector(R) * 300 + vect(0,0,-40));
				C.ClientSetLocation(C.Pawn.Location, rotator(TestPanel.Location - C.Pawn.Location));
				C.bGodMode = true;
			}

			if(TestUseStep == 2)
				CoopPlayer(C).ClientCoopTestCommand("UsePanel " $ TestPanel.Tag);

			if(TestUseStep == 22)
				CoopPlayer(C).ClientCoopTestCommand("StopPanel");

			++TestUseStep;
			TestTime = Level.TimeSeconds + 1;
			return;
		}

		// CoopTestTurretFirst: the client mans the nearest player turret and leaves it before it places the charge
		if(ParseOption(TestOptions, "CoopTestTurretFirst") != "" && TestSubStep < 8)
		{
			if(TestSubStep == 0)
			{
				foreach DynamicActors(class'Turret', Tur)
				{
					if(Tur.bPlayerUsable && Tur.Health > 0 && !Tur.IsA('AutoTurret') && Tur.NavPts.Length > 0 && (TestTurret == None || VSize(Tur.Location - C.Pawn.Location) < VSize(TestTurret.Location - C.Pawn.Location)))
						TestTurret = Tur;
				}

				C.Pawn.SetLocation(TestTurret.NavPts[0].Location);
				C.ClientSetLocation(C.Pawn.Location, C.Pawn.Rotation);
				Host.Pawn.SetLocation(TestTurret.NavPts[0].Location + vect(100,0,60)); // The client would be moved to the host
			}

			if(TestSubStep == 2 || TestSubStep == 6)
				CoopPlayer(C).ServerCoopUseTurret(TestTurret);

			if(TestSubStep == 3)
				CoopPlayer(C).ClientCoopTestCommand("HoldFire");

			if(TestSubStep == 5)
				CoopPlayer(C).ClientCoopTestCommand("ReleaseFire");

			++TestSubStep;
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
			if(ParseOption(TestOptions, "CoopTestTurretFirst") != "")
				Host.Pawn.SetLocation(TestPanel.Location + vector(R) * 300 + vect(0,0,-40)); // The client would be moved to the host

			R = rotator(TestPanel.Location - C.Pawn.Location);
			R.Pitch = -3000;
			C.ClientSetLocation(C.Pawn.Location, R);
			C.ClientSetRotation(R);
			C.bGodMode = true;
			Log("CoopTest: charge: " $ C.PlayerReplicationInfo.PlayerName $ " at " $ TestPanel $ " State=" $ TestPanel.GetStateName());
		}

		Log("CoopTest: charge: " $ TestStep $ " PC=" $ C.GetStateName() $ " Phys=" $ C.Pawn.Physics $ " Loc=" $ C.Pawn.Location $ " Vel=" $ int(VSize(C.Pawn.Velocity)) $ " Acc=" $ int(VSize(C.Pawn.Acceleration)) $ " Incap=" $ C.Pawn.bIncapacitated $ " Weapon=" $ C.Pawn.Weapon $ " WState=" $ C.Pawn.Weapon.GetStateName() $ " Base=" $ C.Pawn.Base $ " Panel=" $ TestPanel.GetStateName() $ " Activating=" $ TestPanel.bActivating $ " Target=" $ C.Target $ " Walking=" $ C.Pawn.bIsWalking $ " Speed=" $ C.Pawn.GroundSpeed);

		// CoopTestUse: holds Use on the panel without keys in the window
		if(ParseOption(TestOptions, "CoopTestUse") != "")
		{
			if(TestStep == 4)
				CoopPlayer(C).ClientCoopTestCommand("UsePanel " $ ParseOption(TestOptions, "CoopTestPanelTag"));

			if(TestStep == 30)
				CoopPlayer(C).ClientCoopTestCommand("StopPanel");

			if(TestStep == 40)
				CoopPlayer(C).ClientCoopTestCommand("Detonate");
		}

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
	else if(TestAction ~= "doorhold" && TestStep == 0)
	{
		// See CoopDoorHold: the host goes to the gate trigger of RAS_01B, the first client to CoopTestAt, on either side of the door
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None || GetHost() == None || GetHost().Pawn == None)
		{
			TestTime = Level.TimeSeconds + 1;
			return;
		}

		foreach AllActors(class'Trigger', HoldGate)
		{
			if(HoldGate.Event == 'Killemall')
				break;
		}

		// SetLocation refuses arbitrary spots past this door (cause not found): nav points are known to be free. CoopTestPast also puts the client there
		foreach AllActors(class'NavigationPoint', NavIt)
		{
			if(NavIt.Location.Y < 6900 && (HoldNav == None || VSize(NavIt.Location - HoldGate.Location) < VSize(HoldNav.Location - HoldGate.Location)))
				HoldNav = NavIt;
		}

		C.bGodMode = true;
		GetHost().bGodMode = true;

		if(ParseOption(TestOptions, "CoopTestPast") != "")
		{
			foreach AllActors(class'NavigationPoint', NavIt)
			{
				if(NavIt != HoldNav && NavIt.Location.Y < 6900 && (ClientNav == None || VSize(NavIt.Location - HoldNav.Location) < VSize(ClientNav.Location - HoldNav.Location)))
					ClientNav = NavIt;
			}

			Log("CoopTest: doorhold: client moved past the door: " $ C.Pawn.SetLocation(ClientNav.Location) $ " at " $ C.Pawn.Location);
		}
		else
		{
			Log("CoopTest: doorhold: client moved to the near side: " $ C.Pawn.SetLocation(vector(ParseOption(TestOptions, "CoopTestAt"))) $ " at " $ C.Pawn.Location);
			TriggerEvent('comintagetcha', GetHost(), GetHost().Pawn); // The ambush a player's walk sets off, the trap needs its enemies
		}

		C.ClientSetLocation(C.Pawn.Location, C.Rotation);
		Log("CoopTest: doorhold: host moved: " $ GetHost().Pawn.SetLocation(HoldNav.Location) $ " at " $ GetHost().Pawn.Location $ ", held: " $ DoorHold.IsHeld(HoldGate, GetHost().Pawn));
		TestTime = Level.TimeSeconds + 15;
		++TestStep;

		if(ParseOption(TestOptions, "CoopTestKillTrap") != "")
			return; // Keeps the scenario for its next step
	}
	else if(TestAction ~= "doorhold" && TestStep == 1 && ParseOption(TestOptions, "CoopTestKillTrap") != "")
	{
		// The squad wins the fight in the trap: the door has to work again
		foreach DynamicActors(class'Pawn', TestTrapPawn)
		{
			if(TestTrapPawn.Health > 0 && TestTrapPawn.IsA('TrandoshanSlaverBerserker'))
			{
				Log("CoopTest: doorhold: killing " $ TestTrapPawn $ " at " $ TestTrapPawn.Location);
				TestTrapPawn.TakeDamage(100000, None, TestTrapPawn.Location, vect(0,0,0), class'CTDamageBallistic');
			}
		}

		++TestStep;
	}
	else if(TestAction ~= "goto" && TestStep <= int(ParseOption(TestOptions, "CoopTestGotoStep")))
	{
		// CoopTestGotoLog: after the move logs the scripts of the level every 2 seconds, up to 40 times
		if(ParseOption(TestOptions, "CoopTestGotoLog") != "" && TestStep > int(ParseOption(TestOptions, "CoopTestGotoStep")))
		{
			foreach AllActors(class'ScriptedController', SC)
			{
				if(SC.SequenceScript != None && SC.Pawn == None && SC.ActionNum < SC.SequenceScript.Actions.Length && InStr(Caps(string(SC.SequenceScript.Tag)), Caps(ParseOption(TestOptions, "CoopTestGotoLog"))) != -1)
					Log("CoopTest: goto: " $ TestStep $ " script " $ SC.SequenceScript $ " (" $ SC.SequenceScript.Tag $ ") at " $ SC.ActionNum $ " " $ SC.SequenceScript.Actions[SC.ActionNum].GetActionString());
			}

			if(TestStep < 40)
			{
				TestTime = Level.TimeSeconds + 2;
				++TestStep;
				return;
			}
		}

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

		if(ParseOption(TestOptions, "CoopTestGotoLog") != "")
		{
			TestTime = Level.TimeSeconds + 2;
			++TestStep;
			return;
		}
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
				if(Tur.bPlayerUsable && Tur.Health > 0 && !Tur.IsA('AutoTurret') && Tur.NavPts.Length > 0 && (ParseOption(TestOptions, "CoopTestTurret") == "" || string(Tur.Class.Name) ~= ParseOption(TestOptions, "CoopTestTurret")) && (ParseOption(TestOptions, "CoopTestTurretMarker") == "" || Tur.SquadMarker != None) && (TestTurret == None || VSize(Tur.Location - C.Pawn.Location) < VSize(TestTurret.Location - C.Pawn.Location)))
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

			if(TestStep == 3 || (TestStep == 14 && ParseOption(TestOptions, "CoopTestTurretDie") == ""))
				CoopPlayer(C).ServerCoopUseTurret(TestTurret);

			// CoopTestTurretTarget: the host watches from the turret's place to stand, a droid stands where the crosshair is
			if(ParseOption(TestOptions, "CoopTestTurretTarget") != "")
			{
				if(TestStep == 5)
				{
					Host.Pawn.SetLocation(TestTurret.NavPts[0].Location + Normal(TestTurret.NavPts[0].Location - TestTurret.Location) * 250 + vect(0,0,60));
					Host.ClientSetRotation(rotator(TestTurret.Location - Host.Pawn.Location));
				}

				// Where the client looks after it turned, as it told the server, from where it looks
				if(TestStep == 8 && !bTestTargetSpawned)
				{
					bTestTargetSpawned = true;
					V = TestTurret.Location + C.Pawn.EyePosition() + vector(C.Rotation) * 700;
					V.Z += TestTurret.TurretHeight;
					TestTarget = Spawn(class<Pawn>(DynamicLoadObject("CTCharacters.BattleDroid", class'Class')),,, V);
					Log("CoopTest: turret: target " $ TestTarget $ " at " $ V $ " Team=" $ TestTarget.TeamIndex $ " gunner team=" $ C.Pawn.TeamIndex);

					if(TestTarget != None)
						TestTarget.SetPhysics(PHYS_None);
				}

				Log("CoopTest: turret: gunner anim " $ TestStep $ " " $ TestAnimString(C.Pawn) $ " idle state " $ C.Pawn.CurrentIdleState $ " Physics=" $ C.Pawn.Physics $ " PhysAnim=" $ C.Pawn.bPhysicsAnimUpdate $ " Control=" $ C.bControlAnimations $ " HasStand=" $ C.Pawn.HasAnim('TurretStandBreathe'));

				if(TestTarget != None)
					Log("CoopTest: turret: target health " $ TestStep $ " " $ TestTarget.Health);
				else if(TestStep > 7)
					Log("CoopTest: turret: target gone " $ TestStep);
			}

			// CoopTestTurretDie: the client's commando dies on the turret
			if(TestStep == 8 && ParseOption(TestOptions, "CoopTestTurretDie") != "")
			{
				C.bGodMode = false;
				Log("CoopTest: turret: killing " $ C.Pawn $ " on the turret");
				C.Pawn.TakeDamage(100000, None, C.Pawn.Location, vect(0,0,0), class'DamageType');
			}

			// The turrets on the server and on the client, before manning and after leaving
			if(TestStep == 2 || TestStep == 17)
			{
				foreach DynamicActors(class'Turret', Tur)
					Log("CoopTest: turretinfo: server " $ TestStep $ " " $ class'CoopPlayer'.static.TurretInfo(Tur));

				CoopPlayer(C).ClientCoopDumpProps(TestStep);
			}

			// Fire like the player (console command on the client) and turn as the client would send it
			if(TestStep == 6)
				CoopPlayer(C).ClientCoopTestCommand("HoldFire");

			if(TestStep == 7)
				CoopPlayer(C).ClientCoopTestCommand("TurretAim");

			if(TestStep >= 4 && TestStep <= 12)
			{
				Log("CoopTest: aim: server " $ TestStep $ " Yaw=" $ TestTurret.Yaw $ " Pitch=" $ TestTurret.Pitch $ " view=" $ C.Rotation $ " " $ class'CoopPlayer'.static.TurretBones(TestTurret));
				CoopPlayer(C).ClientCoopTestCommand("TurretLog");
			}

			if(TestStep == 12)
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

		// CoopTestArriveHost: only the host goes to the first point, the clients stay where they are
		if(TestStep == 34 && ParseOption(TestOptions, "CoopTestArriveHost") != "")
		{
			for(i = 0; i < ArrivalPawns.Length; i = i + 1)
			{
				if(ArrivalPoints[i] != None && WasHeard(ArrivalArmEvents[i]))
				{
					Host.bGodMode = true;
					Host.Pawn.SetLocation(ArrivalPoints[i].Location + vect(0,0,40));
					Log("CoopTest: arrive: moved the host to " $ ArrivalPoints[i]);
					break;
				}
			}
		}
		else if(TestStep >= 34 && TestStep % 4 == 2 && ParseOption(TestOptions, "CoopTestArriveHost") == "")
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
	else if(TestAction ~= "saveslot")
	{
		// Save slots (CoopSaveSlots): step 0 saves to CoopTestSlot (default 1) with 150 health and 77 rounds, step 1 tries slot 2 with a
		// client down (refused). The test is off while saving: the save must not run it again
		if(TestStep == 0)
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(PlayerController(C) == None || C.Pawn == None)
					continue;

				C.Pawn.Health = 150;

				for(TestInv = C.Pawn.Inventory; TestInv != None; TestInv = TestInv.Inventory)
				{
					if(Ammunition(TestInv) != None && TestInv.IsA('DC17mBlasterAmmo'))
						Ammunition(TestInv).AmmoAmount = 77;
				}
			}

			i = Max(1, int(ParseOption(TestOptions, "CoopTestSlot")));
			TestAction = "";
			Str = SaveToSlot(i);
			TestAction = "saveslot";
			Log("CoopTest: saveslot: slot " $ i $ " result '" $ Str $ "' " $ class'CoopSaveSlots'.static.Describe(i) $ ", " $ TestEnemyText());
			TestTime = Level.TimeSeconds + 3;
			++TestStep;
			return;
		}

		if(TestStep == 1)
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				{
					C.Pawn.TakeDamage(1000, None, C.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
					break;
				}
			}

			TestTime = Level.TimeSeconds + 2;
			++TestStep;
			return;
		}

		if(TestStep == 2)
		{
			Log("CoopTest: saveslot: with a client down, slot 2: '" $ SaveToSlot(2) $ "'");

			// The lobby's rule for joining, checked on its own (PreLogin): a stranger and a player of the session
			class'CoopConfig'.default.SessionPlayers = "|Client1|";
			Str = "";
			Str2 = "";
			PreLogin("?Name=Stranger", "127.0.0.1", Str, Str2);
			Log("CoopTest: saveslot: join of a stranger: '" $ Str $ "'");
			Str = "";
			PreLogin("?Name=Client1", "127.0.0.1", Str, Str2);
			Log("CoopTest: saveslot: join of Client1 of the session: '" $ Str $ "'");
			Str = "";
			PreLogin("?Name=Client1_2", "127.0.0.1", Str, Str2);
			Log("CoopTest: saveslot: join of Client1_2 (renamed by MakeNameUnique): '" $ Str $ "'");
			Str = "";
			PreLogin("?Name=Client12", "127.0.0.1", Str, Str2);
			Log("CoopTest: saveslot: join of Client12, a stranger: '" $ Str $ "'");
			class'CoopConfig'.default.SessionPlayers = "";
		}
	}
	else if(TestAction ~= "visorfx")
	{
		// The visor's effects: every player is hit (ballistic, then melee) every 6 s, health given back. Screenshots with Shot.ps1
		// -WaitFor "visorfx: hit"
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(PlayerController(C) == None || C.Pawn == None)
				continue;

			if(TestStep % 2 == 0)
				C.Pawn.TakeDamage(40, None, C.Pawn.Location + vector(C.Pawn.Rotation) * 200, vect(0,0,0), class'CTDamageBallistic');
			else
				C.Pawn.TakeDamage(40, None, C.Pawn.Location + vector(C.Pawn.Rotation) * 50, vect(0,0,0), class'CTDamageMelee');

			C.Pawn.Health = C.Pawn.default.Health;
		}

		Log("CoopTest: visorfx: hit " $ TestStep);

		if(TestStep < 8)
		{
			TestTime = Level.TimeSeconds + 6;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "savemenu")
	{
		// Screenshots: step 0 the host's pause menu, step 1 its SAVE GAME menu (Tools/Shot.ps1 -WaitFor "savemenu")
		if(TestStep == 0)
		{
			Host.ShowMenu();
			Log("CoopTest: savemenu: pause menu");
		}
		else if(TestStep == 1)
		{
			foreach AllActors(class'CoopPauseMenu', TestPauseMenu)
				break;

			if(TestPauseMenu != None)
				TestPauseMenu.SaveGameSelected();

			Log("CoopTest: savemenu: save menu from " $ TestPauseMenu);
		}

		if(TestStep < 2)
		{
			TestTime = Level.TimeSeconds + 6;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "lobbyslot")
	{
		// The lobby with a save slot (CoopTestSlot, default 1): CoopTestLobbyClients clients, the host picks the slot, members are picked,
		// all ready. The loaded level runs no test: its log has "save loaded" and the players coming back
		if(Lobby == None)
			return;

		if(CountClients() < int(ParseOption(TestOptions, "CoopTestLobbyClients")))
		{
			TestTime = Level.TimeSeconds + 1;
			return;
		}

		i = 0;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) == None)
				continue;

			if(TestStep == 3 && IsHost(C))
				CoopPlayer(C).ServerCoopLobbyLevel(class'CoopSaveSlots'.static.Describe(Max(1, int(ParseOption(TestOptions, "CoopTestSlot")))));

			// A player of the save tries another member: refused
			if(TestStep == 5 && !IsHost(C))
				CoopPlayer(C).ServerCoopLobbyChoose(++i);

			if(TestStep == 8)
				CoopPlayer(C).ServerCoopLobbyReady(true);
		}

		Log("CoopTest: lobbyslot: " $ TestStep $ " " $ Lobby.StateString());
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return;
	}
	else if(TestAction ~= "lobby")
	{
		// CoopTestLobbyClients clients pick members 1, 2, 3 in the lobby, everybody gets ready, then the test rope on the level
		if(Lobby == None)
		{
			TestAction = "rope";
			TestStep = 0;
			TestTime = Level.TimeSeconds + 0.1;
			return;
		}

		if(CountClients() < int(ParseOption(TestOptions, "CoopTestLobbyClients")))
		{
			TestTime = Level.TimeSeconds + 1;
			return;
		}

		i = 0;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) == None)
				continue;

			if(TestStep == 3 && !IsHost(C))
				CoopPlayer(C).ServerCoopLobbyChoose(++i);

			// A member that is taken is refused
			if(TestStep == 5 && !IsHost(C) && i == 0)
			{
				++i;
				CoopPlayer(C).ServerCoopLobbyChoose(2);
			}

			if(TestStep == 7 && IsHost(C))
				CoopPlayer(C).ServerCoopLobbyLevel(ParseOption(TestOptions, "CoopTestLobbyMap"));

			if(TestStep == 12)
				CoopPlayer(C).ServerCoopLobbyReady(true);
		}

		Log("CoopTest: lobby: " $ TestStep $ " " $ Lobby.StateString());
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return;
	}
	else if(TestAction ~= "rope")
	{
		// The entrance on a rope: every 0.5 s the commandos and ropes on the server and the client
		if(TestStep == 0)
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C))
					CoopPlayer(C).ClientCoopTestCommand("NetJump");
			}

			foreach DynamicActors(class'Pawn', P)
				Log("CoopTest: jump: server freq " $ P.Class.Name $ " " $ P.NetUpdateFrequency $ " prio " $ P.NetPriority $ " always " $ P.bAlwaysRelevant);
		}

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C))
				CoopPlayer(C).ClientCoopTestCommand("RopeLog");
		}

		Log("CoopTest: rope: server " $ TestStep $ " " $ class'CoopPlayer'.static.RopeLines(self));
		TestTime = Level.TimeSeconds + 0.5;
		++TestStep;
		return;
	}
	else if(TestAction ~= "facing")
	{
		// The host walks away every 8 s, the squad follows. Every 0.5 s where the pawns look and where they go, on server and client
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(TestStep % 16 == 0)
		{
			foreach AllActors(class'PathNode', FacingNode)
			{
				if(VSize(FacingNode.Location - Host.Pawn.Location) > 700 && VSize(FacingNode.Location - Host.Pawn.Location) < 1500)
				{
					Host.Pawn.SetLocation(FacingNode.Location + vect(0,0,40));
					C.Pawn.SetLocation(FacingNode.Location + vect(60,0,40));
					C.ClientSetLocation(C.Pawn.Location, C.Pawn.Rotation);
					Log("CoopTest: facing: host to " $ FacingNode);
					break;
				}
			}
		}

		foreach DynamicActors(class'Pawn', P)
		{
			if(P.Controller != None && PlayerController(P.Controller) == None && P.Health > 0 && !P.IsA('Turret'))
				Log("CoopTest: facing: server " $ class'CoopPlayer'.static.FacingLine(P) $ " focus=" $ P.Controller.Focus $ " enemy=" $ P.Controller.Enemy $ " state=" $ P.Controller.GetStateName());
		}

		CoopPlayer(C).ClientCoopTestCommand("FacingLog");
		Log("CoopTest: facing: step " $ TestStep);
		TestTime = Level.TimeSeconds + 0.25;
		++TestStep;
		return;
	}
	else if(TestAction ~= "hostlift")
	{
		TestHostLift(Host);
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return;
	}
	else if(TestAction ~= "turretnear")
	{
		TestTurretNear(Host);
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return;
	}
	else if(TestAction ~= "endlift")
	{
		// The end lift: the host steps on it, the first client later (CoopTestLater=<seconds>), the squad members stay where they are
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(TestStep == 0)
		{
			if(ParseOption(TestOptions, "CoopTestOpen") != "")
				TriggerEvent('ElevatorDoor', Host.Pawn, Host.Pawn);

			TriggerEvent('Commando40Delta', Host.Pawn, Host.Pawn);
			TriggerEvent('Commando62Delta', Host.Pawn, Host.Pawn);
			TriggerEvent('Commando07Delta', Host.Pawn, Host.Pawn);
			TriggerEvent(EndLift.Gate.Tag, Host.Pawn, Host.Pawn);
			if(ParseOption(TestOptions, "CoopTestOnLift") != "")
				Host.Pawn.SetLocation(EndLift.Lift.Location + vect(0,0,150));
			else
				Host.Pawn.SetLocation(EndLift.Gate.Location + vect(0,0,100));

			Log("CoopTest: endlift: host at " $ Host.Pawn.Location $ " gate " $ EndLift.Gate $ " active " $ EndLift.Gate.bInitiallyActive);
		}

		if(C != None && TestStep == int(ParseOption(TestOptions, "CoopTestLater")))
		{
			if(ParseOption(TestOptions, "CoopTestOnLift") != "")
				C.Pawn.SetLocation(EndLift.Lift.Location + vect(60,60,150));
			else
				C.Pawn.SetLocation(EndLift.Gate.Location + vect(60,60,100));

			C.ClientSetLocation(C.Pawn.Location, C.Pawn.Rotation);
		}

		Log("CoopTest: endlift: " $ TestStep $ " started=" $ EndLift.bStarted $ " lift=" $ EndLift.Lift.Location.Z $ " host base=" $ Host.Pawn.Base $ " client base=" $ C.Pawn.Base);
		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return;
	}
	else if(TestAction ~= "walker")
	{
		if(TestWalker(Host))
			return;
	}
	else if(TestAction ~= "elite")
	{
		if(TestElite(Host))
			return;
	}
	else if(TestAction ~= "aapickup")
	{
		if(TestAAPickup(Host))
			return;
	}
	else if(TestAction ~= "accessory")
	{
		if(TestAccessory(Host))
			return;
	}
	else if(TestAction ~= "namecolor")
	{
		// The host's nickname in tactical mode (CoopExtension.KeepNameColor): the first client stands 300 in front of the host, looks at
		// him and turns tactical mode on, the host too; screenshots on "namecolor: shot"
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C != None && Host.Pawn != None)
		{
			if(TestStep == 0)
			{
				Host.bGodMode = true;
				C.bGodMode = true;
			}

			// The host stands where the client looks (the client's own view isn't turned: it comes back from its moves)
			if(TestStep == 2)
			{
				R = C.Rotation;
				R.Pitch = 0;
				V = C.Pawn.Location + vector(R) * 300;

				if(Host.Pawn.SetLocation(V) || (FindSpawnLocation(V, R, V) && Host.Pawn.SetLocation(V)))
					Log("CoopTest: namecolor: host put " $ int(VSize(Host.Pawn.Location - C.Pawn.Location)) $ " in front of the client");
			}

			Host.SetRotation(rotator(C.Pawn.Location - (Host.Pawn.Location + Host.Pawn.EyePosition())));

			if(TestStep == 3)
			{
				CoopPlayer(C).ClientCoopTestCommand("GotoVisionMode 1");
				Host.GotoVisionMode(1);
			}

			if(TestStep == 2 || TestStep == 5)
			{
				Log("CoopTest: namecolor: host mode " $ Host.Pawn.CurrentUserVisionMode $ " flashlight " $ Host.Pawn.Flashlight $ " tactical " $ Host.InTacticalVisionMode() $ " client at " $ int(VSize(C.Pawn.Location - Host.Pawn.Location)));
				CoopPlayer(C).ClientCoopTestCommand("VisionLog");
			}

			if(TestStep == 6)
				Log("CoopTest: namecolor: shot, host pawn color " $ Host.Pawn.EnhancedVisionColor.R $ "," $ Host.Pawn.EnhancedVisionColor.G $ "," $ Host.Pawn.EnhancedVisionColor.B);
		}

		if(TestStep < 9)
		{
			TestTime = Level.TimeSeconds + 1;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "snipeorder")
	{
		if(TestSnipeOrder(Host))
			return;
	}
	else if(TestAction ~= "ride")
	{
		// Puts the host on the mover CoopTestTag, triggers it at step 4, then logs the host and the clients every 0.5 s
		Mov = None;

		// No string to name cast
		foreach AllActors(class'Mover', Mov)
		{
			if(string(Mov.Tag) ~= ParseOption(TestOptions, "CoopTestTag"))
				break;
		}

		if(Mov != None && !(string(Mov.Tag) ~= ParseOption(TestOptions, "CoopTestTag")))
			Mov = None;

		if(Mov == None || Host.Pawn == None)
		{
			Log("CoopTest: ride: no mover " $ ParseOption(TestOptions, "CoopTestTag"));
			return;
		}

		if(TestStep == 0)
		{
			// The floor of the car, not its roof: the lowest hit on the mover of traces down from several heights over a grid around
			// the mover's origin (the car can be two movers with the same tag, RAS_02D)
			V2 = vect(0,0,1) * 100000;

			for(i = 0; i < 100; i = i + 1)
			{
				V = Mov.Location + vect(1,0,0) * ((i % 5) - 2) * 120 + vect(0,1,0) * (((i / 5) % 5) - 2) * 120 + vect(0,0,1) * (100 + (i / 25) * 170);
				A2 = Trace(HitLoc, HitNorm, V - vect(0,0,700), V, true);

				if(Mover(A2) != None && A2.Tag == Mov.Tag && HitLoc.Z < V2.Z)
					V2 = HitLoc;
			}

			if(V2.Z < 100000)
				Host.Pawn.SetLocation(V2 + vect(0,0,1) * (Host.Pawn.CollisionHeight + 10));

			Log("CoopTest: ride: host put at " $ Host.Pawn.Location $ " over " $ Mov $ " at " $ Mov.Location);
		}

		if(TestStep == 4)
		{
			Log("CoopTest: ride: triggering " $ Mov $ " Base of the host=" $ Host.Pawn.Base);
			Mov.Trigger(self, Host.Pawn);
		}

		Log("CoopTest: ride: " $ TestStep $ " host Base=" $ Host.Pawn.Base $ " Loc=" $ Host.Pawn.Location $ " lift Moving=" $ Mov.bInterpolating $ " Key=" $ Mov.KeyNum $ " Loc=" $ Mov.Location);

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				Log("CoopTest: ride: " $ TestStep $ " " $ C.PlayerReplicationInfo.PlayerName $ " State=" $ C.GetStateName() $ " Base=" $ C.Pawn.Base $ " Loc=" $ C.Pawn.Location $ " Dist=" $ int(VSize(C.Pawn.Location - Host.Pawn.Location)));
		}

		if(TestStep < 90)
		{
			TestTime = Level.TimeSeconds + 0.5;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "movers")
	{
		// Movers that move (or near CoopTestAt) and all running scripts, every 2 s
		foreach AllActors(class'Mover', Mov)
		{
			// CoopTestOpenDoors=1: doors with anti portals open (see CoopPlayer.SyncMoverAntiPortals)
			if(TestStep == 2 && Mov.AntiPortalTag != '' && ParseOption(TestOptions, "CoopTestOpenDoors") != "")
			{
				Mov.InterpolateTo(1, Mov.MoveTimes[0]);
				Log("CoopTest: movers: opening " $ Mov $ " Tag=" $ Mov.Tag $ " anti portals " $ Mov.AntiPortalTag);
			}

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
	else if(TestAction ~= "hud")
	{
		// The clients' HUD (CoopHUD host icon, SyncObjectiveTracker): step 0 sets the clients' window size (CoopTestClientRes=1280x720),
		// step 1 points the host's tracker at a navigation point 1000-3000 uu away, step 3 hides it. Screenshots with Tools/Shot.ps1.
		// The size is set again at step 2 for a client that joined after step 0 (-Delay 1: the tracker is set before it joins).
		if(TestStep == 0 || TestStep == 2)
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C) && ParseOption(TestOptions, "CoopTestClientRes") != "")
					CoopPlayer(C).ClientCoopTestCommand("SETRES " $ TestResText(ParseOption(TestOptions, "CoopTestClientRes")));

				// The names over the commandos as each side has them (CoopExtension.PawnHudName)
				if(CoopPlayer(C) != None && TestStep == 2)
					CoopPlayer(C).ClientCoopTestCommand("HudNames");
			}
		}
		else if(TestStep == 1)
		{
			for(NavIt = Level.NavigationPointList; NavIt != None; NavIt = NavIt.nextNavigationPoint)
			{
				if(VSize(NavIt.Location - Host.Pawn.Location) > 1000 && VSize(NavIt.Location - Host.Pawn.Location) < 3000)
					break;
			}

			Log("CoopTest: hud: host tracker -> " $ NavIt);

			if(NavIt != None)
				Host.Helmet.ShowActorObjectiveTracker(NavIt);
		}
		else if(TestStep == 3)
		{
			Log("CoopTest: hud: host tracker hidden");
			Host.Helmet.HideObjectiveTracker();
		}

		if(TestStep < 4)
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
	else if(TestAction ~= "clientdown")
	{
		// The first client down: step 0 incapacitated with a stale acceleration as if a key was held (TickClientPawns must stop it),
		// step 1 the distance moved, a squad member put on its revive marker and the bleed-out time passed (IsBeingRevived must hold it),
		// step 2 still down, the member taken off, step 3 up again as the same member next to the host (BleedOutClient), the commandos counted
		if(TestStep == 0)
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
					break;
			}

			if(C == None)
				return;

			TestDownPawn = C.Pawn;
			TestDownPawn.TakeDamage(1000, None, TestDownPawn.Location, vect(0,0,0), class'CTDamageBallistic');
			TestDownPawn.Acceleration = vect(1,0,0) * TestDownPawn.AccelRate;
			TestDownLoc = TestDownPawn.Location;
			Log("CoopTest: clientdown: " $ TestDownPawn.Class.Name $ " incapacitated=" $ TestDownPawn.bIncapacitated $ " at " $ TestDownLoc $ " with acceleration " $ TestDownPawn.Acceleration);
		}
		else if(TestStep == 1)
		{
			Log("CoopTest: clientdown: moved " $ VSize(TestDownPawn.Location - TestDownLoc) $ " while down, acceleration " $ TestDownPawn.Acceleration);

			foreach DynamicActors(class'Pawn', TestReviver)
			{
				if(TestReviver != TestDownPawn && TestReviver.IsA('CloneCommando') && AIController(TestReviver.Controller) != None && TestReviver.Health > 0)
					break;
			}

			if(TestReviver != None && CloneCommando(TestDownPawn) != None)
				TestReviver.SquadMarker = CloneCommando(TestDownPawn).ReviveMarker;

			CoopPlayer(TestDownPawn.Controller).IncapacitatedTime = Level.TimeSeconds - ClientBleedOutTime - 1;
			Log("CoopTest: clientdown: reviver " $ TestReviver $ " on " $ TestReviver.SquadMarker $ ", being revived " $ IsBeingRevived(TestDownPawn));
		}
		else if(TestStep == 2)
		{
			Log("CoopTest: clientdown: after the bleed-out time with a reviver: incapacitated=" $ TestDownPawn.bIncapacitated $ " health=" $ TestDownPawn.Health);

			if(TestReviver != None)
				TestReviver.SquadMarker = None;
		}
		else if(TestStep == 3)
		{
			i = 0;

			foreach DynamicActors(class'Pawn', TestReviver)
			{
				if(TestReviver.IsA('CloneCommando'))
					++i;
			}

			Log("CoopTest: clientdown: end: pawn " $ TestDownPawn.Controller.Pawn $ " same " $ (TestDownPawn.Controller.Pawn == TestDownPawn) $ " health " $ TestDownPawn.Health $ " incapacitated " $ TestDownPawn.bIncapacitated $ " " $ VSize(TestDownPawn.Location - Host.Pawn.Location) $ " from the host, commandos " $ i);
		}

		if(TestStep < 3)
		{
			TestTime = Level.TimeSeconds + 4;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "corpsesave")
	{
		// The host's crash of 2026-11-12 (RAS_02D, FLevelSceneNode::FilterProjector on a stale projector): a client's commando died and stayed
		// as a body, the client got a new one, then a checkpoint was saved and the body was gone. Step 0 kills the first client the old way,
		// step 1 (after the respawn) saves a checkpoint, steps 2-9 log what is left of the body every 4 s
		if(TestStep == 0)
		{
			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
					break;
			}

			if(C == None)
				return;

			TestDownPawn = C.Pawn;
			TestDownPawn.SetLocation(Host.Pawn.Location + vector(Host.Pawn.Rotation) * 250);
			TestDownPawn.TakeDamage(1000, None, TestDownPawn.Location, vect(0,0,0), class'CTDamageBallistic');
			TestDownPawn.BleedOut();
			Log("CoopTest: corpsesave: " $ TestDownPawn $ " dead, health " $ TestDownPawn.Health $ ", flashlight " $ TestDownPawn.Flashlight $ ", shadow " $ TestDownPawn.Shadow);
			TestTime = Level.TimeSeconds + 9;
			++TestStep;
			return;
		}

		if(TestStep == 1)
		{
			foreach AllActors(class'Checkpoint', TestCheckpoint)
			{
				if(TestCheckpoint.Tag != 'CheckpointStart')
					break;
			}

			Log("CoopTest: corpsesave: body before the save: " $ TestDownPawn $ " deleted " $ (TestDownPawn == None || TestDownPawn.bDeleteMe));
			TestCheckpoint.Trigger(Host, Host.Pawn);
			Log("CoopTest: corpsesave: triggered " $ TestCheckpoint);
		}
		else
			Log("CoopTest: corpsesave: step " $ TestStep $ " body " $ TestDownPawn $ " deleted " $ (TestDownPawn == None || TestDownPawn.bDeleteMe));

		if(TestStep < 9)
		{
			TestTime = Level.TimeSeconds + 4;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "healweapon")
	{
		// The user's game 2026-11-14: a client with the sniper rifle revives the host with the bacta healer and must get the rifle back,
		// not the blaster. Step 0 gives the client a rifle and brings it up, step 1 puts the host down, step 2 the client revives him
		// (client command ReviveHost), steps 3-6 log the client's weapon on the server; the client's "weapons:" lines show every change
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None)
			return;

		if(TestStep == 0)
		{
			if(C.Pawn.FindInventoryType(class<Inventory>(DynamicLoadObject("CTInventory.DC17mSniper", class'Class'))) == None)
			{
				TestInv = Spawn(class<Inventory>(DynamicLoadObject("CTInventory.DC17mSniper", class'Class')), C.Pawn);

				if(TestInv != None)
					TestInv.GiveTo(C.Pawn);
			}

			C.Pawn.SetLocation(Host.Pawn.Location + vector(Host.Pawn.Rotation) * 120);
			C.ClientSetLocation(C.Pawn.Location, rotator(Host.Pawn.Location - C.Pawn.Location));
			C.bGodMode = true;
			CoopPlayer(C).ClientCoopTestCommand("HoldWeapon DC17mSniper");
			Log("CoopTest: healweapon: client has " $ C.Pawn.Weapon.Class.Name);
		}
		else if(TestStep == 1)
		{
			Log("CoopTest: healweapon: client holds " $ C.Pawn.Weapon.Class.Name $ ", host down");
			Host.Pawn.TakeDamage(1000, None, Host.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
		}
		else if(TestStep == 2)
		{
			Log("CoopTest: healweapon: host incapacitated " $ Host.Pawn.bIncapacitated $ ", client revives");
			CoopPlayer(C).ClientCoopTestCommand("ReviveHost");
		}
		else
			Log("CoopTest: healweapon: step " $ TestStep $ " client weapon " $ C.Pawn.Weapon.Class.Name $ ", host incapacitated " $ Host.Pawn.bIncapacitated);

		if(TestStep < 6)
		{
			TestTime = Level.TimeSeconds + 4;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "bactaicon")
	{
		// The bacta dispenser's hologram on a client (the user's screenshots 2026-11-14: the host has it, the client not). Host and first
		// client hurt and put in front of the nearest dispenser, looking at it; the server's decision for its marker is logged.
		// Screenshots with Shot.ps1 -WaitFor "bactaicon: in front"
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None)
			return;

		foreach DynamicActors(class'ActivateItem', A)
		{
			if(A.IsA('BactaDispenser') && (TestPanel == None || VSize(A.Location - Host.Pawn.Location) < VSize(TestPanel.Location - Host.Pawn.Location)))
				TestPanel = A;
		}

		if(TestPanel == None)
		{
			Log("CoopTest: bactaicon: no dispenser");
			return;
		}

		R = TestPanel.Rotation;
		R.Pitch = 0;
		V = TestPanel.Location + vector(R) * 220 + vect(0,0,-20);
		Host.Pawn.SetLocation(V + vect(0,90,0));
		C.Pawn.SetLocation(V - vect(0,90,0));
		Host.ClientSetLocation(Host.Pawn.Location, rotator(TestPanel.Location - Host.Pawn.Location));
		C.ClientSetLocation(C.Pawn.Location, rotator(TestPanel.Location - C.Pawn.Location));
		C.Pawn.Health = 60;

		// CoopTestHostHurt: the host hurt as well, for comparing what he sees with the client
		if(ParseOption(TestOptions, "CoopTestHostHurt") != "")
			Host.Pawn.Health = 60;

		Host.bGodMode = true;
		C.bGodMode = true;

		foreach AllActors(class'SquadMarker', M)
		{
			if(M.Anchor == TestPanel)
				Log("CoopTest: bactaicon: host health " $ Host.Pawn.Health $ ", client " $ C.Pawn.Health $ ", marker " $ M.Class.Name $ " state " $ M.GetStateName() $ " available " $ MarkerIsAvailable(M) $ " usable " $ TestPanel.bIsUsable $ " host usability " $ int(M.GetMarkerUsability(Host.Pawn)) $ " client usability " $ int(M.GetMarkerUsability(C.Pawn)) $ " hidden " $ M.bHidden);
		}

		Log("CoopTest: bactaicon: in front of " $ TestPanel $ " step " $ TestStep);

		if(TestStep == 1 && ParseOption(TestOptions, "CoopTestForceIcons") != "")
			CoopPlayer(C).ClientCoopTestCommand("ForceIcons");

		if(TestStep == 2)
		{
			CoopPlayer(C).ClientCoopTestCommand("MarkerIcons");

			foreach AllActors(class'SquadMarker', M)
			{
				if(M.Anchor == TestPanel)
				{
					for(i = 0; i < 3; ++i)
						Log("CoopTest: bactaicon: server icon " $ i $ " " $ M.Participants[i].IconActor $ " hidden " $ M.Participants[i].IconActor.bHidden $ " relevant " $ M.Participants[i].IconActor.bAlwaysRelevant $ " alpha " $ M.Participants[i].IconActor.CurrentAlpha $ " mesh " $ M.Participants[i].IconMesh);
				}
			}
		}

		if(TestStep < 3)
		{
			TestTime = Level.TimeSeconds + 5;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "getupdown")
	{
		// The user's game 2026-11-14 (RAS_02C): the host revived, and the client falls while the host still plays the get-up animation.
		// Step 0 the host down, step 1 the host revived (state Reviving) and the client down in the same moment, steps 2-4 log: no
		// "squad is down" may come, the host gets up
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None)
			return;

		// Step 0 a checkpoint (without one a squad wipe only restarts), step 1 the host down by a small hit at 1 health (a big one kills)
		if(TestStep == 0)
		{
			foreach AllActors(class'Checkpoint', TestCheckpoint)
			{
				if(TestCheckpoint.Tag != 'CheckpointStart')
					break;
			}

			TestCheckpoint.Trigger(Host, Host.Pawn);
		}
		else if(TestStep == 1)
		{
			Host.Pawn.TakeDamage(1000, None, Host.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
		}
		else if(TestStep == 2)
		{
			Host.Pawn.Revive();
			C.Pawn.TakeDamage(1000, None, C.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
		}

		Log("CoopTest: getupdown: step " $ TestStep $ " host state " $ Host.Pawn.GetStateName() $ " incap " $ Host.Pawn.bIncapacitated $ " health " $ Host.Pawn.Health $ " up " $ IsUp(Host.Pawn) $ ", client incap " $ C.Pawn.bIncapacitated);

		if(TestStep < 7)
		{
			TestTime = Level.TimeSeconds + 1.5;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "handsidle")
	{
		// The state of the user's game 2026-11-12 after a panel: the client holds its rifle, the server's copy of its hands is left in Idle
		// with another weapon as the last one. HandSignal.Idle.Tick then swapped the two every frame until the hands were parked.
		// Step 0 sets it up, step 1 logs the weapon after 3 s; the client's "weapons:" lines between show every change
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None)
			return;

		if(TestStep == 0)
		{
			TestDownPawn = C.Pawn;

			for(TestInv = C.Pawn.Inventory; TestInv != None; TestInv = TestInv.Inventory)
			{
				if(Weapon(TestInv) != None && Weapon(TestInv).WeaponType == WT_Marker)
					CoopPlayer(C).ServerHands = Weapon(TestInv);
				else if(Weapon(TestInv) != None && Weapon(TestInv) != C.Pawn.Weapon && (Weapon(TestInv).WeaponType == WT_Primary || Weapon(TestInv).WeaponType == WT_Secondary))
					C.Pawn.OldWeapon = Weapon(TestInv);
			}

			Log("CoopTest: handsidle: weapon " $ C.Pawn.Weapon.Class.Name $ ", last " $ C.Pawn.OldWeapon $ ", hands " $ CoopPlayer(C).ServerHands $ " put in Idle");

			if(CoopPlayer(C).ServerHands != None)
				CoopPlayer(C).ServerHands.GotoState('Idle');

			TestTime = Level.TimeSeconds + 3;
			++TestStep;
			return;
		}

		Log("CoopTest: handsidle: after 3 s the weapon is " $ C.Pawn.Weapon.Class.Name $ ", hands in " $ CoopPlayer(C).ServerHands.GetStateName());
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
	       P.Controller != None && PlayerController(P.Controller) == None && !IsScriptBusy(P) && !P.bHidden && !IsSceneOnlyMember(P);
}

// RAS_01B: Sev stands in the sealed core as the prisoner the squad sees through a window, the level removes and destroys him. A client that
// took him was cut off from the others and the slaver's scene had no victim
function bool IsSceneOnlyMember(Pawn P)
{
	return P.Tag == 'Seven' && IsMap("RAS_01B");
}

function bool IsMap(string MapName)
{
	return Left(string(Level), Len(MapName) + 1) ~= (MapName $ ".");
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

	// The script reaches the scene only after waiting for events, the search below stops at those
	if(SevIntro.IsSev(P))
	{
		Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " watches " $ P $ " until its scene ends");
		CP.bIntroWatch = true;
		CP.IntroWaitIndex = SC.ActionNum;
		CP.IntroWatchStart = Level.TimeSeconds;
		StartWatching(CP, P, false);
		return true;
	}

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

		// Everybody gets the control when Sev's scene is over
		if(SevIntro.IsRunning())
			continue;

		SC = ScriptedController(P.Controller);
		Reason = "";

		// On a lift the client gets the member when the lift stops, in the scene at the start of the level when it ends. A level that
		// starts with a scene (GEO_03A) hands the member over as soon as the scene ends: the lift check still saw the host on the
		// elevator for up to 2.5 s (HostLift tolerates stops) and the client waited after the briefing.
		if((InStartScene() || (SceneEndEvent == '' && HostLift(GetHost()) != None && P.Base == HostLift(GetHost()))) && Level.TimeSeconds - CP.IntroWatchStart < 240)
			continue;

		if(SC == None || !SC.IsInState('Scripting') || SC.SequenceScript == None)
			Reason = "script over";
		// The briefing at the start of the level is over: the member's last animation isn't waited for, the player takes over at once
		else if(SceneEndEvent != '' && WasHeard(SceneEndEvent))
			Reason = "scene over";
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
			Str = Str $ " " $ P $ "/" $ P.Class.Name $ "(" $ P.Controller $ ")";
		}
	}

	if(Num != LastCommandoCount)
	{
		LastCommandoCount = Num;
		Log("CoopGame: Commandos: " $ Num $ ":" $ Str);
	}
}

/*
 * A client watching a squad member (its scene, its entrance, the briefing in the lift) still has its own commando where it spawned:
 * GEO_03A showed 7 commandos in the elevator, the squad and the clients' own ones. The own commando is hidden and doesn't collide
 * while its client watches; the takeover destroys it, a watch that ends without one shows it again.
 */
function HideWatchingPawns()
{
	local Controller C;
	local CoopPlayer CP;
	local bool bHide;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || IsHost(CP))
			continue;

		bHide = CoopCommando(CP.Pawn) != None && CP.IsInState('CoopWatching') && CP.WatchedMember != None && CP.WatchedMember != CP.Pawn;

		if(bHide == CP.bWatchHidden)
			continue;

		CP.bWatchHidden = bHide;

		if(bHide)
		{
			Log("CoopGame: hiding the own commando of " $ CP.PlayerReplicationInfo.PlayerName $ " while it watches " $ CP.WatchedMember);
			HidePawnParts(CP.Pawn, CP.OwnHiddenActors);
			CP.Pawn.SetCollision(false, false, false);
		}
		else
		{
			Log("CoopGame: showing the own commando of " $ CP.PlayerReplicationInfo.PlayerName $ " again: " $ CP.Pawn);
			ShowHiddenParts(CP.OwnHiddenActors);

			if(CP.Pawn != None && !CP.Pawn.bDeleteMe)
				CP.Pawn.SetCollision(true, true, true);
		}
	}
}

/*
 * The server's copy of a client's weapon stuck in NormalFire without an animation (GEO_05B: Fixer's rifle after a hack panel, for
 * the rest of the level). CoopPlayer.FixStuckFire only frees the client's copy: the server ignored the client's shots and weapon
 * changes, the client seemed to have lost its weapon or hands. Same fix on the server after 1.5 s.
 */
function CheckServerStuckFire()
{
	local Controller C;
	local CoopPlayer CP;
	local Weapon W;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || IsHost(CP))
			continue;

		W = None;

		if(CP.Pawn != None && !CP.Pawn.bIncapacitated && CP.Pawn.Health > 0)
			W = CP.Pawn.Weapon;

		if(W == None || !(W.IsInState('NormalFire') || W.IsInState('AltFire')) || W.IsAnimating(0) || W.IsAnimating(1) ||
		   W.WeaponType == WT_Heal || W.WeaponType == WT_Marker || W.WeaponType == WT_Turret || CP.IsInState('UsingItem') || CP.IsInState('PlayerManningTurret'))
		{
			CP.ServerStuckFireStart = 0;
			continue;
		}

		if(CP.ServerStuckFireStart == 0)
		{
			CP.ServerStuckFireStart = Level.TimeSeconds;
			continue;
		}

		if(Level.TimeSeconds - CP.ServerStuckFireStart < 1.5)
			continue;

		CP.ServerStuckFireStart = 0;
		Log("CoopGame: weapon " $ W $ " of " $ CP.PlayerReplicationInfo.PlayerName $ " was stuck in " $ W.GetStateName() $ " on the server, ending the shot");
		W.AnimEnd(1);

		if(W.IsInState('NormalFire') || W.IsInState('AltFire'))
			W.GotoState('Idle');
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
		{
			RemoveDuplicateWeapons(CP.Pawn);
			Log("CoopGame: Status " $ CP.PlayerReplicationInfo.PlayerName $ ": State=" $ CP.GetStateName() $ " Pawn=" $ CP.Pawn.Class.Name $ " Health=" $ CP.Pawn.Health $
			    " Incap=" $ CP.Pawn.bIncapacitated $ " Physics=" $ CP.Pawn.Physics $ " Loc=" $ CP.Pawn.Location $ " Ack=" $ (CP.AcknowledgedPawn == CP.Pawn) $ " MoveTime=" $ CP.CurrentTimeStamp $ " ServerMoveAt=" $ CP.ServerTimeStamp $ " Now=" $ Level.TimeSeconds $ " Weapon=" $ CP.Pawn.Weapon $
			    " WeaponState=" $ CP.Pawn.Weapon.GetStateName() $ " Grenade=" $ CP.Pawn.CurrentGrenade $ " Ping=" $ CP.PlayerReplicationInfo.Ping $ " Weapons:" $ CP.WeaponList());
		}
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
	if(P != None && PlayerController(P.Controller) == None)
		SendScriptAnim(P, Anim, Rate, bLoop);
}

/*
 * ACTION_PlayPropAnim on a pawn (the host on the rope: GEO_01A, GEO_01C, GEO_03C, GEO_04A, GEO_04B): replicated like the above, on the
 * clients the host slid down the rope in its idle pose. It isn't the script's controller that holds this animation, it lasts as long as it plays.
 */
function ForwardPropAnim(Pawn P, name Anim, float Rate)
{
	if(P != None && (CoopPlayer(P.Controller) == None || IsHost(P.Controller)))
		SendScriptAnim(P, Anim, Rate, false);
}

function SendScriptAnim(Pawn P, name Anim, float Rate, bool bLoop)
{
	local Controller C;
	local int i;

	for(i = 0; i < ScriptAnimPawns.Length; i = i + 1)
	{
		if(ScriptAnimPawns[i] == P)
			break;
	}

	ScriptAnimPawns[i] = P;
	ScriptAnimNames[i] = Anim;
	ScriptAnimRates[i] = Rate;
	ScriptAnimLoops[i] = byte(bLoop);

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopScriptAnim(P, Anim, Rate, bLoop);
	}
}

function bool ScriptAnimStillPlays(Pawn P, name Anim)
{
	local name Seq;
	local float Frame;

	if(P == None || P.bDeleteMe)
		return false;

	if(P.Controller != None && PlayerController(P.Controller) == None && P.Controller.bControlAnimations)
		return true;

	P.GetAnimParams('', Seq, Frame);

	return Seq == Anim && P.IsAnimating();
}

/*
 * The entrance on a rope is over when the commando stands on the ground, at 90 % of the animation (GEO_04A, GEO_01C): the level's script
 * keeps the host in its briefing state for 4 s more and clients get their members later still, when the member has walked off.
 * Here every player gets the control at once: the client its member, the host its movement (the script's end of the briefing
 * comes later and changes nothing then).
 */
function bool IsOnRope(Pawn P, out float Frame)
{
	local name Seq;

	P.GetAnimParams('', Seq, Frame);

	return Left(Caps(string(Seq)), 12) == "ENTRANCEROPE" || Left(Caps(string(Seq)), 10) == "CUSTOMROPE";
}

function CheckRopeLandings()
{
	local Controller C;
	local CoopPlayer CP;
	local Pawn P;
	local float Frame;
	local bool bOnRope, bHeld;

	// While Sev's scene plays everybody stays where they landed and looks at him
	SevIntro.Check();
	bHeld = SevIntro.IsRunning();

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None)
			continue;

		if(IsHost(CP))
		{
			P = CP.Pawn;

			if(!bHeld && P != None && CP.IsInState('Briefing') && !CP.bLiftView && IsOnRope(P, Frame) && Frame >= 0.9)
			{
				Log("CoopGame: the host landed, ending its briefing");
				CP.GotoState('PlayerWalking');
				P.ChangeAnimation();
			}

			continue;
		}

		P = CP.WatchedMember;

		if(P == None || P.bDeleteMe || P.Health <= 0)
		{
			CP.bWatchedOnRope = false;
			continue;
		}

		bOnRope = IsOnRope(P, Frame);

		if(bOnRope && Frame < 0.9)
			CP.bWatchedOnRope = true;
		else if(CP.bWatchedOnRope && !bHeld)
		{
			Log("CoopGame: " $ CP.PlayerReplicationInfo.PlayerName $ " gets " $ P $ ", it landed");
			CP.bWatchedOnRope = false;
			CP.bIntroWatch = false;
			TakeOver(CP, P, false);
		}
	}
}

function CheckScriptAnims()
{
	local Controller C;
	local Pawn P;
	local int i;
	local name Seq;
	local float Frame;

	if(Level.TimeSeconds < NextScriptAnimCheck)
		return;

	NextScriptAnimCheck = Level.TimeSeconds + 0.2;

	CheckRopeLandings();

	for(i = ScriptAnimPawns.Length - 1; i >= 0; i = i - 1)
	{
		P = ScriptAnimPawns[i];

		if(ScriptAnimStillPlays(P, ScriptAnimNames[i]))
		{
			// An animation that starts with the level comes before its pawn is on the clients (nothing but the controllers is
			// replicated while the level waits for them): GEO_04A, the squad on the ropes. Until they have it
			P.GetAnimParams('', Seq, Frame);

			for(C = Level.ControllerList; C != None; C = C.nextController)
			{
				if(CoopPlayer(C) != None && !IsHost(C))
					CoopPlayer(C).ClientCoopKeepScriptAnim(P, ScriptAnimNames[i], ScriptAnimRates[i], ScriptAnimLoops[i] != 0, Frame);
			}

			continue;
		}

		ScriptAnimPawns.Remove(i, 1);
		ScriptAnimNames.Remove(i, 1);
		ScriptAnimRates.Remove(i, 1);
		ScriptAnimLoops.Remove(i, 1);

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
 * Scripts of pawns that stand on an action that doesn't wait (a condition, a jump to a label): GEO_01C, the sniper scene, Sev's
 * script stood at "If condition TakeOff" and the mission couldn't be completed. Such scripts are continued after 2 seconds.
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

		// Only scripts of pawns on a condition or a jump. Level scripts (ScriptedTrigger) and the other actions were pushed too while
		// they waited legitimately (a timer after SetHidden): the script ran again inside its own state, the host crashed in
		// ScriptedTriggerController.Scripting (GEO_01C, session 2026-10-31)
		if(SC.Pawn == None || ScriptedTriggerController(SC) != None || A == None ||
		   !(A.IsA('ACTION_IfCondition') || A.IsA('ACTION_GotoLabel') || A.IsA('ACTION_Label') || A.IsA('ACTION_EndSection')))
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

/*
 * The objective tracker (the compass ring around the crosshair with direction and distance) of the host's helmet, for every client.
 * Level scripts change it for the host only (ForwardObjectiveTracker sends that at once), this also covers clients that joined or
 * travelled later and actors that move. Sent when it changes and every 5 seconds. Clients with their own pointer (door hold, sniper
 * position, see CoopPlayer.bTrackerOverride) are skipped until it ends.
 */
function SyncObjectiveTracker()
{
	local PlayerController Host;
	local Controller C;
	local CoopPlayer P;
	local Actor A;
	local vector Loc;
	local bool bShow, bResend;

	Host = GetHost();

	if(Host == None || Host.Helmet == None)
		return;

	bShow = Host.Helmet.bShowObjectiveTracker;
	A = Host.Helmet.ObjectiveActor;

	if(A != None)
		Loc = A.Location;
	else
		Loc = Host.Helmet.ObjectivePosition;

	bResend = Level.TimeSeconds >= NextTrackerResend;

	if(bResend)
		NextTrackerResend = Level.TimeSeconds + 5;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		P = CoopPlayer(C);

		if(P == None || IsHost(C) || P.bTrackerOverride)
			continue;

		if(!bResend && P.bSentTrackerShow == bShow && (!bShow || (P.SentTrackerActor == A && VSize(P.SentTrackerLocation - Loc) < 64)))
			continue;

		if(P.bSentTrackerShow != bShow || P.SentTrackerActor != A)
			Log("CoopGame: objective tracker of " $ P.PlayerReplicationInfo.PlayerName $ " -> " $ bShow $ " " $ A $ " " $ Loc);

		SendObjectiveTracker(P, A, Loc, bShow);
	}
}

function SendObjectiveTracker(CoopPlayer P, Actor A, vector Loc, bool bShow)
{
	P.bSentTrackerShow = bShow;
	P.SentTrackerActor = A;
	P.SentTrackerLocation = Loc;
	P.ClientCoopObjectiveTracker(A, Loc, bShow);
}

// A pointer of the mod's own (door hold, sniper position) replaces the host's tracker on this client; when it ends the host's comes back
function SetTrackerOverride(CoopPlayer P, bool bOverride, optional vector Loc)
{
	if(P == None)
		return;

	if(bOverride)
		P.ClientCoopObjectiveTracker(None, Loc, true);
	else if(P.bTrackerOverride)
		P.ClientCoopObjectiveTracker(None, vect(0,0,0), false);

	P.bTrackerOverride = bOverride;
	P.SentTrackerActor = None;
	P.bSentTrackerShow = false;  // The client shows nothing now: SyncObjectiveTracker sends the host's tracker again if it is shown
	P.SentTrackerLocation = vect(0,0,0);
}

// See CoopExtension: HUD changes of level scripts for every client
function ForwardObjectiveTracker(Actor A, bool bShow)
{
	local Controller C;
	local vector Loc;

	if(A != None)
		Loc = A.Location;

	Log("CoopGame: objective tracker of a level script -> " $ bShow $ " " $ A $ " " $ Loc);

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && !CoopPlayer(C).bTrackerOverride)
			SendObjectiveTracker(CoopPlayer(C), A, Loc, bShow);
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

// See CoopActionForward. OnlyTo: just this client.
function ForwardScriptAction(ScriptedAction Action, optional CoopPlayer OnlyTo)
{
	local Controller C;

	if(OnlyTo != None)
	{
		Log("CoopGame: forwarding script action " $ Action $ " to " $ OnlyTo.PlayerReplicationInfo.PlayerName $ ": " $ Action.GetActionString());
		OnlyTo.ClientCoopRunAction(string(Action));
		return;
	}

	Log("CoopGame: forwarding script action " $ Action $ ": " $ Action.GetActionString());
	RememberMusic(Action);

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C))
			CoopPlayer(C).ClientCoopRunAction(string(Action));
	}
}

/*
 * Music started before a client joined (GEO_03A: the briefing music comes at level start, the clients join a few seconds later,
 * also after every level change) is played on the client when it has a pawn: the last action of each music kind, in their order.
 */
function RememberMusic(ScriptedAction Action)
{
	local int i;

	if(ACTION_PlayMusic(Action) != None)
		i = 0;
	else if(ACTION_SetImuseState(Action) != None)
		i = 1;
	else if(ACTION_SetBattleMusicMulti(Action) != None)
		i = 2;
	else
		return;

	LastMusicActions[i] = Action;
	LastMusicTimes[i] = Level.TimeSeconds;
}

// See CoopTriggerForward
function RememberTrigger(Actor A)
{
	TriggeredTimes[TriggeredActors.Length] = Level.TimeSeconds;
	TriggeredActors[TriggeredActors.Length] = A;
}

function SendLastTriggers(CoopPlayer CP)
{
	local int i;

	if(CP.bTriggersSent || CP.Pawn == None)
		return;

	CP.bTriggersSent = true;

	if(TriggeredActors.Length > 0)
		Log("CoopGame: " $ TriggeredActors.Length $ " emitter triggers for " $ CP.PlayerReplicationInfo.PlayerName $ " who joined later");

	for(i = 0; i < TriggeredActors.Length; i = i + 1)
	{
		// Triggered before the client logged in: later ones reached it already
		if(TriggeredActors[i] != None && !TriggeredActors[i].bDeleteMe && TriggeredTimes[i] < CP.LoginTime)
			CP.ClientCoopTriggerActor(TriggeredActors[i]);
	}
}

function SendLastMusic(CoopPlayer CP)
{
	local int i, j, Best;
	local byte bSent[3];

	if(CP.bMusicSent || CP.Pawn == None)
		return;

	CP.bMusicSent = true;

	for(j = 0; j < 3; j = j + 1)
	{
		Best = -1;

		for(i = 0; i < 3; i = i + 1)
		{
			// Played before the client logged in: later ones reached it already (GEO_03C: the intro music started twice)
			if(LastMusicActions[i] != None && bSent[i] == 0 && LastMusicTimes[i] < CP.LoginTime && (Best == -1 || LastMusicTimes[i] < LastMusicTimes[Best]))
				Best = i;
		}

		if(Best == -1)
			return;

		bSent[Best] = 1;
		Log("CoopGame: music for " $ CP.PlayerReplicationInfo.PlayerName $ " who joined later: " $ LastMusicActions[Best].GetActionString());
		CP.ClientCoopRunAction(string(LastMusicActions[Best]));
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
 * The AI sniper ordered to a snipe marker (GEO_01C: the host orders Sev to the balcony): its script waited for WalkToSnipeMarker
 * with a high priority and kept Sev from the marker (session 2026-10-31, InSnipePosition never came). Once the AI member takes part
 * in the marker its script goes to the wait for the marker's EventUnderway (with the low priority the script sets before it), so
 * the marker moves Sev; SkipToSnipeWait goes on when it is in position. Logged every 3 s while the order runs.
 */
function CheckAISnipeOrders()
{
	local SquadMarker M;
	local Pawn P;
	local ScriptedController SC;
	local ACTION_WaitForEvent Wait;
	local CTBot Bot;
	local int i, w;

	foreach AllActors(class'SquadMarker', M)
	{
		if(!M.IsA('MarkerSnipe') || M.EventUnderway == '' || M.bComplete || WasHeard(M.EventUnderway))
			continue;

		P = None;

		for(i = 0; i < 3; i = i + 1)
		{
			if(M.Participants[i].Member != None && ScriptedController(M.Participants[i].Member.Controller) != None)
				P = M.Participants[i].Member;
		}

		if(P == None)
			continue;

		SC = ScriptedController(P.Controller);

		if(M != LastActiveSnipeMarker)
		{
			LastActiveSnipeMarker = M;
			Log("CoopGame: snipe order: " $ P $ " (" $ P.Class.Name $ ") took " $ M $ ", stance " $ P.Squad.Stance $ ", controller state " $ P.Controller.GetStateName() $ ", participants " $ M.Participants[0].Member $ "," $ M.Participants[1].Member $ "," $ M.Participants[2].Member);
		}

		if(Level.TimeSeconds >= NextSnipeOrderLog)
		{
			NextSnipeOrderLog = Level.TimeSeconds + 3;
			Log("CoopGame: " $ P $ " is ordered to " $ M $ " (active " $ M.bMarkerActive $ "), script action " $ SC.ActionNum $ ", " $ int(VSize(P.Location - M.Anchor.Location)) $ " from the anchor");
		}

		if(SC.SequenceScript == None)
			continue;

		for(w = SC.ActionNum; w < SC.SequenceScript.Actions.Length; w = w + 1)
		{
			Wait = ACTION_WaitForEvent(SC.SequenceScript.Actions[w]);

			if(Wait != None && Wait.ExternalEvent == M.EventUnderway)
				break;
		}

		if(w >= SC.SequenceScript.Actions.Length || w == SC.ActionNum)
			continue;

		// The priority the script sets right before that wait
		if(w > 0 && SC.SequenceScript.Actions[w - 1] != None && SC.SequenceScript.Actions[w - 1].IsA('ACTION_SetScriptPriority'))
			w = w - 1;

		if(w <= SC.ActionNum)
			continue;

		Log("CoopGame: " $ P $ " was ordered to " $ M $ ", its script goes on from " $ SC.ActionNum $ " to " $ w $ " (the wait for " $ M.EventUnderway $ ")");
		Bot = CTBot(SC);

		if(Bot != None && Bot.ScriptedGoals != None)
			Bot.ScriptedGoals.Clear();

		SC.ActionNum = w;
		SC.SequenceScript.SetActions(SC);
	}
}

function ListenToSnipeMarkers()
{
	local SquadMarker M;

	foreach AllActors(class'SquadMarker', M)
	{
		if(M.IsA('MarkerSnipe') && M.EventUnderway != '')
			ListenForEvent(M.EventUnderway);
	}
}

/*
 * The AI sniper on its position by the first order (GEO_01C: the host orders Sev to the balcony marker): its script still walked
 * the long way (WalkToSnipeMarker -> MoveToPoint 07StandBySnipe with priority 1) and took Sev off the marker; the shot at the ship
 * then came from somewhere else or Sev ran away (session 2026-10-31). When the marker's EventUnderway comes, the script of the AI
 * member on that marker goes on right after its wait for that event: Sev stays on the marker and waits for the take off.
 */
function SkipToSnipeWait(name EventName)
{
	local ScriptedController SC;
	local ACTION_WaitForEvent Wait;
	local CTBot Bot;
	local int i;

	foreach DynamicActors(class'ScriptedController', SC)
	{
		if(SC.Pawn == None || SC.SequenceScript == None || SC.Pawn.SquadMarker == None || !SC.Pawn.SquadMarker.IsA('MarkerSnipe') ||
		   SC.Pawn.SquadMarker.EventUnderway != EventName)
			continue;

		for(i = SC.ActionNum; i < SC.SequenceScript.Actions.Length; i = i + 1)
		{
			Wait = ACTION_WaitForEvent(SC.SequenceScript.Actions[i]);

			if(Wait != None && Wait.ExternalEvent == EventName)
				break;
		}

		if(i >= SC.SequenceScript.Actions.Length || i == SC.ActionNum)
			continue;

		Log("CoopGame: " $ SC.Pawn $ " is on " $ SC.Pawn.SquadMarker $ ", its script goes on from " $ SC.ActionNum $ " to " $ (i + 1) $ " (after the wait for " $ EventName $ ")");
		Bot = CTBot(SC);

		// The walk of the script (MoveToPoint) is a scripted goal of the bot
		if(Bot != None && Bot.ScriptedGoals != None)
			Bot.ScriptedGoals.Clear();

		SC.ActionNum = i + 1;
		SC.SequenceScript.SetActions(SC);
	}
}

/*
 * A snipe position the level's script waits for (GEO_01C: without Sev on it Sun Fac's ship gets away and the mission fails) while the AI plays
 * Sev: only the host's order sends him there. New players didn't know: the host is told until the order is given. Only this marker so far:
 * for other places where it may help see "Hints for orders" in the DEVLOG.
 */
function HintSnipeOrder(SquadMarker M)
{
	local PlayerController Host;
	local color TextColor;

	Host = GetHost();

	if(CoopPlayer(Host) == None || Host.Pawn == None || M.Tag != 'BalconyMarkerSnipe' || M.EventUnderway == '' || !M.AlwaysVisible || !M.IsInState('Enabled') || M.bComplete ||
	   WasHeard(M.EventUnderway) || Level.TimeSeconds < NextSnipeOrderHint)
		return;

	if(NextSnipeOrderHint == 0)
		Log("CoopGame: the host is told to order the sniper to " $ M);

	NextSnipeOrderHint = Level.TimeSeconds + SNIPE_ORDER_HINT_INTERVAL;
	TextColor.R = 255;
	TextColor.G = 220;
	TextColor.B = 120;
	TextColor.A = 255;
	CoopPlayer(Host).ClientCoopCriticalMessage("ORDER SEV: AIM AT THE CRATE, PRESS USE", SNIPE_ORDER_HINT_TIME, TextColor);
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

		if(PC == None)
			HintSnipeOrder(M);

		if(PC == None || PC.Pawn == None)
			continue;

		for(i = 0; i < ClientSnipeMarkers.Length; i = i + 1)
		{
			if(ClientSnipeMarkers[i] == M)
				break;
		}

		if(i == ClientSnipeMarkers.Length)
		{
			// Only the position whose scene needs Sev himself: the others go to the host's order like in single player (SnipeNeedsClient)
			if(!M.AlwaysVisible || M.Tag != 'BalconyMarkerSnipe')
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
			SetTrackerOverride(CoopPlayer(PC), true, M.Anchor.Location);
		}

		if(ClientSnipeStates[i] == 1 && VSize(PC.Pawn.Location - M.Anchor.Location) < 300)
		{
			ClientSnipeStates[i] = 2;

			SetTrackerOverride(CoopPlayer(PC), false);

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

	RememberMissableEvent(EventName);
	RunLevelRule(EventName);
	RunDeferredTriggers(EventName);
	SkipToSnipeWait(EventName);

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
	local PlayerController Host;
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

		// Players don't see the points: any point of the same arrival counts (GEO_05B: the three spots in the elevator), and so does
		// the host reaching the group, who gathers the squad like in the single player game (the clients ride the lift with the host)
		if(!IsNearArrivalGroup(P, i))
		{
			Host = GetHost();

			if(Host == None || Host.Pawn == None || !IsNearArrivalGroup(Host.Pawn, i))
				continue;

			Log("CoopGame: arrival " $ ArrivalEvents[i] $ ": the host reached " $ ArrivalPoints[i] $ ", counting " $ P.Controller.PlayerReplicationInfo.PlayerName);
		}

		ArrivalDone[i] = 1;
		Log("CoopGame: " $ P.Controller.PlayerReplicationInfo.PlayerName $ " arrived at " $ ArrivalPoints[i] $ ", triggering " $ ArrivalEvents[i]);
		TriggerEvent(ArrivalEvents[i], ArrivalPoints[i], P);
	}
}

// See CheckClientArrivals: the points of the arrivals that trigger the same counter after the same event
function bool IsNearArrivalGroup(Pawn P, int Index)
{
	local int i;

	for(i = 0; i < ArrivalPoints.Length; i = i + 1)
	{
		if(ArrivalPoints[i] != None && ArrivalEvents[i] == ArrivalEvents[Index] && ArrivalArmEvents[i] == ArrivalArmEvents[Index] &&
		   VSize(P.Location - ArrivalPoints[i].Location) <= ArrivalRadius)
			return true;
	}

	return false;
}

// Events of single levels that need something only the host gets from the level's own scripts
function ListenToLevelRules()
{
	if(IsMap("RAS_01A"))
		ListenForEvent('DropshipAnimProp');
	else if(IsMap("YYY_01E"))
		MissionFailEvent = 'MissionFailed';
	else if(IsMap("YYY_05F"))
		MissionFailEvent = 'Tarfful_Dead';

	if(MissionFailEvent != '')
		ListenForEvent(MissionFailEvent);
}

function RunLevelRule(name EventName)
{
	if(EventName == MissionFailEvent && EventName != '' && MissionFailTime == 0 && CountClients() > 0)
	{
		MissionFailTime = Level.TimeSeconds + MISSION_FAIL_DELAY;
		Log("CoopGame: mission failed (" $ EventName $ "), restarting the level for everybody in " $ MISSION_FAIL_DELAY $ " seconds");
	}
}

/*
 * YYY_01E, YYY_05F: when Tarfful dies the script kills the player by the tag only the host has. The clients stayed alive in a level whose end
 * can't come any more (the last guard is made invulnerable), so the level starts over for everybody, as the single player game reloads it.
 */
function CheckMissionFailed()
{
	if(MissionFailTime != 0 && Level.TimeSeconds >= MissionFailTime)
	{
		MissionFailTime = 0;
		CoopRestartLevel();
	}
}

/*
 * RAS_04A, RAS_04B: a landing dispenser crushes the player under it with ACTION_HurtActor on the tag PlayerCommando, which only the host has: a
 * client under it killed the host wherever he was. The players inside the trigger of the condition before the action are hurt instead.
 * Returns true if the action is done. Known limitation: the condition toggles with every player, with two players inside it is false.
 */
function bool HurtPlayersInTrigger(ScriptedController C, ACTION_HurtActor Action)
{
	local Trigger T;
	local Actor A;
	local name ConditionTag;
	local int i;

	if(Action.TargetTag != 'PlayerCommando' || CountClients() == 0 || C.SequenceScript == None)
		return false;

	for(i = C.ActionNum - 1; i >= 0 && ConditionTag == ''; i = i - 1)
	{
		if(ACTION_IfCondition(C.SequenceScript.Actions[i]) != None)
			ConditionTag = ACTION_IfCondition(C.SequenceScript.Actions[i]).TriggeredConditionTag;
	}

	if(ConditionTag == '')
		return false;

	Log("CoopGame: " $ C.SequenceScript $ " hurts the players inside the trigger of " $ ConditionTag);

	foreach AllActors(class'Trigger', T)
	{
		if(T.Event != ConditionTag)
			continue;

		foreach T.TouchingActors(class'Actor', A)
		{
			if(Pawn(A) != None && CoopPlayer(Pawn(A).Controller) != None)
			{
				Log("CoopGame: " $ Action.Type $ " for " $ Pawn(A).Controller.PlayerReplicationInfo.PlayerName $ " inside " $ T);
				A.TakeDamage(Action.Amount * 10, None, vect(0,0,0), Action.Momentum, Action.Type);
			}
		}
	}

	return true;
}

// A script adds a member back that a client plays. Until the next DetachClientMembers the squad AI would treat it as a bot, which crashed the host (GEO_04A)
function bool IsClientMember(name MemberTag)
{
	local Pawn P;

	foreach AllActors(class'Pawn', P, MemberTag)
	{
		if(CoopPlayer(P.Controller) != None && !IsHost(P.Controller))
			return true;
	}

	return false;
}

// See CheckMissedEvents
function RememberFiredEvent(name EventName)
{
	local int n;

	n = FiredEvents.Length;
	FiredEvents.Length = n + 1;
	FiredEvents[n].Event = EventName;
	FiredEvents[n].Time = Level.TimeSeconds;
}

/*
 * A once-only trigger can't send its event twice, so a script that starts waiting for it later waits forever. In the single player
 * game the briefing holds the only player until the script waits, clients aren't held (YYY_04F: a client reaches Trigger19 in 8 seconds,
 * the script waits for Music_start after 15, the charge never comes up). Reusable triggers are left out: a player can fire them again.
 */
function ListenForMissableEvents()
{
	local ScriptedSequence Script;
	local ACTION_WaitForEvent Wait;
	local Trigger T;
	local int i;

	if(bListenedForMissable)
		return;

	bListenedForMissable = true;

	foreach AllActors(class'ScriptedSequence', Script)
	{
		for(i = 0; i < Script.Actions.Length; i = i + 1)
		{
			Wait = ACTION_WaitForEvent(Script.Actions[i]);

			if(Wait == None || Wait.ExternalEvent == '')
				continue;

			foreach AllActors(class'Trigger', T)
			{
				if(T.Event == Wait.ExternalEvent && T.bTriggerOnceOnly)
				{
					MissableEvents[MissableEvents.Length] = T.Event;
					ListenForEvent(T.Event);
					break;
				}
			}
		}
	}
}

// See ListenForMissableEvents. Alone the host is held by the briefing as in the single player game, nothing changes for him
function RememberMissableEvent(name EventName)
{
	local int i;

	if(CountClients() == 0)
		return;

	for(i = 0; i < MissableEvents.Length; i = i + 1)
	{
		if(MissableEvents[i] == EventName)
		{
			RememberFiredEvent(EventName);
			return;
		}
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
	local int i, j;
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
					RememberFiredEvent(ACTION_TriggerEvent(Seq.Actions[j]).Event);
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

	if(SC == None || SC.SequenceScript == None)
		return;

	// While the level waits for the clients the script hasn't started, it would stand on its first wait (YYY_06D: Sev's turret)
	if(!SC.IsInState('Scripting'))
	{
		if(bWaitingForClients)
			DeferFromFirstWait(P, SC);

		return;
	}

	if(SC.ActionNum < SC.SequenceScript.Actions.Length && ACTION_WaitForEvent(SC.SequenceScript.Actions[SC.ActionNum]) != None)
	{
		DeferSkippedTriggers(P, SC, SC.ActionNum);
		return;
	}

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
 * A script dropped while it waits for an event: the events it would trigger once that event comes are triggered when the event is
 * heard (RAS_01B: Sev, held by the slaver, waits for LookAtMe and then triggers HandOff and convpart2, which the door and the rest of
 * the level wait for; the client took Sev over and the level stopped). A member that would man a turret counts too: the turret's
 * ControlEvent is what the level waits for (YYY_06D: the doors past the three turrets), the turret itself stays empty.
 */
function DeferSkippedTriggers(Pawn P, ScriptedController SC, int WaitIndex)
{
	local ScriptedAction Action;
	local name WaitEvent, FireEvent, LastPoint;
	local int i, n;

	WaitEvent = ACTION_WaitForEvent(SC.SequenceScript.Actions[WaitIndex]).ExternalEvent;

	if(WaitEvent == '')
		return;

	for(i = WaitIndex + 1; i < SC.SequenceScript.Actions.Length; i = i + 1)
	{
		Action = SC.SequenceScript.Actions[i];

		if(Action == None)
			continue;

		if(IsScriptStop(Action))
			break;

		FireEvent = '';

		if(ACTION_MoveToPoint(Action) != None)
			LastPoint = ACTION_MoveToPoint(Action).DestinationTag;
		else if(ACTION_TriggerEvent(Action) != None)
			FireEvent = ACTION_TriggerEvent(Action).Event;
		else if(ACTION_AttachToTurret(Action) != None && ACTION_AttachToTurret(Action).Attach)
			FireEvent = TurretControlEvent(ACTION_AttachToTurret(Action).DestinationTag, LastPoint);

		if(FireEvent == '')
			continue;

		n = DeferredFires.Length;
		DeferredEvents[n] = WaitEvent;
		DeferredFires[n] = FireEvent;
		DeferredPawns[n] = P;
		ListenForEvent(WaitEvent);
		Log("CoopGame: script of " $ P $ " dropped while waiting for " $ WaitEvent $ ", triggering " $ FireEvent $ " when it comes");
	}
}

// See RunSkippedActions: the wait a script that hasn't started yet will stand on
function DeferFromFirstWait(Pawn P, ScriptedController SC)
{
	local ScriptedAction Action;
	local int i;

	for(i = SC.ActionNum; i < SC.SequenceScript.Actions.Length; i = i + 1)
	{
		Action = SC.SequenceScript.Actions[i];

		if(Action == None)
			continue;

		if(ACTION_WaitForEvent(Action) != None)
		{
			DeferSkippedTriggers(P, SC, i);
			return;
		}

		if(IsScriptStop(Action))
			return;
	}
}

// Actions after which it isn't known what a dropped script would have done next
function bool IsScriptStop(ScriptedAction Action)
{
	return Action.IsA('ACTION_WaitForEvent') || Action.IsA('ACTION_WaitForPlayer') || Action.IsA('ACTION_GotoAction') || Action.IsA('ACTION_GotoLabel') ||
	       Action.IsA('ACTION_IfCondition') || Action.IsA('ACTION_IfRandomPct') || Action.IsA('ACTION_EndSection') || Action.IsA('ACTION_ChangeScript');
}

// Several turrets can share a tag (YYY_06D: WookieeCannon1), the member takes the one next to the point it walks to
function name TurretControlEvent(name TurretTag, name PointTag)
{
	local Turret T, Best;
	local Actor Point;

	foreach AllActors(class'Actor', Point, PointTag)
		break;

	foreach AllActors(class'Turret', T, TurretTag)
	{
		if(Best == None || (Point != None && VSize(T.Location - Point.Location) < VSize(Best.Location - Point.Location)))
			Best = T;
	}

	if(Best == None)
		return '';

	return Best.ControlEvent;
}

// See DeferSkippedTriggers, called by EventHeard. Scripts may only start waiting for these right after this call (RAS_01B: HandOff is
// triggered inside the action that comes just before the wait), CheckMissedEvents passes them on then
function RunDeferredTriggers(name EventName)
{
	local int i;
	local name FireEvent;
	local Pawn P;

	for(i = 0; i < DeferredFires.Length; i = i + 1)
	{
		if(DeferredEvents[i] != EventName)
			continue;

		FireEvent = DeferredFires[i];
		P = DeferredPawns[i];
		DeferredEvents.Remove(i, 1);
		DeferredFires.Remove(i, 1);
		DeferredPawns.Remove(i, 1);
		i = i - 1;
		Log("CoopGame: " $ EventName $ " came, triggering " $ FireEvent $ " for the dropped script of " $ P);
		RememberFiredEvent(FireEvent);
		TriggerEvent(FireEvent, self, P);
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

				if(CP != None && !IsHost(CP) && CoopCommando(CP.Pawn) != None && CP.WatchedMember == None && IsFreeForMember(CP) &&
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

/*
 * Test: ?CoopTestOrder=<F1|F2|F3|F4|none> on GEO_01C: the host gives this squad command after Sev's scene, then presses Use on the snipe marker
 * when the level enables it, the way a player does. Logs Sev every second, "CoopTest: order".
 */
function CheckTestSnipeOrder()
{
	local string Order;
	local CoopPlayer Host;
	local SquadMarker M, Breach;
	local Pawn P, Sev;
	local rotator R;

	Order = ParseOption(TestOptions, "CoopTestOrder");

	if(Order == "" || SevIntro.IsRunning() || LevelStartTime <= 0 || Level.TimeSeconds < NextTestOrderStep)
		return;

	NextTestOrderStep = Level.TimeSeconds + 1;
	Host = CoopPlayer(GetHost());

	if(Host == None || Host.Pawn == None)
		return;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.IsA('Commando07Delta'))
			Sev = P;
	}

	foreach AllActors(class'SquadMarker', M)
	{
		if(M.Tag == 'BalconyMarkerSnipe')
			break;
	}

	// ?CoopTestStuckMarker=1: the door breach marker with the AI members on it, put into the stuck state (see CheckStuckBreachMarkers)
	if(ParseOption(TestOptions, "CoopTestStuckMarker") != "")
	{
		foreach AllActors(class'SquadMarker', Breach)
		{
			if(Breach.IsA('MarkerDoorBreach') && Breach.Anchor != None)
				break;
		}

		if(TestOrderTime == 0)
		{
			TestOrderTime = Level.TimeSeconds;
			Log("CoopTest: order: stuck marker, ExecuteMarker=" $ Breach.ExecuteMarker(Host.Pawn) $ " active=" $ Breach.bMarkerActive);
			Breach.bComplete = true;
			Breach.GotoState('Executed');
		}

		if(Level.TimeSeconds - TestOrderTime < 12)
			Log("CoopTest: order: stuck marker state=" $ Breach.GetStateName() $ " active=" $ Breach.bMarkerActive $ " Sev marker=" $ Sev.SquadMarker $ " usability=" $ Breach.GetMarkerUsability(Host.Pawn));

		return;
	}

	// ?CoopTestBreachFirst=1: the door breach of the level first, everybody moved to the door
	if(TestOrderStage == 0 && !bTestBreachDone && ParseOption(TestOptions, "CoopTestBreachFirst") != "" && Host.IsInState('PlayerWalking'))
	{
		foreach AllActors(class'SquadMarker', Breach)
		{
			if(Breach.IsA('MarkerDoorBreach') && Breach.Anchor != None && Breach.Anchor.Tag == 'BreachDoorSunFac')
				break;
		}

		if(Breach != None && GatherMarker == None && BreachMarker == None && !bTestBreachOrdered)
		{
			bTestBreachOrdered = true;
			R = rotator(Host.Location - Breach.Anchor.Location);
			Host.Pawn.SetLocation(Breach.Anchor.Location + vector(R) * 150 + vect(0,0,-40));

			foreach DynamicActors(class'Pawn', P)
			{
				if(P.IsA('CloneCommando') && P != Host.Pawn)
					P.SetLocation(Breach.Anchor.Location + vector(R) * 260 + vect(0,0,-40));
			}

			Log("CoopTest: order: breach ordered, handled=" $ OrderDoorBreach(Host, Breach, false));
			return;
		}

		if(bTestBreachOrdered && Breach.Anchor != None && !Breach.Anchor.IsInState('Locked') && !Breach.Anchor.IsInState('ChargeLocked') && BreachMarker == None)
		{
			bTestBreachDone = true;
			NextTestCause = Level.TimeSeconds - LevelStartTime + 5;
			TestCauses = "ActivateShield";
			Log("CoopTest: order: door open, active=" $ Breach.bMarkerActive $ " complete=" $ Breach.bComplete);
		}

		return;
	}

	if(TestOrderStage == 0 && Host.IsInState('PlayerWalking'))
	{
		TestOrderStage = 1;
		Log("CoopTest: order: squad command " $ Order);

		if(Order ~= "F1")
			Host.SetStanceOffensive();
		else if(Order ~= "F2")
			Host.SetStanceDefensive();
		else if(Order ~= "F3")
			Host.SquadEngage();
		else if(Order ~= "F4")
			Host.CancelAllMarkers();
	}
	else if(TestOrderStage == 1 && M != None && M.IsInState('Enabled') && M.AlwaysVisible && Host.Pawn != None && Host.IsInState('PlayerWalking'))
	{
		TestOrderStage = 2;
		TestOrderTime = Level.TimeSeconds;
		Host.TargetMarker = M;
		Host.TargetType = TGT_Marker;
		Host.Use();
		Log("CoopTest: order: pressed Use on " $ M $ " active=" $ M.bMarkerActive $ " Sev=" $ Sev $ " Squad=" $ Sev.Squad $ " leader=" $ Sev.Squad.SquadLeader);
	}

	if(TestOrderStage > 0 && Sev != None && M != None && Level.TimeSeconds - TestOrderTime < 40)
		Log("CoopTest: order: stage " $ TestOrderStage $ " Sev dist " $ int(VSize(Sev.Location - M.Anchor.Location)) $ " Marker=" $ Sev.SquadMarker $ " active=" $ M.bMarkerActive $ " underway=" $ WasHeard(M.EventUnderway) $ " Controller=" $ Sev.Controller.GetStateName() $ " action=" $ ScriptedController(Sev.Controller).ActionNum $ " stance=" $ Sev.Squad.Stance $ " host target=" $ Host.TargetType);
}

// Test: ?CoopTestCause=<event>,<event>... triggers the events of a scene, one every CoopTestCauseEvery seconds, the first after that time
function CheckTestCauses()
{
	local string Event;
	local Actor A;
	local int i;

	if(TestCauses == "" || LevelStartTime <= 0 || Level.TimeSeconds - LevelStartTime < NextTestCause)
		return;

	NextTestCause += float(ParseOption(TestOptions, "CoopTestCauseEvery"));
	i = InStr(TestCauses, ",");

	if(i == -1)
	{
		Event = TestCauses;
		TestCauses = "";
	}
	else
	{
		Event = Left(TestCauses, i);
		TestCauses = Mid(TestCauses, i + 1);
	}

	Log("CoopTest: cause " $ Event);
	foreach AllActors(class'Actor', A)
	{
		if(string(A.Tag) ~= Event)
			A.Trigger(self, GetHost().Pawn);
	}
}

// See SpawnClient: the script of the member still has to add it to the squad
function bool JoinsLater(Pawn P)
{
	local ScriptedController SC;
	local ACTION_ChangeSquadMember Change;
	local int i;

	SC = ScriptedController(P.Controller);

	// Not the state: while the level waits for the clients the script hasn't started yet
	if(SC == None || SC.SequenceScript == None)
		return false;

	for(i = SC.ActionNum; i < SC.SequenceScript.Actions.Length; ++i)
	{
		Change = ACTION_ChangeSquadMember(SC.SequenceScript.Actions[i]);

		if(Change != None && Change.bAddMember && Change.MemberTag == P.Tag)
			return true;
	}

	return false;
}

/*
 * See SpawnClient: a captive that a script takes out of the squad as soon as the level starts (RAS_02C: Sev, RAS_02D: Scorch). During
 * the pause before the start he is still in the squad, a client that took him would sit in the cell and his scene would be lost, and
 * with it the revive the exit door needs. After the pause he isn't in the squad any more; he is taken over when he joins again.
 */
function bool IsCaptiveAtStart(Pawn P)
{
	local ScriptedSequence Script;
	local ACTION_ChangeSquadMember Change;
	local ACTION_WaitForEvent Wait;
	local int i;

	if(!bWaitingForClients)
		return false;

	foreach AllActors(class'ScriptedSequence', Script)
	{
		for(i = 0; i < Script.Actions.Length; i = i + 1)
		{
			Change = ACTION_ChangeSquadMember(Script.Actions[i]);

			if(Change != None && !Change.bAddMember && Change.MemberTag == P.Tag)
				return true;

			Wait = ACTION_WaitForEvent(Script.Actions[i]);

			// Only the wait for the start of the level comes before it (YYY_06D: the members leave the squad much later)
			if(Wait != None && (i > 0 || !IsLevelStartEvent(Wait.ExternalEvent)))
				break;
		}
	}

	return false;
}

function bool IsLevelStartEvent(name EventName)
{
	local PlayerStart Start;

	foreach AllActors(class'PlayerStart', Start)
	{
		if(EventName != '' && Start.Event == EventName)
			return true;
	}

	return false;
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

// See CheckSquadTakeover: the client of the member (or the closest one without a member) watches its joining scene
function StartJoinWatch(Pawn P)
{
	local Controller C;
	local CoopPlayer CP, Best;

	Best = CoopPlayer(FindAssignedPlayer(P));

	if(Best == None)
	{
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			CP = CoopPlayer(C);

			if(CP != None && !IsHost(CP) && CoopCommando(CP.Pawn) != None && CP.Pawn.Health > 0 && !CP.Pawn.bIncapacitated &&
			   CP.WatchedMember == None && IsFreeForMember(CP) && (Best == None || VSize(CP.Pawn.Location - P.Location) < VSize(Best.Pawn.Location - P.Location)))
				Best = CP;
		}

		if(Best == None)
			return;

		SetAssignment(Best, string(P.Class));
	}

	if(CoopCommando(Best.Pawn) == None || Best.IsInState('CoopWatching') || Best.bIntroWatch || Best.bInBreach || Best.Pawn.Health <= 0 || Best.Pawn.bIncapacitated)
		return;

	Log("CoopGame: " $ Best.PlayerReplicationInfo.PlayerName $ " watches " $ P $ " join the squad during its script (" $ TestActionString(P) $ ")");
	StartWatching(Best, P, true);
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
		// A member that joins the squad in the middle of an animation of its script (GEO_05B: Sev with the droidekas, a script of
		// the level adds him): the camera of its client flies to it and watches the rest, the takeover comes when it's over
		if(P != Host.Pawn && P.IsA('CloneCommando') && P.Squad != None && P.Squad == Host.Pawn.Squad && P.Health > 0 && !P.bIncapacitated &&
		   P.Controller != None && PlayerController(P.Controller) == None && !P.bHidden && IsScriptBusy(P) && FindWatcher(P) == None && !IsSceneOnlyMember(P))
		{
			StartJoinWatch(P);
			continue;
		}

		if(!CanBeTakenOver(P, Host.Pawn))
			continue;

		// Still in the squad until its script starts, it joins in its scene (GEO_01B: Fixer, see SpawnClient)
		if(JoinsLater(P) && !SevIntro.IsSev(P))
			continue;

		// A client that already played this squad member gets it back right away, wherever it is
		C = FindAssignedPlayer(P);

		if(C != None)
		{
			if(CoopPlayer(C).bIntroWatch || CoopPlayer(C).bInBreach)
				continue;

			if(CoopCommando(C.Pawn) != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated)
			{
				// A member with an entrance still to play (GEO_01C: the rope) is watched first. A client that played the member
				// before but has its own commando now (GEO_05B: the squad joins again) sees its camera fly to it, unless it already
				// watches it
				if(!StartIntroWatch(CoopPlayer(C), P))
					TakeOver(CoopPlayer(C), P, !C.IsInState('CoopWatching'));

				return;
			}

			continue; // Reserved for that client
		}

		// Otherwise the closest client without a squad member, wherever it is (GEO_01C: a client that spawned on the balcony can't
		// follow the host down the rope to Scorch). The camera flies to the squad member. A client whose member isn't in this level
		// at all counts as free and plays this one from now on (session 2026-10-31: Client1 played Sev, the game was started on
		// GEO_01B, where Sev isn't, and the client took nobody). With a fixed squad (CoopTest.bat) a client only plays its own member.
		Best = None;

		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && CoopCommando(C.Pawn) != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated &&
			   IsFreeForMember(PlayerController(C)) && (Best == None || VSize(C.Pawn.Location - P.Location) < VSize(Best.Pawn.Location - P.Location)))
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

	if(Marker.IsA('MarkerDemolition') || Marker.IsA('MarkerDoorBreach') || Marker.IsA('MarkerSetProximityMine'))
		return "CTCharacters.Commando62Delta";

	if(Marker.IsA('MarkerHackDoor') || Marker.IsA('MarkerHackTerminal') || Marker.IsA('MarkerDisarmTrap'))
		return "CTCharacters.Commando40Delta";

	if(Marker.IsA('MarkerSnipe'))
		return "CTCharacters.Commando07Delta";

	return "";
}

/*
 * What a player playing a Delta squad member may do himself, by its specialty (same split as MarkerSpecialist). Scorch could hack
 * consoles, Fixer could blow doors (session 2026-10-31). The host (the squad leader) and players without a squad member may do
 * everything, the AI is not limited. Bacta dispensers and the plunger of a placed charge are for everybody.
 */
static function bool MemberCanUse(Pawn P, ActivateItem Item)
{
	local string MemberClass;

	if(P == None || Item == None || PlayerController(P.Controller) == None)
		return true;

	MemberClass = string(P.Class);

	if(InStr(MemberClass, "Delta") == -1)
		return true;

	switch(Item.ActivateItemType)
	{
	case AIT_Demolition:
	case AIT_BreachDoor:
	case AIT_ProximityMine:
	case AIT_SetTrap:
		return MemberClass ~= "CTCharacters.Commando62Delta";
	case AIT_HackTerminal:
	case AIT_HackDoor:
	case AIT_DisarmTrap:
		return MemberClass ~= "CTCharacters.Commando40Delta";
	}

	return true;
}

/*
 * A sniper position only a client playing Sev can take. In single player any member takes one: Sev is only preferred (PreferredPawnClass
 * weighs the distance, ASquadMarker::SortParticipants), and with the AI Sev Fixer took them too. The host's order was refused whenever a
 * client played Sev (RAS_03A, the user's game 2026-11-14; the user's decision: like single player). Kept for the client: GEO_01C's balcony,
 * where the level's scene needs Sev's own shot, and the positions the client was asked to take (CheckClientSnipers).
 */
function bool SnipeNeedsClient(SquadMarker M)
{
	local int i;

	if(M == None || M.Tag == 'BalconyMarkerSnipe')
		return true;

	for(i = 0; i < ClientSnipeMarkers.Length; i = i + 1)
	{
		if(ClientSnipeMarkers[i] == M)
			return true;
	}

	return false;
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

/*
 * A client without a squad member may get a new one: when it never played one, or when the one it played isn't in this level
 * (session 2026-10-31, GEO_01B without Sev). With a fixed squad (CoopTest.bat) only a client that never played one.
 */
function bool IsFreeForMember(PlayerController PC)
{
	if(class'CoopConfig'.default.bFixedSquad)
		return GetAssignedClass(PC) == "";

	return !IsAssignedMemberInLevel(PC);
}

// The client has a squad member it played before and that member is somewhere in this level, alive
function bool IsAssignedMemberInLevel(PlayerController PC)
{
	local string MemberClass;
	local Pawn P;

	MemberClass = GetAssignedClass(PC);

	if(MemberClass == "")
		return false;

	foreach DynamicActors(class'Pawn', P)
	{
		if(string(P.Class) ~= MemberClass && P.Health > 0)
			return true;
	}

	return false;
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
		if(string(P.Class) ~= MemberClass && P.Health > 0 && PlayerController(P.Controller) == None && P.Squad == Host.Pawn.Squad && !IsSceneOnlyMember(P))
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

	RetireAI(OldAI, P);

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
	CP.ClientCoopWeaponsQuiet(true, None);

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

	GiveHostWeapons(P);

	if(P.Inventory != None)
		P.Inventory.OwnerEvent('LoadOut');

	EquipQuietly(CP, P);

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
			bQuietLeave = true;

			// A squad member the client played goes back to its AI, the client gets it again when it is back (CheckSquadTakeover).
			// Destroyed, the member was gone after a save was loaded (test lobbyslot, 2026-11-11)
			if(C.Pawn != None && CoopCommando(C.Pawn) == None && C.Pawn.ControllerClass != None && C.Pawn.Health > 0)
				ReturnToAI(C);
			else if(C.Pawn != None)
				C.Pawn.Destroy();

			C.Destroy();
			bQuietLeave = false;
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

	// The native lookup knows "Name" and "Name.ctm" but not "Name.ctm#Portal" (YYY_06C sent everybody to the prologue)
	i = InStr(Map, "#");

	if(i != -1)
		Map = Left(Map, i);

	if(InStr(Caps(Map), "BRIEFING") == -1)
		return URL;

	Host = GetHost();

	// GetNextLevel(-1) gives the first level of the campaign
	if(Host == None || Host.GetLevelIndex(Map) == -1)
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

/*
 * The squad member of a client is saved under its address and name. Through the Steam relay every client has the address 127.0.0.1:
 * two players with the same name shared one entry and one of them lost its member (test: lobby through the relay). The client keeps the
 * new name in its URL, so it comes back with it after a level change.
 */
function MakeNameUnique(PlayerController PC)
{
	local Controller C;
	local string Base, NewName;
	local int n;
	local bool bTaken;

	if(PC.PlayerReplicationInfo == None)
		return;

	Base = PC.PlayerReplicationInfo.PlayerName;
	NewName = Base;
	n = 1;

	do
	{
		bTaken = false;

		// Not the controllers of a loaded save that have no connection: AfterSaveLoaded removes them only on its first timer, a client
		// logging in before that was renamed (YYY_01C checkpoint, <name> -> <name>_2) and refused at the next level (PreLogin, the user's game 2026-11-14)
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(C != PC && PlayerController(C) != None && PlayerController(C).Player != None && C.PlayerReplicationInfo != None && C.PlayerReplicationInfo.PlayerName ~= NewName)
				bTaken = true;
		}

		if(bTaken)
			NewName = Base $ "_" $ string(++n);
	}
	until(!bTaken || n > 8);

	if(NewName == Base)
		return;

	Log("CoopGame: the name " $ Base $ " is taken, this player is " $ NewName);
	PC.PlayerReplicationInfo.SetPlayerName(NewName);

	if(CoopPlayer(PC) != None)
		CoopPlayer(PC).ClientCoopKeepName(NewName);
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
	local Controller C;
	local int n;

	// A client that sees the level but has no pawn yet (GEO_05B: no room to spawn it around the host in the lift, the lift isn't known as
	// its base while paused) only gets one when the game runs: spawning is retried by the timer, which is paused too. It looked like the
	// game had hung for the whole of MaxClientWait (session 2026-11-01).
	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && CoopPlayer(C).bCoopReady)
			++n;
	}

	if(n < class'CoopConfig'.default.TravelClients)
		ClientsReadyTime = 0;
	else if(ClientsReadyTime == 0)
		ClientsReadyTime = class'CoopNative'.static.GetRealTime();
	else if(class'CoopNative'.static.GetRealTime() - ClientsReadyTime >= 3)
	{
		Log("CoopGame: all clients are ready, some have no pawn yet, starting the level to spawn them");
		StopWaitingForClients();
		return;
	}

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
	// get the member only now, all clients only now get the commandos of a scene at the start (GEO_01C, the ropes: half of it was
	// over). The level runs 10 times slower until their cameras are on it and they have the commandos (CheckSlowStart), at most 4
	// seconds. Not slower: replication goes by the level's time too.
	if(CountClients() > 0)
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
	local Pawn P;
	local int Waiting, Commandos;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.IsA('CloneCommando') && P.Health > 0 && P.bAlwaysRelevant)
			++Commandos;
	}

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && CoopPlayer(C).bIntroWatch && !CoopPlayer(C).bWatchCameraOn)
			++Waiting;

		if(CoopPlayer(C) != None && !IsHost(C) && !CoopPlayer(C).bCommandosHere)
		{
			++Waiting;
			CoopPlayer(C).ClientCoopCheckCommandos(Commandos);
		}
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

// LOAD CHECKPOINT of the host's pause menu (CoopPauseMenu): back to the last checkpoint without a reload, the beginning of the level without one
function CoopLoadCheckpoint()
{
	if(LoadSavedCheckpoint() || CheckpointReturn.Load())
		return;

	Log("CoopGame: load checkpoint: no checkpoint to go back to, restarting the level");
	CoopRestartLevel();
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
	local string ClientURL, S, Map;

	ClientURL = ExpandRelativeURL(URL);

	// The host loads a save (LoadSavedCheckpoint), the clients the clean map: the save is only on the host, the state comes by replication
	// Only the game type: with ?listen a client tried to listen itself and crashed in LoadMap (test 2026-11-10)
	if(InStr(Caps(URL), "LOAD=") != -1 && GetHost() != None)
	{
		// A slot loaded from the lobby is another map than this one
		Map = class'CoopConfig'.default.LoadingSaveMap;

		if(Map == "")
			GetHost().GetCurrentMapName(Map);

		ClientURL = Map $ "?game=" $ GAME_CLASS $ "?MaxPlayers=" $ MaxPlayers;
	}

	ClientURL = ClientURL $ ConsoleCommand("XLIVE CLIENT_TRAVEL");

	bTravelling = true;

	// Who comes along: their leaving here and arriving there aren't announced (IsQuietArrival)
	class'CoopConfig'.default.TravelPlayers = "|";

	foreach DynamicActors(class'PlayerController', P)
	{
		if(P.PlayerReplicationInfo != None)
			class'CoopConfig'.default.TravelPlayers = class'CoopConfig'.default.TravelPlayers $ class'CoopSaveSlots'.static.CleanName(P.PlayerReplicationInfo.PlayerName) $ "|";
	}

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

			if(CoopPlayer(P) != None)
				CoopPlayer(P).ClientCoopPrepareTravel(TravelMapName(ClientURL));

			P.ClientTravel(S, TRAVEL_Relative, false);
		}
		else
		{
			LocalPlayer = P;
			P.PreClientTravel();
		}
	}

	// The engine waits 4 s here for the clients to get the travel. It only makes them wait longer for a host that hasn't started loading
	Level.NextSwitchCountdown = class'CoopConfig'.default.TravelSwitchDelay;
	Log("CoopGame: the level switches in " $ Level.NextSwitchCountdown $ " s");

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
