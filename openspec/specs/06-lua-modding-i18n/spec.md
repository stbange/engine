# Lua 5.1 / LuaJIT Scripting, Sandboxing, Modding & Localization Specification

## Purpose
Defines the embedded Lua 5.1 scripting layer (`eng_lua`, `lua/eng/*`), C-to-Lua `eng.*` bindings, sandboxing, coroutines, hot reload, mod overlay hooks, and UTF-8 localization (`eng_i18n`).

## Requirements

### Requirement: Unified Lua 5.1 + bit.* Contract Across Desktop and Web
The engine SHALL embed LuaJIT 2.1 on Desktop builds and PUC-Rio Lua 5.1.5 + LuaBitOp (`bit.*`) on Emscripten Web and coverage builds, exposing an identical `eng.*` Lua API across all targets.

#### Scenario: Identical script execution on Desktop and Web
- **WHEN** a game script uses `eng.ecs`, `eng.physics`, coroutines, and `bit.band` / `bit.lshift`
- **THEN** the script executes with identical semantics under Desktop LuaJIT and Web PUC-Rio Lua 5.1.5

### Requirement: Sandboxed Execution and Infinite-Loop Watchdog
The engine SHALL isolate game and mod scripts via `lua_setfenv` (removing raw `io`, `os.execute`, `debug`, and `package.loadlib` access) and SHALL enforce a per-frame `lua_sethook` instruction limit.

#### Scenario: Runaway while-true loop recovery
- **WHEN** a game or mod script enters `while true do end` without yielding
- **THEN** `eng_lua` aborts the frame hook cleanly with a `file:line` error traceback without hanging the engine process

### Requirement: State-Preserving Lua Hot Reload and Coroutine Scheduler
The engine SHALL reload modified `.lua` scripts on disk while preserving entity component tables and `game.state`, and SHALL provide a frame-synchronized coroutine scheduler (`eng.async`).

#### Scenario: Live Lua hot reload
- **WHEN** `scripts/main.lua` is edited while the engine is running
- **THEN** `eng_lua` reloads the updated functions on the next hot-reload poll while keeping existing `game.state` fields intact

### Requirement: Modding Overlay Hooks and UTF-8 Parameterized Localization
The engine SHALL load active `mods/<mod_id>/` overlays above base game folders and SHALL resolve UTF-8 string keys from `locales/<lang>.json` with `{param}` substitution and fallback locale support.

#### Scenario: Mod asset and event hook override
- **WHEN** `--mod example_retro_pack` is passed on startup
- **THEN** files in `mods/example_retro_pack/` override matching game VFS paths and registered sandboxed mod callbacks fire on game events
