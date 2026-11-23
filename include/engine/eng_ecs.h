#ifndef ENG_ECS_H
#define ENG_ECS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_ENTITY_NULL 0ULL
#define ENG_ECS_MAX_COMPONENTS 64

typedef uint64_t eng_entity_t;
typedef uint32_t eng_comp_id_t;
typedef struct eng_ecs_s eng_ecs_t;

typedef struct {
    const eng_ecs_t *ecs;
    uint64_t include_mask;
    uint64_t exclude_mask;
    eng_comp_id_t driver_comp;
    uint32_t cursor;
    bool use_all_entities;
} eng_ecs_query_t;

eng_ecs_t *eng_ecs_create(uint32_t max_entities);
void eng_ecs_destroy(eng_ecs_t *ecs);

/* Register a SoA component column; returns component ID in [0, 63], or UINT32_MAX on error. */
eng_comp_id_t eng_ecs_register_component(eng_ecs_t *ecs, const char *name, size_t elem_size);
eng_comp_id_t eng_ecs_find_component(const eng_ecs_t *ecs, const char *name);
uint64_t eng_ecs_comp_bit(eng_comp_id_t id);

eng_entity_t eng_ecs_spawn(eng_ecs_t *ecs, const char *name);
bool eng_ecs_despawn(eng_ecs_t *ecs, eng_entity_t ent);
bool eng_ecs_alive(const eng_ecs_t *ecs, eng_entity_t ent);
uint32_t eng_ecs_alive_count(const eng_ecs_t *ecs);

const char *eng_ecs_get_name(const eng_ecs_t *ecs, eng_entity_t ent);
eng_entity_t eng_ecs_find_by_name(const eng_ecs_t *ecs, const char *name);

void *eng_ecs_add(eng_ecs_t *ecs, eng_entity_t ent, eng_comp_id_t cid, const void *initial_val);
bool eng_ecs_remove(eng_ecs_t *ecs, eng_entity_t ent, eng_comp_id_t cid);
void *eng_ecs_get(const eng_ecs_t *ecs, eng_entity_t ent, eng_comp_id_t cid);
bool eng_ecs_has(const eng_ecs_t *ecs, eng_entity_t ent, eng_comp_id_t cid);

/* Direct dense SoA column access for branchless linear loops */
void *eng_ecs_raw_column(const eng_ecs_t *ecs, eng_comp_id_t cid, const eng_entity_t **out_entities, uint32_t *out_count);

/* Multi-component bitmask query */
eng_ecs_query_t eng_ecs_query_init(const eng_ecs_t *ecs, uint64_t include_mask, uint64_t exclude_mask);
bool eng_ecs_query_next(eng_ecs_query_t *q, eng_entity_t *out_ent);

/* Context-window-compact JSON snapshot of active entities for failure diagnostics */
size_t eng_ecs_dump_json(const eng_ecs_t *ecs, char *out_buf, size_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* ENG_ECS_H */
