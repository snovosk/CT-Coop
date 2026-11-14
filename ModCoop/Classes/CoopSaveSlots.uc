class CoopSaveSlots extends Object;

/*
 * CoopSaveSlots
 * Purpose: the host's saves of a coop game, 5 slots (the user's choice, 2026-11-11). A slot is a real save of the level, Save\CoopSave<n>
 *   (CoopNative.EngineSaveGame), and its record in Save\ModCoopSaves.ini: map, time, the build of the mod, and every player by name with the
 *   squad member it played and what it had (place, health, shields, weapons, ammunition, see CoopCheckpointReturn).
 * Entry points: CoopGame.SaveToSlot writes, CoopLobby reads (the host picks a slot as the level, the players get their members back),
 *   CoopGame.LoadSlotFromLobby loads, CoopSaveMenu shows the slots.
 * Logging: "CoopGame: save slot".
 * State: only the files.
 * Known limitations: a save of another build of the mod can't be loaded (it holds the mod's objects): IsCompatible compares the GUID of
 *   ModCoop.u. Players are known by their name (the user's choice): a renamed player counts as new.
 */

const NUM_SLOTS = 5;
const INI_NAME = "ModCoopSaves.ini";

static function int NumSlots()
{
	return NUM_SLOTS;
}

static function string SaveName(int Slot)
{
	return "CoopSave" $ Slot;
}

static function string Read(int Slot, string Key)
{
	return class'CoopNative'.static.ReadSavedString(INI_NAME, "Slot" $ Slot, Key);
}

static function Write(int Slot, string Key, string Value)
{
	class'CoopNative'.static.WriteSavedString(INI_NAME, "Slot" $ Slot, Key, Value);
}

static function bool IsUsed(int Slot)
{
	return Slot >= 1 && Slot <= NUM_SLOTS && Read(Slot, "Map") != "";
}

static function bool IsCompatible(int Slot)
{
	return IsUsed(Slot) && Read(Slot, "Build") != "" && Read(Slot, "Build") == class'CoopNative'.static.ModPackageGuid();
}

static function string TwoDigits(int Value)
{
	if(Value < 10)
		return "0" $ Value;

	return string(Value);
}

// The name of a save, SAVE <level> <date>:<time> (the user's format, 2026-11-11), e.g. "SAVE RAS_01B 11.11:21:04". In the lobby's save row,
// the host menu and the save menu. The map is the word after "SAVE " (MapOfItem): map names have no spaces
static function string Describe(int Slot)
{
	if(!IsUsed(Slot))
		return "SLOT " $ Slot $ ": EMPTY";

	if(!IsCompatible(Slot))
		return "SAVE " $ Read(Slot, "Map") $ " " $ Read(Slot, "Time") $ " (OTHER MOD BUILD)";

	return "SAVE " $ Read(Slot, "Map") $ " " $ Read(Slot, "Time");
}

// The slot of a save's name made by Describe, 0 for a plain level
static function int SlotFromItem(string Item)
{
	local int i;

	if(Left(Item, 5) != "SAVE ")
		return 0;

	for(i = 1; i <= NUM_SLOTS; ++i)
	{
		if(IsUsed(i) && Describe(i) == Item)
			return i;
	}

	return 0;
}

// The map of a save's name, "" for a plain level
static function string MapOfItem(string Item)
{
	if(Left(Item, 5) != "SAVE ")
		return "";

	Item = Mid(Item, 5);

	if(InStr(Item, " ") != -1)
		Item = Left(Item, InStr(Item, " "));

	return Item;
}

static function string TimeText(LevelInfo Level)
{
	return TwoDigits(Level.Day) $ "." $ TwoDigits(Level.Month) $ ":" $ TwoDigits(Level.Hour) $ ":" $ TwoDigits(Level.Minute);
}

static function int NumPlayers(int Slot)
{
	return int(Read(Slot, "Players"));
}

static function string PlayerLine(int Slot, int i)
{
	return Read(Slot, "Player" $ i);
}

// Field n of a player line: 0 name, 1 squad member class, 2 health, 3 shields, 4 place, 5 yaw, 6 items
static function string Field(string Line, int n)
{
	local int i;

	for(i = 0; i < n; ++i)
	{
		if(InStr(Line, "|") == -1)
			return "";

		Line = Mid(Line, InStr(Line, "|") + 1);
	}

	if(InStr(Line, "|") != -1)
		Line = Left(Line, InStr(Line, "|"));

	return Line;
}

// The squad member the player played in this save, "" if none or not in it
static function string SavedMember(int Slot, string PlayerName)
{
	local int i;
	local string Line;

	for(i = 0; i < NumPlayers(Slot); ++i)
	{
		Line = PlayerLine(Slot, i);

		if(Field(Line, 0) == PlayerName)
			return Field(Line, 1);
	}

	return "";
}

static function bool HasPlayer(int Slot, string PlayerName)
{
	local int i;

	for(i = 0; i < NumPlayers(Slot); ++i)
	{
		if(Field(PlayerLine(Slot, i), 0) == PlayerName)
			return true;
	}

	return false;
}

// Names can't hold the separators of the record
static function string CleanName(string PlayerName)
{
	local string Result, C;
	local int i;

	for(i = 0; i < Len(PlayerName); ++i)
	{
		C = Mid(PlayerName, i, 1);

		if(C == "|" || C == ";" || C == "=")
			C = "_";

		Result = Result $ C;
	}

	return Result;
}
