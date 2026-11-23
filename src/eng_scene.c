#include "engine/eng_scene.h"
#include "engine/eng_log.h"
#include "engine/eng_mem.h"
#include "engine/eng_serde.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_POCKETS 64

typedef struct {
    eng_entity_t ent;
    uint32_t depth;
} eng_depth_node_t;

struct eng_scene_s {
    char name[64];
    eng_ecs_t *ecs;
    uint32_t max_entities;
    eng_comp_id_t cid_local;
    eng_comp_id_t cid_world;
    eng_entity_t *parents;
    uint32_t *depths;
    uint16_t *pockets;
    char pocket_names[ENG_MAX_POCKETS][48];
    uint16_t pocket_count;
    eng_depth_node_t *sorted_nodes;
    uint32_t sorted_count;
    bool order_dirty;
};

static int cmp_depth_node(const void *a, const void *b) {
    const eng_depth_node_t *na = (const eng_depth_node_t *)a;
    const eng_depth_node_t *nb = (const eng_depth_node_t *)b;
    return (na->depth > nb->depth) - (na->depth < nb->depth);
}

eng_scene_t *eng_scene_create(uint32_t max_entities) {
    if (max_entities == 0) return NULL;
    eng_scene_t *sc = (eng_scene_t *)calloc(1, sizeof(eng_scene_t));
    if (!sc) return NULL;
    snprintf(sc->name, sizeof(sc->name), "untitled");
    snprintf(sc->pocket_names[0], sizeof(sc->pocket_names[0]), "world");
    sc->pocket_count = 1;
    sc->max_entities = max_entities;
    sc->ecs = eng_ecs_create(max_entities);
    sc->parents = (eng_entity_t *)calloc(max_entities, sizeof(eng_entity_t));
    sc->depths = (uint32_t *)calloc(max_entities, sizeof(uint32_t));
    sc->pockets = (uint16_t *)calloc(max_entities, sizeof(uint16_t));
    sc->sorted_nodes = (eng_depth_node_t *)calloc(max_entities, sizeof(eng_depth_node_t));
    if (!sc->ecs || !sc->parents || !sc->depths || !sc->pockets || !sc->sorted_nodes) {
        eng_scene_destroy(sc);
        return NULL;
    }
    sc->cid_local = eng_ecs_register_component(sc->ecs, "TransformLocal", sizeof(eng_transform_local_t));
    sc->cid_world = eng_ecs_register_component(sc->ecs, "TransformWorld", sizeof(eng_transform_world_t));
    sc->order_dirty = true;
    return sc;
}

void eng_scene_destroy(eng_scene_t *scene) {
    if (!scene) return;
    eng_ecs_destroy(scene->ecs);
    free(scene->parents);
    free(scene->depths);
    free(scene->pockets);
    free(scene->sorted_nodes);
    free(scene);
}

eng_ecs_t *eng_scene_ecs(eng_scene_t *scene) { return scene ? scene->ecs : NULL; }
eng_comp_id_t eng_scene_comp_local(const eng_scene_t *scene) { return scene ? scene->cid_local : UINT32_MAX; }
eng_comp_id_t eng_scene_comp_world(const eng_scene_t *scene) { return scene ? scene->cid_world : UINT32_MAX; }
const char *eng_scene_name(const eng_scene_t *scene) { return scene ? scene->name : ""; }

uint16_t eng_scene_register_pocket(eng_scene_t *scene, const char *pocket_name) {
    if (!scene || !pocket_name || pocket_name[0] == '\0') return 0;
    for (uint16_t i = 0; i < scene->pocket_count; i++) {
        if (strcmp(scene->pocket_names[i], pocket_name) == 0) return i;
    }
    if (scene->pocket_count >= ENG_MAX_POCKETS) return 0;
    uint16_t id = scene->pocket_count++;
    snprintf(scene->pocket_names[id], sizeof(scene->pocket_names[0]), "%s", pocket_name);
    return id;
}

const char *eng_scene_pocket_name(const eng_scene_t *scene, uint16_t pocket_id) {
    if (!scene || pocket_id >= scene->pocket_count) return "world";
    return scene->pocket_names[pocket_id];
}

bool eng_scene_set_pocket(eng_scene_t *scene, eng_entity_t ent, uint16_t pocket_id) {
    if (!scene || !eng_ecs_alive(scene->ecs, ent) || pocket_id >= scene->pocket_count) return false;
    scene->pockets[(uint32_t)(ent & 0xFFFFFFFFu)] = pocket_id;
    return true;
}

uint16_t eng_scene_get_pocket(const eng_scene_t *scene, eng_entity_t ent) {
    if (!scene || !eng_ecs_alive(scene->ecs, ent)) return 0;
    return scene->pockets[(uint32_t)(ent & 0xFFFFFFFFu)];
}

eng_entity_t eng_scene_spawn(eng_scene_t *scene, const char *name) {
    if (!scene) return ENG_ENTITY_NULL;
    eng_entity_t ent = eng_ecs_spawn(scene->ecs, name);
    if (ent == ENG_ENTITY_NULL) return ENG_ENTITY_NULL;
    uint32_t slot = (uint32_t)(ent & 0xFFFFFFFFu);
    scene->parents[slot] = ENG_ENTITY_NULL;
    scene->depths[slot] = 0;
    scene->pockets[slot] = 0;

    eng_transform_local_t loc = {eng_v3(0.0f, 0.0f, 0.0f), eng_quat_identity(), eng_v3(1.0f, 1.0f, 1.0f)};
    eng_transform_world_t wrld = {eng_mat4_identity()};
    eng_ecs_add(scene->ecs, ent, scene->cid_local, &loc);
    eng_ecs_add(scene->ecs, ent, scene->cid_world, &wrld);
    scene->order_dirty = true;
    return ent;
}

bool eng_scene_despawn(eng_scene_t *scene, eng_entity_t ent) {
    if (!scene || !eng_ecs_alive(scene->ecs, ent)) return false;
    uint32_t slot = (uint32_t)(ent & 0xFFFFFFFFu);
    scene->parents[slot] = ENG_ENTITY_NULL;
    scene->depths[slot] = 0;
    scene->pockets[slot] = 0;
    for (uint32_t i = 0; i < scene->max_entities; i++) {
        if (scene->parents[i] == ent) {
            scene->parents[i] = ENG_ENTITY_NULL;
            scene->depths[i] = 0;
        }
    }
    scene->order_dirty = true;
    return eng_ecs_despawn(scene->ecs, ent);
}

bool eng_scene_set_local_pos(eng_scene_t *scene, eng_entity_t ent, eng_vec3_t pos) {
    if (!eng_v3_is_finite(pos)) {
        ENG_LOGE("scene", "NaN/Inf rejected in set_local_pos");
        return false;
    }
    eng_transform_local_t *t = scene ? (eng_transform_local_t *)eng_ecs_get(scene->ecs, ent, scene->cid_local) : NULL;
    if (!t) return false;
    t->pos = pos;
    return true;
}

bool eng_scene_set_local_rot(eng_scene_t *scene, eng_entity_t ent, eng_quat_t rot) {
    if (!eng_quat_is_finite(rot)) {
        ENG_LOGE("scene", "NaN/Inf rejected in set_local_rot");
        return false;
    }
    eng_transform_local_t *t = scene ? (eng_transform_local_t *)eng_ecs_get(scene->ecs, ent, scene->cid_local) : NULL;
    if (!t) return false;
    t->rot = eng_quat_norm(rot);
    return true;
}

bool eng_scene_set_local_scale(eng_scene_t *scene, eng_entity_t ent, eng_vec3_t scale) {
    if (!eng_v3_is_finite(scale)) {
        ENG_LOGE("scene", "NaN/Inf rejected in set_local_scale");
        return false;
    }
    eng_transform_local_t *t = scene ? (eng_transform_local_t *)eng_ecs_get(scene->ecs, ent, scene->cid_local) : NULL;
    if (!t) return false;
    t->scale = scale;
    return true;
}

const eng_transform_local_t *eng_scene_get_local(const eng_scene_t *scene, eng_entity_t ent) {
    return scene ? (const eng_transform_local_t *)eng_ecs_get(scene->ecs, ent, scene->cid_local) : NULL;
}

const eng_mat4_t *eng_scene_get_world_matrix(const eng_scene_t *scene, eng_entity_t ent) {
    const eng_transform_world_t *w = scene ? (const eng_transform_world_t *)eng_ecs_get(scene->ecs, ent, scene->cid_world) : NULL;
    return w ? &w->world : NULL;
}

bool eng_scene_set_parent(eng_scene_t *scene, eng_entity_t child, eng_entity_t parent) {
    if (!scene || !eng_ecs_alive(scene->ecs, child) || child == parent) return false;
    if (parent != ENG_ENTITY_NULL && !eng_ecs_alive(scene->ecs, parent)) return false;

    eng_entity_t cur = parent;
    while (cur != ENG_ENTITY_NULL) {
        if (cur == child) {
            ENG_LOGE("scene", "Hierarchy cycle rejected");
            return false;
        }
        cur = scene->parents[(uint32_t)(cur & 0xFFFFFFFFu)];
    }

    uint32_t child_slot = (uint32_t)(child & 0xFFFFFFFFu);
    scene->parents[child_slot] = parent;
    if (parent != ENG_ENTITY_NULL) {
        scene->pockets[child_slot] = scene->pockets[(uint32_t)(parent & 0xFFFFFFFFu)];
    }
    scene->order_dirty = true;
    return true;
}

eng_entity_t eng_scene_get_parent(const eng_scene_t *scene, eng_entity_t child) {
    if (!scene || !eng_ecs_alive(scene->ecs, child)) return ENG_ENTITY_NULL;
    return scene->parents[(uint32_t)(child & 0xFFFFFFFFu)];
}

static void rebuild_depth_order(eng_scene_t *scene) {
    const eng_entity_t *ents = NULL;
    uint32_t count = 0;
    eng_ecs_raw_column(scene->ecs, scene->cid_local, &ents, &count);
    scene->sorted_count = count;
    for (uint32_t i = 0; i < count; i++) {
        eng_entity_t e = ents[i];
        uint32_t d = 0;
        eng_entity_t p = scene->parents[(uint32_t)(e & 0xFFFFFFFFu)];
        while (p != ENG_ENTITY_NULL && eng_ecs_alive(scene->ecs, p)) {
            d++;
            p = scene->parents[(uint32_t)(p & 0xFFFFFFFFu)];
        }
        scene->depths[(uint32_t)(e & 0xFFFFFFFFu)] = d;
        scene->sorted_nodes[i].ent = e;
        scene->sorted_nodes[i].depth = d;
    }
    if (count > 1) {
        qsort(scene->sorted_nodes, count, sizeof(eng_depth_node_t), cmp_depth_node);
    }
    scene->order_dirty = false;
}

void eng_scene_update_transforms(eng_scene_t *scene) {
    if (!scene) return;
    if (scene->order_dirty) {
        rebuild_depth_order(scene);
    }
    for (uint32_t i = 0; i < scene->sorted_count; i++) {
        eng_entity_t ent = scene->sorted_nodes[i].ent;
        const eng_transform_local_t *loc = eng_scene_get_local(scene, ent);
        eng_transform_world_t *wrld = (eng_transform_world_t *)eng_ecs_get(scene->ecs, ent, scene->cid_world);
        if (!loc || !wrld) continue;
        eng_mat4_t local_m = eng_mat4_trs(loc->pos, loc->rot, loc->scale);
        eng_entity_t parent = scene->parents[(uint32_t)(ent & 0xFFFFFFFFu)];
        if (parent != ENG_ENTITY_NULL) {
            const eng_mat4_t *pm = eng_scene_get_world_matrix(scene, parent);
            wrld->world = pm ? eng_mat4_mul(pm, &local_m) : local_m;
        } else {
            wrld->world = local_m;
        }
    }
}

static const char *const k_scene_root_keys[] = {"name", "skybox", "entities"};
static const char *const k_entity_keys[] = {
    "name", "parent", "pocket", "tags", "transform", "camera", "light",
    "mesh", "sprite", "voxel", "portal", "procgen", "rigid_body", "collider",
    "audio_source", "nav_agent", "script"
};
static const char *const k_transform_keys[] = {"pos", "rot_deg", "scale"};

bool eng_scene_load_json(eng_scene_t *scene, const char *json_src, char *err_buf, size_t err_cap) {
    if (err_buf && err_cap > 0) err_buf[0] = '\0';
    if (!scene || !json_src) return false;

    eng_arena_t arena;
    if (!eng_arena_init(&arena, 256 * 1024)) return false;

    eng_json_val_t *root = eng_json_parse(&arena, json_src, err_buf, err_cap);
    if (!root || !eng_json_validate_keys(root, k_scene_root_keys, 3, err_buf, err_cap)) {
        eng_arena_destroy(&arena);
        return false;
    }

    const char *sname = eng_json_get_str(root, "name", NULL);
    const eng_json_val_t *ents = eng_json_get(root, "entities");
    if (!sname || !ents || ents->type != ENG_JSON_ARR) {
        if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "scene requires 'name' string and 'entities' array");
        eng_arena_destroy(&arena);
        return false;
    }
    snprintf(scene->name, sizeof(scene->name), "%s", sname);

    for (size_t i = 0; i < ents->u.arr.len; i++) {
        const eng_json_val_t *ej = ents->u.arr.items[i];
        if (!eng_json_validate_keys(ej, k_entity_keys, sizeof(k_entity_keys) / sizeof(k_entity_keys[0]), err_buf, err_cap)) {
            eng_arena_destroy(&arena);
            return false;
        }
        const char *ename = eng_json_get_str(ej, "name", NULL);
        if (!ename) {
            if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "entity[%zu] missing 'name'", i);
            eng_arena_destroy(&arena);
            return false;
        }
        eng_entity_t e = eng_scene_spawn(scene, ename);
        const char *pocket_str = eng_json_get_str(ej, "pocket", NULL);
        if (pocket_str) {
            eng_scene_set_pocket(scene, e, eng_scene_register_pocket(scene, pocket_str));
        }
        const eng_json_val_t *tr = eng_json_get(ej, "transform");
        if (tr) {
            if (!eng_json_validate_keys(tr, k_transform_keys, 3, err_buf, err_cap)) {
                eng_arena_destroy(&arena);
                return false;
            }
            eng_vec3_t pos = eng_json_get_v3(tr, "pos", eng_v3(0.0f, 0.0f, 0.0f));
            eng_vec3_t rot_deg = eng_json_get_v3(tr, "rot_deg", eng_v3(0.0f, 0.0f, 0.0f));
            eng_vec3_t scale = eng_json_get_v3(tr, "scale", eng_v3(1.0f, 1.0f, 1.0f));
            eng_scene_set_local_pos(scene, e, pos);
            eng_scene_set_local_rot(scene, e, eng_quat_from_euler_deg(rot_deg));
            eng_scene_set_local_scale(scene, e, scale);
        }
    }

    for (size_t i = 0; i < ents->u.arr.len; i++) {
        const eng_json_val_t *ej = ents->u.arr.items[i];
        const char *ename = eng_json_get_str(ej, "name", NULL);
        const char *pname = eng_json_get_str(ej, "parent", NULL);
        const char *explicit_pocket = eng_json_get_str(ej, "pocket", NULL);
        if (pname && pname[0] != '\0') {
            eng_entity_t child = eng_ecs_find_by_name(scene->ecs, ename);
            eng_entity_t parent = eng_ecs_find_by_name(scene->ecs, pname);
            if (parent == ENG_ENTITY_NULL || !eng_scene_set_parent(scene, child, parent)) {
                if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "invalid parent '%s' for '%s'", pname, ename);
                eng_arena_destroy(&arena);
                return false;
            }
            if (explicit_pocket) {
                eng_scene_set_pocket(scene, child, eng_scene_register_pocket(scene, explicit_pocket));
            }
        }
    }

    eng_arena_destroy(&arena);
    eng_scene_update_transforms(scene);
    return true;
}

size_t eng_scene_save_json(const eng_scene_t *scene, char *out_buf, size_t out_cap) {
    if (!out_buf || out_cap == 0) return 0;
    out_buf[0] = '\0';
    if (!scene) return 0;

    const eng_entity_t *ents = NULL;
    uint32_t count = 0;
    eng_ecs_raw_column(scene->ecs, scene->cid_local, &ents, &count);

    size_t pos = (size_t)snprintf(out_buf, out_cap, "{\n  \"name\": \"%s\",\n  \"entities\": [\n", scene->name);
    for (uint32_t i = 0; i < count && pos + 160 < out_cap; i++) {
        eng_entity_t e = ents[i];
        const char *ename = eng_ecs_get_name(scene->ecs, e);
        const eng_transform_local_t *loc = eng_scene_get_local(scene, e);
        eng_entity_t p = eng_scene_get_parent(scene, e);
        const char *pname = (p != ENG_ENTITY_NULL) ? eng_ecs_get_name(scene->ecs, p) : NULL;
        uint16_t pk = eng_scene_get_pocket(scene, e);
        const char *pkname = (pk > 0) ? eng_scene_pocket_name(scene, pk) : NULL;
        pos += (size_t)snprintf(
            out_buf + pos, out_cap - pos,
            "    {\"name\": \"%s\"%s%s%s%s%s%s, \"transform\": {\"pos\": [%.3f, %.3f, %.3f], \"scale\": [%.3f, %.3f, %.3f]}}%s\n",
            ename ? ename : "",
            pname ? ", \"parent\": \"" : "", pname ? pname : "", pname ? "\"" : "",
            pkname ? ", \"pocket\": \"" : "", pkname ? pkname : "", pkname ? "\"" : "",
            loc->pos.x, loc->pos.y, loc->pos.z,
            loc->scale.x, loc->scale.y, loc->scale.z,
            (i + 1 < count) ? "," : ""
        );
    }
    if (pos + 8 < out_cap) {
        pos += (size_t)snprintf(out_buf + pos, out_cap - pos, "  ]\n}\n");
    }
    return pos;
}
