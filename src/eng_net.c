#include "engine/eng_net.h"
#include "engine/eng_log.h"
#include "engine/eng_serde.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/websocket.h>
#elif defined(ENG_HAS_SDL3_NET)
#include <SDL3/SDL.h>
#include <SDL3_net/SDL_net.h>
#endif

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_PKT_MAGIC 0x4E45u
#define ENG_UDP_MTU 1400u
#define ENG_EVT_QUEUE_CAP 64
#define ENG_WS_RX_INIT_CAP 4096u

typedef struct {
    eng_net_evt_type_t type;
    uint32_t client_id;
    eng_net_channel_t chan;
    uint8_t *data;
    size_t len;
} queued_evt_t;

typedef struct {
    bool active;
    uint16_t seq;
    uint8_t pkt[ENG_UDP_MTU];
    size_t len;
} unacked_pkt_t;

typedef struct {
    bool active;
    uint32_t id;
    /* Loopback partner */
    eng_net_peer_t *loop_peer;
    uint32_t loop_remote_id;
#ifdef ENG_HAS_SDL3_NET
    /* WebSocket TCP stream (via SDL3_net) */
    NET_StreamSocket *ws_sock;
    bool ws_open;
    bool ws_hs_sent;
    uint8_t *rx_buf;
    size_t rx_len;
    size_t rx_cap;
    /* UDP remote endpoint (via SDL3_net) */
    NET_Address *udp_addr;
    uint16_t udp_port;
#endif
    uint16_t next_seq;
    uint16_t last_recv_seq;
    uint16_t last_unrel_seq;
    bool has_unrel_seq;
    unacked_pkt_t pending[16];
} net_slot_t;

struct eng_net_peer_s {
    eng_net_transport_t transport;
    bool is_server;
    bool connected;
    uint16_t local_port;
    uint32_t next_client_id;
    uint32_t mask_rng;
#ifdef ENG_HAS_SDL3_NET
    NET_Server *ws_server;
    NET_DatagramSocket *udp_sock;
    char ws_host[128];
    char ws_path[128];
#elif defined(__EMSCRIPTEN__)
    EMSCRIPTEN_WEBSOCKET_T em_ws;
#endif
    net_slot_t slots[ENG_NET_MAX_CLIENTS];
    queued_evt_t evts[ENG_EVT_QUEUE_CAP];
    size_t evt_head;
    size_t evt_count;
};

#ifdef ENG_HAS_SDL3_NET
static void wr_u16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)(v & 0xFFu); p[1] = (uint8_t)(v >> 8); }
static uint16_t rd_u16(const uint8_t *p) { return (uint16_t)p[0] | (uint16_t)((uint16_t)p[1] << 8); }
#endif

static void push_evt(eng_net_peer_t *p, eng_net_evt_type_t type, uint32_t cid,
                     eng_net_channel_t chan, const void *data, size_t len) {
    if (!p || p->evt_count >= ENG_EVT_QUEUE_CAP) return;
    uint8_t *copy = NULL;
    if (data && len > 0) {
        copy = (uint8_t *)malloc(len);
        if (!copy) return;
        memcpy(copy, data, len);
    }
    size_t idx = (p->evt_head + p->evt_count) % ENG_EVT_QUEUE_CAP;
    p->evts[idx] = (queued_evt_t){type, cid, chan, copy, len};
    p->evt_count++;
}

static net_slot_t *find_slot_by_id(eng_net_peer_t *p, uint32_t cid) {
    if (!p || cid == 0) return NULL;
    for (int i = 0; i < ENG_NET_MAX_CLIENTS; i++) {
        if (p->slots[i].active && p->slots[i].id == cid) return &p->slots[i];
    }
    return NULL;
}

static net_slot_t *alloc_slot(eng_net_peer_t *p) {
    for (int i = 0; i < ENG_NET_MAX_CLIENTS; i++) {
        if (!p->slots[i].active) {
            memset(&p->slots[i], 0, sizeof(p->slots[i]));
            p->slots[i].active = true;
            p->slots[i].id = p->next_client_id++;
            p->slots[i].next_seq = 1u;
            return &p->slots[i];
        }
    }
    return NULL;
}

static void clear_slot(net_slot_t *s) {
    if (!s || !s->active) return;
#ifdef ENG_HAS_SDL3_NET
    if (s->ws_sock) NET_DestroyStreamSocket(s->ws_sock);
    if (s->udp_addr) NET_UnrefAddress(s->udp_addr);
    free(s->rx_buf);
#endif
    memset(s, 0, sizeof(*s));
}

/* --------------------------------------------------------------------------
 * Pure-C11 RFC 3174 SHA-1 + Base64 + RFC 6455 Binary WebSocket Framing
 * -------------------------------------------------------------------------- */
#ifdef ENG_HAS_SDL3_NET
static int g_sdlnet_refs = 0;
static uint16_t g_port_cursor = 49200u;

static bool sdlnet_acquire(void) {
    if (g_sdlnet_refs == 0) {
        if (!NET_Init()) return false;
    }
    g_sdlnet_refs++;
    return true;
}

static void sdlnet_release(void) {
    if (g_sdlnet_refs > 0 && --g_sdlnet_refs == 0) {
        NET_Quit();
    }
}

static uint32_t rol32(uint32_t v, int bits) { return (v << bits) | (v >> (32 - bits)); }

static void sha1_digest(const uint8_t *msg, size_t len, uint8_t out[20]) {
    uint32_t h0 = 0x67452301u, h1 = 0xEFCDAB89u, h2 = 0x98BADCFEu, h3 = 0x10325476u, h4 = 0xC3D2E1F0u;
    size_t pad_len = ((len + 9u + 63u) / 64u) * 64u;
    uint8_t *buf = (uint8_t *)calloc(1, pad_len);
    if (!buf) return;
    memcpy(buf, msg, len);
    buf[len] = 0x80u;
    uint64_t bits = (uint64_t)len * 8u;
    for (int i = 0; i < 8; i++) buf[pad_len - 1u - (size_t)i] = (uint8_t)(bits >> (i * 8));

    for (size_t off = 0; off < pad_len; off += 64u) {
        uint32_t w[80];
        for (int i = 0; i < 16; i++) {
            const uint8_t *b = buf + off + (size_t)i * 4u;
            w[i] = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
        }
        for (int i = 16; i < 80; i++) w[i] = rol32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        uint32_t a = h0, b = h1, c = h2, d = h3, e = h4;
        for (int i = 0; i < 80; i++) {
            uint32_t f, k;
            if (i < 20)      { f = (b & c) | ((~b) & d);           k = 0x5A827999u; }
            else if (i < 40) { f = b ^ c ^ d;                      k = 0x6ED9EBA1u; }
            else if (i < 60) { f = (b & c) | (b & d) | (c & d);    k = 0x8F1BBCDCu; }
            else             { f = b ^ c ^ d;                      k = 0xCA62C1D6u; }
            uint32_t tmp = rol32(a, 5) + f + e + k + w[i];
            e = d; d = c; c = rol32(b, 30); b = a; a = tmp;
        }
        h0 += a; h1 += b; h2 += c; h3 += d; h4 += e;
    }
    free(buf);
    uint32_t hs[5] = {h0, h1, h2, h3, h4};
    for (int i = 0; i < 5; i++) {
        out[i * 4 + 0] = (uint8_t)(hs[i] >> 24);
        out[i * 4 + 1] = (uint8_t)(hs[i] >> 16);
        out[i * 4 + 2] = (uint8_t)(hs[i] >> 8);
        out[i * 4 + 3] = (uint8_t)(hs[i]);
    }
}

static void b64_encode(const uint8_t *in, size_t len, char *out) {
    static const char tbl[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t o = 0;
    for (size_t i = 0; i < len; i += 3u) {
        uint32_t v = ((uint32_t)in[i] << 16)
                   | ((i + 1u < len ? (uint32_t)in[i + 1u] : 0u) << 8)
                   | (i + 2u < len ? (uint32_t)in[i + 2u] : 0u);
        out[o++] = tbl[(v >> 18) & 63u];
        out[o++] = tbl[(v >> 12) & 63u];
        out[o++] = (i + 1u < len) ? tbl[(v >> 6) & 63u] : '=';
        out[o++] = (i + 2u < len) ? tbl[v & 63u] : '=';
    }
    out[o] = '\0';
}

static void ws_compute_accept(const char *client_key, char out_b64[32]) {
    char combo[128];
    int n = snprintf(combo, sizeof(combo), "%s258EAFA5-E914-47DA-95CA-C5AB0DC85B11", client_key);
    uint8_t hash[20];
    sha1_digest((const uint8_t *)combo, (size_t)(n > 0 ? n : 0), hash);
    b64_encode(hash, 20, out_b64);
}

static bool ws_send_frame(eng_net_peer_t *p, NET_StreamSocket *sock, uint8_t opcode,
                          const uint8_t *payload, size_t len, bool mask) {
    if (!sock || len > ENG_NET_MAX_MSG_SIZE) return false;
    uint8_t hdr[14];
    size_t hlen = 2u;
    hdr[0] = (uint8_t)(0x80u | (opcode & 0x0Fu));
    uint8_t mbit = mask ? 0x80u : 0x00u;
    if (len < 126u) {
        hdr[1] = (uint8_t)(mbit | (uint8_t)len);
    } else {
        hdr[1] = (uint8_t)(mbit | 126u);
        hdr[2] = (uint8_t)((len >> 8) & 0xFFu);
        hdr[3] = (uint8_t)(len & 0xFFu);
        hlen = 4u;
    }
    uint8_t mkey[4] = {0};
    if (mask) {
        p->mask_rng = p->mask_rng * 1664525u + 1013904223u;
        mkey[0] = (uint8_t)(p->mask_rng >> 24); mkey[1] = (uint8_t)(p->mask_rng >> 16);
        mkey[2] = (uint8_t)(p->mask_rng >> 8);  mkey[3] = (uint8_t)(p->mask_rng | 1u);
        memcpy(hdr + hlen, mkey, 4u);
        hlen += 4u;
    }
    uint8_t *frame = (uint8_t *)malloc(hlen + len);
    if (!frame) return false;
    memcpy(frame, hdr, hlen);
    if (len > 0 && payload) {
        if (mask) {
            for (size_t i = 0; i < len; i++) frame[hlen + i] = payload[i] ^ mkey[i & 3u];
        } else {
            memcpy(frame + hlen, payload, len);
        }
    }
    bool ok = NET_WriteToStreamSocket(sock, frame, (int)(hlen + len));
    free(frame);
    return ok;
}

static bool ws_send_app_msg(eng_net_peer_t *p, net_slot_t *s, eng_net_channel_t chan,
                            const void *payload, size_t len) {
    if (!s || !s->ws_sock || !s->ws_open || len + 1u > ENG_NET_MAX_MSG_SIZE) return false;
    uint8_t *buf = (uint8_t *)malloc(len + 1u);
    if (!buf) return false;
    buf[0] = (uint8_t)chan;
    if (len > 0 && payload) memcpy(buf + 1u, payload, len);
    bool ok = ws_send_frame(p, s->ws_sock, 0x02u, buf, len + 1u, !p->is_server);
    free(buf);
    return ok;
}

static bool ci_prefix(const char *s, const char *pre) {
    while (*pre) {
        if (tolower((unsigned char)*s) != tolower((unsigned char)*pre)) return false;
        s++; pre++;
    }
    return true;
}

static bool extract_ws_key(const char *hdrs, size_t hlen, char out_key[64]) {
    size_t i = 0;
    while (i < hlen) {
        size_t ls = i;
        while (i < hlen && hdrs[i] != '\n') i++;
        size_t ll = i - ls;
        if (ll > 18u && ci_prefix(hdrs + ls, "sec-websocket-key:")) {
            const char *v = hdrs + ls + 18u;
            size_t vl = ll - 18u;
            while (vl > 0 && (*v == ' ' || *v == '\t')) { v++; vl--; }
            while (vl > 0 && (v[vl - 1] == '\r' || v[vl - 1] == ' ')) vl--;
            if (vl > 0 && vl < 63u) {
                memcpy(out_key, v, vl);
                out_key[vl] = '\0';
                return true;
            }
        }
        if (i < hlen) i++;
    }
    return false;
}

static bool ws_rx_ensure(net_slot_t *s, size_t need) {
    if (s->rx_cap >= need) return true;
    size_t nc = s->rx_cap ? s->rx_cap * 2u : ENG_WS_RX_INIT_CAP;
    while (nc < need) nc *= 2u;
    if (nc > ENG_NET_MAX_MSG_SIZE + 4096u) return false;
    uint8_t *nb = (uint8_t *)realloc(s->rx_buf, nc);
    if (!nb) return false;
    s->rx_buf = nb;
    s->rx_cap = nc;
    return true;
}

static void ws_rx_consume(net_slot_t *s, size_t n) {
    if (n >= s->rx_len) { s->rx_len = 0; return; }
    memmove(s->rx_buf, s->rx_buf + n, s->rx_len - n);
    s->rx_len -= n;
}

static void ws_pump_slot(eng_net_peer_t *p, net_slot_t *s) {
    if (!s->active || !s->ws_sock) return;

    /* Client-side async TCP connect + HTTP Upgrade send */
    if (!p->is_server && !s->ws_open) {
        NET_Status st = NET_GetConnectionStatus(s->ws_sock);
        if (st == NET_FAILURE) {
            p->connected = false;
            clear_slot(s);
            push_evt(p, ENG_NET_EVT_DISCONNECT, 0, ENG_CHAN_RELIABLE, NULL, 0);
            return;
        }
        if (st == NET_WAITING) return;
        if (!s->ws_hs_sent) {
            uint8_t nonce[16];
            for (int i = 0; i < 16; i++) {
                p->mask_rng = p->mask_rng * 1664525u + 1013904223u;
                nonce[i] = (uint8_t)(p->mask_rng >> 24);
            }
            char key_b64[32];
            b64_encode(nonce, 16, key_b64);
            char req[512];
            int rn = snprintf(req, sizeof(req),
                              "GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\n"
                              "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
                              "Sec-WebSocket-Version: 13\r\n\r\n",
                              p->ws_path[0] ? p->ws_path : "/",
                              p->ws_host[0] ? p->ws_host : "localhost", key_b64);
            NET_WriteToStreamSocket(s->ws_sock, req, rn);
            s->ws_hs_sent = true;
        }
    }

    /* Non-blocking drain from stream socket */
    uint8_t tmp[4096];
    for (;;) {
        int n = NET_ReadFromStreamSocket(s->ws_sock, tmp, (int)sizeof(tmp));
        if (n < 0) {
            uint32_t cid = p->is_server ? s->id : 0u;
            bool was_open = s->ws_open;
            if (!p->is_server) p->connected = false;
            clear_slot(s);
            if (was_open) push_evt(p, ENG_NET_EVT_DISCONNECT, cid, ENG_CHAN_RELIABLE, NULL, 0);
            return;
        }
        if (n == 0) break;
        if (!ws_rx_ensure(s, s->rx_len + (size_t)n + 1u)) {
            uint32_t cid = p->is_server ? s->id : 0u;
            clear_slot(s);
            push_evt(p, ENG_NET_EVT_DISCONNECT, cid, ENG_CHAN_RELIABLE, NULL, 0);
            return;
        }
        memcpy(s->rx_buf + s->rx_len, tmp, (size_t)n);
        s->rx_len += (size_t)n;
        s->rx_buf[s->rx_len] = '\0';
    }

    /* HTTP 101 Upgrade Handshake */
    if (!s->ws_open) {
        if (!s->rx_buf || s->rx_len < 4u) return;
        const char *end = strstr((const char *)s->rx_buf, "\r\n\r\n");
        if (!end) return;
        size_t hdr_len = (size_t)(end - (const char *)s->rx_buf) + 4u;
        if (p->is_server) {
            char ckey[64] = {0};
            if (!extract_ws_key((const char *)s->rx_buf, hdr_len, ckey)) {
                clear_slot(s);
                return;
            }
            char accept_b64[32];
            ws_compute_accept(ckey, accept_b64);
            char resp[256];
            int rn = snprintf(resp, sizeof(resp),
                              "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                              "Connection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n",
                              accept_b64);
            NET_WriteToStreamSocket(s->ws_sock, resp, rn);
            ws_rx_consume(s, hdr_len);
            s->ws_open = true;
            push_evt(p, ENG_NET_EVT_CONNECT, s->id, ENG_CHAN_RELIABLE, NULL, 0);
        } else {
            if (strstr((const char *)s->rx_buf, " 101 ") == NULL) {
                p->connected = false;
                clear_slot(s);
                return;
            }
            ws_rx_consume(s, hdr_len);
            s->ws_open = true;
            p->connected = true;
            push_evt(p, ENG_NET_EVT_CONNECT, 0, ENG_CHAN_RELIABLE, NULL, 0);
        }
    }

    /* Parse complete RFC 6455 frames */
    while (s->active && s->ws_open && s->rx_len >= 2u) {
        uint8_t b0 = s->rx_buf[0], b1 = s->rx_buf[1];
        uint8_t opcode = b0 & 0x0Fu;
        bool masked = (b1 & 0x80u) != 0;
        size_t plen = (size_t)(b1 & 0x7Fu);
        size_t off = 2u;
        if (plen == 126u) {
            if (s->rx_len < 4u) break;
            plen = ((size_t)s->rx_buf[2] << 8) | (size_t)s->rx_buf[3];
            off = 4u;
        } else if (plen == 127u) {
            /* Reject oversized >64KB frames cleanly */
            uint32_t cid = p->is_server ? s->id : 0u;
            clear_slot(s);
            push_evt(p, ENG_NET_EVT_DISCONNECT, cid, ENG_CHAN_RELIABLE, NULL, 0);
            return;
        }
        size_t total = off + (masked ? 4u : 0u) + plen;
        if (s->rx_len < total) break;
        uint8_t *body = s->rx_buf + off + (masked ? 4u : 0u);
        if (masked) {
            const uint8_t *mk = s->rx_buf + off;
            for (size_t i = 0; i < plen; i++) body[i] ^= mk[i & 3u];
        }
        if (opcode == 0x09u) {
            ws_send_frame(p, s->ws_sock, 0x0Au, body, plen, !p->is_server);
        } else if (opcode == 0x08u) {
            ws_send_frame(p, s->ws_sock, 0x08u, NULL, 0, !p->is_server);
            uint32_t cid = p->is_server ? s->id : 0u;
            if (!p->is_server) p->connected = false;
            clear_slot(s);
            push_evt(p, ENG_NET_EVT_DISCONNECT, cid, ENG_CHAN_RELIABLE, NULL, 0);
            return;
        } else if ((opcode == 0x02u || opcode == 0x01u) && plen >= 1u) {
            eng_net_channel_t ch = body[0] ? ENG_CHAN_RELIABLE : ENG_CHAN_UNRELIABLE;
            push_evt(p, ENG_NET_EVT_MESSAGE, p->is_server ? s->id : 0u, ch, body + 1u, plen - 1u);
        }
        ws_rx_consume(s, total);
    }
}

static bool parse_ws_url(const char *url, uint16_t fallback_port,
                         char host_out[128], uint16_t *port_out, char path_out[128], bool *is_wss) {
    *is_wss = false;
    const char *s = url;
    uint16_t def_port = fallback_port ? fallback_port : 7777u;
    if (strncmp(s, "ws://", 5) == 0) { s += 5; if (!fallback_port) def_port = 80u; }
    else if (strncmp(s, "wss://", 6) == 0) { s += 6; *is_wss = true; if (!fallback_port) def_port = 443u; }
    const char *slash = strchr(s, '/');
    size_t hlen = slash ? (size_t)(slash - s) : strlen(s);
    const char *colon = NULL;
    for (size_t i = 0; i < hlen; i++) if (s[i] == ':') colon = s + i;
    size_t host_len = colon ? (size_t)(colon - s) : hlen;
    if (host_len == 0 || host_len >= 127u) return false;
    memcpy(host_out, s, host_len);
    host_out[host_len] = '\0';
    *port_out = colon ? (uint16_t)atoi(colon + 1) : def_port;
    snprintf(path_out, 128, "%s", slash ? slash : "/");
    return *port_out > 0;
}

static bool udp_send_wire(eng_net_peer_t *p, net_slot_t *s, const uint8_t *pkt, size_t len) {
    if (!p->udp_sock || !s || !s->udp_addr || s->udp_port == 0) return false;
    return NET_SendDatagram(p->udp_sock, s->udp_addr, s->udp_port, pkt, (int)len);
}

static bool udp_send_slot(eng_net_peer_t *p, net_slot_t *s, eng_net_channel_t chan,
                          const void *payload, size_t len) {
    if (!s || len + 8u > ENG_UDP_MTU) return false;
    uint8_t pkt[ENG_UDP_MTU];
    uint16_t seq = s->next_seq++;
    wr_u16(pkt + 0, ENG_PKT_MAGIC);
    wr_u16(pkt + 2, seq);
    wr_u16(pkt + 4, s->last_recv_seq);
    pkt[6] = (uint8_t)chan;
    pkt[7] = 0u;
    if (len > 0 && payload) memcpy(pkt + 8, payload, len);
    if (chan == ENG_CHAN_RELIABLE) {
        for (int i = 0; i < 16; i++) {
            if (!s->pending[i].active) {
                s->pending[i].active = true;
                s->pending[i].seq = seq;
                memcpy(s->pending[i].pkt, pkt, len + 8u);
                s->pending[i].len = len + 8u;
                break;
            }
        }
    }
    return udp_send_wire(p, s, pkt, len + 8u);
}

static void udp_pump(eng_net_peer_t *p) {
    if (!p->udp_sock) return;
    NET_Datagram *dg = NULL;
    while (NET_ReceiveDatagram(p->udp_sock, &dg) && dg != NULL) {
        if (dg->buflen >= 8 && rd_u16(dg->buf) == ENG_PKT_MAGIC) {
            net_slot_t *s = NULL;
            for (int i = 0; i < ENG_NET_MAX_CLIENTS; i++) {
                if (p->slots[i].active && p->slots[i].udp_addr &&
                    p->slots[i].udp_port == dg->port &&
                    NET_CompareAddresses(p->slots[i].udp_addr, dg->addr) == 0) {
                    s = &p->slots[i];
                    break;
                }
            }
            if (!s) {
                s = alloc_slot(p);
                if (s) {
                    s->udp_addr = NET_RefAddress(dg->addr);
                    s->udp_port = dg->port;
                    if (p->is_server) push_evt(p, ENG_NET_EVT_CONNECT, s->id, ENG_CHAN_RELIABLE, NULL, 0);
                }
            }
            if (s) {
                uint16_t seq = rd_u16(dg->buf + 2);
                uint16_t ack = rd_u16(dg->buf + 4);
                eng_net_channel_t chan = (eng_net_channel_t)dg->buf[6];
                uint8_t flags = dg->buf[7];
                for (int i = 0; i < 16; i++) {
                    if (s->pending[i].active && (int16_t)(ack - s->pending[i].seq) >= 0) {
                        s->pending[i].active = false;
                    }
                }
                if ((flags & 1u) == 0) {
                    s->last_recv_seq = seq;
                    bool drop = false;
                    if (chan == ENG_CHAN_RELIABLE) {
                        uint8_t ack_pkt[8];
                        wr_u16(ack_pkt + 0, ENG_PKT_MAGIC);
                        wr_u16(ack_pkt + 2, 0);
                        wr_u16(ack_pkt + 4, seq);
                        ack_pkt[6] = ENG_CHAN_UNRELIABLE;
                        ack_pkt[7] = 1u;
                        udp_send_wire(p, s, ack_pkt, 8u);
                    } else {
                        if (s->has_unrel_seq && (int16_t)(seq - s->last_unrel_seq) <= 0) drop = true;
                        else { s->last_unrel_seq = seq; s->has_unrel_seq = true; }
                    }
                    if (!drop && dg->buflen > 8) {
                        push_evt(p, ENG_NET_EVT_MESSAGE, p->is_server ? s->id : 0u,
                                 chan, dg->buf + 8, (size_t)dg->buflen - 8u);
                    }
                }
            }
        }
        NET_DestroyDatagram(dg);
        dg = NULL;
    }
    for (int i = 0; i < ENG_NET_MAX_CLIENTS; i++) {
        net_slot_t *s = &p->slots[i];
        if (!s->active) continue;
        for (int k = 0; k < 16; k++) {
            if (s->pending[k].active) udp_send_wire(p, s, s->pending[k].pkt, s->pending[k].len);
        }
    }
}
#endif

#ifdef __EMSCRIPTEN__
static EM_BOOL em_ws_onopen(int et, const EmscriptenWebSocketOpenEvent *ev, void *ud) {
    (void)et; (void)ev;
    eng_net_peer_t *p = (eng_net_peer_t *)ud;
    if (p) {
        p->connected = true;
        push_evt(p, ENG_NET_EVT_CONNECT, 0, ENG_CHAN_RELIABLE, NULL, 0);
    }
    return EM_TRUE;
}
static EM_BOOL em_ws_onmessage(int et, const EmscriptenWebSocketMessageEvent *ev, void *ud) {
    (void)et;
    eng_net_peer_t *p = (eng_net_peer_t *)ud;
    if (p && ev && ev->data && ev->numBytes >= 1) {
        eng_net_channel_t ch = ev->data[0] ? ENG_CHAN_RELIABLE : ENG_CHAN_UNRELIABLE;
        push_evt(p, ENG_NET_EVT_MESSAGE, 0, ch, ev->data + 1, (size_t)ev->numBytes - 1u);
    }
    return EM_TRUE;
}
static EM_BOOL em_ws_onclose(int et, const EmscriptenWebSocketCloseEvent *ev, void *ud) {
    (void)et; (void)ev;
    eng_net_peer_t *p = (eng_net_peer_t *)ud;
    if (p) {
        p->connected = false;
        push_evt(p, ENG_NET_EVT_DISCONNECT, 0, ENG_CHAN_RELIABLE, NULL, 0);
    }
    return EM_TRUE;
}
static EM_BOOL em_ws_onerror(int et, const EmscriptenWebSocketErrorEvent *ev, void *ud) {
    (void)et; (void)ev;
    eng_net_peer_t *p = (eng_net_peer_t *)ud;
    if (p && p->connected) {
        p->connected = false;
        push_evt(p, ENG_NET_EVT_DISCONNECT, 0, ENG_CHAN_RELIABLE, NULL, 0);
    }
    return EM_TRUE;
}
#endif

/* --------------------------------------------------------------------------
 * Public Lifecycle, Host & Connect
 * -------------------------------------------------------------------------- */
eng_net_peer_t *eng_net_host(eng_net_transport_t transport, const char *bind_ip, uint16_t port) {
    eng_net_peer_t *p = (eng_net_peer_t *)calloc(1, sizeof(eng_net_peer_t));
    if (!p) return NULL;
    p->transport = transport;
    p->is_server = true;
    p->next_client_id = 1u;
    p->mask_rng = 0x9E3779B9u;

#ifdef ENG_HAS_SDL3_NET
    if (transport == ENG_NET_UDP || transport == ENG_NET_WEBSOCKET) {
        if (!sdlnet_acquire()) { free(p); return NULL; }
        NET_Address *addr = NULL;
        if (bind_ip && bind_ip[0] && strcmp(bind_ip, "0.0.0.0") != 0) {
            addr = NET_ResolveHostname(bind_ip);
            if (!addr || NET_WaitUntilResolved(addr, 500) != NET_SUCCESS) {
                if (addr) NET_UnrefAddress(addr);
                sdlnet_release();
                free(p);
                return NULL;
            }
        }
        uint16_t try_port = port;
        int attempts = (port == 0) ? 64 : 1;
        for (int a = 0; a < attempts; a++) {
            uint16_t cand = (port == 0) ? (uint16_t)(49152u + ((g_port_cursor++ + (uint16_t)a) % 15000u)) : try_port;
            if (transport == ENG_NET_WEBSOCKET) {
                p->ws_server = NET_CreateServer(addr, cand, 0);
                if (p->ws_server) { p->local_port = cand; break; }
            } else {
                p->udp_sock = NET_CreateDatagramSocket(addr, cand, 0);
                if (p->udp_sock) { p->local_port = cand; break; }
            }
        }
        if (addr) NET_UnrefAddress(addr);
        if (p->local_port == 0) {
            sdlnet_release();
            free(p);
            return NULL;
        }
    }
#else
    (void)bind_ip;
    p->local_port = port;
#endif
    return p;
}

eng_net_peer_t *eng_net_create(eng_net_transport_t transport, uint16_t local_port) {
    if (transport == ENG_NET_UDP) {
        eng_net_peer_t *p = eng_net_host(ENG_NET_UDP, "127.0.0.1", local_port);
        if (p) p->is_server = (local_port != 0);
        return p;
    }
    eng_net_peer_t *p = (eng_net_peer_t *)calloc(1, sizeof(eng_net_peer_t));
    if (!p) return NULL;
    p->transport = transport;
    p->is_server = false;
    p->next_client_id = 1u;
    p->mask_rng = 0x9E3779B9u;
    p->local_port = local_port;
#ifdef ENG_HAS_SDL3_NET
    if (transport == ENG_NET_WEBSOCKET) {
        if (!sdlnet_acquire()) { free(p); return NULL; }
    }
#endif
    return p;
}

void eng_net_destroy(eng_net_peer_t *peer) {
    if (!peer) return;
    for (int i = 0; i < ENG_NET_MAX_CLIENTS; i++) {
        net_slot_t *s = &peer->slots[i];
        if (!s->active) continue;
        if (s->loop_peer) {
            net_slot_t *rs = find_slot_by_id(s->loop_peer, s->loop_remote_id);
            if (rs) {
                uint32_t rcid = s->loop_peer->is_server ? rs->id : 0u;
                rs->loop_peer = NULL;
                clear_slot(rs);
                if (!s->loop_peer->is_server) s->loop_peer->connected = false;
                push_evt(s->loop_peer, ENG_NET_EVT_DISCONNECT, rcid, ENG_CHAN_RELIABLE, NULL, 0);
            }
        }
        clear_slot(s);
    }
    while (peer->evt_count > 0) {
        free(peer->evts[peer->evt_head].data);
        peer->evt_head = (peer->evt_head + 1u) % ENG_EVT_QUEUE_CAP;
        peer->evt_count--;
    }
#ifdef ENG_HAS_SDL3_NET
    if (peer->ws_server) NET_DestroyServer(peer->ws_server);
    if (peer->udp_sock) NET_DestroyDatagramSocket(peer->udp_sock);
    if (peer->transport == ENG_NET_UDP || peer->transport == ENG_NET_WEBSOCKET) sdlnet_release();
#elif defined(__EMSCRIPTEN__)
    if (peer->em_ws > 0) {
        emscripten_websocket_close(peer->em_ws, 1000, "bye");
        emscripten_websocket_delete(peer->em_ws);
    }
#endif
    free(peer);
}

uint16_t eng_net_bound_port(const eng_net_peer_t *peer) { return peer ? peer->local_port : 0; }
bool eng_net_is_server(const eng_net_peer_t *peer) { return peer ? peer->is_server : false; }

bool eng_net_is_connected(const eng_net_peer_t *peer) {
    if (!peer) return false;
    if (peer->is_server) return eng_net_client_count(peer) > 0;
    return peer->connected;
}

size_t eng_net_client_count(const eng_net_peer_t *peer) {
    if (!peer) return 0;
    size_t n = 0;
    for (int i = 0; i < ENG_NET_MAX_CLIENTS; i++) {
        if (!peer->slots[i].active) continue;
#ifdef ENG_HAS_SDL3_NET
        if (peer->transport == ENG_NET_WEBSOCKET && !peer->slots[i].ws_open) continue;
#endif
        n++;
    }
    return n;
}

size_t eng_net_client_ids(const eng_net_peer_t *peer, uint32_t *out_ids, size_t max_out) {
    if (!peer || !out_ids || max_out == 0) return 0;
    size_t n = 0;
    for (int i = 0; i < ENG_NET_MAX_CLIENTS && n < max_out; i++) {
        if (!peer->slots[i].active) continue;
#ifdef ENG_HAS_SDL3_NET
        if (peer->transport == ENG_NET_WEBSOCKET && !peer->slots[i].ws_open) continue;
#endif
        out_ids[n++] = peer->slots[i].id;
    }
    return n;
}

bool eng_net_disconnect_client(eng_net_peer_t *peer, uint32_t client_id) {
    net_slot_t *s = find_slot_by_id(peer, client_id);
    if (!s) return false;
    if (s->loop_peer) {
        net_slot_t *rs = find_slot_by_id(s->loop_peer, s->loop_remote_id);
        if (rs) {
            s->loop_peer->connected = false;
            clear_slot(rs);
            push_evt(s->loop_peer, ENG_NET_EVT_DISCONNECT, 0, ENG_CHAN_RELIABLE, NULL, 0);
        }
    }
#ifdef ENG_HAS_SDL3_NET
    if (s->ws_sock && s->ws_open) ws_send_frame(peer, s->ws_sock, 0x08u, NULL, 0, !peer->is_server);
#endif
    clear_slot(s);
    push_evt(peer, ENG_NET_EVT_DISCONNECT, client_id, ENG_CHAN_RELIABLE, NULL, 0);
    return true;
}

bool eng_net_connect_loopback(eng_net_peer_t *a, eng_net_peer_t *b) {
    if (!a || !b || a == b) return false;
    net_slot_t *sa = alloc_slot(a);
    net_slot_t *sb = alloc_slot(b);
    if (!sa || !sb) {
        if (sa) clear_slot(sa);
        if (sb) clear_slot(sb);
        return false;
    }
    sa->loop_peer = b; sa->loop_remote_id = sb->id;
    sb->loop_peer = a; sb->loop_remote_id = sa->id;
    if (!a->is_server) a->connected = true;
    if (!b->is_server) b->connected = true;
    push_evt(a, ENG_NET_EVT_CONNECT, a->is_server ? sa->id : 0u, ENG_CHAN_RELIABLE, NULL, 0);
    push_evt(b, ENG_NET_EVT_CONNECT, b->is_server ? sb->id : 0u, ENG_CHAN_RELIABLE, NULL, 0);
    return true;
}

bool eng_net_connect_remote(eng_net_peer_t *peer, const char *host_or_url, uint16_t remote_port) {
    if (!peer || !host_or_url || !host_or_url[0]) return false;
#ifdef __EMSCRIPTEN__
    if (peer->transport != ENG_NET_WEBSOCKET) return false;
    char url[256];
    if (strncmp(host_or_url, "ws://", 5) == 0 || strncmp(host_or_url, "wss://", 6) == 0) {
        snprintf(url, sizeof(url), "%s", host_or_url);
    } else {
        snprintf(url, sizeof(url), "ws://%s:%u/", host_or_url, (unsigned)(remote_port ? remote_port : 7777u));
    }
    EmscriptenWebSocketCreateAttributes attr;
    emscripten_websocket_init_create_attributes(&attr);
    attr.url = url;
    attr.protocols = NULL;
    attr.createOnMainThread = EM_TRUE;
    peer->em_ws = emscripten_websocket_new(&attr);
    if (peer->em_ws <= 0) return false;
    emscripten_websocket_set_onopen_callback(peer->em_ws, peer, em_ws_onopen);
    emscripten_websocket_set_onmessage_callback(peer->em_ws, peer, em_ws_onmessage);
    emscripten_websocket_set_onclose_callback(peer->em_ws, peer, em_ws_onclose);
    emscripten_websocket_set_onerror_callback(peer->em_ws, peer, em_ws_onerror);
    return true;
#elif defined(ENG_HAS_SDL3_NET)
    if (peer->transport == ENG_NET_UDP && peer->udp_sock) {
        NET_Address *addr = NET_ResolveHostname(host_or_url);
        if (!addr || NET_WaitUntilResolved(addr, 500) != NET_SUCCESS) {
            if (addr) NET_UnrefAddress(addr);
            return false;
        }
        clear_slot(&peer->slots[0]);
        net_slot_t *s = alloc_slot(peer);
        if (!s) { NET_UnrefAddress(addr); return false; }
        s->udp_addr = addr;
        s->udp_port = remote_port;
        peer->connected = true;
        return true;
    }
    if (peer->transport == ENG_NET_WEBSOCKET) {
        uint16_t port = 0;
        bool is_wss = false;
        if (!parse_ws_url(host_or_url, remote_port, peer->ws_host, &port, peer->ws_path, &is_wss)) return false;
        if (is_wss) {
            ENG_LOGW("net", "Native desktop client requires plain ws:// (use server ws:// port or TLS tunnel)");
            return false;
        }
        NET_Address *addr = NET_ResolveHostname(peer->ws_host);
        if (!addr || NET_WaitUntilResolved(addr, 1000) != NET_SUCCESS) {
            if (addr) NET_UnrefAddress(addr);
            return false;
        }
        NET_StreamSocket *sock = NET_CreateClient(addr, port, 0);
        NET_UnrefAddress(addr);
        if (!sock) return false;
        clear_slot(&peer->slots[0]);
        net_slot_t *s = alloc_slot(peer);
        if (!s) { NET_DestroyStreamSocket(sock); return false; }
        s->ws_sock = sock;
        ws_pump_slot(peer, s);
        return true;
    }
    return false;
#else
    (void)remote_port;
    return false;
#endif
}

/* --------------------------------------------------------------------------
 * Send, Poll & Events
 * -------------------------------------------------------------------------- */
static bool send_on_slot(eng_net_peer_t *peer, net_slot_t *s, eng_net_channel_t channel,
                         const void *payload, size_t len) {
    if (!s || !s->active) return false;
    if (s->loop_peer) {
        uint32_t sender_cid = s->loop_peer->is_server ? s->loop_remote_id : 0u;
        push_evt(s->loop_peer, ENG_NET_EVT_MESSAGE, sender_cid, channel, payload, len);
        return true;
    }
#ifdef ENG_HAS_SDL3_NET
    if (peer->transport == ENG_NET_WEBSOCKET) return ws_send_app_msg(peer, s, channel, payload, len);
    if (peer->transport == ENG_NET_UDP) return udp_send_slot(peer, s, channel, payload, len);
#else
    (void)peer;
#endif
    return false;
}

bool eng_net_send_to(eng_net_peer_t *peer, uint32_t client_id, eng_net_channel_t channel,
                     const void *payload, size_t len) {
    if (!peer || (!payload && len > 0) || len > ENG_NET_MAX_MSG_SIZE) return false;
#ifdef __EMSCRIPTEN__
    if (peer->transport == ENG_NET_WEBSOCKET) {
        if (peer->em_ws <= 0 || !peer->connected) return false;
        uint8_t *buf = (uint8_t *)malloc(len + 1u);
        if (!buf) return false;
        buf[0] = (uint8_t)channel;
        if (len > 0) memcpy(buf + 1u, payload, len);
        EMSCRIPTEN_RESULT res = emscripten_websocket_send_binary(peer->em_ws, buf, (uint32_t)(len + 1u));
        free(buf);
        return res == EMSCRIPTEN_RESULT_SUCCESS;
    }
#endif
    if (client_id != 0) {
        return send_on_slot(peer, find_slot_by_id(peer, client_id), channel, payload, len);
    }
    bool any = false;
    for (int i = 0; i < ENG_NET_MAX_CLIENTS; i++) {
        if (peer->slots[i].active) {
            if (send_on_slot(peer, &peer->slots[i], channel, payload, len)) any = true;
        }
    }
    return any;
}

bool eng_net_send(eng_net_peer_t *peer, eng_net_channel_t channel, const void *payload, size_t len) {
    return eng_net_send_to(peer, 0, channel, payload, len);
}

static void pump_transport(eng_net_peer_t *peer) {
#ifdef ENG_HAS_SDL3_NET
    if (peer->transport == ENG_NET_WEBSOCKET) {
        if (peer->ws_server) {
            NET_StreamSocket *ns = NULL;
            while (NET_AcceptClient(peer->ws_server, &ns) && ns != NULL) {
                net_slot_t *s = alloc_slot(peer);
                if (!s) {
                    NET_DestroyStreamSocket(ns);
                } else {
                    s->ws_sock = ns;
                }
                ns = NULL;
            }
        }
        for (int i = 0; i < ENG_NET_MAX_CLIENTS; i++) {
            if (peer->slots[i].active) ws_pump_slot(peer, &peer->slots[i]);
        }
    } else if (peer->transport == ENG_NET_UDP) {
        udp_pump(peer);
    }
#else
    (void)peer;
#endif
}

bool eng_net_poll_event(eng_net_peer_t *peer, eng_net_event_t *out_evt, void *out_payload, size_t max_len) {
    if (!peer || !out_evt) return false;
    pump_transport(peer);
    if (peer->evt_count == 0) {
        out_evt->type = ENG_NET_EVT_NONE;
        out_evt->client_id = 0;
        out_evt->len = 0;
        return false;
    }
    queued_evt_t q = peer->evts[peer->evt_head];
    peer->evt_head = (peer->evt_head + 1u) % ENG_EVT_QUEUE_CAP;
    peer->evt_count--;

    out_evt->type = q.type;
    out_evt->client_id = q.client_id;
    out_evt->chan = q.chan;
    out_evt->len = 0;
    if (q.data && q.len > 0 && out_payload && max_len > 0) {
        size_t cp = q.len < max_len ? q.len : max_len;
        memcpy(out_payload, q.data, cp);
        out_evt->len = cp;
    }
    free(q.data);
    return true;
}

size_t eng_net_poll(eng_net_peer_t *peer, void *out_payload, size_t max_len, eng_net_channel_t *out_chan) {
    if (!peer || !out_payload || max_len == 0) return 0;
    eng_net_event_t evt;
    while (eng_net_poll_event(peer, &evt, out_payload, max_len)) {
        if (evt.type == ENG_NET_EVT_MESSAGE && evt.len > 0) {
            if (out_chan) *out_chan = evt.chan;
            return evt.len;
        }
    }
    return 0;
}

/* --------------------------------------------------------------------------
 * Pocket-Aware ECS Scene State Replication (up to 256 entities over WS/Loopback)
 * -------------------------------------------------------------------------- */
#define ENG_SNAP_SCHEMA 1u
#define ENG_SNAP_MAX_ENTS 256

bool eng_net_send_scene_snapshot_to(eng_net_peer_t *authority, uint32_t client_id, const eng_scene_t *scene) {
    if (!authority || !scene) return false;
    eng_ecs_t *ecs = eng_scene_ecs((eng_scene_t *)(uintptr_t)scene);
    eng_bin_writer_t w;
    if (!eng_bin_writer_init(&w, ENG_SNAP_SCHEMA, 1024)) return false;

    uint32_t cap = (authority->transport == ENG_NET_UDP) ? 24u : (uint32_t)ENG_SNAP_MAX_ENTS;
    eng_entity_t ents[ENG_SNAP_MAX_ENTS];
    uint32_t count = 0;
    eng_ecs_query_t q = eng_ecs_query_init(ecs, eng_ecs_comp_bit(eng_scene_comp_local(scene)), 0);
    eng_entity_t qe = ENG_ENTITY_NULL;
    while (count < cap && eng_ecs_query_next(&q, &qe)) {
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

    bool ok = !w.failed && eng_net_send_to(authority, client_id, ENG_CHAN_RELIABLE, w.buf, w.size);
    eng_bin_writer_destroy(&w);
    return ok;
}

bool eng_net_send_scene_snapshot(eng_net_peer_t *authority, const eng_scene_t *scene) {
    return eng_net_send_scene_snapshot_to(authority, 0, scene);
}

bool eng_net_apply_scene_snapshot(eng_scene_t *replica_scene, const void *payload, size_t len) {
    if (!replica_scene || !payload || len == 0) return false;
    eng_bin_reader_t r;
    if (!eng_bin_reader_init(&r, payload, len, ENG_SNAP_SCHEMA)) return false;

    uint32_t count = 0;
    if (!eng_bin_read_u32(&r, &count) || count > ENG_SNAP_MAX_ENTS) return false;
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
