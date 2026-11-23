#if !defined(_WIN32) && !defined(_XOPEN_SOURCE)
#define _XOPEN_SOURCE 700
#endif

#include "engine/eng_net.h"
#include "engine/eng_serde.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#elif defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#define ENG_PKT_MAGIC 0x4E45u
#define ENG_MAX_PKT_SIZE 1400
#define ENG_LOOP_QUEUE_CAP 64

typedef struct {
    uint8_t bytes[ENG_MAX_PKT_SIZE];
    size_t len;
} raw_pkt_t;

typedef struct {
    bool active;
    uint16_t seq;
    uint8_t pkt[ENG_MAX_PKT_SIZE];
    size_t len;
} unacked_pkt_t;

struct eng_net_peer_s {
    eng_net_transport_t transport;
    uint16_t local_port;
    int sock_fd;
#if !defined(__EMSCRIPTEN__) && !defined(_WIN32)
    struct sockaddr_in remote_addr;
    bool has_remote;
#endif
    eng_net_peer_t *loop_partner;
    raw_pkt_t inbox[ENG_LOOP_QUEUE_CAP];
    size_t inbox_head;
    size_t inbox_count;

    uint16_t next_seq;
    uint16_t last_recv_seq;
    uint16_t last_unrel_seq;
    bool has_unrel_seq;
    unacked_pkt_t pending[16];
};

static void wr_u16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)(v & 0xFFu); p[1] = (uint8_t)(v >> 8); }
static uint16_t rd_u16(const uint8_t *p) { return (uint16_t)p[0] | (uint16_t)((uint16_t)p[1] << 8); }

eng_net_peer_t *eng_net_create(eng_net_transport_t transport, uint16_t local_port) {
    eng_net_peer_t *p = (eng_net_peer_t *)calloc(1, sizeof(eng_net_peer_t));
    if (!p) return NULL;
    p->transport = transport;
    p->sock_fd = -1;
    p->next_seq = 1u;

#if !defined(__EMSCRIPTEN__) && !defined(_WIN32)
    if (transport == ENG_NET_UDP) {
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        if (fd < 0) { free(p); return NULL; }
        int fl = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = htons(local_port);
        if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(fd);
            free(p);
            return NULL;
        }
        socklen_t alen = sizeof(addr);
        if (getsockname(fd, (struct sockaddr *)&addr, &alen) == 0) {
            p->local_port = ntohs(addr.sin_port);
        }
        p->sock_fd = fd;
    }
#else
    (void)local_port;
#endif
    return p;
}

void eng_net_destroy(eng_net_peer_t *peer) {
    if (!peer) return;
    if (peer->loop_partner && peer->loop_partner->loop_partner == peer) {
        peer->loop_partner->loop_partner = NULL;
    }
#if !defined(__EMSCRIPTEN__) && !defined(_WIN32)
    if (peer->sock_fd >= 0) close(peer->sock_fd);
#endif
    free(peer);
}

uint16_t eng_net_bound_port(const eng_net_peer_t *peer) {
    return peer ? peer->local_port : 0;
}

bool eng_net_connect_loopback(eng_net_peer_t *a, eng_net_peer_t *b) {
    if (!a || !b || a == b) return false;
    a->loop_partner = b;
    b->loop_partner = a;
    return true;
}

bool eng_net_connect_remote(eng_net_peer_t *peer, const char *host_or_url, uint16_t remote_port) {
    if (!peer || !host_or_url) return false;
#ifdef __EMSCRIPTEN__
    if (peer->transport == ENG_NET_WEBSOCKET) {
        char js[256];
        snprintf(js, sizeof(js), "Module._engWsUrl = '%s';", host_or_url);
        emscripten_run_script(js);
        return true;
    }
    (void)remote_port;
    return false;
#elif !defined(_WIN32)
    if (peer->transport == ENG_NET_UDP && peer->sock_fd >= 0) {
        memset(&peer->remote_addr, 0, sizeof(peer->remote_addr));
        peer->remote_addr.sin_family = AF_INET;
        peer->remote_addr.sin_port = htons(remote_port);
        if (inet_pton(AF_INET, host_or_url, &peer->remote_addr.sin_addr) != 1) return false;
        peer->has_remote = true;
        return true;
    }
    return peer->transport == ENG_NET_WEBSOCKET;
#else
    (void)remote_port;
    return false;
#endif
}

static bool transmit_wire(eng_net_peer_t *peer, const uint8_t *pkt, size_t pkt_len) {
    if (peer->loop_partner) {
        eng_net_peer_t *dst = peer->loop_partner;
        if (dst->inbox_count >= ENG_LOOP_QUEUE_CAP) return false;
        size_t slot = (dst->inbox_head + dst->inbox_count) % ENG_LOOP_QUEUE_CAP;
        memcpy(dst->inbox[slot].bytes, pkt, pkt_len);
        dst->inbox[slot].len = pkt_len;
        dst->inbox_count++;
        return true;
    }
#if !defined(__EMSCRIPTEN__) && !defined(_WIN32)
    if (peer->transport == ENG_NET_UDP && peer->sock_fd >= 0 && peer->has_remote) {
        ssize_t n = sendto(peer->sock_fd, pkt, pkt_len, 0,
                           (const struct sockaddr *)&peer->remote_addr, sizeof(peer->remote_addr));
        return n == (ssize_t)pkt_len;
    }
#endif
    return false;
}

/* Wire header (8 bytes): magic(2), seq(2), ack(2), channel(1), flags(1: bit0=ack_only) */
bool eng_net_send(eng_net_peer_t *peer, eng_net_channel_t channel, const void *payload, size_t len) {
    if (!peer || (!payload && len > 0) || len + 8u > ENG_MAX_PKT_SIZE) return false;
    uint8_t pkt[ENG_MAX_PKT_SIZE];
    uint16_t seq = peer->next_seq++;
    wr_u16(pkt + 0, ENG_PKT_MAGIC);
    wr_u16(pkt + 2, seq);
    wr_u16(pkt + 4, peer->last_recv_seq);
    pkt[6] = (uint8_t)channel;
    pkt[7] = 0u;
    if (len > 0) memcpy(pkt + 8, payload, len);

    if (channel == ENG_CHAN_RELIABLE) {
        for (int i = 0; i < 16; i++) {
            if (!peer->pending[i].active) {
                peer->pending[i].active = true;
                peer->pending[i].seq = seq;
                memcpy(peer->pending[i].pkt, pkt, len + 8u);
                peer->pending[i].len = len + 8u;
                break;
            }
        }
    }
    return transmit_wire(peer, pkt, len + 8u);
}

static bool recv_wire(eng_net_peer_t *peer, uint8_t *out_pkt, size_t *out_len) {
    if (peer->inbox_count > 0) {
        raw_pkt_t *r = &peer->inbox[peer->inbox_head];
        memcpy(out_pkt, r->bytes, r->len);
        *out_len = r->len;
        peer->inbox_head = (peer->inbox_head + 1u) % ENG_LOOP_QUEUE_CAP;
        peer->inbox_count--;
        return true;
    }
#if !defined(__EMSCRIPTEN__) && !defined(_WIN32)
    if (peer->transport == ENG_NET_UDP && peer->sock_fd >= 0) {
        struct sockaddr_in src;
        socklen_t slen = sizeof(src);
        ssize_t n = recvfrom(peer->sock_fd, out_pkt, ENG_MAX_PKT_SIZE, 0, (struct sockaddr *)&src, &slen);
        if (n > 0) {
            if (!peer->has_remote) {
                peer->remote_addr = src;
                peer->has_remote = true;
            }
            *out_len = (size_t)n;
            return true;
        }
    }
#endif
    return false;
}

size_t eng_net_poll(eng_net_peer_t *peer, void *out_payload, size_t max_len, eng_net_channel_t *out_chan) {
    if (!peer || !out_payload || max_len == 0) return 0;

    uint8_t pkt[ENG_MAX_PKT_SIZE];
    size_t plen = 0;
    while (recv_wire(peer, pkt, &plen)) {
        if (plen < 8u || rd_u16(pkt + 0) != ENG_PKT_MAGIC) continue;
        uint16_t seq = rd_u16(pkt + 2);
        uint16_t ack = rd_u16(pkt + 4);
        eng_net_channel_t chan = (eng_net_channel_t)pkt[6];
        uint8_t flags = pkt[7];

        /* Clear acknowledged reliable packets */
        for (int i = 0; i < 16; i++) {
            if (peer->pending[i].active && (int16_t)(ack - peer->pending[i].seq) >= 0) {
                peer->pending[i].active = false;
            }
        }
        if (flags & 1u) continue; /* Pure ACK packet */

        peer->last_recv_seq = seq;
        if (chan == ENG_CHAN_RELIABLE) {
            uint8_t ack_pkt[8];
            wr_u16(ack_pkt + 0, ENG_PKT_MAGIC);
            wr_u16(ack_pkt + 2, 0);
            wr_u16(ack_pkt + 4, seq);
            ack_pkt[6] = ENG_CHAN_UNRELIABLE;
            ack_pkt[7] = 1u;
            transmit_wire(peer, ack_pkt, 8u);
        } else {
            /* Drop out-of-order stale unreliable packets */
            if (peer->has_unrel_seq && (int16_t)(seq - peer->last_unrel_seq) <= 0) continue;
            peer->last_unrel_seq = seq;
            peer->has_unrel_seq = true;
        }

        size_t body_len = plen - 8u;
        if (body_len == 0 || body_len > max_len) continue;
        memcpy(out_payload, pkt + 8, body_len);
        if (out_chan) *out_chan = chan;
        return body_len;
    }

    /* Retransmit any still-unacknowledged reliable packets */
    for (int i = 0; i < 16; i++) {
        if (peer->pending[i].active) {
            transmit_wire(peer, peer->pending[i].pkt, peer->pending[i].len);
        }
    }
    return 0;
}

/* --------------------------------------------------------------------------
 * Pocket-Aware ECS Scene State Replication
 * -------------------------------------------------------------------------- */
#define ENG_SNAP_SCHEMA 1u

bool eng_net_send_scene_snapshot(eng_net_peer_t *authority, const eng_scene_t *scene) {
    if (!authority || !scene) return false;
    eng_ecs_t *ecs = eng_scene_ecs((eng_scene_t *)(uintptr_t)scene);
    eng_bin_writer_t w;
    if (!eng_bin_writer_init(&w, ENG_SNAP_SCHEMA, 512)) return false;

    eng_entity_t ents[64];
    uint32_t count = 0;
    eng_ecs_query_t q = eng_ecs_query_init(ecs, eng_ecs_comp_bit(eng_scene_comp_local(scene)), 0);
    eng_entity_t qe = ENG_ENTITY_NULL;
    while (count < 64 && eng_ecs_query_next(&q, &qe)) {
        if (eng_scene_get_local(scene, qe)) ents[count++] = qe;
    }

    eng_bin_write_u32(&w, count);
    for (uint32_t i = 0; i < count; i++) {
        eng_entity_t e = ents[i];
        const char *name = eng_ecs_get_name(ecs, e);
        uint16_t pid = eng_scene_get_pocket(scene, e);
        const char *pname = eng_scene_pocket_name(scene, pid);
        const eng_transform_local_t *tr = eng_scene_get_local(scene, e);

        eng_bin_write_str(&w, name ? name : "ent");
        eng_bin_write_str(&w, pname ? pname : "world");
        eng_bin_write_f32(&w, tr->pos.x); eng_bin_write_f32(&w, tr->pos.y); eng_bin_write_f32(&w, tr->pos.z);
        eng_bin_write_f32(&w, tr->rot.x); eng_bin_write_f32(&w, tr->rot.y); eng_bin_write_f32(&w, tr->rot.z); eng_bin_write_f32(&w, tr->rot.w);
        eng_bin_write_f32(&w, tr->scale.x); eng_bin_write_f32(&w, tr->scale.y); eng_bin_write_f32(&w, tr->scale.z);
    }

    bool ok = !w.failed && eng_net_send(authority, ENG_CHAN_RELIABLE, w.buf, w.size);
    eng_bin_writer_destroy(&w);
    return ok;
}

bool eng_net_apply_scene_snapshot(eng_scene_t *replica_scene, const void *payload, size_t len) {
    if (!replica_scene || !payload || len == 0) return false;
    eng_bin_reader_t r;
    if (!eng_bin_reader_init(&r, payload, len, ENG_SNAP_SCHEMA)) return false;

    uint32_t count = 0;
    if (!eng_bin_read_u32(&r, &count) || count > 64) return false;
    eng_ecs_t *ecs = eng_scene_ecs(replica_scene);

    for (uint32_t i = 0; i < count; i++) {
        char name[64] = {0}, pname[32] = {0};
        eng_vec3_t pos, scl;
        eng_quat_t rot;
        if (!eng_bin_read_str(&r, name, sizeof(name)) || !eng_bin_read_str(&r, pname, sizeof(pname))) return false;
        if (!eng_bin_read_f32(&r, &pos.x) || !eng_bin_read_f32(&r, &pos.y) || !eng_bin_read_f32(&r, &pos.z)) return false;
        if (!eng_bin_read_f32(&r, &rot.x) || !eng_bin_read_f32(&r, &rot.y) || !eng_bin_read_f32(&r, &rot.z) || !eng_bin_read_f32(&r, &rot.w)) return false;
        if (!eng_bin_read_f32(&r, &scl.x) || !eng_bin_read_f32(&r, &scl.y) || !eng_bin_read_f32(&r, &scl.z)) return false;

        eng_entity_t e = eng_ecs_find_by_name(ecs, name);
        if (e == ENG_ENTITY_NULL) e = eng_scene_spawn(replica_scene, name);
        uint16_t pid = eng_scene_register_pocket(replica_scene, pname);
        eng_scene_set_pocket(replica_scene, e, pid);
        eng_scene_set_local_pos(replica_scene, e, pos);
        eng_scene_set_local_rot(replica_scene, e, rot);
        eng_scene_set_local_scale(replica_scene, e, scl);
    }
    eng_scene_update_transforms(replica_scene);
    return true;
}
