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

## 4b. Low-Res Realism Lens, Water, Fire, Lighting, Shadows & Volumetrics (`eng.fx.*`, `eng.render.*`, `eng.particles.*`)
- **Low-Res Realism Lens (Engine Signature Aesthetic)**: Prefer `"retro": { "preset": "lowres_realism", "pixel_height": 360 }` in `game.json` or `eng.render.set_retro("lowres_realism")` (or customize `{ preset="lowres_realism", pixel_height=360, render_scale=0.5, sharp_upscale="sharp"|"nearest", ssao=0.65, volumetric_fog=0.45, fog_sun_scatter=0.75, fog_density=0.015, fog_height=3.0, bloom=0.35 }`). This renders full physical HDR PBR, `2048²` slope-bias Bayer-PCF soft shadows, inverse-square lights, cotangent normal/roughness maps (auto-generated by `eng.procgen.texture`!), surface `wetness` (`eng.scene.set_wetness(ent, 0..1)`), SSAO, and shadowed volumetric god-rays at crisp `360p` upscaled cleanly behind native-resolution HUD text — with zero PS1 polygon wobble unless `"preset": "ps1"` is explicitly chosen.
- **Realistic Gerstner Water & Buoyancy**: Enable physical water in 1 call via `eng.fx.water(eng, "coastal_clear"|"alpine_river"|"murky_swamp", { level=0.0, flow={1.2, 0} })` or `eng.render.set_water({...})`. Automatically renders 4-lobe Gerstner waves, Beer-Lambert RGB depth absorption, screen-space refraction, shallow caustics, shoreline/crest foam, underwater camera immersion, underwater audio muffling, and Archimedes physics buoyancy (`eng.render.water_height(x, z)` queries live wave height).
- **Planck Blackbody Fire, Curl Turbulence & Soft Particles**: `eng.fx.spawn(eng, "fire", x, y, z, pocket?, opts?)` (or `eng.particles.create({ blackbody=true, temp_start=3400, temp_end=520, turbulence=2.4, wind={wx,wy,wz} })`) maps cooling particle temperature from incandescent white/orange additive flames into rising alpha-blended soot smoke with soft depth-faded intersections. Pair with `eng.sim_ext.update_firelight(eng, light_id, time, pocket)` for flickering inverse-square firelight.
- **Metals, Crystals & Skyboxes**: Use `eng.fx.material("gold"|"chrome"|"copper"|"obsidian"|"crystal"|"ruby"|"emerald"|"ice"|"glass"|"lava", overrides?)` with `eng.scene.set_mesh`, and `eng.fx.sky(eng, "alpine_day"|"sunset_mountains"|"synthwave_city"|"starry_night"|"overcast_forest"|"mars_dunes", { pocket=? })` for skyboxes, cubemaps, per-pocket portal skies, and 4-layer horizon parallax.

## 4c. Full 6-DOF Physics, Buoyancy, Breakable Joints & Voxel Fracture (`eng.physics.*`)
- **6-DOF Rigid Bodies & Material Density**: Dynamic `sphere`, `aabb` (OBB when rotated), `hull`, and `voxel` bodies tumble in full 3D (`capsule` locks rotation by default for character controllers; override with `freeze_rot = false`). Pass `density = 600` (wood floats in `1000 kg/m³` water!) or `density = 2600` (stone sinks!) on `eng.physics.add_body`. Settled debris sleeps automatically.
- **Impulses, Shockwaves, Wind & Joints**: Use `eng.physics.apply_impulse(bid, ix, iy, iz, px?, py?, pz?)` for off-center torque, `eng.physics.blast(pocket, cx, cy, cz, radius, impulse)` for explosions, `eng.physics.set_wind(pocket, wx, wy, wz)`, and `eng.physics.add_joint({ type="distance"|"ball"|"hinge"|"spring", body_a=0_or_bid, body_b=bid, anchor_a={...}, anchor_b={...}, break_force=250 })` for swinging lanterns, bridges, and breakable supports.
- **Structural Voxel Fracture**: Build voxel structures with `local mesh_id, vox_id = eng.asset.voxel_ascii(layers, sx, sy, sz, vs)` and carve/sever floating islands dynamically via `eng.physics.fracture_voxel(ent, vox_id, lx, ly, lz, radius)` — ungrounded components automatically detach as tumbling 6-DOF voxel rigid bodies!

## 4d. Systemic Chemistry, Thermodynamics & Biology (`eng.sim.*`, `eng.sim_ext.*`)
- **Cellular Chemistry & Phase Laws**: Initialize per-pocket reactive grids with `eng.sim.init({ gx=32, gy=16, gz=32, cell_size=0.5, origin={-8,0,-8} })` across 26 calibrated materials (`water`, `salt_water`, `ice`, `steam`, `oil`, `ethanol`, `lava`, `wood`, `charcoal`, `ash`, `foliage`, `gunpowder`, `stone`, `obsidian`, `sand`, `glass`, `soil`, `mud`, `iron`, `copper`, `rust`, `acid`, `smoke`, `methane`, `flesh`). Calling `eng.sim.step(dt)` simulates heat conduction/convection, `ice <-> water <-> steam`, `lava + water -> obsidian + steam`, `oil` floating & burning on `water`, `O2`-limited combustion (`wood -> charcoal -> ash` enriching soil!), `gunpowder`/`methane` physics blasts, voltage conduction (`eng.sim.set_voltage`) across metals/`salt_water`/wet surfaces, `acid` dissolution, and wet `iron -> rust`. Render cellular solids/liquids with `eng.sim.build_mesh(include_liquids)`.
- **Living Flora, Homeostasis & Wind Scent AI**: Register plants on soil (`eng.sim.add_plant`, `eng.sim.get_plant`) that grow (`seed -> sprout -> mature -> seeding`) from sunlight, moisture (`eng.sim.rain`), and wildfire `ash` nutrients. Track creature homeostasis (`eng.sim.add_bio`, `eng.sim.get_bio`: `37°C` core temp, cold-water hypothermia, heatstroke, drowning/smoke `O2`, electric shock, acid burns) and drive AI with wind-advected olfaction (`eng.sim.sample_scent`) and smoke/fog/darkness-aware sight (`eng.sim.can_see`).

## 4e. Split-Screen, Per-Player Gamepads & Cross-Platform Networking
- **1–4 Player Split-Screen & Gamepads**: Call `eng.camera.set_split(2|3|4, layout)`, `eng.camera.set_view(i, ...)`, `eng.ui.viewport_anchor(...)`, `eng.input.player_move(i)`, and `eng.camera.fps_steer_player(i, ...)`.
- **Cross-Platform Online Multiplayer**: Use `eng.mp.create_server` / `eng.mp.create_client` with `--server --port 7777` and `--connect ws://...` or `?server=wss://...` (see `.agents/skills/engine-server/SKILL.md`).

## 5. Closed-Loop Agent Workflow
1. **Scaffold**: `./build/engine --new games/<slug> --template <fps|voxel|pocket_house|procgen_roguelike|planet_explorer|multiplayer|xr>`
2. **Spatial & Multi-Seed Lint**: `./build/engine --headless --doctor --fuzz-seeds 10 --game games/<slug>`
3. **Visual & Media Check**: `./build/engine --headless --game games/<slug> --capture-sheet /tmp/sheet.png --frames 30` (see `.agents/skills/engine-media/SKILL.md` for replays, 4K screenshots, and Reels/YouTube exports)
4. **Automated Playtest**: `./build/engine --headless --game games/<slug> --test tests/playtest.lua --seed 42 --max-frames 600`
