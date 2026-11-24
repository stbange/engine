#include "engine/eng_physics.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_BODIES 1024
#define ENG_MAX_POCKET_GRAV 32
#define ENG_MAX_CONTACTS 512

typedef struct {
    bool active;
    eng_body_desc_t b;
    float inv_mass;
    eng_aabb_t world_aabb;
} body_slot_t;

typedef struct {
    bool radial;
    eng_vec3_t linear;
    eng_vec3_t center;
    float surface_g;
    bool has_planet_cfg;
    eng_planet_cfg_t planet_cfg;
} pocket_grav_t;

typedef struct {
    eng_aabb_t box;
    int left;
    int right;
    int body_slot; /* >= 0 for leaf */
} bvh_node_t;

struct eng_physics_s {
    body_slot_t bodies[ENG_MAX_BODIES];
    uint32_t body_high;
    pocket_grav_t grav[ENG_MAX_POCKET_GRAV];
    eng_contact_event_t contacts[ENG_MAX_CONTACTS];
    size_t contact_count;
};

eng_body_desc_t eng_body_default_desc(eng_shape_type_t shape, eng_body_motion_t motion) {
    return (eng_body_desc_t){
        .entity = ENG_ENTITY_NULL,
        .motion = motion,
        .shape = shape,
        .pocket_id = 0,
        .is_trigger = false,
        .pos = {0, 0, 0},
        .rot = {0, 0, 0, 1},
        .vel = {0, 0, 0},
        .ang_vel = {0, 0, 0},
        .mass = (motion == ENG_BODY_DYNAMIC) ? 1.0f : 0.0f,
        .restitution = 0.2f,
        .friction = 0.5f,
        .radius = 0.5f,
        .half_height = 0.5f,
        .half_extents = {0.5f, 0.5f, 0.5f}
    };
}

eng_physics_t *eng_physics_create(void) {
    eng_physics_t *p = (eng_physics_t *)calloc(1, sizeof(eng_physics_t));
    if (!p) return NULL;
    for (int i = 0; i < ENG_MAX_POCKET_GRAV; i++) {
        p->grav[i].linear = eng_v3(0.0f, -9.81f, 0.0f);
    }
    return p;
}

void eng_physics_destroy(eng_physics_t *phys) {
    free(phys);
}

void eng_physics_set_gravity(eng_physics_t *phys, uint16_t pocket_id, eng_vec3_t linear_gravity) {
    if (!phys || pocket_id >= ENG_MAX_POCKET_GRAV) return;
    phys->grav[pocket_id].radial = false;
    phys->grav[pocket_id].linear = linear_gravity;
}

void eng_physics_set_planet_gravity(eng_physics_t *phys, uint16_t pocket_id,
                                    eng_vec3_t planet_center, float surface_g,
                                    const eng_planet_cfg_t *planet_surface_opt) {
    if (!phys || pocket_id >= ENG_MAX_POCKET_GRAV) return;
    pocket_grav_t *g = &phys->grav[pocket_id];
    g->radial = true;
    g->center = planet_center;
    g->surface_g = surface_g > 0.0f ? surface_g : 9.81f;
    g->has_planet_cfg = (planet_surface_opt != NULL);
    if (planet_surface_opt) g->planet_cfg = *planet_surface_opt;
}

static eng_aabb_t compute_body_aabb(const eng_body_desc_t *b) {
    switch (b->shape) {
        case ENG_SHAPE_SPHERE: {
            eng_vec3_t r = eng_v3(b->radius, b->radius, b->radius);
            return (eng_aabb_t){eng_v3_sub(b->pos, r), eng_v3_add(b->pos, r)};
        }
        case ENG_SHAPE_CAPSULE: {
            eng_vec3_t up = eng_quat_rotate_v3(b->rot, eng_v3(0.0f, b->half_height, 0.0f));
            eng_vec3_t p0 = eng_v3_sub(b->pos, up), p1 = eng_v3_add(b->pos, up);
            eng_vec3_t r = eng_v3(b->radius, b->radius, b->radius);
            eng_vec3_t mn = eng_v3(fminf(p0.x, p1.x), fminf(p0.y, p1.y), fminf(p0.z, p1.z));
            eng_vec3_t mx = eng_v3(fmaxf(p0.x, p1.x), fmaxf(p0.y, p1.y), fmaxf(p0.z, p1.z));
            return (eng_aabb_t){eng_v3_sub(mn, r), eng_v3_add(mx, r)};
        }
        case ENG_SHAPE_CONVEX_HULL: {
            eng_aabb_t box = {eng_v3(FLT_MAX, FLT_MAX, FLT_MAX), eng_v3(-FLT_MAX, -FLT_MAX, -FLT_MAX)};
            for (uint32_t i = 0; i < b->hull_vert_count && i < 16; i++) {
                eng_vec3_t wp = eng_v3_add(b->pos, eng_quat_rotate_v3(b->rot, b->hull_verts[i]));
                if (wp.x < box.min.x) box.min.x = wp.x;
                if (wp.y < box.min.y) box.min.y = wp.y;
                if (wp.z < box.min.z) box.min.z = wp.z;
                if (wp.x > box.max.x) box.max.x = wp.x;
                if (wp.y > box.max.y) box.max.y = wp.y;
                if (wp.z > box.max.z) box.max.z = wp.z;
            }
            return box;
        }
        case ENG_SHAPE_VOXEL_CHUNK: {
            if (!b->voxel_chunk) return (eng_aabb_t){b->pos, b->pos};
            float vs = b->voxel_chunk->voxel_size;
            eng_vec3_t sz = eng_v3((float)b->voxel_chunk->sx * vs, (float)b->voxel_chunk->sy * vs, (float)b->voxel_chunk->sz * vs);
            return (eng_aabb_t){b->pos, eng_v3_add(b->pos, sz)};
        }
        case ENG_SHAPE_TERRAIN: {
            if (!b->terrain) return (eng_aabb_t){b->pos, b->pos};
            float wx = (float)(b->terrain->grid_w - 1) * b->terrain->cell_size;
            float wz = (float)(b->terrain->grid_d - 1) * b->terrain->cell_size;
            return (eng_aabb_t){eng_v3(b->pos.x, -500.0f, b->pos.z), eng_v3(b->pos.x + wx, 500.0f, b->pos.z + wz)};
        }
        default: /* ENG_SHAPE_AABB */
            return (eng_aabb_t){eng_v3_sub(b->pos, b->half_extents), eng_v3_add(b->pos, b->half_extents)};
    }
}

uint32_t eng_physics_add_body(eng_physics_t *phys, const eng_body_desc_t *desc) {
    if (!phys || !desc) return 0;
    for (uint32_t i = 0; i < ENG_MAX_BODIES; i++) {
        if (!phys->bodies[i].active) {
            body_slot_t *s = &phys->bodies[i];
            s->active = true;
            s->b = *desc;
            s->inv_mass = (desc->motion == ENG_BODY_DYNAMIC && desc->mass > 1e-4f) ? (1.0f / desc->mass) : 0.0f;
            s->world_aabb = compute_body_aabb(&s->b);
            if (i + 1u > phys->body_high) phys->body_high = i + 1u;
            return i + 1u;
        }
    }
    return 0;
}

bool eng_physics_remove_body(eng_physics_t *phys, uint32_t body_id) {
    if (!phys || body_id == 0 || body_id > ENG_MAX_BODIES || !phys->bodies[body_id - 1u].active) return false;
    memset(&phys->bodies[body_id - 1u], 0, sizeof(body_slot_t));
    return true;
}

eng_body_desc_t *eng_physics_get_body(eng_physics_t *phys, uint32_t body_id) {
    if (!phys || body_id == 0 || body_id > ENG_MAX_BODIES || !phys->bodies[body_id - 1u].active) return NULL;
    return &phys->bodies[body_id - 1u].b;
}

/* --------------------------------------------------------------------------
 * Pure-C11 Gilbert-Johnson-Keerthi (GJK) Convex Intersection
 * -------------------------------------------------------------------------- */
static eng_vec3_t support_cloud(const eng_vec3_t *verts, size_t n, eng_vec3_t dir) {
    float best = -FLT_MAX;
    eng_vec3_t out = verts[0];
    for (size_t i = 0; i < n; i++) {
        float d = eng_v3_dot(verts[i], dir);
        if (d > best) { best = d; out = verts[i]; }
    }
    return out;
}

static eng_vec3_t minkowski_sup(const eng_vec3_t *va, size_t na, const eng_vec3_t *vb, size_t nb, eng_vec3_t d) {
    return eng_v3_sub(support_cloud(va, na, d), support_cloud(vb, nb, eng_v3_scale(d, -1.0f)));
}

static eng_vec3_t triple_prod(eng_vec3_t a, eng_vec3_t b, eng_vec3_t c) {
    /* (a x b) x c = b(a.c) - a(b.c) */
    return eng_v3_sub(eng_v3_scale(b, eng_v3_dot(a, c)), eng_v3_scale(a, eng_v3_dot(b, c)));
}

bool eng_physics_gjk_intersect(const eng_vec3_t *va, size_t na,
                               const eng_vec3_t *vb, size_t nb,
                               eng_vec3_t *out_sep_dir, float *out_depth) {
    if (!va || !vb || na == 0 || nb == 0) return false;

    eng_vec3_t ca = {0, 0, 0}, cb = {0, 0, 0};
    for (size_t i = 0; i < na; i++) ca = eng_v3_add(ca, va[i]);
    for (size_t i = 0; i < nb; i++) cb = eng_v3_add(cb, vb[i]);
    ca = eng_v3_scale(ca, 1.0f / (float)na);
    cb = eng_v3_scale(cb, 1.0f / (float)nb);

    eng_vec3_t dir = eng_v3_sub(cb, ca);
    if (eng_v3_dot(dir, dir) < 1e-6f) dir = eng_v3(1.0f, 0.0f, 0.0f);

    eng_vec3_t s[4];
    int sn = 1;
    s[0] = minkowski_sup(va, na, vb, nb, dir);
    dir = eng_v3_scale(s[0], -1.0f);

    for (int iter = 0; iter < 24; iter++) {
        if (eng_v3_dot(dir, dir) < 1e-8f) break;
        eng_vec3_t a = minkowski_sup(va, na, vb, nb, dir);
        if (eng_v3_dot(a, dir) < 0.0f) return false; /* Separating axis found */

        s[sn++] = a;
        eng_vec3_t ao = eng_v3_scale(a, -1.0f);
        if (sn == 2) {
            eng_vec3_t ab = eng_v3_sub(s[0], a);
            dir = triple_prod(ab, ao, ab);
            if (eng_v3_dot(dir, dir) < 1e-8f) dir = eng_v3_cross(ab, eng_v3(0, 1, 0));
            if (eng_v3_dot(dir, dir) < 1e-8f) dir = eng_v3_cross(ab, eng_v3(1, 0, 0));
        } else if (sn == 3) {
            eng_vec3_t ab = eng_v3_sub(s[1], a);
            eng_vec3_t ac = eng_v3_sub(s[0], a);
            eng_vec3_t abc = eng_v3_cross(ab, ac);
            if (eng_v3_dot(eng_v3_cross(abc, ac), ao) > 0.0f) {
                s[1] = a; sn = 2;
                dir = triple_prod(ac, ao, ac);
            } else if (eng_v3_dot(eng_v3_cross(ab, abc), ao) > 0.0f) {
                s[0] = s[1]; s[1] = a; sn = 2;
                dir = triple_prod(ab, ao, ab);
            } else {
                if (eng_v3_dot(abc, ao) > 0.0f) {
                    dir = abc;
                } else {
                    eng_vec3_t tmp = s[0]; s[0] = s[1]; s[1] = tmp;
                    dir = eng_v3_scale(abc, -1.0f);
                }
            }
        } else { /* Tetrahedron sn == 4 */
            eng_vec3_t ab = eng_v3_sub(s[2], a);
            eng_vec3_t ac = eng_v3_sub(s[1], a);
            eng_vec3_t ad = eng_v3_sub(s[0], a);
            eng_vec3_t abc = eng_v3_cross(ab, ac);
            eng_vec3_t acd = eng_v3_cross(ac, ad);
            eng_vec3_t adb = eng_v3_cross(ad, ab);

            if (eng_v3_dot(abc, ao) > 0.0f) {
                s[0] = s[1]; s[1] = s[2]; s[2] = a; sn = 3; dir = abc;
            } else if (eng_v3_dot(acd, ao) > 0.0f) {
                s[2] = a; sn = 3; dir = acd;
            } else if (eng_v3_dot(adb, ao) > 0.0f) {
                s[1] = s[0]; s[0] = s[2]; s[2] = a; sn = 3; dir = adb;
            } else {
                /* Origin enclosed inside tetrahedron -> estimate MTV along centroid axis */
                eng_vec3_t n = eng_v3_norm(eng_v3_sub(cb, ca));
                if (eng_v3_dot(n, n) < 0.1f) n = eng_v3(0.0f, 1.0f, 0.0f);
                eng_vec3_t p = minkowski_sup(va, na, vb, nb, n);
                if (out_sep_dir) *out_sep_dir = n;
                if (out_depth) *out_depth = fmaxf(eng_v3_dot(p, n), 0.01f);
                return true;
            }
        }
    }
    return false;
}

/* --------------------------------------------------------------------------
 * Narrowphase Contact Generation (Normal points from A -> B)
 * -------------------------------------------------------------------------- */
static bool sphere_vs_aabb(eng_vec3_t sp_c, float rad, eng_aabb_t box, eng_vec3_t *out_n, float *out_pen) {
    eng_vec3_t closest = eng_v3(
        eng_clampf(sp_c.x, box.min.x, box.max.x),
        eng_clampf(sp_c.y, box.min.y, box.max.y),
        eng_clampf(sp_c.z, box.min.z, box.max.z)
    );
    eng_vec3_t diff = eng_v3_sub(closest, sp_c);
    float d2 = eng_v3_dot(diff, diff);
    if (d2 > rad * rad) return false;
    float d = sqrtf(d2);
    if (d > 1e-5f) {
        *out_n = eng_v3_scale(diff, 1.0f / d);
        *out_pen = rad - d;
    } else {
        /* Sphere center inside AABB: push out along shallowest axis */
        float dx0 = sp_c.x - box.min.x, dx1 = box.max.x - sp_c.x;
        float dy0 = sp_c.y - box.min.y, dy1 = box.max.y - sp_c.y;
        float dz0 = sp_c.z - box.min.z, dz1 = box.max.z - sp_c.z;
        float best = dy1; *out_n = eng_v3(0, -1, 0);
        if (dy0 < best) { best = dy0; *out_n = eng_v3(0, 1, 0); }
        if (dx0 < best) { best = dx0; *out_n = eng_v3(1, 0, 0); }
        if (dx1 < best) { best = dx1; *out_n = eng_v3(-1, 0, 0); }
        if (dz0 < best) { best = dz0; *out_n = eng_v3(0, 0, 1); }
        if (dz1 < best) { best = dz1; *out_n = eng_v3(0, 0, -1); }
        *out_pen = rad + best;
    }
    return true;
}

static size_t body_world_hull(const eng_body_desc_t *b, eng_vec3_t out_v[16]) {
    if (b->shape == ENG_SHAPE_CONVEX_HULL) {
        size_t n = b->hull_vert_count < 16 ? b->hull_vert_count : 16;
        for (size_t i = 0; i < n; i++) out_v[i] = eng_v3_add(b->pos, eng_quat_rotate_v3(b->rot, b->hull_verts[i]));
        return n;
    }
    eng_aabb_t ab = compute_body_aabb(b);
    out_v[0] = eng_v3(ab.min.x, ab.min.y, ab.min.z); out_v[1] = eng_v3(ab.max.x, ab.min.y, ab.min.z);
    out_v[2] = eng_v3(ab.min.x, ab.max.y, ab.min.z); out_v[3] = eng_v3(ab.max.x, ab.max.y, ab.min.z);
    out_v[4] = eng_v3(ab.min.x, ab.min.y, ab.max.z); out_v[5] = eng_v3(ab.max.x, ab.min.y, ab.max.z);
    out_v[6] = eng_v3(ab.min.x, ab.max.y, ab.max.z); out_v[7] = eng_v3(ab.max.x, ab.max.y, ab.max.z);
    return 8;
}

static bool test_pair(const eng_body_desc_t *a, eng_aabb_t box_a,
                      const eng_body_desc_t *b, eng_aabb_t box_b,
                      eng_vec3_t *out_n, float *out_pen) {
    /* Terrain heightfield vs dynamic Sphere/Capsule/AABB */
    if (b->shape == ENG_SHAPE_TERRAIN && b->terrain) {
        float bottom = box_a.min.y;
        float th = b->pos.y + eng_terrain_sample_height(b->terrain, a->pos.x - b->pos.x, a->pos.z - b->pos.z);
        if (bottom < th) {
            eng_vec3_t tn = eng_terrain_sample_normal(b->terrain, a->pos.x - b->pos.x, a->pos.z - b->pos.z);
            *out_n = eng_v3_scale(tn, -1.0f);
            *out_pen = th - bottom;
            return true;
        }
        return false;
    }
    if (a->shape == ENG_SHAPE_TERRAIN && a->terrain) {
        if (test_pair(b, box_b, a, box_a, out_n, out_pen)) {
            *out_n = eng_v3_scale(*out_n, -1.0f);
            return true;
        }
        return false;
    }

    if (!eng_aabb_overlaps(box_a, box_b, NULL)) return false;

    /* Voxel chunk narrowphase */
    if (b->shape == ENG_SHAPE_VOXEL_CHUNK && b->voxel_chunk) {
        const eng_voxel_chunk_t *vc = b->voxel_chunk;
        float vs = vc->voxel_size;
        int x0 = (int)floorf((box_a.min.x - b->pos.x) / vs), x1 = (int)floorf((box_a.max.x - b->pos.x) / vs);
        int y0 = (int)floorf((box_a.min.y - b->pos.y) / vs), y1 = (int)floorf((box_a.max.y - b->pos.y) / vs);
        int z0 = (int)floorf((box_a.min.z - b->pos.z) / vs), z1 = (int)floorf((box_a.max.z - b->pos.z) / vs);
        float sp_r = (a->shape == ENG_SHAPE_SPHERE || a->shape == ENG_SHAPE_CAPSULE) ? a->radius : eng_v3_len(a->half_extents) * 0.58f;
        float best_pen = 0.0f;
        eng_vec3_t best_n = {0, 1, 0};
        for (int vy = y0; vy <= y1; vy++) {
            for (int vz = z0; vz <= z1; vz++) {
                for (int vx = x0; vx <= x1; vx++) {
                    if (eng_voxel_get(vc, vx, vy, vz) == 0) continue;
                    eng_aabb_t cell = {
                        eng_v3(b->pos.x + (float)vx * vs, b->pos.y + (float)vy * vs, b->pos.z + (float)vz * vs),
                        eng_v3(b->pos.x + (float)(vx + 1) * vs, b->pos.y + (float)(vy + 1) * vs, b->pos.z + (float)(vz + 1) * vs)
                    };
                    eng_vec3_t pa = a->pos;
                    if (a->shape == ENG_SHAPE_CAPSULE) {
                        pa.y = eng_clampf((cell.min.y + cell.max.y) * 0.5f, a->pos.y - a->half_height, a->pos.y + a->half_height);
                    }
                    eng_vec3_t cn; float cp;
                    if (sphere_vs_aabb(pa, sp_r, cell, &cn, &cp) && cp > best_pen) {
                        best_pen = cp;
                        best_n = cn;
                    }
                }
            }
        }
        if (best_pen > 0.0f) {
            *out_n = best_n;
            *out_pen = best_pen;
            return true;
        }
        return false;
    }
    if (a->shape == ENG_SHAPE_VOXEL_CHUNK) {
        if (test_pair(b, box_b, a, box_a, out_n, out_pen)) {
            *out_n = eng_v3_scale(*out_n, -1.0f);
            return true;
        }
        return false;
    }

    /* Convex Hull GJK */
    if (a->shape == ENG_SHAPE_CONVEX_HULL || b->shape == ENG_SHAPE_CONVEX_HULL) {
        eng_vec3_t va[16], vb[16];
        size_t na = body_world_hull(a, va), nb = body_world_hull(b, vb);
        return eng_physics_gjk_intersect(va, na, vb, nb, out_n, out_pen);
    }

    /* Sphere / Capsule vs Sphere / Capsule */
    bool a_round = (a->shape == ENG_SHAPE_SPHERE || a->shape == ENG_SHAPE_CAPSULE);
    bool b_round = (b->shape == ENG_SHAPE_SPHERE || b->shape == ENG_SHAPE_CAPSULE);
    if (a_round && b_round) {
        eng_vec3_t pa = a->pos, pb = b->pos;
        if (a->shape == ENG_SHAPE_CAPSULE) pa.y = eng_clampf(b->pos.y, a->pos.y - a->half_height, a->pos.y + a->half_height);
        if (b->shape == ENG_SHAPE_CAPSULE) pb.y = eng_clampf(pa.y, b->pos.y - b->half_height, b->pos.y + b->half_height);
        eng_vec3_t diff = eng_v3_sub(pb, pa);
        float d = eng_v3_len(diff);
        float rsum = a->radius + b->radius;
        if (d >= rsum) return false;
        *out_n = d > 1e-5f ? eng_v3_scale(diff, 1.0f / d) : eng_v3(0, -1, 0);
        *out_pen = rsum - d;
        return true;
    }
    if (a_round && b->shape == ENG_SHAPE_AABB) {
        eng_vec3_t pa = a->pos;
        if (a->shape == ENG_SHAPE_CAPSULE) {
            float cy = eng_clampf((box_b.min.y + box_b.max.y) * 0.5f, a->pos.y - a->half_height, a->pos.y + a->half_height);
            pa.y = cy;
        }
        return sphere_vs_aabb(pa, a->radius, box_b, out_n, out_pen);
    }
    if (a->shape == ENG_SHAPE_AABB && b_round) {
        if (test_pair(b, box_b, a, box_a, out_n, out_pen)) {
            *out_n = eng_v3_scale(*out_n, -1.0f);
            return true;
        }
        return false;
    }

    /* AABB vs AABB minimum-translation axis */
    float ox = fminf(box_a.max.x, box_b.max.x) - fmaxf(box_a.min.x, box_b.min.x);
    float oy = fminf(box_a.max.y, box_b.max.y) - fmaxf(box_a.min.y, box_b.min.y);
    float oz = fminf(box_a.max.z, box_b.max.z) - fmaxf(box_a.min.z, box_b.min.z);
    if (ox <= 0.0f || oy <= 0.0f || oz <= 0.0f) return false;
    if (oy <= ox && oy <= oz) {
        *out_n = (a->pos.y < b->pos.y) ? eng_v3(0, 1, 0) : eng_v3(0, -1, 0);
        *out_pen = oy;
    } else if (ox <= oz) {
        *out_n = (a->pos.x < b->pos.x) ? eng_v3(1, 0, 0) : eng_v3(-1, 0, 0);
        *out_pen = ox;
    } else {
        *out_n = (a->pos.z < b->pos.z) ? eng_v3(0, 0, 1) : eng_v3(0, 0, -1);
        *out_pen = oz;
    }
    return true;
}

/* --------------------------------------------------------------------------
 * Top-Down Median-Split Pocket BVH
 * -------------------------------------------------------------------------- */
static int build_bvh_rec(bvh_node_t *nodes, int *node_cnt, int *slots, int count, const body_slot_t *bodies) {
    int idx = (*node_cnt)++;
    eng_aabb_t bounds = bodies[slots[0]].world_aabb;
    for (int i = 1; i < count; i++) {
        eng_aabb_t b = bodies[slots[i]].world_aabb;
        bounds.min = eng_v3(fminf(bounds.min.x, b.min.x), fminf(bounds.min.y, b.min.y), fminf(bounds.min.z, b.min.z));
        bounds.max = eng_v3(fmaxf(bounds.max.x, b.max.x), fmaxf(bounds.max.y, b.max.y), fmaxf(bounds.max.z, b.max.z));
    }
    nodes[idx].box = bounds;
    if (count == 1) {
        nodes[idx].left = nodes[idx].right = -1;
        nodes[idx].body_slot = slots[0];
        return idx;
    }
    nodes[idx].body_slot = -1;
    eng_vec3_t ext = eng_v3_sub(bounds.max, bounds.min);
    int axis = (ext.x >= ext.y && ext.x >= ext.z) ? 0 : (ext.y >= ext.z ? 1 : 2);

    /* Simple insertion partition around midpoint */
    for (int i = 1; i < count; i++) {
        int key = slots[i];
        float kc = (&bodies[key].b.pos.x)[axis];
        int j = i - 1;
        while (j >= 0 && (&bodies[slots[j]].b.pos.x)[axis] > kc) {
            slots[j + 1] = slots[j];
            j--;
        }
        slots[j + 1] = key;
    }
    int mid = count / 2;
    nodes[idx].left = build_bvh_rec(nodes, node_cnt, slots, mid, bodies);
    nodes[idx].right = build_bvh_rec(nodes, node_cnt, slots + mid, count - mid, bodies);
    return idx;
}

static void query_bvh_overlaps(const bvh_node_t *nodes, int node_idx, eng_aabb_t query_box, int *out_slots, int *out_n, int max_n) {
    if (node_idx < 0 || *out_n >= max_n) return;
    if (!eng_aabb_overlaps(nodes[node_idx].box, query_box, NULL)) return;
    if (nodes[node_idx].body_slot >= 0) {
        out_slots[(*out_n)++] = nodes[node_idx].body_slot;
        return;
    }
    query_bvh_overlaps(nodes, nodes[node_idx].left, query_box, out_slots, out_n, max_n);
    query_bvh_overlaps(nodes, nodes[node_idx].right, query_box, out_slots, out_n, max_n);
}

static void resolve_impulse(body_slot_t *sa, body_slot_t *sb, eng_vec3_t n, float pen) {
    float inv_sum = sa->inv_mass + sb->inv_mass;
    if (inv_sum <= 0.0f) return;

    /* Positional Baumgarte projection */
    float corr = fmaxf(pen - 0.002f, 0.0f) * 0.8f / inv_sum;
    sa->b.pos = eng_v3_sub(sa->b.pos, eng_v3_scale(n, corr * sa->inv_mass));
    sb->b.pos = eng_v3_add(sb->b.pos, eng_v3_scale(n, corr * sb->inv_mass));

    eng_vec3_t rv = eng_v3_sub(sb->b.vel, sa->b.vel);
    float vn = eng_v3_dot(rv, n);
    if (vn > 0.0f) return;

    float e = fminf(sa->b.restitution, sb->b.restitution);
    float j = -(1.0f + e) * vn / inv_sum;
    eng_vec3_t imp = eng_v3_scale(n, j);
    sa->b.vel = eng_v3_sub(sa->b.vel, eng_v3_scale(imp, sa->inv_mass));
    sb->b.vel = eng_v3_add(sb->b.vel, eng_v3_scale(imp, sb->inv_mass));

    /* Coulomb tangential friction */
    eng_vec3_t tang = eng_v3_sub(rv, eng_v3_scale(n, vn));
    float tlen = eng_v3_len(tang);
    if (tlen > 1e-4f) {
        tang = eng_v3_scale(tang, 1.0f / tlen);
        float jt = -eng_v3_dot(rv, tang) / inv_sum;
        float mu = sqrtf(fmaxf(0.0f, sa->b.friction * sb->b.friction));
        jt = eng_clampf(jt, -j * mu, j * mu);
        eng_vec3_t fimp = eng_v3_scale(tang, jt);
        sa->b.vel = eng_v3_sub(sa->b.vel, eng_v3_scale(fimp, sa->inv_mass));
        sb->b.vel = eng_v3_add(sb->b.vel, eng_v3_scale(fimp, sb->inv_mass));
    }
}

static void warp_body_across_portal(body_slot_t *s, const eng_portal_sys_t *portals, const eng_scene_t *scene,
                                    const eng_portal_t *p, eng_vec3_t prev_pos, eng_vec3_t warped_pos) {
    eng_mat4_t warp;
    if (!eng_portal_warp_matrix(scene, p, &warp)) return;
    s->b.vel = eng_portal_transform_velocity(portals, scene, p, prev_pos, s->b.vel);
    s->b.pos = warped_pos;
    s->b.radius *= p->scale_ratio;
    s->b.half_height *= p->scale_ratio;
    s->b.half_extents = eng_v3_scale(s->b.half_extents, p->scale_ratio);
    s->b.pocket_id = p->dst_pocket;
}

void eng_physics_step(eng_physics_t *phys, const eng_scene_t *scene,
                      const eng_portal_sys_t *portals, float dt) {
    if (!phys || dt <= 0.0f) return;
    phys->contact_count = 0;

    /* 1. Integrate forces & velocities + check cross-portal threshold teleportation */
    for (uint32_t i = 0; i < phys->body_high; i++) {
        body_slot_t *s = &phys->bodies[i];
        if (!s->active) continue;
        eng_vec3_t prev_pos = s->b.pos;

        if (s->b.motion == ENG_BODY_DYNAMIC) {
            uint16_t pid = s->b.pocket_id < ENG_MAX_POCKET_GRAV ? s->b.pocket_id : 0;
            const pocket_grav_t *g = &phys->grav[pid];
            eng_vec3_t acc = g->radial
                                 ? eng_v3_scale(eng_planet_gravity_up(g->center, s->b.pos), -g->surface_g)
                                 : g->linear;
            s->b.vel = eng_v3_add(s->b.vel, eng_v3_scale(acc, dt));
            s->b.pos = eng_v3_add(s->b.pos, eng_v3_scale(s->b.vel, dt));

            /* Procedural planet spherical surface collision */
            if (g->radial && g->has_planet_cfg) {
                eng_vec3_t up = eng_planet_gravity_up(g->center, s->b.pos);
                float surf_r = eng_planet_sample_radius(&g->planet_cfg, up);
                float cur_r = eng_v3_len(eng_v3_sub(s->b.pos, g->center));
                float min_r = surf_r + s->b.radius;
                if (cur_r < min_r) {
                    s->b.pos = eng_v3_add(g->center, eng_v3_scale(up, min_r));
                    float vn = eng_v3_dot(s->b.vel, up);
                    if (vn < 0.0f) s->b.vel = eng_v3_sub(s->b.vel, eng_v3_scale(up, (1.0f + s->b.restitution) * vn));
                }
            }
        } else if (s->b.motion == ENG_BODY_KINEMATIC) {
            s->b.pos = eng_v3_add(s->b.pos, eng_v3_scale(s->b.vel, dt));
        }

        if (s->b.motion != ENG_BODY_STATIC && portals && scene) {
            eng_vec3_t warped;
            const eng_portal_t *crossed = eng_portal_check_crossing(portals, scene, s->b.pocket_id, prev_pos, s->b.pos, &warped);
            if (crossed) warp_body_across_portal(s, portals, scene, crossed, prev_pos, warped);
        }
        s->world_aabb = compute_body_aabb(&s->b);
    }

    /* 2. Build per-pocket BVHs and solve contacts + cross-portal ghost proxy contacts */
    bvh_node_t *nodes = (bvh_node_t *)malloc(2u * ENG_MAX_BODIES * sizeof(bvh_node_t));
    int *slot_buf = (int *)malloc(ENG_MAX_BODIES * sizeof(int));
    if (!nodes || !slot_buf) { free(nodes); free(slot_buf); return; }

    for (uint16_t pk = 0; pk < ENG_MAX_POCKET_GRAV; pk++) {
        int cnt = 0;
        for (uint32_t i = 0; i < phys->body_high; i++) {
            if (phys->bodies[i].active && phys->bodies[i].b.pocket_id == pk) slot_buf[cnt++] = (int)i;
        }
        if (cnt < 2) continue;

        int node_cnt = 0;
        int root = build_bvh_rec(nodes, &node_cnt, slot_buf, cnt, phys->bodies);

        int hits[128];
        for (uint32_t i = 0; i < phys->body_high; i++) {
            body_slot_t *sa = &phys->bodies[i];
            if (!sa->active || sa->b.pocket_id != pk) continue;
            int hn = 0;
            query_bvh_overlaps(nodes, root, sa->world_aabb, hits, &hn, 128);
            for (int k = 0; k < hn; k++) {
                uint32_t j = (uint32_t)hits[k];
                if (j <= i) continue;
                body_slot_t *sb = &phys->bodies[j];
                if (sa->b.motion == ENG_BODY_STATIC && sb->b.motion == ENG_BODY_STATIC) continue;

                eng_vec3_t n = {0, 1, 0};
                float pen = 0.0f;
                if (test_pair(&sa->b, sa->world_aabb, &sb->b, sb->world_aabb, &n, &pen)) {
                    bool trig = sa->b.is_trigger || sb->b.is_trigger;
                    if (!trig) {
                        resolve_impulse(sa, sb, n, pen);
                        sa->world_aabb = compute_body_aabb(&sa->b);
                        sb->world_aabb = compute_body_aabb(&sb->b);
                    }
                    if (phys->contact_count < ENG_MAX_CONTACTS) {
                        phys->contacts[phys->contact_count++] = (eng_contact_event_t){i + 1u, j + 1u, n, pen, trig};
                    }
                }
            }
        }
    }

    /* Cross-portal ghost proxy collider resolution for bodies straddling a portal doorway */
    if (portals && scene) {
        size_t pc = eng_portal_count(portals);
        for (size_t pi = 0; pi < pc; pi++) {
            const eng_portal_t *p = eng_portal_get(portals, pi);
            const eng_mat4_t *m_src = p ? eng_scene_get_world_matrix(scene, p->src_ent) : NULL;
            eng_mat4_t warp, inv_warp;
            if (!p || !p->passable || !m_src || !eng_portal_warp_matrix(scene, p, &warp) || !eng_mat4_invert(&warp, &inv_warp)) continue;
            eng_vec3_t door_pos = eng_v3(m_src->m[12], m_src->m[13], m_src->m[14]);

            for (uint32_t i = 0; i < phys->body_high; i++) {
                body_slot_t *sa = &phys->bodies[i];
                if (!sa->active || sa->b.motion != ENG_BODY_DYNAMIC || sa->b.pocket_id != p->src_pocket) continue;
                if (eng_v3_len(eng_v3_sub(sa->b.pos, door_pos)) > fmaxf(p->half_w, p->half_h) + 1.5f) continue;

                /* Test warped dynamic body against static colliders in dst_pocket */
                body_slot_t ghost = *sa;
                ghost.b.pos = eng_mat4_transform_point(&warp, sa->b.pos);
                ghost.b.radius *= p->scale_ratio;
                ghost.b.half_extents = eng_v3_scale(sa->b.half_extents, p->scale_ratio);
                ghost.world_aabb = compute_body_aabb(&ghost.b);

                for (uint32_t j = 0; j < phys->body_high; j++) {
                    body_slot_t *sb = &phys->bodies[j];
                    if (!sb->active || sb->b.motion != ENG_BODY_STATIC || sb->b.pocket_id != p->dst_pocket || sb->b.is_trigger) continue;
                    eng_vec3_t n = {0, 1, 0};
                    float pen = 0.0f;
                    if (test_pair(&ghost.b, ghost.world_aabb, &sb->b, sb->world_aabb, &n, &pen)) {
                        ghost.b.pos = eng_v3_sub(ghost.b.pos, eng_v3_scale(n, pen));
                        sa->b.pos = eng_mat4_transform_point(&inv_warp, ghost.b.pos);
                        sa->world_aabb = compute_body_aabb(&sa->b);
                    }
                }
            }
        }
    }

    free(nodes);
    free(slot_buf);
}

bool eng_physics_move_character(eng_physics_t *phys, const eng_scene_t *scene,
                                const eng_portal_sys_t *portals, uint32_t body_id,
                                eng_vec3_t wish_disp, float max_step_height, bool *out_grounded) {
    if (!phys || body_id == 0 || body_id > ENG_MAX_BODIES || !phys->bodies[body_id - 1u].active) return false;
    body_slot_t *ch = &phys->bodies[body_id - 1u];
    uint16_t pid = ch->b.pocket_id < ENG_MAX_POCKET_GRAV ? ch->b.pocket_id : 0;
    const pocket_grav_t *g = &phys->grav[pid];
    eng_vec3_t up = g->radial ? eng_planet_gravity_up(g->center, ch->b.pos) : eng_v3(0.0f, 1.0f, 0.0f);

    eng_vec3_t prev_pos = ch->b.pos;
    ch->b.pos = eng_v3_add(ch->b.pos, wish_disp);
    ch->world_aabb = compute_body_aabb(&ch->b);

    bool grounded = false;
    if (g->radial && g->has_planet_cfg) {
        eng_vec3_t n_up = eng_planet_gravity_up(g->center, ch->b.pos);
        float min_r = eng_planet_sample_radius(&g->planet_cfg, n_up) + ch->b.radius;
        if (eng_v3_len(eng_v3_sub(ch->b.pos, g->center)) <= min_r + 0.03f) {
            ch->b.pos = eng_v3_add(g->center, eng_v3_scale(n_up, min_r));
            grounded = true;
        }
    }

    for (uint32_t j = 0; j < phys->body_high; j++) {
        if (j == body_id - 1u) continue;
        body_slot_t *sb = &phys->bodies[j];
        if (!sb->active || sb->b.pocket_id != ch->b.pocket_id || sb->b.is_trigger) continue;

        eng_vec3_t n = {0, 1, 0};
        float pen = 0.0f;
        if (!test_pair(&ch->b, ch->world_aabb, &sb->b, sb->world_aabb, &n, &pen)) continue;

        /* Check if lateral obstacle can be stepped over cleanly */
        float wall_dot = fabsf(eng_v3_dot(n, up));
        if (wall_dot < 0.4f && max_step_height > 0.01f) {
            eng_body_desc_t stepped = ch->b;
            stepped.pos = eng_v3_add(ch->b.pos, eng_v3_scale(up, max_step_height));
            eng_aabb_t step_box = compute_body_aabb(&stepped);
            eng_vec3_t dummy_n; float dummy_p;
            if (!test_pair(&stepped, step_box, &sb->b, sb->world_aabb, &dummy_n, &dummy_p)) {
                ch->b.pos = stepped.pos;
                ch->world_aabb = step_box;
                grounded = true;
                continue;
            }
        }

        ch->b.pos = eng_v3_sub(ch->b.pos, eng_v3_scale(n, pen));
        ch->world_aabb = compute_body_aabb(&ch->b);
        if (eng_v3_dot(eng_v3_scale(n, -1.0f), up) > 0.65f) grounded = true;
    }

    if (portals && scene) {
        eng_vec3_t warped;
        const eng_portal_t *crossed = eng_portal_check_crossing(portals, scene, ch->b.pocket_id, prev_pos, ch->b.pos, &warped);
        if (crossed) {
            warp_body_across_portal(ch, portals, scene, crossed, prev_pos, warped);
            ch->world_aabb = compute_body_aabb(&ch->b);
        }
    }

    if (out_grounded) *out_grounded = grounded;
    return true;
}

eng_vec3_t eng_physics_slide_xz(const eng_physics_t *phys, uint16_t pocket_id,
                                eng_vec3_t pos, float dx, float dz, float radius) {
    eng_vec3_t out = eng_v3(pos.x + dx, pos.y, pos.z + dz);
    if (!phys) return out;
    eng_body_desc_t probe = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_KINEMATIC);
    probe.pocket_id = pocket_id;
    probe.radius = (radius > 0.05f) ? radius : 0.38f;
    probe.pos = pos;
    float dist = sqrtf(dx * dx + dz * dz);
    int steps = (dist > probe.radius * 0.5f) ? (int)ceilf(dist / (probe.radius * 0.5f)) : 1;
    if (steps > 16) steps = 16;
    float sdx = dx / (float)steps, sdz = dz / (float)steps;
    for (int st = 0; st < steps; st++) {
        probe.pos.x += sdx;
        probe.pos.z += sdz;
        for (int iter = 0; iter < 3; iter++) {
            bool hit_any = false;
            eng_aabb_t pbox = compute_body_aabb(&probe);
            for (uint32_t j = 0; j < phys->body_high; j++) {
                const body_slot_t *sb = &phys->bodies[j];
                if (!sb->active || sb->b.pocket_id != pocket_id || sb->b.is_trigger || sb->b.motion != ENG_BODY_STATIC) continue;
                eng_vec3_t n = {0, 1, 0};
                float pen = 0.0f;
                if (!test_pair(&probe, pbox, &sb->b, sb->world_aabb, &n, &pen)) continue;
                if (fabsf(n.y) > 0.65f) continue; /* ignore floors/ceilings */
                float nlen = sqrtf(n.x * n.x + n.z * n.z);
                if (nlen > 1e-4f) {
                    probe.pos.x -= (n.x / nlen) * pen;
                    probe.pos.z -= (n.z / nlen) * pen;
                    pbox = compute_body_aabb(&probe);
                    hit_any = true;
                }
            }
            if (!hit_any) break;
        }
    }
    return eng_v3(probe.pos.x, pos.y, probe.pos.z);
}

static bool ray_vs_sphere(eng_vec3_t o, eng_vec3_t d, eng_vec3_t c, float r, float max_d, float *out_t, eng_vec3_t *out_n) {
    eng_vec3_t oc = eng_v3_sub(o, c);
    float b = eng_v3_dot(oc, d);
    float ct = eng_v3_dot(oc, oc) - r * r;
    float disc = b * b - ct;
    if (disc < 0.0f) return false;
    float t = -b - sqrtf(disc);
    if (t < 0.0f) t = -b + sqrtf(disc);
    if (t < 0.0f || t > max_d) return false;
    *out_t = t;
    *out_n = eng_v3_norm(eng_v3_sub(eng_v3_add(o, eng_v3_scale(d, t)), c));
    return true;
}

eng_raycast_hit_t eng_physics_raycast(const eng_physics_t *phys, const eng_scene_t *scene,
                                      const eng_portal_sys_t *portals, uint16_t start_pocket,
                                      eng_vec3_t origin, eng_vec3_t dir, float max_dist) {
    eng_raycast_hit_t res;
    memset(&res, 0, sizeof(res));
    if (!phys || max_dist <= 0.0f) return res;

    eng_vec3_t cur_o = origin;
    eng_vec3_t cur_d = eng_v3_norm(dir);
    if (eng_v3_dot(cur_d, cur_d) < 0.5f) return res;
    uint16_t cur_pocket = start_pocket;
    float rem_dist = max_dist;
    float accum_dist = 0.0f;

    for (uint32_t hop = 0; hop <= 4u && rem_dist > 1e-4f; hop++) {
        float best_body_t = rem_dist + 1.0f;
        uint32_t best_id = 0;
        eng_vec3_t best_n = {0, 1, 0};

        for (uint32_t i = 0; i < phys->body_high; i++) {
            const body_slot_t *s = &phys->bodies[i];
            if (!s->active || s->b.pocket_id != cur_pocket) continue;
            float t_box = 0.0f;
            if (!eng_aabb_ray_hit(s->world_aabb, cur_o, cur_d, rem_dist, &t_box)) continue;

            float t = t_box;
            eng_vec3_t n = {0, 1, 0};
            if (s->b.shape == ENG_SHAPE_SPHERE) {
                if (!ray_vs_sphere(cur_o, cur_d, s->b.pos, s->b.radius, rem_dist, &t, &n)) continue;
            } else if (s->b.shape == ENG_SHAPE_VOXEL_CHUNK && s->b.voxel_chunk) {
                eng_voxel_hit_t vh = eng_voxel_raycast(s->b.voxel_chunk, eng_v3_sub(cur_o, s->b.pos), cur_d, rem_dist);
                if (!vh.hit) continue;
                t = vh.dist;
                n = eng_v3((float)vh.nx, (float)vh.ny, (float)vh.nz);
            } else {
                /* Compute exact AABB face normal at hit point */
                eng_vec3_t hp = eng_v3_add(cur_o, eng_v3_scale(cur_d, t));
                eng_vec3_t c = eng_v3_scale(eng_v3_add(s->world_aabb.min, s->world_aabb.max), 0.5f);
                eng_vec3_t he = eng_v3_scale(eng_v3_sub(s->world_aabb.max, s->world_aabb.min), 0.5f);
                eng_vec3_t drel = eng_v3(
                    (hp.x - c.x) / fmaxf(he.x, 1e-4f),
                    (hp.y - c.y) / fmaxf(he.y, 1e-4f),
                    (hp.z - c.z) / fmaxf(he.z, 1e-4f)
                );
                if (fabsf(drel.x) >= fabsf(drel.y) && fabsf(drel.x) >= fabsf(drel.z)) n = eng_v3(drel.x > 0 ? 1.0f : -1.0f, 0, 0);
                else if (fabsf(drel.y) >= fabsf(drel.z)) n = eng_v3(0, drel.y > 0 ? 1.0f : -1.0f, 0);
                else n = eng_v3(0, 0, drel.z > 0 ? 1.0f : -1.0f);
            }

            if (t < best_body_t) {
                best_body_t = t;
                best_id = i + 1u;
                best_n = n;
            }
        }

        /* Check if ray enters an open portal quad BEFORE hitting best_body_t */
        const eng_portal_t *hit_portal = NULL;
        float best_portal_t = best_body_t;
        if (portals && scene && hop < 4u) {
            size_t pc = eng_portal_count(portals);
            for (size_t pi = 0; pi < pc; pi++) {
                const eng_portal_t *p = eng_portal_get(portals, pi);
                const eng_mat4_t *m_src = p ? eng_scene_get_world_matrix(scene, p->src_ent) : NULL;
                eng_mat4_t inv_src;
                if (!p || p->src_pocket != cur_pocket || !m_src || !eng_mat4_invert(m_src, &inv_src)) continue;

                eng_vec3_t lo = eng_mat4_transform_point(&inv_src, cur_o);
                eng_vec3_t ld = eng_v3(
                    inv_src.m[0] * cur_d.x + inv_src.m[4] * cur_d.y + inv_src.m[8]  * cur_d.z,
                    inv_src.m[1] * cur_d.x + inv_src.m[5] * cur_d.y + inv_src.m[9]  * cur_d.z,
                    inv_src.m[2] * cur_d.x + inv_src.m[6] * cur_d.y + inv_src.m[10] * cur_d.z
                );
                if (lo.z > 1e-4f && ld.z < -1e-5f) {
                    float tp = -lo.z / ld.z;
                    if (tp > 0.0f && tp < best_portal_t && tp <= rem_dist) {
                        float hx = lo.x + ld.x * tp;
                        float hy = lo.y + ld.y * tp;
                        if (fabsf(hx) <= p->half_w && fabsf(hy) <= p->half_h) {
                            best_portal_t = tp;
                            hit_portal = p;
                        }
                    }
                }
            }
        }

        if (best_id != 0 && !hit_portal) {
            res.hit = true;
            res.body_id = best_id;
            res.entity = phys->bodies[best_id - 1u].b.entity;
            res.pocket_id = cur_pocket;
            res.point = eng_v3_add(cur_o, eng_v3_scale(cur_d, best_body_t));
            res.normal = best_n;
            res.distance = accum_dist + best_body_t;
            res.portal_hops = hop;
            return res;
        }
        if (!hit_portal) break;

        eng_mat4_t warp;
        if (!eng_portal_warp_matrix(scene, hit_portal, &warp)) break;
        eng_vec3_t entry_pt = eng_v3_add(cur_o, eng_v3_scale(cur_d, best_portal_t + 1e-3f));
        eng_vec3_t d = cur_d;
        cur_o = eng_mat4_transform_point(&warp, entry_pt);
        cur_d = eng_v3_norm(eng_v3(
            warp.m[0] * d.x + warp.m[4] * d.y + warp.m[8]  * d.z,
            warp.m[1] * d.x + warp.m[5] * d.y + warp.m[9]  * d.z,
            warp.m[2] * d.x + warp.m[6] * d.y + warp.m[10] * d.z
        ));
        rem_dist = (rem_dist - best_portal_t) * hit_portal->scale_ratio;
        accum_dist += best_portal_t;
        cur_pocket = hit_portal->dst_pocket;
    }
    return res;
}

size_t eng_physics_contact_count(const eng_physics_t *phys) {
    return phys ? phys->contact_count : 0;
}

const eng_contact_event_t *eng_physics_contact_get(const eng_physics_t *phys, size_t index) {
    return (phys && index < phys->contact_count) ? &phys->contacts[index] : NULL;
}
