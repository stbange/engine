#ifndef ENG_VOXEL_H
#define ENG_VOXEL_H

#include "eng_asset.h"
#include "eng_math.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_VOXEL_MAX_DIM 32

typedef enum {
    ENG_CSG_UNION = 0,
    ENG_CSG_SUBTRACT,
    ENG_CSG_INTERSECT
} eng_csg_op_t;

typedef struct {
    int sx, sy, sz;
    float voxel_size;
    uint8_t blocks[ENG_VOXEL_MAX_DIM * ENG_VOXEL_MAX_DIM * ENG_VOXEL_MAX_DIM];
    uint32_t palette[256]; /* RGBA8 packed as 0xAABBGGRR or R,G,B,A bytes */
    bool dirty;
} eng_voxel_chunk_t;

typedef struct {
    bool hit;
    int vx, vy, vz;
    int nx, ny, nz;
    float dist;
    uint8_t block_id;
} eng_voxel_hit_t;

void eng_voxel_chunk_init(eng_voxel_chunk_t *chunk, int sx, int sy, int sz, float voxel_size);
void eng_voxel_set_palette_color(eng_voxel_chunk_t *chunk, uint8_t id, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
uint8_t eng_voxel_get(const eng_voxel_chunk_t *chunk, int x, int y, int z);
bool eng_voxel_set(eng_voxel_chunk_t *chunk, int x, int y, int z, uint8_t block_id);

/* LLM-friendly multi-layer ASCII builder ('.' or ' ' = empty, '1'..'9'/'A'..'Z' = palette indices). */
bool eng_voxel_from_ascii(eng_voxel_chunk_t *chunk, const char *const *layers_y_bottom_up, int num_layers);

/* MagicaVoxel .vox binary loader (SIZE + XYZI + RGBA chunks). */
bool eng_voxel_load_vox(eng_voxel_chunk_t *chunk, const void *bytes, size_t byte_len);

/* Exact voxel grid boolean CSG operations */
void eng_voxel_csg_box(eng_voxel_chunk_t *chunk, int x0, int y0, int z0, int x1, int y1, int z1, uint8_t id, eng_csg_op_t op);
void eng_voxel_csg_sphere(eng_voxel_chunk_t *chunk, float cx, float cy, float cz, float radius, uint8_t id, eng_csg_op_t op);

/* 6-face Greedy Mesher with 4-level per-vertex Ambient Occlusion */
bool eng_voxel_build_mesh(eng_voxel_chunk_t *chunk, eng_mesh_data_t *out_mesh);

/* Fast 3D Amanatides-Woo DDA voxel raycast in chunk local space */
eng_voxel_hit_t eng_voxel_raycast(const eng_voxel_chunk_t *chunk, eng_vec3_t local_origin, eng_vec3_t local_dir, float max_dist);

/* Carve ungrounded (y > 0 disconnected) 6-connected voxel components out of src_chunk into compact islands. */
size_t eng_voxel_extract_floating_islands(eng_voxel_chunk_t *src_chunk,
                                          eng_voxel_chunk_t *out_islands,
                                          eng_vec3_t *out_local_origins,
                                          size_t max_islands);

#ifdef __cplusplus
}
#endif

#endif /* ENG_VOXEL_H */
