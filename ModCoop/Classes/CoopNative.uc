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

// Releases all CD keys registered with GameSpy. Required to have a client and a host running on the same PC.
native static final function ReleaseAllCDKeys();

// Changes the connection timeouts of all net drivers and the defaults for new ones. Only in memory, System.ini is not modified.
native static final function SetNetTimeouts(float ConnectionTimeout, float InitialConnectTimeout);

// The game reads mod config files from System but saves them to the save directory (GameData\Save).
// This loads the class defaults from the saved file so settings like the recent addresses persist.
native static final function LoadSavedConfig(class<Object> ConfigClass, string IniName);

// Native fixes that are needed to play single player maps as a network client
native static final function InstallClientFixes();
