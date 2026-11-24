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
- `game.json` — metadata (`"description"` powers the built-in `H` help overlay), `engine_version`, `pipeline` (`"forward"` or `"deferred"`), `retro` flags, `touch_preset`, `xr_mode` (`"diorama"`, `"cockpit"`, `"first_person"`, `"6dof"`).
- `scripts/main.lua` — implements `init()`, `update(dt)`, `draw()`, and optional `on_reload(state)`.
- `scenes/*.json` — plain-text entity/component definitions (`"pocket"`, `"portal"`, `"procgen"` supported natively).
- `assets/` — game-specific overrides; shared assets live in `assets/shared/` (check `assets/shared/catalog.json` for exact `[w, h, d]` metric sizes, pivots, forward axes, and clip names).
- `locales/*.json` — UTF-8 localization tables (`en.json`, `de.json`; optional `"controls"` key overrides the auto-detected help-bar control hints).
- `tests/playtest.lua` — deterministic headless playtest.

## 2b. Camera, Pointer Lock & Movement
- **First-person, free-roam & walkable interiors**: Never aim a moving player with `eng.camera.look_at(px, py, pz, FIXED_X, FIXED_Y, FIXED_Z)` (it makes movement orbit that fixed point). Call `eng.input.set_mouse_lock(true)` in `init()`, update with `yaw, pitch, dx, dz = eng.camera.fps_steer(yaw, pitch, speed, dt)` for mouse look + camera-relative WASD forward/back/left-strafe/right-strafe, and apply `eng.camera.set(px, py, pz, pitch, yaw, 0, pocket)`.
- **Aim / turret / flight views**: Use `eng.input.set_mouse_lock(true)` + `mdx, mdy = eng.input.mouse_delta()` (on Web, canvas click locks and `ESC` unlocks automatically; mobile right-half touch drag feeds `mouse_delta`).
- **Top-down / third-person follow cameras**: Translate both camera position and `look_at` target with the player/vehicle so the view never pivots around world origin.

## 3. "Bigger on the Inside" Pocket Spaces (`eng.space.*` & `eng.portal.*`)
- **Never** fake oversized interiors by placing rooms at `[10000, -5000, 0]`. Instead, assign interior entities to a named **pocket space** (`pocket = "cabin_inside"`) centered cleanly around local `(0, 0, 0)`.
- Use **one-call helpers**:
  - `eng.space.create_pocket_building(eng, { exterior_pos=..., exterior_size={3,3,3}, interior_size={24,10,30}, door_size={1.2,2.2}, pocket="hut_in" })`
  - `eng.space.attach_vehicle_interior(eng, vehicle_ent, { interior_size=..., door_local_pos=..., pocket="ship_deck" })`
  - `eng.space.create_steerable_vehicle(eng, vehicle_ent, { pocket="mech_bridge", interior_size={16,5.5,18}, windshield_local_pos=..., side_windows=true, stations={...}, inertial_sway=0.2, step_bob_amp=0.14 })` for multi-crew steerable vehicles with live stencil cockpit windows, persistent cruise steering, Galilean ramp exits, and moving-ramp scoop boarding!
  - `eng.space.cut_wall_with_door(...)` when building custom doorways so solid wall colliders never block portal apertures!
- Raycasts, 3D audio, rigid bodies, Galilean relative velocity, player movement, Stereo WebXR views, and NavMesh A* automatically traverse linked portals.

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
