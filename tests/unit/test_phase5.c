#include "engine/engine.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void test_anim_ik_and_procgen_life(void) {
    /* 1. All 6 DNA Animal archetypes + procedural gait IK + FABRIK */
    for (int arch = 0; arch <= (int)ENG_ANIMAL_SERPENTINE; arch++) {
        eng_animal_asset_t anim_asset;
        assert(eng_procgen_animal(700u + (uint64_t)arch, (eng_animal_archetype_t)arch, &anim_asset));
        assert(anim_asset.mesh.vert_count > 40 && anim_asset.skeleton.bone_count >= 4);

        eng_anim_pose_t pose;
        eng_anim_pose_reset(&anim_asset.skeleton, &pose);
        eng_anim_step_gait(&anim_asset.skeleton, &anim_asset.gait, 0.35f, 1.0f, &pose);
        eng_anim_compute_skin_matrices(&anim_asset.skeleton, &pose);
        assert(eng_mat4_is_finite(&pose.skin_mats[0]));

        if (arch == (int)ENG_ANIMAL_SERPENTINE) {
            uint32_t chain[4] = {3, 4, 5, 6};
            assert(eng_anim_ik_fabrik(&anim_asset.skeleton, &pose, chain, 4, eng_v3(0.5f, 0.4f, 1.8f), 8));
        }
        eng_animal_asset_free(&anim_asset);
    }

    /* 2. Modular Person / NPC + Humanoid Gait IK */
    eng_person_asset_t npc;
    assert(eng_procgen_person(12345u, &npc));
    assert(strlen(npc.name) >= 3 && strlen(npc.role) >= 4 && npc.gait.limb_count == 2);
    eng_anim_pose_t p_idle, p_walk, p_blend;
    eng_anim_pose_reset(&npc.skeleton, &p_idle);
    eng_anim_pose_reset(&npc.skeleton, &p_walk);
    eng_anim_step_gait(&npc.skeleton, &npc.gait, 0.25f, 1.0f, &p_walk);
    eng_anim_blend_poses(&npc.skeleton, &p_idle, &p_walk, 0.6f, ~0ULL, &p_blend);
    eng_anim_compute_skin_matrices(&npc.skeleton, &p_blend);
    assert(eng_mat4_is_finite(&p_blend.skin_mats[npc.gait.knee_bone[0]]));

    /* 3. Clip sampling (STEP, LINEAR, CUBIC) */
    eng_anim_clip_t clip;
    memset(&clip, 0, sizeof(clip));
    snprintf(clip.name, sizeof(clip.name), "test_clip");
    clip.duration = 1.0f;
    clip.channel_count = 3;
    clip.channels = (eng_anim_channel_t *)calloc(3, sizeof(eng_anim_channel_t));

    /* Linear pos on bone 0 */
    clip.channels[0].bone_idx = 0;
    clip.channels[0].path = ENG_ANIM_PATH_POS;
    clip.channels[0].interp = ENG_INTERP_LINEAR;
    clip.channels[0].key_count = 2;
    clip.channels[0].times = (float *)calloc(2, sizeof(float));
    clip.channels[0].values = (float *)calloc(6, sizeof(float));
    clip.channels[0].times[1] = 1.0f;
    clip.channels[0].values[4] = 2.0f;

    /* Step rot on bone 1 */
    clip.channels[1].bone_idx = 1;
    clip.channels[1].path = ENG_ANIM_PATH_ROT;
    clip.channels[1].interp = ENG_INTERP_STEP;
    clip.channels[1].key_count = 2;
    clip.channels[1].times = (float *)calloc(2, sizeof(float));
    clip.channels[1].values = (float *)calloc(8, sizeof(float));
    clip.channels[1].times[1] = 1.0f;
    clip.channels[1].values[3] = 1.0f;
    clip.channels[1].values[7] = 1.0f;

    /* Cubic scale on bone 2 */
    clip.channels[2].bone_idx = 2;
    clip.channels[2].path = ENG_ANIM_PATH_SCALE;
    clip.channels[2].interp = ENG_INTERP_CUBIC;
    clip.channels[2].key_count = 2;
    clip.channels[2].times = (float *)calloc(2, sizeof(float));
    clip.channels[2].values = (float *)calloc(18, sizeof(float));
    clip.channels[2].times[1] = 1.0f;
    clip.channels[2].values[3] = 1.0f; clip.channels[2].values[4] = 1.0f; clip.channels[2].values[5] = 1.0f;
    clip.channels[2].values[12] = 2.0f; clip.channels[2].values[13] = 2.0f; clip.channels[2].values[14] = 2.0f;

    eng_anim_sample_clip(&npc.skeleton, &clip, 0.5f, true, &p_idle);
    assert(fabsf(p_idle.local_pos[0].y - 1.0f) < 0.05f);
    assert(fabsf(p_idle.local_scale[2].x - 1.5f) < 0.05f);
    eng_anim_clip_free(&clip);
    eng_person_asset_free(&npc);

    /* 4. glTF skin + animation loader */
    const char *gltf_skin =
        "{\"asset\":{\"version\":\"2.0\"},"
        "\"buffers\":[{\"uri\":\"data:application/octet-stream;base64,AAAAAAAAgD8AAACAPwAAAIA/AAAAAAAA\",\"byteLength\":24}],"
        "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":8},{\"buffer\":0,\"byteOffset\":8,\"byteLength\":16}],"
        "\"accessors\":["
        "{\"bufferView\":0,\"componentType\":5126,\"count\":2,\"type\":\"SCALAR\"},"
        "{\"bufferView\":1,\"componentType\":5126,\"count\":2,\"type\":\"VEC3\",\"byteStride\":8}"
        "],"
        "\"nodes\":[{\"name\":\"root\",\"children\":[1]},{\"name\":\"tip\",\"translation\":[0,1,0]}],"
        "\"skins\":[{\"joints\":[0,1]}],"
        "\"animations\":[{\"name\":\"move\",\"samplers\":[{\"input\":0,\"output\":1}],\"channels\":[{\"sampler\":0,\"target\":{\"node\":1,\"path\":\"translation\"}}]}]"
        "}";
    eng_skeleton_t gltf_sk;
    eng_anim_clip_t gltf_cl;
    assert(eng_anim_load_gltf(gltf_skin, strlen(gltf_skin), &gltf_sk, &gltf_cl));
    assert(gltf_sk.bone_count == 2 && gltf_cl.channel_count == 1);
    eng_anim_clip_free(&gltf_cl);
}

static void test_physics_determinism_gjk_voxels_terrain(void) {
    /* 1. Pure-C GJK convex hull overlap vs separated */
    eng_vec3_t tetra_a[4] = {{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
    eng_vec3_t tetra_b[4] = {{0.3f, 0.2f, 0.2f}, {1.3f, 0.2f, 0.2f}, {0.3f, 1.2f, 0.2f}, {0.3f, 0.2f, 1.2f}};
    eng_vec3_t tetra_c[4] = {{5, 0, 0}, {6, 0, 0}, {5, 1, 0}, {5, 0, 1}};
    eng_vec3_t sep = {0, 0, 0}; float depth = 0.0f;
    assert(eng_physics_gjk_intersect(tetra_a, 4, tetra_b, 4, &sep, &depth) && depth > 0.0f);
    assert(!eng_physics_gjk_intersect(tetra_a, 4, tetra_c, 4, &sep, &depth));

    /* 2. Bit-identical deterministic rigid-body simulation across two independent worlds */
    eng_vec3_t final_pos[2];
    for (int run = 0; run < 2; run++) {
        eng_physics_t *phys = eng_physics_create();
        eng_body_desc_t floor_d = eng_body_default_desc(ENG_SHAPE_AABB, ENG_BODY_STATIC);
        floor_d.pos = eng_v3(0.0f, -0.5f, 0.0f);
        floor_d.half_extents = eng_v3(20.0f, 0.5f, 20.0f);
        eng_physics_add_body(phys, &floor_d);

        eng_body_desc_t trig_d = eng_body_default_desc(ENG_SHAPE_AABB, ENG_BODY_STATIC);
        trig_d.pos = eng_v3(0.0f, 1.0f, 0.0f);
        trig_d.half_extents = eng_v3(2.0f, 2.0f, 2.0f);
        trig_d.is_trigger = true;
        eng_physics_add_body(phys, &trig_d);

        eng_body_desc_t ball_d = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
        ball_d.pos = eng_v3(0.0f, 4.0f, 0.0f);
        ball_d.vel = eng_v3(1.5f, 0.0f, -0.5f);
        ball_d.radius = 0.5f;
        uint32_t ball_id = eng_physics_add_body(phys, &ball_d);

        eng_body_desc_t hull_d = eng_body_default_desc(ENG_SHAPE_CONVEX_HULL, ENG_BODY_DYNAMIC);
        hull_d.pos = eng_v3(0.4f, 2.0f, 0.0f);
        hull_d.hull_vert_count = 4;
        memcpy(hull_d.hull_verts, tetra_a, sizeof(tetra_a));
        eng_physics_add_body(phys, &hull_d);

        bool saw_trigger = false;
        for (int step = 0; step < 120; step++) {
            eng_physics_step(phys, NULL, NULL, 1.0f / 60.0f);
            for (size_t c = 0; c < eng_physics_contact_count(phys); c++) {
                if (eng_physics_contact_get(phys, c)->is_trigger) saw_trigger = true;
            }
        }
        assert(saw_trigger);
        final_pos[run] = eng_physics_get_body(phys, ball_id)->pos;
        eng_physics_destroy(phys);
    }
    assert(memcmp(&final_pos[0], &final_pos[1], sizeof(eng_vec3_t)) == 0);

    /* 3. Voxel chunk + Terrain collision + Stair-stepping character controller */
    eng_voxel_chunk_t vox;
    eng_voxel_chunk_init(&vox, 8, 8, 8, 0.5f);
    eng_voxel_csg_box(&vox, 0, 0, 0, 7, 0, 7, 1, ENG_CSG_UNION); /* Ground y in [0, 0.5] */
    eng_voxel_set(&vox, 3, 1, 3, 1); /* 0.5m step at x=1.5..2.0, y=0.5..1.0 */

    eng_terrain_t ter;
    eng_terrain_init(&ter, 8, 8, 2.0f, NULL);

    eng_physics_t *vp = eng_physics_create();
    eng_body_desc_t vb = eng_body_default_desc(ENG_SHAPE_VOXEL_CHUNK, ENG_BODY_STATIC);
    vb.voxel_chunk = &vox;
    eng_physics_add_body(vp, &vb);

    eng_body_desc_t tb = eng_body_default_desc(ENG_SHAPE_TERRAIN, ENG_BODY_STATIC);
    tb.pos = eng_v3(20.0f, 0.0f, 0.0f);
    tb.terrain = &ter;
    eng_physics_add_body(vp, &tb);

    eng_body_desc_t cb = eng_body_default_desc(ENG_SHAPE_CAPSULE, ENG_BODY_KINEMATIC);
    cb.pos = eng_v3(1.2f, 1.3f, 1.75f);
    cb.radius = 0.3f;
    cb.half_height = 0.5f;
    uint32_t char_id = eng_physics_add_body(vp, &cb);

    bool grounded = false;
    assert(eng_physics_move_character(vp, NULL, NULL, char_id, eng_v3(0.45f, -0.05f, 0.0f), 0.6f, &grounded));
    assert(grounded && eng_physics_get_body(vp, char_id)->pos.y > 1.4f);
    assert(eng_physics_remove_body(vp, char_id));

    eng_raycast_hit_t vhit = eng_physics_raycast(vp, NULL, NULL, 0, eng_v3(1.75f, 5.0f, 1.75f), eng_v3(0, -1, 0), 10.0f);
    assert(vhit.hit && fabsf(vhit.point.y - 1.0f) < 0.05f);
    eng_terrain_free(&ter);
    eng_physics_destroy(vp);
}

static void test_cross_portal_physics_raycast_and_planet_gravity(void) {
    eng_scene_t *sc = eng_scene_create(64);
    uint16_t p_world = eng_scene_register_pocket(sc, "world");
    uint16_t p_cabin = eng_scene_register_pocket(sc, "cabin");

    eng_entity_t d_ext = eng_scene_spawn(sc, "d_ext");
    eng_entity_t d_int = eng_scene_spawn(sc, "d_int");
    eng_scene_set_pocket(sc, d_ext, p_world);
    eng_scene_set_pocket(sc, d_int, p_cabin);
    eng_scene_set_local_pos(sc, d_ext, eng_v3(0.0f, 1.0f, 0.0f));
    eng_scene_set_local_pos(sc, d_int, eng_v3(0.0f, 1.0f, 20.0f));
    eng_scene_update_transforms(sc);

    eng_portal_sys_t *ps = eng_portal_sys_create();
    eng_portal_link(ps, sc, d_ext, d_int, 2.0f, 2.4f, 1.0f, true, true);

    eng_physics_t *phys = eng_physics_create();
    eng_physics_set_gravity(phys, p_world, eng_v3(0, 0, 0));
    eng_physics_set_gravity(phys, p_cabin, eng_v3(0, 0, 0));

    /* Target inside "cabin" at (0, 1, 24) (4m past interior doorway along +Z!) */
    eng_entity_t tgt_ent = eng_scene_spawn(sc, "cabin_target");
    eng_body_desc_t tgt = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_STATIC);
    tgt.entity = tgt_ent;
    tgt.pocket_id = p_cabin;
    tgt.pos = eng_v3(0.0f, 1.0f, 24.0f);
    tgt.radius = 0.6f;
    uint32_t tgt_id = eng_physics_add_body(phys, &tgt);

    /* 1. Cross-portal raycast from exterior world (0, 1, 3) along -Z into pocket "cabin" */
    eng_raycast_hit_t rhit = eng_physics_raycast(phys, sc, ps, p_world, eng_v3(0.0f, 1.0f, 3.0f), eng_v3(0.0f, 0.0f, -1.0f), 20.0f);
    assert(rhit.hit && rhit.body_id == tgt_id && rhit.pocket_id == p_cabin && rhit.portal_hops == 1);
    assert(fabsf(rhit.distance - 6.4f) < 0.1f);

    /* Static interior floor right inside doorway to exercise cross-portal ghost proxy collider */
    eng_body_desc_t in_floor = eng_body_default_desc(ENG_SHAPE_AABB, ENG_BODY_STATIC);
    in_floor.pocket_id = p_cabin;
    in_floor.pos = eng_v3(0.0f, -0.35f, 21.5f);
    in_floor.half_extents = eng_v3(3.0f, 0.5f, 1.5f);
    eng_physics_add_body(phys, &in_floor);

    /* AABB-vs-AABB & Sphere-vs-Sphere in world */
    eng_body_desc_t box1 = eng_body_default_desc(ENG_SHAPE_AABB, ENG_BODY_DYNAMIC);
    box1.pocket_id = p_world; box1.pos = eng_v3(6.0f, 1.0f, 0.0f); box1.vel = eng_v3(1.0f, 0, 0);
    eng_body_desc_t box2 = eng_body_default_desc(ENG_SHAPE_AABB, ENG_BODY_STATIC);
    box2.pocket_id = p_world; box2.pos = eng_v3(6.8f, 1.0f, 0.0f);
    eng_physics_add_body(phys, &box1);
    eng_physics_add_body(phys, &box2);

    eng_body_desc_t sp1 = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
    sp1.pocket_id = p_world; sp1.pos = eng_v3(-6.0f, 1.0f, 0.0f);
    eng_body_desc_t sp2 = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
    sp2.pocket_id = p_world; sp2.pos = eng_v3(-5.3f, 1.0f, 0.0f);
    eng_physics_add_body(phys, &sp1);
    eng_physics_add_body(phys, &sp2);

    /* 2. Dynamic projectile straddling & flying through open portal from "world" into "cabin" */
    eng_body_desc_t proj_d = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
    proj_d.pocket_id = p_world;
    proj_d.pos = eng_v3(0.0f, 0.35f, 0.3f);
    proj_d.vel = eng_v3(0.0f, 0.0f, -6.0f);
    proj_d.radius = 0.25f;
    proj_d.friction = 0.0f;
    uint32_t proj_id = eng_physics_add_body(phys, &proj_d);

    for (int i = 0; i < 15; i++) {
        eng_physics_step(phys, sc, ps, 1.0f / 60.0f);
    }
    eng_body_desc_t *pb = eng_physics_get_body(phys, proj_id);
    assert(pb->pocket_id == p_cabin && pb->pos.z > 20.5f && pb->vel.z > 5.0f);

    /* 3. Radial spherical planet gravity + planet character controller in pocket 2 */
    eng_planet_cfg_t pcfg = eng_planet_default_cfg(55u, 30.0f);
    pcfg.continent_amp = 0.0f; /* Exact R=30 smooth test sphere */
    eng_physics_set_planet_gravity(phys, 2, eng_v3(0, 0, 0), 9.81f, &pcfg);

    eng_body_desc_t astro = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
    astro.pocket_id = 2;
    astro.pos = eng_v3(0.0f, -31.5f, 0.0f); /* South pole! Falls UP toward (0, -30.5, 0)! */
    astro.radius = 0.5f;
    uint32_t astro_id = eng_physics_add_body(phys, &astro);

    for (int i = 0; i < 60; i++) {
        eng_physics_step(phys, sc, ps, 1.0f / 60.0f);
    }
    eng_body_desc_t *ab = eng_physics_get_body(phys, astro_id);
    assert(fabsf(ab->pos.y + 30.5f) < 0.1f);

    bool planet_grounded = false;
    assert(eng_physics_move_character(phys, sc, ps, astro_id, eng_v3(0.1f, 0.02f, 0.0f), 0.3f, &planet_grounded));
    assert(planet_grounded);

    eng_physics_destroy(phys);
    eng_portal_sys_destroy(ps);
    eng_scene_destroy(sc);
}

static void test_moving_vehicle_portal_kinematics_and_galilean_velocity(void) {
    eng_scene_t *sc = eng_scene_create(64);
    uint16_t p_world = eng_scene_register_pocket(sc, "world");
    uint16_t p_bridge = eng_scene_register_pocket(sc, "bridge");

    eng_entity_t veh = eng_scene_spawn(sc, "mech_hull");
    eng_scene_set_pocket(sc, veh, p_world);
    eng_scene_set_local_pos(sc, veh, eng_v3(0.0f, 0.0f, 0.0f));

    /* Front-facing scoop hatch on vehicle (rot_y = 180 -> local +Z points along world -Z) */
    eng_entity_t h_ext = eng_scene_spawn(sc, "scoop_ext");
    eng_scene_set_pocket(sc, h_ext, p_world);
    eng_scene_set_parent(sc, h_ext, veh);
    eng_scene_set_local_pos(sc, h_ext, eng_v3(0.0f, 1.0f, 0.0f));
    eng_scene_set_local_rot(sc, h_ext, eng_quat_from_euler_deg(eng_v3(0.0f, 180.0f, 0.0f)));

    eng_entity_t h_int = eng_scene_spawn(sc, "scoop_int");
    eng_scene_set_pocket(sc, h_int, p_bridge);
    eng_scene_set_local_pos(sc, h_int, eng_v3(0.0f, 1.0f, 8.0f));
    eng_scene_set_local_rot(sc, h_int, eng_quat_from_euler_deg(eng_v3(0.0f, 180.0f, 0.0f)));
    eng_scene_update_transforms(sc);

    eng_portal_sys_t *ps = eng_portal_sys_create();
    int p_ext_to_int = eng_portal_link(ps, sc, h_ext, h_int, 3.0f, 3.0f, 1.0f, true, true);
    assert(p_ext_to_int == 0);
    eng_portal_step_kinematics(ps, sc, 0.0f);

    eng_physics_t *phys = eng_physics_create();
    eng_physics_set_gravity(phys, p_world, eng_v3(0, 0, 0));
    eng_physics_set_gravity(phys, p_bridge, eng_v3(0, 0, 0));

    /* 1. Stationary external crate at (0, 1, -0.4) gets scooped into bridge when vehicle advances -1.0m in dt=0.05s (-20 m/s) */
    eng_body_desc_t crate_d = eng_body_default_desc(ENG_SHAPE_SPHERE, ENG_BODY_DYNAMIC);
    crate_d.pocket_id = p_world;
    crate_d.pos = eng_v3(0.0f, 1.0f, -0.4f);
    crate_d.vel = eng_v3(0.0f, 0.0f, 0.0f);
    uint32_t crate_id = eng_physics_add_body(phys, &crate_d);

    float dt = 0.05f;
    eng_scene_set_local_pos(sc, veh, eng_v3(0.0f, 0.0f, -1.0f));
    eng_scene_update_transforms(sc);
    eng_portal_step_kinematics(ps, sc, dt);
    eng_physics_step(phys, sc, ps, dt);

    eng_body_desc_t *cb = eng_physics_get_body(phys, crate_id);
    assert(cb->pocket_id == p_bridge);
    /* Crate was stationary while vehicle moved -20m/s -> enters interior moving -20m/s relative to bridge */
    assert(fabsf(cb->vel.z + 20.0f) < 0.25f);

    /* 2. Exiting interior bridge (portal index 1: h_int -> h_ext) with explicit linear + angular hull velocity */
    assert(eng_portal_set_velocity(ps, 1, eng_v3(0, 0, 0), eng_v3(0, 0, 0),
                                   eng_v3(0.0f, 0.0f, -15.0f), eng_v3(0.0f, 2.0f, 0.0f)));
    const eng_portal_t *p_out = eng_portal_get(ps, 1);
    /* Exit off-center at x = -1.0 inside yaw=180 doorway -> warps to r_dst = (+1,0,0) on h_ext; omega=(0,2,0) x r=(1,0,0) = (0,0,-2) */
    eng_vec3_t exit_v = eng_portal_transform_velocity(ps, sc, p_out, eng_v3(-1.0f, 1.0f, 8.0f), eng_v3(0.0f, 0.0f, 3.0f));
    /* Local +3 m/s exit along +Z flips to -3 m/s out the -Z front scoop, plus -15 m/s hull + -2 m/s tangential = -20 m/s! */
    assert(fabsf(exit_v.z + 20.0f) < 0.2f);

    eng_physics_destroy(phys);
    eng_portal_sys_destroy(ps);
    eng_scene_destroy(sc);
}

int main(void) {
    test_anim_ik_and_procgen_life();
    test_physics_determinism_gjk_voxels_terrain();
    test_cross_portal_physics_raycast_and_planet_gravity();
    test_moving_vehicle_portal_kinematics_and_galilean_velocity();
    printf("Phase 5 unit tests passed!\n");
    return 0;
}
