class CoopSteamMenu extends MenuTemplateTitledBA;

#exec OBJ LOAD FILE="XInterface.u"

/*
 * CoopSteamMenu
 * Purpose: joining a Steam friend from inside the game. Shows the friends who are hosting, found by the relay (CoopTunnel/Main.cpp, mode watch).
 * Entry points: CoopMultiplayerMenu (entry shown only when the relay has Steam); test: -CoopSteamAuto selects the first host.
 * Logging: "ModCoop: steam".
 * State: HostIds (what the rows stand for), bJoining + TimeLeft while the relay starts towards the host.
 * Known limitations: only friends who are online and not invisible are found. Between two Steam accounts the game connects to
 *   127.0.0.1 through the relay, the host sees all such players on one address (see CoopGame.MakeNameUnique).
 */

const NUM_HOSTS = 5;

var() MenuButtonText Hosts[NUM_HOSTS];
var() MenuText       StatusText;
var() MenuText       HelpText;
var() string         SearchingStr, NoHostsStr, NoSteamStr, JoiningStr, FailedStr;

var string HostIds[NUM_HOSTS];
var int    NumHosts;
var bool   bJoining;
var float  NextCheck;
var float  TimeLeft;
var float  WaitedForRelay;

simulated function Init(string Args)
{
	local int i;

	Super.Init(Args);

	for(i = 0; i < NUM_HOSTS; ++i)
		Hosts[i].bHidden = 1;

	MenuTitle.Text = "CO-OP CAMPAIGN: STEAM FRIENDS (MOD " $ class'CoopConfig'.static.Version() $ ")";
	StatusText.Text = SearchingStr;
	AButton.bHidden = 1;

	class'CoopNative'.static.StartRelay("watch");
}

simulated function Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);

	NextCheck -= DeltaTime;

	if(bJoining)
	{
		TimeLeft -= DeltaTime;

		if(TimeLeft <= 0)
		{
			Log("ModCoop: steam: no answer from the relay or the host");
			bJoining = false;
			StatusText.Text = FailedStr;
			class'CoopConfig'.static.EndSession();
			class'CoopNative'.static.StartRelay("watch");
		}
	}

	if(NextCheck > 0)
		return;

	NextCheck = 0.5;

	if(bJoining)
		CheckJoin();
	else
		ShowHosts();
}

simulated function ShowHosts()
{
	local string Status, Line;
	local int i, Separator, Before;

	Status = class'CoopNative'.static.ReadRelayStatus();
	WaitedForRelay += 0.5;

	if(class'CoopConfig'.static.RelayValue(Status, "steam") != "1")
	{
		if(WaitedForRelay > 6 || class'CoopConfig'.static.RelayValue(Status, "steam") == "0")
			StatusText.Text = NoSteamStr;

		return;
	}

	Before = NumHosts;
	NumHosts = 0;

	while(NumHosts < NUM_HOSTS)
	{
		Line = class'CoopConfig'.static.RelayValue(Status, "host");

		if(Line == "")
			break;

		// The next host= is behind this one
		Status = Mid(Status, InStr(Status, "host=" $ Line) + Len(Line) + 5);
		Separator = InStr(Line, "|");
		HostIds[NumHosts] = Left(Line, Separator);
		Hosts[NumHosts].Blurred.Text = Caps(Mid(Line, Separator + 1));
		Hosts[NumHosts].bHidden = 0;
		++NumHosts;
	}

	for(i = NumHosts; i < NUM_HOSTS; ++i)
		Hosts[i].bHidden = 1;

	if(NumHosts != Before)
		Log("ModCoop: steam: friends hosting " $ NumHosts);

	AButton.bHidden = int(NumHosts == 0);

	if(NumHosts == 0)
	{
		StatusText.Text = NoHostsStr;
		return;
	}

	StatusText.Text = "";

	if(Before == 0)
		FocusOnWidget(Hosts[0]);

	// TEST: nobody to press the button
	if(InStr(Caps(class'CoopNative'.static.GetCommandLine()), "-COOPSTEAMAUTO") != -1)
		JoinHost(0);
}

simulated function JoinHost(int i)
{
	Log("ModCoop: steam: joining a friend");
	bJoining = true;
	TimeLeft = 20;
	StatusText.Text = JoiningStr @ Hosts[i].Blurred.Text;
	class'CoopNative'.static.StartRelay("join " $ HostIds[i]);

	for(i = 0; i < NUM_HOSTS; ++i)
		Hosts[i].bHidden = 1;

	AButton.bHidden = 1;
	NumHosts = 0;
}

simulated function CheckJoin()
{
	local string Port, Address;

	Port = class'CoopConfig'.static.RelayValue(class'CoopNative'.static.ReadRelayStatus(), "port");

	if(Port == "")
		return;

	Address = "127.0.0.1:" $ Port;
	bJoining = false;
	class'CoopConfig'.static.BeginSession(Address);

	class'GameEngine'.default.DisconnectMenuClass = "ModCoop.CoopMultiplayerMenu";
	class'GameEngine'.default.DisconnectMenuArgs = "";

	Log("ModCoop: steam: connecting through the relay");
	GetPlayerOwner().ConsoleCommand("open " $ class'CoopConfig'.static.MakeConnectURL(Address));
}

simulated function HostSelected()
{
	local int i;

	for(i = 0; i < NumHosts; ++i)
	{
		if(Hosts[i].bHasFocus != 0)
		{
			JoinHost(i);
			return;
		}
	}
}

simulated function OnAButton()
{
	HostSelected();
}

simulated function HandleInputBack()
{
	GotoMenuClass("XInterfaceCTMenus.CTMultiplayerPCMenu");
}

defaultproperties
{
	MenuTitle=(Text="CO-OP CAMPAIGN: STEAM FRIENDS",bHidden=0)
	Hosts(0)=(Blurred=(Text="",PosX=0.5,PosY=0.36),BackgroundBlurred=(PosX=0.5,PosY=0.36,ScaleX=0.5,ScaleY=0.04333),OnSelect="HostSelected",Style="ButtonTextStyle1")
	Hosts(1)=(Blurred=(PosY=0.41666),BackgroundBlurred=(PosY=0.41666))
	Hosts(2)=(Blurred=(PosY=0.47332),BackgroundBlurred=(PosY=0.47332))
	Hosts(3)=(Blurred=(PosY=0.52998),BackgroundBlurred=(PosY=0.52998))
	Hosts(4)=(Blurred=(PosY=0.58664),BackgroundBlurred=(PosY=0.58664))
	StatusText=(MenuFont=Font'OrbitFonts.OrbitBold15',DrawColor=(B=120,G=220,R=255,A=255),DrawPivot=DP_MiddleLeft,PosX=0.1,PosY=0.7,ScaleX=0.6,ScaleY=0.6,MaxSizeX=0.8,bWordWrap=1,Pass=2)
	HelpText=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="THE HOST CREATES A LOBBY (CO-OP: HOST CAMPAIGN). FRIENDS MUST BE ONLINE, NOT INVISIBLE, WITH THE GAME ON STEAM. EVERYBODY NEEDS THE SAME VERSION OF THE MOD.",DrawPivot=DP_MiddleLeft,PosX=0.1,PosY=0.83,ScaleX=0.6,ScaleY=0.6,MaxSizeX=0.8,bWordWrap=1,Pass=2,Style="LabelText")
	SearchingStr="LOOKING FOR FRIENDS WHO ARE HOSTING..."
	NoHostsStr="NO FRIENDS ARE HOSTING RIGHT NOW. THE LIST UPDATES BY ITSELF."
	NoSteamStr="STEAM ISN'T AVAILABLE: IS IT RUNNING AND IS THE GAME ON THIS ACCOUNT? JOINING BY IP STILL WORKS."
	JoiningStr="JOINING"
	FailedStr="NO ANSWER. TRY AGAIN."
	AButton=(Blurred=(Text="JOIN"),bHidden=1)
	Background=(WidgetTexture=Texture'GUIContent.Menu.CT_MainMenuGraphics',Style="FullScreen")
}
