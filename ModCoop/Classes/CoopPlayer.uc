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

replication
{
	reliable if(Role == ROLE_Authority)
		ClientCoopMessage, ClientCoopPawnRevived;
	reliable if(Role < ROLE_Authority)
		ServerTeleportToHost, ServerCoopSetTarget;
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

		EnsureClientTeams();

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
 * Pawn.Reviving calls PawnRevived only on the server. The local player of a single player game is on the server but a client's
 * controller would stay in state CtrlIncapacitated: unable to move with the camera stuck at the 'DeathCamera' bone.
 */
simulated function PawnRevived(Pawn P)
{
	Super.PawnRevived(P);

	if(Role == ROLE_Authority && !IsCoopHost() && P == Pawn)
		ClientCoopPawnRevived();
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
}
