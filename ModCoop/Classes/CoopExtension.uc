class CoopExtension extends SWRCFixExtension;

#exec OBJ LOAD FILE="XInterface.u"
#exec OBJ LOAD FILE="XInterfaceCommon.u"

/*
 * CoopExtension
 * Loaded by SWRCFix at startup on every machine that has ModCoop installed.
 * - Adds the coop entries to the multiplayer menu
 * - Automatically reconnects to the coop host when the connection is lost (e.g. when the host loads a checkpoint)
 */

var FunctionOverride ConnectionFailedInitOverride;
var FunctionOverride DisconnectOnYesOverride;
var FunctionOverride PlayJumpOverride;
var FunctionOverride PlayFallingOverride;
var FunctionOverride GunshipPostBeginPlayOverride;
var FunctionOverride HasRequiredInventoryOverride;
var FunctionOverride ObjectiveTrackerOverride;  // HUD changes of level scripts for the clients (see CoopGame.ForwardObjectiveTracker)
var FunctionOverride BlinkSquadOverride;
var FunctionOverride BlinkSquadCommandPromptOverride;
var FunctionOverride BlinkGrenadeOverride;
var FunctionOverride BlinkHealthOverride;
var FunctionOverride BlinkShieldsOverride;
var FunctionOverride ShakeViewOverride;
var FunctionOverride ScreenFadeOverride;
var FunctionOverride ObjectiveUpdateOverride;
var FunctionOverride CriticalMessageOverride;
var FunctionOverride ActivateItemTransitionOverride; // Effects for the clients (see CoopGame.ForwardEffect)
var FunctionOverride DispenserTransitionOverride;
var FunctionOverride FactoryRangeTestOverride;     // Players without a pawn (see FactoryPlayerRangeTest)
var FunctionOverride FactoryCovertOverride;
var FunctionOverride FactoryGenerateOverride;

function Init(SWRCFix Fix)
{
	Log("ModCoop version " $ class'CoopConfig'.static.Version());
	class'CoopNative'.static.InstallClientFixes();
	class'CoopNative'.static.LoadSavedConfig(class'CoopConfig', "ModCoop.ini");
	class'CoopConfig'.static.LoadLists();
	class'CoopNative'.static.LoadSavedConfig(class'CoopGame', "ModCoop.ini");

	// Coop server started from the command line (e.g. the host batch file). The package must be added before the server starts listening.
	if(InStr(Caps(class'CoopNative'.static.GetCommandLine()), "MODCOOP.COOPGAME") != -1)
		class'CoopNative'.static.AddServerPackage("ModCoop");

	ConnectionFailedInitOverride = new class'FunctionOverride';
	ConnectionFailedInitOverride.Init(class'MenuConnectionFailed', 'Init', self, 'ConnectionFailedInit');

	DisconnectOnYesOverride = new class'FunctionOverride';
	DisconnectOnYesOverride.Init(class'MenuDisconnect', 'OnYes', self, 'DisconnectOnYes');

	PlayJumpOverride = new class'FunctionOverride';
	PlayJumpOverride.Init(class'Pawn', 'PlayJump', self, 'PawnPlayJump');

	PlayFallingOverride = new class'FunctionOverride';
	PlayFallingOverride.Init(class'Pawn', 'PlayFalling', self, 'PawnPlayFalling');

	GunshipPostBeginPlayOverride = new class'FunctionOverride';
	GunshipPostBeginPlayOverride.Init(class'Gunship', 'PostBeginPlay', self, 'GunshipPostBeginPlay');

	HasRequiredInventoryOverride = new class'FunctionOverride';
	HasRequiredInventoryOverride.Init(class'ActivateItem', 'HasRequiredInventory', self, 'ActivateItemHasRequiredInventory');

	ObjectiveTrackerOverride = new class'FunctionOverride';
	ObjectiveTrackerOverride.Init(class'ACTION_ShowActorObjectiveTracker', 'InitActionFor', self, 'ObjectiveTrackerInitActionFor');
	BlinkSquadOverride = new class'FunctionOverride';
	BlinkSquadOverride.Init(class'ACTION_BlinkHUDSquad', 'InitActionFor', self, 'BlinkSquadInitActionFor');
	BlinkSquadCommandPromptOverride = new class'FunctionOverride';
	BlinkSquadCommandPromptOverride.Init(class'ACTION_BlinkHUDSquadCommandPrompt', 'InitActionFor', self, 'BlinkSquadCommandPromptInitActionFor');
	BlinkGrenadeOverride = new class'FunctionOverride';
	BlinkGrenadeOverride.Init(class'ACTION_BlinkHUDGrenade', 'InitActionFor', self, 'BlinkGrenadeInitActionFor');
	BlinkHealthOverride = new class'FunctionOverride';
	BlinkHealthOverride.Init(class'ACTION_BlinkHUDHealth', 'InitActionFor', self, 'BlinkHealthInitActionFor');
	BlinkShieldsOverride = new class'FunctionOverride';
	BlinkShieldsOverride.Init(class'ACTION_BlinkHUDShields', 'InitActionFor', self, 'BlinkShieldsInitActionFor');
	ShakeViewOverride = new class'FunctionOverride';
	ShakeViewOverride.Init(class'ACTION_ShakeView', 'InitActionFor', self, 'ShakeViewInitActionFor');
	ScreenFadeOverride = new class'FunctionOverride';
	ScreenFadeOverride.Init(class'ACTION_ScreenFade', 'InitActionFor', self, 'ScreenFadeInitActionFor');
	ObjectiveUpdateOverride = new class'FunctionOverride';
	ObjectiveUpdateOverride.Init(class'ACTION_ObjectiveUpdate', 'InitActionFor', self, 'ObjectiveUpdateInitActionFor');
	CriticalMessageOverride = new class'FunctionOverride';
	CriticalMessageOverride.Init(class'ACTION_DisplayCriticalMessage', 'InitActionFor', self, 'CriticalMessageInitActionFor');
	ActivateItemTransitionOverride = new class'FunctionOverride';
	ActivateItemTransitionOverride.Init(class'ActivateItem', 'MakeTransition', self, 'ActivateItemMakeTransition');
	DispenserTransitionOverride = new class'FunctionOverride';
	DispenserTransitionOverride.Init(class'DroidDispenser', 'MakeTransition', self, 'DispenserMakeTransition');
	FactoryRangeTestOverride = new class'FunctionOverride';
	FactoryRangeTestOverride.Init(class'Factory', 'PlayerRangeTest', self, 'FactoryPlayerRangeTest');
	FactoryCovertOverride = new class'FunctionOverride';
	FactoryCovertOverride.Init(class'Factory', 'IsLocationCovert', self, 'FactoryIsLocationCovert');
	FactoryGenerateOverride = new class'FunctionOverride';
	FactoryGenerateOverride.Init(class'Factory', 'GenerateActor', self, 'FactoryGenerateActor');
}

/*
 * Jump animations of other players.
 * Pawn.PlayJump does nothing and the native animation code of the single player commando keeps the standing pose while falling:
 * a jumping player was seen frozen upright in the air by everyone else. In single player you never see yourself from the outside
 * so it didn't matter. The commando mesh has the Jump and FallBreathe animations, they are played for players that are not
 * controlled locally. Called on the server for clients' pawns and on clients for simulated proxies.
 */
simulated function bool UseMPJumpAnims(Pawn P)
{
	return PlayerCommando(P) != None && P.Level.NetMode != NM_Standalone && !P.IsLocallyControlled() && P.HasAnim('Jump');
}

simulated function PawnPlayJump()
{
	local Pawn P;

	P = Pawn(PlayJumpOverride.CurrentSelf);

	// Pawn.PlayJump itself does nothing
	if(UseMPJumpAnims(P))
		P.PlayAnim('Jump', , , , 3);
}

simulated function PawnPlayFalling()
{
	local Pawn P;

	P = Pawn(PlayFallingOverride.CurrentSelf);

	if(UseMPJumpAnims(P))
	{
		if(P.HasAnim('FallBreathe'))
			P.LoopAnim('FallBreathe');
		else if(!P.IsPlayingAnim('Jump'))
			P.PlayAnim('Jump', , , , 3);

		return;
	}

	// Same as Pawn.PlayFalling (calling it here would run overrides of subclasses twice)
	if(P.HasAnim('FallBreathe'))
		P.LoopAnim('FallBreathe');
	else
		P.PlayBreathe();
}

/*
 * Gunship.PostBeginPlay is simulated and spawns the ball turrets on network clients as well. These local copies are not the
 * server's turrets: they get their own AI controller, are left behind when the gunship is destroyed, fall out of the world and
 * die on the client without a GameInfo. Players on GEO_03D crashed in CTPlayer.PlayerTick (target selection) afterwards.
 * The turrets of the server are replicated so the local copies are removed right away.
 */
simulated function GunshipPostBeginPlay()
{
	local Gunship G;

	G = Gunship(GunshipPostBeginPlayOverride.CurrentSelf);
	G.PostBeginPlay(); // Calls the original function

	if(G.Level.NetMode != NM_Client)
		return;

	DestroyLocalTurret(G.LeftTurret);
	DestroyLocalTurret(G.RightTurret);
	G.LeftTurret = None;
	G.RightTurret = None;
}

simulated function DestroyLocalTurret(Pawn Turret)
{
	if(Turret == None || Turret.Role != ROLE_Authority)
		return;

	if(Turret.Controller != None)
		Turret.Controller.Destroy();

	Turret.Destroy();
}

/*
 * The target selection of the player (native CTPlayer.SelectTargetType) asks a panel whether the player has the required inventory.
 * ActivateItem.HasRequiredInventory is not simulated: on clients, where panels are proxies, it was not executed and returned false,
 * so clients could never target a panel (bacta dispensers, hacking, explosives). Same code, but simulated.
 */
simulated function bool ActivateItemHasRequiredInventory(Pawn P)
{
	local ActivateItem Item;
	local Ammunition AmmoType;

	Item = ActivateItem(HasRequiredInventoryOverride.CurrentSelf);

	if(Item.AmmunitionRequired == None)
		return true;

	if(P == None)
		return false;

	AmmoType = Ammunition(P.FindInventoryType(Item.AmmunitionRequired));

	return AmmoType != None && AmmoType.AmmoAmount > 0;
}

function string RedirectMenuClass(string MenuClassName)
{
	if(MenuClassName ~= "XInterfaceCTMenus.CTMultiplayerPCMenu")
		return "ModCoop.CoopMultiplayerMenu";

	return MenuClassName;
}

// The engine opens MenuConnectionFailed when the connection to the server is lost or could not be established
simulated function ConnectionFailedInit(string Args)
{
	local MenuConnectionFailed Menu;

	Menu = MenuConnectionFailed(ConnectionFailedInitOverride.CurrentSelf);
	Menu.Init(Args);

	if(class'CoopConfig'.default.ReconnectAddress == "")
		return;

	// Errors that won't go away by retrying
	if(InStr(Args, "BadCDKey") != -1 || InStr(Args, "MissingContent") != -1 || InStr(Args, "__SERVERFULL__") != -1 ||
	   Menu.GetPlayerOwner().bBadCDKey || Menu.GetPlayerOwner().bMissingContent)
	{
		class'CoopConfig'.static.EndSession();
		return;
	}

	if(class'CoopConfig'.default.ReconnectAttempts >= class'CoopConfig'.default.MaxReconnectAttempts)
	{
		Log("ModCoop: Giving up reconnecting to " $ class'CoopConfig'.default.ReconnectAddress);
		class'CoopConfig'.static.EndSession();
		return;
	}

	Menu.GotoMenuClass("ModCoop.CoopReconnectMenu", Args);
}

// The player chose to leave the game. Don't reconnect.
simulated function DisconnectOnYes()
{
	class'CoopConfig'.static.EndSession();
	MenuDisconnect(DisconnectOnYesOverride.CurrentSelf).OnYes();
}

/*
 * Level scripts change the HUD of the first player they find (the host): objective tracker, blinking HUD elements, view shakes and
 * screen fades. Critical messages (objectives) only reach players with a HUD on the server. The original runs, then it is forwarded
 * to the clients (CoopPlayer.ClientCoop...).
 */
function bool ObjectiveTrackerInitActionFor(ScriptedController C)
{
	local ACTION_ShowActorObjectiveTracker Action;
	local Actor A, Found;
	local bool bResult;

	Action = ACTION_ShowActorObjectiveTracker(ObjectiveTrackerOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
	{
		if(Action.ActorTag != 'None')
		{
			foreach C.AllActors(class'Actor', A, Action.ActorTag)
			{
				Found = A;
				break;
			}
		}

		CoopGame(C.Level.Game).ForwardObjectiveTracker(Found, Found != None);
	}

	return bResult;
}

function bool BlinkSquadInitActionFor(ScriptedController C)
{
	local ACTION_BlinkHUDSquad Action;
	local bool bResult;

	Action = ACTION_BlinkHUDSquad(BlinkSquadOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardBlinkHUD(0, Action.BlinkTime);

	return bResult;
}

function bool BlinkSquadCommandPromptInitActionFor(ScriptedController C)
{
	local ACTION_BlinkHUDSquadCommandPrompt Action;
	local bool bResult;

	Action = ACTION_BlinkHUDSquadCommandPrompt(BlinkSquadCommandPromptOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardBlinkHUD(1, Action.BlinkTime);

	return bResult;
}

function bool BlinkGrenadeInitActionFor(ScriptedController C)
{
	local ACTION_BlinkHUDGrenade Action;
	local bool bResult;

	Action = ACTION_BlinkHUDGrenade(BlinkGrenadeOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardBlinkHUD(2, Action.BlinkTime);

	return bResult;
}

function bool BlinkHealthInitActionFor(ScriptedController C)
{
	local ACTION_BlinkHUDHealth Action;
	local bool bResult;

	Action = ACTION_BlinkHUDHealth(BlinkHealthOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardBlinkHUD(3, Action.BlinkTime);

	return bResult;
}

function bool BlinkShieldsInitActionFor(ScriptedController C)
{
	local ACTION_BlinkHUDShields Action;
	local bool bResult;

	Action = ACTION_BlinkHUDShields(BlinkShieldsOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardBlinkHUD(4, Action.BlinkTime);

	return bResult;
}

function bool ShakeViewInitActionFor(ScriptedController C)
{
	local ACTION_ShakeView Action;
	local bool bResult;

	Action = ACTION_ShakeView(ShakeViewOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardShakeView(Action.InTime, Action.SustainTime, Action.OutTime, Action.ShakeTranslationMag, Action.ShakeRotationMag, Action.Frequency);

	return bResult;
}

function bool ScreenFadeInitActionFor(ScriptedController C)
{
	local ACTION_ScreenFade Action;
	local bool bResult;

	Action = ACTION_ScreenFade(ScreenFadeOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardScreenFade(Action.FadeTime, Action.FadeColor);

	return bResult;
}

/*
 * Doors, panels and charges (ActivateItem) and droid dispensers spawn the effects of their state changes (e.g. a breached door
 * exploding) on the server only, emitters aren't replicated.
 */
function ActivateItemMakeTransition(ActivateItem.ActivationInfo Info)
{
	local ActivateItem Item;

	Item = ActivateItem(ActivateItemTransitionOverride.CurrentSelf);
	Item.MakeTransition(Info);

	if(Info.TransitionEffect != None && CoopGame(Item.Level.Game) != None)
		CoopGame(Item.Level.Game).ForwardEffect(Info.TransitionEffect, Item.Location + Info.TransitionEffectOffset, Item.Rotation, None);
}

function DispenserMakeTransition(DroidDispenser.TransitionInfo Info)
{
	local DroidDispenser D;

	D = DroidDispenser(DispenserTransitionOverride.CurrentSelf);
	D.MakeTransition(Info);

	if(Info.TransitionEffect != None && CoopGame(D.Level.Game) != None)
		CoopGame(D.Level.Game).ForwardEffect(Info.TransitionEffect, D.Location + Info.TransitionEffectOffset, D.Rotation, D);
}

/*
 * Enemy factories check every player controller's pawn: players without one (joining, waiting to spawn, dead) were taken as
 * standing at the origin of the map. Same code, players without a pawn are skipped.
 */
function bool FactoryPlayerRangeTest(vector Location)
{
	local Factory F;
	local PlayerController P;
	local float MaxSq, MinSq, PlayDist;

	F = Factory(FactoryRangeTestOverride.CurrentSelf);

	if(F.MinPlayerRange >= F.MaxPlayerRange)
		return true;

	MaxSq = F.MaxPlayerRange * F.MaxPlayerRange;
	MinSq = F.MinPlayerRange * F.MinPlayerRange;

	foreach F.DynamicActors(class'PlayerController', P)
	{
		if(P.Pawn == None)
			continue;

		PlayDist = VSize(P.Pawn.Location - Location);
		PlayDist = PlayDist * PlayDist;

		if(PlayDist >= MinSq && PlayDist <= MaxSq)
			return true;
	}

	return false;
}

function bool FactoryIsLocationCovert(vector LocationToTest)
{
	local Factory F;
	local PlayerController P;
	local vector HitLocation, HitNormal, PlayerEyePosition;
	local Actor HitActor;

	F = Factory(FactoryCovertOverride.CurrentSelf);

	foreach F.DynamicActors(class'PlayerController', P)
	{
		if(P.Pawn == None)
			continue;

		PlayerEyePosition = P.Pawn.Location + P.Pawn.EyePosition();

		if((vector(P.Rotation) dot Normal(LocationToTest - PlayerEyePosition)) > Cos(P.FOVAngle * 0.5 * 0.01745))
		{
			HitActor = F.Trace(HitLocation, HitNormal, PlayerEyePosition, LocationToTest, false);

			if(HitActor == None || HitActor == P.Pawn)
				return false;
		}
	}

	return true;
}

// Factory.GenerateActor with SPM_NearPlayer: same code, players without a pawn are skipped (see FactoryPlayerRangeTest)
function bool FactoryGenerateActor()
{
	local Factory F;
	local PlayerController P;
	local int i;
	local int NearestSpawn;
	local bool bSpawnOK;
	local float DistToPlayer, TempDist;
	local int NumInWorld;
	local Actor Other;

	F = Factory(FactoryGenerateOverride.CurrentSelf);
	F.RemoveDeadActor();

	if(F.SpawnedActors.Length < F.MaxAlive && (F.RemainingItems > 0 || F.bGenerateForever))
	{
		if(F.MaxInWorld > 0)
		{
			NumInWorld = 0;

			foreach F.DynamicActors(F.InternalPrototype, Other)
			{
				if(!Other.IsA('Pawn') || Pawn(Other).Health > 0)
					++NumInWorld;
			}

			if(NumInWorld >= F.MaxInWorld)
				return false;
		}

		F.SpawnedActors.Insert(0, 1);

		if(F.SpawnMode == SPM_FromFactory)
		{
			if(F.PlayerRangeTest(F.Location))
			{
				if(!F.bCovert || F.IsLocationCovert(F.Location))
				{
					F.SpawnedActors[0] = F.Spawn(F.InternalPrototype,, F.Tag, F.Location, F.Rotation);
					bSpawnOK = F.SetupNewActor(F.SpawnedActors[0], None);
				}
			}
		}
		else if(F.SpawnMode == SPM_NearPlayer)
		{
			DistToPlayer = 0.0;
			NearestSpawn = -1;

			foreach F.DynamicActors(class'PlayerController', P)
			{
				if(P.Pawn == None)
					continue;

				for(i = 0; i < F.SpawnPoints.Length; ++i)
				{
					TempDist = VDistSq(P.Pawn.Location, F.SpawnPoints[i].Location);

					if(DistToPlayer == 0.0 || DistToPlayer > TempDist)
					{
						if(!F.bCovert || F.IsLocationCovert(F.SpawnPoints[i].Location))
						{
							DistToPlayer = TempDist;
							NearestSpawn = i;
						}
					}
				}
			}

			if(NearestSpawn >= 0 && F.PlayerRangeTest(F.SpawnPoints[NearestSpawn].Location))
			{
				F.SpawnedActors[0] = F.Spawn(F.InternalPrototype,, F.Tag, F.SpawnPoints[NearestSpawn].Location, F.SpawnPoints[NearestSpawn].Rotation);
				bSpawnOK = F.SetupNewActor(F.SpawnedActors[0], F.SpawnPoints[NearestSpawn]);
			}
		}
		else
		{
			if(F.PlayerRangeTest(F.SpawnPoints[F.NextSpawnPoint].Location) && (!F.bCovert || F.IsLocationCovert(F.SpawnPoints[F.NextSpawnPoint].Location)))
			{
				F.SpawnedActors[0] = F.Spawn(F.InternalPrototype,, F.Tag, F.SpawnPoints[F.NextSpawnPoint].Location, F.SpawnPoints[F.NextSpawnPoint].Rotation);
				bSpawnOK = F.SetupNewActor(F.SpawnedActors[0], F.SpawnPoints[F.NextSpawnPoint]);
			}
		}

		if(bSpawnOK && !F.bGenerateForever)
			F.RemainingItems--;

		F.DetermineNextSpawnPoint(bSpawnOK);
		F.TriggerEvent(F.SpawnEvent, F, None);

		if(F.bStartTimerAfterDeath && F.SpawnedActors.Length >= F.MaxAlive)
			F.GotoState('Waiting');

		return true;
	}

	return false;
}

// Critical messages of scripts are shown by the HUDs on the server, remote clients have none there
function bool ObjectiveUpdateInitActionFor(ScriptedController C)
{
	local ACTION_ObjectiveUpdate Action;
	local MissionObjectives Obj;
	local bool bResult;

	Action = ACTION_ObjectiveUpdate(ObjectiveUpdateOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(Action.DisplayText != "" && CoopGame(C.Level.Game) != None)
	{
		foreach C.AllActors(class'MissionObjectives', Obj)
			break;

		if(Obj != None)
			CoopGame(C.Level.Game).ForwardCriticalMessage(Action.DisplayText, Obj.FadeTime, Obj.CritTextColor);
	}

	return bResult;
}

function bool CriticalMessageInitActionFor(ScriptedController C)
{
	local ACTION_DisplayCriticalMessage Action;
	local bool bResult;

	Action = ACTION_DisplayCriticalMessage(CriticalMessageOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardCriticalMessage(Action.Message, Action.Duration, Action.Color);

	return bResult;
}

