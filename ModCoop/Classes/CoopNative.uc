class CoopNative extends Object native;

/*
 * CoopNative
 * Engine functionality that is not accessible from UnrealScript.
 */

// Adds a package to the server's package map so that clients can resolve classes from it.
// The change is only made in memory and does not modify System.ini.
native static final function AddServerPackage(string PackageName);
native static final function RemoveServerPackage(string PackageName);
native static final function bool HasServerPackage(string PackageName);

// Returns the command line the game was started with
native static final function string GetCommandLine();

// Seconds since the game started, also running while the game is paused (Level.TimeSeconds stops)
native static final function float GetRealTime();

// Releases all CD keys registered with GameSpy. Required to have a client and a host running on the same PC.
native static final function ReleaseAllCDKeys();

// Changes the connection timeouts of all net drivers and the defaults for new ones. Only in memory, System.ini is not modified.
native static final function SetNetTimeouts(float ConnectionTimeout, float InitialConnectTimeout);

// Changes the bandwidth per client and the server tick rates of all net drivers and the defaults for new ones. Only in memory.
native static final function SetNetRates(int MaxClientRate, int ServerMaxTickRate);

// The game reads mod config files from System but saves them to the save directory (GameData\Save).
// This loads the class defaults from the saved file so settings like the recent addresses persist.
native static final function LoadSavedConfig(class<Object> ConfigClass, string IniName);

// Reads and writes one value of a file in the save directory. The config writer comments out values that were loaded with
// LoadSavedConfig (they were lost after the next start), values written with this are kept.
native static final function string ReadSavedString(string IniName, string Section, string Key);
native static final function WriteSavedString(string IniName, string Section, string Key, string Value);

// Native fixes that are needed to play single player maps as a network client
native static final function InstallClientFixes();

// Sound journal: <log name>-Sounds.log next to the game's log, every PlaySound/PlayOwnedSound/StopSound of this side and the lines given here
native static final function SetSoundLog(bool bEnabled);
native static final function LogSound(string Line);

// Checkpoint saves (CoopGame.SaveCheckpoint): UGameEngine::SaveGame called directly, past the console command's check of the network mode.
// Returns what happened and the files in the save container.
native static final function string EngineSaveGame(string SaveName);

// Research: the level's package as the network announces it (name, file, GUID, counts)
native static final function string LevelPackageText(Actor A);

// Host, after loading a save: the network numbers the save's objects like the clean map, so clients can follow (see ModCoop.cpp)
native static final function string RemapSavedLevel(Actor A, string SaveName);

// GUID of this build of ModCoop.u: saves of another build can't be loaded (CoopSaveSlots)
native static final function string ModPackageGuid();

// The helmet's single player HUD (visor) in a network game, while a coop HUD exists (see ModCoop.cpp). Returns what happened
// HUD: the coop HUD whose DrawVisorSquad draws into the visor's working target
native static final function string SetVisorHUD(bool bOn, optional Object HUD);

// After a save is loaded: the level's URL without the host it was saved with, so the next level change isn't a connect (see ModCoop.cpp)
native static final function string FixLoadedLevelURL(Actor A);

// Crash diagnostics: the last step of the script, logged with the exception if the game crashes (see ModCoop.cpp)
native static final function SetDebugStep(string Step);

// Writes the computer, Windows, graphics card, the game's exe and the DLL wrappers next to it (d3d9, dgVoodoo, ReShade...) to the log,
// for test reports
native static final function LogSystemInfo();

// Starts CoopTunnel (see CoopTunnel/Main.cpp) with these arguments instead of the running one, nothing if it already runs with them.
// It ends together with the game. Without Steam it reports that in its status and ends.
native static final function StartRelay(string Args);

// The status file of the relay, lines of key=value. Empty until it has started.
native static final function string ReadRelayStatus();

// The addresses of this computer's network adapters (LAN, VPN), separated by ", "
native static final function string GetHostAddresses();

// The address of this computer in the internet, empty until known. The first call asks api.ipify.org in the background.
native static final function string GetPublicAddress();
