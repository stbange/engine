#include "engine/engine.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif
#include <SDL3/SDL_keyboard.h>
#include <SDL3/SDL_timer.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static volatile sig_atomic_t g_srv_stop = 0;
static void on_srv_sig(int sig) { (void)sig; g_srv_stop = 1; }

static void game_slug_from_dir(const char *dir, char *out, size_t cap) {
    if (!out || cap == 0) return;
    if (!dir || !dir[0]) { snprintf(out, cap, "game"); return; }
    size_t len = strlen(dir);
    while (len > 1 && (dir[len - 1] == '/' || dir[len - 1] == '\\')) len--;
    size_t start = len;
    while (start > 0 && dir[start - 1] != '/' && dir[start - 1] != '\\') start--;
    size_t n = len - start;
    if (n == 0 || n >= cap) n = (n == 0) ? 0 : (cap - 1);
    if (n == 0) { snprintf(out, cap, "game"); return; }
    memcpy(out, dir + start, n);
    out[n] = '\0';
}

static bool parse_clip_spec(const char *spec, const eng_replay_t *rep, float *out_start, float *out_end) {
    if (!spec || !spec[0] || !out_start || !out_end) return false;
    if (strncmp(spec, "bookmark:", 9) == 0) {
        char buf[128];
        snprintf(buf, sizeof(buf), "%s", spec + 9);
        char *c1 = strchr(buf, ':');
        float pre = 3.0f, post = 2.0f;
        if (c1) {
            *c1++ = '\0';
            char *c2 = strchr(c1, ':');
            if (c2) { *c2++ = '\0'; post = (float)atof(c2); }
            pre = (float)atof(c1);
        }
        const eng_replay_bookmark_t *bm = eng_replay_find_bookmark(rep, buf);
        if (!bm) return false;
        *out_start = bm->time_sec > pre ? (bm->time_sec - pre) : 0.0f;
        *out_end = bm->time_sec + (post > 0.0f ? post : 0.1f);
        return true;
    }
    const char *colon = strchr(spec, ':');
    if (!colon) return false;
    *out_start = (float)atof(spec);
    *out_end = (float)atof(colon + 1);
    if (*out_start < 0.0f) *out_start = 0.0f;
    return *out_end > *out_start;
}

static size_t parse_shot_spec(const char *spec, const eng_replay_t *rep, float *out_times, size_t cap) {
    if (!spec || !spec[0] || !out_times || cap == 0) return 0;
    size_t n = 0;
    if (strcmp(spec, "bookmarks") == 0) {
        size_t bc = eng_replay_bookmark_count(rep);
        for (size_t i = 0; i < bc && n < cap; i++) {
            const eng_replay_bookmark_t *bm = eng_replay_bookmark_get(rep, i);
            if (bm) out_times[n++] = bm->time_sec;
        }
        return n;
    }
    const char *p = spec;
    while (*p && n < cap) {
        char *end = NULL;
        float v = strtof(p, &end);
        if (end == p) break;
        if (v >= 0.0f) out_times[n++] = v;
        p = (*end == ',') ? (end + 1) : end;
    }
    return n;
}

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
    bool pending_shot;
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
        if (g_web.pending_shot) {
            g_web.pending_shot = false;
            emscripten_run_script("if(window._engOnWebScreenshot)window._engOnWebScreenshot();");
        }
        eng_platform_swap(plat);
    }
    eng_profiler_end_frame(g_web.prof);
}

EMSCRIPTEN_KEEPALIVE void eng_web_request_screenshot(void) {
    g_web.pending_shot = true;
}

EMSCRIPTEN_KEEPALIVE void eng_web_toggle_help(void) {
    eng_ui_toggle_help(g_web.ui);
}

EMSCRIPTEN_KEEPALIVE int eng_web_wants_mouse_lock(void) {
    if (!g_web.rt) return 0;
    if (eng_editor_is_open(g_web.ed) || eng_ui_is_console_open(g_web.ui)) return 0;
    return eng_platform_wants_mouse_lock(eng_runtime_platform(g_web.rt)) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE void eng_web_set_mouse_lock_state(int locked) {
    if (g_web.rt) eng_platform_sync_mouse_lock(eng_runtime_platform(g_web.rt), locked != 0);
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
    const char *bind_ip = NULL;
    const char *connect_url = NULL;
    const char *net_transport = "ws";
    const char *rec_replay_path = NULL;
    const char *play_replay_path = NULL;
    const char *rec_video_path = NULL;
    const char *preset_name = NULL;
    const char *clip_spec = NULL;
    const char *shot_spec = NULL;
    const char *out_dir = "captures";
    const char *director_path = NULL;
    bool headless = false;
    bool is_server = false;
    bool doctor = false;
    bool clean_feed = false;
    int fuzz_seeds = 0;
    int max_frames = 0;
    int tick_rate = 30;
    int win_w = 0, win_h = 0;
    int cap_fps = 0;
    float cap_speed = 1.0f;
    uint16_t server_port = 7777u;
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
        } else if (strcmp(a, "--server") == 0) {
            is_server = true;
            headless = true;
        } else if (strcmp(a, "--port") == 0 && i + 1 < argc) {
            server_port = (uint16_t)atoi(argv[++i]);
        } else if (strcmp(a, "--bind") == 0 && i + 1 < argc) {
            bind_ip = argv[++i];
        } else if (strcmp(a, "--tick-rate") == 0 && i + 1 < argc) {
            tick_rate = atoi(argv[++i]);
        } else if (strcmp(a, "--transport") == 0 && i + 1 < argc) {
            net_transport = argv[++i];
        } else if (strcmp(a, "--connect") == 0 && i + 1 < argc) {
            connect_url = argv[++i];
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
        } else if (strcmp(a, "--record-replay") == 0 && i + 1 < argc) {
            rec_replay_path = argv[++i];
        } else if (strcmp(a, "--replay") == 0 && i + 1 < argc) {
            play_replay_path = argv[++i];
        } else if (strcmp(a, "--record-video") == 0 && i + 1 < argc) {
            rec_video_path = argv[++i];
        } else if (strcmp(a, "--preset") == 0 && i + 1 < argc) {
            preset_name = argv[++i];
        } else if (strcmp(a, "--fps") == 0 && i + 1 < argc) {
            cap_fps = atoi(argv[++i]);
        } else if (strcmp(a, "--clip") == 0 && i + 1 < argc) {
            clip_spec = argv[++i];
        } else if (strcmp(a, "--screenshot-at") == 0 && i + 1 < argc) {
            shot_spec = argv[++i];
        } else if (strcmp(a, "--out-dir") == 0 && i + 1 < argc) {
            out_dir = argv[++i];
        } else if (strcmp(a, "--clean-feed") == 0) {
            clean_feed = true;
        } else if (strcmp(a, "--speed") == 0 && i + 1 < argc) {
            cap_speed = (float)atof(argv[++i]);
        } else if (strcmp(a, "--director") == 0 && i + 1 < argc) {
            director_path = argv[++i];
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
        printf("Engine %s ready. Usage: engine [--game <dir>] [--headless] [--server --port <N>] [--connect <url>] [--doctor] [--test <playtest.lua>] [--record-replay <f.engrep>] [--replay <f.engrep> --record-video <out.mp4> --preset <youtube|reel|square|gif>] [--new <dir> --template <name>]\n",
               eng_version_string());
        return 0;
    }

    if (doctor && fuzz_seeds > 0) {
        eng_doctor_report_t rep;
        bool ok = eng_doctor_fuzz_game(repo_root, game_dir, mod_dir, fuzz_seeds, &rep);
        fputs(rep.summary, ok ? stdout : stderr);
        return ok ? 0 : 1;
    }

    int cap_w = 0, cap_h = 0, preset_fps = 60;
    if (preset_name) {
        if (!eng_capture_resolve_preset(preset_name, &cap_w, &cap_h, &preset_fps)) {
            fprintf(stderr, "Unknown capture preset: %s (expected youtube, youtube4k, reel, shorts, tiktok, square, gif)\n", preset_name);
            return 1;
        }
    }
    if (win_w > 0) cap_w = win_w;
    if (win_h > 0) cap_h = win_h;
    if (cap_fps <= 0) cap_fps = preset_fps;
    cap_speed = eng_clampf(cap_speed, 0.25f, 4.0f);

    eng_replay_t *play_rep = NULL;
    if (play_replay_path) {
        play_rep = eng_replay_load_file(play_replay_path);
        if (!play_rep) {
            fprintf(stderr, "Failed to load replay: %s\n", play_replay_path);
            return 1;
        }
        seed = eng_replay_seed(play_rep);
    }

    float clip_start = 0.0f, clip_end = 1e9f;
    bool has_clip = false;
    if (clip_spec) {
        if (!parse_clip_spec(clip_spec, play_rep, &clip_start, &clip_end)) {
            fprintf(stderr, "Invalid --clip spec: %s\n", clip_spec);
            eng_replay_destroy(play_rep);
            return 1;
        }
        has_clip = true;
    }

    float shot_times[64];
    bool shot_taken[64];
    memset(shot_taken, 0, sizeof(shot_taken));
    size_t shot_count = parse_shot_spec(shot_spec, play_rep, shot_times, 64);

    char slug[64];
    game_slug_from_dir(game_dir, slug, sizeof(slug));

    bool use_offscreen_cap = (preset_name != NULL) || ((rec_video_path != NULL || shot_count > 0) && (cap_w > 0 || cap_h > 0 || headless));
    eng_runtime_cfg_t rcfg = eng_runtime_default_cfg();
    rcfg.repo_root = repo_root;
    rcfg.game_dir = game_dir;
    rcfg.mod_dir = mod_dir;
    rcfg.headless = headless;
    if (use_offscreen_cap) {
        if (cap_w <= 0) cap_w = 1280;
        if (cap_h <= 0) cap_h = 720;
        /* Keep host window compact when rendering 4K/portrait offscreen FBOs */
        rcfg.width = cap_w > 1280 ? 1280 : cap_w;
        rcfg.height = cap_h > 720 ? 720 : cap_h;
    } else {
        if (win_w > 0) rcfg.width = win_w;
        if (win_h > 0) rcfg.height = win_h;
    }
    rcfg.seed = seed;
    rcfg.is_server = is_server;
    rcfg.bind_ip = bind_ip;
    rcfg.server_port = server_port;
    rcfg.connect_url = connect_url;
    rcfg.net_transport = net_transport;

    eng_runtime_t *rt = eng_runtime_create(&rcfg);
    if (!rt) {
        eng_replay_destroy(play_rep);
        return 1;
    }

    char err[1024] = {0};
    if (!eng_runtime_boot_game(rt, err, sizeof(err))) {
        fprintf(stderr, "Boot failed (%s): %s\n", game_dir, err);
        eng_replay_destroy(play_rep);
        eng_runtime_destroy(rt);
        return 1;
    }

    eng_replay_t *rec_rep = NULL;
    char rec_rep_out[512] = {0};
    if (rec_replay_path) {
        rec_rep = eng_replay_create(slug, seed, 60u);
        snprintf(rec_rep_out, sizeof(rec_rep_out), "%s", rec_replay_path);
    }

    eng_capture_t *live_cap = NULL;
    eng_runtime_attach_media(rt, rec_rep, play_rep, &live_cap, &clean_feed);

    if (director_path && !eng_runtime_load_director(rt, director_path, err, sizeof(err))) {
        fprintf(stderr, "Director script error: %s\n", err);
        eng_replay_destroy(rec_rep);
        eng_replay_destroy(play_rep);
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
    } else if (rc == 0 && !doctor && is_server) {
        /* Headless fixed-tick authoritative game server loop (no swap/UI/renderer work) */
        if (tick_rate < 1) tick_rate = 1;
        if (tick_rate > 240) tick_rate = 240;
        float dt = 1.0f / (float)tick_rate;
        uint64_t step_ns = (uint64_t)(1000000000ull / (uint64_t)tick_rate);
        g_srv_stop = 0;
        signal(SIGINT, on_srv_sig);
        signal(SIGTERM, on_srv_sig);
        int f = 0;
        while (!g_srv_stop) {
            uint64_t t0 = SDL_GetTicksNS();
            if (!eng_runtime_step(rt, dt, err, sizeof(err))) {
                fprintf(stderr, "Server error: %s\n", err);
                rc = 1;
                break;
            }
            f++;
            if (max_frames > 0 && f >= max_frames) break;
            if (max_frames == 0) {
                uint64_t el = SDL_GetTicksNS() - t0;
                if (el < step_ns) SDL_DelayNS(step_ns - el);
            }
        }
    } else if (rc == 0 && !doctor) {
        /* Interactive or deterministic replay/export loop with HUD, Editor, and Media Capture */
        eng_platform_t *plat = eng_runtime_platform(rt);
        eng_input_t *inp = eng_runtime_input(rt);
        eng_renderer_t *rend = eng_runtime_renderer(rt);
        eng_audio_t *aud = eng_runtime_audio(rt);
        eng_input_bind_key(inp, "_toggle_editor", SDL_SCANCODE_F1);
        eng_input_bind_key(inp, "_toggle_pie", SDL_SCANCODE_F5);
        eng_input_bind_key(inp, "_toggle_console", SDL_SCANCODE_GRAVE);
        eng_input_bind_key(inp, "_toggle_help", SDL_SCANCODE_H);
        eng_input_bind_key(inp, "_unlock_mouse", SDL_SCANCODE_ESCAPE);
        eng_input_bind_key(inp, "_capture_shot", SDL_SCANCODE_F12);
        eng_input_bind_key(inp, "_capture_video", SDL_SCANCODE_F9);
        eng_input_bind_key(inp, "_capture_bookmark", SDL_SCANCODE_F10);
        eng_input_bind_key(inp, "_capture_clean", SDL_SCANCODE_F11);

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
        if (use_offscreen_cap) {
            eng_renderer_set_capture_target(rend, cap_w, cap_h);
            eng_ui_set_target_fbo(ui, eng_renderer_output_fbo(rend));
        }

        bool video_audio_wired = false;
        if (rec_video_path) {
            int vw = cap_w, vh = cap_h;
            if (vw <= 0 || vh <= 0) eng_renderer_get_size(rend, &vw, &vh);
            eng_capture_cfg_t ccfg = eng_capture_default_cfg(rec_video_path, vw, vh, cap_fps);
            ccfg.speed = cap_speed;
            ccfg.fast_live = (play_rep == NULL && !headless);
            live_cap = eng_capture_start(&ccfg);
            if (!live_cap) {
                fprintf(stderr, "Failed to start video capture: %s\n", rec_video_path);
                rc = 1;
            }
        }

        int f = 0;
        uint32_t seq_shot = 0, seq_vid = 0, seq_rep = 0;
        float sim_t = 0.0f;
        float frame_accum = 0.999f;
        bool was_in_clip = false;

        while (rc == 0 && !eng_platform_should_quit(plat)) {
            eng_profiler_begin_frame(prof);
            float dt = eng_platform_begin_frame(plat);
            eng_input_begin_frame(inp, dt);
            eng_input_poll_sdl(inp, plat);

            if (play_rep) {
                float rep_dt = 1.0f / 60.0f;
                if (!eng_replay_step_playback(play_rep, inp, &rep_dt)) break;
                dt = rep_dt;
            } else if (headless && (rec_video_path || shot_count > 0)) {
                dt = 1.0f / 60.0f;
            }

            if (eng_input_pressed(inp, "_toggle_editor")) eng_editor_toggle(ed);
            if (eng_input_pressed(inp, "_toggle_pie")) eng_editor_toggle_pie(ed, eng_runtime_scene(rt), NULL, 0);
            if (eng_input_pressed(inp, "_toggle_console")) eng_ui_toggle_console(ui);
            if (eng_input_pressed(inp, "_toggle_help")) eng_ui_toggle_help(ui);
            if (eng_input_pressed(inp, "_capture_clean")) clean_feed = !clean_feed;

            bool want_shot = eng_input_pressed(inp, "_capture_shot");
            if (eng_input_pressed(inp, "_capture_bookmark") && rec_rep) {
                eng_replay_add_bookmark(rec_rep, "highlight");
            }
            if (eng_input_pressed(inp, "_capture_video")) {
                if ((SDL_GetModState() & SDL_KMOD_SHIFT) != 0) {
                    if (rec_rep) {
                        eng_replay_save_file(rec_rep, rec_rep_out);
                        eng_replay_destroy(rec_rep);
                        rec_rep = NULL;
                        eng_runtime_attach_media(rt, NULL, play_rep, &live_cap, &clean_feed);
                    } else if (!play_rep) {
                        snprintf(rec_rep_out, sizeof(rec_rep_out), "%s/%s_rep_%03u.engrep", out_dir, slug, ++seq_rep);
                        rec_rep = eng_replay_create(slug, seed, 60u);
                        eng_runtime_attach_media(rt, rec_rep, play_rep, &live_cap, &clean_feed);
                    }
                } else {
                    if (live_cap) {
                        eng_audio_set_capture_cb(aud, NULL, NULL);
                        eng_capture_stop(live_cap);
                        live_cap = NULL;
                        video_audio_wired = false;
                    } else {
                        char vp[512];
                        snprintf(vp, sizeof(vp), "%s/%s_vid_%03u.mp4", out_dir, slug, ++seq_vid);
                        int vw = 0, vh = 0;
                        eng_renderer_get_size(rend, &vw, &vh);
                        eng_capture_cfg_t ccfg = eng_capture_default_cfg(vp, vw, vh, cap_fps);
                        ccfg.fast_live = true;
                        live_cap = eng_capture_start(&ccfg);
                    }
                }
            }

            if (eng_input_pressed(inp, "_unlock_mouse") || eng_editor_is_open(ed) || eng_ui_is_console_open(ui)) {
                if (eng_platform_is_mouse_lock(plat)) eng_platform_sync_mouse_lock(plat, false);
            } else if (!play_rep && eng_platform_wants_mouse_lock(plat) && !eng_platform_is_mouse_lock(plat) && eng_input_pressed(inp, "fire")) {
                eng_platform_sync_mouse_lock(plat, true);
            }

            if (rec_rep && !play_rep) eng_replay_record_frame(rec_rep, inp, dt);

            bool in_clip = !has_clip || (sim_t >= clip_start && sim_t <= clip_end);
            if (live_cap && in_clip && !video_audio_wired) {
                eng_audio_set_capture_cb(aud, eng_capture_push_audio, live_cap);
                video_audio_wired = true;
            } else if (live_cap && !in_clip && video_audio_wired) {
                eng_audio_set_capture_cb(aud, NULL, NULL);
                video_audio_wired = false;
            }
            if (in_clip && !was_in_clip) frame_accum = 0.999f;
            was_in_clip = in_clip;

            eng_profiler_begin_scope(prof, "step");
            bool step_ok = (!eng_editor_is_open(ed) || eng_editor_is_playing(ed))
                               ? eng_runtime_step(rt, dt, err, sizeof(err))
                               : true;
            eng_profiler_end_scope(prof, "step");
            sim_t += dt;

            if (director_path) eng_runtime_apply_director(rt, (uint32_t)f);

            int ww = 1280, wh = 720, pw = 1280, ph = 720;
            if (use_offscreen_cap) {
                eng_renderer_get_size(rend, &pw, &ph);
                ww = pw; wh = ph;
            } else {
                eng_platform_get_size(plat, &ww, &wh);
                eng_platform_get_pixel_size(plat, &pw, &ph);
                eng_renderer_resize(rend, pw, ph);
            }

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

            if (!clean_feed) {
                eng_ui_begin_frame(ui, ww, wh, mp.x, mp.y, eng_input_down(inp, "fire"), eng_input_mouse_wheel(inp));
                eng_ui_set_fb_size(ui, pw, ph);
                draw_runtime_hud(ui, rt);
                if (!play_rep && !rec_video_path) {
                    if (!eng_editor_is_open(ed) && !eng_input_is_touch_active(inp)) eng_ui_draw_help(ui, rt);
                    eng_ui_hud_touch_overlay(ui, inp);
                    eng_ui_draw_console(ui, rt);
                    eng_editor_draw_ui(ed, ui, eng_runtime_scene(rt), eng_runtime_portals(rt), prof);
                    if (eng_editor_is_open(ed)) eng_ui_draw_profiler(ui, prof);
                }
                eng_ui_render(ui);
            }

            if (live_cap && in_clip) {
                if (play_rep || headless) {
                    frame_accum += dt * ((float)cap_fps / cap_speed);
                    while (frame_accum >= 1.0f) {
                        eng_capture_push_video_frame(live_cap, rend);
                        frame_accum -= 1.0f;
                    }
                } else {
                    eng_capture_push_video_frame(live_cap, rend);
                }
            }

            if (want_shot) {
                char sp[512];
                snprintf(sp, sizeof(sp), "%s/%s_shot_%03u.png", out_dir, slug, ++seq_shot);
                eng_capture_screenshot(rend, sp);
            }
            for (size_t si = 0; si < shot_count; si++) {
                if (!shot_taken[si] && sim_t >= shot_times[si]) {
                    shot_taken[si] = true;
                    char sp[512];
                    snprintf(sp, sizeof(sp), "%s/%s_shot_%02zu.png", out_dir, slug, si + 1u);
                    eng_capture_screenshot(rend, sp);
                }
            }

            /* Draw subtle live REC badge AFTER capture readback so it never pollutes exports */
            if (!use_offscreen_cap && !headless && (live_cap || rec_rep)) {
                eng_ui_begin_frame(ui, ww, wh, mp.x, mp.y, false, 0.0f);
                eng_ui_set_fb_size(ui, pw, ph);
                const char *badge = (live_cap && rec_rep) ? "[REC VID+REP]" : (live_cap ? "[REC VID]" : "[REC REP]");
                eng_ui_hud_label(ui, "__rec_badge", ENG_UI_TOP_RIGHT, 12.0f, 12.0f, 150.0f, 26.0f, badge);
                eng_ui_render(ui);
            }

            eng_platform_swap(plat);
            eng_profiler_end_frame(prof);
            f++;
            if (has_clip && sim_t > clip_end) break;
            if (max_frames > 0 && f >= max_frames) break;
            if (headless && max_frames == 0 && !play_rep && shot_count == 0 && f >= 5) break;
            if (headless && max_frames == 0 && !play_rep && shot_count > 0) {
                bool all_done = true;
                for (size_t si = 0; si < shot_count; si++) if (!shot_taken[si]) all_done = false;
                if (all_done) break;
            }
        }

        if (live_cap) {
            eng_audio_set_capture_cb(aud, NULL, NULL);
            if (!eng_capture_stop(live_cap)) rc = 1;
            live_cap = NULL;
        }
        if (use_offscreen_cap) {
            eng_ui_set_target_fbo(ui, 0u);
            eng_renderer_set_capture_target(rend, 0, 0);
        }
        eng_editor_destroy(ed);
        eng_ui_destroy(ui);
        eng_profiler_destroy(prof);
    }

    if (rec_rep) {
        if (!eng_replay_save_file(rec_rep, rec_rep_out)) {
            fprintf(stderr, "Failed to save replay: %s\n", rec_rep_out);
            rc = 1;
        }
        eng_replay_destroy(rec_rep);
    }
    if (play_rep) {
        eng_input_clear_replay_override(eng_runtime_input(rt));
        eng_replay_destroy(play_rep);
    }

    if (rc == 0 && capture_sheet) {
        if (!eng_doctor_capture_sheet(rt, capture_sheet)) rc = 1;
    }

    eng_runtime_destroy(rt);
    return rc;
}
