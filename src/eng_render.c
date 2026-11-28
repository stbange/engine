#include "engine/eng_render.h"
#include "engine/eng_log.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_LIGHTS 32
#define ENG_SHADOW_RES 2048

typedef struct {
    uint32_t item_idx;
    uint32_t mesh_id;
    uint32_t tex_id;
    uint8_t lod;
    float cam_dist;
} vis_draw_t;

typedef struct {
    bool active;
    uint16_t pocket_id;
    eng_sky_config_t cfg;
} pocket_sky_entry_t;

typedef struct {
    bool active;
    uint16_t pocket_id;
    eng_water_cfg_t cfg;
} pocket_water_entry_t;

struct eng_renderer_s {
    eng_vfs_t *vfs;
    eng_asset_cache_t *assets;
    int width;
    int height;
    int internal_w;
    int internal_h;

    eng_pipeline_mode_t pipeline;
    eng_retro_cfg_t retro;
    eng_sky_config_t sky;
    pocket_sky_entry_t pocket_skies[ENG_MAX_POCKET_SKIES];
    pocket_water_entry_t pocket_waters[ENG_MAX_POCKET_WATERS];
    float time;
    eng_vec3_t ambient;
    int max_portal_depth;

    eng_shader_t sh_forward;
    eng_shader_t sh_gbuffer;
    eng_shader_t sh_def_light;
    eng_shader_t sh_shadow;
    eng_shader_t sh_skybox;
    eng_shader_t sh_water;
    eng_shader_t sh_post;

    GLuint fs_vao;
    GLuint fs_vbo;
    GLuint sp_vao;
    GLuint sp_vbo;
    GLuint sp_ebo;
    GLuint sp_inst_vbo;
    uint32_t portal_cap_mesh;
    uint32_t portal_quad_mesh;
    uint32_t water_grid_mesh;
    uint32_t soft_particle_tex;
    GLuint fallback_white_tex;
    GLuint fallback_norm_tex;
    GLuint fallback_cube_tex;

    GLuint hdr_fbo;
    GLuint hdr_color_tex;
    GLuint hdr_ds_tex;
    GLuint scene_snap_fbo;
    GLuint scene_color_tex;
    GLuint scene_ds_tex;
    GLuint bloom_fbo;
    GLuint bloom_tex;
    GLuint gbuf_fbo;
    GLuint gb_albedo_tex;
    GLuint gb_norm_tex;
    GLuint gb_pos_tex;
    GLuint shadow_fbo;
    GLuint shadow_tex;
    GLuint cap_fbo;
    GLuint cap_color_tex;

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

eng_sky_config_t eng_sky_default(void) {
    eng_sky_config_t s;
    memset(&s, 0, sizeof(s));
    s.zenith = eng_v3(0.14f, 0.34f, 0.72f);
    s.horizon = eng_v3(0.62f, 0.76f, 0.92f);
    s.ground = eng_v3(0.18f, 0.16f, 0.14f);
    s.sun_color = eng_v3(1.0f, 0.92f, 0.72f);
    s.sun_glow = 1.5f;
    s.cloud_speed = 0.04f;
    s.cloud_scale = 2.4f;
    s.cloud_color = eng_v3(0.98f, 0.98f, 1.0f);
    s.star_scale = 140.0f;
    return s;
}

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
        .bloom_intensity = 0.25f,
        .render_scale = 1.0f,
        .pixel_height = 0,
        .sharp_upscale = 0,
        .ssao_intensity = 0.0f,
        .volumetric_fog = 0.0f,
        .fog_sun_scatter = 0.45f
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
        .bloom_intensity = 0.10f,
        .render_scale = 1.0f,
        .pixel_height = 0,
        .sharp_upscale = 0,
        .ssao_intensity = 0.0f,
        .volumetric_fog = 0.0f,
        .fog_sun_scatter = 0.25f
    };
}

eng_retro_cfg_t eng_retro_lowres_realism_preset(void) {
    return (eng_retro_cfg_t){
        .vertex_snap_res = 0.0f,
        .nearest_textures = false,
        .dither_bayer = true,
        .color_bits = 8,
        .fog_density = 0.012f,
        .fog_color = {0.54f, 0.64f, 0.76f},
        .fog_height = 6.5f,
        .crt_scanlines = 0.0f,
        .bloom_intensity = 0.30f,
        .render_scale = 0.5f,
        .pixel_height = 360,
        .sharp_upscale = 1,
        .ssao_intensity = 0.65f,
        .volumetric_fog = 0.55f,
        .fog_sun_scatter = 0.65f
    };
}

eng_water_cfg_t eng_water_default(void) {
    return (eng_water_cfg_t){
        .enabled = true,
        .level_y = 0.0f,
        .size_x = 240.0f,
        .size_z = 240.0f,
        .center_x = 0.0f,
        .center_z = 0.0f,
        .follow_camera = true,
        .wave_amp = 0.14f,
        .wave_freq = 0.55f,
        .choppiness = 0.65f,
        .wind_dir = {0.8f, 0.6f},
        .flow_speed = 0.65f,
        .absorb_rgb = {0.42f, 0.09f, 0.04f},
        .scatter_rgb = {0.03f, 0.16f, 0.20f},
        .roughness = 0.06f,
        .foam_width = 0.45f,
        .refract_strength = 0.035f,
        .caustics = 0.45f
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

static void compute_internal_dims(const eng_renderer_t *r, int out_w, int out_h, int *out_iw, int *out_ih) {
    int iw = out_w > 0 ? out_w : 640;
    int ih = out_h > 0 ? out_h : 480;
    if (r->retro.pixel_height > 0 && r->retro.pixel_height < ih) {
        ih = r->retro.pixel_height;
        iw = (int)floorf((float)out_w * ((float)ih / (float)(out_h > 0 ? out_h : 1)) + 0.5f);
    } else if (r->retro.render_scale > 0.05f && r->retro.render_scale < 0.995f) {
        iw = (int)floorf((float)iw * r->retro.render_scale + 0.5f);
        ih = (int)floorf((float)ih * r->retro.render_scale + 0.5f);
    }
    if (iw < 2) iw = 2;
    if (ih < 2) ih = 2;
    *out_iw = iw;
    *out_ih = ih;
}

static void destroy_scene_targets(eng_renderer_t *r) {
    const eng_gl_api_t *gl = eng_gl();
    GLuint fbos[4] = {r->hdr_fbo, r->scene_snap_fbo, r->bloom_fbo, r->gbuf_fbo};
    GLuint texs[8] = {
        r->hdr_color_tex, r->hdr_ds_tex, r->scene_color_tex, r->scene_ds_tex,
        r->bloom_tex, r->gb_albedo_tex, r->gb_norm_tex, r->gb_pos_tex
    };
    for (int i = 0; i < 4; i++) {
        if (fbos[i]) gl->DeleteFramebuffers(1, &fbos[i]);
    }
    for (int i = 0; i < 8; i++) {
        if (texs[i]) gl->DeleteTextures(1, &texs[i]);
    }
    r->hdr_fbo = r->scene_snap_fbo = r->bloom_fbo = r->gbuf_fbo = 0;
    r->hdr_color_tex = r->hdr_ds_tex = r->scene_color_tex = r->scene_ds_tex = 0;
    r->bloom_tex = r->gb_albedo_tex = r->gb_norm_tex = r->gb_pos_tex = 0;
}

static bool create_scene_targets(eng_renderer_t *r, int iw, int ih) {
    const eng_gl_api_t *gl = eng_gl();
    destroy_scene_targets(r);
    r->internal_w = iw > 1 ? iw : 2;
    r->internal_h = ih > 1 ? ih : 2;

    GLint hdr_ifmt = gl->is_gles ? ENG_GL_RGBA8 : ENG_GL_RGBA16F;
    GLenum hdr_type = gl->is_gles ? ENG_GL_UNSIGNED_BYTE : ENG_GL_FLOAT;

    r->hdr_color_tex = make_tex2d(r->internal_w, r->internal_h, hdr_ifmt, ENG_GL_RGBA, hdr_type, ENG_GL_LINEAR);
    r->hdr_ds_tex = make_tex2d(r->internal_w, r->internal_h, ENG_GL_DEPTH24_STENCIL8,
                               ENG_GL_DEPTH_STENCIL, ENG_GL_UNSIGNED_INT_24_8, ENG_GL_NEAREST);
    gl->GenFramebuffers(1, &r->hdr_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT0, ENG_GL_TEXTURE_2D, r->hdr_color_tex, 0);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_DEPTH_STENCIL_ATTACHMENT, ENG_GL_TEXTURE_2D, r->hdr_ds_tex, 0);
    GLenum hdr_st = gl->CheckFramebufferStatus(ENG_GL_FRAMEBUFFER);
    if (hdr_st != ENG_GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "[render] hdr_fbo incomplete: 0x%x (%dx%d)\n", hdr_st, r->internal_w, r->internal_h);
        return false;
    }

    r->scene_color_tex = make_tex2d(r->internal_w, r->internal_h, hdr_ifmt, ENG_GL_RGBA, hdr_type, ENG_GL_LINEAR);
    r->scene_ds_tex = make_tex2d(r->internal_w, r->internal_h, ENG_GL_DEPTH24_STENCIL8,
                                 ENG_GL_DEPTH_STENCIL, ENG_GL_UNSIGNED_INT_24_8, ENG_GL_NEAREST);
    gl->GenFramebuffers(1, &r->scene_snap_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->scene_snap_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT0, ENG_GL_TEXTURE_2D, r->scene_color_tex, 0);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_DEPTH_STENCIL_ATTACHMENT, ENG_GL_TEXTURE_2D, r->scene_ds_tex, 0);

    int bw = r->internal_w > 1 ? r->internal_w / 2 : 1;
    int bh = r->internal_h > 1 ? r->internal_h / 2 : 1;
    r->bloom_tex = make_tex2d(bw, bh, hdr_ifmt, ENG_GL_RGBA, hdr_type, ENG_GL_LINEAR);
    gl->GenFramebuffers(1, &r->bloom_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->bloom_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT0, ENG_GL_TEXTURE_2D, r->bloom_tex, 0);

    r->gb_albedo_tex = make_tex2d(r->internal_w, r->internal_h, ENG_GL_RGBA8, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, ENG_GL_NEAREST);
    r->gb_norm_tex = make_tex2d(r->internal_w, r->internal_h, ENG_GL_RGBA8, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, ENG_GL_NEAREST);
    r->gb_pos_tex = make_tex2d(r->internal_w, r->internal_h, hdr_ifmt, ENG_GL_RGBA, hdr_type, ENG_GL_NEAREST);
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
        r->gb_pos_tex = make_tex2d(r->internal_w, r->internal_h, ENG_GL_RGBA8, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, ENG_GL_NEAREST);
        gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT2, ENG_GL_TEXTURE_2D, r->gb_pos_tex, 0);
    }

    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, 0);
    return true;
}

static bool sync_internal_targets(eng_renderer_t *r, bool force_native) {
    int iw = r->width, ih = r->height;
    if (!force_native) compute_internal_dims(r, r->width, r->height, &iw, &ih);
    if (iw == r->internal_w && ih == r->internal_h && r->hdr_fbo != 0) return true;
    return create_scene_targets(r, iw, ih);
}

bool eng_renderer_reload_shaders(eng_renderer_t *r) {
    if (!r || !r->vfs) return false;
    bool ok = true;
    ok &= eng_shader_load_vfs(&r->sh_forward, r->vfs, "shaders/forward.vert", "shaders/forward.frag");
    (void)eng_shader_load_vfs(&r->sh_gbuffer, r->vfs, "shaders/gbuffer.vert", "shaders/gbuffer.frag");
    (void)eng_shader_load_vfs(&r->sh_def_light, r->vfs, "shaders/post.vert", "shaders/deferred_light.frag");
    ok &= eng_shader_load_vfs(&r->sh_shadow, r->vfs, "shaders/shadow.vert", "shaders/shadow.frag");
    ok &= eng_shader_load_vfs(&r->sh_skybox, r->vfs, "shaders/skybox.vert", "shaders/skybox.frag");
    ok &= eng_shader_load_vfs(&r->sh_water, r->vfs, "shaders/water.vert", "shaders/water.frag");
    ok &= eng_shader_load_vfs(&r->sh_post, r->vfs, "shaders/post.vert", "shaders/post.frag");
    return ok;
}

static uint32_t build_water_grid_mesh(eng_asset_cache_t *assets, int subdiv) {
    eng_mesh_data_t md;
    eng_mesh_data_init(&md);
    int vx_n = subdiv + 1;
    md.vert_cap = (size_t)(vx_n * vx_n);
    md.idx_cap = (size_t)(subdiv * subdiv * 6);
    md.verts = (eng_vertex_t *)calloc(md.vert_cap, sizeof(eng_vertex_t));
    md.indices = (uint32_t *)malloc(md.idx_cap * sizeof(uint32_t));
    if (!md.verts || !md.indices) { eng_mesh_data_free(&md); return 0; }

    for (int z = 0; z < vx_n; z++) {
        for (int x = 0; x < vx_n; x++) {
            eng_vertex_t *v = &md.verts[md.vert_count++];
            v->pos[0] = (float)x / (float)subdiv - 0.5f;
            v->pos[1] = 0.0f;
            v->pos[2] = (float)z / (float)subdiv - 0.5f;
            v->norm[1] = 1.0f;
            v->uv[0] = (float)x / (float)subdiv;
            v->uv[1] = (float)z / (float)subdiv;
            v->color[0] = v->color[1] = v->color[2] = v->color[3] = 1.0f;
        }
    }
    for (int z = 0; z < subdiv; z++) {
        for (int x = 0; x < subdiv; x++) {
            uint32_t i0 = (uint32_t)(z * vx_n + x);
            uint32_t i1 = i0 + 1u;
            uint32_t i2 = i0 + (uint32_t)vx_n;
            uint32_t i3 = i2 + 1u;
            md.indices[md.idx_count++] = i0; md.indices[md.idx_count++] = i2; md.indices[md.idx_count++] = i1;
            md.indices[md.idx_count++] = i1; md.indices[md.idx_count++] = i2; md.indices[md.idx_count++] = i3;
        }
    }
    uint32_t id = eng_asset_upload_mesh(assets, "__water_grid", &md);
    eng_mesh_data_free(&md);
    return id;
}

eng_renderer_t *eng_renderer_create(eng_vfs_t *vfs, eng_asset_cache_t *assets, int width, int height) {
    if (!vfs || !assets) return NULL;
    eng_renderer_t *r = (eng_renderer_t *)calloc(1, sizeof(eng_renderer_t));
    if (!r) return NULL;

    r->vfs = vfs;
    r->assets = assets;
    r->width = width > 0 ? width : 640;
    r->height = height > 0 ? height : 480;
    r->pipeline = ENG_PIPELINE_FORWARD;
    r->retro = eng_retro_default();
    r->sky = eng_sky_default();
    r->ambient = eng_v3(0.16f, 0.18f, 0.22f);
    r->max_portal_depth = 2;

    const eng_gl_api_t *gl = eng_gl();
    r->shadow_tex = make_tex2d(ENG_SHADOW_RES, ENG_SHADOW_RES, ENG_GL_DEPTH_COMPONENT24,
                               ENG_GL_DEPTH_COMPONENT, ENG_GL_UNSIGNED_INT, ENG_GL_NEAREST);
    gl->GenFramebuffers(1, &r->shadow_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->shadow_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_DEPTH_ATTACHMENT, ENG_GL_TEXTURE_2D, r->shadow_tex, 0);
    const GLenum none_buf = 0;
    gl->DrawBuffers(1, &none_buf);
    gl->ReadBuffer(0);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, 0);

    if (!eng_renderer_reload_shaders(r) || !sync_internal_targets(r, false)) {
        eng_renderer_destroy(r);
        return NULL;
    }

    static const uint8_t px_white[4] = {255, 255, 255, 255};
    gl->GenTextures(1, &r->fallback_white_tex);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->fallback_white_tex);
    gl->TexImage2D(ENG_GL_TEXTURE_2D, 0, ENG_GL_RGBA8, 1, 1, 0, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, px_white);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MIN_FILTER, ENG_GL_NEAREST);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MAG_FILTER, ENG_GL_NEAREST);

    static const uint8_t px_flat_norm[4] = {128, 128, 255, 128};
    gl->GenTextures(1, &r->fallback_norm_tex);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->fallback_norm_tex);
    gl->TexImage2D(ENG_GL_TEXTURE_2D, 0, ENG_GL_RGBA8, 1, 1, 0, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, px_flat_norm);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MIN_FILTER, ENG_GL_NEAREST);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MAG_FILTER, ENG_GL_NEAREST);

    static const uint8_t px_black[4] = {0, 0, 0, 255};
    gl->GenTextures(1, &r->fallback_cube_tex);
    gl->BindTexture(ENG_GL_TEXTURE_CUBE_MAP, r->fallback_cube_tex);
    for (int f = 0; f < 6; f++) {
        gl->TexImage2D(ENG_GL_TEXTURE_CUBE_MAP_POSITIVE_X + (GLenum)f, 0, ENG_GL_RGBA8,
                       1, 1, 0, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, px_black);
    }
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_MIN_FILTER, ENG_GL_NEAREST);
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_MAG_FILTER, ENG_GL_NEAREST);
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_WRAP_S, ENG_GL_CLAMP_TO_EDGE);
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_WRAP_T, ENG_GL_CLAMP_TO_EDGE);
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_WRAP_R, ENG_GL_CLAMP_TO_EDGE);

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

    /* Unit portal inverted near-plane cap, doorway quad & subdivided Gerstner water sheet */
    eng_mesh_data_t cap_md, quad_md;
    eng_mesh_data_init(&cap_md);
    eng_mesh_append_box(&cap_md, eng_v3(0.0f, 0.0f, 0.125f), eng_v3(2.0f, 2.0f, 0.25f), (eng_vec4_t){1, 1, 1, 1});
    r->portal_cap_mesh = eng_asset_upload_mesh(assets, "__portal_cap", &cap_md);
    eng_mesh_data_free(&cap_md);

    eng_mesh_data_init(&quad_md);
    eng_mesh_append_box(&quad_md, eng_v3(0.0f, 0.0f, 0.0f), eng_v3(2.0f, 2.0f, 0.002f), (eng_vec4_t){1, 1, 1, 1});
    r->portal_quad_mesh = eng_asset_upload_mesh(assets, "__portal_quad", &quad_md);
    eng_mesh_data_free(&quad_md);

    r->water_grid_mesh = build_water_grid_mesh(assets, 48);

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
    destroy_scene_targets(r);
    if (r->shadow_fbo) gl->DeleteFramebuffers(1, &r->shadow_fbo);
    if (r->shadow_tex) gl->DeleteTextures(1, &r->shadow_tex);
    eng_shader_destroy(&r->sh_forward);
    eng_shader_destroy(&r->sh_gbuffer);
    eng_shader_destroy(&r->sh_def_light);
    eng_shader_destroy(&r->sh_shadow);
    eng_shader_destroy(&r->sh_skybox);
    eng_shader_destroy(&r->sh_water);
    eng_shader_destroy(&r->sh_post);
    if (r->fallback_white_tex) gl->DeleteTextures(1, &r->fallback_white_tex);
    if (r->fallback_norm_tex) gl->DeleteTextures(1, &r->fallback_norm_tex);
    if (r->fallback_cube_tex) gl->DeleteTextures(1, &r->fallback_cube_tex);
    if (r->cap_fbo) gl->DeleteFramebuffers(1, &r->cap_fbo);
    if (r->cap_color_tex) gl->DeleteTextures(1, &r->cap_color_tex);
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
    r->width = width;
    r->height = height;
    return sync_internal_targets(r, false);
}

static const eng_sky_config_t *resolve_sky(const eng_renderer_t *r, uint16_t pocket_id) {
    for (int i = 0; i < ENG_MAX_POCKET_SKIES; i++) {
        if (r->pocket_skies[i].active && r->pocket_skies[i].pocket_id == pocket_id) {
            return &r->pocket_skies[i].cfg;
        }
    }
    return &r->sky;
}

static const eng_water_cfg_t *resolve_water(const eng_renderer_t *r, uint16_t pocket_id) {
    for (int i = 0; i < ENG_MAX_POCKET_WATERS; i++) {
        if (r->pocket_waters[i].active && r->pocket_waters[i].pocket_id == pocket_id && r->pocket_waters[i].cfg.enabled) {
            return &r->pocket_waters[i].cfg;
        }
    }
    return NULL;
}

void eng_renderer_set_pipeline(eng_renderer_t *r, eng_pipeline_mode_t mode) { if (r) r->pipeline = mode; }
eng_pipeline_mode_t eng_renderer_get_pipeline(const eng_renderer_t *r) { return r ? r->pipeline : ENG_PIPELINE_FORWARD; }
void eng_renderer_set_retro(eng_renderer_t *r, const eng_retro_cfg_t *cfg) {
    if (!r || !cfg) return;
    r->retro = *cfg;
    (void)sync_internal_targets(r, false);
}
eng_retro_cfg_t eng_renderer_get_retro(const eng_renderer_t *r) { return r ? r->retro : eng_retro_default(); }

bool eng_renderer_set_water(eng_renderer_t *r, uint16_t pocket_id, const eng_water_cfg_t *cfg) {
    if (!r) return false;
    if (!cfg || !cfg->enabled) {
        for (int i = 0; i < ENG_MAX_POCKET_WATERS; i++) {
            if (r->pocket_waters[i].active && r->pocket_waters[i].pocket_id == pocket_id) {
                r->pocket_waters[i].active = false;
                r->pocket_waters[i].cfg.enabled = false;
            }
        }
        return true;
    }
    int slot = -1;
    for (int i = 0; i < ENG_MAX_POCKET_WATERS; i++) {
        if (r->pocket_waters[i].active && r->pocket_waters[i].pocket_id == pocket_id) { slot = i; break; }
        if (!r->pocket_waters[i].active && slot < 0) slot = i;
    }
    if (slot < 0) return false;
    r->pocket_waters[slot].active = true;
    r->pocket_waters[slot].pocket_id = pocket_id;
    r->pocket_waters[slot].cfg = *cfg;
    return true;
}

eng_water_cfg_t eng_renderer_get_water(const eng_renderer_t *r, uint16_t pocket_id) {
    if (r) {
        for (int i = 0; i < ENG_MAX_POCKET_WATERS; i++) {
            if (r->pocket_waters[i].active && r->pocket_waters[i].pocket_id == pocket_id) {
                return r->pocket_waters[i].cfg;
            }
        }
    }
    eng_water_cfg_t off = eng_water_default();
    off.enabled = false;
    return off;
}

float eng_renderer_sample_water_height(const eng_renderer_t *r, uint16_t pocket_id, float x, float z, bool *out_enabled) {
    const eng_water_cfg_t *w = r ? resolve_water(r, pocket_id) : NULL;
    if (out_enabled) *out_enabled = (w != NULL);
    if (!w) return -1e6f;
    if (!w->follow_camera && w->size_x > 0.0f && w->size_z > 0.0f) {
        if (fabsf(x - w->center_x) > w->size_x * 0.5f || fabsf(z - w->center_z) > w->size_z * 0.5f) {
            if (out_enabled) *out_enabled = false;
            return -1e6f;
        }
    }
    float y = w->level_y;
    if (w->wave_amp > 0.0005f) {
        float freq = fmaxf(w->wave_freq, 0.05f);
        float c0 = sqrtf(9.81f * freq);
        float wx = w->wind_dir.x, wz = w->wind_dir.y;
        float wlen = sqrtf(wx * wx + wz * wz);
        if (wlen > 0.01f) { wx /= wlen; wz /= wlen; } else { wx = 0.8f; wz = 0.6f; }
        float dirs[4][2] = {
            {wx, wz},
            {wx * 0.82f - wz * 0.57f, wx * 0.57f + wz * 0.82f},
            {wx * 0.64f + wz * 0.77f, -wx * 0.77f + wz * 0.64f},
            {-wz, wx}
        };
        const float amps[4] = {0.50f, 0.26f, 0.15f, 0.09f};
        const float freqs[4] = {1.00f, 1.73f, 2.85f, 4.30f};
        const float spds[4] = {1.00f, 1.31f, 1.68f, 2.07f};
        for (int k = 0; k < 4; k++) {
            float ph = (dirs[k][0] * x + dirs[k][1] * z) * (freq * freqs[k]) + r->time * (c0 * spds[k]);
            y += w->wave_amp * amps[k] * sinf(ph);
        }
    }
    return y;
}

void eng_renderer_set_sky(eng_renderer_t *r, eng_vec3_t z, eng_vec3_t h, eng_vec3_t g) {
    if (r) { r->sky.zenith = z; r->sky.horizon = h; r->sky.ground = g; }
}
void eng_renderer_set_sky_fx(eng_renderer_t *r, const eng_sky_config_t *cfg) {
    if (!r || !cfg) return;
    r->sky = *cfg;
    if (r->sky.parallax_count < 0) r->sky.parallax_count = 0;
    if (r->sky.parallax_count > ENG_MAX_PARALLAX_LAYERS) r->sky.parallax_count = ENG_MAX_PARALLAX_LAYERS;
}
eng_sky_config_t eng_renderer_get_sky_fx(const eng_renderer_t *r) {
    return r ? r->sky : eng_sky_default();
}
bool eng_renderer_set_pocket_sky(eng_renderer_t *r, uint16_t pocket_id, const eng_sky_config_t *cfg) {
    if (!r || !cfg) return false;
    int slot = -1;
    for (int i = 0; i < ENG_MAX_POCKET_SKIES; i++) {
        if (r->pocket_skies[i].active && r->pocket_skies[i].pocket_id == pocket_id) { slot = i; break; }
        if (!r->pocket_skies[i].active && slot < 0) slot = i;
    }
    if (slot < 0) return false;
    r->pocket_skies[slot].active = true;
    r->pocket_skies[slot].pocket_id = pocket_id;
    r->pocket_skies[slot].cfg = *cfg;
    if (r->pocket_skies[slot].cfg.parallax_count < 0) r->pocket_skies[slot].cfg.parallax_count = 0;
    if (r->pocket_skies[slot].cfg.parallax_count > ENG_MAX_PARALLAX_LAYERS) {
        r->pocket_skies[slot].cfg.parallax_count = ENG_MAX_PARALLAX_LAYERS;
    }
    return true;
}
eng_sky_config_t eng_renderer_get_pocket_sky(const eng_renderer_t *r, uint16_t pocket_id) {
    return r ? *resolve_sky(r, pocket_id) : eng_sky_default();
}
void eng_renderer_clear_pocket_sky(eng_renderer_t *r, uint16_t pocket_id) {
    if (!r) return;
    for (int i = 0; i < ENG_MAX_POCKET_SKIES; i++) {
        if (r->pocket_skies[i].active && r->pocket_skies[i].pocket_id == pocket_id) {
            r->pocket_skies[i].active = false;
        }
    }
}
void eng_renderer_set_parallax(eng_renderer_t *r, uint16_t pocket_id, bool per_pocket,
                               const eng_parallax_layer_t *layers, int count) {
    if (!r) return;
    eng_sky_config_t cfg = per_pocket ? *resolve_sky(r, pocket_id) : r->sky;
    int n = (layers && count > 0) ? (count > ENG_MAX_PARALLAX_LAYERS ? ENG_MAX_PARALLAX_LAYERS : count) : 0;
    memset(cfg.parallax, 0, sizeof(cfg.parallax));
    for (int i = 0; i < n; i++) cfg.parallax[i] = layers[i];
    cfg.parallax_count = n;
    if (per_pocket) eng_renderer_set_pocket_sky(r, pocket_id, &cfg);
    else r->sky = cfg;
}
void eng_renderer_set_time(eng_renderer_t *r, float time_sec) { if (r) r->time = time_sec; }
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

static eng_vec3_t resolve_sun_dir(const eng_renderer_t *r, uint16_t pocket_id, const eng_sky_config_t *sky) {
    eng_vec3_t sun_dir = sky->sun_dir;
    if (eng_v3_len(sun_dir) < 0.001f) {
        sun_dir = eng_v3(-0.4f, -0.8f, -0.4f);
        for (size_t li = 0; li < r->light_count; li++) {
            if (r->lights[li].pocket_id == pocket_id && r->lights[li].type == ENG_LIGHT_DIR) {
                sun_dir = r->lights[li].dir;
                break;
            }
        }
    }
    return sun_dir;
}

static void upload_lights_and_env(const eng_shader_t *sh, const eng_renderer_t *r, uint16_t pocket_id,
                                  eng_vec3_t cam_pos, float z_near, float z_far,
                                  const eng_mat4_t *light_vp, bool has_shadow) {
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
    const eng_sky_config_t *sky = resolve_sky(r, pocket_id);
    eng_vec3_t sun_dir = resolve_sun_dir(r, pocket_id, sky);
    eng_vec3_t to_sun = eng_v3_norm(eng_v3_scale(sun_dir, -1.0f));
    if (eng_v3_dot(to_sun, to_sun) < 0.1f) to_sun = eng_v3(0.0f, 1.0f, 0.0f);

    eng_shader_set_v3(sh, "u_cam_pos", cam_pos);
    eng_shader_set_v3(sh, "u_ambient", r->ambient);
    eng_shader_set_v3(sh, "u_sky_zenith", sky->zenith);
    eng_shader_set_v3(sh, "u_sky_horizon", sky->horizon);
    eng_shader_set_v3(sh, "u_sky_ground", sky->ground);
    eng_shader_set_v3(sh, "u_sun_to_sky", to_sun);
    eng_shader_set_v3(sh, "u_sun_color", sky->sun_color);
    eng_shader_set_v4(sh, "u_fog", (eng_vec4_t){r->retro.fog_color.x, r->retro.fog_color.y, r->retro.fog_color.z, r->retro.fog_density});
    eng_shader_set_float(sh, "u_fog_height", r->retro.fog_height);
    eng_shader_set_float(sh, "u_fog_mie", r->retro.fog_sun_scatter);
    eng_shader_set_v4(sh, "u_fb_depth", (eng_vec4_t){
        1.0f / (float)(r->internal_w > 0 ? r->internal_w : 1),
        1.0f / (float)(r->internal_h > 0 ? r->internal_h : 1),
        z_near > 0.001f ? z_near : 0.08f,
        z_far > 1.0f ? z_far : 500.0f
    });
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
                    nxt->normal_tex != first->normal_tex ||
                    fabsf(nxt->wetness - first->wetness) > 1e-3f ||
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

        uint32_t nrm_id = first->normal_tex ? first->normal_tex : ((gt && first->albedo_tex > 0) ? gt->norm_rough_tex : 0u);
        GLuint nrm_gl = r->fallback_norm_tex;
        float has_nrm = 0.0f;
        if (nrm_id > 0) {
            const eng_gpu_tex_t *ngt = eng_asset_get_texture(r->assets, nrm_id);
            if (ngt && ngt->valid && !ngt->is_cubemap) {
                nrm_gl = ngt->tex_id;
                has_nrm = 1.0f;
            }
        }
        gl->ActiveTexture(ENG_GL_TEXTURE0 + 2u);
        gl->BindTexture(ENG_GL_TEXTURE_2D, nrm_gl);

        eng_shader_set_int(sh, "u_albedo_tex", 0);
        eng_shader_set_int(sh, "u_norm_rough_tex", 2);
        eng_shader_set_v4(sh, "u_tint", first->tint);
        eng_shader_set_v3(sh, "u_mat_mr", eng_v3(first->metallic, first->roughness, pass_mode == 1 ? 1.0f : 0.0f));
        eng_shader_set_v4(sh, "u_mat_extra", (eng_vec4_t){has_nrm, first->wetness, 0.0f, 0.0f});
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
    gl->ActiveTexture(ENG_GL_TEXTURE0);
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

static void snapshot_scene_fbo(eng_renderer_t *r, const int vp_rect[4], const int scissor_rect[4]) {
    const eng_gl_api_t *gl = eng_gl();
    gl->Disable(ENG_GL_SCISSOR_TEST);
    gl->BindFramebuffer(ENG_GL_READ_FRAMEBUFFER, r->hdr_fbo);
    gl->BindFramebuffer(ENG_GL_DRAW_FRAMEBUFFER, r->scene_snap_fbo);
    gl->BlitFramebuffer(0, 0, r->internal_w, r->internal_h, 0, 0, r->internal_w, r->internal_h,
                        ENG_GL_COLOR_BUFFER_BIT, ENG_GL_NEAREST);
    gl->BlitFramebuffer(0, 0, r->internal_w, r->internal_h, 0, 0, r->internal_w, r->internal_h,
                        ENG_GL_DEPTH_BUFFER_BIT, ENG_GL_NEAREST);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
    gl->Viewport(vp_rect[0], vp_rect[1], vp_rect[2], vp_rect[3]);
    gl->Enable(ENG_GL_SCISSOR_TEST);
    gl->Scissor(scissor_rect[0], scissor_rect[1], scissor_rect[2], scissor_rect[3]);
}

static void draw_pocket_water(eng_renderer_t *r, uint16_t pocket_id, const eng_mat4_t *vp,
                              eng_vec3_t cam_pos, float z_near, float z_far,
                              const eng_mat4_t *light_vp, bool has_shadow, bool has_snap) {
    const eng_water_cfg_t *w = resolve_water(r, pocket_id);
    if (!w || !r->water_grid_mesh || !r->sh_water.valid) return;
    const eng_gl_api_t *gl = eng_gl();

    float sx = w->size_x > 0.1f ? w->size_x : 240.0f;
    float sz = w->size_z > 0.1f ? w->size_z : 240.0f;
    float cx = w->follow_camera ? (floorf(cam_pos.x * 0.5f) * 2.0f) : w->center_x;
    float cz = w->follow_camera ? (floorf(cam_pos.z * 0.5f) * 2.0f) : w->center_z;

    gl->Disable(ENG_GL_CULL_FACE);
    gl->Enable(ENG_GL_BLEND);
    gl->BlendFunc(ENG_GL_SRC_ALPHA, ENG_GL_ONE_MINUS_SRC_ALPHA);
    gl->DepthMask(ENG_GL_TRUE);

    eng_shader_bind(&r->sh_water);
    eng_shader_set_mat4(&r->sh_water, "u_vp", vp);
    eng_shader_set_float(&r->sh_water, "u_vertex_snap", r->retro.vertex_snap_res);
    eng_shader_set_v4(&r->sh_water, "u_water_bounds", (eng_vec4_t){cx, cz, sx, sz});
    eng_shader_set_v4(&r->sh_water, "u_water_wave", (eng_vec4_t){w->level_y, w->wave_amp, w->wave_freq, r->time});
    eng_shader_set_v4(&r->sh_water, "u_water_wind", (eng_vec4_t){w->wind_dir.x, w->wind_dir.y, w->choppiness, w->flow_speed});
    eng_shader_set_v3(&r->sh_water, "u_water_absorb", w->absorb_rgb);
    eng_shader_set_v3(&r->sh_water, "u_water_scatter", w->scatter_rgb);
    eng_shader_set_v4(&r->sh_water, "u_water_opt", (eng_vec4_t){w->roughness, w->foam_width, w->refract_strength, w->caustics});
    eng_shader_set_int(&r->sh_water, "u_has_scene_snap", has_snap ? 1 : 0);
    upload_lights_and_env(&r->sh_water, r, pocket_id, cam_pos, z_near, z_far, light_vp, has_shadow);

    gl->ActiveTexture(ENG_GL_TEXTURE0);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->scene_color_tex);
    eng_shader_set_int(&r->sh_water, "u_scene_color_tex", 0);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
    eng_shader_set_int(&r->sh_water, "u_shadow_tex", 1);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 2u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->scene_ds_tex);
    eng_shader_set_int(&r->sh_water, "u_scene_depth_tex", 2);

    eng_mat4_t ident = eng_mat4_identity();
    draw_single_mesh_xform(r, r->water_grid_mesh, &ident);
    r->stats.draw_batches++;

    gl->ActiveTexture(ENG_GL_TEXTURE0);
    gl->Disable(ENG_GL_BLEND);
    gl->Enable(ENG_GL_CULL_FACE);
}

static void draw_pocket_sprites(eng_renderer_t *r, uint16_t pocket_id, const eng_mat4_t *view,
                                const eng_mat4_t *vp, eng_vec3_t cam_pos, float z_near, float z_far,
                                const eng_mat4_t *light_vp, bool has_shadow, bool has_snap) {
    if (r->sprite_count == 0) return;
    const eng_gl_api_t *gl = eng_gl();
    eng_vec3_t cam_right = eng_v3(view->m[0], view->m[4], view->m[8]);
    eng_vec3_t cam_up = eng_v3(view->m[1], view->m[5], view->m[9]);

    eng_shader_bind(&r->sh_forward);
    eng_shader_set_mat4(&r->sh_forward, "u_vp", vp);
    eng_shader_set_float(&r->sh_forward, "u_vertex_snap", 0.0f);
    eng_shader_set_int(&r->sh_forward, "u_skinned", 0);
    eng_shader_set_v4(&r->sh_forward, "u_tint", (eng_vec4_t){1, 1, 1, 1});
    upload_lights_and_env(&r->sh_forward, r, pocket_id, cam_pos, z_near, z_far, light_vp, has_shadow);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
    eng_shader_set_int(&r->sh_forward, "u_shadow_tex", 1);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 2u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->fallback_norm_tex);
    eng_shader_set_int(&r->sh_forward, "u_norm_rough_tex", 2);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 3u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->scene_ds_tex);
    eng_shader_set_int(&r->sh_forward, "u_scene_depth_tex", 3);
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
            eng_shader_set_v4(&r->sh_forward, "u_mat_extra", (eng_vec4_t){
                0.0f, 0.0f, is_sph ? 0.35f : 0.0f, (is_sph && has_snap) ? 1.0f : 0.0f
            });
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
    gl->ActiveTexture(ENG_GL_TEXTURE0);
    gl->DepthMask(ENG_GL_TRUE);
    gl->BlendFunc(ENG_GL_SRC_ALPHA, ENG_GL_ONE_MINUS_SRC_ALPHA);
    gl->Disable(ENG_GL_BLEND);
}

static bool pocket_needs_scene_snap(const eng_renderer_t *r, uint16_t pocket_id) {
    if (resolve_water(r, pocket_id) != NULL) return true;
    for (size_t i = 0; i < r->sprite_count; i++) {
        if (r->sprites[i].pocket_id == pocket_id && r->sprites[i].mode == ENG_SPRITE_BILLBOARD_SPHERICAL) {
            return true;
        }
    }
    return false;
}

static void render_pocket_recursive(eng_renderer_t *r, const eng_scene_t *scene,
                                    const eng_portal_sys_t *portals, uint16_t pocket_id,
                                    const eng_mat4_t *view, const eng_mat4_t *proj,
                                    eng_vec3_t cam_pos, float z_near, float z_far,
                                    const int vp_rect[4], const int scissor_rect[4], int depth,
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
        upload_lights_and_env(&r->sh_def_light, r, pocket_id, cam_pos, z_near, z_far, root_light_vp, has_sh);
        gl->BindVertexArray(r->fs_vao);
        gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);
        gl->ActiveTexture(ENG_GL_TEXTURE0);
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
        upload_lights_and_env(&r->sh_forward, r, pocket_id, cam_pos, z_near, z_far, root_light_vp, has_sh);
        draw_pocket_meshes(r, pocket_id, &vp, cam_pos, &r->sh_forward, depth == 0, 0);
    }

    /* Skybox + Retro Multi-Layer Parallax at far plane (depth == 1.0, stencil == depth) */
    eng_mat4_t inv_vp;
    if (eng_mat4_invert(&vp, &inv_vp)) {
        const eng_sky_config_t *sky = resolve_sky(r, pocket_id);
        eng_vec3_t sun_dir = resolve_sun_dir(r, pocket_id, sky);
        int tex_mode = 0;
        GLuint sky_tex2d = r->fallback_white_tex;
        GLuint sky_cube = r->fallback_cube_tex;
        if (sky->cubemap_tex > 0) {
            const eng_gpu_tex_t *gt = eng_asset_get_texture(r->assets, sky->cubemap_tex);
            if (gt && gt->valid && gt->is_cubemap) { sky_cube = gt->tex_id; tex_mode = 2; }
        }
        if (tex_mode == 0 && sky->panorama_tex > 0) {
            const eng_gpu_tex_t *gt = eng_asset_get_texture(r->assets, sky->panorama_tex);
            if (gt && gt->valid && !gt->is_cubemap) { sky_tex2d = gt->tex_id; tex_mode = 1; }
        }

        gl->DepthFunc(ENG_GL_LEQUAL);
        gl->DepthMask(ENG_GL_FALSE);
        eng_shader_bind(&r->sh_skybox);
        eng_shader_set_mat4(&r->sh_skybox, "u_inv_vp", &inv_vp);
        eng_shader_set_v3(&r->sh_skybox, "u_sky_zenith", sky->zenith);
        eng_shader_set_v3(&r->sh_skybox, "u_sky_horizon", sky->horizon);
        eng_shader_set_v3(&r->sh_skybox, "u_sky_ground", sky->ground);
        eng_shader_set_v3(&r->sh_skybox, "u_sun_dir", sun_dir);
        eng_shader_set_v3(&r->sh_skybox, "u_sun_color", sky->sun_color);
        eng_shader_set_v3(&r->sh_skybox, "u_cloud_color", sky->cloud_color);
        eng_shader_set_v3(&r->sh_skybox, "u_cam_pos", cam_pos);
        eng_shader_set_v4(&r->sh_skybox, "u_sun_params", (eng_vec4_t){
            sky->sun_size, sky->sun_glow, sky->sun_banded ? 1.0f : 0.0f, r->time
        });
        eng_shader_set_v4(&r->sh_skybox, "u_sky_fx", (eng_vec4_t){
            sky->clouds, sky->cloud_speed, sky->cloud_scale, sky->stars
        });
        eng_shader_set_v4(&r->sh_skybox, "u_sky_fx2", (eng_vec4_t){
            sky->star_scale, sky->pixel_snap, (float)tex_mode, (float)sky->parallax_count
        });

        gl->ActiveTexture(ENG_GL_TEXTURE0);
        gl->BindTexture(ENG_GL_TEXTURE_2D, sky_tex2d);
        eng_shader_set_int(&r->sh_skybox, "u_sky_tex", 0);
        gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
        gl->BindTexture(ENG_GL_TEXTURE_CUBE_MAP, sky_cube);
        eng_shader_set_int(&r->sh_skybox, "u_sky_cube", 1);

        eng_vec4_t p0[ENG_MAX_PARALLAX_LAYERS], p1[ENG_MAX_PARALLAX_LAYERS];
        eng_vec4_t ptint[ENG_MAX_PARALLAX_LAYERS], pacc[ENG_MAX_PARALLAX_LAYERS];
        static const char *const k_plx_names[ENG_MAX_PARALLAX_LAYERS] = {
            "u_plx_tex0", "u_plx_tex1", "u_plx_tex2", "u_plx_tex3"
        };
        for (int li = 0; li < ENG_MAX_PARALLAX_LAYERS; li++) {
            GLuint ltex = r->fallback_white_tex;
            if (li < sky->parallax_count) {
                const eng_parallax_layer_t *pl = &sky->parallax[li];
                float has_tex = 0.0f;
                if (pl->tex_id > 0) {
                    const eng_gpu_tex_t *gt = eng_asset_get_texture(r->assets, pl->tex_id);
                    if (gt && gt->valid && !gt->is_cubemap) { ltex = gt->tex_id; has_tex = 1.0f; }
                }
                p0[li] = (eng_vec4_t){(float)pl->style, pl->parallax, pl->move_parallax, pl->scroll_speed};
                p1[li] = (eng_vec4_t){pl->height, pl->offset, pl->scale, pl->fog_blend};
                ptint[li] = pl->tint;
                pacc[li] = (eng_vec4_t){pl->accent.x, pl->accent.y, pl->accent.z, has_tex};
            } else {
                p0[li] = p1[li] = ptint[li] = pacc[li] = (eng_vec4_t){0, 0, 0, 0};
            }
            gl->ActiveTexture(ENG_GL_TEXTURE0 + 2u + (GLenum)li);
            gl->BindTexture(ENG_GL_TEXTURE_2D, ltex);
            eng_shader_set_int(&r->sh_skybox, k_plx_names[li], 2 + li);
        }
        GLint lp0 = gl->GetUniformLocation(r->sh_skybox.program, "u_plx_p0");
        GLint lp1 = gl->GetUniformLocation(r->sh_skybox.program, "u_plx_p1");
        GLint lpt = gl->GetUniformLocation(r->sh_skybox.program, "u_plx_tint");
        GLint lpa = gl->GetUniformLocation(r->sh_skybox.program, "u_plx_acc");
        if (lp0 >= 0) gl->Uniform4fv(lp0, ENG_MAX_PARALLAX_LAYERS, &p0[0].x);
        if (lp1 >= 0) gl->Uniform4fv(lp1, ENG_MAX_PARALLAX_LAYERS, &p1[0].x);
        if (lpt >= 0) gl->Uniform4fv(lpt, ENG_MAX_PARALLAX_LAYERS, &ptint[0].x);
        if (lpa >= 0) gl->Uniform4fv(lpa, ENG_MAX_PARALLAX_LAYERS, &pacc[0].x);
        gl->ActiveTexture(ENG_GL_TEXTURE0);

        gl->BindVertexArray(r->fs_vao);
        gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);
        gl->DepthMask(ENG_GL_TRUE);
        gl->DepthFunc(ENG_GL_LESS);
    }

    /* Recursive Stencil + Lengyel Oblique Near-Plane Portals (before water & soft particles so portals refract cleanly) */
    if (scene && portals && depth < r->max_portal_depth) {
        size_t pcount = eng_portal_count(portals);
        for (size_t i = 0; i < pcount; i++) {
            const eng_portal_t *p = eng_portal_get(portals, i);
            if (!p || p->src_pocket != pocket_id || p->src_ent == entered_dst_ent) continue;

            int local_sc[4];
            if (!eng_portal_screen_scissor(scene, p, &vp, vp_rect[2], vp_rect[3], local_sc)) continue;

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
            eng_shader_set_v4(&r->sh_skybox, "u_sky_fx", (eng_vec4_t){0, 0, 0, 0});
            eng_shader_set_v4(&r->sh_skybox, "u_sky_fx2", (eng_vec4_t){0, 0, 0, 0});
            gl->BindVertexArray(r->fs_vao);
            gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);

            /* 3. Render destination pocket through virtual oblique camera */
            r->stats.portal_views++;
            eng_vec3_t virt_cam_pos = eng_mat4_transform_point(&warp, cam_pos);
            render_pocket_recursive(r, scene, portals, p->dst_pocket, &virt_view, &oblique_proj,
                                    virt_cam_pos, z_near, z_far, vp_rect, child_sc, depth + 1, p->dst_ent, root_light_vp, false);

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
            gl->StencilFunc(ENG_GL_EQUAL, depth, 0xFFu);
            gl->StencilOp(ENG_GL_KEEP, ENG_GL_KEEP, ENG_GL_KEEP);
        }
    }

    /* WebGL2-safe scene color + depth snapshot for refractive Beer-Lambert water & soft depth-faded fire/smoke */
    bool has_snap = false;
    if (r->scene_snap_fbo && pocket_needs_scene_snap(r, pocket_id)) {
        snapshot_scene_fbo(r, vp_rect, scissor_rect);
        has_snap = true;
    }

    /* Forward composite pass for deferred opaque emissives, Gerstner water, crystals, and soft particles */
    eng_shader_bind(&r->sh_forward);
    eng_shader_set_mat4(&r->sh_forward, "u_vp", &vp);
    eng_shader_set_float(&r->sh_forward, "u_vertex_snap", r->retro.vertex_snap_res);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
    eng_shader_set_int(&r->sh_forward, "u_shadow_tex", 1);
    upload_lights_and_env(&r->sh_forward, r, pocket_id, cam_pos, z_near, z_far, root_light_vp, has_sh);
    if (use_deferred) {
        draw_pocket_meshes(r, pocket_id, &vp, cam_pos, &r->sh_forward, depth == 0, 2);
    }

    draw_pocket_water(r, pocket_id, &vp, cam_pos, z_near, z_far, root_light_vp, has_sh, has_snap);

    eng_shader_bind(&r->sh_forward);
    eng_shader_set_mat4(&r->sh_forward, "u_vp", &vp);
    eng_shader_set_float(&r->sh_forward, "u_vertex_snap", r->retro.vertex_snap_res);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
    eng_shader_set_int(&r->sh_forward, "u_shadow_tex", 1);
    upload_lights_and_env(&r->sh_forward, r, pocket_id, cam_pos, z_near, z_far, root_light_vp, has_sh);
    gl->Enable(ENG_GL_BLEND);
    gl->BlendFunc(ENG_GL_SRC_ALPHA, ENG_GL_ONE_MINUS_SRC_ALPHA);
    gl->DepthMask(ENG_GL_FALSE);
    draw_pocket_meshes(r, pocket_id, &vp, cam_pos, &r->sh_forward, depth == 0, 1);
    gl->DepthMask(ENG_GL_TRUE);
    gl->Disable(ENG_GL_BLEND);

    /* Sprites & Soft-Depth Blackbody/Smoke Particles in this pocket */
    gl->Disable(ENG_GL_CULL_FACE);
    draw_pocket_sprites(r, pocket_id, view, &vp, cam_pos, z_near, z_far, root_light_vp, has_sh, has_snap);
    gl->Enable(ENG_GL_CULL_FACE);
}

void eng_renderer_render_views(eng_renderer_t *r, const eng_scene_t *scene,
                               const eng_portal_sys_t *portals,
                               const eng_viewport_t *views, int view_count,
                               const eng_xr_t *xr) {
    if (!r || !views || view_count <= 0) return;
    if (view_count > ENG_MAX_VIEWPORTS) view_count = ENG_MAX_VIEWPORTS;
    const eng_gl_api_t *gl = eng_gl();
    bool xr_on = (xr != NULL && eng_xr_is_active(xr));
    (void)sync_internal_targets(r, xr_on);

    int iw = r->internal_w, ih = r->internal_h;
    gl->Disable(ENG_GL_BLEND);

    /* Clear low-res HDR + Depth + Stencil FBO once before viewport/eye loop */
    const eng_sky_config_t *root_sky = resolve_sky(r, views[0].cam.pocket_id);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
    gl->Viewport(0, 0, iw, ih);
    gl->Disable(ENG_GL_SCISSOR_TEST);
    gl->Disable(ENG_GL_STENCIL_TEST);
    gl->ColorMask(ENG_GL_TRUE, ENG_GL_TRUE, ENG_GL_TRUE, ENG_GL_TRUE);
    gl->DepthMask(ENG_GL_TRUE);
    gl->StencilMask(0xFFu);
    gl->ClearColor(root_sky->horizon.x, root_sky->horizon.y, root_sky->horizon.z, 1.0f);
    gl->ClearStencil(0);
    gl->Clear(ENG_GL_COLOR_BUFFER_BIT | ENG_GL_DEPTH_BUFFER_BIT | ENG_GL_STENCIL_BUFFER_BIT);

    int pass_count = xr_on ? 2 : view_count;
    GLuint dst_fbo = xr_on ? eng_xr_framebuffer(xr) : r->cap_fbo;

    eng_mat4_t light_vp = eng_mat4_identity();
    eng_mat4_t primary_inv_vp = eng_mat4_identity();
    bool has_shadow = false;
    if (xr_on) {
        has_shadow = render_shadow_map(r, views[0].cam.pocket_id, views[0].cam.pos, &light_vp);
        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
    }

    for (int pass = 0; pass < pass_count; pass++) {
        const eng_camera_t *cam = &views[xr_on ? 0 : pass].cam;
        eng_mat4_t view, proj;
        int vp_rect[4] = {0, 0, iw, ih};
        eng_vec3_t eye_pos = cam->pos;
        float zn = cam->z_near > 0.001f ? cam->z_near : 0.08f;
        float zf = cam->z_far > 1.0f ? cam->z_far : 500.0f;

        if (xr_on) {
            const eng_xr_eye_t *xe = eng_xr_get_eye(xr, pass);
            if (!xe) continue;
            view = xe->view;
            proj = xe->proj;
            memcpy(vp_rect, xe->viewport, sizeof(vp_rect));
            if (vp_rect[2] <= 0 || vp_rect[3] <= 0) {
                vp_rect[0] = (pass == 0) ? 0 : (iw / 2);
                vp_rect[1] = 0;
                vp_rect[2] = iw / 2;
                vp_rect[3] = ih;
            }
            eng_mat4_t inv_v;
            if (eng_mat4_invert(&view, &inv_v)) {
                eye_pos = eng_v3(inv_v.m[12], inv_v.m[13], inv_v.m[14]);
            }
        } else {
            const float *nr = views[pass].norm_rect;
            vp_rect[0] = (int)floorf(nr[0] * (float)iw + 0.5f);
            vp_rect[1] = (int)floorf(nr[1] * (float)ih + 0.5f);
            vp_rect[2] = (int)floorf(nr[2] * (float)iw + 0.5f);
            vp_rect[3] = (int)floorf(nr[3] * (float)ih + 0.5f);
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
            proj = eng_mat4_perspective(fov_y, aspect, zn, zf);
            if (pass == 0) {
                eng_mat4_t vp0 = eng_mat4_mul(&proj, &view);
                (void)eng_mat4_invert(&vp0, &primary_inv_vp);
            }
        }

        render_pocket_recursive(r, scene, portals, cam->pocket_id, &view, &proj,
                                eye_pos, zn, zf, vp_rect, vp_rect, 0, ENG_ENTITY_NULL, &light_vp, has_shadow);
    }

    /* Draw crisp divider lines between split-screen viewports */
    if (!xr_on && view_count > 1) {
        gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->hdr_fbo);
        gl->Enable(ENG_GL_SCISSOR_TEST);
        gl->Disable(ENG_GL_STENCIL_TEST);
        gl->Disable(ENG_GL_DEPTH_TEST);
        gl->ClearColor(0.03f, 0.04f, 0.07f, 1.0f);
        for (int i = 0; i < view_count; i++) {
            const float *nr = views[i].norm_rect;
            if (nr[0] > 0.01f) {
                int sx = (int)(nr[0] * (float)iw) - 1;
                gl->Scissor(sx > 0 ? sx : 0, (int)(nr[1] * (float)ih), 2, (int)(nr[3] * (float)ih));
                gl->Clear(ENG_GL_COLOR_BUFFER_BIT);
            }
            if (nr[1] > 0.01f) {
                int sy = (int)(nr[1] * (float)ih) - 1;
                gl->Scissor((int)(nr[0] * (float)iw), sy > 0 ? sy : 0, (int)(nr[2] * (float)iw), 2);
                gl->Clear(ENG_GL_COLOR_BUFFER_BIT);
            }
        }
    }

    /* Post-Processing: Dual-Kawase Bloom + SSAO + Volumetric God-Rays + Underwater + Low-Res Lens Upscale */
    gl->Disable(ENG_GL_SCISSOR_TEST);
    gl->Disable(ENG_GL_STENCIL_TEST);
    gl->Disable(ENG_GL_DEPTH_TEST);
    gl->DepthMask(ENG_GL_FALSE);
    gl->BindVertexArray(r->fs_vao);
    eng_shader_bind(&r->sh_post);

    int bw = iw > 1 ? iw / 2 : 1;
    int bh = ih > 1 ? ih / 2 : 1;
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->bloom_fbo);
    gl->Viewport(0, 0, bw, bh);
    gl->ActiveTexture(ENG_GL_TEXTURE0);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->hdr_color_tex);
    eng_shader_set_int(&r->sh_post, "u_hdr_tex", 0);
    eng_shader_set_v3(&r->sh_post, "u_inv_res", eng_v3(1.0f / (float)iw, 1.0f / (float)ih, 0.0f));
    eng_shader_set_int(&r->sh_post, "u_pass_mode", 0);
    gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);

    const eng_camera_t *c0 = &views[0].cam;
    float zn0 = c0->z_near > 0.001f ? c0->z_near : 0.08f;
    float zf0 = c0->z_far > 1.0f ? c0->z_far : 500.0f;
    bool single_view = (!xr_on && view_count == 1);
    int sharp_mode = r->retro.sharp_upscale;
    if (sharp_mode == 0 && (iw < r->width || ih < r->height)) sharp_mode = 1;

    eng_vec3_t sun_dir = resolve_sun_dir(r, c0->pocket_id, root_sky);
    eng_vec3_t to_sun = eng_v3_norm(eng_v3_scale(sun_dir, -1.0f));
    if (eng_v3_dot(to_sun, to_sun) < 0.1f) to_sun = eng_v3(0.0f, 1.0f, 0.0f);

    eng_vec4_t vpos_r[4] = {0}, vcol[4] = {0};
    int vl_n = 0;
    for (size_t li = 0; li < r->light_count && vl_n < 4; li++) {
        const eng_light_t *l = &r->lights[li];
        if (l->pocket_id == c0->pocket_id && l->type != ENG_LIGHT_DIR) {
            vpos_r[vl_n] = (eng_vec4_t){l->pos.x, l->pos.y, l->pos.z, l->range > 0.1f ? l->range : 15.0f};
            vcol[vl_n] = (eng_vec4_t){l->color.x, l->color.y, l->color.z, 1.0f};
            vl_n++;
        }
    }

    bool w_on = false;
    float wh = eng_renderer_sample_water_height(r, c0->pocket_id, c0->pos.x, c0->pos.z, &w_on);
    bool submerged = (single_view && w_on && c0->pos.y < wh);
    const eng_water_cfg_t *wcfg = resolve_water(r, c0->pocket_id);

    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, dst_fbo);
    gl->Viewport(0, 0, r->width, r->height);
    gl->ActiveTexture(ENG_GL_TEXTURE0);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->hdr_color_tex);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 1u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->bloom_tex);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 2u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->hdr_ds_tex);
    gl->ActiveTexture(ENG_GL_TEXTURE0 + 3u);
    gl->BindTexture(ENG_GL_TEXTURE_2D, r->shadow_tex);
    eng_shader_set_int(&r->sh_post, "u_hdr_tex", 0);
    eng_shader_set_int(&r->sh_post, "u_bloom_tex", 1);
    eng_shader_set_int(&r->sh_post, "u_scene_depth_tex", 2);
    eng_shader_set_int(&r->sh_post, "u_shadow_tex", 3);
    eng_shader_set_int(&r->sh_post, "u_pass_mode", 1);
    eng_shader_set_v3(&r->sh_post, "u_inv_res", eng_v3(1.0f / (float)iw, 1.0f / (float)ih, (float)sharp_mode));
    eng_shader_set_v4(&r->sh_post, "u_fb_depth", (eng_vec4_t){(float)iw, (float)ih, zn0, zf0});
    eng_shader_set_v4(&r->sh_post, "u_post_fx", (eng_vec4_t){
        r->retro.ssao_intensity,
        single_view ? r->retro.volumetric_fog : 0.0f,
        (!xr_on) ? 1.0f : 0.0f,
        r->time
    });
    eng_shader_set_mat4(&r->sh_post, "u_inv_vp", &primary_inv_vp);
    eng_shader_set_mat4(&r->sh_post, "u_light_vp", &light_vp);
    eng_shader_set_v3(&r->sh_post, "u_cam_pos", c0->pos);
    eng_shader_set_v3(&r->sh_post, "u_sun_to_sky", to_sun);
    eng_shader_set_v3(&r->sh_post, "u_sun_color", root_sky->sun_color);
    eng_shader_set_v4(&r->sh_post, "u_fog", (eng_vec4_t){r->retro.fog_color.x, r->retro.fog_color.y, r->retro.fog_color.z, r->retro.fog_density});
    eng_shader_set_float(&r->sh_post, "u_fog_height", r->retro.fog_height);
    eng_shader_set_int(&r->sh_post, "u_has_shadow", has_shadow ? 1 : 0);
    eng_shader_set_int(&r->sh_post, "u_vol_light_count", vl_n);
    if (vl_n > 0) {
        GLint vp_loc = gl->GetUniformLocation(r->sh_post.program, "u_vol_light_pos_r");
        GLint vc_loc = gl->GetUniformLocation(r->sh_post.program, "u_vol_light_col");
        if (vp_loc >= 0) gl->Uniform4fv(vp_loc, vl_n, &vpos_r[0].x);
        if (vc_loc >= 0) gl->Uniform4fv(vc_loc, vl_n, &vcol[0].x);
    }
    eng_shader_set_v4(&r->sh_post, "u_underwater", (eng_vec4_t){
        submerged ? 1.0f : 0.0f, submerged ? (wh - c0->pos.y) : 0.0f, 0.0f, 0.0f
    });
    eng_shader_set_v3(&r->sh_post, "u_water_absorb", wcfg ? wcfg->absorb_rgb : eng_v3(0.42f, 0.09f, 0.04f));
    eng_shader_set_v3(&r->sh_post, "u_water_scatter", wcfg ? wcfg->scatter_rgb : eng_v3(0.03f, 0.16f, 0.20f));

    eng_shader_set_float(&r->sh_post, "u_bloom_amt", r->retro.bloom_intensity);
    eng_shader_set_int(&r->sh_post, "u_dither_bayer", r->retro.dither_bayer ? 1 : 0);
    float levels = (r->retro.color_bits > 0 && r->retro.color_bits < 8)
                       ? (float)((1 << r->retro.color_bits) - 1)
                       : 0.0f;
    eng_shader_set_float(&r->sh_post, "u_color_levels", levels);
    eng_shader_set_float(&r->sh_post, "u_crt_scanline", r->retro.crt_scanlines);
    gl->DrawArrays(ENG_GL_TRIANGLES, 0, 6);
    gl->ActiveTexture(ENG_GL_TEXTURE0);
}

void eng_renderer_render_frame(eng_renderer_t *r, const eng_scene_t *scene,
                               const eng_portal_sys_t *portals,
                               const eng_camera_t *cam, const eng_xr_t *xr) {
    if (!r || !cam) return;
    eng_viewport_t v = {*cam, {0.0f, 0.0f, 1.0f, 1.0f}};
    eng_renderer_render_views(r, scene, portals, &v, 1, xr);
}

bool eng_renderer_set_capture_target(eng_renderer_t *r, int width, int height) {
    if (!r) return false;
    const eng_gl_api_t *gl = eng_gl();
    if (r->cap_fbo) { gl->DeleteFramebuffers(1, &r->cap_fbo); r->cap_fbo = 0; }
    if (r->cap_color_tex) { gl->DeleteTextures(1, &r->cap_color_tex); r->cap_color_tex = 0; }
    if (width <= 0 || height <= 0) return true;
    if (!eng_renderer_resize(r, width, height)) return false;
    r->cap_color_tex = make_tex2d(r->width, r->height, ENG_GL_RGBA8, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, ENG_GL_LINEAR);
    gl->GenFramebuffers(1, &r->cap_fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->cap_fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT0, ENG_GL_TEXTURE_2D, r->cap_color_tex, 0);
    bool ok = (gl->CheckFramebufferStatus(ENG_GL_FRAMEBUFFER) == ENG_GL_FRAMEBUFFER_COMPLETE);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, 0);
    if (!ok) {
        gl->DeleteFramebuffers(1, &r->cap_fbo); r->cap_fbo = 0;
        gl->DeleteTextures(1, &r->cap_color_tex); r->cap_color_tex = 0;
    }
    return ok;
}

GLuint eng_renderer_output_fbo(const eng_renderer_t *r) { return r ? r->cap_fbo : 0u; }

void eng_renderer_get_size(const eng_renderer_t *r, int *out_w, int *out_h) {
    if (out_w) *out_w = r ? r->width : 0;
    if (out_h) *out_h = r ? r->height : 0;
}

void eng_renderer_get_internal_size(const eng_renderer_t *r, int *out_w, int *out_h) {
    if (out_w) *out_w = r ? r->internal_w : 0;
    if (out_h) *out_h = r ? r->internal_h : 0;
}

bool eng_renderer_read_pixels(const eng_renderer_t *r, uint8_t *out_rgba_bottom_up, int w, int h) {
    if (!r || !out_rgba_bottom_up || w <= 0 || h <= 0 || w > r->width || h > r->height) return false;
    const eng_gl_api_t *gl = eng_gl();
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, r->cap_fbo);
    gl->ReadPixels(0, 0, w, h, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, out_rgba_bottom_up);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, 0);
    return true;
}

eng_render_stats_t eng_renderer_stats(const eng_renderer_t *r) {
    eng_render_stats_t empty;
    memset(&empty, 0, sizeof(empty));
    return r ? r->stats : empty;
}
