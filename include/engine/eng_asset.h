#ifndef ENG_ASSET_H
#define ENG_ASSET_H

#include "eng_gl.h"
#include "eng_math.h"
#include "eng_vfs.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float pos[3];
    float norm[3];
    float uv[2];
    float color[4];
    uint8_t joints[4];
    float weights[4];
} eng_vertex_t;

typedef struct {
    eng_vertex_t *verts;
    size_t vert_count;
    size_t vert_cap;
    uint32_t *indices;
    size_t idx_count;
    size_t idx_cap;
} eng_mesh_data_t;

typedef struct {
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLuint instance_vbo;
    uint32_t lod_index_offsets[4];
    uint32_t lod_index_counts[4]; /* LOD0 (full) .. LOD3 */
    eng_aabb_t local_aabb;
    bool valid;
} eng_gpu_mesh_t;

typedef struct {
    GLuint tex_id;
    int width;
    int height;
    bool nearest;
    bool valid;
    bool is_cubemap;
    uint32_t norm_rough_tex; /* optional 1-based cache ID for packed RGBA8 (Nx, Ny, Nz, Roughness) */
} eng_gpu_tex_t;

typedef struct eng_asset_cache_s eng_asset_cache_t;

/* CPU procedural & compound CSG mesh builder (LLM-friendly text-to-3D primitives) */
void eng_mesh_data_init(eng_mesh_data_t *md);
void eng_mesh_data_free(eng_mesh_data_t *md);
bool eng_mesh_append_transformed(eng_mesh_data_t *dst, const eng_mesh_data_t *src,
                                 const eng_mat4_t *xform, eng_vec4_t color);
bool eng_mesh_append_box(eng_mesh_data_t *md, eng_vec3_t center, eng_vec3_t size, eng_vec4_t color);
bool eng_mesh_append_sphere(eng_mesh_data_t *md, eng_vec3_t center, float radius, int rings, int sectors, eng_vec4_t color);
bool eng_mesh_append_cylinder(eng_mesh_data_t *md, eng_vec3_t base, float r_bottom, float r_top, float height, int slices, eng_vec4_t color);
bool eng_mesh_append_lathe(eng_mesh_data_t *md, const eng_vec2_t *profile_ry, size_t profile_len, int slices, eng_vec4_t color);

/* File-format parsers (OBJ & glTF 2.0 / GLB) */
bool eng_mesh_parse_obj(eng_mesh_data_t *out, const char *obj_text);
bool eng_mesh_parse_gltf(eng_mesh_data_t *out, const void *bytes, size_t byte_len);

/* Ref-counted GPU Asset Cache */
eng_asset_cache_t *eng_asset_cache_create(eng_vfs_t *vfs);
void eng_asset_cache_destroy(eng_asset_cache_t *cache);

uint32_t eng_asset_upload_mesh(eng_asset_cache_t *cache, const char *key, const eng_mesh_data_t *md);
uint32_t eng_asset_upload_mesh_lods(eng_asset_cache_t *cache, const char *key, const eng_mesh_data_t *lods, int lod_count);
bool eng_asset_update_mesh(eng_asset_cache_t *cache, uint32_t mesh_id, const eng_mesh_data_t *md);
uint32_t eng_asset_load_mesh(eng_asset_cache_t *cache, const char *vpath);
const eng_gpu_mesh_t *eng_asset_get_mesh(const eng_asset_cache_t *cache, uint32_t mesh_id);

uint32_t eng_asset_create_texture_rgba(eng_asset_cache_t *cache, const char *key,
                                       int w, int h, const uint8_t *rgba, bool nearest);
uint32_t eng_asset_load_texture(eng_asset_cache_t *cache, const char *vpath, bool nearest);
uint32_t eng_asset_create_cubemap_rgba(eng_asset_cache_t *cache, const char *key, int size,
                                       const uint8_t *const faces_rgba[6], bool nearest);
uint32_t eng_asset_load_cubemap(eng_asset_cache_t *cache, const char *const face_vpaths[6], bool nearest);
void eng_asset_set_texture_pbr(eng_asset_cache_t *cache, uint32_t albedo_tex_id, uint32_t norm_rough_tex_id);
const eng_gpu_tex_t *eng_asset_get_texture(const eng_asset_cache_t *cache, uint32_t tex_id);

/* Save bottom-up OpenGL RGBA8 framebuffer pixels to a top-down PNG file. */
bool eng_asset_write_png(const char *host_path, int w, int h, const uint8_t *gl_rgba_bottom_up);

#ifdef __cplusplus
}
#endif

#endif /* ENG_ASSET_H */
