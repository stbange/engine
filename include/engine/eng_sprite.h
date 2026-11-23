#ifndef ENG_SPRITE_H
#define ENG_SPRITE_H

#include "eng_asset.h"
#include "eng_math.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_SPRITE_BILLBOARD_Y = 0,     /* Cylindrical upright retro sprite (Doom/Duke3D trees/enemies) */
    ENG_SPRITE_BILLBOARD_SPHERICAL, /* Full camera-plane billboard (sparks, flares, pickups) */
    ENG_SPRITE_DIRECTIONAL_8        /* Doom-style 8-angle sprite sheet row/column selection */
} eng_sprite_mode_t;

typedef struct {
    eng_vec3_t pos;
    eng_vec2_t size;
    float facing_yaw_rad;
    eng_vec4_t uv_rect; /* u0, v0, u1, v1 */
    eng_vec4_t tint;
    uint32_t tex_id;
    uint16_t pocket_id;
    eng_sprite_mode_t mode;
} eng_sprite_item_t;

/* Return [0..7] Doom-style 8-way viewing angle index (0 = front, 4 = back). */
int eng_sprite_dir8_index(eng_vec3_t cam_pos, eng_vec3_t sprite_pos, float sprite_yaw_rad);

/* Append camera-oriented quads for all sprites matching active_pocket into out_mesh. */
size_t eng_sprite_build_batch(const eng_sprite_item_t *items, size_t count,
                              uint16_t active_pocket, eng_vec3_t cam_pos, eng_vec3_t cam_right, eng_vec3_t cam_up,
                              eng_mesh_data_t *out_mesh);

#ifdef __cplusplus
}
#endif

#endif /* ENG_SPRITE_H */
