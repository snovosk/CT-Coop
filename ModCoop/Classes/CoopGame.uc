class CoopGame extends CTGameInfoSP config(ModCoop);

#exec OBJ LOAD FILE="CTGame.u"
#exec OBJ LOAD FILE="CTCharacters.u"
#exec OBJ LOAD FILE="Gameplay.u"

/*
 * CoopGame
 * Host-authoritative campaign coop on a listen server.
 * - The host plays exactly like in single player and keeps the Delta squad.
 * - Clients spawn as additional commandos next to the host, respawn there after dying and follow the host on level changes.
 * - Progress only exists on the host. The engine can't save on a listen server so the checkpoint is the beginning of the current level.
 * Uses native UE2 replication only. The single player level scripts run on the server as usual.
 */

var() config int   MaxCoopPlayers;        // Including the host
var() config float ClientRespawnDelay;    // Seconds before a dead client respawns next to the host
var() config float ClientBleedOutTime;    // Seconds an incapacitated client can wait for a revive before he bleeds out and respawns
var() config bool  bPrivateNetworksOnly;  // Only accept clients from LAN/VPN address ranges
var() config float CatchUpDistance;       // Clients further away from the host are moved to him after CatchUpDelay seconds (0 disables it)
var() config float CatchUpDelay;
var() config float HostReviveWaitTime;    // Seconds a downed host waits for a client to revive him when the whole squad is down (0 = single player behavior)
var() config float MaxSpawnWait;          // Seconds a client waits for the host to be free (see IsHostFree) before it is spawned anyway

var CoopFixes Fixes;
var int       NextCoopSkin;
var bool      bCheckedLevel;
var float     HostDownTime;       // Level.TimeSeconds when the host's bleed out was delayed, zero if not waiting
var bool      bAllowHostBleedOut;

// Developer test automation, only active with ?CoopTest=<action> in the URL (see DEVLOG.md)
var string    TestAction;
var float     TestTime;
var int       TestStep;

const GAME_CLASS = "ModCoop.CoopGame";

event InitGame(string Options, out string Error)
{
	Super.InitGame(Options, Error);

	// Clients need ModCoop to resolve CoopPlayer and CoopCommando. This normally already happened before the server started listening
	// (CoopHostMenu or CoopExtension). Adding it now only helps for the next level change.
	if(!class'CoopNative'.static.HasServerPackage("ModCoop"))
	{
		Warn("ModCoop is not a server package. Clients won't be able to join until the next level change. Start the coop server from the menu or the host batch file");
		class'CoopNative'.static.AddServerPackage("ModCoop");
	}

	// MaxPlayers is a globalconfig variable of GameInfo. It is only changed in memory and never saved here.
	MaxPlayers = Clamp(GetIntOption(Options, "MaxPlayers", MaxCoopPlayers), 1, 4);
	bPauseable = false;
	bAdminCanPause = false;

	// Drop clients that crashed or lost the connection faster than the System.ini default of 120 seconds
	class'CoopNative'.static.SetNetTimeouts(class'CoopConfig'.default.ServerTimeout, class'CoopConfig'.default.ServerTimeout);

	TestAction = ParseOption(Options, "CoopTest");
	TestTime = float(ParseOption(Options, "CoopTestDelay"));

	if(TestTime <= 0)
		TestTime = 60;

	Log("CoopGame initialized: MaxPlayers=" $ MaxPlayers $ " NetMode=" $ Level.NetMode);
}

function PostBeginPlay()
{
	local Actor A;

	Super.PostBeginPlay();
	InitFixes();
	SetTimer(1.0, true);

	if(class'CoopConfig'.default.bDebugLog)
	{
		foreach AllActors(class'Actor', A)
		{
			if((A.default.bStatic || A.default.bNoDelete) && !A.bStatic && !A.bNoDelete && A.RemoteRole != ROLE_None)
				Log("CoopDebug: Replicated actor of static class: " $ A $ " Class=" $ A.Class $ " RemoteRole=" $ A.RemoteRole $ " bAlwaysRelevant=" $ A.bAlwaysRelevant);
		}
	}
}

event PostLoadBeginPlay()
{
	Super.PostLoadBeginPlay();
	InitFixes();
	SetTimer(1.0, true);
}

function InitFixes()
{
	if(Fixes == None)
	{
		Fixes = new class'CoopFixes';
		Fixes.Init(self);
	}
}

event Destroyed()
{
	if(Fixes != None)
	{
		Fixes.Deinit();
		Fixes = None;
	}

	Super.Destroyed();
}

/*
 * Login
 */

static function bool IsPrivateAddress(string Address)
{
	local int A, B;
	local int Dot;

	Dot = InStr(Address, ".");

	if(Dot == -1)
		return false;

	A = int(Left(Address, Dot));
	Address = Mid(Address, Dot + 1);
	Dot = InStr(Address, ".");
	B = int(Left(Address, Dot));

	return A == 10 ||                          // LAN, ZeroTier
	       A == 127 ||                         // Loopback
	       (A == 172 && B >= 16 && B <= 31) || // LAN, ZeroTier
	       (A == 192 && B == 168) ||           // LAN
	       A == 25 || A == 26 ||               // Hamachi, Radmin VPN
	       (A == 100 && B >= 64 && B <= 127);  // CGNAT range used by Tailscale
}

event PreLogin(string Options, string Address, out string Error, out string FailCode)
{
	local string ClientVersion;

	Super.PreLogin(Options, Address, Error, FailCode);

	ClientVersion = ParseOption(Options, "CoopVersion");
	Log("CoopGame: Login from " $ Address $ " ModCoop version '" $ ClientVersion $ "' (host: " $ class'CoopConfig'.static.Version() $ ")" $ " Error='" $ Error $ "'");

	// Clients that connect without the option (old versions, plain 'open <ip>' or level changes) are not checked here
	if(Error == "" && ClientVersion != "" && ClientVersion != class'CoopConfig'.static.Version())
		Error = "ModCoop version mismatch: the host has " $ class'CoopConfig'.static.Version() $ ", you have " $ ClientVersion $ ". Both players need the same archive.";

	if(Error == "" && bPrivateNetworksOnly && !IsPrivateAddress(Address))
	{
		Log("CoopGame: Rejected " $ Address $ " (bPrivateNetworksOnly)");
		Error = "This coop server only accepts LAN/VPN addresses";
	}
}

event PostLogin(PlayerController NewPlayer)
{
	Super.PostLogin(NewPlayer);

	// Otherwise a second game instance on the same PC is rejected because of the duplicate CD key
	class'CoopNative'.static.ReleaseAllCDKeys();

	if(!IsHost(NewPlayer))
	{
		Log("CoopGame: Client joined: " $ NewPlayer.PlayerReplicationInfo.PlayerName);
		Broadcast(self, NewPlayer.PlayerReplicationInfo.PlayerName $ " joined the squad");
	}
}

function Logout(Controller Exiting)
{
	if(PlayerController(Exiting) != None && !IsHost(PlayerController(Exiting)))
	{
		Broadcast(self, Exiting.PlayerReplicationInfo.PlayerName $ " left the squad");

		// Remove the pawn so it doesn't stand around without a player
		if(Exiting.Pawn != None)
			Exiting.Pawn.Destroy();
	}

	Super.Logout(Exiting);
}

/*
 * Spawning
 */

function bool IsHost(Controller C)
{
	return PlayerController(C) != None && Viewport(PlayerController(C).Player) != None;
}

function PlayerController GetHost()
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(IsHost(C))
			return PlayerController(C);
	}

	return None;
}

function RestartPlayer(Controller aPlayer)
{
	local CoopPlayer CP;

	CP = CoopPlayer(aPlayer);

	if(CP == None || IsHost(CP))
	{
		Super.RestartPlayer(aPlayer);
		return;
	}

	if(CP.Pawn != None && !CP.Pawn.bDeleteMe && CP.Pawn.Health > 0)
		return; // Already alive

	if(!SpawnClient(CP))
	{
		// Try again from the timer (e.g. the host is still loading or there is no free space right now)
		Log("CoopGame: Can't spawn client " $ CP.PlayerReplicationInfo.PlayerName $ " right now, retrying");
		CP.DeadTime = Level.TimeSeconds;
	}
}

// Finds a free spot around a location from which the location is visible
function bool FindSpawnLocation(vector Center, rotator Dir, out vector OutLocation)
{
	local int Ring, i;
	local rotator R;
	local vector Test;
	local vector HitLocation, HitNormal;

	Dir.Pitch = 0;
	Dir.Roll = 0;

	for(Ring = 1; Ring <= 4; ++Ring)
	{
		for(i = 0; i < 8; ++i)
		{
			// Prefer the spots behind the host
			R = Dir;
			R.Yaw += 32768 + (i / 2) * 8192 * (1 - 2 * (i % 2));
			Test = Center + vector(R) * (Ring * 100.0);

			if(!FastTrace(Test, Center))
				continue;

			// Make sure there is ground below the spot
			if(Trace(HitLocation, HitNormal, Test - vect(0, 0, 300), Test, false) == None)
				continue;

			OutLocation = Test;
			return true;
		}
	}

	return false;
}

/*
 * False while the host is moved by a level script, e.g. riding a gunship during an intro or being interpolated during a cutscene.
 * Clients are not spawned/moved next to the host at that time since they would be left behind in mid air.
 */
function bool IsHostFree(PlayerController Host)
{
	local Pawn P;

	if(Host == None || Host.Pawn == None || Host.Pawn.bDeleteMe || Host.Pawn.Health <= 0 || Host.Pawn.bIncapacitated)
		return false;

	P = Host.Pawn;

	if(P.Physics != PHYS_Walking)
		return false;

	return P.Base == None || P.Base.bWorldGeometry || P.Base.bStatic;
}

function bool SpawnClient(CoopPlayer CP)
{
	local PlayerController Host;
	local NavigationPoint StartSpot;
	local vector SpawnLocation;
	local rotator SpawnRotation;
	local Pawn P;

	Host = GetHost();

	if(Host != None && Host.Pawn != None && !Host.Pawn.bDeleteMe)
	{
		if(CP.SpawnWaitStart == 0)
			CP.SpawnWaitStart = Level.TimeSeconds;

		// Wait until the host stands on the ground, but not forever
		if(!IsHostFree(Host) && Level.TimeSeconds - CP.SpawnWaitStart < MaxSpawnWait)
		{
			Log("CoopGame: Waiting for the host to be free before spawning a client: Physics=" $ Host.Pawn.Physics $ " Base=" $ Host.Pawn.Base $ " Health=" $ Host.Pawn.Health);
			return false;
		}
		SpawnRotation = Host.Pawn.Rotation;

		if(FindSpawnLocation(Host.Pawn.Location, SpawnRotation, SpawnLocation))
			P = Spawn(class'CoopCommando',,, SpawnLocation, SpawnRotation);
	}

	if(P == None) // Fall back to the player starts
	{
		StartSpot = FindPlayerStart(CP, 1);

		if(StartSpot != None && FindSpawnLocation(StartSpot.Location, StartSpot.Rotation, SpawnLocation))
			P = Spawn(class'CoopCommando',,, SpawnLocation, StartSpot.Rotation);
	}

	if(P == None)
		return false;

	SpawnRotation = P.Rotation;
	SpawnRotation.Pitch = 0;
	SpawnRotation.Roll = 0;

	P.SetTeamIndex(1); // Player friendly team
	CP.Possess(P);
	CP.PawnClass = P.Class;
	CP.ClientSetRotation(SpawnRotation);
	SetPlayerDefaults(P);
	P.AddDefaultInventory();

	if(CoopCommando(P).CoopSkin == 0)
	{
		NextCoopSkin = NextCoopSkin % 4 + 1;
		CoopCommando(P).SetCoopSkin(NextCoopSkin);
	}

	CP.IncapacitatedTime = 0;
	CP.DeadTime = 0;
	CP.SpawnWaitStart = 0;

	Log("CoopGame: Spawned " $ CP.PlayerReplicationInfo.PlayerName $ " at " $ P.Location);

	return true;
}

/*
 * Periodic server side bookkeeping
 */

function Timer()
{
	local Controller C;
	local CoopPlayer CP;

	InitFixes();
	CleanUpOrphans();

	if(!bCheckedLevel)
		CheckLevel();

	if(HostDownTime != 0)
		CheckHostDown();

	if(TestAction != "")
		TickTest();

	if(class'CoopConfig'.default.bDebugLog)
		LogPawns();

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || IsHost(CP))
			continue;

		if(CP.Pawn == None || CP.Pawn.bDeleteMe || (CP.Pawn.Health <= 0 && !CP.Pawn.bIncapacitated))
		{
			// Dead: respawn after a short delay
			if(CP.DeadTime == 0)
				CP.DeadTime = Level.TimeSeconds;
			else if(Level.TimeSeconds - CP.DeadTime >= ClientRespawnDelay)
				RestartPlayer(CP);
		}
		else if(CP.Pawn.bIncapacitated)
		{
			// Incapacitated: the squad doesn't revive clients so they bleed out after a while unless another player revives them
			if(CP.IncapacitatedTime == 0)
			{
				CP.IncapacitatedTime = Level.TimeSeconds;
				CP.ClientCoopMessage("You are down! Wait for another player to revive you.");
			}
			else if(!CP.Pawn.bBeingRevivedByPlayer && Level.TimeSeconds - CP.IncapacitatedTime >= ClientBleedOutTime)
			{
				CP.IncapacitatedTime = 0;
				CP.Pawn.BleedOut();
			}
		}
		else
		{
			CP.IncapacitatedTime = 0;
			CP.DeadTime = 0;
			CheckCatchUp(CP);
		}
	}
}

function bool HasLivingClient()
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.nextController)
	{
		if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated)
			return true;
	}

	return false;
}

// Called from CoopFixes when a pawn is about to bleed out
function bool ShouldDelayHostBleedOut(Pawn P)
{
	local PlayerController Host;

	Host = GetHost();

	if(bAllowHostBleedOut || HostReviveWaitTime <= 0 || Host == None || P != Host.Pawn || !P.bIncapacitated || !HasLivingClient())
		return false;

	if(HostDownTime == 0)
	{
		HostDownTime = Level.TimeSeconds;
		Log("CoopGame: Host is down, waiting for a client to revive him");
		Broadcast(self, "The host is down! Revive him: look at him and hold USE.");
	}

	return Level.TimeSeconds - HostDownTime < HostReviveWaitTime;
}

function CheckHostDown()
{
	local PlayerController Host;

	Host = GetHost();

	if(Host == None || Host.Pawn == None || !Host.Pawn.bIncapacitated)
	{
		HostDownTime = 0; // Revived
		return;
	}

	if(!HasLivingClient() || Level.TimeSeconds - HostDownTime >= HostReviveWaitTime)
	{
		Log("CoopGame: Nobody revived the host");
		HostDownTime = 0;
		bAllowHostBleedOut = true;
		Host.Pawn.BleedOut();
		bAllowHostBleedOut = false;
	}
}

// Leaves levels that can't be played in coop (see SkipBriefing)
function CheckLevel()
{
	local PlayerController Host;
	local string Map;

	Host = GetHost();

	if(Host == None)
		return;

	bCheckedLevel = true;
	Host.GetCurrentMapName(Map);

	if(SkipBriefing(Map) != Map)
		CoopTravel(Map);
}

// Moves a client that got separated from the host (usually by a level script that only moves the host) next to the host
function CheckCatchUp(CoopPlayer CP)
{
	local PlayerController Host;

	if(CatchUpDistance <= 0)
		return;

	Host = GetHost();

	if(!IsHostFree(Host) || VSize(CP.Pawn.Location - Host.Pawn.Location) < CatchUpDistance)
	{
		CP.FarFromHostTime = 0;
		return;
	}

	if(CP.FarFromHostTime == 0)
	{
		CP.FarFromHostTime = Level.TimeSeconds;
		return;
	}

	if(Level.TimeSeconds - CP.FarFromHostTime >= CatchUpDelay)
	{
		CP.FarFromHostTime = 0;

		if(TeleportToHost(CP))
			CP.ClientCoopMessage("You were moved to the host because you got separated.");
	}
}

function bool TeleportToHost(CoopPlayer CP)
{
	local PlayerController Host;
	local vector NewLocation;
	local rotator NewRotation;

	Host = GetHost();

	if(CP.Pawn == None || CP.Pawn.bIncapacitated || !IsHostFree(Host))
		return false;

	NewRotation = Host.Pawn.Rotation;
	NewRotation.Pitch = 0;
	NewRotation.Roll = 0;

	if(!FindSpawnLocation(Host.Pawn.Location, NewRotation, NewLocation) || !CP.Pawn.SetLocation(NewLocation))
		return false;

	CP.Pawn.Velocity = vect(0,0,0);
	CP.Pawn.SetPhysics(PHYS_Falling);
	CP.ClientSetLocation(NewLocation, NewRotation);
	Log("CoopGame: Moved " $ CP.PlayerReplicationInfo.PlayerName $ " to the host");

	return true;
}

function LogPawns()
{
	local Pawn P;
	local int Num;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P.Health > 0)
			++Num;

		if(P.IsHumanControlled() || P.Squad != None)
			Log("CoopDebug: Server " $ P.Class.Name $ " " $ P.Location $ " Health=" $ P.Health $ " Incap=" $ P.bIncapacitated);
	}

	Log("CoopDebug: Server living pawns=" $ Num);
}

// Developer test automation. The timer runs once per second.
function TickTest()
{
	local PlayerController Host;
	local Controller C;
	local string NextMap;
	local rotator R;

	if(Level.TimeSeconds < TestTime)
		return;

	Host = GetHost();
	Log("CoopTest: Executing step " $ TestStep $ " of '" $ TestAction $ "'");

	if(TestAction ~= "travel" && TestStep == 0)
	{
		Host.GetCurrentMapName(NextMap);
		Host.GetNextLevel(Host.GetLevelIndex(NextMap), NextMap);
		CoopTravel(NextMap);
	}
	else if(TestAction ~= "restart" && TestStep == 0)
	{
		CoopRestartLevel();
	}
	else if(TestAction ~= "checkpoint")
	{
		if(TestStep == 0)
		{
			Log("CoopTest: Host reloads the checkpoint");
			Host.Reload();
		}
	}
	else if(TestAction ~= "clientdeath" && TestStep == 0)
	{
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				Log("CoopTest: Killing " $ C.PlayerReplicationInfo.PlayerName);
				C.Pawn.Died(None, class'DamageBleedOut', C.Pawn.Location);
			}
		}
	}
	else if(TestAction ~= "revive")
	{
		// Checks that the host can revive an incapacitated client: 0 = move client to host, 1 = incapacitate, 2 = look at client and press use, 3 = check
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
				break;
		}

		if(C == None || Host == None || Host.Pawn == None)
		{
			Log("CoopTest: revive: no client or host pawn");
			TestAction = "";
			return;
		}

		if(TestStep == 0)
		{
			TeleportToHost(CoopPlayer(C));
		}
		else if(TestStep == 1)
		{
			Log("CoopTest: Incapacitating " $ C.PlayerReplicationInfo.PlayerName $ " Distance=" $ VSize(C.Pawn.Location - Host.Pawn.Location));
			C.Pawn.TakeDamage(1000, None, C.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
		}
		else if(TestStep == 2)
		{
			Host.SetRotation(rotator(C.Pawn.Location - vect(0,0,60) - (Host.Pawn.Location + Host.Pawn.EyePosition())));
			Log("CoopTest: Client incapacitated=" $ C.Pawn.bIncapacitated $ " Host TargetType=" $ Host.TargetType $ " Target=" $ Host.Target);
			Host.Use();
		}
		else if(TestStep < 15)
		{
			Host.SetRotation(rotator(C.Pawn.Location - vect(0,0,60) - (Host.Pawn.Location + Host.Pawn.EyePosition())));
			Log("CoopTest: Reviving: Host state=" $ Host.GetStateName() $ " TargetType=" $ Host.TargetType $ " Client incapacitated=" $ C.Pawn.bIncapacitated);
			Host.bUse = true; // Simulate holding the use key

			if(!Host.IsInState('UsingItem'))
				Host.Use();

			if(!C.Pawn.bIncapacitated)
			{
				Log("CoopTest: revive SUCCEEDED");
				Host.StopUse();
				TestAction = "";
			}
		}
		else
		{
			Log("CoopTest: revive FAILED");
			Host.StopUse();
			TestAction = "";
		}

		TestTime = Level.TimeSeconds + 1;
		++TestStep;
		return;
	}
	else if(TestAction ~= "jump")
	{
		// Clients jump in front of the host so the animation of a remote player can be watched in the host's window
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				if(TestStep == 0)
				{
					// In front of the host, far enough to see the whole model
					R = Host.Pawn.Rotation;
					R.Pitch = 0;
					C.Pawn.SetLocation(Host.Pawn.Location + vector(R) * 400);
					C.Pawn.SetPhysics(PHYS_Falling);
				}

				Host.SetRotation(rotator(C.Pawn.Location - (Host.Pawn.Location + Host.Pawn.EyePosition())));

				if(TestStep > 0 && C.Pawn.Physics == PHYS_Walking)
				{
					Log("CoopTest: Jump " $ C.Pawn);
					C.Pawn.DoJump(false);
				}
			}
		}

		if(TestStep < 8)
		{
			TestTime = Level.TimeSeconds + 2;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "hostjump")
	{
		// The host jumps in front of a client so the animation of a simulated proxy can be watched in the client's window
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				if(TestStep == 0)
				{
					// Same spot as in the jump test which is known to be free
					R = Host.Pawn.Rotation;
					R.Pitch = 0;
					C.Pawn.SetLocation(Host.Pawn.Location + vector(R) * 400);
					C.Pawn.SetPhysics(PHYS_Falling);
				}

				R = rotator(Host.Pawn.Location - C.Pawn.Location);
				R.Pitch = 0;
				C.ClientSetRotation(R);

				if(TestStep > 0 && Host.Pawn.Physics == PHYS_Walking)
				{
					Log("CoopTest: Jump " $ Host.Pawn);
					Host.Pawn.DoJump(false);
				}

				break;
			}
		}

		if(TestStep < 8)
		{
			TestTime = Level.TimeSeconds + 2;
			++TestStep;
			return;
		}
	}
	else if(TestAction ~= "hostdown")
	{
		// Simulates the whole squad being down: the host is incapacitated and the game tries to make him bleed out
		if(TestStep == 0)
		{
			Host.Pawn.TakeDamage(1000, None, Host.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
			TestTime = Level.TimeSeconds + 3;
			++TestStep;
			return;
		}
		else if(TestStep == 1)
		{
			Log("CoopTest: Host incapacitated=" $ Host.Pawn.bIncapacitated $ ", calling BleedOut");
			Host.Pawn.BleedOut();
			Log("CoopTest: After BleedOut: Host health=" $ Host.Pawn.Health $ " incapacitated=" $ Host.Pawn.bIncapacitated);
		}
	}
	else if(TestAction ~= "clientincap" && TestStep == 0)
	{
		for(C = Level.ControllerList; C != None; C = C.nextController)
		{
			if(CoopPlayer(C) != None && !IsHost(C) && C.Pawn != None)
			{
				Log("CoopTest: Incapacitating " $ C.PlayerReplicationInfo.PlayerName);
				C.Pawn.TakeDamage(1000, None, C.Pawn.Location, vect(0,0,0), class'CTDamageBallistic');
			}
		}
	}

	TestAction = "";
}

// After loading a save game the controllers and pawns of the clients from the time of saving still exist but have no connection anymore
function CleanUpOrphans()
{
	local Controller C, Next;
	local CoopCommando P;

	for(C = Level.ControllerList; C != None; C = Next)
	{
		Next = C.nextController;

		if(CoopPlayer(C) != None && PlayerController(C).Player == None)
		{
			Log("CoopGame: Removing orphaned client controller " $ C);

			if(C.Pawn != None)
				C.Pawn.Destroy();

			C.Destroy();
		}
	}

	foreach DynamicActors(class'CoopCommando', P)
	{
		if(P.Controller == None && !P.bIncapacitated && P.Health > 0)
		{
			Log("CoopGame: Removing orphaned client pawn " $ P);
			P.Destroy();
		}
	}
}

/*
 * Travel
 * All level changes must use server travel so that the clients follow the host.
 */

function string MakeCoopURL(string URL)
{
	if(InStr(Caps(URL), "?GAME=") == -1)
		URL = URL $ "?game=" $ GAME_CLASS;

	if(InStr(Caps(URL), "?LISTEN") == -1)
		URL = URL $ "?listen";

	if(InStr(Caps(URL), "?MAXPLAYERS=") == -1)
		URL = URL $ "?MaxPlayers=" $ MaxPlayers;

	return URL;
}

// Prepares the host's pawn for travel the same way the single player level change does
function PrepareHostForTravel()
{
	local PlayerController Host;
	local PlayerCommando P;

	Host = GetHost();

	if(Host == None)
		return;

	P = PlayerCommando(Host.Pawn);

	if(P == None)
		return;

	if(P.Squad != None)
		P.SaveSquadTravelInfo();

	// PlayerCommando.TravelPostAccept sets this stance on the squad of the next level. It is None if there was no squad in the current level.
	if(P.CurrentStance == None)
		P.CurrentStance = class'StanceFormUp';
}

/*
 * Briefing levels crash network clients while the level starts (the process exits during BeginPlay without an error message).
 * They don't contain gameplay so coop skips them and goes to the next level of the campaign.
 */
function string SkipBriefing(string URL)
{
	local PlayerController Host;
	local string Map, Options, NextMap;
	local int i;

	Map = URL;
	i = InStr(Map, "?");

	if(i != -1)
	{
		Options = Mid(Map, i);
		Map = Left(Map, i);
	}

	if(InStr(Caps(Map), "BRIEFING") == -1)
		return URL;

	Host = GetHost();

	if(Host == None)
		return URL;

	Host.GetNextLevel(Host.GetLevelIndex(Map), NextMap);

	if(NextMap == "" || Host.GetLevelIndex(NextMap) == -1)
		return URL;

	Log("CoopGame: Skipping briefing " $ Map $ " -> " $ NextMap);

	return NextMap $ Options;
}

function CoopTravel(string URL)
{
	URL = SkipBriefing(URL);
	PrepareHostForTravel();
	Log("CoopGame: Traveling to " $ URL);
	Level.ServerTravel(MakeCoopURL(URL), true);
}

// Coop "checkpoint": restarts the current level for everybody (see CoopPlayer.AutoSave)
function CoopRestartLevel()
{
	local PlayerController Host;
	local string Map;

	Host = GetHost();

	if(Host != None)
		Host.GetCurrentMapName(Map);

	if(Map == "")
	{
		Log("CoopGame: Restarting level");
		Level.ServerTravel("?restart", false);
		return;
	}

	Broadcast(self, "Restarting the level...");
	Log("CoopGame: Restarting level " $ Map);
	Level.ServerTravel(MakeCoopURL(Map), false);
}

/*
 * Same as GameInfo.ProcessServerTravel but clients never travel with their items. Their pawns get the default inventory on the new
 * level anyway and a client without a pawn (e.g. still waiting to spawn) crashes while exporting its travel items.
 */
function ProcessServerTravel(string URL, bool bItems)
{
	local PlayerController P, LocalPlayer;
	local string ClientURL, S;

	ClientURL = ExpandRelativeURL(URL);
	ClientURL = ClientURL $ ConsoleCommand("XLIVE CLIENT_TRAVEL");

	BaseMutator.ServerTraveling(ClientURL, bItems);
	EndLogging("mapchange");
	Log("CoopGame: ProcessServerTravel: " $ ClientURL);

	foreach DynamicActors(class'PlayerController', P)
	{
		if(NetConnection(P.Player) != None)
		{
			S = ClientURL;

			if(P.PlayerReplicationInfo != None && P.PlayerReplicationInfo.Team != None)
				S = S $ "?Team=" $ P.PlayerReplicationInfo.Team.TeamIndex;

			P.ClientTravel(S, TRAVEL_Relative, false);
		}
		else
		{
			LocalPlayer = P;
			P.PreClientTravel();
		}
	}

	if(Level.NetMode == NM_ListenServer && LocalPlayer != None)
	{
		Level.NextURL = Level.NextURL
		              $ "?Team=" $ LocalPlayer.GetDefaultURL("Team")
		              $ "?Name=" $ LocalPlayer.GetDefaultURL("Name")
		              $ "?Class=" $ LocalPlayer.GetDefaultURL("Class")
		              $ "?Character=" $ LocalPlayer.GetDefaultURL("Character");
	}
}

function SendPlayer(PlayerController aPlayer, string URL)
{
	CoopTravel(URL);
}

defaultproperties
{
	MaxCoopPlayers=4
	ClientRespawnDelay=5.0
	ClientBleedOutTime=45.0
	CatchUpDistance=4000.0
	CatchUpDelay=15.0
	MaxSpawnWait=30.0
	HostReviveWaitTime=60.0
	bPrivateNetworksOnly=False
	PlayerControllerClassName="ModCoop.CoopPlayer"
	GameName="Republic Commando Coop"
}
