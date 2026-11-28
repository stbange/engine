#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "engine/engine.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static float custom_wave_sampler(float x, float z, uint16_t pocket_id, void *ud) {
    (void)z;
    (void)pocket_id;
    float base = ud ? *(const float *)ud : 0.0f;
    return base + 0.05f * sinf(x);
}

/* 1. Real-GL Low-Res Realism Lens (1280x720 -> 640x360), Soft Shadows, Normal/Wetness, SSAO, Volumetrics & Water */
static void test_lowres_realism_water_and_volumetrics_gl(void) {
    eng_retro_cfg_t lr = eng_retro_lowres_realism_preset();
    assert(lr.pixel_height == 360);
    assert(lr.vertex_snap_res == 0.0f);
    assert(!lr.nearest_textures);
    assert(lr.sharp_upscale == 1);
    assert(lr.ssao_intensity > 0.4f);
    assert(lr.volumetric_fog > 0.2f);

    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.game_dir = ENG_SOURCE_DIR "/games/103_living_wilds";
    cfg.headless = false; /* Real GL 3.3 Core under xvfb-run, software mock fallback otherwise */
    cfg.width = 1280;
    cfg.height = 720;
    cfg.lua_cov_out_path = ENG_BINARY_DIR "/lua_coverage.info";

    eng_runtime_t *rt = eng_runtime_create(&cfg);
    assert(rt != NULL);
    char err[512] = {0};
    assert(eng_runtime_boot_game(rt, err, sizeof(err)));

    eng_renderer_t *rend = eng_runtime_renderer(rt);
    assert(rend != NULL);

    int out_w = 0, out_h = 0, int_w = 0, int_h = 0;
    eng_renderer_get_size(rend, &out_w, &out_h);
    eng_renderer_get_internal_size(rend, &int_w, &int_h);
    assert(out_w == 1280 && out_h == 720);
    assert(int_w == 640 && int_h == 360);

    bool w_en = false;
    float wh0 = eng_renderer_sample_water_height(rend, 0, 0.0f, -2.0f, &w_en);
    assert(w_en && fabsf(wh0) < 0.35f);
    eng_water_cfg_t wgot = eng_renderer_get_water(rend, 0);
    assert(wgot.enabled && wgot.wave_amp > 0.01f);
    bool bad_en = true;
    assert(eng_renderer_sample_water_height(rend, 99, 0.0f, 0.0f, &bad_en) < -1e5f && !bad_en);

    /* Forward pass render with 360p lens, Gerstner water, normal/wetness maps, SSAO & god-rays */
    assert(eng_runtime_step(rt, 1.0f / 60.0f, err, sizeof(err)));
    assert(eng_runtime_render(rt, err, sizeof(err)));

    uint8_t *rgba = (uint8_t *)malloc((size_t)out_w * (size_t)out_h * 4u);
    assert(rgba != NULL);
    if (!eng_gl()->is_mock && eng_renderer_read_pixels(rend, rgba, out_w, out_h)) {
        uint64_t lum_sum = 0;
        for (size_t i = 0; i < (size_t)out_w * (size_t)out_h * 4u; i += 16u) {
            lum_sum += (uint64_t)rgba[i] + (uint64_t)rgba[i + 1] + (uint64_t)rgba[i + 2];
        }
        assert(lum_sum > 5000u);
    }

    /* Switch to Deferred pipeline, add spot light, submerge camera below water level (y = -0.6m), and test render_scale */
    char lrep[256] = {0};
    const char *lua_gl_cov =
        "eng.render.set_pipeline('deferred')\n"
        "eng.render.add_light({ type='spot', pocket=0, pos={0, 2.5, 0}, dir={0, -1, 0}, color={2, 2, 2}, range=12, cone=0.82 })\n"
        "eng.render.set_retro({ render_scale=0.5, pixel_height=0, sharp_upscale='nearest', ssao=0.65, volumetric_fog=0.5, fog_sun_scatter=0.8 })\n"
        "eng.fx.water(eng, 'coastal_clear', { level = 0.0 })\n"
        "eng.fx.water(eng, 'murky_swamp', { level = 0.0 })\n"
        "eng.camera.set(0.0, -0.65, -2.0, -5.0, 0.0, 0.0, 0)\n"
        "local s_dead = eng.sim_ext.plant_scale_for_stage('dead', 0.5)\n"
        "local s_seed = eng.sim_ext.plant_scale_for_stage('seeding', 0.8)\n"
        "assert(s_dead < 0.35 and s_seed > 0.85)\n"
        "return 'ok'";
    assert(eng_runtime_exec_lua(rt, "=gl_cov", lua_gl_cov, lrep, sizeof(lrep)));
    eng_renderer_get_internal_size(rend, &int_w, &int_h);
    assert(int_w == 640 && int_h == 360);

    /* Render directly with underwater camera before stepping Lua (which would reset camera to player pos) */
    assert(eng_runtime_render(rt, err, sizeof(err)));
    /*Also submerge explorer entity so eng_runtime_step triggers automatic underwater audio muffling! */
    assert(eng_runtime_exec_lua(rt, "=submerge",
        "eng.scene.set_pos(game.state.player_ent, 0.0, -1.2, -2.0)\n"
        "game.state.px, game.state.py, game.state.pz, game.state.pocket = 0.0, -1.2, -2.0, 0\n"
        "return 'ok'", lrep, sizeof(lrep)));
    assert(eng_runtime_step(rt, 1.0f / 60.0f, err, sizeof(err)));

    /* Also exercise preset string aliases ('lowres_realism', 'ps1', false) and disabling water */
    assert(eng_runtime_exec_lua(rt, "=presets",
        "eng.render.set_retro('ps1')\n"
        "eng.render.set_retro(false)\n"
        "eng.render.set_retro('lowres_realism')\n"
        "eng.render.set_retro({ sharp_upscale = 'linear' })\n"
        "eng.render.set_water(false)\n"
        "return 'ok'", lrep, sizeof(lrep)));
    assert(!eng_renderer_get_water(rend, 0).enabled);

    free(rgba);
    eng_runtime_destroy(rt);
}

/* 2. Underwater 1-Pole Audio Low-Pass Muffling & Planck Blackbody + Curl-Turbulence Particles */
static void test_underwater_audio_and_blackbody_particles(void) {
    eng_audio_t *aud = eng_audio_create(true);
    assert(aud != NULL);
    eng_synth_desc_t sd = eng_synth_default_desc(ENG_WAVE_SAW, 3400.0f, 0.5f);
    sd.attack_sec = 0.001f;
    sd.gain = 0.8f;
    uint32_t clip = eng_audio_synth_retro(aud, &sd);
    assert(clip != 0);

    eng_voice_desc_t vd = eng_voice_default_desc(clip);
    vd.spatial_3d = false;
    vd.loop = true;
    eng_audio_play(aud, &vd);

    float dry_pcm[1024] = {0};
    eng_audio_set_underwater(aud, 0.0f);
    assert(fabsf(eng_audio_get_underwater(aud)) < 0.001f);
    eng_audio_mix_frames(aud, NULL, NULL, dry_pcm, 512);

    float wet_pcm[1024] = {0};
    eng_audio_set_underwater(aud, 1.0f);
    assert(fabsf(eng_audio_get_underwater(aud) - 1.0f) < 0.001f);
    eng_audio_mix_frames(aud, NULL, NULL, wet_pcm, 512);

    double dry_hf = 0.0, wet_hf = 0.0;
    for (size_t i = 2; i < 1024; i += 2) {
        dry_hf += fabs((double)dry_pcm[i] - (double)dry_pcm[i - 2]);
        wet_hf += fabs((double)wet_pcm[i] - (double)wet_pcm[i - 2]);
    }
    assert(dry_hf > 5.0);
    assert(wet_hf < dry_hf * 0.55); /* Low-pass underwater filter strongly attenuates treble */
    eng_audio_destroy(aud);

    /* Planck blackbody color curve: 3600K incandescent core vs 850K red ember vs 480K dark soot */
    eng_vec3_t hot = eng_particles_blackbody_color(3600.0f);
    eng_vec3_t ember = eng_particles_blackbody_color(850.0f);
    eng_vec3_t soot = eng_particles_blackbody_color(480.0f);
    assert(hot.x > 1.0f && hot.y > 0.5f && hot.z > 0.08f);
    assert(ember.x > ember.y * 2.5f && ember.z < 0.02f);
    assert(soot.x < 0.25f && soot.y < 0.25f && soot.z < 0.25f);

    eng_emitter_cfg_t ecfg = eng_emitter_default_cfg();
    ecfg.blackbody = true;
    ecfg.additive = true;
    ecfg.temp_start_k = 3400.0f;
    ecfg.temp_end_k = 460.0f;
    ecfg.life_min = 1.0f;
    ecfg.life_max = 1.0f;
    ecfg.turbulence = 2.6f;
    ecfg.wind = eng_v3(3.5f, 0.0f, 0.0f);
    ecfg.drag = 0.8f;
    ecfg.spawn_rate = 0.0f;

    eng_emitter_t *em = eng_emitter_create(64, 99u, &ecfg);
    assert(em != NULL);
    assert(eng_emitter_burst(em, 24) == 24u);

    eng_emitter_step(em, 0.05f);
    eng_sprite_item_t sprites[32];
    size_t n_hot = eng_emitter_collect_sprites(em, sprites, 32);
    assert(n_hot == 24u && sprites[0].additive == true);

    /* Step past flame cooling threshold so particles transition to alpha-blended soot drifted +X by wind */
    for (int i = 0; i < 16; i++) eng_emitter_step(em, 0.05f);
    size_t n_cool = eng_emitter_collect_sprites(em, sprites, 32);
    assert(n_cool == 24u && sprites[0].additive == false);
    float avg_x = 0.0f;
    for (size_t i = 0; i < n_cool; i++) avg_x += sprites[i].pos.x;
    avg_x /= (float)n_cool;
    assert(avg_x > 0.4f);
    eng_emitter_destroy(em);
}

/* 3. Full 6-DOF Rotational Physics, Buoyancy, Wind, Breakable Joints & Voxel Island Fracture */
static void test_6dof_physics_buoyancy_joints_and_fracture(void) {
    eng_physics_t *phys = eng_physics_create();
    assert(phys != NULL);

    /* Capsule defaults to freeze_rotation = true; dynamic AABB/OBB defaults to freeze_rotation = false */
    eng_body_desc_t cap_d = eng_body_default_desc(ENG_SHAPE_CAPSULE, ENG_BODY_DYNAMIC);
    eng_body_desc_t box_d = eng_body_default_desc(ENG_SHAPE_AABB, ENG_BODY_DYNAMIC);
    assert(cap_d.freeze_rotation == true);
    assert(box_d.freeze_rotation == false);

    /* Static ground floor at y = -5.0 (for dry spin/sleep subtest in pocket 1) */
    eng_body_desc_t floor_d = eng_body_default_desc(ENG_SHAPE_AABB, ENG_BODY_STATIC);
    floor_d.pocket_id = 1;
    floor_d.pos = eng_v3(0.0f, -0.5f, 0.0f);
    floor_d.half_extents = eng_v3(20.0f, 0.5f, 20.0f);
    eng_physics_add_body(phys, &floor_d);

    /* Off-center impulse induces spin, then rotated crate lands on floor, settles to sleep, and wakes on blast! */
    box_d.pocket_id = 1;
    box_d.pos = eng_v3(0.0f, 1.2f, 0.0f);
    box_d.half_extents = eng_v3(0.4f, 0.4f, 0.4f);
    box_d.angular_damping = 0.8f;
    box_d.linear_damping = 0.4f;
    uint32_t crate_id = eng_physics_add_body(phys, &box_d);
    assert(eng_physics_apply_impulse_at(phys, crate_id, eng_v3(2.5f, 0.0f, 0.0f), eng_v3(0.0f, 1.58f, 0.0f)));
    eng_body_desc_t *crate = eng_physics_get_body(phys, crate_id);
    assert(eng_v3_len(crate->ang_vel) > 0.5f);

    for (int i = 0; i < 240; i++) eng_physics_step(phys, NULL, NULL, 1.0f / 60.0f);
    assert(crate->pos.y > 0.25f && crate->pos.y < 0.65f);
    assert(crate->sleeping == true);

    size_t blasted = eng_physics_radial_blast(phys, 1, eng_v3(-1.0f, 0.4f, 0.0f), 5.0f, 14.0f);
    assert(blasted >= 1u && crate->sleeping == false && crate->vel.x > 0.5f);
    crate->sleeping = true;
    eng_physics_wake_body(phys, crate_id);
    assert(crate->sleeping == false);

    /* Archimedes multi-probe buoyancy & wind in pocket 0 (water at y = 0, density = 1000 kg/m^3) */
    float base_lv = 0.0f;
    eng_physics_set_fluid(phys, 0, true, 0.0f, 1000.0f, 1.2f, (eng_vec2_t){1.5f, 0.0f});
    eng_physics_set_fluid_sampler(phys, custom_wave_sampler, &base_lv);
    eng_physics_set_wind(phys, 0, eng_v3(2.5f, 0.0f, 0.0f));

    eng_body_desc_t wood_d = eng_body_default_desc(ENG_SHAPE_AABB, ENG_BODY_DYNAMIC);
    wood_d.pocket_id = 0;
    wood_d.pos = eng_v3(0.0f, 0.1f, 0.0f);
    wood_d.half_extents = eng_v3(0.3f, 0.3f, 0.3f);
    wood_d.density = 520.0f; /* Pine floats! */
    uint32_t wood_id = eng_physics_add_body(phys, &wood_d);

    eng_body_desc_t iron_d = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
    iron_d.pocket_id = 0;
    iron_d.pos = eng_v3(2.0f, 0.1f, 0.0f);
    iron_d.radius = 0.25f;
    iron_d.density = 7800.0f; /* Iron sinks! */
    uint32_t iron_id = eng_physics_add_body(phys, &iron_d);

    for (int i = 0; i < 120; i++) eng_physics_step(phys, NULL, NULL, 1.0f / 60.0f);
    eng_body_desc_t *wood = eng_physics_get_body(phys, wood_id);
    eng_body_desc_t *iron = eng_physics_get_body(phys, iron_id);
    assert(wood->pos.y > -0.30f && wood->pos.y < 0.35f && wood->pos.x > 0.2f);
    assert(iron->pos.y < -2.5f);

    /* Joints in pocket 2: DISTANCE, BALL, HINGE, SPRING, and break_force snapping under heavy load */
    const eng_joint_type_t jtypes[4] = { ENG_JOINT_DISTANCE, ENG_JOINT_BALL, ENG_JOINT_HINGE, ENG_JOINT_SPRING };
    for (int k = 0; k < 4; k++) {
        eng_body_desc_t pend = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
        pend.pocket_id = 2;
        pend.pos = eng_v3((float)k * 2.0f, 4.0f, 0.0f);
        pend.radius = 0.2f;
        pend.mass = 1.0f;
        uint32_t bid = eng_physics_add_body(phys, &pend);
        eng_joint_desc_t jd = eng_joint_default_desc(jtypes[k], 0, bid);
        jd.anchor_a = eng_v3((float)k * 2.0f, 5.0f, 0.0f);
        jd.anchor_b = eng_v3(0.0f, 0.2f, 0.0f);
        jd.stiffness = 120.0f;
        jd.damping = 8.0f;
        uint32_t jid = eng_physics_add_joint(phys, &jd);
        assert(eng_physics_joint_is_active(phys, jid));
    }

    /* Heavy anvil on fragile rope (break_force = 12 N << m*g = 50*9.81 = 490 N) must snap! */
    eng_body_desc_t anvil = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
    anvil.pocket_id = 2;
    anvil.pos = eng_v3(10.0f, 4.0f, 0.0f);
    anvil.mass = 50.0f;
    uint32_t anvil_id = eng_physics_add_body(phys, &anvil);
    eng_joint_desc_t weak_j = eng_joint_default_desc(ENG_JOINT_DISTANCE, 0, anvil_id);
    weak_j.anchor_a = eng_v3(10.0f, 5.0f, 0.0f);
    weak_j.rest_length = 1.0f;
    weak_j.break_force = 12.0f;
    uint32_t weak_jid = eng_physics_add_joint(phys, &weak_j);

    for (int i = 0; i < 30; i++) eng_physics_step(phys, NULL, NULL, 1.0f / 60.0f);
    assert(!eng_physics_joint_is_active(phys, weak_jid));
    assert(eng_physics_get_body(phys, anvil_id)->pos.y < 3.0f);

    eng_physics_destroy(phys);

    /* 6-Connected Floating Voxel Island Fracture */
    eng_voxel_chunk_t pillar;
    eng_voxel_chunk_init(&pillar, 4, 6, 4, 0.5f);
    eng_voxel_csg_box(&pillar, 1, 0, 1, 2, 5, 2, 1, ENG_CSG_UNION);
    /* Sever y = 2 slice so y = 3..5 becomes an ungrounded floating island while y = 0..1 stays grounded */
    eng_voxel_csg_box(&pillar, 0, 2, 0, 3, 2, 3, 0, ENG_CSG_SUBTRACT);

    eng_voxel_chunk_t islands[4];
    eng_vec3_t origins[4];
    size_t n_isl = eng_voxel_extract_floating_islands(&pillar, islands, origins, 4);
    assert(n_isl == 1u);
    assert(fabsf(origins[0].x - 0.5f) < 0.01f && fabsf(origins[0].y - 1.5f) < 0.01f && fabsf(origins[0].z - 0.5f) < 0.01f);
    assert(islands[0].sx == 2 && islands[0].sy == 3 && islands[0].sz == 2);
    assert(eng_voxel_get(&pillar, 1, 0, 1) == 1 && eng_voxel_get(&pillar, 1, 4, 1) == 0);
}

/* 4. Systemic Chemistry, Thermodynamics, Electricity, Flora, Homeostasis & Wind Senses */
static void test_systemic_chemistry_and_biology(void) {
    eng_sim_t *sim = eng_sim_create(16, 10, 16, 0.5f, eng_v3(0.0f, 0.0f, 0.0f), 2026u);
    assert(sim != NULL);

    int gx = 0, gy = 0, gz = 0;
    float cs = 0.0f;
    eng_vec3_t orig;
    eng_sim_get_dims(sim, &gx, &gy, &gz, &cs, &orig);
    assert(gx == 16 && gy == 10 && gz == 16 && fabsf(cs - 0.5f) < 0.001f);

    int cx = 0, cy = 0, cz = 0;
    assert(eng_sim_world_to_grid(sim, eng_v3(1.2f, 2.2f, 3.2f), &cx, &cy, &cz) && cx == 2 && cy == 4 && cz == 6);
    eng_vec3_t wp = eng_sim_grid_to_world(sim, 2, 4, 6);
    assert(fabsf(wp.x - 1.25f) < 0.01f);

    /* Custom material registration */
    eng_mat_def_t thermite = *eng_sim_get_material(sim, ENG_MAT_IRON);
    snprintf(thermite.name, sizeof(thermite.name), "thermite");
    thermite.ignite_temp_c = 400.0f;
    thermite.fuel_energy = 1200.0f;
    thermite.burn_into = ENG_MAT_LAVA;
    int tid = eng_sim_register_material(sim, &thermite);
    assert(tid >= ENG_MAT_BUILTIN_COUNT && eng_sim_find_material(sim, "thermite") == tid);

    /* A. Phase transitions: ice -> water -> steam, sand -> glass, lava + water -> obsidian + steam */
    eng_sim_fill_box(sim, 0, 0, 0, 15, 0, 15, ENG_MAT_STONE);
    eng_sim_fill_box(sim, 5, 1, 1, 8, 1, 3, ENG_MAT_STONE); /* Stone trough for lava+water */
    eng_sim_set_cell(sim, 2, 1, 2, ENG_MAT_ICE);
    eng_sim_set_temperature(sim, 2, 1, 2, 45.0f);
    eng_sim_set_cell(sim, 4, 1, 2, ENG_MAT_SAND);
    eng_sim_set_temperature(sim, 4, 1, 2, 1850.0f);
    eng_sim_set_cell(sim, 6, 1, 2, ENG_MAT_LAVA);
    eng_sim_set_cell(sim, 7, 1, 2, ENG_MAT_WATER);
    eng_sim_step(sim, 0.1f);
    assert(eng_sim_get_cell(sim, 2, 1, 2)->mat == ENG_MAT_WATER || eng_sim_get_cell(sim, 1, 1, 2)->mat == ENG_MAT_WATER);
    assert(eng_sim_get_cell(sim, 4, 1, 2)->mat == ENG_MAT_GLASS);
    assert(eng_sim_get_cell(sim, 6, 1, 2)->mat == ENG_MAT_OBSIDIAN);
    assert(eng_sim_get_cell(sim, 7, 1, 2)->mat == ENG_MAT_STEAM || eng_sim_get_cell(sim, 7, 2, 2)->mat == ENG_MAT_STEAM);

    /* Boil water -> steam, freeze water -> ice inside stone trough */
    eng_sim_fill_box(sim, 1, 1, 1, 3, 1, 3, ENG_MAT_STONE);
    eng_sim_set_cell(sim, 2, 1, 2, ENG_MAT_WATER);
    eng_sim_set_temperature(sim, 2, 1, 2, -35.0f);
    eng_sim_step(sim, 0.1f);
    assert(eng_sim_get_cell(sim, 2, 1, 2)->mat == ENG_MAT_ICE);

    /* B. Density stratification: oil placed BELOW water floats to top and burns on water! */
    eng_sim_fill_box(sim, 1, 1, 5, 3, 3, 7, ENG_MAT_STONE);
    eng_sim_set_cell(sim, 2, 1, 6, ENG_MAT_OIL);
    eng_sim_set_cell(sim, 2, 2, 6, ENG_MAT_WATER);
    eng_sim_set_cell(sim, 2, 3, 6, ENG_MAT_AIR);
    for (int i = 0; i < 6; i++) eng_sim_step(sim, 0.05f);
    assert(eng_sim_get_cell(sim, 2, 2, 6)->mat == ENG_MAT_OIL);
    assert(eng_sim_get_cell(sim, 2, 1, 6)->mat == ENG_MAT_WATER);
    assert(eng_sim_ignite(sim, 2, 2, 6));
    assert(eng_sim_active_fire_count(sim, NULL) >= 1u);

    /* C. Sealed chamber suffocates fire (O2 depletion) vs open wood charring -> charcoal/ash + gunpowder blast */
    eng_sim_fill_box(sim, 9, 1, 1, 11, 3, 3, ENG_MAT_STONE);
    eng_sim_set_cell(sim, 10, 2, 2, ENG_MAT_WOOD);
    eng_sim_cell_mut(sim, 10, 2, 2)->o2 = 0.03f;
    assert(eng_sim_ignite(sim, 10, 2, 2));

    eng_sim_set_cell(sim, 6, 0, 8, ENG_MAT_SOIL);
    eng_sim_set_cell(sim, 6, 1, 8, ENG_MAT_WOOD);
    eng_sim_cell_mut(sim, 6, 1, 8)->fuel = 0.12f;
    assert(eng_sim_ignite(sim, 6, 1, 8));

    eng_sim_set_cell(sim, 12, 1, 12, ENG_MAT_GUNPOWDER);
    assert(eng_sim_ignite(sim, 12, 1, 12));

    for (int i = 0; i < 15; i++) eng_sim_step(sim, 0.1f);
    assert(eng_sim_get_cell(sim, 10, 2, 2)->burning == false); /* Sealed stone box starved of O2! */
    uint8_t charred = eng_sim_get_cell(sim, 6, 1, 8)->mat;
    assert(charred == ENG_MAT_CHARCOAL || charred == ENG_MAT_ASH);

    eng_sim_blast_t blast;
    assert(eng_sim_pop_blast(sim, &blast) && blast.radius > 1.0f && blast.impulse > 5.0f);

    /* D. Electrical conduction (copper + salt_water vs dry wood), acid dissolution & iron -> rust */
    eng_sim_fill_box(sim, 0, 1, 9, 4, 1, 11, ENG_MAT_STONE);
    eng_sim_set_cell(sim, 1, 1, 10, ENG_MAT_COPPER);
    eng_sim_set_cell(sim, 2, 1, 10, ENG_MAT_COPPER);
    eng_sim_set_cell(sim, 3, 1, 10, ENG_MAT_SALT_WATER);
    eng_sim_set_cell(sim, 1, 1, 11, ENG_MAT_WOOD);
    assert(eng_sim_set_voltage_source(sim, 1, 1, 10, 24.0f));

    eng_sim_fill_box(sim, 4, 1, 11, 6, 2, 13, ENG_MAT_STONE);
    eng_sim_set_cell(sim, 5, 1, 12, ENG_MAT_IRON);
    eng_sim_cell_mut(sim, 5, 1, 12)->integrity = 0.08f;
    eng_sim_set_cell(sim, 5, 2, 12, ENG_MAT_ACID);

    eng_sim_set_cell(sim, 7, 1, 12, ENG_MAT_IRON);
    eng_sim_cell_mut(sim, 7, 1, 12)->wetness = 1.0f;
    eng_sim_cell_mut(sim, 7, 1, 12)->integrity = 0.04f;

    for (int i = 0; i < 10; i++) eng_sim_step(sim, 0.2f);
    assert(eng_sim_get_cell(sim, 3, 1, 10)->voltage > 6.0f);
    assert(eng_sim_get_cell(sim, 1, 1, 11)->voltage < 0.5f);
    assert(eng_sim_get_cell(sim, 5, 1, 12)->mat != ENG_MAT_IRON); /* Dissolved by acid! */
    assert(eng_sim_get_cell(sim, 7, 1, 12)->mat == ENG_MAT_RUST); /* Wet oxygenated iron rusted! */

    /* E. Rain, shadow-raymarched flora growth (sunlit ash-fertilized vs shaded roof) */
    eng_sim_set_sun_dir(sim, eng_v3(0.0f, 1.0f, 0.0f));
    eng_sim_set_cell(sim, 8, 0, 8, ENG_MAT_SOIL);
    eng_sim_set_cell(sim, 8, 1, 8, ENG_MAT_ASH);
    eng_sim_apply_rain(sim, 1.0f, 0.5f);
    eng_sim_set_cell(sim, 8, 1, 8, ENG_MAT_AIR);
    eng_sim_cell_mut(sim, 8, 0, 8)->moisture = 0.9f;
    eng_sim_cell_mut(sim, 8, 0, 8)->nutrients = 0.9f;
    uint32_t sunny_pl = eng_sim_add_plant(sim, 8, 0, 8, 0);

    eng_sim_set_cell(sim, 13, 0, 8, ENG_MAT_SOIL);
    eng_sim_cell_mut(sim, 13, 0, 8)->moisture = 0.0f;
    eng_sim_fill_box(sim, 12, 4, 7, 14, 4, 9, ENG_MAT_STONE); /* Opaque shadow roof */
    uint32_t shaded_pl = eng_sim_add_plant(sim, 13, 0, 8, 0);

    for (int i = 0; i < 60; i++) {
        eng_sim_cell_mut(sim, 8, 0, 8)->moisture = 0.85f;
        eng_sim_step(sim, 0.5f);
    }
    const eng_plant_t *psun = eng_sim_get_plant(sim, sunny_pl);
    const eng_plant_t *pshd = eng_sim_get_plant(sim, shaded_pl);
    assert(psun->sun_exposure > 0.8f && psun->stage >= ENG_PLANT_MATURE);
    assert(pshd->sun_exposure < 0.2f && pshd->stage == ENG_PLANT_SEED);

    /* F. Organism Homeostasis (cold water hypothermia + drowning vs aquatic fish) & Wind Scent + Sight */
    eng_sim_t *bsim = eng_sim_create(16, 8, 16, 0.5f, eng_v3(0.0f, 0.0f, 0.0f), 99u);
    eng_sim_set_wind(bsim, eng_v3(4.0f, 0.0f, 0.0f)); /* Blowing toward +X */
    eng_sim_fill_box(bsim, 0, 0, 0, 4, 4, 4, ENG_MAT_STONE);
    eng_sim_fill_box(bsim, 1, 1, 1, 3, 4, 3, ENG_MAT_WATER);
    for (int z = 1; z <= 3; z++)
        for (int x = 1; x <= 3; x++)
            for (int y = 1; y <= 4; y++) eng_sim_set_temperature(bsim, x, y, z, 2.0f);

    uint32_t mammal = eng_sim_add_bio(bsim, eng_v3(1.25f, 0.75f, 1.25f), false, 0.0f, 0);
    uint32_t fish   = eng_sim_add_bio(bsim, eng_v3(1.25f, 0.75f, 1.25f), true,  0.0f, 0);
    uint32_t scent_src = eng_sim_add_bio(bsim, eng_v3(4.0f, 1.5f, 4.0f), false, 3.0f, 0);
    assert(scent_src != 0);

    for (int i = 0; i < 25; i++) eng_sim_step(bsim, 0.2f);
    eng_bio_body_t *mb = eng_sim_get_bio(bsim, mammal);
    eng_bio_body_t *fb = eng_sim_get_bio(bsim, fish);
    assert(mb->core_temp_c < 36.6f && mb->o2_level < 0.85f && mb->wetness > 0.8f);
    assert(fb->o2_level > 0.95f);
    eng_sim_apply_bio_trauma(bsim, mammal, 0.1f, 0.1f, 0.1f);
    assert(mb->health < 0.75f);

    /* Downwind (+X) scent must strongly exceed upwind (-X) scent */
    float sc_down = eng_sim_sample_scent(bsim, eng_v3(5.8f, 1.5f, 4.0f));
    float sc_up   = eng_sim_sample_scent(bsim, eng_v3(2.2f, 1.5f, 4.0f));
    assert(sc_down > sc_up * 3.0f && sc_down > 0.02f);

    /* Visibility raymarch: clear air vs solid stone wall vs smoke plume */
    assert(eng_sim_check_visibility(bsim, eng_v3(1.0f, 2.5f, 6.0f), eng_v3(6.0f, 2.5f, 6.0f), 1.0f, 0.0f) > 0.85f);
    eng_sim_fill_box(bsim, 6, 4, 11, 6, 6, 13, ENG_MAT_STONE);
    assert(eng_sim_check_visibility(bsim, eng_v3(1.0f, 2.5f, 6.0f), eng_v3(6.0f, 2.5f, 6.0f), 1.0f, 0.0f) == 0.0f);
    eng_sim_fill_box(bsim, 4, 4, 14, 5, 6, 15, ENG_MAT_SMOKE);
    float vis_smoke = eng_sim_check_visibility(bsim, eng_v3(1.0f, 2.5f, 7.5f), eng_v3(6.0f, 2.5f, 7.5f), 1.0f, 0.02f);
    assert(vis_smoke > 0.05f && vis_smoke < 0.65f);

    eng_voxel_chunk_t vox;
    eng_sim_export_voxels(sim, &vox, true);
    eng_sim_export_voxels(sim, &vox, false);

    eng_sim_destroy(bsim);
    eng_sim_destroy(sim);
}

/* 5. Flagship Game 103 Automated Playtest + Remaining Lua Sim/Physics Bindings */
static void test_flagship_103_living_wilds_playtest(void) {
    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.game_dir = ENG_SOURCE_DIR "/games/103_living_wilds";
    cfg.headless = true;
    cfg.seed = 42u;
    cfg.lua_cov_out_path = ENG_BINARY_DIR "/lua_coverage.info";

    eng_runtime_t *rt = eng_runtime_create(&cfg);
    assert(rt != NULL);
    char err[512] = {0};
    assert(eng_runtime_boot_game(rt, err, sizeof(err)));
    assert(eng_runtime_run_playtest(rt, "tests/playtest.lua", 450, err, sizeof(err)));

    /* Exercise remaining Lua bindings (mat_id, can_see, set_bio_pos, apply_trauma, set_fluid, remove_joint, extinguished firelight) */
    char rep[256] = {0};
    const char *extra_lua =
        "assert(eng.sim.mat_id('obsidian', 0) > 0)\n"
        "eng.sim.set_bio_pos(game.state.stag_bio, -7.0, 0.7, 1.0, 0)\n"
        "eng.sim.apply_trauma(game.state.stag_bio, 0.05, 0.0, 0.0, 0)\n"
        "local vis = eng.sim.can_see(-6.0, 1.5, 2.0, 0.0, 1.5, 2.0, 1.0, 0.01, 0)\n"
        "assert(vis > 0.1)\n"
        "eng.physics.set_fluid(0, 0.0, 1000.0, 1.1, 0.5, 0.0, true)\n"
        "local tj = eng.physics.add_joint({ type = 'spring', body_a = 0, body_b = game.state.lantern_body, rest_length = 1.5, stiffness = 40.0 })\n"
        "assert(eng.physics.joint_active(tj) and eng.physics.remove_joint(tj))\n"
        "assert(not eng.physics.joint_active(tj))\n"
        "eng.sim.init({ pocket = 2, gx = 6, gy = 6, gz = 6, cell_size = 0.5 })\n"
        "assert(eng.sim_ext.update_firelight(eng, game.state.fire_light, 1.0, 2) == 0)\n"
        "return 'done'";
    assert(eng_runtime_exec_lua(rt, "=extra_lua", extra_lua, rep, sizeof(rep)));
    assert(strcmp(rep, "done") == 0);

    eng_runtime_destroy(rt);
}

int main(void) {
    eng_log_init();
    test_lowres_realism_water_and_volumetrics_gl();
    test_underwater_audio_and_blackbody_particles();
    test_6dof_physics_buoyancy_joints_and_fracture();
    test_systemic_chemistry_and_biology();
    test_flagship_103_living_wilds_playtest();
    printf("[PASS] Phase 10 Low-Res Realism, Water, Fire, 6-DOF Physics & Systemic World tests passed!\n");
    return 0;
}
