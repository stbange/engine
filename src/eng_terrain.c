#include "engine/eng_terrain.h"
#include "engine/eng_procgen.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

bool eng_terrain_init(eng_terrain_t *t, int grid_w, int grid_d, float cell_size, const float *heights_opt) {
    if (!t || grid_w < 2 || grid_d < 2 || cell_size <= 0.01f) return false;
    memset(t, 0, sizeof(*t));
    size_t count = (size_t)grid_w * (size_t)grid_d;
    t->heights = (float *)calloc(count, sizeof(float));
    if (!t->heights) return false;
    t->grid_w = grid_w;
    t->grid_d = grid_d;
    t->cell_size = cell_size;
    if (heights_opt) {
        memcpy(t->heights, heights_opt, count * sizeof(float));
    }
    return true;
}

void eng_terrain_free(eng_terrain_t *t) {
    if (!t) return;
    free(t->heights);
    memset(t, 0, sizeof(*t));
}

void eng_terrain_generate_hills(eng_terrain_t *t, uint64_t seed, float max_height, float freq) {
    if (!t || !t->heights) return;
    float f = freq > 0.0001f ? freq : 0.04f;
    for (int z = 0; z < t->grid_d; z++) {
        for (int x = 0; x < t->grid_w; x++) {
            float wx = (float)x * t->cell_size * f;
            float wz = (float)z * t->cell_size * f;
            float n = eng_noise_fbm3d(wx, 0.0f, wz, seed, 4, 2.0f, 0.5f);
            float r = eng_noise_ridged3d(wx * 0.5f, 3.1f, wz * 0.5f, seed ^ 0x9E3779B9u, 3);
            t->heights[z * t->grid_w + x] = (n * 0.6f + r * 0.4f) * max_height;
        }
    }
}

static float height_at_clamped(const eng_terrain_t *t, int gx, int gz) {
    if (gx < 0) gx = 0;
    if (gz < 0) gz = 0;
    if (gx >= t->grid_w) gx = t->grid_w - 1;
    if (gz >= t->grid_d) gz = t->grid_d - 1;
    return t->heights[gz * t->grid_w + gx];
}

float eng_terrain_sample_height(const eng_terrain_t *t, float world_x, float world_z) {
    if (!t || !t->heights) return 0.0f;
    float fx = eng_clampf(world_x / t->cell_size, 0.0f, (float)(t->grid_w - 1));
    float fz = eng_clampf(world_z / t->cell_size, 0.0f, (float)(t->grid_d - 1));
    int x0 = (int)floorf(fx);
    int z0 = (int)floorf(fz);
    int x1 = (x0 + 1 < t->grid_w) ? (x0 + 1) : x0;
    int z1 = (z0 + 1 < t->grid_d) ? (z0 + 1) : z0;
    float tx = fx - (float)x0;
    float tz = fz - (float)z0;

    float h00 = height_at_clamped(t, x0, z0);
    float h10 = height_at_clamped(t, x1, z0);
    float h01 = height_at_clamped(t, x0, z1);
    float h11 = height_at_clamped(t, x1, z1);
    return eng_lerpf(eng_lerpf(h00, h10, tx), eng_lerpf(h01, h11, tx), tz);
}

eng_vec3_t eng_terrain_sample_normal(const eng_terrain_t *t, float world_x, float world_z) {
    if (!t || !t->heights) return eng_v3(0.0f, 1.0f, 0.0f);
    float eps = t->cell_size * 0.5f;
    float hl = eng_terrain_sample_height(t, world_x - eps, world_z);
    float hr = eng_terrain_sample_height(t, world_x + eps, world_z);
    float hd = eng_terrain_sample_height(t, world_x, world_z - eps);
    float hu = eng_terrain_sample_height(t, world_x, world_z + eps);
    return eng_v3_norm(eng_v3(hl - hr, 2.0f * eps, hd - hu));
}

static eng_vec4_t splat_biome_color(float h, eng_vec3_t nrm) {
    /* 4-layer height + slope biome splatting: sand -> grass -> cliff rock -> snow */
    eng_vec3_t sand  = eng_v3(0.82f, 0.76f, 0.54f);
    eng_vec3_t grass = eng_v3(0.28f, 0.58f, 0.24f);
    eng_vec3_t rock  = eng_v3(0.44f, 0.42f, 0.40f);
    eng_vec3_t snow  = eng_v3(0.92f, 0.94f, 0.97f);

    eng_vec3_t base = (h < 1.5f) ? eng_v3_lerp(sand, grass, eng_clampf(h / 1.5f, 0.0f, 1.0f))
                                 : eng_v3_lerp(grass, snow, eng_clampf((h - 8.0f) / 6.0f, 0.0f, 1.0f));
    float slope = 1.0f - eng_clampf(nrm.y, 0.0f, 1.0f);
    eng_vec3_t col = eng_v3_lerp(base, rock, eng_clampf((slope - 0.25f) * 3.0f, 0.0f, 1.0f));
    return (eng_vec4_t){col.x, col.y, col.z, 1.0f};
}

bool eng_terrain_build_chunk_mesh(const eng_terrain_t *t, int x0, int z0, int x1, int z1,
                                  int lod_step, float skirt_depth, eng_mesh_data_t *out_mesh) {
    if (!t || !t->heights || !out_mesh) return false;
    eng_mesh_data_init(out_mesh);
    if (lod_step < 1) lod_step = 1;
    if (x0 < 0) x0 = 0;
    if (z0 < 0) z0 = 0;
    if (x1 >= t->grid_w) x1 = t->grid_w - 1;
    if (z1 >= t->grid_d) z1 = t->grid_d - 1;
    if (x1 - x0 < lod_step || z1 - z0 < lod_step) return false;

    int nx = ((x1 - x0) / lod_step) + 1;
    int nz = ((z1 - z0) / lod_step) + 1;
    size_t surf_v = (size_t)(nx * nz);
    size_t skirt_v = (skirt_depth > 0.0f) ? (size_t)(2 * (nx + nz)) : 0u;
    size_t max_v = surf_v + skirt_v;
    size_t max_i = (size_t)((nx - 1) * (nz - 1) * 6) + (skirt_v * 6u);

    out_mesh->verts = (eng_vertex_t *)calloc(max_v, sizeof(eng_vertex_t));
    out_mesh->indices = (uint32_t *)malloc(max_i * sizeof(uint32_t));
    if (!out_mesh->verts || !out_mesh->indices) {
        eng_mesh_data_free(out_mesh);
        return false;
    }
    out_mesh->vert_cap = max_v;
    out_mesh->idx_cap = max_i;

    for (int j = 0; j < nz; j++) {
        int gz = z0 + j * lod_step;
        if (gz > z1) gz = z1;
        for (int i = 0; i < nx; i++) {
            int gx = x0 + i * lod_step;
            if (gx > x1) gx = x1;
            float wx = (float)gx * t->cell_size;
            float wz = (float)gz * t->cell_size;
            float wy = height_at_clamped(t, gx, gz);
            eng_vec3_t nrm = eng_terrain_sample_normal(t, wx, wz);
            eng_vec4_t col = splat_biome_color(wy, nrm);

            eng_vertex_t *vt = &out_mesh->verts[out_mesh->vert_count++];
            vt->pos[0] = wx; vt->pos[1] = wy; vt->pos[2] = wz;
            vt->norm[0] = nrm.x; vt->norm[1] = nrm.y; vt->norm[2] = nrm.z;
            vt->uv[0] = (float)gx * 0.25f; vt->uv[1] = (float)gz * 0.25f;
            vt->color[0] = col.x; vt->color[1] = col.y; vt->color[2] = col.z; vt->color[3] = 1.0f;
            vt->weights[0] = 1.0f;
        }
    }

    for (int j = 0; j + 1 < nz; j++) {
        for (int i = 0; i + 1 < nx; i++) {
            uint32_t i0 = (uint32_t)(j * nx + i);
            uint32_t i1 = i0 + (uint32_t)nx;
            out_mesh->indices[out_mesh->idx_count++] = i0;
            out_mesh->indices[out_mesh->idx_count++] = i1;
            out_mesh->indices[out_mesh->idx_count++] = i0 + 1;
            out_mesh->indices[out_mesh->idx_count++] = i0 + 1;
            out_mesh->indices[out_mesh->idx_count++] = i1;
            out_mesh->indices[out_mesh->idx_count++] = i1 + 1;
        }
    }

    /* Append perimeter skirts along bottom edge (j=0) and top edge (j=nz-1) to seal LOD seams */
    if (skirt_depth > 0.0f) {
        const int rows[2] = {0, nz - 1};
        for (int r = 0; r < 2; r++) {
            uint32_t sk_base = (uint32_t)out_mesh->vert_count;
            for (int i = 0; i < nx; i++) {
                eng_vertex_t vt = out_mesh->verts[rows[r] * nx + i];
                vt.pos[1] -= skirt_depth;
                out_mesh->verts[out_mesh->vert_count++] = vt;
            }
            for (int i = 0; i + 1 < nx; i++) {
                uint32_t t0 = (uint32_t)(rows[r] * nx + i);
                uint32_t b0 = sk_base + (uint32_t)i;
                out_mesh->indices[out_mesh->idx_count++] = t0;
                out_mesh->indices[out_mesh->idx_count++] = b0;
                out_mesh->indices[out_mesh->idx_count++] = t0 + 1;
                out_mesh->indices[out_mesh->idx_count++] = t0 + 1;
                out_mesh->indices[out_mesh->idx_count++] = b0;
                out_mesh->indices[out_mesh->idx_count++] = b0 + 1;
            }
        }
    }
    return true;
}
