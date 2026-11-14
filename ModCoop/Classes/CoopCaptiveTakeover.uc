class CoopCaptiveTakeover extends Object;

/*
 * CoopCaptiveTakeover
 * Purpose: a squad member a level script keeps as a captive and puts down (RAS_02C: Sev at his execution, RAS_02D: Scorch in the cell) is out of
 *   the squad, so the client that plays him only got him back when he was revived and joined again, in the middle of the next fight (session
 *   2026-11-10). The user's decision: a zone around the lying captive; when any player steps into it, the camera of the client bound to that
 *   member flies to him and the client plays him, still down, until somebody revives him. His revive event (07Revived, 62Revived) opens the way on.
 * Entry points: Setup (CoopGame.CheckLevel), Check (CoopGame.Timer), IsCaptive (CoopGame: no bleed-out for a captive's client).
 * Logging: "CoopGame: captive".
 * State: Game, Captives (taken over while down, until revived). Server only.
 * Known limitations: needs a client bound to that member, or a free one; without one the captive stays with the AI as before.
 *   A captive is found by its state, not by a table: down, a Delta member, not in the host's squad.
 */

const ZONE_RADIUS = 700.0;

var CoopGame Game;
var array<Pawn> Captives;

function Setup(CoopGame G)
{
	Game = G;
}

// The client playing him doesn't bleed out: dead, he couldn't be revived and the revive event the level waits for would never come
function bool IsCaptive(Pawn P)
{
	local int i;

	for(i = 0; i < Captives.Length; ++i)
	{
		if(Captives[i] == P)
			return P != None && P.bIncapacitated;
	}

	return false;
}

function Check()
{
	local PlayerController Host;
	local CoopPlayer CP;
	local Pawn P;
	local int i;

	for(i = Captives.Length - 1; i >= 0; --i)
	{
		if(Captives[i] == None || Captives[i].bDeleteMe || !Captives[i].bIncapacitated)
		{
			if(Captives[i] != None && !Captives[i].bDeleteMe)
				Log("CoopGame: captive " $ Captives[i] $ " is up again");

			Captives.Remove(i, 1);
		}
	}

	Host = Game.GetHost();

	if(!Game.bClientsTakeOverSquad || Host == None || Host.Pawn == None)
		return;

	foreach Game.DynamicActors(class'Pawn', P)
	{
		if(!P.IsA('CloneCommando') || !P.bIncapacitated || P.bDeleteMe || PlayerController(P.Controller) != None || P == Host.Pawn)
			continue;

		// A member down in a fight is still in the squad, the squad revives him
		if(P.Squad != None && P.Squad == Host.Pawn.Squad)
			continue;

		if(!IsPlayerNear(P))
			continue;

		CP = FindClientFor(P);

		if(CP == None)
			continue;

		Log("CoopGame: captive " $ P $ " (" $ P.Class.Name $ ") reached, " $ CP.PlayerReplicationInfo.PlayerName $ " takes him over while he is down");
		Captives[Captives.Length] = P;
		Game.TakeOver(CP, P, true);

		return; // One per second
	}
}

function bool IsPlayerNear(Pawn Captive)
{
	local Controller C;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) != None && C.Pawn != None && C.Pawn != Captive && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated &&
		   VSize(C.Pawn.Location - Captive.Location) < ZONE_RADIUS)
			return true;
	}

	return false;
}

// The client bound to this member, else the nearest client without one (as CoopGame.CheckSquadTakeover), on its own commando and up
function CoopPlayer FindClientFor(Pawn Captive)
{
	local Controller C, Best;

	C = Game.FindAssignedPlayer(Captive);

	if(C != None)
	{
		if(IsReady(CoopPlayer(C)))
			return CoopPlayer(C);

		return None; // Reserved for that client
	}

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(IsReady(CoopPlayer(C)) && Game.IsFreeForMember(PlayerController(C)) &&
		   (Best == None || VSize(C.Pawn.Location - Captive.Location) < VSize(Best.Pawn.Location - Captive.Location)))
			Best = C;
	}

	if(Best != None)
		Game.SetAssignment(PlayerController(Best), string(Captive.Class));

	return CoopPlayer(Best);
}

function bool IsReady(CoopPlayer CP)
{
	return CP != None && !Game.IsHost(CP) && CoopCommando(CP.Pawn) != None && CP.Pawn.Health > 0 && !CP.Pawn.bIncapacitated && !CP.bIntroWatch && !CP.bInBreach;
}
