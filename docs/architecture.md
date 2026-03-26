# Project Architecture

## Current baseline (stable)

The project currently has two production-ready domains:

1. `rewards` automation
2. `tracker` (gems/traits/gold/level to sheet API)

These two systems are considered stable and must keep working while new
automation is introduced.

## Current implementation status

Implemented and integrated:

1. Lobby vs Match detection (primary by `PlaceId`, fallback by `workspace.Map`)
2. Tutorial gate at startup (upvalue-based status + skip remote)
3. Rewards execution in lobby only
4. Unit equip step in lobby (best unit by level, target slot)
5. Settings sync step in lobby:
   - target map fully implemented
   - random processing order
   - random short delays per action
   - runs once per script execution
6. Tracker + HUD active

## Non-breaking rule (mandatory)

All next steps must preserve compatibility with the current behavior:

1. Do not break `RewardSystem.run()`.
2. Do not break `TrackerSystem.sendNow()` and `TrackerSystem.start()`.
3. Add new modules above existing systems (orchestrator layer), not by replacing
   working code in a single migration.
4. Introduce new features behind config flags whenever possible.

## Current runtime flow

1. `RewardSystem.run()`
2. `Tracker.sendNow()`
3. `Tracker.start()`

## Target direction: "Kaitun" full automation

The target is an orchestrated flow that handles:

1. Lobby vs Match state detection
2. Tutorial skip (pre-skip / post-skip scenarios)
3. Lobby preparation pipeline
4. Match runtime automation
5. Recovery strategy on failures/timeouts
6. Always-on HUD status panel

## Target module layout (planned)

This is the planned structure to be implemented incrementally:

```text
src/
  app.lua
  core/
    config.lua
    logger.lua
    orchestrator.lua
    game_state_detector.lua
    state_context.lua
    status_bus.lua
  systems/
    reward/                     (existing, keep)
    tracker/                    (existing, keep)
    hud/
      hud_system.lua
    tutorial/
      tutorial_system.lua
    lobby/
      lobby_pipeline.lua
    match/
      match_pipeline.lua
    recovery/
      recovery_system.lua
  integrations/
    sheets_client.lua
  utils/
    numbers.lua
```

## Orchestrator state model (planned)

High-level finite state machine:

1. `BOOT`
2. `STATE_DETECT`
3. `TUTORIAL`
4. `LOBBY_PIPELINE`
5. `MATCH_PIPELINE`
6. `RECOVERY`

Transition rules:

1. If tutorial is visible in any context, go to `TUTORIAL`.
2. If in lobby and no tutorial, run lobby pipeline.
3. If in match and no tutorial, run match pipeline.
4. Any timeout/error routes to recovery, then returns to state detect.

## Lobby pipeline

Execution order:

1. Rewards claim
2. Equip desired unit
3. Apply settings (fully implemented, lobby-only, one-time per execution)
4. Move to matchmaking area
5. Join match

## Match pipeline (planned)

Execution order:

1. Verify AutoPlay state
2. Enable AutoPlay if needed
3. Enable/maintain anti-AFK

## HUD requirements (planned)

Single dark overlay panel:

1. Responsive layout (anchors/scales, no hard-locked fixed viewport assumptions)
2. Toggle key: `B`
3. Display:
   - Gems
   - Level
   - Traits
   - Current status step
4. Must coexist with console logs (HUD is visual guide, logs remain source for debug)

## Contracts for new modules (planned)

Each new module should follow a predictable contract:

1. `detect()` for read-only detection when needed
2. `run(context)` for actions
3. Return object: `{ ok = boolean, nextState = string?, reason = string? }`
4. Internal timeout and retry policy

This keeps orchestrator integration deterministic.

## Reliability strategy

To minimize break risk on game updates:

1. Use layered detection:
   - Primary: reliable signals (server result/state change)
   - Secondary: UI-specific checks
   - Fallback: generic interaction with bounded retries
2. Never block forever on UI.
3. Add per-state timeouts and circuit-breaker behavior.
4. Keep logs explicit about why state transitions happen.

## Incremental implementation roadmap

Implementation order (safe evolution):

1. Add `orchestrator` with passive mode (detection + logs only).
2. Add HUD system and status bus.
3. Add tutorial system.
4. Add lobby pipeline using existing `RewardSystem` (no rewrite).
5. Add match pipeline (autoplay + anti-afk).
6. Add recovery system and robust retry/timeout handling.

Each step should be validated before moving to the next one.

## Execution in executor

1. Configure `baseUrl` in `main.lua` to point to hosted `src/`.
2. Execute `main.lua`.
3. Modules are loaded via HTTP with in-memory cache.

Example runtime config for secrets (do not commit real values):

```lua
getgenv().SCRIPT_AVG_CONFIG = {
    tracker = {
        webhookUrl = "PRIVATE_URL",
        secretToken = "PRIVATE_TOKEN",
        intervalMinutes = 5,
        retry = {
            maxRetries = 3,
            retryDelaySeconds = 2,
        },
    },
}
```

Example base URL:

```text
https://raw.githubusercontent.com/<user>/<repo>/main/src/
```
