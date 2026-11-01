/*
 * SteamLink
 * Purpose: Steam's peer-to-peer connection (ISteamNetworking: NAT traversal, Steam's relays as a fallback) and the friends who host a
 *   game (ISteamFriends rich presence, key "connect").
 * Entry points: CreateSteamLink (Main.cpp).
 * Logging: "Steam:" lines, see Open and Advertise for the checks that show the calls work.
 * State: the library's functions, its interfaces, the pipe of manual dispatch.
 * Known limitations: the App ID comes from steam_appid.txt next to the program (6000, the game). steam_api64.dll is loaded at run time
 *   by its flat functions, so a missing file or Steam is a message, not a failed start. The declarations below follow the
 *   Steamworks flat API; the library must export these interface versions.
 */
#include "Link.h"

#include <windows.h>
#include <stdint.h>

namespace
{
	const int GAME_APP_ID             = 6000;
	const int FRIEND_FLAG_IMMEDIATE   = 4;
	const int P2P_SEND_UNRELIABLE     = 0;
	const int CALLBACK_SESSION_REQUEST = 1202;
	const int CALLBACK_SESSION_FAILED  = 1203;

	struct CallbackMessage
	{
		int32_t  User;
		int32_t  Id;
		uint8_t* Param;
		int32_t  ParamSize;
	};

	struct GamePlayed
	{
		uint64_t GameId;
		uint32_t GameIp;
		uint16_t GamePort;
		uint16_t QueryPort;
		uint64_t Lobby;
	};

	typedef bool (*InitFunc)();
	typedef void (*VoidFunc)();
	typedef int32_t (*GetPipeFunc)();
	typedef void (*RunFrameFunc)(int32_t);
	typedef bool (*NextCallbackFunc)(int32_t, CallbackMessage*);
	typedef void (*FreeCallbackFunc)(int32_t);
	typedef void* (*InterfaceFunc)();
	typedef uint64_t (*GetSteamIdFunc)(void*);
	typedef bool (*AllowRelayFunc)(void*, bool);
	typedef bool (*AcceptFunc)(void*, uint64_t);
	typedef bool (*SendFunc)(void*, uint64_t, const void*, uint32_t, int, int);
	typedef bool (*AvailableFunc)(void*, uint32_t*, int);
	typedef bool (*ReadFunc)(void*, void*, uint32_t, uint32_t*, uint64_t*, int);
	typedef int (*FriendCountFunc)(void*, int);
	typedef uint64_t (*FriendByIndexFunc)(void*, int, int);
	typedef bool (*FriendGameFunc)(void*, uint64_t, GamePlayed*);
	typedef const char* (*FriendPresenceFunc)(void*, uint64_t, const char*);
	typedef void (*RequestPresenceFunc)(void*, uint64_t);
	typedef bool (*SetPresenceFunc)(void*, const char*, const char*);
	typedef const char* (*FriendNameFunc)(void*, uint64_t);

	uint64_t ParseId(const std::string& Text)
	{
		return _strtoui64(Text.c_str(), NULL, 10);
	}

	bool IsSteamId(const char* Text)
	{
		if(Text == NULL || strlen(Text) < 5)
			return false;

		for(; *Text != 0; ++Text)
		{
			if(*Text < '0' || *Text > '9')
				return false;
		}

		return true;
	}

	// The fonts of the menus have no Cyrillic, and the status file separates with | and line ends
	std::string MenuName(const char* Name, int Number)
	{
		std::string Result;

		for(; Name != NULL && *Name != 0; ++Name)
		{
			char c = *Name;

			if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ' ' || c == '_' || c == '-' || c == '.')
				Result += c;
		}

		while(!Result.empty() && Result[0] == ' ')
			Result.erase(0, 1);

		if(Result.empty())
			Result = "STEAM FRIEND " + std::to_string(Number);

		return Result;
	}

	class SteamLink : public Link
	{
	public:
		bool Open(std::string& Error) override
		{
			char Path[MAX_PATH];
			GetModuleFileNameA(NULL, Path, MAX_PATH);
			char* Slash = strrchr(Path, '\\');

			if(Slash != NULL)
				strcpy_s(Slash + 1, MAX_PATH - (Slash + 1 - Path), "steam_api64.dll");

			Library = LoadLibraryExA(Path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);

			if(Library == NULL)
			{
				Error = "steam_api64.dll couldn't be loaded";
				return false;
			}

			if(!LoadFunctions())
			{
				Error = "steam_api64.dll doesn't have the functions this program needs";
				return false;
			}

			if(!Init())
			{
				Error = "Steam isn't available: is it running, are you signed in, is the game on this account?";
				return false;
			}

			ManualDispatchInit();
			Pipe = GetPipe();
			Networking = GetNetworking();
			Friends = GetFriends();
			User = GetUser();

			if(Networking == NULL || Friends == NULL || User == NULL)
			{
				Error = "Steam doesn't offer the interfaces this program needs";
				return false;
			}

			AllowRelay(Networking, true);
			SelfId = GetSteamId(User);

			// Shows in the log that the calls work, whether or not somebody is online
			RelayLog("Steam: signed in, %d friends", FriendCount(Friends, FRIEND_FLAG_IMMEDIATE));
			return true;
		}

		std::string LocalId() override
		{
			return std::to_string(SelfId);
		}

		void Pump() override
		{
			CallbackMessage Message;

			RunFrame(Pipe);

			while(NextCallback(Pipe, &Message))
			{
				if(Message.Id == CALLBACK_SESSION_REQUEST && Message.Param != NULL)
				{
					// Anybody may connect, the game decides who plays
					Accept(Networking, *reinterpret_cast<uint64_t*>(Message.Param));
				}
				else if(Message.Id == CALLBACK_SESSION_FAILED && Message.Param != NULL)
				{
					RelayLog("Steam: connection to %s failed, error %d", Describe(std::to_string(*reinterpret_cast<uint64_t*>(Message.Param))).c_str(), Message.Param[8]);
				}

				FreeCallback(Pipe);
			}
		}

		bool Receive(std::string& From, std::vector<char>& Data) override
		{
			uint32_t Size = 0;
			uint64_t Sender = 0;

			if(!Available(Networking, &Size, 0))
				return false;

			Data.resize(Size);

			if(!Read(Networking, Data.data(), Size, &Size, &Sender, 0))
				return false;

			Data.resize(Size);
			From = std::to_string(Sender);
			return true;
		}

		void Send(const std::string& To, const char* Data, int Size) override
		{
			if(!SendPacket(Networking, ParseId(To), Data, Size, P2P_SEND_UNRELIABLE, 0) && !bSendFailureLogged)
			{
				bSendFailureLogged = true;
				RelayLog("Steam: a packet of %d bytes to %s wasn't accepted", Size, Describe(To).c_str());
			}
		}

		std::string Describe(const std::string& Peer) override
		{
			const char* Name = FriendName(Friends, ParseId(Peer));
			return Name != NULL && *Name != 0 ? std::string(Name) + " (" + Peer + ")" : Peer;
		}

		void Advertise(bool bHosting) override
		{
			SetPresence(Friends, "status", bHosting ? "Hosting Republic Commando co-op" : "");

			if(!SetPresence(Friends, "connect", bHosting ? LocalId().c_str() : ""))
				RelayLog("Steam: refused the host status, friends won't find this host");

			if(bHosting)
			{
				const char* Value = FriendPresence(Friends, SelfId, "connect");
				RelayLog("Steam: host status set, reads back %s", Value != NULL && LocalId() == Value ? "the same" : "something else");
			}
		}

		std::vector<FriendHost> FindHosts() override
		{
			std::vector<FriendHost> Hosts;
			int Count = FriendCount(Friends, FRIEND_FLAG_IMMEDIATE);

			for(int i = 0; i < Count; ++i)
			{
				uint64_t Friend = FriendByIndex(Friends, i, FRIEND_FLAG_IMMEDIATE);
				GamePlayed Game;

				if(!FriendGame(Friends, Friend, &Game) || (Game.GameId & 0xFFFFFF) != GAME_APP_ID)
					continue;

				// The answer comes a moment after the request, Watch asks again
				RequestPresence(Friends, Friend);
				const char* Connect = FriendPresence(Friends, Friend, "connect");

				if(IsSteamId(Connect))
				{
					FriendHost Host;
					Host.Id = Connect;
					Host.Name = MenuName(FriendName(Friends, Friend), static_cast<int>(Hosts.size()) + 1);
					Hosts.push_back(Host);
				}
			}

			return Hosts;
		}

	private:
		template<typename T>
		bool Load(T& Function, const char* Name)
		{
			Function = reinterpret_cast<T>(GetProcAddress(Library, Name));

			if(Function == NULL)
				RelayLog("Steam: steam_api64.dll has no %s", Name);

			return Function != NULL;
		}

		bool LoadFunctions()
		{
			bool bOk = true;

			bOk &= Load(Init, "SteamAPI_InitSafe");
			bOk &= Load(ManualDispatchInit, "SteamAPI_ManualDispatch_Init");
			bOk &= Load(GetPipe, "SteamAPI_GetHSteamPipe");
			bOk &= Load(RunFrame, "SteamAPI_ManualDispatch_RunFrame");
			bOk &= Load(NextCallback, "SteamAPI_ManualDispatch_GetNextCallback");
			bOk &= Load(FreeCallback, "SteamAPI_ManualDispatch_FreeLastCallback");
			bOk &= Load(GetNetworking, "SteamAPI_SteamNetworking_v006");
			bOk &= Load(GetFriends, "SteamAPI_SteamFriends_v018");
			bOk &= Load(GetUser, "SteamAPI_SteamUser_v023");
			bOk &= Load(GetSteamId, "SteamAPI_ISteamUser_GetSteamID");
			bOk &= Load(AllowRelay, "SteamAPI_ISteamNetworking_AllowP2PPacketRelay");
			bOk &= Load(Accept, "SteamAPI_ISteamNetworking_AcceptP2PSessionWithUser");
			bOk &= Load(SendPacket, "SteamAPI_ISteamNetworking_SendP2PPacket");
			bOk &= Load(Available, "SteamAPI_ISteamNetworking_IsP2PPacketAvailable");
			bOk &= Load(Read, "SteamAPI_ISteamNetworking_ReadP2PPacket");
			bOk &= Load(FriendCount, "SteamAPI_ISteamFriends_GetFriendCount");
			bOk &= Load(FriendByIndex, "SteamAPI_ISteamFriends_GetFriendByIndex");
			bOk &= Load(FriendGame, "SteamAPI_ISteamFriends_GetFriendGamePlayed");
			bOk &= Load(FriendPresence, "SteamAPI_ISteamFriends_GetFriendRichPresence");
			bOk &= Load(RequestPresence, "SteamAPI_ISteamFriends_RequestFriendRichPresence");
			bOk &= Load(SetPresence, "SteamAPI_ISteamFriends_SetRichPresence");
			bOk &= Load(FriendName, "SteamAPI_ISteamFriends_GetFriendPersonaName");

			return bOk;
		}

		HMODULE Library = NULL;
		int32_t Pipe = 0;
		void* Networking = NULL;
		void* Friends = NULL;
		void* User = NULL;
		uint64_t SelfId = 0;
		bool bSendFailureLogged = false;

		InitFunc Init = NULL;
		VoidFunc ManualDispatchInit = NULL;
		GetPipeFunc GetPipe = NULL;
		RunFrameFunc RunFrame = NULL;
		NextCallbackFunc NextCallback = NULL;
		FreeCallbackFunc FreeCallback = NULL;
		InterfaceFunc GetNetworking = NULL;
		InterfaceFunc GetFriends = NULL;
		InterfaceFunc GetUser = NULL;
		GetSteamIdFunc GetSteamId = NULL;
		AllowRelayFunc AllowRelay = NULL;
		AcceptFunc Accept = NULL;
		SendFunc SendPacket = NULL;
		AvailableFunc Available = NULL;
		ReadFunc Read = NULL;
		FriendCountFunc FriendCount = NULL;
		FriendByIndexFunc FriendByIndex = NULL;
		FriendGameFunc FriendGame = NULL;
		FriendPresenceFunc FriendPresence = NULL;
		RequestPresenceFunc RequestPresence = NULL;
		SetPresenceFunc SetPresence = NULL;
		FriendNameFunc FriendName = NULL;
	};
}

Link* CreateSteamLink()
{
	return new SteamLink();
}
