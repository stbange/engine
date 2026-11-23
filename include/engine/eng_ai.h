#ifndef ENG_AI_H
#define ENG_AI_H

#include "eng_math.h"
#include "eng_portal.h"
#include "eng_scene.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------------------
 * 1. Multi-Pocket NavGrid / NavMesh A* + Funnel String-Pulling + Portal Links
 * -------------------------------------------------------------------------- */
typedef struct eng_nav_s eng_nav_t;

eng_nav_t *eng_nav_create(void);
void eng_nav_destroy(eng_nav_t *nav);

/* Register a walkable 2D/2.5D grid for pocket_id (walkable_cells[z * w + x] != 0 means walkable). */
bool eng_nav_set_grid(eng_nav_t *nav, uint16_t pocket_id, eng_vec3_t origin,
                      float cell_size, int w, int d, const uint8_t *walkable_cells);

/* Automatically connect walkable cells across all open passable portals in scene. */
size_t eng_nav_sync_portals(eng_nav_t *nav, const eng_scene_t *scene, const eng_portal_sys_t *portals);

/* Find string-pulled 3D path from (start_pocket, start_pos) to (goal_pocket, goal_pos).
 * Returns number of waypoints written (0 if unreachable). */
size_t eng_ai_find_path(const eng_nav_t *nav,
                        uint16_t start_pocket, eng_vec3_t start_pos,
                        uint16_t goal_pocket, eng_vec3_t goal_pos,
                        eng_vec3_t *out_waypoints, uint16_t *out_pockets,
                        size_t max_waypoints);

/* --------------------------------------------------------------------------
 * 2. Behavior Tree + Entity Blackboard
 * -------------------------------------------------------------------------- */
typedef enum {
    ENG_BT_SUCCESS = 0,
    ENG_BT_FAILURE = 1,
    ENG_BT_RUNNING = 2
} eng_bt_status_t;

typedef enum {
    ENG_BT_SEQUENCE = 0,
    ENG_BT_SELECTOR,
    ENG_BT_INVERTER,
    ENG_BT_ACTION
} eng_bt_node_type_t;

typedef struct eng_blackboard_s {
    char keys[16][24];
    float values[16];
    size_t count;
} eng_blackboard_t;

typedef eng_bt_status_t (*eng_bt_action_fn)(eng_blackboard_t *bb, float dt, void *userdata);
typedef struct eng_bt_s eng_bt_t;

void eng_bb_init(eng_blackboard_t *bb);
void eng_bb_set(eng_blackboard_t *bb, const char *key, float value);
float eng_bb_get(const eng_blackboard_t *bb, const char *key, float fallback);

eng_bt_t *eng_bt_create(void);
void eng_bt_destroy(eng_bt_t *bt);

int eng_bt_add_composite(eng_bt_t *bt, int parent_idx, eng_bt_node_type_t type);
int eng_bt_add_action(eng_bt_t *bt, int parent_idx, eng_bt_action_fn fn, void *userdata);
eng_bt_status_t eng_bt_tick(eng_bt_t *bt, int root_idx, eng_blackboard_t *bb, float dt);

#ifdef __cplusplus
}
#endif

#endif /* ENG_AI_H */
