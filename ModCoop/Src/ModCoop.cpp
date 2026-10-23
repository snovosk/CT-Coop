#include "ModCoopPrivate.h"
#include "IpDrv.h"
#include "CodeInjection.h"

#include <shlobj.h>
#include <shellapi.h>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "uuid.lib")

/*
 * CoopNative
 */

/*
 * The member layout of UGameEngine in the headers is not verified to match Engine.dll so the ServerPackages array is looked up via its script property.
 */
static TArray<FString>* GetServerPackages()
{
	if(!GEngine)
		return NULL;

	UArrayProperty* Property = FindField<UArrayProperty>(GEngine->GetClass(), "ServerPackages");

	if(!Property || !Property->Inner || !Property->Inner->IsA(UStrProperty::StaticClass()))
	{
		debugf(NAME_Warning, "ModCoop: ServerPackages property not found");
		return NULL;
	}

	return reinterpret_cast<TArray<FString>*>(reinterpret_cast<BYTE*>(GEngine) + Property->Offset);
}

static INT FindServerPackage(TArray<FString>& ServerPackages, const FString& PackageName)
{
	for(INT i = 0; i < ServerPackages.Num(); ++i)
	{
		if(appStricmp(*ServerPackages[i], *PackageName) == 0)
			return i;
	}

	return INDEX_NONE;
}

void UCoopNative::execAddServerPackage(FFrame& Stack, void* Result)
{
	P_GET_STR(PackageName);
	P_FINISH;

	TArray<FString>* ServerPackages = GetServerPackages();

	// Only changed in memory, the config is never saved from here.
	// Must happen before the server starts listening since that's when the package map is built.
	if(ServerPackages && FindServerPackage(*ServerPackages, PackageName) == INDEX_NONE)
	{
		debugf("ModCoop: Adding '%s' to ServerPackages", *PackageName);
		new(*ServerPackages) FString(PackageName);
	}
}

void UCoopNative::execRemoveServerPackage(FFrame& Stack, void* Result)
{
	P_GET_STR(PackageName);
	P_FINISH;

	TArray<FString>* ServerPackages = GetServerPackages();

	if(ServerPackages)
	{
		INT Index = FindServerPackage(*ServerPackages, PackageName);

		if(Index != INDEX_NONE)
		{
			debugf("ModCoop: Removing '%s' from ServerPackages", *PackageName);
			ServerPackages->Remove(Index);
		}
	}
}

void UCoopNative::execHasServerPackage(FFrame& Stack, void* Result)
{
	P_GET_STR(PackageName);
	P_FINISH;

	TArray<FString>* ServerPackages = GetServerPackages();

	*static_cast<UBOOL*>(Result) = ServerPackages && FindServerPackage(*ServerPackages, PackageName) != INDEX_NONE;
}

void UCoopNative::execGetCommandLine(FFrame& Stack, void* Result)
{
	P_FINISH;

	*static_cast<FString*>(Result) = appCmdLine();
}

void UCoopNative::execReleaseAllCDKeys(FFrame& Stack, void* Result)
{
	P_FINISH;

	GameSpyMgr* GameSpy = GetGameSpyMgr();

	if(GameSpy)
		GameSpy->ReleaseAllCDKey();
}

static void SetFloatProperty(UObject* Object, const TCHAR* Name, FLOAT Value)
{
	UFloatProperty* Property = FindField<UFloatProperty>(Object->GetClass(), Name);

	if(Property)
		*reinterpret_cast<FLOAT*>(reinterpret_cast<BYTE*>(Object) + Property->Offset) = Value;
}

void UCoopNative::execSetNetTimeouts(FFrame& Stack, void* Result)
{
	P_GET_FLOAT(ConnectionTimeout);
	P_GET_FLOAT(InitialConnectTimeout);
	P_FINISH;

	// Existing drivers and their class defaults (new drivers are constructed from the defaults)
	foreachobj(UNetDriver, It)
	{
		SetFloatProperty(*It, "ConnectionTimeout", ConnectionTimeout);
		SetFloatProperty(*It, "InitialConnectTimeout", InitialConnectTimeout);
	}

	foreachobj(UClass, It)
	{
		if(It->IsChildOf(UNetDriver::StaticClass()) && It->GetDefaultObject())
		{
			SetFloatProperty(It->GetDefaultObject(), "ConnectionTimeout", ConnectionTimeout);
			SetFloatProperty(It->GetDefaultObject(), "InitialConnectTimeout", InitialConnectTimeout);
		}
	}
}

void UCoopNative::execLoadSavedConfig(FFrame& Stack, void* Result)
{
	P_GET_OBJECT(UClass, ConfigClass);
	P_GET_STR(IniName);
	P_FINISH;

	if(!ConfigClass || IniName.Len() == 0)
		return;

	FString Path = GSavePath * IniName;

	if(GFileManager->FileSize(*Path) <= 0)
	{
		debugf("ModCoop: No saved config '%s'", *Path);
		return;
	}

	debugf("ModCoop: Loading config of %s from '%s'", ConfigClass->GetName(), *Path);
	ConfigClass->GetDefaultObject()->LoadConfig(0, ConfigClass, *Path);
}

/*
 * Client fixes
 */

// Offset of LevelInfo.NetMode looked up via the script property since the header layout is not verified
static INT NetModeOffset = INDEX_NONE;

static BYTE GetNetMode(AActor* Actor)
{
	if(!Actor || !Actor->Level || NetModeOffset == INDEX_NONE)
		return NM_Standalone;

	return *(reinterpret_cast<BYTE*>(Actor->Level) + NetModeOffset);
}

static UBOOL(__fastcall*OriginalCTBotTick)(AActor*, DWORD, FLOAT, ELevelTick) = NULL;

/*
 * Single player maps contain AI that the engine keeps on network clients. Their controllers crash in ULocalSituation::Assess
 * because the AI data only exists on the server. AI must only run on the server so these controllers are not ticked on clients.
 */
static UBOOL __fastcall CTBotTickOverride(AActor* Self, DWORD Edx, FLOAT DeltaTime, ELevelTick TickType)
{
	if(GetNetMode(Self) == NM_Client)
	{
		AController* Controller = static_cast<AController*>(Self);

		static TArray<AActor*> LoggedControllers;

		if(!Self->bDeleteMe && LoggedControllers.FindItemIndex(Self) == INDEX_NONE)
		{
			LoggedControllers.AddItem(Self);

			APawn* P = Controller->Pawn;

			debugf("ModCoop: Disabling client side AI controller %s (Pawn=%s Role=%i RemoteRole=%i bNoDelete=%i)",
			       Self->GetFullName(),
			       P ? P->GetFullName() : "None",
			       P ? P->Role : -1,
			       P ? P->RemoteRole : -1,
			       P ? P->bNoDelete : -1);
		}

		return 1;
	}

	return OriginalCTBotTick(Self, Edx, DeltaTime, TickType);
}

/*
 * Single player maps contain actors of classes that are static by default (StaticMeshActor and Mover) which were made dynamic in the map.
 * A client removes them when loading the map because they are replicated by the server. But spawning them fails on the client
 * because the class defaults say bStatic/bNoDelete which crashes the engine (InitialClientActor).
 * The fix temporarily clears these flags in the class defaults while the client processes network packets.
 */
static AActor* StaticClassDefaults[2] = {NULL, NULL}; // Mover and StaticMeshActor, the only classes affected in the campaign maps
static BYTE    StaticClassFlags[2];

static void(__fastcall*OriginalTickDispatch)(UNetDriver*, DWORD, FLOAT) = NULL;

static UBOOL IsNetClient()
{
	if(!GEngine || !GEngine->Client || GEngine->Client->Viewports.Num() == 0 || !GEngine->Client->Viewports[0])
		return 0;

	return GetNetMode(GEngine->Client->Viewports[0]->Actor) == NM_Client;
}

static void __fastcall TickDispatchOverride(UNetDriver* Self, DWORD Edx, FLOAT DeltaTime)
{
	if(!IsNetClient())
	{
		OriginalTickDispatch(Self, Edx, DeltaTime);
		return;
	}

	for(INT i = 0; i < ARRAY_COUNT(StaticClassDefaults); ++i)
	{
		AActor* Default = StaticClassDefaults[i];

		StaticClassFlags[i] = static_cast<BYTE>(Default->bStatic | (Default->bNoDelete << 1));
		Default->bStatic = 0;
		Default->bNoDelete = 0;
	}

	OriginalTickDispatch(Self, Edx, DeltaTime);

	for(INT i = 0; i < ARRAY_COUNT(StaticClassDefaults); ++i)
	{
		AActor* Default = StaticClassDefaults[i];

		Default->bStatic = StaticClassFlags[i] & 1;
		Default->bNoDelete = (StaticClassFlags[i] >> 1) & 1;
	}
}

static UBOOL VerifyActorFlags()
{
	UClass* MoverClass           = FindObject<UClass>(ANY_PACKAGE, "Mover");
	UClass* StaticMeshActorClass = FindObject<UClass>(ANY_PACKAGE, "StaticMeshActor");

	if(!MoverClass || !StaticMeshActorClass)
		return 0;

	AActor* Mover           = static_cast<AActor*>(MoverClass->GetDefaultObject());
	AActor* StaticMeshActor = static_cast<AActor*>(StaticMeshActorClass->GetDefaultObject());
	AActor* Pawn            = static_cast<AActor*>(APawn::StaticClass()->GetDefaultObject());

	if(!Mover->bNoDelete || !StaticMeshActor->bStatic || Pawn->bStatic || Pawn->bNoDelete)
		return 0;

	// Engine classes are never unloaded so the pointers stay valid
	StaticClassDefaults[0] = Mover;
	StaticClassDefaults[1] = StaticMeshActor;

	return 1;
}

static void InstallStaticActorFix()
{
	if(!VerifyActorFlags())
	{
		debugf(NAME_Warning, "ModCoop: Actor flags don't match the expected layout, static actor fix disabled");
		return;
	}

	HMODULE IpDrvDll = LoadLibraryA("IpDrv.dll");

	if(!IpDrvDll)
	{
		debugf(NAME_Warning, "ModCoop: IpDrv.dll not found, static actor fix disabled");
		return;
	}

	void*  TickDispatch = GetProcAddress(IpDrvDll, "?TickDispatch@UTcpNetDriver@@UAEXM@Z");
	void** VTable       = reinterpret_cast<void**>(GetProcAddress(IpDrvDll, "??_7UTcpNetDriver@@6BUObject@@@"));

	if(!TickDispatch || !VTable)
	{
		debugf(NAME_Warning, "ModCoop: UTcpNetDriver::TickDispatch not found, static actor fix disabled");
		return;
	}

	for(INT i = 0; i < 256; ++i)
	{
		if(VTable[i] == TickDispatch)
		{
			OriginalTickDispatch = PatchVTable(&VTable, i, TickDispatchOverride);
			debugf("ModCoop: Installed static actor fix (UTcpNetDriver vtable slot %i)", i);
			return;
		}
	}

	debugf(NAME_Warning, "ModCoop: UTcpNetDriver::TickDispatch slot not found, static actor fix disabled");
}

/*
 * First start setup: desktop shortcut and firewall rule.
 * Each step runs only once per installation (marker files in the save directory), so deleting the shortcut or declining the
 * firewall question is respected. Start the game with -CoopNoSetup to skip it.
 */
static const wchar_t* FirewallRuleName = L"SWRC Coop (CT.exe)";

static FString SetupMarkerPath(const TCHAR* Name)
{
	return GSavePath * Name;
}

static UBOOL HasSetupMarker(const TCHAR* Name)
{
	return GFileManager->FileSize(*SetupMarkerPath(Name)) >= 0;
}

static void WriteSetupMarker(const TCHAR* Name)
{
	appSaveStringToFile(FString("done"), *SetupMarkerPath(Name));
}

static DWORD RunHidden(wchar_t* CommandLine)
{
	STARTUPINFOW        StartupInfo = {sizeof(StartupInfo)};
	PROCESS_INFORMATION ProcessInfo = {0};
	DWORD               ExitCode    = 0xFFFFFFFF;

	if(CreateProcessW(NULL, CommandLine, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &StartupInfo, &ProcessInfo))
	{
		if(WaitForSingleObject(ProcessInfo.hProcess, 10000) == WAIT_OBJECT_0)
			GetExitCodeProcess(ProcessInfo.hProcess, &ExitCode);

		CloseHandle(ProcessInfo.hThread);
		CloseHandle(ProcessInfo.hProcess);
	}

	return ExitCode;
}

static void CreateDesktopShortcut(const wchar_t* ExePath)
{
	wchar_t Desktop[MAX_PATH];

	if(FAILED(SHGetFolderPathW(NULL, CSIDL_DESKTOPDIRECTORY, NULL, SHGFP_TYPE_CURRENT, Desktop)))
		return;

	wchar_t LinkPath[MAX_PATH];
	wsprintfW(LinkPath, L"%s\\Star Wars Republic Commando Co-op.lnk", Desktop);

	wchar_t WorkingDir[MAX_PATH];
	lstrcpynW(WorkingDir, ExePath, MAX_PATH);
	wchar_t* LastSlash = wcsrchr(WorkingDir, L'\\');

	if(LastSlash)
		*LastSlash = 0;

	HRESULT ComResult = CoInitialize(NULL);
	IShellLinkW* Link = NULL;

	if(SUCCEEDED(CoCreateInstance(CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, IID_IShellLinkW, reinterpret_cast<void**>(&Link))))
	{
		Link->SetPath(ExePath);
		Link->SetWorkingDirectory(WorkingDir);
		Link->SetArguments(L"-forcelogflush");
		Link->SetIconLocation(ExePath, 0);
		Link->SetDescription(L"Star Wars: Republic Commando (Co-op)");

		IPersistFile* File = NULL;

		if(SUCCEEDED(Link->QueryInterface(IID_IPersistFile, reinterpret_cast<void**>(&File))))
		{
			if(SUCCEEDED(File->Save(LinkPath, TRUE)))
				debugf("ModCoop: Created desktop shortcut");

			File->Release();
		}

		Link->Release();
	}

	if(SUCCEEDED(ComResult))
		CoUninitialize();
}

static void EnsureFirewallRule(const wchar_t* ExePath)
{
	// netsh returns 0 if a rule with this name exists
	wchar_t Check[512];
	wsprintfW(Check, L"netsh advfirewall firewall show rule name=\"%s\"", FirewallRuleName);

	if(RunHidden(Check) == 0)
		return;

	// "Allow the coop mod to accept connections from other players in the Windows firewall? Administrator rights are required.
	//  Without it players can't connect to your game when you host. You can do it later by deleting ModCoopFirewall.done in GameData\Save."
	const wchar_t* Question =
		L"\u0420\u0430\u0437\u0440\u0435\u0448\u0438\u0442\u044C CT.exe \u043F\u0440\u0438\u043D\u0438\u043C\u0430\u0442\u044C \u043F\u043E\u0434\u043A\u043B\u044E\u0447\u0435\u043D\u0438\u044F \u0434\u0440\u0443\u0433\u0438\u0445 \u0438\u0433\u0440\u043E\u043A\u043E\u0432 \u0432 \u0431\u0440\u0430\u043D\u0434\u043C\u0430\u0443\u044D\u0440\u0435 Windows?\n\n\u042D\u0442\u043E \u043D\u0443\u0436\u043D\u043E, \u0447\u0442\u043E\u0431\u044B \u0434\u0440\u0443\u0437\u044C\u044F \u043C\u043E\u0433\u043B\u0438 \u043F\u043E\u0434\u043A\u043B\u044E\u0447\u0438\u0442\u044C\u0441\u044F, \u043A\u043E\u0433\u0434\u0430 \u0432\u044B \u0445\u043E\u0441\u0442. \u041F\u043E\u0442\u0440\u0435\u0431\u0443\u044E\u0442\u0441\u044F \u043F\u0440\u0430\u0432\u0430 \u0430\u0434\u043C\u0438\u043D\u0438\u0441\u0442\u0440\u0430\u0442\u043E\u0440\u0430.";

	if(MessageBoxW(NULL, Question, L"Republic Commando Co-op", MB_YESNO | MB_ICONQUESTION | MB_TOPMOST | MB_SETFOREGROUND) != IDYES)
	{
		debugf("ModCoop: Firewall rule declined");
		return;
	}

	wchar_t Parameters[1024];
	wsprintfW(Parameters, L"advfirewall firewall add rule name=\"%s\" dir=in action=allow program=\"%s\" protocol=udp profile=any enable=yes",
	          FirewallRuleName, ExePath);

	SHELLEXECUTEINFOW Execute = {sizeof(Execute)};
	Execute.fMask        = SEE_MASK_NOCLOSEPROCESS;
	Execute.lpVerb       = L"runas"; // Shows the UAC prompt
	Execute.lpFile       = L"netsh.exe";
	Execute.lpParameters = Parameters;
	Execute.nShow        = SW_HIDE;

	if(ShellExecuteExW(&Execute) && Execute.hProcess)
	{
		WaitForSingleObject(Execute.hProcess, 30000);
		CloseHandle(Execute.hProcess);
		debugf("ModCoop: Added firewall rule");
	}
	else
	{
		debugf("ModCoop: Adding the firewall rule was cancelled");
	}
}

static void FirstStartSetup()
{
	if(GIsEditor || ParseParam(appCmdLine(), "CoopNoSetup"))
		return;

	wchar_t ExePath[MAX_PATH];

	if(!GetModuleFileNameW(NULL, ExePath, MAX_PATH))
		return;

	// Only for the coop launcher, not for the original game executable
	const wchar_t* ExeName = wcsrchr(ExePath, L'\\');

	if(!ExeName || lstrcmpiW(ExeName + 1, L"CT.exe") != 0)
		return;

	if(!HasSetupMarker("ModCoopShortcut.done"))
	{
		CreateDesktopShortcut(ExePath);
		WriteSetupMarker("ModCoopShortcut.done");
	}

	if(!HasSetupMarker("ModCoopFirewall.done"))
	{
		WriteSetupMarker("ModCoopFirewall.done");
		EnsureFirewallRule(ExePath);
	}
}

void UCoopNative::execInstallClientFixes(FFrame& Stack, void* Result)
{
	P_FINISH;

	static UBOOL Installed = 0;

	if(Installed)
		return;

	Installed = 1;

	FirstStartSetup();

	UByteProperty* NetModeProperty = FindField<UByteProperty>(ALevelInfo::StaticClass(), "NetMode");

	if(!NetModeProperty)
	{
		debugf(NAME_Warning, "ModCoop: LevelInfo.NetMode not found, client fixes disabled");
		return;
	}

	NetModeOffset = NetModeProperty->Offset;

	InstallStaticActorFix();

	HMODULE EngineDll = GetModuleHandleA("Engine.dll");
	HMODULE CTGameDll = GetModuleHandleA("CTGame.dll");

	if(!EngineDll || !CTGameDll)
	{
		debugf(NAME_Warning, "ModCoop: Engine.dll or CTGame.dll not loaded, client fixes disabled");
		return;
	}

	void*  ControllerTick    = GetProcAddress(EngineDll, "?Tick@AController@@UAEHMW4ELevelTick@@@Z");
	void** ControllerVTable  = reinterpret_cast<void**>(GetProcAddress(EngineDll, "??_7AController@@6B@"));
	void** BotVTable         = reinterpret_cast<void**>(GetProcAddress(CTGameDll, "??_7ACTBot@@6B@"));

	if(!ControllerTick || !ControllerVTable || !BotVTable)
	{
		debugf(NAME_Warning, "ModCoop: CTBot tick not found, client fixes disabled");
		return;
	}

	/*
	 * Find the Tick slot in the vtable of AController. The vtable of CTBot uses the same slot but points to an import thunk in CTGame.dll
	 * so the address can't be compared directly.
	 */
	for(INT i = 0; i < 256; ++i)
	{
		if(ControllerVTable[i] == ControllerTick)
		{
			OriginalCTBotTick = PatchVTable(&BotVTable, i, CTBotTickOverride);
			debugf("ModCoop: Installed client fixes (CTBot vtable slot %i)", i);
			return;
		}
	}

	debugf(NAME_Warning, "ModCoop: CTBot tick slot not found, client fixes disabled");
}
