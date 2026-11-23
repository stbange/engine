#include "engine/eng_portal.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_PORTALS 128

typedef struct {
    bool has_prev;
    bool manual_vel;
    eng_mat4_t prev_src;
    eng_mat4_t curr_src;
    eng_mat4_t prev_dst;
    eng_mat4_t curr_dst;
    eng_vec3_t src_lin_vel;
    eng_vec3_t src_ang_vel;
    eng_vec3_t dst_lin_vel;
    eng_vec3_t dst_ang_vel;
} eng_portal_kin_t;

struct eng_portal_sys_s {
    eng_portal_t portals[ENG_MAX_PORTALS];
    eng_portal_kin_t kin[ENG_MAX_PORTALS];
    size_t count;
};

eng_portal_sys_t *eng_portal_sys_create(void) {
    return (eng_portal_sys_t *)calloc(1, sizeof(eng_portal_sys_t));
}

void eng_portal_sys_destroy(eng_portal_sys_t *sys) {
    free(sys);
}

static int add_one_portal(eng_portal_sys_t *sys, const eng_scene_t *scene,
                          eng_entity_t src, eng_entity_t dst,
                          float hw, float hh, float ratio, bool passable) {
    if (sys->count >= ENG_MAX_PORTALS) return -1;
    int idx = (int)sys->count++;
    eng_portal_t *p = &sys->portals[idx];
    p->src_ent = src;
    p->dst_ent = dst;
    p->src_pocket = eng_scene_get_pocket(scene, src);
    p->dst_pocket = eng_scene_get_pocket(scene, dst);
    p->half_w = hw;
    p->half_h = hh;
    p->scale_ratio = ratio;
    p->passable = passable;

    const eng_mat4_t *ms = eng_scene_get_world_matrix(scene, src);
    const eng_mat4_t *md = eng_scene_get_world_matrix(scene, dst);
    if (ms && md) {
        sys->kin[idx].prev_src = *ms;
        sys->kin[idx].curr_src = *ms;
        sys->kin[idx].prev_dst = *md;
        sys->kin[idx].curr_dst = *md;
        sys->kin[idx].has_prev = true;
    }
    return idx;
}

int eng_portal_link(eng_portal_sys_t *sys, eng_scene_t *scene,
                    eng_entity_t src_ent, eng_entity_t dst_ent,
                    float width, float height, float scale_ratio,
                    bool passable, bool bidirectional) {
    if (!sys || !scene || width <= 0.0f || height <= 0.0f || scale_ratio <= 0.01f) return -1;
    if (!eng_ecs_alive(eng_scene_ecs(scene), src_ent) ||
        !eng_ecs_alive(eng_scene_ecs(scene), dst_ent)) {
        return -1;
    }
    eng_scene_update_transforms(scene);
    int first = add_one_portal(sys, scene, src_ent, dst_ent, width * 0.5f, height * 0.5f, scale_ratio, passable);
    if (first >= 0 && bidirectional) {
        add_one_portal(sys, scene, dst_ent, src_ent,
                       width * 0.5f * scale_ratio, height * 0.5f * scale_ratio,
                       1.0f / scale_ratio, passable);
    }
    return first;
}

size_t eng_portal_count(const eng_portal_sys_t *sys) { return sys ? sys->count : 0; }

const eng_portal_t *eng_portal_get(const eng_portal_sys_t *sys, size_t index) {
    return (sys && index < sys->count) ? &sys->portals[index] : NULL;
}

static void derive_mat_vel(const eng_mat4_t *m0, const eng_mat4_t *m1, float dt,
                           eng_vec3_t *out_lin, eng_vec3_t *out_ang) {
    if (dt <= 1e-5f) {
        *out_lin = eng_v3(0.0f, 0.0f, 0.0f);
        *out_ang = eng_v3(0.0f, 0.0f, 0.0f);
        return;
    }
    float inv_dt = 1.0f / dt;
    eng_vec3_t p0 = eng_v3(m0->m[12], m0->m[13], m0->m[14]);
    eng_vec3_t p1 = eng_v3(m1->m[12], m1->m[13], m1->m[14]);
    *out_lin = eng_v3_scale(eng_v3_sub(p1, p0), inv_dt);

    eng_vec3_t u0 = eng_v3_norm(eng_v3(m0->m[0], m0->m[1], m0->m[2]));
    eng_vec3_t v0 = eng_v3_norm(eng_v3(m0->m[4], m0->m[5], m0->m[6]));
    eng_vec3_t w0 = eng_v3_norm(eng_v3(m0->m[8], m0->m[9], m0->m[10]));
    eng_vec3_t u1 = eng_v3_norm(eng_v3(m1->m[0], m1->m[1], m1->m[2]));
    eng_vec3_t v1 = eng_v3_norm(eng_v3(m1->m[4], m1->m[5], m1->m[6]));
    eng_vec3_t w1 = eng_v3_norm(eng_v3(m1->m[8], m1->m[9], m1->m[10]));
    eng_vec3_t sum_cross = eng_v3_add(eng_v3_cross(u0, u1), eng_v3_add(eng_v3_cross(v0, v1), eng_v3_cross(w0, w1)));
    *out_ang = eng_v3_scale(sum_cross, 0.5f * inv_dt);
}

void eng_portal_step_kinematics(eng_portal_sys_t *sys, const eng_scene_t *scene, float dt) {
    if (!sys || !scene) return;
    for (size_t i = 0; i < sys->count; i++) {
        const eng_portal_t *p = &sys->portals[i];
        eng_portal_kin_t *k = &sys->kin[i];
        const eng_mat4_t *ms = eng_scene_get_world_matrix(scene, p->src_ent);
        const eng_mat4_t *md = eng_scene_get_world_matrix(scene, p->dst_ent);
        if (!ms || !md) continue;

        if (!k->has_prev || dt <= 0.0f) {
            k->prev_src = *ms;
            k->curr_src = *ms;
            k->prev_dst = *md;
            k->curr_dst = *md;
            if (!k->manual_vel) {
                k->src_lin_vel = eng_v3(0, 0, 0);
                k->src_ang_vel = eng_v3(0, 0, 0);
                k->dst_lin_vel = eng_v3(0, 0, 0);
                k->dst_ang_vel = eng_v3(0, 0, 0);
            }
            k->has_prev = true;
            continue;
        }

        k->prev_src = k->curr_src;
        k->curr_src = *ms;
        k->prev_dst = k->curr_dst;
        k->curr_dst = *md;
        if (!k->manual_vel) {
            derive_mat_vel(&k->prev_src, &k->curr_src, dt, &k->src_lin_vel, &k->src_ang_vel);
            derive_mat_vel(&k->prev_dst, &k->curr_dst, dt, &k->dst_lin_vel, &k->dst_ang_vel);
        }
    }
}

bool eng_portal_set_velocity(eng_portal_sys_t *sys, size_t index,
                             eng_vec3_t src_lin_vel, eng_vec3_t src_ang_vel,
                             eng_vec3_t dst_lin_vel, eng_vec3_t dst_ang_vel) {
    if (!sys || index >= sys->count) return false;
    eng_portal_kin_t *k = &sys->kin[index];
    k->manual_vel = true;
    k->src_lin_vel = src_lin_vel;
    k->src_ang_vel = src_ang_vel;
    k->dst_lin_vel = dst_lin_vel;
    k->dst_ang_vel = dst_ang_vel;
    return true;
}

eng_vec3_t eng_portal_transform_velocity(const eng_portal_sys_t *sys, const eng_scene_t *scene,
                                         const eng_portal_t *p, eng_vec3_t src_world_pos, eng_vec3_t src_world_vel) {
    eng_mat4_t warp;
    if (!scene || !p || !eng_portal_warp_matrix(scene, p, &warp)) return src_world_vel;
    const eng_mat4_t *m_src = eng_scene_get_world_matrix(scene, p->src_ent);
    const eng_mat4_t *m_dst = eng_scene_get_world_matrix(scene, p->dst_ent);

    eng_vec3_t v_src_frame = eng_v3(0, 0, 0);
    eng_vec3_t v_dst_frame = eng_v3(0, 0, 0);
    if (sys && p >= sys->portals && p < sys->portals + sys->count && m_src && m_dst) {
        size_t idx = (size_t)(p - sys->portals);
        const eng_portal_kin_t *k = &sys->kin[idx];
        eng_vec3_t r_src = eng_v3_sub(src_world_pos, eng_v3(m_src->m[12], m_src->m[13], m_src->m[14]));
        v_src_frame = eng_v3_add(k->src_lin_vel, eng_v3_cross(k->src_ang_vel, r_src));

        eng_vec3_t dst_world_pos = eng_mat4_transform_point(&warp, src_world_pos);
        eng_vec3_t r_dst = eng_v3_sub(dst_world_pos, eng_v3(m_dst->m[12], m_dst->m[13], m_dst->m[14]));
        v_dst_frame = eng_v3_add(k->dst_lin_vel, eng_v3_cross(k->dst_ang_vel, r_dst));
    }

    eng_vec3_t v_rel = eng_v3_sub(src_world_vel, v_src_frame);
    eng_vec3_t v_rot = eng_v3(
        warp.m[0] * v_rel.x + warp.m[4] * v_rel.y + warp.m[8]  * v_rel.z,
        warp.m[1] * v_rel.x + warp.m[5] * v_rel.y + warp.m[9]  * v_rel.z,
        warp.m[2] * v_rel.x + warp.m[6] * v_rel.y + warp.m[10] * v_rel.z
    );
    return eng_v3_add(v_rot, v_dst_frame);
}

bool eng_portal_warp_matrix(const eng_scene_t *scene, const eng_portal_t *p, eng_mat4_t *out_warp) {
    if (!scene || !p || !out_warp) return false;
    const eng_mat4_t *m_src = eng_scene_get_world_matrix(scene, p->src_ent);
    const eng_mat4_t *m_dst = eng_scene_get_world_matrix(scene, p->dst_ent);
    if (!m_src || !m_dst) return false;

    eng_mat4_t inv_src;
    if (!eng_mat4_invert(m_src, &inv_src)) return false;

    /* Rotate 180 deg around Y so walking into -Z of src exits out of +Z/-Z facing into dst room */
    eng_quat_t rot180 = eng_quat_from_axis_angle(eng_v3(0.0f, 1.0f, 0.0f), ENG_PI);
    float s = p->scale_ratio;
    eng_mat4_t flip_scale = eng_mat4_trs(eng_v3(0.0f, 0.0f, 0.0f), rot180, eng_v3(s, s, s));
    eng_mat4_t dst_flip = eng_mat4_mul(m_dst, &flip_scale);
    *out_warp = eng_mat4_mul(&dst_flip, &inv_src);
    return true;
}

static float sgnf(float a) {
    return (a > 0.0f) ? 1.0f : ((a < 0.0f) ? -1.0f : 0.0f);
}

eng_mat4_t eng_portal_oblique_proj(const eng_mat4_t *proj, eng_vec4_t c) {
    eng_mat4_t m = *proj;
    /* Lengyel's oblique view-frustum near-plane clipping in OpenGL [-1, 1] NDC */
    eng_vec4_t q;
    q.x = (sgnf(c.x) + m.m[8]) / m.m[0];
    q.y = (sgnf(c.y) + m.m[9]) / m.m[5];
    q.z = -1.0f;
    q.w = (1.0f + m.m[10]) / m.m[14];

    float dot = c.x * q.x + c.y * q.y + c.z * q.z + c.w * q.w;
    if (fabsf(dot) > ENG_EPSILON) {
        float scale = 2.0f / dot;
        m.m[2]  = c.x * scale;
        m.m[6]  = c.y * scale;
        m.m[10] = c.z * scale + 1.0f;
        m.m[14] = c.w * scale;
    }
    return m;
}

bool eng_portal_virtual_camera(const eng_scene_t *scene, const eng_portal_t *p,
                               const eng_mat4_t *cam_view, const eng_mat4_t *cam_proj,
                               eng_mat4_t *out_virt_view, eng_mat4_t *out_oblique_proj) {
    eng_mat4_t warp, cam_world, virt_cam_world;
    if (!cam_view || !cam_proj || !out_virt_view || !out_oblique_proj) return false;
    if (!eng_portal_warp_matrix(scene, p, &warp) || !eng_mat4_invert(cam_view, &cam_world)) {
        return false;
    }
    virt_cam_world = eng_mat4_mul(&warp, &cam_world);
    if (!eng_mat4_invert(&virt_cam_world, out_virt_view)) return false;

    const eng_mat4_t *m_dst = eng_scene_get_world_matrix(scene, p->dst_ent);
    eng_vec3_t dst_pos = eng_v3(m_dst->m[12], m_dst->m[13], m_dst->m[14]);
    eng_vec3_t dst_n = eng_v3_norm(eng_v3(-m_dst->m[8], -m_dst->m[9], -m_dst->m[10]));

    const float *v = out_virt_view->m;
    eng_vec3_t vn = eng_v3(
        v[0] * dst_n.x + v[4] * dst_n.y + v[8]  * dst_n.z,
        v[1] * dst_n.x + v[5] * dst_n.y + v[9]  * dst_n.z,
        v[2] * dst_n.x + v[6] * dst_n.y + v[10] * dst_n.z
    );
    eng_vec3_t vp = eng_mat4_transform_point(out_virt_view, dst_pos);
    if (vn.z > 0.0f) {
        vn = eng_v3_scale(vn, -1.0f);
    }
    float vd = -eng_v3_dot(vn, vp);
    *out_oblique_proj = eng_portal_oblique_proj(cam_proj, (eng_vec4_t){vn.x, vn.y, vn.z, vd});
    return true;
}

bool eng_portal_screen_scissor(const eng_scene_t *scene, const eng_portal_t *p,
                               const eng_mat4_t *vp, int vp_w, int vp_h, int out_rect[4]) {
    if (!scene || !p || !vp || !out_rect || vp_w <= 0 || vp_h <= 0) return false;
    const eng_mat4_t *m_src = eng_scene_get_world_matrix(scene, p->src_ent);
    if (!m_src) return false;

    float min_x = 1.0f, min_y = 1.0f, max_x = -1.0f, max_y = -1.0f;
    bool any_front = false, any_behind_near = false;
    const float sx[4] = {-p->half_w, p->half_w, p->half_w, -p->half_w};
    const float sy[4] = {-p->half_h, -p->half_h, p->half_h, p->half_h};
    const float sz[2] = {0.0f, 0.25f};

    for (int k = 0; k < 2; k++) {
        for (int i = 0; i < 4; i++) {
            eng_vec3_t wp = eng_mat4_transform_point(m_src, eng_v3(sx[i], sy[i], sz[k]));
            float cx = vp->m[0] * wp.x + vp->m[4] * wp.y + vp->m[8]  * wp.z + vp->m[12];
            float cy = vp->m[1] * wp.x + vp->m[5] * wp.y + vp->m[9]  * wp.z + vp->m[13];
            float cw = vp->m[3] * wp.x + vp->m[7] * wp.y + vp->m[11] * wp.z + vp->m[15];
            if (cw > 0.0f) any_front = true;
            if (cw <= 0.15f) {
                any_behind_near = true;
            } else if (k == 0) {
                float nx = cx / cw;
                float ny = cy / cw;
                if (nx < min_x) min_x = nx;
                if (ny < min_y) min_y = ny;
                if (nx > max_x) max_x = nx;
                if (ny > max_y) max_y = ny;
            }
        }
    }
    if (!any_front) return false;
    if (any_behind_near) {
        out_rect[0] = 0; out_rect[1] = 0; out_rect[2] = vp_w; out_rect[3] = vp_h;
        return true;
    }
    if (max_x < -1.0f || min_x > 1.0f || max_y < -1.0f || min_y > 1.0f) return false;
    min_x = eng_clampf(min_x, -1.0f, 1.0f);
    min_y = eng_clampf(min_y, -1.0f, 1.0f);
    max_x = eng_clampf(max_x, -1.0f, 1.0f);
    max_y = eng_clampf(max_y, -1.0f, 1.0f);

    int x0 = (int)((min_x * 0.5f + 0.5f) * (float)vp_w);
    int y0 = (int)((min_y * 0.5f + 0.5f) * (float)vp_h);
    int x1 = (int)ceilf((max_x * 0.5f + 0.5f) * (float)vp_w);
    int y1 = (int)ceilf((max_y * 0.5f + 0.5f) * (float)vp_h);
    if (x1 <= x0 || y1 <= y0) return false;
    out_rect[0] = x0;
    out_rect[1] = y0;
    out_rect[2] = x1 - x0;
    out_rect[3] = y1 - y0;
    return true;
}

const eng_portal_t *eng_portal_check_crossing(const eng_portal_sys_t *sys, const eng_scene_t *scene,
                                              uint16_t active_pocket, eng_vec3_t prev_pos, eng_vec3_t curr_pos,
                                              eng_vec3_t *out_warped_pos) {
    if (!sys || !scene) return NULL;
    for (size_t i = 0; i < sys->count; i++) {
        const eng_portal_t *p = &sys->portals[i];
        if (!p->passable || p->src_pocket != active_pocket) continue;
        const eng_mat4_t *m_curr = eng_scene_get_world_matrix(scene, p->src_ent);
        const eng_mat4_t *m_prev = sys->kin[i].has_prev ? &sys->kin[i].prev_src : m_curr;
        eng_mat4_t inv_prev, inv_curr;
        if (!m_curr || !m_prev || !eng_mat4_invert(m_prev, &inv_prev) || !eng_mat4_invert(m_curr, &inv_curr)) continue;

        /* Evaluate prev_pos in previous portal frame and curr_pos in current portal frame
         * so a moving vehicle ramp sweeping across a stationary player/body triggers cleanly! */
        eng_vec3_t lp0 = eng_mat4_transform_point(&inv_prev, prev_pos);
        eng_vec3_t lp1 = eng_mat4_transform_point(&inv_curr, curr_pos);
        if (lp0.z > 0.0f && lp1.z <= 0.0f) {
            float dz = lp0.z - lp1.z;
            float t = (dz > ENG_EPSILON) ? (lp0.z / dz) : 0.0f;
            float ix = eng_lerpf(lp0.x, lp1.x, t);
            float iy = eng_lerpf(lp0.y, lp1.y, t);
            if (fabsf(ix) <= p->half_w && fabsf(iy) <= p->half_h) {
                eng_mat4_t warp;
                if (eng_portal_warp_matrix(scene, p, &warp)) {
                    if (out_warped_pos) {
                        *out_warped_pos = eng_mat4_transform_point(&warp, curr_pos);
                    }
                    return p;
                }
            }
        }
    }
    return NULL;
}

size_t eng_portal_cut_doorway_boxes(float wall_w, float wall_h, float thickness,
                                    float door_w, float door_h, eng_aabb_t out_boxes[3]) {
    if (!out_boxes || wall_w <= 0.0f || wall_h <= 0.0f || thickness <= 0.0f) return 0;
    float hw = wall_w * 0.5f;
    float dhw = fminf(door_w * 0.5f, hw);
    float dh = fminf(door_h, wall_h);
    float ht = thickness * 0.5f;
    size_t n = 0;
    if (hw - dhw > 0.01f) {
        out_boxes[n++] = (eng_aabb_t){eng_v3(-hw, 0.0f, -ht), eng_v3(-dhw, wall_h, ht)};
        out_boxes[n++] = (eng_aabb_t){eng_v3(dhw, 0.0f, -ht), eng_v3(hw, wall_h, ht)};
    }
    if (wall_h - dh > 0.01f) {
        out_boxes[n++] = (eng_aabb_t){eng_v3(-dhw, dh, -ht), eng_v3(dhw, wall_h, ht)};
    }
    return n;
}
