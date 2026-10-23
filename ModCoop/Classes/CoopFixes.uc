class CoopFixes extends Object;

#exec OBJ LOAD FILE="CTGame.u"
#exec OBJ LOAD FILE="Gameplay.u"
#exec OBJ LOAD FILE="XInterface.u"
#exec OBJ LOAD FILE="XInterfaceCTMenus.u"

/*
 * CoopFixes
 * Hooks into single player code that would break a coop session. Only active while a CoopGame exists (host side).
 * - ACTION_ChangeLevel: uses the coop travel URL so the game type and listen option are kept
 * - CTDebriefingInfo.OnAButton: the debriefing screen at the end of a mission uses 'open <map>' which only moves the host
 */

var CoopGame Game;

var FunctionOverride ChangeLevelOverride;
var FunctionOverride DebriefingOverride;
var FunctionOverride TravelPostAcceptOverride;
var FunctionOverride BleedOutOverride;

function Init(CoopGame InGame)
{
	local class<Object> DebriefingClass;

	Game = InGame;

	ChangeLevelOverride = new class'FunctionOverride';
	ChangeLevelOverride.Init(class'ACTION_ChangeLevel', 'InitActionFor', self, 'ChangeLevelInitActionFor');

	BleedOutOverride = new class'FunctionOverride';
	BleedOutOverride.Init(class'Pawn', 'BleedOut', self, 'PawnBleedOut');

	TravelPostAcceptOverride = new class'FunctionOverride';
	TravelPostAcceptOverride.Init(class'PlayerCommando', 'TravelPostAccept', self, 'PlayerCommandoTravelPostAccept');

	DebriefingClass = class<Object>(DynamicLoadObject("XInterfaceCTMenus.CTDebriefingInfo", class'Class', true));

	if(DebriefingClass != None)
	{
		DebriefingOverride = new class'FunctionOverride';
		DebriefingOverride.Init(DebriefingClass, 'OnAButton', self, 'DebriefingOnAButton');
	}
}

function Deinit()
{
	if(ChangeLevelOverride != None)
	{
		ChangeLevelOverride.Deinit();
		ChangeLevelOverride = None;
	}

	if(BleedOutOverride != None)
	{
		BleedOutOverride.Deinit();
		BleedOutOverride = None;
	}

	if(TravelPostAcceptOverride != None)
	{
		TravelPostAcceptOverride.Deinit();
		TravelPostAcceptOverride = None;
	}

	if(DebriefingOverride != None)
	{
		DebriefingOverride.Deinit();
		DebriefingOverride = None;
	}

	Game = None;
}

function bool ChangeLevelInitActionFor(ScriptedController C)
{
	local ACTION_ChangeLevel Action;

	Action = ACTION_ChangeLevel(ChangeLevelOverride.CurrentSelf);

	if(Game == None || Game.bDeleteMe)
		return Action.InitActionFor(C);

	Game.CoopTravel(Action.URL);

	return true;
}

// When the host and the whole squad are down the single player game makes the host bleed out (-> level restart). In coop a living client can still revive the host.
function PawnBleedOut()
{
	local Pawn P;

	P = Pawn(BleedOutOverride.CurrentSelf);

	if(Game != None && !Game.bDeleteMe && Game.ShouldDelayHostBleedOut(P))
		return;

	P.BleedOut();
}

simulated function DebriefingOnAButton()
{
	local CTDebriefingInfo Menu;

	Menu = CTDebriefingInfo(DebriefingOverride.CurrentSelf);

	if(Game == None || Game.bDeleteMe || Menu.TransitionToLevel == "" || Menu.Level.NetMode != NM_ListenServer)
	{
		Menu.OnAButton();
		return;
	}

	Menu.GetPlayerOwner().SetPause(false);
	Game.CoopTravel(Menu.TransitionToLevel);
}

/*
 * Same as PlayerCommando.TravelPostAccept (restores the squad's health and stance after a level change) but with the checks the original is missing.
 * The original crashes on a listen server when the squad of the new level does not match the one that traveled.
 */
function PlayerCommandoTravelPostAccept()
{
	local PlayerCommando P;
	local int i, j;
	local Pawn Member;

	P = PlayerCommando(TravelPostAcceptOverride.CurrentSelf);

	Log("CoopFixes: TravelPostAccept " $ P $ " Squad=" $ P.Squad $ " Stance=" $ P.CurrentStance);

	if(P.Squad == None)
		return;

	if(P.Squad.SquadMembers.Length > 1)
	{
		for(i = 0; i < P.Squad.SquadMembers.Length; ++i)
		{
			Member = P.Squad.SquadMembers[i].Pawn;

			if(Member == None)
				continue;

			for(j = 0; j < ArrayCount(P.SquadInfo); ++j)
			{
				if(P.SquadInfo[j].SquadMemberClass == Member.Class)
				{
					Member.Health = P.SquadInfo[j].SquadMemberHealth;
					Member.SetHealthLevel();
					P.SquadInfo[j].SquadMemberClass = None;
					break;
				}
			}
		}
	}

	// StanceSecurePosition can't travel properly
	if(P.CurrentStance != None && P.CurrentStance != class'StanceSecurePosition')
		P.Squad.SetStance(P.CurrentStance, false);
}
