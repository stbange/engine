#include "engine/eng_particles.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    eng_vec3_t pos;
    eng_vec3_t vel;
    float age;
    float life;
} particle_t;

struct eng_emitter_s {
    eng_emitter_cfg_t cfg;
    eng_rng_t rng;
    particle_t *pool;
    size_t cap;
    size_t count;
    float spawn_accum;
};

eng_emitter_cfg_t eng_emitter_default_cfg(void) {
    return (eng_emitter_cfg_t){
        .origin = {0, 0, 0},
        .dir = {0, 1, 0},
        .spread_rad = 0.45f,
        .speed_min = 2.0f,
        .speed_max = 5.0f,
        .life_min = 0.4f,
        .life_max = 1.2f,
        .size_start = 0.25f,
        .size_end = 0.04f,
        .color_start = {1.0f, 0.85f, 0.35f, 1.0f},
        .color_end = {0.9f, 0.2f, 0.05f, 0.0f},
        .gravity = {0.0f, -6.0f, 0.0f},
        .drag = 0.5f,
        .spawn_rate = 30.0f,
        .tex_id = 0,
        .pocket_id = 0,
        .active = true
    };
}

eng_emitter_t *eng_emitter_create(size_t capacity, uint64_t seed, const eng_emitter_cfg_t *cfg) {
    if (capacity == 0) return NULL;
    eng_emitter_t *em = (eng_emitter_t *)calloc(1, sizeof(eng_emitter_t));
    if (!em) return NULL;
    em->pool = (particle_t *)calloc(capacity, sizeof(particle_t));
    if (!em->pool) {
        free(em);
        return NULL;
    }
    em->cap = capacity;
    em->cfg = cfg ? *cfg : eng_emitter_default_cfg();
    eng_rng_seed(&em->rng, seed ? seed : 1u);
    return em;
}

void eng_emitter_destroy(eng_emitter_t *em) {
    if (!em) return;
    free(em->pool);
    free(em);
}

void eng_emitter_set_cfg(eng_emitter_t *em, const eng_emitter_cfg_t *cfg) {
    if (em && cfg) em->cfg = *cfg;
}

static bool spawn_one(eng_emitter_t *em) {
    if (em->count >= em->cap) return false;
    eng_vec3_t base_dir = eng_v3_norm(em->cfg.dir);
    if (eng_v3_dot(base_dir, base_dir) < 0.1f) base_dir = eng_v3(0.0f, 1.0f, 0.0f);

    eng_vec3_t jitter = eng_v3(
        eng_rng_rangef(&em->rng, -1.0f, 1.0f) * em->cfg.spread_rad,
        eng_rng_rangef(&em->rng, -1.0f, 1.0f) * em->cfg.spread_rad,
        eng_rng_rangef(&em->rng, -1.0f, 1.0f) * em->cfg.spread_rad
    );
    eng_vec3_t d = eng_v3_norm(eng_v3_add(base_dir, jitter));
    float spd = eng_rng_rangef(&em->rng, em->cfg.speed_min, em->cfg.speed_max);
    float life = eng_rng_rangef(&em->rng, em->cfg.life_min, em->cfg.life_max);

    particle_t *p = &em->pool[em->count++];
    p->pos = em->cfg.origin;
    p->vel = eng_v3_scale(d, spd);
    p->age = 0.0f;
    p->life = life > 0.01f ? life : 0.1f;
    return true;
}

size_t eng_emitter_burst(eng_emitter_t *em, size_t count) {
    if (!em) return 0;
    size_t n = 0;
    for (size_t i = 0; i < count; i++) {
        if (!spawn_one(em)) break;
        n++;
    }
    return n;
}

void eng_emitter_step(eng_emitter_t *em, float dt) {
    if (!em || dt <= 0.0f) return;
    if (em->cfg.active && em->cfg.spawn_rate > 0.0f) {
        em->spawn_accum += em->cfg.spawn_rate * dt;
        while (em->spawn_accum >= 1.0f) {
            em->spawn_accum -= 1.0f;
            spawn_one(em);
        }
    }

    float damp = expf(-em->cfg.drag * dt);
    for (size_t i = 0; i < em->count;) {
        particle_t *p = &em->pool[i];
        p->age += dt;
        if (p->age >= p->life) {
            /* O(1) swap-and-pop compaction */
            em->pool[i] = em->pool[--em->count];
            continue;
        }
        p->vel = eng_v3_scale(eng_v3_add(p->vel, eng_v3_scale(em->cfg.gravity, dt)), damp);
        p->pos = eng_v3_add(p->pos, eng_v3_scale(p->vel, dt));
        i++;
    }
}

size_t eng_emitter_alive_count(const eng_emitter_t *em) {
    return em ? em->count : 0;
}

size_t eng_emitter_collect_sprites(const eng_emitter_t *em, eng_sprite_item_t *out_sprites, size_t max_out) {
    if (!em || !out_sprites || max_out == 0) return 0;
    size_t n = em->count < max_out ? em->count : max_out;
    for (size_t i = 0; i < n; i++) {
        const particle_t *p = &em->pool[i];
        float t = eng_clampf(p->age / p->life, 0.0f, 1.0f);
        float sz = eng_lerpf(em->cfg.size_start, em->cfg.size_end, t);
        eng_sprite_item_t *sp = &out_sprites[i];
        sp->pos = p->pos;
        sp->size = (eng_vec2_t){sz, sz};
        sp->facing_yaw_rad = 0.0f;
        sp->uv_rect = (eng_vec4_t){0.0f, 0.0f, 1.0f, 1.0f};
        sp->tint = (eng_vec4_t){
            eng_lerpf(em->cfg.color_start.x, em->cfg.color_end.x, t),
            eng_lerpf(em->cfg.color_start.y, em->cfg.color_end.y, t),
            eng_lerpf(em->cfg.color_start.z, em->cfg.color_end.z, t),
            eng_lerpf(em->cfg.color_start.w, em->cfg.color_end.w, t)
        };
        sp->tex_id = em->cfg.tex_id;
        sp->pocket_id = em->cfg.pocket_id;
        sp->mode = ENG_SPRITE_BILLBOARD_SPHERICAL;
    }
    return n;
}
