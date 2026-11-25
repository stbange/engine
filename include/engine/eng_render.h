#ifndef ENG_RENDER_H
#define ENG_RENDER_H

#include "eng_asset.h"
#include "eng_math.h"
#include "eng_portal.h"
#include "eng_scene.h"
#include "eng_shader.h"
#include "eng_sprite.h"
#include "eng_vfs.h"
#include "eng_xr.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_PIPELINE_FORWARD = 0,
    ENG_PIPELINE_DEFERRED = 1
} eng_pipeline_mode_t;

typedef enum {
    ENG_LIGHT_DIR = 0,
    ENG_LIGHT_POINT = 1,
    ENG_LIGHT_SPOT = 2
} eng_light_type_t;

typedef struct {
    eng_light_type_t type;
    uint16_t pocket_id;
    eng_vec3_t pos;
    eng_vec3_t dir;
    eng_vec3_t color; /* linear HDR RGB (intensity multiplied in) */
    float range;
    float spot_cos_inner;
    bool cast_shadow;
} eng_light_t;

typedef struct {
    float vertex_snap_res; /* 0 = disabled; e.g. 160.0 = PS1 clip-space vertex snap */
    bool nearest_textures;
    bool dither_bayer;
    int color_bits;        /* 0 or 8 = 24-bit truecolor; 5 = 15-bit RGB555; 4 = 12-bit */
    float fog_density;
    eng_vec3_t fog_color;
    float crt_scanlines;   /* 0.0 .. 1.0 */
    float bloom_intensity; /* 0.0 .. 2.0 */
    float fog_height;      /* 0 = pure distance fog; >0 = exponential ground-mist height falloff (meters) */
} eng_retro_cfg_t;

typedef struct {
    eng_vec3_t pos;
    eng_quat_t rot;
    float fov_y_deg;
    float z_near;
    float z_far;
    uint16_t pocket_id;
} eng_camera_t;

typedef struct {
    uint32_t mesh_id;
    uint32_t albedo_tex;
    eng_mat4_t world;
    eng_vec4_t tint;
    float metallic;
    float roughness;
    uint16_t pocket_id;
    bool cast_shadow;
    bool occluder;
    const eng_mat4_t *skin_bones; /* optional array of joint matrices */
    uint32_t skin_bone_count;
    eng_vec3_t emissive;   /* linear HDR emissive RGB feeding bloom */
} eng_draw_item_t;

typedef struct {
    uint32_t submitted_items;
    uint32_t culled_pocket;
    uint32_t culled_frustum;
    uint32_t culled_occluded;
    uint32_t draw_batches;
    uint32_t instanced_draws;
    uint32_t portal_views;
    uint32_t lod_counts[4];
} eng_render_stats_t;

typedef struct eng_renderer_s eng_renderer_t;

eng_retro_cfg_t eng_retro_default(void);
eng_retro_cfg_t eng_retro_ps1_preset(void);
eng_camera_t eng_camera_default(void);

eng_renderer_t *eng_renderer_create(eng_vfs_t *vfs, eng_asset_cache_t *assets, int width, int height);
void eng_renderer_destroy(eng_renderer_t *r);
bool eng_renderer_resize(eng_renderer_t *r, int width, int height);

void eng_renderer_set_pipeline(eng_renderer_t *r, eng_pipeline_mode_t mode);
eng_pipeline_mode_t eng_renderer_get_pipeline(const eng_renderer_t *r);

void eng_renderer_set_retro(eng_renderer_t *r, const eng_retro_cfg_t *cfg);
eng_retro_cfg_t eng_renderer_get_retro(const eng_renderer_t *r);

void eng_renderer_set_sky(eng_renderer_t *r, eng_vec3_t zenith, eng_vec3_t horizon, eng_vec3_t ground);
void eng_renderer_set_ambient(eng_renderer_t *r, eng_vec3_t ambient);
void eng_renderer_set_max_portal_depth(eng_renderer_t *r, int max_depth);

void eng_renderer_begin_frame(eng_renderer_t *r);
bool eng_renderer_submit_mesh(eng_renderer_t *r, const eng_draw_item_t *item);
bool eng_renderer_submit_sprites(eng_renderer_t *r, const eng_sprite_item_t *sprites, size_t count);
bool eng_renderer_add_light(eng_renderer_t *r, const eng_light_t *light);

#define ENG_MAX_VIEWPORTS 4

typedef struct {
    eng_camera_t cam;
    float norm_rect[4]; /* normalized {x, y, w, h} in [0..1], bottom-left GL coords */
} eng_viewport_t;

void eng_renderer_render_views(eng_renderer_t *r, const eng_scene_t *scene,
                               const eng_portal_sys_t *portals,
                               const eng_viewport_t *views, int view_count,
                               const eng_xr_t *xr);

void eng_renderer_render_frame(eng_renderer_t *r, const eng_scene_t *scene,
                               const eng_portal_sys_t *portals,
                               const eng_camera_t *cam, const eng_xr_t *xr);

bool eng_renderer_read_pixels(const eng_renderer_t *r, uint8_t *out_rgba_bottom_up, int w, int h);
eng_render_stats_t eng_renderer_stats(const eng_renderer_t *r);
bool eng_renderer_reload_shaders(eng_renderer_t *r);

#ifdef __cplusplus
}
#endif

#endif /* ENG_RENDER_H */
