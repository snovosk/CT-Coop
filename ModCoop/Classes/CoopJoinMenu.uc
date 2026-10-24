class CoopJoinMenu extends MenuTemplateTitledBA;

#exec OBJ LOAD FILE="XInterface.u"

/*
 * CoopJoinMenu
 * Connects to a coop host by IP. The last addresses are stored in ModCoop.ini and can be selected directly.
 */

const NUM_RECENT = 5;

var() MenuSprite        LabelBackground;
var() MenuText          Label;
var() MenuEditBox       AddressBox;
var() MenuText          RecentLabel;
var() MenuButtonText    Recent[NUM_RECENT];
var() MenuText          HelpText;
var() MenuText          ErrorText;
var() MenuText          StatusText;

var() localized string  ConnectingStr;
var() localized string  NoAnswerStr;

var float               ConnectTimeLeft;  // > 0 while waiting for the host to answer
var bool                bAutoConnectDone; // The address from the command line (-CoopConnect=) is only used once per game start

simulated function Init(string Args)
{
	local int i;

	Super.Init(Args);

	for(i = 0; i < NUM_RECENT; ++i)
	{
		if(i < class'CoopConfig'.static.NumRecentAddresses())
		{
			Recent[i].Blurred.Text = class'CoopConfig'.default.RecentAddresses[i];
			Recent[i].bHidden = 0;
		}
		else
		{
			Recent[i].bHidden = 1;
		}
	}

	Log("ModCoop: " $ class'CoopConfig'.static.NumRecentAddresses() $ " recent addresses");
	RecentLabel.bHidden = int(class'CoopConfig'.static.NumRecentAddresses() == 0);

	if(class'CoopConfig'.static.NumRecentAddresses() > 0)
		AddressBox.Blurred.Text = class'CoopConfig'.default.RecentAddresses[0];

	ErrorText.bHidden = 1;
	StatusText.bHidden = 1;
	FocusOnWidget(AddressBox);

	AutoConnect();
}

// The join batch file starts the game with -CoopConnect=<address> and this menu so the player sees what is happening
simulated function AutoConnect()
{
	local string CmdLine;
	local int i;

	if(default.bAutoConnectDone)
		return;

	default.bAutoConnectDone = true;
	CmdLine = class'CoopNative'.static.GetCommandLine();
	i = InStr(Caps(CmdLine), "-COOPCONNECT=");

	if(i == -1)
		return;

	CmdLine = Mid(CmdLine, i + Len("-COOPCONNECT="));
	i = InStr(CmdLine, " ");

	if(i != -1)
		CmdLine = Left(CmdLine, i);

	if(CmdLine != "")
	{
		AddressBox.Blurred.Text = CmdLine;
		Connect(CmdLine);
	}
}

simulated function Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);

	if(ConnectTimeLeft <= 0)
		return;

	ConnectTimeLeft -= DeltaTime;

	// Still in this menu: the host did not answer (a successful connection loads the level and closes the menu)
	if(ConnectTimeLeft <= 0)
	{
		Log("ModCoop: No answer from " $ class'CoopConfig'.default.ReconnectAddress);
		StatusText.Text = NoAnswerStr;
		class'CoopConfig'.static.EndSession();
	}
}

simulated function Connect(string Address)
{
	Address = class'CoopConfig'.static.NormalizeAddress(Address);

	if(Address == "" || InStr(Address, ".") == -1 && !(Left(Address, 9) ~= "localhost"))
	{
		ErrorText.bHidden = 0;
		return;
	}

	ErrorText.bHidden = 1;
	StatusText.bHidden = 0;
	StatusText.Text = ConnectingStr @ Address;
	ConnectTimeLeft = class'CoopConfig'.default.ClientTimeout + 3.0;

	class'CoopConfig'.static.AddRecentAddress(Address);
	class'CoopConfig'.static.BeginSession(Address);

	// Where to go if the connection fails for good
	class'GameEngine'.default.DisconnectMenuClass = "XInterfaceCTMenus.CTMultiplayerPCMenu";
	class'GameEngine'.default.DisconnectMenuArgs = "";

	Log("ModCoop: Connecting to " $ Address);
	GetPlayerOwner().ConsoleCommand("open " $ class'CoopConfig'.static.MakeConnectURL(Address));
}

simulated function OnAButton()
{
	Connect(AddressBox.Blurred.Text);
}

simulated function int FocusedRecent()
{
	local int i;

	for(i = 0; i < NUM_RECENT; ++i)
	{
		if(Recent[i].bHasFocus != 0)
			return i;
	}

	return -1;
}

simulated function RecentSelected()
{
	local int i;

	i = FocusedRecent();

	if(i != -1)
	{
		AddressBox.Blurred.Text = Recent[i].Blurred.Text;
		Connect(Recent[i].Blurred.Text);
	}
}

simulated function HandleInputBack()
{
	// Also opened directly from the command line (the join batch file) where there is no menu to go back to
	GotoMenuClass("XInterfaceCTMenus.CTMultiplayerPCMenu");
}

defaultproperties
{
	MenuTitle=(Text="CO-OP CAMPAIGN: JOIN (MOD 0.4)",bHidden=0)
	LabelBackground=(WidgetTexture=Texture'GUIContent.Menu.CT_ButtonDefault',DrawColor=(B=192,G=192,R=192,A=128),DrawPivot=DP_MiddleMiddle,PosX=0.5,PosY=0.25,ScaleX=0.365,ScaleY=0.04333,ScaleMode=MSCM_FitStretch)
	Label=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="HOST IP ADDRESS",DrawColor=(B=192,G=192,R=192,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.5,PosY=0.25,ScaleY=0.8)
	AddressBox=(MaxLength=40,bNoSpaces=1,Blurred=(MenuFont=Font'OrbitFonts.OrbitBold15',DrawColor=(B=255,G=200,R=120,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.5,PosY=0.33,ScaleX=1,ScaleY=0.8),BackgroundBlurred=(WidgetTexture=Texture'GUIContent.Menu.CT_DisplayBox',DrawColor=(B=255,G=255,R=255,A=192),DrawPivot=DP_MiddleMiddle,PosX=0.5,PosY=0.33,ScaleX=0.5,ScaleY=0.04333,ScaleMode=MSCM_FitStretch),OnSelect="OnAButton")
	StatusText=(MenuFont=Font'OrbitFonts.OrbitBold15',DrawColor=(B=120,G=220,R=255,A=255),DrawPivot=DP_MiddleLeft,PosX=0.1,PosY=0.7,ScaleX=0.6,ScaleY=0.6,MaxSizeX=0.8,bWordWrap=1,Pass=2)
	ConnectingStr="CONNECTING TO"
	NoAnswerStr="NO ANSWER FROM THE HOST OR THE CONNECTION WAS CLOSED. IF THE HOST'S LOG SHOWS YOUR 'LOGIN REQUEST', YOU HAVE DIFFERENT MOD VERSIONS: BOTH PLAYERS MUST USE THE SAME ARCHIVE. OTHERWISE CHECK: THE IP ADDRESS, THAT THE HOST HAS STARTED THE SERVER, THAT BOTH PCS ARE IN THE SAME ZEROTIER/RADMIN NETWORK, AND THE WINDOWS FIREWALL ON THE HOST (RUN 'FIREWALL' BATCH FILE, SEE README)."
	ErrorText=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="ENTER AN ADDRESS LIKE 192.168.1.10 OR 192.168.1.10:7777",DrawColor=(B=64,G=64,R=255,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.5,PosY=0.385,ScaleX=0.6,ScaleY=0.6,Pass=2)
	RecentLabel=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="RECENT",DrawColor=(B=192,G=192,R=192,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.5,PosY=0.45,ScaleX=0.8,ScaleY=0.8,Pass=2)
	Recent(0)=(Blurred=(Text="",PosX=0.5,PosY=0.51),BackgroundBlurred=(PosX=0.5,PosY=0.51,ScaleX=0.38,ScaleY=0.04333),OnSelect="RecentSelected",Style="ButtonTextStyle1")
	Recent(1)=(Blurred=(PosY=0.56666),BackgroundBlurred=(PosY=0.56666))
	HelpText=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="LAN AND VPN (ZEROTIER, RADMIN, HAMACHI) ADDRESSES WORK WITHOUT PORT FORWARDING. EVERYBODY NEEDS THE SAME VERSION OF THE MOD.",DrawPivot=DP_MiddleLeft,PosX=0.1,PosY=0.83,ScaleX=0.6,ScaleY=0.6,MaxSizeX=0.8,bWordWrap=1,Pass=2,Style="LabelText")
	AButton=(Blurred=(Text="CONNECT"),bHidden=0)
	Background=(WidgetTexture=Texture'GUIContent.Menu.CT_MainMenuGraphics',Style="FullScreen")
}
