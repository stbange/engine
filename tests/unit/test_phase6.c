#include "engine/engine.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void wr_le16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)(v & 0xFFu); p[1] = (uint8_t)(v >> 8); }
static void wr_le32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFFu); p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu); p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static void test_audio_spatial_synth_wav_and_portals(eng_vfs_t *vfs) {
    eng_audio_t *aud = eng_audio_create(true);
    assert(aud != NULL);

    eng_audio_set_bus_gain(aud, ENG_BUS_SFX, 0.9f);
    assert(fabsf(eng_audio_get_bus_gain(aud, ENG_BUS_SFX) - 0.9f) < 1e-4f);

    /* Synthesize all 5 retro waveforms */
    uint32_t clip_sq = 0;
    for (int w = 0; w <= (int)ENG_WAVE_NOISE; w++) {
        eng_synth_desc_t sd = eng_synth_default_desc((eng_synth_wave_t)w, 440.0f, 0.15f);
        sd.freq_end_hz = 880.0f;
        uint32_t cid = eng_audio_synth_retro(aud, &sd);
        assert(cid != 0);
        if (w == 0) clip_sq = cid;
    }

    /* Build valid minimal 16-bit PCM RIFF WAV in memory + load via VFS */
    uint8_t wav[44 + 200];
    memset(wav, 0, sizeof(wav));
    memcpy(wav + 0, "RIFF", 4); wr_le32(wav + 4, 36 + 200);
    memcpy(wav + 8, "WAVEfmt ", 8); wr_le32(wav + 16, 16);
    wr_le16(wav + 20, 1); wr_le16(wav + 22, 1); wr_le32(wav + 24, 24000);
    wr_le32(wav + 28, 48000); wr_le16(wav + 32, 2); wr_le16(wav + 34, 16);
    memcpy(wav + 36, "data", 4); wr_le32(wav + 40, 200);
    for (int i = 0; i < 100; i++) wr_le16(wav + 44 + i * 2, (uint16_t)(int16_t)((i % 20 < 10) ? 12000 : -12000));
    assert(eng_vfs_write_all(vfs, "beep.wav", wav, sizeof(wav)));
    uint32_t wav_id = eng_audio_load_vfs(aud, vfs, "beep.wav");
    assert(wav_id != 0);
    /* Invalid ogg fails cleanly without crash */
    assert(eng_audio_load_ogg_mem(aud, wav, sizeof(wav)) == 0);

    /* 1. Direct 3D spatialization: source 10m to the right (+X) pans right > left */
    eng_audio_set_listener(aud, 0, eng_v3(0, 0, 0), eng_v3(0, 0, 0), eng_quat_identity());
    eng_voice_desc_t vd = eng_voice_default_desc(clip_sq);
    vd.spatial_3d = true;
    vd.loop = true;
    vd.pocket_id = 0;
    vd.pos = eng_v3(10.0f, 0.0f, 0.0f);
    vd.vel = eng_v3(-20.0f, 0.0f, 0.0f);
    uint32_t vid = eng_audio_play(aud, &vd);
    assert(vid != 0);

    float stereo[512 * 2];
    eng_audio_mix_frames(aud, NULL, NULL, stereo, 512);
    float sum_l = 0.0f, sum_r = 0.0f;
    for (int i = 0; i < 512; i++) {
        sum_l += fabsf(stereo[i * 2 + 0]);
        sum_r += fabsf(stereo[i * 2 + 1]);
    }
    assert(sum_r > sum_l * 3.0f && sum_r > 1.0f);
    eng_audio_stop(aud, vid);

    /* 2. Cross-portal doorway routing vs isolated pocket silence */
    eng_scene_t *sc = eng_scene_create(32);
    uint16_t p_out = eng_scene_register_pocket(sc, "world");
    uint16_t p_in  = eng_scene_register_pocket(sc, "room");
    eng_entity_t de = eng_scene_spawn(sc, "de");
    eng_entity_t di = eng_scene_spawn(sc, "di");
    eng_scene_set_pocket(sc, de, p_out);
    eng_scene_set_pocket(sc, di, p_in);
    eng_scene_set_local_pos(sc, de, eng_v3(-4.0f, 0.0f, -2.0f)); /* Doorway on the LEFT */
    eng_scene_set_local_pos(sc, di, eng_v3(0.0f, 0.0f, 50.0f));
    eng_scene_update_transforms(sc);

    vd.pocket_id = p_in;
    vd.pos = eng_v3(0.0f, 0.0f, 52.0f);
    uint32_t vid_in = eng_audio_play(aud, &vd);

    /* Without portal link: completely silent in exterior pocket! */
    eng_audio_mix_frames(aud, sc, NULL, stereo, 256);
    float unlinked_energy = 0.0f;
    for (int i = 0; i < 512; i++) unlinked_energy += fabsf(stereo[i]);
    assert(unlinked_energy < 1e-6f);

    /* With open portal link on the LEFT (-4, 0, -2): sound emerges from left doorway! */
    eng_portal_sys_t *ps = eng_portal_sys_create();
    eng_portal_link(ps, sc, de, di, 1.5f, 2.2f, 1.0f, true, true);
    eng_audio_mix_frames(aud, sc, ps, stereo, 256);
    sum_l = 0.0f; sum_r = 0.0f;
    for (int i = 0; i < 256; i++) {
        sum_l += fabsf(stereo[i * 2 + 0]);
        sum_r += fabsf(stereo[i * 2 + 1]);
    }
    assert(sum_l > sum_r && sum_l > 1.0f);

    eng_audio_update(aud, sc, ps, 1.0f / 60.0f);
    eng_audio_stop(aud, vid_in);
    eng_portal_sys_destroy(ps);
    eng_scene_destroy(sc);
    eng_audio_destroy(aud);
}

static eng_bt_status_t bt_check_ammo(eng_blackboard_t *bb, float dt, void *ud) {
    (void)dt; (void)ud;
    return eng_bb_get(bb, "ammo", 0.0f) > 0.0f ? ENG_BT_SUCCESS : ENG_BT_FAILURE;
}

static eng_bt_status_t bt_fire(eng_blackboard_t *bb, float dt, void *ud) {
    (void)dt; (void)ud;
    eng_bb_set(bb, "ammo", eng_bb_get(bb, "ammo", 0.0f) - 1.0f);
    eng_bb_set(bb, "fired", 1.0f);
    return ENG_BT_SUCCESS;
}

static eng_bt_status_t bt_reload(eng_blackboard_t *bb, float dt, void *ud) {
    (void)dt; (void)ud;
    eng_bb_set(bb, "ammo", 5.0f);
    return ENG_BT_SUCCESS;
}

static void test_ai_portal_astar_and_bt(void) {
    eng_scene_t *sc = eng_scene_create(32);
    uint16_t p_world = eng_scene_register_pocket(sc, "world");
    uint16_t p_ship  = eng_scene_register_pocket(sc, "ship_cabin");

    eng_entity_t hatch_out = eng_scene_spawn(sc, "hatch_out");
    eng_entity_t hatch_in  = eng_scene_spawn(sc, "hatch_in");
    eng_scene_set_pocket(sc, hatch_out, p_world);
    eng_scene_set_pocket(sc, hatch_in, p_ship);
    eng_scene_set_local_pos(sc, hatch_out, eng_v3(7.5f, 0.0f, 4.5f));
    eng_scene_set_local_pos(sc, hatch_in, eng_v3(1.5f, 0.0f, 1.5f));
    eng_scene_update_transforms(sc);

    eng_portal_sys_t *ps = eng_portal_sys_create();
    eng_portal_link(ps, sc, hatch_out, hatch_in, 1.4f, 2.2f, 1.0f, true, true);

    /* 8x8 exterior grid with a central vertical wall blocking direct X=4 except at Z=7 */
    uint8_t g_out[64];
    memset(g_out, 1, sizeof(g_out));
    for (int z = 0; z < 6; z++) g_out[z * 8 + 4] = 0;

    uint8_t g_in[64];
    memset(g_in, 1, sizeof(g_in));

    eng_nav_t *nav = eng_nav_create();
    assert(eng_nav_set_grid(nav, p_world, eng_v3(0, 0, 0), 1.0f, 8, 8, g_out));
    assert(eng_nav_set_grid(nav, p_ship, eng_v3(0, 0, 0), 1.0f, 8, 8, g_in));
    assert(eng_nav_sync_portals(nav, sc, ps) == 2);

    /* Cross-pocket pathfinding around wall in "world" AND through hatch into "ship_cabin"! */
    eng_vec3_t wps[32];
    uint16_t wp_pockets[32];
    size_t wn = eng_ai_find_path(nav, p_world, eng_v3(1.5f, 0.0f, 1.5f),
                                 p_ship, eng_v3(6.5f, 0.0f, 6.5f), wps, wp_pockets, 32);
    assert(wn >= 3);
    assert(wp_pockets[0] == p_world && wp_pockets[wn - 1] == p_ship);
    assert(eng_v3_len(eng_v3_sub(wps[wn - 1], eng_v3(6.5f, 0.0f, 6.5f))) < 0.01f);

    eng_nav_destroy(nav);
    eng_portal_sys_destroy(ps);
    eng_scene_destroy(sc);

    /* Behavior Tree: Selector( Sequence(CheckAmmo, Fire), Sequence(Inverter(CheckAmmo), Reload) ) */
    eng_bt_t *bt = eng_bt_create();
    int root = eng_bt_add_composite(bt, -1, ENG_BT_SELECTOR);
    int seq_shoot = eng_bt_add_composite(bt, root, ENG_BT_SEQUENCE);
    eng_bt_add_action(bt, seq_shoot, bt_check_ammo, NULL);
    eng_bt_add_action(bt, seq_shoot, bt_fire, NULL);

    int seq_rel = eng_bt_add_composite(bt, root, ENG_BT_SEQUENCE);
    int inv = eng_bt_add_composite(bt, seq_rel, ENG_BT_INVERTER);
    eng_bt_add_action(bt, inv, bt_check_ammo, NULL);
    eng_bt_add_action(bt, seq_rel, bt_reload, NULL);

    eng_blackboard_t bb;
    eng_bb_init(&bb);
    eng_bb_set(&bb, "ammo", 0.0f);
    assert(eng_bt_tick(bt, root, &bb, 0.016f) == ENG_BT_SUCCESS);
    assert(eng_bb_get(&bb, "ammo", 0.0f) == 5.0f);
    assert(eng_bt_tick(bt, root, &bb, 0.016f) == ENG_BT_SUCCESS);
    assert(eng_bb_get(&bb, "fired", 0.0f) == 1.0f && eng_bb_get(&bb, "ammo", 0.0f) == 4.0f);
    eng_bt_destroy(bt);
}

static void test_net_loopback_udp_and_replication(void) {
    /* 1. Loopback reliable scene replication (including pocket_id!) */
    eng_net_peer_t *srv = eng_net_create(ENG_NET_LOOPBACK, 0);
    eng_net_peer_t *cli = eng_net_create(ENG_NET_LOOPBACK, 0);
    assert(eng_net_connect_loopback(srv, cli));

    eng_scene_t *s_srv = eng_scene_create(64);
    uint16_t p_vault = eng_scene_register_pocket(s_srv, "vault");
    eng_entity_t hero = eng_scene_spawn(s_srv, "net_hero");
    eng_scene_set_pocket(s_srv, hero, p_vault);
    eng_scene_set_local_pos(s_srv, hero, eng_v3(12.0f, 3.5f, -8.0f));
    eng_scene_update_transforms(s_srv);

    assert(eng_net_send_scene_snapshot(srv, s_srv));

    uint8_t buf[1400];
    eng_net_channel_t chan = ENG_CHAN_UNRELIABLE;
    size_t rlen = eng_net_poll(cli, buf, sizeof(buf), &chan);
    assert(rlen > 0 && chan == ENG_CHAN_RELIABLE);

    /* Poll server to process client's automatic ACK */
    uint8_t dummy[64];
    assert(eng_net_poll(srv, dummy, sizeof(dummy), NULL) == 0);

    eng_scene_t *s_cli = eng_scene_create(64);
    assert(eng_net_apply_scene_snapshot(s_cli, buf, rlen));
    eng_entity_t c_hero = eng_ecs_find_by_name(eng_scene_ecs(s_cli), "net_hero");
    assert(c_hero != ENG_ENTITY_NULL);
    assert(strcmp(eng_scene_pocket_name(s_cli, eng_scene_get_pocket(s_cli, c_hero)), "vault") == 0);
    assert(fabsf(eng_scene_get_local(s_cli, c_hero)->pos.x - 12.0f) < 1e-4f);

    eng_scene_destroy(s_srv);
    eng_scene_destroy(s_cli);
    eng_net_destroy(srv);
    eng_net_destroy(cli);

    /* 2. Real non-blocking UDP socket round-trip on 127.0.0.1 ephemeral ports */
    eng_net_peer_t *u_srv = eng_net_create(ENG_NET_UDP, 0);
    eng_net_peer_t *u_cli = eng_net_create(ENG_NET_UDP, 0);
    if (u_srv && u_cli && eng_net_bound_port(u_srv) > 0) {
        assert(eng_net_connect_remote(u_cli, "127.0.0.1", eng_net_bound_port(u_srv)));
        const char *ping = "PING_UDP";
        assert(eng_net_send(u_cli, ENG_CHAN_UNRELIABLE, ping, strlen(ping) + 1));
        char recv_msg[64] = {0};
        for (int spin = 0; spin < 1000; spin++) {
            if (eng_net_poll(u_srv, recv_msg, sizeof(recv_msg), NULL) > 0) break;
        }
        assert(strcmp(recv_msg, "PING_UDP") == 0);
    }
    eng_net_destroy(u_srv);
    eng_net_destroy(u_cli);
}

int main(void) {
    eng_vfs_t *vfs = eng_vfs_create();
    assert(eng_vfs_mount(vfs, ENG_SOURCE_DIR, 0, false));
    assert(eng_vfs_mount(vfs, ENG_BINARY_DIR, 10, true));

    test_audio_spatial_synth_wav_and_portals(vfs);
    test_ai_portal_astar_and_bt();
    test_net_loopback_udp_and_replication();

    eng_vfs_destroy(vfs);
    printf("Phase 6 unit tests passed!\n");
    return 0;
}
