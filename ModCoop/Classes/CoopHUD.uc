class CoopHUD extends CTHUD;

/*
 * CoopHUD
 * The helmet draws the squad icons only for AI squad members. Clients have no squad (it isn't replicated) and the squad members
 * played by clients are not in the AI squad of the host (see CoopGame.DetachClientMembers), so their icons were missing. They are
 * drawn here exactly like UHelmet::DrawHUD in Engine.dll does it, the numbers come from its machine code (Notes/HelmetHUD.md):
 * frame, order icon in the color of the health level, number, direction arrow or timer ring, and the corners while the member talks.
 * Clients see every other Delta member (the host, 38, has no icon), the host sees the members played by clients.
 */

var Texture SquadIcons;  // HUDTextures.Icons.CloneVisorIcons, the helmet's CloneVisorIcons
var Texture EventTimer;
var Texture NumberFont;  // OrbitFonts.OrbitBold15_PageA, the page of the helmet's Orbit15Font (see DrawNumber)
var int DigitStarts[10], DigitWidths[10];  // HUDTextures.Reticles.HUD_EventTimer, the helmet's EventTimer

// Order in which the 16 cells (column + 4 * row) of the timer ring fill, a twelfth at a time (UHelmet::DrawTimerRing)
var byte RingCells[16];
var byte RingSteps[16];  // The step (1-12) from which the cell is filled

simulated function PostRender(Canvas C)
{
	class'CoopNative'.static.SetDebugStep("HUD PostRender");
	Super.PostRender(C);

	if(!bHideHUD && PlayerOwner != None && PlayerOwner.Pawn != None && (PlayerOwner.Helmet == None || PlayerOwner.Helmet.bDraw) &&
	   !PlayerOwner.bBehindView)
		DrawCoopSquad(C);
}

simulated function DrawCoopSquad(Canvas C)
{
	local Pawn P;
	local int Slot;
	local bool bOldCurved, bTestOverlay;

	// Test: the host draws the AI members too (tinted), over the helmet's own icons, to compare them
	bTestOverlay = Level.NetMode != NM_Client && CoopGame(Level.Game) != None && CoopGame(Level.Game).TestAction ~= "squadicons";

	// In network games the helmet bends its HUD like the visor (FCanvasUtil curved surface), the same is used here
	bOldCurved = C.SetCurvedSurface(true);

	foreach DynamicActors(class'Pawn', P)
	{
		if(P == PlayerOwner.Pawn || P.bDeleteMe || (P.Health <= 0 && !P.bIncapacitated))
			continue;

		if(P.IsA('Commando07Delta') || P.IsA('Commando40Delta') || P.IsA('Commando62Delta'))
			Slot = P.SquadHUDSlot;
		else
			continue;

		if(Slot < 1 || Slot > 3)
			continue;

		// The host's helmet already shows the AI members; clients only show members that joined the squad (not e.g. Scorch on GEO_01A
		// before his scene)
		if(Level.NetMode != NM_Client && PlayerController(P.Controller) == None && !bTestOverlay)
			continue;

		if(Level.NetMode == NM_Client && (CoopPlayer(PlayerOwner) == None || !CoopPlayer(PlayerOwner).IsSquadIconMember(P)))
			continue;

		DrawSquadIcon(C, P, Slot, bTestOverlay && PlayerController(P.Controller) == None);
	}

	C.Flush();
	C.SetCurvedSurface(bOldCurved);
}

/*
 * One squad icon in the helmet's layout: 800x600, stretched to the screen. Base is 434 in network games (404 only in single player
 * with the visor).
 */
simulated function DrawSquadIcon(Canvas C, Pawn P, int Slot, bool bTint)
{
	local float SX, SY, X, T, Pulse;
	local byte IconX, IconY, MarkerState, Alpha;
	local bool bTarget;
	local int Base;

	SX = C.ClipX / 800.0;
	SY = C.ClipY / 600.0;
	X = 40 * (Slot - 1);
	Base = 434;
	T = Level.TimeSeconds;
	Pulse = 55 + 200 * Sin(5 * T);

	if(Level.NetMode == NM_Client)
		CoopPlayer(PlayerOwner).GetSquadIconState(P, IconX, IconY, MarkerState);
	else
		CoopGame(Level.Game).GetSquadIconState(P, IconX, IconY, MarkerState);

	bTarget = PlayerOwner.Target == P;
	C.Style = ERenderStyle.STY_Alpha;

	// Frame, lit while the player aims at the member
	if(bTarget)
	{
		SetIconColor(C, 255, 255, 255, 240 + 10 * Sin(10 * T), bTint);
		C.SetPos((75 + X) * SX, (Base + 10) * SY);
		C.DrawTile(SquadIcons, 43 * SX, 40 * SY, 148, 400, 44, 41);
	}
	else
	{
		Alpha = 240;

		if(PlayerOwner.Helmet != None && PlayerOwner.Helmet.bBlinkSquad)
			Alpha = Pulse;

		SetIconColor(C, 255, 255, 255, Alpha, bTint);
		C.SetPos((75 + X) * SX, (Base + 10) * SY);
		C.DrawTile(SquadIcons, 43 * SX, 40 * SY, 148, 354, 44, 42);
	}

	// Order icon in the color of the health level, red and blinking while the member is down
	Alpha = 200;

	if(MarkerState == 1)
		Alpha = Pulse;

	if(P.bIncapacitated || P.Health <= 0)
		SetIconColor(C, 255, 73, 43, Pulse, bTint);
	else if(P.HealthLevel == HL_Green)
		SetIconColor(C, 81, 213, 67, Alpha, bTint);
	else if(P.HealthLevel == HL_Yellow)
		SetIconColor(C, 255, 251, 44, Alpha, bTint);
	else if(P.HealthLevel == HL_Orange)
		SetIconColor(C, 246, 139, 31, Alpha, bTint);
	else
		SetIconColor(C, 255, 73, 43, Alpha, bTint);

	C.SetPos((87 + X) * SX, (Base + 21) * SY);
	C.DrawTile(SquadIcons, 20 * SX, 20 * SY, 229 - 27 * IconX, 485 - 27 * IconY, 25, 25);

	// Number: the helmet writes GetHudDescription() with OrbitBold15 at (81, Base - 16), scaled to the screen. Script text can't be
	// scaled, so the digits are drawn from the font's page texture, glyph by glyph (DrawNumber)
	if(P.EndTalkTime > T || bTarget)
		SetIconColor(C, 255, 255, 255, 200, bTint);
	else
		SetIconColor(C, 164, 200, 208, 200, bTint);

	DrawNumber(C, P.GetHudDescription(), int((81 + X) * SX), int((Base - 16) * SY), SX, SY);

	if(MarkerState >= 2)
		DrawTimerRing(C, 97 + X, Base + 31, SX, SY, (MarkerState - 2) / 12.0, bTint);
	else
		DrawDirectionArrow(C, P, X, Base, SX, SY, bTint);

	// Corners blinking while the member talks
	if(P.EndTalkTime > T)
	{
		SetIconColor(C, 255, 255, 255, (Sin(30 * T) + 1) * 127, bTint);
		C.SetPos((78 + X) * SX, (Base + 11) * SY);
		C.DrawTile(SquadIcons, 8 * SX, 8 * SY, 177, 447, 8, 8);
		C.SetPos((109 + X) * SX, (Base + 11) * SY);
		C.DrawTile(SquadIcons, 8 * SX, 8 * SY, 185, 447, -8, 8);
		C.SetPos((109 + X) * SX, (Base + 44) * SY);
		C.DrawTile(SquadIcons, 8 * SX, 8 * SY, 185, 455, -8, -8);
		C.SetPos((78 + X) * SX, (Base + 44) * SY);
		C.DrawTile(SquadIcons, 8 * SX, 8 * SY, 177, 455, 8, -8);
	}
}

/*
 * Like FCanvasUtil::DrawString with OrbitBold15: each character is its rectangle of the font's page texture, stretched with the
 * screen. The rectangles of the digits were read from OrbitFonts.utx (OrbitBold15: StartV 1, height 27, no kerning).
 */
simulated function DrawNumber(Canvas C, string Text, float X, float Y, float SX, float SY)
{
	local int i, Digit;

	if(NumberFont == None)
		NumberFont = Texture(DynamicLoadObject("OrbitFonts.OrbitBold15_PageA", class'Texture'));

	if(NumberFont == None)
		return;

	for(i = 0; i < Len(Text); i = i + 1)
	{
		Digit = Asc(Mid(Text, i, 1)) - 48;

		if(Digit < 0 || Digit > 9)
			continue;

		C.SetPos(X, Y);
		C.DrawTile(NumberFont, DigitWidths[Digit] * SX, 27 * SY, DigitStarts[Digit], 1, DigitWidths[Digit], 27);
		X += DigitWidths[Digit] * SX;
	}
}

// Test overlay: magenta instead of the real colors, so it can be told apart from the helmet's icons
simulated function SetIconColor(Canvas C, byte R, byte G, byte B, byte A, bool bTint)
{
	if(bTint)
		C.SetDrawColor(255, 0, 255, 160);
	else
		C.SetDrawColor(R, G, B, A);
}

/*
 * Like the helmet: a small triangle on a circle around the order icon points to where the member is, seen from the player
 * (up = ahead). The texture has it pointing up right, so it is turned 45 degrees less. The 10 pixels down are in the helmet's code
 * too, unscaled.
 */
simulated function DrawDirectionArrow(Canvas C, Pawn P, float X, int Base, float SX, float SY, bool bTint)
{
	local vector Dir;
	local rotator ViewRotation;
	local int Yaw;
	local float Angle;

	Dir = P.Location - PlayerOwner.Pawn.Location;

	if(PlayerOwner.Pawn.Controller != None)
		ViewRotation = PlayerOwner.Pawn.Controller.Rotation;
	else
		ViewRotation = PlayerOwner.Pawn.Rotation;

	Yaw = rotator(Dir).Yaw - ViewRotation.Yaw;
	Angle = Yaw * Pi / 32768.0;

	if(P.HealthLevel == HL_Red)
		SetIconColor(C, 255, 255, 255, 55 + 200 * Sin(5 * Level.TimeSeconds), bTint);
	else
		SetIconColor(C, 255, 255, 255, 170, bTint);

	C.SetPos((97 + X + 10 * Sin(Angle)) * SX, (Base + 21 - 10 * Cos(Angle)) * SY + 10);
	C.DrawRotatedTile(Yaw + 8191, SquadIcons, 9 * SX, 9 * SY, 189, 447, 8, 9);
}

/*
 * UHelmet::DrawTimerRing: the whole ring in the empty color, then the filled twelfths. The texture is cut into 4x4 cells,
 * each is drawn at its own place.
 */
simulated function DrawTimerRing(Canvas C, float CenterX, float CenterY, float SX, float SY, float Ratio, bool bTint)
{
	local float W, H, CW, CH;
	local int i, Col, Row;

	if(EventTimer == None)
		return;

	W = EventTimer.USize * 0.3;
	H = EventTimer.VSize * 0.3;
	CW = W / 4;
	CH = H / 4;

	SetIconColor(C, 200, 240, 255, 92, bTint);
	C.SetPos((CenterX - W / 2) * SX, (CenterY - H / 2) * SY);
	C.DrawTile(EventTimer, W * SX, H * SY, 0, 0, EventTimer.USize, EventTimer.VSize);

	SetIconColor(C, 200, 240, 255, 255, bTint);

	for(i = 0; i < 16; i = i + 1)
	{
		if(Ratio < 1 && Ratio < RingSteps[i] / 12.0)
			continue;

		Col = RingCells[i] % 4;
		Row = RingCells[i] / 4;
		C.SetPos((CenterX - W / 2 + Col * CW) * SX, (CenterY - H / 2 + Row * CH) * SY);
		C.DrawTile(EventTimer, CW * SX, CH * SY, Col * EventTimer.USize / 4, Row * EventTimer.VSize / 4, EventTimer.USize / 4, EventTimer.VSize / 4);
	}
}

defaultproperties
{
	SquadIcons=Texture'HUDTextures.Icons.CloneVisorIcons'
	EventTimer=Texture'HUDTextures.Reticles.HUD_EventTimer'
	DigitStarts(0)=180
	DigitWidths(0)=16
	DigitStarts(1)=197
	DigitWidths(1)=11
	DigitStarts(2)=209
	DigitWidths(2)=13
	DigitStarts(3)=223
	DigitWidths(3)=15
	DigitStarts(4)=239
	DigitWidths(4)=17
	DigitStarts(5)=257
	DigitWidths(5)=13
	DigitStarts(6)=271
	DigitWidths(6)=16
	DigitStarts(7)=288
	DigitWidths(7)=13
	DigitStarts(8)=302
	DigitWidths(8)=16
	DigitStarts(9)=319
	DigitWidths(9)=16
	RingCells(0)=1
	RingCells(1)=0
	RingCells(2)=5
	RingCells(3)=4
	RingCells(4)=8
	RingCells(5)=12
	RingCells(6)=9
	RingCells(7)=13
	RingCells(8)=14
	RingCells(9)=15
	RingCells(10)=10
	RingCells(11)=11
	RingCells(12)=7
	RingCells(13)=3
	RingCells(14)=6
	RingCells(15)=2
	RingSteps(0)=1
	RingSteps(1)=2
	RingSteps(2)=2
	RingSteps(3)=3
	RingSteps(4)=4
	RingSteps(5)=5
	RingSteps(6)=5
	RingSteps(7)=6
	RingSteps(8)=7
	RingSteps(9)=8
	RingSteps(10)=8
	RingSteps(11)=9
	RingSteps(12)=10
	RingSteps(13)=11
	RingSteps(14)=11
	RingSteps(15)=12
}
