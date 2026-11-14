# ModCoop level triage

The project part of skill `bug-triage`, for "the level stalled, nothing happens": a door doesn't open, a lift doesn't move, a marker doesn't count, the level doesn't end. The original level script waits for an event that in co-op arrives at the wrong place, from the wrong actor, or not at all.

Don't read the whole level. Go from the log to the broken chain.

## Material

- `CoopHost.log`, the main source: level scripts run on the server.
- The log of each client: the cause is often there.
- Level, room or marker, what the player did, and which event didn't happen.

## Typical causes

Check in this order. They explained 6 of 7 past cases. GEO_03D stayed open.

1. **Dropped script on a squad member.** A client took the member, so "reached the point" or "played the animation" is never sent. Look for `takes over` before the stall.
2. **Client pawns outside the squad (`Squad=None`).** The script waits for the arrival or state of a squad member. Compare with the same level with the host alone.
3. **Server-only actors and effects.** The marker or effect the script toggles doesn't exist on the client, so the event goes nowhere.

## Event chain

1. In the host log, take the non-`Status` lines around the stall. Search for `heard`, `counter`, `script state of`, `takes over`.
2. Find which script waits for which event. The names usually tell: `AcessHatch`, `SliceRoomCleared`, `SpawnControlRoom`.
3. Find who triggers the event. The `mapscan.py` dump prints Dispatcher events and ActivationInfo/TransitionInfo structures as `arr(N)`, so use the raw exports.
4. Decide why co-op breaks it: a client sends the event (it doesn't exist in the original), the actor exists only on the server, a client took the source member, or the players were faster than the script and the event left before the subscription.

## Tools

In `Tools/MapScan`, run with `python -I`. See `TESTING.md`.

- `disp.py <map.ctm> <Event>`: who references an event. Checked findings: `Dispatcher35 -> AcessHatch` (YYY_01B), `BreachDoorGeo0 -> SpawnControlRoom` (GEO_03D), `HackTerminalGeo5 -> ControlRoomDroidsDead`.
- `seq.py <dump.txt> <tag regex>`: what a script does with a marker or actor.

## Before syncing an engine variable

1. Search all `.uc` sources for writes to the variable.
2. No writes: native code sets it, and even the host may not hold the expected value. Example: `TotalTimeToRevive` is set by native target selection while aiming. Print the value with a test log first.
3. Writes exist: syncing is possible. Verify with a scene test and record that in DEVLOG.

## Result

- Cause found: DEVLOG row and a scene test as a regression.
- Chain restored, cause not found: write the stuck link in `Feedback/`, don't guess.
- A fact about the engine: `ARCHITECTURE.md`, don't patch the symptom.

This procedure covers level logic. Visual reports start with frames, then code.
