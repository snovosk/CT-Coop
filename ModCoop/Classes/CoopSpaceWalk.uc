class CoopSpaceWalk extends Object;

/*
 * CoopSpaceWalk
 * Purpose: the start of RAS_01A, where the host floats from open space to the ship by the animation AFloatInTemplate (about 20.4 s, script
 *   SPACE_WALK). A client spawned next to him fell 1800 units (log of a real run), so clients now fly with him: the server moves their pawns
 *   next to the host every frame (root motion isn't relied on), and they land beside him when the level event DropshipAnimProp comes.
 *   Runs on the server only, which owns the position. The client gets the target through unreliable RPCs that are resent every 0.1 s, a lost
 *   one costs nothing; the end of the flight is reliable.
 * Entry points: Setup (CoopGame), IsRunning, SpawnFlyer and StartFlight (CoopGame.SpawnClient), Check (CoopGame.Tick, every frame).
 * Logging: "CoopGame: space walk host", "flyer" (once a second), "start", "land", "end", "abort".
 * State: Game, bOnMap, bFinished, bLanding, HostFrame, bHostInAnim, bHostAnimSeen, bHostBriefed, StartTime, LastHostLocation, Slots.
 * Known limitations: a single scene of a single level, three clients. The script's end of the briefing brings the host's weapon up a second
 *   time when he lands, that's the engine's Briefing.EndState. The host can fire while he floats.
 *   NOT VERIFIED: whether turning the freed camera bends the host's flight, if the animation moves him relative to the pawn's rotation.
 *   Check in the "space walk host" lines that loc= ends at the ship when the mouse was moved.
 */

const MAX_FLYERS = 3;

const ANIM_RATE = 1.0;
const ANIM_END_FRAME = 1.0;
const ANIM_REISSUE_INTERVAL = 1.0;

// The flyers close in on their landing spots over the last 40 % of the animation
const CLOSE_IN_FRAME = 0.6;
const CLOSE_IN_SPAN = 0.4;

const POSITION_INTERVAL = 0.1;
const LOG_INTERVAL = 1.0;
const MAX_FLIGHT_TIME = 40.0;

// The whole circle in both directions, like ACTION_Briefing's defaults: the level's script allows the host 1 unit
const FREE_ROTATION = 32768;

const FLOOR_TRACE_DEPTH = 300.0;
const LAND_CLEARANCE = 4.0;
const LAND_RINGS = 4;
const LAND_RING_STEP = 100.0;
const LAND_DIRECTIONS = 8;
const LAND_DIRECTION_STEP = 8192;
const LAND_MIN_SEPARATION = 80.0;

// The event comes about 0.4 s before the animation ends, the host can still be in the air then
const LAND_RETRY_TIME = 5.0;
const LAND_RETRY_INTERVAL = 0.25;

struct FlyerSlot
{
	var CoopPlayer CP;
	var Pawn P;
	var bool bFlying, bWasRelevant;
	var float NextAnim;
};

var CoopGame Game;
var bool bOnMap, bFinished, bLanding;
var bool bHostInAnim, bHostAnimSeen, bHostBriefed;
var float HostFrame, StartTime, NextPosition, NextLog, NextLandTry, LandDeadline;
var vector LastHostLocation;
var FlyerSlot Slots[MAX_FLYERS];

var name FloatAnim, EndEvent;
var vector StartOffsets[MAX_FLYERS], EndOffsets[MAX_FLYERS];

function Setup(CoopGame G)
{
	Game = G;
	bOnMap = Game.IsMap("RAS_01A");
}

function bool IsRunning()
{
	return bOnMap && !bFinished && !Game.WasHeard(EndEvent);
}

// Not through CoopGame.SpawnCommandoNear, that one needs a floor. Works at any point of the animation, a late join takes the same path
function Pawn SpawnFlyer(PlayerController Host, CoopPlayer CP)
{
	local Pawn P;
	local int i;

	if(!IsRunning() || Host == None || Host.Pawn == None || Host.Pawn.bDeleteMe)
		return None;

	for(i = 0; i < MAX_FLYERS; ++i)
	{
		if(Slots[i].P == None || Slots[i].P.bDeleteMe)
			break;
	}

	if(i == MAX_FLYERS)
	{
		Log("CoopGame: space walk abort: no free slot for " $ CP.PlayerReplicationInfo.PlayerName);
		return None;
	}

	P = Game.Spawn(class'CoopCommando',,, Host.Pawn.Location + StartOffsets[i], Host.Pawn.Rotation);

	if(P == None)
	{
		Log("CoopGame: space walk abort: spawn failed at " $ (Host.Pawn.Location + StartOffsets[i]) $ " for " $ CP.PlayerReplicationInfo.PlayerName);
		return None;
	}

	Slots[i].CP = CP;
	Slots[i].P = P;
	Slots[i].bFlying = false;
	Slots[i].NextAnim = 0;

	return P;
}

function StartFlight(CoopPlayer CP, Pawn P)
{
	local int i;

	for(i = 0; i < MAX_FLYERS; ++i)
	{
		if(P != None && Slots[i].P == P && Slots[i].CP == CP && !Slots[i].bFlying)
			break;
	}

	if(i == MAX_FLYERS)
		return;

	Slots[i].bFlying = true;
	Slots[i].bWasRelevant = P.bAlwaysRelevant;

	P.SetPhysics(PHYS_Flying);
	SetPawnCollision(P, false);
	P.bPhysicsAnimUpdate = false;

	// The ship's hull comes between the flyers on the way, the other clients must not lose this one behind it
	P.bAlwaysRelevant = true;

	if(StartTime == 0)
		StartTime = Game.Level.TimeSeconds;

	Log("CoopGame: space walk start: slot=" $ i $ " name=" $ CP.PlayerReplicationInfo.PlayerName $ " loc=" $ P.Location $ " hasanim=" $ P.HasAnim(FloatAnim) $ " weapon=" $ WeaponText(P));
}

function Check(float DeltaTime)
{
	local PlayerController Host;
	local string Reason;
	local bool bHostThere, bSend, bLog;
	local int i;

	if(!bOnMap)
		return;

	Host = Game.GetHost();
	bHostThere = Host != None && Host.Pawn != None && !Host.Pawn.bDeleteMe;

	if(bHostThere)
		LastHostLocation = Host.Pawn.Location;

	if(bFinished)
	{
		if(bLanding && Game.Level.TimeSeconds >= NextLandTry)
			LandAll();

		return;
	}

	if(!bHostThere)
	{
		// At the start of the level he doesn't have a pawn yet, that only counts once somebody depends on him
		if(HasFlyers())
			Finish("abort: the host is gone");

		return;
	}

	UpdateHost(Host);
	Reason = WhyOver(Host);

	if(Reason != "")
	{
		Finish(Reason);
		return;
	}

	bSend = Game.Level.TimeSeconds >= NextPosition;
	bLog = Game.Level.TimeSeconds >= NextLog;

	if(bSend)
		NextPosition = Game.Level.TimeSeconds + POSITION_INTERVAL;

	if(bLog)
	{
		NextLog = Game.Level.TimeSeconds + LOG_INTERVAL;
		Log("CoopGame: space walk host: frame=" $ HostFrame $ " loc=" $ Host.Pawn.Location $ " phys=" $ Host.Pawn.Physics $ " base=" $ Host.Pawn.Base $ " state=" $ Host.GetStateName() $ " weapon=" $ WeaponText(Host.Pawn));
	}

	for(i = 0; i < MAX_FLYERS; ++i)
	{
		if(Slots[i].P != None && !DropInvalidSlot(i) && Slots[i].bFlying)
			UpdateFlyer(i, Host, bSend, bLog);
	}
}

function UpdateHost(PlayerController Host)
{
	local name Seq;
	local float Frame;

	// The script's action 1, the animation is action 4. Before that a host outside the briefing means nothing
	if(Host.IsInState('Briefing'))
		bHostBriefed = true;

	Host.Pawn.GetAnimParams('', Seq, Frame);
	bHostInAnim = Seq == FloatAnim;

	if(bHostInAnim)
		HostFrame = Frame;
	else if(bHostAnimSeen)
		HostFrame = ANIM_END_FRAME;

	if(!bHostInAnim || bHostAnimSeen)
		return;

	bHostAnimSeen = true;

	// The clock of a flyer that waited for the host starts over: the 40 s are about the animation
	StartTime = Game.Level.TimeSeconds;

	Host.LimitRotation(FREE_ROTATION, -FREE_ROTATION, FREE_ROTATION, -FREE_ROTATION);
	BringUpHostWeapon(Host);
}

// ACTION_Briefing puts the weapon down but leaves it as Pawn.Weapon, in state DownWeapon. BringUp is the call Briefing.EndState itself makes, it goes
// to state Active and clears bChangeWeapon. A level started in the briefing can have no weapon at all, then the way of CoopPlayer.ShowHostWeaponInLift
function BringUpHostWeapon(PlayerController Host)
{
	if(Host.Pawn.Weapon != None)
		Host.Pawn.Weapon.BringUp(None);
	else
	{
		Host.bOkToSwitchWeapon = true;
		Host.SwitchToBestWeapon();
		Host.bOkToSwitchWeapon = false;
	}

	Log("CoopGame: space walk host: camera free, weapon=" $ WeaponText(Host.Pawn));
}

function string WhyOver(PlayerController Host)
{
	if(Game.WasHeard(EndEvent))
		return "end: event " $ EndEvent;

	if(bHostBriefed && !Host.IsInState('Briefing'))
		return "end: the host left Briefing";

	if(StartTime > 0 && Game.Level.TimeSeconds - StartTime > MAX_FLIGHT_TIME)
		return "abort: over the time limit, host frame " $ HostFrame;

	return "";
}

function bool HasFlyers()
{
	local int i;

	for(i = 0; i < MAX_FLYERS; ++i)
	{
		if(Slots[i].P != None)
			return true;
	}

	return false;
}

// Frees the slot of a player that left, a dead pawn, or a pawn its player no longer plays (a squad member was taken over during the flight)
function bool DropInvalidSlot(int i)
{
	local CoopPlayer CP;
	local Pawn P;
	local bool bPlayerThere, bPawnAlive;

	CP = Slots[i].CP;
	P = Slots[i].P;
	bPlayerThere = CP != None && !CP.bDeleteMe;
	bPawnAlive = P != None && !P.bDeleteMe && P.Health > 0;

	if(bPlayerThere && bPawnAlive && (!Slots[i].bFlying || CP.Pawn == P))
		return false;

	Log("CoopGame: space walk abort: slot=" $ i $ " freed, player=" $ CP $ " pawn=" $ P $ " alive=" $ bPawnAlive);

	if(bPawnAlive && Slots[i].bFlying)
		RestorePawn(i);

	// A dead pawn: the engine's own state change ends the client's flight
	if(bPlayerThere && Slots[i].bFlying && CP.Pawn != None && CP.Pawn != P)
		CP.ClientCoopEndSpaceWalk(CP.Pawn.Location);

	ClearSlot(i);

	return true;
}

function ClearSlot(int i)
{
	Slots[i].CP = None;
	Slots[i].P = None;
	Slots[i].bFlying = false;
}

function UpdateFlyer(int i, PlayerController Host, bool bSend, bool bLog)
{
	local Pawn P;
	local name Seq;
	local float Frame;
	local vector Target;

	P = Slots[i].P;
	Target = Host.Pawn.Location + StartOffsets[i] + (EndOffsets[i] - StartOffsets[i]) * FClamp((HostFrame - CLOSE_IN_FRAME) / CLOSE_IN_SPAN, 0.0, 1.0);

	P.SetLocation(Target);
	P.SetRotation(Host.Pawn.Rotation);
	P.Velocity = vect(0,0,0);
	P.Acceleration = vect(0,0,0);

	P.GetAnimParams('', Seq, Frame);

	// Something can put the idle pose back. Before the host starts there is nothing to be in step with
	if(bHostInAnim && Seq != FloatAnim && Game.Level.TimeSeconds >= Slots[i].NextAnim)
	{
		Slots[i].NextAnim = Game.Level.TimeSeconds + ANIM_REISSUE_INTERVAL;
		P.PlayAnim(FloatAnim, , ANIM_RATE, FClamp(HostFrame, 0.0, ANIM_END_FRAME));
		Game.SendScriptAnim(P, FloatAnim, ANIM_RATE, false);
	}

	if(bSend)
		Slots[i].CP.ClientCoopSpaceWalkPos(Target);

	if(bLog)
		Log("CoopGame: space walk flyer: slot=" $ i $ " name=" $ Slots[i].CP.PlayerReplicationInfo.PlayerName $ " loc=" $ P.Location $ " delta=" $ VSize(P.Location - Host.Pawn.Location) $ " anim=" $ Seq $ " frame=" $ Frame $ " phys=" $ P.Physics);
}

function Finish(string Reason)
{
	Log("CoopGame: space walk " $ Reason);
	bFinished = true;
	LandDeadline = Game.Level.TimeSeconds + LAND_RETRY_TIME;
	LandAll();
}

function LandAll()
{
	local bool bWaiting;
	local int i;

	NextLandTry = Game.Level.TimeSeconds + LAND_RETRY_INTERVAL;

	for(i = 0; i < MAX_FLYERS; ++i)
	{
		if(Slots[i].P == None || DropInvalidSlot(i) || LandSlot(i))
			continue;

		if(Game.Level.TimeSeconds >= LandDeadline)
			GiveUpSlot(i);
		else
			bWaiting = true;
	}

	bLanding = bWaiting;
}

function bool LandSlot(int i)
{
	local CoopPlayer CP;
	local Pawn P;
	local vector Spot;

	CP = Slots[i].CP;
	P = Slots[i].P;

	// Collision first, then SetLocation refuses a spot inside something. No physics runs before the end of this function
	SetPawnCollision(P, true);

	if(!FindLandingSpot(i, Spot))
	{
		SetPawnCollision(P, false);
		P.SetLocation(LastHostLocation + EndOffsets[i]);
		return false;
	}

	RestorePawn(i);
	CP.GotoState('PlayerWalking');
	CP.ClientCoopEndSpaceWalk(Spot);
	Log("CoopGame: space walk land: slot=" $ i $ " spot=" $ Spot);
	ClearSlot(i);

	return true;
}

// Nothing to stand on near the host (he is gone, or still far from the ship after the time limit): CoopGame.TeleportToHost brings the player later
function GiveUpSlot(int i)
{
	local CoopPlayer CP;
	local Pawn P;

	CP = Slots[i].CP;
	P = Slots[i].P;

	RestorePawn(i);
	Log("CoopGame: space walk abort: slot=" $ i $ " found no floor near " $ LastHostLocation $ ", moved to the host=" $ Game.TeleportToHost(CP));
	CP.GotoState('PlayerWalking');
	CP.ClientCoopEndSpaceWalk(P.Location);
	ClearSlot(i);
}

// The planned spot first, then the rings around the host
function bool FindLandingSpot(int i, out vector Spot)
{
	local Pawn P;
	local rotator R;
	local int Ring, Direction;

	P = Slots[i].P;

	if(TryPlace(P, LastHostLocation + EndOffsets[i], Spot))
		return true;

	for(Ring = 1; Ring <= LAND_RINGS; ++Ring)
	{
		for(Direction = 0; Direction < LAND_DIRECTIONS; ++Direction)
		{
			R.Yaw = Direction * LAND_DIRECTION_STEP;

			if(TryPlace(P, LastHostLocation + vector(R) * (Ring * LAND_RING_STEP), Spot))
				return true;
		}
	}

	return false;
}

function bool TryPlace(Pawn P, vector Test, out vector Spot)
{
	local vector HitLocation, HitNormal;

	if(!Game.FastTrace(Test, LastHostLocation))
		return false;

	if(Game.Trace(HitLocation, HitNormal, Test - vect(0,0,1) * FLOOR_TRACE_DEPTH, Test, false) == None)
		return false;

	Spot = HitLocation;
	Spot.Z += P.CollisionHeight + LAND_CLEARANCE;

	return !IsCrowded(P, Spot) && P.SetLocation(Spot);
}

function bool IsCrowded(Pawn P, vector Spot)
{
	local Pawn Other;
	local vector Delta;
	local int i;
	local bool bStillFlying;

	foreach Game.DynamicActors(class'Pawn', Other)
	{
		if(Other == P || Other.Health <= 0)
			continue;

		// The others still in the air are placed after this one
		bStillFlying = false;

		for(i = 0; i < MAX_FLYERS; ++i)
			bStillFlying = bStillFlying || (Slots[i].P == Other && Slots[i].bFlying);

		if(bStillFlying)
			continue;

		Delta = Other.Location - Spot;
		Delta.Z = 0;

		if(VSize(Delta) < LAND_MIN_SEPARATION)
			return true;
	}

	return false;
}

function SetPawnCollision(Pawn P, bool bOn)
{
	P.bCollideWorld = bOn;

	if(bOn)
		P.SetCollision(true, P.default.bBlockActors, P.default.bBlockPlayers);
	else
		P.SetCollision(false, false, false);
}

function RestorePawn(int i)
{
	local Pawn P;

	P = Slots[i].P;
	SetPawnCollision(P, true);
	P.bPhysicsAnimUpdate = true;
	P.bAlwaysRelevant = Slots[i].bWasRelevant;
	P.Velocity = vect(0,0,0);
	P.Acceleration = vect(0,0,0);
	P.SetPhysics(PHYS_Falling);
	P.ChangeAnimation();
}

function string WeaponText(Pawn P)
{
	if(P.Weapon == None)
		return "None";

	return P.Weapon.Name $ "/" $ P.Weapon.GetStateName();
}

defaultproperties
{
	FloatAnim="AFloatInTemplate"
	EndEvent="DropshipAnimProp"
	StartOffsets(0)=(X=-220.000000,Y=140.000000,Z=40.000000)
	StartOffsets(1)=(X=-220.000000,Y=-140.000000,Z=-40.000000)
	StartOffsets(2)=(X=-360.000000,Y=0.000000,Z=90.000000)
	EndOffsets(0)=(X=-87.000000,Y=48.000000,Z=0.000000)
	EndOffsets(1)=(X=-87.000000,Y=-110.000000,Z=0.000000)
	EndOffsets(2)=(X=-180.000000,Y=-30.000000,Z=0.000000)
}
