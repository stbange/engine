#ifndef ENG_AUDIO_H
#define ENG_AUDIO_H

#include "eng_math.h"
#include "eng_portal.h"
#include "eng_scene.h"
#include "eng_vfs.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_BUS_MASTER = 0,
    ENG_BUS_SFX = 1,
    ENG_BUS_MUSIC = 2,
    ENG_BUS_UI = 3,
    ENG_BUS_COUNT = 4
} eng_audio_bus_t;

typedef enum {
    ENG_WAVE_SQUARE = 0,
    ENG_WAVE_SAW,
    ENG_WAVE_TRIANGLE,
    ENG_WAVE_SINE,
    ENG_WAVE_NOISE
} eng_synth_wave_t;

typedef struct {
    eng_synth_wave_t wave;
    float freq_start_hz;
    float freq_end_hz;
    float duration_sec;
    float attack_sec;
    float decay_sec;
    float sustain_level;
    float release_sec;
    float gain;
} eng_synth_desc_t;

typedef struct {
    uint32_t clip_id;
    eng_audio_bus_t bus;
    bool loop;
    bool spatial_3d;
    uint16_t pocket_id;
    eng_vec3_t pos;
    eng_vec3_t vel;
    float min_dist;
    float max_dist;
    float gain;
    float pitch;
} eng_voice_desc_t;

typedef struct eng_audio_s eng_audio_t;

eng_synth_desc_t eng_synth_default_desc(eng_synth_wave_t wave, float freq_hz, float duration_sec);
eng_voice_desc_t eng_voice_default_desc(uint32_t clip_id);

eng_audio_t *eng_audio_create(bool headless);
void eng_audio_destroy(eng_audio_t *aud);

void eng_audio_set_bus_gain(eng_audio_t *aud, eng_audio_bus_t bus, float gain);
float eng_audio_get_bus_gain(const eng_audio_t *aud, eng_audio_bus_t bus);

void eng_audio_set_listener(eng_audio_t *aud, uint16_t pocket_id,
                            eng_vec3_t pos, eng_vec3_t vel, eng_quat_t rot);

uint32_t eng_audio_load_wav_mem(eng_audio_t *aud, const void *bytes, size_t len);
uint32_t eng_audio_load_ogg_mem(eng_audio_t *aud, const void *bytes, size_t len);
uint32_t eng_audio_load_vfs(eng_audio_t *aud, const eng_vfs_t *vfs, const char *vpath);
uint32_t eng_audio_synth_retro(eng_audio_t *aud, const eng_synth_desc_t *desc);

uint32_t eng_audio_play(eng_audio_t *aud, const eng_voice_desc_t *desc);
void eng_audio_stop(eng_audio_t *aud, uint32_t voice_id);

/* Mix stereo 48kHz float32 frames (L, R interleaved) with 3D panning, attenuation, Doppler, and cross-portal doorway routing. */
void eng_audio_mix_frames(eng_audio_t *aud, const eng_scene_t *scene,
                          const eng_portal_sys_t *portals,
                          float *out_stereo_lr, size_t frames);

/* Pump SDL3 audio stream for frame dt (no-op in headless mode). */
void eng_audio_update(eng_audio_t *aud, const eng_scene_t *scene,
                      const eng_portal_sys_t *portals, float dt);

#ifdef __cplusplus
}
#endif

#endif /* ENG_AUDIO_H */
