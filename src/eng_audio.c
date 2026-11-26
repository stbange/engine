#include "engine/eng_audio.h"

#include <SDL3/SDL.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* Forward declaration of stb_vorbis_decode_memory compiled in third_party_impl.c */
extern int stb_vorbis_decode_memory(const unsigned char *mem, int len, int *channels, int *sample_rate, short **output);

#define ENG_SAMPLE_RATE 48000
#define ENG_MAX_CLIPS 256
#define ENG_MAX_VOICES 64

typedef struct {
    float *mono_samples;
    size_t sample_count;
} audio_clip_t;

typedef struct {
    bool active;
    uint32_t gen_id;
    eng_voice_desc_t d;
    double cursor;
} audio_voice_t;

typedef struct {
    uint16_t pocket_id;
    eng_vec3_t pos;
    eng_vec3_t vel;
    eng_vec3_t right;
} audio_listener_int_t;

struct eng_audio_s {
    bool headless;
    SDL_AudioStream *stream;
    float bus_gain[ENG_BUS_COUNT];

    audio_listener_int_t listeners[ENG_MAX_LISTENERS];
    int listener_count;

    audio_clip_t clips[ENG_MAX_CLIPS];
    uint32_t clip_count;

    audio_voice_t voices[ENG_MAX_VOICES];
    uint32_t next_voice_id;
    eng_rng_t noise_rng;

    eng_audio_capture_fn cap_cb;
    void *cap_ud;
};

eng_synth_desc_t eng_synth_default_desc(eng_synth_wave_t wave, float freq_hz, float duration_sec) {
    return (eng_synth_desc_t){
        .wave = wave,
        .freq_start_hz = freq_hz > 20.0f ? freq_hz : 440.0f,
        .freq_end_hz = freq_hz > 20.0f ? freq_hz : 440.0f,
        .duration_sec = duration_sec > 0.02f ? duration_sec : 0.25f,
        .attack_sec = 0.01f,
        .decay_sec = 0.05f,
        .sustain_level = 0.65f,
        .release_sec = 0.06f,
        .gain = 0.5f
    };
}

eng_voice_desc_t eng_voice_default_desc(uint32_t clip_id) {
    return (eng_voice_desc_t){
        .clip_id = clip_id,
        .bus = ENG_BUS_SFX,
        .loop = false,
        .spatial_3d = false,
        .pocket_id = 0,
        .pos = {0, 0, 0},
        .vel = {0, 0, 0},
        .min_dist = 1.5f,
        .max_dist = 40.0f,
        .gain = 1.0f,
        .pitch = 1.0f
    };
}

eng_audio_t *eng_audio_create(bool headless) {
    eng_audio_t *a = (eng_audio_t *)calloc(1, sizeof(eng_audio_t));
    if (!a) return NULL;
    a->headless = headless;
    for (int i = 0; i < ENG_BUS_COUNT; i++) a->bus_gain[i] = 1.0f;
    a->listener_count = 1;
    a->listeners[0].right = eng_v3(1.0f, 0.0f, 0.0f);
    a->next_voice_id = 1u;
    eng_rng_seed(&a->noise_rng, 0xA0D10u);

    if (!headless && SDL_InitSubSystem(SDL_INIT_AUDIO)) {
        SDL_AudioSpec spec = {SDL_AUDIO_F32, 2, ENG_SAMPLE_RATE};
        a->stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, NULL, NULL);
        if (a->stream) SDL_ResumeAudioStreamDevice(a->stream);
    }
    return a;
}

void eng_audio_destroy(eng_audio_t *aud) {
    if (!aud) return;
    if (aud->stream) SDL_DestroyAudioStream(aud->stream);
    for (uint32_t i = 0; i < aud->clip_count; i++) free(aud->clips[i].mono_samples);
    free(aud);
}

void eng_audio_set_bus_gain(eng_audio_t *aud, eng_audio_bus_t bus, float gain) {
    if (aud && (int)bus >= 0 && bus < ENG_BUS_COUNT) aud->bus_gain[bus] = eng_clampf(gain, 0.0f, 2.0f);
}

float eng_audio_get_bus_gain(const eng_audio_t *aud, eng_audio_bus_t bus) {
    return (aud && (int)bus >= 0 && bus < ENG_BUS_COUNT) ? aud->bus_gain[bus] : 0.0f;
}

void eng_audio_set_listeners(eng_audio_t *aud, const eng_audio_listener_t *listeners, int count) {
    if (!aud || !listeners || count <= 0) return;
    if (count > ENG_MAX_LISTENERS) count = ENG_MAX_LISTENERS;
    aud->listener_count = count;
    for (int i = 0; i < count; i++) {
        aud->listeners[i].pocket_id = listeners[i].pocket_id;
        aud->listeners[i].pos = listeners[i].pos;
        aud->listeners[i].vel = listeners[i].vel;
        aud->listeners[i].right = eng_quat_rotate_v3(listeners[i].rot, eng_v3(1.0f, 0.0f, 0.0f));
    }
}

void eng_audio_set_listener(eng_audio_t *aud, uint16_t pocket_id,
                            eng_vec3_t pos, eng_vec3_t vel, eng_quat_t rot) {
    eng_audio_listener_t l = {pocket_id, pos, vel, rot};
    eng_audio_set_listeners(aud, &l, 1);
}

static uint32_t store_mono_clip(eng_audio_t *aud, float *samples, size_t count) {
    if (!aud || !samples || count == 0 || aud->clip_count >= ENG_MAX_CLIPS) {
        free(samples);
        return 0;
    }
    uint32_t slot = aud->clip_count++;
    aud->clips[slot] = (audio_clip_t){samples, count};
    return slot + 1u;
}

uint32_t eng_audio_load_wav_mem(eng_audio_t *aud, const void *bytes, size_t len) {
    if (!aud || !bytes || len < 16) return 0;
    SDL_IOStream *io = SDL_IOFromConstMem(bytes, len);
    if (!io) return 0;
    SDL_AudioSpec src_spec;
    Uint8 *pcm = NULL;
    Uint32 pcm_len = 0;
    if (!SDL_LoadWAV_IO(io, true, &src_spec, &pcm, &pcm_len)) return 0;

    SDL_AudioSpec dst_spec = {SDL_AUDIO_F32, 1, ENG_SAMPLE_RATE};
    Uint8 *conv = NULL;
    int conv_len = 0;
    bool ok = SDL_ConvertAudioSamples(&src_spec, pcm, (int)pcm_len, &dst_spec, &conv, &conv_len);
    SDL_free(pcm);
    if (!ok || !conv || conv_len <= 0) {
        SDL_free(conv);
        return 0;
    }
    size_t count = (size_t)conv_len / sizeof(float);
    float *copy = (float *)malloc(count * sizeof(float));
    if (copy) memcpy(copy, conv, count * sizeof(float));
    SDL_free(conv);
    return store_mono_clip(aud, copy, count);
}

uint32_t eng_audio_load_ogg_mem(eng_audio_t *aud, const void *bytes, size_t len) {
    if (!aud || !bytes || len < 16) return 0;
    int ch = 0, rate = 0;
    short *decoded = NULL;
    int frames = stb_vorbis_decode_memory((const unsigned char *)bytes, (int)len, &ch, &rate, &decoded);
    if (frames <= 0 || !decoded || ch <= 0 || rate <= 0) return 0;

    size_t out_n = (size_t)((double)frames * (double)ENG_SAMPLE_RATE / (double)rate);
    if (out_n == 0) out_n = 1;
    float *mono = (float *)malloc(out_n * sizeof(float));
    if (!mono) { free(decoded); return 0; }

    for (size_t i = 0; i < out_n; i++) {
        size_t sf = (i * (size_t)rate) / ENG_SAMPLE_RATE;
        if (sf >= (size_t)frames) sf = (size_t)frames - 1u;
        float acc = 0.0f;
        for (int c = 0; c < ch; c++) acc += (float)decoded[sf * (size_t)ch + (size_t)c] / 32768.0f;
        mono[i] = acc / (float)ch;
    }
    free(decoded);
    return store_mono_clip(aud, mono, out_n);
}

uint32_t eng_audio_load_vfs(eng_audio_t *aud, const eng_vfs_t *vfs, const char *vpath) {
    if (!aud || !vfs || !vpath) return 0;
    size_t sz = 0;
    void *raw = eng_vfs_read_all(vfs, vpath, &sz);
    if (!raw) return 0;
    const char *ext = strrchr(vpath, '.');
    uint32_t id = (ext && strcmp(ext, ".ogg") == 0)
                      ? eng_audio_load_ogg_mem(aud, raw, sz)
                      : eng_audio_load_wav_mem(aud, raw, sz);
    free(raw);
    return id;
}

uint32_t eng_audio_synth_retro(eng_audio_t *aud, const eng_synth_desc_t *desc) {
    if (!aud || !desc || desc->duration_sec <= 0.0f) return 0;
    size_t n = (size_t)(desc->duration_sec * (float)ENG_SAMPLE_RATE);
    if (n == 0) n = 1;
    float *buf = (float *)malloc(n * sizeof(float));
    if (!buf) return 0;

    float phase = 0.0f;
    for (size_t i = 0; i < n; i++) {
        float t = (float)i / (float)ENG_SAMPLE_RATE;
        float u = (float)i / (float)n;
        float freq = eng_lerpf(desc->freq_start_hz, desc->freq_end_hz, u);
        phase = fmodf(phase + freq / (float)ENG_SAMPLE_RATE, 1.0f);

        float s = 0.0f;
        switch (desc->wave) {
            case ENG_WAVE_SQUARE:   s = (phase < 0.5f) ? 1.0f : -1.0f; break;
            case ENG_WAVE_SAW:      s = phase * 2.0f - 1.0f; break;
            case ENG_WAVE_TRIANGLE: s = 1.0f - fabsf(phase * 4.0f - 2.0f); break;
            case ENG_WAVE_SINE:     s = sinf(phase * 2.0f * ENG_PI); break;
            case ENG_WAVE_NOISE:    s = eng_rng_rangef(&aud->noise_rng, -1.0f, 1.0f); break;
        }

        /* ADSR envelope */
        float env = desc->sustain_level;
        float rel_start = desc->duration_sec - desc->release_sec;
        if (t < desc->attack_sec && desc->attack_sec > 1e-4f) {
            env = t / desc->attack_sec;
        } else if (t < desc->attack_sec + desc->decay_sec && desc->decay_sec > 1e-4f) {
            float dt = (t - desc->attack_sec) / desc->decay_sec;
            env = eng_lerpf(1.0f, desc->sustain_level, dt);
        } else if (t > rel_start && desc->release_sec > 1e-4f) {
            env = eng_lerpf(desc->sustain_level, 0.0f, (t - rel_start) / desc->release_sec);
        }
        buf[i] = eng_clampf(s * env * desc->gain, -1.0f, 1.0f);
    }
    return store_mono_clip(aud, buf, n);
}

uint32_t eng_audio_play(eng_audio_t *aud, const eng_voice_desc_t *desc) {
    if (!aud || !desc || desc->clip_id == 0 || desc->clip_id > aud->clip_count) return 0;
    for (int i = 0; i < ENG_MAX_VOICES; i++) {
        if (!aud->voices[i].active) {
            uint32_t vid = aud->next_voice_id++;
            aud->voices[i] = (audio_voice_t){true, vid, *desc, 0.0};
            return vid;
        }
    }
    return 0;
}

void eng_audio_stop(eng_audio_t *aud, uint32_t voice_id) {
    if (!aud || voice_id == 0) return;
    for (int i = 0; i < ENG_MAX_VOICES; i++) {
        if (aud->voices[i].active && aud->voices[i].gen_id == voice_id) {
            aud->voices[i].active = false;
        }
    }
}

static bool compute_voice_for_listener(const audio_listener_int_t *lis, const audio_voice_t *v,
                                       const eng_scene_t *scene, const eng_portal_sys_t *portals,
                                       float *out_gain_l, float *out_gain_r, float *out_doppler) {
    *out_doppler = 1.0f;
    eng_vec3_t eff_pos = v->d.pos;
    float extra_dist = 0.0f;

    /* Cross-portal acoustic routing when listener and source live in different pocket spaces */
    if (v->d.pocket_id != lis->pocket_id) {
        if (!scene || !portals) return false;
        float best_total = 1e30f;
        bool found = false;
        size_t pc = eng_portal_count(portals);
        for (size_t i = 0; i < pc; i++) {
            const eng_portal_t *p = eng_portal_get(portals, i);
            if (!p || p->src_pocket != lis->pocket_id || p->dst_pocket != v->d.pocket_id) continue;
            const eng_mat4_t *ms = eng_scene_get_world_matrix(scene, p->src_ent);
            const eng_mat4_t *md = eng_scene_get_world_matrix(scene, p->dst_ent);
            if (!ms || !md) continue;
            eng_vec3_t near_door = eng_v3(ms->m[12], ms->m[13], ms->m[14]);
            eng_vec3_t far_door  = eng_v3(md->m[12], md->m[13], md->m[14]);
            float d1 = eng_v3_len(eng_v3_sub(near_door, lis->pos));
            float d2 = eng_v3_len(eng_v3_sub(v->d.pos, far_door));
            if (d1 + d2 < best_total) {
                best_total = d1 + d2;
                eff_pos = near_door;
                extra_dist = d2;
                found = true;
            }
        }
        if (!found) return false;
    }

    eng_vec3_t to_src = eng_v3_sub(eff_pos, lis->pos);
    float direct_d = eng_v3_len(to_src);
    float total_d = direct_d + extra_dist;
    float max_d = fmaxf(v->d.max_dist, v->d.min_dist + 0.1f);
    if (total_d >= max_d) return false;

    float atten = 1.0f;
    if (total_d > v->d.min_dist) {
        atten = 1.0f - (total_d - v->d.min_dist) / (max_d - v->d.min_dist);
        atten *= atten;
    }

    eng_vec3_t dir = direct_d > 1e-4f ? eng_v3_scale(to_src, 1.0f / direct_d) : eng_v3(0, 0, -1);
    float pan = eng_clampf(eng_v3_dot(dir, lis->right), -1.0f, 1.0f);
    float angle = (pan * 0.5f + 0.5f) * (0.5f * ENG_PI);
    *out_gain_l = cosf(angle) * atten;
    *out_gain_r = sinf(angle) * atten;

    /* Radial Doppler shift (speed of sound = 343 m/s) */
    if (v->d.pocket_id == lis->pocket_id) {
        float vl = eng_clampf(eng_v3_dot(lis->vel, dir), -150.0f, 150.0f);
        float vs = eng_clampf(eng_v3_dot(v->d.vel, dir), -150.0f, 150.0f);
        *out_doppler = eng_clampf((343.0f + vl) / (343.0f + vs), 0.5f, 2.0f);
    }
    return true;
}

static bool compute_voice_spatial(const eng_audio_t *aud, const audio_voice_t *v,
                                  const eng_scene_t *scene, const eng_portal_sys_t *portals,
                                  float *out_gain_l, float *out_gain_r, float *out_doppler) {
    *out_doppler = 1.0f;
    if (!v->d.spatial_3d) {
        *out_gain_l = 0.7071f;
        *out_gain_r = 0.7071f;
        return true;
    }
    bool any = false;
    float best_mag = -1.0f;
    for (int i = 0; i < aud->listener_count; i++) {
        float gl = 0.0f, gr = 0.0f, dop = 1.0f;
        if (compute_voice_for_listener(&aud->listeners[i], v, scene, portals, &gl, &gr, &dop)) {
            float mag = gl + gr;
            if (mag > best_mag) {
                best_mag = mag;
                *out_gain_l = gl;
                *out_gain_r = gr;
                *out_doppler = dop;
                any = true;
            }
        }
    }
    return any;
}

void eng_audio_mix_frames(eng_audio_t *aud, const eng_scene_t *scene,
                          const eng_portal_sys_t *portals,
                          float *out_stereo_lr, size_t frames) {
    if (!out_stereo_lr || frames == 0) return;
    memset(out_stereo_lr, 0, frames * 2u * sizeof(float));
    if (!aud) return;

    float master = aud->bus_gain[ENG_BUS_MASTER];
    for (int vi = 0; vi < ENG_MAX_VOICES; vi++) {
        audio_voice_t *v = &aud->voices[vi];
        if (!v->active) continue;
        const audio_clip_t *clip = &aud->clips[v->d.clip_id - 1u];

        float gl = 0.0f, gr = 0.0f, doppler = 1.0f;
        bool audible = compute_voice_spatial(aud, v, scene, portals, &gl, &gr, &doppler);
        float bg = (v->d.bus < ENG_BUS_COUNT ? aud->bus_gain[v->d.bus] : 1.0f) * master * v->d.gain;
        double step = fmax(0.05, (double)(v->d.pitch * doppler));

        for (size_t f = 0; f < frames; f++) {
            size_t idx = (size_t)v->cursor;
            if (idx >= clip->sample_count) {
                if (v->d.loop) {
                    v->cursor = fmod(v->cursor, (double)clip->sample_count);
                    idx = (size_t)v->cursor;
                } else {
                    v->active = false;
                    break;
                }
            }
            if (audible) {
                float s = clip->mono_samples[idx] * bg;
                out_stereo_lr[f * 2u + 0] += s * gl;
                out_stereo_lr[f * 2u + 1] += s * gr;
            }
            v->cursor += step;
        }
    }

    for (size_t i = 0; i < frames * 2u; i++) {
        out_stereo_lr[i] = eng_clampf(out_stereo_lr[i], -1.0f, 1.0f);
    }
}

void eng_audio_set_capture_cb(eng_audio_t *aud, eng_audio_capture_fn cb, void *user_data) {
    if (!aud) return;
    aud->cap_cb = cb;
    aud->cap_ud = user_data;
}

void eng_audio_update(eng_audio_t *aud, const eng_scene_t *scene,
                      const eng_portal_sys_t *portals, float dt) {
    if (!aud || dt <= 0.0f) return;
    size_t frames = (size_t)(eng_clampf(dt, 0.0f, 0.1f) * (float)ENG_SAMPLE_RATE);
    if (frames == 0) return;
    float scratch[4800 * 2];
    if (frames > 4800) frames = 4800;
    eng_audio_mix_frames(aud, scene, portals, scratch, frames);
    if (aud->cap_cb) {
        aud->cap_cb(scratch, frames, ENG_SAMPLE_RATE, aud->cap_ud);
    }
    if (aud->stream) {
        SDL_PutAudioStreamData(aud->stream, scratch, (int)(frames * 2u * sizeof(float)));
    }
}
