#include "engine/eng_physics.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_BODIES 1024
#define ENG_MAX_POCKET_GRAV 32
#define ENG_MAX_CONTACTS 512
#define ENG_MAX_JOINTS 256

typedef struct {
    bool active;
    eng_body_desc_t b;
    float inv_mass;
    float volume;
    eng_vec3_t inv_inertia_local;
    float sleep_timer;
    eng_aabb_t world_aabb;
} body_slot_t;

typedef struct {
    bool radial;
    eng_vec3_t linear;
    eng_vec3_t center;
    float surface_g;
    bool has_planet_cfg;
    eng_planet_cfg_t planet_cfg;

    bool fluid_enabled;
    float fluid_level_y;
    float fluid_density;
    float fluid_drag;
    eng_vec2_t fluid_flow;
    eng_vec3_t wind_vel;
} pocket_grav_t;

typedef struct {
    bool active;
    eng_joint_desc_t d;
    eng_vec3_t local_axis_b;
} joint_slot_t;

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
    joint_slot_t joints[ENG_MAX_JOINTS];
    uint32_t joint_high;
    eng_fluid_height_fn fluid_fn;
    void *fluid_ud;
    eng_contact_event_t contacts[ENG_MAX_CONTACTS];
    size_t contact_count;
};

static eng_quat_t quat_conj(eng_quat_t q) {
    return (eng_quat_t){-q.x, -q.y, -q.z, q.w};
}

static eng_vec3_t body_com(const eng_body_desc_t *b) {
    if (b->shape == ENG_SHAPE_VOXEL_CHUNK && b->voxel_chunk) {
        float vs = b->voxel_chunk->voxel_size;
        eng_vec3_t half = eng_v3(0.5f * (float)b->voxel_chunk->sx * vs,
                                 0.5f * (float)b->voxel_chunk->sy * vs,
                                 0.5f * (float)b->voxel_chunk->sz * vs);
        return eng_v3_add(b->pos, eng_quat_rotate_v3(b->rot, half));
    }
    return b->pos;
}

static eng_vec3_t apply_world_inv_inertia(const body_slot_t *s, eng_vec3_t tau_world) {
    if (s->b.freeze_rotation || s->inv_mass <= 0.0f) return eng_v3(0, 0, 0);
    eng_vec3_t local_t = eng_quat_rotate_v3(quat_conj(s->b.rot), tau_world);
    eng_vec3_t local_w = eng_v3(local_t.x * s->inv_inertia_local.x,
                                local_t.y * s->inv_inertia_local.y,
                                local_t.z * s->inv_inertia_local.z);
    return eng_quat_rotate_v3(s->b.rot, local_w);
}

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
        .half_extents = {0.5f, 0.5f, 0.5f},
        .density = 0.0f,
        .linear_damping = 0.0f,
        .angular_damping = 0.08f,
        .freeze_rotation = (shape == ENG_SHAPE_CAPSULE),
        .sleeping = false
    };
}

eng_joint_desc_t eng_joint_default_desc(eng_joint_type_t type, uint32_t body_a, uint32_t body_b) {
    return (eng_joint_desc_t){
        .type = type,
        .body_a = body_a,
        .body_b = body_b,
        .anchor_a = {0, 0, 0},
        .anchor_b = {0, 0, 0},
        .axis_a = {0, 1, 0},
        .rest_length = -1.0f,
        .stiffness = 120.0f,
        .damping = 8.0f,
        .break_force = 0.0f
    };
}

eng_physics_t *eng_physics_create(void) {
    eng_physics_t *p = (eng_physics_t *)calloc(1, sizeof(eng_physics_t));
    if (!p) return NULL;
    for (int i = 0; i < ENG_MAX_POCKET_GRAV; i++) {
        p->grav[i].linear = eng_v3(0.0f, -9.81f, 0.0f);
        p->grav[i].fluid_density = 1000.0f;
        p->grav[i].fluid_drag = 1.6f;
    }
    return p;
}

void eng_physics_destroy(eng_physics_t *phys) {
    free(phys);
}

static void wake_pocket_bodies(eng_physics_t *phys, uint16_t pocket_id) {
    for (uint32_t i = 0; i < phys->body_high; i++) {
        if (phys->bodies[i].active && phys->bodies[i].b.pocket_id == pocket_id) {
            phys->bodies[i].b.sleeping = false;
            phys->bodies[i].sleep_timer = 0.0f;
        }
    }
}

void eng_physics_set_gravity(eng_physics_t *phys, uint16_t pocket_id, eng_vec3_t linear_gravity) {
    if (!phys || pocket_id >= ENG_MAX_POCKET_GRAV) return;
    phys->grav[pocket_id].radial = false;
    phys->grav[pocket_id].linear = linear_gravity;
    wake_pocket_bodies(phys, pocket_id);
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
    wake_pocket_bodies(phys, pocket_id);
}

void eng_physics_set_fluid(eng_physics_t *phys, uint16_t pocket_id, bool enabled,
                           float level_y, float fluid_density, float drag_coeff,
                           eng_vec2_t flow_xz) {
    if (!phys || pocket_id >= ENG_MAX_POCKET_GRAV) return;
    pocket_grav_t *g = &phys->grav[pocket_id];
    g->fluid_enabled = enabled;
    g->fluid_level_y = level_y;
    g->fluid_density = fluid_density > 1.0f ? fluid_density : 1000.0f;
    g->fluid_drag = drag_coeff >= 0.0f ? drag_coeff : 1.5f;
    g->fluid_flow = flow_xz;
    wake_pocket_bodies(phys, pocket_id);
}

void eng_physics_set_fluid_sampler(eng_physics_t *phys, eng_fluid_height_fn fn, void *user_data) {
    if (!phys) return;
    phys->fluid_fn = fn;
    phys->fluid_ud = user_data;
}

void eng_physics_set_wind(eng_physics_t *phys, uint16_t pocket_id, eng_vec3_t wind_vel) {
    if (!phys || pocket_id >= ENG_MAX_POCKET_GRAV) return;
    phys->grav[pocket_id].wind_vel = wind_vel;
    if (eng_v3_dot(wind_vel, wind_vel) > 1e-4f) wake_pocket_bodies(phys, pocket_id);
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
            if (fabsf(b->rot.w) < 0.9999f) {
                eng_aabb_t box = {eng_v3(FLT_MAX, FLT_MAX, FLT_MAX), eng_v3(-FLT_MAX, -FLT_MAX, -FLT_MAX)};
                for (int k = 0; k < 8; k++) {
                    eng_vec3_t lc = eng_v3((k & 1) ? sz.x : 0.0f, (k & 2) ? sz.y : 0.0f, (k & 4) ? sz.z : 0.0f);
                    eng_vec3_t wp = eng_v3_add(b->pos, eng_quat_rotate_v3(b->rot, lc));
                    box.min = eng_v3(fminf(box.min.x, wp.x), fminf(box.min.y, wp.y), fminf(box.min.z, wp.z));
                    box.max = eng_v3(fmaxf(box.max.x, wp.x), fmaxf(box.max.y, wp.y), fmaxf(box.max.z, wp.z));
                }
                return box;
            }
            return (eng_aabb_t){b->pos, eng_v3_add(b->pos, sz)};
        }
        case ENG_SHAPE_TERRAIN: {
            if (!b->terrain) return (eng_aabb_t){b->pos, b->pos};
            float wx = (float)(b->terrain->grid_w - 1) * b->terrain->cell_size;
            float wz = (float)(b->terrain->grid_d - 1) * b->terrain->cell_size;
            return (eng_aabb_t){eng_v3(b->pos.x, -500.0f, b->pos.z), eng_v3(b->pos.x + wx, 500.0f, b->pos.z + wz)};
        }
        default: { /* ENG_SHAPE_AABB (supports rotated OBB bounds when rot != identity) */
            if (fabsf(b->rot.w) < 0.9999f) {
                eng_vec3_t ax = eng_quat_rotate_v3(b->rot, eng_v3(b->half_extents.x, 0, 0));
                eng_vec3_t ay = eng_quat_rotate_v3(b->rot, eng_v3(0, b->half_extents.y, 0));
                eng_vec3_t az = eng_quat_rotate_v3(b->rot, eng_v3(0, 0, b->half_extents.z));
                eng_vec3_t ex = eng_v3(fabsf(ax.x) + fabsf(ay.x) + fabsf(az.x),
                                       fabsf(ax.y) + fabsf(ay.y) + fabsf(az.y),
                                       fabsf(ax.z) + fabsf(ay.z) + fabsf(az.z));
                return (eng_aabb_t){eng_v3_sub(b->pos, ex), eng_v3_add(b->pos, ex)};
            }
            return (eng_aabb_t){eng_v3_sub(b->pos, b->half_extents), eng_v3_add(b->pos, b->half_extents)};
        }
    }
}

static void init_body_mass_and_inertia(body_slot_t *s) {
    const eng_body_desc_t *b = &s->b;
    float vol = 1.0f;
    eng_vec3_t he = b->half_extents;
    switch (b->shape) {
        case ENG_SHAPE_SPHERE:
            vol = (4.0f / 3.0f) * ENG_PI * b->radius * b->radius * b->radius;
            break;
        case ENG_SHAPE_CAPSULE:
            vol = (4.0f / 3.0f) * ENG_PI * b->radius * b->radius * b->radius
                  + 2.0f * ENG_PI * b->radius * b->radius * b->half_height;
            break;
        case ENG_SHAPE_VOXEL_CHUNK:
            if (b->voxel_chunk) {
                float vs = b->voxel_chunk->voxel_size;
                size_t filled = 0;
                int total = b->voxel_chunk->sx * b->voxel_chunk->sy * b->voxel_chunk->sz;
                for (int k = 0; k < total; k++) if (b->voxel_chunk->blocks[k] != 0) filled++;
                vol = fmaxf((float)filled * vs * vs * vs, vs * vs * vs);
                he = eng_v3(0.5f * (float)b->voxel_chunk->sx * vs,
                            0.5f * (float)b->voxel_chunk->sy * vs,
                            0.5f * (float)b->voxel_chunk->sz * vs);
            }
            break;
        case ENG_SHAPE_CONVEX_HULL: {
            eng_aabb_t ab = compute_body_aabb(b);
            he = eng_v3_scale(eng_v3_sub(ab.max, ab.min), 0.5f);
            vol = fmaxf(4.0f * he.x * he.y * he.z, 0.02f);
            break;
        }
        default:
            vol = fmaxf(8.0f * he.x * he.y * he.z, 0.001f);
            break;
    }
    s->volume = fmaxf(vol, 0.001f);
    if (s->b.motion == ENG_BODY_DYNAMIC) {
        if (s->b.density > 0.0f) s->b.mass = fmaxf(s->b.density * s->volume, 0.01f);
        s->inv_mass = (s->b.mass > 1e-4f) ? (1.0f / s->b.mass) : 0.0f;
    } else {
        s->inv_mass = 0.0f;
    }

    if (s->inv_mass <= 0.0f || s->b.freeze_rotation) {
        s->inv_inertia_local = eng_v3(0, 0, 0);
        return;
    }

    float m = s->b.mass;
    float ix, iy, iz;
    if (b->shape == ENG_SHAPE_SPHERE) {
        ix = iy = iz = 0.4f * m * fmaxf(b->radius * b->radius, 0.01f);
    } else if (b->shape == ENG_SHAPE_CAPSULE) {
        float hh = b->half_height + b->radius;
        iy = 0.5f * m * fmaxf(b->radius * b->radius, 0.01f);
        ix = iz = (1.0f / 3.0f) * m * fmaxf(hh * hh, 0.01f);
    } else {
        float ex2 = fmaxf(he.x * he.x, 0.01f);
        float ey2 = fmaxf(he.y * he.y, 0.01f);
        float ez2 = fmaxf(he.z * he.z, 0.01f);
        ix = (1.0f / 3.0f) * m * (ey2 + ez2);
        iy = (1.0f / 3.0f) * m * (ex2 + ez2);
        iz = (1.0f / 3.0f) * m * (ex2 + ey2);
    }
    s->inv_inertia_local = eng_v3(1.0f / ix, 1.0f / iy, 1.0f / iz);
}

uint32_t eng_physics_add_body(eng_physics_t *phys, const eng_body_desc_t *desc) {
    if (!phys || !desc) return 0;
    for (uint32_t i = 0; i < ENG_MAX_BODIES; i++) {
        if (!phys->bodies[i].active) {
            body_slot_t *s = &phys->bodies[i];
            memset(s, 0, sizeof(*s));
            s->active = true;
            s->b = *desc;
            if (eng_v3_dot(eng_v3(s->b.rot.x, s->b.rot.y, s->b.rot.z),
                           eng_v3(s->b.rot.x, s->b.rot.y, s->b.rot.z)) + s->b.rot.w * s->b.rot.w < 1e-6f) {
                s->b.rot = eng_quat_identity();
            } else {
                s->b.rot = eng_quat_norm(s->b.rot);
            }
            init_body_mass_and_inertia(s);
            s->world_aabb = compute_body_aabb(&s->b);
            if (i + 1u > phys->body_high) phys->body_high = i + 1u;
            return i + 1u;
        }
    }
    return 0;
}

bool eng_physics_remove_body(eng_physics_t *phys, uint32_t body_id) {
    if (!phys || body_id == 0 || body_id > ENG_MAX_BODIES || !phys->bodies[body_id - 1u].active) return false;
    for (uint32_t j = 0; j < phys->joint_high; j++) {
        if (phys->joints[j].active && (phys->joints[j].d.body_a == body_id || phys->joints[j].d.body_b == body_id)) {
            phys->joints[j].active = false;
        }
    }
    memset(&phys->bodies[body_id - 1u], 0, sizeof(body_slot_t));
    return true;
}

eng_body_desc_t *eng_physics_get_body(eng_physics_t *phys, uint32_t body_id) {
    if (!phys || body_id == 0 || body_id > ENG_MAX_BODIES || !phys->bodies[body_id - 1u].active) return NULL;
    return &phys->bodies[body_id - 1u].b;
}

void eng_physics_wake_body(eng_physics_t *phys, uint32_t body_id) {
    if (!phys || body_id == 0 || body_id > ENG_MAX_BODIES || !phys->bodies[body_id - 1u].active) return;
    phys->bodies[body_id - 1u].b.sleeping = false;
    phys->bodies[body_id - 1u].sleep_timer = 0.0f;
}

bool eng_physics_apply_impulse_at(eng_physics_t *phys, uint32_t body_id,
                                  eng_vec3_t impulse, eng_vec3_t world_point) {
    if (!phys || body_id == 0 || body_id > ENG_MAX_BODIES || !phys->bodies[body_id - 1u].active) return false;
    body_slot_t *s = &phys->bodies[body_id - 1u];
    if (s->inv_mass <= 0.0f) return false;
    s->b.sleeping = false;
    s->sleep_timer = 0.0f;
    s->b.vel = eng_v3_add(s->b.vel, eng_v3_scale(impulse, s->inv_mass));
    if (!s->b.freeze_rotation) {
        eng_vec3_t r = eng_v3_sub(world_point, body_com(&s->b));
        eng_vec3_t dw = apply_world_inv_inertia(s, eng_v3_cross(r, impulse));
        s->b.ang_vel = eng_v3_add(s->b.ang_vel, dw);
    }
    return true;
}

size_t eng_physics_radial_blast(eng_physics_t *phys, uint16_t pocket_id,
                                eng_vec3_t center, float radius, float max_impulse) {
    if (!phys || radius <= 0.01f || fabsf(max_impulse) < 1e-5f) return 0;
    size_t hit = 0;
    for (uint32_t i = 0; i < phys->body_high; i++) {
        body_slot_t *s = &phys->bodies[i];
        if (!s->active || s->b.pocket_id != pocket_id || s->inv_mass <= 0.0f) continue;
        eng_vec3_t com = body_com(&s->b);
        eng_vec3_t delta = eng_v3_sub(com, center);
        float d = eng_v3_len(delta);
        if (d > radius) continue;
        eng_vec3_t dir = (d > 1e-4f) ? eng_v3_scale(delta, 1.0f / d) : eng_v3(0.0f, 1.0f, 0.0f);
        float falloff = (1.0f - d / radius);
        falloff *= falloff;
        eng_vec3_t imp = eng_v3_scale(dir, max_impulse * falloff);
        /* Apply slightly below/offset from COM so shockwaves impart natural tumble */
        eng_vec3_t app = eng_v3_sub(com, eng_v3(dir.z * 0.12f, 0.12f, -dir.x * 0.12f));
        eng_physics_apply_impulse_at(phys, i + 1u, imp, app);
        hit++;
    }
    return hit;
}

static eng_vec3_t joint_world_anchor(const eng_physics_t *phys, uint32_t body_id, eng_vec3_t local_anchor) {
    if (body_id == 0 || body_id > ENG_MAX_BODIES || !phys->bodies[body_id - 1u].active) return local_anchor;
    const eng_body_desc_t *b = &phys->bodies[body_id - 1u].b;
    return eng_v3_add(b->pos, eng_quat_rotate_v3(b->rot, local_anchor));
}

uint32_t eng_physics_add_joint(eng_physics_t *phys, const eng_joint_desc_t *desc) {
    if (!phys || !desc || desc->body_b == 0 || desc->body_b > ENG_MAX_BODIES || !phys->bodies[desc->body_b - 1u].active) return 0;
    if (desc->body_a > ENG_MAX_BODIES || (desc->body_a > 0 && !phys->bodies[desc->body_a - 1u].active)) return 0;

    for (uint32_t i = 0; i < ENG_MAX_JOINTS; i++) {
        if (!phys->joints[i].active) {
            joint_slot_t *j = &phys->joints[i];
            j->active = true;
            j->d = *desc;
            if (eng_v3_dot(j->d.axis_a, j->d.axis_a) < 1e-4f) j->d.axis_a = eng_v3(0, 1, 0);
            j->d.axis_a = eng_v3_norm(j->d.axis_a);

            eng_vec3_t world_axis = (j->d.body_a > 0)
                                        ? eng_quat_rotate_v3(phys->bodies[j->d.body_a - 1u].b.rot, j->d.axis_a)
                                        : j->d.axis_a;
            j->local_axis_b = eng_quat_rotate_v3(quat_conj(phys->bodies[j->d.body_b - 1u].b.rot), world_axis);

            if (j->d.rest_length < 0.0f) {
                eng_vec3_t pa = joint_world_anchor(phys, j->d.body_a, j->d.anchor_a);
                eng_vec3_t pb = joint_world_anchor(phys, j->d.body_b, j->d.anchor_b);
                j->d.rest_length = eng_v3_len(eng_v3_sub(pb, pa));
            }
            if (j->d.type == ENG_JOINT_BALL || j->d.type == ENG_JOINT_HINGE) j->d.rest_length = 0.0f;
            if (i + 1u > phys->joint_high) phys->joint_high = i + 1u;
            return i + 1u;
        }
    }
    return 0;
}

bool eng_physics_remove_joint(eng_physics_t *phys, uint32_t joint_id) {
    if (!phys || joint_id == 0 || joint_id > ENG_MAX_JOINTS || !phys->joints[joint_id - 1u].active) return false;
    phys->joints[joint_id - 1u].active = false;
    return true;
}

bool eng_physics_joint_is_active(const eng_physics_t *phys, uint32_t joint_id) {
    return (phys && joint_id > 0 && joint_id <= ENG_MAX_JOINTS && phys->joints[joint_id - 1u].active);
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
                /* Origin enclosed inside tetrahedron -> find exact minimum-penetration MTV across candidate axes */
                eng_vec3_t cands[11] = {
                    {1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1},
                    eng_v3_norm(eng_v3_sub(cb, ca)),
                    eng_v3_norm(abc), eng_v3_norm(eng_v3_scale(abc, -1.0f)),
                    eng_v3_norm(acd), eng_v3_norm(adb)
                };
                float best_pen = FLT_MAX;
                eng_vec3_t best_n = eng_v3(0.0f, -1.0f, 0.0f);
                for (int ci = 0; ci < 11; ci++) {
                    eng_vec3_t u = cands[ci];
                    if (eng_v3_dot(u, u) < 0.5f) continue;
                    eng_vec3_t p = minkowski_sup(va, na, vb, nb, u);
                    float pen = eng_v3_dot(p, u);
                    if (pen > 0.0f && pen < best_pen) {
                        best_pen = pen;
                        best_n = u;
                    }
                }
                if (best_pen == FLT_MAX) best_pen = 0.01f;
                if (out_sep_dir) *out_sep_dir = best_n;
                if (out_depth) *out_depth = best_pen;
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
    if (b->shape == ENG_SHAPE_AABB && fabsf(b->rot.w) < 0.9999f) {
        eng_vec3_t he = b->half_extents;
        for (int k = 0; k < 8; k++) {
            eng_vec3_t lc = eng_v3((k & 1) ? he.x : -he.x, (k & 2) ? he.y : -he.y, (k & 4) ? he.z : -he.z);
            out_v[k] = eng_v3_add(b->pos, eng_quat_rotate_v3(b->rot, lc));
        }
        return 8;
    }
    if (b->shape == ENG_SHAPE_VOXEL_CHUNK && b->voxel_chunk && fabsf(b->rot.w) < 0.9999f) {
        float vs = b->voxel_chunk->voxel_size;
        eng_vec3_t sz = eng_v3((float)b->voxel_chunk->sx * vs, (float)b->voxel_chunk->sy * vs, (float)b->voxel_chunk->sz * vs);
        for (int k = 0; k < 8; k++) {
            eng_vec3_t lc = eng_v3((k & 1) ? sz.x : 0.0f, (k & 2) ? sz.y : 0.0f, (k & 4) ? sz.z : 0.0f);
            out_v[k] = eng_v3_add(b->pos, eng_quat_rotate_v3(b->rot, lc));
        }
        return 8;
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

    /* Voxel chunk narrowphase (when static/unrotated) */
    if (b->shape == ENG_SHAPE_VOXEL_CHUNK && b->voxel_chunk && fabsf(b->rot.w) >= 0.9999f &&
        a->shape != ENG_SHAPE_VOXEL_CHUNK) {
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
                    eng_vec3_t pa = body_com(a);
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
    if (a->shape == ENG_SHAPE_VOXEL_CHUNK && fabsf(a->rot.w) >= 0.9999f && b->shape != ENG_SHAPE_VOXEL_CHUNK) {
        if (test_pair(b, box_b, a, box_a, out_n, out_pen)) {
            *out_n = eng_v3_scale(*out_n, -1.0f);
            return true;
        }
        return false;
    }

    /* Convex Hull or Rotated OBB/Voxel GJK */
    bool a_obb = ((a->shape == ENG_SHAPE_AABB || a->shape == ENG_SHAPE_VOXEL_CHUNK) && fabsf(a->rot.w) < 0.9999f);
    bool b_obb = ((b->shape == ENG_SHAPE_AABB || b->shape == ENG_SHAPE_VOXEL_CHUNK) && fabsf(b->rot.w) < 0.9999f);
    if (a->shape == ENG_SHAPE_CONVEX_HULL || b->shape == ENG_SHAPE_CONVEX_HULL || a_obb || b_obb ||
        (a->shape == ENG_SHAPE_VOXEL_CHUNK && b->shape == ENG_SHAPE_VOXEL_CHUNK)) {
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

/* Average support face/edge/corner point in direction dir so flat resting contacts produce zero phantom torque */
static eng_vec3_t support_contact_point(const eng_body_desc_t *b, eng_vec3_t dir) {
    if (b->shape == ENG_SHAPE_SPHERE) {
        return eng_v3_add(b->pos, eng_v3_scale(dir, b->radius));
    }
    if (b->shape == ENG_SHAPE_CAPSULE) {
        eng_vec3_t up = eng_quat_rotate_v3(b->rot, eng_v3(0.0f, b->half_height, 0.0f));
        eng_vec3_t end = (eng_v3_dot(up, dir) >= 0.0f) ? eng_v3_add(b->pos, up) : eng_v3_sub(b->pos, up);
        return eng_v3_add(end, eng_v3_scale(dir, b->radius));
    }
    eng_vec3_t v[16];
    size_t n = body_world_hull(b, v);
    float best = -FLT_MAX;
    for (size_t i = 0; i < n; i++) {
        float d = eng_v3_dot(v[i], dir);
        if (d > best) best = d;
    }
    eng_vec3_t sum = {0, 0, 0};
    int cnt = 0;
    for (size_t i = 0; i < n; i++) {
        if (eng_v3_dot(v[i], dir) >= best - 0.03f) {
            sum = eng_v3_add(sum, v[i]);
            cnt++;
        }
    }
    return cnt > 0 ? eng_v3_scale(sum, 1.0f / (float)cnt) : b->pos;
}

static eng_vec3_t estimate_contact_point(const body_slot_t *sa, const body_slot_t *sb, eng_vec3_t n) {
    if (sa->inv_mass > 0.0f && sb->inv_mass <= 0.0f) {
        return support_contact_point(&sa->b, n);
    }
    if (sb->inv_mass > 0.0f && sa->inv_mass <= 0.0f) {
        return support_contact_point(&sb->b, eng_v3_scale(n, -1.0f));
    }
    eng_vec3_t pa = support_contact_point(&sa->b, n);
    eng_vec3_t pb = support_contact_point(&sb->b, eng_v3_scale(n, -1.0f));
    return eng_v3_scale(eng_v3_add(pa, pb), 0.5f);
}

static float effective_inv_mass(const body_slot_t *sa, const body_slot_t *sb,
                                eng_vec3_t ra, eng_vec3_t rb, eng_vec3_t dir) {
    float k = sa->inv_mass + sb->inv_mass;
    if (!sa->b.freeze_rotation && sa->inv_mass > 0.0f) {
        eng_vec3_t rax = eng_v3_cross(ra, dir);
        k += eng_v3_dot(rax, apply_world_inv_inertia(sa, rax));
    }
    if (!sb->b.freeze_rotation && sb->inv_mass > 0.0f) {
        eng_vec3_t rbx = eng_v3_cross(rb, dir);
        k += eng_v3_dot(rbx, apply_world_inv_inertia(sb, rbx));
    }
    return k;
}

static void resolve_impulse(body_slot_t *sa, body_slot_t *sb, eng_vec3_t n, float pen) {
    float inv_sum = sa->inv_mass + sb->inv_mass;
    if (inv_sum <= 0.0f) return;
    if (sa->b.sleeping && sb->b.sleeping) return;
    if (sa->inv_mass > 0.0f && sa->b.sleeping && (sb->inv_mass > 0.0f && !sb->b.sleeping)) {
        sa->b.sleeping = false; sa->sleep_timer = 0.0f;
    }
    if (sb->inv_mass > 0.0f && sb->b.sleeping && (sa->inv_mass > 0.0f && !sa->b.sleeping)) {
        sb->b.sleeping = false; sb->sleep_timer = 0.0f;
    }

    /* Positional Baumgarte projection */
    float corr = fmaxf(pen - 0.002f, 0.0f) * 0.8f / inv_sum;
    sa->b.pos = eng_v3_sub(sa->b.pos, eng_v3_scale(n, corr * sa->inv_mass));
    sb->b.pos = eng_v3_add(sb->b.pos, eng_v3_scale(n, corr * sb->inv_mass));

    eng_vec3_t cp = estimate_contact_point(sa, sb, n);
    eng_vec3_t ra = eng_v3_sub(cp, body_com(&sa->b));
    eng_vec3_t rb = eng_v3_sub(cp, body_com(&sb->b));

    eng_vec3_t va = eng_v3_add(sa->b.vel, eng_v3_cross(sa->b.ang_vel, ra));
    eng_vec3_t vb = eng_v3_add(sb->b.vel, eng_v3_cross(sb->b.ang_vel, rb));
    eng_vec3_t rv = eng_v3_sub(vb, va);
    float vn = eng_v3_dot(rv, n);
    if (vn > 0.0f) return;

    float e = (vn < -0.22f) ? fminf(sa->b.restitution, sb->b.restitution) : 0.0f;
    float kn = effective_inv_mass(sa, sb, ra, rb, n);
    if (kn <= 1e-8f) return;
    float j = -(1.0f + e) * vn / kn;
    eng_vec3_t imp = eng_v3_scale(n, j);
    sa->b.vel = eng_v3_sub(sa->b.vel, eng_v3_scale(imp, sa->inv_mass));
    sb->b.vel = eng_v3_add(sb->b.vel, eng_v3_scale(imp, sb->inv_mass));
    if (!sa->b.freeze_rotation && sa->inv_mass > 0.0f)
        sa->b.ang_vel = eng_v3_sub(sa->b.ang_vel, apply_world_inv_inertia(sa, eng_v3_cross(ra, imp)));
    if (!sb->b.freeze_rotation && sb->inv_mass > 0.0f)
        sb->b.ang_vel = eng_v3_add(sb->b.ang_vel, apply_world_inv_inertia(sb, eng_v3_cross(rb, imp)));

    /* Coulomb tangential friction + rolling spin coupling */
    va = eng_v3_add(sa->b.vel, eng_v3_cross(sa->b.ang_vel, ra));
    vb = eng_v3_add(sb->b.vel, eng_v3_cross(sb->b.ang_vel, rb));
    rv = eng_v3_sub(vb, va);
    eng_vec3_t tang = eng_v3_sub(rv, eng_v3_scale(n, eng_v3_dot(rv, n)));
    float tlen = eng_v3_len(tang);
    if (tlen > 1e-4f) {
        tang = eng_v3_scale(tang, 1.0f / tlen);
        float kt = effective_inv_mass(sa, sb, ra, rb, tang);
        float jt = -eng_v3_dot(rv, tang) / fmaxf(kt, 1e-6f);
        float mu = sqrtf(fmaxf(0.0f, sa->b.friction * sb->b.friction));
        if (sa->b.shape == ENG_SHAPE_SPHERE && sb->b.shape == ENG_SHAPE_SPHERE) mu *= 0.04f;
        else if (sa->b.restitution > 0.85f || sb->b.restitution > 0.85f) mu *= 0.12f;
        jt = eng_clampf(jt, -j * mu, j * mu);
        eng_vec3_t fimp = eng_v3_scale(tang, jt);
        sa->b.vel = eng_v3_sub(sa->b.vel, eng_v3_scale(fimp, sa->inv_mass));
        sb->b.vel = eng_v3_add(sb->b.vel, eng_v3_scale(fimp, sb->inv_mass));
        if (!sa->b.freeze_rotation && sa->inv_mass > 0.0f)
            sa->b.ang_vel = eng_v3_sub(sa->b.ang_vel, apply_world_inv_inertia(sa, eng_v3_cross(ra, fimp)));
        if (!sb->b.freeze_rotation && sb->inv_mass > 0.0f)
            sb->b.ang_vel = eng_v3_add(sb->b.ang_vel, apply_world_inv_inertia(sb, eng_v3_cross(rb, fimp)));
    }
    /* Rolling resistance (visco-elastic surface deformation opposing pure roll) + GJK OBB settle */
    if (vn > -0.45f) {
        float mu_r = sqrtf(fmaxf(0.0f, sa->b.friction * sb->b.friction)) * 0.55f;
        if (sa->b.shape == ENG_SHAPE_SPHERE && sa->inv_mass > 0.0f && sb->inv_mass <= 0.0f) {
            eng_vec3_t vt = eng_v3_sub(sa->b.vel, eng_v3_scale(n, eng_v3_dot(sa->b.vel, n)));
            float vtl = eng_v3_len(vt);
            if (vtl > 1e-4f) {
                float dv = fminf(vtl, j * mu_r * sa->inv_mass);
                sa->b.vel = eng_v3_sub(sa->b.vel, eng_v3_scale(vt, dv / vtl));
                sa->b.ang_vel = eng_v3_scale(sa->b.ang_vel, (vtl - dv) / vtl);
            }
        } else if (sb->b.shape == ENG_SHAPE_SPHERE && sb->inv_mass > 0.0f && sa->inv_mass <= 0.0f) {
            eng_vec3_t vt = eng_v3_sub(sb->b.vel, eng_v3_scale(n, eng_v3_dot(sb->b.vel, n)));
            float vtl = eng_v3_len(vt);
            if (vtl > 1e-4f) {
                float dv = fminf(vtl, j * mu_r * sb->inv_mass);
                sb->b.vel = eng_v3_sub(sb->b.vel, eng_v3_scale(vt, dv / vtl));
                sb->b.ang_vel = eng_v3_scale(sb->b.ang_vel, (vtl - dv) / vtl);
            }
        }
        /* shortcut: single-point GJK contact without manifold cache, upgrade if multi-contact clipping is added */
        if (!sa->b.freeze_rotation && sa->inv_mass > 0.0f && sa->b.shape != ENG_SHAPE_SPHERE)
            sa->b.ang_vel = eng_v3_scale(sa->b.ang_vel, 0.88f);
        if (!sb->b.freeze_rotation && sb->inv_mass > 0.0f && sb->b.shape != ENG_SHAPE_SPHERE)
            sb->b.ang_vel = eng_v3_scale(sb->b.ang_vel, 0.88f);
    }
}

static float sample_pocket_fluid_y(const eng_physics_t *phys, uint16_t pid, float x, float z) {
    if (phys->fluid_fn) return phys->fluid_fn(x, z, pid, phys->fluid_ud);
    return phys->grav[pid].fluid_level_y;
}

static void apply_fluid_buoyancy(const eng_physics_t *phys, body_slot_t *s, uint16_t pid, float dt) {
    const pocket_grav_t *g = &phys->grav[pid];
    if (!g->fluid_enabled || s->inv_mass <= 0.0f) return;
    float g_mag = g->radial ? g->surface_g : fmaxf(-g->linear.y, 0.0f);
    eng_vec3_t flow = eng_v3(g->fluid_flow.x, 0.0f, g->fluid_flow.y);

    if (s->b.shape == ENG_SHAPE_SPHERE || s->b.shape == ENG_SHAPE_CAPSULE) {
        float wy = sample_pocket_fluid_y(phys, pid, s->b.pos.x, s->b.pos.z);
        float r = fmaxf(s->b.radius, 0.05f);
        float hh = (s->b.shape == ENG_SHAPE_CAPSULE) ? s->b.half_height : 0.0f;
        float bottom = s->b.pos.y - hh - r;
        float height = 2.0f * (hh + r);
        if (wy <= bottom) return;
        float sub_frac = eng_clampf((wy - bottom) / height, 0.0f, 1.0f);
        float v_sub = s->volume * sub_frac;
        if (s->b.shape == ENG_SHAPE_SPHERE) {
            float d = eng_clampf(wy - bottom, 0.0f, 2.0f * r);
            v_sub = (ENG_PI * d * d * (3.0f * r - d)) / 3.0f;
        }
        float fb = g->fluid_density * g_mag * v_sub;
        eng_vec3_t vrel = eng_v3_sub(s->b.vel, flow);
        float spd = eng_v3_len(vrel);
        eng_vec3_t fdrag = eng_v3_scale(vrel, -g->fluid_drag * sub_frac * s->b.mass * (1.2f + 0.5f * spd));
        eng_vec3_t f_tot = eng_v3_add(eng_v3(0.0f, fb, 0.0f), fdrag);
        s->b.vel = eng_v3_add(s->b.vel, eng_v3_scale(f_tot, s->inv_mass * dt));
        s->b.ang_vel = eng_v3_scale(s->b.ang_vel, expf(-2.5f * sub_frac * dt));
        s->b.sleeping = false;
        s->sleep_timer = 0.0f;
        return;
    }

    /* Multi-probe 8-corner Archimedes buoyancy + righting pitch/roll torque + water drag */
    eng_vec3_t corners[16];
    size_t nc = body_world_hull(&s->b, corners);
    if (nc == 0) return;
    eng_vec3_t com = body_com(&s->b);
    float oct_h = fmaxf((s->world_aabb.max.y - s->world_aabb.min.y) * 0.5f, 0.08f);
    float probe_vol = s->volume / (float)nc;
    float total_sub = 0.0f;
    for (size_t k = 0; k < nc; k++) {
        eng_vec3_t rk = eng_v3_scale(eng_v3_sub(corners[k], com), 0.5f);
        eng_vec3_t pk = eng_v3_add(com, rk);
        float oct_bot = pk.y - 0.5f * oct_h;
        float wy = sample_pocket_fluid_y(phys, pid, pk.x, pk.z);
        if (wy <= oct_bot) continue;
        float fk = eng_clampf((wy - oct_bot) / oct_h, 0.0f, 1.0f);
        total_sub += fk / (float)nc;
        eng_vec3_t vk = eng_v3_add(s->b.vel, eng_v3_cross(s->b.ang_vel, rk));
        eng_vec3_t vrel = eng_v3_sub(vk, flow);
        float f_lift = g->fluid_density * g_mag * probe_vol * fk;
        eng_vec3_t f_k = eng_v3_add(eng_v3(0.0f, f_lift, 0.0f),
                                    eng_v3_scale(vrel, -g->fluid_drag * fk * (s->b.mass / (float)nc)));
        eng_vec3_t imp_k = eng_v3_scale(f_k, dt);
        s->b.vel = eng_v3_add(s->b.vel, eng_v3_scale(imp_k, s->inv_mass));
        if (!s->b.freeze_rotation) {
            s->b.ang_vel = eng_v3_add(s->b.ang_vel, apply_world_inv_inertia(s, eng_v3_cross(rk, imp_k)));
        }
    }
    if (total_sub > 0.001f) {
        s->b.ang_vel = eng_v3_scale(s->b.ang_vel, expf(-2.0f * total_sub * dt));
        s->b.sleeping = false;
        s->sleep_timer = 0.0f;
    }
}

static void solve_joints(eng_physics_t *phys, float dt) {
    body_slot_t dummy_world;
    memset(&dummy_world, 0, sizeof(dummy_world));
    dummy_world.b.rot = eng_quat_identity();
    dummy_world.b.freeze_rotation = true;

    for (uint32_t ji = 0; ji < phys->joint_high; ji++) {
        joint_slot_t *js = &phys->joints[ji];
        if (!js->active || js->d.type != ENG_JOINT_SPRING) continue;
        body_slot_t *sa = (js->d.body_a > 0) ? &phys->bodies[js->d.body_a - 1u] : &dummy_world;
        body_slot_t *sb = &phys->bodies[js->d.body_b - 1u];
        if (!sb->active || (js->d.body_a > 0 && !sa->active)) { js->active = false; continue; }

        eng_vec3_t pa = (js->d.body_a > 0) ? eng_v3_add(sa->b.pos, eng_quat_rotate_v3(sa->b.rot, js->d.anchor_a)) : js->d.anchor_a;
        eng_vec3_t pb = eng_v3_add(sb->b.pos, eng_quat_rotate_v3(sb->b.rot, js->d.anchor_b));
        eng_vec3_t dp = eng_v3_sub(pb, pa);
        float len = eng_v3_len(dp);
        eng_vec3_t dir = (len > 1e-5f) ? eng_v3_scale(dp, 1.0f / len) : eng_v3(0, -1, 0);
        eng_vec3_t ra = eng_v3_sub(pa, body_com(&sa->b));
        eng_vec3_t rb = eng_v3_sub(pb, body_com(&sb->b));
        eng_vec3_t va = eng_v3_add(sa->b.vel, eng_v3_cross(sa->b.ang_vel, ra));
        eng_vec3_t vb = eng_v3_add(sb->b.vel, eng_v3_cross(sb->b.ang_vel, rb));
        float f_spring = js->d.stiffness * (len - js->d.rest_length) + js->d.damping * eng_v3_dot(eng_v3_sub(vb, va), dir);
        if (js->d.break_force > 0.0f && fabsf(f_spring) > js->d.break_force) {
            js->active = false;
            if (js->d.body_a > 0) eng_physics_wake_body(phys, js->d.body_a);
            eng_physics_wake_body(phys, js->d.body_b);
            continue;
        }
        eng_vec3_t imp = eng_v3_scale(dir, f_spring * dt);
        if (js->d.body_a > 0 && sa->inv_mass > 0.0f) eng_physics_apply_impulse_at(phys, js->d.body_a, imp, pa);
        if (sb->inv_mass > 0.0f) eng_physics_apply_impulse_at(phys, js->d.body_b, eng_v3_scale(imp, -1.0f), pb);
    }

    /* 6 iterations of Sequential Impulse + positional projection for rigid joints */
    for (int iter = 0; iter < 6; iter++) {
        for (uint32_t ji = 0; ji < phys->joint_high; ji++) {
            joint_slot_t *js = &phys->joints[ji];
            if (!js->active || js->d.type == ENG_JOINT_SPRING) continue;
            body_slot_t *sa = (js->d.body_a > 0) ? &phys->bodies[js->d.body_a - 1u] : &dummy_world;
            body_slot_t *sb = &phys->bodies[js->d.body_b - 1u];
            if (!sb->active || (js->d.body_a > 0 && !sa->active)) { js->active = false; continue; }
            float inv_sum = sa->inv_mass + sb->inv_mass;
            if (inv_sum <= 0.0f) continue;

            eng_vec3_t pa = (js->d.body_a > 0) ? eng_v3_add(sa->b.pos, eng_quat_rotate_v3(sa->b.rot, js->d.anchor_a)) : js->d.anchor_a;
            eng_vec3_t pb = eng_v3_add(sb->b.pos, eng_quat_rotate_v3(sb->b.rot, js->d.anchor_b));
            eng_vec3_t dp = eng_v3_sub(pb, pa);
            float len = eng_v3_len(dp);
            float c_err = len - js->d.rest_length;
            if (fabsf(c_err) > 1e-5f || len > 1e-5f) {
                eng_vec3_t u = (len > 1e-5f) ? eng_v3_scale(dp, 1.0f / len) : eng_v3(0, -1, 0);
                eng_vec3_t ra = eng_v3_sub(pa, body_com(&sa->b));
                eng_vec3_t rb = eng_v3_sub(pb, body_com(&sb->b));
                eng_vec3_t va = eng_v3_add(sa->b.vel, eng_v3_cross(sa->b.ang_vel, ra));
                eng_vec3_t vb = eng_v3_add(sb->b.vel, eng_v3_cross(sb->b.ang_vel, rb));
                float vn = eng_v3_dot(eng_v3_sub(vb, va), u);
                float ku = effective_inv_mass(sa, sb, ra, rb, u);
                float bias = (0.25f / dt) * c_err;
                float lambda = -(vn + bias) / fmaxf(ku, 1e-6f);
                if (iter == 0 && js->d.break_force > 0.0f && (fabsf(lambda) / dt) > js->d.break_force) {
                    js->active = false;
                    if (js->d.body_a > 0) eng_physics_wake_body(phys, js->d.body_a);
                    eng_physics_wake_body(phys, js->d.body_b);
                    continue;
                }
                eng_vec3_t imp = eng_v3_scale(u, lambda);
                sa->b.vel = eng_v3_sub(sa->b.vel, eng_v3_scale(imp, sa->inv_mass));
                sb->b.vel = eng_v3_add(sb->b.vel, eng_v3_scale(imp, sb->inv_mass));
                if (!sa->b.freeze_rotation && sa->inv_mass > 0.0f)
                    sa->b.ang_vel = eng_v3_sub(sa->b.ang_vel, apply_world_inv_inertia(sa, eng_v3_cross(ra, imp)));
                if (!sb->b.freeze_rotation && sb->inv_mass > 0.0f)
                    sb->b.ang_vel = eng_v3_add(sb->b.ang_vel, apply_world_inv_inertia(sb, eng_v3_cross(rb, imp)));
                sa->b.sleeping = false;
                sb->b.sleeping = false;
            }

            if (js->d.type == ENG_JOINT_HINGE) {
                eng_vec3_t ha = (js->d.body_a > 0) ? eng_quat_rotate_v3(sa->b.rot, js->d.axis_a) : js->d.axis_a;
                eng_vec3_t hb = eng_quat_rotate_v3(sb->b.rot, js->local_axis_b);
                eng_vec3_t tilt = eng_v3_cross(hb, ha);
                eng_vec3_t dw = eng_v3_sub(sb->b.ang_vel, sa->b.ang_vel);
                eng_vec3_t dw_perp = eng_v3_sub(dw, eng_v3_scale(ha, eng_v3_dot(dw, ha)));
                eng_vec3_t corr_w = eng_v3_sub(eng_v3_scale(tilt, 4.0f), eng_v3_scale(dw_perp, 0.5f));
                if (!sb->b.freeze_rotation && sb->inv_mass > 0.0f) sb->b.ang_vel = eng_v3_add(sb->b.ang_vel, corr_w);
                if (!sa->b.freeze_rotation && sa->inv_mass > 0.0f) sa->b.ang_vel = eng_v3_sub(sa->b.ang_vel, corr_w);
            }
        }
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
    s->b.sleeping = false;
    s->sleep_timer = 0.0f;
    init_body_mass_and_inertia(s);
}

void eng_physics_step(eng_physics_t *phys, const eng_scene_t *scene,
                      const eng_portal_sys_t *portals, float dt) {
    if (!phys || dt <= 0.0f) return;
    phys->contact_count = 0;

    /* 1. Integrate forces, buoyancy, wind, linear & angular velocities + portal crossing */
    for (uint32_t i = 0; i < phys->body_high; i++) {
        body_slot_t *s = &phys->bodies[i];
        if (!s->active) continue;
        eng_vec3_t prev_pos = s->b.pos;

        if (s->b.motion == ENG_BODY_DYNAMIC) {
            uint16_t pid = s->b.pocket_id < ENG_MAX_POCKET_GRAV ? s->b.pocket_id : 0;
            const pocket_grav_t *g = &phys->grav[pid];
            if (g->fluid_enabled) apply_fluid_buoyancy(phys, s, pid, dt);

            if (!s->b.sleeping) {
                eng_vec3_t acc = g->radial
                                     ? eng_v3_scale(eng_planet_gravity_up(g->center, s->b.pos), -g->surface_g)
                                     : g->linear;
                if (eng_v3_dot(g->wind_vel, g->wind_vel) > 1e-5f) {
                    eng_vec3_t wrel = eng_v3_sub(g->wind_vel, s->b.vel);
                    acc = eng_v3_add(acc, eng_v3_scale(wrel, 0.35f * powf(s->volume, 0.66f) * s->inv_mass));
                }
                s->b.vel = eng_v3_add(s->b.vel, eng_v3_scale(acc, dt));
                if (s->b.linear_damping > 0.0f) {
                    s->b.vel = eng_v3_scale(s->b.vel, expf(-s->b.linear_damping * dt));
                }
                s->b.pos = eng_v3_add(s->b.pos, eng_v3_scale(s->b.vel, dt));

                if (!s->b.freeze_rotation) {
                    if (s->b.angular_damping > 0.0f) {
                        s->b.ang_vel = eng_v3_scale(s->b.ang_vel, expf(-s->b.angular_damping * dt));
                    }
                    float wlen = eng_v3_len(s->b.ang_vel);
                    if (wlen > 1e-6f) {
                        eng_quat_t dq = eng_quat_from_axis_angle(eng_v3_scale(s->b.ang_vel, 1.0f / wlen), wlen * dt);
                        s->b.rot = eng_quat_norm(eng_quat_mul(dq, s->b.rot));
                    }
                } else {
                    s->b.ang_vel = eng_v3(0, 0, 0);
                }

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

    /* 2. Solve joints */
    if (phys->joint_high > 0) {
        solve_joints(phys, dt);
    }

    /* 3. Build per-pocket BVHs and solve contacts + cross-portal ghost proxy contacts */
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

    /* 4. Update sleep timers for settled dynamic bodies */
    for (uint32_t i = 0; i < phys->body_high; i++) {
        body_slot_t *s = &phys->bodies[i];
        if (!s->active || s->b.motion != ENG_BODY_DYNAMIC || s->b.sleeping) continue;
        uint16_t pid = s->b.pocket_id < ENG_MAX_POCKET_GRAV ? s->b.pocket_id : 0;
        if (phys->grav[pid].fluid_enabled) continue;
        float v2 = eng_v3_dot(s->b.vel, s->b.vel);
        float w2 = eng_v3_dot(s->b.ang_vel, s->b.ang_vel);
        if (v2 < 0.015f && w2 < 0.04f) {
            s->sleep_timer += dt;
            if (s->sleep_timer >= 0.45f) {
                s->b.sleeping = true;
                s->b.vel = eng_v3(0, 0, 0);
                s->b.ang_vel = eng_v3(0, 0, 0);
            }
        } else {
            s->sleep_timer = 0.0f;
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
