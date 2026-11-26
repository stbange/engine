#include "engine/eng_asset.h"
#include "engine/eng_log.h"

#include "cgltf.h"
#include "stb_image.h"
#include "stb_image_write.h"

#include <float.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_CACHED_MESHES 256
#define ENG_MAX_CACHED_TEX 256

typedef struct {
    char key[128];
    eng_gpu_mesh_t gpu;
} cached_mesh_t;

typedef struct {
    char key[128];
    eng_gpu_tex_t gpu;
} cached_tex_t;

struct eng_asset_cache_s {
    eng_vfs_t *vfs;
    cached_mesh_t meshes[ENG_MAX_CACHED_MESHES];
    uint32_t mesh_count; /* 1-based IDs; 0 = invalid */
    cached_tex_t texs[ENG_MAX_CACHED_TEX];
    uint32_t tex_count;  /* 1-based IDs; 0 = white default fallback */
};

void eng_mesh_data_init(eng_mesh_data_t *md) {
    if (md) memset(md, 0, sizeof(*md));
}

void eng_mesh_data_free(eng_mesh_data_t *md) {
    if (!md) return;
    free(md->verts);
    free(md->indices);
    memset(md, 0, sizeof(*md));
}

static bool reserve_mesh(eng_mesh_data_t *md, size_t add_v, size_t add_i) {
    if (md->vert_count + add_v > md->vert_cap) {
        size_t nc = md->vert_cap ? md->vert_cap * 2 : 64;
        while (nc < md->vert_count + add_v) nc *= 2;
        eng_vertex_t *nv = (eng_vertex_t *)realloc(md->verts, nc * sizeof(eng_vertex_t));
        if (!nv) return false;
        md->verts = nv;
        md->vert_cap = nc;
    }
    if (md->idx_count + add_i > md->idx_cap) {
        size_t nc = md->idx_cap ? md->idx_cap * 2 : 128;
        while (nc < md->idx_count + add_i) nc *= 2;
        uint32_t *ni = (uint32_t *)realloc(md->indices, nc * sizeof(uint32_t));
        if (!ni) return false;
        md->indices = ni;
        md->idx_cap = nc;
    }
    return true;
}

static eng_vertex_t make_vert(eng_vec3_t p, eng_vec3_t n, float u, float v, eng_vec4_t c) {
    eng_vertex_t vt;
    memset(&vt, 0, sizeof(vt));
    vt.pos[0] = p.x; vt.pos[1] = p.y; vt.pos[2] = p.z;
    vt.norm[0] = n.x; vt.norm[1] = n.y; vt.norm[2] = n.z;
    vt.uv[0] = u; vt.uv[1] = v;
    vt.color[0] = c.x; vt.color[1] = c.y; vt.color[2] = c.z; vt.color[3] = c.w;
    vt.weights[0] = 1.0f;
    return vt;
}

bool eng_mesh_append_transformed(eng_mesh_data_t *dst, const eng_mesh_data_t *src,
                                 const eng_mat4_t *xform, eng_vec4_t color) {
    if (!dst || !src || !xform || !reserve_mesh(dst, src->vert_count, src->idx_count)) return false;
    uint32_t base = (uint32_t)dst->vert_count;
    for (size_t i = 0; i < src->vert_count; i++) {
        eng_vertex_t v = src->verts[i];
        eng_vec3_t p = eng_mat4_transform_point(xform, eng_v3(v.pos[0], v.pos[1], v.pos[2]));
        eng_vec3_t n = eng_v3_norm(eng_v3(
            xform->m[0] * v.norm[0] + xform->m[4] * v.norm[1] + xform->m[8]  * v.norm[2],
            xform->m[1] * v.norm[0] + xform->m[5] * v.norm[1] + xform->m[9]  * v.norm[2],
            xform->m[2] * v.norm[0] + xform->m[6] * v.norm[1] + xform->m[10] * v.norm[2]
        ));
        v.pos[0] = p.x; v.pos[1] = p.y; v.pos[2] = p.z;
        v.norm[0] = n.x; v.norm[1] = n.y; v.norm[2] = n.z;
        v.color[0] *= color.x; v.color[1] *= color.y; v.color[2] *= color.z; v.color[3] *= color.w;
        dst->verts[dst->vert_count++] = v;
    }
    for (size_t i = 0; i < src->idx_count; i++) {
        dst->indices[dst->idx_count++] = base + src->indices[i];
    }
    return true;
}

bool eng_mesh_append_box(eng_mesh_data_t *md, eng_vec3_t c, eng_vec3_t sz, eng_vec4_t col) {
    if (!md || !reserve_mesh(md, 24, 36)) return false;
    float hx = sz.x * 0.5f, hy = sz.y * 0.5f, hz = sz.z * 0.5f;
    static const float fn[6][3] = {
        {0, 0, 1}, {0, 0, -1}, {1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}
    };
    static const float fv[6][4][3] = {
        {{-1,-1, 1}, { 1,-1, 1}, { 1, 1, 1}, {-1, 1, 1}},
        {{ 1,-1,-1}, {-1,-1,-1}, {-1, 1,-1}, { 1, 1,-1}},
        {{ 1,-1, 1}, { 1,-1,-1}, { 1, 1,-1}, { 1, 1, 1}},
        {{-1,-1,-1}, {-1,-1, 1}, {-1, 1, 1}, {-1, 1,-1}},
        {{-1, 1, 1}, { 1, 1, 1}, { 1, 1,-1}, {-1, 1,-1}},
        {{-1,-1,-1}, { 1,-1,-1}, { 1,-1, 1}, {-1,-1, 1}}
    };
    static const float fuv[4][2] = {{0,0}, {1,0}, {1,1}, {0,1}};
    for (int f = 0; f < 6; f++) {
        uint32_t base = (uint32_t)md->vert_count;
        eng_vec3_t n = eng_v3(fn[f][0], fn[f][1], fn[f][2]);
        for (int k = 0; k < 4; k++) {
            eng_vec3_t p = eng_v3(c.x + fv[f][k][0] * hx, c.y + fv[f][k][1] * hy, c.z + fv[f][k][2] * hz);
            md->verts[md->vert_count++] = make_vert(p, n, fuv[k][0], fuv[k][1], col);
        }
        md->indices[md->idx_count++] = base + 0;
        md->indices[md->idx_count++] = base + 1;
        md->indices[md->idx_count++] = base + 2;
        md->indices[md->idx_count++] = base + 0;
        md->indices[md->idx_count++] = base + 2;
        md->indices[md->idx_count++] = base + 3;
    }
    return true;
}

bool eng_mesh_append_sphere(eng_mesh_data_t *md, eng_vec3_t center, float radius, int rings, int sectors, eng_vec4_t col) {
    if (!md || rings < 3 || sectors < 3) return false;
    size_t v_add = (size_t)(rings + 1) * (size_t)(sectors + 1);
    size_t i_add = (size_t)rings * (size_t)sectors * 6u;
    if (!reserve_mesh(md, v_add, i_add)) return false;

    uint32_t base = (uint32_t)md->vert_count;
    for (int r = 0; r <= rings; r++) {
        float v = (float)r / (float)rings;
        float phi = v * ENG_PI;
        for (int s = 0; s <= sectors; s++) {
            float u = (float)s / (float)sectors;
            float theta = u * 2.0f * ENG_PI;
            eng_vec3_t n = eng_v3(sinf(phi) * cosf(theta), cosf(phi), sinf(phi) * sinf(theta));
            eng_vec3_t p = eng_v3_add(center, eng_v3_scale(n, radius));
            md->verts[md->vert_count++] = make_vert(p, n, u, v, col);
        }
    }
    int stride = sectors + 1;
    for (int r = 0; r < rings; r++) {
        for (int s = 0; s < sectors; s++) {
            uint32_t i0 = base + (uint32_t)(r * stride + s);
            uint32_t i1 = i0 + (uint32_t)stride;
            md->indices[md->idx_count++] = i0;
            md->indices[md->idx_count++] = i0 + 1;
            md->indices[md->idx_count++] = i1 + 1;
            md->indices[md->idx_count++] = i0;
            md->indices[md->idx_count++] = i1 + 1;
            md->indices[md->idx_count++] = i1;
        }
    }
    return true;
}

bool eng_mesh_append_lathe(eng_mesh_data_t *md, const eng_vec2_t *profile_ry, size_t profile_len, int slices, eng_vec4_t col) {
    if (!md || !profile_ry || profile_len < 2 || slices < 3) return false;
    size_t v_add = profile_len * (size_t)(slices + 1);
    size_t i_add = (profile_len - 1u) * (size_t)slices * 6u;
    if (!reserve_mesh(md, v_add, i_add)) return false;

    uint32_t base = (uint32_t)md->vert_count;
    for (size_t j = 0; j < profile_len; j++) {
        float rad = profile_ry[j].x;
        float y = profile_ry[j].y;
        float dy = (j + 1 < profile_len) ? (profile_ry[j + 1].y - y) : (y - profile_ry[j - 1].y);
        float dr = (j + 1 < profile_len) ? (profile_ry[j + 1].x - rad) : (rad - profile_ry[j - 1].x);
        float v = (float)j / (float)(profile_len - 1u);
        for (int s = 0; s <= slices; s++) {
            float u = (float)s / (float)slices;
            float ang = u * 2.0f * ENG_PI;
            float ca = cosf(ang), sa = sinf(ang);
            eng_vec3_t p = eng_v3(rad * ca, y, rad * sa);
            eng_vec3_t n = eng_v3_norm(eng_v3(dy * ca, -dr, dy * sa));
            if (eng_v3_dot(n, n) < 0.1f) n = eng_v3(0.0f, 1.0f, 0.0f);
            md->verts[md->vert_count++] = make_vert(p, n, u, v, col);
        }
    }
    uint32_t stride = (uint32_t)(slices + 1);
    for (size_t j = 0; j + 1 < profile_len; j++) {
        for (int s = 0; s < slices; s++) {
            uint32_t i0 = base + (uint32_t)j * stride + (uint32_t)s;
            uint32_t i1 = i0 + stride;
            md->indices[md->idx_count++] = i0;
            md->indices[md->idx_count++] = i0 + 1;
            md->indices[md->idx_count++] = i1 + 1;
            md->indices[md->idx_count++] = i0;
            md->indices[md->idx_count++] = i1 + 1;
            md->indices[md->idx_count++] = i1;
        }
    }
    return true;
}

bool eng_mesh_append_cylinder(eng_mesh_data_t *md, eng_vec3_t base_pos, float r_bottom, float r_top, float height, int slices, eng_vec4_t col) {
    eng_vec2_t prof[4] = {
        {0.0f, base_pos.y},
        {r_bottom, base_pos.y},
        {r_top, base_pos.y + height},
        {0.0f, base_pos.y + height}
    };
    eng_mesh_data_t tmp;
    eng_mesh_data_init(&tmp);
    if (!eng_mesh_append_lathe(&tmp, prof, 4, slices, col)) return false;
    eng_mat4_t xf = eng_mat4_trs(eng_v3(base_pos.x, 0.0f, base_pos.z), eng_quat_identity(), eng_v3(1, 1, 1));
    bool ok = eng_mesh_append_transformed(md, &tmp, &xf, (eng_vec4_t){1, 1, 1, 1});
    eng_mesh_data_free(&tmp);
    return ok;
}

bool eng_mesh_parse_obj(eng_mesh_data_t *out, const char *obj_text) {
    if (!out || !obj_text) return false;
    eng_mesh_data_init(out);
    eng_vec3_t pos[4096]; size_t np = 0;
    eng_vec3_t nrm[4096]; size_t nn = 0;
    eng_vec2_t uvs[4096]; size_t nu = 0;

    const char *line = obj_text;
    while (*line) {
        const char *eol = strchr(line, '\n');
        size_t len = eol ? (size_t)(eol - line) : strlen(line);
        char buf[256];
        size_t clen = len < sizeof(buf) - 1 ? len : sizeof(buf) - 1;
        memcpy(buf, line, clen);
        buf[clen] = '\0';

        if (strncmp(buf, "v ", 2) == 0 && np < 4096) {
            eng_vec3_t v = {0, 0, 0};
            if (sscanf(buf + 2, "%f %f %f", &v.x, &v.y, &v.z) == 3) pos[np++] = v;
        } else if (strncmp(buf, "vn ", 3) == 0 && nn < 4096) {
            eng_vec3_t n = {0, 1, 0};
            if (sscanf(buf + 3, "%f %f %f", &n.x, &n.y, &n.z) == 3) nrm[nn++] = n;
        } else if (strncmp(buf, "vt ", 3) == 0 && nu < 4096) {
            eng_vec2_t t = {0, 0};
            if (sscanf(buf + 3, "%f %f", &t.x, &t.y) == 2) uvs[nu++] = t;
        } else if (strncmp(buf, "f ", 2) == 0) {
            uint32_t face_idx[8];
            int fc = 0;
            char *cur = buf + 2;
            while (*cur && fc < 8) {
                while (*cur == ' ' || *cur == '\t' || *cur == '\r') cur++;
                if (!*cur) break;
                char *tok = cur;
                while (*cur && *cur != ' ' && *cur != '\t' && *cur != '\r') cur++;
                if (*cur) *cur++ = '\0';

                int vi = 0, ti = 0, ni = 0;
                if (strstr(tok, "//")) {
                    sscanf(tok, "%d//%d", &vi, &ni);
                } else if (sscanf(tok, "%d/%d/%d", &vi, &ti, &ni) < 2) {
                    sscanf(tok, "%d", &vi);
                }
                if (vi <= 0 || (size_t)vi > np || !reserve_mesh(out, 1, 3)) continue;
                eng_vec3_t p = pos[vi - 1];
                eng_vec3_t n = (ni > 0 && (size_t)ni <= nn) ? nrm[ni - 1] : eng_v3(0, 1, 0);
                eng_vec2_t uv = (ti > 0 && (size_t)ti <= nu) ? uvs[ti - 1] : (eng_vec2_t){0, 0};
                face_idx[fc++] = (uint32_t)out->vert_count;
                out->verts[out->vert_count++] = make_vert(p, n, uv.x, uv.y, (eng_vec4_t){1, 1, 1, 1});
            }
            for (int k = 1; k + 1 < fc; k++) {
                if (!reserve_mesh(out, 0, 3)) break;
                out->indices[out->idx_count++] = face_idx[0];
                out->indices[out->idx_count++] = face_idx[k];
                out->indices[out->idx_count++] = face_idx[k + 1];
            }
        }
        line = eol ? (eol + 1) : (line + len);
    }
    return out->vert_count > 0 && out->idx_count >= 3;
}

bool eng_mesh_parse_gltf(eng_mesh_data_t *out, const void *bytes, size_t byte_len) {
    if (!out || !bytes || byte_len == 0) return false;
    eng_mesh_data_init(out);
    cgltf_options opts;
    memset(&opts, 0, sizeof(opts));
    cgltf_data *data = NULL;
    if (cgltf_parse(&opts, bytes, byte_len, &data) != cgltf_result_success) {
        return false;
    }
    cgltf_load_buffers(&opts, data, NULL);

    for (cgltf_size m = 0; m < data->meshes_count; m++) {
        for (cgltf_size p = 0; p < data->meshes[m].primitives_count; p++) {
            const cgltf_primitive *prim = &data->meshes[m].primitives[p];
            const cgltf_accessor *acc_pos = NULL, *acc_nrm = NULL, *acc_uv = NULL;
            const cgltf_accessor *acc_jnt = NULL, *acc_wgt = NULL;
            for (cgltf_size a = 0; a < prim->attributes_count; a++) {
                if (prim->attributes[a].type == cgltf_attribute_type_position) acc_pos = prim->attributes[a].data;
                else if (prim->attributes[a].type == cgltf_attribute_type_normal) acc_nrm = prim->attributes[a].data;
                else if (prim->attributes[a].type == cgltf_attribute_type_texcoord) acc_uv = prim->attributes[a].data;
                else if (prim->attributes[a].type == cgltf_attribute_type_joints) acc_jnt = prim->attributes[a].data;
                else if (prim->attributes[a].type == cgltf_attribute_type_weights) acc_wgt = prim->attributes[a].data;
            }
            if (!acc_pos) continue;
            size_t vc = acc_pos->count;
            size_t ic = prim->indices ? prim->indices->count : vc;
            if (!reserve_mesh(out, vc, ic)) break;

            uint32_t base = (uint32_t)out->vert_count;
            for (size_t i = 0; i < vc; i++) {
                float pv[3] = {0, 0, 0}, nv[3] = {0, 1, 0}, tv[2] = {0, 0};
                cgltf_accessor_read_float(acc_pos, i, pv, 3);
                if (acc_nrm) cgltf_accessor_read_float(acc_nrm, i, nv, 3);
                if (acc_uv) cgltf_accessor_read_float(acc_uv, i, tv, 2);
                eng_vertex_t vt = make_vert(
                    eng_v3(pv[0], pv[1], pv[2]),
                    eng_v3(nv[0], nv[1], nv[2]),
                    tv[0], tv[1], (eng_vec4_t){1, 1, 1, 1}
                );
                if (acc_jnt && acc_wgt) {
                    cgltf_uint jv[4] = {0, 0, 0, 0};
                    float wv[4] = {1, 0, 0, 0};
                    cgltf_accessor_read_uint(acc_jnt, i, jv, 4);
                    cgltf_accessor_read_float(acc_wgt, i, wv, 4);
                    for (int k = 0; k < 4; k++) {
                        vt.joints[k] = (uint8_t)(jv[k] & 0xFFu);
                        vt.weights[k] = wv[k];
                    }
                }
                out->verts[out->vert_count++] = vt;
            }
            for (size_t i = 0; i < ic; i++) {
                uint32_t idx = prim->indices ? (uint32_t)cgltf_accessor_read_index(prim->indices, i) : (uint32_t)i;
                out->indices[out->idx_count++] = base + idx;
            }
        }
    }
    cgltf_free(data);
    return out->vert_count > 0 && out->idx_count >= 3;
}

eng_asset_cache_t *eng_asset_cache_create(eng_vfs_t *vfs) {
    eng_asset_cache_t *c = (eng_asset_cache_t *)calloc(1, sizeof(eng_asset_cache_t));
    if (!c) return NULL;
    c->vfs = vfs;
    /* Slot 0 default 1x1 white texture */
    uint8_t white[4] = {255, 255, 255, 255};
    eng_asset_create_texture_rgba(c, "__default_white", 1, 1, white, true);
    return c;
}

void eng_asset_cache_destroy(eng_asset_cache_t *cache) {
    if (!cache) return;
    const eng_gl_api_t *gl = eng_gl();
    for (uint32_t i = 0; i < cache->mesh_count; i++) {
        eng_gpu_mesh_t *gm = &cache->meshes[i].gpu;
        if (gm->valid && gl->DeleteVertexArrays) {
            gl->DeleteBuffers(1, &gm->vbo);
            gl->DeleteBuffers(1, &gm->ebo);
            gl->DeleteBuffers(1, &gm->instance_vbo);
            gl->DeleteVertexArrays(1, &gm->vao);
        }
    }
    for (uint32_t i = 0; i < cache->tex_count; i++) {
        if (cache->texs[i].gpu.valid && gl->DeleteTextures) {
            gl->DeleteTextures(1, &cache->texs[i].gpu.tex_id);
        }
    }
    free(cache);
}

uint32_t eng_asset_upload_mesh_lods(eng_asset_cache_t *cache, const char *key, const eng_mesh_data_t *lods, int lod_count) {
    if (!cache || !lods || lod_count <= 0 || lods[0].vert_count == 0 || lods[0].idx_count == 0 ||
        cache->mesh_count >= ENG_MAX_CACHED_MESHES) {
        return 0;
    }
    if (lod_count > 4) lod_count = 4;

    eng_mesh_data_t packed;
    eng_mesh_data_init(&packed);
    uint32_t offsets[4] = {0, 0, 0, 0};
    uint32_t counts[4] = {0, 0, 0, 0};
    eng_mat4_t ident = eng_mat4_identity();
    for (int l = 0; l < lod_count; l++) {
        offsets[l] = (uint32_t)packed.idx_count;
        counts[l] = (uint32_t)lods[l].idx_count;
        if (!eng_mesh_append_transformed(&packed, &lods[l], &ident, (eng_vec4_t){1, 1, 1, 1})) {
            eng_mesh_data_free(&packed);
            return 0;
        }
    }
    for (int l = lod_count; l < 4; l++) {
        offsets[l] = offsets[lod_count - 1];
        counts[l] = counts[lod_count - 1];
    }

    const eng_gl_api_t *gl = eng_gl();
    uint32_t slot = cache->mesh_count++;
    cached_mesh_t *cm = &cache->meshes[slot];
    snprintf(cm->key, sizeof(cm->key), "%s", key ? key : "proc_mesh");

    eng_gpu_mesh_t *gm = &cm->gpu;
    gm->local_aabb = (eng_aabb_t){eng_v3(FLT_MAX, FLT_MAX, FLT_MAX), eng_v3(-FLT_MAX, -FLT_MAX, -FLT_MAX)};
    for (size_t i = 0; i < lods[0].vert_count; i++) {
        const float *p = lods[0].verts[i].pos;
        if (p[0] < gm->local_aabb.min.x) gm->local_aabb.min.x = p[0];
        if (p[1] < gm->local_aabb.min.y) gm->local_aabb.min.y = p[1];
        if (p[2] < gm->local_aabb.min.z) gm->local_aabb.min.z = p[2];
        if (p[0] > gm->local_aabb.max.x) gm->local_aabb.max.x = p[0];
        if (p[1] > gm->local_aabb.max.y) gm->local_aabb.max.y = p[1];
        if (p[2] > gm->local_aabb.max.z) gm->local_aabb.max.z = p[2];
    }

    gl->GenVertexArrays(1, &gm->vao);
    gl->BindVertexArray(gm->vao);

    gl->GenBuffers(1, &gm->vbo);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, gm->vbo);
    gl->BufferData(ENG_GL_ARRAY_BUFFER, (GLsizeiptr)(packed.vert_count * sizeof(eng_vertex_t)), packed.verts, ENG_GL_STATIC_DRAW);

    gl->GenBuffers(1, &gm->ebo);
    gl->BindBuffer(ENG_GL_ELEMENT_ARRAY_BUFFER, gm->ebo);
    gl->BufferData(ENG_GL_ELEMENT_ARRAY_BUFFER, (GLsizeiptr)(packed.idx_count * sizeof(uint32_t)), packed.indices, ENG_GL_STATIC_DRAW);

    /* Attributes 0..3: pos, norm, uv, color; 8..9: joints, weights */
    gl->EnableVertexAttribArray(0);
    gl->VertexAttribPointer(0, 3, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, pos));
    gl->EnableVertexAttribArray(1);
    gl->VertexAttribPointer(1, 3, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, norm));
    gl->EnableVertexAttribArray(2);
    gl->VertexAttribPointer(2, 2, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, uv));
    gl->EnableVertexAttribArray(3);
    gl->VertexAttribPointer(3, 4, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, color));
    gl->EnableVertexAttribArray(8);
    gl->VertexAttribPointer(8, 4, ENG_GL_UNSIGNED_BYTE, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, joints));
    gl->EnableVertexAttribArray(9);
    gl->VertexAttribPointer(9, 4, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_vertex_t), (const void *)offsetof(eng_vertex_t, weights));

    /* Per-instance 4x4 model matrix on locations 4..7 */
    gl->GenBuffers(1, &gm->instance_vbo);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, gm->instance_vbo);
    gl->BufferData(ENG_GL_ARRAY_BUFFER, sizeof(eng_mat4_t), ident.m, ENG_GL_DYNAMIC_DRAW);
    for (GLuint c = 0; c < 4; c++) {
        gl->EnableVertexAttribArray(4u + c);
        gl->VertexAttribPointer(4u + c, 4, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_mat4_t), (const void *)(uintptr_t)(c * 16u));
        gl->VertexAttribDivisor(4u + c, 1u);
    }

    gl->BindVertexArray(0);
    for (int l = 0; l < 4; l++) {
        gm->lod_index_offsets[l] = offsets[l];
        gm->lod_index_counts[l] = counts[l];
    }
    gm->valid = true;
    eng_mesh_data_free(&packed);
    return slot + 1u;
}

uint32_t eng_asset_upload_mesh(eng_asset_cache_t *cache, const char *key, const eng_mesh_data_t *md) {
    return eng_asset_upload_mesh_lods(cache, key, md, 1);
}

uint32_t eng_asset_load_mesh(eng_asset_cache_t *cache, const char *vpath) {
    if (!cache || !vpath) return 0;
    for (uint32_t i = 0; i < cache->mesh_count; i++) {
        if (strcmp(cache->meshes[i].key, vpath) == 0) return i + 1u;
    }
    if (!cache->vfs) return 0;
    size_t sz = 0;
    void *raw = eng_vfs_read_all(cache->vfs, vpath, &sz);
    if (!raw) return 0;

    eng_mesh_data_t md;
    bool ok = false;
    const char *ext = strrchr(vpath, '.');
    if (ext && strcmp(ext, ".obj") == 0) {
        ok = eng_mesh_parse_obj(&md, (const char *)raw);
    } else {
        ok = eng_mesh_parse_gltf(&md, raw, sz);
    }
    free(raw);
    if (!ok) {
        eng_mesh_data_free(&md);
        return 0;
    }
    uint32_t id = eng_asset_upload_mesh(cache, vpath, &md);
    eng_mesh_data_free(&md);
    return id;
}

const eng_gpu_mesh_t *eng_asset_get_mesh(const eng_asset_cache_t *cache, uint32_t mesh_id) {
    if (!cache || mesh_id == 0 || mesh_id > cache->mesh_count) return NULL;
    return &cache->meshes[mesh_id - 1u].gpu;
}

uint32_t eng_asset_create_texture_rgba(eng_asset_cache_t *cache, const char *key,
                                       int w, int h, const uint8_t *rgba, bool nearest) {
    if (!cache || w <= 0 || h <= 0 || !rgba || cache->tex_count >= ENG_MAX_CACHED_TEX) return 0;
    const eng_gl_api_t *gl = eng_gl();
    uint32_t slot = cache->tex_count++;
    cached_tex_t *ct = &cache->texs[slot];
    snprintf(ct->key, sizeof(ct->key), "%s", key ? key : "proc_tex");

    GLuint tid = 0;
    gl->GenTextures(1, &tid);
    gl->BindTexture(ENG_GL_TEXTURE_2D, tid);
    gl->TexImage2D(ENG_GL_TEXTURE_2D, 0, ENG_GL_RGBA8, w, h, 0, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, rgba);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_WRAP_S, ENG_GL_REPEAT);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_WRAP_T, ENG_GL_REPEAT);
    if (nearest) {
        gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MIN_FILTER, ENG_GL_NEAREST);
        gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MAG_FILTER, ENG_GL_NEAREST);
    } else {
        gl->GenerateMipmap(ENG_GL_TEXTURE_2D);
        gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MIN_FILTER, ENG_GL_LINEAR_MIPMAP_LINEAR);
        gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MAG_FILTER, ENG_GL_LINEAR);
    }
    ct->gpu = (eng_gpu_tex_t){tid, w, h, nearest, true, false};
    return slot + 1u;
}

uint32_t eng_asset_load_texture(eng_asset_cache_t *cache, const char *vpath, bool nearest) {
    if (!cache || !vpath) return 0;
    for (uint32_t i = 0; i < cache->tex_count; i++) {
        if (strcmp(cache->texs[i].key, vpath) == 0) return i + 1u;
    }
    if (!cache->vfs) return 0;
    size_t sz = 0;
    void *raw = eng_vfs_read_all(cache->vfs, vpath, &sz);
    if (!raw) return 0;

    int w = 0, h = 0, ch = 0;
    stbi_uc *px = stbi_load_from_memory((const stbi_uc *)raw, (int)sz, &w, &h, &ch, 4);
    free(raw);
    if (!px) return 0;
    uint32_t id = eng_asset_create_texture_rgba(cache, vpath, w, h, px, nearest);
    stbi_image_free(px);
    return id;
}

uint32_t eng_asset_create_cubemap_rgba(eng_asset_cache_t *cache, const char *key, int size,
                                       const uint8_t *const faces_rgba[6], bool nearest) {
    if (!cache || size <= 0 || !faces_rgba || cache->tex_count >= ENG_MAX_CACHED_TEX) return 0;
    for (int i = 0; i < 6; i++) {
        if (!faces_rgba[i]) return 0;
    }
    const eng_gl_api_t *gl = eng_gl();
    uint32_t slot = cache->tex_count++;
    cached_tex_t *ct = &cache->texs[slot];
    snprintf(ct->key, sizeof(ct->key), "%s", key ? key : "proc_cube");

    GLuint tid = 0;
    gl->GenTextures(1, &tid);
    gl->BindTexture(ENG_GL_TEXTURE_CUBE_MAP, tid);
    for (int i = 0; i < 6; i++) {
        gl->TexImage2D(ENG_GL_TEXTURE_CUBE_MAP_POSITIVE_X + (GLenum)i, 0, ENG_GL_RGBA8,
                       size, size, 0, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, faces_rgba[i]);
    }
    GLint filt = nearest ? (GLint)ENG_GL_NEAREST : (GLint)ENG_GL_LINEAR;
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_MIN_FILTER, filt);
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_MAG_FILTER, filt);
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_WRAP_S, ENG_GL_CLAMP_TO_EDGE);
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_WRAP_T, ENG_GL_CLAMP_TO_EDGE);
    gl->TexParameteri(ENG_GL_TEXTURE_CUBE_MAP, ENG_GL_TEXTURE_WRAP_R, ENG_GL_CLAMP_TO_EDGE);
    ct->gpu = (eng_gpu_tex_t){tid, size, size, nearest, true, true};
    return slot + 1u;
}

uint32_t eng_asset_load_cubemap(eng_asset_cache_t *cache, const char *const face_vpaths[6], bool nearest) {
    if (!cache || !cache->vfs || !face_vpaths) return 0;
    for (int i = 0; i < 6; i++) {
        if (!face_vpaths[i] || !face_vpaths[i][0]) return 0;
    }
    char key[128];
    snprintf(key, sizeof(key), "cube:%s|%s", face_vpaths[0], face_vpaths[5]);
    for (uint32_t i = 0; i < cache->tex_count; i++) {
        if (strcmp(cache->texs[i].key, key) == 0 && cache->texs[i].gpu.is_cubemap) return i + 1u;
    }
    stbi_uc *px[6] = {0};
    int size = 0;
    bool ok = true;
    for (int i = 0; i < 6; i++) {
        size_t sz = 0;
        void *raw = eng_vfs_read_all(cache->vfs, face_vpaths[i], &sz);
        if (!raw) { ok = false; break; }
        int w = 0, h = 0, ch = 0;
        px[i] = stbi_load_from_memory((const stbi_uc *)raw, (int)sz, &w, &h, &ch, 4);
        free(raw);
        if (!px[i] || w <= 0 || w != h || (size > 0 && w != size)) { ok = false; break; }
        size = w;
    }
    uint32_t id = 0;
    if (ok) {
        const uint8_t *faces[6] = {px[0], px[1], px[2], px[3], px[4], px[5]};
        id = eng_asset_create_cubemap_rgba(cache, key, size, faces, nearest);
    }
    for (int i = 0; i < 6; i++) {
        if (px[i]) stbi_image_free(px[i]);
    }
    return id;
}

const eng_gpu_tex_t *eng_asset_get_texture(const eng_asset_cache_t *cache, uint32_t tex_id) {
    if (!cache) return NULL;
    if (tex_id == 0 || tex_id > cache->tex_count) {
        return cache->tex_count > 0 ? &cache->texs[0].gpu : NULL;
    }
    return &cache->texs[tex_id - 1u].gpu;
}

bool eng_asset_write_png(const char *host_path, int w, int h, const uint8_t *gl_rgba_bottom_up) {
    if (!host_path || w <= 0 || h <= 0 || !gl_rgba_bottom_up) return false;
    size_t row_bytes = (size_t)w * 4u;
    uint8_t *flipped = (uint8_t *)malloc(row_bytes * (size_t)h);
    if (!flipped) return false;
    for (int y = 0; y < h; y++) {
        memcpy(flipped + (size_t)y * row_bytes, gl_rgba_bottom_up + (size_t)(h - 1 - y) * row_bytes, row_bytes);
    }
    int ok = stbi_write_png(host_path, w, h, 4, flipped, (int)row_bytes);
    free(flipped);
    return ok != 0;
}
