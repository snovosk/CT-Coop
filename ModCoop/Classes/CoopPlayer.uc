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
var int         DisplaySyncPasses;
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
var Pawn        WatchedMember;
var Pawn        WatchHiddenPawn;      // Client only: watched squad member hidden while its scene is seen through its eyes (see PlayerCalcView)
var array<Actor> WatchHiddenActors;
var vector      WatchCameraLocation;
var rotator     WatchCameraRotation;
var float       WatchCameraTime;
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
};
var array<SmoothedPawn> SmoothedPawns;
var vector      BlockCheckLocation;   // Client only: see CheckBlocked
var float       BlockCheckTime;
var float       NextBlockLog;
var float       NextCorrectionLog;
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
var int         TurretYaw, TurretPitch;     // Client: the aim of the turret it mans (see state PlayerManningTurret)
var int         SentTurretYaw, SentTurretPitch;
var float       NextTurretSend, NextTurretLog;
var CoopAnimController AnimController;     // Client: see ClientCoopScriptAnim
var int         LastCommandoCount;          // Client: see LogCommandos
var bool        bLiftView;                  // Riding a lift: the camera over the shoulder looks at the center of the car (ClientCoopLiftView)
var vector      LiftCenter;
var float       LiftLookYaw, LiftLookPitch; // Looking around from there
var bool        bLiftViewSent;              // Server: ClientCoopLiftView(true) was sent
var bool        bHideRiders;                // Client: see ClientCoopHideRiders
var array<Actor> RideHiddenActors;
var bool        bHideRidersSent;            // Server: ClientCoopHideRiders(true) was sent
var bool        bLiftFaced;                 // Server: turned to the middle of the lift (CoopGame.FaceLiftCenter)

replication
{
	reliable if(Role == ROLE_Authority)
		ClientCoopMessage, ClientCoopPawnRevived, ClientCoopSetIncapacitated, ClientCoopSetIdleState, ClientCoopSetPanelState, ClientCoopTakeoverCamera, ClientCoopSetActorCollision;
	reliable if(Role == ROLE_Authority)
		ClientCoopDumpProps, ClientCoopObjectiveTracker, ClientCoopBlinkHUD, ClientCoopShakeView, ClientCoopScreenFade, ClientCoopCriticalMessage, ClientCoopSetObjectives, ClientCoopTestLag, ClientCoopTestCommand, ClientCoopProbe, ClientCoopSetWatchFocus, ClientCoopSetCollisionByTag, ClientCoopSetHiddenByTag, ClientCoopSetMarkerState, ClientCoopManTurret, ClientCoopLeaveTurret, ClientCoopScriptAnim, ClientCoopEndScriptAnim, ClientCoopLiftView, ClientCoopHideRiders;
	unreliable if(Role == ROLE_Authority)
		ClientCoopSetSquadState, ClientCoopSpawnEffect, ClientCoopSetActorDisplay, ClientCoopSetActorLook, ClientCoopSetPanelLinks, ClientCoopSetPanelProgress, ClientCoopSetLight;
	reliable if(Role < ROLE_Authority)
		ServerTeleportToHost, ServerCoopSetTarget, ServerCoopUsingItem, ServerCoopUsePanel, ServerCoopStartHandSignal, ServerCoopReady, ServerCoopWatchCameraOn, ServerCoopUseTurret;
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

	Log("ModCoop: Joined coop host " $ ServerAddress);
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
simulated function ClientCoopSetPanelLinks(ActivateItem Item, SquadMarker Marker, NavigationPoint Nav0, NavigationPoint Nav1, bool bUsableByPlayer)
{
	local Actor A;

	if(Item == None || Item.Role == ROLE_Authority)
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

simulated function ClientCoopEndScriptAnim(Pawn P)
{
	if(Level.NetMode != NM_Client || P == None || P.Controller != AnimController || AnimController == None)
		return;

	P.Controller = None;
	P.ChangeAnimation();
}

// See CoopGame.ForwardMarkerState
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

simulated function ClientCoopSetActorDisplay(Actor A, float ScaleX, float ScaleY, float ScaleZ, vector NewPrePivot, Material Skin0, Material Skin1)
{
	local vector NewScale3D;

	if(A == None || A.Role == ROLE_Authority)
		return;

	NewScale3D.X = ScaleX;
	NewScale3D.Y = ScaleY;
	NewScale3D.Z = ScaleZ;

	if(A.DrawScale3D != NewScale3D)
		if(A.DrawScale3D != NewScale3D)
		A.SetDrawScale3D(NewScale3D);

	A.PrePivot = NewPrePivot;

	if(Skin0 != None)
		A.Skins[0] = Skin0;

	if(Skin1 != None)
		A.Skins[1] = Skin1;
}

// See CoopGame.NeedsLookSync
simulated function ClientCoopSetActorLook(Actor A, name NewTag, byte Glow, bool bNewUnlit, string InstanceName, float X, float Y, float Z, int Pitch, int Yaw, int Roll)
{
	local StaticMeshInstance Instance;
	local vector Loc;
	local rotator Rot;

	if(A == None || A.Role == ROLE_Authority)
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
			A.SetRotation(Rot);
	}

	A.Tag = NewTag;
	A.AmbientGlow = Glow;
	A.bUnlit = bNewUnlit;

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
	Log("ModCoop: Blocked at " $ Pawn.Location $ " moving " $ Normal(Pawn.Acceleration) $ " knee=" $ HitKnee $ " (" $ HitKnee.Class $ " " $ HitKnee.StaticMesh $ ") chest=" $ HitChest $ " (" $ HitChest.Class $ " " $ HitChest.StaticMesh $ ") level=" $ Level.Title);
}

// Large corrections of the client's position by the server mean the server's pawn is stopped by something the client doesn't have
function LongClientAdjustPosition(float TimeStamp, name newState, EPhysics newPhysics, float NewLocX, float NewLocY, float NewLocZ, float NewVelX, float NewVelY, float NewVelZ, Actor NewBase, float NewFloorX, float NewFloorY, float NewFloorZ)
{
	local vector NewLocation;

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

	if(Pawn.OldWeapon != None && Pawn.OldWeapon.WeaponType != WT_Marker)
		Pawn.SwitchToLastWeapon();
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

	if(Pawn == None || Pawn.bIncapacitated || Pawn.Health <= 0 || Pawn.Weapon == None || !Pawn.Weapon.IsInState('DownWeapon') || Pawn.Weapon.IsAnimating())
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

event PlayerTick(float DeltaTime)
{
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
		DebugStep("EnsureClientTeams");
		EnsureClientTeams();
		if(bHideRiders)
			ApplyHideRiders();

		// Spawned while the camera was still on the controller (the level was waiting for the clients): the client saw its own
		// commando from inside and no weapon (GEO_05A, in the lift)
		if(Pawn != None && ViewTarget != Pawn && !bBehindView && !IsInState('CoopWatching') && (IsInState('PlayerWalking') || IsInState('CoopLiftRide')))
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
		LogClientStatus();

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

		DebugStep("CTPlayer.PlayerTick in state " $ GetStateName() $ " Pawn=" $ Pawn $ " Weapon=" $ Pawn.Weapon $ " Target=" $ Target);
	}

	Super.PlayerTick(DeltaTime);

	if(Level.NetMode == NM_Client)
		DebugStep("after PlayerTick");
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
			Str = Str $ " " $ P.Class.Name $ "(" $ P.Role $ "," $ P.bHidden $ "," $ int(P.Location.X) $ "," $ int(P.Location.Y) $ "," $ int(P.Location.Z) $ ")";
		}
	}

	if(Num != LastCommandoCount)
	{
		LastCommandoCount = Num;
		Log("ModCoop: Commandos seen: " $ Num $ ":" $ Str);
	}
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
	    " Ping=" $ PlayerReplicationInfo.Ping);
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

	// Door breaches wait for the clients of the squad (see CoopGame.OrderDoorBreach)
	if(IsCoopHost() && CoopGame(Level.Game) != None && (TargetType == TGT_Marker || TargetType == TGT_MarkerCancel) &&
	   CoopGame(Level.Game).OrderDoorBreach(self, TargetMarker, TargetType == TGT_MarkerCancel))
		return;

	// The host can't order a squad marker whose specialist is played by a client (see CoopGame.MarkerSpecialist)
	if(IsCoopHost() && CoopGame(Level.Game) != None && (TargetType == TGT_Marker || TargetType == TGT_MarkerCancel) && TargetMarker != None)
	{
		Specialist = CoopGame(Level.Game).MarkerClient(TargetMarker);

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

	Super.Use();
}

/*
 * Turrets manned by clients. In single player the turret is aimed in PlayerManningTurret.PlayerMove on the player's own computer;
 * a client's moves never reached the server. Now the client aims (its own copy of the angles, the camera follows them), sends the
 * angles to the server, the server turns the turret and puts the turret's first person weapon where the camera is, so the shots of
 * that weapon (fired like any other weapon of the client) come out of the turret.
 */
function ServerCoopUseTurret(Turret T)
{
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

	if(!T.IsAvailableFor(Pawn))
		return;

	T.UsedBy(Pawn);

	if(T.Gunner != Pawn)
		return;

	// PlayerManTurret hides the turret for the player looking through it, here that was everybody
	T.bHidden = false;
	Log("CoopPlayer: " $ PlayerReplicationInfo.PlayerName $ " mans " $ T);
	ClientCoopManTurret(T, T.Yaw, T.Pitch);
}

function ServerCoopTurretAim(int NewYaw, int NewPitch)
{
	local Turret T;

	T = Turret(Machine);

	if(T == None || T.Gunner != Pawn)
		return;

	// The turret's own clamping and bone rotations
	T.ChangeAngle(NewYaw - T.Yaw, NewPitch - T.Pitch, 100);
	SetRotation(T.GetCameraRotation());

	if(Pawn.Weapon != None && Pawn.Weapon.WeaponType == WT_Turret)
	{
		Pawn.Weapon.SetLocation(T.GetCameraLocation());
		Pawn.Weapon.SetRotation(T.GetCameraRotation());
	}
}

simulated function ClientCoopManTurret(Turret T, int StartYaw, int StartPitch)
{
	if(Level.NetMode != NM_Client || T == None)
		return;

	Machine = T;
	TurretYaw = StartYaw;
	TurretPitch = StartPitch;
	SentTurretYaw = StartYaw;
	SentTurretPitch = StartPitch;
	T.bHidden = true;
	Log("ModCoop: Manning " $ T);
	GotoState('PlayerManningTurret');
}

simulated function ClientCoopLeaveTurret()
{
	if(Level.NetMode != NM_Client)
		return;

	Log("ModCoop: Left " $ Machine);

	if(Machine != None)
		Machine.bHidden = false;

	Machine = None;
	GotoState('PlayerWalking');
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
}

// Moves the camera along an arc from the old pawn to the new one after a takeover
event PlayerCalcView(out actor ViewActor, out vector CameraLocation, out rotator CameraRotation)
{
	local float Alpha;

	Super.PlayerCalcView(ViewActor, CameraLocation, CameraRotation);

	if(CoopGame(Level.Game) != None && CoopGame(Level.Game).bWaitingForClients)
		CoopGame(Level.Game).CheckClientWaitTime();

	// The host's own lift view (see CoopGame.CheckLiftRides)
	if(Level.NetMode != NM_Client && (bLiftView || WatchCameraPawn != None))
		CalcWatchView(ViewActor, CameraLocation, CameraRotation);

	if(Level.NetMode == NM_Client)
	{
		CalcWatchView(ViewActor, CameraLocation, CameraRotation);

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

	if(TakeoverStartTime == 0)
		return;

	Alpha = (Level.TimeSeconds - TakeoverStartTime) / 1.5;

	if(Alpha >= 1.0 || Alpha < 0)
	{
		TakeoverStartTime = 0;
		return;
	}

	Alpha = Alpha * Alpha * (3 - 2 * Alpha);
	CameraLocation = TakeoverFromLocation + (CameraLocation - TakeoverFromLocation) * Alpha + vect(0,0,1) * TakeoverArc * Sin(Alpha * Pi);
	CameraRotation = TakeoverFromRotation + Normalize(CameraRotation - TakeoverFromRotation) * Alpha;
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

			// Back in the own eyes after the lift: looking where the camera looked
			if(WatchCameraPawn == None && Pawn != None && !IsInState('CoopWatching'))
			{
				TakeoverFromRotation.Roll = 0;
				SetRotation(TakeoverFromRotation);
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
	if(Pawn == None || !IsInState('PlayerWalking'))
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

simulated function ClientCoopDumpProps(int Step)
{
	local Actor A;

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
		return Super.RestartGame();

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
		if(P.PlayerReplicationInfo == None && P != Pawn)
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

	Log("ModCoop: Lift view " $ bOn $ " center " $ Center);
	bLiftView = bOn;
	LiftLookYaw = 0;
	LiftLookPitch = 0;

	// Behind view: the own model is drawn, no first person weapon (back to first person after the lift unless watching a scene)
	if(bOn)
		bBehindView = true;
	else if(!IsInState('CoopWatching'))
		bBehindView = false;
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
			Super.EndState();
	}

	function PlayerMove(float DeltaTime)
	{
		local Turret T;
		local rotator R;
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

		R = T.Rotation;
		R.Yaw += TurretYaw;
		R.Pitch += TurretPitch;
		R.Roll = 0;
		SetRotation(R);

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

state Briefing
{
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
