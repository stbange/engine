#include "engine/eng_render.h"
#include "engine/eng_log.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_LIGHTS 32
#define ENG_SHADOW_RES 1024

typedef struct {
    uint32_t item_idx;
    uint32_t mesh_id;
    uint32_t tex_id;
    uint8_t lod;
    float cam_dist;
} vis_draw_t;

struct eng_renderer_s {
    eng_vfs_t *vfs;
    eng_asset_cache_t *assets;
    int width;
    int height;

    eng_pipeline_mode_t pipeline;
    eng_retro_cfg_t retro;
    eng_vec3_t sky_zenith;
    eng_vec3_t sky_horizon;
    eng_vec3_t sky_ground;
    eng_vec3_t ambient;
    int max_portal_depth;

    eng_shader_t sh_forward;
    eng_shader_t sh_gbuffer;
    eng_shader_t sh_def_light;
    eng_shader_t sh_shadow;
    eng_shader_t sh_skybox;
    eng_shader_t sh_post;

    GLuint fs_vao;
    GLuint fs_vbo;
    GLuint sp_vao;
    GLuint sp_vbo;
    GLuint sp_ebo;
    GLuint sp_inst_vbo;
    uint32_t portal_cap_mesh;
    uint32_t portal_quad_mesh;
    uint32_t soft_particle_tex;

    GLuint hdr_fbo;
    GLuint hdr_color_tex;
    GLuint hdr_ds_tex;
    GLuint bloom_fbo;
    GLuint bloom_tex;
    GLuint gbuf_fbo;
    GLuint gb_albedo_tex;
    GLuint gb_norm_tex;
    GLuint gb_pos_tex;
    GLuint shadow_fbo;
    GLuint shadow_tex;

    eng_draw_item_t *items;
    size_t item_count;
    size_t item_cap;

    eng_sprite_item_t *sprites;
    size_t sprite_count;
    size_t sprite_cap;

    eng_light_t lights[ENG_MAX_LIGHTS];
    size_t light_count;

    eng_mat4_t *inst_scratch;
    size_t inst_cap;

    eng_render_stats_t stats;
};

eng_retro_cfg_t eng_retro_default(void) {
    return (eng_retro_cfg_t){
        .vertex_snap_res = 0.0f,
        .nearest_textures = false,
        .dither_bayer = false,
        .color_bits = 8,
        .fog_density = 0.004f,
        .fog_color = {0.55f, 0.65f, 0.78f},
        .fog_height = 0.0f,
        .crt_scanlines = 0.0f,
        .bloom_intensity = 0.25f
    };
}

eng_retro_cfg_t eng_retro_ps1_preset(void) {
    return (eng_retro_cfg_t){
        .vertex_snap_res = 160.0f,
        .nearest_textures = true,
        .dither_bayer = true,
        .color_bits = 5,
        .fog_density = 0.018f,
        .fog_color = {0.14f, 0.12f, 0.18f},
        .fog_height = 0.0f,
        .crt_scanlines = 0.18f,
        .bloom_intensity = 0.10f
    };
}

eng_camera_t eng_camera_default(void) {
    return (eng_camera_t){
        .pos = {0.0f, 1.7f, 5.0f},
        .rot = {0.0f, 0.0f, 0.0f, 1.0f},
        .fov_y_deg = 65.0f,
        .z_near = 0.08f,
        .z_far = 500.0f,
        .pocket_id = 0
    };
}

static GLuint make_tex2d(int w, int h, GLint internal_fmt, GLenum fmt, GLenum type, GLint filter) {
    const eng_gl_api_t *gl = eng_gl();
    GLuint t = 0;
    gl->GenTextures(1, &t);
    gl->BindTexture(ENG_GL_TEXTURE_2D, t);
    gl->TexImage2D(ENG_GL_TEXTURE_2D, 0, internal_fmt, w, h, 0, fmt, type, NULL);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MIN_FILTER, filter);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MAG_FILTER, filter);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_WRAP_S, ENG_GL_CLAMP_TO_EDGE);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_WRAP_T, ENG_GL_CLAMP_TO_EDGE);
    return t;
}

static void destroy_targets(eng_renderer_t *r) {
    const eng_gl_api_t *gl = eng_gl();
    GLuint fbos[4] = {r->hdr_fbo, r->bloom_fbo, r->gbuf_fbo, r->shadow_fbo};
    GLuint texs[7] = {
        r->hdr_color_tex, r->hdr_ds_tex, r->bloom_tex,
        r->gb_albedo_tex, r->gb_norm_tex, r->gb_pos_tex, r->shadow_tex
    };
    for (int i = 0; i < 4; i++) {
        if (fbos[i]) gl->DeleteFramebuffers(1, &fbos[i]);
    }
    for (int i = 0; i < 7; i++) {
        if (texs[i]) gl->DeleteTextures(1, &texs[i]);
    }
    r->hdr_fbo = r->bloom_fbo = r->gbuf_fbo = r->shadow_fbo = 0;
}

static bool create_targets(eng_renderer_t *r, int w, int h) {
    const eng_gl_api_t *gl = eng_gl();
    destroy_targets(r);
    r->width = w > 0 ? w : 640;
    r->height = h > 0 ? h : 480;

    GLint hdr_ifmt = gl->is_gles ? ENG_GL_RGBA8 : ENG_GL_RGBA16F;
    GLenum hdr_type = gl->is_gles ? ENG_GL_UNSIGNED_BYTE : ENG_GL_FLOAT;

    r->hdr_color_tex = make_tex2d(r->width, r->height, hdr_ifmt, ENG_GL_RGBA, hdr_type, ENG_GL_LINEAR);
    r->hdr_ds_tex = make_tex2d(r->width, r->height, ENG_GL_DEPTH24_STENCIL8,
                               ENG_GL_DEPTH_STENCIL, ENG_GL_UNSIGNED_INT_24_8, ENG_GL_NEAREST);
    gl->GenFramebuffers(1, &r->hdr_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT0, ENG_GL_TEXTURE_2D, r->hdr_color_tex, 0);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_DEPTH_STENCIL_ATTACHMENT, ENG_GL_TEXTURE_2D, r->hdr_ds_tex, 0);
    GLenum hdr_st = gl->CheckFramebufferStatus(ENG_GL_FRAMEBUFFER);
    if (hdr_st != ENG_GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "[render] hdr_fbo incomplete: 0x%x (%dx%d)\n", hdr_st, r->width, r->height);
        return false;
    }

    int bw = r->width > 1 ? r->width / 2 : 1;
    int bh = r->height > 1 ? r->height / 2 : 1;
    r->bloom_tex = make_tex2d(bw, bh, hdr_ifmt, ENG_GL_RGBA, hdr_type, ENG_GL_LINEAR);
    gl->GenFramebuffers(1, &r->bloom_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->bloom_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT0, ENG_GL_TEXTURE_2D, r->bloom_tex, 0);

    r->gb_albedo_tex = make_tex2d(r->width, r->height, ENG_GL_RGBA8, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, ENG_GL_NEAREST);
    r->gb_norm_tex = make_tex2d(r->width, r->height, ENG_GL_RGBA8, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, ENG_GL_NEAREST);
    r->gb_pos_tex = make_tex2d(r->width, r->height, hdr_ifmt, ENG_GL_RGBA, hdr_type, ENG_GL_NEAREST);
    gl->GenFramebuffers(1, &r->gbuf_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->gbuf_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT0, ENG_GL_TEXTURE_2D, r->gb_albedo_tex, 0);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT1, ENG_GL_TEXTURE_2D, r->gb_norm_tex, 0);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT2, ENG_GL_TEXTURE_2D, r->gb_pos_tex, 0);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_DEPTH_STENCIL_ATTACHMENT, ENG_GL_TEXTURE_2D, r->hdr_ds_tex, 0);
    const GLenum gbuf_atts[3] = {ENG_GL_COLOR_ATTACHMENT0, ENG_GL_COLOR_ATTACHMENT1, ENG_GL_COLOR_ATTACHMENT2};
    gl->DrawBuffers(3, gbuf_atts);
    if (gl->CheckFramebufferStatus(ENG_GL_FRAMEBUFFER) != ENG_GL_FRAMEBUFFER_COMPLETE) {
        gl->DeleteTextures(1, &r->gb_pos_tex);
        r->gb_pos_tex = make_tex2d(r->width, r->height, ENG_GL_RGBA8, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, ENG_GL_NEAREST);
        gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT2, ENG_GL_TEXTURE_2D, r->gb_pos_tex, 0);
    }

    r->shadow_tex = make_tex2d(ENG_SHADOW_RES, ENG_SHADOW_RES, ENG_GL_DEPTH_COMPONENT24,
                               ENG_GL_DEPTH_COMPONENT, ENG_GL_UNSIGNED_INT, ENG_GL_NEAREST);
    gl->GenFramebuffers(1, &r->shadow_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->shadow_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_DEPTH_ATTACHMENT, ENG_GL_TEXTURE_2D, r->shadow_tex, 0);
    const GLenum none_buf = 0;
    gl->DrawBuffers(1, &none_buf);
    gl->ReadBuffer(0);

    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, 0);
    return true;
}

bool eng_renderer_reload_shaders(eng_renderer_t *r) {
    if (!r || !r->vfs) return false;
    bool ok = true;
    ok &= eng_shader_load_vfs(&r->sh_forward, r->vfs, "shaders/forward.vert", "shaders/forward.frag");
    (void)eng_shader_load_vfs(&r->sh_gbuffer, r->vfs, "shaders/gbuffer.vert", "shaders/gbuffer.frag");
    (void)eng_shader_load_vfs(&r->sh_def_light, r->vfs, "shaders/post.vert", "shaders/deferred_light.frag");
    ok &= eng_shader_load_vfs(&r->sh_shadow, r->vfs, "shaders/shadow.vert", "shaders/shadow.frag");
    ok &= eng_shader_load_vfs(&r->sh_skybox, r->vfs, "shaders/skybox.vert", "shaders/skybox.frag");
    ok &= eng_shader_load_vfs(&r->sh_post, r->vfs, "shaders/post.vert", "shaders/post.frag");
    return ok;
}

eng_renderer_t *eng_renderer_create(eng_vfs_t *vfs, eng_asset_cache_t *assets, int width, int height) {
    if (!vfs || !assets) return NULL;
    eng_renderer_t *r = (eng_renderer_t *)calloc(1, sizeof(eng_renderer_t));
    if (!r) return NULL;

    r->vfs = vfs;
    r->assets = assets;
    r->pipeline = ENG_PIPELINE_FORWARD;
    r->retro = eng_retro_default();
    r->sky_zenith = eng_v3(0.14f, 0.34f, 0.72f);
    r->sky_horizon = eng_v3(0.62f, 0.76f, 0.92f);
    r->sky_ground = eng_v3(0.18f, 0.16f, 0.14f);
    r->ambient = eng_v3(0.16f, 0.18f, 0.22f);
    r->max_portal_depth = 2;

    if (!eng_renderer_reload_shaders(r) || !create_targets(r, width, height)) {
        eng_renderer_destroy(r);
        return NULL;
    }

    const eng_gl_api_t *gl = eng_gl();
    static const float fs_quad[12] = {
        -1.0f, -1.0f,  1.0f, -1.0f,  1.0f,  1.0f,
        -1.0f, -1.0f,  1.0f,  1.0f, -1.0f,  1.0f
    };
    gl->GenVertexArrays(1, &r->fs_vao);
    gl->BindVertexArray(r->fs_vao);
    gl->GenBuffers(1, &r->fs_vbo);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, r->fs_vbo);
    gl->BufferData(ENG_GL_ARRAY_BUFFER, sizeof(fs_quad), fs_quad, ENG_GL_STATIC_DRAW);
    gl->EnableVertexAttribArray(0);
    gl->VertexAttribPointer(0, 2, ENG_GL_FLOAT, ENG_GL_FALSE, 2 * sizeof(float), NULL);

    /* Dynamic sprite batch VAO */
    gl->GenVertexArrays(1, &r->sp_vao);
    gl->BindVertexArray(r->sp_vao);
    gl->GenBuffers(1, &r->sp_vbo);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, r->sp_vbo);
    gl->GenBuffers(1, &r->sp_ebo);
    gl->BindBuffer(ENG_GL_ELEMENT_ARRAY_BUFFER, r->sp_ebo);
    gl->EnableVertexAttribArray(0);
    gl->VertexAttribPointer(0, 3, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, pos));
    gl->EnableVertexAttribArray(1);
    gl->VertexAttribPointer(1, 3, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, norm));
    gl->EnableVertexAttribArray(2);
    gl->VertexAttribPointer(2, 2, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, uv));
    gl->EnableVertexAttribArray(3);
    gl->VertexAttribPointer(3, 4, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, color));
    eng_mat4_t sp_ident = eng_mat4_identity();
    gl->GenBuffers(1, &r->sp_inst_vbo);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, r->sp_inst_vbo);
    gl->BufferData(ENG_GL_ARRAY_BUFFER, sizeof(eng_mat4_t), sp_ident.m, ENG_GL_STATIC_DRAW);
    for (GLuint c = 0; c < 4; c++) {
        gl->EnableVertexAttribArray(4u + c);
        gl->VertexAttribPointer(4u + c, 4, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_mat4_t), (const void *)(uintptr_t)(c * 16u));
        gl->VertexAttribDivisor(4u + c, 1u);
    }
    gl->BindVertexArray(0);

    /* Unit portal inverted near-plane cap & flat doorway quad */
    eng_mesh_data_t cap_md, quad_md;
    eng_mesh_data_init(&cap_md);
    eng_mesh_append_box(&cap_md, eng_v3(0.0f, 0.0f, 0.125f), eng_v3(2.0f, 2.0f, 0.25f), (eng_vec4_t){1, 1, 1, 1});
    r->portal_cap_mesh = eng_asset_upload_mesh(assets, "__portal_cap", &cap_md);
    eng_mesh_data_free(&cap_md);

    eng_mesh_data_init(&quad_md);
    eng_mesh_append_box(&quad_md, eng_v3(0.0f, 0.0f, 0.0f), eng_v3(2.0f, 2.0f, 0.002f), (eng_vec4_t){1, 1, 1, 1});
    r->portal_quad_mesh = eng_asset_upload_mesh(assets, "__portal_quad", &quad_md);
    eng_mesh_data_free(&quad_md);

    /* Built-in 32x32 soft radial Gaussian puff texture for fire, smoke, sparks & glow */
    uint8_t puff[32 * 32 * 4];
    for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
            float dx = ((float)x + 0.5f) / 16.0f - 1.0f;
            float dy = ((float)y + 0.5f) / 16.0f - 1.0f;
            float r2 = dx * dx + dy * dy;
            float a = (r2 < 1.0f) ? expf(-3.2f * r2) * (1.0f - r2) : 0.0f;
            int idx = (y * 32 + x) * 4;
            puff[idx + 0] = puff[idx + 1] = puff[idx + 2] = 255u;
            puff[idx + 3] = (uint8_t)(eng_clampf(a, 0.0f, 1.0f) * 255.0f);
        }
    }
    r->soft_particle_tex = eng_asset_create_texture_rgba(assets, "__soft_puff", 32, 32, puff, false);

    return r;
}

void eng_renderer_destroy(eng_renderer_t *r) {
    if (!r) return;
    const eng_gl_api_t *gl = eng_gl();
    destroy_targets(r);
    eng_shader_destroy(&r->sh_forward);
    eng_shader_destroy(&r->sh_gbuffer);
    eng_shader_destroy(&r->sh_def_light);
    eng_shader_destroy(&r->sh_shadow);
    eng_shader_destroy(&r->sh_skybox);
    eng_shader_destroy(&r->sh_post);
    if (r->fs_vbo) gl->DeleteBuffers(1, &r->fs_vbo);
    if (r->fs_vao) gl->DeleteVertexArrays(1, &r->fs_vao);
    if (r->sp_vbo) gl->DeleteBuffers(1, &r->sp_vbo);
    if (r->sp_ebo) gl->DeleteBuffers(1, &r->sp_ebo);
    if (r->sp_inst_vbo) gl->DeleteBuffers(1, &r->sp_inst_vbo);
    if (r->sp_vao) gl->DeleteVertexArrays(1, &r->sp_vao);
    free(r->items);
    free(r->sprites);
    free(r->inst_scratch);
    free(r);
}

bool eng_renderer_resize(eng_renderer_t *r, int width, int height) {
    if (!r || width <= 0 || height <= 0) return false;
    if (width == r->width && height == r->height) return true;
    return create_targets(r, width, height);
}

void eng_renderer_set_pipeline(eng_renderer_t *r, eng_pipeline_mode_t mode) { if (r) r->pipeline = mode; }
eng_pipeline_mode_t eng_renderer_get_pipeline(const eng_renderer_t *r) { return r ? r->pipeline : ENG_PIPELINE_FORWARD; }
void eng_renderer_set_retro(eng_renderer_t *r, const eng_retro_cfg_t *cfg) { if (r && cfg) r->retro = *cfg; }
eng_retro_cfg_t eng_renderer_get_retro(const eng_renderer_t *r) { return r ? r->retro : eng_retro_default(); }
void eng_renderer_set_sky(eng_renderer_t *r, eng_vec3_t z, eng_vec3_t h, eng_vec3_t g) {
    if (r) { r->sky_zenith = z; r->sky_horizon = h; r->sky_ground = g; }
}
void eng_renderer_set_ambient(eng_renderer_t *r, eng_vec3_t a) { if (r) r->ambient = a; }
void eng_renderer_set_max_portal_depth(eng_renderer_t *r, int d) { if (r) r->max_portal_depth = d < 0 ? 0 : (d > 4 ? 4 : d); }

void eng_renderer_begin_frame(eng_renderer_t *r) {
    if (!r) return;
    r->item_count = 0;
    r->sprite_count = 0;
    r->light_count = 0;
    memset(&r->stats, 0, sizeof(r->stats));
}

bool eng_renderer_submit_mesh(eng_renderer_t *r, const eng_draw_item_t *item) {
    if (!r || !item || item->mesh_id == 0) return false;
    if (r->item_count == r->item_cap) {
        size_t nc = r->item_cap ? r->item_cap * 2 : 128;
        eng_draw_item_t *ni = (eng_draw_item_t *)realloc(r->items, nc * sizeof(eng_draw_item_t));
        if (!ni) return false;
        r->items = ni;
        r->item_cap = nc;
    }
    r->items[r->item_count++] = *item;
    r->stats.submitted_items++;
    return true;
}

bool eng_renderer_submit_sprites(eng_renderer_t *r, const eng_sprite_item_t *sprites, size_t count) {
    if (!r || !sprites || count == 0) return false;
    if (r->sprite_count + count > r->sprite_cap) {
        size_t nc = r->sprite_cap ? r->sprite_cap * 2 : 128;
        while (nc < r->sprite_count + count) nc *= 2;
        eng_sprite_item_t *ns = (eng_sprite_item_t *)realloc(r->sprites, nc * sizeof(eng_sprite_item_t));
        if (!ns) return false;
        r->sprites = ns;
        r->sprite_cap = nc;
    }
    memcpy(r->sprites + r->sprite_count, sprites, count * sizeof(eng_sprite_item_t));
    r->sprite_count += count;
    return true;
}

bool eng_renderer_add_light(eng_renderer_t *r, const eng_light_t *light) {
    if (!r || !light || r->light_count >= ENG_MAX_LIGHTS) return false;
    r->lights[r->light_count++] = *light;
    return true;
}

static bool is_aabb_occluded(eng_vec3_t cam_pos, eng_aabb_t target, const eng_aabb_t *occs, size_t occ_count) {
    if (occ_count == 0) return false;
    eng_vec3_t corners[8] = {
        {target.min.x, target.min.y, target.min.z}, {target.max.x, target.min.y, target.min.z},
        {target.min.x, target.max.y, target.min.z}, {target.max.x, target.max.y, target.min.z},
        {target.min.x, target.min.y, target.max.z}, {target.max.x, target.min.y, target.max.z},
        {target.min.x, target.max.y, target.max.z}, {target.max.x, target.max.y, target.max.z}
    };
    for (size_t o = 0; o < occ_count; o++) {
        bool all_blocked = true;
        for (int c = 0; c < 8; c++) {
            eng_vec3_t to_c = eng_v3_sub(corners[c], cam_pos);
            float dist = eng_v3_len(to_c);
            if (dist < 0.05f) { all_blocked = false; break; }
            float t_hit = 0.0f;
            if (!eng_aabb_ray_hit(occs[o], cam_pos, eng_v3_scale(to_c, 1.0f / dist), dist - 0.02f, &t_hit) || t_hit <= 0.001f) {
                all_blocked = false;
                break;
            }
        }
        if (all_blocked) return true;
    }
    return false;
}

static int cmp_vis_draw(const void *a, const void *b) {
    const vis_draw_t *da = (const vis_draw_t *)a;
    const vis_draw_t *db = (const vis_draw_t *)b;
    if (da->mesh_id != db->mesh_id) return da->mesh_id < db->mesh_id ? -1 : 1;
    if (da->tex_id != db->tex_id) return da->tex_id < db->tex_id ? -1 : 1;
    return (int)da->lod - (int)db->lod;
}

static int cmp_vis_trans(const void *a, const void *b) {
    const vis_draw_t *da = (const vis_draw_t *)a;
    const vis_draw_t *db = (const vis_draw_t *)b;
    return (da->cam_dist < db->cam_dist) ? 1 : (da->cam_dist > db->cam_dist ? -1 : 0);
}

static void upload_lights_and_env(const eng_shader_t *sh, const eng_renderer_t *r, uint16_t pocket_id,
                                  eng_vec3_t cam_pos, const eng_mat4_t *light_vp, bool has_shadow) {
    const eng_gl_api_t *gl = eng_gl();
    eng_vec4_t pos_type[8];
    eng_vec4_t dir_range[8];
    eng_vec4_t col_cone[8];
    int n = 0;
    for (size_t i = 0; i < r->light_count && n < 8; i++) {
        const eng_light_t *l = &r->lights[i];
        if (l->pocket_id != pocket_id) continue;
        pos_type[n] = (eng_vec4_t){l->pos.x, l->pos.y, l->pos.z, (float)l->type};
        dir_range[n] = (eng_vec4_t){l->dir.x, l->dir.y, l->dir.z, l->range > 0.0f ? l->range : 20.0f};
        col_cone[n] = (eng_vec4_t){l->color.x, l->color.y, l->color.z, l->spot_cos_inner};
        n++;
    }
    eng_shader_set_v3(sh, "u_cam_pos", cam_pos);
    eng_shader_set_v3(sh, "u_ambient", r->ambient);
    eng_shader_set_v3(sh, "u_sky_zenith", r->sky_zenith);
    eng_shader_set_v3(sh, "u_sky_horizon", r->sky_horizon);
    eng_shader_set_v3(sh, "u_sky_ground", r->sky_ground);
    eng_shader_set_v4(sh, "u_fog", (eng_vec4_t){r->retro.fog_color.x, r->retro.fog_color.y, r->retro.fog_color.z, r->retro.fog_density});
    eng_shader_set_float(sh, "u_fog_height", r->retro.fog_height);
    eng_shader_set_mat4(sh, "u_light_vp", light_vp);
    eng_shader_set_int(sh, "u_has_shadow", has_shadow ? 1 : 0);
    eng_shader_set_int(sh, "u_light_count", n);
    if (n > 0) {
        GLint lp = gl->GetUniformLocation(sh->program, "u_light_pos_type");
        GLint ld = gl->GetUniformLocation(sh->program, "u_light_dir_range");
        GLint lc = gl->GetUniformLocation(sh->program, "u_light_color_cone");
        if (lp >= 0) gl->Uniform4fv(lp, n, &pos_type[0].x);
        if (ld >= 0) gl->Uniform4fv(ld, n, &dir_range[0].x);
        if (lc >= 0) gl->Uniform4fv(lc, n, &col_cone[0].x);
    }
}

static void draw_single_mesh_xform(eng_renderer_t *r, uint32_t mesh_id, const eng_mat4_t *world) {
    const eng_gl_api_t *gl = eng_gl();
    const eng_gpu_mesh_t *gm = eng_asset_get_mesh(r->assets, mesh_id);
    if (!gm || !gm->valid) return;
    gl->BindVertexArray(gm->vao);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, gm->instance_vbo);
    gl->BufferData(ENG_GL_ARRAY_BUFFER, sizeof(eng_mat4_t), world->m, ENG_GL_DYNAMIC_DRAW);
    gl->DrawElementsInstanced(ENG_GL_TRIANGLES, (GLsizei)gm->lod_index_counts[0], ENG_GL_UNSIGNED_INT, NULL, 1);
}

/* pass_mode: 0 = opaque (skips emissive in deferred gbuffer), 1 = translucent Fresnel, 2 = deferred opaque emissive */
static void draw_pocket_meshes(eng_renderer_t *r, uint16_t pocket_id, const eng_mat4_t *vp,
                               eng_vec3_t cam_pos, const eng_shader_t *sh, bool count_cull_stats, int pass_mode) {
    const eng_gl_api_t *gl = eng_gl();
    eng_frustum_t frust = eng_frustum_from_mat4(vp);
    bool is_gbuf = (sh == &r->sh_gbuffer);

    eng_aabb_t occluders[32];
    size_t occ_count = 0;
    for (size_t i = 0; i < r->item_count && occ_count < 32; i++) {
        if (r->items[i].pocket_id == pocket_id && r->items[i].occluder) {
            const eng_gpu_mesh_t *gm = eng_asset_get_mesh(r->assets, r->items[i].mesh_id);
            if (gm) occluders[occ_count++] = eng_aabb_transform(gm->local_aabb, &r->items[i].world);
        }
    }

    vis_draw_t *vis = (vis_draw_t *)malloc((r->item_count + 1u) * sizeof(vis_draw_t));
    if (!vis) return;
    size_t vis_count = 0;

    for (size_t i = 0; i < r->item_count; i++) {
        const eng_draw_item_t *it = &r->items[i];
        if (it->pocket_id != pocket_id) {
            if (count_cull_stats) r->stats.culled_pocket++;
            continue;
        }
        bool is_trans = (it->tint.w < 0.99f);
        bool has_em = (it->emissive.x > 0.001f || it->emissive.y > 0.001f || it->emissive.z > 0.001f);
        if (pass_mode == 0 && (is_trans || (is_gbuf && has_em))) continue;
        if (pass_mode == 1 && !is_trans) continue;
        if (pass_mode == 2 && (is_trans || !has_em)) continue;

        const eng_gpu_mesh_t *gm = eng_asset_get_mesh(r->assets, it->mesh_id);
        if (!gm || !gm->valid) continue;

        eng_aabb_t waabb = eng_aabb_transform(gm->local_aabb, &it->world);
        if (!eng_frustum_test_aabb(&frust, waabb)) {
            if (count_cull_stats) r->stats.culled_frustum++;
            continue;
        }
        if (!it->occluder && is_aabb_occluded(cam_pos, waabb, occluders, occ_count)) {
            if (count_cull_stats) r->stats.culled_occluded++;
            continue;
        }

        eng_vec3_t center = eng_v3_scale(eng_v3_add(waabb.min, waabb.max), 0.5f);
        float dist = eng_v3_len(eng_v3_sub(center, cam_pos));
        uint8_t lod = (dist < 15.0f) ? 0u : (dist < 35.0f ? 1u : (dist < 75.0f ? 2u : 3u));
        if (count_cull_stats) r->stats.lod_counts[lod]++;
        vis[vis_count++] = (vis_draw_t){(uint32_t)i, it->mesh_id, it->albedo_tex, lod, dist};
    }

    if (vis_count > 1) qsort(vis, vis_count, sizeof(vis_draw_t), pass_mode == 1 ? cmp_vis_trans : cmp_vis_draw);

    for (size_t b = 0; b < vis_count;) {
        const eng_draw_item_t *first = &r->items[vis[b].item_idx];
        size_t batch_len = 1;
        if (!first->skin_bones && pass_mode != 1) {
            while (b + batch_len < vis_count) {
                const eng_draw_item_t *nxt = &r->items[vis[b + batch_len].item_idx];
                if (nxt->skin_bones ||
                    vis[b + batch_len].mesh_id != vis[b].mesh_id ||
                    vis[b + batch_len].tex_id != vis[b].tex_id ||
                    vis[b + batch_len].lod != vis[b].lod ||
                    fabsf(nxt->tint.x - first->tint.x) > 1e-3f ||
                    fabsf(nxt->tint.y - first->tint.y) > 1e-3f ||
                    fabsf(nxt->tint.z - first->tint.z) > 1e-3f ||
                    fabsf(nxt->tint.w - first->tint.w) > 1e-3f ||
                    fabsf(nxt->metallic - first->metallic) > 1e-3f ||
                    fabsf(nxt->roughness - first->roughness) > 1e-3f ||
                    fabsf(nxt->emissive.x - first->emissive.x) > 1e-3f ||
                    fabsf(nxt->emissive.y - first->emissive.y) > 1e-3f ||
                    fabsf(nxt->emissive.z - first->emissive.z) > 1e-3f) {
                    break;
                }
                batch_len++;
            }
        }

        if (batch_len > r->inst_cap) {
            size_t nc = batch_len * 2u;
            eng_mat4_t *nm = (eng_mat4_t *)realloc(r->inst_scratch, nc * sizeof(eng_mat4_t));
            if (!nm) break;
            r->inst_scratch = nm;
            r->inst_cap = nc;
        }
        for (size_t k = 0; k < batch_len; k++) {
            r->inst_scratch[k] = r->items[vis[b + k].item_idx].world;
        }

        const eng_gpu_mesh_t *gm = eng_asset_get_mesh(r->assets, first->mesh_id);
        const eng_gpu_tex_t *gt = eng_asset_get_texture(r->assets, first->albedo_tex);
        gl->ActiveTexture(ENG_GL_TEXTURE0);
        gl->BindTexture(ENG_GL_TEXTURE_2D, gt ? gt->tex_id : 0);
        if (gt && gt->tex_id) {
            GLint fmode = (r->retro.nearest_textures || gt->nearest) ? ENG_GL_NEAREST : ENG_GL_LINEAR;
            gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MAG_FILTER, fmode);
        }

        eng_shader_set_int(sh, "u_albedo_tex", 0);
        eng_shader_set_v4(sh, "u_tint", first->tint);
        eng_shader_set_v3(sh, "u_mat_mr", eng_v3(first->metallic, first->roughness, pass_mode == 1 ? 1.0f : 0.0f));
        eng_shader_set_v3(sh, "u_emissive", first->emissive);

        if (first->skin_bones && first->skin_bone_count > 0) {
            uint32_t bc = first->skin_bone_count > 48u ? 48u : first->skin_bone_count;
            eng_shader_set_int(sh, "u_skinned", 1);
            GLint bloc = gl->GetUniformLocation(sh->program, "u_bones");
            if (bloc >= 0) gl->UniformMatrix4fv(bloc, (GLsizei)bc, ENG_GL_FALSE, first->skin_bones[0].m);
        } else {
            eng_shader_set_int(sh, "u_skinned", 0);
        }

        uint8_t lod = vis[b].lod;
        gl->BindVertexArray(gm->vao);
        gl->BindBuffer(ENG_GL_ARRAY_BUFFER, gm->instance_vbo);
        gl->BufferData(ENG_GL_ARRAY_BUFFER, (GLsizeiptr)(batch_len * sizeof(eng_mat4_t)), r->inst_scratch, ENG_GL_DYNAMIC_DRAW);
        gl->DrawElementsInstanced(
            ENG_GL_TRIANGLES,
            (GLsizei)gm->lod_index_counts[lod],
            ENG_GL_UNSIGNED_INT,
            (const void *)(uintptr_t)(gm->lod_index_offsets[lod] * sizeof(uint32_t)),
            (GLsizei)batch_len
        );

        r->stats.draw_batches++;
        if (batch_len > 1) r->stats.instanced_draws += (uint32_t)batch_len;
        b += batch_len;
    }
    free(vis);
}

static bool render_shadow_map(eng_renderer_t *r, uint16_t pocket_id, eng_vec3_t focus_pos, eng_mat4_t *out_light_vp) {
    const eng_light_t *sun = NULL;
    for (size_t i = 0; i < r->light_count; i++) {
        if (r->lights[i].pocket_id == pocket_id && r->lights[i].type == ENG_LIGHT_DIR && r->lights[i].cast_shadow) {
            sun = &r->lights[i];
            break;
        }
    }
    if (!sun) {
        *out_light_vp = eng_mat4_identity();
        return false;
    }

    eng_vec3_t dir = eng_v3_norm(sun->dir);
    if (eng_v3_dot(dir, dir) < 0.1f) dir = eng_v3(0.0f, -1.0f, 0.0f);
    eng_vec3_t up = fabsf(dir.y) > 0.95f ? eng_v3(0.0f, 0.0f, 1.0f) : eng_v3(0.0f, 1.0f, 0.0f);
    eng_mat4_t lview = eng_mat4_look_at(eng_v3_sub(focus_pos, eng_v3_scale(dir, 40.0f)), focus_pos, up);
    eng_mat4_t lproj = eng_mat4_ortho(-30.0f, 30.0f, -30.0f, 30.0f, 1.0f, 100.0f);
    *out_light_vp = eng_mat4_mul(&lproj, &lview);

    const eng_gl_api_t *gl = eng_gl();
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->shadow_fbo);
    gl->Viewport(0, 0, ENG_SHADOW_RES, ENG_SHADOW_RES);
    gl->Disable(ENG_GL_SCISSOR_TEST);
    gl->Disable(ENG_GL_STENCIL_TEST);
    gl->Enable(ENG_GL_DEPTH_TEST);
    gl->DepthMask(ENG_GL_TRUE);
    gl->DepthFunc(ENG_GL_LESS);
    gl->Clear(ENG_GL_DEPTH_BUFFER_BIT);

    eng_shader_bind(&r->sh_shadow);
    eng_shader_set_mat4(&r->sh_shadow, "u_vp", out_light_vp);
    for (size_t i = 0; i < r->item_count; i++) {
        if (r->items[i].pocket_id == pocket_id && r->items[i].cast_shadow && r->items[i].tint.w >= 0.99f) {
            draw_single_mesh_xform(r, r->items[i].mesh_id, &r->items[i].world);
        }
    }
    return true;
}

static void draw_pocket_sprites(eng_renderer_t *r, uint16_t pocket_id, const eng_mat4_t *view,
                                const eng_mat4_t *vp, eng_vec3_t cam_pos, const eng_mat4_t *light_vp, bool has_shadow) {
    if (r->sprite_count == 0) return;
    const eng_gl_api_t *gl = eng_gl();
    eng_vec3_t cam_right = eng_v3(view->m[0], view->m[4], view->m[8]);
    eng_vec3_t cam_up = eng_v3(view->m[1], view->m[5], view->m[9]);

    eng_shader_bind(&r->sh_forward);
    eng_shader_set_mat4(&r->sh_forward, "u_vp", vp);
    eng_shader_set_float(&r->sh_forward, "u_vertex_snap", 0.0f);
    eng_shader_set_int(&r->sh_forward, "u_skinned", 0);
    eng_shader_set_v4(&r->sh_forward, "u_tint", (eng_vec4_t){1, 1, 1, 1});
    upload_lights_and_env(&r->sh_forward, r, pocket_id, cam_pos, light_vp, has_shadow);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
    eng_shader_set_int(&r->sh_forward, "u_shadow_tex", 1);
    gl->Enable(ENG_GL_BLEND);

    /* Batch per unique (tex_id, additive, spherical) group in pocket */
    for (size_t i = 0; i < r->sprite_count; i++) {
        if (r->sprites[i].pocket_id != pocket_id) continue;
        uint32_t tid = r->sprites[i].tex_id;
        bool add_b = r->sprites[i].additive;
        bool is_sph = (r->sprites[i].mode == ENG_SPRITE_BILLBOARD_SPHERICAL);
        bool seen = false;
        for (size_t k = 0; k < i; k++) {
            if (r->sprites[k].pocket_id == pocket_id && r->sprites[k].tex_id == tid &&
                r->sprites[k].additive == add_b && (r->sprites[k].mode == ENG_SPRITE_BILLBOARD_SPHERICAL) == is_sph) {
                seen = true;
                break;
            }
        }
        if (seen) continue;

        eng_sprite_item_t *sub = (eng_sprite_item_t *)malloc(r->sprite_count * sizeof(eng_sprite_item_t));
        if (!sub) break;
        size_t sub_n = 0;
        for (size_t k = i; k < r->sprite_count; k++) {
            if (r->sprites[k].pocket_id == pocket_id && r->sprites[k].tex_id == tid &&
                r->sprites[k].additive == add_b && (r->sprites[k].mode == ENG_SPRITE_BILLBOARD_SPHERICAL) == is_sph) {
                sub[sub_n++] = r->sprites[k];
            }
        }
        eng_mesh_data_t smd;
        if (eng_sprite_build_batch(sub, sub_n, pocket_id, cam_pos, cam_right, cam_up, &smd) > 0) {
            uint32_t eff_tid = (tid == 0 && is_sph) ? r->soft_particle_tex : tid;
            const eng_gpu_tex_t *gt = eng_asset_get_texture(r->assets, eff_tid);
            gl->ActiveTexture(ENG_GL_TEXTURE0);
            gl->BindTexture(ENG_GL_TEXTURE_2D, gt ? gt->tex_id : 0);
            eng_shader_set_int(&r->sh_forward, "u_albedo_tex", 0);
            gl->BlendFunc(ENG_GL_SRC_ALPHA, add_b ? ENG_GL_ONE : ENG_GL_ONE_MINUS_SRC_ALPHA);
            gl->DepthMask(is_sph ? ENG_GL_FALSE : ENG_GL_TRUE);
            eng_shader_set_v3(&r->sh_forward, "u_mat_mr", eng_v3(0.0f, 0.92f, add_b ? -1.0f : (is_sph ? 0.25f : 0.0f)));
            eng_shader_set_v3(&r->sh_forward, "u_emissive", add_b ? eng_v3(0.55f, 0.55f, 0.55f) : eng_v3(0.0f, 0.0f, 0.0f));

            gl->BindVertexArray(r->sp_vao);
            gl->BindBuffer(ENG_GL_ARRAY_BUFFER, r->sp_vbo);
            gl->BufferData(ENG_GL_ARRAY_BUFFER, (GLsizeiptr)(smd.vert_count * sizeof(eng_vertex_t)), smd.verts, ENG_GL_DYNAMIC_DRAW);
            gl->BindBuffer(ENG_GL_ELEMENT_ARRAY_BUFFER, r->sp_ebo);
            gl->BufferData(ENG_GL_ELEMENT_ARRAY_BUFFER, (GLsizeiptr)(smd.idx_count * sizeof(uint32_t)), smd.indices, ENG_GL_DYNAMIC_DRAW);
            gl->DrawElementsInstanced(ENG_GL_TRIANGLES, (GLsizei)smd.idx_count, ENG_GL_UNSIGNED_INT, NULL, 1);
            r->stats.draw_batches++;
        }
        eng_mesh_data_free(&smd);
        free(sub);
    }
    gl->DepthMask(ENG_GL_TRUE);
    gl->BlendFunc(ENG_GL_SRC_ALPHA, ENG_GL_ONE_MINUS_SRC_ALPHA);
    gl->Disable(ENG_GL_BLEND);
}

static void render_pocket_recursive(eng_renderer_t *r, const eng_scene_t *scene,
                                    const eng_portal_sys_t *portals, uint16_t pocket_id,
                                    const eng_mat4_t *view, const eng_mat4_t *proj,
                                    eng_vec3_t cam_pos, const int vp_rect[4],
                                    const int scissor_rect[4], int depth,
                                    eng_entity_t entered_dst_ent,
                                    const eng_mat4_t *root_light_vp, bool root_has_shadow) {
    const eng_gl_api_t *gl = eng_gl();
    eng_mat4_t vp = eng_mat4_mul(proj, view);
    bool has_sh = (depth == 0) ? root_has_shadow : false;

    gl->Viewport(vp_rect[0], vp_rect[1], vp_rect[2], vp_rect[3]);
    gl->Enable(ENG_GL_SCISSOR_TEST);
    gl->Scissor(scissor_rect[0], scissor_rect[1], scissor_rect[2], scissor_rect[3]);
    gl->Enable(ENG_GL_STENCIL_TEST);
    gl->StencilFunc(ENG_GL_EQUAL, depth, 0xFFu);
    gl->StencilOp(ENG_GL_KEEP, ENG_GL_KEEP, ENG_GL_KEEP);
    gl->StencilMask(0x00u);
    gl->ColorMask(ENG_GL_TRUE, ENG_GL_TRUE, ENG_GL_TRUE, ENG_GL_TRUE);
    gl->Enable(ENG_GL_DEPTH_TEST);
    gl->DepthMask(ENG_GL_TRUE);
    gl->DepthFunc(ENG_GL_LESS);
    gl->Enable(ENG_GL_CULL_FACE);
    gl->CullFace(ENG_GL_BACK);

    bool use_deferred = (r->pipeline == ENG_PIPELINE_DEFERRED && r->sh_gbuffer.valid && r->sh_def_light.valid);
    if (use_deferred) {
        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->gbuf_fbo);
        gl->ClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        gl->Clear(ENG_GL_COLOR_BUFFER_BIT);
        eng_shader_bind(&r->sh_gbuffer);
        eng_shader_set_mat4(&r->sh_gbuffer, "u_vp", &vp);
        eng_shader_set_float(&r->sh_gbuffer, "u_vertex_snap", r->retro.vertex_snap_res);
        draw_pocket_meshes(r, pocket_id, &vp, cam_pos, &r->sh_gbuffer, depth == 0, 0);

        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
        gl->Disable(ENG_GL_DEPTH_TEST);
        gl->DepthMask(ENG_GL_FALSE);
        eng_shader_bind(&r->sh_def_light);
        gl->ActiveTexture(ENG_GL_TEXTURE0); gl->BindTexture(ENG_GL_TEXTURE_2D, r->gb_albedo_tex);
        gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u); gl->BindTexture(ENG_GL_TEXTURE_2D, r->gb_norm_tex);
        gl->ActiveTexture(ENG_GL_TEXTURE0 + 2u); gl->BindTexture(ENG_GL_TEXTURE_2D, r->gb_pos_tex);
        gl->ActiveTexture(ENG_GL_TEXTURE0 + 3u); gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
        eng_shader_set_int(&r->sh_def_light, "u_gb_albedo_met", 0);
        eng_shader_set_int(&r->sh_def_light, "u_gb_norm_rough", 1);
        eng_shader_set_int(&r->sh_def_light, "u_gb_pos_ao", 2);
        eng_shader_set_int(&r->sh_def_light, "u_shadow_tex", 3);
        upload_lights_and_env(&r->sh_def_light, r, pocket_id, cam_pos, root_light_vp, has_sh);
        gl->BindVertexArray(r->fs_vao);
        gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);
        gl->Enable(ENG_GL_DEPTH_TEST);
        gl->DepthMask(ENG_GL_TRUE);
    } else {
        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
        eng_shader_bind(&r->sh_forward);
        eng_shader_set_mat4(&r->sh_forward, "u_vp", &vp);
        eng_shader_set_float(&r->sh_forward, "u_vertex_snap", r->retro.vertex_snap_res);
        gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
        gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
        eng_shader_set_int(&r->sh_forward, "u_shadow_tex", 1);
        upload_lights_and_env(&r->sh_forward, r, pocket_id, cam_pos, root_light_vp, has_sh);
        draw_pocket_meshes(r, pocket_id, &vp, cam_pos, &r->sh_forward, depth == 0, 0);
    }

    /* Skybox at far plane where depth == 1.0 and stencil == depth */
    eng_mat4_t inv_vp;
    if (eng_mat4_invert(&vp, &inv_vp)) {
        gl->DepthFunc(ENG_GL_LEQUAL);
        gl->DepthMask(ENG_GL_FALSE);
        eng_shader_bind(&r->sh_skybox);
        eng_shader_set_mat4(&r->sh_skybox, "u_inv_vp", &inv_vp);
        eng_shader_set_v3(&r->sh_skybox, "u_sky_zenith", r->sky_zenith);
        eng_shader_set_v3(&r->sh_skybox, "u_sky_horizon", r->sky_horizon);
        eng_shader_set_v3(&r->sh_skybox, "u_sky_ground", r->sky_ground);
        eng_shader_set_v3(&r->sh_skybox, "u_sun_dir", eng_v3(-0.4f, -0.8f, -0.4f));
        gl->BindVertexArray(r->fs_vao);
        gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);
        gl->DepthMask(ENG_GL_TRUE);
        gl->DepthFunc(ENG_GL_LESS);
    }

    /* Forward composite pass for deferred opaque emissives and translucent Fresnel meshes (crystals/glass/water) */
    eng_shader_bind(&r->sh_forward);
    eng_shader_set_mat4(&r->sh_forward, "u_vp", &vp);
    eng_shader_set_float(&r->sh_forward, "u_vertex_snap", r->retro.vertex_snap_res);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
    eng_shader_set_int(&r->sh_forward, "u_shadow_tex", 1);
    upload_lights_and_env(&r->sh_forward, r, pocket_id, cam_pos, root_light_vp, has_sh);
    if (use_deferred) {
        draw_pocket_meshes(r, pocket_id, &vp, cam_pos, &r->sh_forward, depth == 0, 2);
    }
    gl->Enable(ENG_GL_BLEND);
    gl->BlendFunc(ENG_GL_SRC_ALPHA, ENG_GL_ONE_MINUS_SRC_ALPHA);
    gl->DepthMask(ENG_GL_FALSE);
    draw_pocket_meshes(r, pocket_id, &vp, cam_pos, &r->sh_forward, depth == 0, 1);
    gl->DepthMask(ENG_GL_TRUE);
    gl->Disable(ENG_GL_BLEND);

    /* Sprites & Particles in this pocket */
    gl->Disable(ENG_GL_CULL_FACE);
    draw_pocket_sprites(r, pocket_id, view, &vp, cam_pos, root_light_vp, has_sh);
    gl->Enable(ENG_GL_CULL_FACE);

    /* Recursive Stencil + Lengyel Oblique Near-Plane Portals */
    if (!scene || !portals || depth >= r->max_portal_depth) return;
    size_t pcount = eng_portal_count(portals);
    for (size_t i = 0; i < pcount; i++) {
        const eng_portal_t *p = eng_portal_get(portals, i);
        if (!p || p->src_pocket != pocket_id || p->src_ent == entered_dst_ent) continue;

        int local_sc[4];
        if (!eng_portal_screen_scissor(scene, p, &vp, vp_rect[2], vp_rect[3], local_sc)) continue;

        /* Intersect portal screen rect with current parent scissor */
        int x0 = local_sc[0] + vp_rect[0];
        int y0 = local_sc[1] + vp_rect[1];
        int x1 = x0 + local_sc[2];
        int y1 = y0 + local_sc[3];
        if (x0 < scissor_rect[0]) x0 = scissor_rect[0];
        if (y0 < scissor_rect[1]) y0 = scissor_rect[1];
        if (x1 > scissor_rect[0] + scissor_rect[2]) x1 = scissor_rect[0] + scissor_rect[2];
        if (y1 > scissor_rect[1] + scissor_rect[3]) y1 = scissor_rect[1] + scissor_rect[3];
        if (x1 <= x0 || y1 <= y0) continue;
        int child_sc[4] = {x0, y0, x1 - x0, y1 - y0};

        eng_mat4_t virt_view, oblique_proj, warp;
        if (!eng_portal_virtual_camera(scene, p, view, proj, &virt_view, &oblique_proj) ||
            !eng_portal_warp_matrix(scene, p, &warp)) {
            continue;
        }
        const eng_mat4_t *m_src = eng_scene_get_world_matrix(scene, p->src_ent);
        if (!m_src) continue;

        eng_mat4_t scale_m = eng_mat4_trs(eng_v3(0, 0, 0), eng_quat_identity(), eng_v3(p->half_w, p->half_h, 1.0f));
        eng_mat4_t cap_world = eng_mat4_mul(m_src, &scale_m);

        /* 1. Mark portal aperture + inverted near-plane cap in stencil (depth -> depth + 1) */
        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
        gl->Scissor(child_sc[0], child_sc[1], child_sc[2], child_sc[3]);
        gl->ColorMask(ENG_GL_FALSE, ENG_GL_FALSE, ENG_GL_FALSE, ENG_GL_FALSE);
        gl->DepthMask(ENG_GL_FALSE);
        gl->Disable(ENG_GL_CULL_FACE);
        gl->StencilMask(0xFFu);
        gl->StencilFunc(ENG_GL_EQUAL, depth, 0xFFu);
        gl->StencilOp(ENG_GL_KEEP, ENG_GL_KEEP, ENG_GL_INCR);
        eng_shader_bind(&r->sh_shadow);
        eng_shader_set_mat4(&r->sh_shadow, "u_vp", &vp);
        draw_single_mesh_xform(r, r->portal_cap_mesh, &cap_world);

        /* 2. Reset depth inside stencil == depth + 1 to 1.0 (far plane) without touching outer pocket depth */
        gl->StencilMask(0x00u);
        gl->StencilFunc(ENG_GL_EQUAL, depth + 1, 0xFFu);
        gl->StencilOp(ENG_GL_KEEP, ENG_GL_KEEP, ENG_GL_KEEP);
        gl->DepthMask(ENG_GL_TRUE);
        gl->DepthFunc(ENG_GL_ALWAYS);
        eng_shader_bind(&r->sh_skybox);
        eng_mat4_t ident = eng_mat4_identity();
        eng_shader_set_mat4(&r->sh_skybox, "u_inv_vp", &ident);
        gl->BindVertexArray(r->fs_vao);
        gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);

        /* 3. Render destination pocket through virtual oblique camera */
        r->stats.portal_views++;
        eng_vec3_t virt_cam_pos = eng_mat4_transform_point(&warp, cam_pos);
        render_pocket_recursive(r, scene, portals, p->dst_pocket, &virt_view, &oblique_proj,
                                virt_cam_pos, vp_rect, child_sc, depth + 1, p->dst_ent, root_light_vp, false);

        /* 4. Restore stencil (depth + 1 -> depth) and seal doorway depth in parent pocket */
        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
        gl->Viewport(vp_rect[0], vp_rect[1], vp_rect[2], vp_rect[3]);
        gl->Scissor(child_sc[0], child_sc[1], child_sc[2], child_sc[3]);
        gl->ColorMask(ENG_GL_FALSE, ENG_GL_FALSE, ENG_GL_FALSE, ENG_GL_FALSE);
        gl->DepthMask(ENG_GL_TRUE);
        gl->DepthFunc(ENG_GL_ALWAYS);
        gl->Disable(ENG_GL_CULL_FACE);
        gl->StencilMask(0xFFu);
        gl->StencilFunc(ENG_GL_EQUAL, depth + 1, 0xFFu);
        gl->StencilOp(ENG_GL_KEEP, ENG_GL_KEEP, ENG_GL_DECR);
        eng_shader_bind(&r->sh_shadow);
        eng_shader_set_mat4(&r->sh_shadow, "u_vp", &vp);
        draw_single_mesh_xform(r, r->portal_quad_mesh, &cap_world);

        gl->ColorMask(ENG_GL_TRUE, ENG_GL_TRUE, ENG_GL_TRUE, ENG_GL_TRUE);
        gl->StencilMask(0x00u);
        gl->DepthFunc(ENG_GL_LESS);
        gl->Enable(ENG_GL_CULL_FACE);
        gl->Scissor(scissor_rect[0], scissor_rect[1], scissor_rect[2], scissor_rect[3]);
    }
}

void eng_renderer_render_views(eng_renderer_t *r, const eng_scene_t *scene,
                               const eng_portal_sys_t *portals,
                               const eng_viewport_t *views, int view_count,
                               const eng_xr_t *xr) {
    if (!r || !views || view_count <= 0) return;
    if (view_count > ENG_MAX_VIEWPORTS) view_count = ENG_MAX_VIEWPORTS;
    const eng_gl_api_t *gl = eng_gl();
    gl->Disable(ENG_GL_BLEND);

    /* Clear HDR + Depth + Stencil FBO once before viewport/eye loop */
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
    gl->Viewport(0, 0, r->width, r->height);
    gl->Disable(ENG_GL_SCISSOR_TEST);
    gl->Disable(ENG_GL_STENCIL_TEST);
    gl->ColorMask(ENG_GL_TRUE, ENG_GL_TRUE, ENG_GL_TRUE, ENG_GL_TRUE);
    gl->DepthMask(ENG_GL_TRUE);
    gl->StencilMask(0xFFu);
    gl->ClearColor(r->sky_horizon.x, r->sky_horizon.y, r->sky_horizon.z, 1.0f);
    gl->ClearStencil(0);
    gl->Clear(ENG_GL_COLOR_BUFFER_BIT | ENG_GL_DEPTH_BUFFER_BIT | ENG_GL_STENCIL_BUFFER_BIT);

    bool xr_on = (xr != NULL && eng_xr_is_active(xr));
    int pass_count = xr_on ? 2 : view_count;
    GLuint dst_fbo = xr_on ? eng_xr_framebuffer(xr) : 0u;

    eng_mat4_t light_vp;
    bool has_shadow = false;
    if (xr_on) {
        has_shadow = render_shadow_map(r, views[0].cam.pocket_id, views[0].cam.pos, &light_vp);
        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
    }

    for (int pass = 0; pass < pass_count; pass++) {
        const eng_camera_t *cam = &views[xr_on ? 0 : pass].cam;
        eng_mat4_t view, proj;
        int vp_rect[4] = {0, 0, r->width, r->height};
        eng_vec3_t eye_pos = cam->pos;

        if (xr_on) {
            const eng_xr_eye_t *xe = eng_xr_get_eye(xr, pass);
            if (!xe) continue;
            view = xe->view;
            proj = xe->proj;
            memcpy(vp_rect, xe->viewport, sizeof(vp_rect));
            if (vp_rect[2] <= 0 || vp_rect[3] <= 0) {
                vp_rect[0] = (pass == 0) ? 0 : (r->width / 2);
                vp_rect[1] = 0;
                vp_rect[2] = r->width / 2;
                vp_rect[3] = r->height;
            }
            eng_mat4_t inv_v;
            if (eng_mat4_invert(&view, &inv_v)) {
                eye_pos = eng_v3(inv_v.m[12], inv_v.m[13], inv_v.m[14]);
            }
        } else {
            const float *nr = views[pass].norm_rect;
            vp_rect[0] = (int)floorf(nr[0] * (float)r->width + 0.5f);
            vp_rect[1] = (int)floorf(nr[1] * (float)r->height + 0.5f);
            vp_rect[2] = (int)floorf(nr[2] * (float)r->width + 0.5f);
            vp_rect[3] = (int)floorf(nr[3] * (float)r->height + 0.5f);
            if (vp_rect[2] <= 0 || vp_rect[3] <= 0) continue;

            has_shadow = render_shadow_map(r, cam->pocket_id, cam->pos, &light_vp);
            gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);

            eng_vec3_t fwd = eng_quat_rotate_v3(cam->rot, eng_v3(0.0f, 0.0f, -1.0f));
            eng_vec3_t up = eng_quat_rotate_v3(cam->rot, eng_v3(0.0f, 1.0f, 0.0f));
            view = eng_mat4_look_at(cam->pos, eng_v3_add(cam->pos, fwd), up);
            float aspect = (float)vp_rect[2] / (float)vp_rect[3];
            float fov_y = cam->fov_y_deg * ENG_DEG2RAD;
            if (aspect < 1.0f) {
                fov_y = 2.0f * atanf(tanf(fov_y * 0.5f) / fmaxf(aspect, 0.55f));
                if (fov_y > 105.0f * ENG_DEG2RAD) fov_y = 105.0f * ENG_DEG2RAD;
            }
            proj = eng_mat4_perspective(fov_y, aspect, cam->z_near, cam->z_far);
        }

        render_pocket_recursive(r, scene, portals, cam->pocket_id, &view, &proj,
                                eye_pos, vp_rect, vp_rect, 0, ENG_ENTITY_NULL, &light_vp, has_shadow);
    }

    /* Draw crisp 2px dark divider lines between split-screen viewports */
    if (!xr_on && view_count > 1) {
        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
        gl->Enable(ENG_GL_SCISSOR_TEST);
        gl->Disable(ENG_GL_STENCIL_TEST);
        gl->Disable(ENG_GL_DEPTH_TEST);
        gl->ClearColor(0.03f, 0.04f, 0.07f, 1.0f);
        for (int i = 0; i < view_count; i++) {
            const float *nr = views[i].norm_rect;
            if (nr[0] > 0.01f) {
                int sx = (int)(nr[0] * (float)r->width) - 1;
                gl->Scissor(sx > 0 ? sx : 0, (int)(nr[1] * (float)r->height), 2, (int)(nr[3] * (float)r->height));
                gl->Clear(ENG_GL_COLOR_BUFFER_BIT);
            }
            if (nr[1] > 0.01f) {
                int sy = (int)(nr[1] * (float)r->height) - 1;
                gl->Scissor((int)(nr[0] * (float)r->width), sy > 0 ? sy : 0, (int)(nr[2] * (float)r->width), 2);
                gl->Clear(ENG_GL_COLOR_BUFFER_BIT);
            }
        }
    }

    /* Post-Processing: Dual-Kawase Bloom + ACES Tonemap + Bayer Dither + CRT */
    gl->Disable(ENG_GL_SCISSOR_TEST);
    gl->Disable(ENG_GL_STENCIL_TEST);
    gl->Disable(ENG_GL_DEPTH_TEST);
    gl->DepthMask(ENG_GL_FALSE);
    gl->BindVertexArray(r->fs_vao);
    eng_shader_bind(&r->sh_post);

    int bw = r->width > 1 ? r->width / 2 : 1;
    int bh = r->height > 1 ? r->height / 2 : 1;
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->bloom_fbo);
    gl->Viewport(0, 0, bw, bh);
    gl->ActiveTexture(ENG_GL_TEXTURE0);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->hdr_color_tex);
    eng_shader_set_int(&r->sh_post, "u_hdr_tex", 0);
    eng_shader_set_v3(&r->sh_post, "u_inv_res", eng_v3(1.0f / (float)r->width, 1.0f / (float)r->height, 0.0f));
    eng_shader_set_int(&r->sh_post, "u_pass_mode", 0);
    gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);

    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, dst_fbo);
    gl->Viewport(0, 0, r->width, r->height);
    gl->ActiveTexture(ENG_GL_TEXTURE0);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->hdr_color_tex);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->bloom_tex);
    eng_shader_set_int(&r->sh_post, "u_hdr_tex", 0);
    eng_shader_set_int(&r->sh_post, "u_bloom_tex", 1);
    eng_shader_set_int(&r->sh_post, "u_pass_mode", 1);
    eng_shader_set_float(&r->sh_post, "u_bloom_amt", r->retro.bloom_intensity);
    eng_shader_set_int(&r->sh_post, "u_dither_bayer", r->retro.dither_bayer ? 1 : 0);
    float levels = (r->retro.color_bits > 0 && r->retro.color_bits < 8)
                       ? (float)((1 << r->retro.color_bits) - 1)
                       : 0.0f;
    eng_shader_set_float(&r->sh_post, "u_color_levels", levels);
    eng_shader_set_float(&r->sh_post, "u_crt_scanline", r->retro.crt_scanlines);
    gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);
}

void eng_renderer_render_frame(eng_renderer_t *r, const eng_scene_t *scene,
                               const eng_portal_sys_t *portals,
                               const eng_camera_t *cam, const eng_xr_t *xr) {
    if (!r || !cam) return;
    eng_viewport_t v = {*cam, {0.0f, 0.0f, 1.0f, 1.0f}};
    eng_renderer_render_views(r, scene, portals, &v, 1, xr);
}

bool eng_renderer_read_pixels(const eng_renderer_t *r, uint8_t *out_rgba_bottom_up, int w, int h) {
    if (!r || !out_rgba_bottom_up || w <= 0 || h <= 0 || w > r->width || h > r->height) return false;
    const eng_gl_api_t *gl = eng_gl();
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, 0);
    gl->ReadPixels(0, 0, w, h, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, out_rgba_bottom_up);
    return true;
}

eng_render_stats_t eng_renderer_stats(const eng_renderer_t *r) {
    eng_render_stats_t empty;
    memset(&empty, 0, sizeof(empty));
    return r ? r->stats : empty;
}
