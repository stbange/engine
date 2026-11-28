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
    float sim_time;
};

eng_vec3_t eng_particles_blackbody_color(float temp_k) {
    float t = eng_clampf(temp_k, 800.0f, 12000.0f) * 0.01f;
    float r = (t <= 66.0f) ? 1.0f : eng_clampf(1.292936f * powf(t - 60.0f, -0.1332048f), 0.0f, 1.0f);
    float g = (t <= 66.0f)
                  ? eng_clampf(0.3900816f * logf(fmaxf(t, 1.1f)) - 0.6318414f, 0.0f, 1.0f)
                  : eng_clampf(1.129891f * powf(t - 60.0f, -0.0755148f), 0.0f, 1.0f);
    float b = (t >= 66.0f) ? 1.0f : (t <= 19.0f ? 0.0f : eng_clampf(0.5432068f * logf(t - 10.0f) - 1.196254f, 0.0f, 1.0f));
    float lum = eng_clampf((temp_k - 800.0f) / 1400.0f, 0.0f, 1.0f);
    float boost = 1.0f + fmaxf(temp_k - 1800.0f, 0.0f) * 0.0009f;
    return eng_v3(powf(r, 2.2f) * lum * boost, powf(g, 2.2f) * lum * boost, powf(b, 2.2f) * lum * boost);
}

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
        .active = true,
        .temp_start_k = 3200.0f,
        .temp_end_k = 600.0f
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

void eng_emitter_set_pos(eng_emitter_t *em, eng_vec3_t origin, int pocket_id) {
    if (!em) return;
    em->cfg.origin = origin;
    if (pocket_id >= 0) em->cfg.pocket_id = (uint16_t)pocket_id;
}

void eng_emitter_set_rate(eng_emitter_t *em, float spawn_rate) {
    if (em) em->cfg.spawn_rate = spawn_rate > 0.0f ? spawn_rate : 0.0f;
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

/* Analytically divergence-free 3D curl of separable trig vector potential A(x,y,z,t) */
static eng_vec3_t sample_curl_noise(eng_vec3_t p, float t) {
    float cx = -1.5f * sinf(1.3f * p.x - 1.9f * t) * sinf(1.5f * p.y + 1.6f * t)
               - 1.5f * cosf(1.5f * p.z + 1.8f * t) * cosf(1.7f * p.x + 1.2f * t);
    float cy = -1.3f * sinf(1.7f * p.y + 2.1f * t) * sinf(1.3f * p.z - 1.4f * t)
               - 1.3f * cosf(1.3f * p.x - 1.9f * t) * cosf(1.5f * p.y + 1.6f * t);
    float cz = -1.7f * sinf(1.5f * p.z + 1.8f * t) * sinf(1.7f * p.x + 1.2f * t)
               - 1.7f * cosf(1.7f * p.y + 2.1f * t) * cosf(1.3f * p.z - 1.4f * t);
    return eng_v3(cx, cy, cz);
}

void eng_emitter_step(eng_emitter_t *em, float dt) {
    if (!em || dt <= 0.0f) return;
    em->sim_time += dt;
    if (em->cfg.active && em->cfg.spawn_rate > 0.0f) {
        em->spawn_accum += em->cfg.spawn_rate * dt;
        while (em->spawn_accum >= 1.0f) {
            em->spawn_accum -= 1.0f;
            spawn_one(em);
        }
    }

    float damp = expf(-em->cfg.drag * dt);
    bool has_turb = (em->cfg.turbulence > 1e-4f);
    bool has_wind = (eng_v3_dot(em->cfg.wind, em->cfg.wind) > 1e-6f);
    for (size_t i = 0; i < em->count;) {
        particle_t *p = &em->pool[i];
        p->age += dt;
        if (p->age >= p->life) {
            /* O(1) swap-and-pop compaction */
            em->pool[i] = em->pool[--em->count];
            continue;
        }
        eng_vec3_t acc = em->cfg.gravity;
        if (has_turb) {
            eng_vec3_t curl = sample_curl_noise(p->pos, em->sim_time);
            acc = eng_v3_add(acc, eng_v3_scale(curl, em->cfg.turbulence));
        }
        if (has_wind) {
            acc = eng_v3_add(acc, em->cfg.wind);
        }
        p->vel = eng_v3_scale(eng_v3_add(p->vel, eng_v3_scale(acc, dt)), damp);
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
        sp->facing_yaw_rad = 0.0f;
        sp->uv_rect = (eng_vec4_t){0.0f, 0.0f, 1.0f, 1.0f};
        sp->tex_id = em->cfg.tex_id;
        sp->pocket_id = em->cfg.pocket_id;
        sp->mode = ENG_SPRITE_BILLBOARD_SPHERICAL;

        if (em->cfg.blackbody) {
            float temp = eng_lerpf(em->cfg.temp_start_k > 0.0f ? em->cfg.temp_start_k : 3300.0f,
                                   em->cfg.temp_end_k > 0.0f ? em->cfg.temp_end_k : 550.0f, t);
            if (temp >= 950.0f) {
                eng_vec3_t bb = eng_particles_blackbody_color(temp);
                float fade_in = eng_clampf(t * 7.0f, 0.15f, 1.0f);
                sp->tint = (eng_vec4_t){bb.x, bb.y, bb.z, em->cfg.color_start.w * fade_in};
                sp->additive = true;
            } else {
                float soot_u = eng_clampf((950.0f - temp) / 350.0f, 0.0f, 1.0f);
                sz *= (1.0f + 0.85f * soot_u);
                float alpha = (1.0f - t) * 0.55f;
                sp->tint = (eng_vec4_t){0.13f, 0.12f, 0.12f, alpha};
                sp->additive = false;
            }
        } else {
            sp->tint = (eng_vec4_t){
                eng_lerpf(em->cfg.color_start.x, em->cfg.color_end.x, t),
                eng_lerpf(em->cfg.color_start.y, em->cfg.color_end.y, t),
                eng_lerpf(em->cfg.color_start.z, em->cfg.color_end.z, t),
                eng_lerpf(em->cfg.color_start.w, em->cfg.color_end.w, t)
            };
            sp->additive = em->cfg.additive;
        }
        sp->size = (eng_vec2_t){sz, sz};
    }
    return n;
}
