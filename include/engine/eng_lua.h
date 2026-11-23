#ifndef ENG_LUA_H
#define ENG_LUA_H

#include "eng_ai.h"
#include "eng_anim.h"
#include "eng_asset.h"
#include "eng_audio.h"
#include "eng_i18n.h"
#include "eng_input.h"
#include "eng_math.h"
#include "eng_net.h"
#include "eng_particles.h"
#include "eng_physics.h"
#include "eng_platform.h"
#include "eng_portal.h"
#include "eng_procgen.h"
#include "eng_render.h"
#include "eng_scene.h"
#include "eng_terrain.h"
#include "eng_text.h"
#include "eng_vfs.h"
#include "eng_voxel.h"
#include "eng_xr.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *repo_root;
    const char *game_dir;
    const char *mod_dir;
    bool headless;
    int width;
    int height;
    uint64_t seed;
    const char *lua_cov_out_path;
} eng_runtime_cfg_t;

typedef struct eng_runtime_s eng_runtime_t;

eng_runtime_cfg_t eng_runtime_default_cfg(void);

eng_runtime_t *eng_runtime_create(const eng_runtime_cfg_t *cfg);
void eng_runtime_destroy(eng_runtime_t *rt);

/* Accessors for subsystems (used by Spatial Doctor, Editor, Profiler & Tests) */
eng_vfs_t *eng_runtime_vfs(eng_runtime_t *rt);
eng_scene_t *eng_runtime_scene(eng_runtime_t *rt);
eng_portal_sys_t *eng_runtime_portals(eng_runtime_t *rt);
eng_physics_t *eng_runtime_physics(eng_runtime_t *rt);
eng_renderer_t *eng_runtime_renderer(eng_runtime_t *rt);
eng_asset_cache_t *eng_runtime_assets(eng_runtime_t *rt);
eng_input_t *eng_runtime_input(eng_runtime_t *rt);
eng_xr_t *eng_runtime_xr(eng_runtime_t *rt);
eng_platform_t *eng_runtime_platform(eng_runtime_t *rt);
eng_camera_t *eng_runtime_camera(eng_runtime_t *rt);
uint32_t eng_runtime_light_count(const eng_runtime_t *rt);
size_t eng_runtime_hud_text_count(const eng_runtime_t *rt);
const char *eng_runtime_hud_text_get(const eng_runtime_t *rt, size_t idx, float *out_x, float *out_y);

/* Load game.json + scenes/main.json (if present) + scripts/main.lua + active mod.lua, then call init(). */
bool eng_runtime_boot_game(eng_runtime_t *rt, char *err_buf, size_t err_cap);

/* Execute one deterministic simulation tick (input -> async/update(dt) -> physics -> gait IK -> audio -> hot-reload). */
bool eng_runtime_step(eng_runtime_t *rt, float dt, char *err_buf, size_t err_cap);

/* Submit all scene entities, procedural animations, HUD text, and Lua draw() calls to renderer. */
bool eng_runtime_render(eng_runtime_t *rt, char *err_buf, size_t err_cap);

/* State-preserving script hot reload (reloads scripts/main.lua while keeping game.state intact). */
bool eng_runtime_reload_scripts(eng_runtime_t *rt, char *err_buf, size_t err_cap);

/* Evaluate sandboxed Lua snippet (used by ~ console REPL, unit tests, and playtest runner). */
bool eng_runtime_exec_lua(eng_runtime_t *rt, const char *chunk_name, const char *code,
                          char *out_or_err, size_t cap);

/* Run an external playtest script (e.g. "tests/playtest.lua") with failing-frame JSON snapshot diagnostics. */
bool eng_runtime_run_playtest(eng_runtime_t *rt, const char *test_vpath, int max_frames,
                              char *err_buf, size_t err_cap);

/* Auto-generate lua/eng_api.lua (LuaLS ---@meta annotations) from C registration descriptors. */
bool eng_lua_write_api_stubs(const char *out_path);

#ifdef __cplusplus
}
#endif

#endif /* ENG_LUA_H */
