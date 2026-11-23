# LLM-Native Ergonomics, Spatial Doctor, Stubs & Scaffolder Specification

## Purpose
Defines the AI-agent productivity capabilities (`eng_doctor`, strict `eng.*` diagnostics, build-generated `lua/eng_api.lua` & `schemas/*.schema.json`, `catalog.json`, context-safe crash snapshots, and `--new` scaffolding).

## Requirements

### Requirement: Spatial Scene Doctor and 2x2 Multimodal Contact Sheet
The engine SHALL provide `--doctor` (`eng.scene.audit()`) to detect empty camera frustums, unlit dark PBR scenes, spawn collider overlaps, and extreme scale mismatches, and `--capture-sheet <path.png>` to render a 2×2 composite diagnostic image.

#### Scenario: Detecting camera facing away from scene
- **WHEN** `--doctor` runs on a scene whose active camera has `0` visible entities in its frustum while entities exist behind it
- **THEN** `--doctor` outputs a structured warning naming the camera orientation and nearest entity direction

### Requirement: Strict Lua Metatables with Levenshtein Suggestions and Auto-Generated Stubs
The engine SHALL reject unknown `eng.*` symbol lookups with Levenshtein `"did you mean?"` suggestions and SHALL auto-generate `lua/eng_api.lua` (LuaLS annotations) and `schemas/*.schema.json` directly from C registration descriptors.

#### Scenario: Typo in Lua API function name
- **WHEN** a Lua script calls `eng.physics.ray_cast(...)`
- **THEN** `eng_lua` raises an immediate error suggesting `eng.physics.raycast` along with its parameter signature

### Requirement: Text-to-3D Procedural Builders, Asset Catalog, Crash Snapshots, and Game Scaffolder
The engine SHALL provide `eng.voxel.from_ascii` and `eng.mesh.compound` procedural builders, maintain `assets/shared/catalog.json` metric/clip metadata, deduplicate repeated logs, dump failing-frame entity JSON snapshots on test assertion failure, and scaffold runnable games via `--new`.

#### Scenario: Scaffolding and auditing a new game in two commands
- **WHEN** an agent runs `./engine --new games/test_demo --template voxel` followed by `./engine --headless --doctor --game games/test_demo`
- **THEN** `--new` creates a complete external game directory that passes `--doctor` and `tests/playtest.lua` out of the box
