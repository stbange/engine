# Upgrading Guide (`stbange/engine`)

This document tracks **every breaking change** across versions of `stbange/engine` so human developers and AI coding agents that cloned this repository (`git clone https://github.com/stbange/engine`) can upgrade safely and deterministically.

---

## How Coding Agents Should Upgrade a Downstream Project

1. Pull the target revision on `main` (`git -C engine pull origin main`).
2. Compare your game's `"engine_version"` in `game.json` (or `ENG_VERSION_STRING` if linking `libengine` from C) with `include/engine/eng_version.h`.
3. Apply every migration section below between your previous version and the new version in chronological order.
4. Rebuild and verify:
   ```bash
   cmake --build build -j
   ./build/engine --headless --doctor --game <your_game_dir>
   ./build/engine --headless --game <your_game_dir> --test tests/playtest.lua --seed 42
   ```
5. Update `"engine_version"` in `game.json` once diagnostics and playtests pass.

---

## Entry Template (Mandatory for Future Breaking Changes)

Every breaking change committed to `main` MUST append an entry in this exact machine- and human-readable format:

```markdown
## [X.Y.Z] - YYYY-MM-DD
### Breaking: <Short summary of symbol / Lua API / JSON field change>
- **Scope**: `C API` | `Lua API` | `Scene/Game JSON` | `Shader Uniforms`
- **Detect (`rg`)**: `rg "<old_pattern>" <project_dir>`
- **Before**:
  ```lua
  -- old usage
  ```
- **After**:
  ```lua
  -- new usage
  ```
- **Rationale**: <1-line reason>
```

---

## [0.1.0] - Initial Baseline
- Initial `eng_` C11 API, `eng.*` Lua 5.1 API, and `game.json` / `scene.json` v1 schemas established. No breaking migrations required yet.
