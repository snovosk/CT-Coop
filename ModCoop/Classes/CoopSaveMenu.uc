class CoopSaveMenu extends MenuTemplateTitledBA;

#exec OBJ LOAD FILE="XInterface.u"

/*
 * CoopSaveMenu
 * Purpose: SAVE GAME of the host's pause menu: 5 slots (CoopSaveSlots), a used one asks before it is overwritten. The game is loaded in the
 *   lobby, where the host picks the slot as the level (CoopLobby).
 * Entry points: CoopPauseMenu.SaveGameSelected.
 * Logging: CoopGame.SaveToSlot ("CoopGame: save slot").
 * State: PendingSlot while the question is open.
 * Known limitations: no saving while a player is down or during a scene (CoopGame.SaveBlocker): the message says why.
 */

const NUM_SLOTS = 5;

var() MenuButtonText Slots[NUM_SLOTS];
var() MenuText Message;
var() localized string OverwriteQuestion, SavedText;
var int PendingSlot;

simulated function Init(string Args)
{
	Super.Init(Args);
	ShowSlots();
	FocusOnWidget(Slots[0]);
	HideAButton(1);
}

simulated function ShowSlots()
{
	local int i;

	for(i = 0; i < NUM_SLOTS; ++i)
		Slots[i].Blurred.Text = class'CoopSaveSlots'.static.Describe(i + 1);
}

simulated function Slot1Selected() { SlotSelected(1); }
simulated function Slot2Selected() { SlotSelected(2); }
simulated function Slot3Selected() { SlotSelected(3); }
simulated function Slot4Selected() { SlotSelected(4); }
simulated function Slot5Selected() { SlotSelected(5); }

simulated function SlotSelected(int Slot)
{
	local string Reason;

	if(CoopGame(GetPlayerOwner().Level.Game) == None)
		return;

	// Said before the question, not after it
	Reason = CoopGame(GetPlayerOwner().Level.Game).SaveBlocker();

	if(Reason != "")
	{
		Message.Text = Reason;
		return;
	}

	if(class'CoopSaveSlots'.static.IsUsed(Slot))
	{
		PendingSlot = Slot;
		OverlayMenuClass("XInterface.MenuQuestionYesNo", MakeQuotedString(OverwriteQuestion @ class'CoopSaveSlots'.static.Describe(Slot) $ "?"));
		return;
	}

	Save(Slot);
}

simulated function Save(int Slot)
{
	local string Reason;

	Reason = CoopGame(GetPlayerOwner().Level.Game).SaveToSlot(Slot);

	if(Reason == "")
		Message.Text = SavedText @ Slot;
	else
		Message.Text = Reason;

	ShowSlots();
}

simulated function bool MenuClosed(Menu ClosingMenu)
{
	local MenuQuestionYesNo QuestionMenu;
	local int Slot;

	QuestionMenu = MenuQuestionYesNo(ClosingMenu);

	if(QuestionMenu == None || PendingSlot == 0)
		return Super.MenuClosed(ClosingMenu);

	Slot = PendingSlot;
	PendingSlot = 0;

	if(QuestionMenu.bSelectedYes)
		Save(Slot);

	return true;
}

simulated function HandleInputBack()
{
	CloseMenu();
}

defaultproperties
{
	Slots(0)=(Blurred=(Text="SLOT 1",PosX=0.5,PosY=0.35),BackgroundBlurred=(PosX=0.5,PosY=0.35,ScaleX=0.7,ScaleY=0.04333),OnSelect="Slot1Selected",Style="ButtonTextStyle1")
	Slots(1)=(Blurred=(Text="SLOT 2",PosY=0.41),BackgroundBlurred=(PosY=0.41),OnSelect="Slot2Selected")
	Slots(2)=(Blurred=(Text="SLOT 3",PosY=0.47),BackgroundBlurred=(PosY=0.47),OnSelect="Slot3Selected")
	Slots(3)=(Blurred=(Text="SLOT 4",PosY=0.53),BackgroundBlurred=(PosY=0.53),OnSelect="Slot4Selected")
	Slots(4)=(Blurred=(Text="SLOT 5",PosY=0.59),BackgroundBlurred=(PosY=0.59),OnSelect="Slot5Selected")
	Message=(MenuFont=Font'OrbitFonts.OrbitBold15',DrawColor=(B=253,G=216,R=153,A=255),DrawPivot=DP_MiddleMiddle,PosX=0.5,PosY=0.68,ScaleX=0.7,ScaleY=0.7)
	OverwriteQuestion="OVERWRITE"
	SavedText="GAME SAVED TO SLOT"
	MenuTitle=(Text="CO-OP: SAVE GAME",bHidden=0)
}
