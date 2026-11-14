class CoopHostMenu extends MenuTemplateTitledBA;

#exec OBJ LOAD FILE="XInterface.u"

/*
 * CoopHostMenu
 * Creates the lobby (CoopLobby) of a coop game, nothing else: the level, the save slot and the number of players are picked there (the
 *   user, 2026-11-12). The last level is its start (?CoopLobbyLevel). CoopLobbyMenu uses the three rows of this menu.
 */

const NUM_OPTIONS = 3;
const OPTION_LEVEL = 0;
const OPTION_PLAYERS = 1;
const OPTION_SAVE = 2;

var() MenuSprite        OptionsBorder;
var() MenuText          OptionLabels[NUM_OPTIONS];
var() MenuButtonEnum    Options[NUM_OPTIONS];
var() MenuButtonSprite  OptionLeftArrows[NUM_OPTIONS];
var() MenuButtonSprite  OptionRightArrows[NUM_OPTIONS];
var() MenuText          HelpText;
var() string            TitleText;
var array<int>          SaveSlots;  // Slot of each item of the save row, 0 for a new game

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

	FillSaves();
	FocusOnWidget(Options[OPTION_LEVEL]);

	// Everything is picked in the lobby (the user, 2026-11-12): here only the button. The lobby uses all three rows
	if(!IsA('CoopLobbyMenu'))
		HideRows();
	MenuTitle.Text = TitleText $ " (MOD " $ class'CoopConfig'.static.Version() $ ")";
}

// NEW GAME and the slots this build can load
simulated function FillSaves()
{
	local int i;

	Options[OPTION_SAVE].Items.Length = 1;
	Options[OPTION_SAVE].Items[0] = "NEW GAME";
	SaveSlots.Length = 1;
	SaveSlots[0] = 0;

	for(i = 1; i <= class'CoopSaveSlots'.static.NumSlots(); ++i)
	{
		if(class'CoopSaveSlots'.static.IsCompatible(i))
		{
			SaveSlots[SaveSlots.Length] = i;
			Options[OPTION_SAVE].Items[Options[OPTION_SAVE].Items.Length] = class'CoopSaveSlots'.static.Describe(i);
		}
	}

	Options[OPTION_SAVE].Current = 0;
}

// The host menu without rows: the lobby picks the level, the save and the number of players
simulated function HideRows()
{
	local int i;

	for(i = 0; i < NUM_OPTIONS; ++i)
	{
		OptionLabels[i].bHidden = 1;
		Options[i].bHidden = 1;
		OptionLeftArrows[i].bHidden = 1;
		OptionRightArrows[i].bHidden = 1;
	}

	OptionsBorder.bHidden = 1;
	FocusOnWidget(AButton);
}

simulated function MoveRow(int i, float Y)
{
	OptionLabels[i].PosY = Y;
	Options[i].Blurred.PosY = Y;
	Options[i].BackgroundBlurred.PosY = Y;
	OptionLeftArrows[i].Blurred.PosY = Y;
	OptionRightArrows[i].Blurred.PosY = Y;
}

simulated function int SelectedSave()
{
	if(Options[OPTION_SAVE].Current < 0 || Options[OPTION_SAVE].Current >= SaveSlots.Length)
		return 0;

	return SaveSlots[Options[OPTION_SAVE].Current];
}

// The index of a level in the level row, added when it isn't there
simulated function int LevelItem(string Map)
{
	local int i;

	for(i = 0; i < Options[OPTION_LEVEL].Items.Length; ++i)
	{
		if(Options[OPTION_LEVEL].Items[i] ~= Map)
			return i;
	}

	Options[OPTION_LEVEL].Items[i] = Map;
	return i;
}

// A save sets the level and the players it had, and the level can't be changed while it is picked
simulated function ApplySave()
{
	local int Slot;

	Slot = SelectedSave();

	if(Options[OPTION_LEVEL].bHidden == 0)
	{
		OptionLeftArrows[OPTION_LEVEL].bHidden = int(Slot != 0);
		OptionRightArrows[OPTION_LEVEL].bHidden = int(Slot != 0);
	}

	if(Slot == 0)
		return;

	Options[OPTION_LEVEL].Current = LevelItem(class'CoopSaveSlots'.static.Read(Slot, "Map"));
	Options[OPTION_PLAYERS].Current = Clamp(class'CoopSaveSlots'.static.NumPlayers(Slot) - 2, 0, Options[OPTION_PLAYERS].Items.Length - 1);
}

simulated function ChangeOption(int i, int Delta)
{
	local int NewItem;

	if(i == OPTION_LEVEL && SelectedSave() != 0)
		return;

	NewItem = Options[i].Current + Delta;

	if(NewItem >= Options[i].Items.Length)
		NewItem = 0;
	else if(NewItem < 0)
		NewItem = Options[i].Items.Length - 1;

	Options[i].Current = NewItem;

	if(i == OPTION_SAVE)
		ApplySave();
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

	// The lobby starts with room for everybody and the last level, the host sets both there (CoopLobbyMenu)
	Map = Options[OPTION_LEVEL].Items[Options[OPTION_LEVEL].Current];
	Players = 4;

	class'CoopConfig'.static.StaticSaveConfig();
	class'CoopConfig'.static.EndSession(); // The host never reconnects

	class'GameEngine'.default.DisconnectMenuClass = "ModCoop.CoopMultiplayerMenu";
	class'GameEngine'.default.DisconnectMenuArgs = "";

	// Must be done before the server starts listening
	class'CoopNative'.static.AddServerPackage("ModCoop");

	GetPlayerOwner().MenuClose();
	GetPlayerOwner().ClientTravel("MPCustom?game=ModCoop.CoopGame?listen?MaxPlayers=" $ Players $ "?CoopLobby=1?CoopLobbyLevel=" $ Map,
	                              TRAVEL_Absolute, false);
}

simulated function HandleInputBack()
{
	CloseMenu();
}

defaultproperties
{
	MenuTitle=(Text="CO-OP CAMPAIGN: HOST (MOD 0.59)",bHidden=0)
	OptionsBorder=(PosX=0.5,PosY=0.41,ScaleX=0.8,ScaleY=0.26,Style="BorderStyle1")
	OptionLabels(0)=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="LEVEL",DrawPivot=DP_MiddleLeft,PosX=0.15,PosY=0.34,ScaleX=0.8,ScaleY=0.8,Pass=2,Style="LabelText")
	OptionLabels(1)=(Text="MAX PLAYERS",PosY=0.41)
	OptionLabels(2)=(Text="SAVE",PosY=0.48)
	Options(0)=(Items=("GEO_01A"),Blurred=(PosX=0.68,PosY=0.34,ScaleX=0.8,ScaleY=0.8),BackgroundBlurred=(PosX=0.68,PosY=0.34,ScaleX=0.3,ScaleY=0.035),OnLeft="OnLeft",OnRight="OnRight",Pass=2,Style="ButtonEnumStyle1")
	Options(1)=(Items=("2","3","4"),Blurred=(PosY=0.41),BackgroundBlurred=(PosY=0.41))
	Options(2)=(Items=("NEW GAME"),Blurred=(PosY=0.48,ScaleX=0.55,ScaleY=0.6),BackgroundBlurred=(PosY=0.48))
	OptionLeftArrows(0)=(Blurred=(WidgetTexture=Texture'GUIContent.Menu.CT_ArrowLeft',DrawColor=(B=255,G=255,R=255,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.51,PosY=0.34,ScaleX=0.5,ScaleY=0.5),Focused=(DrawColor=(B=255,G=255,R=255,A=255),ScaleX=0.65,ScaleY=0.65),bIgnoreController=1,OnSelect="OnLeft",Pass=2)
	OptionLeftArrows(1)=(Blurred=(PosX=0.51,PosY=0.41))
	OptionLeftArrows(2)=(Blurred=(PosX=0.51,PosY=0.48))
	OptionRightArrows(0)=(Blurred=(WidgetTexture=Texture'GUIContent.Menu.CT_ArrowRight',DrawColor=(B=255,G=255,R=255,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.85,PosY=0.34,ScaleX=0.5,ScaleY=0.5),Focused=(DrawColor=(B=255,G=255,R=255,A=255),ScaleX=0.65,ScaleY=0.65),bIgnoreController=1,OnSelect="OnRight",Pass=2)
	OptionRightArrows(1)=(Blurred=(PosX=0.85,PosY=0.41))
	OptionRightArrows(2)=(Blurred=(PosX=0.85,PosY=0.48))
	HelpText=(MenuFont=Font'OrbitFonts.OrbitBold15',Text="OTHER PLAYERS JOIN WITH YOUR IP ADDRESS (LAN OR VPN), PORT 7777. YOU ARE THE SERVER: PROGRESS AND CHECKPOINTS ARE YOURS.",DrawPivot=DP_MiddleLeft,PosX=0.1,PosY=0.62,ScaleX=0.6,ScaleY=0.6,MaxSizeX=0.8,bWordWrap=1,Pass=2,Style="LabelText")
	AButton=(Blurred=(Text="CREATE LOBBY"),bHidden=0)
	TitleText="CO-OP CAMPAIGN: HOST"
	Background=(WidgetTexture=Texture'GUIContent.Menu.CT_MainMenuGraphics',Style="FullScreen")
}
