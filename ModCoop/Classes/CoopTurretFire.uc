class CoopTurretFire extends Object;

/*
 * CoopTurretFire
 * Purpose: shots of a client on a turret start at the turret's muzzle and go where the client's crosshair is. The first person
 *   weapon of a turret shoots from its own bone or the view; on the server it stands at the turret's camera, so the shots started
 *   above the barrel and missed what the crosshair was on (GEO_03C, GEO_04A, session 2026-11-01). The ray of the crosshair is built
 *   like the client's view (CoopPlayer.PlayerManningTurret), not from the turret's camera bone: the client looks from elsewhere (73
 *   units higher on the gunship cannon) and the fire animation rocks the bones. One instance per CalculateFire
 *   function (Weapon, EWebTurret, GunshipTurret, MissileTurret, ATTEWalkerTurret; WookieeTurret fires in its own TurretFire).
 * Entry points: Init (CoopExtension.Init), TurretCalculateFire (replaces CalculateFire, server).
 * Logging: none per shot (the test `turret` logs the projectiles and the target's health).
 * State: Override (the hook of this function).
 * Known limitations: the fire animation of the turret is played on the server only, other clients don't see it.
 */

const MIN_EFFECT_INTERVAL = 0.3;

var FunctionOverride Override;

function Init(class<Weapon> WeaponClass)
{
	Override = new class'FunctionOverride';
	Override.Init(WeaponClass, 'CalculateFire', self, 'TurretCalculateFire');
}

// Server. Everything else (rifles, the host's turret) goes on to the original
function TurretCalculateFire()
{
	local Weapon W;
	local Pawn P;
	local Turret T;
	local vector Start, CameraLocation, End, HitLocation, HitNormal;
	local rotator Aim;
	local int Range;

	W = Weapon(Override.CurrentSelf);
	P = Pawn(W.Owner);

	if(P != None && W.WeaponType == WT_Turret && CoopPlayer(P.Controller) != None && Viewport(CoopPlayer(P.Controller).Player) == None)
		T = Turret(P.Controller.Machine);

	if(T == None || T.Gunner != P || W.AmmoType == None)
	{
		W.CalculateFire();
		return;
	}

	Start = T.GetMuzzleLocation();
	CameraLocation = T.Location + P.EyePosition();
	CameraLocation.Z += T.TurretHeight;
	Range = W.AmmoType.Range;

	if(Range <= 0)
		Range = 10000;

	End = CameraLocation + vector(class'CoopPlayer'.static.TurretView(T, T.Yaw, T.Pitch)) * Range;

	// Trace ignores the gunner, the turret of a player has no collision
	if(P.Trace(HitLocation, HitNormal, End, CameraLocation, true) != None)
		End = HitLocation;

	Aim = rotator(End - Start);
	W.AmmoType.DoFire(Start, Aim);

	if(LaserWeapon(W) != None)
		AlignBeam(LaserWeapon(W), P, T, Start, Aim);


	// A laser "fires" every frame: only once in a while or the effects pile up and the animations start over without ever playing
	if(P.Level.TimeSeconds - T.LastFireTime >= MIN_EFFECT_INTERVAL)
	{
		T.LastFireTime = P.Level.TimeSeconds;
		T.DoMuzzleEffect(T.GetMuzzleBone(), Start);
		T.PlayAnim('Fire',,,,4);
		P.PlayAnim(T.PawnFireAnim(), 'Fire',,,3);
	}
}

/*
 * What the host sees of a laser: LaserWeaponAmmo hangs its beam effect on the gunner's hand bone, it pointed at the sky (GEO_04A, session
 * 2026-11-01). It is moved to the turret's muzzle after every shot (the ammo attaches it again each time), along the shot.
 * The mesh beam of the weapon is attached to a bone of the first person weapon no one sees on the server. The weapon's place on the
 * server isn't sent to anyone, so the weapon is moved until that beam starts at the muzzle and points along the shot. Measured from
 * the beam itself: the bone's offset isn't known here and it converges in a few shots.
 */
function AlignBeam(LaserWeapon W, Pawn P, Turret T, vector Start, rotator Aim)
{
	local Emitter Tracer;
	local rotator R;

	if(LaserWeaponAmmo(W.AmmoType) != None)
		Tracer = LaserWeaponAmmo(W.AmmoType).RemoteTracerEmitter;

	if(Tracer != None)
	{
		P.DetachFromBone(Tracer);
		T.AttachToBone(Tracer, T.GetMuzzleBone());
		Tracer.SetRelativeLocation(vect(0,0,0));
		Tracer.SetRelativeRotation(Aim - T.GetBoneRotation(T.GetMuzzleBone()));
	}

	if(W.Laser == None)
		return;

	W.SetLocation(W.Location + Start - W.Laser.Location);
	R = W.Rotation;
	R.Pitch += Aim.Pitch - W.Laser.Rotation.Pitch;
	R.Yaw += Aim.Yaw - W.Laser.Rotation.Yaw;
	W.SetRotation(R);
}
