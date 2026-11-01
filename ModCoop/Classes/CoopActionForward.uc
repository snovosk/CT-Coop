class CoopActionForward extends Object;

/*
 * CoopActionForward
 * Purpose: level script actions that only reach the local player of the server (music, visor effects, HUD text, tutorial prompts,
 *   zone audio, marker highlight, vision mode, title cards) are run on every client too. One instance per action class.
 *   Tutorial prompts only go to the player who triggered them, like the game does in network games.
 * Entry points: Init (CoopExtension.Init, on the server and the clients), ForwardInitActionFor (replaces InitActionFor of the
 *   action class), RunOnClient (CoopPlayer.ClientCoopRunAction).
 * Logging: server "CoopGame: forwarding script action", client "ModCoop: script action of the host", "ModCoop: script action not
 *   found".
 * State: Override (the hook of this action class).
 * Known limitations: the client looks the action up by its path in the map package, so it only works for actions placed in the map.
 *   Console commands are only forwarded for the vision mode (the other ones in the maps are debug cheats).
 */

var FunctionOverride Override;

function Init(class<ScriptedAction> ActionClass)
{
	Override = new class'FunctionOverride';
	Override.Init(ActionClass, 'InitActionFor', self, 'ForwardInitActionFor');
}

// Server: the original runs, then the clients run the same action. On the clients CoopGame is None and only the original runs.
function bool ForwardInitActionFor(ScriptedController C)
{
	local ScriptedAction Action;
	local bool bResult;

	Action = ScriptedAction(Override.CurrentSelf);
	bResult = Action.InitActionFor(C);

	if(CoopGame(C.Level.Game) == None || !ShouldForward(Action))
		return bResult;

	// In network games the prompt is only for the player who triggered it (ACTION_ShowPrompt): "You have been incapacitated" of the
	// host must not reach the clients. The original already showed it if that was the host.
	if(ACTION_ShowPrompt(Action) != None)
	{
		if(C.Instigator != None && CoopPlayer(C.Instigator.Controller) != None && !CoopGame(C.Level.Game).IsHost(C.Instigator.Controller))
			CoopGame(C.Level.Game).ForwardScriptAction(Action, CoopPlayer(C.Instigator.Controller));

		return bResult;
	}

	CoopGame(C.Level.Game).ForwardScriptAction(Action);

	return bResult;
}

static function bool ShouldForward(ScriptedAction Action)
{
	if(ACTION_ConsoleCommand(Action) != None)
		return Left(Caps(ACTION_ConsoleCommand(Action).CommandStr), 14) == "GOTOVISIONMODE";

	return true;
}

/*
 * Client: the action is run with a local script controller, so its loops over the player controllers only find the local player
 * and ACTION_ShowPrompt (which in network games only shows the prompt to the instigator) finds it as the instigator's controller.
 */
static function RunOnClient(CoopPlayer PC, string ActionPath)
{
	local ScriptedAction Action;

	Action = ScriptedAction(DynamicLoadObject(ActionPath, class'ScriptedAction', true));

	if(Action == None)
	{
		Log("ModCoop: script action not found: " $ ActionPath);
		return;
	}

	if(PC.LocalActionController == None)
		PC.LocalActionController = PC.Spawn(class'ScriptedController');

	if(PC.LocalActionController == None)
	{
		Log("ModCoop: no local script controller for " $ ActionPath);
		return;
	}

	PC.LocalActionController.Instigator = PC.Pawn;
	Log("ModCoop: script action of the host: " $ Action.GetActionString());
	Action.InitActionFor(PC.LocalActionController);
}
