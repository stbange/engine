# Engine (`stbange/engine`)

**Engine** (`eng_` in C11, `eng.*` in Lua 5.1) is a lightweight, extendable, retro-optimized 3D game engine written in **100% pure C11**, **SDL3**, **OpenGL 3.3 Core / WebGL2 (GLES 3.0)**, and **LuaJIT 2.1 / Lua 5.1**, built specifically for frictionless use by AI coding agents and human developers via `git clone`.

Licensed under the [MIT License](LICENSE) ([Third-Party Notices](THIRD_PARTY_NOTICES.md)).

---

## Key Capabilities

- **Agent-First `git clone` Workflow**:
  - **Unbaked Data-Driven Runner**: `./build/engine --game games/001_catacomb_blitz` runs external Lua scripts, JSON scenes, shaders, and assets directly from folders beside the binary—zero C recompilation needed.
  - **CMake Library Mode**: `add_subdirectory(engine)` links `engine::core` (`#include <engine/engine.h>`) into any C11 project.
  - **LLM Spatial Doctor, Fuzz Auditor & Scaffolder**: `--doctor` (and `--fuzz-seeds N`) audits camera frustums, lighting, metric scale (`1.0 = 1m`), portal doorway clearance, and collider overlaps; `--capture-sheet out.png` renders a 2×2 diagnostic contact sheet; `--new` scaffolds games; `lua/eng_api.lua` & `schemas/*.schema.json` provide Levenshtein `"did you mean?"` diagnostics and `NaN` traps.
- **"Bigger on the Inside" Pocket Spaces, Portals & Steerable Walkable Vehicles (`eng_portal`, `eng.space.*`)**:
  - Isolated `pocket_id` spatial universes prevent oversized interiors (houses, tents, chests, starships, submarines, giant bipedal mechs) from poking through compact exteriors.
  - Recursive hardware stencil + Lengyel oblique near-plane clipping + inverted doorway throat cap (zero 1-frame near-plane blink, including Stereo WebXR), Galilean relative velocity transfer & moving-portal threshold sweep, `eng.space.create_steerable_vehicle` multi-window/multi-station vehicle builder, plus cross-portal physics, ghost proxy colliders, raycasts, 3D spatial audio, and NavGrid A* links.
- **Deterministic Random & Procedural Content Generation (`eng_procgen`, `eng.procgen.*`)**:
  - Seeded 2D/3D Value/Perlin/Simplex/Voronoi/fBm/Ridged/Domain-Warp noise, tileable `RGBA8` PBR/retro textures + Sobel normal maps, solvability-guaranteed BSP/cellular/WFC dungeons, seamless 3D cube-sphere planets with Whittaker biomes & radial gravity, DNA-articulated animals with auto-skeleton & phase-shifted IK gaits, modular rigged NPCs (`eng_procgen_person`), 3D L-system flora, and Poisson-disk scatter.
- **Retro 3D Graphics (Meshes, Sprites & Voxels)**:
  - Forward PBR/Retro (default) and G-Buffer Deferred pipelines, dynamic directional/point/spot lights & shadow maps, HDR + Dual-Kawase bloom, procedural skyboxes, GPU instancing, frustum + convex AABB occlusion culling, mesh LODs, PS1 vertex snap, 4×4 Bayer dithering, fog, and CRT scanlines.
  - Greedy-meshed palette voxel chunks (`.vox` + `voxel_ascii` + boolean CSG + 4-level vertex AO + DDA raycasts), 8-directional & billboard sprites, heightmap terrain, particles, and `stb_truetype` UTF-8 SDF text.
- **Cross-Platform Desktop, Mobile Web & Stereo WebXR**:
  - Targets **Windows**, **Linux**, **macOS**, **WebAssembly (Emscripten)** with automatic mobile touch HUD switching, and **Stereo WebXR (`immersive-vr`)** (`diorama`, `cockpit`, `first_person`, `6dof`).
- **Complete Runtime, Tooling & 101 Example Games**:
  - Sparse-set SoA ECS, arena/pool allocators, `SDL_Thread` jobs, pure-C BVH/GJK/voxel physics, glTF skinning + 2-bone/FABRIK IK, SDL3 3D audio (`WAV`, `stb_vorbis` Ogg, ADSR synth), NavGrid A* + Lua Behavior Trees, UDP/WebSocket/Loopback netcode, Nuklear HUD, `~` console + sandboxed Lua REPL, CPU/GPU profiler + 3D debug draw, `F1` scene editor (`F5` Play-in-Editor), modding VFS (`mods/`), `ENGB`/JSON saves, and UTF-8 i18n.
  - Ships **101 playable, automated-tested games** (`games/001_*` – `games/101_*`, including 3-player walkable giant bipedal mech `101_giant_cleaner_mech`) deployed to GitHub Pages from `main` via one shared `engine.wasm`.

---

## Quickstart

### 1. Build (Linux / macOS / Windows)
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

### 2. Run, Audit, Edit, or Mod Any of the 101 Games
```bash
# Play interactively (press H for Help, F1 for Level Editor, F5 for Play-in-Editor, ~ for Lua Console)
./build/engine --game games/101_giant_cleaner_mech

# Play with an active VFS + Lua mod overlay
./build/engine --game games/001_catacomb_blitz --mod mods/example_retro_pack

# Headless Spatial Doctor + multi-seed procedural fuzz audit + 2x2 contact sheet
./build/engine --headless --doctor --fuzz-seeds 5 --game games/101_giant_cleaner_mech
./build/engine --headless --game games/101_giant_cleaner_mech --capture-sheet sheet.png --frames 30

# Run all 101 automated game audits & headless playtests
python3 tests/run_all_games.py ./build/engine --expect-count 101
```

### 3. Run Unit Tests & >= 95% C + Lua Coverage Gate
```bash
cmake -B build-cov -DENG_ENABLE_COVERAGE=ON
cmake --build build-cov -j
xvfb-run -a ctest --test-dir build-cov --output-on-failure
python3 tests/check_coverage.py build-cov
```

### 4. Build Web & WebXR GitHub Pages Hub (`dist/`)
```bash
emcmake cmake -B build-web -DCMAKE_BUILD_TYPE=Release
cmake --build build-web -j
python3 web/build_pages.py --wasm-dir build-web --out-dir dist
```

### 5. Consume via `add_subdirectory` in Your Own Project
```cmake
add_subdirectory(engine)
target_link_libraries(my_custom_host PRIVATE engine::core)
```

---

## Upgrading & Breaking Changes
Downstream projects should check [CHANGELOG.md](CHANGELOG.md), [UPGRADING.md](UPGRADING.md), and [`.agents/skills/engine-upgrade/SKILL.md`](.agents/skills/engine-upgrade/SKILL.md) whenever pulling updates from `main`.
