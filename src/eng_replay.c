#include "engine/eng_replay.h"
#include "engine/eng_serde.h"
#include "engine/eng_version.h"

#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_REPLAY_MAGIC 0x50455245u /* "EREP" */
#define ENG_REPLAY_MAX_ACTIONS 64
#define ENG_REPLAY_MAX_AXES 32

struct eng_replay_s {
    char game_id[96];
    char engine_ver[32];
    uint64_t seed;
    uint16_t target_fps;

    char action_names[ENG_REPLAY_MAX_ACTIONS][48];
    const char *action_ptrs[ENG_REPLAY_MAX_ACTIONS];
    size_t action_count;

    char axis_names[ENG_REPLAY_MAX_AXES][48];
    const char *axis_ptrs[ENG_REPLAY_MAX_AXES];
    size_t axis_count;

    eng_input_frame_t *frames;
    size_t frame_count;
    size_t frame_cap;
    size_t cursor;
    float duration_sec;

    eng_replay_bookmark_t *bookmarks;
    size_t bookmark_count;
    size_t bookmark_cap;
};

static void ensure_parent_dirs(const char *path) {
    if (!path) return;
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/' || *p == '\\') {
            char saved = *p;
            *p = '\0';
#ifdef _WIN32
            (void)_mkdir(tmp);
#else
            (void)mkdir(tmp, 0755);
#endif
            *p = saved;
        }
    }
}

static void sync_name_tables(eng_replay_t *rep, const eng_input_t *inp) {
    size_t ac = eng_input_action_count(inp);
    if (ac > ENG_REPLAY_MAX_ACTIONS) ac = ENG_REPLAY_MAX_ACTIONS;
    for (size_t i = rep->action_count; i < ac; i++) {
        const char *nm = eng_input_action_name(inp, i);
        snprintf(rep->action_names[i], sizeof(rep->action_names[i]), "%s", nm ? nm : "");
        rep->action_ptrs[i] = rep->action_names[i];
    }
    if (ac > rep->action_count) rep->action_count = ac;

    size_t xc = eng_input_axis_count(inp);
    if (xc > ENG_REPLAY_MAX_AXES) xc = ENG_REPLAY_MAX_AXES;
    for (size_t i = rep->axis_count; i < xc; i++) {
        const char *nm = eng_input_axis_name(inp, i);
        snprintf(rep->axis_names[i], sizeof(rep->axis_names[i]), "%s", nm ? nm : "");
        rep->axis_ptrs[i] = rep->axis_names[i];
    }
    if (xc > rep->axis_count) rep->axis_count = xc;
}

eng_replay_t *eng_replay_create(const char *game_id, uint64_t seed, uint16_t target_fps) {
    eng_replay_t *rep = (eng_replay_t *)calloc(1, sizeof(eng_replay_t));
    if (!rep) return NULL;
    snprintf(rep->game_id, sizeof(rep->game_id), "%s", (game_id && game_id[0]) ? game_id : "game");
    snprintf(rep->engine_ver, sizeof(rep->engine_ver), "%s", eng_version_string());
    rep->seed = seed;
    rep->target_fps = target_fps > 0 ? target_fps : 60u;
    return rep;
}

void eng_replay_destroy(eng_replay_t *rep) {
    if (!rep) return;
    free(rep->frames);
    free(rep->bookmarks);
    free(rep);
}

bool eng_replay_record_frame(eng_replay_t *rep, const eng_input_t *inp, float dt) {
    if (!rep || !inp || dt <= 0.0f) return false;
    sync_name_tables(rep, inp);
    if (rep->frame_count >= rep->frame_cap) {
        size_t nc = rep->frame_cap ? rep->frame_cap * 2u : 512u;
        eng_input_frame_t *nf = (eng_input_frame_t *)realloc(rep->frames, nc * sizeof(eng_input_frame_t));
        if (!nf) return false;
        rep->frames = nf;
        rep->frame_cap = nc;
    }
    eng_input_capture_frame(inp, dt, &rep->frames[rep->frame_count++]);
    rep->duration_sec += dt;
    return true;
}

bool eng_replay_add_bookmark(eng_replay_t *rep, const char *label) {
    if (!rep) return false;
    if (rep->bookmark_count >= rep->bookmark_cap) {
        size_t nc = rep->bookmark_cap ? rep->bookmark_cap * 2u : 16u;
        eng_replay_bookmark_t *nb = (eng_replay_bookmark_t *)realloc(rep->bookmarks, nc * sizeof(eng_replay_bookmark_t));
        if (!nb) return false;
        rep->bookmarks = nb;
        rep->bookmark_cap = nc;
    }
    eng_replay_bookmark_t *b = &rep->bookmarks[rep->bookmark_count++];
    memset(b, 0, sizeof(*b));
    b->frame = (uint32_t)rep->frame_count;
    b->time_sec = rep->duration_sec;
    snprintf(b->label, sizeof(b->label), "%s", (label && label[0]) ? label : "highlight");
    return true;
}

bool eng_replay_save_file(const eng_replay_t *rep, const char *host_path) {
    if (!rep || !host_path || !host_path[0]) return false;
    eng_bin_writer_t w;
    if (!eng_bin_writer_init(&w, ENG_REPLAY_SCHEMA_VERSION, 4096u + rep->frame_count * 48u)) return false;

    eng_bin_write_u32(&w, ENG_REPLAY_MAGIC);
    eng_bin_write_str(&w, rep->game_id);
    eng_bin_write_str(&w, rep->engine_ver);
    eng_bin_write_u32(&w, (uint32_t)(rep->seed & 0xFFFFFFFFull));
    eng_bin_write_u32(&w, (uint32_t)(rep->seed >> 32));
    eng_bin_write_u32(&w, (uint32_t)rep->target_fps);

    eng_bin_write_u32(&w, (uint32_t)rep->action_count);
    for (size_t i = 0; i < rep->action_count; i++) eng_bin_write_str(&w, rep->action_names[i]);
    eng_bin_write_u32(&w, (uint32_t)rep->axis_count);
    for (size_t i = 0; i < rep->axis_count; i++) eng_bin_write_str(&w, rep->axis_names[i]);

    eng_bin_write_u32(&w, (uint32_t)rep->bookmark_count);
    for (size_t i = 0; i < rep->bookmark_count; i++) {
        eng_bin_write_u32(&w, rep->bookmarks[i].frame);
        eng_bin_write_f32(&w, rep->bookmarks[i].time_sec);
        eng_bin_write_str(&w, rep->bookmarks[i].label);
    }

    eng_bin_write_u32(&w, (uint32_t)rep->frame_count);
    for (size_t i = 0; i < rep->frame_count; i++) {
        const eng_input_frame_t *f = &rep->frames[i];
        eng_bin_write_f32(&w, f->dt);
        eng_bin_write_u32(&w, (uint32_t)(f->action_mask & 0xFFFFFFFFull));
        eng_bin_write_u32(&w, (uint32_t)(f->action_mask >> 32));
        eng_bin_write_u32(&w, (uint32_t)f->axis_count);
        for (uint8_t k = 0; k < f->axis_count; k++) {
            eng_bin_write_u32(&w, (uint32_t)f->axis_idx[k]);
            eng_bin_write_f32(&w, f->axis_val[k]);
        }
        eng_bin_write_f32(&w, f->mouse_pos.x);
        eng_bin_write_f32(&w, f->mouse_pos.y);
        eng_bin_write_f32(&w, f->mouse_delta.x);
        eng_bin_write_f32(&w, f->mouse_delta.y);
        eng_bin_write_f32(&w, f->wheel_y);
        uint32_t pmask = ((uint32_t)f->player_mask[0]) | ((uint32_t)f->player_mask[1] << 8)
                       | ((uint32_t)f->player_mask[2] << 16) | ((uint32_t)f->player_mask[3] << 24);
        eng_bin_write_u32(&w, pmask);
        for (int p = 0; p < ENG_MAX_PLAYERS; p++) {
            eng_bin_write_f32(&w, f->player_move[p].x);
            eng_bin_write_f32(&w, f->player_move[p].y);
            eng_bin_write_f32(&w, f->player_look[p].x);
            eng_bin_write_f32(&w, f->player_look[p].y);
        }
    }

    if (w.failed) { eng_bin_writer_destroy(&w); return false; }
    ensure_parent_dirs(host_path);
    FILE *fp = fopen(host_path, "wb");
    if (!fp) { eng_bin_writer_destroy(&w); return false; }
    bool ok = (fwrite(w.buf, 1u, w.size, fp) == w.size);
    fclose(fp);
    eng_bin_writer_destroy(&w);
    return ok;
}

eng_replay_t *eng_replay_load_file(const char *host_path) {
    if (!host_path || !host_path[0]) return NULL;
    FILE *fp = fopen(host_path, "rb");
    if (!fp) return NULL;
    if (fseek(fp, 0, SEEK_END) != 0) { fclose(fp); return NULL; }
    long sz = ftell(fp);
    if (sz <= 0 || sz > 64 * 1024 * 1024) { fclose(fp); return NULL; }
    rewind(fp);
    uint8_t *raw = (uint8_t *)malloc((size_t)sz);
    if (!raw) { fclose(fp); return NULL; }
    size_t got = fread(raw, 1u, (size_t)sz, fp);
    fclose(fp);

    eng_bin_reader_t r;
    uint32_t magic = 0, seed_lo = 0, seed_hi = 0, fps = 60, ac = 0, xc = 0, bc = 0, fc = 0;
    if (!eng_bin_reader_init(&r, raw, got, ENG_REPLAY_SCHEMA_VERSION) ||
        !eng_bin_read_u32(&r, &magic) || magic != ENG_REPLAY_MAGIC) {
        free(raw);
        return NULL;
    }

    eng_replay_t *rep = (eng_replay_t *)calloc(1, sizeof(eng_replay_t));
    if (!rep) { free(raw); return NULL; }

    bool ok = eng_bin_read_str(&r, rep->game_id, sizeof(rep->game_id))
           && eng_bin_read_str(&r, rep->engine_ver, sizeof(rep->engine_ver))
           && eng_bin_read_u32(&r, &seed_lo)
           && eng_bin_read_u32(&r, &seed_hi)
           && eng_bin_read_u32(&r, &fps)
           && eng_bin_read_u32(&r, &ac) && ac <= ENG_REPLAY_MAX_ACTIONS;
    rep->seed = ((uint64_t)seed_hi << 32) | (uint64_t)seed_lo;
    rep->target_fps = (uint16_t)(fps > 0 && fps <= 240 ? fps : 60u);

    if (ok) {
        rep->action_count = ac;
        for (size_t i = 0; i < ac && ok; i++) {
            ok = eng_bin_read_str(&r, rep->action_names[i], sizeof(rep->action_names[i]));
            rep->action_ptrs[i] = rep->action_names[i];
        }
    }
    if (ok) ok = eng_bin_read_u32(&r, &xc) && xc <= ENG_REPLAY_MAX_AXES;
    if (ok) {
        rep->axis_count = xc;
        for (size_t i = 0; i < xc && ok; i++) {
            ok = eng_bin_read_str(&r, rep->axis_names[i], sizeof(rep->axis_names[i]));
            rep->axis_ptrs[i] = rep->axis_names[i];
        }
    }
    if (ok) ok = eng_bin_read_u32(&r, &bc) && bc <= 4096u;
    if (ok && bc > 0) {
        rep->bookmarks = (eng_replay_bookmark_t *)calloc(bc, sizeof(eng_replay_bookmark_t));
        rep->bookmark_cap = bc;
        rep->bookmark_count = bc;
        if (!rep->bookmarks) ok = false;
        for (size_t i = 0; i < bc && ok; i++) {
            ok = eng_bin_read_u32(&r, &rep->bookmarks[i].frame)
              && eng_bin_read_f32(&r, &rep->bookmarks[i].time_sec)
              && eng_bin_read_str(&r, rep->bookmarks[i].label, sizeof(rep->bookmarks[i].label));
        }
    }
    if (ok) ok = eng_bin_read_u32(&r, &fc) && fc <= 1000000u;
    if (ok && fc > 0) {
        rep->frames = (eng_input_frame_t *)calloc(fc, sizeof(eng_input_frame_t));
        rep->frame_cap = fc;
        rep->frame_count = fc;
        if (!rep->frames) ok = false;
        for (size_t i = 0; i < fc && ok; i++) {
            eng_input_frame_t *f = &rep->frames[i];
            uint32_t mlo = 0, mhi = 0, axc = 0, pmask = 0;
            ok = eng_bin_read_f32(&r, &f->dt)
              && eng_bin_read_u32(&r, &mlo)
              && eng_bin_read_u32(&r, &mhi)
              && eng_bin_read_u32(&r, &axc) && axc <= ENG_INPUT_MAX_SNAP_AXES;
            f->action_mask = ((uint64_t)mhi << 32) | (uint64_t)mlo;
            f->axis_count = (uint8_t)axc;
            for (uint32_t k = 0; k < axc && ok; k++) {
                uint32_t aidx = 0;
                ok = eng_bin_read_u32(&r, &aidx) && eng_bin_read_f32(&r, &f->axis_val[k]);
                f->axis_idx[k] = (uint8_t)aidx;
            }
            if (ok) {
                ok = eng_bin_read_f32(&r, &f->mouse_pos.x) && eng_bin_read_f32(&r, &f->mouse_pos.y)
                  && eng_bin_read_f32(&r, &f->mouse_delta.x) && eng_bin_read_f32(&r, &f->mouse_delta.y)
                  && eng_bin_read_f32(&r, &f->wheel_y) && eng_bin_read_u32(&r, &pmask);
            }
            f->player_mask[0] = (uint8_t)(pmask & 0xFFu);
            f->player_mask[1] = (uint8_t)((pmask >> 8) & 0xFFu);
            f->player_mask[2] = (uint8_t)((pmask >> 16) & 0xFFu);
            f->player_mask[3] = (uint8_t)((pmask >> 24) & 0xFFu);
            for (int p = 0; p < ENG_MAX_PLAYERS && ok; p++) {
                ok = eng_bin_read_f32(&r, &f->player_move[p].x) && eng_bin_read_f32(&r, &f->player_move[p].y)
                  && eng_bin_read_f32(&r, &f->player_look[p].x) && eng_bin_read_f32(&r, &f->player_look[p].y);
            }
            if (ok) rep->duration_sec += f->dt;
        }
    }

    free(raw);
    if (!ok) { eng_replay_destroy(rep); return NULL; }
    return rep;
}

bool eng_replay_step_playback(eng_replay_t *rep, eng_input_t *inp, float *out_dt) {
    if (!rep || !inp || rep->cursor >= rep->frame_count) return false;
    const eng_input_frame_t *f = &rep->frames[rep->cursor++];
    eng_input_apply_frame(inp, f, rep->action_ptrs, rep->action_count, rep->axis_ptrs, rep->axis_count);
    if (out_dt) *out_dt = f->dt;
    return true;
}

void eng_replay_rewind(eng_replay_t *rep) { if (rep) rep->cursor = 0; }
size_t eng_replay_frame_count(const eng_replay_t *rep) { return rep ? rep->frame_count : 0; }
size_t eng_replay_cursor(const eng_replay_t *rep) { return rep ? rep->cursor : 0; }
float eng_replay_duration(const eng_replay_t *rep) { return rep ? rep->duration_sec : 0.0f; }
uint64_t eng_replay_seed(const eng_replay_t *rep) { return rep ? rep->seed : 0; }
uint16_t eng_replay_target_fps(const eng_replay_t *rep) { return rep ? rep->target_fps : 60u; }
const char *eng_replay_game_id(const eng_replay_t *rep) { return rep ? rep->game_id : ""; }
size_t eng_replay_bookmark_count(const eng_replay_t *rep) { return rep ? rep->bookmark_count : 0; }

const eng_replay_bookmark_t *eng_replay_bookmark_get(const eng_replay_t *rep, size_t idx) {
    return (rep && idx < rep->bookmark_count) ? &rep->bookmarks[idx] : NULL;
}

const eng_replay_bookmark_t *eng_replay_find_bookmark(const eng_replay_t *rep, const char *label) {
    if (!rep || !label || !label[0]) return NULL;
    for (size_t i = 0; i < rep->bookmark_count; i++) {
        if (strcmp(rep->bookmarks[i].label, label) == 0) return &rep->bookmarks[i];
    }
    return NULL;
}
