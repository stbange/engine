#include "engine/eng_procgen.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

static uint32_t hash3i(int x, int y, int z, uint64_t seed) {
    uint64_t h = seed ^ ((uint64_t)(uint32_t)x * 0x9E3779B185EBCA87ULL) ^
                        ((uint64_t)(uint32_t)y * 0xC2B2AE3D27D4EB4FULL) ^
                        ((uint64_t)(uint32_t)z * 0x165667B19E3779F9ULL);
    h ^= h >> 30;
    h *= 0xBF58476D1CE4E5B9ULL;
    h ^= h >> 27;
    h *= 0x94D049BB133111EBULL;
    h ^= h >> 31;
    return (uint32_t)h;
}

static float hash_f01(int x, int y, int z, uint64_t seed) {
    return (float)(hash3i(x, y, z, seed) >> 8) * (1.0f / 16777216.0f);
}

static float fade5(float t) {
    return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

float eng_noise_value3d(float x, float y, float z, uint64_t seed) {
    int ix = (int)floorf(x), iy = (int)floorf(y), iz = (int)floorf(z);
    float fx = fade5(x - (float)ix);
    float fy = fade5(y - (float)iy);
    float fz = fade5(z - (float)iz);

    float c000 = hash_f01(ix,     iy,     iz,     seed);
    float c100 = hash_f01(ix + 1, iy,     iz,     seed);
    float c010 = hash_f01(ix,     iy + 1, iz,     seed);
    float c110 = hash_f01(ix + 1, iy + 1, iz,     seed);
    float c001 = hash_f01(ix,     iy,     iz + 1, seed);
    float c101 = hash_f01(ix + 1, iy,     iz + 1, seed);
    float c011 = hash_f01(ix,     iy + 1, iz + 1, seed);
    float c111 = hash_f01(ix + 1, iy + 1, iz + 1, seed);

    float x00 = eng_lerpf(c000, c100, fx), x10 = eng_lerpf(c010, c110, fx);
    float x01 = eng_lerpf(c001, c101, fx), x11 = eng_lerpf(c011, c111, fx);
    float y0 = eng_lerpf(x00, x10, fy), y1 = eng_lerpf(x01, x11, fy);
    return eng_lerpf(y0, y1, fz) * 2.0f - 1.0f;
}

float eng_noise_value2d(float x, float y, uint64_t seed) {
    return eng_noise_value3d(x, y, 0.0f, seed);
}

static float grad3(uint32_t h, float x, float y, float z) {
    switch (h & 15u) {
        case 0:  return  x + y;
        case 1:  return -x + y;
        case 2:  return  x - y;
        case 3:  return -x - y;
        case 4:  return  x + z;
        case 5:  return -x + z;
        case 6:  return  x - z;
        case 7:  return -x - z;
        case 8:  return  y + z;
        case 9:  return -y + z;
        case 10: return  y - z;
        case 11: return -y - z;
        case 12: return  y + x;
        case 13: return -y + z;
        case 14: return  y - x;
        default: return -y - z;
    }
}

float eng_noise_perlin3d(float x, float y, float z, uint64_t seed) {
    int ix = (int)floorf(x), iy = (int)floorf(y), iz = (int)floorf(z);
    float dx = x - (float)ix, dy = y - (float)iy, dz = z - (float)iz;
    float u = fade5(dx), v = fade5(dy), w = fade5(dz);

    float n000 = grad3(hash3i(ix,     iy,     iz,     seed), dx,        dy,        dz);
    float n100 = grad3(hash3i(ix + 1, iy,     iz,     seed), dx - 1.0f, dy,        dz);
    float n010 = grad3(hash3i(ix,     iy + 1, iz,     seed), dx,        dy - 1.0f, dz);
    float n110 = grad3(hash3i(ix + 1, iy + 1, iz,     seed), dx - 1.0f, dy - 1.0f, dz);
    float n001 = grad3(hash3i(ix,     iy,     iz + 1, seed), dx,        dy,        dz - 1.0f);
    float n101 = grad3(hash3i(ix + 1, iy,     iz + 1, seed), dx - 1.0f, dy,        dz - 1.0f);
    float n011 = grad3(hash3i(ix,     iy + 1, iz + 1, seed), dx,        dy - 1.0f, dz - 1.0f);
    float n111 = grad3(hash3i(ix + 1, iy + 1, iz + 1, seed), dx - 1.0f, dy - 1.0f, dz - 1.0f);

    float x00 = eng_lerpf(n000, n100, u), x10 = eng_lerpf(n010, n110, u);
    float x01 = eng_lerpf(n001, n101, u), x11 = eng_lerpf(n011, n111, u);
    return eng_clampf(eng_lerpf(eng_lerpf(x00, x10, v), eng_lerpf(x01, x11, v), w), -1.0f, 1.0f);
}

float eng_noise_perlin2d(float x, float y, uint64_t seed) {
    return eng_noise_perlin3d(x, y, 0.37f, seed);
}

float eng_noise_simplex2d(float x, float y, uint64_t seed) {
    const float F2 = 0.36602540378f;
    const float G2 = 0.21132486540f;
    float s = (x + y) * F2;
    int i = (int)floorf(x + s);
    int j = (int)floorf(y + s);
    float t = (float)(i + j) * G2;
    float x0 = x - ((float)i - t);
    float y0 = y - ((float)j - t);

    int i1 = (x0 > y0) ? 1 : 0;
    int j1 = (x0 > y0) ? 0 : 1;
    float x1 = x0 - (float)i1 + G2;
    float y1 = y0 - (float)j1 + G2;
    float x2 = x0 - 1.0f + 2.0f * G2;
    float y2 = y0 - 1.0f + 2.0f * G2;

    float px[3] = {x0, x1, x2};
    float py[3] = {y0, y1, y2};
    int ci[3] = {i, i + i1, i + 1};
    int cj[3] = {j, j + j1, j + 1};
    float sum = 0.0f;
    for (int k = 0; k < 3; k++) {
        float attn = 0.5f - px[k] * px[k] - py[k] * py[k];
        if (attn > 0.0f) {
            attn *= attn;
            sum += attn * attn * grad3(hash3i(ci[k], cj[k], 0, seed), px[k], py[k], 0.0f);
        }
    }
    return eng_clampf(45.0f * sum, -1.0f, 1.0f);
}

float eng_noise_voronoi2d(float x, float y, uint64_t seed, uint32_t *out_cell_id) {
    int ix = (int)floorf(x), iy = (int)floorf(y);
    float best_d2 = 1e30f;
    uint32_t best_id = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int cx = ix + dx, cy = iy + dy;
            uint32_t id = hash3i(cx, cy, 11, seed);
            float fx = (float)cx + hash_f01(cx, cy, 1, seed);
            float fy = (float)cy + hash_f01(cx, cy, 2, seed);
            float d2 = (fx - x) * (fx - x) + (fy - y) * (fy - y);
            if (d2 < best_d2) {
                best_d2 = d2;
                best_id = id;
            }
        }
    }
    if (out_cell_id) *out_cell_id = best_id;
    return sqrtf(best_d2);
}

float eng_noise_fbm3d(float x, float y, float z, uint64_t seed, int octaves, float lacunarity, float gain) {
    if (octaves < 1) octaves = 1;
    float sum = 0.0f, amp = 0.5f, norm = 0.0f, freq = 1.0f;
    for (int i = 0; i < octaves; i++) {
        sum += amp * eng_noise_perlin3d(x * freq, y * freq, z * freq, seed + (uint64_t)i * 101u);
        norm += amp;
        freq *= lacunarity;
        amp *= gain;
    }
    return norm > 0.0f ? (sum / norm) : 0.0f;
}

float eng_noise_ridged3d(float x, float y, float z, uint64_t seed, int octaves) {
    if (octaves < 1) octaves = 1;
    float sum = 0.0f, amp = 0.5f, norm = 0.0f, freq = 1.0f;
    for (int i = 0; i < octaves; i++) {
        float r = 1.0f - fabsf(eng_noise_perlin3d(x * freq, y * freq, z * freq, seed + (uint64_t)i * 313u));
        sum += amp * (r * r);
        norm += amp;
        freq *= 2.0f;
        amp *= 0.5f;
    }
    return norm > 0.0f ? (sum / norm) : 0.0f;
}

float eng_noise_domain_warp3d(float x, float y, float z, uint64_t seed, float warp_amp) {
    float wx = eng_noise_fbm3d(x + 1.7f, y + 9.2f, z + 3.4f, seed ^ 0x11u, 3, 2.0f, 0.5f);
    float wy = eng_noise_fbm3d(x + 8.3f, y + 2.8f, z + 5.1f, seed ^ 0x22u, 3, 2.0f, 0.5f);
    float wz = eng_noise_fbm3d(x + 4.5f, y + 6.1f, z + 7.9f, seed ^ 0x33u, 3, 2.0f, 0.5f);
    return eng_noise_fbm3d(x + wx * warp_amp, y + wy * warp_amp, z + wz * warp_amp, seed, 4, 2.0f, 0.5f);
}

/* Periodic seamless torus noise helper for tileable textures */
static float tile_noise(float u, float v, float scale, uint64_t seed) {
    float a = u * 2.0f * ENG_PI;
    float b = v * 2.0f * ENG_PI;
    return eng_noise_fbm3d(cosf(a) * scale, sinf(a) * scale, cosf(b) * scale + sinf(b) * scale * 0.7f,
                           seed, 3, 2.0f, 0.5f);
}

bool eng_procgen_texture(const char *recipe, uint64_t seed, int size,
                         uint8_t *out_albedo_rgba,
                         uint8_t *out_normal_rgba,
                         uint8_t *out_roughness_r) {
    if (!recipe || size < 4 || !out_albedo_rgba) return false;
    float *hmap = (float *)malloc((size_t)(size * size) * sizeof(float));
    if (!hmap) return false;

    for (int y = 0; y < size; y++) {
        float v = (float)y / (float)size;
        for (int x = 0; x < size; x++) {
            float u = (float)x / (float)size;
            float n = tile_noise(u, v, 2.5f, seed);
            eng_vec3_t col = eng_v3(0.5f, 0.5f, 0.5f);
            float h = 0.5f + 0.5f * n;
            float rough = 0.7f;

            if (strcmp(recipe, "stone_brick") == 0) {
                float row = floorf(v * 4.0f);
                float bu = fmodf(u * 4.0f + row * 0.5f, 1.0f);
                float bv = fmodf(v * 4.0f, 1.0f);
                bool mortar = (bu < 0.07f || bv < 0.10f);
                h = mortar ? 0.15f : (0.65f + 0.25f * n);
                col = mortar ? eng_v3(0.28f, 0.27f, 0.25f) : eng_v3_scale(eng_v3(0.55f, 0.53f, 0.50f), 0.85f + 0.3f * h);
                rough = mortar ? 0.95f : 0.78f;
            } else if (strcmp(recipe, "wood_planks") == 0 || strcmp(recipe, "wood_grain") == 0) {
                float grain = sinf((v * 6.0f + n * 0.35f) * 24.0f) * 0.5f + 0.5f;
                bool seam = (strcmp(recipe, "wood_planks") == 0) && fmodf(u * 4.0f, 1.0f) < 0.04f;
                h = seam ? 0.1f : (0.5f + 0.3f * grain);
                col = seam ? eng_v3(0.18f, 0.11f, 0.06f) : eng_v3_lerp(eng_v3(0.42f, 0.25f, 0.12f), eng_v3(0.62f, 0.40f, 0.20f), grain);
                rough = 0.65f;
            } else if (strcmp(recipe, "grass") == 0) {
                float blades = tile_noise(u, v, 8.0f, seed ^ 0x55u) * 0.5f + 0.5f;
                h = blades;
                col = eng_v3_lerp(eng_v3(0.16f, 0.38f, 0.12f), eng_v3(0.36f, 0.68f, 0.22f), blades);
                rough = 0.88f;
            } else if (strcmp(recipe, "rust_metal") == 0) {
                float rust = eng_clampf(n * 1.6f + 0.3f, 0.0f, 1.0f);
                h = 0.6f - 0.3f * rust;
                col = eng_v3_lerp(eng_v3(0.56f, 0.58f, 0.62f), eng_v3(0.58f, 0.26f, 0.12f), rust);
                rough = eng_lerpf(0.28f, 0.92f, rust);
            } else if (strcmp(recipe, "metal_rivets") == 0) {
                float gx = fmodf(u * 2.0f, 1.0f), gy = fmodf(v * 2.0f, 1.0f);
                bool seam = (gx < 0.04f || gy < 0.04f);
                float rx = fabsf(gx - 0.5f) - 0.36f, ry = fabsf(gy - 0.5f) - 0.36f;
                bool rivet = (rx * rx + ry * ry) < 0.0028f;
                h = seam ? 0.15f : (rivet ? 0.95f : (0.62f + 0.08f * n));
                col = seam ? eng_v3(0.22f, 0.25f, 0.29f) : (rivet ? eng_v3(0.76f, 0.80f, 0.85f) : eng_v3_scale(eng_v3(0.52f, 0.56f, 0.62f), 0.92f + 0.12f * n));
                rough = rivet ? 0.22f : 0.38f;
            } else if (strcmp(recipe, "sci_fi_panel") == 0) {
                float gx = fmodf(u * 2.0f, 1.0f), gy = fmodf(v * 2.0f, 1.0f);
                bool groove = (gx < 0.06f || gy < 0.06f || (fabsf(gx - 0.5f) < 0.02f && gy > 0.2f && gy < 0.8f));
                h = groove ? 0.2f : 0.8f;
                col = groove ? eng_v3(0.12f, 0.22f, 0.30f) : eng_v3(0.62f, 0.66f, 0.72f);
                rough = groove ? 0.6f : 0.32f;
            } else if (strcmp(recipe, "water_caustics") == 0) {
                float d = eng_noise_voronoi2d(cosf(u * 2.0f * ENG_PI) * 2.0f + 4.0f, sinf(v * 2.0f * ENG_PI) * 2.0f + 4.0f, seed, NULL);
                float c = eng_clampf(powf(d, 1.8f) * 1.4f, 0.0f, 1.0f);
                h = c;
                col = eng_v3_lerp(eng_v3(0.06f, 0.32f, 0.58f), eng_v3(0.55f, 0.90f, 1.0f), c);
                rough = 0.12f;
            } else if (strcmp(recipe, "marble") == 0) {
                float vein = fabsf(sinf((u * 3.0f + v * 2.0f + n * 1.4f) * ENG_PI));
                h = 0.7f + 0.2f * vein;
                col = eng_v3_lerp(eng_v3(0.28f, 0.30f, 0.34f), eng_v3(0.93f, 0.92f, 0.90f), powf(vein, 0.4f));
                rough = 0.22f;
            } else if (strcmp(recipe, "lava_cracks") == 0) {
                float d = eng_noise_voronoi2d(u * 5.0f, v * 5.0f, seed, NULL);
                float glow = eng_clampf((d - 0.52f) * 3.2f, 0.0f, 1.0f);
                h = 1.0f - glow * 0.8f;
                col = eng_v3_lerp(eng_v3(0.14f, 0.11f, 0.11f), eng_v3(1.0f, 0.36f + 0.45f * glow, 0.06f), glow);
                rough = eng_lerpf(0.92f, 0.25f, glow);
            } else { /* "cobble" & generic fallback */
                float d = eng_noise_voronoi2d(u * 6.0f, v * 6.0f, seed, NULL);
                h = eng_clampf(1.0f - d * 1.2f, 0.0f, 1.0f);
                col = eng_v3_scale(eng_v3(0.48f, 0.46f, 0.44f), 0.5f + 0.6f * h);
                rough = 0.85f;
            }

            int idx = y * size + x;
            hmap[idx] = h;
            out_albedo_rgba[idx * 4 + 0] = (uint8_t)(eng_clampf(col.x, 0.0f, 1.0f) * 255.0f);
            out_albedo_rgba[idx * 4 + 1] = (uint8_t)(eng_clampf(col.y, 0.0f, 1.0f) * 255.0f);
            out_albedo_rgba[idx * 4 + 2] = (uint8_t)(eng_clampf(col.z, 0.0f, 1.0f) * 255.0f);
            out_albedo_rgba[idx * 4 + 3] = 255;
            if (out_roughness_r) out_roughness_r[idx] = (uint8_t)(eng_clampf(rough, 0.0f, 1.0f) * 255.0f);
        }
    }

    if (out_normal_rgba) {
        for (int y = 0; y < size; y++) {
            int ym = (y - 1 + size) % size, yp = (y + 1) % size;
            for (int x = 0; x < size; x++) {
                int xm = (x - 1 + size) % size, xp = (x + 1) % size;
                float dx = (hmap[y * size + xp] - hmap[y * size + xm]) * 2.5f;
                float dy = (hmap[yp * size + x] - hmap[ym * size + x]) * 2.5f;
                eng_vec3_t nrm = eng_v3_norm(eng_v3(-dx, -dy, 1.0f));
                int idx = (y * size + x) * 4;
                out_normal_rgba[idx + 0] = (uint8_t)((nrm.x * 0.5f + 0.5f) * 255.0f);
                out_normal_rgba[idx + 1] = (uint8_t)((nrm.y * 0.5f + 0.5f) * 255.0f);
                out_normal_rgba[idx + 2] = (uint8_t)((nrm.z * 0.5f + 0.5f) * 255.0f);
                out_normal_rgba[idx + 3] = 255;
            }
        }
    }
    free(hmap);
    return true;
}

/* --------------------------------------------------------------------------
 * Solvable Dungeons, Cellular Caves & Tiled WFC
 * -------------------------------------------------------------------------- */
void eng_dungeon_free(eng_dungeon_t *d) {
    if (!d) return;
    free(d->cells);
    memset(d, 0, sizeof(*d));
}

uint8_t eng_dungeon_get(const eng_dungeon_t *d, int x, int y) {
    if (!d || !d->cells || x < 0 || y < 0 || x >= d->width || y >= d->height) return ENG_TILE_WALL;
    return d->cells[y * d->width + x];
}

static void set_tile(eng_dungeon_t *d, int x, int y, uint8_t t) {
    if (x > 0 && y > 0 && x + 1 < d->width && y + 1 < d->height) {
        d->cells[y * d->width + x] = t;
    }
}

static void carve_corridor(eng_dungeon_t *d, int x0, int y0, int x1, int y1) {
    int x = x0, y = y0;
    while (x != x1) {
        if (d->cells[y * d->width + x] == ENG_TILE_WALL) set_tile(d, x, y, ENG_TILE_FLOOR);
        x += (x1 > x) ? 1 : -1;
    }
    while (y != y1) {
        if (d->cells[y * d->width + x] == ENG_TILE_WALL) set_tile(d, x, y, ENG_TILE_FLOOR);
        y += (y1 > y) ? 1 : -1;
    }
    if (d->cells[y1 * d->width + x1] == ENG_TILE_WALL) set_tile(d, x1, y1, ENG_TILE_FLOOR);
}

static bool bfs_reach(const eng_dungeon_t *d, int sx, int sy, int gx, int gy, bool allow_locked, int *out_dist_map) {
    int total = d->width * d->height;
    int *dist = out_dist_map ? out_dist_map : (int *)malloc((size_t)total * sizeof(int));
    int *q = (int *)malloc((size_t)total * sizeof(int));
    if (!dist || !q) {
        if (!out_dist_map) free(dist);
        free(q);
        return false;
    }
    for (int i = 0; i < total; i++) dist[i] = -1;
    int head = 0, tail = 0;
    dist[sy * d->width + sx] = 0;
    q[tail++] = sy * d->width + sx;

    static const int dx[4] = {1, -1, 0, 0};
    static const int dy[4] = {0, 0, 1, -1};
    while (head < tail) {
        int cur = q[head++];
        int cx = cur % d->width, cy = cur / d->width;
        for (int k = 0; k < 4; k++) {
            int nx = cx + dx[k], ny = cy + dy[k];
            if (nx < 0 || ny < 0 || nx >= d->width || ny >= d->height) continue;
            uint8_t t = d->cells[ny * d->width + nx];
            if (t == ENG_TILE_WALL) continue;
            if (t == ENG_TILE_LOCKED_DOOR && !allow_locked) continue;
            int ni = ny * d->width + nx;
            if (dist[ni] < 0) {
                dist[ni] = dist[cur] + 1;
                q[tail++] = ni;
            }
        }
    }
    bool hit = (gx >= 0 && gy >= 0 && dist[gy * d->width + gx] >= 0);
    if (!out_dist_map) free(dist);
    free(q);
    return hit;
}

bool eng_procgen_dungeon_is_solvable(const eng_dungeon_t *d) {
    if (!d || !d->cells) return false;
    if (d->has_key_lock) {
        if (!bfs_reach(d, d->entrance_x, d->entrance_y, d->key_x, d->key_y, false, NULL)) return false;
        return bfs_reach(d, d->key_x, d->key_y, d->exit_x, d->exit_y, true, NULL);
    }
    return bfs_reach(d, d->entrance_x, d->entrance_y, d->exit_x, d->exit_y, true, NULL);
}

static void repair_and_finalize_dungeon(eng_dungeon_t *d, bool place_key_lock) {
    int total = d->width * d->height;
    /* Ensure at least two open tiles exist */
    int open_count = 0;
    int first_idx = -1;
    for (int i = 0; i < total; i++) {
        if (d->cells[i] != ENG_TILE_WALL) {
            if (first_idx < 0) first_idx = i;
            open_count++;
        }
    }
    if (open_count < 4) {
        carve_corridor(d, 2, 2, d->width - 3, d->height - 3);
        first_idx = 2 * d->width + 2;
    }

    /* Connect all disconnected open islands to the main component via L-tunnels */
    int *dist = (int *)malloc((size_t)total * sizeof(int));
    if (!dist) return;
    int sx = first_idx % d->width, sy = first_idx / d->width;
    for (int pass = 0; pass < 64; pass++) {
        bfs_reach(d, sx, sy, sx, sy, true, dist);
        int isolated = -1;
        for (int i = 0; i < total; i++) {
            if (d->cells[i] != ENG_TILE_WALL && dist[i] < 0) {
                isolated = i;
                break;
            }
        }
        if (isolated < 0) break;
        carve_corridor(d, sx, sy, isolated % d->width, isolated / d->width);
    }

    /* Place entrance at sx,sy and exit at maximum BFS geodesic distance */
    bfs_reach(d, sx, sy, sx, sy, true, dist);
    int best_idx = first_idx, max_d = 0;
    for (int i = 0; i < total; i++) {
        if (dist[i] > max_d) {
            max_d = dist[i];
            best_idx = i;
        }
    }
    d->entrance_x = sx; d->entrance_y = sy;
    d->exit_x = best_idx % d->width; d->exit_y = best_idx / d->width;
    d->cells[sy * d->width + sx] = ENG_TILE_ENTRANCE;
    d->cells[best_idx] = ENG_TILE_EXIT;

    if (place_key_lock && max_d >= 6) {
        int key_i = -1, lock_i = -1;
        for (int i = 0; i < total; i++) {
            if (i == first_idx || i == best_idx) continue;
            if (dist[i] >= 2 && dist[i] <= max_d / 3 && key_i < 0) key_i = i;
            if (dist[i] >= (2 * max_d) / 3 && dist[i] < max_d && lock_i < 0) lock_i = i;
        }
        if (key_i >= 0 && lock_i >= 0 && key_i != lock_i) {
            d->key_x = key_i % d->width; d->key_y = key_i / d->width;
            d->lock_x = lock_i % d->width; d->lock_y = lock_i / d->width;
            d->cells[key_i] = ENG_TILE_KEY;
            d->cells[lock_i] = ENG_TILE_LOCKED_DOOR;
            d->has_key_lock = true;
            if (!eng_procgen_dungeon_is_solvable(d)) {
                d->cells[lock_i] = ENG_TILE_DOOR;
                d->has_key_lock = false;
            }
        }
    }
    free(dist);
}

static void bsp_split(eng_dungeon_t *d, eng_rng_t *rng, int x, int y, int w, int h, int depth) {
    if (depth == 0 || (w < 10 && h < 10) || d->room_count >= 32) {
        int rw = w > 5 ? (int)eng_rng_rangef(rng, 3.0f, (float)(w - 2)) : (w - 2);
        int rh = h > 5 ? (int)eng_rng_rangef(rng, 3.0f, (float)(h - 2)) : (h - 2);
        if (rw < 2) rw = 2;
        if (rh < 2) rh = 2;
        int rx = x + 1 + ((w - 2 > rw) ? (int)(eng_rng_u32(rng) % (uint32_t)(w - 2 - rw)) : 0);
        int ry = y + 1 + ((h - 2 > rh) ? (int)(eng_rng_u32(rng) % (uint32_t)(h - 2 - rh)) : 0);
        for (int yy = ry; yy < ry + rh; yy++) {
            for (int xx = rx; xx < rx + rw; xx++) set_tile(d, xx, yy, ENG_TILE_FLOOR);
        }
        d->rooms[d->room_count++] = (eng_room_rect_t){rx, ry, rw, rh};
        return;
    }
    bool split_h = (w > h) ? false : (h > w ? true : (eng_rng_float01(rng) > 0.5f));
    if (split_h && h >= 10) {
        int sp = h / 2 + (int)eng_rng_rangef(rng, -2.0f, 2.0f);
        bsp_split(d, rng, x, y, w, sp, depth - 1);
        bsp_split(d, rng, x, y + sp, w, h - sp, depth - 1);
    } else if (w >= 10) {
        int sp = w / 2 + (int)eng_rng_rangef(rng, -2.0f, 2.0f);
        bsp_split(d, rng, x, y, sp, h, depth - 1);
        bsp_split(d, rng, x + sp, y, w - sp, h, depth - 1);
    } else {
        bsp_split(d, rng, x, y, w, h, 0);
    }
}

bool eng_procgen_dungeon_bsp(eng_dungeon_t *out, int w, int h, uint64_t seed) {
    if (!out || w < 12 || h < 12) return false;
    memset(out, 0, sizeof(*out));
    out->width = w;
    out->height = h;
    out->cells = (uint8_t *)calloc((size_t)(w * h), 1);
    if (!out->cells) return false;

    eng_rng_t rng;
    eng_rng_seed(&rng, seed ? seed : 42u);
    bsp_split(out, &rng, 1, 1, w - 2, h - 2, 3);
    for (size_t i = 1; i < out->room_count; i++) {
        int x0 = out->rooms[i - 1].x + out->rooms[i - 1].w / 2;
        int y0 = out->rooms[i - 1].y + out->rooms[i - 1].h / 2;
        int x1 = out->rooms[i].x + out->rooms[i].w / 2;
        int y1 = out->rooms[i].y + out->rooms[i].h / 2;
        carve_corridor(out, x0, y0, x1, y1);
    }
    repair_and_finalize_dungeon(out, true);
    return true;
}

bool eng_procgen_cave_cellular(eng_dungeon_t *out, int w, int h, uint64_t seed) {
    if (!out || w < 12 || h < 12) return false;
    memset(out, 0, sizeof(*out));
    out->width = w;
    out->height = h;
    out->cells = (uint8_t *)calloc((size_t)(w * h), 1);
    uint8_t *tmp = (uint8_t *)calloc((size_t)(w * h), 1);
    if (!out->cells || !tmp) {
        free(out->cells); free(tmp);
        return false;
    }

    eng_rng_t rng;
    eng_rng_seed(&rng, seed ? seed : 99u);
    for (int y = 1; y + 1 < h; y++) {
        for (int x = 1; x + 1 < w; x++) {
            out->cells[y * w + x] = (eng_rng_float01(&rng) > 0.44f) ? ENG_TILE_FLOOR : ENG_TILE_WALL;
        }
    }

    for (int step = 0; step < 4; step++) {
        memset(tmp, ENG_TILE_WALL, (size_t)(w * h));
        for (int y = 1; y + 1 < h; y++) {
            for (int x = 1; x + 1 < w; x++) {
                int walls = 0;
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        if (dx == 0 && dy == 0) continue;
                        if (out->cells[(y + dy) * w + (x + dx)] == ENG_TILE_WALL) walls++;
                    }
                }
                tmp[y * w + x] = (walls >= 5) ? ENG_TILE_WALL : (walls <= 3 ? ENG_TILE_FLOOR : out->cells[y * w + x]);
            }
        }
        memcpy(out->cells, tmp, (size_t)(w * h));
    }
    free(tmp);
    repair_and_finalize_dungeon(out, false);
    return true;
}

bool eng_procgen_wfc_grid(eng_dungeon_t *out, int w, int h, uint64_t seed) {
    if (!out || w < 12 || h < 12) return false;
    memset(out, 0, sizeof(*out));
    out->width = w;
    out->height = h;
    out->cells = (uint8_t *)calloc((size_t)(w * h), 1);
    if (!out->cells) return false;

    /* 7 macro-tiles (3x3) with N(1), E(2), S(4), W(8) open socket bitmasks */
    static const uint8_t tile_sockets[7] = {0u, 15u, 5u, 10u, 3u, 6u, 12u};
    int cw = (w - 2) / 3;
    int ch = (h - 2) / 3;
    uint8_t *domain = (uint8_t *)malloc((size_t)(cw * ch));
    if (!domain) { free(out->cells); return false; }
    memset(domain, 0x7Fu, (size_t)(cw * ch));

    eng_rng_t rng;
    eng_rng_seed(&rng, seed ? seed : 7u);

    for (int step = 0; step < cw * ch; step++) {
        /* Pick lowest non-collapsed popcount cell */
        int best_c = -1, best_pop = 99;
        for (int i = 0; i < cw * ch; i++) {
            uint8_t m = domain[i];
            int pop = 0;
            for (int b = 0; b < 7; b++) if (m & (1u << b)) pop++;
            if (pop > 1 && pop < best_pop) {
                best_pop = pop;
                best_c = i;
            }
        }
        if (best_c < 0) break;

        /* Weighted pick favoring connected corridors/crosses over empty solid rock (tile 0) */
        uint8_t mask = domain[best_c] & 0x7Eu;
        if (!mask) mask = domain[best_c];
        int choices[7], nc = 0;
        for (int b = 0; b < 7; b++) if (mask & (1u << b)) choices[nc++] = b;
        int chosen = choices[eng_rng_u32(&rng) % (uint32_t)nc];
        domain[best_c] = (uint8_t)(1u << chosen);

        /* 1-ring socket constraint propagation */
        int cx = best_c % cw, cy = best_c / cw;
        uint8_t sk = tile_sockets[chosen];
        const int nx_off[4] = {0, 1, 0, -1};
        const int ny_off[4] = {-1, 0, 1, 0};
        const uint8_t my_bit[4] = {1u, 2u, 4u, 8u};
        const uint8_t nb_bit[4] = {4u, 8u, 1u, 2u};
        for (int dir = 0; dir < 4; dir++) {
            int nx = cx + nx_off[dir], ny = cy + ny_off[dir];
            if (nx < 0 || ny < 0 || nx >= cw || ny >= ch) continue;
            bool open = (sk & my_bit[dir]) != 0;
            uint8_t compat = 0;
            for (int b = 0; b < 7; b++) {
                if (((tile_sockets[b] & nb_bit[dir]) != 0) == open) compat |= (uint8_t)(1u << b);
            }
            uint8_t next_m = domain[ny * cw + nx] & compat;
            if (next_m) domain[ny * cw + nx] = next_m;
        }
    }

    for (int cy = 0; cy < ch; cy++) {
        for (int cx = 0; cx < cw; cx++) {
            uint8_t m = domain[cy * cw + cx];
            int t = 1;
            for (int b = 0; b < 7; b++) if (m & (1u << b)) { t = b; break; }
            uint8_t sk = tile_sockets[t];
            int bx = 1 + cx * 3, by = 1 + cy * 3;
            if (sk != 0) set_tile(out, bx + 1, by + 1, ENG_TILE_FLOOR);
            if (sk & 1u) set_tile(out, bx + 1, by + 0, ENG_TILE_FLOOR);
            if (sk & 2u) set_tile(out, bx + 2, by + 1, ENG_TILE_FLOOR);
            if (sk & 4u) set_tile(out, bx + 1, by + 2, ENG_TILE_FLOOR);
            if (sk & 8u) set_tile(out, bx + 0, by + 1, ENG_TILE_FLOOR);
        }
    }
    free(domain);
    repair_and_finalize_dungeon(out, true);
    return true;
}

bool eng_procgen_dungeon_build_mesh(const eng_dungeon_t *d, float tile_size, float wall_h, eng_mesh_data_t *out_mesh) {
    if (!d || !d->cells || !out_mesh || tile_size <= 0.05f || wall_h <= 0.1f) return false;
    eng_mesh_data_init(out_mesh);
    for (int y = 0; y < d->height; y++) {
        for (int x = 0; x < d->width; x++) {
            uint8_t t = d->cells[y * d->width + x];
            float cx = ((float)x + 0.5f) * tile_size;
            float cz = ((float)y + 0.5f) * tile_size;
            if (t == ENG_TILE_WALL) {
                eng_mesh_append_box(out_mesh, eng_v3(cx, wall_h * 0.5f, cz),
                                    eng_v3(tile_size, wall_h, tile_size), (eng_vec4_t){0.38f, 0.36f, 0.40f, 1.0f});
            } else {
                eng_vec4_t fc = (t == ENG_TILE_ENTRANCE) ? (eng_vec4_t){0.2f, 0.8f, 0.4f, 1.0f} :
                                (t == ENG_TILE_EXIT)     ? (eng_vec4_t){0.9f, 0.8f, 0.2f, 1.0f} :
                                                           (eng_vec4_t){0.52f, 0.50f, 0.46f, 1.0f};
                eng_mesh_append_box(out_mesh, eng_v3(cx, -0.04f, cz),
                                    eng_v3(tile_size, 0.10f, tile_size), fc);
            }
        }
    }
    return out_mesh->vert_count > 0;
}

/* --------------------------------------------------------------------------
 * 3D Cube-Sphere Planets (Whittaker Biomes + Radial Gravity)
 * -------------------------------------------------------------------------- */
eng_planet_cfg_t eng_planet_default_cfg(uint64_t seed, float radius) {
    return (eng_planet_cfg_t){
        .seed = seed ? seed : 101u,
        .radius = radius > 1.0f ? radius : 30.0f,
        .subdivisions = 20,
        .continent_amp = radius * 0.12f,
        .sea_level = 0.0f,
        .crater_count = 6
    };
}

float eng_planet_sample_radius(const eng_planet_cfg_t *cfg, eng_vec3_t unit_dir) {
    if (!cfg) return 1.0f;
    eng_vec3_t d = eng_v3_norm(unit_dir);
    float cont = eng_noise_fbm3d(d.x * 2.2f, d.y * 2.2f, d.z * 2.2f, cfg->seed, 4, 2.0f, 0.5f);
    float ridg = eng_noise_ridged3d(d.x * 4.5f, d.y * 4.5f, d.z * 4.5f, cfg->seed ^ 0x77u, 3);
    float elev = (cont * 0.75f + (ridg - 0.5f) * 0.45f) * cfg->continent_amp;

    /* Deterministic spherical-cap impact craters */
    for (int c = 0; c < cfg->crater_count && c < 16; c++) {
        eng_vec3_t cdir = eng_v3_norm(eng_v3(
            hash_f01(c, 1, 0, cfg->seed) * 2.0f - 1.0f,
            hash_f01(c, 2, 0, cfg->seed) * 2.0f - 1.0f,
            hash_f01(c, 3, 0, cfg->seed) * 2.0f - 1.0f
        ));
        float dist = eng_v3_len(eng_v3_sub(d, cdir));
        float cr = 0.18f + 0.15f * hash_f01(c, 4, 0, cfg->seed);
        if (dist < cr) {
            float x = dist / cr;
            float bowl = (x * x - 1.0f) * 0.35f * cfg->continent_amp;
            float rim = expf(-((x - 0.9f) * (x - 0.9f)) * 30.0f) * 0.12f * cfg->continent_amp;
            elev += bowl + rim;
        }
    }

    float sea = cfg->radius + cfg->sea_level;
    float r = cfg->radius + elev;
    return r < sea ? sea : r;
}

eng_vec3_t eng_planet_gravity_up(eng_vec3_t planet_center, eng_vec3_t world_pos) {
    eng_vec3_t up = eng_v3_norm(eng_v3_sub(world_pos, planet_center));
    return eng_v3_dot(up, up) > 0.1f ? up : eng_v3(0.0f, 1.0f, 0.0f);
}

static eng_vec4_t planet_biome_color(const eng_planet_cfg_t *cfg, eng_vec3_t d, float r) {
    float sea = cfg->radius + cfg->sea_level;
    float rel = (r - sea) / (cfg->continent_amp > 0.01f ? cfg->continent_amp : 1.0f);
    float lat = fabsf(d.y);
    float moist = eng_noise_fbm3d(d.x * 3.5f + 9.0f, d.y * 3.5f, d.z * 3.5f, cfg->seed ^ 0xABC1u, 3, 2.0f, 0.5f) * 0.5f + 0.5f;

    eng_vec3_t c;
    if (rel <= 0.002f) {
        c = (lat > 0.86f) ? eng_v3(0.85f, 0.92f, 0.98f) : eng_v3(0.08f, 0.28f, 0.62f);
    } else if (lat + rel * 0.35f > 0.84f) {
        c = eng_v3(0.93f, 0.95f, 0.98f); /* Polar / alpine snow */
    } else if (rel < 0.06f) {
        c = eng_v3(0.84f, 0.78f, 0.56f); /* Beach */
    } else if (rel > 0.55f) {
        c = eng_v3(0.45f, 0.43f, 0.41f); /* High mountain rock */
    } else {
        c = (moist > 0.48f) ? eng_v3(0.18f, 0.54f, 0.22f) : eng_v3(0.72f, 0.60f, 0.34f); /* Forest vs Savanna/Desert */
    }
    return (eng_vec4_t){c.x, c.y, c.z, 1.0f};
}

bool eng_procgen_planet_mesh(const eng_planet_cfg_t *cfg, eng_mesh_data_t *out_mesh) {
    if (!cfg || !out_mesh || cfg->radius <= 0.1f) return false;
    eng_mesh_data_init(out_mesh);
    int n = cfg->subdivisions >= 4 ? (cfg->subdivisions <= 64 ? cfg->subdivisions : 64) : 8;
    int stride = n + 1;
    size_t v_per_face = (size_t)(stride * stride);
    size_t i_per_face = (size_t)(n * n * 6);

    out_mesh->verts = (eng_vertex_t *)calloc(6u * v_per_face, sizeof(eng_vertex_t));
    out_mesh->indices = (uint32_t *)malloc(6u * i_per_face * sizeof(uint32_t));
    if (!out_mesh->verts || !out_mesh->indices) {
        eng_mesh_data_free(out_mesh);
        return false;
    }
    out_mesh->vert_cap = 6u * v_per_face;
    out_mesh->idx_cap = 6u * i_per_face;

    /* 6 right-handed outward cube faces: normal, tangent_u, tangent_v */
    static const float faces[6][3][3] = {
        {{ 0,  0,  1}, { 1,  0,  0}, { 0,  1,  0}},
        {{ 0,  0, -1}, {-1,  0,  0}, { 0,  1,  0}},
        {{ 1,  0,  0}, { 0,  0, -1}, { 0,  1,  0}},
        {{-1,  0,  0}, { 0,  0,  1}, { 0,  1,  0}},
        {{ 0,  1,  0}, { 1,  0,  0}, { 0,  0, -1}},
        {{ 0, -1,  0}, { 1,  0,  0}, { 0,  0,  1}}
    };

    for (int f = 0; f < 6; f++) {
        uint32_t base = (uint32_t)out_mesh->vert_count;
        eng_vec3_t fn = eng_v3(faces[f][0][0], faces[f][0][1], faces[f][0][2]);
        eng_vec3_t fu = eng_v3(faces[f][1][0], faces[f][1][1], faces[f][1][2]);
        eng_vec3_t fv = eng_v3(faces[f][2][0], faces[f][2][1], faces[f][2][2]);

        for (int j = 0; j <= n; j++) {
            float tv = (float)j / (float)n * 2.0f - 1.0f;
            for (int i = 0; i <= n; i++) {
                float tu = (float)i / (float)n * 2.0f - 1.0f;
                eng_vec3_t cube_p = eng_v3_add(fn, eng_v3_add(eng_v3_scale(fu, tu), eng_v3_scale(fv, tv)));
                eng_vec3_t d = eng_v3_norm(cube_p);
                float r = eng_planet_sample_radius(cfg, d);
                eng_vec3_t p = eng_v3_scale(d, r);

                /* Finite-difference displaced surface normal */
                float eps = 0.02f;
                eng_vec3_t du = eng_v3_norm(eng_v3_add(cube_p, eng_v3_scale(fu, eps)));
                eng_vec3_t dv = eng_v3_norm(eng_v3_add(cube_p, eng_v3_scale(fv, eps)));
                eng_vec3_t pu = eng_v3_scale(du, eng_planet_sample_radius(cfg, du));
                eng_vec3_t pv = eng_v3_scale(dv, eng_planet_sample_radius(cfg, dv));
                eng_vec3_t nrm = eng_v3_norm(eng_v3_cross(eng_v3_sub(pu, p), eng_v3_sub(pv, p)));
                if (eng_v3_dot(nrm, d) < 0.0f) nrm = eng_v3_scale(nrm, -1.0f);

                eng_vec4_t col = planet_biome_color(cfg, d, r);
                eng_vertex_t *vt = &out_mesh->verts[out_mesh->vert_count++];
                vt->pos[0] = p.x; vt->pos[1] = p.y; vt->pos[2] = p.z;
                vt->norm[0] = nrm.x; vt->norm[1] = nrm.y; vt->norm[2] = nrm.z;
                vt->uv[0] = (float)i / (float)n; vt->uv[1] = (float)j / (float)n;
                vt->color[0] = col.x; vt->color[1] = col.y; vt->color[2] = col.z; vt->color[3] = 1.0f;
                vt->weights[0] = 1.0f;
            }
        }
        for (int j = 0; j < n; j++) {
            for (int i = 0; i < n; i++) {
                uint32_t i0 = base + (uint32_t)(j * stride + i);
                uint32_t i1 = i0 + (uint32_t)stride;
                out_mesh->indices[out_mesh->idx_count++] = i0;
                out_mesh->indices[out_mesh->idx_count++] = i0 + 1;
                out_mesh->indices[out_mesh->idx_count++] = i1 + 1;
                out_mesh->indices[out_mesh->idx_count++] = i0;
                out_mesh->indices[out_mesh->idx_count++] = i1 + 1;
                out_mesh->indices[out_mesh->idx_count++] = i1;
            }
        }
    }
    return true;
}

/* --------------------------------------------------------------------------
 * 3D L-System Flora & Poisson-Disk Scatter
 * -------------------------------------------------------------------------- */
static void grow_branch(eng_mesh_data_t *out, eng_rng_t *rng, eng_vec3_t base, eng_quat_t rot,
                        float len, float rad, int depth) {
    eng_mesh_data_t seg;
    eng_mesh_data_init(&seg);
    eng_mesh_append_cylinder(&seg, eng_v3(0, 0, 0), rad, rad * 0.7f, len, 6, (eng_vec4_t){0.42f, 0.27f, 0.14f, 1.0f});
    eng_mat4_t xf = eng_mat4_trs(base, rot, eng_v3(1, 1, 1));
    eng_mesh_append_transformed(out, &seg, &xf, (eng_vec4_t){1, 1, 1, 1});
    eng_mesh_data_free(&seg);

    eng_vec3_t tip = eng_mat4_transform_point(&xf, eng_v3(0.0f, len, 0.0f));
    if (depth <= 0) {
        eng_mesh_append_sphere(out, tip, rad * 5.5f + 0.25f, 5, 6, (eng_vec4_t){0.20f, 0.58f, 0.22f, 1.0f});
        return;
    }
    int children = 2 + (int)(eng_rng_u32(rng) % 2u);
    for (int k = 0; k < children; k++) {
        float yaw = ((float)k / (float)children) * 360.0f + eng_rng_rangef(rng, -25.0f, 25.0f);
        float tilt = eng_rng_rangef(rng, 24.0f, 42.0f);
        eng_quat_t child_rot = eng_quat_mul(rot, eng_quat_from_euler_deg(eng_v3(tilt, yaw, 0.0f)));
        grow_branch(out, rng, tip, child_rot, len * 0.72f, rad * 0.68f, depth - 1);
    }
}

bool eng_procgen_tree_mesh(uint64_t seed, int depth, float trunk_height, float trunk_radius, eng_mesh_data_t *out_mesh) {
    if (!out_mesh || trunk_height <= 0.1f || trunk_radius <= 0.02f) return false;
    eng_mesh_data_init(out_mesh);
    if (depth < 0) depth = 0;
    if (depth > 4) depth = 4;
    eng_rng_t rng;
    eng_rng_seed(&rng, seed ? seed : 55u);
    grow_branch(out_mesh, &rng, eng_v3(0, 0, 0), eng_quat_identity(), trunk_height, trunk_radius, depth);
    return out_mesh->vert_count > 0;
}

size_t eng_procgen_poisson_2d(uint64_t seed, float width, float height, float min_dist,
                              eng_vec2_t *out_pts, size_t max_pts) {
    if (!out_pts || max_pts == 0 || width <= 0.0f || height <= 0.0f || min_dist <= 0.01f) return 0;
    eng_rng_t rng;
    eng_rng_seed(&rng, seed ? seed : 77u);
    float d2 = min_dist * min_dist;
    size_t n = 0;
    size_t max_attempts = max_pts * 30u;
    for (size_t a = 0; a < max_attempts && n < max_pts; a++) {
        eng_vec2_t cand = {eng_rng_rangef(&rng, 0.0f, width), eng_rng_rangef(&rng, 0.0f, height)};
        bool ok = true;
        for (size_t i = 0; i < n; i++) {
            float dx = cand.x - out_pts[i].x, dy = cand.y - out_pts[i].y;
            if (dx * dx + dy * dy < d2) { ok = false; break; }
        }
        if (ok) out_pts[n++] = cand;
    }
    return n;
}

size_t eng_procgen_poisson_sphere(uint64_t seed, float radius, float min_chord_dist,
                                  eng_vec3_t *out_pts, size_t max_pts) {
    if (!out_pts || max_pts == 0 || radius <= 0.01f || min_chord_dist <= 0.01f) return 0;
    eng_rng_t rng;
    eng_rng_seed(&rng, seed ? seed : 88u);
    float d2 = min_chord_dist * min_chord_dist;
    size_t n = 0;
    size_t max_attempts = max_pts * 30u;
    for (size_t a = 0; a < max_attempts && n < max_pts; a++) {
        float z = eng_rng_rangef(&rng, -1.0f, 1.0f);
        float theta = eng_rng_rangef(&rng, 0.0f, 2.0f * ENG_PI);
        float r_xy = sqrtf(fmaxf(0.0f, 1.0f - z * z));
        eng_vec3_t cand = eng_v3(r_xy * cosf(theta) * radius, z * radius, r_xy * sinf(theta) * radius);
        bool ok = true;
        for (size_t i = 0; i < n; i++) {
            eng_vec3_t diff = eng_v3_sub(cand, out_pts[i]);
            if (eng_v3_dot(diff, diff) < d2) { ok = false; break; }
        }
        if (ok) out_pts[n++] = cand;
    }
    return n;
}

/* --------------------------------------------------------------------------
 * 6. DNA-Driven Articulated Animals & Modular People / NPCs
 * -------------------------------------------------------------------------- */
#include <stdio.h>

static void append_skinned_box(eng_mesh_data_t *md, eng_vec3_t center, eng_vec3_t sz,
                               eng_vec4_t col, uint8_t bone_idx) {
    size_t v0 = md->vert_count;
    if (eng_mesh_append_box(md, center, sz, col)) {
        for (size_t i = v0; i < md->vert_count; i++) {
            md->verts[i].joints[0] = bone_idx;
            md->verts[i].weights[0] = 1.0f;
        }
    }
}

static void append_skinned_sphere(eng_mesh_data_t *md, eng_vec3_t center, float rad,
                                  eng_vec4_t col, uint8_t bone_idx) {
    size_t v0 = md->vert_count;
    if (eng_mesh_append_sphere(md, center, rad, 6, 8, col)) {
        for (size_t i = v0; i < md->vert_count; i++) {
            md->verts[i].joints[0] = bone_idx;
            md->verts[i].weights[0] = 1.0f;
        }
    }
}

static void generate_coat_texture(uint64_t seed, eng_vec3_t base_col, eng_vec3_t accent_col, uint8_t out_rgba[64 * 64 * 4]) {
    int pattern = (int)(hash3i(1, 2, 3, seed) % 3u); /* 0=spots, 1=stripes, 2=countershade */
    for (int y = 0; y < 64; y++) {
        float v = (float)y / 64.0f;
        for (int x = 0; x < 64; x++) {
            float u = (float)x / 64.0f;
            float t = 0.0f;
            if (pattern == 0) {
                float d = eng_noise_voronoi2d(u * 7.0f, v * 7.0f, seed, NULL);
                t = d < 0.28f ? 1.0f : 0.0f;
            } else if (pattern == 1) {
                float w = sinf((u * 8.0f + eng_noise_perlin2d(u * 4.0f, v * 4.0f, seed) * 0.6f) * ENG_PI);
                t = w > 0.3f ? 1.0f : 0.0f;
            } else {
                t = eng_clampf(1.0f - v * 1.4f, 0.0f, 1.0f);
            }
            eng_vec3_t c = eng_v3_lerp(base_col, accent_col, t);
            int idx = (y * 64 + x) * 4;
            out_rgba[idx + 0] = (uint8_t)(eng_clampf(c.x, 0.0f, 1.0f) * 255.0f);
            out_rgba[idx + 1] = (uint8_t)(eng_clampf(c.y, 0.0f, 1.0f) * 255.0f);
            out_rgba[idx + 2] = (uint8_t)(eng_clampf(c.z, 0.0f, 1.0f) * 255.0f);
            out_rgba[idx + 3] = 255;
        }
    }
}

bool eng_procgen_animal(uint64_t seed, eng_animal_archetype_t archetype, eng_animal_asset_t *out) {
    if (!out) return false;
    memset(out, 0, sizeof(*out));
    eng_mesh_data_init(&out->mesh);
    eng_skeleton_init(&out->skeleton);

    eng_rng_t rng;
    eng_rng_seed(&rng, seed ? seed : 2026u);

    eng_vec3_t c1 = eng_v3(eng_rng_rangef(&rng, 0.25f, 0.85f), eng_rng_rangef(&rng, 0.20f, 0.75f), eng_rng_rangef(&rng, 0.12f, 0.65f));
    eng_vec3_t c2 = eng_v3(eng_rng_rangef(&rng, 0.10f, 0.95f), eng_rng_rangef(&rng, 0.10f, 0.90f), eng_rng_rangef(&rng, 0.10f, 0.85f));
    generate_coat_texture(seed, c1, c2, out->coat_rgba);
    eng_vec4_t body_col = {c1.x, c1.y, c1.z, 1.0f};
    eng_vec4_t trim_col = {c2.x, c2.y, c2.z, 1.0f};

    float body_len = eng_rng_rangef(&rng, 0.9f, 1.6f);
    float body_rad = eng_rng_rangef(&rng, 0.22f, 0.38f);
    float leg_h = (archetype == ENG_ANIMAL_AQUATIC || archetype == ENG_ANIMAL_SERPENTINE)
                      ? 0.12f
                      : eng_rng_rangef(&rng, 0.45f, 0.85f);

    int b_root = eng_skeleton_add_bone(&out->skeleton, "pelvis", -1, eng_v3(0.0f, leg_h + body_rad, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));
    int b_chest = eng_skeleton_add_bone(&out->skeleton, "chest", b_root, eng_v3(0.0f, 0.0f, -body_len * 0.45f), eng_quat_identity(), eng_v3(1, 1, 1));
    int b_head = eng_skeleton_add_bone(&out->skeleton, "head", b_chest, eng_v3(0.0f, body_rad * 0.55f, -body_len * 0.30f), eng_quat_identity(), eng_v3(1, 1, 1));
    int b_tail = eng_skeleton_add_bone(&out->skeleton, "tail", b_root, eng_v3(0.0f, 0.0f, body_len * 0.45f), eng_quat_identity(), eng_v3(1, 1, 1));

    /* Lofted torso + chest + snout/ears + tail */
    append_skinned_box(&out->mesh, eng_v3(0.0f, leg_h + body_rad, 0.0f), eng_v3(body_rad * 1.6f, body_rad * 1.5f, body_len), body_col, (uint8_t)b_root);
    eng_vec3_t head_p = eng_v3(0.0f, leg_h + body_rad * 1.55f, -body_len * 0.75f);
    append_skinned_sphere(&out->mesh, head_p, body_rad * 0.72f, body_col, (uint8_t)b_head);
    /* Snout & symmetrical ears/horns */
    append_skinned_box(&out->mesh, eng_v3_add(head_p, eng_v3(0.0f, -0.05f, -body_rad * 0.65f)),
                       eng_v3(body_rad * 0.6f, body_rad * 0.45f, body_rad * 0.6f), trim_col, (uint8_t)b_head);
    append_skinned_box(&out->mesh, eng_v3_add(head_p, eng_v3(-body_rad * 0.4f, body_rad * 0.65f, 0.0f)),
                       eng_v3(0.08f, 0.22f, 0.08f), trim_col, (uint8_t)b_head);
    append_skinned_box(&out->mesh, eng_v3_add(head_p, eng_v3( body_rad * 0.4f, body_rad * 0.65f, 0.0f)),
                       eng_v3(0.08f, 0.22f, 0.08f), trim_col, (uint8_t)b_head);
    append_skinned_box(&out->mesh, eng_v3(0.0f, leg_h + body_rad, body_len * 0.70f),
                       eng_v3(body_rad * 0.4f, body_rad * 0.4f, body_len * 0.5f), trim_col, (uint8_t)b_tail);

    int pairs = (archetype == ENG_ANIMAL_INSECTOID) ? 3 :
                (archetype == ENG_ANIMAL_QUADRUPED) ? 2 :
                (archetype == ENG_ANIMAL_BIPED || archetype == ENG_ANIMAL_AVIAN) ? 1 : 0;

    out->gait.stride_length = leg_h * 0.65f;
    out->gait.step_height = leg_h * 0.28f;
    out->gait.cycle_hz = 2.0f;

    for (int p = 0; p < pairs; p++) {
        float z_rel = (pairs == 1) ? 0.0f : eng_lerpf(-body_len * 0.35f, body_len * 0.35f, (float)p / (float)(pairs - 1));
        int parent_b = (z_rel < -0.05f) ? b_chest : b_root;
        float parent_z = (parent_b == b_chest) ? (-body_len * 0.45f) : 0.0f;

        for (int side = 0; side < 2; side++) {
            float sx = (side == 0 ? -1.0f : 1.0f) * (body_rad * 0.78f);
            float seg = leg_h * 0.5f;
            int hip = eng_skeleton_add_bone(&out->skeleton, "hip", parent_b,
                                            eng_v3(sx, -body_rad * 0.3f, z_rel - parent_z), eng_quat_identity(), eng_v3(1, 1, 1));
            int knee = eng_skeleton_add_bone(&out->skeleton, "knee", hip,
                                             eng_v3(0.0f, -seg, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));
            int ankle = eng_skeleton_add_bone(&out->skeleton, "ankle", knee,
                                              eng_v3(0.0f, -seg, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));

            float wy_hip = leg_h + body_rad * 0.7f;
            append_skinned_box(&out->mesh, eng_v3(sx, wy_hip - seg * 0.5f, z_rel),
                               eng_v3(0.11f, seg, 0.11f), body_col, (uint8_t)hip);
            append_skinned_box(&out->mesh, eng_v3(sx, wy_hip - seg * 1.5f, z_rel),
                               eng_v3(0.09f, seg, 0.12f), trim_col, (uint8_t)knee);

            uint32_t li = out->gait.limb_count++;
            out->gait.hip_bone[li] = (uint8_t)hip;
            out->gait.knee_bone[li] = (uint8_t)knee;
            out->gait.ankle_bone[li] = (uint8_t)ankle;
            out->gait.rest_foot_offset[li] = eng_v3(sx, 0.0f, z_rel);
            out->gait.pole_dir[li] = eng_v3(0.0f, 0.0f, (archetype == ENG_ANIMAL_AVIAN) ? 1.0f : -1.0f);
            /* Diagonal trot / alternating tripod phase schedule */
            out->gait.phase_offset[li] = ((p + side) & 1) ? 0.5f : 0.0f;
        }
    }

    if (archetype == ENG_ANIMAL_AVIAN || archetype == ENG_ANIMAL_AQUATIC) {
        /* Symmetrical wings or lateral pectoral fins */
        float span = body_len * (archetype == ENG_ANIMAL_AVIAN ? 0.95f : 0.55f);
        append_skinned_box(&out->mesh, eng_v3(-span * 0.5f - body_rad * 0.5f, leg_h + body_rad * 1.1f, -0.1f),
                           eng_v3(span, 0.05f, body_len * 0.45f), trim_col, (uint8_t)b_chest);
        append_skinned_box(&out->mesh, eng_v3( span * 0.5f + body_rad * 0.5f, leg_h + body_rad * 1.1f, -0.1f),
                           eng_v3(span, 0.05f, body_len * 0.45f), trim_col, (uint8_t)b_chest);
    } else if (archetype == ENG_ANIMAL_SERPENTINE) {
        /* Multi-segment undulating spine chain */
        int prev = b_tail;
        for (int s = 0; s < 3; s++) {
            int seg_b = eng_skeleton_add_bone(&out->skeleton, "serp_seg", prev,
                                              eng_v3(0.0f, 0.0f, body_len * 0.35f), eng_quat_identity(), eng_v3(1, 1, 1));
            append_skinned_sphere(&out->mesh, eng_v3(0.0f, leg_h + body_rad * 0.8f, body_len * (0.85f + 0.35f * (float)s)),
                                  body_rad * (0.65f - 0.12f * (float)s), body_col, (uint8_t)seg_b);
            prev = seg_b;
        }
    }

    eng_skeleton_compute_inv_bind(&out->skeleton);
    out->height = leg_h + body_rad * 2.2f;
    out->length = body_len * 1.8f;
    return out->mesh.vert_count > 0;
}

void eng_animal_asset_free(eng_animal_asset_t *a) {
    if (!a) return;
    eng_mesh_data_free(&a->mesh);
    memset(a, 0, sizeof(*a));
}

bool eng_procgen_person(uint64_t seed, eng_person_asset_t *out) {
    if (!out) return false;
    memset(out, 0, sizeof(*out));
    eng_mesh_data_init(&out->mesh);
    eng_skeleton_init(&out->skeleton);

    eng_rng_t rng;
    eng_rng_seed(&rng, seed ? seed : 404u);

    static const char *const syl_a[8] = {"Ka", "Ma", "Lo", "Vi", "Ta", "Re", "So", "Ni"};
    static const char *const syl_b[8] = {"ra", "len", "vo", "mi", "ko", "na", "ric", "sa"};
    static const char *const roles[6] = {"guard", "merchant", "pilot", "scholar", "scout", "smith"};
    snprintf(out->name, sizeof(out->name), "%s%s", syl_a[eng_rng_u32(&rng) & 7u], syl_b[eng_rng_u32(&rng) & 7u]);
    snprintf(out->role, sizeof(out->role), "%s", roles[eng_rng_u32(&rng) % 6u]);

    float h = eng_rng_rangef(&rng, 1.58f, 1.92f);
    float build = eng_rng_rangef(&rng, 0.88f, 1.18f);
    out->height = h;

    float skin_t = eng_rng_float01(&rng);
    eng_vec3_t skin_rgb = eng_v3_lerp(eng_v3(0.32f, 0.21f, 0.14f), eng_v3(0.92f, 0.74f, 0.62f), skin_t);
    eng_vec4_t skin = {skin_rgb.x, skin_rgb.y, skin_rgb.z, 1.0f};
    eng_vec4_t tunic = {eng_rng_rangef(&rng, 0.15f, 0.85f), eng_rng_rangef(&rng, 0.15f, 0.85f), eng_rng_rangef(&rng, 0.15f, 0.85f), 1.0f};
    eng_vec4_t pants = {0.22f, 0.24f, 0.30f, 1.0f};
    eng_vec4_t hair  = {eng_rng_rangef(&rng, 0.08f, 0.75f), eng_rng_rangef(&rng, 0.06f, 0.55f), 0.08f, 1.0f};

    float leg_h = h * 0.48f;
    float torso_h = h * 0.32f;
    float head_r = h * 0.075f;

    int b_hips  = eng_skeleton_add_bone(&out->skeleton, "hips", -1, eng_v3(0.0f, leg_h, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));
    int b_spine = eng_skeleton_add_bone(&out->skeleton, "spine", b_hips, eng_v3(0.0f, torso_h * 0.5f, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));
    int b_head  = eng_skeleton_add_bone(&out->skeleton, "head", b_spine, eng_v3(0.0f, torso_h * 0.5f + head_r, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));

    append_skinned_box(&out->mesh, eng_v3(0.0f, leg_h + torso_h * 0.5f, 0.0f),
                       eng_v3(0.36f * build, torso_h, 0.22f * build), tunic, (uint8_t)b_spine);
    append_skinned_sphere(&out->mesh, eng_v3(0.0f, leg_h + torso_h + head_r, 0.0f), head_r, skin, (uint8_t)b_head);
    /* Hair cap / hat + optional backpack */
    append_skinned_box(&out->mesh, eng_v3(0.0f, leg_h + torso_h + head_r * 1.55f, 0.0f),
                       eng_v3(head_r * 2.1f, head_r * 0.8f, head_r * 2.1f), hair, (uint8_t)b_head);
    if ((eng_rng_u32(&rng) & 1u) != 0) {
        append_skinned_box(&out->mesh, eng_v3(0.0f, leg_h + torso_h * 0.55f, 0.16f * build),
                           eng_v3(0.26f, 0.32f, 0.14f), hair, (uint8_t)b_spine);
    }

    /* Arms */
    for (int s = 0; s < 2; s++) {
        float sx = (s == 0 ? -1.0f : 1.0f) * (0.24f * build);
        int sh = eng_skeleton_add_bone(&out->skeleton, s == 0 ? "arm_l" : "arm_r", b_spine,
                                       eng_v3(sx, torso_h * 0.42f, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));
        append_skinned_box(&out->mesh, eng_v3(sx, leg_h + torso_h * 0.55f, 0.0f),
                           eng_v3(0.10f, torso_h * 0.85f, 0.10f), skin, (uint8_t)sh);
    }

    /* 2-bone IK legs */
    out->gait.stride_length = leg_h * 0.70f;
    out->gait.step_height = leg_h * 0.22f;
    out->gait.cycle_hz = 1.7f;
    for (int s = 0; s < 2; s++) {
        float sx = (s == 0 ? -1.0f : 1.0f) * 0.11f * build;
        float seg = leg_h * 0.5f;
        int hip   = eng_skeleton_add_bone(&out->skeleton, s == 0 ? "hip_l" : "hip_r", b_hips, eng_v3(sx, 0.0f, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));
        int knee  = eng_skeleton_add_bone(&out->skeleton, s == 0 ? "knee_l" : "knee_r", hip, eng_v3(0.0f, -seg, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));
        int ankle = eng_skeleton_add_bone(&out->skeleton, s == 0 ? "ankle_l" : "ankle_r", knee, eng_v3(0.0f, -seg, 0.0f), eng_quat_identity(), eng_v3(1, 1, 1));

        append_skinned_box(&out->mesh, eng_v3(sx, leg_h - seg * 0.5f, 0.0f), eng_v3(0.12f, seg, 0.12f), pants, (uint8_t)hip);
        append_skinned_box(&out->mesh, eng_v3(sx, seg * 0.5f, 0.0f), eng_v3(0.10f, seg, 0.13f), pants, (uint8_t)knee);

        uint32_t li = out->gait.limb_count++;
        out->gait.hip_bone[li] = (uint8_t)hip;
        out->gait.knee_bone[li] = (uint8_t)knee;
        out->gait.ankle_bone[li] = (uint8_t)ankle;
        out->gait.rest_foot_offset[li] = eng_v3(sx, 0.0f, 0.0f);
        out->gait.pole_dir[li] = eng_v3(0.0f, 0.0f, -1.0f);
        out->gait.phase_offset[li] = (s == 0) ? 0.0f : 0.5f;
    }

    eng_skeleton_compute_inv_bind(&out->skeleton);
    return out->mesh.vert_count > 0;
}

void eng_person_asset_free(eng_person_asset_t *p) {
    if (!p) return;
    eng_mesh_data_free(&p->mesh);
    memset(p, 0, sizeof(*p));
}
