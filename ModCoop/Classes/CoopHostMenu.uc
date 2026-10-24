class CoopHostMenu extends MenuTemplateTitledBA;

#exec OBJ LOAD FILE="XInterface.u"

/*
 * CoopHostMenu
 * Starts a listen server running the coop game on the selected campaign level.
 */

const NUM_OPTIONS = 2;
const OPTION_LEVEL = 0;
const OPTION_PLAYERS = 1;

var() MenuSprite        OptionsBorder;
var() MenuText          OptionLabels[NUM_OPTIONS];
var() MenuButtonEnum    Options[NUM_OPTIONS];
var() MenuButtonSprite  OptionLeftArrows[NUM_OPTIONS];
var() MenuButtonSprite  OptionRightArrows[NUM_OPTIONS];
var() MenuText          HelpText;

simulated function Init(string Args)
{
	local int i, j;

	Super.Init(Args);

	Options[OPTION_LEVEL].Items.Length = 0;

	// Skip duplicates: the config can be loaded twice (see CoopNative.LoadSavedConfig) and 'CoopLevels+=' then adds the levels twice
	for(i = 0; i < class'CoopConfig'.default.CoopLevels.Length; ++i)
	{
		for(j = 0; j < Options[OPTION_LEVEL].Items.Length; ++j)
		{
			if(Options[OPTION_LEVEL].Items[j] ~= class'CoopConfig'.default.CoopLevels[i])
				break;
		}

		if(j == Options[OPTION_LEVEL].Items.Length && class'CoopConfig'.default.CoopLevels[i] != "")
			Options[OPTION_LEVEL].Items[Options[OPTION_LEVEL].Items.Length] = class'CoopConfig'.default.CoopLevels[i];
	}

	Log("ModCoop: " $ Options[OPTION_LEVEL].Items.Length $ " coop levels in the host menu");

	if(Options[OPTION_LEVEL].Items.Length == 0)
		Options[OPTION_LEVEL].Items[0] = "GEO_01A";

	Options[OPTION_LEVEL].Current = Clamp(class'CoopConfig'.default.LastLevelIndex, 0, Options[OPTION_LEVEL].Items.Length - 1);
	Options[OPTION_PLAYERS].Current = Clamp(class'CoopConfig'.default.LastMaxPlayers - 2, 0, Options[OPTION_PLAYERS].Items.Length - 1);

	FocusOnWidget(Options[OPTION_LEVEL]);
}

simulated function ChangeOption(int i, int Delta)
{
	local int NewItem;

	NewItem = Options[i].Current + Delta;

	if(NewItem >= Options[i].Items.Length)
		NewItem = 0;
	else if(NewItem < 0)
		NewItem = Options[i].Items.Length - 1;

	Options[i].Current = NewItem;
}

simulated function int FocusedOption()
{
	local int i;

	for(i = 0; i < NUM_OPTIONS; ++i)
	{
		if(Options[i].bHasFocus != 0 || OptionLeftArrows[i].bHasFocus != 0 || OptionRightArrows[i].bHasFocus != 0)
			return i;
	}

	return -1;
}

simulated function OnLeft()
{
	local int i;

	i = FocusedOption();

	if(i != -1)
		ChangeOption(i, -1);
}

simulated function OnRight()
{
	local int i;

	i = FocusedOption();

	if(i != -1)
		ChangeOption(i, 1);
}

simulated function OnAButton()
{
	local string Map;
	local int Players;

	Map = Options[OPTION_LEVEL].Items[Options[OPTION_LEVEL].Current];
	Players = Options[OPTION_PLAYERS].Current + 2;

	class'CoopConfig'.default.LastLevelIndex = Options[OPTION_LEVEL].Current;
	class'CoopConfig'.default.LastMaxPlayers = Players;
	class'CoopConfig'.static.StaticSaveConfig();
	class'CoopConfig'.static.EndSession(); // The host never reconnects

	class'GameEngine'.default.DisconnectMenuClass = "XInterfaceCTMenus.CTMultiplayerPCMenu";
	class'GameEngine'.default.DisconnectMenuArgs = "";

	// Must be done before the server starts listening
	class'CoopNative'.static.AddServerPackage("ModCoop");

	GetPlayerOwner().MenuClose();
	GetPlayerOwner().ClientTravel(Map $ "?game=ModCoop.CoopGame?listen?MaxPlayers=" $ Players, TRAVEL_Absolute, false);
}

simulated function HandleInputBack()
{
	CloseMenu();
}

defaultproperties
{
	MenuTitle=(Text="CO-OP CAMPAIGN: HOST (MOD 0.4)",bHidden=0)
	OptionsBorder=(PosX=0.5,PosY=0.42,ScaleX=0.8,ScaleY=0.2,Style="BorderStyle1")
	OptionLabels(0)=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="LEVEL",DrawPivot=DP_MiddleLeft,PosX=0.15,PosY=0.37,ScaleX=0.8,ScaleY=0.8,Pass=2,Style="LabelText")
	OptionLabels(1)=(Text="MAX PLAYERS",PosY=0.45)
	Options(0)=(Items=("GEO_01A"),Blurred=(PosX=0.68,PosY=0.37,ScaleX=0.8,ScaleY=0.8),BackgroundBlurred=(PosX=0.68,PosY=0.37,ScaleX=0.3,ScaleY=0.035),OnLeft="OnLeft",OnRight="OnRight",Pass=2,Style="ButtonEnumStyle1")
	Options(1)=(Items=("2","3","4"),Blurred=(PosY=0.45),BackgroundBlurred=(PosY=0.45))
	OptionLeftArrows(0)=(Blurred=(WidgetTexture=Texture'GUIContent.Menu.CT_ArrowLeft',DrawColor=(B=255,G=255,R=255,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.51,PosY=0.37,ScaleX=0.5,ScaleY=0.5),Focused=(DrawColor=(B=255,G=255,R=255,A=255),ScaleX=0.65,ScaleY=0.65),bIgnoreController=1,OnSelect="OnLeft",Pass=2)
	OptionLeftArrows(1)=(Blurred=(PosX=0.51,PosY=0.45))
	OptionRightArrows(0)=(Blurred=(WidgetTexture=Texture'GUIContent.Menu.CT_ArrowRight',DrawColor=(B=255,G=255,R=255,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.85,PosY=0.37,ScaleX=0.5,ScaleY=0.5),Focused=(DrawColor=(B=255,G=255,R=255,A=255),ScaleX=0.65,ScaleY=0.65),bIgnoreController=1,OnSelect="OnRight",Pass=2)
	OptionRightArrows(1)=(Blurred=(PosX=0.85,PosY=0.45))
	HelpText=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="OTHER PLAYERS JOIN WITH YOUR IP ADDRESS (LAN OR VPN), PORT 7777. YOU ARE THE SERVER: PROGRESS AND CHECKPOINTS ARE YOURS.",DrawPivot=DP_MiddleLeft,PosX=0.1,PosY=0.62,ScaleX=0.6,ScaleY=0.6,MaxSizeX=0.8,bWordWrap=1,Pass=2,Style="LabelText")
	AButton=(Blurred=(Text="START"),bHidden=0)
	Background=(WidgetTexture=Texture'GUIContent.Menu.CT_MainMenuGraphics',Style="FullScreen")
}
