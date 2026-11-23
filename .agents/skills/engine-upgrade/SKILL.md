---
name: engine-upgrade
description: >
  Safely upgrade downstream projects that cloned stbange/engine by checking
  engine_version, reading CHANGELOG.md and UPGRADING.md, validating OpenSpec
  deltas, and running --doctor + headless playtests.
license: MIT
---

# Engine Upgrade & Migration Skill (`stbange/engine`)

Use this skill when pulling updates from `https://github.com/stbange/engine` (`main` branch) into a downstream project or updating games after an engine change.

## Upgrade Checklist
1. **Check Current vs Incoming Version**:
   - Compare downstream `game.json` `"engine_version"` (or linked `ENG_VERSION_STRING` in `include/engine/eng_version.h`) against the updated `include/engine/eng_version.h`.
2. **Read Breaking Changes First**:
   - Inspect `CHANGELOG.md` and `UPGRADING.md` for every version between the old and new `ENG_VERSION`.
   - Each breaking entry in `UPGRADING.md` includes exact `rg` search patterns, before/after C and Lua snippets, and JSON schema field migrations.
3. **Validate Schemas & Lua Stubs**:
   - Check `lua/eng_api.lua` and `schemas/game.schema.json` / `schemas/scene.schema.json` for updated signatures.
4. **Rebuild & Run Diagnostics**:
   - Rebuild `engine` (`cmake --build build -j`), then run:
     - `./build/engine --headless --doctor --game <game_dir>`
     - `./build/engine --headless --game <game_dir> --test tests/playtest.lua --seed 42`
   - Update `"engine_version"` in `game.json` once all checks pass with zero warnings.
