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
