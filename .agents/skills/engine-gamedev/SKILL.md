---
name: engine-gamedev
description: >
  Build, inspect, debug, and test 3D/sprite/voxel games on stbange/engine using
  external Lua 5.1 scripts, JSON scenes, "Bigger on the Inside" pocket portals,
  deterministic procedural generation, Spatial Doctor (--doctor), and headless playtests.
license: MIT
---

# Engine Game Development Skill (`stbange/engine`)

Use this skill whenever creating, editing, or debugging a game powered by `stbange/engine`.

## 1. Coordinate System & Units (Read First!)
- **Handedness & Axes**: Right-handed 3D space: **`+X` Right, `+Y` Up, `-Z` Forward**.
- **Units**: `1.0` world unit = **`1.0` meter** (`g = -9.81` on `Y`, or radial toward planet center on 3D planets). Angles in C math are radians; JSON scene Euler angles (`rot_deg`) are degrees `[pitch_x, yaw_y, roll_z]`.
- **Lua Runtime**: Strict **Lua 5.1 + `bit.*`** subset (`LuaJIT 2.1` on Desktop, `PUC-Rio Lua 5.1.5 + LuaBitOp` on Web). Always use `bit.band`, `bit.bor`, `bit.lshift`.

## 2. Unbaked External Folder Contract
Never recompile C to build a standard game. Every game lives in its own external directory (e.g. `games/<slug>/`):
- `game.json` — metadata, `engine_version`, `pipeline` (`"forward"` or `"deferred"`), `retro` flags, `touch_preset`, `xr_mode` (`"diorama"`, `"cockpit"`, `"first_person"`, `"6dof"`).
- `scripts/main.lua` — implements `init()`, `update(dt)`, `draw()`, and optional `on_reload(state)`.
- `scenes/*.json` — plain-text entity/component definitions (`"pocket"`, `"portal"`, `"procgen"` supported natively).
- `assets/` — game-specific overrides; shared assets live in `assets/shared/` (check `assets/shared/catalog.json` for exact `[w, h, d]` metric sizes, pivots, forward axes, and clip names).
- `locales/*.json` — UTF-8 localization tables (`en.json`, `de.json`).
- `tests/playtest.lua` — deterministic headless playtest.

## 3. "Bigger on the Inside" Pocket Spaces (`eng.space.*` & `eng.portal.*`)
- **Never** fake oversized interiors by placing rooms at `[10000, -5000, 0]`. Instead, assign interior entities to a named **pocket space** (`pocket = "cabin_inside"`) centered cleanly around local `(0, 0, 0)`.
- Use **one-call helpers**:
  - `eng.space.create_pocket_building({ exterior_pos=..., exterior_size={3,3,3}, interior_size={24,10,30}, door_size={1.2,2.2}, pocket="hut_in" })`
  - `eng.space.attach_vehicle_interior(vehicle_ent, { interior_size=..., door_local_pos=..., pocket="ship_deck" })`
  - `eng.space.cut_wall_with_door(...)` when building custom doorways so solid wall colliders never block portal apertures!
- Raycasts, 3D audio, rigid bodies, player movement, Stereo WebXR views, and NavMesh A* automatically traverse linked portals.

## 4. Deterministic Procedural Generation (`eng.procgen.*`)
Always pass explicit integer seeds derived from run/level seeds (never use `math.random` or `os.time` directly in gameplay logic):
- **Noise**: `eng.procgen.noise2d/3d`, `fbm3d`, `ridged3d`, `voronoi2d`.
- **Textures**: `eng.procgen.texture(recipe, seed, size)` (`"stone_brick"`, `"wood_grain"`, `"metal_rivets"`, `"grass"`, `"lava_cracks"`, `"fur_scales"`, etc.).
- **Dungeons & Caves**: `eng.procgen.dungeon({ seed=..., rooms=12, locks=2 })`, `eng.procgen.cave3d(...)`, `eng.procgen.wfc(...)` (connectivity and `key_depth < lock_depth` guaranteed).
- **3D Planets**: `eng.procgen.planet({ seed=..., radius=50.0, sea_level=0.0 })` + radial gravity helper.
- **Animals & People**: `eng.procgen.animal({ seed=..., archetype="quadruped" })` (auto-rigged with procedural IK gait!) and `eng.procgen.person({ seed=..., role="villager" })`.
- **Flora & Scatter**: `eng.procgen.tree(...)` and `eng.procgen.scatter_poisson(...)`.

## 5. Closed-Loop Agent Workflow
1. **Scaffold**: `./build/engine --new games/<slug> --template <fps|voxel|pocket_house|procgen_roguelike|planet_explorer|xr>`
2. **Spatial & Multi-Seed Lint**: `./build/engine --headless --doctor --fuzz-seeds 10 --game games/<slug>`
3. **Visual Check**: `./build/engine --headless --game games/<slug> --capture-sheet /tmp/sheet.png --frames 30`
4. **Automated Playtest**: `./build/engine --headless --game games/<slug> --test tests/playtest.lua --seed 42 --max-frames 600`
