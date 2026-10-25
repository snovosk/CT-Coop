class CoopHUD extends CTHUD;

/*
 * CoopHUD
 * The helmet draws the squad icons only for AI squad members. Clients have no squad (it isn't replicated) and the squad members
 * played by clients are not in the AI squad of the host (see CoopGame.DetachClientMembers), so their icons were missing. They are
 * drawn here like the helmet does it: number, frame and status (healthy, wounded, critical, incapacitated) in the slot of the member.
 * Clients see every other Delta member (the host, 38, has no icon), the host sees the members played by clients.
 */

var Texture SquadIcons;  // HUDTextures.Icons.CloneVisorIcons, see Squad.MemberInfo

simulated function PostRender(Canvas C)
{
	Super.PostRender(C);

	if(!bHideHUD && PlayerOwner != None && PlayerOwner.Pawn != None && (PlayerOwner.Helmet == None || PlayerOwner.Helmet.bDraw) &&
	   !PlayerOwner.bBehindView)
		DrawCoopSquad(C);
}

simulated function DrawCoopSquad(Canvas C)
{
	local Pawn P;
	local int Slot;
	local float ScaleX, ScaleY, X, Y;

	// The helmet is laid out for 800x600 and stretched to the screen: x and widths with the width, y and heights with the height.
	// The HUD is projected onto the curved visor, so these were fitted on screenshots at 800x600 and 1280x720 against the
	// helmet's own icons: first frame at 79,449, 40.4 apart
	ScaleX = C.ClipX / 800.0;
	ScaleY = C.ClipY / 600.0;

	foreach DynamicActors(class'Pawn', P)
	{
		if(P == PlayerOwner.Pawn || P.bDeleteMe || (P.Health <= 0 && !P.bIncapacitated))
			continue;

		if(P.IsA('Commando07Delta'))
			Slot = 0;
		else if(P.IsA('Commando40Delta'))
			Slot = 1;
		else if(P.IsA('Commando62Delta'))
			Slot = 2;
		else
			continue;

		// The host's helmet already shows the AI members; clients only show members that joined the squad (not e.g. Scorch on GEO_01A
		// before his scene)
		if(Level.NetMode != NM_Client && PlayerController(P.Controller) == None)
			continue;

		if(Level.NetMode == NM_Client && (CoopPlayer(PlayerOwner) == None || !CoopPlayer(PlayerOwner).IsSquadIconMember(P)))
			continue;

		X = (79 + Slot * 40.4) * ScaleX;
		Y = 449 * ScaleY;
		DrawSquadIcon(C, P, X, Y, ScaleX, ScaleY);
	}
}

simulated function DrawSquadIcon(Canvas C, Pawn P, float X, float Y, float ScaleX, float ScaleY)
{
	local float HealthFraction;
	local int IconX, IconY, LabelY;

	C.Style = ERenderStyle.STY_Alpha;

	// Frame
	C.SetDrawColor(255, 255, 255, 200);
	C.SetPos(X, Y);
	C.DrawTile(SquadIcons, 38 * ScaleX, 36 * ScaleY, 145, 397, 47, 45);

	// Status: the icon of the order (cell 1,3 counted from the bottom right) or the cross while incapacitated (cell 1,1)
	IconX = 1;
	IconY = 3;
	HealthFraction = P.Health / FMax(1, P.default.Health);

	if(P.bIncapacitated)
	{
		IconY = 1;
		C.SetDrawColor(255, 40, 40, 255);
	}
	else if(HealthFraction > 0.66)
		C.SetDrawColor(60, 230, 60, 255);
	else if(HealthFraction > 0.33)
		C.SetDrawColor(240, 220, 40, 255);
	else
		C.SetDrawColor(255, 60, 40, 255);

	C.SetPos(X + 9 * ScaleX, Y + 7 * ScaleY);
	C.DrawTile(SquadIcons, 18 * ScaleX, 18 * ScaleY, 230 - 27 * IconX, 486 - 27 * IconY, 25, 25);

	DrawDirectionArrow(C, P, X, Y, ScaleX, ScaleY);

	// Number above the frame, from the same texture (62, 40 and 07 below each other)
	if(P.IsA('Commando62Delta'))
		LabelY = 104;
	else if(P.IsA('Commando40Delta'))
		LabelY = 120;
	else
		LabelY = 136;

	C.SetDrawColor(255, 255, 255, 255);
	C.SetPos(X + 2 * ScaleX, Y - 27 * ScaleY);
	C.DrawTile(SquadIcons, 30 * ScaleX, 19 * ScaleY, 151, LabelY, 23, 15);
}

/*
 * Like the helmet: a small triangle on the frame points to where the squad member is, seen from the player (up = ahead,
 * down = behind). The texture has it pointing down right, it is mirrored for the other directions.
 */
simulated function DrawDirectionArrow(Canvas C, Pawn P, float X, float Y, float ScaleX, float ScaleY)
{
	local vector Dir;
	local rotator ViewRotation;
	local float Angle, S, Co, AX, AY, UL, VL;
	local float U, V;

	Dir = P.Location - PlayerOwner.Pawn.Location;
	Dir.Z = 0;

	if(VSize(Dir) < 1)
		return;

	ViewRotation = PlayerOwner.Rotation;
	Angle = (rotator(Dir).Yaw - ViewRotation.Yaw) * Pi / 32768.0;
	S = Sin(Angle);
	Co = Cos(Angle);

	// On the frame around the center of the icon
	AX = X + (19 + S * 14 - 5) * ScaleX;
	AY = Y + (18 - Co * 13 - 5) * ScaleY;

	U = 175;
	V = 445;
	UL = 11;
	VL = 11;

	// Left of the player: mirrored horizontally; ahead: mirrored vertically
	if(S < 0)
	{
		U += UL;
		UL = -UL;
	}

	if(Co > 0)
	{
		V += VL;
		VL = -VL;
	}

	C.SetDrawColor(255, 255, 255, 255);
	C.SetPos(AX, AY);
	C.DrawTile(SquadIcons, 10 * ScaleX, 10 * ScaleY, U, V, UL, VL);
}

defaultproperties
{
	SquadIcons=Texture'HUDTextures.Icons.CloneVisorIcons'
}
