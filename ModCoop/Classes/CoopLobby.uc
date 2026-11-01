class CoopLobby extends Object;

/*
 * CoopLobby
 * Purpose: the players meet before the campaign starts: the host creates a lobby on the small map MPCustom of the game, the clients connect, each
 *   picks a squad member, the host picks the level, and when everybody is ready the level starts for all of them. The level change
 *   waits for the clients like any other (CoopGame.WaitForClients).
 * Entry points: Setup (CoopGame.InitGame with ?CoopLobby), PlayerJoined (CoopGame.PostLogin), Refresh (CoopGame.Timer), Choose, SetReady,
 *   SetLevel (CoopPlayer.ServerCoopLobby*).
 * Logging: "CoopGame: lobby" (state, refused choices, the start).
 * State: Game, LevelName, bStarted, LastCount; per player CoopPlayer.LobbyMember and bLobbyReady.
 * Known limitations: a client who connects after the start joins the running game as before. A member nobody picked is played by the AI
 *   or taken by a client who picked "any".
 */

const NUM_MEMBERS = 3;

var CoopGame Game;
var string LevelName;
var bool bStarted;
var int LastCount;

function Setup(CoopGame G, string FirstLevel)
{
	Game = G;
	LevelName = FirstLevel;

	if(LevelName == "" && class'CoopConfig'.default.CoopLevels.Length > 0)
		LevelName = class'CoopConfig'.default.CoopLevels[0];

	Log("CoopGame: lobby for " $ LevelName);
}

static function string MemberClass(int Member)
{
	switch(Member)
	{
		case 1: return "CTCharacters.Commando62Delta";
		case 2: return "CTCharacters.Commando40Delta";
		case 3: return "CTCharacters.Commando07Delta";
	}

	return "";
}

function PlayerJoined(CoopPlayer CP)
{
	SendState();
}

// Every second: somebody left (the controller is gone only some time after Logout)
function Refresh()
{
	local Controller C;
	local int n;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None)
			++n;
	}

	if(n != LastCount)
	{
		LastCount = n;
		SendState();
		CheckStart();
	}
}

// Each member once
function Choose(CoopPlayer CP, int Member)
{
	local Controller C;

	if(bStarted)
		return;

	Member = Clamp(Member, 0, NUM_MEMBERS);

	if(Member != 0)
	{
		for(C = Game.Level.ControllerList; C != None; C = C.nextController)
		{
			if(C != CP && CoopPlayer(C) != None && CoopPlayer(C).LobbyMember == Member)
			{
				Log("CoopGame: lobby: " $ CP.PlayerReplicationInfo.PlayerName $ " can't pick member " $ Member $ ", it is taken");
				SendState();
				return;
			}
		}
	}

	CP.LobbyMember = Member;
	CP.bLobbyReady = false;
	SendState();
}

function SetReady(CoopPlayer CP, bool bReady)
{
	if(bStarted)
		return;

	CP.bLobbyReady = bReady;
	SendState();
	CheckStart();
}

function SetLevel(CoopPlayer CP, string NewLevel)
{
	local int i;

	if(bStarted || !Game.IsHost(CP))
		return;

	for(i = 0; i < class'CoopConfig'.default.CoopLevels.Length; ++i)
	{
		if(class'CoopConfig'.default.CoopLevels[i] ~= NewLevel)
		{
			LevelName = class'CoopConfig'.default.CoopLevels[i];
			SendState();
			return;
		}
	}
}

// Level|Name,Member,Ready;Name,Member,Ready;...
function string StateString()
{
	local Controller C;
	local string Result;

	Result = LevelName $ "|";

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && C.PlayerReplicationInfo != None)
			Result = Result $ C.PlayerReplicationInfo.PlayerName $ "," $ int(Game.IsHost(C)) * 9 + CoopPlayer(C).LobbyMember $ "," $ int(CoopPlayer(C).bLobbyReady) $ ";";
	}

	return Result;
}

function SendState()
{
	local Controller C;
	local string StateText;

	StateText = StateString();
	Log("CoopGame: lobby: " $ StateText);

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None)
			CoopPlayer(C).ClientCoopLobbyState(StateText);
	}
}

function CheckStart()
{
	local Controller C;
	local bool bAnyMember;
	local int Num;

	if(bStarted)
		return;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) == None)
			continue;

		if(!CoopPlayer(C).bLobbyReady)
			return;

		++Num;
		bAnyMember = bAnyMember || CoopPlayer(C).LobbyMember != 0;
	}

	// The host alone: a double click on the button of the host menu (same place) started the level at once
	if(Num < 2)
		return;

	bStarted = true;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !Game.IsHost(C))
			class'CoopConfig'.static.SetSquadAssignment(Game.PlayerKey(PlayerController(C)), MemberClass(CoopPlayer(C).LobbyMember));

		if(CoopPlayer(C) != None)
			CoopPlayer(C).ClientCoopLobbyState("START");
	}

	class'CoopConfig'.default.bFixedSquad = bAnyMember;
	Log("CoopGame: lobby: starting " $ LevelName $ " with " $ Num $ " players, fixed squad " $ bAnyMember);
	Game.CoopTravel(LevelName);
}
