#include <engine/engine.h>

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool cmd_hello(int argc, const char *const *argv, char *out_reply, size_t cap) {
    snprintf(out_reply, cap, "hello %s", (argc > 1) ? argv[1] : "world");
    return true;
}

int main(void) {
    eng_log_init();
    eng_gl_init_software_mock();

    /* 1. Resolution-Anchored HUD Scaling (1280x720 -> 1920x1080 & clamping) */
    eng_ui_rect_t tl = eng_ui_resolve_anchor(ENG_UI_TOP_LEFT, 20.0f, 10.0f, 200.0f, 50.0f, 1920, 1080);
    assert(fabsf(tl.x - 30.0f) < 0.1f && fabsf(tl.y - 15.0f) < 0.1f);
    assert(fabsf(tl.w - 300.0f) < 0.1f && fabsf(tl.h - 75.0f) < 0.1f);

    eng_ui_rect_t tr = eng_ui_resolve_anchor(ENG_UI_TOP_RIGHT, 20.0f, 10.0f, 200.0f, 50.0f, 1920, 1080);
    assert(tr.x >= 0.0f && tr.x + tr.w <= 1920.0f);

    eng_ui_rect_t bl = eng_ui_resolve_anchor(ENG_UI_BOTTOM_LEFT, 16.0f, 16.0f, 120.0f, 40.0f, 1280, 720);
    assert(fabsf(bl.x - 16.0f) < 0.1f && fabsf(bl.y - (720.0f - 40.0f - 16.0f)) < 0.1f);

    eng_ui_rect_t br = eng_ui_resolve_anchor(ENG_UI_BOTTOM_RIGHT, 9999.0f, 9999.0f, 100.0f, 40.0f, 640, 360);
    assert(br.x >= 0.0f && br.y >= 0.0f && br.x + br.w <= 640.0f && br.y + br.h <= 360.0f);

    eng_ui_rect_t ct = eng_ui_resolve_anchor(ENG_UI_CENTER, 0.0f, 0.0f, 200.0f, 100.0f, 1280, 720);
    assert(fabsf(ct.x - 540.0f) < 0.1f && fabsf(ct.y - 310.0f) < 0.1f);

    /* 2. Profiler CPU/GPU Timings, Arena Stats & 3D Debug Draw */
    eng_profiler_t *prof = eng_profiler_create();
    assert(prof != NULL);
    eng_profiler_begin_frame(prof);
    eng_profiler_begin_scope(prof, "physics");
    eng_profiler_end_scope(prof, "physics");
    eng_profiler_begin_scope(prof, "render");
    eng_profiler_end_scope(prof, "render");
    eng_profiler_set_arena_stats(prof, 64 * 1024, 512 * 1024);

    size_t a_used = 0, a_cap = 0;
    eng_profiler_get_arena_stats(prof, &a_used, &a_cap);
    assert(a_used == 64 * 1024 && a_cap == 512 * 1024);
    assert(eng_profiler_scope_count(prof) == 2);
    float p_ms = -1.0f;
    assert(strcmp(eng_profiler_scope_name(prof, 0, &p_ms), "physics") == 0 && p_ms >= 0.0f);
    assert(eng_profiler_scope_ms(prof, "physics") >= 0.0f);
    assert(eng_profiler_scope_ms(prof, "missing") == 0.0f);

    eng_debug_line(prof, eng_v3(0, 0, 0), eng_v3(1, 1, 1), (eng_vec4_t){1, 0, 0, 1});
    eng_debug_aabb(prof, (eng_aabb_t){eng_v3(-1, -1, -1), eng_v3(1, 1, 1)}, (eng_vec4_t){0, 1, 0, 1});
    eng_debug_sphere(prof, eng_v3(0, 2, 0), 0.5f, (eng_vec4_t){0, 0, 1, 1});
    eng_debug_portal(prof, eng_v3(0, 1, -3), eng_quat_identity(), 1.2f, 2.2f, (eng_vec4_t){0, 1, 1, 1});
    eng_vec3_t joints[3] = {eng_v3(0, 0, 0), eng_v3(0, 1, 0), eng_v3(0, 2, 0)};
    int32_t parents[3] = {-1, 0, 1};
    eng_debug_skeleton(prof, joints, parents, 3, (eng_vec4_t){1, 1, 0, 1});
    eng_debug_navpath(prof, joints, 3, (eng_vec4_t){1, 0, 1, 1});
    assert(eng_profiler_debug_vertex_count(prof) > 20);

    eng_mat4_t vp = eng_mat4_identity();
    eng_profiler_render_debug_lines(prof, &vp);
    assert(eng_profiler_debug_vertex_count(prof) == 0);
    eng_profiler_end_frame(prof);
    assert(eng_profiler_frame_ms(prof) >= 0.0f && eng_profiler_fps(prof) > 0.0f);

    /* 3. Nuklear Immediate-Mode UI, Touch HUD, Console (~) & Sandboxed Lua REPL */
    char game_dir[512];
    snprintf(game_dir, sizeof(game_dir), "%s/phase8_tmp_game", ENG_BINARY_DIR);
    char err[512] = {0};
    assert(eng_scaffold_game(game_dir, "fps", err, sizeof(err)));

    eng_runtime_cfg_t rcfg = eng_runtime_default_cfg();
    rcfg.repo_root = ENG_SOURCE_DIR;
    rcfg.game_dir = game_dir;
    rcfg.headless = true;
    rcfg.lua_cov_out_path = ENG_BINARY_DIR "/lua_coverage.info";
    eng_runtime_t *rt = eng_runtime_create(&rcfg);
    assert(rt != NULL);
    assert(eng_runtime_boot_game(rt, err, sizeof(err)));

    /* Exercise Lua eng.ui.anchor across all anchor presets for >=95% Lua line coverage */
    char lrep[256] = {0};
    assert(eng_runtime_exec_lua(rt, "=ui_cov",
        "local x1 = eng.ui.anchor('top_left', 10, 10, 100, 30, 1920, 1080)\n"
        "local x2 = eng.ui.anchor('top_right', 10, 10, 100, 30, 1920, 1080)\n"
        "local x3 = eng.ui.anchor('bottom_left', 10, 10, 100, 30, 1280, 720)\n"
        "local x4 = eng.ui.anchor('bottom_right', 10, 10, 100, 30, 1280, 720)\n"
        "local x5 = eng.ui.anchor('center', 0, 0, 100, 30, 1280, 720)\n"
        "return math.floor(x1 + x2 + x3 + x4 + x5)", lrep, sizeof(lrep)));
    assert(atoi(lrep) > 1000);

    eng_ui_t *ui = eng_ui_create();
    assert(ui != NULL && eng_ui_nk(ui) != NULL);

    eng_cvar_register_float("r_test_fov", 75.0f);
    eng_cmd_register("greet", cmd_hello);

    assert(!eng_ui_is_console_open(ui));
    eng_ui_toggle_console(ui);
    assert(eng_ui_is_console_open(ui));

    char crep[256] = {0};
    assert(eng_ui_console_submit(ui, rt, "set r_test_fov 92.5", crep, sizeof(crep)));
    assert(fabsf(eng_cvar_get_float("r_test_fov", 0.0f) - 92.5f) < 0.01f);
    assert(eng_ui_console_submit(ui, rt, "greet agent", crep, sizeof(crep)));
    assert(strcmp(crep, "hello agent") == 0);
    assert(eng_ui_console_submit(ui, rt, "=20 + 22", crep, sizeof(crep)));
    assert(strcmp(crep, "42") == 0);
    assert(eng_ui_console_submit(ui, rt, "lua game.state.console_flag = 99", crep, sizeof(crep)));
    assert(eng_ui_console_submit(ui, rt, "=game.state.console_flag", crep, sizeof(crep)));
    assert(strcmp(crep, "99") == 0);
    assert(eng_ui_console_history_count(ui) >= 5);
    assert(eng_ui_console_history_get(ui, 0) != NULL);

    /* Simulate touch event so touch overlay renders */
    SDL_Event tev;
    memset(&tev, 0, sizeof(tev));
    tev.type = SDL_EVENT_FINGER_DOWN;
    tev.tfinger.x = 0.2f;
    tev.tfinger.y = 0.8f;
    eng_input_process_event(eng_runtime_input(rt), eng_runtime_platform(rt), &tev);

    eng_ui_begin_frame(ui, 1280, 720, 40.0f, 40.0f, false, 0.0f);
    assert(eng_ui_width(ui) == 1280 && eng_ui_height(ui) == 720);
    eng_ui_hud_label(ui, "hud_score", ENG_UI_TOP_LEFT, 12.0f, 12.0f, 180.0f, 36.0f, "SCORE: 100");
    (void)eng_ui_hud_button(ui, "hud_btn", ENG_UI_TOP_LEFT, 12.0f, 56.0f, 140.0f, 36.0f, "Click Me");
    eng_ui_hud_bar(ui, "hud_hp", ENG_UI_BOTTOM_LEFT, 12.0f, 12.0f, 220.0f, 44.0f, 0.75f, "HP");
    eng_ui_hud_touch_overlay(ui, eng_runtime_input(rt));
    eng_ui_draw_console(ui, rt);
    eng_ui_draw_profiler(ui, prof);

    /* 4. Built-In Scene & Level Editor (F1), Gizmos, Voxel Brush & F5 Play-in-Editor */
    eng_editor_t *ed = eng_editor_create();
    assert(ed != NULL && !eng_editor_is_open(ed));
    eng_editor_toggle(ed);
    assert(eng_editor_is_open(ed));

    eng_scene_t *scene = eng_runtime_scene(rt);
    uint16_t cabin_pk = eng_scene_register_pocket(scene, "cabin");
    eng_editor_set_active_pocket(ed, cabin_pk);
    assert(eng_editor_active_pocket(ed) == cabin_pk);
    eng_editor_set_seed(ed, 100u);
    assert(eng_editor_step_seed(ed, 5) == 105u && eng_editor_seed(ed) == 105u);

    eng_entity_t crate = eng_editor_spawn_prefab(ed, scene, "EditorCrate", eng_v3(1.0f, 2.0f, -3.0f));
    assert(crate != ENG_ENTITY_NULL && eng_editor_selected(ed) == crate);

    eng_editor_set_gizmo_mode(ed, ENG_GIZMO_TRANSLATE);
    assert(eng_editor_gizmo_mode(ed) == ENG_GIZMO_TRANSLATE);
    assert(eng_editor_apply_gizmo_delta(ed, scene, eng_v3(2.0f, 0.5f, -1.0f)));
    const eng_transform_local_t *edited_loc = eng_scene_get_local(scene, crate);
    assert(fabsf(edited_loc->pos.x - 3.0f) < 0.01f && fabsf(edited_loc->pos.y - 2.5f) < 0.01f);

    eng_editor_set_gizmo_mode(ed, ENG_GIZMO_ROTATE);
    assert(eng_editor_apply_gizmo_delta(ed, scene, eng_v3(0.0f, 45.0f, 0.0f)));
    eng_editor_set_gizmo_mode(ed, ENG_GIZMO_SCALE);
    assert(eng_editor_apply_gizmo_delta(ed, scene, eng_v3(0.5f, 0.5f, 0.5f)));

    /* Voxel paint brush */
    eng_voxel_chunk_t vchunk;
    eng_voxel_chunk_init(&vchunk, 8, 8, 8, 0.5f);
    assert(eng_editor_voxel_paint(ed, &vchunk, 2, 3, 4, 5));
    assert(eng_voxel_get(&vchunk, 2, 3, 4) == 5);

    /* Viewport ray-picking & mouse-drag gizmo + interactive two-step portal linker */
    eng_editor_select(ed, ENG_ENTITY_NULL);
    eng_entity_t picked = eng_editor_viewport_interact(ed, scene, eng_v3(3.0f, 2.5f, 5.0f), eng_v3(0.0f, 0.0f, -1.0f),
                                                       true, true, 0.0f, 0.0f);
    assert(picked == crate && eng_editor_selected(ed) == crate);
    eng_editor_set_gizmo_mode(ed, ENG_GIZMO_TRANSLATE);
    eng_editor_viewport_interact(ed, scene, eng_v3(3.0f, 2.5f, 5.0f), eng_v3(0.0f, 0.0f, -1.0f),
                                 false, true, 0.0f, 0.0f);

    eng_entity_t p_a = eng_scene_spawn(scene, "DoorA");
    eng_entity_t p_b = eng_scene_spawn(scene, "DoorB");
    eng_scene_set_pocket(scene, p_a, cabin_pk);
    eng_editor_mark_portal_source(ed, p_a);
    eng_editor_select(ed, p_b);
    eng_editor_viewport_interact(ed, scene, eng_v3(0.0f, 0.0f, 5.0f), eng_v3(0.0f, 0.0f, -1.0f),
                                 false, true, 2.0f, -1.0f);
    assert(eng_editor_link_portal_to_selected(ed, eng_runtime_portals(rt), scene, 1.2f, 2.2f) >= 0);
    eng_editor_select(ed, crate);

    /* Exercise newly exposed Lua bindings: terrain, particles, anim IK, net, and procgen noise/sphere */
    assert(eng_runtime_exec_lua(rt, "=lua_parity",
        "local n3 = eng.procgen.noise3d(1.1, 2.2, 3.3, 9)\n"
        "local vd, vc = eng.procgen.voronoi2d(1.5, 2.5, 9)\n"
        "local r3 = eng.procgen.ridged3d(0.5, 0.5, 0.5, 9, 3)\n"
        "local w3 = eng.procgen.warp3d(0.5, 0.5, 0.5, 9, 1.2)\n"
        "local sp = eng.procgen.scatter_sphere(7, 10.0, 4.0, 12)\n"
        "local tid, tmesh = eng.terrain.create(17, 17, 1.0, 42, 4.0, 0.08)\n"
        "local th = eng.terrain.height(tid, 4.0, 4.0)\n"
        "local eid = eng.particles.create({ pos = {0, 1, -3}, dir = {0, 1, 0}, rate = 10 })\n"
        "local burst_n = eng.particles.burst(eid, 8)\n"
        "local alive_n = eng.particles.alive(eid)\n"
        "local rig_e = eng.scene.spawn('RigBeast')\n"
        "eng.procgen.animal(rig_e, 13, 'biped')\n"
        "eng.anim.set_gait_speed(rig_e, 1.5)\n"
        "local ik2 = eng.anim.ik_two_bone(rig_e, 0, 1, 2, 0.2, 0.0, -0.2)\n"
        "local ikf = eng.anim.ik_fabrik(rig_e, {0, 1, 2}, 0.1, 0.2, -0.3, 6)\n"
        "assert(eng.net.start_loopback())\n"
        "assert(eng.net.send('server', 'ping_42', true))\n"
        "assert(eng.net.poll('client') == 'ping_42')\n"
        "assert(eng.net.sync_scene())\n"
        "local up = eng.net.host('loopback', 0)\n"
        "eng.net.connect('loopback', '127.0.0.1', up)\n"
        "local mech = eng.scene.spawn('TestMech'); eng.scene.set_pos(mech, 0, 0, -10)\n"
        "local sv = eng.space.create_steerable_vehicle(eng, mech, {\n"
        "    pocket = 'test_mech_bridge', interior_size = {12, 5, 16},\n"
        "    step_bob_amp = 0.1, stations = {{ name = 'helm', pos = {0, 0, -5} }, { name = 'vac', pos = {-3, 0, 0} }}\n"
        "})\n"
        "sv:set_helm_input(1.0, 0.4); sv:step(1.0 / 30.0)\n"
        "sv:set_helm_input(-0.5, -0.2); sv:step(1.0 / 30.0)\n"
        "assert(sv:find_station(0.0, -5.0, 1.5) == 'helm' and sv:find_station(99.0, 99.0, 1.0) == nil)\n"
        "local tvx, tvy, tvz = eng.portal.transform_vel(sv.hatch_portal, 0, 1.2, -7.0, 0, 0, 1)\n"
        "assert(tvz ~= nil)\n"
        "eng.scene.despawn(rig_e)\n"
        "assert(#sp > 0 and tid >= 1 and tmesh >= 1 and burst_n == 8 and alive_n == 8 and ik2 ~= nil and ikf ~= nil)\n"
        "return tostring(math.floor((n3 + vd + r3 + w3 + th) * 100))", lrep, sizeof(lrep)));
    assert(eng_runtime_step(rt, 1.0f / 60.0f, err, sizeof(err)));
    assert(eng_runtime_render(rt, err, sizeof(err)));

    eng_editor_draw_ui(ed, ui, scene, eng_runtime_portals(rt), prof);
    uint32_t ui_draws = eng_ui_render(ui);
    assert(ui_draws > 0);
    eng_profiler_render_debug_lines(prof, &vp);

    /* F5 Start Play-in-Editor -> mutate & spawn entities -> F5 Stop Play-in-Editor -> verify exact restore! */
    assert(!eng_editor_is_playing(ed));
    assert(eng_editor_toggle_pie(ed, scene, err, sizeof(err)));
    assert(eng_editor_is_playing(ed));

    /* Mutate crate & spawn temporary bullet during PIE */
    eng_scene_set_local_pos(scene, crate, eng_v3(999.0f, -50.0f, 999.0f));
    eng_entity_t temp_bullet = eng_scene_spawn(scene, "RuntimeBullet");
    assert(temp_bullet != ENG_ENTITY_NULL);

    /* Stop PIE (F5): restores pre-play snapshot! */
    assert(eng_editor_toggle_pie(ed, scene, err, sizeof(err)));
    assert(!eng_editor_is_playing(ed));
    assert(eng_ecs_find_by_name(eng_scene_ecs(scene), "RuntimeBullet") == ENG_ENTITY_NULL);
    eng_entity_t restored_crate = eng_ecs_find_by_name(eng_scene_ecs(scene), "EditorCrate");
    assert(restored_crate != ENG_ENTITY_NULL);
    const eng_transform_local_t *rest_loc = eng_scene_get_local(scene, restored_crate);
    assert(fabsf(rest_loc->pos.x - 3.0f) < 0.02f && fabsf(rest_loc->pos.y - 2.5f) < 0.02f);

    /* Save edited scene to JSON file and validate reload */
    char scene_out[600];
    snprintf(scene_out, sizeof(scene_out), "%s/scenes/edited.json", game_dir);
    assert(eng_editor_save_scene_file(ed, scene, scene_out));
    eng_scene_t *verify_sc = eng_scene_create(64);
    size_t jlen = 0;
    char *jsrc = (char *)eng_vfs_read_all(eng_runtime_vfs(rt), "scenes/edited.json", &jlen);
    assert(jsrc != NULL && eng_scene_load_json(verify_sc, jsrc, err, sizeof(err)));
    free(jsrc);
    eng_scene_destroy(verify_sc);

    eng_editor_destroy(ed);
    eng_ui_destroy(ui);
    eng_profiler_destroy(prof);
    eng_runtime_destroy(rt);

    /* 5. Exercise CLI entrypoints (--version, no-args usage, --gen-stubs, --fuzz-seeds, headless loop) */
    char *av_ver[] = {"engine", "--version"};
    assert(eng_cli_run(2, av_ver) == 0);

    char *av_usage[] = {"engine"};
    assert(eng_cli_run(1, av_usage) == 0);

    char stubs_tmp[512];
    snprintf(stubs_tmp, sizeof(stubs_tmp), "%s/tmp_api.lua", ENG_BINARY_DIR);
    char *av_stubs[] = {"engine", "--gen-stubs", stubs_tmp};
    assert(eng_cli_run(3, av_stubs) == 0);

    char *av_fuzz[] = {"engine", "--repo-root", ENG_SOURCE_DIR, "--game", game_dir, "--headless", "--doctor", "--fuzz-seeds", "2"};
    assert(eng_cli_run(9, av_fuzz) == 0);

    char *av_repo_stubs[] = {"engine", "--gen-stubs", ENG_SOURCE_DIR "/lua/eng_api.lua"};
    assert(eng_cli_run(3, av_repo_stubs) == 0);

    char sheet_tmp[512];
    snprintf(sheet_tmp, sizeof(sheet_tmp), "%s/tmp_sheet.png", ENG_BINARY_DIR);
    char *av_loop[] = {"engine", "--repo-root", ENG_SOURCE_DIR, "--game", game_dir, "--headless", "--width", "160", "--height", "120", "--max-frames", "2", "--seed", "7", "--capture-sheet", sheet_tmp};
    assert(eng_cli_run(15, av_loop) == 0);

    eng_log_shutdown();
    printf("Phase 8 UI, Console REPL, Profiler & F1/F5 Level Editor tests passed!\n");
    return 0;
}
