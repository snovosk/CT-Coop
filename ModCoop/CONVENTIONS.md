# ModCoop conventions

Source of the rules: skill `code-style` with profile `game-mod`, the code that already exists, and lessons from past sessions. If two rules disagree, change the rule here and tell the user.

## Language

**English everywhere:** identifiers, comments, log markers, DEVLOG, these documents. Only text players see follows the localization: `README.ru.md` is Russian, in-game strings are English because the game's fonts have no Cyrillic.
Decided by the user on 2026-11-08.

## Where code goes

| Code | Place |
|---|---|
| New mechanic or scene | Its own `Classes/Coop<Mechanic>.uc`, with `Setup`/`Check` called from `CoopGame` |
| Server sync of existing state | `CoopGame`, next to related `Sync*` |
| Client reaction, RPC | `CoopPlayer` |
| Hook of a game function | `CoopExtension` installs it. Three lines at most, then call the handler |
| Native engine access or a crash fix | `CoopNative.uc` + `Src/ModCoop.cpp` |
| Steam transport | `CoopTunnel/` |
| Developer scripts | `Tools/`. `package.ps1` doesn't ship them |
| Documents for players | `Dist/` |

A file over about 400 lines, or one with two responsibilities, is a reason to start a new file. Before adding a var or state to `CoopGame` or `CoopPlayer`, grep for the name: a duplicate stops the compile.

## File header

Every new file opens with this block. `CoopLobby.uc` is the model:

```
/*
 * CoopThing
 * Purpose: what it does and why.
 * Entry points: who calls what.
 * Logging: the markers.
 * State: the fields that matter.
 * Known limitations: what isn't handled.
 */
```

An empty block is written as `none yet`, never left out. Named constants, no magic numbers. Comments say why, not what.

## Hacks

```
// HACK: what was done -- why it can't be done otherwise -- how to check it still works
// TEMPORARY: what and why -- can be removed when <condition>
```

Older code explains its workarounds in plain comments. Don't add tags to it unless the code is being changed anyway.

## Network

- RPC names: `ClientCoop*` (server to client), `ServerCoop*` (client to server), listed in the `replication` block of `CoopPlayer`.
- New network methods say their side (server, client, both) and who owns the state. Decide what happens on a desync when writing them, not later.
- One-time state (display, links, settings) is **reliable**, with a resend request when the client doesn't have the actor yet. Only values resent all the time (progress, aim) may be unreliable.
- For anything both sides must agree on, log the value on both sides and compare.
- A change to replicated functions breaks compatibility: raise the version.

## Behaviour rules

- Every return from an outside view goes through `CoopPlayer.BeginBlendToEyes`/`EndBlendToEyes`.
- Every removal of an AI from a pawn goes through `CoopGame.RetireAI`.
- Before a new weapon watchdog, list the states where the condition is normal. After changing a weapon, check the result and restore the old one if the change failed.

## Logging

- Markers: `ModCoop:` (client and general), `CoopGame:` (server), `CoopTest:` (automated tests), `CoopDebug:`. Testers' instructions name existing markers, so don't rename them.
- A line says the fact and enough context to diagnose without running the game: who, where, with what.
- Never log personal data beyond what the engine writes itself.

## DEVLOG

Each change is a table row under the section of its version, in this order:

`| Level / module | Was | Now | Reason | Verified |`

`Verified` keeps the levels apart: code review, automated test, manual play (`TESTING.md`). An unfinished check says `pending`. Anything done without asking and against these rules gets `deviation:` with the reason.

## Definition of done

A task is done only when the build passes, the automated tests that apply are green, the DEVLOG row is written, and it can be explained how to check it by hand. Until a person has played it, the row says `pending manual verification`, not done.

A deviation from these rules: stop and ask, unless told to work alone. Then record it with `deviation:`.

## Learning from work

After each significant step, if something took longer than expected, a decision was corrected, a sequence repeated, or a rule was broken, write `Feedback/YYYY-MM-DD_<topic>.md` in the project root:

```
# <topic>
- Date, task:
- Type: stumble | correction | repetition | deviation
- What happened: 2-3 sentences of facts
- Missing: fact, procedure or prohibition
- Replacement rule:
- Where it should live: project-knowledge | skill | code template
- Confirmed:
- Repetitions: N
```

One entry per stumble, a repeat raises its counter. Files the user wrote there are the user's: don't change or comment on them. Don't create skills along the way. Every 5 to 10 tasks, or on "скомпилируй feedback", group the entries and propose skills only where `Repetitions >= 3` or a correction already states a ready rule.

## How to work

- Look at a bug vertically through the code: the user's rule, because the same errors come back again and again.
- Say "cause not found" until a test or a log shows it. A fix for a symptom is called a safety net.
- Bug reports: follow the log to the script chain, don't read the whole level.
- After fixing a class of bug that can be found in map data, scan every campaign map for it.
- For a native crash, resolve every frame of the stack before picking a fix.
- A visual report needs a screenshot of the right window before any fix.
- A test takes its expected value from the other side of the network, not from the code under test.
- For behaviour players see, offer the options before building one.
- For anything in the network path, compare with a run without the change and report the measured total time.
- No builds or tests while the user is testing: check that `CT.exe` isn't running. Back up the logs before a test run. After tests, clear `SquadAssignmentList` (`Tools/RunTest.ps1` does both).
- After a tool call is rejected, check the state: part of it may have run.

## Privacy

The repository and release archives are public. Never commit or ship:
logs, `CoopLogs-*.zip`, `Save/`, `.pdb`, real names, computer names, Steam IDs, IP addresses of players, absolute paths under a user profile, keys or tokens, the game's own binaries, or decompiled code.

- Commits use the GitHub noreply address.
- Never `git push --all` or `--mirror`: local branch `backup-before-fork` holds commits with a personal e-mail and was never pushed.
- When a script promises to remove personal data, open its output and search for the real values.

## Commits and releases

- Commits, pushes, archives and releases only when the user says so.
- Author: the GitHub noreply identity configured in the repository. Push with `git push origin main:master`, GitHub calls use `--repo snovosk/CT-Coop`.
- Before a commit: line endings as at HEAD, `bDebugLog` default false.
- Release notes are English only and recommend playing co-op without other mods. Say how each item was verified.

## Versions

`major.minor`, a new number whenever builds can't play together. The version lives in `CoopConfig.MOD_VERSION` (menu title, log, join check), and in the archive name, release notes and DEVLOG. `package.ps1` reads it from `CoopConfig`.

Milestones, approved by the user on 2026-11-08:

- 0.7x: Geonosis played by hand in co-op (reached)
- 0.8: Raxus Prime played by hand
- 0.9: Kashyyyk played by hand, campaign closed
- 1.0: menus and networking finished, full manual playthrough, network format frozen
