#ifndef ENG_SIM_H
#define ENG_SIM_H

#include "eng_ecs.h"
#include "eng_math.h"
#include "eng_voxel.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_SIM_MAX_MATERIALS 64
#define ENG_SIM_MAX_PLANTS    256
#define ENG_SIM_MAX_AGENTS    128
#define ENG_SIM_MAX_BLASTS    32

typedef enum {
    ENG_MAT_AIR = 0,
    ENG_MAT_WATER = 1,
    ENG_MAT_SALT_WATER = 2,
    ENG_MAT_ICE = 3,
    ENG_MAT_STEAM = 4,
    ENG_MAT_OIL = 5,
    ENG_MAT_ETHANOL = 6,
    ENG_MAT_LAVA = 7,
    ENG_MAT_WOOD = 8,
    ENG_MAT_CHARCOAL = 9,
    ENG_MAT_ASH = 10,
    ENG_MAT_FOLIAGE = 11,
    ENG_MAT_GUNPOWDER = 12,
    ENG_MAT_STONE = 13,
    ENG_MAT_OBSIDIAN = 14,
    ENG_MAT_SAND = 15,
    ENG_MAT_GLASS = 16,
    ENG_MAT_SOIL = 17,
    ENG_MAT_MUD = 18,
    ENG_MAT_IRON = 19,
    ENG_MAT_COPPER = 20,
    ENG_MAT_RUST = 21,
    ENG_MAT_ACID = 22,
    ENG_MAT_SMOKE = 23,
    ENG_MAT_METHANE = 24,
    ENG_MAT_FLESH = 25,
    ENG_MAT_BUILTIN_COUNT = 26
} eng_mat_id_t;

typedef enum {
    ENG_PHASE_GAS = 0,
    ENG_PHASE_LIQUID = 1,
    ENG_PHASE_GRANULAR = 2,
    ENG_PHASE_SOLID = 3
} eng_mat_phase_t;

typedef struct {
    char name[24];
    eng_mat_phase_t phase;
    float density;        /* kg/m^3 */
    float thermal_cond;   /* 0..1 */
    float heat_capacity;  /* >= 0.1 relative heat capacity */
    float melt_temp_c;    /* < 9000 if melts */
    uint8_t melt_into;
    float boil_temp_c;    /* < 9000 if boils */
    uint8_t boil_into;
    float freeze_temp_c;  /* > -900 if freezes or condenses */
    uint8_t freeze_into;
    float ignite_temp_c;  /* < 9000 if flammable */
    float fuel_energy;    /* exothermic heat output (C/s) */
    uint8_t burn_into;    /* residue material after fuel depletes */
    bool explosive;       /* detonates with pressure blast on ignition */
    float elec_cond;      /* 0..1 electrical conductivity */
    float corrosiveness;  /* 0..1 acid dissolution rate */
    float color_rgb[3];   /* linear RGB */
} eng_mat_def_t;

typedef struct {
    uint8_t mat;
    bool burning;
    float temp_c;
    float fuel;
    float wetness;
    float voltage;
    float voltage_src;
    float o2;
    float moisture;
    float nutrients;
    float scent;
    float integrity;
} eng_sim_cell_t;

typedef enum {
    ENG_PLANT_SEED = 0,
    ENG_PLANT_SPROUT = 1,
    ENG_PLANT_MATURE = 2,
    ENG_PLANT_SEEDING = 3,
    ENG_PLANT_DEAD = 4
} eng_plant_stage_t;

typedef struct {
    bool active;
    eng_entity_t entity;
    int gx, gy, gz;
    eng_plant_stage_t stage;
    float growth;       /* 0..1 */
    float health;       /* 0..1 */
    float sun_exposure; /* 0..1 */
} eng_plant_t;

typedef struct {
    bool active;
    eng_entity_t entity;
    eng_vec3_t pos;
    float head_offset_y;
    bool aquatic;
    float core_temp_c;    /* 37.0 C mammal homeotherm target */
    float wetness;        /* 0..1 */
    float o2_level;       /* 0..1 */
    float hydration;      /* 0..1 */
    float energy;         /* 0..1 */
    float health;         /* 0..1 */
    float scent_strength; /* >= 0 olfactory emission rate */
} eng_bio_body_t;

typedef struct {
    eng_vec3_t pos;
    float radius;
    float impulse;
} eng_sim_blast_t;

typedef struct eng_sim_s eng_sim_t;

eng_sim_t *eng_sim_create(int gx, int gy, int gz, float cell_size, eng_vec3_t origin, uint64_t seed);
void eng_sim_destroy(eng_sim_t *sim);

void eng_sim_get_dims(const eng_sim_t *sim, int *out_gx, int *out_gy, int *out_gz, float *out_cell_size, eng_vec3_t *out_origin);
bool eng_sim_world_to_grid(const eng_sim_t *sim, eng_vec3_t world_pos, int *out_x, int *out_y, int *out_z);
eng_vec3_t eng_sim_grid_to_world(const eng_sim_t *sim, int x, int y, int z);

/* Material registry */
int eng_sim_register_material(eng_sim_t *sim, const eng_mat_def_t *def);
int eng_sim_find_material(const eng_sim_t *sim, const char *name);
const eng_mat_def_t *eng_sim_get_material(const eng_sim_t *sim, uint8_t mat_id);

/* Cell state access & environmental drivers */
bool eng_sim_set_cell(eng_sim_t *sim, int x, int y, int z, uint8_t mat_id);
const eng_sim_cell_t *eng_sim_get_cell(const eng_sim_t *sim, int x, int y, int z);
eng_sim_cell_t *eng_sim_cell_mut(eng_sim_t *sim, int x, int y, int z);

void eng_sim_fill_box(eng_sim_t *sim, int x0, int y0, int z0, int x1, int y1, int z1, uint8_t mat_id);
bool eng_sim_set_temperature(eng_sim_t *sim, int x, int y, int z, float temp_c);
bool eng_sim_ignite(eng_sim_t *sim, int x, int y, int z);
bool eng_sim_set_voltage_source(eng_sim_t *sim, int x, int y, int z, float volts);

void eng_sim_set_ambient_temp(eng_sim_t *sim, float ambient_c);
void eng_sim_set_wind(eng_sim_t *sim, eng_vec3_t wind_vel);
void eng_sim_set_sun_dir(eng_sim_t *sim, eng_vec3_t dir_to_light);
void eng_sim_apply_rain(eng_sim_t *sim, float intensity, float dt);

/* Flora & Organism Homeostasis */
uint32_t eng_sim_add_plant(eng_sim_t *sim, int soil_x, int soil_y, int soil_z, eng_entity_t entity);
const eng_plant_t *eng_sim_get_plant(const eng_sim_t *sim, uint32_t plant_id);

uint32_t eng_sim_add_bio(eng_sim_t *sim, eng_vec3_t pos, bool aquatic, float scent_strength, eng_entity_t entity);
eng_bio_body_t *eng_sim_get_bio(eng_sim_t *sim, uint32_t bio_id);
void eng_sim_apply_bio_trauma(eng_sim_t *sim, uint32_t bio_id, float kinetic_dmg, float thermal_dmg, float chem_dmg);

/* Physical senses */
float eng_sim_sample_scent(const eng_sim_t *sim, eng_vec3_t world_pos);
float eng_sim_check_visibility(const eng_sim_t *sim, eng_vec3_t from, eng_vec3_t to,
                               float ambient_light, float fog_density);

/* Step simulation & export to renderable voxel chunk / pop deflagration blasts */
void eng_sim_step(eng_sim_t *sim, float dt);
bool eng_sim_pop_blast(eng_sim_t *sim, eng_sim_blast_t *out_blast);
void eng_sim_export_voxels(const eng_sim_t *sim, eng_voxel_chunk_t *out_chunk, bool include_liquids);
size_t eng_sim_active_fire_count(const eng_sim_t *sim, eng_vec3_t *out_avg_pos);

#ifdef __cplusplus
}
#endif

#endif /* ENG_SIM_H */
