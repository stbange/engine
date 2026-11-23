#include "engine/eng_ecs.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_SPARSE_NIL UINT32_MAX

typedef struct {
    char name[48];
    size_t elem_size;
    uint8_t *dense_data;
    eng_entity_t *dense_entities;
    uint32_t *sparse;
    uint32_t count;
    bool registered;
} eng_comp_pool_t;

struct eng_ecs_s {
    uint32_t max_entities;
    uint32_t *generations;
    uint32_t *free_slots;
    uint32_t free_top;
    bool *alive;
    uint64_t *masks;
    char (*names)[48];
    uint32_t alive_count;
    eng_comp_pool_t comps[ENG_ECS_MAX_COMPONENTS];
    uint32_t comp_count;
};

static bool unpack_entity(const eng_ecs_t *ecs, eng_entity_t ent, uint32_t *out_slot) {
    if (!ecs || ent == ENG_ENTITY_NULL) return false;
    uint32_t slot = (uint32_t)(ent & 0xFFFFFFFFu);
    uint32_t gen = (uint32_t)(ent >> 32);
    if (slot >= ecs->max_entities || !ecs->alive[slot] || ecs->generations[slot] != gen) {
        return false;
    }
    *out_slot = slot;
    return true;
}

eng_ecs_t *eng_ecs_create(uint32_t max_entities) {
    if (max_entities == 0) return NULL;
    eng_ecs_t *ecs = (eng_ecs_t *)calloc(1, sizeof(eng_ecs_t));
    if (!ecs) return NULL;
    ecs->max_entities = max_entities;
    ecs->generations = (uint32_t *)calloc(max_entities, sizeof(uint32_t));
    ecs->free_slots = (uint32_t *)malloc(max_entities * sizeof(uint32_t));
    ecs->alive = (bool *)calloc(max_entities, sizeof(bool));
    ecs->masks = (uint64_t *)calloc(max_entities, sizeof(uint64_t));
    ecs->names = (char (*)[48])calloc(max_entities, sizeof(*ecs->names));
    if (!ecs->generations || !ecs->free_slots || !ecs->alive || !ecs->masks || !ecs->names) {
        eng_ecs_destroy(ecs);
        return NULL;
    }
    ecs->free_top = max_entities;
    for (uint32_t i = 0; i < max_entities; i++) {
        ecs->generations[i] = 1u;
        ecs->free_slots[i] = max_entities - 1u - i;
    }
    return ecs;
}

void eng_ecs_destroy(eng_ecs_t *ecs) {
    if (!ecs) return;
    for (uint32_t c = 0; c < ecs->comp_count; c++) {
        free(ecs->comps[c].dense_data);
        free(ecs->comps[c].dense_entities);
        free(ecs->comps[c].sparse);
    }
    free(ecs->generations);
    free(ecs->free_slots);
    free(ecs->alive);
    free(ecs->masks);
    free(ecs->names);
    free(ecs);
}

eng_comp_id_t eng_ecs_register_component(eng_ecs_t *ecs, const char *name, size_t elem_size) {
    if (!ecs || !name || name[0] == '\0' || elem_size == 0 || ecs->comp_count >= ENG_ECS_MAX_COMPONENTS) {
        return UINT32_MAX;
    }
    if (eng_ecs_find_component(ecs, name) != UINT32_MAX) {
        return UINT32_MAX;
    }
    eng_comp_id_t id = ecs->comp_count;
    eng_comp_pool_t *cp = &ecs->comps[id];
    snprintf(cp->name, sizeof(cp->name), "%s", name);
    cp->elem_size = elem_size;
    cp->dense_data = (uint8_t *)calloc(ecs->max_entities, elem_size);
    cp->dense_entities = (eng_entity_t *)calloc(ecs->max_entities, sizeof(eng_entity_t));
    cp->sparse = (uint32_t *)malloc(ecs->max_entities * sizeof(uint32_t));
    if (!cp->dense_data || !cp->dense_entities || !cp->sparse) {
        free(cp->dense_data);
        free(cp->dense_entities);
        free(cp->sparse);
        memset(cp, 0, sizeof(*cp));
        return UINT32_MAX;
    }
    for (uint32_t i = 0; i < ecs->max_entities; i++) {
        cp->sparse[i] = ENG_SPARSE_NIL;
    }
    cp->registered = true;
    ecs->comp_count++;
    return id;
}

eng_comp_id_t eng_ecs_find_component(const eng_ecs_t *ecs, const char *name) {
    if (!ecs || !name) return UINT32_MAX;
    for (uint32_t i = 0; i < ecs->comp_count; i++) {
        if (strcmp(ecs->comps[i].name, name) == 0) return i;
    }
    return UINT32_MAX;
}

uint64_t eng_ecs_comp_bit(eng_comp_id_t id) {
    return (id < ENG_ECS_MAX_COMPONENTS) ? (1ULL << id) : 0ULL;
}

eng_entity_t eng_ecs_spawn(eng_ecs_t *ecs, const char *name) {
    if (!ecs || ecs->free_top == 0) return ENG_ENTITY_NULL;
    uint32_t slot = ecs->free_slots[--ecs->free_top];
    ecs->alive[slot] = true;
    ecs->masks[slot] = 0ULL;
    ecs->names[slot][0] = '\0';
    if (name) {
        snprintf(ecs->names[slot], sizeof(ecs->names[slot]), "%s", name);
    }
    ecs->alive_count++;
    return ((uint64_t)ecs->generations[slot] << 32) | (uint64_t)slot;
}

bool eng_ecs_despawn(eng_ecs_t *ecs, eng_entity_t ent) {
    uint32_t slot = 0;
    if (!unpack_entity(ecs, ent, &slot)) return false;
    uint64_t mask = ecs->masks[slot];
    for (uint32_t cid = 0; cid < ecs->comp_count && mask != 0; cid++) {
        if (mask & (1ULL << cid)) {
            eng_ecs_remove(ecs, ent, cid);
            mask &= ~(1ULL << cid);
        }
    }
    ecs->alive[slot] = false;
    ecs->names[slot][0] = '\0';
    ecs->generations[slot]++;
    if (ecs->generations[slot] == 0) ecs->generations[slot] = 1u;
    ecs->free_slots[ecs->free_top++] = slot;
    ecs->alive_count--;
    return true;
}

bool eng_ecs_alive(const eng_ecs_t *ecs, eng_entity_t ent) {
    uint32_t slot = 0;
    return unpack_entity(ecs, ent, &slot);
}

uint32_t eng_ecs_alive_count(const eng_ecs_t *ecs) {
    return ecs ? ecs->alive_count : 0;
}

const char *eng_ecs_get_name(const eng_ecs_t *ecs, eng_entity_t ent) {
    uint32_t slot = 0;
    if (!unpack_entity(ecs, ent, &slot)) return NULL;
    return ecs->names[slot];
}

eng_entity_t eng_ecs_find_by_name(const eng_ecs_t *ecs, const char *name) {
    if (!ecs || !name || name[0] == '\0') return ENG_ENTITY_NULL;
    for (uint32_t slot = 0; slot < ecs->max_entities; slot++) {
        if (ecs->alive[slot] && strcmp(ecs->names[slot], name) == 0) {
            return ((uint64_t)ecs->generations[slot] << 32) | (uint64_t)slot;
        }
    }
    return ENG_ENTITY_NULL;
}

void *eng_ecs_add(eng_ecs_t *ecs, eng_entity_t ent, eng_comp_id_t cid, const void *initial_val) {
    uint32_t slot = 0;
    if (!unpack_entity(ecs, ent, &slot) || cid >= ecs->comp_count) return NULL;
    eng_comp_pool_t *cp = &ecs->comps[cid];
    uint32_t dense_idx = cp->sparse[slot];
    if (dense_idx == ENG_SPARSE_NIL) {
        dense_idx = cp->count++;
        cp->sparse[slot] = dense_idx;
        cp->dense_entities[dense_idx] = ent;
        ecs->masks[slot] |= (1ULL << cid);
    }
    void *dst = cp->dense_data + ((size_t)dense_idx * cp->elem_size);
    if (initial_val) {
        memcpy(dst, initial_val, cp->elem_size);
    } else {
        memset(dst, 0, cp->elem_size);
    }
    return dst;
}

bool eng_ecs_remove(eng_ecs_t *ecs, eng_entity_t ent, eng_comp_id_t cid) {
    uint32_t slot = 0;
    if (!unpack_entity(ecs, ent, &slot) || cid >= ecs->comp_count) return false;
    eng_comp_pool_t *cp = &ecs->comps[cid];
    uint32_t dense_idx = cp->sparse[slot];
    if (dense_idx == ENG_SPARSE_NIL) return false;

    uint32_t last_idx = --cp->count;
    if (dense_idx != last_idx) {
        eng_entity_t moved_ent = cp->dense_entities[last_idx];
        uint32_t moved_slot = (uint32_t)(moved_ent & 0xFFFFFFFFu);
        memcpy(cp->dense_data + ((size_t)dense_idx * cp->elem_size),
               cp->dense_data + ((size_t)last_idx * cp->elem_size),
               cp->elem_size);
        cp->dense_entities[dense_idx] = moved_ent;
        cp->sparse[moved_slot] = dense_idx;
    }
    cp->sparse[slot] = ENG_SPARSE_NIL;
    ecs->masks[slot] &= ~(1ULL << cid);
    return true;
}

void *eng_ecs_get(const eng_ecs_t *ecs, eng_entity_t ent, eng_comp_id_t cid) {
    uint32_t slot = 0;
    if (!unpack_entity(ecs, ent, &slot) || cid >= ecs->comp_count) return NULL;
    const eng_comp_pool_t *cp = &ecs->comps[cid];
    uint32_t dense_idx = cp->sparse[slot];
    if (dense_idx == ENG_SPARSE_NIL) return NULL;
    return cp->dense_data + ((size_t)dense_idx * cp->elem_size);
}

bool eng_ecs_has(const eng_ecs_t *ecs, eng_entity_t ent, eng_comp_id_t cid) {
    return eng_ecs_get(ecs, ent, cid) != NULL;
}

void *eng_ecs_raw_column(const eng_ecs_t *ecs, eng_comp_id_t cid, const eng_entity_t **out_entities, uint32_t *out_count) {
    if (!ecs || cid >= ecs->comp_count) {
        if (out_entities) *out_entities = NULL;
        if (out_count) *out_count = 0;
        return NULL;
    }
    const eng_comp_pool_t *cp = &ecs->comps[cid];
    if (out_entities) *out_entities = cp->dense_entities;
    if (out_count) *out_count = cp->count;
    return cp->dense_data;
}

eng_ecs_query_t eng_ecs_query_init(const eng_ecs_t *ecs, uint64_t include_mask, uint64_t exclude_mask) {
    eng_ecs_query_t q = {ecs, include_mask, exclude_mask, UINT32_MAX, 0, false};
    if (!ecs) return q;
    if (include_mask == 0ULL) {
        q.use_all_entities = true;
        return q;
    }
    uint32_t best_count = UINT32_MAX;
    for (uint32_t cid = 0; cid < ecs->comp_count; cid++) {
        if (include_mask & (1ULL << cid)) {
            if (ecs->comps[cid].count < best_count) {
                best_count = ecs->comps[cid].count;
                q.driver_comp = cid;
            }
        }
    }
    return q;
}

bool eng_ecs_query_next(eng_ecs_query_t *q, eng_entity_t *out_ent) {
    if (!q || !q->ecs || !out_ent) return false;
    const eng_ecs_t *ecs = q->ecs;
    if (q->use_all_entities) {
        while (q->cursor < ecs->max_entities) {
            uint32_t slot = q->cursor++;
            if (ecs->alive[slot] && (ecs->masks[slot] & q->exclude_mask) == 0ULL) {
                *out_ent = ((uint64_t)ecs->generations[slot] << 32) | (uint64_t)slot;
                return true;
            }
        }
        return false;
    }
    if (q->driver_comp >= ecs->comp_count) return false;
    const eng_comp_pool_t *cp = &ecs->comps[q->driver_comp];
    while (q->cursor < cp->count) {
        eng_entity_t ent = cp->dense_entities[q->cursor++];
        uint32_t slot = (uint32_t)(ent & 0xFFFFFFFFu);
        uint64_t m = ecs->masks[slot];
        if ((m & q->include_mask) == q->include_mask && (m & q->exclude_mask) == 0ULL) {
            *out_ent = ent;
            return true;
        }
    }
    return false;
}

size_t eng_ecs_dump_json(const eng_ecs_t *ecs, char *out_buf, size_t out_cap) {
    if (!out_buf || out_cap == 0) return 0;
    out_buf[0] = '\0';
    if (!ecs) return 0;
    size_t pos = (size_t)snprintf(out_buf, out_cap, "{\"alive\":%u,\"entities\":[", ecs->alive_count);
    bool first = true;
    for (uint32_t slot = 0; slot < ecs->max_entities && pos + 64 < out_cap; slot++) {
        if (!ecs->alive[slot]) continue;
        pos += (size_t)snprintf(out_buf + pos, out_cap - pos,
                                "%s{\"slot\":%u,\"name\":\"%s\",\"mask\":%llu}",
                                first ? "" : ",", slot, ecs->names[slot],
                                (unsigned long long)ecs->masks[slot]);
        first = false;
    }
    if (pos + 3 < out_cap) {
        pos += (size_t)snprintf(out_buf + pos, out_cap - pos, "]}");
    }
    return pos;
}
