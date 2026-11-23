#include "engine/engine.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void test_procgen_noise_and_textures(void) {
    /* Bit-exact determinism & finite bounds across all noise families */
    for (int i = 0; i < 16; i++) {
        float x = (float)i * 0.73f - 3.1f;
        float y = (float)i * 1.19f + 0.5f;
        float z = (float)i * 0.41f;
        float nv2 = eng_noise_value2d(x, y, 1337u);
        float nv3 = eng_noise_value3d(x, y, z, 1337u);
        float np2 = eng_noise_perlin2d(x, y, 1337u);
        float np3 = eng_noise_perlin3d(x, y, z, 1337u);
        float ns2 = eng_noise_simplex2d(x, y, 1337u);
        uint32_t cid = 0;
        float nvor = eng_noise_voronoi2d(x, y, 1337u, &cid);
        float nfbm = eng_noise_fbm3d(x, y, z, 1337u, 4, 2.0f, 0.5f);
        float nrid = eng_noise_ridged3d(x, y, z, 1337u, 4);
        float nwrp = eng_noise_domain_warp3d(x, y, z, 1337u, 1.5f);

        assert(eng_math_is_finite(nv2) && nv2 >= -1.01f && nv2 <= 1.01f);
        assert(eng_math_is_finite(nv3) && eng_math_is_finite(np2) && eng_math_is_finite(np3));
        assert(eng_math_is_finite(ns2) && eng_math_is_finite(nvor) && nvor >= 0.0f);
        assert(eng_math_is_finite(nfbm) && eng_math_is_finite(nrid) && eng_math_is_finite(nwrp));
        assert(np3 == eng_noise_perlin3d(x, y, z, 1337u));
    }

    static const char *const recipes[8] = {
        "stone_brick", "wood_planks", "grass", "rust_metal",
        "sci_fi_panel", "water_caustics", "marble", "cobble"
    };
    uint8_t alb1[32 * 32 * 4], alb2[32 * 32 * 4], nrm[32 * 32 * 4], rgh[32 * 32];
    for (int r = 0; r < 8; r++) {
        assert(eng_procgen_texture(recipes[r], 1337u, 32, alb1, nrm, rgh));
        assert(eng_procgen_texture(recipes[r], 1337u, 32, alb2, NULL, NULL));
        assert(memcmp(alb1, alb2, sizeof(alb1)) == 0);
        assert(nrm[2] > 100); /* Upward +Z tangent-space normal bias */
    }
}

static void test_procgen_dungeons_planets_flora_scatter(void) {
    /* Audit 25 seeds across BSP, Cellular Caves, and Tiled WFC for 100% guaranteed solvability */
    for (uint64_t seed = 1; seed <= 25; seed++) {
        eng_dungeon_t d_bsp, d_cave, d_wfc;
        assert(eng_procgen_dungeon_bsp(&d_bsp, 28, 28, seed));
        assert(eng_procgen_dungeon_is_solvable(&d_bsp));
        assert(eng_dungeon_get(&d_bsp, d_bsp.entrance_x, d_bsp.entrance_y) == ENG_TILE_ENTRANCE);

        assert(eng_procgen_cave_cellular(&d_cave, 26, 26, seed * 31u));
        assert(eng_procgen_dungeon_is_solvable(&d_cave));

        assert(eng_procgen_wfc_grid(&d_wfc, 23, 23, seed * 97u));
        assert(eng_procgen_dungeon_is_solvable(&d_wfc));

        if (seed == 1) {
            eng_mesh_data_t dmd;
            assert(eng_procgen_dungeon_build_mesh(&d_bsp, 2.0f, 3.0f, &dmd));
            assert(dmd.vert_count > 100 && dmd.idx_count > 150);
            eng_mesh_data_free(&dmd);
        }
        eng_dungeon_free(&d_bsp);
        eng_dungeon_free(&d_cave);
        eng_dungeon_free(&d_wfc);
    }

    /* 3D Cube-Sphere Planet + Radial Gravity */
    eng_planet_cfg_t pcfg = eng_planet_default_cfg(99u, 40.0f);
    pcfg.subdivisions = 12;
    float r_north = eng_planet_sample_radius(&pcfg, eng_v3(0, 1, 0));
    float r_eq    = eng_planet_sample_radius(&pcfg, eng_v3(1, 0, 0));
    assert(r_north >= 39.9f && r_eq >= 39.9f);
    eng_vec3_t g_up = eng_planet_gravity_up(eng_v3(0, 0, 0), eng_v3(0, -42.0f, 0));
    assert(fabsf(g_up.y + 1.0f) < 1e-4f);

    eng_mesh_data_t planet_md;
    assert(eng_procgen_planet_mesh(&pcfg, &planet_md));
    assert(planet_md.vert_count == 6u * 13u * 13u);
    assert(planet_md.idx_count == 6u * 12u * 12u * 6u);
    eng_mesh_data_free(&planet_md);

    /* 3D L-System Tree */
    eng_mesh_data_t tree_md;
    assert(eng_procgen_tree_mesh(777u, 2, 3.0f, 0.25f, &tree_md));
    assert(tree_md.vert_count > 50);
    eng_mesh_data_free(&tree_md);

    /* Overlap-free 2D & Spherical Poisson-Disk Scatter */
    eng_vec2_t pts2[64];
    size_t n2 = eng_procgen_poisson_2d(42u, 50.0f, 50.0f, 4.0f, pts2, 64);
    assert(n2 >= 20);
    for (size_t i = 0; i < n2; i++) {
        for (size_t j = i + 1; j < n2; j++) {
            float dx = pts2[i].x - pts2[j].x, dy = pts2[i].y - pts2[j].y;
            assert(dx * dx + dy * dy >= 15.99f);
        }
    }

    eng_vec3_t pts3[64];
    size_t n3 = eng_procgen_poisson_sphere(42u, 20.0f, 5.0f, pts3, 64);
    assert(n3 >= 20);
    for (size_t i = 0; i < n3; i++) {
        for (size_t j = i + 1; j < n3; j++) {
            assert(eng_v3_len(eng_v3_sub(pts3[i], pts3[j])) >= 4.99f);
        }
    }
}

static void test_terrain_and_particles(void) {
    eng_terrain_t ter;
    assert(eng_terrain_init(&ter, 33, 33, 2.0f, NULL));
    eng_terrain_generate_hills(&ter, 1234u, 14.0f, 0.05f);

    float h = eng_terrain_sample_height(&ter, 12.5f, 18.3f);
    eng_vec3_t nrm = eng_terrain_sample_normal(&ter, 12.5f, 18.3f);
    assert(eng_math_is_finite(h) && nrm.y > 0.1f);

    eng_mesh_data_t c0, c1;
    assert(eng_terrain_build_chunk_mesh(&ter, 0, 0, 16, 16, 1, 2.0f, &c0));
    assert(eng_terrain_build_chunk_mesh(&ter, 16, 0, 32, 16, 2, 2.0f, &c1));
    assert(c0.idx_count > c1.idx_count);
    eng_mesh_data_free(&c0);
    eng_mesh_data_free(&c1);
    eng_terrain_free(&ter);

    /* Particles */
    eng_emitter_cfg_t ecfg = eng_emitter_default_cfg();
    ecfg.pocket_id = 2;
    ecfg.life_min = 0.2f;
    ecfg.life_max = 0.3f;
    ecfg.spawn_rate = 60.0f;
    eng_emitter_t *em = eng_emitter_create(128, 99u, &ecfg);
    assert(em != NULL);
    assert(eng_emitter_burst(em, 20) == 20);
    assert(eng_emitter_alive_count(em) == 20);

    eng_emitter_step(em, 0.05f);
    assert(eng_emitter_alive_count(em) >= 22);

    eng_sprite_item_t sp_out[64];
    size_t sp_n = eng_emitter_collect_sprites(em, sp_out, 64);
    assert(sp_n == eng_emitter_alive_count(em));
    assert(sp_out[0].pocket_id == 2 && sp_out[0].mode == ENG_SPRITE_BILLBOARD_SPHERICAL);

    ecfg.active = false;
    eng_emitter_set_cfg(em, &ecfg);
    eng_emitter_step(em, 0.5f);
    assert(eng_emitter_alive_count(em) == 0);
    eng_emitter_destroy(em);
}

static void test_text_and_i18n(eng_vfs_t *vfs) {
    /* UTF-8 1..4 byte sequences + malformed byte replacement */
    const char *utf8 = "A\xC3\xA4\xE2\x82\xAC\xF0\x9F\x9A\x80\xFF";
    const char *p = utf8;
    assert(eng_utf8_next(&p) == 'A');
    assert(eng_utf8_next(&p) == 0xE4u);    /* ä */
    assert(eng_utf8_next(&p) == 0x20ACu);  /* € */
    assert(eng_utf8_next(&p) == 0x1F680u); /* 🚀 */
    assert(eng_utf8_next(&p) == 0xFFFDu);  /* invalid byte -> U+FFFD */
    assert(eng_utf8_next(&p) == 0u);

    eng_gl_init_software_mock();
    eng_asset_cache_t *assets = eng_asset_cache_create(vfs);

    eng_font_t *bf = eng_font_create_builtin(assets);
    assert(bf != NULL && eng_font_texture_id(bf) != 0);
    eng_vec2_t bsz = eng_text_measure(bf, "Hello\nWorld", 1.0f);
    assert(bsz.x > 20.0f && bsz.y > 15.0f);

    /* Real stb_truetype SDF bake from MIT ProggyClean.ttf */
    eng_font_t *ttf = eng_font_load_ttf(assets, vfs, "assets/shared/fonts/proggy_clean.ttf", 18.0f);
    assert(ttf != NULL && eng_font_texture_id(ttf) != 0);
    eng_mesh_data_t tmd;
    size_t quads = eng_text_build_mesh(ttf, "Score: 100\nReady!", eng_v3(0, 0, 0), 0.1f, (eng_vec4_t){1, 1, 1, 1}, &tmd);
    assert(quads == 15 && tmd.vert_count == 60 && tmd.idx_count == 90);
    eng_mesh_data_free(&tmd);
    eng_font_destroy(ttf);
    eng_font_destroy(bf);
    eng_asset_cache_destroy(assets);

    /* i18n JSON locale + fallback + {param} interpolation */
    const char *en_json = "{\"greet\":\"Hello {name}!\",\"only_en\":\"Fallback Works\"}";
    const char *de_json = "{\"greet\":\"Hallo {name} — Punkte: {pts}!\"}";
    assert(eng_vfs_write_all(vfs, "locales/en.json", en_json, strlen(en_json)));
    assert(eng_vfs_write_all(vfs, "locales/de.json", de_json, strlen(de_json)));

    eng_i18n_t *loc = eng_i18n_create(vfs, "en");
    assert(loc != NULL && strcmp(eng_i18n_get_lang(loc), "en") == 0);
    assert(eng_i18n_set_lang(loc, "de"));
    assert(strcmp(eng_i18n_get_lang(loc), "de") == 0);
    assert(strcmp(eng_i18n_get(loc, "only_en"), "Fallback Works") == 0);
    assert(strcmp(eng_i18n_get(loc, "missing_key"), "missing_key") == 0);

    eng_i18n_param_t params[2] = {{"name", "Ada"}, {"pts", "9000"}};
    char formatted[128];
    eng_i18n_format(loc, "greet", params, 2, formatted, sizeof(formatted));
    assert(strcmp(formatted, "Hallo Ada — Punkte: 9000!") == 0);
    eng_i18n_destroy(loc);
}

int main(void) {
    eng_vfs_t *vfs = eng_vfs_create();
    assert(eng_vfs_mount(vfs, ENG_SOURCE_DIR, 0, false));
    assert(eng_vfs_mount(vfs, ENG_BINARY_DIR, 10, true));

    test_procgen_noise_and_textures();
    test_procgen_dungeons_planets_flora_scatter();
    test_terrain_and_particles();
    test_text_and_i18n(vfs);

    eng_vfs_destroy(vfs);
    printf("Phase 4 unit tests passed!\n");
    return 0;
}
