# ModCoop — development log

A co-op campaign for Star Wars: Republic Commando with a host-authoritative design:
the host runs a listen server (`?listen`), clients connect to IP:7777. Only the native replication of UE2 is used.
Custom C++ is used only where the engine crashes or blocks network play on single player maps.

## Status (0.6, test build)

The first episode (Geonosis) has been played by hand in co-op up to GEO_05A (three live sessions with up to 4 players), single
scenes were checked with automated tests up to GEO_05C. The scripts of all campaign maps were read from the .ctm files and the
scenes that depend on squad member scripts are handled (arrivals, sniper, door breach, start scenes, lifts). Each of up to three
clients plays its own Delta squad member.

0.6 (test build for public testing):
- **No more drops on level changes**: the CD key check of the new level's master server uplink kicked 1-2 clients on every
  level, it is removed in the first frames now.
- **Turrets for clients** (mount, aim, fire, leave), **lifts and start scenes** (GEO_03A elevator briefing, RAS_03A/YYY_04B holo
  briefing, GEO_05A/GEO_04D lifts: on lifts everybody rides first person on the host's spot, seeing only themselves; in the briefing scenes everybody watches over the shoulder looking at the middle, standing still, the members play
  their scripts and are handed over at the end), **NPC animations of level scripts on clients**, **map objects look like on the
  host** (tag, glow, baked lighting: the yellow shield of GEO_03A), **markers that scripts disable/enable** (GEO_04D charge),
  **arrivals of client members** (GEO_05B elevator, GEO_05C end), **sniper scene with the AI only for the shot** and the squad's
  sniper rifle, **weapons stuck in firing/down** on clients.
- **Test reports:** the log has the system (Windows, CPU, RAM, GPU, desktop, exe, wrappers like dgVoodoo/DXVK/ReShade) and the
  number of commandos on the host and each client when it changes.

0.59 (test build, not tested by hand yet):
- **Squad icons redone from the helmet's machine code** (`UHelmet::DrawHUD` in Engine.dll, see `Notes/HelmetHUD.md`): exact
  positions and texture parts, the helmet's bent HUD in network games (`Canvas.SetCurvedSurface`), the four health colors
  (green, yellow, orange, red), the icon of the member's current order, the frame lit while the player aims at the member,
  the timer ring while the member places a charge or hacks, blinking corners while the member talks. The order and the marker
  state come from the host (`CoopGame.GetSquadIconState`). Against the helmet's own icons at 800x600, 1280x720 and 1600x900
  the frame, order icon and arrow match to the pixel.
- Fixes from the live test of 0.58 (also in the updated 0.58 archive): enemies after Fixer on GEO_01B, the weapon after the
  detonator, Scorch's speed after the takeover; factories that spawn near the player no longer use players without a pawn.

0.58 only changed what players see:
- **Squad icons** are back on the host's HUD for the squad members played by clients, and clients see them for every other
  Delta member (`CoopHUD`). The host, 38, has no icon, as in single player. Like the helmet's own icons they show the number,
  the health (green, yellow, red), incapacitation (a red cross) and a small arrow on the frame that points to where the member
  is, seen from the player. Health and incapacitation of other pawns are not replicated, the server sends them
  (`SyncSquadHealth`) together with who is in the squad, so a member shows up only after joining (Scorch on GEO_01A only
  after his scene). As in the helmet (`UHelmet::GetSquadPawnHUDPosition` returns `Pawn.SquadHUDSlot`), every member has a
  fixed place: 07, 40, 62 from the left, so a single 62 stands in the third place. The Delta pawns are always relevant so the
  icons of members far away don't disappear.
  The helmet is laid out for 800x600, stretched to the screen (x with the width, y with the height); 0.59 draws them like the
  helmet does (see above).
- **Objective tracker** (the ring with distance and direction around the crosshair), the **current objective** text, critical
  messages of scripts, blinking HUD elements, view shakes and screen fades now reach the clients. Level scripts changed them
  for the first player they found (the host) or for players with a HUD on the server only; `CoopExtension` hooks the script
  actions and forwards them (`ClientCoopObjectiveTracker`, `ClientCoopSetObjectives`, `ClientCoopCriticalMessage`, ...).
- **Effects of map actors on clients:** emitters are not replicated (`RemoteRole=ROLE_None`), so clients saw no explosion when
  a door was breached, no shattering window, no destroyed props. The server forwards the effects of `ActivateItem` and
  `DroidDispenser` state changes and of damaged and destroyed props (`ForwardEffect`, `SyncPropEffects`). Effects that clients
  spawn themselves (weapons, grenades) are not forwarded, so nothing appears twice.

Changes after 0.55 (released in 0.57):
- the scene in which a squad member joins is seen through the member's eyes (smoothed camera, the model is hidden) instead of
  from the side;
- the scene ends at "Add squad member": the client gets the member right away, the walk of the bot to its next position (Fixer
  walked about 750 units to the panel) is cut, and the events of the skipped part of the script (`trigger event`, objectives)
  are triggered at once (`RunSkippedActions`);
- door breach (`MarkerDoorBreach`): the host gives the order as usual, everybody sees "Delta, gather at the door (X/N)", and
  once all clients playing squad members are closer than 600 units to the door, the charge is placed and the door is blown
  (`CheckGather`);
- a free squad member goes to the closest client without one, at any distance (before, the client had to come within 500
  units; on GEO_01C a client who spawned on the balcony couldn't get down to Scorch);
- after a level change the game is paused until all clients of the last level are back (at most `MaxClientWait` = 60 s), so
  nobody misses the intro cutscene;
- the sniper scene on GEO_01C works in both variants: the AI shoots (Sev played by the AI) or a client plays Sev — once the
  marker is shown the client sees "Take the sniper position", and next to the sniper crate the server triggers
  `InSnipePosition` itself (`CheckClientSnipers`). The outcome of the scene depends on this flag when the ship takes off, not on
  a hit (the ship is invulnerable);
- protection against script races (`CheckMissedEvents`): if a script starts waiting for an event that another script sent
  within the last 30 s, the event is passed on to it (only the first time it waits for that event). On GEO_01C, with a fast
  sniper, Sun Fac missed `SunFacRunToShip` and the scene stopped forever — most likely why "the AI sniper didn't shoot" in the
  manual tests;
- smoothing of NPCs on clients (`SmoothProxies`): the error of the visible position of flying Geonosians at a ping of 50–90 ms
  went down from 60–134 to 21–29 units.

## Architecture

| Component | Where | What it does |
|---|---|---|
| `ModCoop.CoopGame` | server | The game type, a subclass of `CTGameInfoSP`. The host plays as in single player. Clients are spawned next to the host, respawned, get the "wounded" timer, are moved to the host when left behind; all level changes use `ServerTravel`. |
| `ModCoop.CoopPlayer` | both | `CTPlayer` for co-op. A client doesn't take over the squad (`AssignSquadMembers` is skipped). The host can restart the level in a network game (the engine's `RestartLevel`/`LoadGame` only work in standalone). On clients: creates the missing teams, remembers the host's address. |
| `ModCoop.CoopCommando` | both | A client's own pawn: `PlayerCommando` without the single player events `PlayerIncapacitated`/`PlayerRevived`, not part of the squad, colored multiplayer armor (replicated skin index), `bCannotDie` (wounded instead of dead, like the host). |
| `ModCoop.CoopHUD` | both | `CTHUD` that adds the squad icons the helmet doesn't draw (squad members played by clients on the host, all other Delta members on clients). |
| `ModCoop.CoopFixes` | host | Hooks of single player scripts with `Mod.FunctionOverride`: `ACTION_ChangeLevel` (level change that keeps `?game`/`?listen`), `CTDebriefingInfo.OnAButton` (`open <map>` → `ServerTravel`), `PlayerCommando.TravelPostAccept` (a safe version, see the bugs). |
| `ModCoop.CoopExtension` | both | Loaded by Mod at startup (`SWRCFix.ExtensionClasses`). CO-OP entries in the multiplayer menu, automatic reconnect, installs the native client fixes, hooks of script actions that change the HUD or spawn effects. |
| Menus | client/host | `CoopMultiplayerMenu` (replaces `CTMultiplayerPCMenu`), `CoopHostMenu`, `CoopJoinMenu` (the last 5 addresses in `ModCoop.ini`), `CoopReconnectMenu`. |
| `ModCoop.dll` (`CoopNative`) | both | `ServerPackages` in memory, releasing CD keys, connection timeouts and net rates in memory, reading and writing saved settings, the native client fixes (below). |

Changes to existing projects of the repository:
- **Mod**: `SWRCFixExtension` + `SWRCFix.ExtensionClasses`/`RedirectMenuClass` (pluggable extensions and menu redirection;
  without ModCoop the list is simply skipped). `FunctionOverride.Init` removes an earlier active hook of the same function —
  otherwise, after a level change, a new hook could store the old one as the "original" and recurse.
- **CT (Launcher)**: `-forcelogflush` now really writes the log line by line.
- **All projects**: `/EHa` (see "Building").
- **UCC.ini**: `EditPackages+=ModCoop` and the section `[UCC.Make] AutoLoad+=...` (parent classes from the game's packages).

Compatibility with the original game: no game files are changed, `System.ini` is not edited. `SWRepublicCommando.exe` works as
before. `ModCoop` is added to `ServerPackages` only in memory and only for a co-op server (the normal multiplayer menu removes it).

## Building

The repository has to be in the game folder as `Code` (next to `GameData`).

1. **C++**: `build.bat release` from the Visual Studio "Developer Command Prompt" (tested with VS 2026, toolset v145, x86).
   The solution was converted from VS 2003 (`devenv CT.sln /upgrade`); the original `.vcproj` files are in `Backup`.
   `build.bat` uses CRLF line endings (`cmd` didn't run it with LF).
   All projects use `/EHa` and the static CRT `/MT` (players don't need the VC++ Redistributable): with `/EHa`, `catch(...)`
   catches access violations and the UE2 error handler shows the call stack.
   If `NoDefaultCurrentDirectoryInExePath` is set on the system, call the batch file as `.\build.bat release`.
2. **UnrealScript**: from `GameData\System`: `UCC.exe make -silent -ini=..\..\Code\UCC\UCC.ini`.
   Only packages without a `.u` file are built, so delete `Mod.u` and `ModCoop.u` before building.
   The order matters: **first the DLL, then `make`** — otherwise UCC hangs on the "failed to bind native function" dialog.
   UCC regenerates `ModCoop/Inc/ModCoopClasses.h` and `Mod/Inc/ModClasses.h` itself. If native fields or functions changed,
   build the DLL again after `make`.
   Note: don't add the game's packages to `[Editor.EditorEngine] EditPackages` while their exported sources
   (`ucc batchexport`) are next to them. Make would try to recompile them. Use `[UCC.Make] AutoLoad+=` for dependencies.
3. **Test on one PC**: host
   `CT.exe "GEO_01A?game=ModCoop.CoopGame?listen?MaxPlayers=2" -windowed -forcelogflush -CoopNoSetup LOG=CoopHost.log`,
   client `CT.exe "Entry?Menu=ModCoop.CoopJoinMenu" -CoopConnect=127.0.0.1 -windowed -forcelogflush -CoopNoSetup LOG=CoopClient.log`.
4. **Archive**: `README.md`, `README.ru.md`, `DEVLOG.md` and `System\CT.exe`, `Mod.dll`, `Mod.int`, `Mod.u`, `ModCoop.dll`,
   `ModCoop.u`, `PropertyOverrides\*` in `SWRC-Coop-<version>.zip`.

## Native fixes (why C++)

All of them were found from the call stack (`History:` in the log) in real host + client runs.

1. **AI on clients** — `ULocalSituation::Assess <- AController::Tick` (NetMode=3). The engine keeps local copies of some
   single player pawns on clients (e.g. the gunship turrets on GEO_01A) together with their `CTBot`, but the AI data only
   exists on the server. Fix: the `Tick` slot in the vtable of `ACTBot` (found by comparing with the export
   `AController::Tick` in the vtable of `AController`) is replaced: on clients the AI doesn't tick. On the server the original
   is called, with the bot's name in the crash history (`CoopCTBotTick`).
2. **Teams on clients** — `APawn::GetRelationTowards <- CTPlayer.PlayerTick`. Single player uses 10 teams, but the native
   replication of `GameReplicationInfo` only sends the multiplayer teams. Team relations are class constants, so the client
   creates the missing `TeamInfo` actors locally (`CoopPlayer.EnsureClientTeams`, plain UnrealScript).
3. **"Static" actors that became dynamic** — `InitialClientActor <- UActorChannel::ReceivedBunch (Actor None)`.
   On single player maps the designers cleared `bStatic`/`bNoDelete` on some `Mover`/`StaticMeshActor` actors. The server
   replicates them as new actors, and the client can't spawn them because the class defaults forbid it. Fix: on clients the
   flags are cleared on the defaults of these classes during `UTcpNetDriver::TickDispatch` and restored afterwards. A scan of
   all 50 levels: such actors exist on 20 maps (1 to 101 of them, most on YYY_06C).
4. **Saving** — `UGameEngine::SaveGame` (and the console command `SaveGame`) writes nothing in network mode. Calling the
   exported function directly doesn't create a file either. A workaround would need reverse engineering of the binary — not
   done (see "Left out").
5. **Timeouts** — `System.ini` has 120/150 s: the client "hung" for 2 minutes after the host crashed. ModCoop sets 15 s on the
   client and 30 s on the server in memory (through the driver's reflection properties, `System.ini` isn't changed).
6. **Saved settings** — the config writer of RC comments out (`;  `) values that were read from `Save\ModCoop.ini`, so they
   were lost after the next start, and `StaticSaveConfig` put a changed string back to the value saved first.
   `CoopNative.LoadSavedConfig` marks the values it read as changed; the lists are written with
   `CoopNative.Read/WriteSavedString` to their own section `[ModCoop.Lists]`.
7. **Real time** — `CoopNative.GetRealTime` (`appSeconds`) for timeouts while the game is paused (`Level.TimeSeconds` stops).

About reverse engineering: the binaries were not disassembled. Only the exported symbols of the DLLs, vtable patching (as in
Mod) and property offsets through UnrealScript reflection (`FindField`) were used, because the layout of some C++ headers of
the repository (e.g. `UGameEngine`) doesn't match the real Engine.dll: writing to `GameEngine->ServerPackages` through the
header corrupted memory (the first version crashed). The `AActor` fields (`bStatic`, `bNoDelete`) are checked against known
classes at startup; if they don't match, fix 3 is turned off with a warning in the log.

## Bugs found and fixed along the way

Versions before 0.4 were called 1.0–1.3 (release 1.3 was renamed to 0.3).

| Symptom | Cause | Fix |
|---|---|---|
| CT.exe crashed at startup in `UClass::Serialize` | fields were added to `SWRCFix.uc`, but the C++ header `ModClasses.h` wasn't updated | the header was updated (UCC now regenerates it during `make`) |
| Crashes without a log or call stack | VS 2026 uses `/EHsc` by default: `catch(...)` doesn't catch access violations and the UE2 handler doesn't run | `/EHa` in all projects — a crash now shows the error dialog, `History:` and the full log |
| The host crashed in `PlayerCommando.TravelPostAccept` on a level change | `Squad.SetStance(None)` if the previous level had no squad | a safe version of the function in `CoopFixes` |
| The client crashed in `ClientTravel` (exporting items) | a client without a pawn on a level change with `bItems` | clients always travel without items (`CoopGame.ProcessServerTravel`), the equipment is given again |
| The client spawned "in mid air" (GEO_01C) | spawned next to the host during a scripted landing | wait until the host stands on the ground (up to 30 s), plus moving to the host after 15 s at a distance > 4000 |
| The client died at once instead of being wounded | the single player player has `bCannotDie` | `bCannotDie=True` on `CoopCommando` |
| The ModCoop settings (recent addresses) weren't kept between starts | RC reads mod ini files from `System`, but `SaveConfig` writes to `GameData\Save`; dynamic arrays are written commented out | `RecentAddresses[5]` is a static array; `CoopNative.LoadSavedConfig` reads the defaults from `Save\ModCoop.ini` at startup; duplicate `CoopLevels+=` lines are removed in the host menu |
| First live test over ZeroTier: "doesn't connect, no logs" | No firewall rule for the new `CT.exe` on the PC (incoming UDP blocked, the ZeroTier and Ethernet networks are "Public"); the client's log: not a single answer from the host in 43 s. The logs were in `CT.log`, not in `CoopHost/CoopClient.log`. The empty checkered room on the screenshot is the Entry map where the client waits for the connection | a batch file that allows CT.exe in the firewall (the user runs it, rule for `CT.exe`, UDP, all profiles); the batch files write `CoopHost.log`/`CoopClient.log` line by line; the connect batch file opens `CoopJoinMenu` with the connection status and the hint "NO ANSWER FROM THE HOST" after 18 s |
| Second live test: the network works (ping, `Login request` on the host), but the client disconnects right after `Welcomed by server` both ways | different builds of the mod on the two PCs (the GUIDs of the packages `ModCoop.u`/`Mod.u` change with every compile), the engine silently stops loading | the mod version `CoopConfig.MOD_VERSION` (1.1) in the log and the menu titles; the client sends `?CoopVersion=`, the host logs it and refuses with a clear reason if the version differs (not checked without the option). Tested: the option is kept across level changes |
| After copying the game, even the original exe didn't start on a friend's PC | VS 2026 builds with `/MD` need the VC++ Redistributable x86 (`vcruntime140`, `api-ms-win-crt-*`); CT.exe saves `RenderDevice=Mod.ModRenderDevice` in `Save\System.ini`, so the original exe loads `Mod.dll` too | all projects use the static CRT (`/MT`; the engine's `new`/`delete` go through `appMalloc` anyway), no dependency on the VC++ Redistributable (checked with `dumpbin /dependents`); version 1.2 |
| (live test, 1.2) A revived client can't move; the client's camera "breaks" (probably the same on GEO_03C) | `Pawn.Reviving` calls `Controller.PawnRevived` → `EnterStartState` on the server only; the client's controller stayed in `CtrlIncapacitated` (movement off, camera on the `DeathCamera` bone) | `CoopPlayer.PawnRevived` calls `ClientCoopPawnRevived` on the client (tested: the client's state after the revive is `PlayerWalking`) |
| (live test, 1.2) A client revives the host — the animation resets | `TargetType`/`Target` are computed only on the player's machine; on the server the client has `TGT_Default`, and `BactaHealer.Idle.BeginState` on the server forced a weapon switch | the client sends its target to the server when it changes (`ServerCoopSetTarget`) |
| (live test, 1.2) The host and the squad are down, a client is up — the level restarts | the single player code calls `BleedOut` on the wounded host every frame when nobody can help | hook of `Pawn.BleedOut`: while a client is alive, the host waits to be revived for up to `HostReviveWaitTime` (60 s); a scripted `ACTION_FailMission` (host not wounded) isn't delayed. Tested with `?CoopTest=hostdown` |
| (live test, 1.2) The visor/headlamp doesn't work on the client | `PlayerCommando` creates `CloneHeadlamp` in `PostBeginPlay` (server only), `GotoVisionMode` on the client returned early with `Flashlight == None` | `CoopCommando.PostNetBeginPlay` creates the headlamp on the client |
| Clients play the Delta squad members (prototype) | Request: clients instead of the squad bots | `CoopGame.CheckSquadTakeover`: when a squad member joins the host's squad (GEO_01A: Scorch after his script and the trigger `Add62ToSquad`) and the script has let it go (not `Scripting`), the first client without a squad member within 5 m takes it over: the AI is removed, so is the client's old pawn, the camera flies to the member within 1.5 s (`ClientCoopTakeoverCamera`), the member gets the player's equipment. The assignment "IP/name → member class" is saved in `ModCoop.ini`. On the following levels the client starts as the member without the flight; if the member is still busy with a script, the client watches through its eyes for up to 30 s. The host can't order a marker whose specialist is played by a client (demolition — 62, hacking — 40, sniping — 07), the client does it themselves. Test `CoopTest=pickup?CoopTestNext=GEO_01B` with two clients |
| Enemies still moved jerkily on the client | The request `SetNetSpeed(40000)` on the client was silently cut to `MaxClientRate` of its own driver (10000 from System.ini), the log showed "Net speed 5000" → effectively 10000 | Before the request the client raises the limit of its driver (`SetNetRates`, in memory only). The client's log now shows "Net speed is now 40000" |
| After hand signals (panels, charge, detonator) the client didn't get the weapon back, the hands played the wrong animations without the item in the hand | `HandSignal.MarkerHandSetup` (choice of animations and item) and `Idle.Tick` (weapon back) only run on the server; the animation that raises the hands didn't start on the client, the hands stayed in `Active` | `CoopPlayer.SetupClientHandSignal` chooses the animations and the item on the client in the same way; `FixHandSignalWeapon` starts the animation if it isn't running and gives the weapon back. A client's charge is detonated after 1 s, after the detonator animation (`CoopGame.CheckDetonations`) |
| Night vision didn't work for a client playing a squad member | The visors use the headlamp, the Delta member on the client has none | `CoopPlayer.EnsureHeadlamp` creates it on the client |
| The client had no timer/progress for placing a charge and hacking | `FractionComplete`, `DurationRemaining`, `ElapseSetupTime` only exist on the server | `ClientCoopSetPanelProgress` every 0.2 s while the panel is being activated or counting down |
| Invisible walls on the client where objects were destroyed | A destroyed `Prop` turns off its collision and changes its mesh on the server; the replicated flags don't update the client's collision | `CoopGame.SyncMapActorCollision` sends the changes, the client applies `SetCollision`/`SetStaticMesh` |
| Fixer's camera looked at a wall, after the takeover the member crouched | The member's eyes point at a wall in the scene; the script wounds Fixer and leaves him crouching | The scene was shown from the third person (replaced in 0.57 by a smoothed first person view); on takeover `ShouldCrouch(false)` and full health |
| The client's HUD was visible during a squad member's scene | `CoopWatching` shows someone else's eyes, but the client's own HUD and visor | `SetCoopHUDHidden`: `myHUD` and `Helmet` are hidden while watching (the previous values are restored) |
| Scenes in which a member joins the squad (GEO_01B: Fixer behind the door Scorch blows up) | The member joins the squad inside its script (`ACTION_ChangeSquadMember`), after that the script waits for an event that the client playing the member triggers themselves (Fixer waits for the shield to be hacked) | `CoopGame.CheckSceneWatch`: while the scene between the last wait and the joining plays, the client that will play the member (the one from before, otherwise the closest free one) watches through its eyes with locked controls (`CoopPlayer.CoopWatching`). The member is free once it's in the squad and the script only waits for an event (`IsScriptBusy`); then the takeover happens and the old model disappears |
| The client playing Scorch couldn't blow the door | The host can't give the order if a client plays the specialist. The client's copy lacked the change of the charge type to the detonator (`AIT_Plunger`) and `User`/`bPlayerActivated`; the detonation — `HandSignal.FireWeapon` is called by a first person animation that only exists on the client | `ClientCoopSetPanelState` sends the type, the flag and the user's pawn; `ServerCoopStartHandSignal` with `TGT_DemolitionReady` puts the client's charge into `Explode` itself. Test `CoopTest=door` (GEO_01B, Client1 — Scorch, Client2 gets Fixer) |
| Tutorial hints paused everybody | `CTPauseHintText` is shown to the host | In network games `CoopPlayer.ShowMenu` doesn't open the hints |
| A second client with the same CD key was disconnected after a level change ("CD key in use") | The host checks the keys again when everybody reconnects at the same time; the GameSpy servers have been down for a long time | The keys are released in `PreLogin` as well; in co-op the client ignores `ClientSetBadCDKey`. If the host still drops the connection, the client reconnects by itself |
| Client crash on GEO_01C: `Assertion failed` in `CTPlayer.UsingItem.PlayerTick` | Since 0.4 the server mirrors the client's `UsingItem` state. The client released "Use" and left the state, but the server's position correction (still in `UsingItem`) put it back with `bUse=False`, which `assert(bUse)` catches | `CoopPlayer.UsingItem`: without the button held, go to `PlayerWalking` at once (before the original code), and `BeginState` doesn't tell the server about the start of the use in that case |
| The client can't use panels (bacta dispensers, hacking) | 1) `ActivateItem.HasRequiredInventory` isn't `simulated`: on the client, where the panel is a proxy, it didn't run and returned false, so the native target selection dropped the panel. 2) The client deletes its copies of the panels and gets them over the network without the links created at map start (the panel's marker and its `Anchor`, `NavPts`, the list of bacta dispensers). 3) Scripts enable and disable panels only on the server. 4) `CTPlayer.Use`/`StartHandSignal` changed the panel and remembered the target only on the client, while `HandSignal` and the panel work on the server | Hook of `HasRequiredInventory` (same code, `simulated`); `ClientCoopSetPanelLinks` and `ClientCoopSetPanelState` (flags usable/activating/activated, changes at once, everything every 3 s); `ServerCoopUsePanel` and `ServerCoopStartHandSignal`. Test `CoopTest=panel` (`CoopTestPanel=<type>`, `CoopTestForce=Locked/Unplaced`): bacta 40→200 health, hacking the door on GEO_01C goes past 87% and on |
| Map objects have a different shape on clients (the bunker on GEO_01A) | `DrawScale3D`, `PrePivot` and `Skins` aren't replicated: the client creates the object with the class defaults (Bunker2 is scaled 2.0 on the server, 1.0 on the client) | `CoopGame.SendMapActorDisplay` sends them to the client once per second, 10 times (`ClientCoopSetActorDisplay`, the scale as three floats because replicated vectors are rounded to integers) |
| NPCs move jerkily on clients | The multiplayer network settings: 10000 bytes/s per client and 20 updates per second on the server, and the client's default internet speed `ConfiguredInternetSpeed=5000` (the log showed "Net speed 5000"), lowered further by `bDynamicNetSpeed` | Native `SetNetRates`: on the host `MaxClientRate=40000`, `NetServerMaxTickRate=35` (`CoopConfig.NetClientRate/NetTickRate`, in memory only). On joining, the client turns off `bDynamicNetSpeed` and asks for 40000 |
| NPCs on clients move in the same pose all the time | The pawn's stance (`CurrentIdleState`: relaxed, alert, berserk, at a turret…) is set by the AI on the server and isn't replicated, but the idle, walk and run animations depend on it. On the client all NPCs kept the default stance | `CoopGame.SyncIdleStates` (changes every 0.2 s, everything every 3 s) → `CoopPlayer.ClientCoopSetIdleState`. Checked in the log: the squad is "relaxed" on the server, was "alert" on the client, matches after the sync |
| Map objects (bunkers, bunker walls) appear late or not at all on clients | Dynamic static meshes of the map are replicated, the client deletes its own copies. The server sends an actor only while it considers it visible (a trace to its center), and the center of large meshes is often inside other geometry | `CoopGame.MakeMapActorsRelevant` sets `bAlwaysRelevant` on such actors when the level loads (32 actors on GEO_01A, 72 on GEO_01B) |
| Client crashes on GEO_03D (`General protection fault` in `CoopPlayer.PlayerTick`) | `Gunship.PostBeginPlay` is `simulated` and creates the ship's turrets on the client too. These local copies get their own AI controller, are left behind by the ship, fall out of the world and "die" on the client without a `GameInfo`, after which the player's target selection crashed | Hook of `Gunship.PostBeginPlay` in `CoopExtension`: on the client the local turrets and their controllers are removed at once, the server's turrets come over the network. A scan of 17 levels (GEO/RAS/YYY) in 0.57: no local pawns with a controller are left on clients, only a harmless dead clone without a controller on GEO_01A |
| The client couldn't revive the host and couldn't heal with bacta at all | 1) The native replication of Pawn doesn't send `bIncapacitated` to clients: for the client nobody was wounded. 2) The client goes to the `UsingItem` state, but the server kept it in `PlayerWalking` and threw it back right away during the position check (`ClientAdjustPosition` sends the server's state) | `CoopGame.SyncIncapacitated` tells the clients once per second who is wounded (`ClientCoopSetIncapacitated`). `CoopPlayer.UsingItem` tells the server about the start and the end of the use (`ServerCoopUsingItem`), the server mirrors the state. Tested with `CoopTest=clientrevive` with real key presses in the client's window |
| After being revived the client has no weapon until it picks up ammo | The weapon stayed in `DownWeapon`: the game wants to "change" the weapon to the same one, and `Pawn.ChangedWeapon` does nothing in that case (the code is commented out in the original) | `CoopPlayer.FixStuckWeapon`: if the weapon is down and the animation ended more than 1.5 s ago, the client raises it itself and the server gets `ServerChangedWeapon` |
| White screen after a client died | `Dead.BeginState` of single player fades the screen to white (fade, bloom, blur); in single player loading a save resets it | For clients `Dead.BeginState` does what the original does without the effects; until the respawn the camera shows another player from the third person |
| The host looks gray and blurry to clients | The single player commando has no skin of its own: the default material of the mesh is used, which nobody ever saw in single player | Clients give the host's model the white multiplayer skin `CloneCommandoWhite_Shader` |
| Other players froze standing in mid air when jumping and fell to the ground like that | `Pawn.PlayJump` is empty, and the native animation of the single player commando keeps the standing pose in the air (in single player you never see yourself from the outside) | Hooks of `PlayJump`/`PlayFalling` in `CoopExtension`: for other commandos (on the host and on clients) `Jump` and `FallBreathe` are played, the model has them. Tested with `CoopTest=jump` and `hostjump` with frame captures. Released in 0.4 (before that as an updated archive of release 0.3) |
| Batch files were inconvenient: the player had to know which one to run | Everything the batch files did is already in the menu (`CO-OP: HOST/JOIN`) | The batch files were removed. On the first start of `CT.exe`, `ModCoop.dll` creates a desktop shortcut once (`-forcelogflush`) and asks once about the firewall rule (`MessageBox` → `netsh` through UAC, only with the player's consent; markers `Save\ModCoopShortcut.done` / `ModCoopFirewall.done`, skipped with `-CoopNoSetup`). `ModCoop.u` wasn't rebuilt, the version stayed 1.3 |
| The second and third client lost their squad member on the next level | `StaticSaveConfig` in RC puts a changed string back to the value saved first; in addition, values read from `Save\ModCoop.ini` are written commented out (`;  `) and lost after a restart | The lists (recent addresses, squad members of the clients) are written natively to the section `[ModCoop.Lists]` (`CoopNative.Read/WriteSavedString`), values read from the config are marked as changed (`LoadSavedConfig`) |
| Host crash in `AController::Tick` (the one on the screenshots; reproduced on GEO_04A right after Scorch was taken over) | The native squad AI (stack: `Commando07Bot`) treats every squad member as a bot, but a client already controls the member | Squad members of clients are taken out of the AI squad (`DetachClientMembers`, checked every second — scripts add them back); they rejoin before a level change so they travel with the squad. The crash history now shows the bot's name (`CoopCTBotTick`). Their HUD icons are drawn by `CoopHUD` since 0.58 |
| "The AI sniper doesn't shoot" on GEO_01C | Two conditions of the scene: a player standing at the sniper crate keeps Sev from the position (the marker stays in `Setup`); when the position is reached too fast, Sun Fac misses the event and doesn't run to his ship | The second is fixed by `CheckMissedEvents`; the first is how the original works: the sniper position has to be free |
| The third client was dropped 3 s after joining (BADCDKEY) | `MasterServerUplink` checks the CD keys of the clients; the same key (one PC or the same GOG key) is "in use" | The host removes `MasterServerUplink`: co-op connects by address, advertising the server on GameSpy isn't needed |
| The squad icons were missing for squad members played by clients (host) and for everybody (clients) | The helmet draws the icons natively, only for AI members of the player's own squad; clients have no squad (it isn't replicated). Putting the client members into a squad just for drawing didn't help | `CoopHUD.DrawCoopSquad` draws them with the same texture (`CloneVisorIcons`) in the slots of the helmet |
| Clients had no objective tracker, no current objective, no critical messages of scripts | See "Status (0.58)" | Forwarding of the script actions in `CoopExtension`, objectives synced by `CoopGame.SyncObjectives` |
| Clients saw no explosion when a door was breached | Emitters aren't replicated | `CoopGame.ForwardEffect` for `ActivateItem`/`DroidDispenser` transitions and props |
| A client who played Fixer before saw the level through Fixer's eyes from the start of GEO_01B | `SpawnClient` waited for the client's squad member wherever it was; Fixer is on GEO_01B before he joins | Only members already in the host's squad are waited for; the others are handed over in their scene, always with the camera flight |
| The third of three clients didn't spawn on GEO_01B | The spawn spot next to the host was taken by another client, no other spot was tried | `SpawnCommandoNear` tries every spot around the host |
| Scorch moved slowly and couldn't crouch after the takeover, fine on the next level | His script walked him (`bIsWalking`, `MaximumDesiredSpeed` = 156) and the values stayed on the pawn | `TakeOver` resets walking, analog speed, ground speed and the crouch/jump flags |
| (live test) The client had no weapon after detonating the charge to Fixer's door | The hands (`HandSignal`) kept playing an animation on the client and stayed in `Active`, while the server had already given the weapon back | Hands that stay active for 3 s without "Use" held go on to `Idle`, which brings the weapon back (`FixHandSignalWeapon`) |
| Enemy factories got `Accessed None: Pawn` | `Factory.PlayerRangeTest`/`IsLocationCovert` use the pawn of every player controller, players without one (joining, dead) counted as standing at the origin | Hooks with the same code that skip players without a pawn |
| Factories that spawn near the player (`SPM_NearPlayer`, e.g. falling dust on GEO_01B) logged `Accessed None: Pawn` many times and could pick a spawn point near the origin of the map | `Factory.GenerateActor` looks for the spawn point nearest to every player controller's pawn, also for players without one | Hook with the same code that skips players without a pawn (`CoopExtension.FactoryGenerateActor`). Tested (`CoopTest=factories`): no warnings, the near-player factory spawns all its items |
| (live test) No enemies in the two rooms after Fixer on GEO_01B (bacta room, room with the door to hack) | The level spawns them after `BrokenDoorDemoUnderway`, the `EventUnderway` of the demolition marker of Fixer's door. A client playing Scorch places the charge himself, the marker isn't started and the event never came (same for `SpawnDemoDroids` on GEO_01A) | When a player activates a panel that belongs to a squad marker the AI isn't doing, the server triggers the marker's `Event` and `EventUnderway` (`SyncPanelStates`); the door breach does the same (`CheckGather`). Tested: `SpawnControlRoom` goes online after the client's detonation |
| The custom squad icons didn't line up with the helmet's own ones, especially in a grid of 4 windows; no orange health level, no order, no timer ring | The numbers were fitted by eye. The machine code of `UHelmet::DrawHUD` in Engine.dll shows the exact layout, and that in network games the helmet bends its HUD (`FCanvasUtil` curved surface: points pulled to the center by up to 10%) | `CoopHUD` redone from the machine code (see `Notes/HelmetHUD.md`), with `Canvas.SetCurvedSurface`; order icon and marker state from the host (`CoopGame.GetSquadIconState`). Tested against the helmet's icons at 800x600, 1280x720 and 1600x900: frame, order icon and arrow match to the pixel |
| (4-window test) A client playing Fixer threw a grenade: the animation played, no grenade flew and none was used up | Squad members taken over from the AI have no current grenade on the server (`Pawn.CurrentGrenade`), so `ServerThrowGrenade` failed (`Accessed None: CurrentGrenade` on the host); the client picks one itself (`EnsureGrenade`) | `CoopGame.EnsureClientGrenades` picks the first thrown weapon on the server too. Tested: grenade removed on the server (`CoopTest=grenade?CoopTestClearGrenade=1`) is picked again within a second |
| (4-window test) Fixer's camera was lower after a client took him over | `Pawn.BecomeViewTarget`, which turns on the eye height, only runs on the server: the former AI pawn kept `EyeHeight` 0 on the client, the camera was at the center of the body, 60 units too low | `CoopPlayer.FixEyeHeight` turns it on for the client's own pawn. Tested on GEO_01B: EyeHeight 0 → 60 |
| (4-window test) The scene of a squad member (Fixer) was seen through his eyes and the scene itself was mostly not in the picture | — | The camera looks over the member's right shoulder during the scene and moves into his eyes when the client gets him (`CalcWatchView`, `TakeoverArc` 0). The member isn't the view actor, otherwise the engine doesn't draw him |
| (4-window test) Invisible wall: a client's log showed "Server corrected the position by 240" 30 times with the same server position | The pawn on the server didn't move while the client walked on; after every correction the client replays its moves and is ahead again. Nothing blocks there at the start of GEO_01B on the server (`CoopTest=probe`), so it is something that appears during play | Diagnostics on the host: "... is blocked on the server at ... hit <actor> (class, location, mesh, state)" (`CheckClientsBlocked`) |
| (4-window test) Hands and weapon still disappear on clients | not found yet (the test logs were overwritten by a later test run) | Diagnostics on the client: "Weapon problem: ..." when the weapon stays missing or in a non-idle state without animation for 3 s (`CheckWeaponShown`) |
| (live test) Hands and weapon disappeared on clients | The friend's log: over a thousand `CTPlayer.UsingItem.PlayerTick ... Accessed None: Weapon`. The client stayed in `UsingItem` without a weapon; every tick it saw no hand signal weapon and started the hand signal again | A client without a weapon for a second brings up the pending weapon or its best one (`FixMissingWeapon`) |
| (live test) GEO_03A: the elevator at the start didn't stop | The elevator's lights ride on a mover that loops forever; the script can't destroy it (`bNoDelete`) and turns the lights off instead (`ShutoffElevatorLights`, `TriggerLight`). `TriggerLight.Tick` only runs on the server, on clients the lights stayed on and the elevator seemed to go on | `CoopGame.SyncTriggerLights` sends the brightness of trigger lights. Tested: the 4 elevator lights turn off on the client |
| (live test) The numbers above the squad icons looked different from the helmet's | They were the small numbers of `CloneVisorIcons`, scaled | The digits of the helmet's font (`OrbitFonts.OrbitBold15`) are drawn from its page texture, glyph by glyph, with the rectangles read from `OrbitFonts.utx` (`CoopHUD.DrawNumber`). At 800x600 identical to the helmet's |
| (live test) A client (Fixer, GEO_01C, at the door to breach) crashed: `General protection fault` in `CoopPlayer.PlayerTick` | not found: no script warning before it; walking into the same door in a test doesn't crash | — |
| (live tests) Remote clients crashed on GEO_01C (`General protection fault` in `CoopPlayer.PlayerTick`) | The crash diagnostics showed it: `CTGame.dll+0x2A5EA` in `ACTPlayer::SelectTargetType` (what the player looks at), reading `Target.SquadMarker` (offset 0x18C) right after it found `Target` is None. A bug of the game that single player never reaches; network clients do | `ModCoop.dll` calls the native through a guard (`execSafeSelectTargetType`): a crash there clears the target and the game goes on (logged as "Caught a crash in CTPlayer.SelectTargetType"). Targeting tested with the bacta dispenser |
| (live test) After GEO_01B → GEO_01C two clients with their squad members stayed up where the squad comes down on ropes and had to jump | Clients load slower than the host and got their members while the level waited for them; the ropes are scripts of the AI, a member played by a client skipped its entrance | The host waits with the level until every client's camera has something to show (its pawn or the member it watches; `CheckClientsArrived`). A member whose script still has an entrance (waits for an event, then an animation or a physics change) isn't given to its client at once: the client watches it over the shoulder and gets it when the entrance is over (`StartIntroWatch`, `CheckIntroWatch`, at most 40 s). Fallbacks: a member in a scripted physics is set to falling on takeover; in the first 40 s a client more than 400 units above the landed host is moved to the host. Tested (`CoopTest=travel?CoopTestStopAt=GEO_01C`): the client watches 40 come down the rope and gets him below |
| (live test) Collision: the host's "blocked on the server" lines | All real blocks were real objects the client hit as well (a chair on GEO_01C, barrels, a bacta dispenser); "nothing in front" were pawns that were only slow | Only logged when the pawn on the server really stands still |
| (live test) Invisible walls in the hangar of GEO_01B (every client stopped at x≈215 and x≈1065 while the server went on, corrections up to 680 units) | The explosion shows the wrecks of the fighters (`K_GEO4FighterDestroyed`, `KarmaProp`) and throws them around. Karma is simulated by every computer itself, positions aren't replicated: each client had its wrecks elsewhere | Karma props that the physics moved don't block players anymore (`UnblockKarmaProps`, also sent to the clients); untouched ones (explosive barrels) still do, AI still bumps into all of them. Tested: the woken fighter wreck is unblocked, the barrels are not |
| (live test) GEO_01C: the descent started before the clients on the host's PC had loaded | The host only checked that the clients had a pawn or a member to watch | A client counts once it has drawn its first frame (`ServerCoopReady` from `PlayerCalcView`, works while the level is paused) and has a pawn or member to watch |
| (4-window test) GEO_01C: Scorch's animation broke at the start (a game started on GEO_01C) | A client without an assignment got Scorch from `CheckSquadTakeover` before his rope; only assigned members were watched first | Every takeover path checks for an entrance first (`StartIntroWatch`) |
| (4-window test) The camera of the entrance didn't follow the model down the rope | The camera followed the pawn's location, the rope moves the mesh; and while the level is paused only controllers are replicated: the clients got their members at the bottom | The camera follows the helmet bone (`lightAttach`); the watched member is always relevant; after the pause the level runs 10 times slower until the watching clients report their camera on the member (`CheckSlowStart`, at most 4 s). Tested: camera from the top (Z 1240) down with the model |
| (4-window test) A client playing Sev had no way to find the sniper position: only a text, the marker icons aren't shown on clients; the ship got away | — | The objective tracker points to the sniper position until the client is there (radius 300). Not tested by hand yet |
| Door breach with players | The charge was placed at once when the squad had gathered, without the single player animations | Gather radius 900. Once gathered, the clients' squad members go back to the AI (`StartAIBreach`) and the squad does the breach like in single player; the clients watch over the shoulder, looking at the door, and get their members back as soon as the door blows (`CheckAIBreach`). Tested on GEO_01C with 3 clients |
| The host hung right after the breach | `CTSquadNative::RemoveAssignmentsByMember` (CTGame.dll+0x51E0, found by sampling the hung process) loops forever over the assignments of a member whose controller isn't a `CTBot`: the members were removed from the squad after the players had them again | Members leave the squad while the AI still has them (`EndAIBreach`, `TakeOver`) |
| After the breach the clients saw their own model from inside, no first person weapon | The client's copy of the pawn had no controller anymore (the AI had it): eye height 0 every tick | `FixEyeHeight` gives the pawn its controller back on the client |
| (live test) GEO_01B: invisible walls in the hangar (clients stopped at x≈215 and x≈1065, corrections up to 850) | `Hangar01BlockingVolume`, a static blocking volume: the level script switches its collision off (`ACTION_SetCollision`, event `Fighter01Destroyed`) on the server only, static actors aren't replicated | `ACTION_SetCollision` and `ACTION_SetHidden` are hooked: the clients do the same by tag (`ClientCoopSetCollisionByTag`, `ClientCoopSetHiddenByTag`, sent again every 10 s). Tested: the volume is off on the client |
| (live test) GEO_01C: a client playing Sev couldn't do the sniper scene, the ship got away | The scene is Sev's AI script (walk to the position, wait for the take-off, shoot) | Sev goes to the AI for the scene (`StartAISnipe`): his script is started again where it waits for the order, the marker's events are triggered as the marker would, he is invulnerable like in his script; back to the client when the shot target is gone. Tested (`CoopTest=snipe?CoopTestChain=1`): Sun Fac's ship is shot down, the objective is completed |
| Scripts stood forever on an action that doesn't wait ("If condition") | A new AI controller didn't continue its script after a wait | `CheckStalledScripts` continues such scripts after 2 s |
| (live test) GEO_03A: no briefing, the elevator never stopped | Scorch throws the holo projector in his script and its animation starts the briefing (`StartBriefing`); the briefing ends with the event `Elevator` that stops the elevator. Clients got Scorch (and the others) at once, the script was a moment past its first wait | An entrance is any animation or physics change before the next wait for an event, wherever the script is; watched for up to 90 s. Tested GEO_01C → GEO_03A with 3 clients: the briefing plays, `Elevator` comes, the clients get their members |
| (code survey) GEO_05B: the elevator at the end, GEO_05C: the hatch and the end of the level | On an event each squad member's own script walks it to a point and triggers a counter (`MemberArrived`, `MemberArrived00/01`, 3 needed). The script of a member a client plays is dropped, so the counter never got it and the level stopped. Found by reading the scripts of all campaign maps from the .ctm files | `CoopGame.ScanArrivals` finds, in the script of each client's member, a walk to a point followed by the trigger of a counter, and the event the script waited for before it (outside of its conditions); `CoopEventListener` hears that event, `CheckClientArrivals` triggers the counter when the client is within 250 of the point, or right away if the member died. Tested with 3 clients (`CoopTest=arrive`): GEO_05B `StartElevatorTrigger`, GEO_05C `BlowHatch` and `EndLevel` |
| (live test 3 sessions) 1-2 clients dropped on every level change | The master server uplink of the new level checked the clients' CD keys ("CD Key in use", BADCDKEY) the moment the level started after waiting for them; `RemoveUplink` ran from the Timer, a second too late | The uplink is removed in the first frames of the level (`Tick`). Not yet tested in a live session |
| (live test) Weapon gone or frozen on clients (after pickups, panels, healing) | The fire animation of the weapon was cleared (pickup, hands, bacta healer) and the weapon stayed in NormalFire on the client; a weapon going down waited 1.5 s before `FixStuckWeapon`, too long for the healer | `CoopPlayer.FixStuckFire` ends a shot without animation after 1 s (not the healer, the hands or with Use held); stuck down weapons are brought up after 0.4 s. A pickup test (`CoopTest=weaponpickup`) swaps secondary weapons correctly; the live case was not reproduced |
| (live test) Clients couldn't use turrets (GEO_04D) | `CTPlayer.Use` mounts with `Target.UsedBy` on the client only; aiming happens in `PlayerManningTurret.PlayerMove` which never reached the server; the turret's ammo isn't linked on the client | `ServerCoopUseTurret` mounts/leaves on the server, the client aims with its own angles (camera follows), `ServerCoopTurretAim` turns the turret and puts the turret's weapon at the camera; ammo linked on the client; no catch-up teleport while on a turret; the weapon comes back after leaving. Tested (`CoopTest=turret`): gunship cannon and E-Web manned, aimed, E-Web fires, left |
| (live test) Demolition marker gone before the spider droids (GEO_04D) | The level disables the marker at the start and enables it later with `ACTION_GotoState`, only on the server | `ACTION_GotoState` on squad markers is forwarded to the clients (`ForwardMarkerState`, resent every 10 s) |
| (live test) A client spawned under the map at the start of GEO_05A | The level starts in a lift (38 s); clients waited for the host to get off, after 30 s they were spawned next to him at the bottom of the shaft | While the host rides a lift (`HostLift`) clients are spawned / put on the floor of the car (`FindLiftSpot`) and stand still like him (`CoopLiftRide`) until it stops. Tested on GEO_05A with 2 clients: they ride up with the host |
| (live test) Sniper scene: the AI had Sev too long, wrong weapon, teleported away | The AI took Sev when the marker appeared; then the client's Sev shot with the blaster, got him back before the ship's cutscene and the catch-up teleport moved him to the host | The client walks to the position himself; the AI gets Sev at `TakeOff` (the shot), with a lent `DC17mSniperCommando` switched in at once, keeps him until the ship's script is over, no catch-up teleport during the task and 30 s after. Tested: the ship's script takes the success branch (`ShootDownSunFac`) |
| (live test) A big yellow ball on clients (GEO_03A: the shield of the jamming device in the tower; GEO_01A: the wall) | Map static meshes that replicate (Prop, StaticProp...) are recreated on clients from the class defaults: the shield had the tag "Prop" instead of "shield", no ambient glow (0 instead of 102) and no static lighting baked into the map (`StaticMeshInstance` None); location and rotation rounded | `CoopGame.NeedsLookSync`/`ClientCoopSetActorLook` send the tag, glow, unlit flag, the name of the map's `StaticMeshInstance` (loaded on the client from the level package) and the exact location/rotation. Tested on GEO_03A: the client's shield has the host's values and looks like the translucent dome, destroying it reaches the client |
| (live test) NPC animations of level scripts missing on clients (the GEO_03A elevator) | `ACTION_PlayAnim` is replicated (SimAnim), but the script's controller takes over the animations (`bControlAnimations`) and controllers aren't replicated: on clients `Pawn.ChangeAnimation` went on playing idle/moving animations over it | `ACTION_PlayAnim` is hooked (`CoopGame.ForwardScriptAnim`): clients play the animation and put a local `CoopAnimController` (bControlAnimations) on the NPC until the script lets go (`CheckScriptAnims`). Covers all 372 `ACTION_PlayAnim` of the campaign. Tested on GEO_03A: the clients get the talk animations in the elevator |
| (live test) GEO_03A: in the elevator nobody had the animations of the original scene, clients got their members at once | The car doesn't move (the walls of the shaft do), the lift detection didn't see it; the takeover dropped the members' scripts (talk animations, Scorch's holo projector) | Start scenes by level and end event (`SceneMaps`/`SceneEndEvents`: GEO_03A `Elevator`, RAS_03A/YYY_04B `UnlockPlayer`): until the event the members keep their scripts, clients watch them, host and clients stand still, everybody's camera over the shoulder looks at the middle of the squad and can look around (`ClientCoopLiftView`). Tested on GEO_03A with 3 clients: the scripts play to their end, `Elevator` comes, then each client gets its member |
| (live test) GEO_05A: two clients behind the walls of the lift shaft, first person wanted | Clients were put on free spots next to the host, outside the small car; a stop of the lift between its keyframes ended the ride | Everybody stands on the host's spot, the players don't block each other and every computer only draws its own player's commando (`HideRiders`, `ClientCoopHideRiders`, also for clients that arrive later), first person with free look (the camera is put back on the own commando if a spawn left it elsewhere), attached parts hidden too; short stops don't end the ride; on arrival the clients are moved to free spots before blocking is on again. Tested on GEO_05A with 2 clients |
| (live test) 7 models of the squad seen once | Not reproduced (4 commandos on the host and every client in the same level) | Host and clients log the commandos they see when the number changes (`Commandos:`, `Commandos seen:`) |
| Crashes of remote clients that the engine only reports as "PlayerTick" | — | Crash diagnostics in `ModCoop.dll`: a vectored exception handler logs the exception, `module+offset`, the registers, the return addresses on the stack and the last step the script marked (`CoopNative.SetDebugStep`, every step of the client's `PlayerTick` and the HUD). Status lines every 10 s on the client ("ModCoop: Status") and for every client on the host ("CoopGame: Status"). Tested with a crash on purpose (`CoopTestGPF=1`) |
| (live test) Invisible walls on the client in two places, not reproduced yet | — | Diagnostics in the client's log: "Blocked at ... knee=... chest=..." when the pawn doesn't move while the player moves, and "Server corrected the position by ..." for large corrections |
| The reconnect menu tried only once | a failed `open` from the menu doesn't open `MenuConnectionFailed` | the menu waits for the timeout itself and tries again (up to 12 times) |

## Tested (automated tests on one PC, host + client 127.0.0.1)

Environment: Windows 11, Visual Studio 2026 (v145), GOG version of the game, the host and the clients are separate `CT.exe`
windows on one PC (up to 4).

| Test | Result |
|---|---|
| The host loads each of the 50 playable levels of the campaign in co-op mode (scan of all `CoopLevels`, 28 s per level) | 50/50 without crashes |
| A run through the whole campaign with a client: the host moves on to the next level every 50 s, the client follows | all 50 levels + EPILOGUE: the client connected on every one, no crashes (after the fixes above) |
| Position sync (`bDebugLog`): server vs client | difference < 1 unit (rounding during replication) |
| Level change with the squad (GEO_01B, GEO_01C): squad 07/40/62 present, on the host's HUD | yes |
| A client is wounded → the host revives them (`revive`, the original `TGT_FriendToHeal` + holding "Use") | revived after ~5 s |
| A client died → respawn next to the host | after 5 s, health 200 |
| The host "loads the checkpoint" → the part restarts | everybody stays in the game, the client doesn't reconnect |
| The host process is killed → the host is started again after 15–40 s | client: RECONNECTING screen, back in the game on the 2nd attempt |
| All 4 co-op menus open (`?Menu=`) | no script errors |
| Host + 3 clients on GEO_01C from scratch, then the level change to GEO_03A (0.57) | every client gets their own squad member and keeps it on the next level |
| Sniper scene GEO_01C with the AI sniper and with a client playing Sev, also with a "too fast" sniper (0.57) | mission success in all three cases |
| Hacking by a client playing Fixer (GEO_01C), demolition by a client playing Scorch (GEO_01B) (0.57) | door unlocked, charge armed, no crashes |
| Squad icons, objective tracker, objectives and effects on clients (0.58) | logged and captured on screenshots, not tested by hand |
| Squad icons (0.59): a copy drawn over the helmet's own icons (`CoopTest=squadicons`) at 800x600, 1280x720, 1600x900; timer ring while a client places the charge on GEO_01B, seen by the host and another client; factories (`CoopTest=factories`) | frame, order icon and arrow hidden completely by the helmet's icons, ring the same for host and client, no factory warnings |

Crashes found by the runs and fixed: see the table above (travel/`TravelPostAccept`, `ClientTravel` without a pawn,
`InitialClientActor`, briefings, `UpdatePreNet` — an outdated class cache in fix 3, now only `Mover`/`StaticMeshActor`).

**What the automated tests don't cover:** most levels were checked for about a minute (loading, spawning, network, level
change), not played through. Scripted scenes in the middle of levels (turrets, defending positions, boss fights), fighting
enemies and the squad's behavior in combat with connected clients need a live test with several players.

Tools (for the developer, players don't need them):
- `?CoopTest=<action>?CoopTestDelay=<s>` in the host's URL — automated scenarios in `CoopGame.TickTest`, e.g.
  `travel` (next level; the option is kept → a run through the whole campaign), `restart`, `checkpoint`, `clientdeath`,
  `clientincap`, `revive`, `panel`, `door`, `breach`, `scene`, `snipe`, `levelinfo`, `memberinfo`, `squadicons`.
- `ModCoop.ini`: `[ModCoop.CoopConfig] bDebugLog=True` — positions/health of the players on the server and the clients once
  per second, and at level start the list of "static" actors that will be replicated.

## Known limitations and bugs

- **No saves in co-op.** A checkpoint is the start of the current part. The parts are short (usually 10–20 minutes).
- **Only the host commands the squad.** Clients are not squad leaders: the AI doesn't heal or cover them, and the clients'
  orders are ignored. Reason: the native squad code (`CTSquadNative`) is designed for one player leader. A second leader can't
  be added safely without reverse engineering.
- **Movies are only seen by the host.** Bink videos (`ACTION_PlayMovie`) play locally on the host while the clients stand
  still. Matinee scenes only move the host's pawn; clients left behind are moved to the host.
- **Pausing** doesn't work in network games (turned off on purpose: otherwise the host's menu would freeze everybody).
- **Menu texts are in English:** the game's fonts have no Cyrillic letters.
- After leaving a co-op session, the shortened connection timeouts (15/30 s) stay for the rest of that game session — this
  doesn't affect normal multiplayer except for a faster disconnect when the connection drops.
- **GEO_01A, the wall explosion (`Prop3` "BarricadeWall", `Arena_HR.ArenaWalls.BlowAwayWall`): the client loses the textures** — probably fixed by sending the static lighting (see the GEO_03A shield), not checked on that wall;
  — not fixed. The wall is a destructible `Prop`; on the client it's a replicated copy without baked lighting
  (`StaticMeshInstance`), and the change of material (`Skins[0]`) on destruction isn't replicated. A screenshot is needed to
  tell which of the two causes it.
- NPCs on clients don't lean their body and head towards the target like on the server: the aiming is computed by native code
  from AI data that doesn't exist on clients.
- On the host, squad members played by clients are not in the AI squad: the AI doesn't revive them, and markers that need
  several AI members may not start (the door breach doesn't need them, see `CheckGather`).

## Left out and why

- **Saving/loading in network games** — the engine blocks writing a save in network mode in `UGameEngine::SaveGame`.
  A workaround needs reverse engineering of Engine.dll (against the rule "high level paths first"). Replaced by restarting
  the current part.
- **Squad orders from clients** — see the limitations: native squad code.
- **Showing movies to clients in sync** — a client function `PlayMovie` with a sync of the movie's end could be added, but
  the server would have to wait for all clients; postponed for stability.
- **Briefings (GEO_01Briefing, RAS_01Briefing, YYY_01Briefing, YYY07Briefing) are excluded.** The client reliably exits
  during the level start on them (BeginPlay), without an exception and without an entry in the Windows event log — there is no
  call stack, and finding the cause needs debugging of the binary. Briefings are cutscenes without gameplay, so
  `CoopGame.SkipBriefing` sends any level change to a briefing straight to the next level of the campaign (by
  `GameEngine.ProgressLevels`), and if the server was started on a briefing, it leaves it within the first second. PRO
  (the prologue) isn't in the host menu either.
