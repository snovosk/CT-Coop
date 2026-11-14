class CoopPlayer extends CTPlayer;

#exec OBJ LOAD FILE="CTGame.u"
#exec OBJ LOAD FILE="CTCharacters.u"

/*
 * CoopPlayer
 * Player controller for coop games. The host (the player sitting in front of the listen server) behaves like in single player.
 * Clients control a CoopCommando that is not part of the squad, respawn next to the host and never load save games themselves.
 */

var float IncapacitatedTime; // Server only: Level.TimeSeconds when the client pawn got incapacitated, zero if not incapacitated
var float DeadTime;          // Server only: Level.TimeSeconds when the client died, zero if alive
var float NextDebugLogTime;
var float FarFromHostTime;   // Server only: Level.TimeSeconds since when the client is too far away from the host
var float LastTeleportRequest;
var float SpawnWaitStart;    // Server only: Level.TimeSeconds when the client started waiting for the host to be free
var Actor       SentTarget;     // Client only: last target sent to the server
var ETargetType SentTargetType;
var Material    HostSkin;       // Skin of the host's pawn as seen by clients (see ApplyHostSkin)
var float       NextHostSkinCheck;
var int         DisplaySyncIndex;  // Server only: see CoopGame.SendMapActorDisplay
var float       DisplaySyncStart;      // Server only: when the map actors are sent (see CoopGame.SendMapActorDisplay)
var array<int>  DisplayResend;         // Server only: indices of SyncedMapActors the client didn't have yet
var array<byte> DisplayResendCount;
var bool        bSetCoopNetSpeed;
var bool        bCoopTakeover;   // Server only: possessing a squad member (see CoopGame.TakeOver)
var bool        bCoopReady;      // Server only: the client sees the level (see ServerCoopReady)
var bool        bSentCoopReady;  // Client only
var bool        bInBreach;       // Server only: its squad member does a door breach with the AI (see CoopGame.StartAIBreach)
var bool        bWatchCameraOn;  // Server only: the client's scene camera is on the watched member (ServerCoopWatchCameraOn)
var bool        bIntroWatch;     // Server only: watching the entrance of its squad member (see CoopGame.StartIntroWatch)
var int         IntroWaitIndex;
var float       IntroWatchStart;
var vector      TakeoverFromLocation; // Client only: camera flight to a taken over squad member (see PlayerCalcView)
var rotator     TakeoverFromRotation;
var float       TakeoverStartTime;
var float       TakeoverArc;          // Height of the flight's arc; none from the scene camera into the eyes
var bool        bCoopHUDHidden, bWasHUDHidden, bWasHelmetDrawn; // See SetCoopHUDHidden
var Pawn        VisionModePawn;       // Local player: the pawn put in its default vision mode (CheckVisionMode)
var Pawn        WatchedMember;
var Pawn        WatchHiddenPawn;      // Client only: watched squad member hidden while its scene is seen through its eyes (see PlayerCalcView)
var array<Actor> WatchHiddenActors;
var vector      WatchCameraLocation;
var rotator     WatchCameraRotation;
var float       WatchCameraTime;
var array<Pawn> SnipeKeptOff;         // See KeepOthersFromSnipe
var float NextNameColorCheck;          // See CheckNameColors
var bool  bNoAccessoryFix;             // Test only: CheckAccessoryOwners off ("AccessoryFix 0")
var Actor TurretHidden;               // Client: hidden for its own view while on the turret (the walker, see ClientCoopManTurret)
var bool        bWatchFocus;          // Client only: the scene camera looks at WatchFocus (a door breach)
var vector      WatchFocus;
var Pawn        WatchCameraPawn;      // Client only: squad member whose scene the camera shows (see CalcWatchView)
var float       NextWatchLog;
var vector      ServerBlockLocation;  // Server only: see CoopGame.CheckClientsBlocked
var float       NextServerBlockLog;
var Pawn        EyeFixedPawn;
var float       NextStatusLog;        // Client only: see LogClientStatus         // Client only: see FixEyeHeight
var float       TakeoverTime;    // Server only: Level.TimeSeconds of the last takeover (see CoopGame.TakeOver)
// See SmoothProxies
struct SmoothedPawn
{
	var Pawn P;
	var vector LastLocation;
	var vector LastVelocity;
	var vector Offset;
	var vector BasePrePivot;
	var vector UpdateLocation;  // Where the last update without a velocity put it
	var float UpdateTime;
	var float ChaseSpeed;       // Speed that brings the mesh there by the time the next update comes
};
var array<SmoothedPawn> SmoothedPawns;
var vector      BlockCheckLocation;   // Client only: see CheckBlocked
var float       BlockCheckTime;
var float       NextBlockLog;
var float       NextCorrectionLog;
var float       NextCameraLog;
var float       LastOnCarTime;        // Server, see CoopGame.StaysOnCar
var float       UsingItemStart;       // See LongClientAdjustPosition
const USE_CORRECTION_GRACE = 1.0;
const TURRET_USE_RANGE = 260.0;
const TURRET_USE_AIM = 0.6;
var float       HandSignalActiveTime; // Client only: see FixHandSignalWeapon
var float       HandSignalIdleTime;   // Client only: see FixHandSignalWeapon
var bool        bPlayedHandSignalAnim;
var Actor       ClientAttachItem;     // Client only: item in the hand during a hand signal (see SetupClientHandSignal)
var ActivateItem PendingDetonation;   // Server only: charge a client detonates when its hand animation is done (CoopGame.Tick)
var float       DetonationTime;   // Server only: squad member whose scene this client watches before playing it (see CoopGame.CheckSceneWatch)
var float WeaponProblemTime, NextWeaponProblemLog; // See CheckWeaponShown
var bool  bTestLagSent;                         // Server only: see ClientCoopTestLag
var float NoWeaponTime;                           // See FixMissingWeapon
var Pawn  ViewLoggedPawn;                         // See LogNewPawnView
var float ViewLogTime;
var array<Pawn> SquadIconMembers;     // Client only: see ClientCoopSetSquadState
var array<int>  SquadIconStates;      // Order icon and marker state of SquadIconMembers, see CoopGame.GetSquadIconState
var float       WeaponDownTime; // Client only: Level.TimeSeconds since when the weapon is down without being changed
var float       StuckFireTime;  // Client only: see FixStuckFire
var float       ServerStuckFireStart; // Server only: see CoopGame.CheckServerStuckFire
var int         TurretYaw, TurretPitch;     // Client: the aim of the turret it mans (see state PlayerManningTurret)
var Pawn        TurretPawn;               // Client: the pawn that manned the turret (see CheckTurretPawn)
var int         SentTurretYaw, SentTurretPitch;
var float       NextTurretSend, NextTurretLog;
var string      LastWeaponTrace;
var int         LobbyMember;               // Server: the member picked in the lobby (1-3, see CoopLobby)
var bool        bLobbyReady;               // Server: see CoopLobby
var string      LobbyState;                // Client: see CoopLobby.StateString
var bool        bCommandosHere;            // Server: see ClientCoopCheckCommandos
var bool        bWatchedOnRope;            // Server: the member this client watches is on a rope (CoopGame.CheckRopeLandings)
var bool        bTestNetJump;              // Test only: see TestNetJump
var array<Pawn>  JumpPawns;
var array<vector> JumpLocs;
var array<int>   JumpFrames, JumpMoved, JumpOver;
var array<float> JumpMax, JumpSum;
var float       NextJumpLog;
var vector      JumpCamera;
var float       JumpCameraMax;
var Weapon      ServerHands;               // See ParkServerHands
var MarkerIconActor WatchIcon;              // Test only: see the client command WatchIcon
var bool        bIconWatchHidden;
var float       WatchAlpha;
var bool        bSwitchWeaponCall;         // A weapon key (SwitchWeapon) is being handled, see ForceWeaponSwitch
var Weapon      LastHeldWeapon;            // Client: the rifle or pistol held before the hands, see FixHandSignalWeapon
var CoopAnimController AnimController;     // Client: see ClientCoopScriptAnim
var int         LastCommandoCount;          // Client: see LogCommandos
var bool        bLiftView;                  // Riding a lift: the camera over the shoulder looks at the center of the car (ClientCoopLiftView)
var vector      LiftCenter;
var bool        bLiftHoldSet;               // Host: see HoldHostLiftRotation
var bool        bBlendToEyes;               // See ClientCoopLiftView
var bool        bQuietWeaponSet, bQuietEnding; // Client: see ClientCoopWeaponsQuiet
var class<Weapon> QuietWeaponClass;
var float       QuietWeaponEnd;
var ScriptedController LocalActionController; // Client: runs the host's script actions (see CoopActionForward)
var bool        bMusicSent;    // Server: the music of the level was sent after joining (see CoopGame.SendLastMusic)
var float       LoginTime;     // Server: when the client logged in to this level (see CoopGame.PostLogin)
var bool        bTriggersSent; // Server: the emitters triggered before joining were triggered (see CoopGame.SendLastTriggers)
var name        HostWaitAnim;               // Host: see SetHostWaitAnim
var bool        bHostWaitAnimSent;          // Server: the host's waiting animation was sent to this client
var float       NextHostWaitSend;           // Host: see SendHostWaitAnim
var name        ClientHostWaitAnim;         // Client: see ClientCoopHostWaitAnim
var rotator     LiftHoldRotation;
var float       LiftLookYaw, LiftLookPitch; // Looking around from there
var bool        bLiftViewSent;              // Server: ClientCoopLiftView(true) was sent
var bool        bHideRiders;                // Client: see ClientCoopHideRiders
var array<Actor> RideHiddenActors;
var bool        bHideRidersSent;            // Server: ClientCoopHideRiders(true) was sent
var bool        bWatchHidden;               // Server: own commando hidden while watching a member (see CoopGame.HideWatchingPawns)
var array<Actor> OwnHiddenActors;          // Server: see bWatchHidden
var bool        bLiftFaced;                 // Server: turned to the middle of the lift (CoopGame.FaceLiftCenter)
var bool        bSpaceWalk, bSpaceWalkDone; // Client: see ClientCoopSpaceWalkPos
var vector      SpaceWalkTarget;
var float       NextSpaceWalkLog;
var array<SquadMarker> ShownMarkers;        // Client: see ClientCoopSetMarkerShown
var array<byte> ShownMarkerValues;          // 0 hidden, 1 shown, 2 not known yet
var array<byte> ShownMarkerLogged;
var array<byte> ShownMarkerDisabled; // 1: ClientCoopSetMarkerShown put the client's copy into Disabled
var array<Actor> AmbientActors;      // See CheckAmbientSounds
var array<Sound> AmbientSounds;
var float NextAmbientCheck;
var array<SquadMarker> SentMarkers;         // Server: see CoopGame.SyncMarkerVisibility
var array<byte> SentMarkerFlags;
var bool bTrackerOverride;                  // Server: the client's tracker shows a pointer of the mod (see CoopGame.SetTrackerOverride)
var bool bSentTrackerShow;                  // Server: what the client's tracker shows, see CoopGame.SyncObjectiveTracker
var Actor SentTrackerActor;
var vector SentTrackerLocation;
const SPACE_WALK_SNAP_DISTANCE = 300.0;     // Further from the server's position than interpolation should cover
const SPACE_WALK_FOLLOW_RATE = 8.0;         // Share of the distance to the target covered per second

replication
{
	reliable if(Role == ROLE_Authority)
		ClientCoopMessage, ClientCoopPawnRevived, ClientCoopSetIncapacitated, ClientCoopSetIdleState, ClientCoopSetPanelState, ClientCoopTakeoverCamera, ClientCoopSetActorCollision;
	reliable if(Role == ROLE_Authority)
		ClientCoopDumpProps, ClientCoopObjectiveTracker, ClientCoopBlinkHUD, ClientCoopShakeView, ClientCoopScreenFade, ClientCoopCriticalMessage, ClientCoopSetObjectives, ClientCoopTestLag, ClientCoopTestCommand, ClientCoopProbe, ClientCoopSetWatchFocus, ClientCoopSetCollisionByTag, ClientCoopSetHiddenByTag, ClientCoopSetMarkerState, ClientCoopManTurret, ClientCoopLeaveTurret, ClientCoopScriptAnim, ClientCoopEndScriptAnim, ClientCoopLiftView, ClientCoopHideRiders, ClientCoopWeaponsQuiet, ClientCoopHostWaitAnim, ClientCoopEndHostWaitAnim, ClientCoopRunAction, ClientCoopTriggerActor, ClientCoopTriggerLocal, ClientCoopTriggerMaterial, ClientCoopEndSpaceWalk, ClientCoopSetMarkerShown, ClientCoopPrepareTravel, ClientCoopMoverStop;
	unreliable if(Role == ROLE_Authority)
		ClientCoopSetSquadState, ClientCoopSpawnEffect, ClientCoopSetPanelProgress, ClientCoopSetLight, ClientCoopKeepScriptAnim, ClientCoopCheckCommandos, ClientCoopSpaceWalkPos;
	reliable if(Role == ROLE_Authority)
		ClientCoopSetActorDisplay, ClientCoopSetActorLook, ClientCoopSetPanelLinks, ClientCoopSetMarkerLink, ClientCoopLobbyState, ClientCoopKeepName;
	reliable if(Role < ROLE_Authority)
		ServerTeleportToHost, ServerCoopSetTarget, ServerCoopUsingItem, ServerCoopUsePanel, ServerCoopStartHandSignal, ServerCoopReady, ServerCoopWatchCameraOn, ServerCoopUseTurret, ServerCoopMapActorMissing, ServerCoopLobbyChoose, ServerCoopLobbyReady, ServerCoopLobbyLevel, ServerCoopCommandosHere;
	unreliable if(Role < ROLE_Authority)
		ServerCoopTurretAim;
}

simulated event PostNetBeginPlay()
{
	local string ServerAddress;

	Super.PostNetBeginPlay();

	if(Level.NetMode != NM_Client)
		return;

	// Connected to a coop host: remember it so we can reconnect automatically (also works when joining from the command line)
	ServerAddress = GetServerNetworkAddress();

	if(ServerAddress != "")
		class'CoopConfig'.static.BeginSession(ServerAddress);
	else
		class'CoopConfig'.default.ReconnectAttempts = 0;

	Log("ModCoop: Joined coop host " $ ServerAddress $ ", level package " $ class'CoopNative'.static.LevelPackageText(self));
}

/*
 * Client, reliable, sent just before ClientTravel. The host refuses connections until it has loaded the level, which took 16 s from the client's
 * Browse in the logs of 2026-11-09, and a client giving up after ClientTimeout (15 s) went through the failure menu and a reconnect.
 * BeginSession restores the short timeout when the client has joined.
 */
simulated function ClientCoopPrepareTravel(string MapName)
{
	local string MenuClass, Pic, Title, Text;
	local int Hints;
	local MenuTemplate M;

	if(Level.NetMode != NM_Client)
		return;

	class'CoopConfig'.static.ApplyTravelTimeouts();
	Log("ModCoop: level change, waiting for the host up to " $ class'CoopConfig'.default.TravelConnectTimeout $ " s");

	// The host sees the engine's loading screen, the client saw its old level stand still until the host was ready (the user, 2026-11-11).
	// The same screen until the next level replaces this one
	// The engine fills the host's screen from LevelLoadingInfo.int by map name (GameEngine.InitLevelLoadingInfo): the menu class, the
	// title, a picture and text at the start of a chapter. The client's screen had no title (the user, 2026-11-14). Same table here
	MenuClass = GetLoadingMenuClass();
	FindLoadingInfo(MapName, MenuClass, Pic, Title, Text, Hints);
	ClientOpenMenu(MenuClass);

	foreach AllActors(class'MenuTemplate', M)
	{
		if(CTInfoBase(M) != None)
			CTInfoBase(M).SetInfoOptions(Pic, Title, Text, MapName, Hints != 0);
		else if(CTLoading(M) != None)
			CTLoading(M).SetInfoOptions(Pic, Title, Text, MapName, Hints != 0);
	}

	Log("ModCoop: loading screen " $ MenuClass $ " for " $ MapName $ ": '" $ Title $ "'");
}

// The entry of LevelLoadingInfo.int for a map, read the same way as GameEngine.InitLevelLoadingInfo
simulated function FindLoadingInfo(string MapName, out string MenuClass, out string Pic, out string Title, out string Text, out int Hints)
{
	local int i;
	local string Value;

	for(i = 0; i < 200; ++i)
	{
		Value = Localize("LevelLoadingInfo", "MapName[" $ i $ "]", "LevelLoadingInfo", true);

		if(Value == "")
			continue;

		if(!(Value ~= MapName))
			continue;

		Value = Localize("LevelLoadingInfo", "LoadingMenuClass[" $ i $ "]", "LevelLoadingInfo", true);

		if(Value != "")
			MenuClass = Value;

		Pic = Localize("LevelLoadingInfo", "LoadingPic[" $ i $ "]", "LevelLoadingInfo", true);
		Title = Localize("LevelLoadingInfo", "LoadingTitle[" $ i $ "]", "LevelLoadingInfo", true);
		Text = Localize("LevelLoadingInfo", "LoadingText[" $ i $ "]", "LevelLoadingInfo", true);
		Hints = int(Localize("LevelLoadingInfo", "LoadingShowHints[" $ i $ "]", "LevelLoadingInfo", true));
		return;
	}
}

// See CoopConfig.NetClientRate. The server limits it to its own setting. Not saved to the config.
simulated function SetCoopNetSpeed()
{
	local string CommandLine;
	local int Lag;

	bSetCoopNetSpeed = true;
	bDynamicNetSpeed = false;
	Log("ModCoop: Net speed " $ Player.CurrentNetSpeed $ ", requesting " $ class'CoopConfig'.default.NetClientRate);

	// SetNetSpeed is limited by MaxClientRate of the client's own net driver (10000 in System.ini)
	class'CoopNative'.static.SetNetRates(class'CoopConfig'.default.NetClientRate, class'CoopConfig'.default.NetTickRate);
	SetNetSpeed(class'CoopConfig'.default.NetClientRate);
	Log("ModCoop: Net speed is now " $ Player.CurrentNetSpeed);

	// Tests on one PC: simulate an internet connection (-CoopPktLag=<ms>)
	CommandLine = class'CoopNative'.static.GetCommandLine();

	if(InStr(Caps(CommandLine), "-COOPPKTLAG=") != -1)
	{
		Lag = int(Mid(CommandLine, InStr(Caps(CommandLine), "-COOPPKTLAG=") + 12));
		Log("ModCoop: Simulating lag " $ Lag $ ": " $ ConsoleCommand("PKTLAG " $ Lag) $ " / " $ ConsoleCommand("PKTLAGVARIANCE " $ (Lag / 3)));
	}
}

// See CoopGame.MakeMapActorsRelevant. Item is None if it does not exist on this client yet, it is sent again later.
/*
 * The squad marker of a turret the server sent (GEO_03C: the sonic turret and its MarkerTurret). The map's links point to the
 * client's own copy, deleted when the map loaded: the client's turret had no marker and the marker no anchor, the client never saw
 * that the turret can be used (session 2026-11-01). See CoopGame.SendMapActorTo.
 */
simulated function ClientCoopSetMarkerLink(int Index, Actor A, SquadMarker Marker, NavigationPoint Nav0, NavigationPoint Nav1)
{
	if(A == None)
	{
		ServerCoopMapActorMissing(Index);
		return;
	}

	if(A.Role == ROLE_Authority)
		return;

	if(Marker != None)
	{
		A.SquadMarker = Marker;
		Marker.Anchor = A;

		if(Marker.Actors.Length > 0 && Marker.Actors[0] == None)
			Marker.Actors[0] = A;
	}

	// The places to stand at the turret are links of the map too
	if(Nav0 != None && A.NavPts.Length == 0)
		A.NavPts[0] = Nav0;

	if(Nav1 != None && A.NavPts.Length == 1)
		A.NavPts[1] = Nav1;

	Log("ModCoop: " $ A $ " (" $ A.Class.Name $ ") belongs to the marker " $ Marker $ ", places " $ A.NavPts.Length);
	KeepTurretOnBase(Turret(A));
}

simulated function ClientCoopSetPanelLinks(int Index, ActivateItem Item, SquadMarker Marker, NavigationPoint Nav0, NavigationPoint Nav1, bool bUsableByPlayer)
{
	local Actor A;

	if(Item == None)
	{
		ServerCoopMapActorMissing(Index);
		return;
	}

	if(Item.Role == ROLE_Authority)
		return;

	Item.bIsUsableByPlayer = bUsableByPlayer;

	if(Marker != None)
	{
		Item.SquadMarker = Marker;
		Marker.Anchor = Item;
	}

	if(Nav0 != None && Item.NavPts.Length == 0)
		Item.NavPts[0] = Nav0;

	if(Nav1 != None && Item.NavPts.Length == 1)
		Item.NavPts[1] = Nav1;

	if(BactaDispenser(Item) != None)
	{
		for(A = Level.BactaDispenserList; A != None; A = BactaDispenser(A).NextDispenser)
		{
			if(A == Item)
				return;
		}

		BactaDispenser(Item).NextDispenser = BactaDispenser(Level.BactaDispenserList);
		Level.BactaDispenserList = Item;
	}
}

// See CoopGame.MakeMapActorsRelevant. A is None if it does not exist on this client yet, it is sent again later.
// The scale is sent as floats because replicated vectors are rounded to integers.
function ServerCoopWatchCameraOn(Pawn P)
{
	bWatchCameraOn = P != None && P == WatchedMember;
	Log("CoopGame: " $ PlayerReplicationInfo.PlayerName $ " has the scene camera on " $ P $ " (watching " $ WatchedMember $ ")");
}

function ServerCoopReady()
{
	bCoopReady = true;
	Log("CoopGame: " $ PlayerReplicationInfo.PlayerName $ " sees the level (camera on " $ ViewTarget $ ")");

	if(CoopGame(Level.Game) != None && CoopGame(Level.Game).bWaitingForClients)
		CoopGame(Level.Game).CheckClientsArrived();
}

// See CoopGame.StartAIBreach
/*
 * Every player is a normal commando, whatever Class= the player's User.ini or URL asks for. A class from another mod (FirstPersonPlayer on a
 * tester's host, session 2026-11-01) isn't in ServerPackages: a client without that mod can't load it and doesn't see the player.
 */
function SetPawnClass(string InClass)
{
	if(!(InClass ~= string(class'PlayerCommando')))
		Log("CoopPlayer: class " $ InClass $ " replaced by " $ class'PlayerCommando');

	PawnClass = class'PlayerCommando';
}

simulated function ClientCoopSetWatchFocus(vector Focus, bool bSet)
{
	WatchFocus = Focus;
	bWatchFocus = bSet;
}

// See CoopGame.ForwardSetHidden (same filter as ACTION_SetHidden)
simulated function ClientCoopSetHiddenByTag(name ActorTag, bool bHidden)
{
	local Actor A;

	if(Level.NetMode != NM_Client)
		return;

	foreach AllActors(class'Actor', A, ActorTag)
	{
		if(Controller(A) == None && A.Class.Name != 'SpawnPoint' && A.bHidden != bHidden)
			A.bHidden = bHidden;
	}
}

// See CoopGame.MakeNameUnique
simulated function ClientCoopKeepName(string NewName)
{
	UpdateURL("Name", NewName, false);
}

// See CoopLobby
simulated function ClientCoopLobbyState(string NewState)
{
	if(LobbyState != NewState)
		Log("ModCoop: lobby: " $ NewState);

	LobbyState = NewState;
}

function ServerCoopLobbyChoose(int Member)
{
	if(CoopGame(Level.Game) != None && CoopGame(Level.Game).Lobby != None)
		CoopGame(Level.Game).Lobby.Choose(self, Member);
}

function ServerCoopLobbyReady(bool bReady)
{
	if(CoopGame(Level.Game) != None && CoopGame(Level.Game).Lobby != None)
		CoopGame(Level.Game).Lobby.SetReady(self, bReady);
}

function ServerCoopLobbyLevel(string NewLevel)
{
	if(CoopGame(Level.Game) != None && CoopGame(Level.Game).Lobby != None)
		CoopGame(Level.Game).Lobby.SetLevel(self, NewLevel);
}

// See CoopGame.CheckSlowStart: the client tells the server when it has the commandos of the level
simulated function ClientCoopCheckCommandos(int Expected)
{
	local Pawn P;
	local int n;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.IsA('CloneCommando'))
			++n;
	}

	if(n >= Expected)
		ServerCoopCommandosHere();
}

function ServerCoopCommandosHere()
{
	bCommandosHere = true;
}

// See CoopGame.ForwardScriptAnim
simulated function ClientCoopScriptAnim(Pawn P, name Anim, float Rate, bool bLoop)
{
	if(Level.NetMode != NM_Client || P == None || (P.Controller != None && P.Controller != AnimController))
		return;

	if(AnimController == None)
		AnimController = Spawn(class'CoopAnimController');

	// Pawn.ChangeAnimation keeps its hands off while the controller controls the animations, like the script's on the server
	P.Controller = AnimController;

	if(Rate <= 0)
		Rate = 1.0;

	if(bLoop)
		P.LoopAnim(Anim, , Rate);
	else
		P.PlayAnim(Anim, , Rate);

	if(class'CoopConfig'.default.bDebugLog)
		Log("ModCoop: Script animation " $ Anim $ " of " $ P $ " (loop " $ bLoop $ ")");
}

// Repeated by the server while the animation plays: for a client that didn't have the pawn when it started, and because something on
// the client puts the idle pose back while the pawn is on its way down a rope (GEO_04A; what it is wasn't found: the check below holds)
simulated function ClientCoopKeepScriptAnim(Pawn P, name Anim, float Rate, bool bLoop, float Frame)
{
	local name Seq;
	local float OwnFrame;

	if(Level.NetMode != NM_Client || P == None)
		return;

	P.GetAnimParams('', Seq, OwnFrame);

	if(Seq == Anim && AnimController != None && P.Controller == AnimController)
		return;

	ClientCoopScriptAnim(P, Anim, Rate, bLoop);

	if(AnimController != None && P.Controller == AnimController)
		P.PlayAnim(Anim, , Rate, Frame);
}

simulated function ClientCoopEndScriptAnim(Pawn P)
{
	if(Level.NetMode != NM_Client || P == None || P.Controller != AnimController || AnimController == None)
		return;

	P.Controller = None;
	P.ChangeAnimation();
}

// Test only
static function string TurretCollision(Turret T)
{
	return T $ " (" $ T.Class.Name $ ") Collide=" $ T.bCollideActors $ " Zero=" $ T.bBlockZeroExtentTraces $ " NonZero=" $ T.bBlockNonZeroExtentTraces $ " ProjTarget=" $ T.bProjTarget $ " Hidden=" $ T.bHidden $ " PlayerUsable=" $ T.bPlayerUsable $ " Base=" $ T.Base $ " Loc=" $ T.Location;
}

// Client: where a mover moved by a level script stops, see CoopGame.SendMoverStops. M is None if the actor isn't here yet.
simulated function ClientCoopMoverStop(Mover M, int Key)
{
	local Turret T;

	if(Level.NetMode != NM_Client || M == None || M.ScriptTriggeredKeyframe == Key)
		return;

	Log("ModCoop: " $ M $ " (" $ M.Tag $ ") stops at key " $ Key $ " like on the server, it is at key " $ M.KeyNum $ " moving " $ M.bInterpolating);
	M.ScriptTriggeredKeyframe = Key;

	foreach DynamicActors(class'Turret', T)
	{
		if(T.Base == M)
			KeepTurretOnBase(T);
	}
}

/*
 * Client: a turret that rides a mover (RAS_04C, the walker's cannon on BigLift, AttachTag). Turret has bMovable=False by default, the map
 * sets it for this one, and a client's copy is made from the class defaults (bMovable isn't replicated): the base couldn't carry it and
 * SetLocation failed. It stayed at the bottom of the lift shaft while the lift brought the walker up, 4500 units from where the server
 * has it, and the client could never aim at it (test walker). Its Physics also differs (PHYS_Flying on the client, none on the server).
 * Movable and put back on its base, like on the server.
 */
simulated function KeepTurretOnBase(Turret T)
{
	local Actor B;
	local bool bMoved;

	// Only on movers: the gunship's ball turrets ride their gunship and weren't part of this (test turret on GEO_04A)
	if(T == None || T.Role == ROLE_Authority || Mover(T.Base) == None || (T.bMovable && T.Physics == PHYS_None))
		return;

	B = T.Base;
	T.bMovable = true;
	T.SetPhysics(PHYS_None);
	bMoved = T.SetLocation(B.Location + (T.RelativeLocation >> B.Rotation));
	T.SetBase(B);
	Log("ModCoop: " $ T $ " (" $ T.Class.Name $ ") put back on " $ B $ ": moved " $ bMoved $ " to " $ T.Location);
}

/*
 * Client: the marker of an item that the server lets this client see. The item's SquadMarker is set by the marker on the server
 * (SquadMarker.PostBeginPlay isn't simulated) and is None on a client; the marker's Anchor comes with the map.
 */
simulated function SquadMarker ShownMarkerOf(Actor Item)
{
	local int i;

	for(i = 0; i < ShownMarkers.Length; ++i)
	{
		if(ShownMarkers[i] != None && ShownMarkers[i].Anchor == Item && ShownMarkerValues[i] == 1)
			return ShownMarkers[i];
	}

	return None;
}

// Client: the server's decision for a marker (SyncMarkerVisibility), see CoopExtension.SquadMarkerShowIcons
simulated function bool IsMarkerShown(SquadMarker M)
{
	local int i;

	for(i = 0; i < ShownMarkers.Length; ++i)
	{
		if(ShownMarkers[i] == M)
			return ShownMarkerValues[i] == 1;
	}

	return false;
}

// Test only: see WatchIcon
simulated function WatchIconTick()
{
	if(WatchIcon.bHidden == bIconWatchHidden && Abs(WatchIcon.CurrentAlpha - WatchAlpha) < 0.05)
		return;

	Log("CoopTest: watch " $ WatchIcon $ " hidden " $ bIconWatchHidden $ " -> " $ WatchIcon.bHidden $ ", alpha " $ WatchAlpha $ " -> " $ WatchIcon.CurrentAlpha $ ", state " $ WatchIcon.GetStateName() $ " at " $ Level.TimeSeconds);
	bIconWatchHidden = WatchIcon.bHidden;
	WatchAlpha = WatchIcon.CurrentAlpha;
}

/*
 * Client, see CoopGame.SyncMarkerVisibility (the server owns the state). M is None if the actor isn't here yet, the full resend covers it.
 * The state of the marker is logged once so a test can tell whether bHidden really removes the icon.
 */
simulated function ClientCoopSetMarkerShown(SquadMarker M, bool bShown, optional Actor Anchor)
{
	local int i, Value;
	local string Usability;

	if(Level.NetMode != NM_Client || M == None)
		return;

	// Markers spawned while playing (the bacta dispenser's) get their item on the server only: the client's copy had none (ShownMarkerOf)
	if(M.Anchor == None && Anchor != None)
		M.Anchor = Anchor;

	if(M == WatchIcon)
		Log("CoopTest: watch: ClientCoopSetMarkerShown " $ bShown $ " at " $ Level.TimeSeconds);

	M.bHidden = !bShown;

	for(i = 0; i < ShownMarkers.Length; ++i)
	{
		if(ShownMarkers[i] == M)
			break;
	}

	if(i == ShownMarkers.Length)
	{
		ShownMarkers.Length = i + 1;
		ShownMarkers[i] = M;
		ShownMarkerValues[i] = 2;
		ShownMarkerLogged[i] = 0;
		ShownMarkerDisabled[i] = 0;
	}

	// A hidden icon was still highlighted when looked at (user, 2026-11-10): the native targeting goes by the client's copy, which stays in
	// its auto state Enabled. Disabled ignores NotifyTargeted. Only a state this function set is undone.
	if(!bShown && M.IsInState('Enabled'))
	{
		M.GotoState('Disabled');
		ShownMarkerDisabled[i] = 1;
	}
	else if(bShown && ShownMarkerDisabled[i] == 1)
	{
		ShownMarkerDisabled[i] = 0;

		if(M.IsInState('Disabled'))
			M.GotoState('Enabled');
	}

	if(bShown)
		Value = 1;

	if(ShownMarkerValues[i] != Value)
	{
		ShownMarkerValues[i] = Value;
		Log("ModCoop: marker shown M=" $ M $ " shown=" $ bShown);
	}

	if(ShownMarkerLogged[i] != 0 || Pawn == None)
		return;

	ShownMarkerLogged[i] = 1;
	Usability = "no anchor";

	// Native code, a client's marker may not have its anchor yet
	if(M.Anchor != None)
		Usability = string(M.GetMarkerUsability(Pawn));

	Log("ModCoop: marker look M=" $ M $ " state=" $ M.GetStateName() $ " bHidden=" $ M.bHidden $ " alpha=" $ M.GetPropertyText("CurrentAlpha") $ " usability=" $ Usability);
}

/*
 * The server's CoopSpaceWalk carries a client's flyer along the host's flight on RAS_01A. Client, the server owns the position.
 * Repeated by the server; the first one starts the state, nothing after the end can start it again. A lost update is replaced by the next one.
 */
simulated function ClientCoopSpaceWalkPos(vector Target)
{
	if(Level.NetMode != NM_Client || bSpaceWalkDone)
		return;

	SpaceWalkTarget = Target;

	if(bSpaceWalk)
		return;

	bSpaceWalk = true;
	Log("ModCoop: space walk starts, target " $ Target);

	// Without a pawn CheckSpaceWalk starts it after ClientRestart
	if(Pawn != None)
		GotoState('CoopSpaceWalk');
}

// Client, reliable: the flight is over at Spot
simulated function ClientCoopEndSpaceWalk(vector Spot)
{
	if(Level.NetMode != NM_Client)
		return;

	bSpaceWalk = false;
	bSpaceWalkDone = true;
	Log("ModCoop: space walk ends at " $ Spot);

	if(Pawn != None)
	{
		Pawn.SetLocation(Spot);
		Pawn.Velocity = vect(0,0,0);
		Pawn.Acceleration = vect(0,0,0);
		Pawn.SetPhysics(PHYS_Falling);
	}

	if(IsInState('CoopSpaceWalk'))
		GotoState('PlayerWalking');
}

/*
 * The sound journal (CoopNative.SetSoundLog) also gets the looping sounds actors carry (AmbientSound: movers while they move, machines): a
 * stuck sound is often one of them that never went off on this side. Once a second, the player of this window only.
 */
simulated function CheckAmbientSounds()
{
	local Actor A;
	local int i;
	local bool bFound;

	if(!class'CoopConfig'.default.bSoundLog || Viewport(Player) == None || Level.TimeSeconds < NextAmbientCheck)
		return;

	NextAmbientCheck = Level.TimeSeconds + 1.0;

	for(i = AmbientActors.Length - 1; i >= 0; --i)
	{
		if(AmbientActors[i] == None || AmbientActors[i].bDeleteMe || AmbientActors[i].AmbientSound != AmbientSounds[i])
		{
			class'CoopNative'.static.LogSound("Ambient off " $ AmbientSounds[i] $ " of " $ AmbientActors[i]);
			AmbientActors.Remove(i, 1);
			AmbientSounds.Remove(i, 1);
		}
	}

	foreach DynamicActors(class'Actor', A)
	{
		if(A.AmbientSound == None)
			continue;

		bFound = false;

		for(i = 0; i < AmbientActors.Length && !bFound; ++i)
			bFound = AmbientActors[i] == A;

		if(bFound)
			continue;

		AmbientActors[AmbientActors.Length] = A;
		AmbientSounds[AmbientSounds.Length] = A.AmbientSound;
		class'CoopNative'.static.LogSound("Ambient on " $ A.AmbientSound $ " of " $ A $ " (" $ A.Class.Name $ ") at " $ A.Location);
	}
}

// Client: ClientRestart (the possession of the flyer) sends the client to PlayerWalking, and the flight has to survive that
simulated function CheckSpaceWalk()
{
	local string WeaponText, WeaponState;

	if(!bSpaceWalk)
		return;

	if(Pawn != None && IsInState('PlayerWalking'))
	{
		Log("ModCoop: space walk: back from PlayerWalking");
		GotoState('CoopSpaceWalk');
	}

	if(Pawn == None || Level.TimeSeconds < NextSpaceWalkLog)
		return;

	NextSpaceWalkLog = Level.TimeSeconds + 1.0;
	WeaponText = "None";
	WeaponState = "None";

	if(Pawn.Weapon != None)
	{
		WeaponText = string(Pawn.Weapon);
		WeaponState = string(Pawn.Weapon.GetStateName());
	}

	Log("ModCoop: space walk client: loc=" $ Pawn.Location $ " target=" $ SpaceWalkTarget $ " err=" $ int(VSize(SpaceWalkTarget - Pawn.Location)) $ " state=" $ GetStateName() $ " phys=" $ Pawn.Physics $ " weapon=" $ WeaponText $ " wstate=" $ WeaponState $ " yaw=" $ Rotation.Yaw);
}

// See CoopGame.ForwardMarkerState
/*
 * Client: see CoopGame.EquipQuietly. While the server gives a new inventory, weapons that arrive don't switch (see
 * CoopExtension.WeaponClientWeaponSet); at the end WantClass is brought up once it has arrived (at most 3 s), or the best weapon.
 */
simulated function ClientCoopWeaponsQuiet(bool bQuiet, class<Weapon> WantClass)
{
	if(Level.NetMode != NM_Client)
		return;

	bQuietWeaponSet = true;
	bQuietEnding = !bQuiet;
	QuietWeaponClass = WantClass;

	if(bQuiet)
		QuietWeaponEnd = Level.TimeSeconds + 5;
	else
		QuietWeaponEnd = Level.TimeSeconds + 3;
}

simulated function CheckQuietWeapons()
{
	local Weapon W;

	if(!bQuietWeaponSet || (!bQuietEnding && Level.TimeSeconds < QuietWeaponEnd))
		return;

	if(Pawn != None && QuietWeaponClass != None)
		W = Weapon(Pawn.FindInventoryType(QuietWeaponClass));

	// The inventory comes after the RPC: wait for the weapon
	if(W == None && QuietWeaponClass != None && Level.TimeSeconds < QuietWeaponEnd)
		return;

	bQuietWeaponSet = false;

	if(Pawn == None)
		return;

	if(W == None)
	{
		Log("ModCoop: new inventory without " $ QuietWeaponClass $ ", switching to the best weapon");
		SwitchToBestWeapon();
		return;
	}

	Log("ModCoop: new inventory, bringing up " $ W $ " once (had " $ Pawn.Weapon $ ")");

	if(Pawn.Weapon == W)
		return;

	Pawn.PendingWeapon = W;

	if(Pawn.Weapon == None)
		Pawn.ChangedWeapon();
	else
		Pawn.Weapon.PutDown(W);
}

simulated function ClientCoopSetMarkerState(name MarkerTag, name NewState)
{
	local SquadMarker M;

	if(Level.NetMode != NM_Client)
		return;

	foreach AllActors(class'SquadMarker', M, MarkerTag)
	{
		if(!M.IsInState(NewState) && !(NewState == 'Auto' && M.IsInState(M.InitialState)))
		{
			Log("ModCoop: Script state of marker " $ M $ " (" $ MarkerTag $ "): " $ M.GetStateName() $ " -> " $ NewState);
			M.GotoState(NewState);
		}
	}
}

// See CoopGame.ForwardSetCollision
simulated function ClientCoopSetCollisionByTag(name ActorTag, bool bCollide, bool bBlockActors, bool bBlockPlayers)
{
	local Actor A;

	if(Level.NetMode != NM_Client)
		return;

	foreach AllActors(class'Actor', A, ActorTag)
	{
		if(Pawn(A) != None || Controller(A) != None)
			continue;

		if(A.bCollideActors != bCollide || A.bBlockActors != bBlockActors || A.bBlockPlayers != bBlockPlayers)
		{
			Log("ModCoop: Script collision of " $ A $ " (" $ ActorTag $ "): Collide=" $ bCollide $ " BlockActors=" $ bBlockActors $ " BlockPlayers=" $ bBlockPlayers);
			A.SetCollision(bCollide, bBlockActors, bBlockPlayers);
		}
	}
}

// See CoopGame.SyncTriggerLights
simulated function ClientCoopSetLight(Actor L, float NewBrightness, bool bNewCorona)
{
	if(L == None || L.Role == ROLE_Authority)
		return;

	if(NewBrightness == 0 && L.LightBrightness != 0)
		Log("ModCoop: Light " $ L $ " turned off by the server");

	L.LightBrightness = NewBrightness;
	L.bCorona = bNewCorona;
}

simulated function ClientCoopSetActorDisplay(int Index, Actor A, float ScaleX, float ScaleY, float ScaleZ, vector NewPrePivot, Material Skin0, Material Skin1)
{
	local vector NewScale3D;

	if(A == None)
	{
		ServerCoopMapActorMissing(Index);
		return;
	}

	if(A.Role == ROLE_Authority)
		return;

	NewScale3D.X = ScaleX;
	NewScale3D.Y = ScaleY;
	NewScale3D.Z = ScaleZ;

	if(A.DrawScale3D != NewScale3D)
		A.SetDrawScale3D(NewScale3D);

	A.PrePivot = NewPrePivot;

	if(Skin0 != None)
		A.Skins[0] = Skin0;

	if(Skin1 != None)
		A.Skins[1] = Skin1;
}

// Client: a map actor the server sent the display of isn't here yet (see CoopGame.SendMapActorDisplay). Server.
function ServerCoopMapActorMissing(int Index)
{
	if(CoopGame(Level.Game) != None)
		CoopGame(Level.Game).QueueMapActorResend(self, Index);
}

// See CoopGame.NeedsLookSync
/*
 * The replicated rotation of an actor with bMovable=False is dropped by the client (the native move refuses): turrets stood at rotation
 * 0 on the clients although the server sent them. Turning such an actor needs bMovable for a moment.
 */
static function RotateMapActor(Actor A, rotator Rot)
{
	local bool bWasMovable;

	bWasMovable = A.bMovable;
	A.bMovable = true;
	A.SetRotation(Rot);
	A.bMovable = bWasMovable;
}

simulated function ClientCoopSetActorLook(int Index, Actor A, name NewTag, byte Glow, bool bNewUnlit, bool bNewHidden, string InstanceName, float X, float Y, float Z, int Pitch, int Yaw, int Roll)
{
	local StaticMeshInstance Instance;
	local vector Loc;
	local rotator Rot;

	if(A == None)
	{
		ServerCoopMapActorMissing(Index);
		return;
	}

	if(A.Role == ROLE_Authority)
		return;

	// Replication rounds the location and the rotation, the static lighting belongs to the exact ones (only for actors that don't move)
	if(A.Physics == PHYS_None && !A.bInterpolating)
	{
		Loc.X = X;
		Loc.Y = Y;
		Loc.Z = Z;
		Rot.Pitch = Pitch;
		Rot.Yaw = Yaw;
		Rot.Roll = Roll;

		if(VSize(A.Location - Loc) < 2 && VSize(A.Location - Loc) > 0.01)
			A.SetLocation(Loc);

		if(A.Rotation != Rot)
			RotateMapActor(A, Rot);
	}

	A.Tag = NewTag;
	A.AmbientGlow = Glow;
	A.bUnlit = bNewUnlit;

	// The visibility of the server: GEO_03A, the jamming device under the yellow shield is hidden by default and shown on the server
	// only, its bHidden never reached the clients (session 2026-10-31)
	if(A.bHidden != bNewHidden)
	{
		Log("ModCoop: " $ A $ " (" $ NewTag $ ") hidden " $ bNewHidden $ " like on the server");
		A.bHidden = bNewHidden;
	}

	// The map's object is still in the loaded level package
	if(A.StaticMeshInstance == None && InstanceName != "" && InstanceName != "None")
	{
		Instance = StaticMeshInstance(DynamicLoadObject(InstanceName, class'StaticMeshInstance', true));

		if(Instance != None)
			A.StaticMeshInstance = Instance;

		Log("ModCoop: Look of " $ A $ " (" $ NewTag $ "): glow " $ Glow $ ", static lighting " $ InstanceName $ " " $ Instance);
	}
}

static function class<TeamInfo> GetSinglePlayerTeamClass(int Index)
{
	// Same as CTGameInfoSP.PostBeginPlay
	switch(Index)
	{
	case 0:
		return class'TeamNeutral';
	case 1:
	case 2:
		return class'TeamPlayer';
	case 3:
		return class'TeamWookiee';
	case 4:
		return class'TeamAttachedScav';
	case 5:
		return class'TeamHostile';
	case 6:
	case 7:
	case 8:
		return class'TeamMP';
	case 9:
		return class'TeamBerserker';
	}

	return None;
}

/*
 * Single player uses ten teams but the native replication of GameReplicationInfo only sends the multiplayer ones.
 * The native code crashes when it looks up the relationship to a missing team. The relationships are static (class defaults)
 * so the client creates the missing teams locally.
 */
simulated function EnsureClientTeams()
{
	local int i;
	local class<TeamInfo> TeamClass;
	local TeamInfo Team;

	for(i = 0; i < 10; ++i)
	{
		if(Level.GRI.Teams[i] != None)
			continue;

		TeamClass = GetSinglePlayerTeamClass(i);

		if(TeamClass == None)
			continue;

		Team = Spawn(TeamClass);

		if(Team != None)
		{
			Team.TeamIndex = i;
			Level.GRI.Teams[i] = Team;
		}
	}
}

/*
 * After being revived the weapon of a client stayed in state DownWeapon: the pawn wants to change to the weapon it already holds
 * and Pawn.ChangedWeapon does nothing in that case (the code for it is commented out in the original). The player could move but
 * had no weapon until an ammo pickup switched weapons. A weapon that is down and finished its animation is brought up again.
 */
/*
 * The host plays the single player commando which has no skin of its own: the mesh's default material is used, it was never meant
 * to be seen (the single player is only seen in first person) and looked grey and blurry to clients. The host gets the white
 * multiplayer skin, clients have the colored ones (CoopCommando).
 */
simulated function ApplyHostSkin()
{
	local PlayerCommando P;

	if(HostSkin == None)
		return;

	foreach DynamicActors(class'PlayerCommando', P)
	{
		if(CoopCommando(P) == None && P != Pawn && P.Skins.Length <= 1 && (P.Skins.Length == 0 || P.Skins[0] != HostSkin))
			P.Skins[0] = HostSkin;
	}
}

/*
 * HandSignal (the hands used for panels, demolition charges and the detonator) switches back to the previous weapon in Idle.Tick,
 * which only runs on the server: a client kept empty hands after using a panel. Same condition as HandSignal.Idle.Tick.
 */
/*
 * Diagnostics for invisible walls on clients: when the player keeps moving but the pawn stays where it is, the log says what it ran
 * into (traced from the knees and the chest in the direction of the movement). See also LongClientAdjustPosition.
 */
simulated function CheckBlocked()
{
	local vector Dir, HitLocation, HitNormal;
	local Actor HitKnee, HitChest;

	if(Pawn == None || Pawn.Physics != PHYS_Walking || VSize(Pawn.Acceleration) < 1)
	{
		BlockCheckTime = 0;
		return;
	}

	if(BlockCheckTime == 0 || VSize(Pawn.Location - BlockCheckLocation) > 20)
	{
		BlockCheckTime = Level.TimeSeconds;
		BlockCheckLocation = Pawn.Location;
		return;
	}

	if(Level.TimeSeconds - BlockCheckTime < 0.5 || Level.TimeSeconds < NextBlockLog)
		return;

	NextBlockLog = Level.TimeSeconds + 2;
	Dir = Normal(Pawn.Acceleration * vect(1,1,0)) * (Pawn.CollisionRadius + 40);
	HitKnee = Trace(HitLocation, HitNormal, Pawn.Location + Dir - vect(0,0,1) * Pawn.CollisionHeight * 0.5, Pawn.Location - vect(0,0,1) * Pawn.CollisionHeight * 0.5, true);
	HitChest = Trace(HitLocation, HitNormal, Pawn.Location + Dir + vect(0,0,1) * Pawn.CollisionHeight * 0.5, Pawn.Location + vect(0,0,1) * Pawn.CollisionHeight * 0.5, true);
	// Nothing in the way of the traces is logged too (a pawn or a corner): no warnings for the None
	Log("ModCoop: Blocked at " $ Pawn.Location $ " moving " $ Normal(Pawn.Acceleration) $ " knee=" $ BlockText(HitKnee) $ " chest=" $ BlockText(HitChest) $ " level=" $ Level.Title);
}

static function string BlockText(Actor A)
{
	if(A == None)
		return "None";

	return A $ " (" $ A.Class $ " " $ A.StaticMesh $ ")";
}

// Large corrections of the client's position by the server mean the server's pawn is stopped by something the client doesn't have
function LongClientAdjustPosition(float TimeStamp, name newState, EPhysics newPhysics, float NewLocX, float NewLocY, float NewLocZ, float NewVelX, float NewVelY, float NewVelZ, Actor NewBase, float NewFloorX, float NewFloorY, float NewFloorZ)
{
	local vector NewLocation;

	// The server decides the position of a flyer through ClientCoopSpaceWalkPos, a late correction would throw it out of the flight
	if(bSpaceWalk)
		return;

	if(Pawn != None && Level.NetMode == NM_Client && Level.TimeSeconds >= NextCorrectionLog)
	{
		NewLocation.X = NewLocX;
		NewLocation.Y = NewLocY;
		NewLocation.Z = NewLocZ;

		if(VSize(NewLocation - Pawn.Location) > 30)
		{
			NextCorrectionLog = Level.TimeSeconds + 2;
			Log("ModCoop: Server corrected the position by " $ int(VSize(NewLocation - Pawn.Location)) $ ": server " $ NewLocation $ " client " $ Pawn.Location);
		}
	}

	// A correction sent before the server heard of the use key threw the client out of UsingItem with the key still held: its EndState also stopped
	// the server, 9 of 36 uses of a panel or a revive failed in the session of 2026-11-02 and had to be pressed again. The server follows in a moment.
	if(newState == 'PlayerWalking' && IsInState('UsingItem') && bUse && Level.TimeSeconds - UsingItemStart < USE_CORRECTION_GRACE)
	{
		Log("ModCoop: use kept: the server's correction said PlayerWalking " $ (Level.TimeSeconds - UsingItemStart) $ " s after the key");
		newState = 'UsingItem';
	}

	Super.LongClientAdjustPosition(TimeStamp, newState, newPhysics, NewLocX, NewLocY, NewLocZ, NewVelX, NewVelY, NewVelZ, NewBase, NewFloorX, NewFloorY, NewFloorZ);
}

simulated function FixHandSignalWeapon(float DeltaTime)
{
	// After the detonator the hands kept playing an animation on the client and stayed in Active: the player had no weapon while
	// the server had already given it back. Hands that are still active after a few seconds without "Use" held go on to Idle.
	if(Pawn != None && Pawn.Weapon != None && Pawn.Weapon.WeaponType == WT_Marker && Pawn.Weapon.IsInState('Active') && !bUse)
	{
		HandSignalActiveTime += DeltaTime;

		if(HandSignalActiveTime > 3)
		{
			Log("ModCoop: Hands were stuck in Active, going on to Idle");
			HandSignalActiveTime = 0;
			bPlayedHandSignalAnim = false;
			Pawn.Weapon.GotoState('Idle');
			return;
		}
	}
	else
	{
		HandSignalActiveTime = 0;
	}

	// The hands wait in Active for the end of their animation, which isn't started on clients: play it (the detonator, placing a
	// charge...), then go on to Idle
	if(Pawn != None && Pawn.Weapon != None && Pawn.Weapon.WeaponType == WT_Marker && Pawn.Weapon.IsInState('Active') && !Pawn.Weapon.IsAnimating())
	{
		HandSignalIdleTime += DeltaTime;

		if(HandSignalIdleTime < 0.2)
			return;

		if(!bPlayedHandSignalAnim && Pawn.Weapon.LoadAnim != '' && Pawn.Weapon.HasAnim(Pawn.Weapon.LoadAnim))
		{
			bPlayedHandSignalAnim = true;
			Pawn.Weapon.PlayAnim(Pawn.Weapon.LoadAnim);
		}
		else
		{
			bPlayedHandSignalAnim = false;
			Pawn.Weapon.GotoState('Idle');
		}

		HandSignalIdleTime = 0;
		return;
	}

	if(Pawn == None || Pawn.Weapon == None || Pawn.Weapon.WeaponType != WT_Marker || !Pawn.Weapon.IsInState('Active'))
		bPlayedHandSignalAnim = false;

	if(Pawn == None || Pawn.Weapon == None || Pawn.Weapon.WeaponType != WT_Marker || !Pawn.Weapon.IsInState('Idle') ||
	   (Pawn.Weapon.FireAnim != '' && (TargetType == TGT_Panel || TargetType == TGT_DemolitionReady)))
	{
		HandSignalIdleTime = 0;

		// The item stays in the hand while the hands are used
		if(Pawn == None || Pawn.Weapon == None || Pawn.Weapon.WeaponType != WT_Marker || Pawn.Weapon.IsInState('DownWeapon'))
			DestroyClientAttachItem();

		return;
	}

	HandSignalIdleTime += DeltaTime;

	if(HandSignalIdleTime < 0.5)
		return;

	HandSignalIdleTime = 0;
	DestroyClientAttachItem();

	// Weapon.BringUp forgets the previous weapon when it was the hands (OldWeapon = None), and the blaster came instead of the
	// weapon held before the panel (the user's game 2026-11-12, "weapons:" lines). The weapon held last goes back
	if(Pawn.OldWeapon != None && Pawn.OldWeapon.WeaponType != WT_Marker)
		Pawn.SwitchToLastWeapon();
	else if(LastHeldWeapon != None && !LastHeldWeapon.bDeleteMe && LastHeldWeapon.Owner == Pawn)
	{
		Log("ModCoop: hands done, back to " $ LastHeldWeapon);
		Pawn.OldWeapon = LastHeldWeapon;
		Pawn.SwitchToLastWeapon();
	}
	else
		SwitchWeapon(1);
}

/*
 * The headlamp is also used by the visor modes (night vision). PlayerCommando spawns it on the server, squad members taken over
 * by a client have none on the client (CoopCommando does the same in PostNetBeginPlay).
 */
/*
 * After a takeover the server picks the current grenade while creating the inventory. The reference reached the client before the
 * grenades themselves and wasn't sent again: no grenade on the HUD and none could be thrown. Same choice as Pawn.CreateInventory.
 */
/*
 * Between network updates a client moves other pawns by their velocity. Fast and erratic enemies (Geonosians flying and jumping
 * around) end up far from where the server has them and jump to the new position with every update: 60-130 units several times
 * per second at 50-90 ms latency. The jump is hidden by drawing the mesh at the old position (PrePivot) and moving it to the real
 * one within about a tenth of a second. Collision and hits are not affected.
 * Pawns moved by an animation (the ropes) or without physics arrive with velocity 0, 6-20 times a second (test rope with NetJump): the
 * client has nothing to move them with between updates and predicting from the last two overshoots (updates are irregular). The mesh
 * then moves at a steady speed that reaches each update's position when the next one is due: it is about one update behind.
 */
simulated function SmoothProxies(float DeltaTime)
{
	local Pawn P;
	local int i;
	local vector Error;
	local float ErrorSize;

	DebugStep("SmoothProxies: removing");

	for(i = SmoothedPawns.Length - 1; i >= 0; --i)
	{
		P = SmoothedPawns[i].P;

		if(P == None || P.bDeleteMe || P.Health <= 0 || P.Role != ROLE_SimulatedProxy)
		{
			if(P != None && !P.bDeleteMe)
				P.PrePivot = SmoothedPawns[i].BasePrePivot;

			SmoothedPawns.Remove(i, 1);
		}
	}

	foreach DynamicActors(class'Pawn', P)
	{
		if(P == Pawn || P.Role != ROLE_SimulatedProxy || P.Health <= 0 || P.bHidden || P.DrawType != DT_Mesh)
			continue;

		for(i = 0; i < SmoothedPawns.Length; ++i)
		{
			if(SmoothedPawns[i].P == P)
				break;
		}

		if(i == SmoothedPawns.Length)
		{
			SmoothedPawns.Length = i + 1;
			SmoothedPawns[i].P = P;
			SmoothedPawns[i].LastLocation = P.Location;
			SmoothedPawns[i].LastVelocity = P.Velocity;
			SmoothedPawns[i].BasePrePivot = P.PrePivot;
			continue;
		}

		DebugStep("SmoothProxies: " $ P);
		if(VSize(P.Velocity) < 1 && VSize(SmoothedPawns[i].LastVelocity) < 1)
		{
			// The mesh stays where it was drawn
			SmoothedPawns[i].Offset += SmoothedPawns[i].LastLocation - P.Location;
			ErrorSize = VSize(SmoothedPawns[i].Offset);

			if(ErrorSize > 1500) // Teleported
			{
				SmoothedPawns[i].Offset = vect(0,0,0);
				ErrorSize = 0;
			}

			if(P.Location != SmoothedPawns[i].UpdateLocation)
			{
				SmoothedPawns[i].ChaseSpeed = ErrorSize / FClamp(Level.TimeSeconds - SmoothedPawns[i].UpdateTime, 0.03, 0.25);
				SmoothedPawns[i].UpdateLocation = P.Location;
				SmoothedPawns[i].UpdateTime = Level.TimeSeconds;
			}

			if(ErrorSize <= SmoothedPawns[i].ChaseSpeed * DeltaTime)
				SmoothedPawns[i].Offset = vect(0,0,0);
			else
				SmoothedPawns[i].Offset -= Normal(SmoothedPawns[i].Offset) * SmoothedPawns[i].ChaseSpeed * DeltaTime;

			P.PrePivot = SmoothedPawns[i].BasePrePivot + SmoothedPawns[i].Offset;
			SmoothedPawns[i].LastLocation = P.Location;
			SmoothedPawns[i].LastVelocity = P.Velocity;
			continue;
		}

		SmoothedPawns[i].UpdateLocation = P.Location;
		SmoothedPawns[i].UpdateTime = Level.TimeSeconds;
		Error = P.Location - (SmoothedPawns[i].LastLocation + SmoothedPawns[i].LastVelocity * DeltaTime);
		ErrorSize = VSize(Error);

		if(ErrorSize > 300) // Teleported
			SmoothedPawns[i].Offset = vect(0,0,0);
		else if(ErrorSize > 2)
			SmoothedPawns[i].Offset -= Error;

		SmoothedPawns[i].Offset *= FMax(0, 1 - DeltaTime * 8);

		if(VSize(SmoothedPawns[i].Offset) > 150)
			SmoothedPawns[i].Offset = Normal(SmoothedPawns[i].Offset) * 150;

		P.PrePivot = SmoothedPawns[i].BasePrePivot + SmoothedPawns[i].Offset;
		SmoothedPawns[i].LastLocation = P.Location;
		SmoothedPawns[i].LastVelocity = P.Velocity;
	}
}

simulated function EnsureGrenade()
{
	local Inventory Inv;

	if(Pawn == None || Pawn.CurrentGrenade != None)
		return;

	for(Inv = Pawn.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		if(Weapon(Inv) != None && Weapon(Inv).WeaponType == WT_Thrown)
		{
			Pawn.CurrentGrenade = Weapon(Inv);
			return;
		}
	}
}

simulated function EnsureHeadlamp()
{
	if(Pawn == None || Pawn.Flashlight != None || CoopCommando(Pawn) != None || !Pawn.IsA('CloneCommando'))
		return;

	Pawn.Flashlight = Pawn.Spawn(class'CloneHeadlamp', Pawn);

	if(Pawn.Flashlight != None)
	{
		Pawn.AttachToBone(Pawn.Flashlight, 'lightAttach');
		Pawn.Flashlight.SetRelativeLocation(vect(0,0,0));
		Pawn.Flashlight.SetRelativeRotation(rot(0,0,0));
		Log("ModCoop: Created client side headlamp for " $ Pawn);
	}
}

// Diagnostics: the view height of a new pawn a few seconds after getting it (Fixer's camera was lower after the takeover)
simulated function LogNewPawnView()
{
	if(Pawn == ViewLoggedPawn)
		return;

	if(ViewLogTime == 0)
	{
		ViewLogTime = Level.TimeSeconds + 3;
		return;
	}

	if(Level.TimeSeconds < ViewLogTime)
		return;

	ViewLogTime = 0;
	ViewLoggedPawn = Pawn;

	if(Pawn != None)
		Log("ModCoop: View of " $ Pawn $ " (" $ Pawn.Class $ "): EyeHeight=" $ Pawn.EyeHeight $ " BaseEyeHeight=" $ Pawn.BaseEyeHeight $ " CollisionHeight=" $ Pawn.CollisionHeight $ " Crouched=" $ Pawn.bIsCrouched $ " WantsToCrouch=" $ Pawn.bWantsToCrouch $ " Physics=" $ Pawn.Physics $ " State=" $ GetStateName() $ " BehindView=" $ bBehindView $ " ViewTarget=" $ ViewTarget);
}

// Diagnostics for "the hands and the weapon disappeared": logs the weapon when it stays missing or in a state other than Idle
simulated function CheckWeaponShown(float DeltaTime)
{
	local string Problem;

	if(Pawn == None || Pawn.bIncapacitated || Pawn.Health <= 0 || bBehindView)
	{
		WeaponProblemTime = 0;
		return;
	}

	if(Pawn.Weapon == None)
		Problem = "no weapon";
	else if(!Pawn.Weapon.IsInState('Idle') && !Pawn.Weapon.IsAnimating())
		Problem = "weapon not animating in state " $ Pawn.Weapon.GetStateName();

	if(Problem == "")
	{
		WeaponProblemTime = 0;
		return;
	}

	WeaponProblemTime += DeltaTime;

	if(WeaponProblemTime < 3 || Level.TimeSeconds < NextWeaponProblemLog)
		return;

	NextWeaponProblemLog = Level.TimeSeconds + 5;
	Log("ModCoop: Weapon problem: " $ Problem $ ": Weapon=" $ Pawn.Weapon $ " Pending=" $ Pawn.PendingWeapon $ " Old=" $ Pawn.OldWeapon $ " Grenade=" $ Pawn.CurrentGrenade $ " State=" $ GetStateName() $ " Target=" $ Target $ " TargetType=" $ TargetType $ " Anim=" $ Pawn.Weapon.IsAnimating());
}

/*
 * The hands and the weapon disappeared: the client stayed in CTPlayer's UsingItem without a weapon (Pawn.Weapon None), so every tick
 * it started the hand signal again ("Accessed None: Weapon" over a thousand times). A client without a weapon for a second brings
 * up the pending one or its best one.
 */
simulated function FixMissingWeapon(float DeltaTime)
{
	if(Pawn == None || Pawn.bIncapacitated || Pawn.Health <= 0 || Pawn.Weapon != None || Pawn.Inventory == None || IsInState('CoopWatching'))
	{
		NoWeaponTime = 0;
		return;
	}

	NoWeaponTime += DeltaTime;

	if(NoWeaponTime < 1)
		return;

	NoWeaponTime = 0;
	Log("ModCoop: No weapon for a second in state " $ GetStateName() $ ", bringing up " $ Pawn.PendingWeapon);

	if(Pawn.PendingWeapon != None)
		Pawn.ChangedWeapon();
	else
		SwitchToBestWeapon();
}

/*
 * A weapon goes back from firing to Idle when its fire animation (channel 1) ends. When something else cleared that animation (a
 * weapon pickup, the hands of a panel or the bacta healer during the shot) the weapon stayed in NormalFire forever on the client:
 * it neither fired nor could be switched ("weapon not animating in state NormalFire", the weapon seemed gone). After a second
 * without any animation the end of the animation is sent to it.
 */
simulated function FixStuckFire(float DeltaTime)
{
	local Weapon W;

	if(Pawn == None || Pawn.Weapon == None || Pawn.bIncapacitated || Pawn.Health <= 0)
	{
		StuckFireTime = 0;
		return;
	}

	W = Pawn.Weapon;

	// The bacta healer and the hands fire without an animation as long as Use is held
	if(!(W.IsInState('NormalFire') || W.IsInState('AltFire')) || W.IsAnimating(0) || W.IsAnimating(1) || W.WeaponType == WT_Heal || W.WeaponType == WT_Marker || bUse)
	{
		StuckFireTime = 0;
		return;
	}

	StuckFireTime += DeltaTime;

	if(StuckFireTime < 1)
		return;

	StuckFireTime = 0;
	Log("ModCoop: Weapon " $ W $ " was stuck in " $ W.GetStateName() $ " without an animation, ending the shot");
	W.AnimEnd(1);

	// Still there (no ClientThink for this weapon): back to Idle
	if(W.IsInState('NormalFire') || W.IsInState('AltFire'))
		W.GotoState('Idle');
}

simulated function FixStuckWeapon()
{
	local Weapon W;

	// Not while an item is used: the weapon goes down for the hands there (session 2026-10-31, GEO_03C: the rifle was brought up
	// again in UsingItem, the change didn't finish and the client had no weapon at all)
	if(Pawn == None || Pawn.bIncapacitated || Pawn.Health <= 0 || Pawn.Weapon == None || !Pawn.Weapon.IsInState('DownWeapon') || Pawn.Weapon.IsAnimating() ||
	   IsInState('UsingItem') || bUse)
	{
		WeaponDownTime = 0;
		return;
	}

	if(WeaponDownTime == 0)
	{
		WeaponDownTime = Level.TimeSeconds;
		return;
	}

	// The down animation is over, normally the next weapon comes at once. Waiting 1.5 s was too long for the bacta healer: reviving
	// switches weapons right away and the client gave up before the healer was up
	if(Level.TimeSeconds - WeaponDownTime < 0.4)
		return;

	WeaponDownTime = 0;
	W = Pawn.PendingWeapon;

	if(W == None || W == Pawn.Weapon)
	{
		// Same weapon: changing from no weapon brings it up on the client and on the server (ServerChangedWeapon)
		W = Pawn.Weapon;
		Pawn.Weapon = None;
		Pawn.PendingWeapon = W;
	}

	Log("ModCoop: Bringing up weapon " $ W $ " that was stuck in state DownWeapon");
	Pawn.ChangedWeapon();

	if(Pawn.Weapon == None)
	{
		Log("ModCoop: " $ W $ " didn't come up, keeping it as the weapon");
		Pawn.Weapon = W;
		Pawn.PendingWeapon = None;
		W.BringUp(None);
	}
}

simulated function LogPawns()
{
	local Pawn P;
	local int Num;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.Health > 0)
			++Num;

		if(PlayerCommando(P) != None || P.PlayerReplicationInfo != None)
			Log("CoopDebug: Client " $ P.Class.Name $ " " $ P.Location $ " Health=" $ P.Health $ " Incap=" $ P.bIncapacitated $ " Role=" $ P.Role);
	}

	Log("CoopDebug: Client living pawns=" $ Num);
}

/*
 * In tactical mode APawn::PostRender draws the nickname in the pawn's EnhancedVisionColor (Actor+500, Engine.dll). The Delta members have
 * theirs, a player's own commando (the host's PlayerCommando, a client's CoopCommando) has none: black, unreadable (the user's game
 * 2026-11-14). Every player's pawn without a color gets #AFFFFC on this machine, the user's choice; once a second (pawns come and go).
 * The color is also the pawn's outline in that mode, like the members have.
 */
simulated function CheckNameColors()
{
	local Pawn P;

	if(Level.NetMode == NM_Standalone || Level.TimeSeconds < NextNameColorCheck)
		return;

	NextNameColorCheck = Level.TimeSeconds + 1;
	CheckAccessoryOwners();

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.PlayerReplicationInfo == None || P.EnhancedVisionColor.R != 0 || P.EnhancedVisionColor.G != 0 || P.EnhancedVisionColor.B != 0)
			continue;

		P.EnhancedVisionColor.R = 175; // AF
		P.EnhancedVisionColor.G = 255; // FF
		P.EnhancedVisionColor.B = 252; // FC
		P.EnhancedVisionColor.A = 255;
	}
}

/*
 * Client: armour pieces (Accessory: Squad40Head, Squad62Spine2, MercShoulderSpike_L...) hang on their pawn (Base). On a client their Owner
 * never arrives (None, the server has the pawn) and they don't follow the pawn: test accessory measured Scorch's Squad62Spine2 staying
 * in one place while Scorch walked 2000 units away. They still blocked traces: invisible pieces left around the level. CTPlayer.
 * SelectTargetType turns a Flashlight or Accessory on a pawn into its Owner; with None it read Target.SquadMarker of nothing
 * (CTGame.dll+0x2A5EA, the only place the target becomes None there), the guard of ModCoop.dll caught it and cleared the target (RAS_03A in
 * the user's game; only the first 10 are logged). On a client the pieces don't take traces any more (the server decides every hit),
 * and get their Owner like on the server. Once a second.
 */
simulated function CheckAccessoryOwners()
{
	local Actor A;

	if(Level.NetMode != NM_Client || bNoAccessoryFix)
		return;

	foreach DynamicActors(class'Actor', A)
	{
		if(Pawn(A.Base) == None || !(A.IsA('Accessory') || A.IsA('Flashlight')))
			continue;

		if(A.Owner == None)
			A.SetOwner(A.Base);

		if(A.bCollideActors || A.bBlockZeroExtentTraces || A.bBlockNonZeroExtentTraces)
		{
			A.SetCollision(false, false, false);
			A.bBlockZeroExtentTraces = false;
			A.bBlockNonZeroExtentTraces = false;
		}
	}
}

event PlayerTick(float DeltaTime)
{
	CheckAmbientSounds();
	CheckVisionMode();
	CheckNameColors();

	if(Level.NetMode == NM_Client)
	{
		// CTPlayer's target selection needs the teams
		if(Level.GRI == None)
		{
			Super(PlayerController).PlayerTick(DeltaTime);
			return;
		}

		if(!bSetCoopNetSpeed && Player != None)
			SetCoopNetSpeed();

		// Each step is marked for the crash diagnostics of ModCoop.dll (the engine only says "PlayerTick")
		DebugStep("CheckQuietWeapons");
		CheckQuietWeapons();
		CheckTurretPawn();
		CheckSpaceWalk();
		TraceWeapons();
		ResetStaleHands();
		DebugStep("EnsureClientTeams");
		EnsureClientTeams();
		if(bHideRiders)
			ApplyHideRiders();

		// Spawned while the camera was still on the controller (the level was waiting for the clients): the client saw its own
		// commando from inside and no weapon (GEO_05A, in the lift)
		if(Pawn != None && ViewTarget != Pawn && !bBehindView && !IsInState('CoopWatching') && (IsInState('PlayerWalking') || IsInState('CoopLiftRide') || IsInState('CoopSpaceWalk')))
		{
			Log("ModCoop: The camera was on " $ ViewTarget $ ", back to the own commando " $ Pawn);
			SetViewTarget(Pawn);
		}

		DebugStep("FixStuckWeapon");
		FixStuckWeapon();
		FixStuckFire(DeltaTime);
		DebugStep("FixMissingWeapon");
		FixMissingWeapon(DeltaTime);
		DebugStep("CheckWeaponShown");
		CheckWeaponShown(DeltaTime);
		DebugStep("FixEyeHeight");
		FixEyeHeight();
		LogNewPawnView();
		DebugStep("CheckBlocked");
		CheckBlocked();
		DebugStep("FixHandSignalWeapon");
		FixHandSignalWeapon(DeltaTime);
		DebugStep("EnsureHeadlamp");
		EnsureHeadlamp();
		DebugStep("EnsureGrenade");
		EnsureGrenade();
		SmoothProxies(DeltaTime);
		if(bTestNetJump)
			TestNetJump(DeltaTime);
		LogClientStatus();

		if(WatchIcon != None)
			WatchIconTick();

		if(Level.TimeSeconds >= NextHostSkinCheck)
		{
			NextHostSkinCheck = Level.TimeSeconds + 1.0;
			DebugStep("ApplyHostSkin");
			ApplyHostSkin();
		}

		DebugStep("ServerCoopSetTarget");

		// The target (what the player looks at) is only selected on the client but server side code depends on it.
		// E.g. the bacta healer switches back to the rifle on the server if the target is not an incapacitated friend.
		if(Target != SentTarget || TargetType != SentTargetType)
		{
			SentTarget = Target;
			SentTargetType = TargetType;
			ServerCoopSetTarget(Target, TargetType);
		}

		if(class'CoopConfig'.default.bDebugLog && Level.TimeSeconds >= NextDebugLogTime)
		{
			NextDebugLogTime = Level.TimeSeconds + 1.0;
			LogPawns();
		}

		if(Pawn != None)
			DebugStep("CTPlayer.PlayerTick in state " $ GetStateName() $ " Pawn=" $ Pawn $ " Weapon=" $ Pawn.Weapon $ " Target=" $ Target);
		else
			DebugStep("CTPlayer.PlayerTick in state " $ GetStateName() $ " without a pawn");
	}

	Super.PlayerTick(DeltaTime);

	if(Level.NetMode == NM_Client)
		DebugStep("after PlayerTick");
	else
		HoldHostLiftRotation();
}

/*
 * The host over the shoulder in a lift or a briefing (GEO_03A): the mouse turned the host's commando although Briefing.PlayerMove only
 * moves the camera. The rotation of the controller and the pawn is held where it was when the view started.
 */
function HoldHostLiftRotation()
{
	local rotator R;

	if(!bLiftView || Pawn == None || IsInState('CoopWatching'))
	{
		bLiftHoldSet = false;
		return;
	}

	KeepHostWaitAnim();
	SendHostWaitAnim();

	if(!bLiftHoldSet)
	{
		bLiftHoldSet = true;
		LiftHoldRotation = Rotation;
		Log("ModCoop: holding the host's rotation " $ Rotation $ " in the lift view (State=" $ GetStateName() $ ")");
	}

	if(Rotation != LiftHoldRotation)
		SetRotation(LiftHoldRotation);

	R = LiftHoldRotation;
	R.Pitch = 0;
	R.Roll = 0;

	if(Pawn.Rotation != R)
		Pawn.SetRotation(R);
}

simulated function DebugStep(string Step)
{
	class'CoopNative'.static.SetDebugStep(Step);
}

// Diagnostics: the client's state every 10 seconds, to see what happened before a problem
// Diagnostics: the commandos this client sees (one run showed 7 models of the squad)
simulated function LogCommandos()
{
	local Pawn P;
	local string Str;
	local int Num;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.IsA('CloneCommando') && P.Health > 0)
		{
			++Num;
			Str = Str $ " " $ P.Class.Name $ "(" $ P.Skins[0] $ "," $ P.Role $ "," $ P.bHidden $ "," $ int(P.Location.X) $ "," $ int(P.Location.Y) $ "," $ int(P.Location.Z) $ ")";
		}
	}

	if(Num != LastCommandoCount)
	{
		LastCommandoCount = Num;
		Log("ModCoop: Commandos seen: " $ Num $ ":" $ Str);
	}
}

// The weapons in the pawn's inventory: a client saw two sets of them (session 2026-11-02), which side has them wasn't in the logs. See also CoopGame.RemoveDuplicateWeapons
simulated function string WeaponList()
{
	local Inventory Inv;
	local string Text;
	local int Guard;

	if(Pawn == None)
		return "";

	for(Inv = Pawn.Inventory; Inv != None && Guard < 40; Inv = Inv.Inventory)
	{
		Guard = Guard + 1;

		if(Weapon(Inv) != None)
			Text = Text $ " " $ Inv.Class.Name;
	}

	return Text;
}

simulated function LogClientStatus()
{
	if(Level.TimeSeconds < NextStatusLog)
		return;

	NextStatusLog = Level.TimeSeconds + 10;
	LogCommandos();

	if(Pawn == None)
	{
		Log("ModCoop: Status: State=" $ GetStateName() $ " no pawn, ViewTarget=" $ ViewTarget);
		return;
	}

	Log("ModCoop: Status: State=" $ GetStateName() $ " Pawn=" $ Pawn.Class.Name $ " Health=" $ Pawn.Health $ " Incap=" $ Pawn.bIncapacitated $ " Physics=" $ Pawn.Physics $
	    " Loc=" $ Pawn.Location $ " Weapon=" $ Pawn.Weapon $ " WeaponState=" $ Pawn.Weapon.GetStateName() $ " Pending=" $ Pawn.PendingWeapon $
	    " Grenade=" $ Pawn.CurrentGrenade $ " Target=" $ Target $ " TargetType=" $ TargetType $ " ViewTarget=" $ ViewTarget $ " BehindView=" $ bBehindView $
	    " Ping=" $ PlayerReplicationInfo.Ping $ " Weapons:" $ WeaponList());
}

function ServerCoopSetTarget(Actor NewTarget, ETargetType NewTargetType)
{
	if(IsCoopHost())
		return;

	Target = NewTarget;
	TargetType = NewTargetType;
}

/*
 * Using an item (reviving with the bacta healer, panels) is the client side state UsingItem. The server kept the controller in
 * PlayerWalking and its position corrections (ClientAdjustPosition sends the server's state) threw the client out of UsingItem
 * right after it started: a client could never revive anybody. The server follows the client's state instead.
 */
function ServerCoopUsingItem(bool bStart, Actor NewTarget, ETargetType NewTargetType)
{
	if(IsCoopHost() || Pawn == None)
		return;

	if(bStart)
	{
		Target = NewTarget;
		TargetType = NewTargetType;
		bUse = true;

		if(!IsInState('UsingItem'))
			GotoState('UsingItem');

		if(TargetType == TGT_FriendToHeal && Pawn(Target) != None)
			Pawn(Target).bBeingRevivedByPlayer = true;
	}
	else
	{
		bUse = false;

		if(Pawn(Target) != None)
			Pawn(Target).bBeingRevivedByPlayer = false;

		if(IsInState('UsingItem'))
			GotoState('PlayerWalking');
	}
}

/*
 * Panels (bacta dispensers, hacking, explosives): CTPlayer.Use and StartHandSignal only change the panel and remember the hand signal
 * target on the client. The hand signal weapon (HandSignal.MarkerHandSetup) and the panel run on the server which knew nothing about
 * it: clients could not use any panel. The server does the same.
 */
exec function Use()
{
	local PlayerController Specialist;
	local ActivateItem Item;
	local Turret T;

	LogUse("pressed");

	// Door breaches wait for the clients of the squad (see CoopGame.OrderDoorBreach)
	if(IsCoopHost() && CoopGame(Level.Game) != None && (TargetType == TGT_Marker || TargetType == TGT_MarkerCancel) &&
	   CoopGame(Level.Game).OrderDoorBreach(self, TargetMarker, TargetType == TGT_MarkerCancel))
		return;

	// The host can't order a squad marker whose specialist is played by a client (see CoopGame.MarkerSpecialist)
	if(IsCoopHost() && CoopGame(Level.Game) != None && (TargetType == TGT_Marker || TargetType == TGT_MarkerCancel) && TargetMarker != None)
	{
		Specialist = CoopGame(Level.Game).MarkerClient(TargetMarker);

		// A sniper position goes to the AI members like in single player (see CoopGame.SnipeNeedsClient)
		if(Specialist != None && TargetMarker.IsA('MarkerSnipe') && !CoopGame(Level.Game).SnipeNeedsClient(TargetMarker))
		{
			Log("ModCoop: " $ TargetMarker $ " ordered to the AI members, " $ Specialist.PlayerReplicationInfo.PlayerName $ " plays Sev");
			Specialist = None;
		}

		if(Specialist != None)
		{
			Item = ActivateItem(TargetMarker.Anchor);

			if(Item != None)
				Item.bIsUsableByPlayer = true;

			ClientMessage(Specialist.PlayerReplicationInfo.PlayerName $ " has to do this himself");
			return;
		}
	}

	if(Level.NetMode == NM_Client && Pawn != None && TargetType == TGT_Panel && ActivateItem(Target) != None)
		ServerCoopUsePanel(Target);

	// CTPlayer.Use mounts a turret with Target.UsedBy, which only ran on the client: clients could never use a turret
	if(Level.NetMode == NM_Client && Pawn != None && TargetType == TGT_MountTurret && Turret(Target) != None)
	{
		ServerCoopUseTurret(Turret(Target));
		return;
	}

	// GEO_03C: the sonic turret at the tower was never a target for clients (its Geonosian gunner was dead, the client still saw
	// it as manned). Use right at a free looking turret asks the server, which decides.
	if(Level.NetMode == NM_Client && Pawn != None && (Target == None || TargetType == TGT_Pickup || TargetType == TGT_KarmaProp))
	{
		T = FindNearTurret();

		if(T != None)
		{
			Log("ModCoop: Use at " $ T $ " without a turret target (TargetType=" $ TargetType $ " Gunner=" $ T.Gunner $ "), asking the server");
			ServerCoopUseTurret(T);
			return;
		}
	}

	KeepOthersFromSnipe(true);
	Super.Use();
	KeepOthersFromSnipe(false);
	LogUse("done");
}

/*
 * HACK: the sniper position of GEO_01C goes to whoever the marker picks first, with the squad following the host that can be Fixer: he stood on the
 * position while Sev stayed behind (user's run 2026-11-02). While the order is executed the other AI members are out of the squad, Sev is
 * the only one to choose, they are back in the same call. Remove it if the marker's choice can be set another way.
 */
function KeepOthersFromSnipe(bool bKeep)
{
	local Pawn P, Sev;
	local int i;

	if(!bKeep)
	{
		for(i = 0; i < SnipeKeptOff.Length; i = i + 1)
		{
			if(SnipeKeptOff[i] != None && !SnipeKeptOff[i].bDeleteMe && Pawn != None && Pawn.Squad != None)
				Pawn.Squad.AddToSquad(SnipeKeptOff[i]);
		}

		if(SnipeKeptOff.Length > 0)
			Log("ModCoop: sniper order done, marker " $ TargetMarker $ " active " $ TargetMarker.bMarkerActive $ " participants " $ TargetMarker.Participants[0].Member $ "," $ TargetMarker.Participants[1].Member $ "," $ TargetMarker.Participants[2].Member);

		SnipeKeptOff.Length = 0;
		return;
	}

	if(!IsCoopHost() || Pawn == None || Pawn.Squad == None || TargetType != TGT_Marker || TargetMarker == None || TargetMarker.Tag != 'BalconyMarkerSnipe')
		return;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.IsA('Commando07Delta') && P.Squad == Pawn.Squad && AIController(P.Controller) != None && P.Health > 0 && !P.bIncapacitated)
			Sev = P;
	}

	if(Sev == None)
		return;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P != Sev && P != Pawn && P.Squad == Pawn.Squad && AIController(P.Controller) != None)
			SnipeKeptOff[SnipeKeptOff.Length] = P;
	}

	for(i = 0; i < SnipeKeptOff.Length; i = i + 1)
		Pawn.Squad.RemoveFromSquad(SnipeKeptOff[i]);

	Log("ModCoop: sniper order for " $ Sev $ ", " $ SnipeKeptOff.Length $ " others kept off");
}

/*
 * Squad orders that don't work for testers (GEO_01C: Sev doesn't go to the sniper position, the host only sees the squad commands): what the
 * player targeted when pressing Use, what the marker and the squad said, and the squad commands before it.
 * Logging: "ModCoop: use", "ModCoop: squad command"; the bot's failure is the engine's "Marker goal ... failed".
 */
simulated function LogUse(string Step)
{
	local string Text;
	local Squad S;
	local Pawn P;
	local SquadMarker M;

	Text = "ModCoop: use " $ Step $ ": TargetType=" $ TargetType $ " Target=" $ Target $ " State=" $ GetStateName();

	// ASquadMarker::GetMarkerUsability reads Pawn.Squad without a check: Use with no pawn (a dead host, the order of test snipe) crashed the
	// host (Engine.dll+0x2AD93, test run 2026-11-14)
	if(TargetMarker != None)
		Text = Text $ " Marker=" $ TargetMarker $ " tag=" $ TargetMarker.Tag $ " class=" $ TargetMarker.Class.Name $ " state=" $ TargetMarker.GetStateName() $ " visible=" $ TargetMarker.AlwaysVisible $ " active=" $ TargetMarker.bMarkerActive $ " complete=" $ TargetMarker.bComplete;

	if(TargetMarker != None && Pawn != None)
		Text = Text $ " usability=" $ TargetMarker.GetMarkerUsability(Pawn);

	if(Pawn != None)
	{
		S = Pawn.Squad;
		Text = Text $ " Pawn=" $ Pawn.Class.Name $ " Squad=" $ S;

		if(S != None)
			Text = Text $ " leader=" $ (S.SquadLeader == Pawn) $ " alive=" $ S.CountAliveMembers() $ " stance=" $ S.Stance;
	}

	Log(Text);

	// What may keep the squad occupied: its members and the markers that are active
	if(Step == "pressed" && Role == ROLE_Authority && TargetMarker != None && S != None)
	{
		foreach DynamicActors(class'Pawn', P)
		{
			if(P.Squad == S && P != Pawn)
				Log("ModCoop: use member " $ P.Class.Name $ " marker=" $ P.SquadMarker $ " controller=" $ P.Controller.Class.Name $ "/" $ P.Controller.GetStateName() $ " health=" $ P.Health $ " incap=" $ P.bIncapacitated);
		}

		foreach AllActors(class'SquadMarker', M)
		{
			if(M.bMarkerActive)
				Log("ModCoop: use active marker " $ M $ " state=" $ M.GetStateName() $ " complete=" $ M.bComplete $ " participants=" $ M.TotalParticipants $ " members=" $ M.Participants[0].Member $ "," $ M.Participants[1].Member $ "," $ M.Participants[2].Member);
		}
	}
}

exec function SetStanceOffensive()
{
	Log("ModCoop: squad command F1 search and destroy");
	Super.SetStanceOffensive();
}

exec function SetStanceDefensive()
{
	Log("ModCoop: squad command F2 form up");
	Super.SetStanceDefensive();
}

exec function SquadEngage()
{
	Log("ModCoop: squad command F3 secure position");
	Super.SquadEngage();
}

exec function CancelAllMarkers()
{
	Log("ModCoop: squad command F4 recall");
	Super.CancelAllMarkers();
}

// See Use and SelectTargetType. The traces start at the eyes: the pawn's center is often behind the turret's own base
simulated function Turret FindNearTurret()
{
	local Turret T;

	foreach CollidingActors(class'Turret', T, TURRET_USE_RANGE, Pawn.Location)
	{
		if(!T.IsA('AutoTurret') && (T.Gunner == None || T.Gunner.Health <= 0) && (Normal(T.Location - Pawn.Location) dot vector(Rotation)) > TURRET_USE_AIM &&
		   FastTrace(T.Location, Pawn.Location + Pawn.EyePosition()))
			return T;
	}

	return None;
}

/*
 * The game only offers a turret when the crosshair is nearly inside its model: testers had to walk into it (session 2026-11-02). Looking
 * towards a free turret close by is enough now, for the prompt and for Use. Nothing else the player could target gets replaced.
 */
simulated event ETargetType SelectTargetType()
{
	local ETargetType Found;
	local Turret T;

	Found = Super.SelectTargetType();

	/*
	 * The marker icon of what the crosshair is on (the "+" over a bacta dispenser, the console's icon) is drawn by the helmet for
	 * TargetMarker. ACTPlayer::SelectTargetType takes the marker of the item looked at (Target.SquadMarker) only for the leader of a
	 * squad (Pawn.Squad.SquadLeader == Pawn): a client, with no squad of its own, never had it, while the host had (the user's
	 * screenshots 2026-11-14). A client gets the item's marker when the server lets it see that marker (SyncMarkerVisibility). The
	 * target type isn't changed: the item is still used by hand.
	 */
	if(Level.NetMode == NM_Client && Pawn != None && TargetMarker == None && Target != None && (Pawn.Squad == None || Pawn.Squad.SquadLeader != Pawn))
		TargetMarker = ShownMarkerOf(Target);

	// A turret with a marker is an order for the squad, not for a client: Use did nothing until the player stood right at it (GEO_04A, test turretnear)
	if(Pawn != None && Found == TGT_Marker && Turret(Target) != None && (Pawn.Squad == None || Pawn.Squad.SquadLeader != Pawn))
		Found = TGT_Default;

	if(Pawn != None && IsInState('PlayerWalking') && (Found == TGT_Default || Found == TGT_Pickup || Found == TGT_KarmaProp))
	{
		T = FindNearTurret();

		if(T != None && (Level.NetMode == NM_Client || T.IsAvailableFor(Pawn)))
		{
			Target = T;
			return TGT_MountTurret;
		}
	}

	return Found;
}

/*
 * Turrets manned by clients. In single player the turret is aimed in PlayerManningTurret.PlayerMove on the player's own computer;
 * a client's moves never reached the server. Now the client aims (its own copy of the angles, the camera follows them), sends the
 * angles to the server, the server turns the turret and puts the turret's first person weapon where the camera is, so the shots of
 * that weapon (fired like any other weapon of the client) come out of the turret.
 */
function ServerCoopUseTurret(Turret T)
{
	local Actor Hide;

	if(Pawn == None || T == None || VSize(T.Location - Pawn.Location) > 600)
		return;

	if(T.Gunner == Pawn)
	{
		Log("CoopPlayer: " $ PlayerReplicationInfo.PlayerName $ " leaves " $ T);
		T.UsedBy(Pawn);
		ClientCoopLeaveTurret();

		// LeaveTurret deletes the turret's weapon; the server had no weapon for the client afterwards
		if(Pawn.Weapon == None)
			SwitchToBestWeapon();

		ClientSwitchToBestWeapon();
		return;
	}

	// A dead gunner (GEO_03C: the Geonosian on the sonic turret) still had the turret
	if(T.Gunner != None && (T.Gunner.bDeleteMe || T.Gunner.Health <= 0))
	{
		Log("CoopPlayer: " $ T $ " still had the dead gunner " $ T.Gunner $ ", freeing it");
		T.Gunner = None;
	}

	if(T.ReservedBy != None && T.ReservedBy != Pawn && (T.ReservedBy.bDeleteMe || T.ReservedBy.Health <= 0))
	{
		Log("CoopPlayer: " $ T $ " was still reserved by the dead " $ T.ReservedBy $ ", freeing it");
		T.ReservedBy = None;
	}

	if(!T.IsAvailableFor(Pawn))
	{
		Log("CoopPlayer: " $ PlayerReplicationInfo.PlayerName $ " can't use " $ T $ ": Gunner=" $ T.Gunner $ " ReservedBy=" $ T.ReservedBy $ " Weapon=" $ Pawn.Weapon);
		return;
	}

	T.UsedBy(Pawn);

	if(T.Gunner != Pawn)
		return;

	// PlayerManTurret hides the turret for the player looking through it, here that was everybody. The walker's cannon hides the walker
	// itself (ATTEWalkerCannon.TurretBase): the host saw it vanish while a client manned it (test walker, screenshots). Only the gunner's
	// own copy is hidden (ClientCoopManTurret)
	T.bHidden = false;
	Hide = None;

	if(ATTEWalkerCannon(T) != None && ATTEWalkerCannon(T).TurretBase != None)
	{
		Hide = ATTEWalkerCannon(T).TurretBase;
		Hide.bHidden = false;
	}

	Log("CoopPlayer: " $ PlayerReplicationInfo.PlayerName $ " mans " $ T);
	ClientCoopManTurret(T, T.Yaw, T.Pitch, T.Rotation.Pitch, T.Rotation.Yaw, T.Rotation.Roll, Hide);
}

function ServerCoopTurretAim(int NewYaw, int NewPitch)
{
	local Turret T;

	T = Turret(Machine);

	if(T == None || T.Gunner != Pawn)
		return;

	// The turret's own clamping and bone rotations
	T.ChangeAngle(NewYaw - T.Yaw, NewPitch - T.Pitch, 100);
	SetRotation(TurretView(T, T.Yaw, T.Pitch));

	// WookieeTurret fires in its own TurretFire from here, the others in CoopTurretFire
	if(Pawn.Weapon != None && Pawn.Weapon.WeaponType == WT_Turret && LaserWeapon(Pawn.Weapon) == None)
	{
		Pawn.Weapon.SetLocation(T.GetCameraLocation());
		Pawn.Weapon.SetRotation(Rotation);
	}
}

// Where the gunner on a client looks, the same on the server and the client. The bones of the turret say the same at rest, but its
// fire animation rocks them (up to 300 units of pitch, GEO_04A).
static function rotator TurretView(Turret T, int Yaw, int Pitch)
{
	local rotator R;

	R = T.Rotation;
	R.Yaw += Yaw;
	R.Pitch += Pitch;
	R.Roll = 0;

	return R;
}

simulated function ClientCoopManTurret(Turret T, int StartYaw, int StartPitch, int BasePitch, int BaseYaw, int BaseRoll, optional Actor HideAlso)
{
	local rotator Base;

	// The look of the turret may come later than this
	Base.Pitch = BasePitch;
	Base.Yaw = BaseYaw;
	Base.Roll = BaseRoll;

	if(T != None && T.Rotation != Base)
		RotateMapActor(T, Base);

	if(Level.NetMode != NM_Client || T == None)
		return;

	Machine = T;
	TurretYaw = StartYaw;
	TurretPitch = StartPitch;
	SentTurretYaw = StartYaw;
	SentTurretPitch = StartPitch;
	T.bHidden = true;
	TurretPawn = Pawn;

	// The walker around its cannon, for this player's view only (see ServerCoopUseTurret)
	TurretHidden = HideAlso;

	if(HideAlso != None)
		HideAlso.bHidden = true;

	Log("ModCoop: Manning " $ T $ ", hidden for the view: " $ HideAlso);
	GotoState('PlayerManningTurret');
}

/*
 * Client: the turret state is left when the server says so (ClientCoopLeaveTurret). A client whose commando died on the turret or
 * that got another pawn (respawn, takeover) stayed in PlayerManningTurret with the new pawn: stuck, the camera at the ground
 * (GEO_04A, session 2026-11-01). It leaves the turret then.
 */
simulated function CheckTurretPawn()
{
	if(Level.NetMode != NM_Client)
		return;

	if(!IsInState('PlayerManningTurret'))
		return;

	if(Pawn != None && Pawn == TurretPawn && Pawn.Health > 0 && !Pawn.bIncapacitated)
		return;

	Log("ModCoop: the pawn that manned " $ Machine $ " is gone or down (" $ Pawn $ "), leaving the turret");
	TurretPawn = None;
	ClientCoopLeaveTurret();
	bBehindView = false;
}

// Client, in UsingItem, see its PlayerTick
// Client: every change of the hands goes to the log with the class names, the Status lines only show unnamed objects (GEO_04A: which
// weapon was gone couldn't be told from the logs of session 2026-11-01). Grep for "ModCoop: weapons:"
simulated function TraceWeapons()
{
	local string Trace;

	if(Pawn == None)
		return;

	if(Pawn.Weapon != None && (Pawn.Weapon.WeaponType == WT_Primary || Pawn.Weapon.WeaponType == WT_Secondary))
		LastHeldWeapon = Pawn.Weapon;

	Trace = "Weapon=" $ WeaponTraceName(Pawn.Weapon) $ " Pending=" $ WeaponTraceName(Pawn.PendingWeapon) $ " Old=" $ WeaponTraceName(Pawn.OldWeapon);

	if(Trace != LastWeaponTrace)
	{
		LastWeaponTrace = Trace;
		Log("ModCoop: weapons: " $ string(Level.NetMode == NM_Client) $ " " $ Trace $ " State=" $ GetStateName() $ " Use=" $ bUse $ " Time=" $ Level.TimeSeconds);
	}
}

simulated function string WeaponTraceName(Weapon W)
{
	if(W == None)
		return "None";

	return W.Class.Name $ "(" $ W.GetStateName() $ ",change=" $ W.bChangeWeapon $ ",new=" $ W.NewWeapon $ ")";
}

/*
 * HandSignal.Active.BeginState isn't simulated: on a client the reset of bChangeWeapon in Weapon.Active.BeginState never runs for the
 * hands. Left over from putting them down the last time, it sent them down again at the end of their animation with nothing pending:
 * Pawn.ChangedWeapon made that "no weapon". From the second panel, charge or detonator of a client on, the panel's animation was lost
 * and the weapon with it (GEO_04A, reproduced by the test charge with CoopTestUseFirst). The hands in Active never go down
 * (HandSignal.Active.PutDown), so the flag can only be stale there.
 */
simulated function ResetStaleHands()
{
	if(Pawn != None && Pawn.Weapon != None && Pawn.Weapon.WeaponType == WT_Marker && Pawn.Weapon.bChangeWeapon && Pawn.Weapon.IsInState('Active'))
	{
		Pawn.Weapon.bChangeWeapon = false;
		Pawn.Weapon.NewWeapon = None;
	}
}

/*
 * Server: HandSignal.Idle.Tick sends the player back to the last weapon, every frame, as long as the hands are in Idle, whichever
 * weapon the player holds. In single player the hands go through DownWeapon first; the weapon of a client comes back through
 * ServerChangedWeapon and the hands of the server went on to Idle afterwards, for the rest of the level. On a turret they took the
 * turret's weapon away again and again (test charge with CoopTestUseFirst, "weapons:" lines). Bringing them up works from no state.
 * Called every frame (CoopGame.Tick): once a second left up to a second of rifle and pistol swapping, 6 changes in 0.1 s after a
 * panel (the user's game 2026-11-12, stopped at "parking the hands").
 */
function ParkServerHands()
{
	if(Pawn == None || Pawn.Weapon == None)
		return;

	if(Pawn.Weapon.WeaponType == WT_Marker)
		ServerHands = Pawn.Weapon;
	else if(ServerHands != None && ServerHands.IsInState('Idle'))
	{
		Log("CoopPlayer: parking the hands of " $ PlayerReplicationInfo.PlayerName);
		ServerHands.GotoState('');
	}
}

/*
 * Weapon changes of a client happen on the client, the server follows (Pawn.ServerChangedWeapon). The server also ran the single player
 * code that picks a weapon after the bacta healer or the hands (CTPlayer.ReturnToWeapon, UsingItem.BeginState's ForceWeaponSwitch,
 * SwitchWeapon): its copy of the client's last weapon is often None, so it picked the blaster and sent it to the client (the user's game
 * 2026-11-14, RAS_01C: rifle, healer, rifle, then blaster on both sides, twice). For a client the server picks nothing now.
 * The client: the healer and the hands make Weapon.BringUp forget the last weapon, the rifle or pistol held before them is used.
 */
simulated function bool IsRemoteOnServer()
{
	return Level.NetMode != NM_Client && Viewport(Player) == None;
}

function ReturnToWeapon()
{
	if(IsRemoteOnServer())
		return;

	if(Pawn != None && Pawn.Weapon != None && (Pawn.Weapon.WeaponType == WT_Marker || Pawn.Weapon.WeaponType == WT_Heal))
		LogWeaponCall("ReturnToWeapon");

	if(Pawn != None && (Pawn.OldWeapon == None || (Pawn.OldWeapon.WeaponType != WT_Primary && Pawn.OldWeapon.WeaponType != WT_Secondary)) &&
	   LastHeldWeapon != None && !LastHeldWeapon.bDeleteMe && LastHeldWeapon.Owner == Pawn && Pawn.Weapon != LastHeldWeapon)
		Pawn.OldWeapon = LastHeldWeapon;

	Super.ReturnToWeapon();
}

/*
 * BactaHealer.Idle.BeginState asks for the blaster (ForceWeaponSwitch(1)) when the healer goes idle without a friend to heal. In single
 * player the healer is put down from NormalFire and never gets there. On a client it went to Idle after the revive, with the rifle
 * already back in the hands, and swapped it for the blaster (test healweapon: "ForceWeaponSwitch 1 in PlayerWalking, holding" the rifle,
 * as in the user's game). Only the healer and ACTION_Briefing call it directly, a key goes through SwitchWeapon (bSwitchWeaponCall).
 * A direct call while a rifle or pistol is held does nothing; with the healer held it goes back to the weapon held before it.
 */
simulated function ForceWeaponSwitch(byte F)
{
	if(IsRemoteOnServer())
		return;

	if(F == 1)
		LogWeaponCall("ForceWeaponSwitch " $ F);

	if(F == 1 && !bSwitchWeaponCall && !bBriefing && Pawn != None && Pawn.Weapon != None)
	{
		if(Pawn.Weapon.WeaponType == WT_Primary || Pawn.Weapon.WeaponType == WT_Secondary)
		{
			Log("ModCoop: the healer's switch to the blaster ignored, holding " $ Pawn.Weapon);
			return;
		}

		if(Pawn.Weapon.WeaponType == WT_Heal && LastHeldWeapon != None && !LastHeldWeapon.bDeleteMe && LastHeldWeapon.Owner == Pawn)
		{
			Log("ModCoop: the idle healer goes back to " $ LastHeldWeapon);
			Pawn.OldWeapon = LastHeldWeapon;
			Pawn.SwitchToLastWeapon();
			return;
		}
	}

	Super.ForceWeaponSwitch(F);
}



exec function SwitchWeapon(byte F)
{
	if(IsRemoteOnServer())
		return;

	LogWeaponCall("SwitchWeapon " $ F);
	bSwitchWeaponCall = true;
	Super.SwitchWeapon(F);
	bSwitchWeaponCall = false;
}

// Which code changes the weapon (no stack traces in this engine): the caller's state and the weapons at that moment
simulated function LogWeaponCall(string What)
{
	if(Pawn != None)
		Log("ModCoop: weapon call " $ What $ " in " $ GetStateName() $ ", holding " $ Pawn.Weapon $ " (" $ Pawn.Weapon.GetStateName() $ ") pending " $ Pawn.PendingWeapon $ " old " $ Pawn.OldWeapon $ " target " $ TargetType);
}

exec function SwitchToBestWeapon()
{
	LogWeaponCall("SwitchToBestWeapon");
	Super.SwitchToBestWeapon();
}

simulated function ClientSwitchToBestWeapon()
{
	LogWeaponCall("ClientSwitchToBestWeapon");
	Super.ClientSwitchToBestWeapon();
}

simulated function BringUpUsingHands()
{
	local Weapon Hands;

	if(Pawn == None || Pawn.Weapon != None || Pawn.PendingWeapon != None || Pawn.Inventory == None || TargetType != TGT_Panel)
		return;

	Hands = Pawn.Inventory.WeaponChange(11, true);
	Log("ModCoop: no weapon while using " $ Target $ ", Old=" $ Pawn.OldWeapon $ ", bringing up the hands " $ Hands);

	if(Hands == None)
		return;

	Pawn.PendingWeapon = Hands;
	Pawn.ChangedWeapon();
}

simulated function ClientCoopLeaveTurret()
{
	if(Level.NetMode != NM_Client)
		return;

	Log("ModCoop: Left " $ Machine);

	if(Machine != None)
		Machine.bHidden = false;

	if(TurretHidden != None)
		TurretHidden.bHidden = false;

	TurretHidden = None;
	Machine = None;
	GotoState('PlayerWalking');

	// The turret's first person weapon refuses to be put down (GeoTurret, GunshipTurret: PutDown is false in Idle and NormalFire):
	// the server took it off the pawn, the client kept it in the hands (session 2026-11-01). It goes, the best weapon comes
	if(Pawn != None && Pawn.Weapon != None && Pawn.Weapon.WeaponType == WT_Turret)
	{
		Log("ModCoop: taking the turret's weapon " $ Pawn.Weapon $ " off the hands");
		Pawn.Weapon.GotoState('');
		Pawn.Weapon.bHidden = true;
		Pawn.Weapon = None;
		Pawn.PendingWeapon = None;
		SwitchToBestWeapon();
	}
}

/*
 * HandSignal.MarkerHandSetup chooses the hand animations (demolition charge, detonator, bacta, keypad...) and the item in the hand,
 * but only on the server. Clients played the default animations without the item. Same choice for panels on the client.
 */
simulated function SetupClientHandSignal(ETargetType NewType, Actor NewTarget, SquadMarker NewMarker)
{
	local Weapon Hands;
	local ActivateItem Item;
	local class<Actor> AttachClass;
	local name LoadAnim, FireAnim, HolsterAnim;

	Hands = Weapon(Pawn.FindInventoryType(class<Inventory>(DynamicLoadObject("CTInventory.HandSignal", class'Class'))));

	if(Hands == None)
		return;

	Item = ActivateItem(NewTarget);

	if(Item == None && NewMarker != None)
		Item = ActivateItem(NewMarker.Anchor);

	if(Item == None)
		return;

	HolsterAnim = 'Holster';

	switch(Item.ActivateItemType)
	{
	case AIT_BactaDispenser:
		LoadAnim = 'BactaLoad';
		FireAnim = 'BactaLoop';
		HolsterAnim = 'BactaHolster';
		break;
	case AIT_BreachDoor:
		LoadAnim = 'SetDoorCharge';
		FireAnim = 'StartDoorCharge';
		AttachClass = Item.AttachItemClass;
		break;
	case AIT_Demolition:
		FireAnim = 'KeypadLoop';

		if(!Item.bActivated && !Item.bActivating)
		{
			LoadAnim = 'SetDemolition';
			AttachClass = Item.AttachItemClass;
		}
		else
		{
			LoadAnim = 'Load';
		}
		break;
	case AIT_Plunger:
		LoadAnim = 'Detonate';
		AttachClass = class<Actor>(DynamicLoadObject("CTInventory.DemolitionPlungerObject", class'Class', true));
		break;
	case AIT_ProximityMine:
		if(!Item.bActivated && !Item.bActivating)
		{
			LoadAnim = 'SetProxMine';
			AttachClass = Item.AttachItemClass;
		}
		else
		{
			LoadAnim = 'Load';
		}
		break;
	case AIT_DisarmTrap:
	case AIT_HackTerminal:
		LoadAnim = 'KeypadLoad';
		FireAnim = 'KeypadLoop';
		HolsterAnim = 'KeypadHolster';
		break;
	default:
		LoadAnim = 'Load';
		FireAnim = 'KeypadLoop';
	}

	Hands.LoadAnim = LoadAnim;
	Hands.FireAnim = FireAnim;
	Hands.HolsterAnim = HolsterAnim;

	DestroyClientAttachItem();

	if(AttachClass != None)
	{
		ClientAttachItem = Hands.Spawn(AttachClass, Hands,, Hands.GetBoneLocation('weaponAttach_L'));

		if(ClientAttachItem != None)
		{
			Hands.AttachToBone(ClientAttachItem, 'weaponAttach_L');
			ClientAttachItem.SetRelativeLocation(vect(0,0,0));
			ClientAttachItem.SetRelativeRotation(rot(0,0,0));
		}
	}
}

simulated function DestroyClientAttachItem()
{
	if(ClientAttachItem != None)
	{
		ClientAttachItem.Destroy();
		ClientAttachItem = None;
	}
}

function StartHandSignal()
{
	if(Role < ROLE_Authority && Pawn != None)
		SetupClientHandSignal(TargetType, Target, TargetMarker);

	Super.StartHandSignal();

	if(Role < ROLE_Authority)
		ServerCoopStartHandSignal(HandSignalTargetType, HandSignalTarget, HandSignalTargetMarker);
}

// Same as the TGT_Panel case of CTPlayer.Use
function ServerCoopUsePanel(Actor NewTarget)
{
	local ActivateItem TargetActivate;

	TargetActivate = ActivateItem(NewTarget);

	if(IsCoopHost() || Pawn == None || TargetActivate == None || VSize(TargetActivate.Location - Pawn.Location) > 500)
		return;

	if(!class'CoopGame'.static.MemberCanUse(Pawn, TargetActivate))
	{
		Log("ModCoop: " $ Pawn.Class.Name $ " of " $ PlayerReplicationInfo.PlayerName $ " can't use " $ TargetActivate $ " (" $ TargetActivate.ActivateItemType $ "), not its specialty");
		return;
	}

	if(TargetActivate.ActivateItemType == AIT_BactaDispenser && Pawn.Health >= Pawn.MaxHealth)
		return;

	if(!TargetActivate.bActivating)
	{
		TargetActivate.bPlayerActivated = true;
		TargetActivate.bUsed = true;
		TriggerEvent(TargetActivate.EventUnderway, TargetActivate, Pawn);
	}
}

function ServerCoopStartHandSignal(ETargetType NewType, Actor NewTarget, SquadMarker NewMarker)
{
	local ActivateItem Item;

	if(IsCoopHost())
		return;

	HandSignalTargetType = NewType;
	HandSignalTarget = NewTarget;
	HandSignalTargetMarker = NewMarker;

	// Detonating a demolition charge: HandSignal.FireWeapon is called by the first person animation which only plays on the client
	if(NewType == TGT_DemolitionReady)
	{
		Item = ActivateItem(NewTarget);

		if((Item == None || Item.ActivateItemType != AIT_Plunger) && NewMarker != None)
			Item = ActivateItem(NewMarker.Anchor);

		if(Item == None || Item.ActivateItemType != AIT_Plunger)
		{
			foreach DynamicActors(class'ActivateItem', Item)
			{
				if(Item.ActivateItemType == AIT_Plunger && Item.bActivated && Item.User == self)
					break;
			}
		}

		if(Item != None && Item.ActivateItemType == AIT_Plunger && Item.bActivated)
		{
			// After the 'Detonate' animation of the hands (see CoopGame.Tick)
			Log("ModCoop: " $ PlayerReplicationInfo.PlayerName $ " detonates " $ Item);
			PendingDetonation = Item;
			DetonationTime = Level.TimeSeconds + 1.0;
		}
	}
}

/*
 * Pawn.Reviving calls PawnRevived only on the server. The local player of a single player game is on the server but a client's
 * controller would stay in state CtrlIncapacitated: unable to move with the camera stuck at the 'DeathCamera' bone.
 */
simulated function PawnRevived(Pawn P)
{
	Super.PawnRevived(P);

	if(Role == ROLE_Authority && !IsCoopHost() && P == Pawn)
		ClientCoopPawnRevived();
}

// See CoopGame.SyncIncapacitated. P is None if it is not relevant for this client.
simulated function ClientCoopSetIncapacitated(Pawn P, bool bIncapacitated)
{
	if(P != None && P.Role < ROLE_Authority)
		P.bIncapacitated = bIncapacitated;
}

// Tutorial hints (CTPauseHintText, shown by scripts with ACTION_ShowDebriefingScreen) are not shown in coop
exec event ShowMenu(optional string MenuClass, optional string Title, optional string Text, optional string PicName, optional string NewLevel)
{
	if(Level.NetMode != NM_Standalone && InStr(Caps(MenuClass), "PAUSEHINT") != -1)
	{
		Log("ModCoop: Skipped hint " $ Title);
		return;
	}

	// The engine opens its pause menu by its own setting, not through CoopExtension.RedirectMenuClass
	if(MenuClass == "" && Level.NetMode == NM_ListenServer && IsCoopHost())
		MenuClass = "ModCoop.CoopPauseMenu";

	Super.ShowMenu(MenuClass, Title, Text, PicName, NewLevel);
}

/*
 * The CD key check of the host (the GameSpy servers are long gone) refused a client whose key was in use by another player, e.g.
 * two game instances on one PC or two players with the same copy after a level change. Coop doesn't care.
 */
simulated event ClientSetBadCDKey(bool bSet)
{
	if(bSet && Level.NetMode == NM_Client)
	{
		Log("ModCoop: Ignoring the host's CD key check");
		return;
	}

	Super.ClientSetBadCDKey(bSet);
}

// See CoopGame.TakeOver
simulated function ClientCoopTakeoverCamera(vector FromLocation, rotator FromRotation)
{
	TakeoverFromLocation = FromLocation;
	TakeoverFromRotation = FromRotation;
	TakeoverStartTime = Level.TimeSeconds;
	TakeoverArc = 150;
	BeginBlendToEyes();
}

// Moves the camera along an arc from the old pawn to the new one after a takeover
event PlayerCalcView(out actor ViewActor, out vector CameraLocation, out rotator CameraRotation)
{
	local float Alpha;

	Super.PlayerCalcView(ViewActor, CameraLocation, CameraRotation);

	// The lobby: the loading screen closes every menu when the map is up, so the menu opens whenever none is open (see CoopLobby)
	if(LobbyState != "" && LobbyState != "START" && Player != None && Player.Console != None && Player.Console.CurMenu == None)
		ClientOpenMenu("ModCoop.CoopLobbyMenu");

	if(CoopGame(Level.Game) != None && CoopGame(Level.Game).bWaitingForClients)
		CoopGame(Level.Game).CheckClientWaitTime();

	// The host's own lift view (see CoopGame.CheckLiftRides)
	if(Level.NetMode != NM_Client && (bLiftView || WatchCameraPawn != None))
		CalcWatchView(ViewActor, CameraLocation, CameraRotation);

	if(Level.NetMode == NM_Client)
	{
		CalcWatchView(ViewActor, CameraLocation, CameraRotation);

		// The camera of a client flies up after a lift (session 2026-11-02), the logs couldn't tell why
		if(Pawn != None && ViewTarget == Pawn && !bBehindView && TakeoverStartTime == 0 && Level.TimeSeconds >= NextCameraLog &&
		   (Abs(Pawn.EyeHeight - Pawn.BaseEyeHeight) > 40 || VSize(CameraLocation - Pawn.Location) > 150))
		{
			NextCameraLog = Level.TimeSeconds + 1;
			Log("ModCoop: camera off the eyes: camera " $ CameraLocation $ " pawn " $ Pawn.Location $ " EyeHeight=" $ Pawn.EyeHeight $ " Base=" $ Pawn.Base $ " Physics=" $ Pawn.Physics $ " State=" $ GetStateName());
		}

		// Looking through another pawn: at what is drawn (see SmoothProxies), the scene camera is smoothed itself
		if(WatchCameraPawn == None && Pawn(ViewTarget) != None && ViewTarget != Pawn)
			CameraLocation += ViewTarget.PrePivot;

		if(bTestNetJump)
		{
			if(VSize(CameraLocation - JumpCamera) > JumpCameraMax)
				JumpCameraMax = VSize(CameraLocation - JumpCamera);

			JumpCamera = CameraLocation;
		}

		// The host waits with the level until every client sees it (CoopGame.CheckClientsArrived). Here because the level is
		// paused while the host waits: PlayerTick doesn't run, the view is still calculated.
		// First frame drawn after loading: the client is ready (also while the host waits with the level paused)
		if(!bSentCoopReady)
		{
			bSentCoopReady = true;
			Log("ModCoop: Ready, the camera is on " $ ViewTarget);
			ServerCoopReady();
		}
	}

	if(bBlendToEyes && TakeoverStartTime == 0 && WatchCameraPawn == None && !bLiftView)
		EndBlendToEyes();

	if(TakeoverStartTime == 0)
		return;

	Alpha = (Level.TimeSeconds - TakeoverStartTime) / 1.5;

	if(Alpha >= 1.0 || Alpha < 0)
	{
		TakeoverStartTime = 0;

		if(bBlendToEyes)
			EndBlendToEyes();

		return;
	}

	// Still in behind view: the flight ends in the eyes, the own model stays drawn until then (a server's ClientSetBehindView(false)
	// in the middle of it is overruled). A flight into a scene camera (StartWatching) ends there, not in the eyes.
	if(bBlendToEyes && Pawn != None && !IsInState('CoopWatching') && !bLiftView)
	{
		bBehindView = true;
		CameraLocation = Pawn.Location + Pawn.EyePosition();
		CameraRotation = Rotation;
		ViewActor = self;
	}

	Alpha = Alpha * Alpha * (3 - 2 * Alpha);
	CameraLocation = TakeoverFromLocation + (CameraLocation - TakeoverFromLocation) * Alpha + vect(0,0,1) * TakeoverArc * Sin(Alpha * Pi);
	CameraRotation = TakeoverFromRotation + Normalize(CameraRotation - TakeoverFromRotation) * Alpha;
}

/*
 * Every camera flight back into the own eyes (the end of a lift view, a briefing, a watched scene, an entrance, a door breach, the
 * reunion, the flight from the own commando to a member at a takeover) keeps the behind view until the camera is in the eyes: the
 * model stays drawn and the first person weapon comes after it. Before, first person came at once and the weapon hung in the air.
 * Host and clients alike.
 */
simulated function BeginBlendToEyes()
{
	bBlendToEyes = true;

	if(!IsInState('CoopWatching') && !bLiftView)
		bBehindView = true;
}

// See BeginBlendToEyes: the camera has reached the eyes, first person now
simulated function EndBlendToEyes()
{
	bBlendToEyes = false;

	if(!bLiftView && !IsInState('CoopWatching'))
	{
		bBehindView = false;
		SetHostOutsideLook(false);
		Log("ModCoop: first person again after the camera flight, rotation " $ Rotation);
	}
}

/*
 * A level started in the level's briefing hasn't brought the weapon up (Briefing doesn't allow switching): it isn't attached to the pawn. Single player
 * never shows that, the lift view shows the host's body (GEO_03A: empty hands, session 2026-11-02). The end of the briefing brings it up in
 * first person as usual.
 */
function ShowHostWeaponInLift()
{
	Log("ModCoop: host weapon in the lift: " $ Pawn.Weapon $ " pending " $ Pawn.PendingWeapon);

	if(Pawn.Weapon == None)
	{
		bOkToSwitchWeapon = true;
		SwitchToBestWeapon();
		bOkToSwitchWeapon = false;
	}

	if(Pawn.Weapon == None)
		return;

	if(Pawn.Weapon.ThirdPersonActor == None || Pawn.Weapon.ThirdPersonActor.Base != Pawn)
		Pawn.Weapon.AttachToPawn(Pawn);

	if(Pawn.Weapon.ThirdPersonActor != None)
		Pawn.Weapon.ThirdPersonActor.bHidden = false;

	Log("ModCoop: host weapon in the lift now: " $ Pawn.Weapon $ " attachment " $ Pawn.Weapon.ThirdPersonActor $ " base " $ Pawn.Weapon.ThirdPersonActor.Base);
}

/*
 * The host stood still in the briefing (GEO_03A: the elevator) while the squad around it played its animations. In the lift view it
 * plays a relaxed waiting loop, on the host and on the clients (sent like an animation of a level script, once to every client, also
 * to the ones that join during the scene).
 */
function SetHostWaitAnim(bool bOn)
{
	local Controller C;

	if(Level.NetMode == NM_Client || Pawn == None || Viewport(Player) == None)
		return;

	if(bOn)
	{
		// Checked in the GEO_03A elevator (session 2026-10-31): BriefingElevatorSM1 is Scorch's pose there (the host copied him),
		// PlayerImmobileBreathe lies on the floor, RelaxBreatheIdle raises the rifle, MarchBreathe isn't in the commando's set.
		// RelaxBreathe stands still and calm
		if(Pawn.HasAnim('RelaxBreathe'))
			HostWaitAnim = 'RelaxBreathe';
		else if(Pawn.HasAnim('ActionBreathe'))
			HostWaitAnim = 'ActionBreathe';
		else
			return;

		// Pawn.ChangeAnimation keeps its hands off while the controller controls the animations
		bControlAnimations = true;

		// The upper body channels (weapon pose, breathing) are blended over the base channel: only the waiting loop is left
		Pawn.StopAnimating(true);
		Pawn.LoopAnim(HostWaitAnim);
		Log("ModCoop: the host waits with " $ HostWaitAnim);
		SendHostWaitAnim();

		ShowHostWeaponInLift();
		return;
	}

	if(HostWaitAnim == '')
		return;

	HostWaitAnim = '';
	bControlAnimations = false;
	Pawn.ChangeAnimation();

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && C != self && CoopPlayer(C).bHostWaitAnimSent)
		{
			CoopPlayer(C).bHostWaitAnimSent = false;
			CoopPlayer(C).ClientCoopEndHostWaitAnim(Pawn);
		}
	}
}

// The engine's breathing (Pawn.PlayBreathe: ActionBreathe on the base channel) replaced the loop on the server, and the server's
// animation is replicated to the clients: they kept seeing ActionBreathe. The loop is put back whenever it was replaced.
function KeepHostWaitAnim()
{
	local name Seq;
	local float Frame;

	if(HostWaitAnim == '' || Pawn == None)
		return;

	Pawn.GetAnimParams('', Seq, Frame);

	if(Seq != HostWaitAnim)
	{
		Pawn.StopAnimating(true);
		Pawn.LoopAnim(HostWaitAnim);
	}
}

// Sent again every 2 s: a client that loads during the scene doesn't have the host's pawn yet (the call is lost)
function SendHostWaitAnim()
{
	local Controller C;

	if(HostWaitAnim == '' || Pawn == None || Level.TimeSeconds < NextHostWaitSend)
		return;

	NextHostWaitSend = Level.TimeSeconds + 2;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && C != self && CoopPlayer(C).Player != None)
		{
			CoopPlayer(C).bHostWaitAnimSent = true;
			CoopPlayer(C).ClientCoopHostWaitAnim(Pawn, HostWaitAnim);
		}
	}
}

simulated function ClientCoopEndHostWaitAnim(Pawn P)
{
	ClientHostWaitAnim = '';
	ClientCoopEndScriptAnim(P);
}

// Client: see SetHostWaitAnim (a call again doesn't restart the loop)
simulated function ClientCoopHostWaitAnim(Pawn P, name Anim)
{
	local name Seq;
	local float Frame;

	if(Level.NetMode != NM_Client || P == None)
		return;

	// Diagnostics: what the host's pawn plays here (the loop was sent, but the model looked frozen)
	P.GetAnimParams('', Seq, Frame);

	if(AnimController != None && P.Controller == AnimController && ClientHostWaitAnim == Anim)
	{
		if(Seq != Anim)
		{
			Log("ModCoop: the host's pawn plays " $ Seq $ " instead of " $ Anim $ ", playing it again");
			P.StopAnimating(true);
			P.LoopAnim(Anim);
		}

		return;
	}

	ClientHostWaitAnim = Anim;
	Log("ModCoop: the host waits with " $ Anim);
	P.StopAnimating(true);
	ClientCoopScriptAnim(P, Anim, 1.0, true);
}

/*
 * The host's own commando has no skin (single player never shows it from outside): the host saw it black over the shoulder, the
 * clients see it fine. While the host sees it from outside (the lift view and the flight back into the eyes) it wears the clients'
 * white armor, lit like the squad next to it.
 */
simulated function SetHostOutsideLook(bool bOn)
{
	if(Level.NetMode == NM_Client || Pawn == None || CoopCommando(Pawn) != None)
		return;

	if(bOn)
	{
		Pawn.Skins[0] = class'CoopCommando'.default.CoopSkins[0];
		Pawn.AmbientGlow = 40;
		return;
	}

	if(Pawn.Skins.Length > 0 && Pawn.Skins[0] == class'CoopCommando'.default.CoopSkins[0])
		Pawn.Skins[0] = None;

	Pawn.AmbientGlow = Pawn.default.AmbientGlow;
}

// Scene watching (CoopGame.StartWatching): the camera looks over the right shoulder of the squad member, so the scene is in the
// picture (through its eyes it mostly wasn't), smoothed because the replicated location and rotation of the pawn jump. When the
// scene is over the camera moves into the eyes of the member (see PlayerCalcView).
simulated function CalcWatchView(out actor ViewActor, out vector CameraLocation, out rotator CameraRotation)
{
	local Pawn P;
	local float DeltaTime;
	local vector Head, Desired, HitLocation, HitNormal, X, Y, Z;
	local rotator DesiredRotation;

	P = Pawn(ViewTarget);

	// Riding a lift with the own pawn: the same camera on it (behind view again after a respawn or a takeover reset it)
	if(bLiftView && !IsInState('CoopWatching'))
	{
		P = Pawn;
		bBehindView = true;
	}

	// The member may still be this client's pawn here (a door breach: the AI has it, the client doesn't know yet)
	// Not P.Health: on a client the health of a member may not have arrived yet (0) while the level waits for the clients
	if(!(IsInState('CoopWatching') || bLiftView) || P == None || P.bDeleteMe)
	{
		if(IsInState('CoopWatching') && Level.TimeSeconds >= NextWatchLog)
		{
			NextWatchLog = Level.TimeSeconds + 1;
			Log("ModCoop: Watching without a scene camera: ViewTarget=" $ ViewTarget $ " (" $ ViewTarget.Class $ ") Pawn=" $ Pawn $ " WatchedMember=" $ WatchedMember);
		}

		if(WatchCameraPawn != None)
		{
			Log("ModCoop: Scene camera on " $ WatchCameraPawn $ " ended: State=" $ GetStateName() $ " ViewTarget=" $ ViewTarget);
			bWatchFocus = false;
			WatchCameraPawn = None;
			TakeoverFromLocation = WatchCameraLocation;
			TakeoverFromRotation = WatchCameraRotation;
			TakeoverStartTime = Level.TimeSeconds;
			TakeoverArc = 0;
			BeginBlendToEyes();

			// Back in the own eyes after the lift: looking where the camera looked
			if(WatchCameraPawn == None && Pawn != None && !IsInState('CoopWatching'))
			{
				TakeoverFromRotation.Roll = 0;
				SetRotation(TakeoverFromRotation);
				Log("ModCoop: looking where the scene camera looked: " $ TakeoverFromRotation $ " now " $ Rotation $ " State=" $ GetStateName());
			}
		}

		RestoreWatchedPawn();
		return;
	}

	DesiredRotation = P.Rotation;
	DesiredRotation.Pitch = -1200;
	DesiredRotation.Roll = 0;

	// The helmet's bone (where the headlamp is): it follows the animation, the pawn's location doesn't (GEO_01C: down the rope the
	// model moved and the camera stayed up until the location jumped)
	Head = P.GetBoneLocation('lightAttach');

	if(Head == vect(0,0,0) || VSize(Head - P.Location) > 3000)
		Head = P.Location + vect(0,0,1) * P.BaseEyeHeight;

	// Lift: looking at the center of the car, the player looks around from there
	if(bLiftView)
	{
		DesiredRotation = rotator(LiftCenter - Head);
		DesiredRotation.Pitch = Clamp((DesiredRotation.Pitch + 32768) % 65536 - 32768, -6000, 3000) + LiftLookPitch;
		DesiredRotation.Yaw += LiftLookYaw;
		DesiredRotation.Roll = 0;
	}
	// Door breach: behind the member, looking at the door
	else if(bWatchFocus)
	{
		DesiredRotation = rotator(WatchFocus - Head);
		DesiredRotation.Pitch = Clamp((DesiredRotation.Pitch + 32768) % 65536 - 32768, -3000, 1500) - 1200;
		DesiredRotation.Roll = 0;
	}

	if(WatchCameraPawn != P)
	{
		WatchCameraPawn = P;
		Log("ModCoop: Scene camera on " $ P);
		ServerCoopWatchCameraOn(P);
		WatchCameraRotation = DesiredRotation;
		GetAxes(WatchCameraRotation, X, Y, Z);
		WatchCameraLocation = Head - X * 180 + Y * 50 + Z * 25;
		WatchCameraTime = Level.TimeSeconds;
	}

	DeltaTime = FClamp(Level.TimeSeconds - WatchCameraTime, 0, 0.1);
	WatchCameraTime = Level.TimeSeconds;

	// Looking around follows the mouse quicker than the scene camera
	if(bLiftView)
		WatchCameraRotation = Normalize(WatchCameraRotation + Normalize(DesiredRotation - WatchCameraRotation) * FMin(1.0, DeltaTime * 12));
	else
		WatchCameraRotation = Normalize(WatchCameraRotation + Normalize(DesiredRotation - WatchCameraRotation) * FMin(1.0, DeltaTime * 4));
	WatchCameraRotation.Roll = 0;

	GetAxes(WatchCameraRotation, X, Y, Z);
	Desired = Head - X * 180 + Y * 50 + Z * 25;

	// Not into walls
	if(Trace(HitLocation, HitNormal, Desired, Head, false, vect(8,8,8)) != None)
		Desired = HitLocation;

	WatchCameraLocation = WatchCameraLocation + (Desired - WatchCameraLocation) * FMin(1.0, DeltaTime * 10);

	if(class'CoopConfig'.default.bDebugLog && Level.TimeSeconds >= NextWatchLog)
	{
		NextWatchLog = Level.TimeSeconds + 0.1;
		Log("CoopDebug: scene camera Z=" $ int(WatchCameraLocation.Z) $ " helmet Z=" $ int(Head.Z) $ " pawn Z=" $ int(P.Location.Z) $ " Physics=" $ P.Physics);
	}

	// Not the member: the view actor isn't drawn in first person
	ViewActor = self;
	CameraLocation = WatchCameraLocation;
	CameraRotation = WatchCameraRotation;
}

/*
 * A squad member taken over from the AI kept EyeHeight 0 on the client: Pawn.BecomeViewTarget, which turns the eye height on, only
 * runs on the server. Fixer's camera was at the center of his body, 60 units too low.
 */
simulated function FixEyeHeight()
{
	if(Pawn == None || !(IsInState('PlayerWalking') || IsInState('CoopSpaceWalk')))
		return;

	// After a door breach (the AI had the pawn) the client's copy of the pawn had no controller: Pawn.UpdateEyeHeight set the eye
	// height to 0 every tick (the camera was in the body, the own model was drawn) and the first person weapon wasn't drawn
	if(Pawn.Controller != self)
	{
		Log("ModCoop: " $ Pawn $ " had the controller " $ Pawn.Controller $ ", setting it to this player");
		Pawn.Controller = self;
		Pawn.bUpdateEyeHeight = false;
	}

	if(Pawn.bUpdateEyeHeight)
		return;

	if(EyeFixedPawn != Pawn)
	{
		EyeFixedPawn = Pawn;
		Log("ModCoop: Turning on the eye height of " $ Pawn $ " (EyeHeight=" $ Pawn.EyeHeight $ ")");
	}

	Pawn.bUpdateEyeHeight = true;
	Pawn.EyeHeight = Pawn.BaseEyeHeight;
}

simulated function RestoreWatchedPawn()
{
	local int i;

	if(WatchHiddenPawn == None && WatchHiddenActors.Length == 0)
		return;

	for(i = 0; i < WatchHiddenActors.Length; i = i + 1)
	{
		if(WatchHiddenActors[i] != None)
			WatchHiddenActors[i].bHidden = false;
	}

	WatchHiddenActors.Length = 0;
	WatchHiddenPawn = None;
}

// CTPlayer always spawns CTHUD
function SpawnDefaultHUD()
{
	if(myHUD == None)
		myHUD = Spawn(class'CoopHUD', self);

	Super.SpawnDefaultHUD();
}

simulated function bool IsDeltaMember(Pawn P)
{
	return P.IsA('Commando07Delta') || P.IsA('Commando40Delta') || P.IsA('Commando62Delta');
}

// Health of other pawns and the squad aren't replicated, the squad icons show them (see CoopGame.SyncSquadHealth)
simulated function ClientCoopSetSquadState(Pawn P, float NewHealth, bool bSquadMember, byte IconX, byte IconY, byte MarkerState)
{
	local int i;

	if(P == None || P.Role == ROLE_Authority)
		return;

	P.Health = NewHealth;

	for(i = SquadIconMembers.Length - 1; i >= 0; i = i - 1)
	{
		if(SquadIconMembers[i] == None || SquadIconMembers[i] == P)
		{
			SquadIconMembers.Remove(i, 1);
			SquadIconStates.Remove(i, 1);
		}
	}

	if(bSquadMember)
	{
		SquadIconStates[SquadIconMembers.Length] = IconX * 4096 + IconY * 256 + MarkerState;
		SquadIconMembers[SquadIconMembers.Length] = P;
	}
}

// See CoopGame.GetSquadIconState
simulated function GetSquadIconState(Pawn P, out byte IconX, out byte IconY, out byte MarkerState)
{
	local int i;

	IconX = 1;
	IconY = 4;
	MarkerState = 0;

	for(i = 0; i < SquadIconMembers.Length; i = i + 1)
	{
		if(SquadIconMembers[i] == P)
		{
			IconX = SquadIconStates[i] / 4096;
			IconY = (SquadIconStates[i] / 256) % 16;
			MarkerState = SquadIconStates[i] % 256;
			return;
		}
	}
}

simulated function bool IsSquadIconMember(Pawn P)
{
	local int i;

	for(i = 0; i < SquadIconMembers.Length; i = i + 1)
	{
		if(SquadIconMembers[i] == P)
			return true;
	}

	return false;
}

/*
 * Single player puts a new pawn in tactical vision (PlayerController.GivePawn, Possess: VisorModeDefault != 1, only standalone). Coop
 * didn't, and the helmet shows the squad's names only in tactical vision (APawn::PostRender, InTacticalVisionMode). The local player's
 * pawn gets it here too, as soon as it has its headlamp (GotoVisionMode needs it). Host and clients, both run it for themselves only.
 */
simulated function CheckVisionMode()
{
	if(Pawn == None || Pawn == VisionModePawn || Viewport(Player) == None || Pawn.Flashlight == None)
		return;

	VisionModePawn = Pawn;

	if(VisorModeDefault != 1 && Pawn.CurrentUserVisionMode == 0)
	{
		// A briefing or a scene keeps the mode it found and puts it back at its end (PlayerController states): the host's pawn was put
		// back to 0 that way (test 2026-11-12). Single player set it before them
		SavedVisionMode = 1;

		if(!bBriefing)
			GotoVisionMode(1);

		Log("ModCoop: vision mode " $ Pawn.CurrentUserVisionMode $ " (after a briefing or scene " $ SavedVisionMode $ ") for " $ Pawn);
	}
}

// Emitters are not replicated: effects of doors, panels, droid dispensers and props the server spawned (see CoopGame.ForwardEffect)
simulated function ClientCoopSpawnEffect(class<Emitter> EffectClass, vector EffectLocation, rotator EffectRotation, Actor AttachTo)
{
	local Emitter E;

	if(EffectClass == None)
		return;

	E = Spawn(EffectClass,,, EffectLocation, EffectRotation);

	if(E != None && AttachTo != None)
		E.SetBase(AttachTo);
}

/*
 * Level scripts change the HUD of the first player only (ACTION_ShowActorObjectiveTracker, ACTION_BlinkHUD..., ACTION_ShakeView,
 * ACTION_ScreenFade) or of the players with a HUD on the server (critical messages). The server forwards them (see CoopExtension).
 */
simulated function ClientCoopObjectiveTracker(Actor A, vector Location, bool bShow)
{
	if(Helmet == None)
		return;

	if(bShow != Helmet.bShowObjectiveTracker)
		Log("ModCoop: objective tracker " $ bShow $ " " $ A $ " " $ Location);

	if(!bShow)
		Helmet.HideObjectiveTracker();
	else if(A != None)
		Helmet.ShowActorObjectiveTracker(A);
	else
		Helmet.ShowPositionObjectiveTracker(Location);
}

simulated function ClientCoopBlinkHUD(byte Element, float BlinkTime)
{
	if(Helmet == None)
		return;

	switch(Element)
	{
	case 0: BlinkHUDSquad(BlinkTime); break;
	case 1: BlinkHUDSquadCommandPrompt(BlinkTime); break;
	case 2: BlinkHUDGrenade(BlinkTime); break;
	case 3: BlinkHUDHealth(BlinkTime); break;
	case 4: BlinkHUDShields(BlinkTime); break;
	}
}

simulated function ClientCoopShakeView(float InTime, float SustainTime, float OutTime, vector TranslationMag, rotator RotationMag, float Frequency)
{
	ShakeView(InTime, SustainTime, OutTime, TranslationMag.X, TranslationMag.Y, TranslationMag.Z, RotationMag.Yaw, RotationMag.Pitch, Frequency);
}

simulated function ClientCoopScreenFade(float FadeTime, color FadeColor)
{
	StartScreenFade(FadeTime, FadeColor);
}

// Map actors that events change only on the server (see CoopTriggerForward). Client, sent by the server.
simulated function ClientCoopTriggerActor(Actor A)
{
	class'CoopTriggerForward'.static.TriggerOnClient(A);
}

simulated function ClientCoopTriggerLocal(name EventTag, bool bUnTrigger)
{
	class'CoopTriggerForward'.static.TriggerTagOnClient(self, EventTag, bUnTrigger);
}

simulated function ClientCoopTriggerMaterial(string MaterialPath)
{
	class'CoopTriggerForward'.static.TriggerMaterialOnClient(self, MaterialPath);
}

// Level script actions that only reach the server's player (see CoopActionForward). Client, sent by the server.
simulated function ClientCoopRunAction(string ActionPath)
{
	class'CoopActionForward'.static.RunOnClient(self, ActionPath);
}

simulated function ClientCoopCriticalMessage(string Message, float Duration, color TextColor)
{
	if(myHUD != None)
		myHUD.AddCriticalMessage(Message, Duration, TextColor);
}

// State of the mission objectives, one digit per objective (see CoopGame.SyncObjectives). The helmet shows the current one.
simulated function ClientCoopSetObjectives(MissionObjectives O, string States, int Current)
{
	local int i;

	if(O == None || O.Role == ROLE_Authority)
		return;

	for(i = 0; i < O.MissionObj.Length && i < Len(States); i = i + 1)
		O.MissionObj[i].Stat = EObjectiveMode(int(Mid(States, i, 1)));

	O.CurrentObjective = Current;
	Objectives = O;
}

// Test propinfo (CoopGame.TickTest): the props as the client sees them
// Test only (CoopGame options CoopTestLag, CoopTestGPF): simulated network delay or a crash on purpose on this client
simulated function ClientCoopTestLag(int Milliseconds)
{
	if(Milliseconds < 0)
	{
		Log("ModCoop: Test crash on purpose");
		DebugStep("test crash on purpose");
		ConsoleCommand("DEBUG GPF");
		return;
	}

	Log("ModCoop: Test network delay " $ Milliseconds $ " ms: " $ ConsoleCommand("PKTLAG=" $ Milliseconds));
}

// Test only: a console command on this client (e.g. CoopGame test "weaponpickup" switches weapons like the player)
simulated function ClientCoopTestCommand(string Command)
{
	local ActivateItem Panel;
	local Pawn FacingPawn;
	local Inventory Inv;
	local MarkerIconActor Icon;
	local Mover Mov;
	local Turret Tur;
	local Actor A, Piece;
	local vector Aim;

	// Holding fire like the button (the console alias Fire doesn't work from a console command)
	if(Command ~= "HoldFire" || Command ~= "ReleaseFire")
	{
		bFire = byte(Command ~= "HoldFire");
		Log("ModCoop: Test " $ Command $ ": Weapon=" $ Pawn.Weapon $ " State=" $ Pawn.Weapon.GetStateName() $ " Ammo=" $ Pawn.Weapon.AmmoType.AmmoAmount);

		if(bFire != 0)
			Fire(0);
		else
			StopFire(0);

		return;
	}

	// Test only: the client turns the turret as its mouse would / logs what its view and its copy of the turret say
	if(Command ~= "TurretAim")
	{
		TurretYaw = 3000;
		TurretPitch = -1000;
		return;
	}

	// Test only: holds Use on a panel, as if the crosshair was on it
	if(Left(Command, 9) ~= "UsePanel ")
	{
		foreach DynamicActors(class'ActivateItem', Panel)
		{
			if(string(Panel.Tag) ~= Mid(Command, 9) || string(Panel.Name) ~= Mid(Command, 9))
			{
				Target = Panel;
				TargetType = TGT_Panel;
				bUse = true;
				Log("ModCoop: Test UsePanel " $ Panel $ " State=" $ Panel.GetStateName());
				Use();
			}
		}

		return;
	}

	// Test only: the detonator's hand signal, as if the crosshair was on the armed charge
	if(Command ~= "Detonate")
	{
		TargetType = TGT_DemolitionReady;
		Log("ModCoop: Test Detonate");
		StartHandSignal();
		return;
	}

	// Test only: the marker holograms near the pawn as this client has them
	if(Command ~= "MarkerIcons")
	{
		foreach AllActors(class'MarkerIconActor', Icon)
		{
			if(Pawn != None && VSize(Icon.Location - Pawn.Location) < 800)
				Log("CoopTest: icon " $ Icon.Class.Name $ " " $ Icon $ " hidden " $ Icon.bHidden $ " alpha " $ Icon.CurrentAlpha $ " morph " $ Icon.CurrentMorph $ " mesh " $ Icon.StaticMesh $ " state " $ Icon.GetStateName() $ " role " $ Icon.Role $ " dist " $ int(VSize(Icon.Location - Pawn.Location)) $ " anchor " $ SquadMarker(Icon).Anchor $ " allowed " $ IsMarkerShown(SquadMarker(Icon)) $ " target " $ Target $ " TargetMarker " $ TargetMarker);
		}

		return;
	}

	// Test only: the nearest hologram, shown at full alpha, then every change of it logged each frame (WatchIconTick)
	if(Command ~= "WatchIcon")
	{
		foreach AllActors(class'MarkerIconActor', Icon)
		{
			if(Pawn != None && (WatchIcon == None || VSize(Icon.Location - Pawn.Location) < VSize(WatchIcon.Location - Pawn.Location)))
				WatchIcon = Icon;
		}

		WatchIcon.bHidden = false;
		WatchIcon.CurrentAlpha = 1;
		WatchIcon.CurrentMorph = 1;
		bIconWatchHidden = false;
		WatchAlpha = 1;
		class'CoopPlayer'.default.WatchIcon = WatchIcon;
		Log("CoopTest: watch " $ WatchIcon $ " state " $ WatchIcon.GetStateName() $ " at " $ Level.TimeSeconds);
		return;
	}

	// Test only: the holograms near the pawn shown at full alpha (does that draw them?)
	if(Command ~= "ForceIcons")
	{
		foreach AllActors(class'MarkerIconActor', Icon)
		{
			if(Pawn != None && VSize(Icon.Location - Pawn.Location) < 800)
			{
				Icon.bHidden = false;
				Icon.CurrentAlpha = 1;
				Icon.CurrentMorph = 1;

				Log("CoopTest: icon forced " $ Icon);
			}
		}

		return;
	}

	// Test only: bring up the weapon of that class (HoldWeapon DC17mSniper)
	if(Left(Command, 11) ~= "HoldWeapon ")
	{
		for(Inv = Pawn.Inventory; Inv != None; Inv = Inv.Inventory)
		{
			if(Weapon(Inv) != None && string(Inv.Class.Name) ~= Mid(Command, 11) && Pawn.Weapon != Inv)
			{
				Pawn.PendingWeapon = Weapon(Inv);

				if(Pawn.Weapon != None)
					Pawn.Weapon.PutDown(Pawn.PendingWeapon);
				else
					Pawn.ChangedWeapon();
			}
		}

		Log("ModCoop: Test HoldWeapon " $ Mid(Command, 11) $ ": " $ Pawn.Weapon $ " pending " $ Pawn.PendingWeapon);
		return;
	}

	// Test only: revive the host with the bacta healer, as if the crosshair was on him and the use key held until he is up
	if(Command ~= "ReviveHost")
	{
		foreach DynamicActors(class'Pawn', FacingPawn)
		{
			if(FacingPawn != Pawn && FacingPawn.bIncapacitated && FacingPawn.IsA('PlayerCommando'))
			{
				Target = FacingPawn;
				TargetType = TGT_FriendToHeal;
				bUse = true;
				Log("ModCoop: Test ReviveHost " $ FacingPawn);
				Use();
			}
		}

		return;
	}

	if(Command ~= "StopPanel")
	{
		bUse = false;
		StopUse();
		return;
	}

	// Test only: see FacingLine
	if(Command ~= "FacingLog")
	{
		foreach DynamicActors(class'Pawn', FacingPawn)
		{
			if(FacingPawn != Pawn && FacingPawn.Health > 0 && !FacingPawn.IsA('Turret'))
				Log("CoopTest: facing: client " $ FacingLine(FacingPawn));
		}

		return;
	}

	// Test only: see RopeLine
	if(Command ~= "RopeLog")
	{
		Log("CoopTest: rope: client " $ RopeLines(self));
		return;
	}

	// Test only: see TestNetJump
	if(Command ~= "NetJump")
	{
		bTestNetJump = true;
		return;
	}

	// Living pawns other than commandos as this client has them (see CoopGame.TestEnemyText)
	if(Command ~= "PawnLog")
	{
		foreach DynamicActors(class'Pawn', FacingPawn)
		{
			if(FacingPawn.Health > 0 && !FacingPawn.IsA('CloneCommando'))
				Command = Command $ " " $ FacingPawn.Class.Name $ "@" $ int(FacingPawn.Location.X) $ "," $ int(FacingPawn.Location.Y);
		}

		Log("CoopTest: client pawns: " $ Command);
		return;
	}

	// What APawn::PostRender would write over each commando (EngineHUD names, see CoopExtension.PawnHudName)
	if(Command ~= "HudNames")
	{
		foreach DynamicActors(class'Pawn', FacingPawn)
		{
			if(FacingPawn.IsA('CloneCommando'))
				Log("CoopTest: hud names: " $ FacingPawn.Class.Name $ " description '" $ FacingPawn.GetHudDescription() $ "' nickname '" $ FacingPawn.GetHudNickname() $ "'");
		}

		return;
	}

	// Test only: this client's copy of the movers with a tag
	if(Left(Command, 9) ~= "MoverLog ")
	{
		foreach AllActors(class'Mover', Mov)
		{
			if(string(Mov.Tag) ~= Mid(Command, 9))
			{
				Log("CoopTest: mover: client " $ Mov $ " Key=" $ Mov.KeyNum $ " Stop=" $ Mov.ScriptTriggeredKeyframe $ " Moving=" $ Mov.bInterpolating $ " Loc=" $ Mov.Location $ " pawn Loc=" $ Pawn.Location $ " Base=" $ Pawn.Base);

				foreach DynamicActors(class'Actor', A)
				{
					if(A.Base == Mov || A.Tag == 'Walker')
						Log("CoopTest: mover: client on it " $ A $ " (" $ A.Class.Name $ ") Base=" $ A.Base $ " Loc=" $ A.Location $ " Rel=" $ A.RelativeLocation $ " Physics=" $ A.Physics $ " CollideWorld=" $ A.bCollideWorld $ " Collide=" $ A.bCollideActors $ " Role=" $ A.Role);
				}
			}
		}

		return;
	}

	// Test only: flashlights and accessories on pawns, with their owners (CTPlayer.SelectTargetType turns them into their Owner)
	if(Command ~= "AttachedLog")
	{
		foreach AllActors(class'Actor', A)
		{
			if((A.IsA('Flashlight') || A.IsA('Accessory')) && Pawn(A.Base) != None)
				Log("CoopTest: attached: " $ A.Class.Name $ " on " $ A.Base.Class.Name $ " Owner=" $ A.Owner $ " Role=" $ A.Role $ " Collide=" $ A.bCollideActors $ " ZeroTrace=" $ A.bBlockZeroExtentTraces $ " Hidden=" $ A.bHidden);
		}

		return;
	}

	// Test only: turn to the closest armour piece of another pawn (see CheckAccessoryOwners); "AccessoryFix 0/1" turns the fix off/on
	if(Command ~= "AimAccessory")
	{
		foreach DynamicActors(class'Actor', A)
		{
			// The piece that sticks out of its pawn's collision the most: inside it the trace hits the pawn first
			if(A.IsA('Accessory') && Pawn(A.Base) != None && A.Base != Pawn && VSize(A.Location - Pawn.Location) < 1500 && FastTrace(A.Location, Pawn.Location + Pawn.EyePosition()) &&
			   (Piece == None || VSize2D(A.Location - A.Base.Location) - A.Base.CollisionRadius > VSize2D(Piece.Location - Piece.Base.Location) - Piece.Base.CollisionRadius))
				Piece = A;
		}

		// At the part of the piece outside the pawn: its center pushed away from the pawn's axis
		if(Piece != None)
		{
			Aim = Piece.Location;
			Aim += Normal(Piece.Location - Piece.Base.Location) * vect(1,1,0) * 6;
			SetRotation(rotator(Aim - (Pawn.Location + Pawn.EyePosition())));
			Log("CoopTest: aimaccessory: out of the pawn by " $ int(VSize2D(Piece.Location - Piece.Base.Location) - Piece.Base.CollisionRadius));
		}

		Log("CoopTest: aimaccessory: " $ Piece $ " (" $ Piece.Class.Name $ ") on " $ Piece.Base $ " Owner=" $ Piece.Owner $ " dist " $ int(VSize(Piece.Location - Pawn.Location)) $ " Target=" $ Target $ " TargetType=" $ TargetType $ " fix " $ !bNoAccessoryFix);
		return;
	}

	if(Left(Command, 13) ~= "AccessoryFix ")
	{
		bNoAccessoryFix = Mid(Command, 13) == "0";

		// Without the fix the pieces are as a client gets them
		if(bNoAccessoryFix)
		{
			foreach DynamicActors(class'Actor', A)
			{
				if(Pawn(A.Base) != None && A.Owner == A.Base && (A.IsA('Accessory') || A.IsA('Flashlight')))
					A.SetOwner(None);
			}
		}

		Log("CoopTest: aimaccessory: fix " $ !bNoAccessoryFix);
		return;
	}

	// Test only: the visor mode, see CoopGame test namecolor
	if(Command ~= "VisionLog")
	{
		Log("CoopTest: namecolor: client mode " $ Pawn.CurrentUserVisionMode $ " flashlight " $ Pawn.Flashlight $ " tactical " $ InTacticalVisionMode() $ " visor default " $ VisorModeDefault $ " view " $ Rotation $ " at " $ Pawn.Location $ " ViewTarget " $ ViewTarget $ " state " $ GetStateName());

		foreach DynamicActors(class'Pawn', FacingPawn)
		{
			if(FacingPawn.PlayerReplicationInfo != None)
				Log("CoopTest: namecolor: client sees " $ FacingPawn $ " color " $ FacingPawn.EnhancedVisionColor.R $ "," $ FacingPawn.EnhancedVisionColor.G $ "," $ FacingPawn.EnhancedVisionColor.B);
		}

		return;
	}

	// Test only: Use as the player presses it, on what the crosshair is on now
	if(Command ~= "UseLooked")
	{
		Log("CoopTest: uselooked: Target=" $ Target $ " TargetType=" $ TargetType $ " State=" $ GetStateName() $ " Loc=" $ Pawn.Location $ " view=" $ Rotation $ " near turret " $ FindNearTurret());

		foreach DynamicActors(class'Turret', Tur)
			Log("CoopTest: uselooked: " $ TurretCollision(Tur) $ " dist " $ int(VSize(Tur.Location - Pawn.Location)) $ " dot " $ (Normal(Tur.Location - Pawn.Location) dot vector(Rotation)) $ " free " $ FastTrace(Tur.Location, Pawn.Location + Pawn.EyePosition()) $ " Gunner=" $ Tur.Gunner);

		Use();
		return;
	}

	if(Command ~= "TurretLog")
	{
		Log("CoopTest: aim: client Yaw=" $ TurretYaw $ " Pitch=" $ TurretPitch $ " view=" $ Rotation $ " Loc=" $ Pawn.Location $ " eye=" $ Pawn.EyePosition() $ " " $ TurretBones(Turret(Machine)));
		return;
	}

	Log("ModCoop: Test command " $ Command $ ": " $ ConsoleCommand(Command));
}

// Test only: actors that block players around Loc on this client (see CoopGame test "charge")
simulated function ClientCoopProbe(vector Loc, float Radius, int Step)
{
	local Actor A;

	foreach AllActors(class'Actor', A)
	{
		if(A.bCollideActors && (A.bBlockPlayers || A.bBlockActors) && Pawn(A) == None && (VSize(A.Location - Loc) < Radius || Volume(A) != None || Mover(A) != None || A.IsA('BlockingVolume')))
			Log("CoopTest: probe: client " $ Step $ " " $ A $ " (" $ A.Class $ ") Tag=" $ A.Tag $ " State=" $ A.GetStateName() $ " Hidden=" $ A.bHidden $ " Role=" $ A.Role $ " Static=" $ A.bStatic $ " Block=" $ A.bBlockActors $ A.bBlockPlayers $ " Mesh=" $ A.StaticMesh $ " Loc=" $ A.Location $ " Dist=" $ int(VSize(A.Location - Loc)));
	}
}

// Test only: where a pawn looks and where it goes (test facing)
static function string FacingLine(Pawn P)
{
	local name Seq;
	local float Frame;

	P.GetAnimParams('', Seq, Frame);

	return P.Class.Name $ " Loc=" $ int(P.Location.X) $ "," $ int(P.Location.Y) $ " yaw=" $ (P.Rotation.Yaw & 65535) $ " vel=" $ (rotator(P.Velocity).Yaw & 65535) $ " speed=" $ int(VSize(P.Velocity)) $ " anim=" $ Seq $ " phys=" $ P.Physics $ " pau=" $ P.bPhysicsAnimUpdate;
}

// Test only: the commandos and the ropes as this side has them (test rope)
static function string RopeLines(Actor Here)
{
	local Actor A;
	local string Line;
	local name Seq;
	local float Frame;

	foreach Here.AllActors(class'Actor', A)
	{
		if(A.IsA('Rope') || A.IsA('CloneCommando'))
		{
			A.GetAnimParams('', Seq, Frame);
			Line = Line $ " | " $ A.Class.Name $ " tag=" $ A.Tag $ " hidden=" $ A.bHidden $ " role=" $ A.Role $ " anim=" $ Seq $ " f=" $ int(Frame * 100) $ " z=" $ int(A.Location.Z) $ " rate=" $ A.IsAnimating() $ " phys=" $ A.Physics;

			if(Pawn(A) != None)
				Line = Line $ " pau=" $ Pawn(A).bPhysicsAnimUpdate $ " ctrl=" $ Pawn(A).Controller $ " vel=" $ int(VSize(A.Velocity));
		}
	}

	return Line;
}

// Test only: per second and pawn on the client: frames, frames it moved, biggest step of a frame against what its speed explains
simulated function TestNetJump(float DeltaTime)
{
	local Pawn P;
	local int i;
	local float Step;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P == Pawn || P.Health <= 0 || P.IsA('Turret'))
			continue;

		for(i = 0; i < JumpPawns.Length; ++i)
		{
			if(JumpPawns[i] == P)
				break;
		}

		if(i == JumpPawns.Length)
		{
			JumpPawns[i] = P;
			JumpLocs[i] = P.Location;
			JumpFrames[i] = 0;
			JumpMoved[i] = 0;
			JumpMax[i] = 0;
			JumpSum[i] = 0;
			JumpOver[i] = 0;
			continue;
		}

		Step = VSize(P.Location + P.PrePivot - JumpLocs[i]);
		JumpLocs[i] = P.Location + P.PrePivot;
		JumpFrames[i] = JumpFrames[i] + 1;

		if(Step > 0.01)
			JumpMoved[i] = JumpMoved[i] + 1;

		JumpSum[i] = JumpSum[i] + Step;

		if(Step > JumpMax[i])
			JumpMax[i] = Step;

		// Faster than a commando can run in this frame
		if(Step > FMax(VSize(P.Velocity), 300) * DeltaTime * 2 + 5)
			JumpOver[i] = JumpOver[i] + 1;
	}

	if(Level.TimeSeconds < NextJumpLog)
		return;

	NextJumpLog = Level.TimeSeconds + 1;
	Log("CoopTest: jump: t=" $ int(Level.TimeSeconds) $ " camera state=" $ GetStateName() $ " watch=" $ WatchCameraPawn $ " max=" $ int(JumpCameraMax));
	JumpCameraMax = 0;

	for(i = 0; i < JumpPawns.Length; ++i)
	{
		if(JumpPawns[i] != None && JumpSum[i] > 1)
			Log("CoopTest: jump: t=" $ int(Level.TimeSeconds) $ " " $ JumpPawns[i].Class.Name $ " frames=" $ JumpFrames[i] $ " moved=" $ JumpMoved[i] $ " jumps=" $ JumpOver[i] $ " max=" $ int(JumpMax[i]) $ " dist=" $ int(JumpSum[i]) $ " vel=" $ int(VSize(JumpPawns[i].Velocity)) $ " anim=" $ TestAnimName(JumpPawns[i]) $ " phys=" $ JumpPawns[i].Physics $ " freq=" $ JumpPawns[i].NetUpdateFrequency);

		JumpFrames[i] = 0;
		JumpMoved[i] = 0;
		JumpMax[i] = 0;
		JumpSum[i] = 0;
		JumpOver[i] = 0;
	}
}

static function name TestAnimName(Actor A)
{
	local name Seq;
	local float Frame;

	A.GetAnimParams('', Seq, Frame);

	return Seq;
}

static function string TurretBones(Turret T)
{
	if(T == None)
		return "no turret";

	return "turret rot=" $ T.Rotation $ " camera=" $ T.GetBoneLocation('camera') $ " " $ T.GetBoneRotation('camera') $ " muzzle=" $ T.GetBoneLocation('muzzle') $ " " $ T.GetBoneRotation('muzzle');
}

static function string TurretInfo(Turret T)
{
	return T $ " (" $ T.Class.Name $ ") State=" $ T.GetStateName() $ " PlayerUsable=" $ T.bPlayerUsable $ " Gunner=" $ T.Gunner $ " Controller=" $ T.Controller $
	       " ReservedBy=" $ T.ReservedBy $ " Auto=" $ T.bIsAuto $ " Hidden=" $ T.bHidden $ " Health=" $ T.Health $ " Collide=" $ T.bCollideActors $ " Marker=" $ T.SquadMarker $
	       " Role=" $ T.Role $ " Loc=" $ T.Location;
}

simulated function ClientCoopDumpProps(int Step)
{
	local Actor A;
	local Turret T;
	local Inventory I;
	local Weapon Found;
	local string Chain;
	local int Num;

	foreach AllActors(class'Turret', T)
		Log("CoopTest: turretinfo: client " $ Step $ " " $ TurretInfo(T));

	if(Pawn != None)
	{
		Chain = "";

		for(I = Pawn.Inventory; I != None && Num < 30; I = I.Inventory)
		{
			Chain = Chain $ " " $ I.Class.Name;
			++Num;
		}

		if(Pawn.Inventory != None)
			Found = Pawn.Inventory.WeaponChange(11, true);

		Log("CoopTest: inventory: client " $ Step $ " Weapon=" $ Pawn.Weapon.Class.Name $ " Old=" $ Pawn.OldWeapon.Class.Name $ " Hands=" $ Found $ " Items:" $ Chain);
	}

	foreach AllActors(class'Actor', A)
	{
		if(Prop(A) != None)
			Log("CoopTest: propinfo: client " $ Step $ " " $ A $ " Tag=" $ A.Tag $ " State=" $ A.GetStateName() $ " Collide=" $ A.bCollideActors $ A.bBlockActors $ A.bBlockPlayers $ " Hidden=" $ A.bHidden $ " Mesh=" $ A.StaticMesh $ " Role=" $ A.Role $ " Physics=" $ A.Physics $ " Loc=" $ A.Location $ " Rot=" $ A.Rotation $
			    " Skins=" $ A.Skins.Length $ " " $ A.Skins[0] $ " Style=" $ A.Style $ " Unlit=" $ A.bUnlit $ " Glow=" $ A.AmbientGlow $ " Zone=" $ A.Region.Zone $ " Instance=" $ A.StaticMeshInstance);
	}

	// Actors that only exist on this client and block players (the server's copy is gone or was never there)
	foreach AllActors(class'Actor', A)
	{
		if(A.Role == ROLE_Authority && !A.bStatic && !A.bNoDelete && A.bBlockPlayers && A.bCollideActors && Controller(A) == None && A != Pawn)
			Log("CoopTest: propinfo: localblock " $ Step $ " " $ A $ " (" $ A.Class $ ") Mesh=" $ A.StaticMesh $ " Physics=" $ A.Physics $ " Loc=" $ A.Location);
	}

	foreach AllActors(class'Actor', A)
	{
		if(A.Role == ROLE_Authority && A.bNoDelete && !A.bStatic && A.bBlockPlayers && A.bCollideActors && A.RemoteRole != ROLE_None)
			Log("CoopTest: propinfo: localnodelete " $ Step $ " " $ A $ " (" $ A.Class $ ") Mesh=" $ A.StaticMesh $ " Loc=" $ A.Location);
	}
}

// See CoopGame.SyncPanelStates: progress of planting a charge, hacking etc. shown by the HUD
simulated function ClientCoopSetPanelProgress(ActivateItem Item, float FractionComplete, float DurationRemaining, float ElapseSetupTime)
{
	if(Item == None || Item.Role == ROLE_Authority)
		return;

	Item.FractionComplete = FractionComplete;
	Item.DurationRemaining = DurationRemaining;
	Item.ElapseSetupTime = ElapseSetupTime;
}

// See CoopGame.SyncMapActorCollision
simulated function ClientCoopSetActorCollision(Actor A, bool bCollide, bool bBlockActors, bool bBlockPlayers, StaticMesh NewMesh, bool bNewHidden)
{
	if(A == None || A.Role == ROLE_Authority)
		return;

	if(NewMesh != None && A.StaticMesh != NewMesh)
		A.SetStaticMesh(NewMesh);

	A.SetCollision(bCollide, bBlockActors, bBlockPlayers);
	A.bHidden = bNewHidden;
}

// See CoopGame.SyncPanelStates
simulated function ClientCoopSetPanelState(ActivateItem Item, byte Flags, byte ItemType, Pawn UserPawn)
{
	if(Item == None || Item.Role == ROLE_Authority)
		return;

	Item.bIsUsable = (Flags & 1) != 0;
	Item.bIsUsableByPlayer = (Flags & 2) != 0;
	Item.bActivating = (Flags & 4) != 0;
	Item.bActivated = (Flags & 8) != 0;
	Item.bPlayerActivated = (Flags & 16) != 0;
	Item.ActivateItemType = EActivateItemType(ItemType);
	Item.Instigator = UserPawn;

	// Only the own controller exists on a client
	if(UserPawn != None && UserPawn == Pawn)
		Item.User = self;
	else
		Item.User = None;
}

// See CoopGame.SyncIdleStates. P is None if it is not relevant for this client.
simulated function ClientCoopSetIdleState(Pawn P, byte NewState)
{
	if(P != None && P.Role < ROLE_Authority && P.CurrentIdleState != NewState)
		P.CurrentIdleState = EIdleState(NewState);
}

simulated function ClientCoopPawnRevived()
{
	if(Role < ROLE_Authority)
	{
		CleanOutSavedMoves();
		EnterStartState();
		Log("ModCoop: Revived, controller state is now " $ GetStateName());
	}
}

// True on the listen server for the controller of the local player
// Pawn of another living player the dead client can watch until it respawns
function Pawn FindSpectateTarget()
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(C != self && PlayerController(C) != None && C.Pawn != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated)
			return C.Pawn;
	}

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(C != self && PlayerController(C) != None && C.Pawn != None)
			return C.Pawn;
	}

	return None;
}

simulated function bool IsCoopHost()
{
	return Level.NetMode != NM_Client && Viewport(Player) != None;
}

function Possess(Pawn APawn)
{
	if(CoopCommando(APawn) == None && !bCoopTakeover)
	{
		Super.Possess(APawn);
		return;
	}

	// Clients must not take over the squad. CTPlayer.Possess would call AssignSquadMembers which steals the host's squad.
	Super(PlayerController).Possess(APawn);
	APawn.bCanPickupInventory = true;

	if(APawn.bIncapacitated)
		GotoState('CtrlIncapacitated');
}

// Called by CTGameInfoSP.RestartPlayer. In single player this loads the last save game when the player died.
function bool RestartGame()
{
	if(IsCoopHost())
	{
		if(CoopGame(Level.Game) != None && CoopGame(Level.Game).bRespawningHost)
			return false;

		return Super.RestartGame();
	}

	return false; // Clients just respawn
}

// Console command for clients that got stuck or separated from the host
exec function CoopTeleportToHost()
{
	ServerTeleportToHost();
}

function ServerTeleportToHost()
{
	if(IsCoopHost() || CoopGame(Level.Game) == None || Level.TimeSeconds - LastTeleportRequest < 5.0)
		return;

	LastTeleportRequest = Level.TimeSeconds;

	if(!CoopGame(Level.Game).TeleportToHost(self))
		ClientCoopMessage("Can't move to the host right now.");
}

simulated function ClientCoopMessage(string Msg)
{
	ClientMessage(Msg);
}

/*
 * The engine only allows these in standalone games. On a listen server the host would be stuck after dying.
 */

exec function RestartLevel()
{
	if(Level.NetMode == NM_ListenServer && IsCoopHost())
	{
		if(CoopGame(Level.Game) != None)
			CoopGame(Level.Game).CoopRestartLevel();

		return;
	}

	Super.RestartLevel();
}

exec function LoadGame(string Name)
{
	if(Level.NetMode == NM_ListenServer && IsCoopHost())
	{
		if(CoopGame(Level.Game) != None)
			CoopGame(Level.Game).CoopRestartLevel();

		return;
	}

	Super.LoadGame(Name);
}

/*
 * The engine can't save the game on a listen server (UGameEngine::SaveGame refuses to write it). Instead, a coop "checkpoint" is the
 * beginning of the current level: when the host dies or loads, the level restarts and the clients follow without reconnecting.
 */
function AutoSave()
{
	if(Level.NetMode != NM_ListenServer)
		Super.AutoSave();
	else if(CoopGame(Level.Game) != None)
		CoopGame(Level.Game).SaveCheckpoint();
}

exec function QuickSave()
{
	if(Level.NetMode != NM_ListenServer)
	{
		Super.QuickSave();
		return;
	}

	ClientMessage("Saving is not available in coop. The level restarts from its beginning if the host dies.");
}

simulated function AddLiftLook(float DeltaTime)
{
	LiftLookYaw += 32 * DeltaTime * aTurn;
	LiftLookPitch = FClamp(LiftLookPitch + 32 * DeltaTime * aLookUp, -6000, 6000);
}

// See CoopGame.HideRiders: only the own commando is drawn while riding a lift (the others stand on the same spot)
simulated function ClientCoopHideRiders(bool bHide)
{
	local Pawn P;

	Log("ModCoop: Hide riders " $ bHide $ " NetMode=" $ Level.NetMode);

	if(Level.NetMode != NM_Client)
		return;

	bHideRiders = bHide;
	ApplyHideRiders();

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.IsA('CloneCommando'))
			Log("ModCoop: Riders hidden " $ bHide $ ": " $ P $ " (" $ P.Class.Name $ ") PRI=" $ P.PlayerReplicationInfo $ " Hidden=" $ P.bHidden $ " Own=" $ (P == Pawn));
	}
}

simulated function ApplyHideRiders()
{
	local Pawn P;
	local bool bHideThis;

	foreach DynamicActors(class'Pawn', P)
	{
		// GEO_05C: the level starts on a lift, the host's PRI hadn't arrived and the host stayed visible, the players stood in each other (session 2026-11-02)
		if(P.PlayerReplicationInfo == None && P != Pawn && !P.IsA('PlayerCommando') && !P.IsA('CoopCommando'))
			continue;

		bHideThis = bHideRiders && P != Pawn;

		if(bHideThis)
			class'CoopGame'.static.HidePawnParts(P, RideHiddenActors);
		else if(P == Pawn)
		{
			// The server hides the clients' commandos, this client's own one stays visible here
			if(P.bHidden)
				P.bHidden = false;

			if(P.Weapon != None && P.Weapon.ThirdPersonActor != None && P.Weapon.ThirdPersonActor.bHidden)
				P.Weapon.ThirdPersonActor.bHidden = false;
		}
	}

	if(!bHideRiders)
		class'CoopGame'.static.ShowHiddenParts(RideHiddenActors);
}

// See CoopGame.CheckLiftRides: the camera over the shoulder looking at the center of the lift car
simulated function ClientCoopLiftView(bool bOn, vector Center)
{
	LiftCenter = Center;

	if(bOn == bLiftView)
		return;

	Log("ModCoop: Lift view " $ bOn $ " center " $ Center $ " State=" $ GetStateName() $ " Pawn=" $ Pawn);
	bLiftView = bOn;
	LiftLookYaw = 0;
	LiftLookPitch = 0;

	if(bOn)
		SetHostOutsideLook(true);

	SetHostWaitAnim(bOn);

	// Behind view: the own model is drawn, no first person weapon (back to first person after the lift unless watching a scene).
	// With the scene camera on, first person comes when the camera has flown into the eyes (see PlayerCalcView): before, the own
	// model vanished and the first person weapon hung in the air while the camera was still flying.
	if(bOn)
	{
		bBehindView = true;
		bBlendToEyes = false;
	}
	else if(!IsInState('CoopWatching'))
	{
		if(WatchCameraPawn != None)
			bBlendToEyes = true;
		else
		{
			bBehindView = false;
			SetHostOutsideLook(false);
		}
	}
}

// Riding a lift with the host (CoopGame.CheckLiftRides): standing still like the host, looking around and shooting are allowed
state CoopLiftRide extends PlayerWalking
{
	ignores SeePlayer, HearNoise, Bump;

	exec function Jump(optional float F) {}

	function PlayerMove(float DeltaTime)
	{
		if(Pawn == None)
			return;

		Pawn.Acceleration = vect(0,0,0);

		if(bLiftView)
			AddLiftLook(DeltaTime);
		else
			UpdateRotation(DeltaTime, 2);

		if(Role < ROLE_Authority)
			ReplicateMove(DeltaTime, vect(0,0,0), DCLICK_None, rot(0,0,0));
		else
			ProcessMove(DeltaTime, vect(0,0,0), DCLICK_None, rot(0,0,0));
	}
}

// Watching the scene of the squad member the client will play (CoopGame.CheckSceneWatch): no controls until the takeover
state CoopWatching
{
	ignores SeePlayer, HearNoise, Bump;

	exec function Fire(optional float F) {}
	exec function AltFire(optional float F) {}
	exec function Use() {}
	exec function Jump(optional float F) {}
	exec function ThrowGrenade(optional float F) {}
	exec function SwitchWeapon(byte F) {}

	function PlayerMove(float DeltaTime)
	{
		if(Pawn != None)
			Pawn.Acceleration = vect(0,0,0);

		if(bLiftView)
			AddLiftLook(DeltaTime);
	}

	function BeginState()
	{
		if(Pawn != None)
		{
			Pawn.Velocity = vect(0,0,0);
			Pawn.Acceleration = vect(0,0,0);
		}

		// The client's own health, ammo and visor don't belong to the squad member it watches
		SetCoopHUDHidden(true);
		DestroyClientAttachItem();
	}

	function EndState()
	{
		SetCoopHUDHidden(false);
	}
}

/*
 * Flying with the host on RAS_01A (client, see CoopGame.SpawnClient and ClientCoopSpaceWalkPos): the camera is free and the first person weapon stays
 * in the hands, but nothing is sent: without ReplicateMove there is no ServerMove, so the server has no reason to send a correction.
 */
state CoopSpaceWalk
{
	ignores SeePlayer, HearNoise, Bump;

	exec function Fire(optional float F) {}
	exec function AltFire(optional float F) {}
	exec function Use() {}
	exec function Jump(optional float F) {}
	exec function ThrowGrenade(optional float F) {}
	exec function SwitchWeapon(byte F) {}

	function PlayerMove(float DeltaTime)
	{
		local vector ToTarget;
		local float Distance;

		if(Pawn == None)
			return;

		UpdateRotation(DeltaTime, 1);

		// Only SetLocation moves the flyer here, physics would pull it down between the updates
		if(Pawn.Physics != PHYS_None)
			Pawn.SetPhysics(PHYS_None);

		Pawn.Velocity = vect(0,0,0);
		Pawn.Acceleration = vect(0,0,0);
		ToTarget = SpaceWalkTarget - Pawn.Location;
		Distance = VSize(ToTarget);

		if(Distance > SPACE_WALK_SNAP_DISTANCE)
			Pawn.SetLocation(SpaceWalkTarget);
		else if(Distance > 0.5)
			Pawn.SetLocation(Pawn.Location + ToTarget * FMin(1.0, DeltaTime * SPACE_WALK_FOLLOW_RATE));
	}
}

simulated function SetCoopHUDHidden(bool bHidden)
{
	if(bHidden == bCoopHUDHidden)
		return;

	bCoopHUDHidden = bHidden;

	if(myHUD != None)
	{
		if(bHidden)
			bWasHUDHidden = myHUD.bHideHUD;

		myHUD.bHideHUD = bHidden || bWasHUDHidden;
	}

	if(Helmet != None)
	{
		if(bHidden)
			bWasHelmetDrawn = Helmet.bDraw;

		Helmet.bDraw = !bHidden && bWasHelmetDrawn;
	}
}

state PlayerManningTurret
{
	simulated function BeginState()
	{
		if(Level.NetMode != NM_Client)
		{
			Super.BeginState();

			// A client that got on the turret through the original Use (GEO_04A: not ServerCoopUseTurret) had no local aiming: its shots
			// all went to one spot and the turret stayed in its hands after leaving. Any way onto a turret sets the client up now.
			if(Viewport(Player) == None && Turret(Machine) != None && Turret(Machine).Gunner == Pawn)
			{
				Machine.bHidden = false;
				Log("CoopPlayer: " $ PlayerReplicationInfo.PlayerName $ " is on " $ Machine $ ", setting up the client's turret controls");
				ClientCoopManTurret(Turret(Machine), Turret(Machine).Yaw, Turret(Machine).Pitch, Machine.Rotation.Pitch, Machine.Rotation.Yaw, Machine.Rotation.Roll);
			}

			return;
		}

		if(Pawn != None)
		{
			Pawn.Velocity = vect(0,0,0);
			Pawn.Acceleration = vect(0,0,0);
		}
	}

	simulated function EndState()
	{
		if(Level.NetMode != NM_Client)
		{
			Super.EndState();

			// See BeginState: the client leaves its turret controls whatever made the server leave the turret
			if(Viewport(Player) == None)
			{
				ClientCoopLeaveTurret();

				if(Pawn != None && Pawn.Weapon == None)
					SwitchToBestWeapon();

				ClientSwitchToBestWeapon();
			}
		}
	}

	function PlayerMove(float DeltaTime)
	{
		local Turret T;
		local vector Loc;
		local float SpeedMax;
		local Inventory Inv;

		if(Level.NetMode != NM_Client)
		{
			Super.PlayerMove(DeltaTime);
			return;
		}

		T = Turret(Machine);

		if(T == None || Pawn == None)
			return;

		// Same limits as Turret.ChangeAngle
		SpeedMax = T.Speed * DeltaTime;
		TurretYaw += FClamp(DeltaTime * aTurn * 32, -SpeedMax, SpeedMax);
		TurretPitch += FClamp(DeltaTime * aLookUp * 32, -SpeedMax, SpeedMax);

		if(!T.bUnlimitedYaw)
			TurretYaw = Clamp(TurretYaw, T.MinYaw, T.MaxYaw);

		TurretPitch = Clamp(TurretPitch, T.MinPitch, T.MaxPitch);

		SetRotation(TurretView(T, TurretYaw, TurretPitch));

		Loc = T.Location;
		Loc.Z += T.TurretHeight;
		Pawn.SetLocation(Loc);
		Pawn.Velocity = vect(0,0,0);
		Pawn.Acceleration = vect(0,0,0);

		// The turret's first person weapon comes from the server a moment later
		if(Pawn.Weapon == None || Pawn.Weapon.WeaponType != WT_Turret)
		{
			for(Inv = Pawn.Inventory; Inv != None; Inv = Inv.Inventory)
			{
				if(Weapon(Inv) != None && Weapon(Inv).WeaponType == WT_Turret && Pawn.PendingWeapon != Inv)
				{
					Pawn.PendingWeapon = Weapon(Inv);

					if(Pawn.Weapon == None)
						Pawn.ChangedWeapon();
					else
						Pawn.Weapon.PutDown(Weapon(Inv));

					break;
				}
			}
		}

		// The ammo of the turret's weapon isn't linked to it on the client, it fired nothing (Weapon.Fire: no ammo)
		if(Pawn.Weapon != None && Pawn.Weapon.WeaponType == WT_Turret && Pawn.Weapon.AmmoType == None)
		{
			for(Inv = Pawn.Inventory; Inv != None; Inv = Inv.Inventory)
			{
				if(Ammunition(Inv) != None && Inv.Class == Pawn.Weapon.AmmoName)
				{
					Pawn.Weapon.AmmoType = Ammunition(Inv);
					Log("ModCoop: Linked " $ Inv $ " to the turret weapon");
					break;
				}
			}
		}

		if((TurretYaw != SentTurretYaw || TurretPitch != SentTurretPitch) && Level.TimeSeconds >= NextTurretSend)
		{
			NextTurretSend = Level.TimeSeconds + 0.03;
			SentTurretYaw = TurretYaw;
			SentTurretPitch = TurretPitch;
			ServerCoopTurretAim(TurretYaw, TurretPitch);
		}

		if(class'CoopConfig'.default.bDebugLog && Level.TimeSeconds >= NextTurretLog)
		{
			NextTurretLog = Level.TimeSeconds + 2;
			Log("ModCoop: Turret " $ T $ " Yaw=" $ TurretYaw $ " Pitch=" $ TurretPitch $ " aTurn=" $ aTurn $ " aLookUp=" $ aLookUp $ " bFire=" $ bFire $
			    " Weapon=" $ Pawn.Weapon $ " (" $ Pawn.Weapon.GetStateName() $ ", " $ Pawn.Weapon.WeaponType $ ") Ammo=" $ Pawn.Weapon.AmmoType $ " " $ Pawn.Weapon.AmmoType.AmmoAmount);
		}

		ViewShake(DeltaTime);
		ViewFlash(DeltaTime);
	}

	exec function Use()
	{
		// Like the original: markers and enemies are orders to the squad, anything else leaves the turret (on the server)
		if(Level.NetMode == NM_Client && TargetType != TGT_Marker && TargetType != TGT_MarkerCancel && TargetType != TGT_Enemy && TargetType != TGT_EngagedEnemy)
		{
			ServerCoopUseTurret(Turret(Machine));
			return;
		}

		Super.Use();
	}
}

state UsingItem
{
	function BeginState()
	{
		Super.BeginState();
		UsingItemStart = Level.TimeSeconds;

		// Not when the server's position correction put us back into this state after the use key was released (see PlayerTick)
		if(Role < ROLE_Authority && bUse)
			ServerCoopUsingItem(true, Target, TargetType);
	}

	/*
	 * CTPlayer.UsingItem.PlayerTick asserts bUse. A client that released the use key leaves the state but the server only follows
	 * a moment later: its position correction (ClientAdjustPosition sends the server's state) could put the client back into
	 * UsingItem with bUse false and the assertion crashed the game (seen on GEO_01C).
	 */
	event PlayerTick(float DeltaTime)
	{
		// The state has its own PlayerTick, the checks of the global one don't run here (see ResetStaleHands). BringUpUsingHands is a
		// safety net: "no weapon while using" in a log means there is another way to lose the weapon
		if(Role < ROLE_Authority)
		{
			TraceWeapons();
			ResetStaleHands();
			BringUpUsingHands();
		}

		/*
		 * Clients revived a squad member at once: the time to revive (TotalTimeToRevive, set by the native target selection) was 0
		 * on the client. At least the 2 s of the engine's old TimeToRevive constant.
		 */
		if(Level.NetMode == NM_Client && TargetType == TGT_FriendToHeal && TotalTimeToRevive < 2.0)
		{
			// Once per revive, the native code may set it again every frame
			if(HealingTime == 0)
				Log("ModCoop: time to revive was " $ TotalTimeToRevive $ " s, using 2 s");

			TotalTimeToRevive = 2.0;
		}

		if(!bUse)
		{
			GotoState('PlayerWalking');
			return;
		}

		if(Level.NetMode == NM_Client)
			FixHandSignalWeapon(DeltaTime);

		Super.PlayerTick(DeltaTime);
	}

	function EndState()
	{
		Super.EndState();

		if(Role < ROLE_Authority)
			ServerCoopUsingItem(false, None, TGT_Default);
	}
}

// See also PlayerMove: the briefing at the start of a level (GEO_03A: the elevator) locks the player in Briefing, where the mouse
// turns the pawn. With the scene camera over the shoulder (CoopGame.CheckLiftRides) the host's commando was the only one turning
// with the view. The mouse only moves the camera then, like in CoopLiftRide.
state Briefing
{
	function PlayerMove(float DeltaTime)
	{
		if(bLiftView)
		{
			AddLiftLook(DeltaTime);
			return;
		}

		Super.PlayerMove(DeltaTime);
	}

	exec function Use()
	{
		local string CurrentMap;
		local string NextMap;
		local int CurrentLevelIndex;

		if(Level.NetMode == NM_Standalone)
		{
			Super.Use();
			return;
		}

		if(!IsCoopHost() || CoopGame(Level.Game) == None)
			return;

		// Same as the single player version but uses server travel so that clients follow the host
		GetCurrentMapName(CurrentMap);

		if(InStr(Caps(CurrentMap), "BRIEFING") != -1)
		{
			CurrentLevelIndex = GetLevelIndex(CurrentMap);

			if(CurrentLevelIndex < LevelProgress && CurrentLevelIndex != -1)
			{
				GetNextLevel(CurrentLevelIndex, NextMap);

				if(GetLevelIndex(NextMap) != -1)
				{
					CoopGame(Level.Game).CoopTravel(NextMap);
				}
			}
		}
	}
}

state Dead
{
	function BeginState()
	{
		local Pawn SpectateTarget;

		if(IsCoopHost())
		{
			Super.BeginState();
			return;
		}

		// Same as PlayerController.Dead.BeginState without the fade to white, bloom and blur. Single player loads a save game
		// afterwards which resets them, a respawned client kept the white screen forever.
		EndZoom();
		FOVAngle = DesiredFOV;

		if(Pawn != None && Pawn.Weapon != None)
			Pawn.Weapon.SetWeapFOV(FOVAngle);

		Enemy = None;
		bFrozen = true;
		bJumpStatus = false;
		bPressedJump = false;
		StopForceFeedback();
		ClientPlayForceFeedback("Damage");
		CleanOutSavedMoves();
		SetTimer(5, false);

		if(Role < ROLE_Authority)
			return;

		// Watch another player until the respawn
		SpectateTarget = FindSpectateTarget();

		if(SpectateTarget != None)
		{
			SetViewTarget(SpectateTarget);
			ClientSetViewTarget(SpectateTarget);
			bBehindView = true;
			ClientSetBehindView(true);
		}

		ClientCoopMessage("You are dead. You will respawn next to the host shortly.");
	}

	function Timer()
	{
		// Clients don't get the single player death menu (it would load a save game locally). The server respawns them automatically.
		if(Level.NetMode == NM_Client || !IsCoopHost())
		{
			bFrozen = false;
			bPressedJump = false;
			return;
		}

		Super.Timer();
	}
}

defaultproperties
{
	HostSkin=Shader'CloneTextures.CloneTextures.CloneCommandoWhite_Shader'
}
