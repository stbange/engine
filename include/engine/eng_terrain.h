#ifndef ENG_TERRAIN_H
#define ENG_TERRAIN_H

#include "eng_asset.h"
#include "eng_math.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int grid_w;
    int grid_d;
    float cell_size;
    float *heights; /* grid_w * grid_d floats */
} eng_terrain_t;

bool eng_terrain_init(eng_terrain_t *t, int grid_w, int grid_d, float cell_size, const float *heights_opt);
void eng_terrain_free(eng_terrain_t *t);

/* Generate deterministic ridged/fBm hills & valleys directly into terrain heights. */
void eng_terrain_generate_hills(eng_terrain_t *t, uint64_t seed, float max_height, float freq);

/* Bilinear world-space height & normal queries (centered at X=0, Z=0 or starting at 0,0 -> [0, (w-1)*cs]). */
float eng_terrain_sample_height(const eng_terrain_t *t, float world_x, float world_z);
eng_vec3_t eng_terrain_sample_normal(const eng_terrain_t *t, float world_x, float world_z);

/* Build chunk mesh [x0..x1, z0..z1] at lod_step (1, 2, 4, 8) with 4-layer height/slope splatting and crack-hiding skirts. */
bool eng_terrain_build_chunk_mesh(const eng_terrain_t *t, int x0, int z0, int x1, int z1,
                                  int lod_step, float skirt_depth, eng_mesh_data_t *out_mesh);

#ifdef __cplusplus
}
#endif

#endif /* ENG_TERRAIN_H */
