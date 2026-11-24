#include "engine/eng_ai.h"

#include <float.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_NAV_GRIDS 16
#define ENG_MAX_NAV_LINKS 64
#define ENG_MAX_BT_NODES 128

typedef struct {
    bool valid;
    uint16_t pocket_id;
    eng_vec3_t origin;
    float cell_size;
    int w, d;
    uint8_t *walk;
    int base_node;
} nav_grid_t;

typedef struct {
    int src_node;
    int dst_node;
    float cost;
} nav_link_t;

struct eng_nav_s {
    nav_grid_t grids[ENG_MAX_NAV_GRIDS];
    size_t grid_count;
    int total_nodes;
    nav_link_t links[ENG_MAX_NAV_LINKS];
    size_t link_count;
};

eng_nav_t *eng_nav_create(void) {
    return (eng_nav_t *)calloc(1, sizeof(eng_nav_t));
}

void eng_nav_destroy(eng_nav_t *nav) {
    if (!nav) return;
    for (size_t i = 0; i < nav->grid_count; i++) free(nav->grids[i].walk);
    free(nav);
}

bool eng_nav_set_grid(eng_nav_t *nav, uint16_t pocket_id, eng_vec3_t origin,
                      float cell_size, int w, int d, const uint8_t *walkable_cells) {
    if (!nav || w < 2 || d < 2 || cell_size <= 0.05f || !walkable_cells) return false;
    nav_grid_t *g = NULL;
    for (size_t i = 0; i < nav->grid_count; i++) {
        if (nav->grids[i].valid && nav->grids[i].pocket_id == pocket_id) { g = &nav->grids[i]; break; }
    }
    if (!g && nav->grid_count >= ENG_MAX_NAV_GRIDS) return false;
    uint8_t *buf = (uint8_t *)malloc((size_t)(w * d));
    if (!buf) return false;
    memcpy(buf, walkable_cells, (size_t)(w * d));
    if (!g) {
        g = &nav->grids[nav->grid_count++];
    } else {
        free(g->walk);
        nav->link_count = 0; /* Invalidate stale node links when a pocket grid is replaced */
    }
    g->valid = true;
    g->pocket_id = pocket_id;
    g->origin = origin;
    g->cell_size = cell_size;
    g->w = w;
    g->d = d;
    g->walk = buf;
    nav->total_nodes = 0;
    for (size_t i = 0; i < nav->grid_count; i++) {
        nav->grids[i].base_node = nav->total_nodes;
        nav->total_nodes += nav->grids[i].w * nav->grids[i].d;
    }
    return true;
}

static const nav_grid_t *find_grid_by_pocket(const eng_nav_t *nav, uint16_t pocket_id) {
    for (size_t i = 0; i < nav->grid_count; i++) {
        if (nav->grids[i].valid && nav->grids[i].pocket_id == pocket_id) return &nav->grids[i];
    }
    return NULL;
}

static const nav_grid_t *find_grid_by_node(const eng_nav_t *nav, int node) {
    for (size_t i = 0; i < nav->grid_count; i++) {
        const nav_grid_t *g = &nav->grids[i];
        if (node >= g->base_node && node < g->base_node + g->w * g->d) return g;
    }
    return NULL;
}

static eng_vec3_t node_world_pos(const nav_grid_t *g, int node) {
    int local = node - g->base_node;
    int x = local % g->w, z = local / g->w;
    return eng_v3(g->origin.x + ((float)x + 0.5f) * g->cell_size,
                  g->origin.y,
                  g->origin.z + ((float)z + 0.5f) * g->cell_size);
}

static int closest_walkable_node(const nav_grid_t *g, eng_vec3_t pos) {
    int gx = (int)floorf((pos.x - g->origin.x) / g->cell_size);
    int gz = (int)floorf((pos.z - g->origin.z) / g->cell_size);
    gx = gx < 0 ? 0 : (gx >= g->w ? g->w - 1 : gx);
    gz = gz < 0 ? 0 : (gz >= g->d ? g->d - 1 : gz);
    if (g->walk[gz * g->w + gx]) return g->base_node + gz * g->w + gx;

    int best = -1;
    int best_d2 = 1000000;
    for (int z = 0; z < g->d; z++) {
        for (int x = 0; x < g->w; x++) {
            if (!g->walk[z * g->w + x]) continue;
            int d2 = (x - gx) * (x - gx) + (z - gz) * (z - gz);
            if (d2 < best_d2) { best_d2 = d2; best = g->base_node + z * g->w + x; }
        }
    }
    return best;
}

size_t eng_nav_sync_portals(eng_nav_t *nav, const eng_scene_t *scene, const eng_portal_sys_t *portals) {
    if (!nav) return 0;
    nav->link_count = 0;
    if (!scene || !portals) return 0;

    size_t pc = eng_portal_count(portals);
    for (size_t i = 0; i < pc && nav->link_count < ENG_MAX_NAV_LINKS; i++) {
        const eng_portal_t *p = eng_portal_get(portals, i);
        if (!p || !p->passable) continue;
        const nav_grid_t *gs = find_grid_by_pocket(nav, p->src_pocket);
        const nav_grid_t *gd = find_grid_by_pocket(nav, p->dst_pocket);
        const eng_mat4_t *ms = eng_scene_get_world_matrix(scene, p->src_ent);
        const eng_mat4_t *md = eng_scene_get_world_matrix(scene, p->dst_ent);
        if (!gs || !gd || !ms || !md) continue;

        int ns = closest_walkable_node(gs, eng_v3(ms->m[12], ms->m[13], ms->m[14]));
        int nd = closest_walkable_node(gd, eng_v3(md->m[12], md->m[13], md->m[14]));
        if (ns >= 0 && nd >= 0) {
            nav->links[nav->link_count++] = (nav_link_t){ns, nd, gs->cell_size};
        }
    }
    return nav->link_count;
}

static bool grid_los_clear(const nav_grid_t *g, eng_vec3_t a, eng_vec3_t b) {
    float dist = eng_v3_len(eng_v3_sub(b, a));
    int steps = (int)ceilf(dist / (g->cell_size * 0.25f));
    float m = g->cell_size * 0.24f;
    static const float ox[4] = {-1.0f, 1.0f, -1.0f, 1.0f}, oz[4] = {-1.0f, -1.0f, 1.0f, 1.0f};
    for (int s = 1; s < steps; s++) {
        eng_vec3_t p = eng_v3_lerp(a, b, (float)s / (float)steps);
        for (int k = 0; k < 4; k++) {
            int gx = (int)floorf((p.x + ox[k] * m - g->origin.x) / g->cell_size);
            int gz = (int)floorf((p.z + oz[k] * m - g->origin.z) / g->cell_size);
            if (gx < 0 || gz < 0 || gx >= g->w || gz >= g->d || !g->walk[gz * g->w + gx]) return false;
        }
    }
    return true;
}

size_t eng_ai_find_path(const eng_nav_t *nav,
                        uint16_t start_pocket, eng_vec3_t start_pos,
                        uint16_t goal_pocket, eng_vec3_t goal_pos,
                        eng_vec3_t *out_waypoints, uint16_t *out_pockets,
                        size_t max_waypoints) {
    if (!nav || !out_waypoints || max_waypoints == 0 || nav->total_nodes <= 0) return 0;
    const nav_grid_t *gs = find_grid_by_pocket(nav, start_pocket);
    const nav_grid_t *gg = find_grid_by_pocket(nav, goal_pocket);
    if (!gs || !gg) return 0;

    int start_n = closest_walkable_node(gs, start_pos);
    int goal_n  = closest_walkable_node(gg, goal_pos);
    if (start_n < 0 || goal_n < 0) return 0;

    int total = nav->total_nodes;
    float *g_score = (float *)malloc((size_t)total * sizeof(float));
    float *f_score = (float *)malloc((size_t)total * sizeof(float));
    int *came_from = (int *)malloc((size_t)total * sizeof(int));
    uint8_t *state = (uint8_t *)calloc((size_t)total, 1); /* 0=unseen, 1=open, 2=closed */
    if (!g_score || !f_score || !came_from || !state) {
        free(g_score); free(f_score); free(came_from); free(state);
        return 0;
    }
    for (int i = 0; i < total; i++) { g_score[i] = FLT_MAX; f_score[i] = FLT_MAX; came_from[i] = -1; }

    g_score[start_n] = 0.0f;
    f_score[start_n] = (start_pocket == goal_pocket) ? eng_v3_len(eng_v3_sub(goal_pos, start_pos)) : 0.0f;
    state[start_n] = 1u;

    bool found = false;
    while (true) {
        int cur = -1;
        float best_f = FLT_MAX;
        for (int i = 0; i < total; i++) {
            if (state[i] == 1u && f_score[i] < best_f) { best_f = f_score[i]; cur = i; }
        }
        if (cur < 0) break;
        if (cur == goal_n) { found = true; break; }
        state[cur] = 2u;

        const nav_grid_t *cg = find_grid_by_node(nav, cur);
        if (!cg) continue;
        int loc = cur - cg->base_node;
        int cx = loc % cg->w, cz = loc / cg->w;

        /* 8-connected grid neighbors (diagonal blocked if corner-cutting wall) */
        static const int dx[8] = {1, -1, 0, 0, 1, 1, -1, -1};
        static const int dz[8] = {0, 0, 1, -1, 1, -1, 1, -1};
        for (int k = 0; k < 8; k++) {
            int nx = cx + dx[k], nz = cz + dz[k];
            if (nx < 0 || nz < 0 || nx >= cg->w || nz >= cg->d || !cg->walk[nz * cg->w + nx]) continue;
            if (k >= 4 && (!cg->walk[cz * cg->w + nx] || !cg->walk[nz * cg->w + cx])) continue;

            int nb = cg->base_node + nz * cg->w + nx;
            if (state[nb] == 2u) continue;
            float step_c = (k < 4 ? 1.0f : 1.4142135f) * cg->cell_size;
            float ng = g_score[cur] + step_c;
            if (ng < g_score[nb]) {
                came_from[nb] = cur;
                g_score[nb] = ng;
                float h = (cg->pocket_id == goal_pocket) ? eng_v3_len(eng_v3_sub(goal_pos, node_world_pos(cg, nb))) : 0.0f;
                f_score[nb] = ng + h;
                state[nb] = 1u;
            }
        }

        /* Off-mesh bi-directional portal links */
        for (size_t l = 0; l < nav->link_count; l++) {
            if (nav->links[l].src_node != cur) continue;
            int nb = nav->links[l].dst_node;
            if (state[nb] == 2u) continue;
            float ng = g_score[cur] + nav->links[l].cost;
            if (ng < g_score[nb]) {
                const nav_grid_t *ngrid = find_grid_by_node(nav, nb);
                came_from[nb] = cur;
                g_score[nb] = ng;
                float h = (ngrid && ngrid->pocket_id == goal_pocket)
                              ? eng_v3_len(eng_v3_sub(goal_pos, node_world_pos(ngrid, nb)))
                              : 0.0f;
                f_score[nb] = ng + h;
                state[nb] = 1u;
            }
        }
    }

    size_t out_n = 0;
    if (found) {
        int *raw = (int *)malloc((size_t)total * sizeof(int));
        int rlen = 0;
        for (int c = goal_n; c >= 0; c = came_from[c]) raw[rlen++] = c;
        /* Reverse raw[0..rlen-1] in place */
        for (int i = 0; i < rlen / 2; i++) { int t = raw[i]; raw[i] = raw[rlen - 1 - i]; raw[rlen - 1 - i] = t; }

        /* String-pull within same-pocket segments, preserving exact portal transition waypoints */
        int idx = 0;
        while (idx < rlen && out_n < max_waypoints) {
            const nav_grid_t *g_cur = find_grid_by_node(nav, raw[idx]);
            eng_vec3_t wp = (idx == rlen - 1) ? goal_pos : node_world_pos(g_cur, raw[idx]);
            out_waypoints[out_n] = wp;
            if (out_pockets) out_pockets[out_n] = g_cur->pocket_id;
            out_n++;
            if (idx == rlen - 1) break;

            int next_idx = idx + 1;
            while (next_idx + 1 < rlen) {
                const nav_grid_t *g_test = find_grid_by_node(nav, raw[next_idx + 1]);
                if (g_test != g_cur) break; /* Stop string-pulling at portal jump */
                eng_vec3_t cand_p = (next_idx + 1 == rlen - 1) ? goal_pos : node_world_pos(g_cur, raw[next_idx + 1]);
                if (!grid_los_clear(g_cur, wp, cand_p)) break;
                next_idx++;
            }
            idx = next_idx;
        }
        free(raw);
    }

    free(g_score); free(f_score); free(came_from); free(state);
    return out_n;
}

/* --------------------------------------------------------------------------
 * Behavior Tree + Blackboard
 * -------------------------------------------------------------------------- */
typedef struct {
    eng_bt_node_type_t type;
    int children[8];
    int child_count;
    eng_bt_action_fn fn;
    void *userdata;
} bt_node_t;

struct eng_bt_s {
    bt_node_t nodes[ENG_MAX_BT_NODES];
    int count;
};

void eng_bb_init(eng_blackboard_t *bb) {
    if (bb) memset(bb, 0, sizeof(*bb));
}

void eng_bb_set(eng_blackboard_t *bb, const char *key, float value) {
    if (!bb || !key) return;
    for (size_t i = 0; i < bb->count; i++) {
        if (strcmp(bb->keys[i], key) == 0) { bb->values[i] = value; return; }
    }
    if (bb->count < 16) {
        snprintf(bb->keys[bb->count], sizeof(bb->keys[0]), "%s", key);
        bb->values[bb->count++] = value;
    }
}

float eng_bb_get(const eng_blackboard_t *bb, const char *key, float fallback) {
    if (!bb || !key) return fallback;
    for (size_t i = 0; i < bb->count; i++) {
        if (strcmp(bb->keys[i], key) == 0) return bb->values[i];
    }
    return fallback;
}

eng_bt_t *eng_bt_create(void) {
    return (eng_bt_t *)calloc(1, sizeof(eng_bt_t));
}

void eng_bt_destroy(eng_bt_t *bt) {
    free(bt);
}

static int alloc_bt_node(eng_bt_t *bt, int parent_idx, eng_bt_node_type_t type) {
    if (!bt || bt->count >= ENG_MAX_BT_NODES) return -1;
    if (parent_idx >= 0 && (parent_idx >= bt->count || bt->nodes[parent_idx].child_count >= 8)) return -1;
    int idx = bt->count++;
    bt->nodes[idx].type = type;
    if (parent_idx >= 0) {
        bt->nodes[parent_idx].children[bt->nodes[parent_idx].child_count++] = idx;
    }
    return idx;
}

int eng_bt_add_composite(eng_bt_t *bt, int parent_idx, eng_bt_node_type_t type) {
    return alloc_bt_node(bt, parent_idx, type);
}

int eng_bt_add_action(eng_bt_t *bt, int parent_idx, eng_bt_action_fn fn, void *userdata) {
    int idx = alloc_bt_node(bt, parent_idx, ENG_BT_ACTION);
    if (idx >= 0) {
        bt->nodes[idx].fn = fn;
        bt->nodes[idx].userdata = userdata;
    }
    return idx;
}

eng_bt_status_t eng_bt_tick(eng_bt_t *bt, int node_idx, eng_blackboard_t *bb, float dt) {
    if (!bt || node_idx < 0 || node_idx >= bt->count) return ENG_BT_FAILURE;
    const bt_node_t *n = &bt->nodes[node_idx];
    switch (n->type) {
        case ENG_BT_ACTION:
            return n->fn ? n->fn(bb, dt, n->userdata) : ENG_BT_FAILURE;
        case ENG_BT_INVERTER: {
            if (n->child_count == 0) return ENG_BT_FAILURE;
            eng_bt_status_t s = eng_bt_tick(bt, n->children[0], bb, dt);
            return (s == ENG_BT_SUCCESS) ? ENG_BT_FAILURE : (s == ENG_BT_FAILURE ? ENG_BT_SUCCESS : ENG_BT_RUNNING);
        }
        case ENG_BT_SEQUENCE:
            for (int i = 0; i < n->child_count; i++) {
                eng_bt_status_t s = eng_bt_tick(bt, n->children[i], bb, dt);
                if (s != ENG_BT_SUCCESS) return s;
            }
            return ENG_BT_SUCCESS;
        case ENG_BT_SELECTOR:
            for (int i = 0; i < n->child_count; i++) {
                eng_bt_status_t s = eng_bt_tick(bt, n->children[i], bb, dt);
                if (s != ENG_BT_FAILURE) return s;
            }
            return ENG_BT_FAILURE;
    }
    return ENG_BT_FAILURE;
}
