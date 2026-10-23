class CoopMultiplayerMenu extends CTMultiplayerPCMenu;

#exec OBJ LOAD FILE="XInterface.u"
#exec OBJ LOAD FILE="XInterfaceCTMenus.u"

/*
 * CoopMultiplayerMenu
 * The regular multiplayer menu with two additional entries for the coop campaign.
 * Replaces XInterfaceCTMenus.CTMultiplayerPCMenu via CoopExtension.RedirectMenuClass.
 */

var() MenuButtonText CoopOptions[2];

simulated function Init(String Args)
{
	Super.Init(Args);

	// ModCoop is only needed as a server package for coop games. Regular multiplayer servers must not require it from clients.
	class'CoopNative'.static.RemoveServerPackage("ModCoop");

	// Undo the border tightening of the parent class to make room for the coop entries
	Border.PosY += 0.05666;
	Border.ScaleY += 0.11332;
}

simulated function CoopHostSelected()
{
	CallMenuClass("ModCoop.CoopHostMenu");
}

simulated function CoopJoinSelected()
{
	CallMenuClass("ModCoop.CoopJoinMenu");
}

defaultproperties
{
	CoopOptions(0)=(Blurred=(Text="CO-OP: HOST CAMPAIGN",PosX=0.68375,PosY=0.76),BackgroundBlurred=(PosX=0.68375,PosY=0.76,ScaleX=0.38,ScaleY=0.04333),OnSelect="CoopHostSelected",Style="ButtonTextStyle1")
	CoopOptions(1)=(Blurred=(Text="CO-OP: JOIN BY IP",PosY=0.81666),BackgroundBlurred=(PosY=0.81666),OnSelect="CoopJoinSelected")
}
