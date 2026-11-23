#ifndef ENG_PORTAL_H
#define ENG_PORTAL_H

#include "eng_math.h"
#include "eng_scene.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    eng_entity_t src_ent;
    eng_entity_t dst_ent;
    uint16_t src_pocket;
    uint16_t dst_pocket;
    float half_w;
    float half_h;
    float scale_ratio; /* 1.0 = metric 1:1; >1 or <1 = Alice-in-Wonderland scale shift */
    bool passable;     /* true = walkable doorway; false = window-only portal */
} eng_portal_t;

typedef struct eng_portal_sys_s eng_portal_sys_t;

eng_portal_sys_t *eng_portal_sys_create(void);
void eng_portal_sys_destroy(eng_portal_sys_t *sys);

/* Link src_ent -> dst_ent (and automatically dst_ent -> src_ent if bidirectional == true). */
int eng_portal_link(eng_portal_sys_t *sys, eng_scene_t *scene,
                    eng_entity_t src_ent, eng_entity_t dst_ent,
                    float width, float height, float scale_ratio,
                    bool passable, bool bidirectional);

size_t eng_portal_count(const eng_portal_sys_t *sys);
const eng_portal_t *eng_portal_get(const eng_portal_sys_t *sys, size_t index);

/* Compute M_portal = M_dst * Scale(ratio) * RotY(PI) * inv(M_src) */
bool eng_portal_warp_matrix(const eng_scene_t *scene, const eng_portal_t *p, eng_mat4_t *out_warp);

/* Compute virtual camera view matrix & Lengyel oblique near-plane projection matrix. */
bool eng_portal_virtual_camera(const eng_scene_t *scene, const eng_portal_t *p,
                               const eng_mat4_t *cam_view, const eng_mat4_t *cam_proj,
                               eng_mat4_t *out_virt_view, eng_mat4_t *out_oblique_proj);

/* Modify a standard OpenGL perspective matrix so view_plane (nx, ny, nz, d) becomes the exact near clip plane. */
eng_mat4_t eng_portal_oblique_proj(const eng_mat4_t *proj, eng_vec4_t clip_plane_view);

/* Project portal quad into pixel scissor [x, y, w, h]; returns false if completely behind/outside frustum. */
bool eng_portal_screen_scissor(const eng_scene_t *scene, const eng_portal_t *p,
                               const eng_mat4_t *vp, int vp_w, int vp_h, int out_rect[4]);

/* Check if a point moved from prev_pos to curr_pos across an open passable portal in active_pocket. */
const eng_portal_t *eng_portal_check_crossing(const eng_portal_sys_t *sys, const eng_scene_t *scene,
                                              uint16_t active_pocket, eng_vec3_t prev_pos, eng_vec3_t curr_pos,
                                              eng_vec3_t *out_warped_pos);

/* LLM helper: split a wall of (wall_w, wall_h, thickness) around a centered bottom doorway (door_w, door_h)
 * into up to 3 non-overlapping local AABBs (left pillar, right pillar, lintel) so colliders never block portals. */
size_t eng_portal_cut_doorway_boxes(float wall_w, float wall_h, float thickness,
                                    float door_w, float door_h, eng_aabb_t out_boxes[3]);

#ifdef __cplusplus
}
#endif

#endif /* ENG_PORTAL_H */
