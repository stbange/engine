#include "engine/engine.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void test_lua_bindings_sandbox_watchdog_and_stdlib(void) {
    /* 1. Generate lua/eng_api.lua directly from C registration descriptors */
    char stub_path[512];
    snprintf(stub_path, sizeof(stub_path), "%s/lua/eng_api.lua", ENG_SOURCE_DIR);
    assert(eng_lua_write_api_stubs(stub_path));

    char cov_path[512];
    snprintf(cov_path, sizeof(cov_path), "%s/lua_coverage.info", ENG_BINARY_DIR);

    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.game_dir = ENG_BINARY_DIR;
    cfg.headless = true;
    cfg.lua_cov_out_path = cov_path;

    eng_runtime_t *rt = eng_runtime_create(&cfg);
    assert(rt != NULL);

    char out[1024] = {0};

    /* 2. Sandbox blocks io/os/debug */
    assert(eng_runtime_exec_lua(rt, "sb_check", "assert(io == nil and os == nil and debug == nil); return 'ok'", out, sizeof(out)));
    assert(strcmp(out, "ok") == 0);

    /* 3. Strict Levenshtein 'did you mean?' on module and function typos */
    assert(!eng_runtime_exec_lua(rt, "typo_mod", "return eng.physic", out, sizeof(out)));
    assert(strstr(out, "did you mean 'eng.physics'") != NULL);

    assert(!eng_runtime_exec_lua(rt, "typo_fn", "return eng.physics.ray_cast()", out, sizeof(out)));
    assert(strstr(out, "did you mean 'eng.physics.raycast") != NULL);

    /* 4. NaN / Inf numeric trap */
    assert(!eng_runtime_exec_lua(rt, "nan_trap", "local e = eng.scene.spawn('x'); eng.scene.set_pos(e, 0/0, 1, 2)", out, sizeof(out)));
    assert(strstr(out, "NaN/Inf") != NULL);

    /* 5. Infinite-loop watchdog recovery */
    assert(!eng_runtime_exec_lua(rt, "inf_loop", "while true do end", out, sizeof(out)));
    assert(strstr(out, "Watchdog") != NULL);

    /* 6. Comprehensive exercise of C bindings + all 8 lua/eng/*.lua stdlib modules */
    const char *full_test_lua =
        "assert(eng.core.is_finite(3.14) and eng.core.mask_combine(1, 2) > 0)\n"
        "eng.log.info('hello'); eng.log.warn('warn'); eng.log.error('err')\n"
        "eng.math.seed(123); local r = eng.math.rand(); local rg = eng.math.range(1, 5)\n"
        "assert(eng.math.clamp(10, 0, 5) == 5 and eng.math.dist3(0,0,0, 3,4,0) == 5)\n"
        "eng.input.inject('jump', true); assert(eng.input.down('jump') and eng.input.pressed('jump'))\n"
        "local ax, ay = eng.input.axis2d('left', 'right', 'down', 'up'); assert(ax == 0 and ay == 0)\n"
        "eng.xr.set_mode('cockpit'); assert(not eng.xr.is_active())\n"
        "eng.render.set_pipeline('forward'); eng.render.set_retro({ vertex_snap = 160, dither = true, color_bits = 5, fog_density = 0.01, crt = 0.1 })\n"
        "eng.render.set_sky(0.1, 0.2, 0.6, 0.5, 0.6, 0.8)\n"
        "eng.render.set_sky(0.02, 0.03, 0.1, 0.1, 0.12, 0.25, 0.02, 0.02, 0.04, 'hut_p')\n"
        "local chk = 'assets/shared/textures/checker.png'\n"
        "local ctex = eng.asset.load_cubemap({ chk, chk, chk, chk, chk, chk }, true)\n"
        "local ctex2 = eng.asset.load_cubemap({ right=chk, left=chk, top=chk, bottom=chk, front=chk, back=chk })\n"
        "local ctex3 = eng.asset.load_cubemap({ px=chk, nx=chk, py=chk, ny=chk, pz=chk, nz=chk })\n"
        "assert(ctex > 0 and ctex2 == ctex and ctex3 == ctex)\n"
        "local ptex = eng.asset.load_texture(chk, true)\n"
        "eng.fx.sky(eng, 'alpine_day')\n"
        "eng.fx.sky(eng, 'sunset_mountains')\n"
        "eng.fx.sky(eng, 'synthwave_city', { pocket = 'hut_p' })\n"
        "eng.fx.sky(eng, 'starry_night')\n"
        "eng.fx.sky(eng, 'overcast_forest')\n"
        "eng.fx.sky(eng, 'mars_dunes')\n"
        "eng.render.set_sky_fx({ tex = ptex, panorama = ptex, cubemap = ctex, sun_dir = {0,-1,0}, sun_color = {1,0.9,0.7}, sun_size = 0.08, sun_glow = 1.2, sun_banded = true, clouds = 0.5, cloud_speed = 0.04, cloud_scale = 2.0, cloud_color = {1,1,1}, stars = 0.6, star_scale = 120, pixel_snap = 160 })\n"
        "eng.render.set_parallax({ { tex = ptex, style = 'texture', parallax = 0.5, move_parallax = 0.2, scroll_speed = 0.01, height = 0.2, offset = 0.0, scale = 2.0, color = {1,1,1,0.5}, accent = {1,1,1}, fog_blend = 0.2 }, { style = 'unknown' } }, 'hut_p')\n"
        "eng.render.clear_pocket_sky('hut_p')\n"
        "eng.render.add_light({ type = 'dir', dir = {-0.3, -1.0, -0.4}, color = {2, 2, 2}, shadow = true })\n"
        "local m_sph = eng.asset.sphere(0.5, 8, 8); local m_cyl = eng.asset.cylinder(0.3, 0.2, 1.0, 8)\n"
        "local m_vox = eng.asset.voxel_ascii({'11\\n11'}, 2, 1, 2, 0.5)\n"
        "assert(m_sph > 0 and m_cyl > 0 and m_vox > 0)\n"
        "-- Space: Pocket building + moving vehicle cabin\n"
        "local hut = eng.space.create_pocket_building(eng, { exterior_pos = {0, 0, -6}, pocket = 'hut_p' })\n"
        "local veh = eng.scene.spawn('van'); eng.scene.set_pos(veh, 5, 0, -6)\n"
        "local cab = eng.space.attach_vehicle_interior(eng, veh, { pocket = 'van_p' })\n"
        "local pk_hit = eng.portal.check_crossing(0, 0, 1.0, -4.2, 0, 1.0, -4.8)\n"
        "assert(pk_hit == hut.pocket_id and cab.pocket_id > 0)\n"
        "-- ProcGen + Physics + AI + Audio + Save + Mod\n"
        "assert(eng.procgen.noise2d(1.2, 3.4, 7) ~= nil and eng.procgen.fbm3d(1, 2, 3, 7, 3) ~= nil)\n"
        "local tree_m = eng.procgen.tree(5, 2, 2.5, 0.2)\n"
        "local pts = eng.procgen.scatter_poisson(5, 20, 20, 4.0, 10)\n"
        "assert(tree_m > 0 and #pts > 0)\n"
        "local dng = eng.procgen_ext.spawn_dungeon_entity(eng, { width = 16, height = 16, seed = 9, pocket = 'dng_p' })\n"
        "local pln = eng.procgen_ext.spawn_planet_entity(eng, { radius = 15, seed = 3, pocket = 'pln_p' })\n"
        "local pet = eng.procgen_ext.spawn_creature(eng, { pos = {-2, 0, -4}, seed = 4, archetype = 'quadruped' })\n"
        "local npc = eng.procgen_ext.spawn_npc(eng, { pos = {2, 0, -4}, seed = 8 })\n"
        "assert(dng.solvable and pln.radius == 15 and npc.name ~= '')\n"
        "local mover = eng.scene.spawn('mover'); eng.scene.set_pos(mover, 0, 2, -3)\n"
        "local bid = eng.physics.add_body(mover, { shape = 'capsule', motion = 'kinematic', radius = 0.3, half_height = 0.5 })\n"
        "eng.physics.set_vel(bid, 1, 0, 0); local vx = eng.physics.get_vel(bid); assert(vx == 1)\n"
        "eng.physics.move_character(bid, 0, -0.1, 0, 0.3)\n"
        "local rhit = eng.physics.raycast(0, 0, 2, 0, 0, 0, -1, 20)\n"
        "local sfx = eng.audio.synth('square', 440, 0.08, 660); eng.audio.play(sfx, 0, 1, -3, 0)\n"
        "eng.ai.set_grid(0, 1.0, 6, 6); local path = eng.ai.find_path(0, 0.5, 0, 0.5, 0, 4.5, 0, 4.5); assert(#path >= 2)\n"
        "assert(eng.save.write('slot_a', 'payload123') and eng.save.read('slot_a') == 'payload123')\n"
        "eng.mod.on('coin', function(v) game.state.mod_val = v end); eng.mod.emit('coin', 77); assert(game.state.mod_val == 77)\n"
        "-- Async Coroutines\n"
        "game.state.co_steps = 0\n"
        "eng.async.spawn(function()\n"
        "    game.state.co_steps = 1\n"
        "    eng.async.wait_frames(1)\n"
        "    game.state.co_steps = 2\n"
        "    eng.async.wait_seconds(0.02)\n"
        "    game.state.co_steps = 3\n"
        "end)\n"
        "eng.async.step_all(0.016); eng.async.step_all(0.016); eng.async.step_all(0.03)\n"
        "assert(game.state.co_steps == 3)\n"
        "eng.async.clear()\n"
        "-- Behavior Trees\n"
        "local tree = eng.bt.selector({\n"
        "    eng.bt.sequence({ eng.bt.inverter(eng.bt.action(function() return eng.bt.SUCCESS end)) }),\n"
        "    eng.bt.sequence({ eng.bt.inverter(eng.bt.action(function() return eng.bt.FAILURE end)), eng.bt.action(function(ctx) ctx.ok = true; return eng.bt.SUCCESS end) })\n"
        "})\n"
        "local bctx = {}; assert(tree(bctx, 0.016) == eng.bt.SUCCESS and bctx.ok)\n"
        "-- UI + Fun Telemetry + Playtest Assertions\n"
        "eng.ui.label(10, 10, 'HP', 1.0); eng.ui.bar(10, 26, 100, 0.7, 'HP '); eng.ui.flush(eng)\n"
        "local tr = eng.fun.new_tracker()\n"
        "eng.fun.record_action(tr, true); eng.fun.record_near_miss(tr)\n"
        "eng.fun.record_position(tr, 2, 4, 2.0); eng.fun.record_outcome(tr, true); eng.fun.record_outcome(tr, false)\n"
        "local rep = eng.fun.evaluate(tr); assert(rep.fun_score > 0.2)\n"
        "eng.test.assert_true(eng, true, 'ok'); eng.test.assert_eq(eng, 4, 4, 'eq'); eng.test.assert_near(eng, 1.0, 1.0001, 0.01, 'near')\n"
        "local ok_fail, err_fail = pcall(function() eng.test.assert_eq(eng, 1, 2, 'boom') end)\n"
        "assert(not ok_fail and string.find(err_fail, 'Entity Snapshot') ~= nil)\n"
        "eng.camera.look_at(0, 2, 4, 0, 1, -5, 0)\n"
        "local cx, cy, cz, cpk = eng.camera.get(); assert(cy == 2 and cpk == 0)\n"
        "assert(eng.scene.find('van') == veh)\n"
        "eng.scene.despawn(mover)\n";

    if (!eng_runtime_exec_lua(rt, "full_stdlib", full_test_lua, out, sizeof(out))) {
        fprintf(stderr, "full_stdlib failed: %s\n", out);
        assert(false);
    }
    assert(eng_runtime_step(rt, 1.0f / 60.0f, out, sizeof(out)));
    assert(eng_runtime_render(rt, out, sizeof(out)));

    /* 7. State-preserving hot reload */
    const char *v1_lua = "function init() game.state.keep = 99 end\nfunction update(dt) game.state.ver = 1 end\n";
    assert(eng_vfs_write_all(eng_runtime_vfs(rt), "scripts/main.lua", v1_lua, strlen(v1_lua)));
    assert(eng_runtime_reload_scripts(rt, out, sizeof(out)));
    assert(eng_runtime_exec_lua(rt, "call_init", "init(); update(0.016)", out, sizeof(out)));

    const char *v2_lua = "function update(dt) game.state.ver = 2 end\nfunction on_reload(st) st.reloaded = true end\n";
    assert(eng_vfs_write_all(eng_runtime_vfs(rt), "scripts/main.lua", v2_lua, strlen(v2_lua)));
    assert(eng_runtime_reload_scripts(rt, out, sizeof(out)));
    assert(eng_runtime_exec_lua(rt, "verify_reload",
                                "update(0.016); assert(game.state.keep == 99 and game.state.ver == 2 and game.state.reloaded)",
                                out, sizeof(out)));

    eng_runtime_destroy(rt);
}

static void test_doctor_scaffolder_and_cli(void) {
    /* 1. Catch blocked portal & empty frustum in Doctor */
    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.headless = true;
    eng_runtime_t *rt = eng_runtime_create(&cfg);

    char out[512];
    const char *bad_scene =
        "local b = eng.asset.box(1, 1, 1)\n"
        "local d1 = eng.scene.spawn('d1'); eng.scene.set_pos(d1, 0, 1, -4)\n"
        "local d2 = eng.scene.spawn('d2'); eng.scene.set_pocket(d2, 'in'); eng.scene.set_pos(d2, 0, 1, 10)\n"
        "eng.portal.link(d1, d2, 1.2, 2.2, 1.0, true, true)\n"
        "local blocker = eng.scene.spawn('solid_wall'); eng.scene.set_pos(blocker, 0, 1, -4); eng.scene.set_scale(blocker, 4, 3, 0.4)\n"
        "eng.scene.set_mesh(blocker, b)\n"
        "eng.physics.add_body(blocker, { shape = 'aabb', motion = 'static', half_extents = {2, 1.5, 0.2} })\n"
        "eng.camera.set(0, 1, 4, 0, 180, 0, 0) -- Looking +Z away from scene!\n";
    assert(eng_runtime_exec_lua(rt, "bad_scene", bad_scene, out, sizeof(out)));

    eng_doctor_report_t rep;
    assert(!eng_doctor_audit(rt, &rep));
    assert(rep.errors >= 2 && strstr(rep.summary, "sees 0/") != NULL && strstr(rep.summary, "blocked by solid collider") != NULL);
    eng_runtime_destroy(rt);

    /* 2. End-to-end CLI workflow across all scaffold templates */
    static const char *const templates[4] = {"pocket_house", "planet_explorer", "procgen_roguelike", "voxel"};
    for (int t = 0; t < 4; t++) {
        char gdir[512], sheet_png[512];
        snprintf(gdir, sizeof(gdir), "%s/tmp_scaf_%s", ENG_BINARY_DIR, templates[t]);
        snprintf(sheet_png, sizeof(sheet_png), "%s/sheet_%s.png", ENG_BINARY_DIR, templates[t]);

        char *argv_new[] = {"engine", "--new", gdir, "--template", (char *)templates[t]};
        assert(eng_cli_run(5, argv_new) == 0);

        char *argv_doc[] = {"engine", "--repo-root", ENG_SOURCE_DIR, "--headless", "--doctor", "--fuzz-seeds", "3", "--game", gdir};
        assert(eng_cli_run(9, argv_doc) == 0);

        char *argv_tst[] = {"engine", "--repo-root", ENG_SOURCE_DIR, "--headless", "--game", gdir,
                            "--test", "tests/playtest.lua", "--capture-sheet", sheet_png};
        assert(eng_cli_run(10, argv_tst) == 0);
    }
}

int main(void) {
    test_lua_bindings_sandbox_watchdog_and_stdlib();
    test_doctor_scaffolder_and_cli();
    printf("Phase 7 Lua, Spatial Doctor, Fuzzing & Scaffolder tests passed!\n");
    return 0;
}
