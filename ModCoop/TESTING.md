# ModCoop testing

## Build

`Code` has to sit next to `GameData`. Needs Visual Studio 2026 with the x86 toolset v145.

```
powershell -ExecutionPolicy Bypass -File ModCoop\Tools\Build.ps1             # ModCoop.dll, then ModCoop.u
powershell -ExecutionPolicy Bypass -File ModCoop\Tools\Build.ps1 -SkipDll    # scripts only
powershell -ExecutionPolicy Bypass -File ModCoop\Tools\Build.ps1 -Tunnel     # also CoopTunnel
```

Order matters: DLL first, then `make`, otherwise UCC hangs on "failed to bind native function". UCC only builds packages without a `.u` file. It regenerates `Inc/ModCoopClasses.h`, so if native fields or functions changed, build the DLL again. UCC doesn't exit after a compile error: the script applies a timeout and reads `UCC.log`.

**Every compile gives `ModCoop.u` a new GUID.** After a build, a player with the released archive can't join. Back up `ModCoop.u` and `ModCoop.dll` first if the installed release has to keep working with others.

The whole solution: `build.bat release` from the x86 developer prompt.

Release archive: `powershell -ExecutionPolicy Bypass -File ModCoop\package.ps1`. See skill `release-pipeline`.

## Automated tests on one PC

```
powershell -ExecutionPolicy Bypass -File ModCoop\Tools\RunTest.ps1 -Map GEO_01A -Clients 1 -Seconds 90
powershell -ExecutionPolicy Bypass -File ModCoop\Tools\RunTest.ps1 -Map GEO_05A -Clients 2 -Test hostlift
powershell -ExecutionPolicy Bypass -File ModCoop\Tools\RunTest.ps1 -Map GEO_01B -Clients 1 -Test door -Members Commando62Delta
```

The script starts a host and clients, waits, stops only its own windows, prints a summary and always clears the test assignments. `GameData\System\CoopTest.bat` is the interactive version for playing by hand.

Scenarios are in `CoopGame.TickTest`, chosen with `?CoopTest=<name>`:

`aapickup accessory arrive assign blocked breach captive charge checkpoint checkpointreturn clientdeath clientdown clientincap clientrevive door doorhold elite endlift facing factories getupdown goto grenade bactaicon handsidle healweapon hostdown corpsesave hostjump hostlift hud lobbyslot jump levelinfo loadcheckpoint lobby memberinfo movers namecolor npc panel pickup probe propinfo restart revive ride rope savemenu saveslot scene snipe snipeorder squadicons squadinfo squadwalk takeover travel turret turretnear walker wall weaponpickup`

Some take more options (`CoopTestCause`, `CoopTestDelay`, `CoopTestEvent`, `CoopTestHost`, `CoopTestPanel`): read the scenario first. A client's rotation can't be set from the server in a test, so check what a test can drive before writing it.

`CoopTestCause` doesn't fire on the first loaded map without `?CoopTestWait=1` (`LevelStartTime` stays 0). `?CoopTestNoCatchUp=1` keeps a client where `goto` put it: the catch-up moves it away after 15 s. `?CoopTestGotoLog=<part of a script tag>` makes `goto` log those scripts every 2 s.

`checkpointreturn` (RAS_01B, `-Delay 32 -Options "?CoopTestWait=1"`): 150 health and 77 rounds before a real checkpoint, then every enemy killed, then the checkpoint loaded: by the button, or `CoopTestSquadDown=1` by the whole squad down. `CoopTestReload=1` loads it a second time. Check `back from the save` (enemies back), `after:` (health, ammunition, place of each player) and the clients' `client pawns`.

Save slots: `saveslot` on a level (`-Members Commando62Delta,Commando40Delta -Delay 40 -Options "?CoopTestWait=1"` on GEO_01B) writes slot `CoopTestSlot` (default 1) with 150 health and 77 rounds, then tries slot 2 with a client down (refused) and checks the joining rule. Then `lobbyslot` on `MPCustom` (`-Options "?CoopTestLobbyClients=2?CoopTestSlot=1"`) picks that slot in the lobby and starts it; the loaded level runs no test, read `save loaded`, `takes over`, `is back` and `Status`. Run both with the same build: a new build can't load the slot. `savemenu` opens the host's pause menu and then SAVE GAME for screenshots (`Shot.ps1 -Front`).

`CoopTestRes` and `CoopTestClientRes` take a size like `1280x720` (window) or `1920x1080f` (full screen; only without `-windowed`, so start such a client by hand). SETRES is saved by the game: put the player's sizes back in `Save\System.ini` after such tests.

`visorfx` hits every player every 6 s (ballistic, then melee) and gives the health back: screenshots with `Shot.ps1 -Front -WaitFor "visorfx: hit"`.

`clientdown` (GEO_01B, `-Delay 40`): the first client down with a held key's acceleration (`moved 0.00 while down`), an AI member put on its revive marker past the bleed-out time (`being revived True`, still down), then taken off: `not revived in time, gets up as` the same pawn next to the host (`same True`).

`handsidle` (GEO_01B, `-Delay 20`): the server's copy of a client's hands left in Idle with another weapon as the last one, the state after a panel. The client's `weapons:` lines must not change and the host logs `parking the hands`.

`doorhold` on RAS_01B with `-Options "?CoopTestAt=-3000,7300,-800?CoopTestKillTrap=1"`: the client on the near side, the door closes at once, `trap: N berserkers`, the test kills them, `trap release (no berserkers left, seen True)`. The host's move fails in this test (`host moved: False`), the hold starts anyway.

`healweapon` (RAS_01C, `-Delay 20`): the client gets the sniper rifle and brings it up (client command `HoldWeapon DC17mSniper`), the host goes down, the client revives him with the bacta healer (`ReviveHost`). Every `healweapon: step` must show the rifle; the client's `weapons:` lines show each change. After a checkpoint load the server's `Status` lines must show the move time (`MoveTime`) counting again.

`HudNames` (a client test command, also sent by `hud` at step 2): every commando's name over its head as host and client have them (`hud names:`).

`hud` checks the clients' HUD: the host's icon and the objective tracker taken from the host's helmet. `?CoopTestClientRes=1280x720` sets the clients' window size (steps 0 and 2), step 1 points the tracker at a navigation point 1000-3000 uu away, step 3 hides it, 10 s apart. Take screenshots with `Shot.ps1 -WaitFor "hud: host tracker ->"`. On GEO_01A the level's own script also points it at the bacta dispenser.

`Tools/Shot.ps1` takes bursts of screenshots of every game window, optionally when a marker appears in a log:

```
powershell -ExecutionPolicy Bypass -File ModCoop\Tools\Shot.ps1 -Count 6 -Interval 0.5 -WaitLog CoopClient1.log -WaitFor "takes over"
```

The game windows have to be visible: a window covered by something else is skipped with a warning.

`bDebugLog=True` in `[ModCoop.CoopConfig]` of `Save\ModCoop.ini` logs positions and health every second.

## What tests can't cover

One PC has no real latency. Most levels were only checked for loading, joining and the level change. Scenes in the middle of levels and combat with the squad need people. Steam needs two PCs for a real result. Tests by IP on one PC all share `127.0.0.1`.

## Verification levels

Use these exact words in DEVLOG and release notes:

- **code review**: read and reasoned, not run
- **automated test**: a named scenario, its log line or screenshot checked
- **manual play**: a person played it, say how many PCs
- **pending**: nothing of the above yet

A fix without a reproduction is written as unverified. An automated test never counts as manual play.

## Reading logs

| Look for | Meaning |
|---|---|
| `ModCoop version` | Build of each side |
| `heard`, `counter`, `script state of`, `takes over` | How far a level script got |
| `General protection`, `Assertion failed`, `Caught a crash` | Crash, resolve the stack |
| `Status` | Periodic state of both sides, includes weapons |
| `use pressed`, `use done`, `use kept`, `squad command` | Use and orders |
| `timed out`, `Reconnect attempt` | Network path trouble |
| `camera off the eyes`, `duplicate weapon` | The two open bugs of 0.73 |

## Bug report

- level and place
- expected and what happened
- `CoopLogs-*.zip` from **each** PC (`Collect-Logs.bat` in `GameData`)
- screenshots from host and client at the same place for anything visual

## Map analysis

`Tools/MapScan` reads the game's `.ctm` packages. Run with `python -I`, the paths are found by themselves.

| Script | Use |
|---|---|
| `mapscan.py <map.ctm> [class ...] > dump.txt` | Text dump of a map |
| `seq.py <dump.txt> <tag regex>` | Scripts with their actions |
| `disp.py <map.ctm> <Event>` | Who references an event, also inside `Dispatcher` arrays that the dump prints as `arr(N)` |
| `squadscan.py [map ...]` | What counts squad members or players |
| `memberevents.py [map ...]` | Events only squad member scripts trigger: what breaks when a client takes the member |
| `clientmissing.py` | Placed actors that never exist on clients |

Scenario `levelinfo` also prints the scripts of a running level to `CoopHost.log`.

Old notes and skills name these under `scratchpad/`, which is gone. `holdkey.ps1`, `clickat.ps1` (fake input for tests) and the one-off scans `hostonly`, `serveronly`, `markers`, `lifts`, `anims`, `conditions`, `emitters`, `markerevents` weren't restored. `disasm_tool.py` for resolving crash stacks isn't restored either: use the exports of the DLLs with `pefile`.
