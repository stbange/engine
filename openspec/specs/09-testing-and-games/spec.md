# Unit Coverage, Automated Game Tests, 100 Example Games & GitHub Pages Specification

## Purpose
Defines the verification, game-showcase, and deployment requirements: >=95.0% C and Lua unit test coverage, deterministic automated gameplay + fun telemetry testing, 100 unbaked example games, and `main`-branch GitHub Pages deployment.

## Requirements

### Requirement: Minimum 95% First-Party C and Lua Line Coverage
The test suite SHALL enforce `>= 95.0%` line coverage across all first-party C source files (`src/*.c`) via `gcov`/`lcov` AND `>= 95.0%` line coverage across all engine Lua runtime modules (`lua/eng/*.lua`) via `LUA_MASKLINE` `lcov` output, excluding `third_party/`.

#### Scenario: Coverage gate enforcement
- **WHEN** `python3 tests/check_coverage.py` runs against a coverage build
- **THEN** it exits non-zero if either `src/*.c` aggregate line coverage or `lua/eng/*.lua` aggregate line coverage is below `95.0%`

### Requirement: 100 Non-Trivial Unbaked Example Games with Automated Playtests
The repository SHALL include 100 distinct, playable example games (`001`–`010` multi-level flagships + `011`–`100` focused genre/mechanic games) using external Lua scripts and unbaked assets, each verified by an automated deterministic `--headless --test tests/playtest.lua` suite.

#### Scenario: Automated headless playtest verification
- **WHEN** CI runs `./engine --headless --game games/<id> --test tests/playtest.lua --seed 42` for all 100 games
- **THEN** every game initializes cleanly, processes synthetic player/bot inputs, verifies gameplay state transitions, and exits `0` with zero unhandled Lua or OpenGL errors

### Requirement: Single Shared WebAssembly Runtime and Overview Hub on GitHub Pages via main
The build pipeline SHALL package a searchable/filterable overview page (`index.html`) linking to all 100 games powered by one shared `engine.wasm` + `engine.js` runtime (loading external `assets/shared/` and `games/<id>/` over HTTP) and deploy via GitHub Actions directly from the `main` branch without creating a `gh-pages` branch.

#### Scenario: Launching any of the 100 games on GitHub Pages
- **WHEN** a desktop, mobile, or WebXR browser opens `play.html?game=001_catacomb_blitz` from the GitHub Pages overview hub
- **THEN** the shared `engine.wasm` mounts `assets/shared/` and `games/001_catacomb_blitz/` from its manifest, activates touch controls automatically on mobile devices, and exposes `"Enter VR"` on WebXR-capable browsers
