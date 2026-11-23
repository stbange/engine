#ifndef ENG_PROCGEN_H
#define ENG_PROCGEN_H

#include "eng_asset.h"
#include "eng_math.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------------------
 * 1. Deterministic 2D/3D Noise (Value, Perlin, Simplex, Voronoi, fBm, Ridged, Warp)
 * -------------------------------------------------------------------------- */
float eng_noise_value2d(float x, float y, uint64_t seed);
float eng_noise_value3d(float x, float y, float z, uint64_t seed);
float eng_noise_perlin2d(float x, float y, uint64_t seed);
float eng_noise_perlin3d(float x, float y, float z, uint64_t seed);
float eng_noise_simplex2d(float x, float y, uint64_t seed);
float eng_noise_voronoi2d(float x, float y, uint64_t seed, uint32_t *out_cell_id);

float eng_noise_fbm3d(float x, float y, float z, uint64_t seed, int octaves, float lacunarity, float gain);
float eng_noise_ridged3d(float x, float y, float z, uint64_t seed, int octaves);
float eng_noise_domain_warp3d(float x, float y, float z, uint64_t seed, float warp_amp);

/* --------------------------------------------------------------------------
 * 2. Procedural Tileable PBR/Retro Texture Synthesis
 * -------------------------------------------------------------------------- */
/* Supported recipes: "stone_brick", "cobble", "wood_planks", "grass",
 * "rust_metal", "sci_fi_panel", "water_caustics", "marble".
 * out_normal_rgba and out_roughness_r are optional (may be NULL). */
bool eng_procgen_texture(const char *recipe, uint64_t seed, int size,
                         uint8_t *out_albedo_rgba,
                         uint8_t *out_normal_rgba,
                         uint8_t *out_roughness_r);

/* --------------------------------------------------------------------------
 * 3. Solvability-Guaranteed Dungeons, Cellular Caves & Tiled WFC
 * -------------------------------------------------------------------------- */
typedef enum {
    ENG_TILE_WALL = 0,
    ENG_TILE_FLOOR = 1,
    ENG_TILE_DOOR = 2,
    ENG_TILE_ENTRANCE = 3,
    ENG_TILE_EXIT = 4,
    ENG_TILE_KEY = 5,
    ENG_TILE_LOCKED_DOOR = 6
} eng_tile_type_t;

typedef struct {
    int x, y, w, h;
} eng_room_rect_t;

typedef struct {
    int width;
    int height;
    uint8_t *cells; /* width * height eng_tile_type_t */
    int entrance_x, entrance_y;
    int exit_x, exit_y;
    int key_x, key_y;
    int lock_x, lock_y;
    bool has_key_lock;
    eng_room_rect_t rooms[32];
    size_t room_count;
} eng_dungeon_t;

void eng_dungeon_free(eng_dungeon_t *d);
uint8_t eng_dungeon_get(const eng_dungeon_t *d, int x, int y);

bool eng_procgen_dungeon_bsp(eng_dungeon_t *out, int w, int h, uint64_t seed);
bool eng_procgen_cave_cellular(eng_dungeon_t *out, int w, int h, uint64_t seed);
bool eng_procgen_wfc_grid(eng_dungeon_t *out, int w, int h, uint64_t seed);

/* Verify via two-stage BFS that entrance -> key (without crossing lock) and key -> exit are 100% reachable. */
bool eng_procgen_dungeon_is_solvable(const eng_dungeon_t *d);

/* Build 3D floor + wall + doorway geometry from dungeon grid. */
bool eng_procgen_dungeon_build_mesh(const eng_dungeon_t *d, float tile_size, float wall_h, eng_mesh_data_t *out_mesh);

/* --------------------------------------------------------------------------
 * 4. Seamless 3D Cube-Sphere Planets (Whittaker Biomes + Radial Gravity)
 * -------------------------------------------------------------------------- */
typedef struct {
    uint64_t seed;
    float radius;
    int subdivisions; /* per cube face, e.g. 16..48 */
    float continent_amp;
    float sea_level;  /* elevation offset relative to radius (default 0.0) */
    int crater_count;
} eng_planet_cfg_t;

eng_planet_cfg_t eng_planet_default_cfg(uint64_t seed, float radius);
float eng_planet_sample_radius(const eng_planet_cfg_t *cfg, eng_vec3_t unit_dir);
eng_vec3_t eng_planet_gravity_up(eng_vec3_t planet_center, eng_vec3_t world_pos);
bool eng_procgen_planet_mesh(const eng_planet_cfg_t *cfg, eng_mesh_data_t *out_mesh);

/* --------------------------------------------------------------------------
 * 5. 3D L-System Flora & Overlap-Free 2D / Spherical Poisson Scatter
 * -------------------------------------------------------------------------- */
bool eng_procgen_tree_mesh(uint64_t seed, int depth, float trunk_height, float trunk_radius, eng_mesh_data_t *out_mesh);

size_t eng_procgen_poisson_2d(uint64_t seed, float width, float height, float min_dist,
                              eng_vec2_t *out_pts, size_t max_pts);

size_t eng_procgen_poisson_sphere(uint64_t seed, float radius, float min_chord_dist,
                                  eng_vec3_t *out_pts, size_t max_pts);

/* --------------------------------------------------------------------------
 * 6. DNA-Driven Articulated Animals & Modular People / NPCs (Auto-Rigged + Gait IK)
 * -------------------------------------------------------------------------- */
#include "eng_anim.h"

typedef enum {
    ENG_ANIMAL_QUADRUPED = 0,
    ENG_ANIMAL_BIPED,
    ENG_ANIMAL_AVIAN,
    ENG_ANIMAL_INSECTOID,
    ENG_ANIMAL_AQUATIC,
    ENG_ANIMAL_SERPENTINE
} eng_animal_archetype_t;

typedef struct {
    eng_mesh_data_t mesh;
    uint8_t coat_rgba[64 * 64 * 4];
    eng_skeleton_t skeleton;
    eng_gait_cfg_t gait;
    float height;
    float length;
} eng_animal_asset_t;

typedef struct {
    char name[32];
    char role[24];
    float height;
    eng_mesh_data_t mesh;
    eng_skeleton_t skeleton;
    eng_gait_cfg_t gait;
} eng_person_asset_t;

bool eng_procgen_animal(uint64_t seed, eng_animal_archetype_t archetype, eng_animal_asset_t *out);
void eng_animal_asset_free(eng_animal_asset_t *a);

bool eng_procgen_person(uint64_t seed, eng_person_asset_t *out);
void eng_person_asset_free(eng_person_asset_t *p);

#ifdef __cplusplus
}
#endif

#endif /* ENG_PROCGEN_H */
