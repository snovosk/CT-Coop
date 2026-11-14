class CoopCheckpointReturn extends Object;

/*
 * CoopCheckpointReturn
 * Purpose: what every player had at a level's checkpoint: place, health, shields, weapons and ammunition. The checkpoint itself is a real
 *   save of the level (CoopGame.SaveCheckpoint, LoadSavedCheckpoint), this puts the clients back after it is loaded (Persist, TakePersisted,
 *   RestoreRejoined). Without the save (it failed, or another map) Load is the fallback: everybody moved back, the world not rewound.
 * Entry points: Setup (CoopGame.InitGame), Remember and Persist (CoopGame.SaveCheckpoint), TakePersisted (CoopGame.AfterSaveLoaded), RestoreRejoined
 *   (CoopGame.Timer), HasPoint and Load
 *   (CoopGame.CoopLoadCheckpoint for the menu, CoopGame.CheckSquadDown when the whole squad is down, CoopGame.CheckHostDown when the host wasn't revived).
 * Logging: "CoopGame: checkpoint".
 * State: Game, Saved, bHasPoint. Written on the server only.
 * Known limitations: a player behind a door that has closed since the checkpoint stays there. A client manning a turret isn't moved.
 *   A dead host gets a new pawn (CoopGame.CheckSquadDown): a level script holding on to the old one isn't handled.
 */

// Levels save a checkpoint as they start: going back there without a rewind would be worse than restarting the level
const START_CHECKPOINT_TIME = 20.0;
const MOVE_PASSES = 2;

struct SavedPlayer
{
	var PlayerController PC;
	var vector Loc;
	var rotator Rot;
	var float Health, Shields;
	var bool bMoved;
	var string PlayerName;  // A client of a loaded save comes back with a new controller, found by name (RestoreRejoined)
	var bool bWaiting;      // Kept from a loaded save until that client is back
};

// What a player carried at the checkpoint: a weapon with its clip, or an ammunition with its amount. Player is the index in Saved
struct SavedItem
{
	var int Player;
	var class<Inventory> ItemClass;
	var int Amount;
};

var CoopGame Game;
var array<SavedPlayer> Saved;
var array<SavedItem> Items;
var bool bHasPoint;

/*
 * A new object takes the class's defaults, where Persist keeps the players of the last checkpoint for a load. Only a loaded save may use them:
 * on the next level they were the places of the old map, and the first client "came back" there (RAS_03C checkpoint, then RAS_04A: the client
 * was put over nothing, fell 10000 units and lay incapacitated, the user's game 2026-11-14).
 */
function Setup(CoopGame G)
{
	Game = G;

	if(class'CoopConfig'.default.bLoadingSave)
		return;

	if(default.Saved.Length > 0)
		Log("CoopGame: checkpoint save of another level dropped (" $ default.Saved.Length $ " players)");

	default.Saved.Length = 0;
	default.Items.Length = 0;
	Saved.Length = 0;
	Items.Length = 0;
}

function bool HasPoint()
{
	return bHasPoint;
}

function Remember()
{
	if(Game.Level.TimeSeconds < START_CHECKPOINT_TIME)
	{
		Log("CoopGame: checkpoint at the start of the level ignored, t=" $ Game.Level.TimeSeconds);
		return;
	}

	RememberAll();
}

// Every player now, for a checkpoint or a save slot (CoopGame.SaveToSlot)
function RememberAll()
{
	local Controller C;
	local PlayerController PC;
	local int i;

	Saved.Length = 0;
	Items.Length = 0;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		PC = PlayerController(C);

		if(PC == None || PC.Pawn == None || PC.Pawn.Health <= 0 || PC.Pawn.bIncapacitated)
			continue;

		i = Saved.Length;
		Saved.Length = i + 1;
		Saved[i].PC = PC;
		Saved[i].Loc = PC.Pawn.Location;
		Saved[i].Rot = PC.Rotation;
		Saved[i].Health = PC.Pawn.Health;
		Saved[i].Shields = PC.Pawn.Shields;
		Saved[i].PlayerName = PC.PlayerReplicationInfo.PlayerName;
		RememberItems(i, PC.Pawn);
		Log("CoopGame: checkpoint saved " $ PC.PlayerReplicationInfo.PlayerName $ " at " $ Saved[i].Loc $ " health " $ Saved[i].Health $ " shields " $ Saved[i].Shields $ " items " $ ItemsText(i));
	}

	bHasPoint = Saved.Length > 0;
}

/*
 * The checkpoint save (CoopGame.SaveCheckpoint) has the clients' commandos, but loading it drops their controllers and the engine logs them
 * out before any script runs. What every player had at the checkpoint is kept in the class's defaults, which live through the load, and taken
 * back by the new CoopCheckpointReturn of the loaded level (TakePersisted). A client back with a new commando gets it by its name
 * (RestoreRejoined). No actor references in the defaults: they would outlive their level.
 */
function Persist()
{
	local int i;

	default.Saved = Saved;
	default.Items = Items;

	for(i = 0; i < default.Saved.Length; ++i)
	{
		default.Saved[i].PC = None;
		default.Saved[i].bWaiting = true;
	}
}

function TakePersisted(string HostName)
{
	local int i;

	Saved = default.Saved;
	Items = default.Items;

	// The host comes back in the save with his own commando
	for(i = 0; i < Saved.Length; ++i)
	{
		if(Saved[i].PlayerName == HostName)
			Saved[i].bWaiting = false;
		else
			Log("CoopGame: checkpoint save: " $ Saved[i].PlayerName $ " will be back at " $ Saved[i].Loc $ " health " $ Saved[i].Health $ " items " $ ItemsText(i));
	}
}

function bool HasWaiting()
{
	local int i;

	for(i = 0; i < Saved.Length; ++i)
	{
		if(Saved[i].bWaiting)
			return true;
	}

	return false;
}

// See RememberLeftPawn: the client's new commando goes to its place in the save, with what it had
function RestoreRejoined(PlayerController PC)
{
	local int i;

	if(PC == None || PC.Pawn == None || PC.Pawn.Health <= 0 || PC.PlayerReplicationInfo == None)
		return;

	for(i = 0; i < Saved.Length; ++i)
	{
		if(!Saved[i].bWaiting || Saved[i].PlayerName != PC.PlayerReplicationInfo.PlayerName)
			continue;

		Saved[i].bWaiting = false;
		Saved[i].PC = PC;
		Game.ResetMoveClock(PC, "back in the save");
		Log("CoopGame: checkpoint save: " $ Saved[i].PlayerName $ " is back, moved: " $ MoveBack(i));
		return;
	}
}

// A player of RememberAll as a line of a save slot (CoopSaveSlots.Field): name|member|health|shields|place|yaw|items
function string EncodePlayer(int Player)
{
	local string Member, ItemText;
	local Pawn P;
	local int i;

	P = Saved[Player].PC.Pawn;

	if(P != None && P.IsA('CloneCommando') && CoopCommando(P) == None && !Game.IsHost(Saved[Player].PC))
		Member = string(P.Class);

	for(i = 0; i < Items.Length; ++i)
	{
		if(Items[i].Player == Player)
			ItemText = ItemText $ string(Items[i].ItemClass) $ "=" $ Items[i].Amount $ ";";
	}

	return class'CoopSaveSlots'.static.CleanName(Saved[Player].PlayerName) $ "|" $ Member $ "|" $ int(Saved[Player].Health) $ "|" $ int(Saved[Player].Shields) $ "|" $
	       int(Saved[Player].Loc.X) $ "," $ int(Saved[Player].Loc.Y) $ "," $ int(Saved[Player].Loc.Z) $ "|" $ Saved[Player].Rot.Yaw $ "|" $ ItemText;
}

/*
 * The players of a save slot into the defaults, like Persist does for the checkpoint save: the loaded level's CoopCheckpointReturn takes
 * them (TakePersisted) and each client gets its own back when it is there (RestoreRejoined).
 */
static function PersistSlot(int Slot)
{
	local int i, n, k;
	local string Line, ItemText, Entry, Place;
	local class<Inventory> ItemClass;

	default.Saved.Length = 0;
	default.Items.Length = 0;

	for(i = 0; i < class'CoopSaveSlots'.static.NumPlayers(Slot); ++i)
	{
		Line = class'CoopSaveSlots'.static.PlayerLine(Slot, i);
		n = default.Saved.Length;
		default.Saved.Length = n + 1;
		default.Saved[n].PlayerName = class'CoopSaveSlots'.static.Field(Line, 0);
		default.Saved[n].Health = float(class'CoopSaveSlots'.static.Field(Line, 2));
		default.Saved[n].Shields = float(class'CoopSaveSlots'.static.Field(Line, 3));
		Place = class'CoopSaveSlots'.static.Field(Line, 4);
		default.Saved[n].Loc.X = float(Left(Place, InStr(Place, ",")));
		Place = Mid(Place, InStr(Place, ",") + 1);
		default.Saved[n].Loc.Y = float(Left(Place, InStr(Place, ",")));
		default.Saved[n].Loc.Z = float(Mid(Place, InStr(Place, ",") + 1));
		default.Saved[n].Rot.Yaw = int(class'CoopSaveSlots'.static.Field(Line, 5));
		default.Saved[n].bWaiting = true;
		ItemText = class'CoopSaveSlots'.static.Field(Line, 6);

		while(InStr(ItemText, ";") != -1)
		{
			Entry = Left(ItemText, InStr(ItemText, ";"));
			ItemText = Mid(ItemText, InStr(ItemText, ";") + 1);
			ItemClass = class<Inventory>(DynamicLoadObject(Left(Entry, InStr(Entry, "=")), class'Class', true));

			if(ItemClass == None)
				continue;

			k = default.Items.Length;
			default.Items.Length = k + 1;
			default.Items[k].Player = n;
			default.Items[k].ItemClass = ItemClass;
			default.Items[k].Amount = int(Mid(Entry, InStr(Entry, "=") + 1));
		}
	}
}

// Turret weapons belong to the turret, not to the player
function RememberItems(int Player, Pawn P)
{
	local Inventory Inv;
	local int i;

	for(Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		if(Weapon(Inv) != None && Weapon(Inv).WeaponType == WT_Turret)
			continue;

		if(Weapon(Inv) == None && Ammunition(Inv) == None)
			continue;

		i = Items.Length;
		Items.Length = i + 1;
		Items[i].Player = Player;
		Items[i].ItemClass = Inv.Class;

		if(Weapon(Inv) != None)
			Items[i].Amount = Weapon(Inv).ReloadCount;
		else
			Items[i].Amount = Ammunition(Inv).AmmoAmount;
	}
}

function string ItemsText(int Player)
{
	local string Text;
	local int i;

	for(i = 0; i < Items.Length; ++i)
	{
		if(Items[i].Player == Player)
			Text = Text $ " " $ Items[i].ItemClass.Name $ "=" $ Items[i].Amount;
	}

	return Text;
}

function int FindItem(int Player, class<Inventory> ItemClass)
{
	local int i;

	for(i = 0; i < Items.Length; ++i)
	{
		if(Items[i].Player == Player && Items[i].ItemClass == ItemClass)
			return i;
	}

	return -1;
}

// Everybody gets up. A player without a saved state (joined later, or down at the checkpoint) keeps what the revive gives
function RestorePlayer(PlayerController PC)
{
	local Pawn P;

	P = PC.Pawn;

	if(P == None || P.bDeleteMe)
		return;

	if(P.bIncapacitated)
	{
		// GotoState skips the get-up animation: its end would set half health a few seconds after the move
		P.Revive();
		P.GotoState('');
	}

	if(P.Health > 0)
		P.ChangeAnimation();
}

/*
 * Health, shields, weapons and ammunition as they were at the checkpoint, so that loading it can't be used to refill. What was picked up
 * since then stays in the inventory, empty.
 */
function RestoreState(int Player)
{
	local Pawn P;
	local Inventory Inv;
	local int i;

	P = Saved[Player].PC.Pawn;

	if(P == None || P.bDeleteMe || P.Health <= 0)
		return;

	P.Health = Saved[Player].Health;
	P.Shields = Saved[Player].Shields;

	// A host back with a new pawn has only the default equipment
	for(i = 0; i < Items.Length; ++i)
	{
		if(Items[i].Player == Player && class<Weapon>(Items[i].ItemClass) != None && P.FindInventoryType(Items[i].ItemClass) == None)
			P.CreateInventory(string(Items[i].ItemClass));
	}

	for(Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		if(Weapon(Inv) != None && Weapon(Inv).WeaponType == WT_Turret)
			continue;

		i = FindItem(Player, Inv.Class);

		if(Ammunition(Inv) != None)
		{
			if(i >= 0)
				Ammunition(Inv).AmmoAmount = Items[i].Amount;
			else
				Ammunition(Inv).AmmoAmount = 0;
		}
		else if(Weapon(Inv) != None)
		{
			if(i >= 0)
				Weapon(Inv).ReloadCount = Items[i].Amount;
			else
				Weapon(Inv).ReloadCount = 0;
		}
	}
}

function bool MoveBack(int i)
{
	local Pawn P;
	local vector Spot;

	P = Saved[i].PC.Pawn;

	if(P == None || P.bDeleteMe || P.Health <= 0)
		return false;

	// RAS_02C, 2026-11-10: the host's spot was taken (a squad member stood there) and the level restarted. The free place nearest to it then
	if(!P.SetLocation(Saved[i].Loc))
	{
		if(!Game.FindSpawnLocation(Saved[i].Loc, Saved[i].Rot, Spot) || !P.SetLocation(Spot))
			return false;

		Log("CoopGame: checkpoint spot of " $ Saved[i].PC.PlayerReplicationInfo.PlayerName $ " taken, next to it at " $ Spot);
	}

	P.Velocity = vect(0,0,0);
	P.Acceleration = vect(0,0,0);
	P.SetPhysics(PHYS_Falling);
	Saved[i].PC.ClientSetLocation(P.Location, Saved[i].Rot);
	Saved[i].bMoved = true;
	RestoreState(i);
	Log("CoopGame: checkpoint moved " $ Saved[i].PC.PlayerReplicationInfo.PlayerName $ " to " $ P.Location $ " health " $ P.Health);

	return true;
}

// A dead host gets a new pawn at a PlayerStart, which a client may be standing on: the clients go back first
function MoveClientsBack(PlayerController Host)
{
	local Controller C;
	local int i;

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) != None && C != Host)
			RestorePlayer(PlayerController(C));
	}

	for(i = 0; i < Saved.Length; ++i)
	{
		if(Saved[i].PC != None && Saved[i].PC != Host)
			MoveBack(i);
	}
}

// False: nothing to go back to or the host can't be moved, the caller restarts the level
function bool Load()
{
	local PlayerController Host;
	local Controller C;
	local CoopPlayer CP;
	local int i, Pass;
	local bool bHostMoved;

	Host = Game.GetHost();

	if(!bHasPoint || Host == None || Host.Pawn == None || Host.Pawn.bDeleteMe || Host.bBriefing || (Host.Pawn.Health <= 0 && !Host.Pawn.bIncapacitated))
	{
		Log("CoopGame: checkpoint can't be loaded: saved=" $ bHasPoint $ " host=" $ Host);
		return false;
	}

	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		if(PlayerController(C) != None)
			RestorePlayer(PlayerController(C));
	}

	for(i = 0; i < Saved.Length; ++i)
		Saved[i].bMoved = false;

	// A player can stand on another's spot until that one has been moved too
	for(Pass = 0; Pass < MOVE_PASSES; ++Pass)
	{
		for(i = 0; i < Saved.Length; ++i)
		{
			if(Saved[i].PC == None || Saved[i].bMoved)
				continue;

			CP = CoopPlayer(Saved[i].PC);

			if(CP != None && (CP.Machine != None || CP.IsInState('PlayerManningTurret')))
				continue;

			MoveBack(i);

			if(Saved[i].PC == Host && Saved[i].bMoved)
				bHostMoved = true;
		}
	}

	if(!bHostMoved)
	{
		Log("CoopGame: checkpoint: the host couldn't be moved back");
		return false;
	}

	// Players who joined after the checkpoint, or were down at it
	for(C = Game.Level.ControllerList; C != None; C = C.nextController)
	{
		CP = CoopPlayer(C);

		if(CP != None && !Game.IsHost(CP) && !WasSaved(CP) && Game.TeleportToHost(CP))
			Log("CoopGame: checkpoint: " $ CP.PlayerReplicationInfo.PlayerName $ " had no spot, moved to the host");
	}

	Game.Broadcast(Game, "Back to the checkpoint.");

	return true;
}

function bool WasSaved(PlayerController PC)
{
	local int i;

	for(i = 0; i < Saved.Length; ++i)
	{
		if(Saved[i].PC == PC)
			return true;
	}

	return false;
}
