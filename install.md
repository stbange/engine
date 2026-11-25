# Install `stbange/engine` into Your Project

> **For AI coding agents**: Execute steps **1–5** in order inside the user's project root directory. Stop and report only if a system dependency or network step fails.

## Layout & Rules
- Keep the engine **unmodified** inside `engine/` so future upgrades stay clean.
- Keep all project game files in `game/` (or the folder the user requested): `game.json`, `scripts/main.lua`, `scenes/`, `locales/`, `assets/`, `tests/playtest.lua`.
- **Runtime contract**: Right-handed **`+X` Right, `+Y` Up, `-Z` Forward**, `1.0 = 1 meter`, strict **Lua 5.1 + `bit.*`**, deterministic `eng.math.*` (never `math.random` or `os.time`).

---

## Step 1 — Add `engine/` to the Project
Run from the project root (skip if `engine/CMakeLists.txt` already exists):

```bash
if [ -d .git ]; then
  git submodule add -b main https://github.com/stbange/engine.git engine \
    || git clone --depth 1 https://github.com/stbange/engine.git engine
else
  git clone --depth 1 https://github.com/stbange/engine.git engine
fi
```

Ensure `engine/build/` is ignored in `.gitignore`:
```bash
grep -qxF 'engine/build/' .gitignore 2>/dev/null || echo 'engine/build/' >> .gitignore
```

---

## Step 2 — Wire Agent Skills & `AGENTS.md`
Expose the engine's built-in agent skills at the project root so future sessions auto-discover them:

```bash
mkdir -p .agents/skills
for s in engine-gamedev engine-server engine-conformity-check engine-upgrade; do
  rm -rf ".agents/skills/$s"
  ln -s "../../engine/.agents/skills/$s" ".agents/skills/$s" 2>/dev/null \
    || cp -r "engine/.agents/skills/$s" ".agents/skills/$s"
done
```

Append the following section to the project's `AGENTS.md` (creating `AGENTS.md` if it does not exist; skip if `stbange/engine` is already mentioned):

```markdown
## Engine (`stbange/engine`)
- Engine checkout lives in `engine/` (do not edit `engine/src/` unless asked for an engine feature).
- Before editing game code, read `engine/.agents/skills/engine-gamedev/SKILL.md`, `engine/lua/eng_api.lua`, and `engine/assets/shared/catalog.json` (plus `engine/.agents/skills/engine-server/SKILL.md` for online servers).
- Use right-handed coordinates (`+X` right, `+Y` up, `-Z` forward, `1.0 = 1m`), strict Lua 5.1 + `bit.*`, and seeded `eng.math.*` RNG.
- Verify every milestone with:
  1. `python3 engine/.agents/skills/engine-conformity-check/scripts/check_conformity.py --strict game`
  2. `./engine/build/engine --repo-root engine --headless --doctor --fuzz-seeds 3 --game game`
  3. `./engine/build/engine --repo-root engine --headless --game game --test tests/playtest.lua --seed 42 --max-frames 300`
- To upgrade `engine/` later, pull `main` in `engine/` and follow `engine/.agents/skills/engine-upgrade/SKILL.md`.
```

---

## Step 3 — Build the Native Engine Runner
```bash
cmake -S engine -B engine/build -DCMAKE_BUILD_TYPE=Release
cmake --build engine/build -j
```

- **Ubuntu / Debian missing dev headers?** Install once:
  `sudo apt-get install -y build-essential cmake libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev libwayland-dev libxkbcommon-dev libgl-dev libegl-dev libasound2-dev libpulse-dev libluajit-5.1-dev`
- **Custom C11 host instead of Lua?** Skip `--new` below and link `engine::core` in your `CMakeLists.txt`:
  ```cmake
  add_subdirectory(engine)
  target_link_libraries(my_app PRIVATE engine::core)
  ```

---

## Step 4 — Scaffold `game/` (Skip if `game/game.json` Already Exists)
Pick the template closest to the user's request (`fps`, `voxel`, `pocket_house`, `procgen_roguelike`, `planet_explorer`, `multiplayer`, or `xr`; default `fps`):

```bash
[ -f game/game.json ] || ./engine/build/engine --new game --template fps
```

---

## Step 5 — Verify End-to-End (All Must Pass)
```bash
python3 engine/.agents/skills/engine-conformity-check/scripts/check_conformity.py --strict game
./engine/build/engine --repo-root engine --headless --doctor --fuzz-seeds 3 --game game
./engine/build/engine --repo-root engine --headless --game game --test tests/playtest.lua --seed 42 --max-frames 300
```

Optional visual 2×2 contact sheet (use `xvfb-run -a` on headless Linux):
```bash
./engine/build/engine --repo-root engine --game game --capture-sheet /tmp/game_check.png --frames 30
```

---

## Step 6 — Run, Host Servers & Build Your Game
- **Play interactively**: `./engine/build/engine --repo-root engine --game game` (`H` Help, `F1` Level Editor, `F5` Play-in-Editor, `~` Lua Console).
- **Run a dedicated cross-play server**: `./engine/build/engine --repo-root engine --server --game game --port 7777` (Desktop connects via `--connect ws://127.0.0.1:7777`; Browser connects via `play.html?game=...&server=ws://127.0.0.1:7777`; see `engine/server/docker-compose.yml` for production `wss://`).
- **Read before building features**:
  - Skill guides: `engine/.agents/skills/engine-gamedev/SKILL.md` and `engine/.agents/skills/engine-server/SKILL.md`
  - Exact Lua API: `engine/lua/eng_api.lua`
  - Shared MIT assets: `engine/assets/shared/catalog.json`
  - 102 reference games: `engine/games/` (e.g. `001_catacomb_blitz` FPS/dungeons, `099_shader_museum_xr` Deferred PBR/portals/gold/chrome/crystals/fire/smoke, `101_giant_cleaner_mech` 3P split-screen walkable mech, `102_portal_arena_mp` 4P split-screen + cross-play WebSocket server).
- **Finish**: Report the installed engine version (`./engine/build/engine --version`), the template scaffolded, and the pass status of all three Step 5 checks.
