/*
 * CoopTunnel
 * Purpose: carries the game's UDP traffic between players through a Link (Steam), so they need no forwarded ports or VPN. It doesn't
 *   understand the game's protocol. To the game on the joining side the host is a server on 127.0.0.1; on the host each socket of a client
 *   has its own local socket towards the server on 127.0.0.1:7777, from an address of its own (127.0.1.N per friend): the engine ignores
 *   more than 5 logins a minute from one address, and through one address the sixth login of three players was lost on a level change.
 * Entry points: started by the game (CoopNative.StartRelay) with a mode and --parent <process of the game>:
 *   watch            looks for friends who host (the menu CoopSteamMenu shows them)
 *   host             the game runs a server, friends can find it while that server is up
 *   join <id>        forwards the game's connection to the host
 *   Test on one PC: --direct <ip:port> uses plain UDP instead of Steam (DirectLink).
 * Logging: CoopTunnel-<mode>.log next to the program, every line with its time. Markers: "Friend connected", "Game server", "Connected".
 * State: %TEMP%\CoopTunnel-<parent>.status for the game: steam=0/1, host=<id>|<name>, port=<n>. It's replaced as a whole, a failed write is
 *   repaired by the next one. The relay ends with the game.
 * Known limitations: every datagram starts with a session byte: one session per socket of the game. The game opens a new socket for each
 *   level while the old one keeps sending for a while, so sessions live side by side. A session on the host closes after SESSION_TIMEOUT_MS
 *   of silence. 256 sessions come round again, long after the first ones ended.
 */
#include "Link.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <map>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

namespace
{
	const int       GAME_PORT = 7777;
	const int       FIRST_JOIN_PORT = 7778;
	const int       JOIN_PORT_TRIES = 10;
	const int       DIRECT_PORT = 7790;
	const int       MAX_DATAGRAM = 65536;
	const u_long    FIRST_PEER_ADDRESS = 0x7F000101; // 127.0.1.1
	const u_long    MAX_PEER_ADDRESSES = 250;
	const ULONGLONG SESSION_TIMEOUT_MS = 30000;
	const ULONGLONG HOST_CHECK_MS = 2000;
	const ULONGLONG STATUS_MS = 1000;
	const ULONGLONG NO_ANSWER_WARNING_MS = 20000;

	FILE*       GLog = NULL;
	std::string GStatusPath;
	HANDLE      GParent = NULL;

	void WriteStatus(const std::string& Text)
	{
		if(GStatusPath.empty())
			return;

		std::string Temporary = GStatusPath + ".tmp";
		FILE* File = NULL;

		if(fopen_s(&File, Temporary.c_str(), "wb") != 0 || File == NULL)
			return;

		fwrite(Text.data(), 1, Text.size(), File);
		fclose(File);
		MoveFileExA(Temporary.c_str(), GStatusPath.c_str(), MOVEFILE_REPLACE_EXISTING);
	}

	void EndWithGame()
	{
		if(GParent != NULL && WaitForSingleObject(GParent, 0) == WAIT_OBJECT_0)
		{
			DeleteFileA(GStatusPath.c_str());
			ExitProcess(0);
		}
	}

	// A datagram socket that doesn't wait and ignores "port unreachable" (the game reopens its sockets on level changes)
	SOCKET OpenSocket(int Port, u_long LocalAddress = INADDR_LOOPBACK)
	{
		SOCKET Socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

		if(Socket == INVALID_SOCKET)
			return Socket;

		u_long NoBlock = 1;
		ioctlsocket(Socket, FIONBIO, &NoBlock);

		BOOL  Report = FALSE;
		DWORD Returned = 0;
		WSAIoctl(Socket, _WSAIOW(IOC_VENDOR, 12), &Report, sizeof(Report), NULL, 0, &Returned, NULL, NULL);

		sockaddr_in Address = {};
		Address.sin_family = AF_INET;
		Address.sin_port = htons(static_cast<u_short>(Port));
		Address.sin_addr.s_addr = htonl(LocalAddress);

		if(bind(Socket, reinterpret_cast<sockaddr*>(&Address), sizeof(Address)) != 0)
		{
			closesocket(Socket);
			return INVALID_SOCKET;
		}

		return Socket;
	}

	sockaddr_in LoopbackAddress(int Port)
	{
		sockaddr_in Address = {};
		Address.sin_family = AF_INET;
		Address.sin_port = htons(static_cast<u_short>(Port));
		Address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
		return Address;
	}

	std::string WithSession(unsigned char Session, const char* Data, int Size)
	{
		std::string Packet;
		Packet.reserve(Size + 1);
		Packet += static_cast<char>(Session);
		Packet.append(Data, Size);
		return Packet;
	}

	// Looks at the list of listeners: a test bind could take the port from the game on a level change
	bool IsServerUp(int Port)
	{
		ULONG Size = 0;
		GetUdpTable(NULL, &Size, FALSE);
		std::vector<char> Buffer(Size);
		MIB_UDPTABLE* Table = reinterpret_cast<MIB_UDPTABLE*>(Buffer.data());

		if(Size == 0 || GetUdpTable(Table, &Size, FALSE) != NO_ERROR)
			return false;

		for(DWORD i = 0; i < Table->dwNumEntries; ++i)
		{
			if(ntohs(static_cast<u_short>(Table->table[i].dwLocalPort)) == Port)
				return true;
		}

		return false;
	}

	// TEST: plain UDP between two relays on one PC
	class DirectLink : public Link
	{
	public:
		DirectLink(const std::string& InTarget, bool bInHost) : Target(InTarget), bHost(bInHost) {}

		bool Open(std::string& Error) override
		{
			Socket = OpenSocket(bHost ? DIRECT_PORT : 0);

			if(Socket == INVALID_SOCKET)
				Error = "the test port is in use";

			return Socket != INVALID_SOCKET;
		}

		std::string LocalId() override { return Target; }
		void Pump() override {}
		std::string Describe(const std::string& Peer) override { return Peer; }
		void Advertise(bool) override {}

		std::vector<FriendHost> FindHosts() override
		{
			FriendHost Host;
			Host.Id = Target;
			Host.Name = "TEST HOST";
			return std::vector<FriendHost>(1, Host);
		}

		bool Receive(std::string& From, std::vector<char>& Data) override
		{
			sockaddr_in Sender = {};
			int SenderSize = sizeof(Sender);
			char Buffer[MAX_DATAGRAM];
			int Size = recvfrom(Socket, Buffer, sizeof(Buffer), 0, reinterpret_cast<sockaddr*>(&Sender), &SenderSize);

			if(Size < 0)
				return false;

			Data.assign(Buffer, Buffer + Size);
			char Text[64];
			inet_ntop(AF_INET, &Sender.sin_addr, Text, sizeof(Text));
			From = std::string(Text) + ":" + std::to_string(ntohs(Sender.sin_port));
			return true;
		}

		void Send(const std::string& To, const char* Data, int Size) override
		{
			size_t Colon = To.find(':');
			sockaddr_in Address = LoopbackAddress(atoi(To.c_str() + Colon + 1));
			sendto(Socket, Data, Size, 0, reinterpret_cast<sockaddr*>(&Address), sizeof(Address));
		}

	private:
		std::string Target;
		bool bHost;
		SOCKET Socket = INVALID_SOCKET;
	};

	int RunWatch(Link& Net)
	{
		size_t Shown = static_cast<size_t>(-1);

		for(;;)
		{
			EndWithGame();
			Net.Pump();

			std::vector<FriendHost> Hosts = Net.FindHosts();
			std::string Status = "steam=1\n";

			for(size_t i = 0; i < Hosts.size(); ++i)
				Status += "host=" + Hosts[i].Id + "|" + Hosts[i].Name + "\n";

			WriteStatus(Status);

			if(Hosts.size() != Shown)
			{
				Shown = Hosts.size();
				RelayLog("Friends hosting: %d", static_cast<int>(Shown));
			}

			Sleep(1000);
		}
	}

	struct HostSession
	{
		std::string Peer;
		unsigned char Id;
		SOCKET Socket;
		ULONGLONG LastHeard;
	};

	int RunHost(Link& Net)
	{
		std::map<std::string, HostSession> Sessions;
		std::map<std::string, u_long> PeerAddresses;
		std::vector<char> Data;
		char Buffer[MAX_DATAGRAM];
		std::string From;
		const sockaddr_in Server = LoopbackAddress(GAME_PORT);
		ULONGLONG NextCheck = 0;
		bool bHosting = false;

		RelayLog("Hosting");

		for(;;)
		{
			bool bBusy = false;
			ULONGLONG Now = GetTickCount64();

			EndWithGame();
			Net.Pump();

			if(Now >= NextCheck)
			{
				NextCheck = Now + HOST_CHECK_MS;
				WriteStatus("steam=1\n");

				// Friends see this host only while the game server is up: back in the game's main menu the relay still runs
				bool bUp = IsServerUp(GAME_PORT);

				if(bUp != bHosting)
				{
					bHosting = bUp;
					Net.Advertise(bUp);
					RelayLog("Game server %s", bUp ? "up, friends can find this host" : "down, hidden from friends");
				}

				for(std::map<std::string, HostSession>::iterator It = Sessions.begin(); It != Sessions.end();)
				{
					if(Now - It->second.LastHeard > SESSION_TIMEOUT_MS)
					{
						closesocket(It->second.Socket);
						It = Sessions.erase(It);
					}
					else
					{
						++It;
					}
				}
			}

			while(Net.Receive(From, Data))
			{
				bBusy = true;

				if(Data.size() < 2)
					continue;

				const unsigned char Id = static_cast<unsigned char>(Data[0]);
				const std::string Key = From + "/" + std::to_string(Id);
				std::map<std::string, HostSession>::iterator It = Sessions.find(Key);

				if(It == Sessions.end())
				{
					HostSession Session;
					Session.Peer = From;
					Session.Id = Id;
					Session.LastHeard = Now;

					if(PeerAddresses.find(From) == PeerAddresses.end())
					{
						PeerAddresses[From] = FIRST_PEER_ADDRESS + (static_cast<u_long>(PeerAddresses.size()) % MAX_PEER_ADDRESSES);
						RelayLog("Friend connected: %s", Net.Describe(From).c_str());
					}

					Session.Socket = OpenSocket(0, PeerAddresses[From]);

					if(Session.Socket == INVALID_SOCKET)
						continue;

					connect(Session.Socket, reinterpret_cast<const sockaddr*>(&Server), sizeof(Server));
					It = Sessions.insert(std::make_pair(Key, Session)).first;
				}

				It->second.LastHeard = Now;
				send(It->second.Socket, Data.data() + 1, static_cast<int>(Data.size()) - 1, 0);
			}

			for(std::map<std::string, HostSession>::iterator It = Sessions.begin(); It != Sessions.end(); ++It)
			{
				int Size;

				while((Size = recv(It->second.Socket, Buffer, sizeof(Buffer), 0)) >= 0)
				{
					bBusy = true;
					const std::string Packet = WithSession(It->second.Id, Buffer, Size);
					Net.Send(It->second.Peer, Packet.data(), static_cast<int>(Packet.size()));
				}
			}

			if(!bBusy)
				Sleep(1);
		}
	}

	int RunJoin(Link& Net, const std::string& Host)
	{
		// The next free port when there are other copies of the game on this PC
		SOCKET Local = INVALID_SOCKET;
		int Port = FIRST_JOIN_PORT;

		for(int i = 0; i < JOIN_PORT_TRIES && Local == INVALID_SOCKET; ++i)
		{
			Port = FIRST_JOIN_PORT + i;
			Local = OpenSocket(Port);
		}

		if(Local == INVALID_SOCKET)
		{
			RelayLog("No free local port for the game");
			return 1;
		}

		RelayLog("Relaying to %s, the game connects to 127.0.0.1:%d", Net.Describe(Host).c_str(), Port);

		std::map<unsigned short, unsigned char> SessionOfPort;
		sockaddr_in GameOfSession[256] = {};
		bool bSessionUsed[256] = {};
		unsigned char LastSession = 0;
		std::vector<char> Data;
		char Buffer[MAX_DATAGRAM];
		std::string From;
		const std::string Status = "steam=1\nport=" + std::to_string(Port) + "\n";
		const ULONGLONG Start = GetTickCount64();
		ULONGLONG NextStatus = 0;
		bool bAnswered = false, bWarned = false;

		for(;;)
		{
			bool bBusy = false;
			ULONGLONG Now = GetTickCount64();

			EndWithGame();
			Net.Pump();

			if(Now >= NextStatus)
			{
				NextStatus = Now + STATUS_MS;
				WriteStatus(Status);
			}

			sockaddr_in Game = {};
			int GameSize = sizeof(Game);
			int Size;

			while((Size = recvfrom(Local, Buffer, sizeof(Buffer), 0, reinterpret_cast<sockaddr*>(&Game), &GameSize)) >= 0)
			{
				bBusy = true;

				std::map<unsigned short, unsigned char>::iterator It = SessionOfPort.find(Game.sin_port);
				unsigned char Session;

				if(It != SessionOfPort.end())
				{
					Session = It->second;
				}
				else
				{
					Session = ++LastSession;

					if(bSessionUsed[Session])
						SessionOfPort.erase(GameOfSession[Session].sin_port);

					bSessionUsed[Session] = true;
					GameOfSession[Session] = Game;
					SessionOfPort[Game.sin_port] = Session;
				}

				const std::string Packet = WithSession(Session, Buffer, Size);
				Net.Send(Host, Packet.data(), static_cast<int>(Packet.size()));
				GameSize = sizeof(Game);
			}

			while(Net.Receive(From, Data))
			{
				bBusy = true;

				if(From != Host || Data.size() < 2)
					continue;

				const unsigned char Session = static_cast<unsigned char>(Data[0]);

				if(bSessionUsed[Session])
				{
					sendto(Local, Data.data() + 1, static_cast<int>(Data.size()) - 1, 0, reinterpret_cast<const sockaddr*>(&GameOfSession[Session]), sizeof(sockaddr_in));
				}

				if(!bAnswered)
				{
					bAnswered = true;
					RelayLog("Connected: the host's game answers");
				}
			}

			if(!bAnswered && !bWarned && Now - Start > NO_ANSWER_WARNING_MS)
			{
				bWarned = true;
				RelayLog(SessionOfPort.empty() ? "The game hasn't connected to this relay yet" : "No answer from the host yet");
			}

			if(!bBusy)
				Sleep(1);
		}
	}

	const char* OptionValue(int Count, char** Arguments, const char* Name)
	{
		for(int i = 1; i + 1 < Count; ++i)
		{
			if(strcmp(Arguments[i], Name) == 0)
				return Arguments[i + 1];
		}

		return NULL;
	}

	void OpenLog(const std::string& Mode)
	{
		char Path[MAX_PATH];
		GetModuleFileNameA(NULL, Path, MAX_PATH);
		std::string Directory = Path;
		Directory.erase(Directory.find_last_of('\\') + 1);

		// Another relay of this mode on the same PC (tests) has the file open
		GLog = _fsopen((Directory + "CoopTunnel-" + Mode + ".log").c_str(), "w", _SH_DENYWR);

		if(GLog == NULL)
			GLog = _fsopen((Directory + "CoopTunnel-" + Mode + "-" + std::to_string(GetCurrentProcessId()) + ".log").c_str(), "w", _SH_DENYWR);
	}
}

void RelayLog(const char* Format, ...)
{
	SYSTEMTIME Time;
	GetLocalTime(&Time);

	char Line[1024];
	va_list Arguments;
	va_start(Arguments, Format);
	vsnprintf(Line, sizeof(Line), Format, Arguments);
	va_end(Arguments);

	printf("%02d:%02d:%02d %s\n", Time.wHour, Time.wMinute, Time.wSecond, Line);

	if(GLog != NULL)
	{
		fprintf(GLog, "%02d:%02d:%02d %s\n", Time.wHour, Time.wMinute, Time.wSecond, Line);
		fflush(GLog);
	}
}

int main(int Count, char** Arguments)
{
	const std::string Mode = Count > 1 ? Arguments[1] : "";

	if(Mode != "watch" && Mode != "host" && Mode != "join")
	{
		printf("Started by the game. Modes: watch, host, join <host's Steam ID>; options: --parent <process>, --direct <ip:port>\n");
		return 1;
	}

	OpenLog(Mode);
	RelayLog("CoopTunnel %s", Mode.c_str());

	if(const char* Parent = OptionValue(Count, Arguments, "--parent"))
	{
		char Temp[MAX_PATH] = "";
		GetTempPathA(MAX_PATH, Temp);
		GStatusPath = std::string(Temp) + "CoopTunnel-" + Parent + ".status";
		GParent = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(atoi(Parent)));

		if(GParent == NULL)
			return 1;
	}

	WSADATA Winsock;
	WSAStartup(MAKEWORD(2, 2), &Winsock);

	const char* Direct = OptionValue(Count, Arguments, "--direct");
	Link* Net = Direct != NULL ? static_cast<Link*>(new DirectLink(Direct, Mode == "host")) : CreateSteamLink();
	std::string Error;

	if(!Net->Open(Error))
	{
		RelayLog("%s", Error.c_str());
		WriteStatus("steam=0\n");
		return 1;
	}

	if(Mode == "watch")
		return RunWatch(*Net);

	if(Mode == "host")
		return RunHost(*Net);

	std::string Host = Direct != NULL ? Direct : "";

	if(Host.empty() && Count > 2 && Arguments[2][0] != '-')
		Host = Arguments[2];

	if(Host.empty())
	{
		RelayLog("join needs the host's Steam ID");
		return 1;
	}

	return RunJoin(*Net, Host);
}
