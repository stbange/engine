#ifndef ENG_NET_H
#define ENG_NET_H

#include "eng_scene.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_NET_LOOPBACK = 0,
    ENG_NET_UDP = 1,
    ENG_NET_WEBSOCKET = 2
} eng_net_transport_t;

typedef enum {
    ENG_CHAN_UNRELIABLE = 0,
    ENG_CHAN_RELIABLE = 1
} eng_net_channel_t;

typedef struct eng_net_peer_s eng_net_peer_t;

/* Create a peer bound to local_port (0 = OS ephemeral port for UDP, ignored for loopback/ws). */
eng_net_peer_t *eng_net_create(eng_net_transport_t transport, uint16_t local_port);
void eng_net_destroy(eng_net_peer_t *peer);

uint16_t eng_net_bound_port(const eng_net_peer_t *peer);

/* Connect loopback peers in-memory, or set target host:port / ws:// URL for UDP/WebSocket. */
bool eng_net_connect_loopback(eng_net_peer_t *a, eng_net_peer_t *b);
bool eng_net_connect_remote(eng_net_peer_t *peer, const char *host_or_url, uint16_t remote_port);

bool eng_net_send(eng_net_peer_t *peer, eng_net_channel_t channel, const void *payload, size_t len);

/* Poll transport, process ACKs & retransmissions, and pop next payload (returns 0 if none ready). */
size_t eng_net_poll(eng_net_peer_t *peer, void *out_payload, size_t max_len, eng_net_channel_t *out_chan);

/* Replicate active scene entities (including pocket_id & transforms) from authority -> replica. */
bool eng_net_send_scene_snapshot(eng_net_peer_t *authority, const eng_scene_t *scene);
bool eng_net_apply_scene_snapshot(eng_scene_t *replica_scene, const void *payload, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* ENG_NET_H */
