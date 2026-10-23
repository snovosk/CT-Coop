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

function Init(SWRCFix Fix)
{
	Log("ModCoop version " $ class'CoopConfig'.static.Version());
	class'CoopNative'.static.InstallClientFixes();
	class'CoopNative'.static.LoadSavedConfig(class'CoopConfig', "ModCoop.ini");
	class'CoopNative'.static.LoadSavedConfig(class'CoopGame', "ModCoop.ini");

	// Coop server started from the command line (e.g. the host batch file). The package must be added before the server starts listening.
	if(InStr(Caps(class'CoopNative'.static.GetCommandLine()), "MODCOOP.COOPGAME") != -1)
		class'CoopNative'.static.AddServerPackage("ModCoop");

	ConnectionFailedInitOverride = new class'FunctionOverride';
	ConnectionFailedInitOverride.Init(class'MenuConnectionFailed', 'Init', self, 'ConnectionFailedInit');

	DisconnectOnYesOverride = new class'FunctionOverride';
	DisconnectOnYesOverride.Init(class'MenuDisconnect', 'OnYes', self, 'DisconnectOnYes');
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
