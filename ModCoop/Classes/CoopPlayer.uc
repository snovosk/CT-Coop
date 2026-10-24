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
var float       WeaponDownTime; // Client only: Level.TimeSeconds since when the weapon is down without being changed

replication
{
	reliable if(Role == ROLE_Authority)
		ClientCoopMessage, ClientCoopPawnRevived, ClientCoopSetIncapacitated, ClientCoopSetIdleState;
	unreliable if(Role == ROLE_Authority)
		ClientCoopSetActorDisplay;
	reliable if(Role < ROLE_Authority)
		ServerTeleportToHost, ServerCoopSetTarget, ServerCoopUsingItem;
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
	bSetCoopNetSpeed = true;
	bDynamicNetSpeed = false;
	Log("ModCoop: Net speed " $ Player.CurrentNetSpeed $ ", requesting " $ class'CoopConfig'.default.NetClientRate);
	SetNetSpeed(class'CoopConfig'.default.NetClientRate);
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
			Log("CoopDebug: Client " $ P.Class.Name $ " " $ P.Location $ " Health=" $ P.Health $ " Incap=" $ P.bIncapacitated $ " Role=" $ P.Role $ " Idle=" $ P.CurrentIdleState $ " Style=" $ P.CurrentMovementStyle $ " MovAnim=" $ P.MovementAnim $ " Enemy=" $ P.Controller.Enemy $ " Focus=" $ P.Controller.Focus);
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
	if(CoopCommando(APawn) == None)
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

state UsingItem
{
	function BeginState()
	{
		Super.BeginState();

		if(Role < ROLE_Authority)
			ServerCoopUsingItem(true, Target, TargetType);
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
