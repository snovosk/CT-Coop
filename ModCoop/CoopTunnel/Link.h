/*
 * Link
 * Purpose: what the relay needs from the way two relays reach each other. SteamLink is the real one, DirectLink (Main.cpp) plain UDP
 *   for tests on one PC.
 * Entry points: Main.cpp creates one link per run.
 * Logging: through RelayLog (Main.cpp).
 * State: none here.
 * Known limitations: datagrams may get lost or come in another order, like the UDP of the game they carry.
 */
#pragma once

#include <string>
#include <vector>

void RelayLog(const char* Format, ...);

struct FriendHost
{
	std::string Id;
	std::string Name;
};

class Link
{
public:
	virtual ~Link() {}

	virtual bool Open(std::string& Error) = 0;
	virtual std::string LocalId() = 0;
	virtual void Pump() = 0;
	virtual bool Receive(std::string& From, std::vector<char>& Data) = 0;
	virtual void Send(const std::string& To, const char* Data, int Size) = 0;
	virtual std::string Describe(const std::string& Peer) = 0;

	// The host tells its friends that it's there, the others look for such friends
	virtual void Advertise(bool bHosting) = 0;
	virtual std::vector<FriendHost> FindHosts() = 0;
};

Link* CreateSteamLink();
