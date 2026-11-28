#ifndef ENG_PHYSICS_H
#define ENG_PHYSICS_H

#include "eng_ecs.h"
#include "eng_math.h"
#include "eng_portal.h"
#include "eng_procgen.h"
#include "eng_scene.h"
#include "eng_terrain.h"
#include "eng_voxel.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_BODY_STATIC = 0,
    ENG_BODY_DYNAMIC = 1,
    ENG_BODY_KINEMATIC = 2
} eng_body_motion_t;

typedef enum {
    ENG_SHAPE_SPHERE = 0,
    ENG_SHAPE_AABB,
    ENG_SHAPE_CAPSULE,
    ENG_SHAPE_CONVEX_HULL,
    ENG_SHAPE_VOXEL_CHUNK,
    ENG_SHAPE_TERRAIN
} eng_shape_type_t;

typedef struct {
    eng_entity_t entity;
    eng_body_motion_t motion;
    eng_shape_type_t shape;
    uint16_t pocket_id;
    bool is_trigger;

    eng_vec3_t pos;
    eng_quat_t rot;
    eng_vec3_t vel;
    eng_vec3_t ang_vel;

    float mass;
    float restitution;
    float friction;

    /* Shape parameters */
    float radius;
    float half_height;
    eng_vec3_t half_extents;
    eng_vec3_t hull_verts[16];
    uint32_t hull_vert_count;
    const eng_voxel_chunk_t *voxel_chunk;
    const eng_terrain_t *terrain;

    /* 6-DOF rotational dynamics, material density & sleeping */
    float density;         /* kg/m^3; if > 0 on dynamic body, auto-computes mass = density * volume */
    float linear_damping;  /* linear drag (1/s) */
    float angular_damping; /* rotational drag (1/s) */
    bool freeze_rotation;  /* locks angular velocity (default true on ENG_SHAPE_CAPSULE) */
    bool sleeping;         /* true when body has settled below motion threshold */
} eng_body_desc_t;

typedef enum {
    ENG_JOINT_DISTANCE = 0,
    ENG_JOINT_BALL = 1,
    ENG_JOINT_HINGE = 2,
    ENG_JOINT_SPRING = 3
} eng_joint_type_t;

typedef struct {
    eng_joint_type_t type;
    uint32_t body_a;      /* 1-based body_id, or 0 for a fixed world-space anchor */
    uint32_t body_b;      /* 1-based body_id */
    eng_vec3_t anchor_a;  /* local offset on body_a (or world point when body_a == 0) */
    eng_vec3_t anchor_b;  /* local offset on body_b */
    eng_vec3_t axis_a;    /* local hinge axis on body_a (ENG_JOINT_HINGE) */
    float rest_length;    /* <= 0 auto-measures initial anchor distance (DISTANCE/SPRING) */
    float stiffness;      /* spring constant k in N/m (ENG_JOINT_SPRING) */
    float damping;        /* spring damper c in N*s/m (ENG_JOINT_SPRING) */
    float break_force;    /* > 0 snaps joint when constraint force exceeds threshold (Newtons) */
} eng_joint_desc_t;

typedef float (*eng_fluid_height_fn)(float x, float z, uint16_t pocket_id, void *user_data);

typedef struct {
    uint32_t body_a;
    uint32_t body_b;
    eng_vec3_t normal;
    float penetration;
    bool is_trigger;
} eng_contact_event_t;

typedef struct {
    bool hit;
    uint32_t body_id;
    eng_entity_t entity;
    uint16_t pocket_id;
    eng_vec3_t point;
    eng_vec3_t normal;
    float distance;
    uint32_t portal_hops;
} eng_raycast_hit_t;

typedef struct eng_physics_s eng_physics_t;

eng_body_desc_t eng_body_default_desc(eng_shape_type_t shape, eng_body_motion_t motion);
eng_joint_desc_t eng_joint_default_desc(eng_joint_type_t type, uint32_t body_a, uint32_t body_b);

eng_physics_t *eng_physics_create(void);
void eng_physics_destroy(eng_physics_t *phys);

void eng_physics_set_gravity(eng_physics_t *phys, uint16_t pocket_id, eng_vec3_t linear_gravity);
void eng_physics_set_planet_gravity(eng_physics_t *phys, uint16_t pocket_id,
                                    eng_vec3_t planet_center, float surface_g,
                                    const eng_planet_cfg_t *planet_surface_opt);
void eng_physics_set_fluid(eng_physics_t *phys, uint16_t pocket_id, bool enabled,
                           float level_y, float fluid_density, float drag_coeff,
                           eng_vec2_t flow_xz);
void eng_physics_set_fluid_sampler(eng_physics_t *phys, eng_fluid_height_fn fn, void *user_data);
void eng_physics_set_wind(eng_physics_t *phys, uint16_t pocket_id, eng_vec3_t wind_vel);

uint32_t eng_physics_add_body(eng_physics_t *phys, const eng_body_desc_t *desc);
bool eng_physics_remove_body(eng_physics_t *phys, uint32_t body_id);
eng_body_desc_t *eng_physics_get_body(eng_physics_t *phys, uint32_t body_id);
void eng_physics_wake_body(eng_physics_t *phys, uint32_t body_id);

bool eng_physics_apply_impulse_at(eng_physics_t *phys, uint32_t body_id,
                                  eng_vec3_t impulse, eng_vec3_t world_point);
size_t eng_physics_radial_blast(eng_physics_t *phys, uint16_t pocket_id,
                                eng_vec3_t center, float radius, float max_impulse);

uint32_t eng_physics_add_joint(eng_physics_t *phys, const eng_joint_desc_t *desc);
bool eng_physics_remove_joint(eng_physics_t *phys, uint32_t joint_id);
bool eng_physics_joint_is_active(const eng_physics_t *phys, uint32_t joint_id);

/* Deterministic fixed-step simulation + cross-portal threshold teleportation & ghost proxy contacts. */
void eng_physics_step(eng_physics_t *phys, const eng_scene_t *scene,
                      const eng_portal_sys_t *portals, float dt);

/* Stair-stepping character controller supporting flat gravity, planet radial gravity, and portal crossing. */
bool eng_physics_move_character(eng_physics_t *phys, const eng_scene_t *scene,
                                const eng_portal_sys_t *portals, uint32_t body_id,
                                eng_vec3_t wish_disp, float max_step_height, bool *out_grounded);

/* Lateral XZ sphere collision + wall sliding against static AABB/voxel colliders in pocket_id. */
eng_vec3_t eng_physics_slide_xz(const eng_physics_t *phys, uint16_t pocket_id,
                                eng_vec3_t pos, float dx, float dz, float radius);

/* Cross-portal & BVH-accelerated raycast (traverses open portals across pocket spaces). */
eng_raycast_hit_t eng_physics_raycast(const eng_physics_t *phys, const eng_scene_t *scene,
                                      const eng_portal_sys_t *portals, uint16_t start_pocket,
                                      eng_vec3_t origin, eng_vec3_t dir, float max_dist);

/* Pure-C GJK intersection test between two convex point clouds in world space. */
bool eng_physics_gjk_intersect(const eng_vec3_t *verts_a, size_t count_a,
                               const eng_vec3_t *verts_b, size_t count_b,
                               eng_vec3_t *out_sep_dir, float *out_depth);

size_t eng_physics_contact_count(const eng_physics_t *phys);
const eng_contact_event_t *eng_physics_contact_get(const eng_physics_t *phys, size_t index);

#ifdef __cplusplus
}
#endif

#endif /* ENG_PHYSICS_H */
