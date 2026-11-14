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
 * Saves: the host can pick a save slot instead of a level (CoopSaveSlots). A player of that save gets the squad member he played there and
 *   can't change it; a new player picks one nobody present has. The game then starts from the save (CoopGame.LoadSlotFromLobby).
 * Who is here when the game starts is the session (CoopConfig.SessionPlayers): nobody else joins until it ends, the players of it can
 *   come back after a crash (CoopGame.PreLogin). The user's rule, 2026-11-11.
 * Known limitations: a member nobody picked is played by the AI or taken by a client who picked "any".
 */

const NUM_MEMBERS = 3;

var CoopGame Game;
var string LevelName;  // A level, or the text of a save slot (CoopSaveSlots.Describe)
var int SaveSlot;      // The slot picked as the level, 0 for a new game
var bool bStarted;
var int LastCount;

function Setup(CoopGame G, string FirstLevel)
{
	Game = G;
	LevelName = FirstLevel;

	if(LevelName == "" && class'CoopConfig'.default.CoopLevels.Length > 0)
		LevelName = class'CoopConfig'.default.CoopLevels[0];

	// A new lobby is a new session
	class'CoopConfig'.default.SessionPlayers = "";
	Log("CoopGame: lobby for " $ LevelName);
}

static function int MemberIndex(string ClassText)
{
	local int i;

	for(i = 1; i <= NUM_MEMBERS; ++i)
	{
		if(ClassText ~= MemberClass(i))
			return i;
	}

	return 0;
}

// The member this player had in the picked save, 0 if none or not in it
function int SavedMemberOf(CoopPlayer CP)
{
	if(SaveSlot == 0 || CP.PlayerReplicationInfo == None)
		return 0;

	return MemberIndex(class'CoopSaveSlots'.static.SavedMember(SaveSlot, class'CoopSaveSlots'.static.CleanName(CP.PlayerReplicationInfo.PlayerName)));
}

/*
 * The save stands for the level. The player limit stays the host's (CoopHostMenu offers the save's number): fewer than in the save is
 * allowed, a player of it who doesn't fit waits for a new lobby (the user's decision, 2026-11-11)
 */
function PickSave(int Slot)
{
	if(!class'CoopSaveSlots'.static.IsCompatible(Slot))
		return;

	SaveSlot = Slot;
	LevelName = class'CoopSaveSlots'.static.Describe(Slot);
	SetMaxPlayers(class'CoopSaveSlots'.static.NumPlayers(Slot));
	Log("CoopGame: lobby: save slot " $ Slot $ " picked, " $ class'CoopSaveSlots'.static.NumPlayers(Slot) $ " players in it, at most " $ Game.MaxPlayers);
	ApplySavedMembers();
}

// The host's MAX PLAYERS (CoopLobbyMenu), or the players of a picked save: 2-4, never below the players present
function SetMaxPlayers(int Wanted)
{
	Game.MaxPlayers = Clamp(Max(Wanted, Game.NumPlayers), 2, 4);
	class'CoopConfig'.default.LastMaxPlayers = Game.MaxPlayers;
	Log("CoopGame: lobby: at most " $ Game.MaxPlayers $ " players (wanted " $ Wanted $ ", " $ Game.NumPlayers $ " here)");
	SendState();
}

// A save was picked or somebody came: its players get their members, a new player loses a member one of them has
function ApplySavedMembers()
{
	local Controller C, C2;
	local int Member;

	if(SaveSlot == 0)
		return;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) == None || Game.IsHost(C))
			continue;

		Member = SavedMemberOf(CoopPlayer(C));

		if(Member != 0 && CoopPlayer(C).LobbyMember != Member)
		{
			CoopPlayer(C).LobbyMember = Member;
			CoopPlayer(C).bLobbyReady = false;

			for(C2 = Game.Level.ControllerList; C2 != None; C2 = C2.nextController)
			{
				if(C2 != C && CoopPlayer(C2) != None && CoopPlayer(C2).LobbyMember == Member)
				{
					CoopPlayer(C2).LobbyMember = 0;
					CoopPlayer(C2).bLobbyReady = false;
				}
			}
		}
	}
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
	ApplySavedMembers();
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

	// A player of the picked save plays what he played there
	if(SavedMemberOf(CP) != 0 && Member != SavedMemberOf(CP))
	{
		Log("CoopGame: lobby: " $ CP.PlayerReplicationInfo.PlayerName $ " plays member " $ SavedMemberOf(CP) $ " of the save");
		SendState();
		return;
	}

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

	i = class'CoopSaveSlots'.static.SlotFromItem(NewLevel);

	if(i != 0)
	{
		if(!class'CoopSaveSlots'.static.IsCompatible(i))
		{
			Log("CoopGame: lobby: save slot " $ i $ " can't be loaded: " $ class'CoopSaveSlots'.static.Describe(i));
			SendState();
			return;
		}

		PickSave(i);
		SendState();
		return;
	}

	for(i = 0; i < class'CoopConfig'.default.CoopLevels.Length; ++i)
	{
		if(class'CoopConfig'.default.CoopLevels[i] ~= NewLevel)
		{
			SaveSlot = 0;
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
	class'CoopConfig'.default.SessionPlayers = "|";

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && C.PlayerReplicationInfo != None)
			class'CoopConfig'.default.SessionPlayers = class'CoopConfig'.default.SessionPlayers $ class'CoopSaveSlots'.static.CleanName(C.PlayerReplicationInfo.PlayerName) $ "|";

		if(CoopPlayer(C) != None && !Game.IsHost(C))
			class'CoopConfig'.static.SetSquadAssignment(Game.PlayerKey(PlayerController(C)), MemberClass(CoopPlayer(C).LobbyMember));

		if(CoopPlayer(C) != None)
			CoopPlayer(C).ClientCoopLobbyState("START");
	}

	class'CoopConfig'.default.bFixedSquad = bAnyMember;
	Log("CoopGame: lobby: starting " $ LevelName $ " with " $ Num $ " players, fixed squad " $ bAnyMember $ ", session " $ class'CoopConfig'.default.SessionPlayers);

	if(SaveSlot != 0)
		Game.LoadSlotFromLobby(SaveSlot);
	else
	{
		// The next lobby starts on this level (CoopHostMenu passes it)
		for(Num = 0; Num < class'CoopConfig'.default.CoopLevels.Length; ++Num)
		{
			if(class'CoopConfig'.default.CoopLevels[Num] ~= LevelName)
				class'CoopConfig'.default.LastLevelIndex = Num;
		}

		class'CoopConfig'.static.StaticSaveConfig();
		Game.CoopTravel(LevelName);
	}
}
