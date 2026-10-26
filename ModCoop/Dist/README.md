# Republic Commando — co-op campaign (ModCoop)

[Русская версия](README.ru.md)

This mod lets you play the Star Wars: Republic Commando campaign together with friends (up to 4 players).
One player is the **host**: they play and run the server at the same time. The others connect to them by IP address.
The host plays 38 (Boss) and commands the squad; as the campaign goes on, the other players take over the Delta squad members
(62 Scorch, 40 Fixer, 07 Sev).

The mod is built on [SWRC-Modding/CT](https://github.com/SWRC-Modding/CT), the community fixes for the game.

> **This is a test build.** The mod is still in development, so expect bugs and crashes. The first episode (Geonosis) has been
> played by hand in co-op up to GEO_05A, with checks of single scenes up to GEO_05C; the scripts of all later levels were
> checked in the code, but they haven't been played yet. If something breaks, keep `GameData\System\CT.log` before you start the
> game again and send it (see [Helping with tests](#helping-with-tests)).

## Requirements

- **The game:** Star Wars: Republic Commando for PC, version 1.0 with the official update: the GOG or Steam version, or a disc
  with the patch. Every player needs the same version of the game.
- **Windows 10 or 11** (32 or 64 bit). Nothing else has to be installed: no Visual C++ runtime, no .NET. Linux/Steam Deck with
  Proton isn't tested.
- **The same co-op archive for every player.** The version is shown in the menu title (`MOD 0.6`) and at the start of the log.
- **A connection between the host and the clients:** the same local network, or the same VPN network (ZeroTier, Radmin VPN,
  Hamachi), or port **7777/UDP** forwarded on the host's router. The host allows `CT.exe` in the Windows firewall (the mod asks
  for it on the first start).
- Up to **4 players** (host + 3).

## Installation

1. Find the game folder and the `GameData` folder inside it
   (GOG: `C:\GOG Games\Star Wars - Republic Commando\GameData`,
   Steam: `...\steamapps\common\Star Wars Republic Commando\GameData`).
2. Extract the mod archive **directly into `GameData`**, replacing the existing files. You should now have
   `GameData\System\CT.exe`, `ModCoop.u`, `ModCoop.dll`, `Mod.u` and `Mod.dll`.
3. Start **`GameData\System\CT.exe`** once. On the first start the mod:
   - creates a **"Star Wars Republic Commando Co-op"** shortcut on the desktop — use it to start the game from now on;
   - asks whether CT.exe may pass the Windows firewall. Answer "Yes" and confirm the administrator prompt:
     without it your friends can't connect when you are the host (Windows silently blocks the connections).
   Both steps happen only once. A deleted shortcut is not created again.
   To repeat a step, delete `GameData\Save\ModCoopShortcut.done` or `ModCoopFirewall.done`.

The normal `SWRepublicCommando.exe` and the old game shortcut still work as before, just without co-op.

**Every player needs the mod, and everyone needs the same version.** The easiest way is to give your friends the same archive.

## How to play

### Host
- `MULTIPLAYER` → `CO-OP: HOST CAMPAIGN` → choose the level and the number of players → `START`.

### Client
- `MULTIPLAYER` → `CO-OP: JOIN BY IP` → enter the host's IP address → `CONNECT`.
  The last 5 addresses are saved and shown as a list (file `GameData\Save\ModCoop.ini`).
  If the host doesn't answer within about 17 seconds, this screen shows what to check.

The default port is **7777 (UDP)**. If the host uses another port, enter `IP:PORT`.

### Finding the host's IP address
- **Same local network (LAN):** the host computer's address in the network, e.g. `192.168.1.10`
  (on the host PC: `Win+R` → `cmd` → `ipconfig`, line "IPv4 Address").
- **Over the internet without port forwarding:** install the same VPN network on every PC —
  [ZeroTier](https://www.zerotier.com/), Radmin VPN or Hamachi — and use the host's IP address **inside that VPN**
  (ZeroTier: usually `10.x.x.x` / `172.2x.x.x`, Radmin: `26.x.x.x`, Hamachi: `25.x.x.x`).
- Over the plain internet without a VPN, port 7777/UDP has to be forwarded on the host's router.

### Testing on one computer
Start the game in windowed mode: add `-windowed` to the target of the co-op shortcut (after `CT.exe"`), then start it twice.
Host a co-op game in the first window and connect to `127.0.0.1` in the second one. The active window gets the input; switch
between them with the mouse. **Don't press `Alt+Enter`** with several copies of the game running: switching to full screen
then fails and the game closes with "CreateDevice failed (D3DERR_DEVICELOST)".

## Co-op rules

- **Only the host's progress counts.** The campaign is split into short parts (GEO_01A, GEO_01B, …).
  The engine can't save in network games, so **a checkpoint in co-op is the start of the current part**.
  Single player saves are neither created nor loaded in co-op.
- **Clients play the Delta squad members.** When a new squad member joins in the story (GEO_01A — Scorch, GEO_01B — Fixer),
  the closest client without a squad member gets them: the camera flies to the squad member, the client watches the scene
  through that member's eyes (controls are locked), and takes control once it ends. The host remembers who plays whom (by IP
  address and name), so on the following levels each client starts as their squad member right away. Clients without a squad
  member play extra commandos in colored armor.
- **The host commands the squad.** Orders that have to be carried out by a squad member played by a client (demolition — 62,
  hacking — 40) can't be given by the host: the client does it themselves ("Use" on the marker). If a client plays Sev (07),
  they get the hint "Take the sniper position" when the sniper marker appears and have to go to the sniper crate.
- **Door breach** (from GEO_01C on): the host gives the order as usual, every client playing a squad member gets the message
  "Delta, gather at the door", and the door is blown as soon as everybody is there.
- **Keep the sniper position free:** while a player stands at the sniper crate, the AI sniper can't take the position and the
  scene doesn't go on.
- **Start of a level:** after a level change the game is paused until every player of the last level is back (up to 60
  seconds), so nobody misses the intro scene.
- **When a client goes down:** another player can revive them (walk up and hold "Use", like with a squad member).
  If nobody does so within 45 seconds or the client dies, they respawn next to the host after 5 seconds. Until then the camera
  shows another player from behind.
- **When the host goes down:** the squad revives the host, as in single player. If the host and the whole squad are down but a
  client is still up, the game waits up to 60 seconds for the client to revive the host (message "The host is down!"). If nobody
  does or the host dies, the current part restarts for everybody (the "load checkpoint" option in the death menu does the same).
  Clients stay connected.
- **Lost connection / host crash:** after about 15 seconds the client shows the `CO-OP: RECONNECTING` screen and tries to
  reconnect for about a minute (`RETRY NOW` tries at once, `BACK` returns to the menu).
- **Level changes:** everybody follows the host automatically.
- **Left behind** (e.g. a scripted scene moved only the host)? After 15 seconds you are moved to the host.
  You can also do it yourself: open the console (`~` key) and enter `CoopTeleportToHost`.
- **Briefings are skipped** (GEO_01Briefing, RAS_01Briefing, YYY_01Briefing, YYY07Briefing): after the last level of an
  episode everybody goes straight to the first level of the next one. The reason is described in DEVLOG.md.
- **Title cards** are shown to the host only; the game waits for everybody until the host closes the title card of an episode.
- Pausing (Esc) doesn't stop a network game (a limitation of the engine's network mode).
- **Tutorial hints** are not shown in co-op.

## Supported levels

All 50 playable levels of the campaign (chosen in the host menu):

| Episode | Levels |
|---|---|
| Geonosis | GEO_01A, GEO_01B, GEO_01C, GEO_03A, GEO_03C, GEO_03D, GEO_04A, GEO_04B, GEO_04C, GEO_04D, GEO_05A, GEO_05B, GEO_05C |
| Assault Ship | RAS_01A, RAS_01B, RAS_01C, RAS_02A, RAS_02B, RAS_02C, RAS_02D, RAS_02E, RAS_03A, RAS_03B, RAS_03C, RAS_04A, RAS_04B, RAS_04C, RAS_04D |
| Kashyyyk | YYY_01B, YYY_01C, YYY_01D, YYY_01E, YYY_35A, YYY_35B, YYY_35C, YYY_04A, YYY_04B, YYY_04C, YYY_04E, YYY_04F, YYY_05A, YYY_05B, YYY_05C, YYY_05D, YYY_05E, YYY_05F, YYY_06A, YYY_06B, YYY_06C, YYY_06D |

Not supported: the **prologue (PRO)** and the **briefings** (GEO_01Briefing, RAS_01Briefing, YYY_01Briefing, YYY07Briefing) —
clients crash on them, so the mod skips them. The epilogue (EPILOGUE) works.

Every level has been checked for loading, a client connecting and moving on to the next level. No level has been played all
the way through in co-op yet — if something breaks on a level, please send `CT.log`.

You can shorten the list of levels in the host menu: in `GameData\Save\ModCoop.ini`, section `[ModCoop.CoopConfig]`, add one
line per level you want: `CoopLevels+=GEO_01A`, `CoopLevels+=GEO_01B`, … (with `+=`).

## Graphics mods

Mods that only change textures, models, shaders or rendering (high resolution texture packs, ReShade, DXVK, dgVoodoo,
widescreen fixes) don't affect co-op, but **all players must have the same game packages**. The engine compares the package
files (`.u`, `.utx`, `.usx`, `.ukx`, maps) of the client and the host and drops the connection if they differ. So install mods
that replace such files for every player in the same way, or for nobody. External tools (ReShade, DXVK, dgVoodoo) don't touch
the game files and are safe. Mods that change `System\*.u` (`Engine.u`, `CTGame.u` etc.) or replace `CT.exe`/`Mod.u` are not
compatible with co-op.

Popular mods in detail:

| Mod | With co-op |
|---|---|
| **SWRC Fix** (2.12-2.15) | Already included, don't install it over the co-op files (see below). |
| **dgVoodoo 2**, **DXVK**, **ReShade** (as `d3d8.dll`/`d3d9.dll`/`dxgi.dll` next to `CT.exe`) | Compatible, may differ between players. |
| **Widescreen Hud Fix**, **16:9 HUD fix**, **Crosshair Fix - Widescreen Aspect Ratio**, **Ultrawide HUD and Crosshair Fix** | Compatible if **every player** installs the same one: they replace `Textures\hudtextures.utx` (and other HUD packages). A player with the fix and a player without it can't connect to each other. |
| **Remaster** (v1.8 beta), **Graphics Enhancer** and other texture/model packs | The same: every player with the same version, or nobody. Not tested with co-op yet. |
| **Order 66**, **The Clone Wars to the Galactic Civil War** and other total conversions | Not compatible (they change the game's code and levels). |

The log shows which wrappers the game really uses (`ModCoop: System: loaded ...d3d8.dll`) and which files lie next to
`CT.exe` (`ModCoop: System: file ...`).

**SWRC Fix** (the community patch, e.g. `SWRCFix2.15.zip`) is already part of the co-op archive: `CT.exe`, `Mod.dll` and `Mod.u`
are built from the same source code, including all changes of 2.15 (the NVIDIA bump map fix) and later ones. Don't install SWRC
Fix over the co-op files: it replaces `CT.exe`, `Mod.u` and `System.ini` with older versions and the host drops players whose
files differ. If you installed SWRC Fix before, just extract the co-op archive over it.

## Helping with tests

Everything that happens in a co-op game is written to `GameData\System\CT.log` (the file is replaced on the next start of the
game, so copy it right after playing). Please send with a report:

- **the `CT.log` of the host and of every client** that was in the game (clients give theirs to the host or attach it to the
  report themselves);
- the level and roughly the place, what you expected and what happened; a screenshot helps a lot (for things that look wrong:
  from the host and from the client at the same place).

The first lines of the log contain what's needed to tell problems of the computer from problems of the mod: the mod's version
(`ModCoop version 0.6`), Windows, processor, memory, graphics card, the resolution of the desktop, the game's exe and the
wrappers next to it (`ModCoop: System: ...`). There is no personal data in it besides the names of the computer and of the
Windows user, which the engine itself writes (`Init: Computer`, `Init: User`); remove them if you like.

## Common problems

| Problem | Solution |
|---|---|
| The client can't connect: `NO ANSWER FROM THE HOST` or an empty checkered room | The host doesn't answer. Check in this order: **1)** the host has started the server (their `CT.log` contains the line `TcpNetDriver on port 7777`); **2)** the firewall was allowed on the host PC at the first start (if you answered "No", delete `GameData\Save\ModCoopFirewall.done` and start the game again); **3)** you connect to the host's IP address **in ZeroTier** (shown in the host's ZeroTier client under "Managed IPs"), not to their home IP address; **4)** both PCs are in the same ZeroTier network and marked `Auth` on my.zerotier.com; **5)** zapret, antivirus software or another VPN — turn them off for a moment and try again. The checkered room is a placeholder map the game shows while it waits for the connection; your textures are fine. |
| The host's log shows `Login request`/`Login from ...`, but the client is dropped right away (the client's log shows `Welcomed by server`, then `Close`) | **You have different versions of the mod.** Every build of the mod is unique, and the engine silently drops the connection if the files don't match. Both players must extract **the same archive** (the version is shown in the menu title, e.g. `CO-OP CAMPAIGN: JOIN (MOD 0.6)`, and at the start of the log: `ModCoop version 0.6`). The host writes `ModCoop version mismatch` with both versions to its log. Versions before 0.4 were called 1.x (release 0.3 shows `MOD 1.3` in the menu). |
| zapret (zapret-discord-youtube) | By itself it doesn't affect ZeroTier addresses `10.x.x.x`, `172.16–31.x.x` or the local network: they are in its `ipset-exclude.txt`. But with **Game Filter** enabled it intercepts all UDP ports 1024–65535, so for Radmin (`26.x.x.x`), Hamachi (`25.x.x.x`) or if you changed the lists, turn Game Filter off (service.bat → option 4) or add the host's address to `lists\ipset-exclude-user.txt`. |
| Connected, but dropped right away with "SERVER CONTENT ... IS NOT PRESENT" | The client has a different version of the mod or no mod at all. Install the same archive as the host. |
| "YOUR CD KEY IS INVALID OR IN USE" | Since 0.57 the host doesn't check the CD keys of clients. If you see this message, the host has an old version of the mod. |
| The CO-OP menu entries don't open | The game wasn't started with `CT.exe`, or `EnableCustomMenu` is turned off in the `[Mod.SWRCFix]` section of `System.ini`. Start the game with the "Star Wars Republic Commando Co-op" shortcut or `GameData\System\CT.exe`. |
| Nothing starts at all (neither `CT.exe` nor the normal `SWRepublicCommando.exe`), especially if the game was copied from another PC | **1)** The `GameData\Save` folder was copied with someone else's settings (resolution, sound, graphics card, `Mod.ModRenderDevice` renderer). Run `GameData\System\RestoreDefaultSystemSettings.bat`: it renames `Save\System.ini` to `BackupSystem.ini` and the game creates new settings. If that doesn't help, rename `Save\User.ini` in the same way. **2)** An old archive of the mod (1.0/1.1) is installed: its files required "Visual C++ 2015–2022 x86". Since 1.2 it isn't needed — extract a current archive. **3)** Both copies of the game must be the same version: don't mix files of two different releases in one folder. |
| The game crashes when `CT.exe` starts | Make sure you extracted **all** files of the archive and replaced the old ones (especially `Mod.u` and `Mod.dll` — they must come from this archive). |
| The host left the game | Clients try to reconnect 12 times (about 4 minutes), then show "THE HOST IS NOT AVAILABLE" — press `BACK`. If the host starts the server again in the meantime, the clients connect by themselves. |
| Stuck or fell through the floor | Console (`~`) → `CoopTeleportToHost`. |
| Where are the logs? | `GameData\System\CT.log`. It is overwritten every time the game starts: after a problem, save a copy before you start the game again. |
| Game version | You need version 1.0 with the update (GOG, Steam or the disc version with the patch). All players need the same version of the game. |

## Uninstalling

Delete `ModCoop.u` and `ModCoop.dll` from `GameData\System`, `ModCoop.ini`, `ModCoopShortcut.done` and `ModCoopFirewall.done`
from `GameData\Save`, and the shortcut on the desktop. The firewall rule "SWRC Coop (CT.exe)" can be removed under
"Windows Defender Firewall → Advanced settings". The other files (`CT.exe`, `Mod.*`) are fixes of the SWRC-Modding/CT
community and can stay.
