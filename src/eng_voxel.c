#include "engine/eng_voxel.h"

#include <ctype.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static int vox_idx(const eng_voxel_chunk_t *c, int x, int y, int z) {
    return (y * c->sz + z) * c->sx + x;
}

void eng_voxel_chunk_init(eng_voxel_chunk_t *chunk, int sx, int sy, int sz, float voxel_size) {
    if (!chunk) return;
    memset(chunk, 0, sizeof(*chunk));
    chunk->sx = sx > 0 && sx <= ENG_VOXEL_MAX_DIM ? sx : 16;
    chunk->sy = sy > 0 && sy <= ENG_VOXEL_MAX_DIM ? sy : 16;
    chunk->sz = sz > 0 && sz <= ENG_VOXEL_MAX_DIM ? sz : 16;
    chunk->voxel_size = voxel_size > 0.01f ? voxel_size : 1.0f;
    chunk->dirty = true;

    /* Default retro 16+ palette */
    static const uint8_t def_pal[8][3] = {
        {0, 0, 0}, {120, 125, 135}, {92, 168, 72}, {138, 96, 62},
        {214, 78, 66}, {68, 136, 224}, {238, 198, 72}, {235, 238, 242}
    };
    for (int i = 1; i < 256; i++) {
        const uint8_t *rgb = def_pal[(i - 1) % 7 + 1];
        eng_voxel_set_palette_color(chunk, (uint8_t)i, rgb[0], rgb[1], rgb[2], 255);
    }
}

void eng_voxel_set_palette_color(eng_voxel_chunk_t *chunk, uint8_t id, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    if (!chunk) return;
    chunk->palette[id] = (uint32_t)r | ((uint32_t)g << 8) | ((uint32_t)b << 16) | ((uint32_t)a << 24);
    chunk->dirty = true;
}

uint8_t eng_voxel_get(const eng_voxel_chunk_t *c, int x, int y, int z) {
    if (!c || x < 0 || y < 0 || z < 0 || x >= c->sx || y >= c->sy || z >= c->sz) return 0;
    return c->blocks[vox_idx(c, x, y, z)];
}

bool eng_voxel_set(eng_voxel_chunk_t *c, int x, int y, int z, uint8_t block_id) {
    if (!c || x < 0 || y < 0 || z < 0 || x >= c->sx || y >= c->sy || z >= c->sz) return false;
    c->blocks[vox_idx(c, x, y, z)] = block_id;
    c->dirty = true;
    return true;
}

bool eng_voxel_from_ascii(eng_voxel_chunk_t *chunk, const char *const *layers_y, int num_layers) {
    if (!chunk || !layers_y || num_layers <= 0) return false;
    memset(chunk->blocks, 0, sizeof(chunk->blocks));
    for (int y = 0; y < num_layers && y < chunk->sy; y++) {
        const char *p = layers_y[y];
        if (!p) continue;
        int z = 0, x = 0;
        while (*p && z < chunk->sz) {
            if (*p == '\n') {
                z++;
                x = 0;
            } else if (*p != '\r') {
                if (x < chunk->sx) {
                    uint8_t id = 0;
                    if (*p >= '1' && *p <= '9') id = (uint8_t)(*p - '0');
                    else if (*p >= 'A' && *p <= 'Z') id = (uint8_t)(10 + (*p - 'A'));
                    else if (*p == '#') id = 1;
                    chunk->blocks[vox_idx(chunk, x, y, z)] = id;
                    x++;
                }
            }
            p++;
        }
    }
    chunk->dirty = true;
    return true;
}

static uint32_t rd_le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

bool eng_voxel_load_vox(eng_voxel_chunk_t *chunk, const void *bytes, size_t byte_len) {
    const uint8_t *b = (const uint8_t *)bytes;
    if (!chunk || !b || byte_len < 20 || memcmp(b, "VOX ", 4) != 0) return false;
    eng_voxel_chunk_init(chunk, 16, 16, 16, 1.0f);

    size_t pos = 8;
    while (pos + 12 <= byte_len) {
        char id[5] = {0};
        memcpy(id, b + pos, 4);
        uint32_t content_sz = rd_le32(b + pos + 4);
        pos += 12;
        if (pos + content_sz > byte_len) break;

        if (strcmp(id, "MAIN") == 0) {
            continue; /* Descend directly into children right after MAIN header */
        } else if (strcmp(id, "SIZE") == 0 && content_sz >= 12) {
            int vx = (int)rd_le32(b + pos);
            int vz = (int)rd_le32(b + pos + 4); /* MagicaVoxel Z-up -> Engine Y-up */
            int vy = (int)rd_le32(b + pos + 8);
            eng_voxel_chunk_init(chunk,
                                 vx <= ENG_VOXEL_MAX_DIM ? vx : ENG_VOXEL_MAX_DIM,
                                 vy <= ENG_VOXEL_MAX_DIM ? vy : ENG_VOXEL_MAX_DIM,
                                 vz <= ENG_VOXEL_MAX_DIM ? vz : ENG_VOXEL_MAX_DIM, 1.0f);
        } else if (strcmp(id, "XYZI") == 0 && content_sz >= 4) {
            uint32_t n = rd_le32(b + pos);
            for (uint32_t i = 0; i < n && 4u + i * 4u + 4u <= content_sz; i++) {
                const uint8_t *v = b + pos + 4u + i * 4u;
                eng_voxel_set(chunk, v[0], v[2], v[1], v[3]); /* Swap Z-up to Y-up */
            }
        } else if (strcmp(id, "RGBA") == 0 && content_sz >= 1024) {
            for (int i = 0; i < 255; i++) {
                const uint8_t *c = b + pos + (size_t)i * 4u;
                eng_voxel_set_palette_color(chunk, (uint8_t)(i + 1), c[0], c[1], c[2], c[3]);
            }
        }
        pos += content_sz;
    }
    return true;
}

static void apply_csg_cell(eng_voxel_chunk_t *c, int x, int y, int z, bool inside, uint8_t id, eng_csg_op_t op) {
    uint8_t cur = eng_voxel_get(c, x, y, z);
    if (op == ENG_CSG_UNION && inside) eng_voxel_set(c, x, y, z, id);
    else if (op == ENG_CSG_SUBTRACT && inside) eng_voxel_set(c, x, y, z, 0);
    else if (op == ENG_CSG_INTERSECT && !inside && cur != 0) eng_voxel_set(c, x, y, z, 0);
}

void eng_voxel_csg_box(eng_voxel_chunk_t *c, int x0, int y0, int z0, int x1, int y1, int z1, uint8_t id, eng_csg_op_t op) {
    if (!c) return;
    for (int y = 0; y < c->sy; y++) {
        for (int z = 0; z < c->sz; z++) {
            for (int x = 0; x < c->sx; x++) {
                bool in = (x >= x0 && x <= x1 && y >= y0 && y <= y1 && z >= z0 && z <= z1);
                apply_csg_cell(c, x, y, z, in, id, op);
            }
        }
    }
}

void eng_voxel_csg_sphere(eng_voxel_chunk_t *c, float cx, float cy, float cz, float radius, uint8_t id, eng_csg_op_t op) {
    if (!c) return;
    float r2 = radius * radius;
    for (int y = 0; y < c->sy; y++) {
        for (int z = 0; z < c->sz; z++) {
            for (int x = 0; x < c->sx; x++) {
                float dx = ((float)x + 0.5f) - cx;
                float dy = ((float)y + 0.5f) - cy;
                float dz = ((float)z + 0.5f) - cz;
                apply_csg_cell(c, x, y, z, (dx * dx + dy * dy + dz * dz) <= r2, id, op);
            }
        }
    }
}

static uint8_t vert_ao(int s1, int s2, int corner) {
    if (s1 && s2) return 0; /* Deepest occlusion */
    return (uint8_t)(3 - (s1 + s2 + corner));
}

bool eng_voxel_build_mesh(eng_voxel_chunk_t *chunk, eng_mesh_data_t *out_mesh) {
    if (!chunk || !out_mesh) return false;
    eng_mesh_data_init(out_mesh);
    const int dims[3] = {chunk->sx, chunk->sy, chunk->sz};
    const float vs = chunk->voxel_size;
    uint32_t mask[ENG_VOXEL_MAX_DIM * ENG_VOXEL_MAX_DIM];

    /* Sweep all 3 axes in both -1 and +1 normal directions */
    for (int axis = 0; axis < 3; axis++) {
        int u = (axis + 1) % 3;
        int v = (axis + 2) % 3;
        int du_len = dims[u], dv_len = dims[v];

        for (int dir = -1; dir <= 1; dir += 2) {
            for (int slice = 0; slice < dims[axis]; slice++) {
                memset(mask, 0, (size_t)(du_len * dv_len) * sizeof(uint32_t));

                for (int j = 0; j < dv_len; j++) {
                    for (int i = 0; i < du_len; i++) {
                        int p[3] = {0, 0, 0}, np[3] = {0, 0, 0};
                        p[axis] = slice; p[u] = i; p[v] = j;
                        np[axis] = slice + dir; np[u] = i; np[v] = j;

                        uint8_t blk = eng_voxel_get(chunk, p[0], p[1], p[2]);
                        if (blk == 0 || eng_voxel_get(chunk, np[0], np[1], np[2]) != 0) continue;

                        /* Sample 8 neighbors in the tangent plane at np[axis] for 4-corner AO */
                        uint8_t ao[4];
                        const int su[4] = {-1,  1,  1, -1};
                        const int sv[4] = {-1, -1,  1,  1};
                        for (int k = 0; k < 4; k++) {
                            int a1[3] = {np[0], np[1], np[2]}, a2[3] = {np[0], np[1], np[2]}, ac[3] = {np[0], np[1], np[2]};
                            a1[u] += su[k];
                            a2[v] += sv[k];
                            ac[u] += su[k]; ac[v] += sv[k];
                            ao[k] = vert_ao(eng_voxel_get(chunk, a1[0], a1[1], a1[2]) != 0,
                                            eng_voxel_get(chunk, a2[0], a2[1], a2[2]) != 0,
                                            eng_voxel_get(chunk, ac[0], ac[1], ac[2]) != 0);
                        }
                        mask[j * du_len + i] = (uint32_t)blk |
                                               ((uint32_t)ao[0] << 8) | ((uint32_t)ao[1] << 10) |
                                               ((uint32_t)ao[2] << 12) | ((uint32_t)ao[3] << 14);
                    }
                }

                /* Greedy 2D rectangle merge across mask */
                for (int j = 0; j < dv_len; j++) {
                    for (int i = 0; i < du_len;) {
                        uint32_t key = mask[j * du_len + i];
                        if (!key) { i++; continue; }
                        int w = 1;
                        while (i + w < du_len && mask[j * du_len + i + w] == key) w++;
                        int h = 1;
                        for (; j + h < dv_len; h++) {
                            bool row_ok = true;
                            for (int k = 0; k < w; k++) {
                                if (mask[(j + h) * du_len + i + k] != key) { row_ok = false; break; }
                            }
                            if (!row_ok) break;
                        }
                        for (int hy = 0; hy < h; hy++) {
                            for (int wx = 0; wx < w; wx++) mask[(j + hy) * du_len + i + wx] = 0;
                        }

                        /* Emit merged quad */
                        uint8_t blk = (uint8_t)(key & 0xFFu);
                        uint32_t rgba = chunk->palette[blk];
                        float cr = (float)(rgba & 0xFFu) / 255.0f;
                        float cg = (float)((rgba >> 8) & 0xFFu) / 255.0f;
                        float cb = (float)((rgba >> 16) & 0xFFu) / 255.0f;
                        float ca = (float)((rgba >> 24) & 0xFFu) / 255.0f;

                        float cpos[4][3];
                        const int du_off[4] = {0, w, w, 0};
                        const int dv_off[4] = {0, 0, h, h};
                        float slice_plane = (float)(slice + (dir > 0 ? 1 : 0));
                        for (int k = 0; k < 4; k++) {
                            cpos[k][axis] = slice_plane * vs;
                            cpos[k][u] = (float)(i + du_off[k]) * vs;
                            cpos[k][v] = (float)(j + dv_off[k]) * vs;
                        }
                        float nrm[3] = {0, 0, 0};
                        nrm[axis] = (float)dir;

                        size_t need_v = out_mesh->vert_count + 4;
                        size_t need_i = out_mesh->idx_count + 6;
                        if (need_v > out_mesh->vert_cap) {
                            size_t nc = out_mesh->vert_cap ? out_mesh->vert_cap * 2 : 256;
                            while (nc < need_v) nc *= 2;
                            out_mesh->verts = (eng_vertex_t *)realloc(out_mesh->verts, nc * sizeof(eng_vertex_t));
                            out_mesh->vert_cap = nc;
                        }
                        if (need_i > out_mesh->idx_cap) {
                            size_t nc = out_mesh->idx_cap ? out_mesh->idx_cap * 2 : 512;
                            while (nc < need_i) nc *= 2;
                            out_mesh->indices = (uint32_t *)realloc(out_mesh->indices, nc * sizeof(uint32_t));
                            out_mesh->idx_cap = nc;
                        }

                        uint32_t base = (uint32_t)out_mesh->vert_count;
                        static const float ao_lut[4] = {0.40f, 0.62f, 0.82f, 1.00f};
                        for (int k = 0; k < 4; k++) {
                            uint8_t aok = (uint8_t)((key >> (8 + k * 2)) & 3u);
                            float shade = ao_lut[aok];
                            eng_vertex_t vt;
                            memset(&vt, 0, sizeof(vt));
                            vt.pos[0] = cpos[k][0]; vt.pos[1] = cpos[k][1]; vt.pos[2] = cpos[k][2];
                            vt.norm[0] = nrm[0]; vt.norm[1] = nrm[1]; vt.norm[2] = nrm[2];
                            vt.uv[0] = (float)du_off[k]; vt.uv[1] = (float)dv_off[k];
                            vt.color[0] = cr * shade; vt.color[1] = cg * shade; vt.color[2] = cb * shade; vt.color[3] = ca;
                            vt.weights[0] = 1.0f;
                            out_mesh->verts[out_mesh->vert_count++] = vt;
                        }
                        if (dir > 0) {
                            out_mesh->indices[out_mesh->idx_count++] = base + 0;
                            out_mesh->indices[out_mesh->idx_count++] = base + 1;
                            out_mesh->indices[out_mesh->idx_count++] = base + 2;
                            out_mesh->indices[out_mesh->idx_count++] = base + 0;
                            out_mesh->indices[out_mesh->idx_count++] = base + 2;
                            out_mesh->indices[out_mesh->idx_count++] = base + 3;
                        } else {
                            out_mesh->indices[out_mesh->idx_count++] = base + 0;
                            out_mesh->indices[out_mesh->idx_count++] = base + 2;
                            out_mesh->indices[out_mesh->idx_count++] = base + 1;
                            out_mesh->indices[out_mesh->idx_count++] = base + 0;
                            out_mesh->indices[out_mesh->idx_count++] = base + 3;
                            out_mesh->indices[out_mesh->idx_count++] = base + 2;
                        }
                        i += w;
                    }
                }
            }
        }
    }
    chunk->dirty = false;
    return true;
}

eng_voxel_hit_t eng_voxel_raycast(const eng_voxel_chunk_t *chunk, eng_vec3_t origin, eng_vec3_t dir, float max_dist) {
    eng_voxel_hit_t res;
    memset(&res, 0, sizeof(res));
    if (!chunk || max_dist <= 0.0f) return res;
    eng_vec3_t d = eng_v3_norm(dir);
    if (eng_v3_dot(d, d) < 0.5f) return res;

    float inv_vs = 1.0f / chunk->voxel_size;
    float ox = origin.x * inv_vs, oy = origin.y * inv_vs, oz = origin.z * inv_vs;
    int x = (int)floorf(ox), y = (int)floorf(oy), z = (int)floorf(oz);
    int step_x = d.x >= 0.0f ? 1 : -1;
    int step_y = d.y >= 0.0f ? 1 : -1;
    int step_z = d.z >= 0.0f ? 1 : -1;

    float t_dx = fabsf(d.x) > ENG_EPSILON ? fabsf(1.0f / d.x) : 1e30f;
    float t_dy = fabsf(d.y) > ENG_EPSILON ? fabsf(1.0f / d.y) : 1e30f;
    float t_dz = fabsf(d.z) > ENG_EPSILON ? fabsf(1.0f / d.z) : 1e30f;

    float t_mx = (d.x >= 0.0f ? ((float)(x + 1) - ox) : (ox - (float)x)) * t_dx;
    float t_my = (d.y >= 0.0f ? ((float)(y + 1) - oy) : (oy - (float)y)) * t_dy;
    float t_mz = (d.z >= 0.0f ? ((float)(z + 1) - oz) : (oz - (float)z)) * t_dz;

    float max_grid_t = max_dist * inv_vs;
    float t = 0.0f;
    int nx = 0, ny = 0, nz = 0;

    for (int iter = 0; iter < 256 && t <= max_grid_t; iter++) {
        uint8_t blk = eng_voxel_get(chunk, x, y, z);
        if (blk != 0) {
            res.hit = true;
            res.vx = x; res.vy = y; res.vz = z;
            res.nx = nx; res.ny = ny; res.nz = nz;
            res.dist = t * chunk->voxel_size;
            res.block_id = blk;
            return res;
        }
        if (t_mx < t_my && t_mx < t_mz) {
            x += step_x; t = t_mx; t_mx += t_dx;
            nx = -step_x; ny = 0; nz = 0;
        } else if (t_my < t_mz) {
            y += step_y; t = t_my; t_my += t_dy;
            nx = 0; ny = -step_y; nz = 0;
        } else {
            z += step_z; t = t_mz; t_mz += t_dz;
            nx = 0; ny = 0; nz = -step_z;
        }
    }
    return res;
}

size_t eng_voxel_extract_floating_islands(eng_voxel_chunk_t *src,
                                          eng_voxel_chunk_t *out_islands,
                                          eng_vec3_t *out_local_origins,
                                          size_t max_islands) {
    if (!src || !out_islands || !out_local_origins || max_islands == 0) return 0;
    const int sx = src->sx, sy = src->sy, sz = src->sz;
    const int total = sx * sy * sz;
    if (total <= 0) return 0;

    uint8_t *vis = (uint8_t *)calloc((size_t)total, sizeof(uint8_t));
    uint16_t *queue = (uint16_t *)malloc((size_t)total * sizeof(uint16_t));
    if (!vis || !queue) {
        free(vis);
        free(queue);
        return 0;
    }

    static const int dirs[6][3] = {{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}};

    /* 1. Flood-fill all voxels grounded to y == 0 */
    int qh = 0, qt = 0;
    for (int z = 0; z < sz; z++) {
        for (int x = 0; x < sx; x++) {
            int idx = vox_idx(src, x, 0, z);
            if (src->blocks[idx] != 0 && !vis[idx]) {
                vis[idx] = 1;
                queue[qt++] = (uint16_t)idx;
            }
        }
    }
    while (qh < qt) {
        int cur = queue[qh++];
        int cx = cur % sx;
        int cz = (cur / sx) % sz;
        int cy = cur / (sx * sz);
        for (int d = 0; d < 6; d++) {
            int nx = cx + dirs[d][0], ny = cy + dirs[d][1], nz = cz + dirs[d][2];
            if (nx < 0 || ny < 0 || nz < 0 || nx >= sx || ny >= sy || nz >= sz) continue;
            int nidx = vox_idx(src, nx, ny, nz);
            if (src->blocks[nidx] != 0 && !vis[nidx]) {
                vis[nidx] = 1;
                queue[qt++] = (uint16_t)nidx;
            }
        }
    }

    /* 2. Extract each ungrounded 6-connected component into its own compact chunk */
    size_t count = 0;
    for (int y = 0; y < sy && count < max_islands; y++) {
        for (int z = 0; z < sz && count < max_islands; z++) {
            for (int x = 0; x < sx && count < max_islands; x++) {
                int start = vox_idx(src, x, y, z);
                if (src->blocks[start] == 0 || vis[start]) continue;

                qh = 0; qt = 0;
                vis[start] = 2;
                queue[qt++] = (uint16_t)start;
                int min_x = x, max_x = x, min_y = y, max_y = y, min_z = z, max_z = z;

                while (qh < qt) {
                    int cur = queue[qh++];
                    int cx = cur % sx;
                    int cz = (cur / sx) % sz;
                    int cy = cur / (sx * sz);
                    if (cx < min_x) min_x = cx;
                    if (cx > max_x) max_x = cx;
                    if (cy < min_y) min_y = cy;
                    if (cy > max_y) max_y = cy;
                    if (cz < min_z) min_z = cz;
                    if (cz > max_z) max_z = cz;

                    for (int d = 0; d < 6; d++) {
                        int nx = cx + dirs[d][0], ny = cy + dirs[d][1], nz = cz + dirs[d][2];
                        if (nx < 0 || ny < 0 || nz < 0 || nx >= sx || ny >= sy || nz >= sz) continue;
                        int nidx = vox_idx(src, nx, ny, nz);
                        if (src->blocks[nidx] != 0 && !vis[nidx]) {
                            vis[nidx] = 2;
                            queue[qt++] = (uint16_t)nidx;
                        }
                    }
                }

                eng_voxel_chunk_t *dst = &out_islands[count];
                eng_voxel_chunk_init(dst, max_x - min_x + 1, max_y - min_y + 1, max_z - min_z + 1, src->voxel_size);
                memcpy(dst->palette, src->palette, sizeof(src->palette));
                for (int i = 0; i < qt; i++) {
                    int vidx = queue[i];
                    int cx = vidx % sx;
                    int cz = (vidx / sx) % sz;
                    int cy = vidx / (sx * sz);
                    eng_voxel_set(dst, cx - min_x, cy - min_y, cz - min_z, src->blocks[vidx]);
                    src->blocks[vidx] = 0;
                }
                dst->dirty = true;
                src->dirty = true;
                out_local_origins[count] = eng_v3((float)min_x * src->voxel_size,
                                                  (float)min_y * src->voxel_size,
                                                  (float)min_z * src->voxel_size);
                count++;
            }
        }
    }

    free(vis);
    free(queue);
    return count;
}
