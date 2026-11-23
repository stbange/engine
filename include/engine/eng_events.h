#ifndef ENG_EVENTS_H
#define ENG_EVENTS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_EVENT_MAX_PAYLOAD 64

typedef struct eng_events_s eng_events_t;
typedef void (*eng_event_fn)(uint32_t topic_id, const void *payload, size_t payload_size, void *userdata);

/* Compute deterministic FNV-1a 32-bit topic ID from string name. */
uint32_t eng_event_id(const char *topic_name);

eng_events_t *eng_events_create(void);
void eng_events_destroy(eng_events_t *bus);

uint32_t eng_events_subscribe(eng_events_t *bus, uint32_t topic_id, eng_event_fn fn, void *userdata);
bool eng_events_unsubscribe(eng_events_t *bus, uint32_t sub_id);

void eng_events_emit(eng_events_t *bus, uint32_t topic_id, const void *payload, size_t payload_size);
bool eng_events_enqueue(eng_events_t *bus, uint32_t topic_id, const void *payload, size_t payload_size);
size_t eng_events_flush(eng_events_t *bus);

#ifdef __cplusplus
}
#endif

#endif /* ENG_EVENTS_H */
