#include "engine/eng_events.h"

#include <stdlib.h>
#include <string.h>

#define ENG_MAX_SUBS 128
#define ENG_MAX_QUEUED_EVENTS 256

typedef struct {
    uint32_t sub_id;
    uint32_t topic_id;
    eng_event_fn fn;
    void *userdata;
    bool active;
} eng_sub_t;

typedef struct {
    uint32_t topic_id;
    uint8_t payload[ENG_EVENT_MAX_PAYLOAD];
    size_t size;
} eng_queued_ev_t;

struct eng_events_s {
    eng_sub_t subs[ENG_MAX_SUBS];
    uint32_t next_sub_id;
    eng_queued_ev_t queue[ENG_MAX_QUEUED_EVENTS];
    size_t queue_count;
};

uint32_t eng_event_id(const char *topic_name) {
    if (!topic_name) return 0;
    uint32_t hash = 2166136261u;
    for (const unsigned char *p = (const unsigned char *)topic_name; *p; p++) {
        hash ^= *p;
        hash *= 16777619u;
    }
    return hash ? hash : 1u;
}

eng_events_t *eng_events_create(void) {
    eng_events_t *bus = (eng_events_t *)calloc(1, sizeof(eng_events_t));
    if (bus) bus->next_sub_id = 1u;
    return bus;
}

void eng_events_destroy(eng_events_t *bus) {
    free(bus);
}

uint32_t eng_events_subscribe(eng_events_t *bus, uint32_t topic_id, eng_event_fn fn, void *userdata) {
    if (!bus || topic_id == 0 || !fn) return 0;
    for (size_t i = 0; i < ENG_MAX_SUBS; i++) {
        if (!bus->subs[i].active) {
            uint32_t id = bus->next_sub_id++;
            bus->subs[i].sub_id = id;
            bus->subs[i].topic_id = topic_id;
            bus->subs[i].fn = fn;
            bus->subs[i].userdata = userdata;
            bus->subs[i].active = true;
            return id;
        }
    }
    return 0;
}

bool eng_events_unsubscribe(eng_events_t *bus, uint32_t sub_id) {
    if (!bus || sub_id == 0) return false;
    for (size_t i = 0; i < ENG_MAX_SUBS; i++) {
        if (bus->subs[i].active && bus->subs[i].sub_id == sub_id) {
            bus->subs[i].active = false;
            return true;
        }
    }
    return false;
}

void eng_events_emit(eng_events_t *bus, uint32_t topic_id, const void *payload, size_t payload_size) {
    if (!bus || topic_id == 0) return;
    for (size_t i = 0; i < ENG_MAX_SUBS; i++) {
        if (bus->subs[i].active && bus->subs[i].topic_id == topic_id) {
            bus->subs[i].fn(topic_id, payload, payload_size, bus->subs[i].userdata);
        }
    }
}

bool eng_events_enqueue(eng_events_t *bus, uint32_t topic_id, const void *payload, size_t payload_size) {
    if (!bus || topic_id == 0 || payload_size > ENG_EVENT_MAX_PAYLOAD ||
        (!payload && payload_size > 0) || bus->queue_count >= ENG_MAX_QUEUED_EVENTS) {
        return false;
    }
    eng_queued_ev_t *ev = &bus->queue[bus->queue_count++];
    ev->topic_id = topic_id;
    ev->size = payload_size;
    if (payload_size > 0) {
        memcpy(ev->payload, payload, payload_size);
    }
    return true;
}

size_t eng_events_flush(eng_events_t *bus) {
    if (!bus) return 0;
    size_t n = bus->queue_count;
    /* Copy count locally and reset so handlers enqueuing next-frame events don't loop infinitely */
    eng_queued_ev_t snapshot[ENG_MAX_QUEUED_EVENTS];
    memcpy(snapshot, bus->queue, n * sizeof(eng_queued_ev_t));
    bus->queue_count = 0;
    for (size_t i = 0; i < n; i++) {
        eng_events_emit(bus, snapshot[i].topic_id, snapshot[i].payload, snapshot[i].size);
    }
    return n;
}
