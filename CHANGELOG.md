# Changelog

All notable changes to **Engine (`stbange/engine`)** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Whenever a release introduces **BREAKING** changes to `include/engine/*.h`, the `eng.*` Lua API, or `schemas/*.schema.json`, see [UPGRADING.md](UPGRADING.md) for automated coding-agent migration instructions.

## [0.2.0] - 2026-11-23

### Added
- **Steerable Walkable Moving Vehicles (`openspec/specs/12-walkable-vehicles/spec.md`, `eng_portal`, `eng_physics`, `eng.space`)**:
  - Moving-portal kinematic tracking (`eng_portal_step_kinematics`, `eng_portal_set_velocity`, `eng.portal.sync_kinematics`) and Galilean relative frame velocity transfer (`eng_portal_transform_velocity`, `eng.portal.transform_vel`, `eng.portal.check_crossing` velocity returns) so exiting a moving/rotating vehicle preserves world momentum and advancing vehicle ramps scoop stationary external entities cleanly.
  - One-call multi-window, multi-station steerable vehicle builder (`eng.space.create_steerable_vehicle`) creating an isolated walkable interior pocket, passable boarding hatch, non-passable panoramic cockpit windshield & side window stencil portals, multi-crew stations, persistent cruise steering, and clamped inertial deck sway (`inertial_sway`, `step_bob_amp`).
  - Default 3-player local split-keyboard action bindings (`p1_*` `WASD+E`, `p2_*` `IJKL+U`, `p3_*` `Arrows+Return`, `switch_crew` `Tab`, `toggle_cam` `C`).
  - **Game `101` (`games/101_giant_cleaner_mech`)**: *Titan Janitor: 3-Crew Cleaning Mech* — three players simultaneously steering, walking, operating Vacuum/Scrubber/Recycler stations, and performing Galilean EVA ramp exits & moving-ramp re-boarding inside a giant 14m bipedal cleaning robot.

### Fixed
- **Emscripten WebAssembly & Chrome Player (`CMakeLists.txt`, `src/eng_platform.c`, `src/eng_cli.c`, `web/shell_play.html`)**:
  - Exported `'callMain'` in `EXPORTED_RUNTIME_METHODS`, raised WASM C stack size from Emscripten's 64 KB default to `2 MB` (`-sSTACK_SIZE=2097152`), enabled WebGL2 `EXT_color_buffer_float` for deferred G-buffers, added full-window high-DPI viewport resize + Nuklear HUD label rendering, and added headless Chrome CI smoke gate (`tests/check_web_bundle.py`).

## [0.1.0] - 2026-11-23

### Added
- **Governance, Ponytail & OpenSpec (`openspec/specs/01..11`)**:
  - Ponytail (`DietrichGebert/ponytail`) & downstream agent skills (`engine-gamedev`, `engine-upgrade`) in `.agents/skills/` and `AGENTS.md`.
  - 11 validated OpenSpec living architecture specifications covering Core ECS/VFS, Platform/Input/WebXR, Retro/Voxel Renderer, Physics/Anim, Audio/AI/Net, Lua/Modding/i18n, UI/Editor/Profiler, LLM Ergonomics/Doctor, Testing/Games, Pocket Portals, and Procedural Generation.
  - Dual-mode CMake build (`engine::core` static library + standalone `engine` runner + Emscripten Web/WebXR target + >=95.0% C & Lua `lcov` coverage gate) with strictly MIT-compatible dependencies.
- **Core C11 Foundation & Platform (`eng_math`, `eng_mem`, `eng_log`, `eng_jobs`, `eng_vfs`, `eng_events`, `eng_serde`, `eng_ecs`, `eng_scene`, `eng_gl`, `eng_platform`, `eng_input`, `eng_xr`)**:
  - Right-handed (`+X` Right, `+Y` Up, `-Z` Forward, `1.0 = 1m`) math, linear arena & generational pool allocators, log deduplication & CVars, `SDL_Thread` job pool, sandboxed priority-overlay VFS with hot-reload watcher, SoA ECS, hierarchy & `pocket_id` scene graph, pure-MIT GL 3.3 / GLES 3.0 loader + software CI mock, SDL3 windowing, rebindable input + mobile touch presets + buffer/coyote helpers, and Stereo WebXR (`immersive-vr`).
- **Retro 3D Renderer, Sprites, Greedy Voxels & "Bigger on the Inside" Portals (`eng_render`, `eng_portal`, `eng_voxel`, `eng_sprite`, `eng_terrain`, `eng_particles`, `eng_text`)**:
  - Selectable Forward PBR/Retro and G-Buffer Deferred pipelines, shadow maps, HDR + Dual-Kawase bloom, procedural skyboxes, frustum + convex AABB occlusion culling, GPU instancing, LODs, PS1 vertex snap, Bayer dithering, fog, and CRT post-processing.
  - Recursive hardware stencil + 2D scissor + inverted near-plane throat cap + Lengyel oblique near-plane portal rendering across isolated `pocket_id` spaces (including moving vehicles and Stereo WebXR).
  - Greedy-meshed palette voxels (`.vox`, ASCII layers, CSG, 4-level AO, DDA raycast), 8-way/billboard sprites, 4-biome terrain, particles, and UTF-8 SDF text.
- **Deterministic Procedural Generation, Physics, Skeletal IK, Audio, AI & Netcode (`eng_procgen`, `eng_physics`, `eng_anim`, `eng_audio`, `eng_ai`, `eng_net`)**:
  - 2D/3D Value/Perlin/Simplex/Voronoi/fBm/Ridged/Domain-Warp noise, tileable PBR/retro textures + Sobel normals, solvability-repaired BSP/cave/WFC dungeons, 3D cube-sphere planets with radial gravity, DNA-articulated animals with auto-skeleton & phase-shifted IK gaits, modular rigged NPCs, 3D L-system flora, and Poisson-disk scatter.
  - Per-pocket BVH + Sphere/Capsule/AABB/Voxel/Terrain/GJK physics with cross-portal teleportation, ghost doorway colliders, and multi-hop cross-portal raycasts; glTF skinning + 2-bone/FABRIK IK; cross-portal 3D SDL3 audio (`WAV`, `Ogg`, ADSR synth); portal-linked NavGrid A* + Behavior Trees; and UDP/WebSocket/Loopback ECS snapshot replication.
- **Lua 5.1 / LuaJIT Runtime, Spatial Doctor, Nuklear Editor & 100 Example Games (`eng_lua`, `eng_doctor`, `eng_ui`, `eng_profiler`, `eng_editor`, `games/001..100`)**:
  - Sandboxed `eng.*` bindings + Lua stdlib (`space.lua`, `procgen.lua`, `async.lua`, `bt.lua`, `ui.lua`, `fun.lua`, `test.lua`), Levenshtein typo suggestions, `NaN` traps, `LUA_MASKCOUNT` watchdog, state-preserving hot reload, auto-generated `lua/eng_api.lua`, `--doctor --fuzz-seeds`, `--capture-sheet`, `--new`, Nuklear anchored HUD, `~` Lua REPL console, CPU/GPU profiler + 3D debug draw, and `F1` editor with `F5` Play-in-Editor.
  - Shared MIT asset library (`assets/shared/catalog.json`), `mods/example_retro_pack/`, `web/shell_play.html` + `web/build_pages.py` single-WASM GitHub Pages hub, and **100 verified playable 3D games** (`001`–`100`).
