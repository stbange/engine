---
name: engine-conformity-check
description: >
  Audit stbange/engine games (one game or the full games/ catalog) for engine
  misuse, silently ignored options, missing physics colliders or wall sliding,
  Z-fighting, non-deterministic RNG, unbound input actions, camera/pocket bugs,
  and Lua 5.1/sandbox violations — then propose and apply idiomatic fixes.
license: MIT
---

# Engine Conformity Check Skill (`stbange/engine`)

Use this skill whenever reviewing an existing `stbange/engine` game or auditing the full `games/` catalog to find places where scripts bypass or misuse engine subsystems instead of using the engine properly.

## 1. Run the Automated Conformity Scanner First

Run the bundled zero-dependency Python scanner from the repository root:

```bash
# Audit every game in games/
python3 .agents/skills/engine-conformity-check/scripts/check_conformity.py

# Audit a single game (exit non-zero on any ERROR or WARN)
python3 .agents/skills/engine-conformity-check/scripts/check_conformity.py games/001_catacomb_blitz --strict
```

When run inside the engine repository, the script inspects `src/eng_lua.c` and `src/eng_procgen.c` directly so allowed option keys, texture recipes, and bound input actions stay synced with the C11 runtime.

## 2. Conformity Rules & Idiomatic Remediations

### A. API Contract & Silent No-Ops (`ERROR`)
- **`unknown-option-key`**: Option tables passed to `eng.render.set_retro`, `eng.scene.set_mesh`, `eng.render.add_light`, `eng.physics.add_body`, `eng.particles.create`, or `game.json` `"retro"` MUST only use keys parsed by `src/eng_lua.c` (e.g. `vertex_snap`, never `ps1_snap` or `snap_res`).
- **`invalid-enum-value`**: String enums passed to `eng.physics.add_body` (`shape`, `motion`), `eng.procgen.texture`, `eng.procgen.animal`, `eng.audio.synth`, `eng.xr.set_mode`, and `eng.render.set_pipeline` MUST match values implemented in C (no silent fallbacks).
- **`unbound-input-action`**: Every literal action passed to `eng.input.down/pressed/axis2d` MUST be bound in `src/eng_lua.c` (otherwise headless `eng.input.inject` passes while real players have no key).
- **`nondeterministic-rng`**: Replace `math.random`, `math.randomseed`, `os.time`, and `os.clock` with `eng.math.rand`/`eng.math.range` and explicit integer seeds.
- **`lua52-incompatible`**: Keep scripts in strict Lua 5.1 + `bit.*` (no `table.unpack`, `bit32`, `goto`, or `//`) so Desktop LuaJIT 2.1 and Web PUC-Rio Lua 5.1.5 behave identically.
- **`missing-asset-or-locale`**: Verify every `eng.asset.load_mesh` / `load_texture` path exists, every `eng.i18n.t("key")` exists in `locales/en.json` and `locales/de.json`, and `game.json` provides `"description"`.
- **`lifecycle-misuse`**: Never allocate meshes, textures, audio clips, or unguarded lights inside `update()`/`draw()`; never call `eng.render.draw_sprite` or `eng.ui.*` inside `update()`.

### B. Physics, Collision & Spatial Integrity (`ERROR` / `WARN`)
- **`slide-move-no-static-bodies`**: Any game calling `eng.physics.slide_move` MUST register static colliders (`motion = "static"`, dungeon voxel collider, or pocket building/vehicle interior) in that pocket — otherwise `slide_move` is a no-op.
- **`fps-missing-wall-collision`**: First-person / walkable-interior games using `eng.camera.fps_steer` that spawn static walls, pillars, buildings, or vehicle cabins MUST attach static colliders (`eng.physics.add_body(..., { motion = "static" })`) and resolve movement through `eng.physics.slide_move` or `eng.physics.move_character`.
- **`pocket-building-missing-collision`**: Walkable games using `eng.space.create_pocket_building` or `eng.space.attach_vehicle_interior` MUST resolve player movement against the building/hull wall colliders via `slide_move` or `move_character` (doorways remain open for `eng.portal.check_crossing`).
- **`walkable-props-missing-collision`**: Top-down / third-person walkable games moving `S.px`/`S.pz` around spawned pillars, counters, tables, or monoliths MUST attach static colliders and resolve movement via `eng.physics.slide_move`.
- **`dungeon-missing-collider`**: Walkable games using `eng.procgen.dungeon(...)` MUST attach `{ shape = "voxel", motion = "static", voxel_id = d.voxel_id }` (or use `eng.procgen_ext.spawn_dungeon_entity`), pass `d.walkable` to `eng.ai.set_grid` when pathfinding, and NEVER render a coplanar `y = 0` floor mesh over the dungeon floor.
- **`collider-order-or-scale`**: Call `eng.scene.set_pos` and `eng.scene.set_pocket` BEFORE static `eng.physics.add_body`, and ensure box AABB `half_extents` match `set_scale * 0.5`.
- **`coplanar-z-fighting`**: Never place two rendered box meshes in the same pocket with identical top `Y` (`|topA - topB| < 0.008m`) and overlapping XZ footprints; never draw sprites at `y <= 0`.

### C. Camera, Pockets, Controls & HUD (`WARN` / `ERROR`)
- **`camera-orbit-or-mismatch`**: Walkable FPS / free-roam games MUST use `eng.input.set_mouse_lock(true)` + `eng.camera.fps_steer`, never fixed-target orbiting `eng.camera.look_at`; `game.json` `xr_mode` and `pipeline` must agree with `scripts/main.lua`.
- **`unlit-pocket-space`**: Every registered non-world pocket (unless created by `create_steerable_vehicle`) MUST register at least one light scoped to that pocket.
- **`fake-distant-interior`**: Never fake separate rooms at coordinates `>= 500m`; use isolated pocket spaces (`eng.space.*`).
- **`hud-overlaps-helpbar`**: Keep persistent `eng.ui.label` / `draw_text` above `y = 600` (virtual `1280x720`) so HUD doesn't collide with the built-in bottom help bar.

## 3. Root-Cause Triage Before Editing Games (Ponytail Rule)

Before patching many games for the same finding, check whether the real gap is in shared engine code:
1. If multiple games pass the same missing texture recipe, particle option, or pocket sync behavior, fix it **once** in `src/` or `lua/eng/` (updating `openspec/specs/` first if public APIs change) and add a unit test.
2. Then patch each remaining non-conforming game with the smallest complete edit (attaching static colliders to existing wall/pillar meshes and wiring `slide_move`, fixing bad keys, updating playtests if they previously clipped through solid walls).

## 4. Mandatory Verification After Applying Propositions

1. `python3 .agents/skills/engine-conformity-check/scripts/check_conformity.py --strict` -> **0 errors, 0 warnings**
2. `OPENSPEC_TELEMETRY=0 openspec validate --specs --strict` -> all specs pass
3. Native build + `python3 tests/run_all_games.py ./build-rel/engine --expect-count 101` -> **100% pass** (`--doctor` + `playtest.lua`)
4. Coverage build + `ctest` + `python3 tests/check_coverage.py build-cov` -> **>= 95.0% C & Lua line coverage**
5. If C/Lua stdlib or web shell changed: Emscripten build + `python3 tests/check_web_bundle.py dist`
