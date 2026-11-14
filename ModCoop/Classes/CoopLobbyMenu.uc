class CoopLobbyMenu extends CoopHostMenu;

/*
 * CoopLobbyMenu
 * Purpose: the menu of the lobby (see CoopLobby) for the host and the clients: who is here, who plays which squad member, the level
 *   (only the host changes it) and the ready button. Uses the two option rows of the host menu.
 * Entry points: opened by CoopLobby.PlayerJoined through ClientOpenMenu; state from CoopPlayer.LobbyState, choices through
 *   CoopPlayer.ServerCoopLobby*.
 * Logging: "ModCoop: lobby" when the state arrives (CoopPlayer.ClientCoopLobbyState).
 * StateText: bIsHost, bReady, LastState.
 * Known limitations: closing the menu (back) leaves the lobby.
 */

const NUM_PLAYERS = 4;

var() MenuText PlayerLines[NUM_PLAYERS];
var() MenuText AddressLines[3];  // Host: where friends connect to
var float NextAddressCheck;
var() localized string MemberNames[4];
var bool bIsHost, bReady;
var string LastState;
var float OpenTime;
var bool bMusicLogged;

simulated function Init(string Args)
{
	local int i;

	Super.Init(Args);

	OpenTime = GetPlayerOwner().Level.TimeSeconds;

	// MenuBase.Init only plays the background movie of the menus on the map Entry, the lobby has its own map
	InLevelBackgroundMovieReplacement.bHidden = 1;
	StartBackgroundMovie();

	// Back: to the multiplayer menu with the co-op entries, and no reconnecting
	class'GameEngine'.default.DisconnectMenuClass = "ModCoop.CoopMultiplayerMenu";
	class'GameEngine'.default.DisconnectMenuArgs = "";

	bIsHost = GetPlayerOwner().Level.NetMode != NM_Client;
	OptionLabels[OPTION_PLAYERS].Text = "SQUAD MEMBER";
	Options[OPTION_PLAYERS].Items.Length = 4;
	Options[OPTION_PLAYERS].Items[0] = MemberNames[0];
	Options[OPTION_PLAYERS].Items[1] = MemberNames[1];
	Options[OPTION_PLAYERS].Items[2] = MemberNames[2];
	Options[OPTION_PLAYERS].Items[3] = MemberNames[3];
	Options[OPTION_PLAYERS].Current = 0;

	// The host plays 38: his second row is the number of players (the host menu has no rows), the clients pick a member there
	if(bIsHost)
	{
		OptionLabels[OPTION_PLAYERS].Text = "MAX PLAYERS";
		Options[OPTION_PLAYERS].Items.Length = 3;
		Options[OPTION_PLAYERS].Items[0] = "2";
		Options[OPTION_PLAYERS].Items[1] = "3";
		Options[OPTION_PLAYERS].Items[2] = "4";
		ShowMaxPlayers();
		FocusOnWidget(Options[OPTION_LEVEL]);
	}
	else
	{
		OptionLeftArrows[OPTION_LEVEL].bHidden = 1;
		OptionRightArrows[OPTION_LEVEL].bHidden = 1;
		OptionLeftArrows[OPTION_SAVE].bHidden = 1;
		OptionRightArrows[OPTION_SAVE].bHidden = 1;
		FocusOnWidget(Options[OPTION_PLAYERS]);
	}

	ShowReady();
	ApplyState();
}

simulated function ShowReady()
{
	if(bReady)
		AButton.Blurred.Text = "NOT READY";
	else
		AButton.Blurred.Text = "READY";
}

simulated function CoopPlayer Me()
{
	return CoopPlayer(GetPlayerOwner());
}

simulated function ChangeOption(int i, int Delta)
{
	if((i == OPTION_LEVEL || i == OPTION_SAVE) && !bIsHost)
		return;

	Super.ChangeOption(i, Delta);

	// The host is the server: the limit is set right here, never below the players already in the lobby
	if(i == OPTION_PLAYERS && bIsHost)
	{
		if(CoopGame(GetPlayerOwner().Level.Game) != None && CoopGame(GetPlayerOwner().Level.Game).Lobby != None)
			CoopGame(GetPlayerOwner().Level.Game).Lobby.SetMaxPlayers(Options[i].Current + 2);

		ShowMaxPlayers();
		return;
	}

	// A save stands for its level (CoopLobby.SetLevel takes the slot's text), NEW GAME for the level row
	if(i == OPTION_SAVE && SelectedSave() != 0)
		Me().ServerCoopLobbyLevel(Options[i].Items[Options[i].Current]);
	else if(i == OPTION_SAVE || i == OPTION_LEVEL)
		Me().ServerCoopLobbyLevel(Options[OPTION_LEVEL].Items[Options[OPTION_LEVEL].Current]);
	else
		Me().ServerCoopLobbyChoose(Options[i].Current);

	if(bReady)
	{
		bReady = false;
		ShowReady();
	}
}

simulated function OnAButton()
{
	// The button of the host menu is in the same place: a double click there must not start the level at once
	if(GetPlayerOwner().Level.TimeSeconds - OpenTime < 1.5)
		return;

	bReady = !bReady;
	ShowReady();
	Me().ServerCoopLobbyReady(bReady);
}

simulated function HandleInputBack()
{
	class'CoopConfig'.static.EndSession();
	GetPlayerOwner().ConsoleCommand("DISCONNECT");
}

simulated function Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);

	// Test: the music of the menu plays (the first second after the menu opened)
	if(!bMusicLogged && GetPlayerOwner().Level.TimeSeconds - OpenTime > 1)
	{
		bMusicLogged = true;
		Log("ModCoop: lobby music " $ GetPlayerOwner().Player.Console.MenuBackgroundMusic $ " playing " $ GetPlayerOwner().Player.Console.IsMenuBackgroundMusicPlaying(BackgroundMusic));
	}

	if(Me() != None && Me().LobbyState != LastState)
		ApplyState();

	NextAddressCheck -= DeltaTime;

	if(bIsHost && NextAddressCheck <= 0)
	{
		NextAddressCheck = 1;
		ShowAddresses();
	}
}

/*
 * The host tells friends where to connect: LAN and VPN addresses work as they are, the internet address needs forwarded ports.
 * Steam friends don't need any address.
 */
simulated function ShowAddresses()
{
	local string Url, Port, Text;
	local int i;

	// The server takes the next port when 7777 is in use
	Url = GetPlayerOwner().Level.GetAddressURL();
	i = InStr(Url, ":");

	if(i != -1 && Mid(Url, i + 1) != "7777")
		Port = Mid(Url, i);

	Text = class'CoopNative'.static.GetHostAddresses();

	if(Text != "")
		AddressLines[0].Text = "LAN / VPN IP: " $ Text $ Port;

	Text = class'CoopNative'.static.GetPublicAddress();

	if(Text != "")
		AddressLines[1].Text = "INTERNET IP: " $ Text $ Port $ " (NEEDS FORWARDED PORTS)";

	if(class'CoopConfig'.static.RelayValue(class'CoopNative'.static.ReadRelayStatus(), "steam") == "1")
		AddressLines[2].Text = "STEAM FRIENDS: MULTIPLAYER > CO-OP: STEAM FRIENDS, NO IP NEEDED";
}

simulated function ApplyState()
{
	local string StateText, Entry, PlayerName;
	local int Line, Member, i;
	local bool bPlayerReady;

	if(Me() == None)
		return;

	StateText = Me().LobbyState;
	LastState = StateText;

	if(StateText == "START")
	{
		GetPlayerOwner().MenuClose();
		return;
	}

	i = InStr(StateText, "|");

	if(i == -1)
		return;

	ShowLevelState(Left(StateText, i));
	ShowMaxPlayers();

	StateText = Mid(StateText, i + 1);

	for(Line = 0; Line < NUM_PLAYERS; ++Line)
	{
		i = InStr(StateText, ";");

		if(i == -1)
		{
			PlayerLines[Line].Text = "";
			continue;
		}

		Entry = Left(StateText, i);
		StateText = Mid(StateText, i + 1);
		i = InStr(Entry, ",");
		PlayerName = Left(Entry, i);
		Entry = Mid(Entry, i + 1);
		i = InStr(Entry, ",");
		Member = int(Left(Entry, i));
		bPlayerReady = int(Mid(Entry, i + 1)) != 0;
		PlayerLines[Line].Text = Caps(PlayerName) $ ": " $ MemberText(Member);

		if(bPlayerReady)
			PlayerLines[Line].Text = PlayerLines[Line].Text $ " - READY";

		// A choice the server refused or an earlier one
		if(!bIsHost && GetPlayerOwner().PlayerReplicationInfo != None && PlayerName == GetPlayerOwner().PlayerReplicationInfo.PlayerName && Member >= 0 && Member <= 3)
			Options[OPTION_PLAYERS].Current = Member;
	}
}

/*
 * The lobby's level is a level or a save's name, "SAVE GEO_01B 11.11:20:26" (CoopSaveSlots.Describe): the save row shows the slot,
 * the level row its map. Clients only show them, the host's rows follow what the server took.
 */
simulated function ShowLevelState(string LevelText)
{
	local string Map;
	local int Line;

	Map = class'CoopSaveSlots'.static.MapOfItem(LevelText);

	if(Map == "")
		Map = LevelText;

	if(!bIsHost)
	{
		Options[OPTION_LEVEL].Items.Length = 1;
		Options[OPTION_LEVEL].Items[0] = Map;
		Options[OPTION_LEVEL].Current = 0;
		Options[OPTION_SAVE].Items.Length = 1;
		Options[OPTION_SAVE].Current = 0;

		if(Map != LevelText)
			Options[OPTION_SAVE].Items[0] = LevelText;
		else
			Options[OPTION_SAVE].Items[0] = "NEW GAME";

		return;
	}

	Options[OPTION_LEVEL].Current = LevelItem(Map);
	Options[OPTION_SAVE].Current = 0;

	for(Line = 0; Line < Options[OPTION_SAVE].Items.Length; ++Line)
	{
		if(Map != LevelText && Options[OPTION_SAVE].Items[Line] == LevelText)
			Options[OPTION_SAVE].Current = Line;
	}

	OptionLeftArrows[OPTION_LEVEL].bHidden = int(Map != LevelText);
	OptionRightArrows[OPTION_LEVEL].bHidden = int(Map != LevelText);
}

// The host's player limit as the lobby has it (a save sets it, the limit can't go below the players present)
simulated function ShowMaxPlayers()
{
	if(bIsHost && GetPlayerOwner().Level.Game != None)
		Options[OPTION_PLAYERS].Current = Clamp(GetPlayerOwner().Level.Game.MaxPlayers - 2, 0, 2);
}

simulated function string MemberText(int Member)
{
	if(Member >= 9)
		return "38 BOSS (HOST)";

	return MemberNames[Clamp(Member, 0, 3)];
}

defaultproperties
{
	TitleText="CO-OP LOBBY"
	bBackgroundMusicDuringLevel=True
	MemberNames(0)="ANY"
	MemberNames(1)="62 SCORCH"
	MemberNames(2)="40 FIXER"
	MemberNames(3)="07 SEV"
	PlayerLines(0)=(MenuFont=Font'OrbitFonts.OrbitBold15',DrawPivot=DP_MiddleLeft,PosX=0.15,PosY=0.59,ScaleX=0.8,ScaleY=0.8)
	PlayerLines(1)=(PosY=0.635)
	PlayerLines(2)=(PosY=0.68)
	PlayerLines(3)=(PosY=0.725)
	AddressLines(0)=(MenuFont=Font'OrbitFonts.OrbitBold15',DrawColor=(B=120,G=220,R=255,A=255),DrawPivot=DP_MiddleLeft,PosX=0.15,PosY=0.775,ScaleX=0.6,ScaleY=0.6)
	AddressLines(1)=(PosY=0.805)
	AddressLines(2)=(PosY=0.835)
	HelpText=(Text="")
	AButton=(Blurred=(Text="READY"),bHidden=0)
}
