class CoopReconnectMenu extends MenuTemplateTitledBA;

#exec OBJ LOAD FILE="XInterface.u"

/*
 * CoopReconnectMenu
 * Shown instead of the 'connection failed' screen while in a coop session. Retries to connect to the host a couple of times.
 * This happens when the host loads a checkpoint, restarts the game or when the connection drops.
 */

var() MenuText Message;
var() MenuText Countdown;
var() localized string ReconnectingStr;
var() localized string AttemptStr;

var() localized string ConnectingStr;
var() localized string GaveUpStr;

var float TimeLeft;     // Time until the next attempt
var bool  bConnecting;  // An attempt is in progress. If it succeeds the level changes and this menu goes away.

simulated function Init(string Args)
{
	Super.Init(Args);

	Message.Text = ReconnectingStr @ class'CoopConfig'.default.ReconnectAddress;
	TimeLeft = class'CoopConfig'.default.ReconnectInterval;

	if(class'CoopConfig'.default.ReconnectAttempts == 0)
		TimeLeft = FMin(TimeLeft, 3.0); // First retry a bit faster

	UpdateCountdown();
}

simulated function UpdateCountdown()
{
	local string Attempt;

	Attempt = AttemptStr @ Min(class'CoopConfig'.default.ReconnectAttempts + int(!bConnecting), class'CoopConfig'.default.MaxReconnectAttempts) $ "/" $ class'CoopConfig'.default.MaxReconnectAttempts;

	if(bConnecting)
		Countdown.Text = Attempt $ ": " $ ConnectingStr;
	else
		Countdown.Text = Attempt $ ": " $ Max(int(TimeLeft + 0.99), 0);
}

simulated function Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);

	if(class'CoopConfig'.default.ReconnectAddress == "")
		return;

	TimeLeft -= DeltaTime;

	if(TimeLeft <= 0)
	{
		if(bConnecting)
		{
			// The attempt failed (the engine doesn't reopen the 'connection failed' menu when connecting from a menu)
			bConnecting = false;
			TimeLeft = class'CoopConfig'.default.ReconnectInterval;
		}
		else if(class'CoopConfig'.default.ReconnectAttempts >= class'CoopConfig'.default.MaxReconnectAttempts)
		{
			Log("ModCoop: Giving up reconnecting to " $ class'CoopConfig'.default.ReconnectAddress);
			Message.Text = GaveUpStr;
			class'CoopConfig'.static.EndSession();
		}
		else
		{
			Reconnect();
		}
	}

	UpdateCountdown();
}

simulated function Reconnect()
{
	if(class'CoopConfig'.default.ReconnectAddress == "")
		return;

	++class'CoopConfig'.default.ReconnectAttempts;
	class'CoopConfig'.static.ApplyClientTimeouts(); // Fail fast if the host is not there yet
	bConnecting = true;
	TimeLeft = class'CoopConfig'.default.ClientTimeout + 2.0;
	Log("ModCoop: Reconnect attempt " $ class'CoopConfig'.default.ReconnectAttempts $ " to " $ class'CoopConfig'.default.ReconnectAddress);
	GetPlayerOwner().ConsoleCommand("open " $ class'CoopConfig'.static.MakeConnectURL(class'CoopConfig'.default.ReconnectAddress));
}

// Reconnect now
simulated function OnAButton()
{
	if(class'CoopConfig'.default.ReconnectAddress == "")
	{
		HandleInputBack();
		return;
	}

	if(class'CoopConfig'.default.ReconnectAttempts >= class'CoopConfig'.default.MaxReconnectAttempts)
		class'CoopConfig'.default.ReconnectAttempts = class'CoopConfig'.default.MaxReconnectAttempts - 1;

	Reconnect();
}

// Cancel
simulated function HandleInputBack()
{
	class'CoopConfig'.static.EndSession();
	GotoMenuClass("XInterfaceCTMenus.CTMultiplayerPCMenu");
}

defaultproperties
{
	ReconnectingStr="CONNECTION TO THE HOST WAS LOST. RECONNECTING TO"
	AttemptStr="ATTEMPT"
	ConnectingStr="CONNECTING..."
	GaveUpStr="THE HOST IS NOT AVAILABLE. PRESS BACK TO RETURN TO THE MENU."
	MenuTitle=(Text="CO-OP: RECONNECTING",bHidden=0)
	Message=(DrawPivot=DP_MiddleLeft,PosX=0.075,PosY=0.45,MaxSizeX=0.85,bWordWrap=1,Pass=2,Style="LabelText")
	Countdown=(DrawPivot=DP_MiddleLeft,PosX=0.075,PosY=0.55,MaxSizeX=0.85,Pass=2,Style="LabelText")
	AButton=(Blurred=(Text="RETRY NOW"),bHidden=0)
	Background=(bHidden=1)
	CrossFadeRate=20
}
