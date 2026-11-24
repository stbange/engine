#if !defined(_WIN32) && !defined(_XOPEN_SOURCE)
#define _XOPEN_SOURCE 700
#endif

#include "engine/eng_doctor.h"
#include "engine/eng_version.h"

#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <direct.h>
#define ENG_MKDIR(p) _mkdir(p)
#else
#include <sys/stat.h>
#define ENG_MKDIR(p) mkdir(p, 0755)
#endif

static void append_msg(eng_doctor_report_t *rep, bool is_err, const char *fmt, ...) {
    if (!rep) return;
    if (is_err) rep->errors++;
    else rep->warnings++;

    size_t cur = strlen(rep->summary);
    if (cur + 64 >= sizeof(rep->summary)) return;
    cur += (size_t)snprintf(rep->summary + cur, sizeof(rep->summary) - cur, "%s", is_err ? "[DOCTOR ERROR] " : "[DOCTOR WARN] ");

    va_list ap;
    va_start(ap, fmt);
    vsnprintf(rep->summary + cur, sizeof(rep->summary) - cur, fmt, ap);
    va_end(ap);

    cur = strlen(rep->summary);
    if (cur + 2 < sizeof(rep->summary)) {
        rep->summary[cur] = '\n';
        rep->summary[cur + 1] = '\0';
    }
}

bool eng_doctor_audit(eng_runtime_t *rt, eng_doctor_report_t *out_report) {
    eng_doctor_report_t rep;
    memset(&rep, 0, sizeof(rep));
    if (!rt) {
        append_msg(&rep, true, "NULL runtime passed to eng_doctor_audit");
        if (out_report) *out_report = rep;
        return false;
    }

    char err[256] = {0};
    eng_runtime_render(rt, err, sizeof(err));
    eng_render_stats_t st = eng_renderer_stats(eng_runtime_renderer(rt));
    eng_scene_t *sc = eng_runtime_scene(rt);
    eng_ecs_t *ecs = eng_scene_ecs(sc);
    eng_camera_t *cam = eng_runtime_camera(rt);

    /* 1. Empty camera frustum check when meshes were submitted */
    uint32_t vis_lods = st.lod_counts[0] + st.lod_counts[1] + st.lod_counts[2] + st.lod_counts[3];
    if (st.submitted_items > 0 && vis_lods == 0) {
        eng_vec3_t nearest = eng_v3(0, 0, -5);
        float best_d = 1e30f;
        eng_ecs_query_t q = eng_ecs_query_init(ecs, eng_ecs_comp_bit(eng_scene_comp_local(sc)), 0);
        eng_entity_t e;
        while (eng_ecs_query_next(&q, &e)) {
            if (eng_scene_get_pocket(sc, e) != cam->pocket_id) continue;
            const eng_transform_local_t *tr = eng_scene_get_local(sc, e);
            if (!tr) continue;
            float d = eng_v3_len(eng_v3_sub(tr->pos, cam->pos));
            if (d > 0.01f && d < best_d) { best_d = d; nearest = tr->pos; }
        }
        append_msg(&rep, true,
                   "Active camera at (%.1f, %.1f, %.1f) in pocket %u sees 0/%u meshes! Try eng.camera.look_at(%.1f, %.1f, %.1f, %.1f, %.1f, %.1f)",
                   cam->pos.x, cam->pos.y, cam->pos.z, (unsigned)cam->pocket_id, st.submitted_items,
                   cam->pos.x, cam->pos.y, cam->pos.z, nearest.x, nearest.y, nearest.z);
    }

    /* 2. Dark unlit PBR scene check */
    if (st.submitted_items > 0 && eng_runtime_light_count(rt) == 0) {
        append_msg(&rep, false, "Scene has 0 dynamic lights registered — call eng.render.add_light({ type='dir', ... })");
    }

    /* 3. Extreme entity scale mismatch */
    eng_ecs_query_t q = eng_ecs_query_init(ecs, eng_ecs_comp_bit(eng_scene_comp_local(sc)), 0);
    eng_entity_t e;
    while (eng_ecs_query_next(&q, &e)) {
        const eng_transform_local_t *tr = eng_scene_get_local(sc, e);
        if (!tr) continue;
        float min_s = fminf(tr->scale.x, fminf(tr->scale.y, tr->scale.z));
        float max_s = fmaxf(tr->scale.x, fmaxf(tr->scale.y, tr->scale.z));
        if (min_s < 0.005f || max_s > 500.0f) {
            const char *nm = eng_ecs_get_name(ecs, e);
            append_msg(&rep, false, "Entity '%s' has extreme scale (%.3f, %.3f, %.3f) in 1.0=1m metric space",
                       nm ? nm : "unnamed", tr->scale.x, tr->scale.y, tr->scale.z);
        }
    }

    /* 4. Blocked passable portal aperture check */
    eng_portal_sys_t *ps = eng_runtime_portals(rt);
    eng_physics_t *phys = eng_runtime_physics(rt);
    size_t pc = eng_portal_count(ps);
    for (size_t i = 0; i < pc; i++) {
        const eng_portal_t *p = eng_portal_get(ps, i);
        const eng_mat4_t *ms = p ? eng_scene_get_world_matrix(sc, p->src_ent) : NULL;
        if (!p || !p->passable || !ms) continue;

        /* Cast a probe ray from 0.4m in front of the portal center into the doorway */
        eng_vec3_t door_c = eng_v3(ms->m[12], ms->m[13], ms->m[14]);
        eng_vec3_t n_out = eng_v3_norm(eng_v3(ms->m[8], ms->m[9], ms->m[10]));
        eng_vec3_t ray_o = eng_v3_add(door_c, eng_v3_scale(n_out, 0.4f));
        eng_vec3_t ray_d = eng_v3_scale(n_out, -1.0f);
        /* Raycast WITHOUT portals so we test if a solid collider in src_pocket blocks the doorway itself! */
        eng_raycast_hit_t blk = eng_physics_raycast(phys, sc, NULL, p->src_pocket, ray_o, ray_d, 0.45f);
        if (blk.hit) {
            const char *bname = eng_ecs_get_name(ecs, blk.entity);
            append_msg(&rep, true,
                       "Passable portal #%zu in pocket %u is blocked by solid collider '%s' — use eng.space.cut_wall_with_door!",
                       i, (unsigned)p->src_pocket, bname ? bname : "body");
        }
    }

    /* 5. Deep initial spawn collider penetration check */
    eng_physics_step(phys, sc, ps, 0.0001f);
    for (size_t c = 0; c < eng_physics_contact_count(phys); c++) {
        const eng_contact_event_t *ce = eng_physics_contact_get(phys, c);
        if (ce && !ce->is_trigger && ce->penetration > 0.35f) {
            append_msg(&rep, false, "Deep initial collider overlap (%.2fm) between bodies #%u and #%u",
                       ce->penetration, ce->body_a, ce->body_b);
        }
    }

    if (rep.errors == 0 && rep.warnings == 0) {
        snprintf(rep.summary, sizeof(rep.summary), "[DOCTOR PASS] Scene healthy (%u visible draws, %u lights, %zu portals).\n",
                 vis_lods, eng_runtime_light_count(rt), pc);
    }
    if (out_report) *out_report = rep;
    return rep.errors == 0 && rep.warnings == 0;
}

bool eng_doctor_fuzz_game(const char *repo_root, const char *game_dir, const char *mod_dir,
                          int num_seeds, eng_doctor_report_t *out_report) {
    if (!game_dir) return false;
    if (num_seeds < 1) num_seeds = 1;
    eng_doctor_report_t agg;
    memset(&agg, 0, sizeof(agg));

    for (int s = 1; s <= num_seeds; s++) {
        eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
        cfg.repo_root = repo_root ? repo_root : ".";
        cfg.game_dir = game_dir;
        cfg.mod_dir = mod_dir;
        cfg.headless = true;
        cfg.seed = (uint64_t)(s * 1009 + 37);

        eng_runtime_t *rt = eng_runtime_create(&cfg);
        if (!rt) return false;
        char err[256] = {0};
        if (!eng_runtime_boot_game(rt, err, sizeof(err))) {
            append_msg(&agg, true, "Seed %d boot failed: %s", s, err);
            eng_runtime_destroy(rt);
            break;
        }
        eng_doctor_report_t one;
        if (!eng_doctor_audit(rt, &one)) {
            agg.errors += one.errors;
            agg.warnings += one.warnings;
            append_msg(&agg, one.errors > 0, "Seed %d failed audit:\n%s", s, one.summary);
            eng_runtime_destroy(rt);
            break;
        }
        eng_runtime_destroy(rt);
    }

    if (agg.errors == 0 && agg.warnings == 0) {
        snprintf(agg.summary, sizeof(agg.summary), "[DOCTOR FUZZ PASS] %d/%d procedural seeds healthy for '%s'.\n",
                 num_seeds, num_seeds, game_dir);
    }
    if (out_report) *out_report = agg;
    return agg.errors == 0 && agg.warnings == 0;
}

bool eng_doctor_capture_sheet(eng_runtime_t *rt, const char *out_png_path) {
    if (!rt || !out_png_path) return false;
    eng_renderer_t *ren = eng_runtime_renderer(rt);
    eng_camera_t *cam = eng_runtime_camera(rt);
    eng_camera_t saved = *cam;

    const int pw = 320, ph = 240;
    eng_renderer_resize(ren, pw, ph);

    uint8_t *panel = (uint8_t *)malloc((size_t)(pw * ph * 4));
    uint8_t *sheet = (uint8_t *)calloc((size_t)((pw * 2) * (ph * 2) * 4), 1);
    if (!panel || !sheet) {
        free(panel); free(sheet);
        return false;
    }

    /* 4 diagnostic camera viewpoints: [0]=Player Cam, [1]=45° Iso, [2]=Top-Down, [3]=Front Close-up */
    eng_camera_t views[4];
    views[0] = saved;
    views[1] = saved;
    views[1].pos = eng_v3(saved.pos.x + 12.0f, saved.pos.y + 12.0f, saved.pos.z + 12.0f);
    views[1].rot = eng_quat_from_euler_deg(eng_v3(-35.0f, 45.0f, 0.0f));
    views[2] = saved;
    views[2].pos = eng_v3(0.0f, 24.0f, 0.1f);
    views[2].rot = eng_quat_from_euler_deg(eng_v3(-89.0f, 0.0f, 0.0f));
    views[3] = saved;
    views[3].pos = eng_v3(saved.pos.x * 0.5f, saved.pos.y, saved.pos.z * 0.5f);

    char err[128];
    for (int v = 0; v < 4; v++) {
        *cam = views[v];
        eng_runtime_render(rt, err, sizeof(err));
        eng_renderer_read_pixels(ren, panel, pw, ph);

        int qx = (v & 1) * pw;
        int qy = (v < 2 ? 1 : 0) * ph; /* Bottom-up GL row layout: v=0,1 at top half (qy=ph) */
        for (int y = 0; y < ph; y++) {
            memcpy(sheet + ((size_t)(qy + y) * (size_t)(pw * 2) + (size_t)qx) * 4u,
                   panel + (size_t)y * (size_t)pw * 4u,
                   (size_t)pw * 4u);
        }
    }

    *cam = saved;
    bool ok = eng_asset_write_png(out_png_path, pw * 2, ph * 2, sheet);
    free(panel);
    free(sheet);
    return ok;
}

static bool write_host_file(const char *dir, const char *rel, const char *content) {
    char full[1024];
    snprintf(full, sizeof(full), "%s/%s", dir, rel);
    FILE *fp = fopen(full, "wb");
    if (!fp) return false;
    size_t len = strlen(content);
    bool ok = fwrite(content, 1, len, fp) == len;
    fclose(fp);
    return ok;
}

bool eng_scaffold_game(const char *target_dir, const char *template_name, char *err_buf, size_t err_cap) {
    if (!target_dir || !target_dir[0]) return false;
    const char *tmpl = (template_name && template_name[0]) ? template_name : "fps";

    ENG_MKDIR(target_dir);
    char sub[1024];
    snprintf(sub, sizeof(sub), "%s/scripts", target_dir); ENG_MKDIR(sub);
    snprintf(sub, sizeof(sub), "%s/scenes", target_dir);  ENG_MKDIR(sub);
    snprintf(sub, sizeof(sub), "%s/locales", target_dir); ENG_MKDIR(sub);
    snprintf(sub, sizeof(sub), "%s/tests", target_dir);   ENG_MKDIR(sub);

    /* Derive clean ^[0-9a-z_]+$ id from target_dir basename */
    const char *base = target_dir;
    for (const char *p = target_dir; *p; p++) {
        if (*p == '/' || *p == '\\') base = p + 1;
    }
    char slug[64] = {0};
    size_t si = 0;
    for (const char *p = base; *p && si + 1 < sizeof(slug); p++) {
        char c = *p;
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        slug[si++] = ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || c == '_') ? c : '_';
    }
    if (si == 0) strcpy(slug, "new_game");

    char game_json[768];
    snprintf(game_json, sizeof(game_json),
             "{\n"
             "  \"id\": \"%s\",\n"
             "  \"title\": \"Scaffolded %s Game\",\n"
             "  \"genre\": \"%s\",\n"
             "  \"primitives\": [\"mesh\", \"voxel\", \"sdf_text\"],\n"
             "  \"engine_version\": \"%s\",\n"
             "  \"entry_script\": \"scripts/main.lua\",\n"
             "  \"pipeline\": \"forward\",\n"
             "  \"xr_mode\": \"%s\",\n"
             "  \"retro\": {\n"
             "    \"vertex_snap\": 240,\n"
             "    \"nearest_textures\": true,\n"
             "    \"dither_bayer\": true,\n"
             "    \"color_bits\": 5\n"
             "  }\n"
             "}\n",
             slug, tmpl, tmpl, ENG_VERSION_STRING, strcmp(tmpl, "xr") == 0 ? "6dof" : "diorama");

    char script_buf[2048];
    if (strcmp(tmpl, "pocket_house") == 0) {
        snprintf(script_buf, sizeof(script_buf),
                 "function init()\n"
                 "    game.state.ticks = 0\n"
                 "    eng.render.add_light({ type = 'dir', dir = {-0.3, -1.0, -0.4}, color = {2.2, 2.1, 1.9} })\n"
                 "    eng.render.add_light({ type = 'point', pocket = 'hut_in', pos = {0, 4, 0}, color = {2.5, 2.0, 1.4}, range = 30 })\n"
                 "    game.state.hut = eng.space.create_pocket_building(eng, {\n"
                 "        exterior_pos = {0, 0, -5}, exterior_size = {3, 3, 3},\n"
                 "        interior_size = {24, 9, 28}, pocket = 'hut_in'\n"
                 "    })\n"
                 "    eng.camera.look_at(0, 1.4, 2, 0, 1.2, -3.5, 0)\n"
                 "end\n"
                 "function update(dt) game.state.ticks = game.state.ticks + 1 end\n"
                 "function draw() eng.ui.label(16, 16, eng.i18n.t('title'), 1.0) end\n");
    } else if (strcmp(tmpl, "planet_explorer") == 0) {
        snprintf(script_buf, sizeof(script_buf),
                 "function init()\n"
                 "    game.state.ticks = 0\n"
                 "    eng.render.add_light({ type = 'dir', dir = {-0.5, -0.8, -0.3}, color = {2.4, 2.3, 2.1} })\n"
                 "    game.state.planet = eng.procgen_ext.spawn_planet_entity(eng, { seed = 99, radius = 20.0 })\n"
                 "    eng.camera.look_at(0, 24, 48, 0, 0, 0, 0)\n"
                 "end\n"
                 "function update(dt) game.state.ticks = game.state.ticks + 1 end\n"
                 "function draw() eng.ui.label(16, 16, eng.i18n.t('title'), 1.0) end\n");
    } else if (strcmp(tmpl, "procgen_roguelike") == 0) {
        snprintf(script_buf, sizeof(script_buf),
                 "function init()\n"
                 "    game.state.ticks = 0\n"
                 "    eng.render.add_light({ type = 'dir', dir = {-0.3, -1.0, -0.4}, color = {2.2, 2.1, 1.9} })\n"
                 "    local d = eng.procgen_ext.spawn_dungeon_entity(eng, { width = 20, height = 20, seed = 42 })\n"
                 "    game.state.solvable = d.solvable\n"
                 "    eng.camera.look_at(d.start_x, 14, d.start_z + 10, d.start_x, 0, d.start_z, 0)\n"
                 "end\n"
                 "function update(dt) game.state.ticks = game.state.ticks + 1 end\n"
                 "function draw() eng.ui.label(16, 16, eng.i18n.t('title'), 1.0) end\n");
    } else {
        snprintf(script_buf, sizeof(script_buf),
                 "function init()\n"
                 "    game.state.ticks = 0\n"
                 "    game.state.px, game.state.py, game.state.pz = 0, 2.5, 2.5\n"
                 "    game.state.yaw, game.state.pitch = 0, -14\n"
                 "    eng.render.add_light({ type = 'dir', dir = {-0.3, -1.0, -0.4}, color = {2.2, 2.1, 1.9} })\n"
                 "    local vox = eng.asset.voxel_ascii({'1111\\n1111\\n1111\\n1111', '1..1\\n....\\n....\\n1..1'}, 4, 2, 4, 0.8)\n"
                 "    local arena = eng.scene.spawn('arena')\n"
                 "    eng.scene.set_pos(arena, -1.6, 0, -6.0)\n"
                 "    eng.scene.set_mesh(arena, vox, { cast_shadow = true })\n"
                 "    eng.procgen_ext.spawn_creature(eng, { name = 'pet', pos = {0, 0, -4}, seed = 7, archetype = 'quadruped' })\n"
                 "    eng.input.set_mouse_lock(true)\n"
                 "    eng.camera.set(game.state.px, game.state.py, game.state.pz, game.state.pitch, game.state.yaw, 0, 0)\n"
                 "end\n"
                 "function update(dt)\n"
                 "    local s = game.state\n"
                 "    s.ticks = s.ticks + 1\n"
                 "    local dx, dz\n"
                 "    s.yaw, s.pitch, dx, dz = eng.camera.fps_steer(s.yaw, s.pitch, 6.0, dt)\n"
                 "    s.px, s.pz = eng.physics.slide_move(0, s.px, s.py, s.pz, dx, dz, 0.38)\n"
                 "    eng.camera.set(s.px, s.py, s.pz, s.pitch, s.yaw, 0, 0)\n"
                 "end\n"
                 "function draw() eng.ui.label(16, 16, eng.i18n.t('title'), 1.0) end\n");
    }

    const char *locale_en = "{\n  \"title\": \"Engine Ready\"\n}\n";
    const char *playtest_lua =
        "function playtest_frame(f)\n"
        "    if f >= 10 then game.state.playtest_done = true end\n"
        "end\n"
        "function playtest_verify()\n"
        "    eng.test.assert_true(eng, game.state.ticks >= 10, 'ticks advanced')\n"
        "end\n";

    if (!write_host_file(target_dir, "game.json", game_json) ||
        !write_host_file(target_dir, "scripts/main.lua", script_buf) ||
        !write_host_file(target_dir, "locales/en.json", locale_en) ||
        !write_host_file(target_dir, "tests/playtest.lua", playtest_lua)) {
        if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "Failed writing scaffold files to '%s'", target_dir);
        return false;
    }
    return true;
}
