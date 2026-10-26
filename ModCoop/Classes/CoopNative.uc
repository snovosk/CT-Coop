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

// Crash diagnostics: the last step of the script, logged with the exception if the game crashes (see ModCoop.cpp)
native static final function SetDebugStep(string Step);

// Writes the computer, Windows, graphics card, the game's exe and the DLL wrappers next to it (d3d9, dgVoodoo, ReShade...) to the log,
// for test reports
native static final function LogSystemInfo();
