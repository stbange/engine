#include "engine/engine.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void wr_le32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static void test_pockets_and_portals(void) {
    eng_scene_t *sc = eng_scene_create(256);
    assert(sc != NULL);

    uint16_t p_world = eng_scene_register_pocket(sc, "world");
    uint16_t p_hut = eng_scene_register_pocket(sc, "hut_inside");
    uint16_t p_hut_dup = eng_scene_register_pocket(sc, "hut_inside");
    assert(p_world == 0 && p_hut == 1 && p_hut_dup == p_hut);
    assert(strcmp(eng_scene_pocket_name(sc, 0), "world") == 0);
    assert(strcmp(eng_scene_pocket_name(sc, p_hut), "hut_inside") == 0);

    eng_entity_t door_ext = eng_scene_spawn(sc, "door_ext");
    eng_entity_t door_int = eng_scene_spawn(sc, "door_int");
    eng_scene_set_pocket(sc, door_ext, p_world);
    eng_scene_set_pocket(sc, door_int, p_hut);
    assert(eng_scene_get_pocket(sc, door_ext) == p_world);
    assert(eng_scene_get_pocket(sc, door_int) == p_hut);

    /* Exterior doorway at (0, 1, 0), interior doorway in oversized pocket at (0, 1, 15) */
    eng_scene_set_local_pos(sc, door_ext, eng_v3(0.0f, 1.0f, 0.0f));
    eng_scene_set_local_pos(sc, door_int, eng_v3(0.0f, 1.0f, 15.0f));
    eng_scene_update_transforms(sc);

    /* Pocket JSON round-trip */
    char json[8192];
    size_t jlen = eng_scene_save_json(sc, json, sizeof(json));
    assert(jlen > 0 && strstr(json, "\"hut_inside\"") != NULL);
    eng_scene_t *sc2 = eng_scene_create(256);
    char err[256] = {0};
    assert(eng_scene_load_json(sc2, json, err, sizeof(err)));
    eng_entity_t loaded_int = eng_ecs_find_by_name(eng_scene_ecs(sc2), "door_int");
    assert(strcmp(eng_scene_pocket_name(sc2, eng_scene_get_pocket(sc2, loaded_int)), "hut_inside") == 0);
    eng_scene_destroy(sc2);

    eng_portal_sys_t *ps = eng_portal_sys_create();
    assert(ps != NULL);
    assert(eng_portal_link(ps, sc, door_ext, door_int, -1.0f, 2.0f, 1.0f, true, true) < 0);
    int pid = eng_portal_link(ps, sc, door_ext, door_int, 1.2f, 2.2f, 1.0f, true, true);
    assert(pid == 0 && eng_portal_count(ps) == 2);

    const eng_portal_t *p0 = eng_portal_get(ps, 0);
    assert(p0 && p0->src_pocket == p_world && p0->dst_pocket == p_hut);

    eng_mat4_t view = eng_mat4_look_at(eng_v3(0.0f, 1.2f, 3.0f), eng_v3(0.0f, 1.2f, 0.0f), eng_v3(0, 1, 0));
    eng_mat4_t proj = eng_mat4_perspective(60.0f * ENG_DEG2RAD, 1.333f, 0.1f, 200.0f);
    eng_mat4_t vp = eng_mat4_mul(&proj, &view);

    eng_mat4_t virt_view, oblique_proj;
    assert(eng_portal_virtual_camera(sc, p0, &view, &proj, &virt_view, &oblique_proj));
    assert(eng_mat4_is_finite(&virt_view) && eng_mat4_is_finite(&oblique_proj));

    int sc_rect[4] = {0};
    assert(eng_portal_screen_scissor(sc, p0, &vp, 640, 480, sc_rect));
    assert(sc_rect[2] > 50 && sc_rect[3] > 50);

    /* Straddling near-plane expands scissor to full viewport cleanly */
    eng_mat4_t close_view = eng_mat4_look_at(eng_v3(0.0f, 1.0f, 0.02f), eng_v3(0.0f, 1.0f, -1.0f), eng_v3(0, 1, 0));
    eng_mat4_t close_vp = eng_mat4_mul(&proj, &close_view);
    assert(eng_portal_screen_scissor(sc, p0, &close_vp, 640, 480, sc_rect));
    assert(sc_rect[2] == 640 && sc_rect[3] == 480);

    /* Looking away culls portal scissor */
    eng_mat4_t away_view = eng_mat4_look_at(eng_v3(0.0f, 1.0f, -3.0f), eng_v3(0.0f, 1.0f, -6.0f), eng_v3(0, 1, 0));
    eng_mat4_t away_vp = eng_mat4_mul(&proj, &away_view);
    assert(!eng_portal_screen_scissor(sc, p0, &away_vp, 640, 480, sc_rect));

    /* Portal threshold crossing */
    eng_vec3_t warped = eng_v3(0, 0, 0);
    assert(eng_portal_check_crossing(ps, sc, p_world, eng_v3(0.0f, 1.0f, 0.4f), eng_v3(0.0f, 1.0f, 0.1f), &warped) == NULL);
    const eng_portal_t *crossed = eng_portal_check_crossing(ps, sc, p_world, eng_v3(0.0f, 1.0f, 0.3f), eng_v3(0.0f, 1.0f, -0.2f), &warped);
    assert(crossed == p0);
    assert(fabsf(warped.z - 15.2f) < 0.05f);

    /* LLM Doorway wall cutter */
    eng_aabb_t wall_boxes[3];
    size_t nb = eng_portal_cut_doorway_boxes(4.0f, 3.0f, 0.2f, 1.2f, 2.2f, wall_boxes);
    assert(nb == 3);

    eng_portal_sys_destroy(ps);
    eng_scene_destroy(sc);
}

static void test_assets_voxels_and_sprites(eng_vfs_t *vfs) {
    eng_gl_init_software_mock();
    eng_asset_cache_t *cache = eng_asset_cache_create(vfs);
    assert(cache != NULL);

    /* Compound CSG mesh primitives */
    eng_mesh_data_t md;
    eng_mesh_data_init(&md);
    assert(eng_mesh_append_box(&md, eng_v3(0, 0, 0), eng_v3(1, 1, 1), (eng_vec4_t){1, 0, 0, 1}));
    assert(eng_mesh_append_sphere(&md, eng_v3(0, 1, 0), 0.5f, 8, 8, (eng_vec4_t){0, 1, 0, 1}));
    assert(eng_mesh_append_cylinder(&md, eng_v3(0, 0, 0), 0.4f, 0.2f, 1.5f, 8, (eng_vec4_t){0, 0, 1, 1}));
    assert(md.vert_count > 40 && md.idx_count > 90);

    /* Multi-LOD upload */
    eng_mesh_data_t lods[3];
    for (int l = 0; l < 3; l++) eng_mesh_data_init(&lods[l]);
    eng_mesh_append_sphere(&lods[0], eng_v3(0, 0, 0), 1.0f, 12, 12, (eng_vec4_t){1, 1, 1, 1});
    eng_mesh_append_sphere(&lods[1], eng_v3(0, 0, 0), 1.0f, 6, 6, (eng_vec4_t){1, 1, 1, 1});
    eng_mesh_append_sphere(&lods[2], eng_v3(0, 0, 0), 1.0f, 4, 4, (eng_vec4_t){1, 1, 1, 1});
    uint32_t lod_mesh = eng_asset_upload_mesh_lods(cache, "sphere_lods", lods, 3);
    assert(lod_mesh != 0);
    const eng_gpu_mesh_t *gm = eng_asset_get_mesh(cache, lod_mesh);
    assert(gm && gm->lod_index_counts[0] > gm->lod_index_counts[1] && gm->lod_index_counts[1] > gm->lod_index_counts[2]);
    for (int l = 0; l < 3; l++) eng_mesh_data_free(&lods[l]);
    eng_mesh_data_free(&md);

    /* OBJ parser & VFS mesh load */
    const char *obj_str =
        "v -1 0 -1\nv 1 0 -1\nv 1 0 1\nv -1 0 1\n"
        "vn 0 1 0\nvt 0 0\nvt 1 1\n"
        "f 1/1/1 2/2/1 3/1/1 4/2/1\n"
        "f 1//1 2//1 3//1\n"
        "f 1 2 3\n";
    assert(eng_vfs_write_all(vfs, "tmp_test.obj", obj_str, strlen(obj_str)));
    uint32_t m_obj = eng_asset_load_mesh(cache, "tmp_test.obj");
    assert(m_obj != 0 && eng_asset_load_mesh(cache, "tmp_test.obj") == m_obj);

    /* Minimal glTF 2.0 JSON + embedded base64 triangle buffer */
    const char *gltf_json =
        "{\"asset\":{\"version\":\"2.0\"},"
        "\"buffers\":[{\"uri\":\"data:application/octet-stream;base64,AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA\",\"byteLength\":36}],"
        "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36}],"
        "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}],"
        "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0}}]}]}";
    assert(eng_vfs_write_all(vfs, "tmp_tri.gltf", gltf_json, strlen(gltf_json)));
    uint32_t m_gltf = eng_asset_load_mesh(cache, "tmp_tri.gltf");
    assert(m_gltf != 0);

    /* PNG write + VFS texture load round-trip */
    uint8_t px[16 * 16 * 4];
    for (int i = 0; i < 16 * 16; i++) {
        px[i * 4 + 0] = 220; px[i * 4 + 1] = 80; px[i * 4 + 2] = 40; px[i * 4 + 3] = 255;
    }
    char png_path[256];
    snprintf(png_path, sizeof(png_path), "%s/tmp_tex.png", ENG_BINARY_DIR);
    assert(eng_asset_write_png(png_path, 16, 16, px));
    uint32_t tid = eng_asset_load_texture(cache, "tmp_tex.png", true);
    assert(tid != 0 && eng_asset_load_texture(cache, "tmp_tex.png", true) == tid);
    const eng_gpu_tex_t *gt = eng_asset_get_texture(cache, tid);
    assert(gt && gt->width == 16 && gt->height == 16);

    /* Also test bilinear mipmapped texture path */
    uint32_t tid_lin = eng_asset_create_texture_rgba(cache, "lin_tex", 16, 16, px, false);
    assert(tid_lin != 0);

    /* Voxels: ASCII builder, CSG, Greedy Meshing & DDA Raycast */
    eng_voxel_chunk_t chunk;
    eng_voxel_chunk_init(&chunk, 8, 8, 8, 1.0f);
    const char *layers[2] = {
        "1111\n1111\n1111\n1111",
        "1..A\n....\n....\n#..2"
    };
    assert(eng_voxel_from_ascii(&chunk, layers, 2));
    assert(eng_voxel_get(&chunk, 0, 0, 0) == 1);
    assert(eng_voxel_get(&chunk, 3, 1, 0) == 10);

    eng_voxel_csg_box(&chunk, 0, 0, 0, 7, 3, 7, 2, ENG_CSG_UNION);
    eng_voxel_csg_sphere(&chunk, 4.0f, 3.0f, 4.0f, 2.0f, 0, ENG_CSG_SUBTRACT);
    eng_voxel_csg_box(&chunk, 0, 0, 0, 6, 3, 6, 2, ENG_CSG_INTERSECT);

    eng_mesh_data_t vox_md;
    assert(eng_voxel_build_mesh(&chunk, &vox_md));
    assert(vox_md.vert_count > 0 && vox_md.vert_count < 600);
    eng_mesh_data_free(&vox_md);

    eng_voxel_hit_t hit = eng_voxel_raycast(&chunk, eng_v3(1.5f, 10.0f, 1.5f), eng_v3(0.0f, -1.0f, 0.0f), 20.0f);
    assert(hit.hit && hit.ny == 1 && hit.block_id == 2);

    /* MagicaVoxel .vox binary loader */
    uint8_t vox_bin[8 + 12 + 24 + 20 + 1036];
    memset(vox_bin, 0, sizeof(vox_bin));
    size_t p = 0;
    memcpy(vox_bin + p, "VOX ", 4); wr_le32(vox_bin + p + 4, 150); p += 8;
    memcpy(vox_bin + p, "MAIN", 4); wr_le32(vox_bin + p + 4, 0); wr_le32(vox_bin + p + 8, 24 + 20 + 1036); p += 12;
    memcpy(vox_bin + p, "SIZE", 4); wr_le32(vox_bin + p + 4, 12); wr_le32(vox_bin + p + 8, 0); p += 12;
    wr_le32(vox_bin + p, 4); wr_le32(vox_bin + p + 4, 4); wr_le32(vox_bin + p + 8, 4); p += 12;
    memcpy(vox_bin + p, "XYZI", 4); wr_le32(vox_bin + p + 4, 8); wr_le32(vox_bin + p + 8, 0); p += 12;
    wr_le32(vox_bin + p, 1); vox_bin[p + 4] = 1; vox_bin[p + 5] = 2; vox_bin[p + 6] = 3; vox_bin[p + 7] = 5; p += 8;
    memcpy(vox_bin + p, "RGBA", 4); wr_le32(vox_bin + p + 4, 1024); wr_le32(vox_bin + p + 8, 0); p += 12;
    vox_bin[p + 16] = 255; p += 1024;
    assert(eng_voxel_load_vox(&chunk, vox_bin, p));
    assert(eng_voxel_get(&chunk, 1, 3, 2) == 5);

    /* Sprites: 8-way angle + batching */
    int d0 = eng_sprite_dir8_index(eng_v3(0, 0, -5), eng_v3(0, 0, 0), 0.0f);
    int d4 = eng_sprite_dir8_index(eng_v3(0, 0, 5), eng_v3(0, 0, 0), 0.0f);
    assert(d0 == 0 && d4 == 4);

    eng_sprite_item_t sps[3] = {
        {eng_v3(0, 0, -4), {1.0f, 2.0f}, 0.0f, {0, 0, 1, 1}, {1, 1, 1, 1}, tid, 0, ENG_SPRITE_BILLBOARD_Y},
        {eng_v3(2, 1, -4), {0.5f, 0.5f}, 0.0f, {0, 0, 1, 1}, {1, 1, 1, 1}, tid, 0, ENG_SPRITE_DIRECTIONAL_8},
        {eng_v3(0, 0, -4), {1.0f, 1.0f}, 0.0f, {0, 0, 1, 1}, {1, 1, 1, 1}, tid, 1, ENG_SPRITE_BILLBOARD_SPHERICAL}
    };
    eng_mesh_data_t sp_md;
    assert(eng_sprite_build_batch(sps, 3, 0, eng_v3(0, 1, 2), eng_v3(1, 0, 0), eng_v3(0, 1, 0), &sp_md) == 2);
    eng_mesh_data_free(&sp_md);

    eng_asset_cache_destroy(cache);
}

static void run_full_render_pipeline_check(eng_vfs_t *vfs, bool verify_real_gl_pixels) {
    eng_asset_cache_t *assets = eng_asset_cache_create(vfs);
    eng_renderer_t *ren = eng_renderer_create(vfs, assets, 320, 240);
    assert(ren != NULL);

    eng_scene_t *sc = eng_scene_create(256);
    uint16_t p_world = eng_scene_register_pocket(sc, "world");
    uint16_t p_inside = eng_scene_register_pocket(sc, "inside");

    eng_entity_t d_ext = eng_scene_spawn(sc, "d_ext");
    eng_entity_t d_int = eng_scene_spawn(sc, "d_int");
    eng_scene_set_pocket(sc, d_ext, p_world);
    eng_scene_set_pocket(sc, d_int, p_inside);
    eng_scene_set_local_pos(sc, d_ext, eng_v3(0.0f, 1.2f, -3.0f));
    eng_scene_set_local_pos(sc, d_int, eng_v3(0.0f, 1.2f, 20.0f));
    eng_scene_update_transforms(sc);

    eng_portal_sys_t *portals = eng_portal_sys_create();
    eng_portal_link(portals, sc, d_ext, d_int, 2.0f, 2.4f, 1.0f, true, true);

    eng_mesh_data_t box_md;
    eng_mesh_data_init(&box_md);
    eng_mesh_append_box(&box_md, eng_v3(0, 0, 0), eng_v3(1, 1, 1), (eng_vec4_t){1, 1, 1, 1});
    uint32_t box_id = eng_asset_upload_mesh(assets, "unit_box", &box_md);
    eng_mesh_data_free(&box_md);

    eng_camera_t cam = eng_camera_default();
    cam.pos = eng_v3(0.0f, 1.5f, 4.0f);
    cam.pocket_id = p_world;

    /* Test 1: Forward PBR/Retro with instancing, frustum culling, occluder culling, LODs & Pocket Portal */
    eng_renderer_set_pipeline(ren, ENG_PIPELINE_FORWARD);
    assert(eng_renderer_get_pipeline(ren) == ENG_PIPELINE_FORWARD);
    eng_retro_cfg_t ps1 = eng_retro_ps1_preset();
    eng_renderer_set_retro(ren, &ps1);
    assert(eng_renderer_get_retro(ren).dither_bayer);
    eng_renderer_set_sky(ren, eng_v3(0.1f, 0.2f, 0.6f), eng_v3(0.5f, 0.6f, 0.8f), eng_v3(0.1f, 0.1f, 0.1f));
    eng_renderer_set_ambient(ren, eng_v3(0.25f, 0.25f, 0.25f));
    eng_renderer_set_max_portal_depth(ren, 2);

    eng_renderer_begin_frame(ren);
    eng_light_t sun = {ENG_LIGHT_DIR, p_world, {0, 20, 10}, {-0.3f, -1.0f, -0.4f}, {2.5f, 2.4f, 2.2f}, 0, 0, true};
    eng_light_t lamp = {ENG_LIGHT_POINT, p_inside, {0, 3, 16}, {0, -1, 0}, {3.0f, 1.2f, 0.4f}, 25.0f, 0, false};
    eng_light_t spot = {ENG_LIGHT_SPOT, p_world, {0, 4, 2}, {0, -1, -1}, {1.0f, 1.0f, 2.0f}, 15.0f, 0.8f, false};
    eng_renderer_add_light(ren, &sun);
    eng_renderer_add_light(ren, &lamp);
    eng_renderer_add_light(ren, &spot);

    /* Large occluder wall on the right & tiny hidden box strictly behind it */
    eng_draw_item_t occ_wall = {
        box_id, 0, eng_mat4_trs(eng_v3(3.0f, 1.5f, -2.0f), eng_quat_identity(), eng_v3(3.0f, 4.0f, 0.5f)),
        {0.8f, 0.2f, 0.2f, 1.0f}, 0.1f, 0.8f, p_world, true, true, NULL, 0
    };
    eng_draw_item_t hidden_box = {
        box_id, 0, eng_mat4_trs(eng_v3(3.2f, 1.5f, -4.0f), eng_quat_identity(), eng_v3(0.3f, 0.3f, 0.3f)),
        {1, 1, 1, 1}, 0.1f, 0.8f, p_world, false, false, NULL, 0
    };
    /* Off-frustum box behind camera */
    eng_draw_item_t behind_cam = {
        box_id, 0, eng_mat4_trs(eng_v3(0.0f, 1.5f, 25.0f), eng_quat_identity(), eng_v3(1, 1, 1)),
        {1, 1, 1, 1}, 0.1f, 0.8f, p_world, false, false, NULL, 0
    };
    /* Giant interior hall mesh in pocket "inside" (visible ONLY through portal!) */
    eng_draw_item_t inside_pillar = {
        box_id, 0, eng_mat4_trs(eng_v3(0.0f, 1.2f, 14.0f), eng_quat_identity(), eng_v3(2.0f, 3.0f, 2.0f)),
        {0.2f, 0.9f, 0.4f, 1.0f}, 0.0f, 0.5f, p_inside, false, false, NULL, 0
    };
    eng_renderer_submit_mesh(ren, &occ_wall);
    eng_renderer_submit_mesh(ren, &hidden_box);
    eng_renderer_submit_mesh(ren, &behind_cam);
    eng_renderer_submit_mesh(ren, &inside_pillar);

    /* 12 instanced cubes spanning LOD0..LOD3 distances */
    const float dists[4] = {-4.0f, -20.0f, -45.0f, -90.0f};
    for (int i = 0; i < 12; i++) {
        float z = dists[i % 4];
        eng_draw_item_t inst = {
            box_id, 0, eng_mat4_trs(eng_v3(-2.5f, 1.5f + (float)(i % 3) * 0.4f, z), eng_quat_identity(), eng_v3(0.4f, 0.4f, 0.4f)),
            {0.9f, 0.8f, 0.3f, 1.0f}, 0.2f, 0.6f, p_world, true, false, NULL, 0
        };
        eng_renderer_submit_mesh(ren, &inst);
    }

    /* Skinned draw item */
    eng_mat4_t bone = eng_mat4_identity();
    eng_draw_item_t skinned = {
        box_id, 0, eng_mat4_trs(eng_v3(-1.2f, 1.0f, -3.5f), eng_quat_identity(), eng_v3(0.5f, 0.5f, 0.5f)),
        {0.4f, 0.7f, 1.0f, 1.0f}, 0.0f, 0.7f, p_world, false, false, &bone, 1, {0, 0, 0}
    };
    eng_renderer_submit_mesh(ren, &skinned);

    /* Opaque HDR emissive + 2 translucent Fresnel crystals (exercises back-to-front cmp_vis_trans) */
    eng_draw_item_t lava_cube = {
        box_id, 0, eng_mat4_trs(eng_v3(-0.6f, 1.1f, -3.0f), eng_quat_identity(), eng_v3(0.4f, 0.4f, 0.4f)),
        {1.0f, 0.3f, 0.05f, 1.0f}, 0.0f, 0.6f, p_world, false, false, NULL, 0, {2.2f, 0.6f, 0.1f}
    };
    eng_draw_item_t crystal_far = {
        box_id, 0, eng_mat4_trs(eng_v3(0.4f, 1.2f, -5.0f), eng_quat_identity(), eng_v3(0.5f, 0.9f, 0.5f)),
        {0.4f, 0.9f, 1.0f, 0.5f}, 0.05f, 0.06f, p_world, false, false, NULL, 0, {0.2f, 0.5f, 0.8f}
    };
    eng_draw_item_t crystal_near = {
        box_id, 0, eng_mat4_trs(eng_v3(0.4f, 1.2f, -3.2f), eng_quat_identity(), eng_v3(0.45f, 0.8f, 0.45f)),
        {0.95f, 0.2f, 0.3f, 0.55f}, 0.05f, 0.07f, p_world, false, false, NULL, 0, {0.6f, 0.1f, 0.15f}
    };
    eng_renderer_submit_mesh(ren, &lava_cube);
    eng_renderer_submit_mesh(ren, &crystal_far);
    eng_renderer_submit_mesh(ren, &crystal_near);

    eng_sprite_item_t sps_fx[3] = {
        {eng_v3(-0.8f, 0.5f, -2.5f), {0.6f, 1.2f}, 0.0f, {0, 0, 1, 1}, {1, 1, 1, 1}, 0, p_world, ENG_SPRITE_BILLBOARD_Y, false},
        {eng_v3(0.0f, 0.9f, -2.8f), {0.4f, 0.4f}, 0.0f, {0, 0, 1, 1}, {1, 0.7f, 0.2f, 0.9f}, 0, p_world, ENG_SPRITE_BILLBOARD_SPHERICAL, true},
        {eng_v3(0.0f, 1.3f, -2.8f), {0.5f, 0.5f}, 0.0f, {0, 0, 1, 1}, {0.3f, 0.3f, 0.35f, 0.45f}, 0, p_world, ENG_SPRITE_BILLBOARD_SPHERICAL, false}
    };
    eng_renderer_submit_sprites(ren, sps_fx, 3);

    eng_renderer_render_frame(ren, sc, portals, &cam, NULL);
    eng_render_stats_t st = eng_renderer_stats(ren);
    assert(st.culled_pocket >= 1);
    assert(st.culled_frustum >= 1);
    assert(st.culled_occluded >= 1);
    assert(st.instanced_draws >= 6);
    assert(st.portal_views >= 1);
    assert(st.lod_counts[0] > 0 && st.lod_counts[1] > 0 && st.lod_counts[2] > 0 && st.lod_counts[3] > 0);

    /* Test 2: Deferred G-Buffer pipeline + Emissive/Crystal Composite + Stereo WebXR + Resize + Hot Reload */
    assert(eng_renderer_resize(ren, 256, 192));
    assert(eng_renderer_reload_shaders(ren));
    eng_renderer_set_pipeline(ren, ENG_PIPELINE_DEFERRED);
    ps1.fog_height = 2.8f;
    eng_renderer_set_retro(ren, &ps1);

    eng_xr_t *xr = eng_xr_create();
    eng_xr_request_session(xr);
    eng_xr_pose_t head = {eng_v3(0, 1.6f, 4.0f), eng_quat_identity(), true};
    eng_xr_eye_t eyes[2];
    memset(eyes, 0, sizeof(eyes));
    for (int e = 0; e < 2; e++) {
        eyes[e].view = eng_mat4_look_at(eng_v3(e == 0 ? -0.03f : 0.03f, 1.6f, 4.0f), eng_v3(0, 1.2f, -3.0f), eng_v3(0, 1, 0));
        eyes[e].proj = eng_mat4_perspective(70.0f * ENG_DEG2RAD, 0.66f, 0.1f, 200.0f);
        eyes[e].viewport[0] = e * 128; eyes[e].viewport[1] = 0; eyes[e].viewport[2] = 128; eyes[e].viewport[3] = 192;
    }
    eng_xr_submit_frame_state(xr, 0, &head, eyes, NULL);

    eng_renderer_begin_frame(ren);
    eng_renderer_add_light(ren, &sun);
    eng_renderer_submit_mesh(ren, &occ_wall);
    eng_renderer_submit_mesh(ren, &inside_pillar);
    eng_renderer_submit_mesh(ren, &lava_cube);
    eng_renderer_submit_mesh(ren, &crystal_far);
    eng_renderer_submit_mesh(ren, &crystal_near);
    eng_renderer_submit_sprites(ren, sps_fx, 3);
    eng_renderer_render_frame(ren, sc, portals, &cam, xr);
    assert(eng_renderer_stats(ren).portal_views >= 2); /* Both left & right XR eyes rendered portal */

    uint8_t *fb = (uint8_t *)malloc(256 * 192 * 4);
    assert(eng_renderer_read_pixels(ren, fb, 256, 192));
    if (verify_real_gl_pixels) {
        uint64_t sum = 0;
        for (int i = 0; i < 256 * 192 * 4; i++) sum += fb[i];
        assert(sum > 0);
    }
    free(fb);

    eng_xr_destroy(xr);
    eng_portal_sys_destroy(portals);
    eng_scene_destroy(sc);
    eng_renderer_destroy(ren);
    eng_asset_cache_destroy(assets);
}

int main(void) {
    eng_vfs_t *vfs = eng_vfs_create();
    assert(eng_vfs_mount(vfs, ENG_SOURCE_DIR, 0, false));
    assert(eng_vfs_mount(vfs, ENG_BINARY_DIR, 10, true));

    test_pockets_and_portals();
    test_assets_voxels_and_sprites(vfs);

    /* Test shader error handling & uniform helpers on mock */
    eng_gl_init_software_mock();
    eng_shader_t sh;
    memset(&sh, 0, sizeof(sh));
    assert(!eng_shader_compile(NULL, vfs, "void main(){}", "void main(){}"));
    assert(eng_shader_compile(&sh, vfs, "#version 330 core\nvoid main(){gl_Position=vec4(0.0);}", "void main(){}"));
    eng_shader_bind(&sh);
    eng_shader_set_int(&sh, "u_a", 1);
    eng_shader_set_float(&sh, "u_b", 2.0f);
    eng_shader_set_v3(&sh, "u_c", eng_v3(1, 2, 3));
    eng_shader_set_v4(&sh, "u_d", (eng_vec4_t){1, 2, 3, 4});
    eng_mat4_t id = eng_mat4_identity();
    eng_shader_set_mat4(&sh, "u_m", &id);
    eng_shader_destroy(&sh);

    /* Run full renderer pipeline against deterministic software mock */
    run_full_render_pipeline_check(vfs, false);

    /* Also run against real OpenGL 3.3 Core context when display/Xvfb is available */
    eng_platform_config_t pcfg = eng_platform_default_config();
    pcfg.width = 256;
    pcfg.height = 192;
    pcfg.headless = false;
    eng_platform_t *plat = eng_platform_create(&pcfg);
    if (plat && !eng_gl()->is_mock) {
        eng_shader_t bad_sh;
        memset(&bad_sh, 0, sizeof(bad_sh));
        assert(!eng_shader_compile(&bad_sh, vfs, "syntax_error_here", "void main(){}"));
        run_full_render_pipeline_check(vfs, true);
    }
    if (plat) eng_platform_destroy(plat);

    eng_vfs_destroy(vfs);
    printf("Phase 3 unit & GL 3.3 pipeline tests passed!\n");
    return 0;
}
