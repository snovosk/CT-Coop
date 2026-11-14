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
var FunctionOverride SetCollisionOverride;      // Collision changes of scripts for the clients (see CoopGame.ForwardSetCollision)
var FunctionOverride SetHiddenOverride;
var FunctionOverride GotoStateOverride;
var FunctionOverride PlayAnimOverride;
var FunctionOverride PlayPropAnimOverride;
var FunctionOverride HurtActorOverride;
var FunctionOverride ChangeSquadMemberOverride;
var FunctionOverride CriticalMessageOverride;
var FunctionOverride ActivateItemTransitionOverride; // Effects for the clients (see CoopGame.ForwardEffect)
var FunctionOverride DispenserTransitionOverride;
var FunctionOverride FactoryRangeTestOverride;     // Players without a pawn (see FactoryPlayerRangeTest)
var FunctionOverride FactoryCovertOverride;
var FunctionOverride FactoryGenerateOverride;
var FunctionOverride TriggerRelevantOverride;    // Squad triggers for the clients' members (see TriggerIsRelevant)
var FunctionOverride CounterTriggerOverride;     // Diagnostics: counters of level scripts (see CounterTrigger)
var FunctionOverride AttachmentEffectsOverride;  // Animations of other players' commandos (see AttachmentThirdPersonEffects)
var FunctionOverride AttachmentBeginOverride;    // Same, when the attachment is spawned (see AttachmentPostNetBeginPlay)
var array<CoopTurretFire> TurretFires;           // Shots of clients on turrets (see CoopTurretFire)
var FunctionOverride WeaponSetOverride;          // Quiet new inventory on clients (see WeaponClientWeaponSet)
var array<CoopActionForward> ActionForwards;     // Script actions that only reach the server's player (see CoopActionForward)
var FunctionOverride StopFactoryOverride;        // Scripts that give up on a door the clients hold (see CoopDoorHold)
var FunctionOverride DestroyActorOverride;
var FunctionOverride ShowIconsOverride;          // One writer of the markers' bHidden on clients (see SquadMarkerShowIcons)
var FunctionOverride LaserDestroyedOverride;     // Remote beam of a destroyed laser (see RemoveRemoteBeam)
var FunctionOverride PawnPlayFiringOverride;     // See PawnPawnPlayFiring
var FunctionOverride MoverToKeyframeOverride;    // A level that starts on a moving lift waits for the clients (see CoopEndLift.ShouldHoldStartLift)
var FunctionOverride HudDescriptionOverride;     // The player's name over the host and over a commando without a squad member (see PawnHudName)
var FunctionOverride HudNicknameOverride;

function Init(SWRCFix Fix)
{
	Log("ModCoop version " $ class'CoopConfig'.static.Version());
	class'CoopNative'.static.LogSystemInfo();
	class'CoopNative'.static.InstallClientFixes();
	class'CoopNative'.static.LoadSavedConfig(class'CoopConfig', "ModCoop.ini");
	class'CoopConfig'.static.LoadLists();
	class'CoopNative'.static.LoadSavedConfig(class'CoopGame', "ModCoop.ini");
	class'CoopNative'.static.SetSoundLog(class'CoopConfig'.default.bSoundLog);

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
	SetCollisionOverride = new class'FunctionOverride';
	SetCollisionOverride.Init(class'ACTION_SetCollision', 'InitActionFor', self, 'SetCollisionInitActionFor');
	SetHiddenOverride = new class'FunctionOverride';
	SetHiddenOverride.Init(class'ACTION_SetHidden', 'InitActionFor', self, 'SetHiddenInitActionFor');
	PlayAnimOverride = new class'FunctionOverride';
	PlayAnimOverride.Init(class'ACTION_PlayAnim', 'InitActionFor', self, 'PlayAnimInitActionFor');
	PlayPropAnimOverride = new class'FunctionOverride';
	PlayPropAnimOverride.Init(class'ACTION_PlayPropAnim', 'InitActionFor', self, 'PlayPropAnimInitActionFor');
	HurtActorOverride = new class'FunctionOverride';
	HurtActorOverride.Init(class'ACTION_HurtActor', 'InitActionFor', self, 'HurtActorInitActionFor');
	ChangeSquadMemberOverride = new class'FunctionOverride';
	ChangeSquadMemberOverride.Init(class'ACTION_ChangeSquadMember', 'InitActionFor', self, 'ChangeSquadMemberInitActionFor');
	GotoStateOverride = new class'FunctionOverride';
	GotoStateOverride.Init(class'ACTION_GotoState', 'InitActionFor', self, 'GotoStateInitActionFor');
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
	TriggerRelevantOverride = new class'FunctionOverride';
	TriggerRelevantOverride.Init(class'Trigger', 'IsRelevant', self, 'TriggerIsRelevant');
	CounterTriggerOverride = new class'FunctionOverride';
	CounterTriggerOverride.Init(class'Counter', 'Trigger', self, 'CounterTrigger');
	AttachmentEffectsOverride = new class'FunctionOverride';
	AttachmentEffectsOverride.Init(class'WeaponAttachment', 'ThirdPersonEffects', self, 'AttachmentThirdPersonEffects');
	AttachmentBeginOverride = new class'FunctionOverride';
	AttachmentBeginOverride.Init(class'WeaponAttachment', 'PostNetBeginPlay', self, 'AttachmentPostNetBeginPlay');
	AddTurretFire(class'Weapon');
	AddTurretFire(class<Weapon>(DynamicLoadObject("CTInventory.EWebTurret", class'Class')));
	AddTurretFire(class<Weapon>(DynamicLoadObject("CTInventory.GunshipTurret", class'Class')));
	AddTurretFire(class<Weapon>(DynamicLoadObject("CTInventory.MissileTurret", class'Class')));
	AddTurretFire(class<Weapon>(DynamicLoadObject("CTInventory.ATTEWalkerTurret", class'Class')));
	WeaponSetOverride = new class'FunctionOverride';
	WeaponSetOverride.Init(class'Weapon', 'ClientWeaponSet', self, 'WeaponClientWeaponSet');
	StopFactoryOverride = new class'FunctionOverride';
	StopFactoryOverride.Init(class'ACTION_StopFactorySpawning', 'InitActionFor', self, 'StopFactorySpawningInitActionFor');
	DestroyActorOverride = new class'FunctionOverride';
	DestroyActorOverride.Init(class'ACTION_DestroyActor', 'InitActionFor', self, 'DestroyActorInitActionFor');
	ShowIconsOverride = new class'FunctionOverride';
	ShowIconsOverride.Init(class'SquadMarker', 'ShowIcons', self, 'SquadMarkerShowIcons');
	LaserDestroyedOverride = new class'FunctionOverride';
	LaserDestroyedOverride.Init(class'LaserWeapon', 'Destroyed', self, 'LaserWeaponDestroyed');
	PawnPlayFiringOverride = new class'FunctionOverride';
	PawnPlayFiringOverride.Init(class'Pawn', 'PawnPlayFiring', self, 'PawnPawnPlayFiring');
	MoverToKeyframeOverride = new class'FunctionOverride';
	MoverToKeyframeOverride.Init(class'ACTION_MoverToKeyframe', 'InitActionFor', self, 'MoverToKeyframeInitActionFor');
	HudDescriptionOverride = new class'FunctionOverride';
	HudDescriptionOverride.Init(class'Pawn', 'GetHudDescription', self, 'PawnHudDescription');
	HudNicknameOverride = new class'FunctionOverride';
	HudNicknameOverride.Init(class'Pawn', 'GetHudNickname', self, 'PawnHudNickname');

	AddActionForward(class'ACTION_PlayMusic');
	AddActionForward(class'ACTION_SetImuseState');
	AddActionForward(class'ACTION_ForceBattleMusic');
	AddActionForward(class'ACTION_ForceVictoryFlourish');
	AddActionForward(class'ACTION_SetBattleMusicMulti');
	AddActionForward(class'ACTION_DisplayMessage');
	AddActionForward(class'ACTION_AnimateVisorFX');
	AddActionForward(class'ACTION_ShowVisor');
	AddActionForward(class'ACTION_ShowPrompt');
	AddActionForward(class'ACTION_ConsoleCommand');
	AddActionForward(class'ACTION_ChangeZoneAudio');
	AddActionForward(class'ACTION_ShowMarker');
	AddActionForward(class'ACTION_ShowTitleCardScreen');
	AddActionForward(class'ACTION_ShowMenuScreen');
}

function AddTurretFire(class<Weapon> WeaponClass)
{
	local CoopTurretFire Fire;

	Fire = new class'CoopTurretFire';
	Fire.Init(WeaponClass);
	TurretFires[TurretFires.Length] = Fire;
}

function AddActionForward(class<ScriptedAction> ActionClass)
{
	local CoopActionForward Forward;

	Forward = new class'CoopActionForward';
	Forward.Init(ActionClass);
	ActionForwards[ActionForwards.Length] = Forward;
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
 * so clients could never target a panel (bacta dispensers, hacking, explosives). Same code, but simulated, and a player's squad member
 * only gets the panels of its specialty.
 */
simulated function bool ActivateItemHasRequiredInventory(Pawn P)
{
	local ActivateItem Item;
	local Ammunition AmmoType;

	Item = ActivateItem(HasRequiredInventoryOverride.CurrentSelf);

	// The specialty of the squad member a player plays (see CoopGame.MemberCanUse)
	if(!class'CoopGame'.static.MemberCanUse(P, Item))
		return false;

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

	if(MenuClassName ~= "XInterfaceCTMenus.CTMultiplayerPausePCMenu")
		return "ModCoop.CoopPauseMenu";

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

/*
 * Triggers of the squad (TT_SquadMemberProximity) only count pawns of the player's squad. The members the clients play are taken out
 * of the AI squad, so these triggers never saw them (YYY_01B: SquadInTrap waits for the 4 commandos in the clearing and enables the
 * demolition marker of the hatch; it never came). Same code, the commandos of the clients count too.
 * Triggers of the player's class (TT_ClassProximity with PlayerCommando, YYY_04B: the reinforcements, the wookiee jump and the last
 * trandoshans) only saw the host: a client playing a Delta member has that member's class. The commandos of the clients count too.
 * A survey of all campaign maps found no other trigger, counter or marker that counts the squad or the players.
 */
function bool TriggerIsRelevant(Actor Other)
{
	local Trigger T;

	T = Trigger(TriggerRelevantOverride.CurrentSelf);

	// See CoopEndLift: it starts when the squad is on the lift, not with the first one who touches this trigger
	if(CoopGame(T.Level.Game) != None && CoopGame(T.Level.Game).EndLift != None && CoopGame(T.Level.Game).EndLift.IsHeld(T))
		return false;

	// See CoopDoorHold
	if(CoopGame(T.Level.Game) != None && CoopGame(T.Level.Game).DoorHold != None && CoopGame(T.Level.Game).DoorHold.IsHeld(T, Other))
		return false;

	if(T.bInitiallyActive && Pawn(Other) != None && CoopPlayer(Pawn(Other).Controller) != None && Pawn(Other).IsA('CloneCommando'))
	{
		if(T.TriggerType == TT_SquadMemberProximity)
			return true;

		if(T.TriggerType == TT_ClassProximity && ClassIsChildOf(T.ClassProximityType, class'PlayerCommando'))
		{
			if(!T.IsRelevant(Other))
				Log("CoopGame: trigger " $ T $ " of the player's class counts " $ Other $ " of a client");

			return true;
		}
	}

	return T.IsRelevant(Other);
}

/*
 * Diagnostics: levels wait for counters (GEO_03D: the control room door waits for two droids and the hacked computer, it never
 * opened in a co-op run and the log couldn't tell which one was missing). Every count is logged on the server.
 */
function CounterTrigger(Actor Other, Pawn EventInstigator)
{
	local Counter C;

	C = Counter(CounterTriggerOverride.CurrentSelf);

	if(C.NumToCount > 0)
		Log("CoopGame: counter " $ C.Tag $ " got " $ Other $ " (instigator " $ EventInstigator $ "), " $ (C.NumToCount - 1) $ " left before " $ C.Event);

	C.Trigger(Other, EventInstigator);
}

/*
 * Weapon attachments play the multiplayer animations on the pawn of another player (DC17mMeleeAttack, DC17mFire, DC17Load...).
 * Single player blanks these names in PostNetBeginPlay (NM_Standalone only), the pawns of the campaign have none of them.
 * - The commandos of co-op use the single player animation set ("PlayAnim: Sequence 'DC17mMeleeAttack' not found" in the clients'
 *   logs): the melee attack, throws, reloads and weapon changes of the host and of other clients weren't seen. The names are
 *   replaced by the single player animations; the fire animation is left to Pawn.SelectFireAnim.
 * - Other pawns (droids, geonosians, trandoshans, troopers, gunships: "DC17Load", "ShotgunFire", "EliteBeamFire" not found on the
 *   host and the clients) get the blank names like in single player, their AI plays its own animations.
 * Other pawns get it when the attachment is spawned and again before its first effect (the owner may only be known then),
 * commandos before their first effect.
 */
simulated function AttachmentPostNetBeginPlay()
{
	local WeaponAttachment WA;

	WA = WeaponAttachment(AttachmentBeginOverride.CurrentSelf);
	WA.PostNetBeginPlay();

	// Commandos only before their first effect, like 0.61: done at the spawn, the blank breathe name made the host's commando play
	// ActionBreathe over its waiting animation in the GEO_03A briefing (session 2026-10-31)
	if(Pawn(WA.Owner) != None && !Pawn(WA.Owner).IsA('CloneCommando'))
		UseCampaignAnims(WA);
}

simulated function AttachmentThirdPersonEffects()
{
	local WeaponAttachment WA;

	WA = WeaponAttachment(AttachmentEffectsOverride.CurrentSelf);

	if(WA.Instigator == None && Pawn(WA.Owner) != None)
		WA.Instigator = Pawn(WA.Owner);

	UseCampaignAnims(WA);
	WA.ThirdPersonEffects();
}

simulated function bool MissingAnim(Pawn P, name Anim)
{
	return Anim != '' && !P.HasAnim(Anim);
}

simulated function UseCampaignAnims(WeaponAttachment WA)
{
	local Pawn P;

	P = WA.Instigator;

	if(P == None)
		P = Pawn(WA.Owner);

	if(P == None || WA.Level.NetMode == NM_Standalone || P.IsA('MPPawn'))
		return;

	if(!MissingAnim(P, WA.MPPawnFireAnim) && !MissingAnim(P, WA.MPPawnLoadAnim) && !MissingAnim(P, WA.MPPawnMeleeAnim) &&
	   !MissingAnim(P, WA.MPPawnBreatheAnim) && !MissingAnim(P, WA.MPPawnThrowAnim) && !MissingAnim(P, WA.MPPawnHolsterAnim))
		return;

	if(P.IsA('CloneCommando'))
	{
		WA.MPPawnFireAnim = '';
		WA.MPPawnMeleeAnim = SPAnim(P, 'MeleeAttack');
		WA.MPPawnThrowAnim = SPAnim(P, 'ThrowGrenade');
		WA.MPPawnLoadAnim = SPAnim(P, 'Load');
		WA.MPPawnHolsterAnim = SPAnim(P, 'Holster');
		WA.MPPawnBreatheAnim = '';
		WA.MPPawnIdleAnim = '';
		Log("ModCoop: single player animations for " $ WA $ " of " $ P $ ": melee " $ WA.MPPawnMeleeAnim $ ", throw " $ WA.MPPawnThrowAnim);
		return;
	}

	WA.MPPawnBreatheAnim = '';
	WA.MPPawnFireAnim = '';
	WA.MPPawnHolsterAnim = '';
	WA.MPPawnLoadAnim = '';
	WA.MPPawnIdleAnim = '';
	WA.MPPawnMeleeAnim = '';
	WA.MPPawnThrowAnim = '';
}

// See CoopPlayer.ClientCoopWeaponsQuiet: a weapon given while the server equips this client's pawn doesn't switch the weapon
simulated function WeaponClientWeaponSet(bool bOptionalSet)
{
	local Weapon W;
	local Pawn P;
	local CoopPlayer CP;

	W = Weapon(WeaponSetOverride.CurrentSelf);
	P = Pawn(W.Owner);

	if(P != None && W.Level.NetMode == NM_Client)
	{
		CP = CoopPlayer(W.Level.GetLocalPlayerController());

		if(CP != None && CP.bQuietWeaponSet && (P.Controller == CP || P.Controller == None))
		{
			W.Instigator = P;

			if(W.IsInState('PendingClientWeaponSet'))
				W.GotoState('');

			return;
		}
	}

	W.ClientWeaponSet(bOptionalSet);
}

simulated function name SPAnim(Pawn P, name AnimName)
{
	if(P.HasAnim(AnimName))
		return AnimName;

	return '';
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

		// Effects of FXFactories (GEO_03A: the explosion of the jamming device, StartFX and MainFX) exist on the server only
		if(F.SpawnedActors[0] != None && Emitter(F.SpawnedActors[0]) != None && F.SpawnedActors[0].RemoteRole == ROLE_None && CoopGame(F.Level.Game) != None)
			CoopGame(F.Level.Game).ForwardEffect(class<Emitter>(F.SpawnedActors[0].Class), F.SpawnedActors[0].Location, F.SpawnedActors[0].Rotation, None);

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
// Scripts switch the collision of map actors on the server only (GEO_01B: Hangar01BlockingVolume, an invisible wall in the hangar for
// clients). Static actors like volumes aren't replicated: the clients do the same by tag.
function bool SetCollisionInitActionFor(ScriptedController C)
{
	local ACTION_SetCollision Action;
	local bool bResult;

	Action = ACTION_SetCollision(SetCollisionOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(Action.CollideActorTag != '' && CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardSetCollision(Action.CollideActorTag, Action.bCollideActors, Action.bBlockActors, Action.bBlockPlayers);

	return bResult;
}

// Same for hiding and showing (GEO_03A: the hologram of the briefing in the elevator)
function bool SetHiddenInitActionFor(ScriptedController C)
{
	local ACTION_SetHidden Action;
	local bool bResult;

	Action = ACTION_SetHidden(SetHiddenOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(Action.HideActorTag != '' && CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardSetHidden(Action.HideActorTag, Action.bHidden);

	return bResult;
}

// Animations of NPC scripts (GEO_03A: the briefing in the elevator) for the clients (see CoopGame.ForwardScriptAnim)
function bool PlayAnimInitActionFor(ScriptedController C)
{
	local ACTION_PlayAnim Action;
	local bool bResult;

	Action = ACTION_PlayAnim(PlayAnimOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(C.Pawn != None && Action.BaseAnim != '' && CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardScriptAnim(C.Pawn, Action.BaseAnim, Action.AnimRate, Action.bLoopAnim || Action.AnimIterations > 0);

	return bResult;
}

// The same for the animations of pawns a script plays as a prop (see CoopGame.ForwardPropAnim)
function bool PlayPropAnimInitActionFor(ScriptedController C)
{
	local ACTION_PlayPropAnim Action;
	local Pawn P;
	local bool bResult;

	Action = ACTION_PlayPropAnim(PlayPropAnimOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) == None || Action.BaseAnim == '')
		return bResult;

	if(Action.AnimPropTag == '')
		CoopGame(C.Level.Game).ForwardPropAnim(C.GetInstigator(), Action.BaseAnim, Action.AnimRate);
	else
	{
		foreach C.AllActors(class'Pawn', P, Action.AnimPropTag)
			CoopGame(C.Level.Game).ForwardPropAnim(P, Action.BaseAnim, Action.AnimRate);
	}

	return bResult;
}

// See CoopGame.HurtPlayersInTrigger
function bool HurtActorInitActionFor(ScriptedController C)
{
	if(CoopGame(C.Level.Game) != None && CoopGame(C.Level.Game).HurtPlayersInTrigger(C, ACTION_HurtActor(HurtActorOverride.CurrentSelf)))
		return false;

	return ACTION_HurtActor(HurtActorOverride.CurrentSelf).InitActionFor(C);
}

// See CoopDoorHold: the script's stop waits until the clients are through the door
function bool StopFactorySpawningInitActionFor(ScriptedController C)
{
	local ACTION_StopFactorySpawning Action;

	Action = ACTION_StopFactorySpawning(StopFactoryOverride.CurrentSelf);

	if(CoopGame(C.Level.Game) != None && CoopGame(C.Level.Game).DoorHold != None && CoopGame(C.Level.Game).DoorHold.ShouldDeferFactoryStop(Action.FactoryTag))
		return false;

	return Action.InitActionFor(C);
}

/*
 * HACK: a flying pawn with full flying animations (bHasFullFlyAnims: the Elite Geonosian) firing during a script's animation lets go of it in
 * single player: the script gets AnimEnd on channel 0 right after PawnPlayFiring and ClearAnimation plays the flying idle. In a network game
 * the same call doesn't end channel 0 (why, in the native animation code, isn't known), the script's animation plays on: GEO_03C's Elite
 * rose 900 units more with the root motion of its Intro, past every FlyPoint, found no anchor and hung under the ceiling for the rest of
 * the fight (the tester's game on 0.73, test elite: 1830 in single player, 2700 in a network game). The script lets go here like in
 * single player. Remove when the native reason is found.
 */
simulated function PawnPawnPlayFiring(name AnimName, bool bLoop)
{
	local Pawn P;
	local ScriptedController C;

	P = Pawn(PawnPlayFiringOverride.CurrentSelf);
	P.PawnPlayFiring(AnimName, bLoop);

	if(P.Level.NetMode == NM_Standalone || P.Level.NetMode == NM_Client || !P.bHasFullFlyAnims || P.Physics != PHYS_Flying || P.bDisableFireAnims)
		return;

	C = ScriptedController(P.Controller);

	if(C != None && C.bControlAnimations && C.IsInState('Scripting') && C.CurrentAnimation != None && !C.CurrentAnimation.bWaitUntilAnimEnd)
	{
		Log("CoopGame: " $ P $ " fires during the script's animation " $ C.CurrentAnimation.BaseAnim $ ", the script lets go of it like in single player");
		C.ClearAnimation();
	}
}

/*
 * See CoopEndLift.ShouldHoldStartLift. The script waits on a timer like the action itself does (CompleteWhenTimer), and ActionNum is put back one
 * so that the completion comes back to this action: it asks again every poll until the lift is released.
 */
function bool MoverToKeyframeInitActionFor(ScriptedController C)
{
	local ACTION_MoverToKeyframe Action;
	local CoopGame Game;
	local bool bLatent;

	Action = ACTION_MoverToKeyframe(MoverToKeyframeOverride.CurrentSelf);
	Game = CoopGame(C.Level.Game);

	if(Game == None || Game.EndLift == None || !Game.EndLift.ShouldHoldStartLift(Action))
	{
		bLatent = Action.InitActionFor(C);

		// Where the mover stops, for the clients' copies (see CoopGame.SendMoverStops)
		if(Game != None && Action.MoverTag != 'None')
			Game.SendMoverStops(Action.MoverTag);

		return bLatent;
	}

	--C.ActionNum;
	C.CurrentAction = Action;
	C.SetTimer(Game.EndLift.StartLiftPoll(), false);

	return true;
}

function bool DestroyActorInitActionFor(ScriptedController C)
{
	local ACTION_DestroyActor Action;

	Action = ACTION_DestroyActor(DestroyActorOverride.CurrentSelf);

	if(CoopGame(C.Level.Game) != None && CoopGame(C.Level.Game).DoorHold != None && CoopGame(C.Level.Game).DoorHold.ShouldDeferDestroy(Action.DestroyTag))
		return false;

	return Action.InitActionFor(C);
}

/*
 * RAS_01C, every console showed as sliceable on clients. PostBeginPlay isn't simulated, so a client's marker has no Participants[0].IconActor and
 * the original only warns there. CoopGame.SyncMarkerVisibility decides the bHidden of the marker on the client, nothing else may write it.
 */
/*
 * Names over squad members (APawn::PostRender, coop since 2026-11-12): Delta members have their nickname (SEV, FIXER, SCORCH), the host's
 * PlayerCommando and a CoopCommando only Pawn's defaults, "00" and "" (the user saw "00" over the host). In a network game a pawn played
 * by somebody shows that player's name. Only Pawn's own functions are hooked, the members' overrides stay as they are.
 */
simulated function string PawnHudName(Pawn P)
{
	if(P == None || P.Level.NetMode == NM_Standalone || P.PlayerReplicationInfo == None || P.PlayerReplicationInfo.PlayerName == "")
		return "";

	return Caps(P.PlayerReplicationInfo.PlayerName);
}

simulated function string PawnHudDescription()
{
	local Pawn P;
	local string Name;

	P = Pawn(HudDescriptionOverride.CurrentSelf);
	Name = PawnHudName(P);

	if(Name != "")
		return Name;

	return P.GetHudDescription();
}

simulated function string PawnHudNickname()
{
	local Pawn P;
	local string Name;

	P = Pawn(HudNicknameOverride.CurrentSelf);
	Name = PawnHudName(P);

	// The color of the name in tactical mode: CoopPlayer.CheckNameColors
	if(Name != "")
		return Name;

	return P.GetHudNickname();
}

/*
 * How a hologram is seen: SquadMarker.UpdateIcons, called every frame for the player's TargetMarker (CTPlayer.PlayerTick), shows it when
 * the marker is of use to that player; the render pass (Engine.dll, the hologram shader near 0x10564340) hides it again, alpha 0 and
 * bHidden, as soon as it is neither looked at nor active. On a client the use is always "irrelevant" (ASquadMarker::GetMarkerUsability
 * needs the viewer to lead a squad), and this hook kept the client's own calls out entirely. On a client the server's decision for that
 * client (CoopGame.SyncMarkerVisibility) now takes the place of the use. See also CoopPlayer.SelectTargetType for the TargetMarker.
 */
simulated function SquadMarkerShowIcons(bool Show, int Start, int Stop)
{
	local SquadMarker M;
	local CoopPlayer PC;
	local int i;

	M = SquadMarker(ShowIconsOverride.CurrentSelf);

	if(M.Role == ROLE_Authority)
	{
		M.ShowIcons(Show, Start, Stop);
		return;
	}

	PC = CoopPlayer(M.Level.GetLocalPlayerController());

	if(PC == None || !PC.IsMarkerShown(M))
		return;

	// SquadMarker.ShowIcons itself, without the icons a client's copy doesn't have: it warned every frame for each of them (8000 lines in
	// the client's log of the user's act 2 game)
	for(i = Start; i < Stop && i < ArrayCount(M.Participants); ++i)
	{
		if(M.Participants[i].IconActor != None)
			M.Participants[i].IconActor.bHidden = false;
	}
}

simulated function LaserWeaponDestroyed()
{
	RemoveRemoteBeam(LaserWeapon(LaserDestroyedOverride.CurrentSelf));
	LaserWeapon(LaserDestroyedOverride.CurrentSelf).Destroyed(); // Calls the original function
}

/*
 * Frozen lightning of scavenger droids: in network mode the ammo spawns a replicated beam on the server, and the only thing that ever ends it is
 * bHidden in the ammo's Tick. A droid killed while firing loses its weapon and ammo at once (ScavBeam has no pickup), the beam stayed in the air
 * forever. Runs before the original, which destroys the ammo's own tracer only.
 */
simulated function RemoveRemoteBeam(LaserWeapon W)
{
	local LaserWeaponAmmo Ammo;

	Ammo = LaserWeaponAmmo(W.AmmoType);

	if(W.Role != ROLE_Authority || Ammo == None || Ammo.RemoteTracerEmitter == None)
		return;

	Ammo.RemoteTracerEmitter.Destroy();
	Ammo.RemoteTracerEmitter = None;
	Log("ModCoop: removed remote beam of " $ W);
}

// See CoopGame.IsClientMember
function bool ChangeSquadMemberInitActionFor(ScriptedController C)
{
	local ACTION_ChangeSquadMember Action;

	Action = ACTION_ChangeSquadMember(ChangeSquadMemberOverride.CurrentSelf);

	if(Action.bAddMember && CoopGame(C.Level.Game) != None && CoopGame(C.Level.Game).IsClientMember(Action.MemberTag))
		return false;

	return Action.InitActionFor(C);
}

// Same for squad markers that a script disables and enables again (GEO_04D: the demolition charge before the spider droids)
function bool GotoStateInitActionFor(ScriptedController C)
{
	local ACTION_GotoState Action;
	local bool bResult;

	Action = ACTION_GotoState(GotoStateOverride.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(Action.TargetTag != '' && Action.TargetTag != 'None' && CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).ForwardMarkerState(Action.TargetTag, Action.State);

	return bResult;
}

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

