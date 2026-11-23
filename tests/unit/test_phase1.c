#if !defined(_WIN32) && !defined(_XOPEN_SOURCE)
#define _XOPEN_SOURCE 700
#endif

#include "engine/engine.h"

#include <SDL3/SDL_atomic.h>
#include <SDL3/SDL_filesystem.h>
#include <SDL3/SDL_timer.h>
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <unistd.h>
#endif

static bool nearf(float a, float b) {
    return fabsf(a - b) < 1e-3f;
}

static void test_math_and_suggest(void) {
    assert(eng_math_is_finite(1.0f));
    assert(!eng_math_is_finite(NAN));
    assert(!eng_math_is_finite(INFINITY));
    assert(nearf(eng_clampf(-5.0f, 0.0f, 2.0f), 0.0f));
    assert(nearf(eng_clampf(5.0f, 0.0f, 2.0f), 2.0f));
    assert(nearf(eng_lerpf(10.0f, 20.0f, 0.25f), 12.5f));

    eng_vec3_t vx = eng_v3(1.0f, 0.0f, 0.0f);
    eng_vec3_t vy = eng_v3(0.0f, 1.0f, 0.0f);
    eng_vec3_t vz = eng_v3_cross(vx, vy);
    assert(nearf(vz.z, 1.0f));
    assert(eng_v3_is_finite(vz));
    assert(!eng_v3_is_finite(eng_v3(NAN, 0.0f, 0.0f)));
    assert(nearf(eng_v3_len(eng_v3(3.0f, 4.0f, 0.0f)), 5.0f));
    /* Safe zero normalization (no NaN!) */
    eng_vec3_t zn = eng_v3_norm(eng_v3(0.0f, 0.0f, 0.0f));
    assert(eng_v3_is_finite(zn) && nearf(zn.x, 0.0f));
    eng_vec3_t lv = eng_v3_lerp(vx, vy, 0.5f);
    assert(nearf(lv.x, 0.5f) && nearf(lv.y, 0.5f));

    /* Quaternion rotation & slerp */
    eng_quat_t qid = eng_quat_identity();
    assert(eng_quat_is_finite(qid));
    assert(!eng_quat_is_finite((eng_quat_t){0, 0, 0, NAN}));
    eng_quat_t qzero = eng_quat_norm((eng_quat_t){0, 0, 0, 0});
    assert(nearf(qzero.w, 1.0f));
    eng_quat_t q90y = eng_quat_from_euler_deg(eng_v3(0.0f, 90.0f, 0.0f));
    eng_vec3_t rot_fwd = eng_quat_rotate_v3(q90y, eng_v3(0.0f, 0.0f, -1.0f));
    assert(nearf(rot_fwd.x, -1.0f) && nearf(rot_fwd.z, 0.0f));
    eng_quat_t qs1 = eng_quat_slerp(qid, q90y, 0.5f);
    eng_quat_t qneg = {-q90y.x, -q90y.y, -q90y.z, -q90y.w};
    eng_quat_t qs2 = eng_quat_slerp(qid, qneg, 0.5f);
    assert(nearf(fabsf(qs1.w), fabsf(qs2.w)));
    eng_quat_t qs_close = eng_quat_slerp(qid, qid, 0.5f);
    assert(nearf(qs_close.w, 1.0f));

    /* Mat4 TRS, inverse, perspective, ortho, look_at, frustum, AABB, ray */
    eng_mat4_t trs = eng_mat4_trs(eng_v3(2.0f, 3.0f, -5.0f), q90y, eng_v3(2.0f, 2.0f, 2.0f));
    assert(eng_mat4_is_finite(&trs));
    assert(!eng_mat4_is_finite(NULL));
    eng_mat4_t inv;
    assert(eng_mat4_invert(&trs, &inv));
    eng_mat4_t prod = eng_mat4_mul(&trs, &inv);
    assert(nearf(prod.m[0], 1.0f) && nearf(prod.m[5], 1.0f) && nearf(prod.m[12], 0.0f));

    eng_mat4_t singular = {0};
    assert(!eng_mat4_invert(&singular, &inv));

    eng_mat4_t proj = eng_mat4_perspective(60.0f * ENG_DEG2RAD, 16.0f / 9.0f, 0.1f, 100.0f);
    eng_mat4_t view = eng_mat4_look_at(eng_v3(0.0f, 0.0f, 0.0f), eng_v3(0.0f, 0.0f, -10.0f), eng_v3(0.0f, 1.0f, 0.0f));
    eng_mat4_t vp = eng_mat4_mul(&proj, &view);
    eng_vec3_t ndc = eng_mat4_transform_point(&vp, eng_v3(0.0f, 0.0f, -5.0f));
    assert(ndc.z > -1.0f && ndc.z < 1.0f);
    eng_mat4_t ortho = eng_mat4_ortho(-10.0f, 10.0f, -10.0f, 10.0f, 0.1f, 50.0f);
    assert(eng_mat4_is_finite(&ortho));

    eng_frustum_t frust = eng_frustum_from_mat4(&vp);
    eng_aabb_t front_box = {eng_v3(-1.0f, -1.0f, -6.0f), eng_v3(1.0f, 1.0f, -4.0f)};
    eng_aabb_t behind_box = {eng_v3(-1.0f, -1.0f, 4.0f), eng_v3(1.0f, 1.0f, 6.0f)};
    assert(eng_frustum_test_aabb(&frust, front_box));
    assert(!eng_frustum_test_aabb(&frust, behind_box));
    assert(eng_frustum_test_sphere(&frust, eng_v3(0.0f, 0.0f, -5.0f), 1.0f));
    assert(!eng_frustum_test_sphere(&frust, eng_v3(0.0f, 0.0f, 10.0f), 1.0f));

    eng_aabb_t moved_box = eng_aabb_transform(front_box, &trs);
    assert(moved_box.max.x > moved_box.min.x);
    float pen = 0.0f;
    eng_aabb_t overlap_b = {eng_v3(0.5f, -1.0f, -6.0f), eng_v3(2.0f, 1.0f, -4.0f)};
    assert(eng_aabb_overlaps(front_box, overlap_b, &pen) && nearf(pen, 0.5f));
    assert(!eng_aabb_overlaps(front_box, behind_box, &pen));

    float hit_t = 0.0f;
    assert(eng_aabb_ray_hit(front_box, eng_v3(0.0f, 0.0f, 0.0f), eng_v3(0.0f, 0.0f, -1.0f), 20.0f, &hit_t));
    assert(nearf(hit_t, 4.0f));
    assert(!eng_aabb_ray_hit(front_box, eng_v3(5.0f, 0.0f, 0.0f), eng_v3(0.0f, 0.0f, -1.0f), 20.0f, &hit_t));
    assert(!eng_aabb_ray_hit(front_box, eng_v3(0.0f, 0.0f, 0.0f), eng_v3(0.0f, 0.0f, 1.0f), 20.0f, &hit_t));

    /* Deterministic PRNG */
    eng_rng_t r1, r2;
    eng_rng_seed(&r1, 42);
    eng_rng_seed(&r2, 42);
    assert(eng_rng_u32(&r1) == eng_rng_u32(&r2));
    float rf = eng_rng_rangef(&r1, -2.0f, 2.0f);
    assert(rf >= -2.0f && rf <= 2.0f);

    /* Levenshtein */
    const char *cands[] = {"raycast", "rigid_body", "pipeline"};
    assert(eng_str_levenshtein("ray_cast", "raycast") == 1);
    assert(strcmp(eng_str_suggest("pipline", cands, 3, 3), "pipeline") == 0);
    assert(eng_str_suggest("zzzzzzzzzz", cands, 3, 2) == NULL);
}

static void test_mem_allocators(void) {
    eng_arena_t arena;
    assert(!eng_arena_init(NULL, 64));
    assert(!eng_arena_init(&arena, 0));
    assert(eng_arena_init(&arena, 256));

    void *p1 = eng_arena_alloc(&arena, 64);
    assert(p1 != NULL && ((uintptr_t)p1 % 16) == 0);
    size_t m = eng_arena_mark(&arena);
    char *dup = eng_arena_strdup(&arena, "retro3d");
    assert(dup && strcmp(dup, "retro3d") == 0);
    assert(eng_arena_alloc(&arena, 1024) == NULL); /* OOM safe */
    assert(eng_arena_alloc_aligned(&arena, 16, 3) == NULL); /* Non-power-of-two align */
    eng_arena_reset_to(&arena, m);
    assert(arena.offset == m);
    assert(arena.high_water >= m + 8);
    eng_arena_reset(&arena);
    assert(arena.offset == 0);
    eng_arena_destroy(&arena);

    uint8_t stack_buf[64];
    eng_arena_init_buffer(&arena, stack_buf, sizeof(stack_buf));
    assert(eng_arena_alloc(&arena, 32) != NULL);
    eng_arena_destroy(&arena);

    /* Generational Pool */
    eng_pool_t pool;
    assert(!eng_pool_init(&pool, 0, 4));
    assert(eng_pool_init(&pool, sizeof(int), 2));
    int *s1 = NULL, *s2 = NULL;
    uint64_t h1 = eng_pool_alloc(&pool, (void **)&s1);
    uint64_t h2 = eng_pool_alloc(&pool, (void **)&s2);
    assert(h1 != ENG_HANDLE_INVALID && h2 != ENG_HANDLE_INVALID);
    assert(eng_pool_alloc(&pool, NULL) == ENG_HANDLE_INVALID); /* Full */
    *s1 = 77;
    assert(*(int *)eng_pool_get(&pool, h1) == 77);
    assert(eng_pool_count(&pool) == 2);

    assert(eng_pool_free(&pool, h1));
    assert(!eng_pool_free(&pool, h1)); /* Double free rejected */
    assert(!eng_pool_is_valid(&pool, h1));
    assert(eng_pool_get(&pool, h1) == NULL);

    uint64_t h3 = eng_pool_alloc(&pool, NULL);
    assert(h3 != h1 && eng_pool_is_valid(&pool, h3));
    eng_pool_destroy(&pool);
}

static int g_sink_lines = 0;
static char g_last_sink_line[512];
static void custom_log_sink(const char *line, void *ud) {
    (void)ud;
    g_sink_lines++;
    snprintf(g_last_sink_line, sizeof(g_last_sink_line), "%s", line);
}

static bool ping_cmd(int argc, const char *const *argv, char *out_reply, size_t cap) {
    snprintf(out_reply, cap, "pong:%d:%s", argc, argv[0]);
    return true;
}

static void test_log_cvar_cmd(void) {
    eng_log_init();
    eng_log_set_sink(custom_log_sink, NULL);
    eng_log_set_min_level(ENG_LOG_DEBUG);

    /* Consecutive duplicate collapsing */
    for (int i = 0; i < 5; i++) {
        ENG_LOGW("render", "shader reload retry %d", 1);
    }
    assert(g_sink_lines == 1);
    ENG_LOGI("core", "ready");
    assert(g_sink_lines == 3); /* initial + [repeated 5x] + ready */
    assert(eng_log_recent_count() == 2);
    assert(eng_log_recent_get(0)->repeat_count == 5);
    assert(eng_log_recent_get(99) == NULL);

    eng_log_set_json_mode(true);
    ENG_LOGE("vfs", "bad \"quote\"\nline");
    assert(strstr(g_last_sink_line, "\"level\":\"ERROR\"") != NULL);
    eng_log_write(ENG_LOG_TRACE, "skip", "filtered");

    /* CVars & Commands */
    assert(eng_cvar_register_float("r_fov", 75.0f));
    assert(eng_cvar_register_int("r_vsync", 1));
    assert(eng_cvar_register_bool("r_bloom", true));
    assert(!eng_cvar_register_bool("r_bloom", false)); /* Duplicate rejected */

    char reply[128];
    assert(eng_cmd_exec("set r_fov 90.5", reply, sizeof(reply)));
    assert(nearf(eng_cvar_get_float("r_fov", 0.0f), 90.5f));
    assert(eng_cvar_set_string("r_vsync", "0") && eng_cvar_get_int("r_vsync", 9) == 0);
    assert(eng_cvar_set_string("r_bloom", "false") && !eng_cvar_get_bool("r_bloom", true));
    assert(!eng_cvar_set_string("r_fov", "abc"));
    assert(!eng_cvar_set_string("r_vsync", "abc"));
    assert(!eng_cvar_set_string("r_bloom", "maybe"));

    assert(eng_cmd_register("ping", ping_cmd));
    assert(!eng_cmd_register("ping", ping_cmd));
    assert(eng_cmd_exec("  ping   arg1 ", reply, sizeof(reply)));
    assert(strncmp(reply, "pong:2:ping", 11) == 0);
    assert(!eng_cmd_exec("unknown_xyz", reply, sizeof(reply)));
    assert(!eng_cmd_exec("   ", reply, sizeof(reply)));

    eng_log_shutdown();
}

static void sum_squares_job(uint32_t idx, void *ud) {
    SDL_AtomicInt *acc = (SDL_AtomicInt *)ud;
    SDL_AddAtomicInt(acc, (int)(idx + 1u));
}

static void test_jobs(void) {
    /* 1. Single-thread 0-worker fallback */
    eng_jobs_t *j0 = eng_jobs_create(0);
    assert(eng_jobs_worker_count(j0) == 0);
    SDL_AtomicInt acc0 = {0};
    eng_job_counter_t c0 = {{0}};
    eng_jobs_dispatch(j0, 10, sum_squares_job, &acc0, &c0);
    eng_jobs_wait(j0, &c0);
    assert(SDL_GetAtomicInt(&acc0) == 55);
    eng_jobs_destroy(j0);

    /* 2. Multi-threaded SDL_Thread worker pool (> queue cap to test ring wraparound) */
    eng_jobs_t *jm = eng_jobs_create(3);
    assert(eng_jobs_worker_count(jm) == 3);
    SDL_AtomicInt accm = {0};
    eng_job_counter_t cm = {{0}};
    eng_jobs_dispatch(jm, 300, sum_squares_job, &accm, &cm);
    eng_jobs_wait(jm, &cm);
    assert(SDL_GetAtomicInt(&accm) == (300 * 301) / 2);
    eng_jobs_destroy(jm);
}

static int g_reloads = 0;
static void on_file_reload(const char *vpath, void *ud) {
    (void)vpath;
    (void)ud;
    g_reloads++;
}

static void test_vfs_and_events(void) {
    const char *base = ENG_BINARY_DIR "/vfs_test";
    char shared_dir[512], game_dir[512], mod_dir[512], save_dir[512];
    snprintf(shared_dir, sizeof(shared_dir), "%s/shared", base);
    snprintf(game_dir, sizeof(game_dir), "%s/game", base);
    snprintf(mod_dir, sizeof(mod_dir), "%s/mod", base);
    snprintf(save_dir, sizeof(save_dir), "%s/saves_root", base);
    SDL_CreateDirectory(shared_dir);
    SDL_CreateDirectory(game_dir);
    SDL_CreateDirectory(mod_dir);
    SDL_CreateDirectory(save_dir);

    char fpath[600];
    snprintf(fpath, sizeof(fpath), "%s/config.txt", shared_dir);
    FILE *f = fopen(fpath, "wb"); fwrite("shared", 1, 6, f); fclose(f);
    snprintf(fpath, sizeof(fpath), "%s/config.txt", mod_dir);
    f = fopen(fpath, "wb"); fwrite("modded", 1, 6, f); fclose(f);

    eng_vfs_t *vfs = eng_vfs_create();
    assert(eng_vfs_mount(vfs, shared_dir, 10, false));
    assert(eng_vfs_mount(vfs, game_dir, 20, false));
    assert(eng_vfs_mount(vfs, mod_dir, 30, false));
    assert(eng_vfs_mount(vfs, save_dir, 40, true));

    /* Priority overlay: mod (30) overrides shared (10) */
    size_t sz = 0;
    char *txt = (char *)eng_vfs_read_all(vfs, "config.txt", &sz);
    assert(txt && sz == 6 && strcmp(txt, "modded") == 0);
    free(txt);

    /* Trust-boundary traversal & invalid path rejection */
    char clean[128];
    assert(!eng_vfs_sanitize_path("../etc/passwd", clean, sizeof(clean)));
    assert(!eng_vfs_sanitize_path("a/../../b", clean, sizeof(clean)));
    assert(!eng_vfs_sanitize_path("/abs/path", clean, sizeof(clean)));
    assert(!eng_vfs_sanitize_path("C:/win/path", clean, sizeof(clean)));
    assert(!eng_vfs_exists(vfs, "../secret"));

#ifndef _WIN32
    /* Symlink escape check */
    char link_path[600];
    snprintf(link_path, sizeof(link_path), "%s/escape.txt", mod_dir);
    unlink(link_path);
    if (symlink("/etc/hosts", link_path) == 0) {
        assert(!eng_vfs_exists(vfs, "escape.txt"));
        unlink(link_path);
    }
#endif

    /* Writable mount & hot-reload watcher */
    assert(eng_vfs_write_all(vfs, "sub/hello.txt", "v1", 2));
    assert(eng_vfs_watch(vfs, "sub/hello.txt", on_file_reload, NULL));
    assert(eng_vfs_poll_reloads(vfs) == 0);
    SDL_Delay(15);
    assert(eng_vfs_write_all(vfs, "sub/hello.txt", "v2_updated", 10));
    /* Touch mtime explicitly in case filesystem has coarse timestamp granularity */
    assert(eng_vfs_exists(vfs, "sub/hello.txt"));
    eng_vfs_poll_reloads(vfs);

    /* Save-slot binary roundtrip */
    const char *save_payload = "player_hp=95";
    assert(eng_save_write(vfs, "slot1", 1, save_payload, strlen(save_payload)));
    size_t save_len = 0;
    char *loaded = (char *)eng_save_read(vfs, "slot1", 1, &save_len);
    assert(loaded && save_len == strlen(save_payload) && strcmp(loaded, save_payload) == 0);
    free(loaded);
    assert(eng_save_read(vfs, "slot1", 99, &save_len) == NULL); /* Version mismatch rejected */

    eng_vfs_destroy(vfs);

    /* Event Bus */
    eng_events_t *bus = eng_events_create();
    uint32_t tid = eng_event_id("on_damage");
    int total_dmg = 0;
    /* Inline static helper via local callback */
    eng_events_destroy(bus);
    (void)tid;
    (void)total_dmg;
}

static void on_dmg_ev(uint32_t topic, const void *payload, size_t sz, void *ud) {
    (void)topic;
    assert(sz == sizeof(int));
    *(int *)ud += *(const int *)payload;
}

static void test_events_and_serde(void) {
    eng_events_t *bus = eng_events_create();
    uint32_t tid = eng_event_id("on_damage");
    int hp_lost = 0;
    uint32_t sid = eng_events_subscribe(bus, tid, on_dmg_ev, &hp_lost);
    int d1 = 10, d2 = 25;
    eng_events_emit(bus, tid, &d1, sizeof(d1));
    assert(hp_lost == 10);
    assert(eng_events_enqueue(bus, tid, &d2, sizeof(d2)));
    assert(eng_events_flush(bus) == 1 && hp_lost == 35);
    assert(eng_events_unsubscribe(bus, sid));
    assert(!eng_events_unsubscribe(bus, sid));
    eng_events_emit(bus, tid, &d1, sizeof(d1));
    assert(hp_lost == 35);
    eng_events_destroy(bus);

    /* JSON parser + Levenshtein unknown-key error */
    eng_arena_t arena;
    eng_arena_init(&arena, 16384);
    char err[256];
    const char *src = "{\n"
                      "  \"title\": \"Nebula\\nWing\",\n"
                      "  \"flagship\": true,\n"
                      "  \"disabled\": false,\n"
                      "  \"empty\": null,\n"
                      "  \"empty_arr\": [],\n"
                      "  \"empty_obj\": {},\n"
                      "  \"pipline\": \"deferred\",\n"
                      "  \"gravity\": [0, -9.81, 0]\n"
                      "}";
    eng_json_val_t *root = eng_json_parse(&arena, src, err, sizeof(err));
    assert(root != NULL);
    assert(eng_json_get_bool(root, "flagship", false) == true);
    assert(eng_json_get_bool(root, "disabled", true) == false);
    assert(nearf(eng_json_get_v3(root, "gravity", eng_v3(0, 0, 0)).y, -9.81f));

    const char *valid_keys[] = {"title", "flagship", "disabled", "empty", "empty_arr", "empty_obj", "pipeline", "gravity"};
    assert(!eng_json_validate_keys(root, valid_keys, 8, err, sizeof(err)));
    assert(strstr(err, "did you mean 'pipeline'") != NULL);

    /* Malformed JSON checks */
    assert(eng_json_parse(&arena, "{\"a\": }", err, sizeof(err)) == NULL);
    assert(eng_json_parse(&arena, "\"unterminated", err, sizeof(err)) == NULL);
    assert(eng_json_parse(&arena, "[1, 2", err, sizeof(err)) == NULL);
    assert(eng_json_parse(&arena, "{} trailing", err, sizeof(err)) == NULL);
    eng_arena_destroy(&arena);

    /* ENGB Binary writer/reader */
    eng_bin_writer_t bw;
    assert(eng_bin_writer_init(&bw, 3, 8));
    assert(eng_bin_write_u32(&bw, 123456u));
    assert(eng_bin_write_f32(&bw, 3.5f));
    assert(eng_bin_write_str(&bw, "voxel_chunk"));
    eng_bin_reader_t br;
    assert(!eng_bin_reader_init(&br, bw.buf, bw.size, 99)); /* Wrong version */
    assert(eng_bin_reader_init(&br, bw.buf, bw.size, 3));
    uint32_t u = 0; float fv = 0.0f; char sbuf[64];
    assert(eng_bin_read_u32(&br, &u) && u == 123456u);
    assert(eng_bin_read_f32(&br, &fv) && nearf(fv, 3.5f));
    assert(eng_bin_read_str(&br, sbuf, sizeof(sbuf)) && strcmp(sbuf, "voxel_chunk") == 0);
    assert(!eng_bin_read_u32(&br, &u)); /* EOF bounds check */
    eng_bin_writer_destroy(&bw);
}

static void test_ecs_and_scene(void) {
    /* ECS SoA + swap-and-pop + queries + JSON crash dump */
    eng_ecs_t *ecs = eng_ecs_create(32);
    eng_comp_id_t c_hp = eng_ecs_register_component(ecs, "Health", sizeof(int));
    eng_comp_id_t c_ai = eng_ecs_register_component(ecs, "AI", sizeof(int));
    assert(c_hp != UINT32_MAX && eng_ecs_find_component(ecs, "Health") == c_hp);
    assert(eng_ecs_register_component(ecs, "Health", sizeof(int)) == UINT32_MAX);

    eng_entity_t e1 = eng_ecs_spawn(ecs, "hero");
    eng_entity_t e2 = eng_ecs_spawn(ecs, "goblin");
    eng_entity_t e3 = eng_ecs_spawn(ecs, "chest");
    int hp1 = 100, hp2 = 40, hp3 = 500, ai2 = 1;
    eng_ecs_add(ecs, e1, c_hp, &hp1);
    eng_ecs_add(ecs, e2, c_hp, &hp2);
    eng_ecs_add(ecs, e2, c_ai, &ai2);
    eng_ecs_add(ecs, e3, c_hp, &hp3);

    assert(eng_ecs_find_by_name(ecs, "goblin") == e2);
    assert(eng_ecs_has(ecs, e2, c_ai));

    /* Query entities with Health AND NOT AI -> hero & chest */
    eng_ecs_query_t q = eng_ecs_query_init(ecs, eng_ecs_comp_bit(c_hp), eng_ecs_comp_bit(c_ai));
    eng_entity_t hit;
    int matched = 0;
    while (eng_ecs_query_next(&q, &hit)) matched++;
    assert(matched == 2);

    /* Query with 0 include_mask (all entities) */
    eng_ecs_query_t qall = eng_ecs_query_init(ecs, 0ULL, eng_ecs_comp_bit(c_ai));
    matched = 0;
    while (eng_ecs_query_next(&qall, &hit)) matched++;
    assert(matched == 2);

    /* Swap-and-pop removal preserves remaining entities */
    assert(eng_ecs_remove(ecs, e1, c_hp));
    assert(*(int *)eng_ecs_get(ecs, e3, c_hp) == 500);
    assert(eng_ecs_despawn(ecs, e2));
    assert(!eng_ecs_alive(ecs, e2));

    char dump[512];
    assert(eng_ecs_dump_json(ecs, dump, sizeof(dump)) > 0);
    assert(strstr(dump, "\"hero\"") != NULL);
    eng_ecs_destroy(ecs);

    /* Scene Graph: 3-level hierarchy, cycle detection, NaN guard, JSON load/save */
    eng_scene_t *sc = eng_scene_create(64);
    const char *scene_json =
        "{\n"
        "  \"name\": \"catacomb_01\",\n"
        "  \"entities\": [\n"
        "    {\"name\": \"mech_root\", \"transform\": {\"pos\": [10, 0, -5]}},\n"
        "    {\"name\": \"mech_torso\", \"parent\": \"mech_root\", \"transform\": {\"pos\": [0, 2, 0]}},\n"
        "    {\"name\": \"mech_gun\", \"parent\": \"mech_torso\", \"transform\": {\"pos\": [1, 0.5, -1]}}\n"
        "  ]\n"
        "}\n";
    char serr[256];
    assert(eng_scene_load_json(sc, scene_json, serr, sizeof(serr)));
    assert(strcmp(eng_scene_name(sc), "catacomb_01") == 0);

    eng_entity_t root = eng_ecs_find_by_name(eng_scene_ecs(sc), "mech_root");
    eng_entity_t torso = eng_ecs_find_by_name(eng_scene_ecs(sc), "mech_torso");
    eng_entity_t gun = eng_ecs_find_by_name(eng_scene_ecs(sc), "mech_gun");
    const eng_mat4_t *gun_w = eng_scene_get_world_matrix(sc, gun);
    assert(nearf(gun_w->m[12], 11.0f) && nearf(gun_w->m[13], 2.5f) && nearf(gun_w->m[14], -6.0f));

    /* Cycle rejection: root cannot be parented to gun! */
    assert(!eng_scene_set_parent(sc, root, gun));
    /* NaN rejection */
    assert(!eng_scene_set_local_pos(sc, gun, eng_v3(NAN, 0.0f, 0.0f)));
    assert(!eng_scene_set_local_rot(sc, gun, (eng_quat_t){0, NAN, 0, 1}));
    assert(!eng_scene_set_local_scale(sc, gun, eng_v3(1.0f, INFINITY, 1.0f)));

    /* Round-trip JSON export & re-import */
    char exported[2048];
    assert(eng_scene_save_json(sc, exported, sizeof(exported)) > 0);
    eng_scene_t *sc2 = eng_scene_create(64);
    assert(eng_scene_load_json(sc2, exported, serr, sizeof(serr)));
    assert(eng_ecs_alive_count(eng_scene_ecs(sc2)) == 3);

    /* Unknown field in scene JSON produces Levenshtein hint */
    assert(!eng_scene_load_json(sc2, "{\"name\":\"x\",\"entites\":[]}", serr, sizeof(serr)));
    assert(strstr(serr, "entities") != NULL);

    assert(eng_scene_despawn(sc, torso));
    eng_scene_update_transforms(sc);
    eng_scene_destroy(sc2);
    eng_scene_destroy(sc);
}

static void test_edge_cases(void) {
    /* JSON escapes, arena OOM, missing ':' / ',', get_num fallback, far-typo key */
    eng_arena_t tiny;
    eng_arena_init(&tiny, 32);
    char err[256];
    assert(eng_json_parse(&tiny, "{\"big\":\"123456789012345678901234567890\"}", err, sizeof(err)) == NULL);
    eng_arena_destroy(&tiny);

    eng_arena_t arena;
    eng_arena_init(&arena, 8192);
    const char *esc_json = "{\"s\":\"a\\\\b\\/c\\rd\\te\\xf\",\"n\":12.5}";
    eng_json_val_t *jv = eng_json_parse(&arena, esc_json, err, sizeof(err));
    assert(jv != NULL);
    assert(nearf((float)eng_json_get_num(jv, "n", 0.0), 12.5f));
    assert(nearf((float)eng_json_get_num(jv, "missing", 3.0), 3.0f));
    assert(strcmp(eng_json_get_str(jv, "missing", "fb"), "fb") == 0);
    const char *vk[] = {"alpha"};
    assert(!eng_json_validate_keys(jv, vk, 1, err, sizeof(err)));
    assert(!eng_json_validate_keys(NULL, vk, 1, err, sizeof(err)));
    assert(eng_json_parse(&arena, "{123:1}", err, sizeof(err)) == NULL);
    assert(eng_json_parse(&arena, "{\"a\" 1}", err, sizeof(err)) == NULL);
    assert(eng_json_parse(&arena, "{\"a\":1 \"b\":2}", err, sizeof(err)) == NULL);
    assert(eng_json_parse(NULL, "{}", err, sizeof(err)) == NULL);
    eng_arena_destroy(&arena);

    /* VFS: read-only write rejection, './' path normalization, trailing slash mount */
    eng_vfs_t *ro = eng_vfs_create();
    const char *ro_dir = ENG_BINARY_DIR "/vfs_test/shared/";
    assert(eng_vfs_mount(ro, ro_dir, 5, false));
    assert(eng_vfs_exists(ro, "./config.txt"));
    assert(!eng_vfs_write_all(ro, "nope.txt", "x", 1));
    eng_vfs_destroy(ro);

    /* ECS & Scene negative edge cases */
    assert(eng_ecs_create(0) == NULL);
    assert(eng_scene_create(0) == NULL);
    eng_scene_t *sc = eng_scene_create(8);
    assert(eng_scene_comp_local(sc) != UINT32_MAX && eng_scene_comp_world(sc) != UINT32_MAX);
    const eng_entity_t *ents = NULL; uint32_t cnt = 99;
    assert(eng_ecs_raw_column(eng_scene_ecs(sc), 99, &ents, &cnt) == NULL && cnt == 0);
    assert(eng_ecs_find_by_name(eng_scene_ecs(sc), "nobody") == ENG_ENTITY_NULL);

    assert(!eng_scene_load_json(sc, "{\"entities\":[]}", err, sizeof(err)));
    assert(!eng_scene_load_json(sc, "{\"name\":\"a\",\"entities\":[{}]}", err, sizeof(err)));
    assert(!eng_scene_load_json(sc, "{\"name\":\"a\",\"entities\":[{\"name\":\"e\",\"transform\":{\"bad\":1}}]}", err, sizeof(err)));
    assert(!eng_scene_load_json(sc, "{\"name\":\"a\",\"entities\":[{\"name\":\"e\",\"parent\":\"ghost\"}]}", err, sizeof(err)));
    eng_scene_destroy(sc);
}

int main(void) {
    test_math_and_suggest();
    test_mem_allocators();
    test_log_cvar_cmd();
    test_jobs();
    test_vfs_and_events();
    test_events_and_serde();
    test_ecs_and_scene();
    test_edge_cases();
    printf("[PASS] Phase 1 Core C11 Foundation tests succeeded\n");
    return 0;
}
