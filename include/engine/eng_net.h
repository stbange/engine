#ifndef ENG_NET_H
#define ENG_NET_H

#include "eng_scene.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_NET_MAX_CLIENTS 16
#define ENG_NET_MAX_MSG_SIZE 65536

typedef enum {
    ENG_NET_LOOPBACK = 0,
    ENG_NET_UDP = 1,
    ENG_NET_WEBSOCKET = 2
} eng_net_transport_t;

typedef enum {
    ENG_CHAN_UNRELIABLE = 0,
    ENG_CHAN_RELIABLE = 1
} eng_net_channel_t;

typedef enum {
    ENG_NET_EVT_NONE = 0,
    ENG_NET_EVT_CONNECT = 1,
    ENG_NET_EVT_DISCONNECT = 2,
    ENG_NET_EVT_MESSAGE = 3
} eng_net_evt_type_t;

typedef struct {
    eng_net_evt_type_t type;
    uint32_t client_id; /* 1..ENG_NET_MAX_CLIENTS on server; 0 = server on client */
    eng_net_channel_t chan;
    size_t len;
} eng_net_event_t;

typedef struct eng_net_peer_s eng_net_peer_t;

/* Create a peer bound to local_port (0 = OS/ephemeral port for UDP/WS host, or unbound client when not hosting). */
eng_net_peer_t *eng_net_create(eng_net_transport_t transport, uint16_t local_port);
/* Host a multi-client server on bind_ip (NULL = all interfaces) and port (0 = auto free port). */
eng_net_peer_t *eng_net_host(eng_net_transport_t transport, const char *bind_ip, uint16_t port);
void eng_net_destroy(eng_net_peer_t *peer);

uint16_t eng_net_bound_port(const eng_net_peer_t *peer);
bool eng_net_is_server(const eng_net_peer_t *peer);
bool eng_net_is_connected(const eng_net_peer_t *peer);
size_t eng_net_client_count(const eng_net_peer_t *peer);
size_t eng_net_client_ids(const eng_net_peer_t *peer, uint32_t *out_ids, size_t max_out);
bool eng_net_disconnect_client(eng_net_peer_t *peer, uint32_t client_id);

/* Connect loopback peers in-memory (supports 1-to-1 and N-clients-to-1-server), or connect remote UDP/WebSocket. */
bool eng_net_connect_loopback(eng_net_peer_t *a, eng_net_peer_t *b);
bool eng_net_connect_remote(eng_net_peer_t *peer, const char *host_or_url, uint16_t remote_port);

/* Send payload: on client sends to server; on server client_id == 0 broadcasts to all clients. */
bool eng_net_send(eng_net_peer_t *peer, eng_net_channel_t channel, const void *payload, size_t len);
bool eng_net_send_to(eng_net_peer_t *peer, uint32_t client_id, eng_net_channel_t channel, const void *payload, size_t len);

/* Poll transport and pop next connect/disconnect/message event (copying message bytes into out_payload). */
bool eng_net_poll_event(eng_net_peer_t *peer, eng_net_event_t *out_evt, void *out_payload, size_t max_len);

/* Legacy message-only poll helper (skips connect/disconnect notifications; returns payload bytes or 0). */
size_t eng_net_poll(eng_net_peer_t *peer, void *out_payload, size_t max_len, eng_net_channel_t *out_chan);

/* Replicate active scene entities (including pocket_id & transforms) from authority -> replica(s). */
bool eng_net_send_scene_snapshot(eng_net_peer_t *authority, const eng_scene_t *scene);
bool eng_net_send_scene_snapshot_to(eng_net_peer_t *authority, uint32_t client_id, const eng_scene_t *scene);
bool eng_net_apply_scene_snapshot(eng_scene_t *replica_scene, const void *payload, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* ENG_NET_H */
