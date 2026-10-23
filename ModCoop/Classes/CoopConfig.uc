class CoopConfig extends Object config(ModCoop);

/*
 * CoopConfig
 * Persistent settings of the coop menus (stored in ModCoop.ini) and the client side reconnect state.
 * Everything is accessed through the class defaults so no instance is needed.
 */

// Mod version. Every player must have the same build (the package GUIDs must match), so increase this with every release.
const MOD_VERSION = "1.3";

var config string        RecentAddresses[5]; // Most recent first. A static array because the config writer of RC comments out dynamic arrays.
var config array<string> CoopLevels;       // Levels that can be selected in the host menu. Remove a level here to disable it.
var config int           LastLevelIndex;
var config int           LastMaxPlayers;
var config int           DefaultPort;

// Reconnect state (client only). Kept in memory, not saved.
var string ReconnectAddress;               // Address of the coop host we are playing on. Empty if not in a coop session.
var int    ReconnectAttempts;
var config int MaxReconnectAttempts;
var config float ReconnectInterval;

var config float ClientTimeout;  // Seconds without data from the host until the client considers the connection lost (System.ini default is 120)
var config float ServerTimeout;  // Same on the host for clients

var config bool bDebugLog; // Log positions of players on server and clients to compare synchronization

static function AddRecentAddress(string Address)
{
	local int i, Found;

	Found = ArrayCount(default.RecentAddresses) - 1;

	for(i = 0; i < ArrayCount(default.RecentAddresses); ++i)
	{
		if(default.RecentAddresses[i] ~= Address)
		{
			Found = i;
			break;
		}
	}

	// Move the entries in front of the found one (or all but the last) back by one
	for(i = Found; i > 0; --i)
		default.RecentAddresses[i] = default.RecentAddresses[i - 1];

	default.RecentAddresses[0] = Address;
	StaticSaveConfig();
}

static function int NumRecentAddresses()
{
	local int i;

	for(i = 0; i < ArrayCount(default.RecentAddresses); ++i)
	{
		if(default.RecentAddresses[i] == "")
			break;
	}

	return i;
}

// Adds the default port if the address does not contain one
static function string NormalizeAddress(string Address)
{
	local int i;

	// Remove spaces
	i = InStr(Address, " ");

	while(i != -1)
	{
		Address = Left(Address, i) $ Mid(Address, i + 1);
		i = InStr(Address, " ");
	}

	if(Address != "" && InStr(Address, ":") == -1)
		Address = Address $ ":" $ default.DefaultPort;

	return Address;
}

static function string Version()
{
	return MOD_VERSION;
}

// URL used to connect to a coop host. The version lets the host reject incompatible clients with a clear message.
static function string MakeConnectURL(string Address)
{
	return Address $ "?CoopVersion=" $ MOD_VERSION;
}

static function ApplyClientTimeouts()
{
	class'CoopNative'.static.SetNetTimeouts(default.ClientTimeout, default.ClientTimeout);
}

static function BeginSession(string Address)
{
	ApplyClientTimeouts();

	default.ReconnectAddress = Address;
	default.ReconnectAttempts = 0;
}

static function EndSession()
{
	default.ReconnectAddress = "";
	default.ReconnectAttempts = 0;
}

defaultproperties
{
	LastMaxPlayers=2
	DefaultPort=7777
	MaxReconnectAttempts=12
	ReconnectInterval=5.0
	ClientTimeout=15.0
	ServerTimeout=30.0
	CoopLevels(0)="GEO_01A"
	CoopLevels(1)="GEO_01B"
	CoopLevels(2)="GEO_01C"
	CoopLevels(3)="GEO_03A"
	CoopLevels(4)="GEO_03C"
	CoopLevels(5)="GEO_03D"
	CoopLevels(6)="GEO_04A"
	CoopLevels(7)="GEO_04B"
	CoopLevels(8)="GEO_04C"
	CoopLevels(9)="GEO_04D"
	CoopLevels(10)="GEO_05A"
	CoopLevels(11)="GEO_05B"
	CoopLevels(12)="GEO_05C"
	CoopLevels(13)="RAS_01A"
	CoopLevels(14)="RAS_01B"
	CoopLevels(15)="RAS_01C"
	CoopLevels(16)="RAS_02A"
	CoopLevels(17)="RAS_02B"
	CoopLevels(18)="RAS_02C"
	CoopLevels(19)="RAS_02D"
	CoopLevels(20)="RAS_02E"
	CoopLevels(21)="RAS_03A"
	CoopLevels(22)="RAS_03B"
	CoopLevels(23)="RAS_03C"
	CoopLevels(24)="RAS_04A"
	CoopLevels(25)="RAS_04B"
	CoopLevels(26)="RAS_04C"
	CoopLevels(27)="RAS_04D"
	CoopLevels(28)="YYY_01B"
	CoopLevels(29)="YYY_01C"
	CoopLevels(30)="YYY_01D"
	CoopLevels(31)="YYY_01E"
	CoopLevels(32)="YYY_35A"
	CoopLevels(33)="YYY_35B"
	CoopLevels(34)="YYY_35C"
	CoopLevels(35)="YYY_04A"
	CoopLevels(36)="YYY_04B"
	CoopLevels(37)="YYY_04C"
	CoopLevels(38)="YYY_04E"
	CoopLevels(39)="YYY_04F"
	CoopLevels(40)="YYY_05A"
	CoopLevels(41)="YYY_05B"
	CoopLevels(42)="YYY_05C"
	CoopLevels(43)="YYY_05D"
	CoopLevels(44)="YYY_05E"
	CoopLevels(45)="YYY_05F"
	CoopLevels(46)="YYY_06A"
	CoopLevels(47)="YYY_06B"
	CoopLevels(48)="YYY_06C"
	CoopLevels(49)="YYY_06D"
}
