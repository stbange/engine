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
#ifndef _WIN32
#include <sys/stat.h>
#include <unistd.h>
#endif

static uint32_t rd_be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}
static uint32_t rd_le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static uint16_t rd_le16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static bool read_png_dims(const char *path, uint32_t *out_w, uint32_t *out_h) {
    FILE *fp = fopen(path, "rb");
    if (!fp) return false;
    uint8_t hdr[24];
    size_t n = fread(hdr, 1, sizeof(hdr), fp);
    fclose(fp);
    if (n < 24) return false;
    if (hdr[0] != 0x89 || hdr[1] != 'P' || hdr[2] != 'N' || hdr[3] != 'G') return false;
    if (out_w) *out_w = rd_be32(hdr + 16);
    if (out_h) *out_h = rd_be32(hdr + 20);
    return true;
}

static void test_presets_and_atempo(void) {
    int w = 0, h = 0, fps = 0;
    assert(eng_capture_resolve_preset("youtube", &w, &h, &fps) && w == 1920 && h == 1080 && fps == 60);
    assert(eng_capture_resolve_preset("landscape", &w, &h, &fps) && w == 1920 && h == 1080 && fps == 60);
    assert(eng_capture_resolve_preset("youtube4k", &w, &h, &fps) && w == 3840 && h == 2160 && fps == 60);
    assert(eng_capture_resolve_preset("4k", &w, &h, &fps) && w == 3840 && h == 2160);
    assert(eng_capture_resolve_preset("reel", &w, &h, &fps) && w == 1080 && h == 1920 && fps == 60);
    assert(eng_capture_resolve_preset("shorts", &w, &h, &fps) && w == 1080 && h == 1920);
    assert(eng_capture_resolve_preset("tiktok", &w, &h, &fps) && w == 1080 && h == 1920);
    assert(eng_capture_resolve_preset("vertical", &w, &h, &fps) && w == 1080 && h == 1920);
    assert(eng_capture_resolve_preset("square", &w, &h, &fps) && w == 1080 && h == 1080 && fps == 60);
    assert(eng_capture_resolve_preset("instagram", &w, &h, &fps) && w == 1080 && h == 1080);
    assert(eng_capture_resolve_preset("gif", &w, &h, &fps) && w == 640 && h == 360 && fps == 24);
    assert(!eng_capture_resolve_preset("unknown_preset", &w, &h, &fps));
    assert(!eng_capture_resolve_preset(NULL, &w, &h, &fps));

    char buf[96];
    assert(!eng_capture_build_atempo(1.0f, buf, sizeof(buf)));
    assert(!eng_capture_build_atempo(0.5f, NULL, 0));
    assert(eng_capture_build_atempo(0.5f, buf, sizeof(buf)) && strcmp(buf, "atempo=0.5000") == 0);
    assert(eng_capture_build_atempo(0.25f, buf, sizeof(buf)) && strcmp(buf, "atempo=0.5,atempo=0.5000") == 0);
    assert(eng_capture_build_atempo(2.0f, buf, sizeof(buf)) && strcmp(buf, "atempo=2.0000") == 0);
    assert(eng_capture_build_atempo(4.0f, buf, sizeof(buf)) && strcmp(buf, "atempo=2.0,atempo=2.0000") == 0);

    /* Reject control characters / empty paths / invalid args */
    eng_capture_cfg_t bad = eng_capture_default_cfg("bad\npath.mp4", 160, 120, 60);
    assert(eng_capture_start(&bad) == NULL);
    eng_capture_cfg_t empty = eng_capture_default_cfg("", 160, 120, 60);
    assert(eng_capture_start(&empty) == NULL);
    assert(eng_capture_start(NULL) == NULL);
    assert(!eng_capture_stop(NULL));
    assert(eng_capture_frame_count(NULL) == 0u);
    assert(eng_capture_audio_frames(NULL) == 0ull);
    assert(!eng_capture_is_using_ffmpeg(NULL));
    assert(strcmp(eng_capture_output_path(NULL), "") == 0);
}

static void run_determinism_pass(eng_replay_t *rep, float *out_x, float *out_z, float *out_yaw, float *out_rng) {
    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.game_dir = ENG_SOURCE_DIR "/games/001_catacomb_blitz";
    cfg.headless = true;
    cfg.width = 160;
    cfg.height = 120;
    cfg.seed = eng_replay_seed(rep);

    eng_runtime_t *rt = eng_runtime_create(&cfg);
    assert(rt != NULL);
    char err[512] = {0};
    assert(eng_runtime_boot_game(rt, err, sizeof(err)));

    /* Inject tiny deterministic state probe that reads actions, axes, mouse deltas, 4P stick & RNG */
    const char *probe =
        "__det = { x = 0, z = 0, yaw = 0, r = 0 }\n"
        "local _orig_upd = update\n"
        "function update(dt)\n"
        "  if _orig_upd then _orig_upd(dt) end\n"
        "  if eng.input.down('up') then __det.z = __det.z - dt * 5 end\n"
        "  if eng.input.down('right') then __det.x = __det.x + dt * 3 end\n"
        "  local dx, dy = eng.input.mouse_delta()\n"
        "  __det.yaw = __det.yaw + dx * 0.01 + dy * 0.005\n"
        "  local p2x, p2y = eng.input.player_move(2)\n"
        "  __det.x = __det.x + p2x * dt\n"
        "  __det.z = __det.z + p2y * dt\n"
        "  __det.r = eng.math.rand() + math.random()\n"
        "end\n";
    assert(eng_runtime_exec_lua(rt, "det_probe", probe, err, sizeof(err)));

    eng_input_t *inp = eng_runtime_input(rt);
    eng_replay_rewind(rep);
    float dt = 0.0f;
    float throttle_sum = 0.0f;
    while (eng_replay_step_playback(rep, inp, &dt)) {
        throttle_sum += eng_input_axis(inp, "throttle") * dt;
        if (!eng_runtime_step(rt, dt, err, sizeof(err))) {
            fprintf(stderr, "step err: %s\n", err);
            assert(false);
        }
    }
    assert(throttle_sum > 0.2f);
    assert(eng_replay_cursor(rep) == eng_replay_frame_count(rep));

    char res[256] = {0};
    assert(eng_runtime_exec_lua(rt, "det_read",
        "return string.format('%.6f %.6f %.6f %.6f', __det.x, __det.z, __det.yaw, __det.r)",
        res, sizeof(res)));
    assert(sscanf(res, "%f %f %f %f", out_x, out_z, out_yaw, out_rng) == 4);

    eng_input_clear_replay_override(inp);
    eng_runtime_destroy(rt);
}

static void test_replay_determinism_and_bookmarks(void) {
    eng_input_t *inp = eng_input_create();
    assert(inp != NULL);
    eng_input_bind_key(inp, "up", SDL_SCANCODE_W);
    eng_input_bind_key(inp, "right", SDL_SCANCODE_D);
    eng_input_bind_key(inp, "fire", SDL_SCANCODE_SPACE);
    eng_input_bind_key(inp, "_capture_shot", SDL_SCANCODE_F12);

    eng_replay_t *rep = eng_replay_create("001_catacomb_blitz", 1337u, 60u);
    assert(rep != NULL);

    for (int f = 0; f < 30; f++) {
        eng_input_begin_frame(inp, 1.0f / 60.0f);
        eng_input_inject_action(inp, "up", f < 20);
        eng_input_inject_action(inp, "right", (f % 3) == 0);
        eng_input_inject_action(inp, "fire", f == 12);
        eng_input_inject_axis(inp, "throttle", (f >= 10) ? 0.75f : 0.0f);
        eng_input_inject_mouse_delta(inp, (f % 2 == 0) ? 2.5f : -1.0f, 0.5f);
        eng_input_inject_player_action(inp, 1, "right", true);
        eng_input_inject_player_action(inp, 1, "up", (f % 2) == 0);
        assert(eng_replay_record_frame(rep, inp, 1.0f / 60.0f));
        if (f == 5) assert(eng_replay_add_bookmark(rep, "opening"));
        if (f == 18) assert(eng_replay_add_bookmark(rep, "combo_kill"));
    }

    assert(eng_replay_frame_count(rep) == 30u);
    assert(fabsf(eng_replay_duration(rep) - 0.5f) < 0.01f);
    assert(eng_replay_seed(rep) == 1337u);
    assert(eng_replay_target_fps(rep) == 60u);
    assert(strcmp(eng_replay_game_id(rep), "001_catacomb_blitz") == 0);
    assert(eng_replay_bookmark_count(rep) == 2u);
    const eng_replay_bookmark_t *bm = eng_replay_find_bookmark(rep, "combo_kill");
    assert(bm != NULL && bm->frame == 19u);
    assert(eng_replay_find_bookmark(rep, "missing") == NULL);

    const char *rpath = ENG_BINARY_DIR "/test_phase9_out/det_run.engrep";
    assert(eng_replay_save_file(rep, rpath));
    eng_replay_destroy(rep);
    eng_input_destroy(inp);

    assert(eng_replay_load_file(ENG_BINARY_DIR "/test_phase9_out/does_not_exist.engrep") == NULL);

    /* Corrupt file rejection */
    const char *bad_path = ENG_BINARY_DIR "/test_phase9_out/bad.engrep";
    FILE *bf = fopen(bad_path, "wb");
    assert(bf != NULL);
    fwrite("NOPE", 1, 4, bf);
    fclose(bf);
    assert(eng_replay_load_file(bad_path) == NULL);

    eng_replay_t *loaded = eng_replay_load_file(rpath);
    assert(loaded != NULL);
    assert(eng_replay_frame_count(loaded) == 30u);
    assert(eng_replay_bookmark_count(loaded) == 2u);
    assert(eng_replay_bookmark_get(loaded, 0) != NULL);
    assert(eng_replay_bookmark_get(loaded, 99) == NULL);

    float x1 = 0, z1 = 0, y1 = 0, r1 = 0;
    float x2 = 0, z2 = 0, y2 = 0, r2 = 0;
    run_determinism_pass(loaded, &x1, &z1, &y1, &r1);
    run_determinism_pass(loaded, &x2, &z2, &y2, &r2);
    assert(x1 == x2 && z1 == z2 && y1 == y2 && r1 == r2);
    assert(fabsf(z1) > 0.1f && fabsf(x1) > 0.1f && fabsf(y1) > 0.01f);

    eng_replay_destroy(loaded);
}

static void test_audio_wav_and_fallback_capture(void) {
    eng_audio_t *aud = eng_audio_create(true);
    assert(aud != NULL);

    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.game_dir = ENG_SOURCE_DIR "/games/001_catacomb_blitz";
    cfg.headless = true;
    cfg.width = 160;
    cfg.height = 120;
    eng_runtime_t *rt = eng_runtime_create(&cfg);
    assert(rt != NULL);
    char err[256] = {0};
    assert(eng_runtime_boot_game(rt, err, sizeof(err)));

    eng_renderer_t *rend = eng_runtime_renderer(rt);
    assert(eng_renderer_set_capture_target(rend, 160, 120));

    const char *vout = ENG_BINARY_DIR "/test_phase9_out/fallback_clip.mp4";
    eng_capture_cfg_t ccfg = eng_capture_default_cfg(vout, 160, 120, 60);
    ccfg.force_fallback = true;
    eng_capture_t *cap = eng_capture_start(&ccfg);
    assert(cap != NULL);
    assert(!eng_capture_is_using_ffmpeg(cap));
    assert(strcmp(eng_capture_output_path(cap), vout) == 0);

    eng_audio_set_capture_cb(aud, eng_capture_push_audio, cap);
    eng_synth_desc_t sd = eng_synth_default_desc(ENG_WAVE_SQUARE, 440.0f, 0.35f);
    sd.gain = 0.8f;
    uint32_t clip = eng_audio_synth_retro(aud, &sd);
    assert(clip != 0u);
    eng_voice_desc_t vd = eng_voice_default_desc(clip);
    vd.spatial_3d = false;
    vd.gain = 0.9f;
    assert(eng_audio_play(aud, &vd) != 0u);
    for (int f = 0; f < 6; f++) {
        eng_audio_update(aud, NULL, NULL, 1.0f / 60.0f);
        assert(eng_runtime_render(rt, err, sizeof(err)));
        assert(eng_capture_push_video_frame(cap, rend));
    }
    eng_audio_set_capture_cb(aud, NULL, NULL);
    assert(eng_capture_frame_count(cap) == 6u);
    assert(eng_capture_audio_frames(cap) >= 4000ull);
    assert(eng_capture_stop(cap));

    uint32_t pw = 0, ph = 0;
    assert(read_png_dims(ENG_BINARY_DIR "/test_phase9_out/fallback_clip.mp4_frames/frame_000000.png", &pw, &ph));
    assert(pw == 160u && ph == 120u);

    /* Validate 48 kHz 16-bit stereo RIFF WAV header & non-zero SFX energy */
    FILE *wf = fopen(ENG_BINARY_DIR "/test_phase9_out/fallback_clip.mp4_frames/audio.wav", "rb");
    assert(wf != NULL);
    uint8_t wh[44];
    assert(fread(wh, 1, 44, wf) == 44);
    assert(memcmp(wh, "RIFF", 4) == 0 && memcmp(wh + 8, "WAVE", 4) == 0);
    assert(rd_le16(wh + 22) == 2u);
    assert(rd_le32(wh + 24) == 48000u);
    assert(rd_le16(wh + 34) == 16u);
    uint32_t data_bytes = rd_le32(wh + 40);
    assert(data_bytes >= 16000u);

    int16_t samples[256];
    size_t sr = fread(samples, sizeof(int16_t), 256, wf);
    fclose(wf);
    int peak = 0;
    for (size_t i = 0; i < sr; i++) {
        int a = samples[i] < 0 ? -samples[i] : samples[i];
        if (a > peak) peak = a;
    }
    assert(peak > 100);

    assert(eng_renderer_set_capture_target(rend, 0, 0));
    eng_runtime_destroy(rt);
    eng_audio_destroy(aud);
}

static void test_offscreen_fbo_portrait_and_landscape(void) {
    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.game_dir = ENG_SOURCE_DIR "/games/001_catacomb_blitz";
    cfg.headless = false; /* Real GL 3.3 Core under xvfb-run, auto-fallback otherwise */
    cfg.width = 240;
    cfg.height = 180;
    eng_runtime_t *rt = eng_runtime_create(&cfg);
    assert(rt != NULL);
    char err[256] = {0};
    assert(eng_runtime_boot_game(rt, err, sizeof(err)));
    assert(eng_runtime_step(rt, 1.0f / 60.0f, err, sizeof(err)));

    eng_renderer_t *rend = eng_runtime_renderer(rt);
    eng_ui_t *ui = eng_ui_create();

    /* 9:16 Portrait capture FBO (180x320) */
    assert(eng_renderer_set_capture_target(rend, 180, 320));
    eng_ui_set_target_fbo(ui, eng_renderer_output_fbo(rend));
    assert(eng_runtime_render(rt, err, sizeof(err)));
    eng_ui_begin_frame(ui, 180, 320, 0, 0, false, 0.0f);
    eng_ui_set_fb_size(ui, 180, 320);
    eng_ui_hud_label(ui, "__reel_hud", ENG_UI_TOP_LEFT, 8.0f, 8.0f, 160.0f, 24.0f, "REEL 9:16");
    eng_ui_render(ui);

    const char *p_shot = ENG_BINARY_DIR "/test_phase9_out/portrait_9x16.png";
    assert(eng_capture_screenshot(rend, p_shot));
    uint32_t pw = 0, ph = 0;
    assert(read_png_dims(p_shot, &pw, &ph) && pw == 180u && ph == 320u);

    /* 16:9 Landscape capture FBO (320x180) */
    assert(eng_renderer_set_capture_target(rend, 320, 180));
    eng_ui_set_target_fbo(ui, eng_renderer_output_fbo(rend));
    assert(eng_runtime_render(rt, err, sizeof(err)));
    const char *l_shot = ENG_BINARY_DIR "/test_phase9_out/landscape_16x9.png";
    assert(eng_capture_screenshot(rend, l_shot));
    assert(read_png_dims(l_shot, &pw, &ph) && pw == 320u && ph == 180u);

    eng_ui_set_target_fbo(ui, 0u);
    assert(eng_renderer_set_capture_target(rend, 0, 0));
    eng_ui_destroy(ui);
    eng_runtime_destroy(rt);
}

static void test_lua_capture_api_and_director(void) {
    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.game_dir = ENG_SOURCE_DIR "/games/001_catacomb_blitz";
    cfg.headless = true;
    cfg.width = 160;
    cfg.height = 120;
    eng_runtime_t *rt = eng_runtime_create(&cfg);
    assert(rt != NULL);
    char err[512] = {0};
    assert(eng_runtime_boot_game(rt, err, sizeof(err)));

    eng_replay_t *rec = eng_replay_create("001_catacomb_blitz", 42u, 60u);
    bool clean = false;
    eng_runtime_attach_media(rt, rec, NULL, NULL, &clean);

    const char *lua_test =
        "assert(not eng.capture.screenshot('../escape.png'))\n"
        "assert(not eng.capture.screenshot('/abs/escape.png'))\n"
        "assert(eng.capture.screenshot('phase9_lua_shot.png'))\n"
        "assert(eng.capture.bookmark('lua_mark'))\n"
        "eng.capture.set_clean_feed(true)\n"
        "assert(not eng.capture.is_replaying())\n"
        "assert(eng.capture.is_recording())\n"
        "assert(not eng.capture.start_video('../bad.mp4', {fallback=true}))\n"
        "assert(eng.capture.start_video('phase9_lua_vid.mp4', {width=160, height=120, fps=30, speed=0.5, fallback=true}))\n"
        "assert(not eng.capture.start_video('dup.mp4', {fallback=true}))\n"
        "return 'ok'\n";
    assert(eng_runtime_exec_lua(rt, "lua_cap_test", lua_test, err, sizeof(err)));
    assert(strcmp(err, "ok") == 0);
    assert(clean == true);
    assert(eng_replay_find_bookmark(rec, "lua_mark") != NULL);

    assert(eng_runtime_render(rt, err, sizeof(err)));
    assert(eng_runtime_render(rt, err, sizeof(err)));
    assert(eng_runtime_exec_lua(rt, "lua_cap_stop", "assert(eng.capture.stop_video()); assert(not eng.capture.stop_video())", err, sizeof(err)));

    /* Director camera script override */
    const char *dpath = ENG_BINARY_DIR "/test_phase9_out/director.lua";
    FILE *df = fopen(dpath, "wb");
    assert(df != NULL);
    fputs("function director_camera(t, f, cam)\n"
          "  eng.camera.set(9.5, 4.25, -3.5, 0.0, 0.5, 0.0, cam.pocket)\n"
          "end\n", df);
    fclose(df);

    assert(!eng_runtime_load_director(rt, ENG_BINARY_DIR "/test_phase9_out/missing_dir.lua", err, sizeof(err)));
    assert(eng_runtime_load_director(rt, dpath, err, sizeof(err)));
    eng_runtime_apply_director(rt, 7u);
    eng_camera_t *cam = eng_runtime_camera(rt);
    assert(fabsf(cam->pos.x - 9.5f) < 1e-4f && fabsf(cam->pos.y - 4.25f) < 1e-4f && fabsf(cam->pos.z + 3.5f) < 1e-4f);

    eng_replay_destroy(rec);
    eng_runtime_destroy(rt);
}

#ifndef _WIN32
static void test_ffmpeg_pipe_mock_posix(void) {
    /* Exercise MP4, WebM, and GIF ffmpeg subprocess piping + muxing deterministically even without host ffmpeg */
    const char *bin_dir = ENG_BINARY_DIR "/test_phase9_out/fakebin";
    mkdir(ENG_BINARY_DIR "/test_phase9_out", 0755);
    mkdir(bin_dir, 0755);
    char stub_path[512];
    snprintf(stub_path, sizeof(stub_path), "%s/ffmpeg", bin_dir);
    FILE *sf = fopen(stub_path, "wb");
    assert(sf != NULL);
    fputs("#!/bin/sh\n"
          "case \"$1\" in -version) exit 0 ;; esac\n"
          "cat >/dev/null\n"
          "for a in \"$@\"; do last=\"$a\"; done\n"
          "printf 'MOCKFF' > \"$last\"\n"
          "exit 0\n", sf);
    fclose(sf);
    chmod(stub_path, 0755);

    const char *old_path = getenv("PATH");
    char saved_path[2048] = {0};
    if (old_path) snprintf(saved_path, sizeof(saved_path), "%s", old_path);
    char new_path[2560];
    snprintf(new_path, sizeof(new_path), "%s:%s", bin_dir, saved_path);
    setenv("PATH", new_path, 1);

    assert(eng_capture_ffmpeg_available());

    eng_runtime_cfg_t cfg = eng_runtime_default_cfg();
    cfg.repo_root = ENG_SOURCE_DIR;
    cfg.game_dir = ENG_SOURCE_DIR "/games/001_catacomb_blitz";
    cfg.headless = true;
    cfg.width = 64;
    cfg.height = 64;
    eng_runtime_t *rt = eng_runtime_create(&cfg);
    assert(rt != NULL);
    char err[256] = {0};
    assert(eng_runtime_boot_game(rt, err, sizeof(err)));
    eng_renderer_t *rend = eng_runtime_renderer(rt);

    const char *outs[3] = {
        ENG_BINARY_DIR "/test_phase9_out/mock_out.mp4",
        ENG_BINARY_DIR "/test_phase9_out/mock_out.webm",
        ENG_BINARY_DIR "/test_phase9_out/mock_out.gif"
    };
    float speeds[3] = {0.5f, 1.0f, 1.0f};
    for (int i = 0; i < 3; i++) {
        eng_capture_cfg_t ccfg = eng_capture_default_cfg(outs[i], 64, 64, 30);
        ccfg.speed = speeds[i];
        ccfg.fast_live = (i == 0);
        eng_capture_t *cap = eng_capture_start(&ccfg);
        assert(cap != NULL && eng_capture_is_using_ffmpeg(cap));
        assert(eng_capture_push_video_frame(cap, rend));
        float pcm[64] = {0.25f, -0.25f};
        if (i < 2) eng_capture_push_audio(pcm, 32, 48000, cap);
        assert(eng_capture_stop(cap));
        FILE *chk = fopen(outs[i], "rb");
        assert(chk != NULL);
        fclose(chk);
    }

    /* Also test video-only MP4 mux branch (0 audio frames) */
    eng_capture_cfg_t vonly = eng_capture_default_cfg(ENG_BINARY_DIR "/test_phase9_out/mock_vonly.mp4", 64, 64, 30);
    eng_capture_t *vcap = eng_capture_start(&vonly);
    assert(vcap != NULL && eng_capture_is_using_ffmpeg(vcap));
    assert(eng_capture_push_video_frame(vcap, rend));
    assert(eng_capture_stop(vcap));

    eng_runtime_destroy(rt);
    if (saved_path[0]) setenv("PATH", saved_path, 1);
}
#endif

static void test_cli_media_pipeline_e2e(void) {
    const char *rep_path = ENG_BINARY_DIR "/test_phase9_out/cli_bot.engrep";
    const char *vid_path = ENG_BINARY_DIR "/test_phase9_out/cli_reel.mp4";
    const char *shots_dir = ENG_BINARY_DIR "/test_phase9_out/cli_shots";
    const char *dir_path = ENG_BINARY_DIR "/test_phase9_out/director.lua";

    /* 1. Record bot playtest to .engrep */
    char *av_rec[] = {
        "engine", "--repo-root", ENG_SOURCE_DIR,
        "--game", ENG_SOURCE_DIR "/games/001_catacomb_blitz",
        "--headless", "--test", "tests/playtest.lua",
        "--max-frames", "600", "--record-replay", (char *)rep_path
    };
    assert(eng_cli_run((int)(sizeof(av_rec) / sizeof(av_rec[0])), av_rec) == 0);

    /* Attach a highlight bookmark at end of recorded playtest and re-save */
    eng_replay_t *r = eng_replay_load_file(rep_path);
    assert(r != NULL && eng_replay_frame_count(r) >= 10u);
    assert(eng_replay_add_bookmark(r, "peak"));
    assert(eng_replay_save_file(r, rep_path));
    eng_replay_destroy(r);

    /* 2. Replay -> offline Reel video + bookmark screenshot + director + clean feed + slow-mo */
    char *av_exp[] = {
        "engine", "--repo-root", ENG_SOURCE_DIR,
        "--game", ENG_SOURCE_DIR "/games/001_catacomb_blitz",
        "--headless", "--replay", (char *)rep_path,
        "--record-video", (char *)vid_path,
        "--preset", "reel", "--width", "120", "--height", "212", "--fps", "30",
        "--speed", "0.5", "--clip", "bookmark:peak:0.3:0.2",
        "--screenshot-at", "bookmarks", "--out-dir", (char *)shots_dir,
        "--clean-feed", "--director", (char *)dir_path
    };
    assert(eng_cli_run((int)(sizeof(av_exp) / sizeof(av_exp[0])), av_exp) == 0);

    char shot_check[512];
    snprintf(shot_check, sizeof(shot_check), "%s/001_catacomb_blitz_shot_01.png", shots_dir);
    uint32_t sw = 0, sh = 0;
    assert(read_png_dims(shot_check, &sw, &sh) && sw == 120u && sh == 212u);

    /* 3. Explicit time-range clip + comma-separated --screenshot-at */
    char *av_range[] = {
        "engine", "--repo-root", ENG_SOURCE_DIR,
        "--game", ENG_SOURCE_DIR "/games/001_catacomb_blitz",
        "--headless", "--replay", (char *)rep_path,
        "--clip", "0.05:0.20", "--screenshot-at", "0.08,0.16",
        "--out-dir", (char *)shots_dir, "--width", "128", "--height", "72"
    };
    assert(eng_cli_run((int)(sizeof(av_range) / sizeof(av_range[0])), av_range) == 0);

    /* 4. CLI error handling branches */
    char *av_bad_preset[] = { "engine", "--repo-root", ENG_SOURCE_DIR, "--game", ENG_SOURCE_DIR "/games/001_catacomb_blitz", "--preset", "nope" };
    assert(eng_cli_run((int)(sizeof(av_bad_preset) / sizeof(av_bad_preset[0])), av_bad_preset) != 0);

    char *av_bad_rep[] = { "engine", "--repo-root", ENG_SOURCE_DIR, "--game", ENG_SOURCE_DIR "/games/001_catacomb_blitz", "--replay", "/nonexistent/x.engrep" };
    assert(eng_cli_run((int)(sizeof(av_bad_rep) / sizeof(av_bad_rep[0])), av_bad_rep) != 0);

    char *av_bad_clip[] = { "engine", "--repo-root", ENG_SOURCE_DIR, "--game", ENG_SOURCE_DIR "/games/001_catacomb_blitz", "--replay", (char *)rep_path, "--clip", "bookmark:nope" };
    assert(eng_cli_run((int)(sizeof(av_bad_clip) / sizeof(av_bad_clip[0])), av_bad_clip) != 0);

    char *av_bad_dir[] = { "engine", "--repo-root", ENG_SOURCE_DIR, "--game", ENG_SOURCE_DIR "/games/001_catacomb_blitz", "--headless", "--director", "/nonexistent/d.lua" };
    assert(eng_cli_run((int)(sizeof(av_bad_dir) / sizeof(av_bad_dir[0])), av_bad_dir) != 0);
}

int main(void) {
    test_presets_and_atempo();
    test_offscreen_fbo_portrait_and_landscape();
    test_replay_determinism_and_bookmarks();
    test_audio_wav_and_fallback_capture();
    test_lua_capture_api_and_director();
#ifndef _WIN32
    test_ffmpeg_pipe_mock_posix();
#endif
    test_cli_media_pipeline_e2e();
    printf("[PASS] Phase 9 Media Capture, Deterministic Replay & Social Export tests passed.\n");
    return 0;
}
