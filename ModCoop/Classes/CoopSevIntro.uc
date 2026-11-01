class CoopSevIntro extends Object;

/*
 * CoopSevIntro
 * Purpose: the scene on GEO_01C in which Sev falls among the enemies and kills them (his script: wait for 07Intro, animation SevIntro, a
 *   voice line, then a walk to 07StartPoint). Everybody sees it: the client playing Sev over his shoulder, the other clients and the host
 *   looking at him. When the animation ends they all get the control together, and Sev's client takes him where he stands: the
 *   walk of the script is dropped. The events behind the voice line (PopUp07Intro, ActivateSquad) keep their time.
 * Entry points: Setup (CoopGame.InitGame), IsRunning, IsSev (CoopGame.StartIntroWatch, CheckIntroWatch, CheckRopeLandings), Check (CoopGame,
 *   every 0.2 s).
 * Logging: "CoopGame: Sev intro".
 * State: Game, bSearching, Searches, Sev, Script, AnimIndex, LineIndex, WalkIndex, bActive, bAnimStarted, AnimStart, PendingEvents, PendingTimes.
 * Known limitations: a single scene of a single level. A squad HUD blink of the script is dropped together with its walk.
 */

const MAX_WAIT_FOR_ANIM = 90.0;
const MAX_ANIM_TIME = 30.0;
const MAX_SEARCHES = 200;

var CoopGame Game;
var Pawn Sev;
var ScriptedSequence Script;
var int AnimIndex, LineIndex, WalkIndex;
var bool bActive, bAnimStarted, bSearching;
var int Searches;
var float AnimStart, NextTraceLog;
var array<name> PendingEvents;
var array<float> PendingTimes;

function Setup(CoopGame G)
{
	Game = G;
	bSearching = Left(Caps(string(Game.Level)), 7) == "GEO_01C";
}

// The squad's scripts aren't there yet when the game is set up (CoopGame.InitGame)
function Search()
{
	local ScriptedController SC;
	local ScriptedAction Action;
	local Pawn P;
	local int i;

	if(!bSearching)
		return;

	foreach Game.DynamicActors(class'Pawn', P)
	{
		SC = ScriptedController(P.Controller);

		if(!P.IsA('Commando07Delta') || SC == None || SC.SequenceScript == None)
			continue;

		AnimIndex = -1;
		LineIndex = -1;
		WalkIndex = -1;

		for(i = 0; i < SC.SequenceScript.Actions.Length; ++i)
		{
			Action = SC.SequenceScript.Actions[i];

			if(AnimIndex == -1 && ACTION_PlayAnim(Action) != None && ACTION_PlayAnim(Action).BaseAnim == 'SevIntro')
				AnimIndex = i;
			else if(AnimIndex != -1 && LineIndex == -1 && ACTION_PlaySound(Action) != None)
				LineIndex = i;
			else if(LineIndex != -1 && WalkIndex == -1 && ACTION_MoveToPoint(Action) != None)
				WalkIndex = i;
		}

		if(WalkIndex != -1)
		{
			Sev = P;
			Script = SC.SequenceScript;
			bActive = true;
			bSearching = false;
			Log("CoopGame: Sev intro: " $ P $ ", animation at action " $ AnimIndex $ ", voice line " $ LineIndex $ ", walk " $ WalkIndex);
			return;
		}
	}

	if(++Searches >= MAX_SEARCHES)
	{
		bSearching = false;
		Log("CoopGame: Sev intro: script not found");
	}
}

function bool IsRunning()
{
	Search();
	return bActive;
}

function bool IsSev(Pawn P)
{
	Search();
	return bActive && P == Sev;
}

function vector SevViewPoint()
{
	local vector Head;

	// The bone follows the animation, the location of the pawn jumps
	Head = Sev.GetBoneLocation('lightAttach');

	if(Head == vect(0,0,0) || VSize(Head - Sev.Location) > 3000)
		Head = Sev.Location;

	return Head;
}

function Check()
{
	local ScriptedController SC;
	local Controller C;
	local CoopPlayer CP;
	local int i;

	for(i = 0; i < PendingEvents.Length; ++i)
	{
		if(Game.Level.TimeSeconds >= PendingTimes[i])
		{
			Log("CoopGame: Sev intro: triggering " $ PendingEvents[i]);
			Game.TriggerEvent(PendingEvents[i], Game, Sev);
			PendingEvents.Remove(i, 1);
			PendingTimes.Remove(i, 1);
			--i;
		}
	}

	if(!IsRunning())
		return;

	if(Sev == None || Sev.bDeleteMe)
	{
		Finish("Sev is gone");
		return;
	}

	SC = ScriptedController(Sev.Controller);

	if(SC == None || SC.SequenceScript != Script || !SC.IsInState('Scripting'))
	{
		Finish("the script is over");
		return;
	}

	if(!bAnimStarted)
	{
		if(SC.ActionNum >= AnimIndex)
		{
			bAnimStarted = true;
			AnimStart = Game.Level.TimeSeconds;
			Log("CoopGame: Sev intro: the animation starts at " $ Sev.Location);
		}
		else
		{
			if(Game.Level.TimeSeconds - Game.LevelStartTime > MAX_WAIT_FOR_ANIM)
				Finish("the animation didn't start");

			return;
		}
	}

	if(SC.ActionNum >= LineIndex)
	{
		Finish("the animation is over after " $ (Game.Level.TimeSeconds - AnimStart) $ " s");
		return;
	}

	if(Game.Level.TimeSeconds - AnimStart > MAX_ANIM_TIME)
	{
		Finish("the animation took too long");
		return;
	}

	if(Game.Level.TimeSeconds >= NextTraceLog)
	{
		NextTraceLog = Game.Level.TimeSeconds + 1;
		Log("CoopGame: Sev intro: Sev at " $ Sev.Location $ " physics " $ Sev.Physics $ " action " $ SC.ActionNum);
	}

	// The other clients look at him over the shoulders of their members
	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP != None && CP.WatchedMember != None && CP.WatchedMember != Sev)
			CP.ClientCoopSetWatchFocus(SevViewPoint(), true);
	}
}

function Finish(string Reason)
{
	local ScriptedController SC;
	local ScriptedAction Action;
	local Controller C;
	local CoopPlayer CP, SevPlayer;
	local Pawn P;
	local float Frame, When;
	local int i;

	Log("CoopGame: Sev intro: over, " $ Reason);
	bActive = false;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None)
			continue;

		if(CP.WatchedMember != None)
			CP.ClientCoopSetWatchFocus(vect(0,0,0), false);

		if(CP.WatchedMember != None && CP.WatchedMember == Sev && CP.bIntroWatch)
			SevPlayer = CP;

		// The host: the script keeps its briefing state until ActivateSquad. Still on the rope: CoopGame.CheckRopeLandings does it
		P = CP.Pawn;

		if(Game.IsHost(CP) && P != None && CP.IsInState('Briefing') && !CP.bLiftView && (!Game.IsOnRope(P, Frame) || Frame >= 0.9))
		{
			CP.GotoState('PlayerWalking');
			P.ChangeAnimation();
		}
	}

	SC = None;

	if(Sev != None)
		SC = ScriptedController(Sev.Controller);

	if(SevPlayer == None || Sev == None || Sev.bDeleteMe)
		return;

	// The script stands on the voice line, which plays on. What's behind it comes at its time, the walk not at all
	if(SC != None && SC.SequenceScript == Script && SC.ActionNum >= LineIndex && SC.ActionNum < WalkIndex)
	{
		When = Game.Level.TimeSeconds;

		for(i = SC.ActionNum; i < WalkIndex; ++i)
		{
			Action = Script.Actions[i];

			if(ACTION_PlaySound(Action) != None)
				When += Game.GetSoundDuration(ACTION_PlaySound(Action).Sound);
			else if(ACTION_WaitForTimer(Action) != None)
				When += ACTION_WaitForTimer(Action).PauseTime;
			else if(ACTION_TriggerEvent(Action) != None && ACTION_TriggerEvent(Action).Event != '')
			{
				PendingEvents[PendingEvents.Length] = ACTION_TriggerEvent(Action).Event;
				PendingTimes[PendingTimes.Length] = When;
			}
		}

		// CoopGame.TakeOver runs what the script skips from here on
		SC.ActionNum = WalkIndex;
	}

	SevPlayer.bIntroWatch = false;
	Game.TakeOver(SevPlayer, Sev, false);
}
