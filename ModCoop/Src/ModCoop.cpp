#include "ModCoopPrivate.h"
#include "IpDrv.h"
#include "CodeInjection.h"

#include <shlobj.h>
#include <shellapi.h>
#include <stdio.h>
#include <wininet.h>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "uuid.lib")
#pragma comment(lib, "version.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "wininet.lib")
#pragma comment(lib, "ws2_32.lib")

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

void UCoopNative::execGetRealTime(FFrame& Stack, void* Result)
{
	P_FINISH;

	static DOUBLE StartTime = appSeconds();

	*static_cast<FLOAT*>(Result) = static_cast<FLOAT>(appSeconds() - StartTime);
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

static void SetIntProperty(UObject* Object, const TCHAR* Name, INT Value)
{
	UIntProperty* Property = FindField<UIntProperty>(Object->GetClass(), Name);

	if(Property)
		*reinterpret_cast<INT*>(reinterpret_cast<BYTE*>(Object) + Property->Offset) = Value;
}

// -1 if the property doesn't exist
static INT GetIntProperty(UObject* Object, const TCHAR* Name)
{
	UIntProperty* Property = FindField<UIntProperty>(Object->GetClass(), Name);

	return Property ? *reinterpret_cast<INT*>(reinterpret_cast<BYTE*>(Object) + Property->Offset) : -1;
}

static void SetNetRateProperties(UObject* Object, INT MaxClientRate, INT ServerMaxTickRate)
{
	SetIntProperty(Object, "MaxClientRate", MaxClientRate);
	SetIntProperty(Object, "MaxInternetClientRate", MaxClientRate);
	SetIntProperty(Object, "NetServerMaxTickRate", ServerMaxTickRate);
	SetIntProperty(Object, "LanServerMaxTickRate", ServerMaxTickRate);
}

void UCoopNative::execSetNetRates(FFrame& Stack, void* Result)
{
	P_GET_INT(MaxClientRate);
	P_GET_INT(ServerMaxTickRate);
	P_FINISH;

	foreachobj(UNetDriver, It)
	{
		SetNetRateProperties(*It, MaxClientRate, ServerMaxTickRate);
		debugf("ModCoop: Net rates of %s: MaxClientRate=%i NetServerMaxTickRate=%i", It->GetFullName(), GetIntProperty(*It, "MaxClientRate"), GetIntProperty(*It, "NetServerMaxTickRate"));
	}

	foreachobj(UClass, It)
	{
		if(It->IsChildOf(UNetDriver::StaticClass()) && It->GetDefaultObject())
			SetNetRateProperties(It->GetDefaultObject(), MaxClientRate, ServerMaxTickRate);
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

	// Values read from a file count as unchanged and the config writer comments them out when the file is saved (FConfigFile::Write),
	// so they were lost after the next start
	FConfigSection* Section = GConfig->GetSectionPrivate(ConfigClass->GetPathName(), 0, 0, *Path);

	if(Section)
	{
		for(FConfigSection::TIterator It(*Section); It; ++It)
			It.Value().Dirty = true;
	}
}

void UCoopNative::execReadSavedString(FFrame& Stack, void* Result)
{
	P_GET_STR(IniName);
	P_GET_STR(Section);
	P_GET_STR(Key);
	P_FINISH;

	FString Path = GSavePath * IniName;
	FString Value;

	if(GConfig->GetFString(*Section, *Key, Value, *Path))
	{
		// Mark it as changed, otherwise the next save of the file comments it out (see FConfigFile::Write)
		GConfig->SetString(*Section, *Key, Value == TEXT("-") ? TEXT("+") : TEXT("-"), *Path);
		GConfig->SetString(*Section, *Key, *Value, *Path);
	}
	else
	{
		Value = TEXT("");
	}

	*static_cast<FString*>(Result) = Value;
}

void UCoopNative::execWriteSavedString(FFrame& Stack, void* Result)
{
	P_GET_STR(IniName);
	P_GET_STR(Section);
	P_GET_STR(Key);
	P_GET_STR(Value);
	P_FINISH;

	FString Path = GSavePath * IniName;

	// An unchanged value would stay marked as loaded and be written commented out (see FConfigFile::Write)
	GConfig->SetString(*Section, *Key, Value == TEXT("-") ? TEXT("+") : TEXT("-"), *Path);
	GConfig->SetString(*Section, *Key, *Value, *Path);
	GConfig->Flush(0, *IniName); // Files are kept by their name without the path
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

	// The controller's name ends up in the crash history (host crash in AController::Tick)
	guard(CoopCTBotTick);
	return OriginalCTBotTick(Self, Edx, DeltaTime, TickType);
	unguardf(("%s", Self->GetFullName()));
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

/*
 * Crash diagnostics
 * The crash history of the engine only names guarded native functions and script events, e.g. "CoopPlayer.PlayerTick" without
 * telling what inside it crashed. A vectored exception handler logs the exception, the module and offset where it happened, the
 * registers, the return addresses on the stack and the last step the script marked with SetDebugStep. It only logs, the engine
 * handles the crash as before.
 */
static ANSICHAR GCoopDebugStep[256] = "";
static UBOOL    GInSafeSelectTargetType = 0;
static LONG GCoopExceptionLogs = 0;

static void DescribeAddress(DWORD Address, ANSICHAR* Out, INT OutSize)
{
	HMODULE Module = NULL;

	if(GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, reinterpret_cast<LPCSTR>(Address), &Module) && Module)
	{
		ANSICHAR Path[MAX_PATH] = "";
		GetModuleFileNameA(Module, Path, MAX_PATH);
		const ANSICHAR* Name = strrchr(Path, '\\');
		_snprintf_s(Out, OutSize, _TRUNCATE, "%s+0x%X", Name ? Name + 1 : Path, Address - reinterpret_cast<DWORD>(Module));
	}
	else
	{
		_snprintf_s(Out, OutSize, _TRUNCATE, "0x%08X", Address);
	}

	Out[OutSize - 1] = 0;
}

static UBOOL IsCodeAddress(DWORD Address)
{
	MEMORY_BASIC_INFORMATION Info;

	if(Address < 0x10000 || !VirtualQuery(reinterpret_cast<LPCVOID>(Address), &Info, sizeof(Info)) || Info.Type != MEM_IMAGE)
		return 0;

	return (Info.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) != 0;
}

static INT ReadStack(DWORD* Stack, DWORD* Out, INT MaxOut)
{
	INT Count = 0;

	__try
	{
		for(INT i = 0; i < 512 && Count < MaxOut; ++i)
		{
			if(IsCodeAddress(Stack[i]))
				Out[Count++] = Stack[i];
		}
	}
	__except(EXCEPTION_EXECUTE_HANDLER)
	{
	}

	return Count;
}

static LONG CALLBACK CoopExceptionHandler(EXCEPTION_POINTERS* Info)
{
	DWORD Code = Info->ExceptionRecord->ExceptionCode;

	if(Code != EXCEPTION_ACCESS_VIOLATION && Code != EXCEPTION_INT_DIVIDE_BY_ZERO && Code != EXCEPTION_ILLEGAL_INSTRUCTION &&
	   Code != EXCEPTION_PRIV_INSTRUCTION && Code != EXCEPTION_ARRAY_BOUNDS_EXCEEDED)
		return EXCEPTION_CONTINUE_SEARCH;

	// Handled by the guard of SelectTargetType (see execSafeSelectTargetType)
	if(GInSafeSelectTargetType)
		return EXCEPTION_CONTINUE_SEARCH;

	CONTEXT* C = Info->ContextRecord;
	ANSICHAR Where[300];
	DescribeAddress(reinterpret_cast<DWORD>(Info->ExceptionRecord->ExceptionAddress), Where, sizeof(Where));

	// Windows itself probes memory with handled exceptions (IsBadReadPtr), these are not crashes
	if(_strnicmp(Where, "KERNEL32", 8) == 0 || _strnicmp(Where, "KERNELBASE", 10) == 0 || _strnicmp(Where, "ntdll", 5) == 0)
		return EXCEPTION_CONTINUE_SEARCH;

	if(InterlockedIncrement(&GCoopExceptionLogs) > 5 || !GLog)
		return EXCEPTION_CONTINUE_SEARCH;

	debugf("ModCoop: Exception 0x%08X at %s (%s 0x%08X) EAX=%08X EBX=%08X ECX=%08X EDX=%08X ESI=%08X EDI=%08X EBP=%08X ESP=%08X",
	       Code, Where, Info->ExceptionRecord->NumberParameters > 1 && Info->ExceptionRecord->ExceptionInformation[0] ? "writing" : "reading",
	       Info->ExceptionRecord->NumberParameters > 1 ? Info->ExceptionRecord->ExceptionInformation[1] : 0,
	       C->Eax, C->Ebx, C->Ecx, C->Edx, C->Esi, C->Edi, C->Ebp, C->Esp);
	debugf("ModCoop: Last script step: %s", GCoopDebugStep);

	DWORD Returns[24];
	INT Count = ReadStack(reinterpret_cast<DWORD*>(C->Esp), Returns, ARRAY_COUNT(Returns));

	for(INT i = 0; i < Count; ++i)
	{
		DescribeAddress(Returns[i], Where, sizeof(Where));
		debugf("ModCoop: Stack %i: %s", i, Where);
	}

	GLog->Flush();

	return EXCEPTION_CONTINUE_SEARCH;
}

static void InstallCrashLog()
{
	static UBOOL Installed = 0;

	if(Installed)
		return;

	Installed = 1;
	AddVectoredExceptionHandler(1, CoopExceptionHandler);
	debugf("ModCoop: Crash diagnostics installed");
}

void UCoopNative::execSetDebugStep(FFrame& Stack, void* Result)
{
	P_GET_STR(Step);
	P_FINISH;

	appStrncpy(GCoopDebugStep, *Step, ARRAY_COUNT(GCoopDebugStep));
}

/*
 * CTPlayer.SelectTargetType (CTGame.dll, what the player looks at) reads Target.SquadMarker after it found that Target is None
 * (CTGame.dll+0x2A5EA). In single player Target is never None there, network clients crashed with "General protection fault" in
 * CoopPlayer.PlayerTick (GEO_01C, several times). The native is called through a guard: if it crashes, the target is cleared and the
 * game goes on.
 */
static Native OriginalSelectTargetType = NULL;
static INT    SelectTargetTypeCrashes = 0;

static INT AccessViolationFilter(DWORD Code)
{
	return Code == EXCEPTION_ACCESS_VIOLATION ? EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH;
}

static UBOOL CallGuarded(UObject* Self, Native Func, FFrame& Stack, void* Result)
{
	__try
	{
		(Self->*Func)(Stack, Result);
		return 1;
	}
	__except(AccessViolationFilter(GetExceptionCode()))
	{
		return 0;
	}
}

// Not a native of the script class: ModCoopClasses.h is regenerated by the script compiler and would lose the declaration
class UCoopSelectTargetGuard : public UObject
{
public:
	void execSafeSelectTargetType(FFrame& Stack, void* Result);
};

void UCoopSelectTargetGuard::execSafeSelectTargetType(FFrame& Stack, void* Result)
{
	APlayerController* Player = reinterpret_cast<APlayerController*>(this);

	GInSafeSelectTargetType = 1;
	UBOOL Ok = CallGuarded(this, OriginalSelectTargetType, Stack, Result);
	GInSafeSelectTargetType = 0;

	if(Ok)
		return;

	if(SelectTargetTypeCrashes++ < 10)
		debugf("ModCoop: Caught a crash in CTPlayer.SelectTargetType (Target=%s), clearing the target", Player->Target ? Player->Target->GetName() : "None");

	Player->Target = NULL;
	*static_cast<BYTE*>(Result) = 0; // TGT_Default
}

static void InstallSelectTargetTypeGuard()
{
	UClass* CTPlayerClass = FindObject<UClass>(ANY_PACKAGE, "CTPlayer");
	UFunction* Function = CTPlayerClass ? FindField<UFunction>(CTPlayerClass, "SelectTargetType") : NULL;

	if(!Function || !Function->Func)
	{
		debugf(NAME_Warning, "ModCoop: CTPlayer.SelectTargetType not found, no guard");
		return;
	}

	if(OriginalSelectTargetType)
		return;

	OriginalSelectTargetType = Function->Func;
	Function->Func = static_cast<Native>(&UCoopSelectTargetGuard::execSafeSelectTargetType);
	debugf("ModCoop: Installed the guard of CTPlayer.SelectTargetType");
}

/*
 * Sound journal (user, 2026-11-10: a sound stayed stuck and nobody could tell which). The natives Actor.PlaySound (native 264, called through
 * GNatives), PlayOwnedSound and StopSound are wrapped: the first argument is read once for the line and read again by the original, the
 * argument expressions of these calls are variables and literals. Written to its own file, flushed per line: the game may end in a crash.
 */
static Native  OriginalPlaySound      = NULL;
static Native  OriginalPlayOwnedSound = NULL;
static Native  OriginalStopSound      = NULL;
static FArchive* GSoundLog            = NULL;
static UBOOL   GSoundLogEnabled       = 0;
static DOUBLE  GSoundLogStart         = 0.0;

static void SoundLogLine(const TCHAR* Line)
{
	if(!GSoundLogEnabled)
		return;

	if(!GSoundLog)
	{
		FString LogName;

		if(!Parse(appCmdLine(), TEXT("LOG="), LogName))
			LogName = FString(appPackage()) + TEXT(".log");

		if(LogName.Right(4) == TEXT(".log"))
			LogName = LogName.Left(LogName.Len() - 4);

		LogName += TEXT("-Sounds.log");
		GSoundLog = GFileManager->CreateFileWriter(*LogName, FILEWRITE_EvenIfReadOnly);
		GSoundLogStart = appSeconds();

		if(!GSoundLog)
		{
			GSoundLogEnabled = 0;
			debugf(NAME_Warning, "ModCoop: sound journal %s can't be written", *LogName);
			return;
		}

		debugf("ModCoop: sound journal %s", *LogName);
	}

	FString Text = FString::Printf(TEXT("%9.2f %s\r\n"), appSeconds() - GSoundLogStart, Line);
	GSoundLog->Serialize(const_cast<TCHAR*>(*Text), Text.Len());
	GSoundLog->Flush();
}

static FString SoundActorText(UObject* Self)
{
	AActor* Actor = Cast<AActor>(Self);

	if(!Actor)
		return Self ? FString(Self->GetName()) : FString(TEXT("None"));

	return FString::Printf(TEXT("%s (%s) at %.0f,%.0f,%.0f"), Actor->GetName(), Actor->GetClass()->GetName(), Actor->Location.X, Actor->Location.Y, Actor->Location.Z);
}

class UCoopSoundHook : public UObject
{
public:
	void LogFirstSound(FFrame& Stack, const TCHAR* What, UObject* Extra)
	{
		BYTE* Code = Stack.Code;
		P_GET_OBJECT(USound, Sound);
		Stack.Code = Code;

		if(GSoundLogEnabled)
			SoundLogLine(*FString::Printf(TEXT("%s %s by %s%s%s"), What, Sound ? Sound->GetPathName() : TEXT("None"), *SoundActorText(this), Extra ? TEXT(" owner ") : TEXT(""), Extra ? Extra->GetName() : TEXT("")));
	}

	void execPlaySound(FFrame& Stack, void* Result)
	{
		LogFirstSound(Stack, TEXT("PlaySound"), NULL);
		(this->*OriginalPlaySound)(Stack, Result);
	}

	void execPlayOwnedSound(FFrame& Stack, void* Result)
	{
		LogFirstSound(Stack, TEXT("PlayOwnedSound"), NULL);
		(this->*OriginalPlayOwnedSound)(Stack, Result);
	}

	// StopSound(Actor Owner, Sound StopSound, float FadeOutTime): the sound is the second argument
	void execStopSound(FFrame& Stack, void* Result)
	{
		BYTE* Code = Stack.Code;
		P_GET_OBJECT(AActor, SoundOwner);
		P_GET_OBJECT(USound, Sound);
		Stack.Code = Code;

		if(GSoundLogEnabled)
			SoundLogLine(*FString::Printf(TEXT("StopSound %s of %s by %s"), Sound ? Sound->GetPathName() : TEXT("None"), *SoundActorText(SoundOwner), *SoundActorText(this)));

		(this->*OriginalStopSound)(Stack, Result);
	}
};

static void HookSoundNative(const TCHAR* Name, Native& Original, Native Replacement)
{
	UFunction* Function = FindField<UFunction>(AActor::StaticClass(), Name);

	if(!Function || !Function->Func)
	{
		debugf(NAME_Warning, "ModCoop: Actor.%s not found, not in the sound journal", Name);
		return;
	}

	if(Original)
		return;

	Original = Function->Func;
	Function->Func = Replacement;

	// A numbered native is called straight from the table by the script code
	if(Function->iNative)
		GNatives[Function->iNative] = Replacement;
}

static void InstallSoundHooks()
{
	HookSoundNative(TEXT("PlaySound"), OriginalPlaySound, static_cast<Native>(&UCoopSoundHook::execPlaySound));
	HookSoundNative(TEXT("PlayOwnedSound"), OriginalPlayOwnedSound, static_cast<Native>(&UCoopSoundHook::execPlayOwnedSound));
	HookSoundNative(TEXT("StopSound"), OriginalStopSound, static_cast<Native>(&UCoopSoundHook::execStopSound));
}

void UCoopNative::execSetSoundLog(FFrame& Stack, void* Result)
{
	P_GET_UBOOL(bEnabled);
	P_FINISH;

	GSoundLogEnabled = bEnabled;

	if(bEnabled)
		InstallSoundHooks();
}

void UCoopNative::execLogSound(FFrame& Stack, void* Result)
{
	P_GET_STR(Line);
	P_FINISH;

	SoundLogLine(*Line);
}

/*
 * Research for real checkpoints. Engine.dll (2026-11-10, dumpbin): the console command SAVEGAME (UGameEngine::Exec, Engine.dll+0x11CE75) refuses
 * when byte 0x440 of the LevelInfo (assumption: NetMode) isn't 0, then calls UGameEngine vtable slot 0x104 = Engine.dll+0x117A80 with the name.
 * That function has no network check of its own: Client->CreateSaveContainer (WinDrv, makes the folder), LevelInfo+0x438 = 2 meanwhile,
 * UObject::SavePackage of the level as <SavePath>/<name>/<name>.cts. The slot is called only when it points at that address.
 */
static const DWORD SaveGameRva   = 0x117A80;
static const INT   SaveGameSlot  = 0x104 / sizeof(void*);

typedef void (__fastcall* FEngineSaveGame)(UObject* Engine, void* Unused, const ANSICHAR* Name);

static UBOOL CallSaveGame(FEngineSaveGame Func, const ANSICHAR* Name)
{
	__try
	{
		Func(GEngine, NULL, Name);
		return 1;
	}
	__except(AccessViolationFilter(GetExceptionCode()))
	{
		return 0;
	}
}

void UCoopNative::execEngineSaveGame(FFrame& Stack, void* Result)
{
	P_GET_STR(SaveName);
	P_FINISH;

	HMODULE EngineDll = GetModuleHandleA("Engine.dll");
	FEngineSaveGame Func = GEngine ? reinterpret_cast<FEngineSaveGame>((*reinterpret_cast<void***>(GEngine))[SaveGameSlot]) : NULL;

	if(!EngineDll || !Func || reinterpret_cast<BYTE*>(Func) != reinterpret_cast<BYTE*>(EngineDll) + SaveGameRva)
	{
		*(FString*)Result = FString::Printf(TEXT("refused: slot points to %p, expected Engine.dll+%X"), Func, SaveGameRva);
		return;
	}

	DOUBLE Start = appSeconds();
	UBOOL Ok = CallSaveGame(Func, appToAnsi(*SaveName));
	FString Text = FString::Printf(TEXT("called %s in %.2f s, SavePath %s, files:"), Ok ? TEXT("ok") : TEXT("CRASHED"), appSeconds() - Start, *GSavePath);

	TArray<FString> Files = GFileManager->FindFiles(*(GSavePath + TEXT("\\") + SaveName + TEXT("\\*.*")), 1, 0);

	for(INT i = 0; i < Files.Num(); ++i)
		Text += FString::Printf(TEXT(" %s (%i bytes)"), *Files[i], GFileManager->FileSize(*(GSavePath + TEXT("\\") + SaveName + TEXT("\\") + Files[i])));

	*(FString*)Result = Text;
}

/*
 * Research: the package the network announces first for a level (UGameEngine::BuildServerMasterMap, Engine.dll+0x116130: the linker of the
 * level's outer, then ServerPackages). After a checkpoint load a client took one object for another: its level package didn't match.
 */
static void FillPackageText(AActor* A, FString* Out)
{
	UObject* Outer = (A && A->XLevel) ? A->XLevel->GetOuter() : NULL;

	if(!Outer)
	{
		*Out = TEXT("no level");
		return;
	}

	// UnLinker.h of these sources doesn't compile here: the outer's name and its class, then what the net driver's package map announces
	*Out = FString::Printf(TEXT("%s (%s)"), Outer->GetPathName(), Outer->GetClass()->GetName());

	// The headers' layouts don't match the binaries (this crashed): offsets from Engine.dll+0x116130 and Core.dll+0x2C9B0, 0x2CAF0.
	// NetDriver+0x3C MasterMap; UPackageMap+0x28 List data, +0x2C count; FPackageInfo 0x40 bytes, +0x08 Parent, +0x0C Guid
	for(TObjectIterator<UNetDriver> It; It; ++It)
	{
		BYTE* Map = *reinterpret_cast<BYTE**>(reinterpret_cast<BYTE*>(*It) + 0x3C);

		if(!Map)
			continue;

		BYTE* Data = *reinterpret_cast<BYTE**>(Map + 0x28);
		INT Num = (*reinterpret_cast<INT*>(Map + 0x2C) << 3) >> 3;
		*Out += FString::Printf(TEXT(" | driver %s, %i packages:"), It->GetName(), Num);

		for(INT i = 0; i < Num && i < 4; ++i)
		{
			BYTE* Info = Data + i * 0x40;
			UObject* Parent = *reinterpret_cast<UObject**>(Info + 0x08);
			DWORD* Guid = reinterpret_cast<DWORD*>(Info + 0x0C);
			*Out += FString::Printf(TEXT(" %s %08X%08X%08X%08X"), Parent ? Parent->GetName() : TEXT("None"), Guid[0], Guid[1], Guid[2], Guid[3]);
		}
	}
}

// No objects with destructors in a function with __try
static UBOOL SafePackageText(AActor* A, FString* Out)
{
	__try
	{
		FillPackageText(A, Out);
		return 1;
	}
	__except(AccessViolationFilter(GetExceptionCode()))
	{
		return 0;
	}
}

void UCoopNative::execLevelPackageText(FFrame& Stack, void* Result)
{
	P_GET_OBJECT(AActor, A);
	P_FINISH;

	FString Text;

	if(!SafePackageText(A, &Text))
		Text = TEXT("CRASHED reading the linker");

	*(FString*)Result = Text;
}

/*
 * Saves with clients (CoopGame.LoadSavedCheckpoint). Measured 2026-11-11, Reports/2026-11-10-save/RESEARCH.md:
 * - UGameEngine::LoadMap loads the save's level from the .cts and renames its objects into the map's package (RAS_01B), whose linker stays
 *   the clean map (.ctm): the save imports its BSP models and static mesh instances from there. The network announces that package.
 * - UPackageMap::ObjectToIndex (Core.dll+0x2B370, vtable slot 33) numbers an object as ObjectBase of its outermost package + its linker
 *   index, here the index in the .cts. A client resolves it in the .ctm: another object ("Forged object", crash).
 * The fix on the host: every object of the save is paired by its full name with the export of the same name in the .ctm, and the package
 * map's ObjectToIndex and IndexToObject (slot 34) use that index. Clients load the clean map and get the state by replication, like a
 * player joining a running level. Objects of the save without a pair are sent as None.
 * Offsets: FPackageInfo 0x40 bytes, +0x08 Parent, +0x24 ObjectBase, +0x28 ObjectCount; UPackageMap +0x28/+0x2C List, +0x30 master map;
 * UGameEngine +0x118 the current level (LoadMap).
 */
typedef INT      (__fastcall* FObjectToIndexFunc)(void* Map, DWORD Edx, UObject* Object);
typedef UObject* (__fastcall* FIndexToObjectFunc)(void* Map, DWORD Edx, INT Index, UBOOL bLoad);
typedef void*    (__fastcall* FInfoGetLinkerFunc)(void* Info, DWORD Edx, DWORD LoadFlags);

static FObjectToIndexFunc  OriginalObjectToIndex = NULL;
static FIndexToObjectFunc  OriginalIndexToObject = NULL;
static UObject*            RemapPackage = NULL;  // The level's package while the remap is active
static void*               RemapLevel = NULL;    // The level it was made for: a level change ends it
static TMap<UObject*, INT> RemapObjectToLocal;   // Object of the save -> export index in the .ctm, -1 = no pair
static TArray<UObject*>    RemapLocalToObject;   // Export index in the .ctm -> object of the save
static INT                 RemapHits = 0;

static void ClearSaveRemap()
{
	if(RemapPackage)
		debugf("ModCoop: save remap ended (%i objects sent by the map's numbers)", RemapHits);

	RemapPackage = NULL;
	RemapLevel = NULL;
	RemapObjectToLocal.Empty();
	RemapLocalToObject.Empty();
	RemapHits = 0;
}

static UBOOL RemapActive()
{
	if(!RemapPackage)
		return 0;

	if(!GEngine || *reinterpret_cast<void**>(reinterpret_cast<BYTE*>(GEngine) + 0x118) != RemapLevel)
	{
		ClearSaveRemap();
		return 0;
	}

	return 1;
}

static BYTE* FindRemapInfo(void* Map, UObject* Package)
{
	BYTE* Data = *reinterpret_cast<BYTE**>(reinterpret_cast<BYTE*>(Map) + 0x28);
	INT Num = (*reinterpret_cast<INT*>(reinterpret_cast<BYTE*>(Map) + 0x2C) << 3) >> 3;

	for(INT i = 0; i < Num; ++i)
	{
		if(*reinterpret_cast<UObject**>(Data + i * 0x40 + 0x08) == Package)
			return Data + i * 0x40;
	}

	return NULL;
}

static INT __fastcall ObjectToIndexOverride(void* Map, DWORD Edx, UObject* Object)
{
	// Connection maps hand it to the master map (+0x30) through this slot again
	if(Object && !*reinterpret_cast<void**>(reinterpret_cast<BYTE*>(Map) + 0x30) && RemapActive())
	{
		INT* Local = RemapObjectToLocal.Find(Object);

		if(Local)
		{
			BYTE* Info = FindRemapInfo(Map, RemapPackage);

			if(*Local < 0 || !Info || *Local >= *reinterpret_cast<INT*>(Info + 0x28))
				return INDEX_NONE;

			++RemapHits;
			return *reinterpret_cast<INT*>(Info + 0x24) + *Local;
		}
	}

	return OriginalObjectToIndex(Map, Edx, Object);
}

static UObject* __fastcall IndexToObjectOverride(void* Map, DWORD Edx, INT Index, UBOOL bLoad)
{
	if(!*reinterpret_cast<void**>(reinterpret_cast<BYTE*>(Map) + 0x30) && RemapActive())
	{
		BYTE* Info = FindRemapInfo(Map, RemapPackage);

		if(Info)
		{
			INT Local = Index - *reinterpret_cast<INT*>(Info + 0x24);

			if(Local >= 0 && Local < *reinterpret_cast<INT*>(Info + 0x28))
			{
				if(Local < RemapLocalToObject.Num() && RemapLocalToObject[Local])
					return RemapLocalToObject[Local];

				// Not in the save: loading it would put the clean map's object into the level a second time
				return OriginalIndexToObject(Map, Edx, Index, 0);
			}
		}
	}

	return OriginalIndexToObject(Map, Edx, Index, bLoad);
}

// Engine.dll's vtables point at its import thunks (jmp dword ptr [IAT]), not at Core.dll's functions
static void* FollowImportThunk(void* Code)
{
	BYTE* Bytes = reinterpret_cast<BYTE*>(Code);

	if(Bytes && Bytes[0] == 0xFF && Bytes[1] == 0x25)
		return **reinterpret_cast<void***>(Bytes + 2);

	return Code;
}

static void InstallPackageMapOverride(void* Map)
{
	if(OriginalObjectToIndex)
		return;

	HMODULE CoreDll = GetModuleHandleA("Core.dll");
	void* ObjectToIndex = CoreDll ? GetProcAddress(CoreDll, "?ObjectToIndex@UPackageMap@@UAEHPAVUObject@@@Z") : NULL;
	void* IndexToObject = CoreDll ? GetProcAddress(CoreDll, "?IndexToObject@UPackageMap@@UAEPAVUObject@@HH@Z") : NULL;
	void** VTable = *reinterpret_cast<void***>(Map);

	if(!ObjectToIndex || !IndexToObject || FollowImportThunk(VTable[33]) != ObjectToIndex || FollowImportThunk(VTable[34]) != IndexToObject)
	{
		debugf(NAME_Warning, "ModCoop: package map slots not as measured, clients can't follow a loaded save");
		return;
	}

	OriginalObjectToIndex = PatchVTable(Map, 33, &ObjectToIndexOverride);
	OriginalIndexToObject = PatchVTable(Map, 34, &IndexToObjectOverride);
	debugf("ModCoop: Installed the save remap of the package map");
}

/*
 * Export full names of a package file, "Class Root.Outer.Name" like UObject::GetFullName. In game the engine renames loaded objects
 * (InGameTempName), so a save's objects can only be told by their index in the save's file. Format of version 159 (SWRC), read from the
 * files: summary tag, version, licensee, flags, then count and offset of names, exports, imports; a name is a compact index length, the
 * characters and 4 bytes of flags; an import: class package, class name (compact), outer (int), name (compact); an export: class,
 * super (compact), outer (int), one more compact index (unknown), name (compact), flags, size, offset (4 bytes each).
 */
struct FPackageReader
{
	const BYTE* Data;
	INT Size, Pos;
	UBOOL bError;

	FPackageReader(const TArray<BYTE>& Bytes, INT Start) : Data(&Bytes[0]), Size(Bytes.Num()), Pos(Start), bError(Start < 0 || Start >= Bytes.Num()) {}

	BYTE Byte()
	{
		if(Pos >= Size)
		{
			bError = 1;
			return 0;
		}

		return Data[Pos++];
	}

	INT Int()
	{
		INT Value = Byte();
		Value |= Byte() << 8;
		Value |= Byte() << 16;
		Value |= Byte() << 24;
		return Value;
	}

	INT Compact()
	{
		BYTE B = Byte();
		UBOOL bNegative = (B & 0x80) != 0;
		INT Value = B & 0x3F;

		if(B & 0x40)
		{
			INT Shift = 6;

			do
			{
				B = Byte();
				Value |= (B & 0x7F) << Shift;
				Shift += 7;
			} while((B & 0x80) && Shift < 32 && !bError);
		}

		return bNegative ? -Value : Value;
	}
};

static UBOOL ReadExportFullNames(const TCHAR* Filename, const TCHAR* Root, TArray<FString>& Out)
{
	TArray<BYTE> Bytes;

	if(!appLoadFileToArray(Bytes, Filename) || Bytes.Num() < 36)
		return 0;

	FPackageReader Header(Bytes, 8);
	Header.Int();  // Package flags
	INT NameCount = Header.Int(), NameOffset = Header.Int(), ExportCount = Header.Int(), ExportOffset = Header.Int();
	INT ImportCount = Header.Int(), ImportOffset = Header.Int();

	if(NameCount <= 0 || ExportCount <= 0 || ImportCount < 0 || NameCount > 1000000 || ExportCount > 1000000 || ImportCount > 1000000)
		return 0;

	TArray<FString> Names;
	FPackageReader R(Bytes, NameOffset);

	for(INT i = 0; i < NameCount && !R.bError; ++i)
	{
		INT Length = R.Compact();

		if(Length < 0 || R.Pos + Length > R.Size)
			return 0;

		FString Name;

		for(INT c = 0; c < Length && R.Data[R.Pos + c]; ++c)
			Name += FString::Printf(TEXT("%c"), (TCHAR)R.Data[R.Pos + c]);

		R.Pos += Length;
		R.Int();
		new(Names) FString(Name);
	}

	TArray<INT> ImportNames;
	FPackageReader I(Bytes, ImportOffset);

	for(INT i = 0; i < ImportCount && !I.bError; ++i)
	{
		I.Compact();
		I.Compact();
		I.Int();
		ImportNames.AddItem(I.Compact());
	}

	TArray<INT> ExportClasses, ExportOuters, ExportNames;
	FPackageReader E(Bytes, ExportOffset);

	for(INT i = 0; i < ExportCount && !E.bError; ++i)
	{
		ExportClasses.AddItem(E.Compact());
		E.Compact();
		ExportOuters.AddItem(E.Int());
		E.Compact();
		ExportNames.AddItem(E.Compact());
		E.Int();
		E.Int();
		E.Int();
	}

	if(R.bError || I.bError || E.bError)
		return 0;

	for(INT i = 0; i < ExportCount; ++i)
	{
		if(ExportNames[i] < 0 || ExportNames[i] >= NameCount)
			return 0;
	}

	Out.Empty();

	for(INT i = 0; i < ExportCount; ++i)
	{
		FString Path = Names[ExportNames[i]];
		INT Outer = ExportOuters[i];

		for(INT Depth = 0; Outer > 0 && Outer <= ExportCount && Depth < 64; ++Depth)
		{
			Path = Names[ExportNames[Outer - 1]] + TEXT(".") + Path;
			Outer = ExportOuters[Outer - 1];
		}

		INT Class = ExportClasses[i];
		FString ClassName = TEXT("Class");

		if(Class < 0 && -Class - 1 < ImportNames.Num() && ImportNames[-Class - 1] >= 0 && ImportNames[-Class - 1] < NameCount)
			ClassName = Names[ImportNames[-Class - 1]];
		else if(Class > 0 && Class <= ExportCount)
			ClassName = Names[ExportNames[Class - 1]];

		new(Out) FString(ClassName + TEXT(" ") + Root + TEXT(".") + Path);
	}

	return 1;
}

static void BuildSaveRemap(AActor* A, const FString& SaveFile, FString* Out)
{
	ClearSaveRemap();

	ULevel* Level = A ? A->XLevel : NULL;
	UObject* Package = Level ? (UObject*)Level->GetPackage() : NULL;
	void* Map = NULL;

	for(TObjectIterator<UNetDriver> It; It && !Map; ++It)
		Map = *reinterpret_cast<void**>(reinterpret_cast<BYTE*>(*It) + 0x3C);

	if(!Package || !Map)
	{
		*Out = TEXT("no level or no net driver");
		return;
	}

	BYTE* Info = FindRemapInfo(Map, Package);
	HMODULE CoreDll = GetModuleHandleA("Core.dll");
	FInfoGetLinkerFunc InfoGetLinker = (FInfoGetLinkerFunc)GetProcAddress(CoreDll, "?GetLinker@FPackageInfo@@QBEPAVULinkerLoad@@K@Z");
	void* MapLinker = (Info && InfoGetLinker) ? InfoGetLinker(Info, 0, 0x10) : NULL;

	if(!Info || !MapLinker)
	{
		*Out = FString::Printf(TEXT("package %s not in the package map or no linker"), Package->GetName());
		return;
	}

	// Both tables from the files: the save's linker is gone after the load, and objects in game are called InGameTempName
	INT Count = *reinterpret_cast<INT*>(Info + 0x28);
	FString MapFile = FString(TEXT("..\\Maps\\")) + Package->GetName() + TEXT(".ctm");
	TArray<FString> MapNames, SaveNames;

	if(!ReadExportFullNames(*MapFile, Package->GetName(), MapNames) || MapNames.Num() != Count)
	{
		*Out = FString::Printf(TEXT("can't read %s or its %i exports aren't the %i of the package map"), *MapFile, MapNames.Num(), Count);
		return;
	}

	if(!ReadExportFullNames(*SaveFile, Package->GetName(), SaveNames))
	{
		*Out = FString::Printf(TEXT("can't read %s"), *SaveFile);
		return;
	}

	TMap<FString, INT> MapExports;

	for(INT i = 0; i < MapNames.Num(); ++i)
		MapExports.Set(*MapNames[i], i);

	INT Paired = 0, Unpaired = 0, ClassMismatch = 0, FromMap = 0;
	FString FirstUnpaired, FirstPaired, FirstMismatch;
	RemapLocalToObject.AddZeroed(Count);

	for(FObjectIterator It; It; ++It)
	{
		UObject* Object = *It;

		// After the load the save's linker is gone, its objects keep their index in it (what ObjectToIndex uses)
		if((UObject*)Object->GetPackage() != Package || Object->GetLinkerIndex() == INDEX_NONE)
			continue;

		if((void*)Object->GetLinker() == MapLinker)
		{
			++FromMap;
			continue;
		}

		INT Index = Object->GetLinkerIndex();
		FString ClassPrefix = FString(Object->GetClass()->GetName()) + TEXT(" ");

		// The class has to be the one of that export in the save: anything else isn't from the save
		if(Index >= SaveNames.Num() || SaveNames[Index].Left(ClassPrefix.Len()) != ClassPrefix)
		{
			if(!ClassMismatch++)
				FirstMismatch = FString::Printf(TEXT("%s index %i"), Object->GetFullName(), Index);

			continue;
		}

		INT* Local = MapExports.Find(*SaveNames[Index]);

		if(Local)
		{
			RemapObjectToLocal.Set(Object, *Local);
			RemapLocalToObject[*Local] = Object;

			if(!Paired++)
				FirstPaired = FString::Printf(TEXT("%s %i -> %i"), *SaveNames[Index], Index, *Local);
		}
		else
		{
			RemapObjectToLocal.Set(Object, INDEX_NONE);

			if(!Unpaired++)
				FirstUnpaired = SaveNames[Index];
		}
	}

	InstallPackageMapOverride(Map);

	// A level loaded from its map (PostLoadBeginPlay runs then too) has nothing to remap
	if(Paired > 0)
	{
		RemapPackage = Package;
		RemapLevel = Level;
	}
	else
		ClearSaveRemap();

	*Out = FString::Printf(TEXT("%s: %i exports in the map, %i in the save; %i objects paired (first: %s), %i without a pair (first: %s), %i of another class (first: %s), %i from the map%s"),
	                       Package->GetName(), Count, SaveNames.Num(), Paired, Paired ? *FirstPaired : TEXT("none"), Unpaired, Unpaired ? *FirstUnpaired : TEXT("none"),
	                       ClassMismatch, ClassMismatch ? *FirstMismatch : TEXT("none"), FromMap, OriginalObjectToIndex ? TEXT("") : TEXT(", NOT INSTALLED"));
}

// No objects with destructors in a function with __try
static UBOOL SafeBuildSaveRemap(AActor* A, const FString& SaveFile, FString* Out)
{
	__try
	{
		BuildSaveRemap(A, SaveFile, Out);
		return 1;
	}
	__except(AccessViolationFilter(GetExceptionCode()))
	{
		RemapPackage = NULL;
		return 0;
	}
}

/*
 * The single player HUD in coop (the visor). The helmet draws it when the option bVisor is on, the screen isn't split and LevelInfo.NetMode
 * (byte 0x440) is 0: in network games never, for the host neither. Three helmet functions read NetMode for it (scan of the helmet's code for byte
 * reads and compares of [reg+0x440] in all of Engine.dll, 2026-11-11): DrawStanceText (RVA 0x12D9D3), DrawHUD (0x130D8E: frame, layout, bars, 16 places depend on it) and
 * DrawHelmet (0x136118: the helmet around the view); each mov al,[reg+0x440] becomes xor al,al (as standalone). A fourth one compares:
 * FPlayerSceneNode::Render (0x1B1824, cmp [ecx+0x440],dl) decides whether the world goes to the working target the helmet bends onto the
 * visor; without it the world was drawn straight and the helmet put an old copy over it (the picture was doubled, test 2026-11-11). It
 * becomes cmp dl,dl. All while a coop HUD exists (CoopHUD), put back after it, so other games keep theirs. The bytes are checked first.
 */
struct FVisorCheck
{
	DWORD RVA;
	BYTE Original[6];
	BYTE Patched[6];
};

static const FVisorCheck VisorChecks[] =
{
	{0x12D9D3, {0x8A, 0x82, 0x40, 0x04, 0x00, 0x00}, {0x32, 0xC0, 0x90, 0x90, 0x90, 0x90}},
	{0x130D8E, {0x8A, 0x81, 0x40, 0x04, 0x00, 0x00}, {0x32, 0xC0, 0x90, 0x90, 0x90, 0x90}},
	{0x136118, {0x8A, 0x81, 0x40, 0x04, 0x00, 0x00}, {0x32, 0xC0, 0x90, 0x90, 0x90, 0x90}},
	{0x1B1824, {0x38, 0x91, 0x40, 0x04, 0x00, 0x00}, {0x38, 0xD2, 0x90, 0x90, 0x90, 0x90}},
};

/*
 * In visor mode FPlayerSceneNode::Render draws the helmet's HUD into a working target (call of UHelmet::DrawHUD at RVA 0x1B1EA1) that
 * DrawHelmet then bends onto the visor and moves with the head. Script HUDs draw later, straight on the screen: the squad icons of CoopHUD
 * stayed flat beside the helmet's own (test 2026-11-11). That call goes to DrawHUDInWorkingTarget instead, which after the helmet calls
 * CoopHUD.DrawVisorSquad with the viewport's canvas: the helmet draws through the same FCanvasUtil (UCanvas+0x88), so the icons land in
 * the working target too. Offsets measured: UViewport+0x60 Canvas.
 */
typedef void (__fastcall* FDrawHUDFunc)(void* Helmet, DWORD Edx, void* Viewport, void* RI);

static const DWORD DrawHUDCallRVA = 0x1B1EA1;
static const DWORD DrawHUDRVA = 0x130B60;
static UObject* VisorHUD = NULL;  // CoopHUD of this machine while the visor HUD is on (SetVisorHUD)

static void __fastcall DrawHUDInWorkingTarget(void* Helmet, DWORD Edx, void* Viewport, void* RI)
{
	reinterpret_cast<FDrawHUDFunc>(reinterpret_cast<BYTE*>(GetModuleHandleA("Engine.dll")) + DrawHUDRVA)(Helmet, Edx, Viewport, RI);

	UObject* Canvas = Viewport ? *reinterpret_cast<UObject**>(reinterpret_cast<BYTE*>(Viewport) + 0x60) : NULL;

	if(!VisorHUD || !Canvas || VisorHUD->IsPendingKill())
		return;

	static FName NDrawVisorSquad(TEXT("DrawVisorSquad"));
	UFunction* Function = VisorHUD->FindFunction(NDrawVisorSquad);

	if(Function)
	{
		struct { UObject* C; } Parms;
		Parms.C = Canvas;
		VisorHUD->ProcessEvent(Function, &Parms);
	}
}

// The call of DrawHUD at RVA 0x1B1EA1 to DrawHUDInWorkingTarget and back. E8 rel32, checked first
static FString SetDrawHUDCall(UBOOL bOn)
{
	BYTE* EngineBase = reinterpret_cast<BYTE*>(GetModuleHandleA("Engine.dll"));

	if(!EngineBase)
		return TEXT(" call: no Engine.dll");

	BYTE* Call = EngineBase + DrawHUDCallRVA;
	BYTE* Original = EngineBase + DrawHUDRVA;
	BYTE* Target = bOn ? reinterpret_cast<BYTE*>(&DrawHUDInWorkingTarget) : Original;
	INT Current = *reinterpret_cast<INT*>(Call + 1);

	if(Call[0] != 0xE8 || (Call + 5 + Current != Original && Call + 5 + Current != reinterpret_cast<BYTE*>(&DrawHUDInWorkingTarget)))
		return TEXT(" call: unexpected bytes, not changed");

	DWORD OldProtect;

	if(!VirtualProtect(Call, 5, PAGE_EXECUTE_READWRITE, &OldProtect))
		return TEXT(" call: VirtualProtect failed");

	*reinterpret_cast<INT*>(Call + 1) = static_cast<INT>(Target - (Call + 5));
	VirtualProtect(Call, 5, OldProtect, &OldProtect);
	FlushInstructionCache(GetCurrentProcess(), Call, 5);
	return bOn ? TEXT(" call on") : TEXT(" call off");
}

/*
 * Names over the squad (SEV, FIXER): APawn::PostRender (Engine.dll RVA 0x189C90) draws a member's GetHudNickname when it is in the AI squad
 * of the viewer (PlayerController.Pawn.Squad, Pawn+0x440, ASquad member index at RVA 0x2A430) and is targeted, or always in tactical vision.
 * Clients have no squad and the host's squad doesn't hold the members played by clients: no names in coop (2026-11-12). The squad check
 * (RVA 0x189CF7, 18 bytes: mov eax,[eax+0x440]; test; je; push edi; mov ecx,eax; call index) becomes push edi; push eax; call
 * CoopSquadIndex; nops: a member of the squad as before, and in coop every other Delta commando counts. On and off with the visor HUD.
 */
typedef INT (__fastcall* FSquadIndexFunc)(void* Squad, DWORD Edx, AActor* Member);

static const DWORD SquadCheckRVA = 0x189CF7;
static const DWORD SquadIndexRVA = 0x2A430;
static const BYTE SquadCheckOriginal[18] = {0x8B, 0x80, 0x40, 0x04, 0x00, 0x00, 0x85, 0xC0, 0x74, 0x32, 0x57, 0x8B, 0xC8, 0xE8, 0x27, 0x07, 0xEA, 0xFF};
static UClass* CloneCommandoClass = NULL;

static INT __stdcall CoopSquadIndex(BYTE* Viewer, AActor* Member)
{
	void* Squad = Viewer ? *reinterpret_cast<void**>(Viewer + 0x440) : NULL;

	if(Squad)
	{
		INT Index = reinterpret_cast<FSquadIndexFunc>(reinterpret_cast<BYTE*>(GetModuleHandleA("Engine.dll")) + SquadIndexRVA)(Squad, 0, Member);

		if(Index >= 0)
			return Index;
	}

	if(!CloneCommandoClass)
		CloneCommandoClass = FindObject<UClass>(ANY_PACKAGE, TEXT("CloneCommando"));

	if(Member && reinterpret_cast<BYTE*>(Member) != Viewer && CloneCommandoClass && Member->IsA(CloneCommandoClass) && !Member->bDeleteMe)
		return 1;

	return INDEX_NONE;
}

static FString SetSquadNames(UBOOL bOn)
{
	BYTE* EngineBase = reinterpret_cast<BYTE*>(GetModuleHandleA("Engine.dll"));

	if(!EngineBase)
		return TEXT(" names: no Engine.dll");

	BYTE* Code = EngineBase + SquadCheckRVA;
	BYTE Patched[18];
	Patched[0] = 0x57;  // push edi (the pawn drawn)
	Patched[1] = 0x50;  // push eax (the viewer's pawn)
	Patched[2] = 0xE8;  // call CoopSquadIndex
	*reinterpret_cast<INT*>(Patched + 3) = static_cast<INT>(reinterpret_cast<BYTE*>(&CoopSquadIndex) - (Code + 7));

	for(INT i = 7; i < 18; ++i)
		Patched[i] = 0x90;

	const BYTE* To = bOn ? Patched : SquadCheckOriginal;
	const BYTE* From = bOn ? SquadCheckOriginal : Patched;

	if(appMemcmp(Code, To, 18) == 0)
		return TEXT(" names already");

	if(appMemcmp(Code, From, 18) != 0)
		return TEXT(" names: unexpected bytes, not changed");

	DWORD OldProtect;

	if(!VirtualProtect(Code, 18, PAGE_EXECUTE_READWRITE, &OldProtect))
		return TEXT(" names: VirtualProtect failed");

	appMemcpy(Code, To, 18);
	VirtualProtect(Code, 18, OldProtect, &OldProtect);
	FlushInstructionCache(GetCurrentProcess(), Code, 18);
	return bOn ? TEXT(" names on") : TEXT(" names off");
}

void UCoopNative::execSetVisorHUD(FFrame& Stack, void* Result)
{
	P_GET_UBOOL(bOn);
	P_GET_OBJECT_OPTX(UObject, HUD, NULL);
	P_FINISH;

	FString Text;
	VisorHUD = bOn ? HUD : NULL;
	BYTE* EngineBase = reinterpret_cast<BYTE*>(GetModuleHandleA("Engine.dll"));

	for(INT i = 0; EngineBase && i < ARRAY_COUNT(VisorChecks); ++i)
	{
		BYTE* Code = EngineBase + VisorChecks[i].RVA;
		const BYTE* From = bOn ? VisorChecks[i].Original : VisorChecks[i].Patched;
		const BYTE* To = bOn ? VisorChecks[i].Patched : VisorChecks[i].Original;
		DWORD OldProtect;

		if(appMemcmp(Code, To, 6) == 0)
			Text += FString::Printf(TEXT(" %X already"), VisorChecks[i].RVA);
		else if(appMemcmp(Code, From, 6) != 0)
			Text += FString::Printf(TEXT(" %X unexpected bytes, not changed"), VisorChecks[i].RVA);
		else if(!VirtualProtect(Code, 6, PAGE_EXECUTE_READWRITE, &OldProtect))
			Text += FString::Printf(TEXT(" %X VirtualProtect failed"), VisorChecks[i].RVA);
		else
		{
			appMemcpy(Code, To, 6);
			VirtualProtect(Code, 6, OldProtect, &OldProtect);
			FlushInstructionCache(GetCurrentProcess(), Code, 6);
			Text += FString::Printf(TEXT(" %X %s"), VisorChecks[i].RVA, bOn ? TEXT("on") : TEXT("off"));
		}
	}

	Text += SetDrawHUDCall(bOn);
	Text += SetSquadNames(bOn);
	*(FString*)Result = Text;
}

/*
 * After a save is loaded the level keeps the URL that was saved with it: UGameEngine::LoadMap copies the travel URL into ULevel::URL
 * (offset 0x44, Engine.dll+0x11EE78) only without the option "load". The saved one has the host 0.0.0.0 of the listening server, so the
 * next level change, relative to it, went to 0.0.0.0/<map> as a client and the level never changed (the user's game RAS_03C, 2026-11-11).
 * The host part is cleared, like the URL of a map loaded the normal way. Returns what it was.
 */
void UCoopNative::execFixLoadedLevelURL(FFrame& Stack, void* Result)
{
	P_GET_OBJECT(AActor, A);
	P_FINISH;

	if(!A || !A->XLevel)
	{
		*(FString*)Result = TEXT("no level");
		return;
	}

	FURL* URL = reinterpret_cast<FURL*>(reinterpret_cast<BYTE*>(A->XLevel) + 0x44);
	FString Text = FString::Printf(TEXT("host '%s' port %i map '%s'"), *URL->Host, URL->Port, *URL->Map);
	URL->Host = TEXT("");
	*(FString*)Result = Text;
}

/*
 * The GUID of this build of ModCoop.u, from its file (bytes 36-51 of the package summary, version 159). A save holds objects of the mod:
 * a save from another build is refused (CoopSaveSlots.IsCompatible).
 */
void UCoopNative::execModPackageGuid(FFrame& Stack, void* Result)
{
	P_FINISH;

	static FString Cached;

	if(Cached.Len() == 0)
	{
		TArray<BYTE> Bytes;

		if(appLoadFileToArray(Bytes, TEXT("ModCoop.u")) && Bytes.Num() >= 52)
		{
			for(INT i = 36; i < 52; ++i)
				Cached += FString::Printf(TEXT("%02X"), Bytes[i]);
		}
	}

	*(FString*)Result = Cached;
}

void UCoopNative::execRemapSavedLevel(FFrame& Stack, void* Result)
{
	P_GET_OBJECT(AActor, A);
	P_GET_STR(SaveName);
	P_FINISH;

	FString Text;
	FString SaveFile = GSavePath + TEXT("\\") + SaveName + TEXT("\\") + SaveName + TEXT(".cts");

	if(!SafeBuildSaveRemap(A, SaveFile, &Text))
		Text = TEXT("CRASHED");

	*(FString*)Result = Text;
}

// A level change ends the remap of a loaded save (its objects go away)
typedef ULevel* (__fastcall* FLoadMapFunc)(UObject* Engine, DWORD Edx, const FURL& URL, UPendingLevel* Pending, const void* TravelInfo, FString& Error, UBOOL bSomething);

static FLoadMapFunc OriginalLoadMap = NULL;

static ULevel* __fastcall LoadMapOverride(UObject* Engine, DWORD Edx, const FURL& URL, UPendingLevel* Pending, const void* TravelInfo, FString& Error, UBOOL bSomething)
{
	ClearSaveRemap();
	return OriginalLoadMap(Engine, Edx, URL, Pending, TravelInfo, Error, bSomething);
}

static void InstallLoadMapOverride()
{
	HMODULE EngineDll = GetModuleHandleA("Engine.dll");
	void* LoadMap = EngineDll ? GetProcAddress(EngineDll, "?LoadMap@UGameEngine@@UAEPAVULevel@@ABVFURL@@PAVUPendingLevel@@PBV?$TMap@VFString@@V1@@@AAVFString@@_N@Z") : NULL;

	if(OriginalLoadMap || !GEngine || !LoadMap)
		return;

	void** VTable = *reinterpret_cast<void***>(GEngine);

	for(INT i = 0; i < 128; ++i)
	{
		if(VTable[i] == LoadMap)
		{
			OriginalLoadMap = PatchVTable(GEngine, i, &LoadMapOverride);
			debugf("ModCoop: Installed the LoadMap hook (UGameEngine vtable slot %i)", i);
			return;
		}
	}

	debugf(NAME_Warning, "ModCoop: UGameEngine::LoadMap slot not found");
}

void UCoopNative::execInstallClientFixes(FFrame& Stack, void* Result)
{
	P_FINISH;

	InstallCrashLog();
	InstallSelectTargetTypeGuard();
	InstallLoadMapOverride();

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

/*
 * System information for test reports. The engine's own lines are wrong on current systems (Windows NT 6.2 because of the
 * compatibility shim, "Unknown processor", the memory capped at 4 GB) and say nothing about the graphics card or the wrappers
 * many players use (dgVoodoo, DXVK, ReShade as d3d8/d3d9/dxgi.dll next to the exe).
 */
static void LogFileInfo(const char* Dir, const char* Name)
{
	char Path[MAX_PATH];
	_snprintf_s(Path, sizeof(Path), _TRUNCATE, "%s\\%s", Dir, Name);

	WIN32_FILE_ATTRIBUTE_DATA Data;

	if(!GetFileAttributesExA(Path, GetFileExInfoStandard, &Data))
		return;

	char Product[128] = "";
	DWORD Handle = 0;
	DWORD Size = GetFileVersionInfoSizeA(Path, &Handle);

	if(Size > 0 && Size < 1024 * 1024)
	{
		BYTE* Buffer = new BYTE[Size];

		if(GetFileVersionInfoA(Path, 0, Size, Buffer))
		{
			struct LangCodePage { WORD Language; WORD CodePage; }* Translation = NULL;
			UINT Len = 0;

			if(VerQueryValueA(Buffer, "\\VarFileInfo\\Translation", reinterpret_cast<void**>(&Translation), &Len) && Len >= sizeof(LangCodePage))
			{
				char Key[64];
				char* Value = NULL;
				UINT ValueLen = 0;

				_snprintf_s(Key, sizeof(Key), _TRUNCATE, "\\StringFileInfo\\%04x%04x\\ProductName", Translation->Language, Translation->CodePage);

				if(VerQueryValueA(Buffer, Key, reinterpret_cast<void**>(&Value), &ValueLen) && Value)
					_snprintf_s(Product, sizeof(Product), _TRUNCATE, "%s", Value);

				_snprintf_s(Key, sizeof(Key), _TRUNCATE, "\\StringFileInfo\\%04x%04x\\ProductVersion", Translation->Language, Translation->CodePage);

				if(VerQueryValueA(Buffer, Key, reinterpret_cast<void**>(&Value), &ValueLen) && Value)
				{
					size_t Used = strlen(Product);
					_snprintf_s(Product + Used, sizeof(Product) - Used, _TRUNCATE, " %s", Value);
				}
			}
		}

		delete[] Buffer;
	}

	SYSTEMTIME Time;
	FileTimeToSystemTime(&Data.ftLastWriteTime, &Time);
	debugf("ModCoop: System: file %s %u bytes %04u-%02u-%02u %s", Name, Data.nFileSizeLow, Time.wYear, Time.wMonth, Time.wDay, Product);
}

void UCoopNative::execLogSystemInfo(FFrame& Stack, void* Result)
{
	P_FINISH;

	// Windows (RtlGetVersion isn't affected by the compatibility shim)
	typedef LONG (WINAPI* RtlGetVersionFunc)(OSVERSIONINFOW*);
	OSVERSIONINFOW Os;
	appMemzero(&Os, sizeof(Os));
	Os.dwOSVersionInfoSize = sizeof(Os);
	RtlGetVersionFunc RtlGetVersion = reinterpret_cast<RtlGetVersionFunc>(GetProcAddress(GetModuleHandleA("ntdll.dll"), "RtlGetVersion"));

	if(RtlGetVersion)
		RtlGetVersion(&Os);

	debugf("ModCoop: System: Windows %u.%u build %u%s", Os.dwMajorVersion, Os.dwMinorVersion, Os.dwBuildNumber,
	       GetProcAddress(GetModuleHandleA("ntdll.dll"), "wine_get_version") ? " (Wine/Proton)" : "");

	// Processor
	char Cpu[128] = "unknown";
	DWORD CpuSize = sizeof(Cpu);
	HKEY Key;

	if(RegOpenKeyExA(HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", 0, KEY_READ, &Key) == ERROR_SUCCESS)
	{
		RegQueryValueExA(Key, "ProcessorNameString", NULL, NULL, reinterpret_cast<BYTE*>(Cpu), &CpuSize);
		RegCloseKey(Key);
	}

	SYSTEM_INFO Info;
	GetSystemInfo(&Info);

	MEMORYSTATUSEX Memory;
	Memory.dwLength = sizeof(Memory);
	GlobalMemoryStatusEx(&Memory);

	debugf("ModCoop: System: CPU %s, %u threads, RAM %u MB", Cpu, Info.dwNumberOfProcessors, static_cast<DWORD>(Memory.ullTotalPhys / (1024 * 1024)));

	// Graphics cards and the desktop
	DISPLAY_DEVICEA Device;

	for(DWORD i = 0; i < 8; ++i)
	{
		appMemzero(&Device, sizeof(Device));
		Device.cb = sizeof(Device);

		if(!EnumDisplayDevicesA(NULL, i, &Device, 0))
			break;

		if(Device.StateFlags & DISPLAY_DEVICE_ACTIVE)
			debugf("ModCoop: System: GPU %s%s", Device.DeviceString, (Device.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) ? " (primary)" : "");
	}

	DEVMODEA Mode;
	appMemzero(&Mode, sizeof(Mode));
	Mode.dmSize = sizeof(Mode);

	if(EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &Mode))
		debugf("ModCoop: System: desktop %ux%u %u Hz", Mode.dmPelsWidth, Mode.dmPelsHeight, Mode.dmDisplayFrequency);

	// The game and what's next to it
	char Exe[MAX_PATH] = "";
	GetModuleFileNameA(NULL, Exe, MAX_PATH);
	debugf("ModCoop: System: exe %s", Exe);

	char Dir[MAX_PATH];
	_snprintf_s(Dir, sizeof(Dir), _TRUNCATE, "%s", Exe);
	char* Slash = strrchr(Dir, '\\');

	if(Slash)
		*Slash = 0;

	const char* Exename = Slash ? Slash + 1 : Exe;
	LogFileInfo(Dir, Exename);

	static const char* Files[] = { "Mod.dll", "ModCoop.dll", "d3d8.dll", "d3d9.dll", "dxgi.dll", "d3d11.dll", "ddraw.dll", "dinput8.dll", "dsound.dll",
	                               "winmm.dll", "version.dll", "opengl32.dll", "dgVoodoo.conf", "dxvk.conf", "ReShade.ini", "dgVoodooCpl.exe", "OpenAL32.dll" };

	for(INT i = 0; i < ARRAY_COUNT(Files); ++i)
		LogFileInfo(Dir, Files[i]);

	// Which Direct3D the game really uses
	static const char* Modules[] = { "d3d8.dll", "d3d9.dll", "dxgi.dll" };

	for(INT i = 0; i < ARRAY_COUNT(Modules); ++i)
	{
		HMODULE Module = GetModuleHandleA(Modules[i]);
		char ModulePath[MAX_PATH];

		if(Module && GetModuleFileNameA(Module, ModulePath, MAX_PATH))
			debugf("ModCoop: System: loaded %s", ModulePath);
	}
}

/*
 * The Steam connection is a separate program (CoopTunnel/Main.cpp): a failure in it can't take the game down, and the game only has to talk to
 * 127.0.0.1. The game starts it and reads its status file, named after the game's process so that two copies of the game on one PC
 * (tests) don't mix.
 * Logging: "ModCoop: relay".
 */
static HANDLE GRelayProcess = NULL;
static char   GRelayArgs[256] = "";

static void RelayStatusPath(char* Out, INT OutSize)
{
	char Temp[MAX_PATH] = "";
	GetTempPathA(MAX_PATH, Temp);
	_snprintf_s(Out, OutSize, _TRUNCATE, "%sCoopTunnel-%u.status", Temp, GetCurrentProcessId());
}

void UCoopNative::execStartRelay(FFrame& Stack, void* Result)
{
	P_GET_STR(Args);
	P_FINISH;

	if(GRelayProcess && strcmp(GRelayArgs, *Args) == 0 && WaitForSingleObject(GRelayProcess, 0) == WAIT_TIMEOUT)
		return;

	if(GRelayProcess)
	{
		TerminateProcess(GRelayProcess, 0);
		WaitForSingleObject(GRelayProcess, 2000);
		CloseHandle(GRelayProcess);
		GRelayProcess = NULL;
	}

	char Status[MAX_PATH];
	RelayStatusPath(Status, sizeof(Status));
	DeleteFileA(Status);

	char Dir[MAX_PATH] = "";
	GetModuleFileNameA(NULL, Dir, MAX_PATH);
	char* Slash = strrchr(Dir, '\\');

	if(Slash)
		*Slash = 0;

	strcat_s(Dir, "\\..\\CoopTunnel");

	// TEST: extra arguments for runs on one PC (--direct instead of Steam)
	char Extra[128] = "";
	GetEnvironmentVariableA("COOP_RELAY_ARGS", Extra, sizeof(Extra));

	char CommandLine[1024];
	_snprintf_s(CommandLine, sizeof(CommandLine), _TRUNCATE, "\"%s\\CoopTunnel.exe\" %s --parent %u %s", Dir, *Args, GetCurrentProcessId(), Extra);

	STARTUPINFOA        StartupInfo = {sizeof(StartupInfo)};
	PROCESS_INFORMATION ProcessInfo = {0};

	// steam_appid.txt is looked up in the working directory
	if(CreateProcessA(NULL, CommandLine, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, Dir, &StartupInfo, &ProcessInfo))
	{
		CloseHandle(ProcessInfo.hThread);
		GRelayProcess = ProcessInfo.hProcess;
		strcpy_s(GRelayArgs, *Args);
		debugf("ModCoop: relay started: %s", strchr(*Args, ' ') ? "join" : *Args);
	}
	else
	{
		debugf(NAME_Warning, "ModCoop: relay not started, error %u", GetLastError());
	}
}

void UCoopNative::execReadRelayStatus(FFrame& Stack, void* Result)
{
	P_FINISH;

	char Path[MAX_PATH];
	RelayStatusPath(Path, sizeof(Path));

	char   Text[4096] = "";
	DWORD  Size = 0;
	HANDLE File = CreateFileA(Path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);

	if(File != INVALID_HANDLE_VALUE)
	{
		ReadFile(File, Text, sizeof(Text) - 1, &Size, NULL);
		CloseHandle(File);
		Text[Size] = 0;
	}

	*static_cast<FString*>(Result) = Text;
}

void UCoopNative::execGetHostAddresses(FFrame& Stack, void* Result)
{
	P_FINISH;

	FString Addresses;
	char    Name[256];

	if(gethostname(Name, sizeof(Name)) == 0)
	{
		hostent* Host = gethostbyname(Name);

		for(INT i = 0; Host && Host->h_addrtype == AF_INET && Host->h_addr_list[i]; ++i)
		{
			const BYTE* Ip = reinterpret_cast<const BYTE*>(Host->h_addr_list[i]);

			// Not reachable by anybody else
			if(Ip[0] == 127 || (Ip[0] == 169 && Ip[1] == 254))
				continue;

			if(Addresses.Len() > 0)
				Addresses += ", ";

			char Text[32];
			_snprintf_s(Text, sizeof(Text), _TRUNCATE, "%u.%u.%u.%u", Ip[0], Ip[1], Ip[2], Ip[3]);
			Addresses += Text;
		}
	}

	*static_cast<FString*>(Result) = Addresses;
}

static char          GPublicAddress[64] = "";
static volatile LONG GPublicAddressReady = 0;
static LONG          GPublicAddressAsked = 0;

static DWORD WINAPI PublicAddressThread(void*)
{
	char  Text[64] = "";
	DWORD Size = 0;
	DWORD Timeout = 5000;

	if(HINTERNET Net = InternetOpenA("ModCoop", INTERNET_OPEN_TYPE_PRECONFIG, NULL, NULL, 0))
	{
		InternetSetOptionA(Net, INTERNET_OPTION_CONNECT_TIMEOUT, &Timeout, sizeof(Timeout));
		InternetSetOptionA(Net, INTERNET_OPTION_RECEIVE_TIMEOUT, &Timeout, sizeof(Timeout));

		if(HINTERNET Url = InternetOpenUrlA(Net, "https://api.ipify.org", NULL, 0, INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE, 0))
		{
			InternetReadFile(Url, Text, sizeof(Text) - 1, &Size);
			InternetCloseHandle(Url);
		}

		InternetCloseHandle(Net);
	}

	Text[Size] = 0;

	// Only an address goes on the screen, not whatever a proxy answered
	UBOOL bValid = Size >= 7;

	for(DWORD i = 0; i < Size; ++i)
	{
		if(!(Text[i] >= '0' && Text[i] <= '9') && Text[i] != '.')
			bValid = 0;
	}

	if(bValid)
	{
		strcpy_s(GPublicAddress, Text);
		InterlockedExchange(&GPublicAddressReady, 1);
	}

	return 0;
}

void UCoopNative::execGetPublicAddress(FFrame& Stack, void* Result)
{
	P_FINISH;

	if(InterlockedExchange(&GPublicAddressAsked, 1) == 0)
	{
		HANDLE Thread = CreateThread(NULL, 0, PublicAddressThread, NULL, 0, NULL);

		if(Thread)
			CloseHandle(Thread);
	}

	*static_cast<FString*>(Result) = GPublicAddressReady ? GPublicAddress : "";
}
