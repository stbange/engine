#ifndef ENG_PARTICLES_H
#define ENG_PARTICLES_H

#include "eng_math.h"
#include "eng_sprite.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    eng_vec3_t origin;
    eng_vec3_t dir;
    float spread_rad;
    float speed_min, speed_max;
    float life_min, life_max;
    float size_start, size_end;
    eng_vec4_t color_start;
    eng_vec4_t color_end;
    eng_vec3_t gravity;
    float drag;
    float spawn_rate; /* particles/sec */
    uint32_t tex_id;
    uint16_t pocket_id;
    bool active;
    bool additive;
} eng_emitter_cfg_t;

typedef struct eng_emitter_s eng_emitter_t;

eng_emitter_cfg_t eng_emitter_default_cfg(void);
eng_emitter_t *eng_emitter_create(size_t capacity, uint64_t seed, const eng_emitter_cfg_t *cfg);
void eng_emitter_destroy(eng_emitter_t *em);

void eng_emitter_set_cfg(eng_emitter_t *em, const eng_emitter_cfg_t *cfg);
void eng_emitter_set_pos(eng_emitter_t *em, eng_vec3_t origin, int pocket_id);
void eng_emitter_set_rate(eng_emitter_t *em, float spawn_rate);
size_t eng_emitter_burst(eng_emitter_t *em, size_t count);
void eng_emitter_step(eng_emitter_t *em, float dt);

size_t eng_emitter_alive_count(const eng_emitter_t *em);

/* Write active particles as camera-facing spherical sprites into out_sprites (up to max_out). */
size_t eng_emitter_collect_sprites(const eng_emitter_t *em, eng_sprite_item_t *out_sprites, size_t max_out);

#ifdef __cplusplus
}
#endif

#endif /* ENG_PARTICLES_H */
