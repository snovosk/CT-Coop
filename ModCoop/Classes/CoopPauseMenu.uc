class CoopPauseMenu extends CTMultiplayerPausePCMenu;

#exec OBJ LOAD FILE="XInterface.u"
#exec OBJ LOAD FILE="XInterfaceCTMenus.u"

/*
 * CoopPauseMenu
 * Purpose: the multiplayer pause menu, with LOAD CHECKPOINT and SAVE GAME (CoopSaveMenu) for the host of a coop game.
 * Entry points: CoopPlayer.ShowMenu opens it for the host, CoopExtension.RedirectMenuClass when a menu goes back to the pause menu by name.
 *   The slots of CHANGE TEAMS and of the spectator mode are reused, coop has neither.
 * Logging: CoopGame logs the action (CoopLoadCheckpoint).
 * State: bLoadCheckpointSelected, while the question is open.
 * Known limitations: none known.
 */

var string LoadCheckpointLabel, LoadCheckpointConfirm, SaveGameLabel;
var bool bLoadCheckpointSelected;

simulated function Init(String Args)
{
	Super.Init(Args);

	if(CoopGame(Level.Game) == None || CoopPlayer(Owner) == None || !CoopPlayer(Owner).IsCoopHost())
		return;

	MenuOptions[1].Blurred.Text = LoadCheckpointLabel;
	MenuOptions[1].OnSelect = 'LoadCheckpointSelected';
	MenuOptions[1].bHidden = 0;

	// The slot of the spectator mode, coop has none
	MenuOptions[2].Blurred.Text = SaveGameLabel;
	MenuOptions[2].OnSelect = 'SaveGameSelected';
	MenuOptions[2].bHidden = 0;

	// AdjustButtons takes the spacing from the first two entries, and Super.Init has already moved the first one
	MenuOptions[0].Blurred.PosY = default.MenuOptions[0].Blurred.PosY;
	MenuOptions[1].Blurred.PosY = default.MenuOptions[1].Blurred.PosY;
	MenuOptions[2].Blurred.PosY = default.MenuOptions[2].Blurred.PosY;
	AdjustButtons();
}

simulated function SaveGameSelected()
{
	CallMenuClass("ModCoop.CoopSaveMenu");
}

simulated function LoadCheckpointSelected()
{
	bLoadCheckpointSelected = True;
	OverlayMenuClass("XInterface.MenuQuestionYesNo", MakeQuotedString(LoadCheckpointConfirm));
}

simulated function ConfirmLoadCheckpoint()
{
	local CoopGame Game;

	Game = CoopGame(Level.Game);
	GetPlayerOwner().SetPause(false);
	GetPlayerOwner().MenuClose();

	if(Game != None)
		Game.CoopLoadCheckpoint();
}

simulated function bool MenuClosed(Menu closingMenu)
{
	local MenuQuestionYesNo QuestionMenu;

	if(!bLoadCheckpointSelected)
		return Super.MenuClosed(closingMenu);

	QuestionMenu = MenuQuestionYesNo(closingMenu);

	if(QuestionMenu == None)
		return false;

	bLoadCheckpointSelected = False;

	if(QuestionMenu.bSelectedYes)
		ConfirmLoadCheckpoint();

	return true;
}

defaultproperties
{
	LoadCheckpointLabel="LOAD CHECKPOINT"
	SaveGameLabel="SAVE GAME"
	LoadCheckpointConfirm="LOAD THE LAST CHECKPOINT FOR ALL PLAYERS?  ANY PROGRESS SINCE THEN WILL BE LOST."
}
