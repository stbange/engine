#include "engine/eng_sim.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct eng_sim_s {
    int gx, gy, gz;
    float cell_size;
    eng_vec3_t origin;
    float ambient_c;
    eng_vec3_t wind;
    eng_vec3_t sun_dir; /* unit vector pointing TOWARD sun */
    eng_rng_t rng;
    uint32_t step_tick;

    eng_mat_def_t mats[ENG_SIM_MAX_MATERIALS];
    int mat_count;

    eng_sim_cell_t *cells;
    float *scent_scratch;
    uint8_t *moved;

    eng_plant_t plants[ENG_SIM_MAX_PLANTS];
    uint32_t plant_high;

    eng_bio_body_t agents[ENG_SIM_MAX_AGENTS];
    uint32_t agent_high;

    eng_sim_blast_t blasts[ENG_SIM_MAX_BLASTS];
    size_t blast_count;
};

static int cell_idx(const eng_sim_t *s, int x, int y, int z) {
    return (y * s->gz + z) * s->gx + x;
}

static bool in_bounds(const eng_sim_t *s, int x, int y, int z) {
    return x >= 0 && y >= 0 && z >= 0 && x < s->gx && y < s->gy && z < s->gz;
}

static void register_builtin_materials(eng_sim_t *s) {
    for (int i = 0; i < ENG_SIM_MAX_MATERIALS; i++) {
        s->mats[i].melt_temp_c = 9999.0f;
        s->mats[i].boil_temp_c = 9999.0f;
        s->mats[i].freeze_temp_c = -9999.0f;
        s->mats[i].ignite_temp_c = 9999.0f;
        s->mats[i].heat_capacity = 1.0f;
    }

#define DEF_MAT(id, nm, ph, dens, k_th, cp, melt_t, melt_to, boil_t, boil_to, frz_t, frz_to, ign_t, fuel_e, burn_to, expl, el_c, corr, r, g, b) \
    do { \
        eng_mat_def_t *m = &s->mats[id]; \
        memset(m, 0, sizeof(*m)); \
        snprintf(m->name, sizeof(m->name), "%s", nm); \
        m->phase = ph; m->density = dens; m->thermal_cond = k_th; m->heat_capacity = cp; \
        m->melt_temp_c = melt_t; m->melt_into = (uint8_t)(melt_to); \
        m->boil_temp_c = boil_t; m->boil_into = (uint8_t)(boil_to); \
        m->freeze_temp_c = frz_t; m->freeze_into = (uint8_t)(frz_to); \
        m->ignite_temp_c = ign_t; m->fuel_energy = fuel_e; m->burn_into = (uint8_t)(burn_to); \
        m->explosive = expl; m->elec_cond = el_c; m->corrosiveness = corr; \
        m->color_rgb[0] = r; m->color_rgb[1] = g; m->color_rgb[2] = b; \
    } while (0)

    DEF_MAT(ENG_MAT_AIR,        "air",        ENG_PHASE_GAS,         1.2f, 0.08f, 0.3f, 9999, 0, 9999, 0, -9999, 0, 9999,   0, 0, false, 0.00f, 0.00f, 0.00f, 0.00f, 0.00f);
    DEF_MAT(ENG_MAT_WATER,      "water",      ENG_PHASE_LIQUID,   1000.0f, 0.55f, 4.2f, 9999, 1,  100, ENG_MAT_STEAM,   -2, ENG_MAT_ICE,   9999,   0, 0, false, 0.18f, 0.00f, 0.12f, 0.42f, 0.72f);
    DEF_MAT(ENG_MAT_SALT_WATER, "salt_water", ENG_PHASE_LIQUID,   1025.0f, 0.58f, 4.0f, 9999, 2,  102, ENG_MAT_STEAM,   -6, ENG_MAT_ICE,   9999,   0, 0, false, 0.88f, 0.00f, 0.10f, 0.48f, 0.68f);
    DEF_MAT(ENG_MAT_ICE,        "ice",        ENG_PHASE_SOLID,     917.0f, 0.65f, 2.1f,    0, ENG_MAT_WATER, 9999, 3, -9999, 3, 9999,   0, 0, false, 0.02f, 0.00f, 0.72f, 0.88f, 0.96f);
    DEF_MAT(ENG_MAT_STEAM,      "steam",      ENG_PHASE_GAS,         0.6f, 0.18f, 1.9f, 9999, 4, 9999, 4,    85, ENG_MAT_WATER, 9999,   0, 0, false, 0.04f, 0.00f, 0.85f, 0.88f, 0.92f);
    DEF_MAT(ENG_MAT_OIL,        "oil",        ENG_PHASE_LIQUID,    800.0f, 0.22f, 2.0f, 9999, 5,  320, ENG_MAT_SMOKE, -9999, 5,  200, 620, ENG_MAT_AIR,      false, 0.00f, 0.00f, 0.16f, 0.13f, 0.08f);
    DEF_MAT(ENG_MAT_ETHANOL,    "ethanol",    ENG_PHASE_LIQUID,    789.0f, 0.24f, 2.4f, 9999, 6,   78, ENG_MAT_METHANE,-9999, 6,  130, 540, ENG_MAT_AIR,      false, 0.00f, 0.00f, 0.82f, 0.86f, 0.90f);
    DEF_MAT(ENG_MAT_LAVA,       "lava",       ENG_PHASE_LIQUID,   2700.0f, 0.75f, 1.4f, 9999, 7, 9999, 7,   700, ENG_MAT_STONE, 9999,   0, 0, false, 0.25f, 0.00f, 1.00f, 0.28f, 0.03f);
    DEF_MAT(ENG_MAT_WOOD,       "wood",       ENG_PHASE_SOLID,     600.0f, 0.16f, 1.7f, 9999, 8, 9999, 8, -9999, 8,  260, 420, ENG_MAT_ASH,      false, 0.00f, 0.00f, 0.46f, 0.28f, 0.14f);
    DEF_MAT(ENG_MAT_CHARCOAL,   "charcoal",   ENG_PHASE_SOLID,     450.0f, 0.18f, 1.2f, 9999, 9, 9999, 9, -9999, 9,  320, 520, ENG_MAT_ASH,      false, 0.08f, 0.00f, 0.12f, 0.11f, 0.10f);
    DEF_MAT(ENG_MAT_ASH,        "ash",        ENG_PHASE_GRANULAR,  520.0f, 0.12f, 0.9f, 9999,10, 9999,10, -9999,10, 9999,   0, 0, false, 0.02f, 0.00f, 0.52f, 0.50f, 0.48f);
    DEF_MAT(ENG_MAT_FOLIAGE,    "foliage",    ENG_PHASE_SOLID,     350.0f, 0.14f, 1.5f, 9999,11, 9999,11, -9999,11,  185, 380, ENG_MAT_ASH,      false, 0.03f, 0.00f, 0.22f, 0.56f, 0.18f);
    DEF_MAT(ENG_MAT_GUNPOWDER,  "gunpowder",  ENG_PHASE_GRANULAR, 1100.0f, 0.20f, 1.0f, 9999,12, 9999,12, -9999,12,  170, 950, ENG_MAT_SMOKE,     true, 0.02f, 0.00f, 0.22f, 0.22f, 0.24f);
    DEF_MAT(ENG_MAT_STONE,      "stone",      ENG_PHASE_SOLID,    2600.0f, 0.52f, 0.9f, 1200, ENG_MAT_LAVA,  9999,13, -9999,13, 9999,   0, 0, false, 0.00f, 0.00f, 0.45f, 0.46f, 0.48f);
    DEF_MAT(ENG_MAT_OBSIDIAN,   "obsidian",   ENG_PHASE_SOLID,    2550.0f, 0.45f, 0.9f, 1350, ENG_MAT_LAVA,  9999,14, -9999,14, 9999,   0, 0, false, 0.00f, 0.00f, 0.09f, 0.07f, 0.12f);
    DEF_MAT(ENG_MAT_SAND,       "sand",       ENG_PHASE_GRANULAR, 1600.0f, 0.30f, 0.8f, 1400, ENG_MAT_GLASS, 9999,15, -9999,15, 9999,   0, 0, false, 0.00f, 0.00f, 0.82f, 0.72f, 0.46f);
    DEF_MAT(ENG_MAT_GLASS,      "glass",      ENG_PHASE_SOLID,    2500.0f, 0.38f, 0.8f, 1950, ENG_MAT_LAVA,  9999,16, -9999,16, 9999,   0, 0, false, 0.00f, 0.00f, 0.78f, 0.90f, 0.92f);
    DEF_MAT(ENG_MAT_SOIL,       "soil",       ENG_PHASE_SOLID,    1300.0f, 0.28f, 1.4f, 9999,17, 9999,17, -9999,17, 9999,   0, 0, false, 0.04f, 0.00f, 0.36f, 0.24f, 0.14f);
    DEF_MAT(ENG_MAT_MUD,        "mud",        ENG_PHASE_GRANULAR, 1700.0f, 0.42f, 2.2f, 9999,18,   80, ENG_MAT_SOIL,  -9999,18, 9999,   0, 0, false, 0.35f, 0.00f, 0.26f, 0.18f, 0.10f);
    DEF_MAT(ENG_MAT_IRON,       "iron",       ENG_PHASE_SOLID,    7800.0f, 0.90f, 0.5f, 1538, ENG_MAT_LAVA,  9999,19, -9999,19, 9999,   0, 0, false, 0.92f, 0.00f, 0.62f, 0.64f, 0.67f);
    DEF_MAT(ENG_MAT_COPPER,     "copper",     ENG_PHASE_SOLID,    8960.0f, 0.98f, 0.4f, 1085, ENG_MAT_LAVA,  9999,20, -9999,20, 9999,   0, 0, false, 1.00f, 0.00f, 0.84f, 0.46f, 0.26f);
    DEF_MAT(ENG_MAT_RUST,       "rust",       ENG_PHASE_GRANULAR, 5200.0f, 0.32f, 0.6f, 9999,21, 9999,21, -9999,21, 9999,   0, 0, false, 0.03f, 0.00f, 0.54f, 0.24f, 0.12f);
    DEF_MAT(ENG_MAT_ACID,       "acid",       ENG_PHASE_LIQUID,   1200.0f, 0.48f, 3.2f, 9999,22,  120, ENG_MAT_SMOKE, -9999,22, 9999,   0, 0, false, 0.82f, 0.85f, 0.42f, 0.92f, 0.18f);
    DEF_MAT(ENG_MAT_SMOKE,      "smoke",      ENG_PHASE_GAS,         0.9f, 0.10f, 0.5f, 9999,23, 9999,23, -9999,23, 9999,   0, 0, false, 0.00f, 0.00f, 0.18f, 0.18f, 0.19f);
    DEF_MAT(ENG_MAT_METHANE,    "methane",    ENG_PHASE_GAS,         0.7f, 0.12f, 0.6f, 9999,24, 9999,24, -9999,24,  180, 880, ENG_MAT_SMOKE,     true, 0.00f, 0.00f, 0.65f, 0.78f, 0.55f);
    DEF_MAT(ENG_MAT_FLESH,      "flesh",      ENG_PHASE_SOLID,    1040.0f, 0.45f, 3.5f, 9999,25, 9999,25, -9999,25,  320, 260, ENG_MAT_ASH,      false, 0.48f, 0.00f, 0.76f, 0.32f, 0.30f);

#undef DEF_MAT
    s->mat_count = ENG_MAT_BUILTIN_COUNT;
}

static void init_cell_for_material(eng_sim_t *s, eng_sim_cell_t *c, uint8_t mat_id) {
    if (mat_id >= (uint8_t)s->mat_count) mat_id = ENG_MAT_AIR;
    const eng_mat_def_t *m = &s->mats[mat_id];
    c->mat = mat_id;
    c->burning = false;
    c->temp_c = s->ambient_c;
    if (mat_id == ENG_MAT_ICE && c->temp_c > -4.0f) c->temp_c = -8.0f;
    else if (mat_id == ENG_MAT_STEAM && c->temp_c < 105.0f) c->temp_c = 115.0f;
    else if (mat_id == ENG_MAT_LAVA) c->temp_c = 1150.0f;

    c->fuel = (m->ignite_temp_c < 5000.0f) ? 1.0f : 0.0f;
    c->wetness = (mat_id == ENG_MAT_WATER || mat_id == ENG_MAT_SALT_WATER || mat_id == ENG_MAT_MUD) ? 1.0f : 0.0f;
    c->voltage = c->voltage_src;
    c->o2 = (m->phase == ENG_PHASE_GAS && mat_id == ENG_MAT_AIR) ? 0.21f : 0.0f;
    c->moisture = (mat_id == ENG_MAT_MUD) ? 0.9f : (mat_id == ENG_MAT_SOIL ? 0.35f : 0.0f);
    c->nutrients = (mat_id == ENG_MAT_SOIL || mat_id == ENG_MAT_MUD) ? 0.30f : (mat_id == ENG_MAT_ASH ? 1.0f : 0.0f);
    c->integrity = 1.0f;
}

eng_sim_t *eng_sim_create(int gx, int gy, int gz, float cell_size, eng_vec3_t origin, uint64_t seed) {
    if (gx <= 0 || gy <= 0 || gz <= 0 || gx > 128 || gy > 128 || gz > 128) return NULL;
    eng_sim_t *s = (eng_sim_t *)calloc(1, sizeof(eng_sim_t));
    if (!s) return NULL;
    s->gx = gx; s->gy = gy; s->gz = gz;
    s->cell_size = cell_size > 0.05f ? cell_size : 0.5f;
    s->origin = origin;
    s->ambient_c = 20.0f;
    s->sun_dir = eng_v3_norm(eng_v3(0.35f, 0.88f, 0.32f));
    eng_rng_seed(&s->rng, seed ? seed : 0x51A7BEEFu);
    register_builtin_materials(s);

    size_t total = (size_t)gx * (size_t)gy * (size_t)gz;
    s->cells = (eng_sim_cell_t *)calloc(total, sizeof(eng_sim_cell_t));
    s->scent_scratch = (float *)calloc(total, sizeof(float));
    s->moved = (uint8_t *)calloc(total, sizeof(uint8_t));
    if (!s->cells || !s->scent_scratch || !s->moved) {
        eng_sim_destroy(s);
        return NULL;
    }
    for (size_t i = 0; i < total; i++) {
        init_cell_for_material(s, &s->cells[i], ENG_MAT_AIR);
    }
    return s;
}

void eng_sim_destroy(eng_sim_t *sim) {
    if (!sim) return;
    free(sim->cells);
    free(sim->scent_scratch);
    free(sim->moved);
    free(sim);
}

void eng_sim_get_dims(const eng_sim_t *sim, int *out_gx, int *out_gy, int *out_gz, float *out_cell_size, eng_vec3_t *out_origin) {
    if (!sim) return;
    if (out_gx) *out_gx = sim->gx;
    if (out_gy) *out_gy = sim->gy;
    if (out_gz) *out_gz = sim->gz;
    if (out_cell_size) *out_cell_size = sim->cell_size;
    if (out_origin) *out_origin = sim->origin;
}

bool eng_sim_world_to_grid(const eng_sim_t *sim, eng_vec3_t wp, int *out_x, int *out_y, int *out_z) {
    if (!sim) return false;
    int x = (int)floorf((wp.x - sim->origin.x) / sim->cell_size);
    int y = (int)floorf((wp.y - sim->origin.y) / sim->cell_size);
    int z = (int)floorf((wp.z - sim->origin.z) / sim->cell_size);
    if (out_x) *out_x = x;
    if (out_y) *out_y = y;
    if (out_z) *out_z = z;
    return in_bounds(sim, x, y, z);
}

eng_vec3_t eng_sim_grid_to_world(const eng_sim_t *sim, int x, int y, int z) {
    if (!sim) return eng_v3(0, 0, 0);
    return eng_v3(sim->origin.x + ((float)x + 0.5f) * sim->cell_size,
                  sim->origin.y + ((float)y + 0.5f) * sim->cell_size,
                  sim->origin.z + ((float)z + 0.5f) * sim->cell_size);
}

int eng_sim_register_material(eng_sim_t *sim, const eng_mat_def_t *def) {
    if (!sim || !def || sim->mat_count >= ENG_SIM_MAX_MATERIALS) return -1;
    int id = sim->mat_count++;
    sim->mats[id] = *def;
    if (sim->mats[id].heat_capacity < 0.1f) sim->mats[id].heat_capacity = 1.0f;
    return id;
}

int eng_sim_find_material(const eng_sim_t *sim, const char *name) {
    if (!sim || !name) return -1;
    for (int i = 0; i < sim->mat_count; i++) {
        if (strcmp(sim->mats[i].name, name) == 0) return i;
    }
    return -1;
}

const eng_mat_def_t *eng_sim_get_material(const eng_sim_t *sim, uint8_t mat_id) {
    return (sim && mat_id < (uint8_t)sim->mat_count) ? &sim->mats[mat_id] : NULL;
}

bool eng_sim_set_cell(eng_sim_t *sim, int x, int y, int z, uint8_t mat_id) {
    if (!sim || !in_bounds(sim, x, y, z) || mat_id >= (uint8_t)sim->mat_count) return false;
    init_cell_for_material(sim, &sim->cells[cell_idx(sim, x, y, z)], mat_id);
    return true;
}

const eng_sim_cell_t *eng_sim_get_cell(const eng_sim_t *sim, int x, int y, int z) {
    if (!sim || !in_bounds(sim, x, y, z)) return NULL;
    return &sim->cells[cell_idx(sim, x, y, z)];
}

eng_sim_cell_t *eng_sim_cell_mut(eng_sim_t *sim, int x, int y, int z) {
    if (!sim || !in_bounds(sim, x, y, z)) return NULL;
    return &sim->cells[cell_idx(sim, x, y, z)];
}

void eng_sim_fill_box(eng_sim_t *sim, int x0, int y0, int z0, int x1, int y1, int z1, uint8_t mat_id) {
    if (!sim) return;
    if (x0 > x1) { int t = x0; x0 = x1; x1 = t; }
    if (y0 > y1) { int t = y0; y0 = y1; y1 = t; }
    if (z0 > z1) { int t = z0; z0 = z1; z1 = t; }
    for (int y = y0; y <= y1; y++) {
        for (int z = z0; z <= z1; z++) {
            for (int x = x0; x <= x1; x++) {
                eng_sim_set_cell(sim, x, y, z, mat_id);
            }
        }
    }
}

bool eng_sim_set_temperature(eng_sim_t *sim, int x, int y, int z, float temp_c) {
    eng_sim_cell_t *c = eng_sim_cell_mut(sim, x, y, z);
    if (!c) return false;
    c->temp_c = eng_clampf(temp_c, -273.15f, 4000.0f);
    return true;
}

bool eng_sim_ignite(eng_sim_t *sim, int x, int y, int z) {
    eng_sim_cell_t *c = eng_sim_cell_mut(sim, x, y, z);
    if (!c) return false;
    const eng_mat_def_t *m = &sim->mats[c->mat];
    if (m->ignite_temp_c >= 5000.0f) return false;
    if (c->temp_c < m->ignite_temp_c + 40.0f) c->temp_c = m->ignite_temp_c + 40.0f;
    if (!m->explosive) c->burning = true;
    return true;
}

bool eng_sim_set_voltage_source(eng_sim_t *sim, int x, int y, int z, float volts) {
    eng_sim_cell_t *c = eng_sim_cell_mut(sim, x, y, z);
    if (!c) return false;
    c->voltage_src = fmaxf(volts, 0.0f);
    c->voltage = c->voltage_src;
    return true;
}

void eng_sim_set_ambient_temp(eng_sim_t *sim, float ambient_c) {
    if (sim) sim->ambient_c = eng_clampf(ambient_c, -100.0f, 200.0f);
}

void eng_sim_set_wind(eng_sim_t *sim, eng_vec3_t wind_vel) {
    if (sim) sim->wind = wind_vel;
}

void eng_sim_set_sun_dir(eng_sim_t *sim, eng_vec3_t dir_to_light) {
    if (!sim) return;
    eng_vec3_t d = eng_v3_norm(dir_to_light);
    if (eng_v3_dot(d, d) > 0.5f) sim->sun_dir = d;
}

void eng_sim_apply_rain(eng_sim_t *sim, float intensity, float dt) {
    if (!sim || intensity <= 0.0f || dt <= 0.0f) return;
    float amt = eng_clampf(intensity, 0.0f, 2.0f) * dt;
    for (int z = 0; z < sim->gz; z++) {
        for (int x = 0; x < sim->gx; x++) {
            /* Trace downward from sky until hitting first non-gas surface */
            for (int y = sim->gy - 1; y >= 0; y--) {
                eng_sim_cell_t *c = &sim->cells[cell_idx(sim, x, y, z)];
                if (sim->mats[c->mat].phase == ENG_PHASE_GAS) continue;
                c->wetness = eng_clampf(c->wetness + amt * 0.9f, 0.0f, 1.0f);
                if (c->mat == ENG_MAT_SOIL || c->mat == ENG_MAT_MUD) {
                    c->moisture = eng_clampf(c->moisture + amt * 0.6f, 0.0f, 1.0f);
                }
                if (c->burning && c->wetness > 0.65f) {
                    c->burning = false;
                    if (y + 1 < sim->gy && sim->cells[cell_idx(sim, x, y + 1, z)].mat == ENG_MAT_AIR) {
                        eng_sim_set_cell(sim, x, y + 1, z, ENG_MAT_STEAM);
                    }
                }
                break;
            }
        }
    }
}

uint32_t eng_sim_add_plant(eng_sim_t *sim, int soil_x, int soil_y, int soil_z, eng_entity_t entity) {
    if (!sim || !in_bounds(sim, soil_x, soil_y, soil_z)) return 0;
    for (uint32_t i = 0; i < ENG_SIM_MAX_PLANTS; i++) {
        if (!sim->plants[i].active) {
            sim->plants[i] = (eng_plant_t){
                .active = true, .entity = entity,
                .gx = soil_x, .gy = soil_y, .gz = soil_z,
                .stage = ENG_PLANT_SEED, .growth = 0.05f, .health = 1.0f, .sun_exposure = 1.0f
            };
            if (i + 1u > sim->plant_high) sim->plant_high = i + 1u;
            return i + 1u;
        }
    }
    return 0;
}

const eng_plant_t *eng_sim_get_plant(const eng_sim_t *sim, uint32_t plant_id) {
    if (!sim || plant_id == 0 || plant_id > ENG_SIM_MAX_PLANTS || !sim->plants[plant_id - 1u].active) return NULL;
    return &sim->plants[plant_id - 1u];
}

uint32_t eng_sim_add_bio(eng_sim_t *sim, eng_vec3_t pos, bool aquatic, float scent_strength, eng_entity_t entity) {
    if (!sim) return 0;
    for (uint32_t i = 0; i < ENG_SIM_MAX_AGENTS; i++) {
        if (!sim->agents[i].active) {
            sim->agents[i] = (eng_bio_body_t){
                .active = true, .entity = entity, .pos = pos,
                .head_offset_y = aquatic ? 0.1f : 0.6f, .aquatic = aquatic,
                .core_temp_c = 37.0f, .wetness = aquatic ? 1.0f : 0.0f,
                .o2_level = 1.0f, .hydration = 1.0f, .energy = 1.0f, .health = 1.0f,
                .scent_strength = fmaxf(scent_strength, 0.0f)
            };
            if (i + 1u > sim->agent_high) sim->agent_high = i + 1u;
            return i + 1u;
        }
    }
    return 0;
}

eng_bio_body_t *eng_sim_get_bio(eng_sim_t *sim, uint32_t bio_id) {
    if (!sim || bio_id == 0 || bio_id > ENG_SIM_MAX_AGENTS || !sim->agents[bio_id - 1u].active) return NULL;
    return &sim->agents[bio_id - 1u];
}

void eng_sim_apply_bio_trauma(eng_sim_t *sim, uint32_t bio_id, float kinetic_dmg, float thermal_dmg, float chem_dmg) {
    eng_bio_body_t *b = eng_sim_get_bio(sim, bio_id);
    if (!b) return;
    float total = fmaxf(kinetic_dmg, 0.0f) + fmaxf(thermal_dmg, 0.0f) + fmaxf(chem_dmg, 0.0f);
    b->health = eng_clampf(b->health - total, 0.0f, 1.0f);
}

static void swap_cells_matter(eng_sim_cell_t *a, eng_sim_cell_t *b) {
    float sa = a->scent, sb = b->scent;
    float vsa = a->voltage_src, vsb = b->voltage_src;
    eng_sim_cell_t tmp = *a;
    *a = *b;
    *b = tmp;
    a->scent = sa; b->scent = sb;
    a->voltage_src = vsa; b->voltage_src = vsb;
}

static float cell_elec_cond(const eng_sim_t *s, const eng_sim_cell_t *c) {
    float base = s->mats[c->mat].elec_cond;
    float wet_c = (c->wetness > 0.35f) ? (0.65f * c->wetness) : 0.0f;
    return fmaxf(base, wet_c);
}

static float sample_scent_grid_trilinear(const eng_sim_t *s, float fx, float fy, float fz) {
    if (fx < -0.5f || fy < -0.5f || fz < -0.5f ||
        fx > (float)s->gx - 0.5f || fy > (float)s->gy - 0.5f || fz > (float)s->gz - 0.5f) {
        return 0.0f;
    }
    int x0 = (int)floorf(fx), y0 = (int)floorf(fy), z0 = (int)floorf(fz);
    float tx = fx - (float)x0, ty = fy - (float)y0, tz = fz - (float)z0;
    float acc = 0.0f;
    for (int dy = 0; dy <= 1; dy++) {
        float wy = dy ? ty : (1.0f - ty);
        int yy = x0; (void)yy;
        int cy = (y0 + dy < 0) ? 0 : ((y0 + dy >= s->gy) ? s->gy - 1 : y0 + dy);
        for (int dz = 0; dz <= 1; dz++) {
            float wz = dz ? tz : (1.0f - tz);
            int cz = (z0 + dz < 0) ? 0 : ((z0 + dz >= s->gz) ? s->gz - 1 : z0 + dz);
            for (int dx = 0; dx <= 1; dx++) {
                float wx = dx ? tx : (1.0f - tx);
                int cx = (x0 + dx < 0) ? 0 : ((x0 + dx >= s->gx) ? s->gx - 1 : x0 + dx);
                acc += wx * wy * wz * s->cells[cell_idx(s, cx, cy, cz)].scent;
            }
        }
    }
    return acc;
}

float eng_sim_sample_scent(const eng_sim_t *sim, eng_vec3_t world_pos) {
    if (!sim) return 0.0f;
    float fx = (world_pos.x - sim->origin.x) / sim->cell_size - 0.5f;
    float fy = (world_pos.y - sim->origin.y) / sim->cell_size - 0.5f;
    float fz = (world_pos.z - sim->origin.z) / sim->cell_size - 0.5f;
    return sample_scent_grid_trilinear(sim, fx, fy, fz);
}

float eng_sim_check_visibility(const eng_sim_t *sim, eng_vec3_t from, eng_vec3_t to,
                               float ambient_light, float fog_density) {
    if (!sim) return 0.0f;
    eng_vec3_t delta = eng_v3_sub(to, from);
    float dist = eng_v3_len(delta);
    if (dist < 1e-4f) return 1.0f;
    float vis = eng_clampf(ambient_light, 0.02f, 1.0f) * expf(-fmaxf(fog_density, 0.0f) * dist);
    int steps = (int)ceilf(dist / (sim->cell_size * 0.65f));
    if (steps > 128) steps = 128;
    for (int i = 1; i < steps; i++) {
        float u = (float)i / (float)steps;
        eng_vec3_t p = eng_v3_add(from, eng_v3_scale(delta, u));
        int gx, gy, gz;
        if (!eng_sim_world_to_grid(sim, p, &gx, &gy, &gz)) continue;
        uint8_t mat = sim->cells[cell_idx(sim, gx, gy, gz)].mat;
        if (mat == ENG_MAT_SMOKE || mat == ENG_MAT_STEAM) {
            vis *= 0.55f;
        } else if (sim->mats[mat].phase == ENG_PHASE_SOLID && mat != ENG_MAT_GLASS && mat != ENG_MAT_ICE) {
            return 0.0f;
        } else if (sim->mats[mat].phase == ENG_PHASE_LIQUID) {
            vis *= 0.72f;
        }
        if (vis < 0.01f) return 0.0f;
    }
    return eng_clampf(vis, 0.0f, 1.0f);
}

static void push_blast(eng_sim_t *s, int x, int y, int z, float radius, float impulse) {
    if (s->blast_count >= ENG_SIM_MAX_BLASTS) return;
    s->blasts[s->blast_count++] = (eng_sim_blast_t){eng_sim_grid_to_world(s, x, y, z), radius, impulse};
}

void eng_sim_step(eng_sim_t *s, float dt) {
    if (!s || dt <= 0.0f) return;
    if (dt > 0.1f) dt = 0.1f;
    s->step_tick++;
    size_t total = (size_t)s->gx * (size_t)s->gy * (size_t)s->gz;
    memset(s->moved, 0, total);

    static const int d6[6][3] = {{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}};
    static const int d4[4][2] = {{1,0}, {-1,0}, {0,1}, {0,-1}};

    /* 1. Gravity, density stratification (oil floats on water!) & fluid spreading */
    for (int y = 0; y < s->gy; y++) {
        for (int z = 0; z < s->gz; z++) {
            for (int x = 0; x < s->gx; x++) {
                int idx = cell_idx(s, x, y, z);
                if (s->moved[idx]) continue;
                eng_sim_cell_t *c = &s->cells[idx];
                const eng_mat_def_t *mc = &s->mats[c->mat];
                if (mc->phase != ENG_PHASE_LIQUID && mc->phase != ENG_PHASE_GRANULAR) continue;

                if (y > 0) {
                    int dn_idx = cell_idx(s, x, y - 1, z);
                    eng_sim_cell_t *dn = &s->cells[dn_idx];
                    const eng_mat_def_t *md = &s->mats[dn->mat];
                    if (!s->moved[dn_idx] &&
                        (md->phase == ENG_PHASE_GAS ||
                         (md->phase == ENG_PHASE_LIQUID && mc->density > md->density * 1.03f))) {
                        swap_cells_matter(c, dn);
                        s->moved[idx] = s->moved[dn_idx] = 1;
                        continue;
                    }
                }

                if (mc->phase == ENG_PHASE_LIQUID && !(c->mat == ENG_MAT_LAVA && (s->step_tick & 3u) != 0u)) {
                    int start_d = (int)((s->step_tick + (uint32_t)(x * 7 + z * 13)) & 3u);
                    for (int k = 0; k < 4; k++) {
                        int d = (start_d + k) & 3;
                        int nx = x + d4[d][0], nz = z + d4[d][1];
                        if (!in_bounds(s, nx, y, nz)) continue;
                        int nidx = cell_idx(s, nx, y, nz);
                        if (s->moved[nidx]) continue;
                        eng_sim_cell_t *nb = &s->cells[nidx];
                        if (nb->mat == ENG_MAT_AIR) {
                            swap_cells_matter(c, nb);
                            s->moved[idx] = s->moved[nidx] = 1;
                            break;
                        }
                    }
                }
            }
        }
    }

    /* Rising buoyant gases (steam, smoke, methane) + lighter liquid rising through heavier liquid */
    for (int y = s->gy - 2; y >= 0; y--) {
        for (int z = 0; z < s->gz; z++) {
            for (int x = 0; x < s->gx; x++) {
                int idx = cell_idx(s, x, y, z);
                if (s->moved[idx]) continue;
                eng_sim_cell_t *c = &s->cells[idx];
                const eng_mat_def_t *mc = &s->mats[c->mat];
                int up_idx = cell_idx(s, x, y + 1, z);
                eng_sim_cell_t *up = &s->cells[up_idx];
                const eng_mat_def_t *mu = &s->mats[up->mat];

                if (!s->moved[up_idx]) {
                    if (mc->phase == ENG_PHASE_GAS && c->mat != ENG_MAT_AIR && up->mat == ENG_MAT_AIR && mc->density < 1.15f) {
                        swap_cells_matter(c, up);
                        s->moved[idx] = s->moved[up_idx] = 1;
                    } else if (mc->phase == ENG_PHASE_LIQUID && mu->phase == ENG_PHASE_LIQUID && mu->density > mc->density * 1.03f) {
                        swap_cells_matter(c, up);
                        s->moved[idx] = s->moved[up_idx] = 1;
                    }
                }
            }
        }
    }

    /* 2. Heat conduction/convection, O2 diffusion, lava+water, wetting, ash fertility, acid & rust */
    for (int y = 0; y < s->gy; y++) {
        for (int z = 0; z < s->gz; z++) {
            for (int x = 0; x < s->gx; x++) {
                int idx = cell_idx(s, x, y, z);
                eng_sim_cell_t *c = &s->cells[idx];
                const eng_mat_def_t *mc = &s->mats[c->mat];

                /* Open grid border air replenishes atmospheric O2 (sealed stone rooms do not!) */
                bool on_border = (x == 0 || y == s->gy - 1 || z == 0 || x == s->gx - 1 || z == s->gz - 1);
                if (c->mat == ENG_MAT_AIR && on_border) {
                    c->o2 = eng_lerpf(c->o2, 0.21f, eng_clampf(2.5f * dt, 0.0f, 1.0f));
                }
                if (c->mat == ENG_MAT_SMOKE && eng_rng_float01(&s->rng) < 0.35f * dt) {
                    c->mat = ENG_MAT_AIR;
                    c->o2 = on_border ? 0.21f : 0.08f;
                }

                float avail_o2 = (mc->phase == ENG_PHASE_GAS) ? c->o2 : 0.0f;
                bool touches_water = false;
                bool touches_salt = false;

                for (int d = 0; d < 6; d++) {
                    int nx = x + d6[d][0], ny = y + d6[d][1], nz = z + d6[d][2];
                    if (!in_bounds(s, nx, ny, nz)) continue;
                    eng_sim_cell_t *nb = &s->cells[cell_idx(s, nx, ny, nz)];
                    const eng_mat_def_t *mn = &s->mats[nb->mat];

                    /* Pairwise heat conduction + upward convection boost */
                    if (nx > x || ny > y || nz > z) {
                        float k_pair = 0.5f * (mc->thermal_cond + mn->thermal_cond);
                        if (ny > y && c->temp_c > nb->temp_c) k_pair += 0.35f;
                        float c_eff = fminf(mc->heat_capacity, mn->heat_capacity);
                        float rate = fminf(k_pair * 2.2f * dt, 0.45f);
                        float flux = (nb->temp_c - c->temp_c) * rate * c_eff;
                        c->temp_c += flux / mc->heat_capacity;
                        nb->temp_c -= flux / mn->heat_capacity;

                        if (mc->phase == ENG_PHASE_GAS && mn->phase == ENG_PHASE_GAS) {
                            float do2 = (nb->o2 - c->o2) * 3.0f * dt;
                            c->o2 = eng_clampf(c->o2 + do2, 0.0f, 0.21f);
                            nb->o2 = eng_clampf(nb->o2 - do2, 0.0f, 0.21f);
                        }
                    }

                    if (mn->phase == ENG_PHASE_GAS && nb->o2 > avail_o2) avail_o2 = nb->o2;
                    if (nb->mat == ENG_MAT_WATER || nb->mat == ENG_MAT_SALT_WATER) touches_water = true;
                    if (nb->mat == ENG_MAT_SALT_WATER) touches_salt = true;

                    /* Lava + Water/Ice -> Obsidian + hot rising Steam */
                    if (c->mat == ENG_MAT_LAVA && (nb->mat == ENG_MAT_WATER || nb->mat == ENG_MAT_SALT_WATER || nb->mat == ENG_MAT_ICE)) {
                        c->mat = ENG_MAT_OBSIDIAN;
                        c->temp_c = 340.0f;
                        nb->mat = ENG_MAT_STEAM;
                        nb->temp_c = 165.0f;
                        nb->wetness = 0.0f;
                    }

                    /* Water wetting & soil moisture seepage */
                    if (c->mat == ENG_MAT_WATER || c->mat == ENG_MAT_SALT_WATER) {
                        if (mn->phase == ENG_PHASE_SOLID) nb->wetness = fminf(1.0f, nb->wetness + 1.5f * dt);
                        if (nb->mat == ENG_MAT_SOIL || nb->mat == ENG_MAT_MUD) {
                            nb->moisture = fminf(1.0f, nb->moisture + 1.2f * dt);
                        }
                    }

                    /* Ash leaches mineral nutrients into adjacent soil/mud */
                    if (c->mat == ENG_MAT_ASH && (nb->mat == ENG_MAT_SOIL || nb->mat == ENG_MAT_MUD)) {
                        nb->nutrients = fminf(1.0f, nb->nutrients + 0.8f * dt);
                    }

                    /* Acid corrosion of metals, stone, wood, and flesh */
                    if (c->mat == ENG_MAT_ACID &&
                        (nb->mat == ENG_MAT_IRON || nb->mat == ENG_MAT_COPPER ||
                         nb->mat == ENG_MAT_STONE || nb->mat == ENG_MAT_WOOD || nb->mat == ENG_MAT_FLESH)) {
                        float rate = (nb->mat == ENG_MAT_STONE) ? 0.25f : 0.75f;
                        nb->integrity -= mc->corrosiveness * rate * dt;
                        c->temp_c += 18.0f * dt;
                        if (nb->integrity <= 0.0f) {
                            init_cell_for_material(s, nb, ENG_MAT_SMOKE);
                            nb->temp_c = c->temp_c;
                            c->integrity -= 0.35f;
                            if (c->integrity <= 0.0f) init_cell_for_material(s, c, ENG_MAT_AIR);
                        }
                    }
                }

                /* Wet iron oxidizes into brittle rust in presence of O2 */
                if (c->mat == ENG_MAT_IRON && (c->wetness > 0.3f || touches_water) && avail_o2 > 0.05f) {
                    c->integrity -= (touches_salt ? 0.30f : 0.10f) * dt;
                    if (c->integrity <= 0.0f) {
                        init_cell_for_material(s, c, ENG_MAT_RUST);
                    }
                }

                /* Evaporation of surface wetness */
                if (c->temp_c > 35.0f && c->wetness > 0.0f && mc->phase == ENG_PHASE_SOLID) {
                    c->wetness = fmaxf(0.0f, c->wetness - (c->temp_c - 30.0f) * 0.01f * dt);
                }
                if (c->mat == ENG_MAT_SOIL && c->temp_c > 40.0f) {
                    c->moisture = fmaxf(0.0f, c->moisture - 0.05f * dt);
                }

                /* 3. Ignition, Oxygen-Limited Combustion, Charring & Deflagration Blasts */
                mc = &s->mats[c->mat];
                if (!c->burning && mc->ignite_temp_c < 5000.0f && c->fuel > 0.01f &&
                    c->temp_c >= mc->ignite_temp_c && c->wetness < 0.5f && avail_o2 >= 0.05f) {
                    if (mc->explosive) {
                        float rad = 4.5f * s->cell_size;
                        push_blast(s, x, y, z, rad, 45.0f);
                        for (int dy = -1; dy <= 1; dy++) {
                            for (int dz = -1; dz <= 1; dz++) {
                                for (int dx = -1; dx <= 1; dx++) {
                                    if (!in_bounds(s, x + dx, y + dy, z + dz)) continue;
                                    eng_sim_cell_t *eb = &s->cells[cell_idx(s, x + dx, y + dy, z + dz)];
                                    eb->temp_c = fmaxf(eb->temp_c, 650.0f);
                                }
                            }
                        }
                        init_cell_for_material(s, c, mc->burn_into);
                        c->temp_c = 900.0f;
                        continue;
                    }
                    c->burning = true;
                }

                if (c->burning) {
                    /* Oil floating on water burns above water! Only quench non-floating fuels or submerged cells */
                    bool submerged_quench = (y + 1 < s->gy) &&
                        (s->cells[cell_idx(s, x, y + 1, z)].mat == ENG_MAT_WATER ||
                         s->cells[cell_idx(s, x, y + 1, z)].mat == ENG_MAT_SALT_WATER);
                    bool side_water_quench = touches_water && (c->mat != ENG_MAT_OIL && c->mat != ENG_MAT_ETHANOL);
                    if (submerged_quench || side_water_quench || c->wetness > 0.7f || avail_o2 < 0.05f) {
                        c->burning = false;
                    } else {
                        c->temp_c = fminf(c->temp_c + mc->fuel_energy * dt, 1050.0f);
                        c->wetness = 0.0f;
                        float burn_rate = (c->mat == ENG_MAT_FOLIAGE || c->mat == ENG_MAT_ETHANOL) ? 0.35f : 0.16f;
                        c->fuel -= burn_rate * dt;

                        /* Consume O2 from self & adjacent gas cells + radiate heat */
                        if (mc->phase == ENG_PHASE_GAS) c->o2 = fmaxf(0.0f, c->o2 - 0.12f * dt);
                        for (int d = 0; d < 6; d++) {
                            int nx = x + d6[d][0], ny = y + d6[d][1], nz = z + d6[d][2];
                            if (!in_bounds(s, nx, ny, nz)) continue;
                            eng_sim_cell_t *nb = &s->cells[cell_idx(s, nx, ny, nz)];
                            if (s->mats[nb->mat].phase == ENG_PHASE_GAS) {
                                nb->o2 = fmaxf(0.0f, nb->o2 - 0.07f * dt);
                            }
                            nb->temp_c = fminf(nb->temp_c + mc->fuel_energy * 0.28f * dt, 1000.0f);
                        }

                        if (y + 1 < s->gy && s->cells[cell_idx(s, x, y + 1, z)].mat == ENG_MAT_AIR &&
                            eng_rng_float01(&s->rng) < 0.45f * dt) {
                            eng_sim_cell_t *ab = &s->cells[cell_idx(s, x, y + 1, z)];
                            ab->mat = ENG_MAT_SMOKE;
                            ab->temp_c = fmaxf(ab->temp_c, 180.0f);
                        }

                        if (c->mat == ENG_MAT_WOOD && c->fuel < 0.35f) {
                            c->mat = ENG_MAT_CHARCOAL;
                        }
                        if (c->fuel <= 0.0f) {
                            float hot = c->temp_c;
                            init_cell_for_material(s, c, mc->burn_into);
                            c->temp_c = hot * 0.6f;
                        }
                    }
                } else {
                    /* Non-burning phase transitions (melt, boil, freeze/condense) */
                    mc = &s->mats[c->mat];
                    if (c->temp_c > mc->melt_temp_c && mc->melt_into != c->mat) {
                        float t_keep = c->temp_c;
                        init_cell_for_material(s, c, mc->melt_into);
                        c->temp_c = t_keep;
                    } else if (c->temp_c > mc->boil_temp_c && mc->boil_into != c->mat) {
                        float t_keep = c->temp_c;
                        init_cell_for_material(s, c, mc->boil_into);
                        c->temp_c = t_keep;
                    } else if (c->temp_c < mc->freeze_temp_c && mc->freeze_into != c->mat) {
                        float t_keep = c->temp_c;
                        init_cell_for_material(s, c, mc->freeze_into);
                        c->temp_c = t_keep;
                    }
                }

                /* Mild relaxation toward ambient temperature at exposed air */
                c->temp_c = eng_lerpf(c->temp_c, s->ambient_c, eng_clampf(0.03f * dt, 0.0f, 1.0f));
            }
        }
    }

    /* 4. Electrical potential relaxation & resistive Joule heating */
    for (size_t i = 0; i < total; i++) {
        eng_sim_cell_t *c = &s->cells[i];
        if (c->voltage_src > 0.0f) c->voltage = c->voltage_src;
        else if (cell_elec_cond(s, c) < 0.05f) c->voltage = 0.0f;
        else c->voltage *= 0.5f;
    }
    for (int sweep = 0; sweep < 8; sweep++) {
        for (int y = 0; y < s->gy; y++) {
            for (int z = 0; z < s->gz; z++) {
                for (int x = 0; x < s->gx; x++) {
                    eng_sim_cell_t *c = &s->cells[cell_idx(s, x, y, z)];
                    if (c->voltage_src > 0.0f) { c->voltage = c->voltage_src; continue; }
                    float sig = cell_elec_cond(s, c);
                    if (sig < 0.05f) { c->voltage = 0.0f; continue; }
                    float best_v = 0.0f;
                    for (int d = 0; d < 6; d++) {
                        int nx = x + d6[d][0], ny = y + d6[d][1], nz = z + d6[d][2];
                        if (!in_bounds(s, nx, ny, nz)) continue;
                        const eng_sim_cell_t *nb = &s->cells[cell_idx(s, nx, ny, nz)];
                        if (cell_elec_cond(s, nb) >= 0.05f || nb->voltage_src > 0.0f) {
                            float cand = nb->voltage * (0.98f - 0.14f * (1.0f - sig));
                            if (cand > best_v) best_v = cand;
                        }
                    }
                    c->voltage = best_v;
                }
            }
        }
    }
    for (int y = 0; y < s->gy; y++) {
        for (int z = 0; z < s->gz; z++) {
            for (int x = 0; x < s->gx; x++) {
                eng_sim_cell_t *c = &s->cells[cell_idx(s, x, y, z)];
                if (c->voltage > 8.0f) {
                    float sig = cell_elec_cond(s, c);
                    c->temp_c += (1.15f - sig) * c->voltage * 1.4f * dt;
                    /* Electrical spark into adjacent volatile oil / ethanol / methane / gunpowder */
                    for (int d = 0; d < 6; d++) {
                        int nx = x + d6[d][0], ny = y + d6[d][1], nz = z + d6[d][2];
                        if (!in_bounds(s, nx, ny, nz)) continue;
                        eng_sim_cell_t *nb = &s->cells[cell_idx(s, nx, ny, nz)];
                        if (nb->mat == ENG_MAT_OIL || nb->mat == ENG_MAT_ETHANOL ||
                            nb->mat == ENG_MAT_METHANE || nb->mat == ENG_MAT_GUNPOWDER) {
                            nb->temp_c = fmaxf(nb->temp_c, s->mats[nb->mat].ignite_temp_c + 25.0f);
                        }
                    }
                }
            }
        }
    }

    /* 5. Organism scent deposition + Semi-Lagrangian wind-advected scent plume */
    for (uint32_t i = 0; i < s->agent_high; i++) {
        const eng_bio_body_t *ag = &s->agents[i];
        if (!ag->active || ag->health <= 0.0f || ag->scent_strength <= 0.0f) continue;
        int gx, gy, gz;
        if (eng_sim_world_to_grid(s, ag->pos, &gx, &gy, &gz)) {
            eng_sim_cell_t *c = &s->cells[cell_idx(s, gx, gy, gz)];
            c->scent = fminf(1.0f, c->scent + ag->scent_strength * dt);
        }
    }

    float inv_cs = 1.0f / s->cell_size;
    float decay = expf(-0.28f * dt);
    for (int y = 0; y < s->gy; y++) {
        for (int z = 0; z < s->gz; z++) {
            for (int x = 0; x < s->gx; x++) {
                int idx = cell_idx(s, x, y, z);
                if (s->mats[s->cells[idx].mat].phase == ENG_PHASE_SOLID) {
                    s->scent_scratch[idx] = 0.0f;
                    continue;
                }
                float ux = (float)x - s->wind.x * dt * inv_cs;
                float uy = (float)y - s->wind.y * dt * inv_cs;
                float uz = (float)z - s->wind.z * dt * inv_cs;
                float adv = sample_scent_grid_trilinear(s, ux, uy, uz);
                float nb_sum = 0.0f;
                for (int d = 0; d < 6; d++) {
                    int nx = x + d6[d][0], ny = y + d6[d][1], nz = z + d6[d][2];
                    if (in_bounds(s, nx, ny, nz)) nb_sum += s->cells[cell_idx(s, nx, ny, nz)].scent;
                }
                s->scent_scratch[idx] = (0.90f * adv + 0.10f * (nb_sum / 6.0f)) * decay;
            }
        }
    }
    for (size_t i = 0; i < total; i++) s->cells[i].scent = s->scent_scratch[i];

    /* 6. Soil-Sunlight Flora Growth */
    for (uint32_t i = 0; i < s->plant_high; i++) {
        eng_plant_t *pl = &s->plants[i];
        if (!pl->active || pl->stage == ENG_PLANT_DEAD) continue;
        eng_sim_cell_t *soil = &s->cells[cell_idx(s, pl->gx, pl->gy, pl->gz)];

        if (soil->burning || soil->temp_c > 160.0f || soil->mat == ENG_MAT_ACID || soil->mat == ENG_MAT_LAVA) {
            pl->health = 0.0f;
            pl->stage = ENG_PLANT_DEAD;
            if (pl->gy + 1 < s->gy && s->cells[cell_idx(s, pl->gx, pl->gy + 1, pl->gz)].mat == ENG_MAT_AIR) {
                eng_sim_set_cell(s, pl->gx, pl->gy + 1, pl->gz, ENG_MAT_FOLIAGE);
                eng_sim_ignite(s, pl->gx, pl->gy + 1, pl->gz);
            }
            continue;
        }

        /* Raymarch toward sun from cell above root to measure shadow/roof occlusion */
        float sun = (s->sun_dir.y > 0.02f) ? 1.0f : 0.05f;
        if (sun > 0.1f) {
            float rx = (float)pl->gx + 0.5f, ry = (float)pl->gy + 1.5f, rz = (float)pl->gz + 0.5f;
            for (int st = 0; st < 32; st++) {
                rx += s->sun_dir.x * 0.8f;
                ry += s->sun_dir.y * 0.8f;
                rz += s->sun_dir.z * 0.8f;
                int ix = (int)floorf(rx), iy = (int)floorf(ry), iz = (int)floorf(rz);
                if (!in_bounds(s, ix, iy, iz)) break;
                uint8_t rm = s->cells[cell_idx(s, ix, iy, iz)].mat;
                if (rm == ENG_MAT_SMOKE) sun *= 0.7f;
                else if (s->mats[rm].phase == ENG_PHASE_SOLID && rm != ENG_MAT_GLASS && rm != ENG_MAT_FOLIAGE) {
                    sun = 0.04f;
                    break;
                }
            }
        }
        pl->sun_exposure = sun;

        bool fertile_substrate = (soil->mat == ENG_MAT_SOIL || soil->mat == ENG_MAT_MUD);
        if (soil->temp_c < -2.0f || soil->temp_c > 48.0f) {
            pl->health = fmaxf(0.0f, pl->health - 0.12f * dt);
            if (pl->health <= 0.0f) pl->stage = ENG_PLANT_DEAD;
        } else if (fertile_substrate && soil->moisture > 0.12f && sun > 0.2f && soil->temp_c >= 5.0f) {
            float rate = 0.14f * sun * (0.25f + 0.75f * soil->moisture) * (0.30f + 1.40f * soil->nutrients);
            pl->growth = eng_clampf(pl->growth + rate * dt, 0.0f, 1.0f);
            soil->moisture = fmaxf(0.0f, soil->moisture - 0.015f * rate * dt);
            if (pl->growth >= 0.85f) pl->stage = ENG_PLANT_SEEDING;
            else if (pl->growth >= 0.50f) pl->stage = ENG_PLANT_MATURE;
            else if (pl->growth >= 0.20f) pl->stage = ENG_PLANT_SPROUT;
            else pl->stage = ENG_PLANT_SEED;
        }
    }

    /* 7. Organism Homeostasis (Thermoregulation, O2/Drowning/Smoke, Shock, Acid, Metabolism) */
    for (uint32_t i = 0; i < s->agent_high; i++) {
        eng_bio_body_t *ag = &s->agents[i];
        if (!ag->active || ag->health <= 0.0f) continue;

        int bx, by, bz, hx, hy, hz;
        bool body_in = eng_sim_world_to_grid(s, ag->pos, &bx, &by, &bz);
        bool head_in = eng_sim_world_to_grid(s, eng_v3(ag->pos.x, ag->pos.y + ag->head_offset_y, ag->pos.z), &hx, &hy, &hz);

        float env_temp = s->ambient_c;
        bool in_water = false;
        if (body_in) {
            const eng_sim_cell_t *bc = &s->cells[cell_idx(s, bx, by, bz)];
            env_temp = bc->temp_c;
            if (bc->mat == ENG_MAT_WATER || bc->mat == ENG_MAT_SALT_WATER) {
                in_water = true;
                ag->wetness = 1.0f;
                ag->hydration = fminf(1.0f, ag->hydration + (bc->mat == ENG_MAT_WATER ? 0.3f : 0.0f) * dt);
            } else {
                ag->wetness = fmaxf(0.0f, ag->wetness - 0.08f * dt);
            }
            if (bc->voltage > 8.0f && (cell_elec_cond(s, bc) >= 0.05f || ag->wetness > 0.3f)) {
                ag->health = fmaxf(0.0f, ag->health - bc->voltage * 0.018f * dt);
            }
            if (bc->mat == ENG_MAT_ACID) {
                ag->health = fmaxf(0.0f, ag->health - 0.45f * dt);
            }
            if (bc->burning || bc->temp_c > 75.0f) {
                ag->health = fmaxf(0.0f, ag->health - (bc->temp_c - 65.0f) * 0.006f * dt);
            }
        }

        /* Conductive heat loss/gain vs homeotherm metabolic regulation toward 37.0 C */
        float k_env = in_water ? 0.42f : (0.04f + 0.12f * ag->wetness);
        ag->core_temp_c += (env_temp - ag->core_temp_c) * k_env * dt;
        ag->core_temp_c += (37.0f - ag->core_temp_c) * (0.14f * ag->energy) * dt;
        if (ag->core_temp_c < 33.5f) {
            ag->health = fmaxf(0.0f, ag->health - (33.5f - ag->core_temp_c) * 0.04f * dt);
        } else if (ag->core_temp_c > 41.2f) {
            ag->health = fmaxf(0.0f, ag->health - (ag->core_temp_c - 41.2f) * 0.06f * dt);
        }

        /* Respiration (air-breathing vs aquatic) */
        bool can_breathe = !ag->aquatic;
        if (head_in) {
            const eng_sim_cell_t *hc = &s->cells[cell_idx(s, hx, hy, hz)];
            if (ag->aquatic) {
                can_breathe = (hc->mat == ENG_MAT_WATER || hc->mat == ENG_MAT_SALT_WATER);
            } else {
                can_breathe = (s->mats[hc->mat].phase == ENG_PHASE_GAS &&
                               hc->mat != ENG_MAT_SMOKE && hc->o2 >= 0.08f);
            }
        }
        if (can_breathe) {
            ag->o2_level = fminf(1.0f, ag->o2_level + 0.45f * dt);
        } else {
            ag->o2_level = fmaxf(0.0f, ag->o2_level - 0.30f * dt);
            if (ag->o2_level <= 0.01f) ag->health = fmaxf(0.0f, ag->health - 0.25f * dt);
        }

        ag->hydration = fmaxf(0.0f, ag->hydration - 0.008f * dt);
        ag->energy = fmaxf(0.0f, ag->energy - 0.006f * dt);
    }
}

bool eng_sim_pop_blast(eng_sim_t *sim, eng_sim_blast_t *out_blast) {
    if (!sim || sim->blast_count == 0) return false;
    if (out_blast) *out_blast = sim->blasts[--sim->blast_count];
    else sim->blast_count--;
    return true;
}

void eng_sim_export_voxels(const eng_sim_t *sim, eng_voxel_chunk_t *out_chunk, bool include_liquids) {
    if (!sim || !out_chunk) return;
    int sx = sim->gx <= ENG_VOXEL_MAX_DIM ? sim->gx : ENG_VOXEL_MAX_DIM;
    int sy = sim->gy <= ENG_VOXEL_MAX_DIM ? sim->gy : ENG_VOXEL_MAX_DIM;
    int sz = sim->gz <= ENG_VOXEL_MAX_DIM ? sim->gz : ENG_VOXEL_MAX_DIM;
    eng_voxel_chunk_init(out_chunk, sx, sy, sz, sim->cell_size);
    for (int m = 1; m < sim->mat_count && m < 255; m++) {
        const eng_mat_def_t *md = &sim->mats[m];
        uint8_t r = (uint8_t)eng_clampf(powf(md->color_rgb[0], 1.0f / 2.2f) * 255.0f, 0.0f, 255.0f);
        uint8_t g = (uint8_t)eng_clampf(powf(md->color_rgb[1], 1.0f / 2.2f) * 255.0f, 0.0f, 255.0f);
        uint8_t b = (uint8_t)eng_clampf(powf(md->color_rgb[2], 1.0f / 2.2f) * 255.0f, 0.0f, 255.0f);
        eng_voxel_set_palette_color(out_chunk, (uint8_t)m, r, g, b, 255);
    }
    /* Palette slot 255 reserved for glowing burning cells */
    eng_voxel_set_palette_color(out_chunk, 255, 255, 165, 42, 255);

    for (int y = 0; y < sy; y++) {
        for (int z = 0; z < sz; z++) {
            for (int x = 0; x < sx; x++) {
                const eng_sim_cell_t *c = &sim->cells[cell_idx(sim, x, y, z)];
                eng_mat_phase_t ph = sim->mats[c->mat].phase;
                if (ph == ENG_PHASE_GAS) continue;
                if (ph == ENG_PHASE_LIQUID && !include_liquids) continue;
                eng_voxel_set(out_chunk, x, y, z, c->burning ? 255u : c->mat);
            }
        }
    }
}

size_t eng_sim_active_fire_count(const eng_sim_t *sim, eng_vec3_t *out_avg_pos) {
    if (!sim) return 0;
    size_t cnt = 0;
    eng_vec3_t sum = {0, 0, 0};
    for (int y = 0; y < sim->gy; y++) {
        for (int z = 0; z < sim->gz; z++) {
            for (int x = 0; x < sim->gx; x++) {
                if (sim->cells[cell_idx(sim, x, y, z)].burning) {
                    sum = eng_v3_add(sum, eng_sim_grid_to_world(sim, x, y, z));
                    cnt++;
                }
            }
        }
    }
    if (out_avg_pos) {
        *out_avg_pos = cnt > 0 ? eng_v3_scale(sum, 1.0f / (float)cnt) : eng_v3(0, 0, 0);
    }
    return cnt;
}
