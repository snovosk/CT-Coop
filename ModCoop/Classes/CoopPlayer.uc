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
var vector      TakeoverFromLocation; // Client only: camera flight to a taken over squad member (see PlayerCalcView)
var rotator     TakeoverFromRotation;
var float       TakeoverStartTime;
var bool        bCoopHUDHidden, bWasHUDHidden, bWasHelmetDrawn; // See SetCoopHUDHidden
var Pawn        WatchedMember;
var Pawn        WatchHiddenPawn;      // Client only: watched squad member hidden while its scene is seen through its eyes (see PlayerCalcView)
var array<Actor> WatchHiddenActors;
var vector      WatchCameraLocation;
var rotator     WatchCameraRotation;
var float       WatchCameraTime;
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
var float       HandSignalIdleTime;   // Client only: see FixHandSignalWeapon
var bool        bPlayedHandSignalAnim;
var Actor       ClientAttachItem;     // Client only: item in the hand during a hand signal (see SetupClientHandSignal)
var ActivateItem PendingDetonation;   // Server only: charge a client detonates when its hand animation is done (CoopGame.Tick)
var float       DetonationTime;   // Server only: squad member whose scene this client watches before playing it (see CoopGame.CheckSceneWatch)
var array<Pawn> SquadIconMembers;     // Client only: see ClientCoopSetSquadState
var float       WeaponDownTime; // Client only: Level.TimeSeconds since when the weapon is down without being changed

replication
{
	reliable if(Role == ROLE_Authority)
		ClientCoopMessage, ClientCoopPawnRevived, ClientCoopSetIncapacitated, ClientCoopSetIdleState, ClientCoopSetPanelState, ClientCoopTakeoverCamera, ClientCoopSetActorCollision;
	reliable if(Role == ROLE_Authority)
		ClientCoopDumpProps, ClientCoopObjectiveTracker, ClientCoopBlinkHUD, ClientCoopShakeView, ClientCoopScreenFade, ClientCoopCriticalMessage, ClientCoopSetObjectives;
	unreliable if(Role == ROLE_Authority)
		ClientCoopSetSquadState, ClientCoopSpawnEffect, ClientCoopSetActorDisplay, ClientCoopSetPanelLinks, ClientCoopSetPanelProgress;
	reliable if(Role < ROLE_Authority)
		ServerTeleportToHost, ServerCoopSetTarget, ServerCoopUsingItem, ServerCoopUsePanel, ServerCoopStartHandSignal;
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
simulated function FixHandSignalWeapon(float DeltaTime)
{
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

	if(Level.TimeSeconds - WeaponDownTime < 1.5)
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

		EnsureClientTeams();
		FixStuckWeapon();
		FixHandSignalWeapon(DeltaTime);
		EnsureHeadlamp();
		EnsureGrenade();
		SmoothProxies(DeltaTime);

		if(Level.TimeSeconds >= NextHostSkinCheck)
		{
			NextHostSkinCheck = Level.TimeSeconds + 1.0;
			ApplyHostSkin();
		}

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
	}

	Super.PlayerTick(DeltaTime);
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

	Super.Use();
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
}

// Moves the camera along an arc from the old pawn to the new one after a takeover
event PlayerCalcView(out actor ViewActor, out vector CameraLocation, out rotator CameraRotation)
{
	local float Alpha;

	Super.PlayerCalcView(ViewActor, CameraLocation, CameraRotation);

	if(CoopGame(Level.Game) != None && CoopGame(Level.Game).bWaitingForClients)
		CoopGame(Level.Game).CheckClientWaitTime();

	if(Level.NetMode == NM_Client)
		CalcWatchView(ViewActor, CameraLocation, CameraRotation);

	if(TakeoverStartTime == 0)
		return;

	Alpha = (Level.TimeSeconds - TakeoverStartTime) / 1.5;

	if(Alpha >= 1.0 || Alpha < 0)
	{
		TakeoverStartTime = 0;
		return;
	}

	Alpha = Alpha * Alpha * (3 - 2 * Alpha);
	CameraLocation = TakeoverFromLocation + (CameraLocation - TakeoverFromLocation) * Alpha + vect(0,0,150) * Sin(Alpha * Pi);
	CameraRotation = TakeoverFromRotation + Normalize(CameraRotation - TakeoverFromRotation) * Alpha;
}

// Scene watching (CoopGame.StartWatching): the camera is in the eyes of the squad member, smoothed because the
// replicated location and rotation of the pawn jump. The pawn and its weapon are hidden so they don't block the view.
simulated function CalcWatchView(out actor ViewActor, out vector CameraLocation, out rotator CameraRotation)
{
	local Pawn P;
	local float DeltaTime, Alpha;
	local int i;

	P = Pawn(ViewTarget);

	if(!IsInState('CoopWatching') || P == None || P == Pawn || P.Health <= 0)
	{
		RestoreWatchedPawn();
		return;
	}

	if(WatchHiddenPawn != P)
	{
		RestoreWatchedPawn();
		WatchHiddenPawn = P;

		if(!P.bHidden)
		{
			P.bHidden = true;
			WatchHiddenActors[WatchHiddenActors.Length] = P;
		}

		for(i = 0; i < P.Attached.Length; i = i + 1)
		{
			if(P.Attached[i] != None && !P.Attached[i].bHidden)
			{
				P.Attached[i].bHidden = true;
				WatchHiddenActors[WatchHiddenActors.Length] = P.Attached[i];
			}
		}

		WatchCameraLocation = P.Location + P.EyePosition();
		WatchCameraRotation = P.Rotation;
		WatchCameraTime = Level.TimeSeconds;
	}

	DeltaTime = FClamp(Level.TimeSeconds - WatchCameraTime, 0, 0.1);
	WatchCameraTime = Level.TimeSeconds;
	Alpha = FMin(1.0, DeltaTime * 10);
	WatchCameraLocation = WatchCameraLocation + (P.Location + P.EyePosition() - WatchCameraLocation) * Alpha;
	Alpha = FMin(1.0, DeltaTime * 5);
	WatchCameraRotation = Normalize(WatchCameraRotation + Normalize(P.Rotation - WatchCameraRotation) * Alpha);
	WatchCameraRotation.Roll = 0;

	ViewActor = P;
	CameraLocation = WatchCameraLocation;
	CameraRotation = WatchCameraRotation;
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
simulated function ClientCoopSetSquadState(Pawn P, float NewHealth, bool bSquadMember)
{
	local int i;

	if(P == None || P.Role == ROLE_Authority)
		return;

	P.Health = NewHealth;

	for(i = SquadIconMembers.Length - 1; i >= 0; i = i - 1)
	{
		if(SquadIconMembers[i] == None || SquadIconMembers[i] == P)
			SquadIconMembers.Remove(i, 1);
	}

	if(bSquadMember)
		SquadIconMembers[SquadIconMembers.Length] = P;
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
simulated function ClientCoopDumpProps(int Step)
{
	local Actor A;

	foreach AllActors(class'Actor', A)
	{
		if(Prop(A) != None)
			Log("CoopTest: propinfo: client " $ Step $ " " $ A $ " Tag=" $ A.Tag $ " State=" $ A.GetStateName() $ " Collide=" $ A.bCollideActors $ A.bBlockActors $ A.bBlockPlayers $ " Hidden=" $ A.bHidden $ " Mesh=" $ A.StaticMesh $ " Role=" $ A.Role $ " Physics=" $ A.Physics $ " Loc=" $ A.Location $ " Rot=" $ A.Rotation);
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
