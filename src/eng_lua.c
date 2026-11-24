#include "engine/eng_lua.h"
#include "engine/eng_log.h"
#include "engine/eng_serde.h"
#include "engine/eng_version.h"

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#ifdef ENG_USING_LUAJIT
#include <luajit.h>
#endif

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef ENG_USING_LUAJIT
int luaopen_bit(lua_State *L);
#endif

#define ENG_MAX_ENT_VISUALS 512
#define ENG_MAX_PERSIST_LIGHTS 16
#define ENG_LUA_WATCHDOG_STEPS 400000

typedef struct {
    eng_entity_t ent;
    uint32_t mesh_id;
    uint32_t tex_id;
    eng_vec4_t color;
    float metallic;
    float roughness;
    bool cast_shadow;
    bool occluder;
    bool has_rig;
    eng_skeleton_t skel;
    eng_gait_cfg_t gait;
    eng_anim_pose_t pose;
    float gait_phase;
    float gait_speed;
} ent_visual_t;

typedef struct {
    eng_entity_t ent;
    uint32_t body_id;
} ent_body_map_t;

typedef struct {
    char path[512];
    bool active[512];
    int hits[512];
} lua_cov_file_t;

struct eng_runtime_s {
    eng_runtime_cfg_t cfg;
    char repo_root_buf[512];
    char game_dir_buf[512];
    char mod_dir_buf[512];
    char cov_path_buf[512];

    eng_vfs_t *vfs;
    eng_platform_t *plat;
    eng_input_t *input;
    eng_xr_t *xr;
    eng_asset_cache_t *assets;
    eng_renderer_t *renderer;
    eng_scene_t *scene;
    eng_portal_sys_t *portals;
    eng_physics_t *physics;
    eng_audio_t *audio;
    eng_nav_t *nav;
    eng_i18n_t *i18n;
    eng_font_t *font;
    eng_net_peer_t *net_srv;
    eng_net_peer_t *net_cli;

    eng_camera_t cam;
    eng_rng_t rng;

    ent_visual_t visuals[ENG_MAX_ENT_VISUALS];
    size_t visual_count;
    ent_body_map_t body_map[ENG_MAX_ENT_VISUALS];
    size_t body_map_count;
    eng_light_t persist_lights[ENG_MAX_PERSIST_LIGHTS];
    size_t persist_light_count;
    eng_terrain_t terrains[8];
    size_t terrain_count;
    eng_voxel_chunk_t dungeon_chunks[8];
    bool dungeon_chunk_valid[8];
    size_t dungeon_chunk_cursor;
    eng_emitter_t *emitters[16];
    size_t emitter_count;

    lua_State *L;
    int sandbox_ref;
    int mod_hooks_ref;
    int watchdog_left;

    struct { float x, y; char text[160]; } hud_texts[24];
    size_t hud_text_count;
    char game_desc[256];
    uint32_t seen_inputs;

    bool kinematics_synced;
    bool cov_enabled;
    lua_cov_file_t cov_files[16];
    size_t cov_file_count;
};

typedef struct {
    const char *mod;
    const char *name;
    lua_CFunction fn;
    const char *sig;
    const char *doc;
} lua_fn_desc_t;

/* --------------------------------------------------------------------------
 * Multi-File Lua Bytecode Line Coverage + Infinite-Loop Watchdog Hook
 * -------------------------------------------------------------------------- */
static char g_reg_rt_key;

static eng_runtime_t *get_rt(lua_State *L) {
    lua_pushlightuserdata(L, &g_reg_rt_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    eng_runtime_t *rt = (eng_runtime_t *)lua_touserdata(L, -1);
    lua_pop(L, 1);
    return rt;
}

static lua_cov_file_t *find_or_add_cov_file(eng_runtime_t *rt, const char *path) {
    for (size_t i = 0; i < rt->cov_file_count; i++) {
        if (strcmp(rt->cov_files[i].path, path) == 0) return &rt->cov_files[i];
    }
    if (rt->cov_file_count >= 16) return NULL;
    lua_cov_file_t *cf = &rt->cov_files[rt->cov_file_count++];
    memset(cf, 0, sizeof(*cf));
    snprintf(cf->path, sizeof(cf->path), "%s", path);
    return cf;
}

static void mark_active_lines_recursive(eng_runtime_t *rt, lua_State *L, lua_cov_file_t *cf) {
    if (!cf) return;
    if (lua_isfunction(L, -1) && !lua_iscfunction(L, -1)) {
        lua_Debug ar;
        lua_pushvalue(L, -1);
        if (lua_getinfo(L, ">L", &ar) && lua_istable(L, -1)) {
            lua_pushnil(L);
            while (lua_next(L, -2) != 0) {
                if (lua_isnumber(L, -2)) {
                    int ln = (int)lua_tointeger(L, -2);
                    if (ln > 0 && ln < 512) cf->active[ln] = true;
                }
                lua_pop(L, 1);
            }
            lua_pop(L, 1);
        }
    } else if (lua_istable(L, -1)) {
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            if (lua_isfunction(L, -1) && !lua_iscfunction(L, -1)) {
                mark_active_lines_recursive(rt, L, cf);
            }
            lua_pop(L, 1);
        }
    }
}

static void unified_lua_hook(lua_State *L, lua_Debug *ar) {
    eng_runtime_t *rt = get_rt(L);
    if (!rt) return;
    if (ar->event == LUA_HOOKLINE && rt->cov_enabled && ar->currentline > 0 && ar->currentline < 512) {
        if (lua_getinfo(L, "S", ar) && ar->source[0] == '@' && strstr(ar->source + 1, "lua/eng/") != NULL) {
            lua_cov_file_t *cf = find_or_add_cov_file(rt, ar->source + 1);
            if (cf) cf->hits[ar->currentline]++;
        }
    } else if (ar->event == LUA_HOOKCOUNT) {
        rt->watchdog_left -= 2000;
        if (rt->watchdog_left <= 0) {
            luaL_error(L, "Watchdog: script exceeded per-frame instruction limit (infinite loop?)");
        }
    }
}

static void arm_watchdog(eng_runtime_t *rt) {
    rt->watchdog_left = ENG_LUA_WATCHDOG_STEPS;
    int mask = LUA_MASKCOUNT | (rt->cov_enabled ? LUA_MASKLINE : 0);
    lua_sethook(rt->L, unified_lua_hook, mask, 2000);
}

static void flush_lua_cov(const eng_runtime_t *rt) {
    if (!rt->cov_enabled || rt->cov_path_buf[0] == '\0') return;
    FILE *fp = fopen(rt->cov_path_buf, "a");
    if (!fp) return;
    for (size_t i = 0; i < rt->cov_file_count; i++) {
        const lua_cov_file_t *cf = &rt->cov_files[i];
        fprintf(fp, "TN:\nSF:%s\n", cf->path);
        for (int ln = 1; ln < 512; ln++) {
            if (cf->active[ln]) fprintf(fp, "DA:%d,%d\n", ln, cf->hits[ln]);
        }
        fprintf(fp, "end_of_record\n");
    }
    fclose(fp);
}

/* --------------------------------------------------------------------------
 * NaN/Inf-Trapped Lua Argument Helpers & Entity Helpers
 * -------------------------------------------------------------------------- */
static float chk_f(lua_State *L, int idx) {
    double v = luaL_checknumber(L, idx);
    float f = (float)v;
    if (!eng_math_is_finite(f)) {
        luaL_where(L, 1);
        lua_pushfstring(L, "%sNaN/Inf passed to numeric argument #%d", lua_tostring(L, -1), idx);
        return (float)lua_error(L);
    }
    return f;
}

static float opt_f(lua_State *L, int idx, float def) {
    return lua_isnoneornil(L, idx) ? def : chk_f(L, idx);
}

static eng_vec3_t opt_tbl_v3(lua_State *L, int idx, eng_vec3_t def) {
    if (!lua_istable(L, idx)) return def;
    eng_vec3_t r = def;
    lua_rawgeti(L, idx, 1); if (lua_isnumber(L, -1)) r.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_rawgeti(L, idx, 2); if (lua_isnumber(L, -1)) r.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_rawgeti(L, idx, 3); if (lua_isnumber(L, -1)) r.z = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    if (!eng_v3_is_finite(r)) luaL_error(L, "NaN/Inf in vec3 table at arg #%d", idx);
    return r;
}

static eng_vec4_t opt_tbl_v4(lua_State *L, int idx, eng_vec4_t def) {
    if (!lua_istable(L, idx)) return def;
    eng_vec4_t r = def;
    lua_rawgeti(L, idx, 1); if (lua_isnumber(L, -1)) r.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_rawgeti(L, idx, 2); if (lua_isnumber(L, -1)) r.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_rawgeti(L, idx, 3); if (lua_isnumber(L, -1)) r.z = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_rawgeti(L, idx, 4); if (lua_isnumber(L, -1)) r.w = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    return r;
}

static ent_visual_t *find_or_alloc_visual(eng_runtime_t *rt, eng_entity_t ent) {
    for (size_t i = 0; i < rt->visual_count; i++) {
        if (rt->visuals[i].ent == ent) return &rt->visuals[i];
    }
    if (rt->visual_count >= ENG_MAX_ENT_VISUALS) return NULL;
    ent_visual_t *v = &rt->visuals[rt->visual_count++];
    memset(v, 0, sizeof(*v));
    v->ent = ent;
    v->color = (eng_vec4_t){1, 1, 1, 1};
    v->roughness = 0.7f;
    return v;
}

static uint32_t find_ent_body(const eng_runtime_t *rt, eng_entity_t ent) {
    for (size_t i = 0; i < rt->body_map_count; i++) {
        if (rt->body_map[i].ent == ent) return rt->body_map[i].body_id;
    }
    return 0;
}

/* --------------------------------------------------------------------------
 * C-to-Lua API Functions (eng.*)
 * -------------------------------------------------------------------------- */
static int l_log_info(lua_State *L)  { ENG_LOGI("lua", "%s", luaL_checkstring(L, 1)); return 0; }
static int l_log_warn(lua_State *L)  { ENG_LOGW("lua", "%s", luaL_checkstring(L, 1)); return 0; }
static int l_log_error(lua_State *L) { ENG_LOGE("lua", "%s", luaL_checkstring(L, 1)); return 0; }

static int l_math_seed(lua_State *L) {
    eng_rng_seed(&get_rt(L)->rng, (uint64_t)luaL_checknumber(L, 1));
    return 0;
}
static int l_math_rand(lua_State *L) {
    lua_pushnumber(L, eng_rng_float01(&get_rt(L)->rng));
    return 1;
}
static int l_math_range(lua_State *L) {
    lua_pushnumber(L, eng_rng_rangef(&get_rt(L)->rng, chk_f(L, 1), chk_f(L, 2)));
    return 1;
}
static int l_math_clamp(lua_State *L) {
    lua_pushnumber(L, eng_clampf(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3)));
    return 1;
}
static int l_math_dist3(lua_State *L) {
    eng_vec3_t d = eng_v3(chk_f(L, 1) - chk_f(L, 4), chk_f(L, 2) - chk_f(L, 5), chk_f(L, 3) - chk_f(L, 6));
    lua_pushnumber(L, eng_v3_len(d));
    return 1;
}

static void note_input_action(eng_runtime_t *rt, const char *act) {
    if (!rt || !act) return;
    if (strcmp(act, "left") == 0 || strcmp(act, "right") == 0) rt->seen_inputs |= 1u;
    else if (strcmp(act, "up") == 0 || strcmp(act, "down") == 0) rt->seen_inputs |= 2u;
    else if (strcmp(act, "fire") == 0) rt->seen_inputs |= 4u;
    else if (strcmp(act, "jump") == 0) rt->seen_inputs |= 8u;
    else if (strcmp(act, "interact") == 0) rt->seen_inputs |= 16u;
}
static int l_input_down(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *act = luaL_checkstring(L, 1);
    note_input_action(rt, act);
    lua_pushboolean(L, eng_input_down(rt->input, act));
    return 1;
}
static int l_input_pressed(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *act = luaL_checkstring(L, 1);
    note_input_action(rt, act);
    lua_pushboolean(L, eng_input_pressed(rt->input, act));
    return 1;
}
static int l_input_axis(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *nx = luaL_checkstring(L, 1), *px = luaL_checkstring(L, 2);
    const char *ny = luaL_checkstring(L, 3), *py = luaL_checkstring(L, 4);
    note_input_action(rt, nx); note_input_action(rt, px);
    note_input_action(rt, ny); note_input_action(rt, py);
    float x = (eng_input_down(rt->input, px) ? 1.0f : 0.0f) - (eng_input_down(rt->input, nx) ? 1.0f : 0.0f);
    float y = (eng_input_down(rt->input, py) ? 1.0f : 0.0f) - (eng_input_down(rt->input, ny) ? 1.0f : 0.0f);
    float len = sqrtf(x * x + y * y);
    if (len > 1.0f) { x /= len; y /= len; }
    lua_pushnumber(L, x);
    lua_pushnumber(L, y);
    return 2;
}
static int l_input_inject(lua_State *L) {
    eng_input_inject_action(get_rt(L)->input, luaL_checkstring(L, 1), lua_toboolean(L, 2));
    return 0;
}
static eng_vec2_t get_look_delta(const eng_runtime_t *rt) {
    if (!rt) return (eng_vec2_t){0.0f, 0.0f};
    bool allow = eng_platform_is_mouse_lock(rt->plat) ||
                 eng_platform_is_headless(rt->plat) ||
                 eng_input_is_touch_active(rt->input) ||
                 eng_input_down(rt->input, "fire");
    return allow ? eng_input_mouse_delta(rt->input) : (eng_vec2_t){0.0f, 0.0f};
}
static int l_input_set_mouse_lock(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    bool locked = lua_toboolean(L, 1) != 0;
    if (locked) rt->seen_inputs |= 32u;
    lua_pushboolean(L, eng_platform_set_mouse_lock(rt->plat, locked));
    return 1;
}
static int l_input_is_mouse_locked(lua_State *L) {
    lua_pushboolean(L, eng_platform_is_mouse_lock(get_rt(L)->plat));
    return 1;
}
static int l_input_mouse_delta(lua_State *L) {
    eng_vec2_t d = get_look_delta(get_rt(L));
    lua_pushnumber(L, d.x);
    lua_pushnumber(L, d.y);
    return 2;
}

static int l_xr_set_mode(lua_State *L) {
    const char *m = luaL_checkstring(L, 1);
    eng_xr_mode_t xm = (strcmp(m, "cockpit") == 0) ? ENG_XR_COCKPIT :
                       (strcmp(m, "first_person") == 0) ? ENG_XR_FIRST_PERSON :
                       (strcmp(m, "6dof") == 0) ? ENG_XR_6DOF : ENG_XR_DIORAMA;
    eng_xr_set_mode(get_rt(L)->xr, xm);
    return 0;
}
static int l_xr_active(lua_State *L) {
    lua_pushboolean(L, eng_xr_is_active(get_rt(L)->xr));
    return 1;
}

static int l_scene_spawn(lua_State *L) {
    eng_entity_t e = eng_scene_spawn(get_rt(L)->scene, luaL_optstring(L, 1, "entity"));
    lua_pushnumber(L, (lua_Number)e);
    return 1;
}
static int l_scene_despawn(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_entity_t e = (eng_entity_t)luaL_checknumber(L, 1);
    uint32_t bid = find_ent_body(rt, e);
    if (bid) {
        eng_physics_remove_body(rt->physics, bid);
        for (size_t i = 0; i < rt->body_map_count; i++) {
            if (rt->body_map[i].ent == e) { rt->body_map[i] = rt->body_map[--rt->body_map_count]; break; }
        }
    }
    for (size_t i = 0; i < rt->visual_count; i++) {
        if (rt->visuals[i].ent == e) { rt->visuals[i] = rt->visuals[--rt->visual_count]; break; }
    }
    lua_pushboolean(L, eng_scene_despawn(rt->scene, e));
    return 1;
}
static int l_scene_find(lua_State *L) {
    eng_entity_t e = eng_ecs_find_by_name(eng_scene_ecs(get_rt(L)->scene), luaL_checkstring(L, 1));
    if (e == ENG_ENTITY_NULL) lua_pushnil(L);
    else lua_pushnumber(L, (lua_Number)e);
    return 1;
}
static int l_scene_set_pos(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_entity_t e = (eng_entity_t)luaL_checknumber(L, 1);
    eng_vec3_t p = eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4));
    eng_scene_set_local_pos(rt->scene, e, p);
    uint32_t bid = find_ent_body(rt, e);
    if (bid) {
        eng_body_desc_t *bd = eng_physics_get_body(rt->physics, bid);
        if (bd) bd->pos = p;
    }
    return 0;
}
static int l_scene_get_pos(lua_State *L) {
    const eng_transform_local_t *tr = eng_scene_get_local(get_rt(L)->scene, (eng_entity_t)luaL_checknumber(L, 1));
    eng_vec3_t p = tr ? tr->pos : eng_v3(0, 0, 0);
    lua_pushnumber(L, p.x); lua_pushnumber(L, p.y); lua_pushnumber(L, p.z);
    return 3;
}
static int l_scene_set_rot_deg(lua_State *L) {
    eng_scene_set_local_rot(get_rt(L)->scene, (eng_entity_t)luaL_checknumber(L, 1),
                            eng_quat_from_euler_deg(eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4))));
    return 0;
}
static int l_scene_set_scale(lua_State *L) {
    eng_scene_set_local_scale(get_rt(L)->scene, (eng_entity_t)luaL_checknumber(L, 1),
                              eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4)));
    return 0;
}
static int l_scene_set_parent(lua_State *L) {
    eng_scene_set_parent(get_rt(L)->scene, (eng_entity_t)luaL_checknumber(L, 1), (eng_entity_t)luaL_optnumber(L, 2, 0));
    return 0;
}
static int l_scene_reg_pocket(lua_State *L) {
    lua_pushinteger(L, eng_scene_register_pocket(get_rt(L)->scene, luaL_checkstring(L, 1)));
    return 1;
}
static int l_scene_set_pocket(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_entity_t e = (eng_entity_t)luaL_checknumber(L, 1);
    uint16_t pid = lua_type(L, 2) == LUA_TSTRING
                       ? eng_scene_register_pocket(rt->scene, lua_tostring(L, 2))
                       : (uint16_t)luaL_checkinteger(L, 2);
    eng_scene_set_pocket(rt->scene, e, pid);
    return 0;
}
static int l_scene_get_pocket(lua_State *L) {
    lua_pushinteger(L, eng_scene_get_pocket(get_rt(L)->scene, (eng_entity_t)luaL_checknumber(L, 1)));
    return 1;
}
static int l_scene_set_mesh(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_entity_t e = (eng_entity_t)luaL_checknumber(L, 1);
    uint32_t mid = (uint32_t)luaL_checkinteger(L, 2);
    ent_visual_t *v = find_or_alloc_visual(rt, e);
    if (!v) return 0;
    v->mesh_id = mid;
    if (lua_istable(L, 3)) {
        lua_getfield(L, 3, "color"); v->color = opt_tbl_v4(L, lua_gettop(L), v->color); lua_pop(L, 1);
        lua_getfield(L, 3, "tex"); if (lua_isnumber(L, -1)) v->tex_id = (uint32_t)lua_tointeger(L, -1); lua_pop(L, 1);
        lua_getfield(L, 3, "metallic"); if (lua_isnumber(L, -1)) v->metallic = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_getfield(L, 3, "roughness"); if (lua_isnumber(L, -1)) v->roughness = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_getfield(L, 3, "cast_shadow"); if (!lua_isnil(L, -1)) v->cast_shadow = lua_toboolean(L, -1); lua_pop(L, 1);
        lua_getfield(L, 3, "occluder"); if (!lua_isnil(L, -1)) v->occluder = lua_toboolean(L, -1); lua_pop(L, 1);
    }
    return 0;
}
static int l_scene_dump_json(lua_State *L) {
    char buf[8192];
    eng_ecs_dump_json(eng_scene_ecs(get_rt(L)->scene), buf, sizeof(buf));
    lua_pushstring(L, buf);
    return 1;
}

static int l_cam_set(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    rt->cam.pos = eng_v3(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3));
    if (!lua_isnoneornil(L, 4)) {
        rt->cam.rot = eng_quat_from_euler_deg(eng_v3(chk_f(L, 4), opt_f(L, 5, 0.0f), opt_f(L, 6, 0.0f)));
    }
    if (!lua_isnoneornil(L, 7)) rt->cam.pocket_id = (uint16_t)luaL_checkinteger(L, 7);
    return 0;
}
static int l_cam_look_at(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_vec3_t eye = eng_v3(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3));
    eng_vec3_t tgt = eng_v3(chk_f(L, 4), chk_f(L, 5), chk_f(L, 6));
    rt->cam.pos = eye;
    eng_vec3_t d = eng_v3_norm(eng_v3_sub(tgt, eye));
    float yaw = atan2f(-d.x, -d.z) * ENG_RAD2DEG;
    float pitch = asinf(eng_clampf(d.y, -1.0f, 1.0f)) * ENG_RAD2DEG;
    rt->cam.rot = eng_quat_from_euler_deg(eng_v3(pitch, yaw, 0.0f));
    if (!lua_isnoneornil(L, 7)) rt->cam.pocket_id = (uint16_t)luaL_checkinteger(L, 7);
    return 0;
}
static int l_cam_get(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    lua_pushnumber(L, rt->cam.pos.x); lua_pushnumber(L, rt->cam.pos.y); lua_pushnumber(L, rt->cam.pos.z);
    lua_pushinteger(L, rt->cam.pocket_id);
    return 4;
}
static int l_cam_fps_steer(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    float yaw = opt_f(L, 1, 0.0f);
    float pitch = opt_f(L, 2, 0.0f);
    float speed = chk_f(L, 3);
    float dt = chk_f(L, 4);
    float sens = opt_f(L, 5, 0.22f);
    if (!eng_platform_wants_mouse_lock(rt->plat)) {
        eng_platform_set_mouse_lock(rt->plat, true);
    }
    rt->seen_inputs |= (1u | 2u | 32u);
    eng_vec2_t md = get_look_delta(rt);
    yaw -= md.x * sens;
    pitch = eng_clampf(pitch - md.y * sens, -80.0f, 80.0f);
    float ix = (eng_input_down(rt->input, "right") ? 1.0f : 0.0f) - (eng_input_down(rt->input, "left") ? 1.0f : 0.0f);
    float iy = (eng_input_down(rt->input, "up") ? 1.0f : 0.0f) - (eng_input_down(rt->input, "down") ? 1.0f : 0.0f);
    float len = sqrtf(ix * ix + iy * iy);
    if (len > 1.0f) { ix /= len; iy /= len; }
    float rad = yaw * ENG_DEG2RAD;
    float fx = -sinf(rad), fz = -cosf(rad);
    float rx = cosf(rad), rz = -sinf(rad);
    lua_pushnumber(L, yaw);
    lua_pushnumber(L, pitch);
    lua_pushnumber(L, (fx * iy + rx * ix) * speed * dt);
    lua_pushnumber(L, (fz * iy + rz * ix) * speed * dt);
    lua_pushnumber(L, fx);
    lua_pushnumber(L, fz);
    return 6;
}

static int l_render_pipeline(lua_State *L) {
    const char *m = luaL_checkstring(L, 1);
    eng_renderer_set_pipeline(get_rt(L)->renderer, strcmp(m, "deferred") == 0 ? ENG_PIPELINE_DEFERRED : ENG_PIPELINE_FORWARD);
    return 0;
}
static int l_render_retro(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_retro_cfg_t cfg = lua_toboolean(L, 1) ? eng_retro_ps1_preset() : eng_retro_default();
    if (lua_istable(L, 1)) {
        cfg = eng_renderer_get_retro(rt->renderer);
        lua_getfield(L, 1, "vertex_snap"); if (lua_isnumber(L, -1)) cfg.vertex_snap_res = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_getfield(L, 1, "dither"); if (!lua_isnil(L, -1)) cfg.dither_bayer = lua_toboolean(L, -1); lua_pop(L, 1);
        lua_getfield(L, 1, "color_bits"); if (lua_isnumber(L, -1)) cfg.color_bits = (int)lua_tointeger(L, -1); lua_pop(L, 1);
        lua_getfield(L, 1, "fog_density"); if (lua_isnumber(L, -1)) cfg.fog_density = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_getfield(L, 1, "crt"); if (lua_isnumber(L, -1)) cfg.crt_scanlines = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    }
    eng_renderer_set_retro(rt->renderer, &cfg);
    return 0;
}
static int l_render_sky(lua_State *L) {
    eng_renderer_set_sky(get_rt(L)->renderer,
                         eng_v3(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3)),
                         eng_v3(chk_f(L, 4), chk_f(L, 5), chk_f(L, 6)),
                         eng_v3(opt_f(L, 7, 0.12f), opt_f(L, 8, 0.11f), opt_f(L, 9, 0.10f)));
    return 0;
}
static int l_render_add_light(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    if (!lua_istable(L, 1) || rt->persist_light_count >= ENG_MAX_PERSIST_LIGHTS) return 0;
    eng_light_t l;
    memset(&l, 0, sizeof(l));
    lua_getfield(L, 1, "type");
    const char *tp = lua_isstring(L, -1) ? lua_tostring(L, -1) : "dir";
    l.type = (strcmp(tp, "point") == 0) ? ENG_LIGHT_POINT : (strcmp(tp, "spot") == 0 ? ENG_LIGHT_SPOT : ENG_LIGHT_DIR);
    lua_pop(L, 1);
    lua_getfield(L, 1, "pocket");
    if (lua_isstring(L, -1)) l.pocket_id = eng_scene_register_pocket(rt->scene, lua_tostring(L, -1));
    else if (lua_isnumber(L, -1)) l.pocket_id = (uint16_t)lua_tointeger(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 1, "pos"); l.pos = opt_tbl_v3(L, lua_gettop(L), eng_v3(0, 10, 0)); lua_pop(L, 1);
    lua_getfield(L, 1, "dir"); l.dir = opt_tbl_v3(L, lua_gettop(L), eng_v3(-0.3f, -1.0f, -0.4f)); lua_pop(L, 1);
    lua_getfield(L, 1, "color"); l.color = opt_tbl_v3(L, lua_gettop(L), eng_v3(2.0f, 1.95f, 1.85f)); lua_pop(L, 1);
    lua_getfield(L, 1, "range"); l.range = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 25.0f; lua_pop(L, 1);
    lua_getfield(L, 1, "shadow"); l.cast_shadow = lua_isnil(L, -1) ? (l.type == ENG_LIGHT_DIR) : lua_toboolean(L, -1); lua_pop(L, 1);
    l.spot_cos_inner = 0.85f;
    rt->persist_lights[rt->persist_light_count++] = l;
    return 0;
}
static int l_render_draw_sprite(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_sprite_item_t sp = {
        eng_v3(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3)),
        {opt_f(L, 4, 1.0f), opt_f(L, 5, 1.0f)},
        0.0f, {0, 0, 1, 1},
        {opt_f(L, 7, 1.0f), opt_f(L, 8, 1.0f), opt_f(L, 9, 1.0f), 1.0f},
        (uint32_t)luaL_optinteger(L, 6, 0),
        (uint16_t)luaL_optinteger(L, 10, rt->cam.pocket_id),
        ENG_SPRITE_BILLBOARD_Y
    };
    eng_renderer_submit_sprites(rt->renderer, &sp, 1);
    return 0;
}
static int l_render_draw_text(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *txt = luaL_checkstring(L, 1);
    float x = chk_f(L, 2), y = chk_f(L, 3), scl = opt_f(L, 4, 1.0f);
    eng_vec4_t col = {opt_f(L, 5, 1.0f), opt_f(L, 6, 1.0f), opt_f(L, 7, 1.0f), opt_f(L, 8, 1.0f)};
    if (rt->hud_text_count < 24) {
        size_t idx = rt->hud_text_count++;
        rt->hud_texts[idx].x = x;
        rt->hud_texts[idx].y = y;
        snprintf(rt->hud_texts[idx].text, sizeof(rt->hud_texts[idx].text), "%s", txt);
    }
    eng_mesh_data_t md;
    eng_vec3_t fwd = eng_quat_rotate_v3(rt->cam.rot, eng_v3(0.0f, 0.0f, -1.5f));
    eng_vec3_t base = eng_v3_add(rt->cam.pos, eng_v3_add(fwd, eng_v3((x - 320.0f) * 0.002f, (240.0f - y) * 0.002f, 0.0f)));
    if (eng_text_build_mesh(rt->font, txt, base, scl * 0.004f, col, &md) > 0) {
        eng_mesh_data_free(&md);
    }
    return 0;
}

static int l_asset_box(lua_State *L) {
    eng_mesh_data_t md; eng_mesh_data_init(&md);
    eng_mesh_append_box(&md, eng_v3(0, 0, 0), eng_v3(opt_f(L, 1, 1.0f), opt_f(L, 2, 1.0f), opt_f(L, 3, 1.0f)), (eng_vec4_t){1, 1, 1, 1});
    uint32_t id = eng_asset_upload_mesh(get_rt(L)->assets, "lua_box", &md);
    eng_mesh_data_free(&md);
    lua_pushinteger(L, id);
    return 1;
}
static int l_asset_sphere(lua_State *L) {
    eng_mesh_data_t md; eng_mesh_data_init(&md);
    eng_mesh_append_sphere(&md, eng_v3(0, 0, 0), opt_f(L, 1, 0.5f), (int)luaL_optinteger(L, 2, 12), (int)luaL_optinteger(L, 3, 16), (eng_vec4_t){1, 1, 1, 1});
    uint32_t id = eng_asset_upload_mesh(get_rt(L)->assets, "lua_sphere", &md);
    eng_mesh_data_free(&md);
    lua_pushinteger(L, id);
    return 1;
}
static int l_asset_cylinder(lua_State *L) {
    eng_mesh_data_t md; eng_mesh_data_init(&md);
    float r0 = opt_f(L, 1, 0.5f), r1 = opt_f(L, 2, r0), h = opt_f(L, 3, 1.0f);
    eng_mesh_append_cylinder(&md, eng_v3(0, -h * 0.5f, 0), r0, r1, h, (int)luaL_optinteger(L, 4, 12), (eng_vec4_t){1, 1, 1, 1});
    uint32_t id = eng_asset_upload_mesh(get_rt(L)->assets, "lua_cyl", &md);
    eng_mesh_data_free(&md);
    lua_pushinteger(L, id);
    return 1;
}
static int l_asset_voxel_ascii(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    int sx = (int)luaL_optinteger(L, 2, 8), sy = (int)luaL_optinteger(L, 3, 8), sz = (int)luaL_optinteger(L, 4, 8);
    float vs = opt_f(L, 5, 0.5f);
    eng_voxel_chunk_t chunk;
    eng_voxel_chunk_init(&chunk, sx, sy, sz, vs);
    const char *layers[ENG_VOXEL_MAX_DIM];
    int nl = (int)lua_objlen(L, 1);
    if (nl > ENG_VOXEL_MAX_DIM) nl = ENG_VOXEL_MAX_DIM;
    for (int i = 0; i < nl; i++) {
        lua_rawgeti(L, 1, i + 1);
        layers[i] = lua_tostring(L, -1);
        lua_pop(L, 1);
    }
    eng_voxel_from_ascii(&chunk, layers, nl);
    eng_mesh_data_t md;
    eng_voxel_build_mesh(&chunk, &md);
    uint32_t id = eng_asset_upload_mesh(get_rt(L)->assets, "lua_vox", &md);
    eng_mesh_data_free(&md);
    lua_pushinteger(L, id);
    return 1;
}
static int l_asset_load_mesh(lua_State *L) {
    lua_pushinteger(L, eng_asset_load_mesh(get_rt(L)->assets, luaL_checkstring(L, 1)));
    return 1;
}
static int l_asset_load_tex(lua_State *L) {
    lua_pushinteger(L, eng_asset_load_texture(get_rt(L)->assets, luaL_checkstring(L, 1), lua_toboolean(L, 2)));
    return 1;
}

static int l_portal_link(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_scene_update_transforms(rt->scene);
    int idx = eng_portal_link(rt->portals, rt->scene,
                              (eng_entity_t)luaL_checknumber(L, 1),
                              (eng_entity_t)luaL_checknumber(L, 2),
                              chk_f(L, 3), chk_f(L, 4), opt_f(L, 5, 1.0f),
                              lua_isnoneornil(L, 6) ? true : lua_toboolean(L, 6),
                              lua_isnoneornil(L, 7) ? true : lua_toboolean(L, 7));
    lua_pushinteger(L, idx);
    return 1;
}
static int l_portal_check_crossing(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_scene_update_transforms(rt->scene);
    uint16_t pk = (uint16_t)luaL_checkinteger(L, 1);
    eng_vec3_t p0 = eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4));
    eng_vec3_t p1 = eng_v3(chk_f(L, 5), chk_f(L, 6), chk_f(L, 7));
    eng_vec3_t v0 = eng_v3(opt_f(L, 8, 0.0f), opt_f(L, 9, 0.0f), opt_f(L, 10, 0.0f));
    eng_vec3_t warped;
    const eng_portal_t *crossed = eng_portal_check_crossing(rt->portals, rt->scene, pk, p0, p1, &warped);
    if (!crossed) {
        lua_pushnil(L);
        return 1;
    }
    eng_vec3_t wvel = eng_portal_transform_velocity(rt->portals, rt->scene, crossed, p0, v0);
    lua_pushinteger(L, crossed->dst_pocket);
    lua_pushnumber(L, warped.x); lua_pushnumber(L, warped.y); lua_pushnumber(L, warped.z);
    lua_pushnumber(L, wvel.x); lua_pushnumber(L, wvel.y); lua_pushnumber(L, wvel.z);
    return 7;
}
static int l_portal_sync_kinematics(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_scene_update_transforms(rt->scene);
    eng_portal_step_kinematics(rt->portals, rt->scene, chk_f(L, 1));
    rt->kinematics_synced = true;
    return 0;
}
static int l_portal_transform_vel(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_scene_update_transforms(rt->scene);
    const eng_portal_t *p = eng_portal_get(rt->portals, (size_t)luaL_checkinteger(L, 1));
    eng_vec3_t pos = eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4));
    eng_vec3_t vel = eng_v3(chk_f(L, 5), chk_f(L, 6), chk_f(L, 7));
    eng_vec3_t out = p ? eng_portal_transform_velocity(rt->portals, rt->scene, p, pos, vel) : vel;
    lua_pushnumber(L, out.x); lua_pushnumber(L, out.y); lua_pushnumber(L, out.z);
    return 3;
}
static int l_portal_cut_doorway(lua_State *L) {
    eng_aabb_t boxes[3];
    size_t n = eng_portal_cut_doorway_boxes(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3), chk_f(L, 4), chk_f(L, 5), boxes);
    lua_newtable(L);
    for (size_t i = 0; i < n; i++) {
        lua_newtable(L);
        lua_newtable(L);
        lua_pushnumber(L, boxes[i].min.x); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, boxes[i].min.y); lua_rawseti(L, -2, 2);
        lua_pushnumber(L, boxes[i].min.z); lua_rawseti(L, -2, 3);
        lua_setfield(L, -2, "min");
        lua_newtable(L);
        lua_pushnumber(L, boxes[i].max.x); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, boxes[i].max.y); lua_rawseti(L, -2, 2);
        lua_pushnumber(L, boxes[i].max.z); lua_rawseti(L, -2, 3);
        lua_setfield(L, -2, "max");
        lua_rawseti(L, -2, (int)(i + 1));
    }
    return 1;
}

static int l_phys_set_grav(lua_State *L) {
    eng_physics_set_gravity(get_rt(L)->physics, (uint16_t)luaL_checkinteger(L, 1),
                            eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4)));
    return 0;
}
static int l_phys_planet_grav(lua_State *L) {
    eng_planet_cfg_t pcfg = eng_planet_default_cfg((uint64_t)luaL_optnumber(L, 6, 99), opt_f(L, 7, 30.0f));
    pcfg.continent_amp = opt_f(L, 8, pcfg.continent_amp);
    eng_physics_set_planet_gravity(get_rt(L)->physics, (uint16_t)luaL_checkinteger(L, 1),
                                   eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4)),
                                   opt_f(L, 5, 9.81f), &pcfg);
    return 0;
}
static int l_phys_add_body(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_entity_t e = (eng_entity_t)luaL_checknumber(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);

    lua_getfield(L, 2, "shape");
    const char *sh = lua_isstring(L, -1) ? lua_tostring(L, -1) : "aabb";
    eng_shape_type_t st = (strcmp(sh, "sphere") == 0) ? ENG_SHAPE_SPHERE :
                          (strcmp(sh, "capsule") == 0) ? ENG_SHAPE_CAPSULE :
                          (strcmp(sh, "voxel") == 0) ? ENG_SHAPE_VOXEL_CHUNK : ENG_SHAPE_AABB;
    lua_pop(L, 1);

    lua_getfield(L, 2, "motion");
    const char *mo = lua_isstring(L, -1) ? lua_tostring(L, -1) : "dynamic";
    eng_body_motion_t mt = (strcmp(mo, "static") == 0) ? ENG_BODY_STATIC :
                           (strcmp(mo, "kinematic") == 0) ? ENG_BODY_KINEMATIC : ENG_BODY_DYNAMIC;
    lua_pop(L, 1);

    eng_body_desc_t bd = eng_body_default_desc(st, mt);
    bd.entity = e;
    const eng_transform_local_t *tr = eng_scene_get_local(rt->scene, e);
    if (tr) bd.pos = tr->pos;
    bd.pocket_id = eng_scene_get_pocket(rt->scene, e);

    lua_getfield(L, 2, "pocket"); if (lua_isnumber(L, -1)) bd.pocket_id = (uint16_t)lua_tointeger(L, -1); lua_pop(L, 1);
    lua_getfield(L, 2, "radius"); if (lua_isnumber(L, -1)) bd.radius = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_getfield(L, 2, "half_height"); if (lua_isnumber(L, -1)) bd.half_height = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_getfield(L, 2, "half_extents"); bd.half_extents = opt_tbl_v3(L, lua_gettop(L), bd.half_extents); lua_pop(L, 1);
    lua_getfield(L, 2, "vel"); bd.vel = opt_tbl_v3(L, lua_gettop(L), bd.vel); lua_pop(L, 1);
    lua_getfield(L, 2, "restitution"); if (lua_isnumber(L, -1)) bd.restitution = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_getfield(L, 2, "trigger"); if (!lua_isnil(L, -1)) bd.is_trigger = lua_toboolean(L, -1); lua_pop(L, 1);
    if (st == ENG_SHAPE_VOXEL_CHUNK) {
        lua_getfield(L, 2, "voxel_id");
        int vid = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
        if (vid >= 1 && vid <= 8 && rt->dungeon_chunk_valid[vid - 1]) {
            bd.voxel_chunk = &rt->dungeon_chunks[vid - 1];
        }
    }

    uint32_t bid = eng_physics_add_body(rt->physics, &bd);
    if (bid && rt->body_map_count < ENG_MAX_ENT_VISUALS) {
        rt->body_map[rt->body_map_count++] = (ent_body_map_t){e, bid};
    }
    lua_pushinteger(L, bid);
    return 1;
}
static int l_phys_set_vel(lua_State *L) {
    eng_body_desc_t *bd = eng_physics_get_body(get_rt(L)->physics, (uint32_t)luaL_checkinteger(L, 1));
    if (bd) bd->vel = eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4));
    return 0;
}
static int l_phys_get_vel(lua_State *L) {
    eng_body_desc_t *bd = eng_physics_get_body(get_rt(L)->physics, (uint32_t)luaL_checkinteger(L, 1));
    eng_vec3_t v = bd ? bd->vel : eng_v3(0, 0, 0);
    lua_pushnumber(L, v.x); lua_pushnumber(L, v.y); lua_pushnumber(L, v.z);
    return 3;
}
static int l_phys_move_char(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    uint32_t bid = (uint32_t)luaL_checkinteger(L, 1);
    bool grounded = false;
    eng_physics_move_character(rt->physics, rt->scene, rt->portals, bid,
                               eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4)), opt_f(L, 5, 0.35f), &grounded);
    eng_body_desc_t *bd = eng_physics_get_body(rt->physics, bid);
    if (bd && bd->entity != ENG_ENTITY_NULL) {
        eng_scene_set_local_pos(rt->scene, bd->entity, bd->pos);
        eng_scene_set_pocket(rt->scene, bd->entity, bd->pocket_id);
    }
    lua_pushboolean(L, grounded);
    return 1;
}
static int l_phys_slide_move(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    uint16_t pk = (uint16_t)luaL_checkinteger(L, 1);
    eng_vec3_t res = eng_physics_slide_xz(rt->physics, pk,
                                          eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4)),
                                          chk_f(L, 5), chk_f(L, 6), opt_f(L, 7, 0.38f));
    lua_pushnumber(L, res.x);
    lua_pushnumber(L, res.z);
    return 2;
}
static int l_phys_raycast(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_scene_update_transforms(rt->scene);
    eng_raycast_hit_t h = eng_physics_raycast(
        rt->physics, rt->scene, rt->portals, (uint16_t)luaL_checkinteger(L, 1),
        eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4)),
        eng_v3(chk_f(L, 5), chk_f(L, 6), chk_f(L, 7)),
        opt_f(L, 8, 100.0f)
    );
    if (!h.hit) { lua_pushnil(L); return 1; }
    lua_newtable(L);
    lua_pushinteger(L, h.body_id); lua_setfield(L, -2, "body_id");
    lua_pushnumber(L, (lua_Number)h.entity); lua_setfield(L, -2, "entity");
    lua_pushinteger(L, h.pocket_id); lua_setfield(L, -2, "pocket_id");
    lua_pushnumber(L, h.distance); lua_setfield(L, -2, "distance");
    lua_pushinteger(L, h.portal_hops); lua_setfield(L, -2, "portal_hops");
    lua_newtable(L);
    lua_pushnumber(L, h.point.x); lua_rawseti(L, -2, 1);
    lua_pushnumber(L, h.point.y); lua_rawseti(L, -2, 2);
    lua_pushnumber(L, h.point.z); lua_rawseti(L, -2, 3);
    lua_setfield(L, -2, "point");
    return 1;
}

static int l_proc_noise2d(lua_State *L) {
    lua_pushnumber(L, eng_noise_perlin2d(chk_f(L, 1), chk_f(L, 2), (uint64_t)luaL_optnumber(L, 3, 1337)));
    return 1;
}
static int l_proc_fbm3d(lua_State *L) {
    lua_pushnumber(L, eng_noise_fbm3d(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3),
                                      (uint64_t)luaL_optnumber(L, 4, 1337), (int)luaL_optinteger(L, 5, 4), 2.0f, 0.5f));
    return 1;
}
static int l_proc_texture(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *rec = luaL_checkstring(L, 1);
    uint64_t seed = (uint64_t)luaL_optnumber(L, 2, 42);
    int sz = (int)luaL_optinteger(L, 3, 64);
    if (sz < 8) sz = 8;
    if (sz > 256) sz = 256;
    uint8_t *rgba = (uint8_t *)malloc((size_t)(sz * sz * 4));
    if (!rgba) return 0;
    eng_procgen_texture(rec, seed, sz, rgba, NULL, NULL);
    char key[64];
    snprintf(key, sizeof(key), "ptex_%s_%llu_%d", rec, (unsigned long long)seed, sz);
    uint32_t tid = eng_asset_create_texture_rgba(rt->assets, key, sz, sz, rgba, true);
    free(rgba);
    lua_pushinteger(L, tid);
    return 1;
}
static int l_proc_dungeon(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    int w = (int)luaL_optinteger(L, 1, 24), h = (int)luaL_optinteger(L, 2, 24);
    uint64_t seed = (uint64_t)luaL_optnumber(L, 3, 42);
    const char *style = luaL_optstring(L, 4, "bsp");
    float ts = opt_f(L, 5, 2.0f), wh = opt_f(L, 6, 3.0f);

    eng_dungeon_t d;
    bool ok = (strcmp(style, "cave") == 0) ? eng_procgen_cave_cellular(&d, w, h, seed) :
              (strcmp(style, "wfc") == 0)  ? eng_procgen_wfc_grid(&d, w, h, seed) :
                                             eng_procgen_dungeon_bsp(&d, w, h, seed);
    if (!ok) return 0;

    eng_mesh_data_t md;
    eng_procgen_dungeon_build_mesh(&d, ts, wh, &md);
    uint32_t mid = eng_asset_upload_mesh(rt->assets, "proc_dungeon", &md);
    eng_mesh_data_free(&md);

    /* Build matching static wall voxel collider in runtime ring buffer */
    size_t slot = rt->dungeon_chunk_cursor++ & 7u;
    int sy = (int)ceilf(wh / fmaxf(ts, 0.1f));
    if (sy < 1) sy = 1;
    rt->dungeon_chunk_valid[slot] = (d.width <= ENG_VOXEL_MAX_DIM && d.height <= ENG_VOXEL_MAX_DIM && sy <= ENG_VOXEL_MAX_DIM);
    if (rt->dungeon_chunk_valid[slot]) eng_voxel_chunk_init(&rt->dungeon_chunks[slot], d.width, sy, d.height, ts);
    int key_gx = d.has_key_lock ? d.key_x : d.entrance_x;
    int key_gy = d.has_key_lock ? d.key_y : d.entrance_y;
    int best_key_d = -1;

    lua_newtable(L);
    lua_pushinteger(L, mid); lua_setfield(L, -2, "mesh_id");
    lua_pushinteger(L, rt->dungeon_chunk_valid[slot] ? (lua_Integer)(slot + 1u) : 0); lua_setfield(L, -2, "voxel_id");
    lua_pushinteger(L, d.width); lua_setfield(L, -2, "width");
    lua_pushinteger(L, d.height); lua_setfield(L, -2, "height");
    lua_pushnumber(L, ts); lua_setfield(L, -2, "tile_size");
    lua_pushnumber(L, ((float)d.entrance_x + 0.5f) * ts); lua_setfield(L, -2, "start_x");
    lua_pushnumber(L, ((float)d.entrance_y + 0.5f) * ts); lua_setfield(L, -2, "start_z");
    lua_pushnumber(L, ((float)d.exit_x + 0.5f) * ts); lua_setfield(L, -2, "exit_x");
    lua_pushnumber(L, ((float)d.exit_y + 0.5f) * ts); lua_setfield(L, -2, "exit_z");

    /* Flood-fill from entrance so d.walkable & key_x/key_z exclude disconnected cave pockets */
    int ncells = d.width * d.height;
    uint8_t *reach = (uint8_t *)calloc((size_t)ncells, 1);
    int *q = (int *)malloc((size_t)ncells * sizeof(int));
    if (reach && q && d.entrance_x >= 0 && d.entrance_x < d.width && d.entrance_y >= 0 && d.entrance_y < d.height) {
        int qh = 0, qt = 0;
        int start_i = d.entrance_y * d.width + d.entrance_x;
        reach[start_i] = 1;
        q[qt++] = start_i;
        static const int k_dx[4] = {1, -1, 0, 0}, k_dy[4] = {0, 0, 1, -1};
        while (qh < qt) {
            int cur = q[qh++];
            int cx = cur % d.width, cy = cur / d.width;
            for (int k = 0; k < 4; k++) {
                int nx = cx + k_dx[k], ny = cy + k_dy[k];
                if (nx < 0 || nx >= d.width || ny < 0 || ny >= d.height) continue;
                int ni = ny * d.width + nx;
                if (!reach[ni] && eng_dungeon_get(&d, nx, ny) != ENG_TILE_WALL) {
                    reach[ni] = 1;
                    q[qt++] = ni;
                }
            }
        }
    }

    lua_newtable(L);
    int idx = 1;
    for (int gy = 0; gy < d.height; gy++) {
        for (int gx = 0; gx < d.width; gx++) {
            bool is_wall = (eng_dungeon_get(&d, gx, gy) == ENG_TILE_WALL);
            bool is_reach = reach ? (reach[gy * d.width + gx] != 0) : !is_wall;
            if (is_wall && rt->dungeon_chunk_valid[slot]) {
                for (int vy = 0; vy < sy; vy++) eng_voxel_set(&rt->dungeon_chunks[slot], gx, vy, gy, 1u);
            } else if (is_reach && !d.has_key_lock) {
                int ds = abs(gx - d.entrance_x) + abs(gy - d.entrance_y);
                int de = abs(gx - d.exit_x) + abs(gy - d.exit_y);
                int score = (ds < de) ? ds : de;
                if (score > best_key_d) { best_key_d = score; key_gx = gx; key_gy = gy; }
            }
            lua_pushinteger(L, is_reach ? 1 : 0);
            lua_rawseti(L, -2, idx++);
        }
    }
    free(reach);
    free(q);
    lua_setfield(L, -2, "walkable");
    lua_pushnumber(L, ((float)key_gx + 0.5f) * ts); lua_setfield(L, -2, "key_x");
    lua_pushnumber(L, ((float)key_gy + 0.5f) * ts); lua_setfield(L, -2, "key_z");
    lua_pushboolean(L, eng_procgen_dungeon_is_solvable(&d)); lua_setfield(L, -2, "solvable");
    eng_dungeon_free(&d);
    return 1;
}
static int l_proc_planet(lua_State *L) {
    eng_planet_cfg_t cfg = eng_planet_default_cfg((uint64_t)luaL_optnumber(L, 1, 99), opt_f(L, 2, 30.0f));
    cfg.subdivisions = (int)luaL_optinteger(L, 3, 20);
    cfg.sea_level = opt_f(L, 4, 0.0f);
    eng_mesh_data_t md;
    eng_procgen_planet_mesh(&cfg, &md);
    uint32_t mid = eng_asset_upload_mesh(get_rt(L)->assets, "proc_planet", &md);
    eng_mesh_data_free(&md);
    lua_pushinteger(L, mid);
    return 1;
}
static int l_proc_tree(lua_State *L) {
    eng_mesh_data_t md;
    eng_procgen_tree_mesh((uint64_t)luaL_optnumber(L, 1, 77), (int)luaL_optinteger(L, 2, 2),
                          opt_f(L, 3, 3.0f), opt_f(L, 4, 0.22f), &md);
    uint32_t mid = eng_asset_upload_mesh(get_rt(L)->assets, "proc_tree", &md);
    eng_mesh_data_free(&md);
    lua_pushinteger(L, mid);
    return 1;
}
static int l_proc_scatter(lua_State *L) {
    eng_vec2_t pts[128];
    size_t max_n = (size_t)luaL_optinteger(L, 5, 32);
    if (max_n > 128) max_n = 128;
    size_t n = eng_procgen_poisson_2d((uint64_t)luaL_optnumber(L, 1, 42), chk_f(L, 2), chk_f(L, 3), chk_f(L, 4), pts, max_n);
    lua_newtable(L);
    for (size_t i = 0; i < n; i++) {
        lua_newtable(L);
        lua_pushnumber(L, pts[i].x); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, pts[i].y); lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, (int)(i + 1));
    }
    return 1;
}
static int l_proc_animal(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_entity_t e = (eng_entity_t)luaL_checknumber(L, 1);
    uint64_t seed = (uint64_t)luaL_optnumber(L, 2, 7);
    const char *arch_s = luaL_optstring(L, 3, "quadruped");
    eng_animal_archetype_t arch =
        (strcmp(arch_s, "biped") == 0) ? ENG_ANIMAL_BIPED :
        (strcmp(arch_s, "avian") == 0) ? ENG_ANIMAL_AVIAN :
        (strcmp(arch_s, "insectoid") == 0) ? ENG_ANIMAL_INSECTOID :
        (strcmp(arch_s, "aquatic") == 0) ? ENG_ANIMAL_AQUATIC :
        (strcmp(arch_s, "serpentine") == 0) ? ENG_ANIMAL_SERPENTINE : ENG_ANIMAL_QUADRUPED;

    eng_animal_asset_t aa;
    if (!eng_procgen_animal(seed, arch, &aa)) return 0;
    uint32_t mid = eng_asset_upload_mesh(rt->assets, "proc_animal", &aa.mesh);
    uint32_t tid = eng_asset_create_texture_rgba(rt->assets, "proc_coat", 64, 64, aa.coat_rgba, true);

    ent_visual_t *v = find_or_alloc_visual(rt, e);
    if (v) {
        v->mesh_id = mid;
        v->tex_id = tid;
        v->cast_shadow = true;
        v->has_rig = true;
        v->skel = aa.skeleton;
        v->gait = aa.gait;
        v->gait_speed = 1.0f;
        eng_anim_pose_reset(&v->skel, &v->pose);
        eng_anim_compute_skin_matrices(&v->skel, &v->pose);
    }
    lua_newtable(L);
    lua_pushinteger(L, mid); lua_setfield(L, -2, "mesh_id");
    lua_pushnumber(L, aa.height); lua_setfield(L, -2, "height");
    lua_pushnumber(L, aa.length); lua_setfield(L, -2, "length");
    eng_animal_asset_free(&aa);
    return 1;
}
static int l_proc_person(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_entity_t e = (eng_entity_t)luaL_checknumber(L, 1);
    uint64_t seed = (uint64_t)luaL_optnumber(L, 2, 11);
    eng_person_asset_t pa;
    if (!eng_procgen_person(seed, &pa)) return 0;
    uint32_t mid = eng_asset_upload_mesh(rt->assets, "proc_person", &pa.mesh);

    ent_visual_t *v = find_or_alloc_visual(rt, e);
    if (v) {
        v->mesh_id = mid;
        v->cast_shadow = true;
        v->has_rig = true;
        v->skel = pa.skeleton;
        v->gait = pa.gait;
        v->gait_speed = 1.0f;
        eng_anim_pose_reset(&v->skel, &v->pose);
        eng_anim_compute_skin_matrices(&v->skel, &v->pose);
    }
    lua_newtable(L);
    lua_pushstring(L, pa.name); lua_setfield(L, -2, "name");
    lua_pushstring(L, pa.role); lua_setfield(L, -2, "role");
    lua_pushnumber(L, pa.height); lua_setfield(L, -2, "height");
    eng_person_asset_free(&pa);
    return 1;
}

static int l_audio_synth(lua_State *L) {
    const char *w = luaL_optstring(L, 1, "square");
    eng_synth_wave_t wt = (strcmp(w, "saw") == 0) ? ENG_WAVE_SAW :
                          (strcmp(w, "triangle") == 0) ? ENG_WAVE_TRIANGLE :
                          (strcmp(w, "sine") == 0) ? ENG_WAVE_SINE :
                          (strcmp(w, "noise") == 0) ? ENG_WAVE_NOISE : ENG_WAVE_SQUARE;
    eng_synth_desc_t sd = eng_synth_default_desc(wt, opt_f(L, 2, 440.0f), opt_f(L, 3, 0.15f));
    sd.freq_end_hz = opt_f(L, 4, sd.freq_start_hz);
    lua_pushinteger(L, eng_audio_synth_retro(get_rt(L)->audio, &sd));
    return 1;
}
static int l_audio_play(lua_State *L) {
    eng_voice_desc_t vd = eng_voice_default_desc((uint32_t)luaL_checkinteger(L, 1));
    if (!lua_isnoneornil(L, 2)) {
        vd.spatial_3d = true;
        vd.pos = eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4));
        vd.pocket_id = (uint16_t)luaL_optinteger(L, 5, get_rt(L)->cam.pocket_id);
    }
    lua_pushinteger(L, eng_audio_play(get_rt(L)->audio, &vd));
    return 1;
}

static int l_ai_set_grid(lua_State *L) {
    uint16_t pk = (uint16_t)luaL_checkinteger(L, 1);
    float cs = chk_f(L, 2);
    int w = (int)luaL_checkinteger(L, 3), d = (int)luaL_checkinteger(L, 4);
    uint8_t *walk = (uint8_t *)malloc((size_t)(w * d));
    if (!walk) return 0;
    memset(walk, 1, (size_t)(w * d));
    if (lua_istable(L, 5)) {
        for (int i = 0; i < w * d; i++) {
            lua_rawgeti(L, 5, i + 1);
            if (!lua_isnil(L, -1)) walk[i] = (lua_tointeger(L, -1) != 0) ? 1u : 0u;
            lua_pop(L, 1);
        }
    }
    lua_pushboolean(L, eng_nav_set_grid(get_rt(L)->nav, pk, eng_v3(0, 0, 0), cs, w, d, walk));
    free(walk);
    return 1;
}
static int l_ai_find_path(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_scene_update_transforms(rt->scene);
    eng_nav_sync_portals(rt->nav, rt->scene, rt->portals);
    eng_vec3_t wps[32];
    uint16_t pks[32];
    size_t n = eng_ai_find_path(rt->nav,
                                (uint16_t)luaL_checkinteger(L, 1), eng_v3(chk_f(L, 2), chk_f(L, 3), chk_f(L, 4)),
                                (uint16_t)luaL_checkinteger(L, 5), eng_v3(chk_f(L, 6), chk_f(L, 7), chk_f(L, 8)),
                                wps, pks, 32);
    lua_newtable(L);
    for (size_t i = 0; i < n; i++) {
        lua_newtable(L);
        lua_pushnumber(L, wps[i].x); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, wps[i].y); lua_rawseti(L, -2, 2);
        lua_pushnumber(L, wps[i].z); lua_rawseti(L, -2, 3);
        lua_pushinteger(L, pks[i]); lua_rawseti(L, -2, 4);
        lua_rawseti(L, -2, (int)(i + 1));
    }
    return 1;
}

static int l_save_write(lua_State *L) {
    const char *slot = luaL_checkstring(L, 1);
    size_t len = 0;
    const char *data = luaL_checklstring(L, 2, &len);
    lua_pushboolean(L, eng_save_write(get_rt(L)->vfs, slot, 1u, data, len));
    return 1;
}
static int l_save_read(lua_State *L) {
    size_t len = 0;
    char *data = (char *)eng_save_read(get_rt(L)->vfs, luaL_checkstring(L, 1), 1u, &len);
    if (!data) { lua_pushnil(L); return 1; }
    lua_pushlstring(L, data, len);
    free(data);
    return 1;
}

static int l_i18n_set(lua_State *L) {
    lua_pushboolean(L, eng_i18n_set_lang(get_rt(L)->i18n, luaL_checkstring(L, 1)));
    return 1;
}
static int l_i18n_t(lua_State *L) {
    lua_pushstring(L, eng_i18n_get(get_rt(L)->i18n, luaL_checkstring(L, 1)));
    return 1;
}

static int l_mod_on(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *ev = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_rawgeti(L, LUA_REGISTRYINDEX, rt->mod_hooks_ref);
    lua_getfield(L, -1, ev);
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, ev);
    }
    int n = (int)lua_objlen(L, -1);
    lua_pushvalue(L, 2);
    lua_rawseti(L, -2, n + 1);
    lua_pop(L, 2);
    return 0;
}
static int l_mod_emit(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *ev = luaL_checkstring(L, 1);
    lua_rawgeti(L, LUA_REGISTRYINDEX, rt->mod_hooks_ref);
    lua_getfield(L, -1, ev);
    if (lua_istable(L, -1)) {
        int n = (int)lua_objlen(L, -1);
        for (int i = 1; i <= n; i++) {
            lua_rawgeti(L, -1, i);
            lua_pushvalue(L, 2);
            lua_pcall(L, 1, 0, 0);
        }
    }
    lua_pop(L, 2);
    return 0;
}

/* Additional ProcGen (noise3d, voronoi2d, ridged3d, warp3d, scatter_sphere), Terrain, Particles, Anim & Net bindings */
static int l_proc_noise3d(lua_State *L) {
    lua_pushnumber(L, eng_noise_perlin3d(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3), (uint64_t)luaL_optnumber(L, 4, 1337)));
    return 1;
}
static int l_proc_voronoi2d(lua_State *L) {
    uint32_t cid = 0;
    float d = eng_noise_voronoi2d(chk_f(L, 1), chk_f(L, 2), (uint64_t)luaL_optnumber(L, 3, 1337), &cid);
    lua_pushnumber(L, d);
    lua_pushinteger(L, (lua_Integer)cid);
    return 2;
}
static int l_proc_ridged3d(lua_State *L) {
    lua_pushnumber(L, eng_noise_ridged3d(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3),
                                         (uint64_t)luaL_optnumber(L, 4, 1337), (int)luaL_optinteger(L, 5, 4)));
    return 1;
}
static int l_proc_warp3d(lua_State *L) {
    lua_pushnumber(L, eng_noise_domain_warp3d(chk_f(L, 1), chk_f(L, 2), chk_f(L, 3),
                                              (uint64_t)luaL_optnumber(L, 4, 1337), opt_f(L, 5, 1.5f)));
    return 1;
}
static int l_proc_scatter_sphere(lua_State *L) {
    uint64_t seed = (uint64_t)luaL_checknumber(L, 1);
    float rad = chk_f(L, 2), min_d = chk_f(L, 3);
    int max_p = (int)luaL_optinteger(L, 4, 64);
    if (max_p < 1) max_p = 1;
    if (max_p > 512) max_p = 512;
    eng_vec3_t *pts = (eng_vec3_t *)malloc((size_t)max_p * sizeof(eng_vec3_t));
    if (!pts) return 0;
    size_t n = eng_procgen_poisson_sphere(seed, rad, min_d, pts, (size_t)max_p);
    lua_newtable(L);
    for (size_t i = 0; i < n; i++) {
        lua_newtable(L);
        lua_pushnumber(L, pts[i].x); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, pts[i].y); lua_rawseti(L, -2, 2);
        lua_pushnumber(L, pts[i].z); lua_rawseti(L, -2, 3);
        lua_rawseti(L, -2, (int)(i + 1));
    }
    free(pts);
    return 1;
}

static int l_terrain_create(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    if (rt->terrain_count >= 8) return luaL_error(L, "Max 8 active terrains reached");
    int gw = (int)luaL_optinteger(L, 1, 33), gd = (int)luaL_optinteger(L, 2, 33);
    float cs = opt_f(L, 3, 1.0f);
    uint64_t seed = (uint64_t)luaL_optnumber(L, 4, 42);
    float max_h = opt_f(L, 5, 6.0f), freq = opt_f(L, 6, 0.06f);
    size_t idx = rt->terrain_count++;
    if (!eng_terrain_init(&rt->terrains[idx], gw, gd, cs, NULL)) { rt->terrain_count--; return 0; }
    eng_terrain_generate_hills(&rt->terrains[idx], seed, max_h, freq);
    eng_mesh_data_t md;
    eng_terrain_build_chunk_mesh(&rt->terrains[idx], 0, 0, gw - 1, gd - 1, 1, 1.0f, &md);
    uint32_t mid = eng_asset_upload_mesh(rt->assets, "lua_terrain", &md);
    eng_mesh_data_free(&md);
    lua_pushinteger(L, (lua_Integer)(idx + 1));
    lua_pushinteger(L, (lua_Integer)mid);
    return 2;
}
static int l_terrain_height(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    int tid = (int)luaL_checkinteger(L, 1) - 1;
    if (tid < 0 || (size_t)tid >= rt->terrain_count) { lua_pushnumber(L, 0.0); return 1; }
    lua_pushnumber(L, eng_terrain_sample_height(&rt->terrains[tid], chk_f(L, 2), chk_f(L, 3)));
    return 1;
}

static int l_part_create(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    if (rt->emitter_count >= 16) return luaL_error(L, "Max 16 particle emitters reached");
    eng_emitter_cfg_t cfg = eng_emitter_default_cfg();
    uint64_t seed = 777u;
    size_t cap = 128;
    if (lua_istable(L, 1)) {
        lua_getfield(L, 1, "pos"); cfg.origin = opt_tbl_v3(L, lua_gettop(L), cfg.origin); lua_pop(L, 1);
        lua_getfield(L, 1, "dir"); cfg.dir = opt_tbl_v3(L, lua_gettop(L), cfg.dir); lua_pop(L, 1);
        lua_getfield(L, 1, "rate"); if (lua_isnumber(L, -1)) cfg.spawn_rate = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_getfield(L, 1, "pocket"); if (lua_isnumber(L, -1)) cfg.pocket_id = (uint16_t)lua_tointeger(L, -1); lua_pop(L, 1);
        lua_getfield(L, 1, "tex"); if (lua_isnumber(L, -1)) cfg.tex_id = (uint32_t)lua_tointeger(L, -1); lua_pop(L, 1);
        lua_getfield(L, 1, "seed"); if (lua_isnumber(L, -1)) seed = (uint64_t)lua_tonumber(L, -1); lua_pop(L, 1);
    }
    eng_emitter_t *em = eng_emitter_create(cap, seed, &cfg);
    if (!em) return 0;
    rt->emitters[rt->emitter_count++] = em;
    lua_pushinteger(L, (lua_Integer)rt->emitter_count);
    return 1;
}
static int l_part_burst(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    int id = (int)luaL_checkinteger(L, 1) - 1;
    if (id < 0 || (size_t)id >= rt->emitter_count) { lua_pushinteger(L, 0); return 1; }
    lua_pushinteger(L, (lua_Integer)eng_emitter_burst(rt->emitters[id], (size_t)luaL_optinteger(L, 2, 16)));
    return 1;
}
static int l_part_alive(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    int id = (int)luaL_checkinteger(L, 1) - 1;
    if (id < 0 || (size_t)id >= rt->emitter_count) { lua_pushinteger(L, 0); return 1; }
    lua_pushinteger(L, (lua_Integer)eng_emitter_alive_count(rt->emitters[id]));
    return 1;
}

static int l_anim_set_gait_speed(lua_State *L) {
    ent_visual_t *v = find_or_alloc_visual(get_rt(L), (eng_entity_t)luaL_checknumber(L, 1));
    if (v) v->gait_speed = chk_f(L, 2);
    return 0;
}
static int l_anim_ik_two_bone(lua_State *L) {
    ent_visual_t *v = find_or_alloc_visual(get_rt(L), (eng_entity_t)luaL_checknumber(L, 1));
    if (!v || !v->has_rig) { lua_pushboolean(L, 0); return 1; }
    bool ok = eng_anim_ik_two_bone(&v->skel, &v->pose,
                                   (uint32_t)luaL_checkinteger(L, 2), (uint32_t)luaL_checkinteger(L, 3), (uint32_t)luaL_checkinteger(L, 4),
                                   eng_v3(chk_f(L, 5), chk_f(L, 6), chk_f(L, 7)), eng_v3(0.0f, 0.0f, -1.0f));
    if (ok) eng_anim_compute_skin_matrices(&v->skel, &v->pose);
    lua_pushboolean(L, ok);
    return 1;
}
static int l_anim_ik_fabrik(lua_State *L) {
    ent_visual_t *v = find_or_alloc_visual(get_rt(L), (eng_entity_t)luaL_checknumber(L, 1));
    luaL_checktype(L, 2, LUA_TTABLE);
    if (!v || !v->has_rig) { lua_pushboolean(L, 0); return 1; }
    uint32_t chain[16];
    int n = (int)lua_objlen(L, 2);
    if (n > 16) n = 16;
    for (int i = 0; i < n; i++) { lua_rawgeti(L, 2, i + 1); chain[i] = (uint32_t)lua_tointeger(L, -1); lua_pop(L, 1); }
    bool ok = eng_anim_ik_fabrik(&v->skel, &v->pose, chain, (size_t)n,
                                 eng_v3(chk_f(L, 3), chk_f(L, 4), chk_f(L, 5)), (int)luaL_optinteger(L, 6, 8));
    if (ok) eng_anim_compute_skin_matrices(&v->skel, &v->pose);
    lua_pushboolean(L, ok);
    return 1;
}

static eng_net_transport_t parse_net_tr(const char *s) {
    if (s && strcmp(s, "udp") == 0) return ENG_NET_UDP;
    if (s && strcmp(s, "websocket") == 0) return ENG_NET_WEBSOCKET;
    return ENG_NET_LOOPBACK;
}
static int l_net_start_loopback(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_net_destroy(rt->net_srv);
    eng_net_destroy(rt->net_cli);
    rt->net_srv = eng_net_create(ENG_NET_LOOPBACK, 0);
    rt->net_cli = eng_net_create(ENG_NET_LOOPBACK, 0);
    lua_pushboolean(L, eng_net_connect_loopback(rt->net_srv, rt->net_cli));
    return 1;
}
static int l_net_host(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_net_destroy(rt->net_srv);
    rt->net_srv = eng_net_create(parse_net_tr(luaL_optstring(L, 1, "udp")), (uint16_t)luaL_optinteger(L, 2, 0));
    lua_pushinteger(L, rt->net_srv ? eng_net_bound_port(rt->net_srv) : 0);
    return 1;
}
static int l_net_connect(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    eng_net_destroy(rt->net_cli);
    rt->net_cli = eng_net_create(parse_net_tr(luaL_optstring(L, 1, "udp")), 0);
    lua_pushboolean(L, rt->net_cli && eng_net_connect_remote(rt->net_cli, luaL_optstring(L, 2, "127.0.0.1"), (uint16_t)luaL_optinteger(L, 3, 7777)));
    return 1;
}
static int l_net_send(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *role = luaL_checkstring(L, 1);
    size_t len = 0;
    const char *msg = luaL_checklstring(L, 2, &len);
    bool rel = lua_isnoneornil(L, 3) ? true : lua_toboolean(L, 3);
    eng_net_peer_t *p = (strcmp(role, "server") == 0) ? rt->net_srv : rt->net_cli;
    lua_pushboolean(L, p && eng_net_send(p, rel ? ENG_CHAN_RELIABLE : ENG_CHAN_UNRELIABLE, msg, len));
    return 1;
}
static int l_net_poll(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    const char *role = luaL_checkstring(L, 1);
    eng_net_peer_t *p = (strcmp(role, "server") == 0) ? rt->net_srv : rt->net_cli;
    char buf[1400];
    size_t n = p ? eng_net_poll(p, buf, sizeof(buf), NULL) : 0;
    if (n == 0) { lua_pushnil(L); return 1; }
    lua_pushlstring(L, buf, n);
    return 1;
}
static int l_net_sync_scene(lua_State *L) {
    eng_runtime_t *rt = get_rt(L);
    if (!rt->net_srv || !rt->net_cli) { lua_pushboolean(L, 0); return 1; }
    if (!eng_net_send_scene_snapshot(rt->net_srv, rt->scene)) { lua_pushboolean(L, 0); return 1; }
    uint8_t snap[1400];
    size_t n = eng_net_poll(rt->net_cli, snap, sizeof(snap), NULL);
    lua_pushboolean(L, n > 0 && eng_net_apply_scene_snapshot(rt->scene, snap, n));
    return 1;
}

/* Master single-source C API registration table (drives BOTH runtime bindings AND lua/eng_api.lua!) */
static const lua_fn_desc_t k_api_table[] = {
    {"log",       "info",             l_log_info,              "(msg: string)", "Log informational message (deduplicated)"},
    {"log",       "warn",             l_log_warn,              "(msg: string)", "Log warning message"},
    {"log",       "error",            l_log_error,             "(msg: string)", "Log error message"},
    {"math",      "seed",             l_math_seed,             "(seed: integer)", "Seed deterministic xoshiro128++ PRNG"},
    {"math",      "rand",             l_math_rand,             "(): number", "Return deterministic float in [0, 1)"},
    {"math",      "range",            l_math_range,            "(lo: number, hi: number): number", "Return deterministic float in [lo, hi]"},
    {"math",      "clamp",            l_math_clamp,            "(x: number, lo: number, hi: number): number", "Clamp scalar"},
    {"math",      "dist3",            l_math_dist3,            "(x1: number, y1: number, z1: number, x2: number, y2: number, z2: number): number", "3D Euclidean distance"},
    {"input",     "down",             l_input_down,            "(action: string): boolean", "True while logical action is held"},
    {"input",     "pressed",          l_input_pressed,         "(action: string): boolean", "True on rising edge of logical action"},
    {"input",     "axis2d",           l_input_axis,            "(neg_x: string, pos_x: string, neg_y: string, pos_y: string): number, number", "2D normalized input vector"},
    {"input",     "inject",           l_input_inject,          "(action: string, down: boolean)", "Inject deterministic virtual input for playtests"},
    {"input",     "set_mouse_lock",   l_input_set_mouse_lock,  "(locked: boolean): boolean", "Request or release relative mouse pointer lock (ESC unlocks)"},
    {"input",     "is_mouse_locked",  l_input_is_mouse_locked, "(): boolean", "True while mouse pointer lock is active"},
    {"input",     "mouse_delta",      l_input_mouse_delta,     "(): number, number", "Relative mouse look delta (dx, dy) while locked/dragging/touch"},
    {"xr",        "set_mode",         l_xr_set_mode,           "(mode: string)", "Set WebXR mode: diorama|cockpit|first_person|6dof"},
    {"xr",        "is_active",        l_xr_active,             "(): boolean", "True while Stereo WebXR session is active"},
    {"scene",     "spawn",            l_scene_spawn,           "(name?: string): number", "Spawn entity (+X right, +Y up, -Z forward)"},
    {"scene",     "despawn",          l_scene_despawn,         "(ent: number): boolean", "Destroy entity and attached physics/visuals"},
    {"scene",     "find",             l_scene_find,            "(name: string): number|nil", "Find entity by name"},
    {"scene",     "set_pos",          l_scene_set_pos,         "(ent: number, x: number, y: number, z: number)", "Set local position (NaN-trapped)"},
    {"scene",     "get_pos",          l_scene_get_pos,         "(ent: number): number, number, number", "Get local position"},
    {"scene",     "set_rot_deg",      l_scene_set_rot_deg,     "(ent: number, pitch: number, yaw: number, roll: number)", "Set Euler rotation in degrees"},
    {"scene",     "set_scale",        l_scene_set_scale,       "(ent: number, sx: number, sy: number, sz: number)", "Set local scale"},
    {"scene",     "set_parent",       l_scene_set_parent,      "(child: number, parent?: number)", "Attach child entity to parent hierarchy"},
    {"scene",     "register_pocket",  l_scene_reg_pocket,      "(name: string): integer", "Register/lookup isolated pocket space ID"},
    {"scene",     "set_pocket",       l_scene_set_pocket,      "(ent: number, pocket: integer|string)", "Assign entity to pocket space"},
    {"scene",     "get_pocket",       l_scene_get_pocket,      "(ent: number): integer", "Return entity pocket_id"},
    {"scene",     "set_mesh",         l_scene_set_mesh,        "(ent: number, mesh_id: integer, opts?: table)", "Attach mesh & PBR/retro material to entity"},
    {"scene",     "dump_json",        l_scene_dump_json,       "(): string", "Compact JSON entity snapshot for diagnostics"},
    {"camera",    "set",              l_cam_set,               "(x: number, y: number, z: number, pitch?: number, yaw?: number, roll?: number, pocket?: integer)", "Set active camera pose & pocket"},
    {"camera",    "look_at",          l_cam_look_at,           "(ex: number, ey: number, ez: number, tx: number, ty: number, tz: number, pocket?: integer)", "Aim camera at 3D target"},
    {"camera",    "get",              l_cam_get,               "(): number, number, number, integer", "Return camera x, y, z, pocket_id"},
    {"camera",    "fps_steer",        l_cam_fps_steer,         "(yaw: number, pitch: number, speed: number, dt: number, sens?: number): number, number, number, number, number, number", "Mouse-locked yaw/pitch look + camera-relative WASD forward/strafe step"},
    {"render",    "set_pipeline",     l_render_pipeline,       "(mode: string)", "Switch forward or deferred pipeline"},
    {"render",    "set_retro",        l_render_retro,          "(ps1_or_table: boolean|table)", "Configure PS1 vertex snap, Bayer dither, fog & CRT"},
    {"render",    "set_sky",          l_render_sky,            "(zx: number, zy: number, zz: number, hx: number, hy: number, hz: number)", "Set procedural skybox gradient"},
    {"render",    "add_light",        l_render_add_light,      "(desc: table)", "Add directional, point, or spot light to pocket"},
    {"render",    "draw_sprite",      l_render_draw_sprite,    "(x: number, y: number, z: number, w?: number, h?: number, tex?: integer)", "Submit billboard sprite"},
    {"render",    "draw_text",        l_render_draw_text,      "(text: string, x: number, y: number, scale?: number, r?: number, g?: number, b?: number, a?: number)", "Draw UTF-8 SDF text"},
    {"asset",     "box",              l_asset_box,             "(w?: number, h?: number, d?: number): integer", "Create procedural box GPU mesh"},
    {"asset",     "sphere",           l_asset_sphere,          "(radius?: number, rings?: integer, sectors?: integer): integer", "Create procedural sphere GPU mesh"},
    {"asset",     "cylinder",         l_asset_cylinder,        "(r_bot?: number, r_top?: number, height?: number, slices?: integer): integer", "Create cylinder/cone GPU mesh"},
    {"asset",     "voxel_ascii",      l_asset_voxel_ascii,     "(layers: table, sx?: integer, sy?: integer, sz?: integer, vs?: number): integer", "Build greedy-meshed AO voxel chunk from ASCII layers"},
    {"asset",     "load_mesh",        l_asset_load_mesh,       "(vpath: string): integer", "Load .gltf/.glb/.obj mesh from VFS"},
    {"asset",     "load_texture",     l_asset_load_tex,        "(vpath: string, nearest?: boolean): integer", "Load PNG/JPG texture from VFS"},
    {"portal",    "link",             l_portal_link,           "(src_ent: number, dst_ent: number, w: number, h: number, scale_ratio?: number, passable?: boolean, bidir?: boolean): integer", "Link portals across pockets"},
    {"portal",    "check_crossing",   l_portal_check_crossing, "(pocket: integer, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, vx?: number, vy?: number, vz?: number): integer|nil, number, number, number, number, number, number", "Test moving-portal threshold crossing and Galilean velocity warp"},
    {"portal",    "sync_kinematics",  l_portal_sync_kinematics,"(dt: number)", "Step moving-vehicle portal world transforms and frame velocities"},
    {"portal",    "transform_vel",    l_portal_transform_vel,  "(portal_idx: integer, x: number, y: number, z: number, vx: number, vy: number, vz: number): number, number, number", "Transform velocity across moving/rotating portal"},
    {"portal",    "cut_doorway",      l_portal_cut_doorway,    "(wall_w: number, wall_h: number, thick: number, door_w: number, door_h: number): table", "Split wall collider around doorway"},
    {"physics",   "set_gravity",      l_phys_set_grav,         "(pocket: integer, gx: number, gy: number, gz: number)", "Set linear pocket gravity"},
    {"physics",   "set_planet_gravity", l_phys_planet_grav,    "(pocket: integer, cx: number, cy: number, cz: number, g?: number, seed?: integer, radius?: number)", "Enable radial spherical planet gravity"},
    {"physics",   "add_body",         l_phys_add_body,         "(ent: number, desc: table): integer", "Attach rigid/static/kinematic collider to entity"},
    {"physics",   "set_vel",          l_phys_set_vel,          "(body_id: integer, vx: number, vy: number, vz: number)", "Set linear body velocity"},
    {"physics",   "get_vel",          l_phys_get_vel,          "(body_id: integer): number, number, number", "Get linear body velocity"},
    {"physics",   "move_character",   l_phys_move_char,        "(body_id: integer, dx: number, dy: number, dz: number, step_h?: number): boolean", "Stair-stepping & portal-aware character move"},
    {"physics",   "slide_move",       l_phys_slide_move,       "(pocket: integer, x: number, y: number, z: number, dx: number, dz: number, radius?: number): number, number", "Slide XZ position against static AABB/voxel walls in pocket"},
    {"physics",   "raycast",          l_phys_raycast,          "(pocket: integer, ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, max_d?: number): table|nil", "Cross-portal 3D raycast"},
    {"procgen",   "noise2d",          l_proc_noise2d,          "(x: number, y: number, seed?: integer): number", "Seeded 2D Perlin noise"},
    {"procgen",   "noise3d",          l_proc_noise3d,          "(x: number, y: number, z: number, seed?: integer): number", "Seeded 3D Perlin noise"},
    {"procgen",   "voronoi2d",        l_proc_voronoi2d,        "(x: number, y: number, seed?: integer): number, integer", "Seeded 2D Worley/Voronoi distance and cell ID"},
    {"procgen",   "fbm3d",            l_proc_fbm3d,            "(x: number, y: number, z: number, seed?: integer, octaves?: integer): number", "Seeded 3D fractal Brownian motion"},
    {"procgen",   "ridged3d",         l_proc_ridged3d,         "(x: number, y: number, z: number, seed?: integer, octaves?: integer): number", "Seeded 3D ridged multifractal noise"},
    {"procgen",   "warp3d",           l_proc_warp3d,           "(x: number, y: number, z: number, seed?: integer, warp_amp?: number): number", "Seeded 3D domain-warped noise"},
    {"procgen",   "texture",          l_proc_texture,          "(recipe: string, seed?: integer, size?: integer): integer", "Synthesize tileable PBR/retro texture"},
    {"procgen",   "dungeon",          l_proc_dungeon,          "(w?: integer, h?: integer, seed?: integer, style?: string, tile_sz?: number, wall_h?: number): table", "Generate solvable BSP/cave/WFC dungeon"},
    {"procgen",   "planet",           l_proc_planet,           "(seed?: integer, radius?: number, subdiv?: integer, sea_level?: number): integer", "Generate seamless 3D cube-sphere planet"},
    {"procgen",   "tree",             l_proc_tree,             "(seed?: integer, depth?: integer, height?: number, radius?: number): integer", "Generate 3D L-system tree mesh"},
    {"procgen",   "scatter_poisson",  l_proc_scatter,          "(seed: integer, w: number, h: number, min_dist: number, max_pts?: integer): table", "Overlap-free 2D Poisson-disk scatter"},
    {"procgen",   "scatter_sphere",   l_proc_scatter_sphere,   "(seed: integer, radius: number, min_chord: number, max_pts?: integer): table", "Overlap-free 3D spherical Poisson-disk scatter"},
    {"procgen",   "animal",           l_proc_animal,           "(ent: number, seed?: integer, archetype?: string): table", "Generate articulated DNA animal with auto-IK gait"},
    {"procgen",   "person",           l_proc_person,           "(ent: number, seed?: integer): table", "Generate modular rigged humanoid NPC"},
    {"terrain",   "create",           l_terrain_create,        "(grid_w?: integer, grid_d?: integer, cell_size?: number, seed?: integer, max_h?: number, freq?: number): integer, integer", "Generate heightmap terrain and skirted GPU mesh"},
    {"terrain",   "height",           l_terrain_height,        "(terrain_id: integer, world_x: number, world_z: number): number", "Sample bilinear terrain world height"},
    {"particles", "create",           l_part_create,           "(opts?: table): integer", "Create instanced 3D particle emitter"},
    {"particles", "burst",            l_part_burst,            "(emitter_id: integer, count?: integer): integer", "Emit instant burst of particles"},
    {"particles", "alive",            l_part_alive,            "(emitter_id: integer): integer", "Return active particle count"},
    {"anim",      "set_gait_speed",   l_anim_set_gait_speed,   "(ent: number, speed: number)", "Set procedural IK gait playback speed"},
    {"anim",      "ik_two_bone",      l_anim_ik_two_bone,      "(ent: number, hip: integer, knee: integer, ankle: integer, tx: number, ty: number, tz: number): boolean", "Solve analytical 2-bone limb IK"},
    {"anim",      "ik_fabrik",        l_anim_ik_fabrik,        "(ent: number, chain_bones: table, tx: number, ty: number, tz: number, iters?: integer): boolean", "Solve multi-joint FABRIK chain IK"},
    {"audio",     "synth",            l_audio_synth,           "(wave?: string, freq_start?: number, dur?: number, freq_end?: number): integer", "Synthesize retro ADSR sound clip"},
    {"audio",     "play",             l_audio_play,            "(clip_id: integer, x?: number, y?: number, z?: number, pocket?: integer): integer", "Play 2D or cross-portal 3D spatial sound"},
    {"ai",        "set_grid",         l_ai_set_grid,           "(pocket: integer, cell_size: number, w: integer, d: integer, walk_tbl?: table): boolean", "Register walkable NavGrid"},
    {"ai",        "find_path",        l_ai_find_path,          "(p0: integer, x0: number, y0: number, z0: number, p1: integer, x1: number, y1: number, z1: number): table", "Portal-traversing A* pathfinding"},
    {"net",       "start_loopback",   l_net_start_loopback,    "(): boolean", "Initialize connected in-memory server/client peers"},
    {"net",       "host",             l_net_host,              "(transport?: string, port?: integer): integer", "Bind server peer (loopback|udp|websocket)"},
    {"net",       "connect",          l_net_connect,           "(transport?: string, host?: string, port?: integer): boolean", "Connect client peer"},
    {"net",       "send",             l_net_send,              "(role: string, msg: string, reliable?: boolean): boolean", "Send packet from server or client peer"},
    {"net",       "poll",             l_net_poll,              "(role: string): string|nil", "Poll next packet on server or client peer"},
    {"net",       "sync_scene",       l_net_sync_scene,        "(): boolean", "Replicate pocket-aware scene snapshot from server to client"},
    {"save",      "write",            l_save_write,            "(slot: string, data: string): boolean", "Write versioned ENGB save slot"},
    {"save",      "read",             l_save_read,             "(slot: string): string|nil", "Read versioned ENGB save slot"},
    {"i18n",      "set_lang",         l_i18n_set,              "(lang: string): boolean", "Switch active localization language"},
    {"i18n",      "t",                l_i18n_t,                "(key: string): string", "Translate UTF-8 key with fallback"},
    {"mod",       "on",               l_mod_on,                "(event: string, fn: function)", "Register sandboxed mod event hook"},
    {"mod",       "emit",             l_mod_emit,              "(event: string, payload?: any)", "Emit event to active mods"}
};

/* Strict __index metatable suggesting closest valid function via Levenshtein distance! */
static int strict_submod_index(lua_State *L) {
    const char *mod_name = lua_tostring(L, lua_upvalueindex(1));
    const char *key = luaL_optstring(L, 2, "?");

    const char *cands[64];
    const lua_fn_desc_t *descs[64];
    size_t n = 0;
    for (size_t i = 0; i < sizeof(k_api_table) / sizeof(k_api_table[0]) && n < 64; i++) {
        if (strcmp(k_api_table[i].mod, mod_name) == 0) {
            cands[n] = k_api_table[i].name;
            descs[n] = &k_api_table[i];
            n++;
        }
    }
    const char *sug = eng_str_suggest(key, cands, n, 4);
    luaL_where(L, 1);
    if (sug) {
        const char *sig = "";
        for (size_t i = 0; i < n; i++) if (strcmp(cands[i], sug) == 0) sig = descs[i]->sig;
        lua_pushfstring(L, "%sUnknown symbol 'eng.%s.%s' — did you mean 'eng.%s.%s%s'?",
                        lua_tostring(L, -1), mod_name, key, mod_name, sug, sig);
    } else {
        lua_pushfstring(L, "%sUnknown symbol 'eng.%s.%s'", lua_tostring(L, -1), mod_name, key);
    }
    return lua_error(L);
}

static int strict_root_index(lua_State *L) {
    const char *key = luaL_optstring(L, 2, "?");
    static const char *const mods[] = {
        "log", "math", "input", "xr", "scene", "camera", "render", "asset",
        "portal", "physics", "procgen", "terrain", "particles", "anim",
        "audio", "ai", "net", "save", "i18n", "mod",
        "async", "bt", "space", "procgen_ext", "ui", "fun", "test"
    };
    const char *sug = eng_str_suggest(key, mods, sizeof(mods) / sizeof(mods[0]), 4);
    luaL_where(L, 1);
    if (sug) {
        lua_pushfstring(L, "%sUnknown module 'eng.%s' — did you mean 'eng.%s'?", lua_tostring(L, -1), key, sug);
    } else {
        lua_pushfstring(L, "%sUnknown module 'eng.%s'", lua_tostring(L, -1), key);
    }
    return lua_error(L);
}

bool eng_lua_write_api_stubs(const char *out_path) {
    if (!out_path) return false;
    FILE *fp = fopen(out_path, "w");
    if (!fp) return false;
    fprintf(fp, "---@meta\n-- Auto-generated by stbange/engine from k_api_table in src/eng_lua.c. DO NOT EDIT.\n\n");
    fprintf(fp, "---@class eng\neng = {}\n\n");

    const char *last_mod = "";
    for (size_t i = 0; i < sizeof(k_api_table) / sizeof(k_api_table[0]); i++) {
        const lua_fn_desc_t *d = &k_api_table[i];
        if (strcmp(d->mod, last_mod) != 0) {
            fprintf(fp, "---@class eng.%s\neng.%s = {}\n\n", d->mod, d->mod);
            last_mod = d->mod;
        }
        fprintf(fp, "--- %s\nfunction eng.%s.%s%s end\n\n", d->doc, d->mod, d->name, d->sig);
    }
    fclose(fp);
    return true;
}

/* --------------------------------------------------------------------------
 * Runtime Creation, Lua Stdlib Loading & Sandboxing
 * -------------------------------------------------------------------------- */
static bool load_eng_lua_module(eng_runtime_t *rt, const char *vpath, const char *attach_name) {
    size_t sz = 0;
    char *src = (char *)eng_vfs_read_all(rt->vfs, vpath, &sz);
    if (!src) return false;

    char host_path[512] = {0};
    char chunk_name[540];
    if (eng_vfs_resolve_read(rt->vfs, vpath, host_path, sizeof(host_path))) {
        snprintf(chunk_name, sizeof(chunk_name), "@%s", host_path);
    } else {
        snprintf(chunk_name, sizeof(chunk_name), "@%s", vpath);
    }

    bool ok = (luaL_loadbuffer(rt->L, src, sz, chunk_name) == 0);
    free(src);
    if (!ok) {
        ENG_LOGE("lua", "Stdlib load failed (%s): %s", vpath, lua_tostring(rt->L, -1));
        lua_pop(rt->L, 1);
        return false;
    }

    lua_cov_file_t *cf = (rt->cov_enabled && host_path[0]) ? find_or_add_cov_file(rt, host_path) : NULL;
    mark_active_lines_recursive(rt, rt->L, cf);

    arm_watchdog(rt);
    if (lua_pcall(rt->L, 0, 1, 0) != 0) {
        ENG_LOGE("lua", "Stdlib exec failed (%s): %s", vpath, lua_tostring(rt->L, -1));
        lua_pop(rt->L, 1);
        return false;
    }
    mark_active_lines_recursive(rt, rt->L, cf);

    if (attach_name) {
        lua_getglobal(rt->L, "eng");
        lua_pushstring(rt->L, attach_name);
        lua_pushvalue(rt->L, -3);
        lua_rawset(rt->L, -3);
        lua_pop(rt->L, 1);
    }
    lua_pop(rt->L, 1);
    return true;
}

static void build_sandbox_env(eng_runtime_t *rt) {
    lua_State *L = rt->L;
    lua_newtable(L); /* sandbox env */

    static const char *const safe_globals[] = {
        "assert", "error", "ipairs", "next", "pairs", "pcall", "select",
        "tonumber", "tostring", "type", "unpack", "xpcall",
        "coroutine", "math", "string", "table", "bit", "eng"
    };
    for (size_t i = 0; i < sizeof(safe_globals) / sizeof(safe_globals[0]); i++) {
        lua_getglobal(L, safe_globals[i]);
        lua_setfield(L, -2, safe_globals[i]);
    }

    /* Persistent game table with surviving game.state across hot reloads */
    lua_newtable(L);
    lua_newtable(L);
    lua_setfield(L, -2, "state");
    lua_setfield(L, -2, "game");

    /* Self-reference _G inside sandbox */
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "_G");

    rt->sandbox_ref = luaL_ref(L, LUA_REGISTRYINDEX);
}

eng_runtime_cfg_t eng_runtime_default_cfg(void) {
    return (eng_runtime_cfg_t){
        .repo_root = ".",
        .game_dir = NULL,
        .mod_dir = NULL,
        .headless = true,
        .width = 640,
        .height = 480,
        .seed = 42u,
        .lua_cov_out_path = NULL
    };
}

eng_runtime_t *eng_runtime_create(const eng_runtime_cfg_t *cfg) {
    eng_runtime_cfg_t c = cfg ? *cfg : eng_runtime_default_cfg();
    eng_runtime_t *rt = (eng_runtime_t *)calloc(1, sizeof(eng_runtime_t));
    if (!rt) return NULL;
    rt->cfg = c;
    snprintf(rt->repo_root_buf, sizeof(rt->repo_root_buf), "%s", c.repo_root ? c.repo_root : ".");
    if (c.game_dir) snprintf(rt->game_dir_buf, sizeof(rt->game_dir_buf), "%s", c.game_dir);
    if (c.mod_dir) snprintf(rt->mod_dir_buf, sizeof(rt->mod_dir_buf), "%s", c.mod_dir);
    if (c.lua_cov_out_path) {
        snprintf(rt->cov_path_buf, sizeof(rt->cov_path_buf), "%s", c.lua_cov_out_path);
        rt->cov_enabled = true;
    }

    eng_rng_seed(&rt->rng, c.seed ? c.seed : 42u);
    rt->cam = eng_camera_default();

    rt->vfs = eng_vfs_create();
    eng_vfs_mount(rt->vfs, rt->repo_root_buf, 0, false);
    if (rt->game_dir_buf[0]) eng_vfs_mount(rt->vfs, rt->game_dir_buf, 10, true);
    if (rt->mod_dir_buf[0]) eng_vfs_mount(rt->vfs, rt->mod_dir_buf, 20, false);

    eng_platform_config_t pcfg = eng_platform_default_config();
    pcfg.width = c.width > 0 ? c.width : 640;
    pcfg.height = c.height > 0 ? c.height : 480;
    pcfg.headless = c.headless;
    rt->plat = eng_platform_create(&pcfg);
    rt->input = eng_input_create();
    eng_input_bind_key(rt->input, "left", SDL_SCANCODE_A);
    eng_input_bind_key(rt->input, "left", SDL_SCANCODE_LEFT);
    eng_input_bind_key(rt->input, "right", SDL_SCANCODE_D);
    eng_input_bind_key(rt->input, "right", SDL_SCANCODE_RIGHT);
    eng_input_bind_key(rt->input, "up", SDL_SCANCODE_W);
    eng_input_bind_key(rt->input, "up", SDL_SCANCODE_UP);
    eng_input_bind_key(rt->input, "down", SDL_SCANCODE_S);
    eng_input_bind_key(rt->input, "down", SDL_SCANCODE_DOWN);
    eng_input_bind_key(rt->input, "jump", SDL_SCANCODE_SPACE);
    eng_input_bind_key(rt->input, "fire", SDL_SCANCODE_RETURN);
    eng_input_bind_key(rt->input, "interact", SDL_SCANCODE_E);
    eng_input_bind_mouse_button(rt->input, "fire", 1);
    /* Local 3-player cooperative keyboard bindings (WASD+E, IJKL+U, Arrows+Return) + Tab/C */
    eng_input_bind_key(rt->input, "p1_up", SDL_SCANCODE_W);
    eng_input_bind_key(rt->input, "p1_down", SDL_SCANCODE_S);
    eng_input_bind_key(rt->input, "p1_left", SDL_SCANCODE_A);
    eng_input_bind_key(rt->input, "p1_right", SDL_SCANCODE_D);
    eng_input_bind_key(rt->input, "p1_act", SDL_SCANCODE_E);
    eng_input_bind_key(rt->input, "p2_up", SDL_SCANCODE_I);
    eng_input_bind_key(rt->input, "p2_down", SDL_SCANCODE_K);
    eng_input_bind_key(rt->input, "p2_left", SDL_SCANCODE_J);
    eng_input_bind_key(rt->input, "p2_right", SDL_SCANCODE_L);
    eng_input_bind_key(rt->input, "p2_act", SDL_SCANCODE_U);
    eng_input_bind_key(rt->input, "p3_up", SDL_SCANCODE_UP);
    eng_input_bind_key(rt->input, "p3_down", SDL_SCANCODE_DOWN);
    eng_input_bind_key(rt->input, "p3_left", SDL_SCANCODE_LEFT);
    eng_input_bind_key(rt->input, "p3_right", SDL_SCANCODE_RIGHT);
    eng_input_bind_key(rt->input, "p3_act", SDL_SCANCODE_RETURN);
    eng_input_bind_key(rt->input, "switch_crew", SDL_SCANCODE_TAB);
    eng_input_bind_key(rt->input, "toggle_cam", SDL_SCANCODE_C);
    rt->xr = eng_xr_create();
    rt->assets = eng_asset_cache_create(rt->vfs);
    rt->renderer = eng_renderer_create(rt->vfs, rt->assets, pcfg.width, pcfg.height);
    rt->scene = eng_scene_create(2048);
    rt->portals = eng_portal_sys_create();
    rt->physics = eng_physics_create();
    rt->audio = eng_audio_create(c.headless);
    rt->nav = eng_nav_create();
    rt->i18n = eng_i18n_create(rt->vfs, "en");
    rt->font = eng_font_load_ttf(rt->assets, rt->vfs, "assets/shared/fonts/proggy_clean.ttf", 16.0f);
    if (!rt->font) rt->font = eng_font_create_builtin(rt->assets);

    /* Initialize Lua 5.1 / LuaJIT VM */
    lua_State *L = luaL_newstate();
    rt->L = L;
    luaL_openlibs(L);
#ifdef ENG_USING_LUAJIT
    /* Keep LuaJIT assembly interpreter deterministic for LUA_MASKCOUNT watchdog & LUA_MASKLINE coverage */
    luaJIT_setmode(L, 0, LUAJIT_MODE_ENGINE | LUAJIT_MODE_OFF);
#else
    lua_pushcfunction(L, luaopen_bit);
    lua_pushstring(L, "bit");
    lua_call(L, 1, 1);
    lua_setglobal(L, "bit");
#endif

    lua_pushlightuserdata(L, &g_reg_rt_key);
    lua_pushlightuserdata(L, rt);
    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_newtable(L);
    rt->mod_hooks_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    /* Build strict-metatable `eng` table and sub-modules */
    lua_newtable(L); /* eng */
    for (size_t i = 0; i < sizeof(k_api_table) / sizeof(k_api_table[0]); i++) {
        const lua_fn_desc_t *d = &k_api_table[i];
        lua_pushstring(L, d->mod);
        lua_rawget(L, -2);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            lua_newtable(L);
            /* Attach strict Levenshtein __index metatable to sub-module */
            lua_newtable(L);
            lua_pushstring(L, d->mod);
            lua_pushcclosure(L, strict_submod_index, 1);
            lua_setfield(L, -2, "__index");
            lua_setmetatable(L, -2);

            lua_pushstring(L, d->mod);
            lua_pushvalue(L, -2);
            lua_rawset(L, -4);
        }
        lua_pushstring(L, d->name);
        lua_pushcfunction(L, d->fn);
        lua_rawset(L, -3);
        lua_pop(L, 1);
    }

    lua_setglobal(L, "eng");

    /* Load first-party Lua stdlib modules from VFS BEFORE locking root eng metatable */
    load_eng_lua_module(rt, "lua/eng/init.lua", "core");
    load_eng_lua_module(rt, "lua/eng/async.lua", "async");
    load_eng_lua_module(rt, "lua/eng/bt.lua", "bt");
    load_eng_lua_module(rt, "lua/eng/space.lua", "space");
    load_eng_lua_module(rt, "lua/eng/procgen.lua", "procgen_ext");
    load_eng_lua_module(rt, "lua/eng/ui.lua", "ui");
    load_eng_lua_module(rt, "lua/eng/fun.lua", "fun");
    load_eng_lua_module(rt, "lua/eng/test.lua", "test");

    /* Lock root `eng` table with strict Levenshtein __index metatable */
    lua_getglobal(L, "eng");
    lua_newtable(L);
    lua_pushcfunction(L, strict_root_index);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);
    lua_pop(L, 1);

    build_sandbox_env(rt);
    return rt;
}

void eng_runtime_destroy(eng_runtime_t *rt) {
    if (!rt) return;
    flush_lua_cov(rt);
    if (rt->L) lua_close(rt->L);
    for (size_t i = 0; i < rt->terrain_count; i++) eng_terrain_free(&rt->terrains[i]);
    for (size_t i = 0; i < rt->emitter_count; i++) eng_emitter_destroy(rt->emitters[i]);
    eng_net_destroy(rt->net_srv);
    eng_net_destroy(rt->net_cli);
    eng_font_destroy(rt->font);
    eng_i18n_destroy(rt->i18n);
    eng_nav_destroy(rt->nav);
    eng_audio_destroy(rt->audio);
    eng_physics_destroy(rt->physics);
    eng_portal_sys_destroy(rt->portals);
    eng_scene_destroy(rt->scene);
    eng_renderer_destroy(rt->renderer);
    eng_asset_cache_destroy(rt->assets);
    eng_xr_destroy(rt->xr);
    eng_input_destroy(rt->input);
    eng_platform_destroy(rt->plat);
    eng_vfs_destroy(rt->vfs);
    free(rt);
}

eng_vfs_t *eng_runtime_vfs(eng_runtime_t *rt)           { return rt ? rt->vfs : NULL; }
eng_scene_t *eng_runtime_scene(eng_runtime_t *rt)       { return rt ? rt->scene : NULL; }
eng_portal_sys_t *eng_runtime_portals(eng_runtime_t *rt){ return rt ? rt->portals : NULL; }
eng_physics_t *eng_runtime_physics(eng_runtime_t *rt)   { return rt ? rt->physics : NULL; }
eng_renderer_t *eng_runtime_renderer(eng_runtime_t *rt) { return rt ? rt->renderer : NULL; }
eng_asset_cache_t *eng_runtime_assets(eng_runtime_t *rt){ return rt ? rt->assets : NULL; }
eng_input_t *eng_runtime_input(eng_runtime_t *rt)       { return rt ? rt->input : NULL; }
eng_xr_t *eng_runtime_xr(eng_runtime_t *rt)             { return rt ? rt->xr : NULL; }
eng_platform_t *eng_runtime_platform(eng_runtime_t *rt) { return rt ? rt->plat : NULL; }
eng_camera_t *eng_runtime_camera(eng_runtime_t *rt)     { return rt ? &rt->cam : NULL; }
uint32_t eng_runtime_light_count(const eng_runtime_t *rt) { return rt ? (uint32_t)rt->persist_light_count : 0; }

bool eng_runtime_exec_lua(eng_runtime_t *rt, const char *chunk_name, const char *code,
                          char *out_or_err, size_t cap) {
    if (!rt || !code) return false;
    if (out_or_err && cap > 0) out_or_err[0] = '\0';
    lua_State *L = rt->L;

    if (luaL_loadbuffer(L, code, strlen(code), chunk_name ? chunk_name : "chunk") != 0) {
        if (out_or_err && cap > 0) snprintf(out_or_err, cap, "%s", lua_tostring(L, -1));
        lua_pop(L, 1);
        return false;
    }

    lua_rawgeti(L, LUA_REGISTRYINDEX, rt->sandbox_ref);
    lua_setfenv(L, -2);
    arm_watchdog(rt);

    if (lua_pcall(L, 0, 1, 0) != 0) {
        if (out_or_err && cap > 0) snprintf(out_or_err, cap, "%s", lua_tostring(L, -1));
        lua_pop(L, 1);
        return false;
    }
    if (!lua_isnil(L, -1) && out_or_err && cap > 0) {
        snprintf(out_or_err, cap, "%s", lua_tostring(L, -1));
    }
    lua_pop(L, 1);
    return true;
}

static bool call_sandbox_fn(eng_runtime_t *rt, const char *fn_name, int nargs, float arg0_opt, char *err_buf, size_t err_cap) {
    lua_State *L = rt->L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, rt->sandbox_ref);
    lua_getfield(L, -1, fn_name);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 2);
        return true; /* Optional lifecycle hook */
    }
    if (nargs == 1) lua_pushnumber(L, arg0_opt);
    arm_watchdog(rt);
    if (lua_pcall(L, nargs, 0, 0) != 0) {
        if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "%s", lua_tostring(L, -1));
        lua_pop(L, 2);
        return false;
    }
    lua_pop(L, 1);
    return true;
}

static void on_script_modified_cb(const char *vpath, void *userdata) {
    (void)vpath;
    eng_runtime_t *rt = (eng_runtime_t *)userdata;
    char err[256];
    eng_runtime_reload_scripts(rt, err, sizeof(err));
}

bool eng_runtime_reload_scripts(eng_runtime_t *rt, char *err_buf, size_t err_cap) {
    if (!rt) return false;
    size_t sz = 0;
    char *code = (char *)eng_vfs_read_all(rt->vfs, "scripts/main.lua", &sz);
    if (!code) {
        if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "Missing scripts/main.lua");
        return false;
    }
    bool ok = eng_runtime_exec_lua(rt, "@scripts/main.lua", code, err_buf, err_cap);
    free(code);
    if (!ok) return false;

    /* Invoke optional on_reload(game.state) */
    lua_State *L = rt->L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, rt->sandbox_ref);
    lua_getfield(L, -1, "on_reload");
    if (lua_isfunction(L, -1)) {
        lua_getfield(L, -2, "game");
        lua_getfield(L, -1, "state");
        lua_remove(L, -2);
        arm_watchdog(rt);
        if (lua_pcall(L, 1, 0, 0) != 0) {
            if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "%s", lua_tostring(L, -1));
            lua_pop(L, 2);
            return false;
        }
    } else {
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
    return true;
}

static void copy_ascii_desc(char *dst, size_t cap, const char *src) {
    size_t o = 0;
    for (const unsigned char *p = (const unsigned char *)src; p && *p && o + 1 < cap; p++) {
        if (*p >= 32 && *p <= 126) {
            dst[o++] = (char)*p;
        } else if (p[0] == 0xE2 && p[1] == 0x80 && (p[2] == 0x93 || p[2] == 0x94)) {
            dst[o++] = '-';
            p += 2;
        }
    }
    dst[o] = '\0';
}

bool eng_runtime_boot_game(eng_runtime_t *rt, char *err_buf, size_t err_cap) {
    if (!rt) return false;
    rt->game_desc[0] = '\0';
    rt->seen_inputs = 0u;
    /* 1. Parse optional game.json */
    char *gjson = (char *)eng_vfs_read_all(rt->vfs, "game.json", NULL);
    if (gjson) {
        eng_arena_t ar;
        if (eng_arena_init(&ar, 16384)) {
            char jerr[128] = {0};
            eng_json_val_t *root = eng_json_parse(&ar, gjson, jerr, sizeof(jerr));
            if (root && root->type == ENG_JSON_OBJ) {
                const char *req_v = eng_json_get_str(root, "engine_version", ENG_VERSION_STRING);
                if (!eng_version_check(req_v)) {
                    if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "Incompatible engine_version '%s'", req_v);
                    eng_arena_destroy(&ar);
                    free(gjson);
                    return false;
                }
                const char *desc = eng_json_get_str(root, "description", "");
                if (!desc[0]) desc = eng_json_get_str(root, "title", "");
                copy_ascii_desc(rt->game_desc, sizeof(rt->game_desc), desc);
                const char *pipe = eng_json_get_str(root, "pipeline", "forward");
                eng_renderer_set_pipeline(rt->renderer, strcmp(pipe, "deferred") == 0 ? ENG_PIPELINE_DEFERRED : ENG_PIPELINE_FORWARD);
                const eng_json_val_t *retro_obj = eng_json_get(root, "retro");
                if (retro_obj && retro_obj->type == ENG_JSON_OBJ) {
                    eng_retro_cfg_t rc = eng_retro_ps1_preset();
                    rc.vertex_snap_res = eng_json_get_num(retro_obj, "vertex_snap", rc.vertex_snap_res);
                    rc.nearest_textures = eng_json_get_bool(retro_obj, "nearest_textures", rc.nearest_textures);
                    rc.dither_bayer = eng_json_get_bool(retro_obj, "dither_bayer", rc.dither_bayer);
                    rc.color_bits = (int)eng_json_get_num(retro_obj, "color_bits", (double)rc.color_bits);
                    rc.crt_scanlines = eng_json_get_bool(retro_obj, "crt_scanlines", false) ? 0.18f : 0.0f;
                    rc.fog_density = eng_json_get_num(retro_obj, "fog_density", rc.fog_density);
                    eng_renderer_set_retro(rt->renderer, &rc);
                } else if (eng_json_get_bool(root, "retro_ps1", false)) {
                    eng_retro_cfg_t ps1 = eng_retro_ps1_preset();
                    eng_renderer_set_retro(rt->renderer, &ps1);
                }
            }
            eng_arena_destroy(&ar);
        }
        free(gjson);
    }

    /* 2. Load optional scenes/main.json */
    char *sjson = (char *)eng_vfs_read_all(rt->vfs, "scenes/main.json", NULL);
    if (sjson) {
        eng_scene_load_json(rt->scene, sjson, err_buf, err_cap);
        free(sjson);
    }

    /* 3. Load scripts/main.lua + watch for hot reload */
    if (eng_vfs_exists(rt->vfs, "scripts/main.lua")) {
        if (!eng_runtime_reload_scripts(rt, err_buf, err_cap)) return false;
        eng_vfs_watch(rt->vfs, "scripts/main.lua", on_script_modified_cb, rt);
    }

    /* 4. Load optional mod.lua overlay */
    char *mcode = (char *)eng_vfs_read_all(rt->vfs, "mod.lua", NULL);
    if (mcode) {
        bool mok = eng_runtime_exec_lua(rt, "@mod.lua", mcode, err_buf, err_cap);
        free(mcode);
        if (!mok) return false;
    }

    if (!call_sandbox_fn(rt, "init", 0, 0.0f, err_buf, err_cap)) return false;
    eng_scene_update_transforms(rt->scene);
    eng_portal_step_kinematics(rt->portals, rt->scene, 0.0f);
    return true;
}

bool eng_runtime_step(eng_runtime_t *rt, float dt, char *err_buf, size_t err_cap) {
    if (!rt) return false;
    rt->kinematics_synced = false;
    eng_vfs_poll_reloads(rt->vfs);

    /* Step coroutine scheduler eng.async.step_all(dt) */
    lua_State *L = rt->L;
    lua_getglobal(L, "eng");
    lua_getfield(L, -1, "async");
    lua_getfield(L, -1, "step_all");
    lua_pushnumber(L, dt);
    arm_watchdog(rt);
    if (lua_pcall(L, 1, 0, 0) != 0) {
        if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "%s", lua_tostring(L, -1));
        lua_pop(L, 3);
        return false;
    }
    lua_pop(L, 2);

    if (!call_sandbox_fn(rt, "update", 1, dt, err_buf, err_cap)) return false;

    eng_scene_update_transforms(rt->scene);
    if (!rt->kinematics_synced) {
        eng_portal_step_kinematics(rt->portals, rt->scene, dt);
    }
    eng_physics_step(rt->physics, rt->scene, rt->portals, dt);

    /* Sync physics poses back to scene entities */
    for (size_t i = 0; i < rt->body_map_count; i++) {
        eng_body_desc_t *bd = eng_physics_get_body(rt->physics, rt->body_map[i].body_id);
        if (bd && bd->motion != ENG_BODY_STATIC) {
            eng_scene_set_local_pos(rt->scene, rt->body_map[i].ent, bd->pos);
            eng_scene_set_pocket(rt->scene, rt->body_map[i].ent, bd->pocket_id);
        }
    }
    eng_scene_update_transforms(rt->scene);

    /* Advance procedural IK gaits on rigged animals & NPCs */
    for (size_t i = 0; i < rt->visual_count; i++) {
        ent_visual_t *v = &rt->visuals[i];
        if (v->has_rig) {
            v->gait_phase += dt;
            eng_anim_step_gait(&v->skel, &v->gait, v->gait_phase, v->gait_speed, &v->pose);
            eng_anim_compute_skin_matrices(&v->skel, &v->pose);
        }
    }

    for (size_t i = 0; i < rt->emitter_count; i++) {
        eng_emitter_step(rt->emitters[i], dt);
    }

    eng_audio_set_listener(rt->audio, rt->cam.pocket_id, rt->cam.pos, eng_v3(0, 0, 0), rt->cam.rot);
    eng_audio_update(rt->audio, rt->scene, rt->portals, dt);
    return true;
}

bool eng_runtime_render(eng_runtime_t *rt, char *err_buf, size_t err_cap) {
    if (!rt) return false;
    eng_scene_update_transforms(rt->scene);
    eng_renderer_begin_frame(rt->renderer);

    for (size_t i = 0; i < rt->persist_light_count; i++) {
        eng_renderer_add_light(rt->renderer, &rt->persist_lights[i]);
    }

    for (size_t i = 0; i < rt->visual_count; i++) {
        const ent_visual_t *v = &rt->visuals[i];
        if (!eng_ecs_alive(eng_scene_ecs(rt->scene), v->ent) || v->mesh_id == 0) continue;
        const eng_mat4_t *wm = eng_scene_get_world_matrix(rt->scene, v->ent);
        if (!wm) continue;
        eng_draw_item_t di = {
            .mesh_id = v->mesh_id,
            .albedo_tex = v->tex_id,
            .world = *wm,
            .tint = v->color,
            .metallic = v->metallic,
            .roughness = v->roughness,
            .pocket_id = eng_scene_get_pocket(rt->scene, v->ent),
            .cast_shadow = v->cast_shadow,
            .occluder = v->occluder,
            .skin_bones = v->has_rig ? v->pose.skin_mats : NULL,
            .skin_bone_count = v->has_rig ? v->skel.bone_count : 0
        };
        eng_renderer_submit_mesh(rt->renderer, &di);
    }

    eng_sprite_item_t p_sprites[128];
    for (size_t i = 0; i < rt->emitter_count; i++) {
        size_t ns = eng_emitter_collect_sprites(rt->emitters[i], p_sprites, 128);
        if (ns > 0) eng_renderer_submit_sprites(rt->renderer, p_sprites, ns);
    }

    rt->hud_text_count = 0;
    if (!call_sandbox_fn(rt, "draw", 0, 0.0f, err_buf, err_cap)) return false;

    /* Flush queued HUD labels/bars */
    lua_State *L = rt->L;
    lua_getglobal(L, "eng");
    lua_getfield(L, -1, "ui");
    lua_getfield(L, -1, "flush");
    lua_getglobal(L, "eng");
    arm_watchdog(rt);
    lua_pcall(L, 1, 0, 0);
    lua_pop(L, 2);

    eng_renderer_render_frame(rt->renderer, rt->scene, rt->portals, &rt->cam, rt->xr);
    return true;
}

size_t eng_runtime_hud_text_count(const eng_runtime_t *rt) {
    return rt ? rt->hud_text_count : 0;
}

const char *eng_runtime_hud_text_get(const eng_runtime_t *rt, size_t idx, float *out_x, float *out_y) {
    if (!rt || idx >= rt->hud_text_count) return NULL;
    if (out_x) *out_x = rt->hud_texts[idx].x;
    if (out_y) *out_y = rt->hud_texts[idx].y;
    return rt->hud_texts[idx].text;
}

const char *eng_runtime_game_desc(const eng_runtime_t *rt) {
    return (rt && rt->game_desc[0]) ? rt->game_desc : "";
}

void eng_runtime_format_controls(const eng_runtime_t *rt, char *out_buf, size_t cap) {
    if (!out_buf || cap == 0) return;
    out_buf[0] = '\0';
    if (!rt) return;
    const char *custom = eng_i18n_get(rt->i18n, "controls");
    if (custom && strcmp(custom, "controls") != 0 && custom[0]) {
        snprintf(out_buf, cap, "%s | [H] Hide Help", custom);
        return;
    }
    uint32_t m = rt->seen_inputs ? rt->seen_inputs : (1u | 2u | 4u | 8u | 16u);
    size_t n = 0;
    if ((m & 3u) == 3u)      n += (size_t)snprintf(out_buf + n, cap - n, "[WASD/Arrows] Move  ");
    else if (m & 1u)         n += (size_t)snprintf(out_buf + n, cap - n, "[A/D or Left/Right] Move  ");
    else if (m & 2u)         n += (size_t)snprintf(out_buf + n, cap - n, "[W/S or Up/Down] Move  ");
    if (m & 32u)             n += (size_t)snprintf(out_buf + n, cap - n, "[Mouse] Look (Click/ESC)  ");
    if (m & 4u)              n += (size_t)snprintf(out_buf + n, cap - n, "[Enter/Click] Action  ");
    if (m & 8u)              n += (size_t)snprintf(out_buf + n, cap - n, "[Space] Jump/Act  ");
    if (m & 16u)             n += (size_t)snprintf(out_buf + n, cap - n, "[E] Interact  ");
    snprintf(out_buf + n, cap - n, "[H] Hide Help  [F1] Editor");
}

bool eng_runtime_run_playtest(eng_runtime_t *rt, const char *test_vpath, int max_frames,
                              char *err_buf, size_t err_cap) {
    if (!rt || !test_vpath) return false;
    char *tcode = (char *)eng_vfs_read_all(rt->vfs, test_vpath, NULL);
    if (!tcode) {
        if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "Missing playtest script '%s'", test_vpath);
        return false;
    }

    /* Expose helper step_frames(n) inside sandbox for playtests */
    bool ok = eng_runtime_exec_lua(rt, test_vpath, tcode, err_buf, err_cap);
    free(tcode);
    if (!ok) return false;

    /* If playtest defines run_test() or on_frame(f), drive deterministic 60Hz loop */
    int limit = max_frames > 0 ? max_frames : 300;
    for (int f = 1; f <= limit; f++) {
        eng_input_begin_frame(rt->input, 1.0f / 60.0f);
        if (!call_sandbox_fn(rt, "playtest_frame", 1, (float)f, err_buf, err_cap)) return false;
        if (!eng_runtime_step(rt, 1.0f / 60.0f, err_buf, err_cap)) return false;
        if (!eng_runtime_render(rt, err_buf, err_cap)) return false;

        /* Allow playtest to finish early by setting game.state.playtest_done = true */
        lua_rawgeti(rt->L, LUA_REGISTRYINDEX, rt->sandbox_ref);
        lua_getfield(rt->L, -1, "game");
        lua_getfield(rt->L, -1, "state");
        lua_getfield(rt->L, -1, "playtest_done");
        bool done = lua_toboolean(rt->L, -1);
        lua_pop(rt->L, 4);
        if (done) break;
    }

    if (!call_sandbox_fn(rt, "playtest_verify", 0, 0.0f, err_buf, err_cap)) return false;
    return true;
}
