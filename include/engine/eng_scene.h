#ifndef ENG_SCENE_H
#define ENG_SCENE_H

#include "eng_ecs.h"
#include "eng_math.h"

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    eng_vec3_t pos;
    eng_quat_t rot;
    eng_vec3_t scale;
} eng_transform_local_t;

typedef struct {
    eng_mat4_t world;
} eng_transform_world_t;

typedef struct eng_scene_s eng_scene_t;

eng_scene_t *eng_scene_create(uint32_t max_entities);
void eng_scene_destroy(eng_scene_t *scene);

eng_ecs_t *eng_scene_ecs(eng_scene_t *scene);
eng_comp_id_t eng_scene_comp_local(const eng_scene_t *scene);
eng_comp_id_t eng_scene_comp_world(const eng_scene_t *scene);
const char *eng_scene_name(const eng_scene_t *scene);

/* Spawn an entity initialized with identity TransformLocal & TransformWorld. */
eng_entity_t eng_scene_spawn(eng_scene_t *scene, const char *name);
bool eng_scene_despawn(eng_scene_t *scene, eng_entity_t ent);

/* NaN/Inf-guarded transform setters */
bool eng_scene_set_local_pos(eng_scene_t *scene, eng_entity_t ent, eng_vec3_t pos);
bool eng_scene_set_local_rot(eng_scene_t *scene, eng_entity_t ent, eng_quat_t rot);
bool eng_scene_set_local_scale(eng_scene_t *scene, eng_entity_t ent, eng_vec3_t scale);
const eng_transform_local_t *eng_scene_get_local(const eng_scene_t *scene, eng_entity_t ent);
const eng_mat4_t *eng_scene_get_world_matrix(const eng_scene_t *scene, eng_entity_t ent);

/* Hierarchy management with cycle detection & single-pass depth-ordered propagation */
bool eng_scene_set_parent(eng_scene_t *scene, eng_entity_t child, eng_entity_t parent);
eng_entity_t eng_scene_get_parent(const eng_scene_t *scene, eng_entity_t child);
void eng_scene_update_transforms(eng_scene_t *scene);

/* Pocket-space ("Bigger on the Inside") spatial isolation (0 = "world") */
uint16_t eng_scene_register_pocket(eng_scene_t *scene, const char *pocket_name);
const char *eng_scene_pocket_name(const eng_scene_t *scene, uint16_t pocket_id);
bool eng_scene_set_pocket(eng_scene_t *scene, eng_entity_t ent, uint16_t pocket_id);
uint16_t eng_scene_get_pocket(const eng_scene_t *scene, eng_entity_t ent);

/* Strict-schema JSON scene import & export */
bool eng_scene_load_json(eng_scene_t *scene, const char *json_src, char *err_buf, size_t err_cap);
size_t eng_scene_save_json(const eng_scene_t *scene, char *out_buf, size_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* ENG_SCENE_H */
