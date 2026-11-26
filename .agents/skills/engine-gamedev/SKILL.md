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
- **First-person, free-roam & walkable interiors**: Never aim a moving player with `eng.camera.look_at(px, py, pz, FIXED_X, FIXED_Y, FIXED_Z)` (it makes movement orbit that fixed point). Call `eng.input.set_mouse_lock(true)` in `init()`, update with `yaw, pitch, dx, dz = eng.camera.fps_steer(yaw, pitch, speed, dt)` for mouse look + camera-relative WASD/Arrow forward/back/strafe, resolve walls with `nx, nz = eng.physics.slide_move(pocket, px, py, pz, dx, dz, 0.38)` (attaching `{ shape = "voxel", motion = "static", voxel_id = d.voxel_id }` on procedural dungeons), and apply `eng.camera.set(px, py, pz, pitch, yaw, 0, pocket)`.
- **Aim / turret / flight views**: Use `eng.input.set_mouse_lock(true)` + `mdx, mdy = eng.input.mouse_delta()` (on Web, canvas click locks and `ESC` unlocks automatically; mobile right-half touch drag feeds `mouse_delta`).
- **Top-down / third-person follow cameras**: Translate both camera position and `look_at` target with the player/vehicle so the view never pivots around world origin.
- **Avoid Z-fighting**: Never render a separate floor mesh coplanar (`y = 0`) with a procedural dungeon mesh (use a physics-only collider or offset Y by at least `0.02m`).

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

## 4b. Special Materials, Crystals, Particles, Lights & Fog (`eng.fx.*`, `eng.render.*`, `eng.particles.*`)
- **Metals, Crystals & Emissive Glow**: Analytic sky-gradient IBL makes high-metallic low-roughness surfaces gleam automatically (`gold`, `chrome`, `copper`, `obsidian`), while `color[4] < 0.99` routes meshes through the back-to-front translucent Fresnel pass and `emissive = {r, g, b}` (or scalar multiplier) drives HDR bloom in both Forward and Deferred pipelines. Use `eng.fx.material("gold"|"chrome"|"copper"|"obsidian"|"crystal"|"ruby"|"emerald"|"ice"|"glass"|"lava", overrides?)` directly with `eng.scene.set_mesh`.
- **Fire, Smoke, Sparks & Dust**: Omit `tex` on `eng.particles.create` to use the built-in soft radial puff texture, and pass `additive = true`, `color_start/end`, `size_start/end`, `gravity`, `drag`, or use 1-call `eng.fx.spawn(eng, "fire"|"smoke"|"sparks"|"dust", x, y, z, pocket?, opts?)`. Reposition live emitters with `eng.particles.set_pos(id, x, y, z, pocket?)` and `eng.particles.set_rate(id, rate)`.
- **Movable Lights & Height Fog**: Capture the 1-based handle returned by `local lid = eng.render.add_light({...})` and animate it each frame with `eng.render.set_light(lid, { pos=..., color=..., range=... })`. Tune colored distance + ground-mist fog and bloom via `eng.render.set_retro({ fog_density=0.03, fog_color={r,g,b}, fog_height=2.8, bloom=0.5 })`.
- **Skyboxes, Cubemaps, Per-Pocket Skies & Retro Parallax**: Use 1-call presets `eng.fx.sky(eng, "alpine_day"|"sunset_mountains"|"synthwave_city"|"starry_night"|"overcast_forest"|"mars_dunes", { pocket=? })`, or customize via `eng.render.set_sky_fx({ pocket?, zenith, horizon, ground, tex?, cubemap?, sun_dir, sun_color, sun_size, sun_glow, sun_banded, clouds, cloud_speed, cloud_scale, stars, pixel_snap, parallax={...} })`, `eng.render.set_parallax(layers, pocket?)`, `eng.render.clear_pocket_sky(pocket)`, and `eng.asset.load_cubemap({px,nx,py,ny,pz,nz})`. Parallax layers support custom alpha textures (`tex`) or zero-asset silhouettes (`mountains`, `hills`, `city`, `trees`, `dunes`, `clouds`) driven by yaw, XZ movement, and time.

## 4c. Split-Screen, Per-Player Gamepads & Cross-Platform Networking
- **1–4 Player Split-Screen**: Call `eng.camera.set_split(2|3|4, "vertical"|"horizontal"|"top2_bot1"|"grid4")` (automatically enables 4-zone non-overlapping split keyboard: P1 `WASD`, P2 `Arrows`, P3 `IJKL`, P4 `TFGH`/`Numpad`). Aim each camera independently with `eng.camera.set_view(i, x, y, z, pitch, yaw, roll, pocket)` or `eng.camera.look_at_view(i, ...)` (works across different pockets and in both Forward & Deferred pipelines, with multi-listener 3D audio). Anchor per-player HUD inside each quadrant with `eng.ui.viewport_anchor(eng.camera.get_view_rect(i), "top_left", ox, oy, w, h)`.
- **Per-Player Gamepads & Split Input**: Use `eng.input.player_move(i)`, `eng.input.player_look(i)`, `eng.input.player_down(i, action)`, `eng.input.player_pressed(i, action)`, `eng.camera.fps_steer_player(i, yaw, pitch, speed, dt)`, `eng.input.gamepad_count()`, `eng.input.set_player_device(i, "auto"|"keyboard"|"gamepad", pad_slot?)`, and `eng.input.inject_player(i, action, down)` for deterministic playtests.
- **Cross-Platform Online Multiplayer**: Use `eng.mp.create_server` / `eng.mp.create_client` (`lua/eng/mp.lua`) with `--server --port 7777` and `--connect ws://...` (Desktop) or `?server=wss://...` (Browser). See `.agents/skills/engine-server/SKILL.md` for dedicated server architecture, loopback playtests, and Docker + Caddy `wss://` deployment.

## 5. Closed-Loop Agent Workflow
1. **Scaffold**: `./build/engine --new games/<slug> --template <fps|voxel|pocket_house|procgen_roguelike|planet_explorer|multiplayer|xr>`
2. **Spatial & Multi-Seed Lint**: `./build/engine --headless --doctor --fuzz-seeds 10 --game games/<slug>`
3. **Visual Check**: `./build/engine --headless --game games/<slug> --capture-sheet /tmp/sheet.png --frames 30`
4. **Automated Playtest**: `./build/engine --headless --game games/<slug> --test tests/playtest.lua --seed 42 --max-frames 600`
