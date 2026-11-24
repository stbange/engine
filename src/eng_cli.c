#include "engine/engine.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void draw_runtime_hud(eng_ui_t *ui, const eng_runtime_t *rt) {
    size_t n = eng_runtime_hud_text_count(rt);
    int uw = eng_ui_width(ui), uh = eng_ui_height(ui);
    float sh = (uh > 0) ? ((float)uh / 720.0f) : 1.0f;
    float min_y = 0.0f;
    for (size_t i = 0; i < n; i++) {
        float hx = 16.0f, hy = 16.0f;
        const char *txt = eng_runtime_hud_text_get(rt, i, &hx, &hy);
        if (!txt || !txt[0]) continue;
        if (uw < 700 || sh < 0.85f) {
            float eff_y = hy * sh;
            if (eff_y < min_y) hy = min_y / (sh > 0.01f ? sh : 1.0f);
            min_y = hy * sh + 24.0f;
        }
        char id[32];
        snprintf(id, sizeof(id), "__hud_%zu", i);
        eng_ui_hud_label(ui, id, ENG_UI_TOP_LEFT, hx, hy, 680.0f, 26.0f, txt);
    }
}

#ifdef __EMSCRIPTEN__
static struct {
    eng_runtime_t *rt;
    eng_profiler_t *prof;
    eng_ui_t *ui;
    eng_editor_t *ed;
} g_web = {0};

static void eng_web_tick_one(void) {
    if (!g_web.rt) return;
    char err[512] = {0};
    eng_platform_t *plat = eng_runtime_platform(g_web.rt);
    eng_input_t *inp = eng_runtime_input(g_web.rt);
    eng_profiler_begin_frame(g_web.prof);
    float dt = eng_platform_begin_frame(plat);
    eng_input_begin_frame(inp, dt);
    eng_input_poll_sdl(inp, plat);
    if (eng_input_pressed(inp, "_toggle_editor")) eng_editor_toggle(g_web.ed);
    if (eng_input_pressed(inp, "_toggle_pie")) eng_editor_toggle_pie(g_web.ed, eng_runtime_scene(g_web.rt), NULL, 0);
    if (eng_input_pressed(inp, "_toggle_console")) eng_ui_toggle_console(g_web.ui);
    if (eng_input_pressed(inp, "_toggle_help")) eng_ui_toggle_help(g_web.ui);

    if (!eng_editor_is_open(g_web.ed) || eng_editor_is_playing(g_web.ed)) {
        eng_runtime_step(g_web.rt, dt, err, sizeof(err));
    }
    if (!eng_xr_is_active(eng_runtime_xr(g_web.rt))) {
        int ww = 1280, wh = 720, pw = 1280, ph = 720;
        eng_platform_get_size(plat, &ww, &wh);
        eng_platform_get_pixel_size(plat, &pw, &ph);
        eng_renderer_resize(eng_runtime_renderer(g_web.rt), pw, ph);
        eng_runtime_render(g_web.rt, err, sizeof(err));
        eng_vec2_t mp = eng_input_mouse_pos(inp);
        eng_ui_begin_frame(g_web.ui, ww, wh, mp.x, mp.y, eng_input_down(inp, "fire"), eng_input_mouse_wheel(inp));
        eng_ui_set_fb_size(g_web.ui, pw, ph);
        draw_runtime_hud(g_web.ui, g_web.rt);
        /* HTML #touch-hud provides mobile touch controls on Web, so draw help without Nuklear touch duplicates */
        if (!eng_editor_is_open(g_web.ed)) eng_ui_draw_help(g_web.ui, g_web.rt);
        eng_ui_draw_console(g_web.ui, g_web.rt);
        eng_editor_draw_ui(g_web.ed, g_web.ui, eng_runtime_scene(g_web.rt), eng_runtime_portals(g_web.rt), g_web.prof);
        eng_ui_render(g_web.ui);
        eng_platform_swap(plat);
    }
    eng_profiler_end_frame(g_web.prof);
}

EMSCRIPTEN_KEEPALIVE void eng_web_toggle_help(void) {
    eng_ui_toggle_help(g_web.ui);
}

EMSCRIPTEN_KEEPALIVE void eng_web_inject_action(const char *action, int down) {
    if (g_web.rt && action) eng_input_inject_action(eng_runtime_input(g_web.rt), action, down != 0);
}

EMSCRIPTEN_KEEPALIVE void eng_web_inject_axis(const char *axis, float value) {
    if (g_web.rt && axis) eng_input_inject_axis(eng_runtime_input(g_web.rt), axis, value);
}

EMSCRIPTEN_KEEPALIVE void eng_web_submit_xr_frame(int fbo_id, const float *head7,
                                                  const float *eyes64, const int *vp8,
                                                  const float *hands24) {
    if (!g_web.rt || !head7 || !eyes64 || !vp8) return;
    eng_xr_pose_t head = {{head7[0], head7[1], head7[2]}, {head7[3], head7[4], head7[5], head7[6]}, true};
    eng_xr_eye_t eyes[2];
    memset(eyes, 0, sizeof(eyes));
    for (int e = 0; e < 2; e++) {
        memcpy(eyes[e].view.m, eyes64 + e * 32, 16 * sizeof(float));
        memcpy(eyes[e].proj.m, eyes64 + e * 32 + 16, 16 * sizeof(float));
        memcpy(eyes[e].viewport, vp8 + e * 4, 4 * sizeof(int));
    }
    eng_xr_hand_t hands[2];
    memset(hands, 0, sizeof(hands));
    if (hands24) {
        for (int h = 0; h < 2; h++) {
            const float *hp = hands24 + h * 12;
            hands[h].pose = (eng_xr_pose_t){{hp[0], hp[1], hp[2]}, {hp[3], hp[4], hp[5], hp[6]}, hp[11] > 0.5f};
            hands[h].trigger = hp[7];
            hands[h].grip = hp[8];
            hands[h].thumbstick = (eng_vec2_t){hp[9], hp[10]};
        }
    }
    eng_xr_submit_frame_state(eng_runtime_xr(g_web.rt), (uint32_t)fbo_id, &head, eyes, hands);
    char err[256] = {0};
    eng_runtime_render(g_web.rt, err, sizeof(err));
}

EMSCRIPTEN_KEEPALIVE void eng_web_end_xr(void) {
    if (g_web.rt) eng_xr_end_session(eng_runtime_xr(g_web.rt));
}
#endif

int eng_cli_run(int argc, char **argv) {
    const char *repo_root = ".";
    const char *game_dir = NULL;
    const char *mod_dir = NULL;
    const char *test_script = NULL;
    const char *capture_sheet = NULL;
    const char *new_dir = NULL;
    const char *tmpl = "fps";
    const char *gen_stubs = NULL;
    bool headless = false;
    bool doctor = false;
    int fuzz_seeds = 0;
    int max_frames = 0;
    int win_w = 0, win_h = 0;
    uint64_t seed = 42u;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "--version") == 0 || strcmp(a, "-v") == 0) {
            printf("Engine %s (%s)\n", eng_version_string(), eng_lua_runtime_name());
            return 0;
        } else if (strcmp(a, "--selfcheck") == 0) {
            const char *root = (i + 1 < argc) ? argv[++i] : ".";
            return eng_bootstrap_selfcheck(root, NULL) ? 0 : 1;
        } else if (strcmp(a, "--gen-stubs") == 0 && i + 1 < argc) {
            gen_stubs = argv[++i];
        } else if (strcmp(a, "--repo-root") == 0 && i + 1 < argc) {
            repo_root = argv[++i];
        } else if (strcmp(a, "--game") == 0 && i + 1 < argc) {
            game_dir = argv[++i];
        } else if (strcmp(a, "--mod") == 0 && i + 1 < argc) {
            mod_dir = argv[++i];
        } else if (strcmp(a, "--headless") == 0) {
            headless = true;
        } else if (strcmp(a, "--doctor") == 0) {
            doctor = true;
        } else if (strcmp(a, "--fuzz-seeds") == 0 && i + 1 < argc) {
            fuzz_seeds = atoi(argv[++i]);
        } else if (strcmp(a, "--capture-sheet") == 0 && i + 1 < argc) {
            capture_sheet = argv[++i];
        } else if (strcmp(a, "--test") == 0 && i + 1 < argc) {
            test_script = argv[++i];
        } else if (strcmp(a, "--seed") == 0 && i + 1 < argc) {
            seed = (uint64_t)strtoull(argv[++i], NULL, 10);
        } else if ((strcmp(a, "--max-frames") == 0 || strcmp(a, "--frames") == 0) && i + 1 < argc) {
            max_frames = atoi(argv[++i]);
        } else if (strcmp(a, "--width") == 0 && i + 1 < argc) {
            win_w = atoi(argv[++i]);
        } else if (strcmp(a, "--height") == 0 && i + 1 < argc) {
            win_h = atoi(argv[++i]);
        } else if (strcmp(a, "--new") == 0 && i + 1 < argc) {
            new_dir = argv[++i];
        } else if (strcmp(a, "--template") == 0 && i + 1 < argc) {
            tmpl = argv[++i];
        }
    }

    if (gen_stubs) {
        return eng_lua_write_api_stubs(gen_stubs) ? 0 : 1;
    }

    if (new_dir) {
        char err[256] = {0};
        if (!eng_scaffold_game(new_dir, tmpl, err, sizeof(err))) {
            fprintf(stderr, "Scaffold error: %s\n", err);
            return 1;
        }
        printf("Scaffolded '%s' (template: %s)\n", new_dir, tmpl);
        return 0;
    }

    if (!game_dir) {
        printf("Engine %s ready. Usage: engine [--game <dir>] [--headless] [--doctor] [--fuzz-seeds <N>] [--test <playtest.lua>] [--capture-sheet <out.png>] [--new <dir> --template <name>]\n",
               eng_version_string());
        return 0;
    }

    if (doctor && fuzz_seeds > 0) {
        eng_doctor_report_t rep;
        bool ok = eng_doctor_fuzz_game(repo_root, game_dir, mod_dir, fuzz_seeds, &rep);
        fputs(rep.summary, ok ? stdout : stderr);
        return ok ? 0 : 1;
    }

    eng_runtime_cfg_t rcfg = eng_runtime_default_cfg();
    rcfg.repo_root = repo_root;
    rcfg.game_dir = game_dir;
    rcfg.mod_dir = mod_dir;
    rcfg.headless = headless;
    if (win_w > 0) rcfg.width = win_w;
    if (win_h > 0) rcfg.height = win_h;
    rcfg.seed = seed;

    eng_runtime_t *rt = eng_runtime_create(&rcfg);
    if (!rt) return 1;

    char err[1024] = {0};
    if (!eng_runtime_boot_game(rt, err, sizeof(err))) {
        fprintf(stderr, "Boot failed (%s): %s\n", game_dir, err);
        eng_runtime_destroy(rt);
        return 1;
    }

    int rc = 0;
    if (doctor) {
        eng_doctor_report_t rep;
        bool ok = eng_doctor_audit(rt, &rep);
        fputs(rep.summary, ok ? stdout : stderr);
        if (!ok) rc = 1;
    }

    if (rc == 0 && test_script) {
        if (!eng_runtime_run_playtest(rt, test_script, max_frames > 0 ? max_frames : 600, err, sizeof(err))) {
            fprintf(stderr, "%s\n", err);
            rc = 1;
        } else {
            printf("[PLAYTEST PASS] %s (%s)\n", game_dir, test_script);
        }
    } else if (rc == 0 && !doctor) {
        /* Standard interactive or fixed-frame loop with Profiler, Nuklear HUD/Console (~) & Editor (F1/F5) */
        eng_platform_t *plat = eng_runtime_platform(rt);
        eng_input_t *inp = eng_runtime_input(rt);
        eng_input_bind_key(inp, "_toggle_editor", SDL_SCANCODE_F1);
        eng_input_bind_key(inp, "_toggle_pie", SDL_SCANCODE_F5);
        eng_input_bind_key(inp, "_toggle_console", SDL_SCANCODE_GRAVE);
        eng_input_bind_key(inp, "_toggle_help", SDL_SCANCODE_H);

        eng_profiler_t *prof = eng_profiler_create();
        eng_ui_t *ui = eng_ui_create();
        eng_editor_t *ed = eng_editor_create();
#ifdef __EMSCRIPTEN__
        if (!headless && max_frames == 0) {
            g_web.rt = rt;
            g_web.prof = prof;
            g_web.ui = ui;
            g_web.ed = ed;
            emscripten_set_main_loop(eng_web_tick_one, 0, 1);
            return 0;
        }
#endif
        int f = 0;
        while (!eng_platform_should_quit(plat)) {
            eng_profiler_begin_frame(prof);
            float dt = eng_platform_begin_frame(plat);
            eng_input_begin_frame(inp, dt);
            eng_input_poll_sdl(inp, plat);
            if (eng_input_pressed(inp, "_toggle_editor")) eng_editor_toggle(ed);
            if (eng_input_pressed(inp, "_toggle_pie")) eng_editor_toggle_pie(ed, eng_runtime_scene(rt), NULL, 0);
            if (eng_input_pressed(inp, "_toggle_console")) eng_ui_toggle_console(ui);
            if (eng_input_pressed(inp, "_toggle_help")) eng_ui_toggle_help(ui);

            eng_profiler_begin_scope(prof, "step");
            bool step_ok = (!eng_editor_is_open(ed) || eng_editor_is_playing(ed))
                               ? eng_runtime_step(rt, dt, err, sizeof(err))
                               : true;
            eng_profiler_end_scope(prof, "step");

            int ww = 1280, wh = 720, pw = 1280, ph = 720;
            eng_platform_get_size(plat, &ww, &wh);
            eng_platform_get_pixel_size(plat, &pw, &ph);
            eng_renderer_resize(eng_runtime_renderer(rt), pw, ph);

            eng_profiler_begin_scope(prof, "render");
            bool rend_ok = step_ok && eng_runtime_render(rt, err, sizeof(err));
            eng_profiler_end_scope(prof, "render");
            if (!rend_ok) {
                fprintf(stderr, "Runtime error: %s\n", err);
                rc = 1;
                break;
            }

            eng_vec2_t mp = eng_input_mouse_pos(inp);
            if (eng_editor_is_open(ed) && mp.x > 560.0f) {
                eng_camera_t *cam = eng_runtime_camera(rt);
                eng_vec2_t md = eng_input_mouse_delta(inp);
                eng_vec3_t rdir = eng_quat_rotate_v3(cam->rot, eng_v3(0.0f, 0.0f, -1.0f));
                eng_editor_viewport_interact(ed, eng_runtime_scene(rt), cam->pos, rdir,
                                             eng_input_pressed(inp, "fire"), eng_input_down(inp, "fire"), md.x, md.y);
            }
            eng_ui_begin_frame(ui, ww, wh, mp.x, mp.y, eng_input_down(inp, "fire"), eng_input_mouse_wheel(inp));
            eng_ui_set_fb_size(ui, pw, ph);
            draw_runtime_hud(ui, rt);
            if (!eng_editor_is_open(ed) && !eng_input_is_touch_active(inp)) eng_ui_draw_help(ui, rt);
            eng_ui_hud_touch_overlay(ui, inp);
            eng_ui_draw_console(ui, rt);
            eng_editor_draw_ui(ed, ui, eng_runtime_scene(rt), eng_runtime_portals(rt), prof);
            if (eng_editor_is_open(ed)) eng_ui_draw_profiler(ui, prof);
            eng_ui_render(ui);

            eng_platform_swap(plat);
            eng_profiler_end_frame(prof);
            f++;
            if ((max_frames > 0 && f >= max_frames) || (headless && max_frames == 0 && f >= 5)) break;
        }
        eng_editor_destroy(ed);
        eng_ui_destroy(ui);
        eng_profiler_destroy(prof);
    }

    if (rc == 0 && capture_sheet) {
        if (!eng_doctor_capture_sheet(rt, capture_sheet)) rc = 1;
    }

    eng_runtime_destroy(rt);
    return rc;
}
