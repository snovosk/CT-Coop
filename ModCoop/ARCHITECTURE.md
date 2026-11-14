# ModCoop architecture

Facts below come from the code, DEVLOG and test logs. Anything else is marked `assumption:`.
History of every change and its reason: `Dist/DEVLOG.md`. Rules for writing code: `CONVENTIONS.md`. Build and test: `TESTING.md`.

## Purpose

Co-op campaign for Star Wars: Republic Commando, 2 to 4 players, Unreal Engine 2 (the game's fork). A listen server on the host decides everything. The host plays 38 and commands the squad, clients take over 62, 40 and 07 as the story brings them in.

Design rule: UnrealScript and the engine's own replication first. C++ only where the engine crashes or blocks network play on single player maps.

## Components

| Component | Runs on | Built into | Responsibility |
|---|---|---|---|
| `Classes/CoopGame.uc` | server | `ModCoop.u` | Game type (`CTGameInfoSP`). Spawning, takeover of squad members, scenes, lifts, level changes, sync loops, automated tests (`TickTest`) |
| `Classes/CoopPlayer.uc` | both | `ModCoop.u` | `CTPlayer` for co-op. All `ClientCoop*`/`ServerCoop*` RPCs, camera, client weapon watchdogs, turrets, states `CoopWatching`, `CoopLiftRide` |
| `Classes/CoopCommando.uc` | both | `ModCoop.u` | A client's own pawn before it gets a squad member |
| `Classes/CoopExtension.uc` | both | `ModCoop.u` | Entry point of the mod, all `FunctionOverride` hooks, menu redirect, reconnect |
| `Classes/CoopFixes.uc` | host | `ModCoop.u` | Hooks of single player scripts (level change, debriefing, `TravelPostAccept`) |
| `Classes/CoopActionForward.uc` | both | `ModCoop.u` | Level script actions that only reach the server's player, run on clients too |
| `Classes/CoopTriggerForward.uc` | both | `ModCoop.u` | Map actors that only exist or change on the server (emitters, anti portals, materials, shakers) |
| `Classes/CoopTurretFire.uc` | server | `ModCoop.u` | A client's turret shots go to the client's crosshair |
| `Classes/CoopEndLift.uc` | server | `ModCoop.u` | Lifts that end a level wait for everybody, table of shared lifts |
| `Classes/CoopSevIntro.uc` | server | `ModCoop.u` | Sev's fall on GEO_01C |
| `Classes/CoopSpaceWalk.uc` | server | `ModCoop.u` | RAS_01A: clients fly in next to the host. Client side is state `CoopSpaceWalk` of `CoopPlayer` |
| `Classes/CoopPauseMenu.uc` | host | `ModCoop.u` | Pause menu of the host with LOAD CHECKPOINT |
| `Classes/CoopCaptiveTakeover.uc` | server | `ModCoop.u` | A lying captive member goes to its client when a player comes near |
| `Classes/CoopCheckpointReturn.uc` | server | `ModCoop.u` | What every player had at a level's checkpoint; puts the clients back after the save is loaded, or everybody back without a reload as the fallback |
| `Classes/CoopDoorHold.uc` | server | `ModCoop.u` | A door that closes behind the first player stays open for a time, table by map |
| `Classes/CoopLobby.uc`, `CoopLobbyMenu.uc` | both | `ModCoop.u` | Lobby on the map `MPCustom`: members, the level or a save slot; who is there when it starts is the session, nobody else joins later (`CoopGame.PreLogin`) |
| `Classes/CoopSaveSlots.uc`, `CoopSaveMenu.uc` | host | `ModCoop.u` | 5 save slots: the level's save and the players by name (`Save\ModCoopSaves.ini`); SAVE GAME of the host's pause menu |
| `Classes/CoopHUD.uc` | both | `ModCoop.u` | Squad icons the helmet doesn't draw, the host's own icon (slot 0) on clients, layout in `Notes/HelmetHUD.md` |
| `Classes/CoopMultiplayerMenu.uc`, `CoopHostMenu.uc`, `CoopJoinMenu.uc`, `CoopSteamMenu.uc`, `CoopReconnectMenu.uc` | client | `ModCoop.u` | Menus |
| `Classes/CoopConfig.uc` | both | `ModCoop.u` | `MOD_VERSION`, saved settings, assignments |
| `Classes/CoopEventListener.uc`, `CoopAnimController.uc` | server, client | `ModCoop.u` | Small helpers: hears a level event, holds a forwarded script animation |
| `Classes/CoopNative.uc` + `Src/ModCoop.cpp` | both | `ModCoop.dll` | Vtable patches, crash log, guarded native calls, net settings in memory, first start setup, starting the relay, public address |
| `CoopTunnel/` | both | `CoopTunnel.exe` (x64) | Carries the game's UDP over Steam P2P. Knows nothing about the game's protocol |
| `Tools/` | developer | not shipped | Build, one-PC test run, screenshots |
| `Dist/` | players | archive | READMEs, DEVLOG, `Collect-Logs` |

Changes outside `ModCoop/`: `Mod` (`SWRCFixExtension`, `ExtensionClasses`, `RedirectMenuClass`, `FunctionOverride.Init` removes an older hook of the same function), `CT` (`-forcelogflush`), `/EHa` and `/MT` in all projects, `UCC/UCC.ini` (`EditPackages+=ModCoop`).

## Load chain

1. `CT.exe` loads `Mod.dll` and `Mod.SWRCFix`. Steam starts `SWRepublicCommando.exe` instead, and that case writes `SWRepublicCommando.log` (confirmed by logs). assumption: `Mod` gets loaded there through the render device or `System.ini`; not traced.
2. `SWRCFix` loads `ExtensionClasses(0)="ModCoop.CoopExtension"` from its defaults with `DynamicLoadObject`, optional, so `System.ini` isn't edited.
3. `CoopExtension.Init`: logs the version and the system, `CoopNative.InstallClientFixes`, loads saved settings, installs the hooks.
4. Menus: `RedirectMenuClass` replaces the multiplayer menu with `CoopMultiplayerMenu`.
5. Host: URL with `?game=ModCoop.CoopGame?listen`, `?CoopLobby` for the lobby. `ModCoop` is added to `ServerPackages` in memory only.
6. Client: connects with `?CoopVersion=`. `CoopGame` refuses another version with a readable reason. Package GUIDs change with every compile, so **every player needs the same build**, not only the same version number.
7. Steam path: `CoopNative.StartRelay` starts `CoopTunnel` (`watch`, `host`, `join <id>`), status goes through `%TEMP%\CoopTunnel-<parent>.status`.

## Server loops

`CoopGame.Timer` (once a second) is the dispatcher: `Check*` and `Sync*` calls, the respawn and bleed-out loop for clients, `TickTest` when `?CoopTest=` is set.
`CoopGame.Tick`: `TurnBotsToMove`, `CheckScriptAnims`, and every 0.2 s `SyncIdleStates`, `SyncPanelStates`, `SyncMapActorCollision`, `CheckDetonations`, `SyncPropEffects`, `CheckGather`, with a full resend every 3 s.
`CoopPlayer.PlayerTick` on the client runs the watchdogs and marks steps for the crash log (`SetDebugStep`).

## Takeover of a squad member

`CheckSquadTakeover`, `CheckSceneWatch`, `StartIntroWatch`, `StartJoinWatch` pick who and when. `TakeOver` does it, `RetireAI` removes the AI. A member played by a client is taken out of the AI squad (`DetachClientMembers`, checked every second because scripts add them back) and rejoins before a level change. Assignments are `address/name=member class`.

The dropped AI script is the main source of level bugs. Compensations: `RunSkippedActions`, `DeferSkippedTriggers`, `ScanArrivals`/`CheckClientArrivals`, `CheckMissedEvents`, `CheckStalledScripts`. Triage: `TRIAGE.md`.

## Persistent data

| Data | Where | Written by | Notes |
|---|---|---|---|
| Settings, recent addresses, assignments | `GameData/Save/ModCoop.ini` | `CoopConfig`, `CoopNative` | Lists go to `[ModCoop.Lists]`, the engine's writer loses them otherwise. Clear `SquadAssignmentList` after tests |
| First start markers | `GameData/Save/ModCoop*.done` | `ModCoop.dll` | Shortcut and firewall asked once |
| Logs | `GameData/System/CT.log`, `SWRepublicCommando.log`, `Coop*.log`, `GameData/CoopTunnel/*.log` | engine, mod | Overwritten on the next start |
| Progress | host: `Save\CoopCheckpoint` | `CoopGame.SaveCheckpoint`, `LoadSavedCheckpoint`, `CoopNative.RemapSavedLevel`, `CoopCheckpointReturn` | Each checkpoint writes a real save. Loading it rewinds the world on the host; clients load the clean map and get the state by replication, the host numbers the save's objects like the map (see the fact below). Clients' place and equipment come back by name. Lost on level change |
| Objective tracker of clients | host's helmet | `CoopGame.SyncObjectiveTracker` | Read once a second, sent on change and every 5 s. Door hold and sniper pointers override it per client (`CoopPlayer.bTrackerOverride`) |

## Network traffic that leaves the machine

Game UDP to players, Steam P2P through `CoopTunnel`, and one HTTPS request to `api.ipify.org` when a host opens the lobby (it reveals the host's address to that service and shows it on the lobby screen). Nothing else: no telemetry, log upload or update check.

## Engine facts that cost us time

- Clients delete every placed actor that is neither `bStatic` nor `bNoDelete`, and the server never sends `RemoteRole=None`. Check existence on the client before planning a sync.
- Controllers aren't replicated. `bIncapacitated`, stance, squad and AI data never reach clients.
- `TotalTimeToRevive` has no script writes, native code sets it. Before syncing a variable, grep its writes in all `.uc` files.
- Attachments use multiplayer animation names, co-op commandos use `CloneCommandoSPSet`. Standalone blanks those names, network games don't.
- A player's pawn animation is replicated from the server, so it has to be set and kept there. Script NPC animations aren't, which is why forwarding works for them.
- Karma is simulated locally on each machine.
- Squad markers: `GetMarkerUsability` returns MU_Invalid 0, Irrelevant 1, Incapacitated 2, Occupied 3, Usable 4. Only `MarkerDoorBreach` takes several members (`MaxMembers=3`). F1 is `SetStanceOffensive`, F2 `SetStanceDefensive`, F3 `SquadEngage`, F4 `CancelAllMarkers`.
- UnrealScript has no ternary operator and no string to name cast.
- The engine ignores more than 5 logins a minute from one address, hence `127.0.1.N` per friend in `CoopTunnel`.
- Some C++ headers don't match the real binaries (`UGameEngine`). Use reflection (`FindField`) and exports.
- UCC doesn't exit after a compile error. `TESTING.md` has the safe way.
- The helmet's single player HUD (visor) is off in network games by four reads of NetMode in Engine.dll; `CoopNative.SetVisorHUD` patches them while a CoopHUD draws and redirects the helmet's DrawHUD call so CoopHUD's icons are drawn into the visor. Details: `Notes/HelmetHUD.md`.
- Saving in network mode: only the console command `SAVEGAME` refuses. `UGameEngine::SaveGame` (vtable slot 0x104) writes a listen server's level, `?load=<name>` loads it and the host keeps listening. Objects made with `new` aren't saved. `LoadMap` renames the save's objects into the map's package, whose linker stays the `.ctm`; `UPackageMap::ObjectToIndex` numbers them by their index in the `.cts`, so clients took one object for another until `CoopNative.RemapSavedLevel` pairs them with the map's exports by name (read from both files: in game `GetFullName` gives `InGameTempName`). The save's client controllers are gone before the clients log in again (their names aren't taken). A client that played a squad member had it again right after logging in, without a takeover: how is not measured. `AfterSaveLoaded` gives the AI to a member left without a controller. Details: `Reports/2026-11-10-save/RESEARCH.md`

## Dangerous places

- **AI teardown:** always through `RetireAI`. Earlier paths crashed in `ReleaseNode` and hung in `RemoveAssignmentsByMember`.
- **Weapon watchdogs:** each one lists the legitimate states it leaves alone (`UsingItem`, `bUse`, turret, `CoopWatching`, incapacitated).
- **`CTPlayer.UsingItem` and position corrections:** `ClientAdjustPosition` sends the server's state and can throw the client out of an action.
- **Level start:** paused until clients arrive, timers are paused too. `CheckSlowStart` slows the first seconds.
- **`CheckStalledScripts`:** only pawns' scripts on a condition or a jump. A wider rule crashed the host.
- **`FunctionOverride`:** the hook has to be unique per function or it recurses after a level change.

## Known structural debt

`CoopGame.uc` (about 8000 lines) and `CoopPlayer.uc` (about 3800) are far over the size limit in `CONVENTIONS.md`. New mechanics go into their own class like `CoopEndLift`. Splitting the old code is a separate task, not part of a bug fix.
