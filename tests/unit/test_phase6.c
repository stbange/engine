#include "engine/engine.h"

#include <SDL3/SDL_timer.h>
#if defined(ENG_HAS_SDL3_NET) && defined(ENG_HAS_BEARSSL)
#include <SDL3_net/SDL_net.h>
#include <bearssl.h>
#endif
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

    /* Multi-listener 3D audio across 2 different pockets (split-screen players in separate spaces!) */
    eng_audio_listener_t l2[2] = {
        { p_out, eng_v3(0.0f, 0.0f, 0.0f), eng_v3(0, 0, 0), eng_quat_identity() },
        { p_in,  eng_v3(-3.0f, 0.0f, 52.0f), eng_v3(0, 0, 0), eng_quat_identity() }
    };
    eng_audio_set_listeners(aud, l2, 2);
    eng_audio_mix_frames(aud, sc, NULL, stereo, 256);
    sum_l = 0.0f; sum_r = 0.0f;
    for (int i = 0; i < 256; i++) { sum_l += fabsf(stereo[i * 2]); sum_r += fabsf(stereo[i * 2 + 1]); }
    assert(sum_r > sum_l && sum_r > 1.0f); /* Listener 2 hears source at +3m on its right even without portals! */

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

    /* Replacing p_world grid with a complete wall across X=4 must block cross-wall routing */
    g_out[6 * 8 + 4] = 0; g_out[7 * 8 + 4] = 0;
    assert(eng_nav_set_grid(nav, p_world, eng_v3(0, 0, 0), 1.0f, 8, 8, g_out));
    assert(eng_ai_find_path(nav, p_world, eng_v3(1.5f, 0.0f, 1.5f),
                            p_world, eng_v3(6.5f, 0.0f, 1.5f), wps, wp_pockets, 32) == 0);

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
    /* 1. Multi-client Loopback reliable scene replication (including pocket_id!) */
    eng_net_peer_t *srv = eng_net_host(ENG_NET_LOOPBACK, NULL, 0);
    eng_net_peer_t *cli = eng_net_create(ENG_NET_LOOPBACK, 0);
    eng_net_peer_t *cli2 = eng_net_create(ENG_NET_LOOPBACK, 0);
    assert(eng_net_is_server(srv) && !eng_net_is_server(cli));
    assert(eng_net_connect_loopback(srv, cli));
    assert(eng_net_connect_loopback(srv, cli2));
    assert(eng_net_client_count(srv) == 2 && eng_net_is_connected(srv) && eng_net_is_connected(cli));
    uint32_t cids[4] = {0};
    assert(eng_net_client_ids(srv, cids, 4) == 2 && cids[0] == 1 && cids[1] == 2);

    /* Drain connect events */
    eng_net_event_t ev;
    uint8_t ev_buf[2048];
    assert(eng_net_poll_event(srv, &ev, ev_buf, sizeof(ev_buf)) && ev.type == ENG_NET_EVT_CONNECT && ev.client_id == 1);
    assert(eng_net_poll_event(srv, &ev, ev_buf, sizeof(ev_buf)) && ev.type == ENG_NET_EVT_CONNECT && ev.client_id == 2);

    eng_scene_t *s_srv = eng_scene_create(64);
    uint16_t p_vault = eng_scene_register_pocket(s_srv, "vault");
    eng_entity_t hero = eng_scene_spawn(s_srv, "net_hero");
    eng_scene_set_pocket(s_srv, hero, p_vault);
    eng_scene_set_local_pos(s_srv, hero, eng_v3(12.0f, 3.5f, -8.0f));
    eng_scene_update_transforms(s_srv);

    assert(eng_net_send_scene_snapshot(srv, s_srv));

    uint8_t buf[2048];
    eng_net_channel_t chan = ENG_CHAN_UNRELIABLE;
    size_t rlen = eng_net_poll(cli, buf, sizeof(buf), &chan);
    assert(rlen > 0 && chan == ENG_CHAN_RELIABLE);
    assert(eng_net_poll(cli2, buf, sizeof(buf), NULL) == rlen);

    /* Targeted send_to + kick disconnect */
    assert(eng_net_send_to(srv, 2, ENG_CHAN_RELIABLE, "ONLY_C2", 7));
    assert(eng_net_poll(cli, ev_buf, sizeof(ev_buf), NULL) == 0);
    assert(eng_net_poll(cli2, ev_buf, sizeof(ev_buf), NULL) == 7);
    assert(eng_net_disconnect_client(srv, 2) && eng_net_client_count(srv) == 1);
    assert(eng_net_poll_event(cli2, &ev, ev_buf, sizeof(ev_buf)) && ev.type == ENG_NET_EVT_DISCONNECT);

    eng_scene_t *s_cli = eng_scene_create(64);
    assert(eng_net_apply_scene_snapshot(s_cli, buf, rlen));
    eng_entity_t c_hero = eng_ecs_find_by_name(eng_scene_ecs(s_cli), "net_hero");
    assert(c_hero != ENG_ENTITY_NULL);
    assert(strcmp(eng_scene_pocket_name(s_cli, eng_scene_get_pocket(s_cli, c_hero)), "vault") == 0);
    assert(fabsf(eng_scene_get_local(s_cli, c_hero)->pos.x - 12.0f) < 1e-4f);

    eng_scene_destroy(s_srv);
    eng_scene_destroy(s_cli);
    eng_net_destroy(cli2);
    eng_net_destroy(srv);
    eng_net_destroy(cli);

    /* 2. Real non-blocking UDP multi-client round-trip via SDL3_net on 127.0.0.1 */
    eng_net_peer_t *u_srv = eng_net_host(ENG_NET_UDP, "127.0.0.1", 0);
    eng_net_peer_t *u_cli = eng_net_create(ENG_NET_UDP, 0);
    if (u_srv && u_cli && eng_net_bound_port(u_srv) > 0) {
        assert(eng_net_connect_remote(u_cli, "127.0.0.1", eng_net_bound_port(u_srv)));
        const char *ping = "PING_UDP";
        assert(eng_net_send(u_cli, ENG_CHAN_RELIABLE, ping, strlen(ping) + 1));
        char recv_msg[64] = {0};
        for (int spin = 0; spin < 2000; spin++) {
            if (eng_net_poll_event(u_srv, &ev, recv_msg, sizeof(recv_msg)) && ev.type == ENG_NET_EVT_MESSAGE) break;
        }
        assert(strcmp(recv_msg, "PING_UDP") == 0 && eng_net_client_count(u_srv) == 1);
        assert(eng_net_send_to(u_srv, ev.client_id, ENG_CHAN_UNRELIABLE, "PONG_UDP", 9));
        char pong[64] = {0};
        for (int spin = 0; spin < 2000; spin++) {
            if (eng_net_poll(u_cli, pong, sizeof(pong), NULL) > 0) break;
        }
        assert(strcmp(pong, "PONG_UDP") == 0);
    }
    eng_net_destroy(u_srv);
    eng_net_destroy(u_cli);

    /* 3. Live RFC 6455 Binary WebSocket Server + 2 Simultaneous Clients over SDL3_net! */
    eng_net_peer_t *ws_srv = eng_net_host(ENG_NET_WEBSOCKET, "127.0.0.1", 0);
    assert(ws_srv != NULL && eng_net_bound_port(ws_srv) > 0);
    char ws_url[64];
    snprintf(ws_url, sizeof(ws_url), "ws://127.0.0.1:%u/", (unsigned)eng_net_bound_port(ws_srv));

    eng_net_peer_t *ws_c1 = eng_net_create(ENG_NET_WEBSOCKET, 0);
    eng_net_peer_t *ws_c2 = eng_net_create(ENG_NET_WEBSOCKET, 0);
    assert(eng_net_connect_remote(ws_c1, ws_url, 0));
    assert(eng_net_connect_remote(ws_c2, ws_url, 0));

    int ws_joins = 0, c1_open = 0, c2_open = 0;
    for (int spin = 0; spin < 4000 && (ws_joins < 2 || !c1_open || !c2_open); spin++) {
        while (eng_net_poll_event(ws_srv, &ev, ev_buf, sizeof(ev_buf))) {
            if (ev.type == ENG_NET_EVT_CONNECT) ws_joins++;
        }
        while (eng_net_poll_event(ws_c1, &ev, ev_buf, sizeof(ev_buf))) {
            if (ev.type == ENG_NET_EVT_CONNECT) c1_open = 1;
        }
        while (eng_net_poll_event(ws_c2, &ev, ev_buf, sizeof(ev_buf))) {
            if (ev.type == ENG_NET_EVT_CONNECT) c2_open = 1;
        }
        SDL_Delay(1);
    }
    assert(ws_joins == 2 && c1_open && c2_open && eng_net_client_count(ws_srv) == 2);

    /* Client 1 sends a large (>126 byte) masked binary frame exercising 16-bit extended WS length */
    char big_msg[260];
    memset(big_msg, 'W', sizeof(big_msg) - 1);
    big_msg[sizeof(big_msg) - 1] = '\0';
    assert(eng_net_send(ws_c1, ENG_CHAN_RELIABLE, big_msg, sizeof(big_msg) - 1));
    bool got_big = false;
    for (int spin = 0; spin < 2000 && !got_big; spin++) {
        if (eng_net_poll_event(ws_srv, &ev, ev_buf, sizeof(ev_buf)) && ev.type == ENG_NET_EVT_MESSAGE) {
            assert(ev.len == sizeof(big_msg) - 1 && ev_buf[0] == 'W' && ev_buf[258] == 'W');
            got_big = true;
        }
        SDL_Delay(1);
    }
    assert(got_big);

    /* Server broadcasts to both WS clients, then kicks client 2 */
    assert(eng_net_send_to(ws_srv, 0, ENG_CHAN_UNRELIABLE, "ALL_WS", 6));
    bool r1 = false, r2 = false;
    for (int spin = 0; spin < 2000 && !(r1 && r2); spin++) {
        if (!r1 && eng_net_poll(ws_c1, ev_buf, sizeof(ev_buf), NULL) == 6 && memcmp(ev_buf, "ALL_WS", 6) == 0) r1 = true;
        if (!r2 && eng_net_poll(ws_c2, ev_buf, sizeof(ev_buf), NULL) == 6 && memcmp(ev_buf, "ALL_WS", 6) == 0) r2 = true;
        SDL_Delay(1);
    }
    assert(r1 && r2);
    assert(eng_net_disconnect_client(ws_srv, 2) && eng_net_client_count(ws_srv) == 1);

    eng_net_destroy(ws_c1);
    eng_net_destroy(ws_c2);
    eng_net_destroy(ws_srv);
}

#if defined(ENG_HAS_SDL3_NET) && defined(ENG_HAS_BEARSSL)
/* Self-signed P-256 test CA + DNS:localhost leaf cert (valid 2020-2049) for offline wss:// testing */
static const char TEST_WSS_CA_PEM[] =
    "-----BEGIN CERTIFICATE-----\n"
    "MIIBbjCCARSgAwIBAgICEAAwCgYIKoZIzj0EAwIwHjEcMBoGA1UEAwwTRW5naW5l\n"
    "IFRlc3QgUm9vdCBDQTAeFw0yMDAxMDEwMDAwMDBaFw00OTEyMzEyMzU5NTlaMB4x\n"
    "HDAaBgNVBAMME0VuZ2luZSBUZXN0IFJvb3QgQ0EwWTATBgcqhkjOPQIBBggqhkjO\n"
    "PQMBBwNCAARjcudou5UTZ34+wdnKxb2uK99nsk+GVrbgMjdqteAWXO2nfpszx7KJ\n"
    "qWoat0REfx9aPwAkD5mhbHiwZIciSk7Eo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4G\n"
    "A1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQU0S5+2Y0JU3A18fyzlgqqQMueHhQwCgYI\n"
    "KoZIzj0EAwIDSAAwRQIgRTfRgsPVTfToej66kBG0u1gim/GfaCQPm+EFAugjHKwC\n"
    "IQCQ5quJcJYm1zuW6cRHtwASVO3BUQQBOrQOlHt9xj4vrw==\n"
    "-----END CERTIFICATE-----\n";

static const unsigned char TEST_WSS_LEAF_DER[] = {
    0x30, 0x82, 0x01, 0xB0, 0x30, 0x82, 0x01, 0x55, 0xA0, 0x03, 0x02, 0x01, 0x02, 0x02, 0x02, 0x10,
    0x01, 0x30, 0x0A, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02, 0x30, 0x1E, 0x31,
    0x1C, 0x30, 0x1A, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0C, 0x13, 0x45, 0x6E, 0x67, 0x69, 0x6E, 0x65,
    0x20, 0x54, 0x65, 0x73, 0x74, 0x20, 0x52, 0x6F, 0x6F, 0x74, 0x20, 0x43, 0x41, 0x30, 0x1E, 0x17,
    0x0D, 0x32, 0x30, 0x30, 0x31, 0x30, 0x31, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x5A, 0x17, 0x0D,
    0x34, 0x39, 0x31, 0x32, 0x33, 0x31, 0x32, 0x33, 0x35, 0x39, 0x35, 0x39, 0x5A, 0x30, 0x14, 0x31,
    0x12, 0x30, 0x10, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0C, 0x09, 0x6C, 0x6F, 0x63, 0x61, 0x6C, 0x68,
    0x6F, 0x73, 0x74, 0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, 0x04, 0xE9, 0xC9,
    0xAA, 0x37, 0xF6, 0xB0, 0x09, 0x5C, 0x51, 0x61, 0x04, 0xA8, 0xAC, 0x3E, 0x45, 0xC6, 0xD3, 0x95,
    0xD1, 0x97, 0x9D, 0x20, 0x15, 0x0D, 0x7C, 0xC6, 0xB0, 0xEB, 0x02, 0x47, 0x6F, 0x8B, 0x71, 0xF2,
    0xC0, 0x54, 0x97, 0x5E, 0x02, 0x20, 0xFA, 0x5B, 0x6E, 0x8B, 0x0A, 0xC8, 0xB3, 0x92, 0x96, 0x24,
    0x1D, 0xAF, 0x57, 0x28, 0x40, 0xF3, 0xAE, 0xE5, 0xB6, 0x25, 0xE6, 0x0D, 0xCD, 0xBC, 0xA3, 0x81,
    0x8C, 0x30, 0x81, 0x89, 0x30, 0x0C, 0x06, 0x03, 0x55, 0x1D, 0x13, 0x01, 0x01, 0xFF, 0x04, 0x02,
    0x30, 0x00, 0x30, 0x0E, 0x06, 0x03, 0x55, 0x1D, 0x0F, 0x01, 0x01, 0xFF, 0x04, 0x04, 0x03, 0x02,
    0x07, 0x80, 0x30, 0x13, 0x06, 0x03, 0x55, 0x1D, 0x25, 0x04, 0x0C, 0x30, 0x0A, 0x06, 0x08, 0x2B,
    0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01, 0x30, 0x14, 0x06, 0x03, 0x55, 0x1D, 0x11, 0x04, 0x0D,
    0x30, 0x0B, 0x82, 0x09, 0x6C, 0x6F, 0x63, 0x61, 0x6C, 0x68, 0x6F, 0x73, 0x74, 0x30, 0x1D, 0x06,
    0x03, 0x55, 0x1D, 0x0E, 0x04, 0x16, 0x04, 0x14, 0xB1, 0xB1, 0x1B, 0xD0, 0xF4, 0x98, 0xD4, 0xB5,
    0x71, 0xBC, 0x63, 0x57, 0x33, 0xA6, 0xDF, 0x9F, 0x6B, 0xA6, 0x57, 0xB6, 0x30, 0x1F, 0x06, 0x03,
    0x55, 0x1D, 0x23, 0x04, 0x18, 0x30, 0x16, 0x80, 0x14, 0xD1, 0x2E, 0x7E, 0xD9, 0x8D, 0x09, 0x53,
    0x70, 0x35, 0xF1, 0xFC, 0xB3, 0x96, 0x0A, 0xAA, 0x40, 0xCB, 0x9E, 0x1E, 0x14, 0x30, 0x0A, 0x06,
    0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02, 0x03, 0x49, 0x00, 0x30, 0x46, 0x02, 0x21,
    0x00, 0xCF, 0xCA, 0x6B, 0x97, 0x91, 0xE1, 0x1B, 0xE6, 0xB9, 0x06, 0xB0, 0xBD, 0xE5, 0xAD, 0x57,
    0xE7, 0xBF, 0x38, 0x0C, 0x31, 0x6B, 0x75, 0x66, 0x5A, 0x11, 0x2F, 0x4D, 0x4C, 0x41, 0xD0, 0x04,
    0x05, 0x02, 0x21, 0x00, 0x90, 0xD8, 0x3A, 0xD1, 0x6E, 0x1D, 0x06, 0xC9, 0x67, 0x78, 0x94, 0xAD,
    0x23, 0x79, 0x3E, 0x73, 0x9A, 0xDD, 0x83, 0x7C, 0x91, 0x06, 0x30, 0xAD, 0x14, 0x2C, 0x74, 0xC2,
    0xD1, 0xBA, 0x5A, 0xC6,
};

static const unsigned char TEST_WSS_LEAF_KEY_X[] = {
    0x28, 0x9A, 0xC9, 0x65, 0x17, 0xA9, 0x66, 0x3F, 0x7C, 0x47, 0x97, 0x82, 0xC1, 0x14, 0xBC, 0x2B,
    0xF7, 0x2A, 0xF3, 0xED, 0xD5, 0x3A, 0x61, 0xB3, 0xFF, 0xDF, 0x33, 0x9E, 0xC5, 0xEF, 0xC9, 0xDD,
};

typedef struct {
    NET_Server *listener;
    NET_StreamSocket *conn;
    br_ssl_server_context sc;
    unsigned char iobuf[BR_SSL_BUFSIZE_BIDI];
    br_x509_certificate chain[1];
    br_ec_private_key sk;
    uint8_t rx[1024];
    size_t rx_len;
    bool upgraded;
    bool got_ping;
} mock_wss_srv_t;

static void mock_wss_reset_conn(mock_wss_srv_t *m) {
    if (m->conn) { NET_DestroyStreamSocket(m->conn); m->conn = NULL; }
    m->rx_len = 0;
    m->upgraded = false;
    m->got_ping = false;
}

static void mock_wss_pump(mock_wss_srv_t *m) {
    if (!m->conn) {
        NET_StreamSocket *ns = NULL;
        if (NET_AcceptClient(m->listener, &ns) && ns) {
            m->conn = ns;
            m->rx_len = 0;
            m->upgraded = false;
            m->got_ping = false;
            br_ssl_server_init_full_ec(&m->sc, m->chain, 1, BR_KEYTYPE_EC, &m->sk);
            br_ssl_engine_set_buffer(&m->sc.eng, m->iobuf, sizeof(m->iobuf), 1);
            br_ssl_server_reset(&m->sc);
        }
        if (!m->conn) return;
    }
    for (int iter = 0; iter < 16; iter++) {
        unsigned st = br_ssl_engine_current_state(&m->sc.eng);
        if (st == BR_SSL_CLOSED) { mock_wss_reset_conn(m); return; }
        bool prog = false;
        if (st & BR_SSL_SENDREC) {
            size_t n = 0;
            unsigned char *b = br_ssl_engine_sendrec_buf(&m->sc.eng, &n);
            if (!NET_WriteToStreamSocket(m->conn, b, (int)n)) { mock_wss_reset_conn(m); return; }
            br_ssl_engine_sendrec_ack(&m->sc.eng, n);
            prog = true;
        }
        if (st & BR_SSL_RECVREC) {
            size_t n = 0;
            unsigned char *b = br_ssl_engine_recvrec_buf(&m->sc.eng, &n);
            int got = NET_ReadFromStreamSocket(m->conn, b, (int)n);
            if (got < 0) { mock_wss_reset_conn(m); return; }
            if (got > 0) { br_ssl_engine_recvrec_ack(&m->sc.eng, (size_t)got); prog = true; }
        }
        if (st & BR_SSL_RECVAPP) {
            size_t n = 0;
            unsigned char *b = br_ssl_engine_recvapp_buf(&m->sc.eng, &n);
            size_t cp = n < (sizeof(m->rx) - 1u - m->rx_len) ? n : (sizeof(m->rx) - 1u - m->rx_len);
            if (cp > 0) { memcpy(m->rx + m->rx_len, b, cp); m->rx_len += cp; m->rx[m->rx_len] = 0; }
            br_ssl_engine_recvapp_ack(&m->sc.eng, n);
            prog = true;
        }
        if (!m->upgraded && m->rx_len > 4) {
            char *hdr_end = strstr((char *)m->rx, "\r\n\r\n");
            if (hdr_end && (br_ssl_engine_current_state(&m->sc.eng) & BR_SSL_SENDAPP)) {
                size_t hlen = (size_t)(hdr_end - (char *)m->rx) + 4u;
                memmove(m->rx, m->rx + hlen, m->rx_len - hlen);
                m->rx_len -= hlen;
                const char *resp = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                                   "Connection: Upgrade\r\nSec-WebSocket-Accept: ok\r\n\r\n";
                size_t alen = 0;
                unsigned char *ab = br_ssl_engine_sendapp_buf(&m->sc.eng, &alen);
                size_t rlen = strlen(resp);
                assert(alen >= rlen);
                memcpy(ab, resp, rlen);
                br_ssl_engine_sendapp_ack(&m->sc.eng, rlen);
                br_ssl_engine_flush(&m->sc.eng, 0);
                m->upgraded = true;
                prog = true;
            }
        } else if (m->upgraded && !m->got_ping && m->rx_len >= 6) {
            size_t plen = (size_t)(m->rx[1] & 0x7Fu);
            if (m->rx_len >= 6u + plen && (br_ssl_engine_current_state(&m->sc.eng) & BR_SSL_SENDAPP)) {
                uint8_t msg[64] = {0};
                for (size_t i = 0; i < plen && i < sizeof(msg) - 1u; i++) msg[i] = m->rx[6u + i] ^ m->rx[2u + (i & 3u)];
                assert(plen == 9u && msg[0] == ENG_CHAN_RELIABLE && memcmp(msg + 1, "PING_WSS", 8) == 0);
                m->got_ping = true;
                uint8_t pong[11] = { 0x82u, 9u, (uint8_t)ENG_CHAN_RELIABLE, 'P','O','N','G','_','W','S','S' };
                size_t alen = 0;
                unsigned char *ab = br_ssl_engine_sendapp_buf(&m->sc.eng, &alen);
                assert(alen >= sizeof(pong));
                memcpy(ab, pong, sizeof(pong));
                br_ssl_engine_sendapp_ack(&m->sc.eng, sizeof(pong));
                br_ssl_engine_flush(&m->sc.eng, 0);
                prog = true;
            }
        }
        if (!prog) break;
    }
}

static void test_net_wss_tls(void) {
    assert(NET_Init());
    NET_Address *laddr = NET_ResolveHostname("localhost");
    assert(laddr != NULL && NET_WaitUntilResolved(laddr, 1000) == NET_SUCCESS);

    mock_wss_srv_t *srv = (mock_wss_srv_t *)calloc(1, sizeof(mock_wss_srv_t));
    assert(srv != NULL);
    srv->chain[0].data = (unsigned char *)(uintptr_t)TEST_WSS_LEAF_DER;
    srv->chain[0].data_len = sizeof(TEST_WSS_LEAF_DER);
    srv->sk.curve = BR_EC_secp256r1;
    srv->sk.x = (unsigned char *)(uintptr_t)TEST_WSS_LEAF_KEY_X;
    srv->sk.xlen = sizeof(TEST_WSS_LEAF_KEY_X);

    uint16_t port = 0;
    for (uint16_t cand = 54321u; cand < 54400u; cand++) {
        srv->listener = NET_CreateServer(laddr, cand, 0);
        if (srv->listener) { port = cand; break; }
    }
    NET_UnrefAddress(laddr);
    assert(srv->listener != NULL && port > 0);

    char wss_url[96];
    snprintf(wss_url, sizeof(wss_url), "wss://localhost:%u/?room=tls", (unsigned)port);

    /* 1. Invalid CA PEM fails closed immediately */
    eng_net_peer_t *bad_ca = eng_net_create(ENG_NET_WEBSOCKET, 0);
    assert(eng_net_set_ca_pem(bad_ca, "NOT A VALID CERTIFICATE"));
    assert(!eng_net_connect_remote(bad_ca, wss_url, 0));
    eng_net_destroy(bad_ca);

    /* 2. Verified TLS 1.2 wss:// handshake + encrypted binary frame round-trip */
    eng_net_peer_t *cli = eng_net_create(ENG_NET_WEBSOCKET, 0);
    assert(eng_net_set_ca_pem(cli, TEST_WSS_CA_PEM));
    assert(eng_net_connect_remote(cli, wss_url, 0));

    eng_net_event_t ev;
    uint8_t buf[256];
    bool connected = false;
    for (int spin = 0; spin < 4000 && !connected; spin++) {
        mock_wss_pump(srv);
        while (eng_net_poll_event(cli, &ev, buf, sizeof(buf))) {
            assert(ev.type != ENG_NET_EVT_DISCONNECT);
            if (ev.type == ENG_NET_EVT_CONNECT) connected = true;
        }
        SDL_Delay(1);
    }
    assert(connected && eng_net_is_connected(cli));

    assert(eng_net_send(cli, ENG_CHAN_RELIABLE, "PING_WSS", 8));
    bool got_pong = false;
    for (int spin = 0; spin < 4000 && !got_pong; spin++) {
        mock_wss_pump(srv);
        while (eng_net_poll_event(cli, &ev, buf, sizeof(buf))) {
            if (ev.type == ENG_NET_EVT_MESSAGE && ev.len == 8 && memcmp(buf, "PONG_WSS", 8) == 0) got_pong = true;
        }
        SDL_Delay(1);
    }
    assert(got_pong && srv->got_ping);
    eng_net_destroy(cli);
    mock_wss_reset_conn(srv);

    /* 3. Untrusted cert against real OS root CA store MUST fail X.509 verification and disconnect */
    eng_net_peer_t *untrusted = eng_net_create(ENG_NET_WEBSOCKET, 0);
    assert(eng_net_connect_remote(untrusted, wss_url, 0));
    bool rejected = false;
    for (int spin = 0; spin < 4000 && !rejected; spin++) {
        mock_wss_pump(srv);
        while (eng_net_poll_event(untrusted, &ev, buf, sizeof(buf))) {
            assert(ev.type != ENG_NET_EVT_CONNECT);
            if (ev.type == ENG_NET_EVT_DISCONNECT) rejected = true;
        }
        SDL_Delay(1);
    }
    assert(rejected && !eng_net_is_connected(untrusted));
    eng_net_destroy(untrusted);

    mock_wss_reset_conn(srv);
    NET_DestroyServer(srv->listener);
    free(srv);
    NET_Quit();
}
#endif

int main(void) {
    eng_vfs_t *vfs = eng_vfs_create();
    assert(eng_vfs_mount(vfs, ENG_SOURCE_DIR, 0, false));
    assert(eng_vfs_mount(vfs, ENG_BINARY_DIR, 10, true));

    test_audio_spatial_synth_wav_and_portals(vfs);
    test_ai_portal_astar_and_bt();
    test_net_loopback_udp_and_replication();
#if defined(ENG_HAS_SDL3_NET) && defined(ENG_HAS_BEARSSL)
    test_net_wss_tls();
#endif

    eng_vfs_destroy(vfs);
    printf("Phase 6 unit tests passed!\n");
    return 0;
}
