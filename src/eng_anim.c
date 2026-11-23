#include "engine/eng_anim.h"
#include "cgltf.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void eng_skeleton_init(eng_skeleton_t *skel) {
    if (skel) memset(skel, 0, sizeof(*skel));
}

int eng_skeleton_add_bone(eng_skeleton_t *skel, const char *name, int parent_idx,
                          eng_vec3_t rest_pos, eng_quat_t rest_rot, eng_vec3_t rest_scale) {
    if (!skel || skel->bone_count >= ENG_MAX_BONES) return -1;
    if (parent_idx >= (int)skel->bone_count) return -1;
    int idx = (int)skel->bone_count++;
    eng_bone_t *b = &skel->bones[idx];
    snprintf(b->name, sizeof(b->name), "%s", name ? name : "bone");
    b->parent_idx = parent_idx;
    b->rest_pos = rest_pos;
    b->rest_rot = eng_quat_norm(rest_rot);
    b->rest_scale = rest_scale;
    b->inv_bind = eng_mat4_identity();
    return idx;
}

void eng_skeleton_compute_inv_bind(eng_skeleton_t *skel) {
    if (!skel) return;
    eng_mat4_t world[ENG_MAX_BONES];
    for (uint32_t i = 0; i < skel->bone_count; i++) {
        const eng_bone_t *b = &skel->bones[i];
        eng_mat4_t loc = eng_mat4_trs(b->rest_pos, b->rest_rot, b->rest_scale);
        world[i] = (b->parent_idx >= 0) ? eng_mat4_mul(&world[b->parent_idx], &loc) : loc;
        if (!eng_mat4_invert(&world[i], &skel->bones[i].inv_bind)) {
            skel->bones[i].inv_bind = eng_mat4_identity();
        }
    }
}

void eng_anim_clip_free(eng_anim_clip_t *clip) {
    if (!clip) return;
    for (size_t i = 0; i < clip->channel_count; i++) {
        free(clip->channels[i].times);
        free(clip->channels[i].values);
    }
    free(clip->channels);
    memset(clip, 0, sizeof(*clip));
}

static int find_node_bone(cgltf_node *const *joints, size_t count, const cgltf_node *target) {
    for (size_t i = 0; i < count; i++) {
        if (joints[i] == target) return (int)i;
    }
    return -1;
}

bool eng_anim_load_gltf(const void *bytes, size_t byte_len,
                        eng_skeleton_t *out_skel, eng_anim_clip_t *out_clip) {
    if (!bytes || byte_len == 0 || !out_skel) return false;
    eng_skeleton_init(out_skel);
    if (out_clip) memset(out_clip, 0, sizeof(*out_clip));

    cgltf_options opts;
    memset(&opts, 0, sizeof(opts));
    cgltf_data *data = NULL;
    if (cgltf_parse(&opts, bytes, byte_len, &data) != cgltf_result_success) return false;
    cgltf_load_buffers(&opts, data, NULL);

    if (data->skins_count == 0) {
        cgltf_free(data);
        return false;
    }
    const cgltf_skin *skin = &data->skins[0];
    size_t jc = skin->joints_count < ENG_MAX_BONES ? skin->joints_count : ENG_MAX_BONES;
    for (size_t i = 0; i < jc; i++) {
        const cgltf_node *nd = skin->joints[i];
        int parent = nd->parent ? find_node_bone(skin->joints, jc, nd->parent) : -1;
        eng_vec3_t pos = nd->has_translation ? eng_v3(nd->translation[0], nd->translation[1], nd->translation[2]) : eng_v3(0, 0, 0);
        eng_quat_t rot = nd->has_rotation ? (eng_quat_t){nd->rotation[0], nd->rotation[1], nd->rotation[2], nd->rotation[3]} : eng_quat_identity();
        eng_vec3_t scl = nd->has_scale ? eng_v3(nd->scale[0], nd->scale[1], nd->scale[2]) : eng_v3(1, 1, 1);
        eng_skeleton_add_bone(out_skel, nd->name ? nd->name : "joint", parent, pos, rot, scl);
    }
    eng_skeleton_compute_inv_bind(out_skel);
    if (skin->inverse_bind_matrices) {
        for (size_t i = 0; i < jc && i < skin->inverse_bind_matrices->count; i++) {
            cgltf_accessor_read_float(skin->inverse_bind_matrices, i, out_skel->bones[i].inv_bind.m, 16);
        }
    }

    if (out_clip && data->animations_count > 0) {
        const cgltf_animation *anim = &data->animations[0];
        snprintf(out_clip->name, sizeof(out_clip->name), "%s", anim->name ? anim->name : "clip0");
        out_clip->channels = (eng_anim_channel_t *)calloc(anim->channels_count, sizeof(eng_anim_channel_t));
        for (size_t c = 0; c < anim->channels_count && out_clip->channels; c++) {
            const cgltf_animation_channel *ch = &anim->channels[c];
            int bi = find_node_bone(skin->joints, jc, ch->target_node);
            if (bi < 0 || !ch->sampler || !ch->sampler->input || !ch->sampler->output) continue;
            size_t kc = ch->sampler->input->count;
            if (kc == 0) continue;

            eng_anim_channel_t *dst = &out_clip->channels[out_clip->channel_count++];
            dst->bone_idx = (uint32_t)bi;
            dst->path = (ch->target_path == cgltf_animation_path_type_rotation) ? ENG_ANIM_PATH_ROT :
                        (ch->target_path == cgltf_animation_path_type_scale)    ? ENG_ANIM_PATH_SCALE : ENG_ANIM_PATH_POS;
            dst->interp = (ch->sampler->interpolation == cgltf_interpolation_type_step) ? ENG_INTERP_STEP :
                          (ch->sampler->interpolation == cgltf_interpolation_type_cubic_spline) ? ENG_INTERP_CUBIC : ENG_INTERP_LINEAR;
            dst->key_count = kc;
            size_t comps = (dst->path == ENG_ANIM_PATH_ROT ? 4u : 3u) * (dst->interp == ENG_INTERP_CUBIC ? 3u : 1u);
            dst->times = (float *)calloc(kc, sizeof(float));
            dst->values = (float *)calloc(kc * comps, sizeof(float));
            for (size_t k = 0; k < kc; k++) {
                cgltf_accessor_read_float(ch->sampler->input, k, &dst->times[k], 1);
                if (dst->times[k] > out_clip->duration) out_clip->duration = dst->times[k];
            }
            for (size_t k = 0; k < ch->sampler->output->count && k < kc * (dst->interp == ENG_INTERP_CUBIC ? 3u : 1u); k++) {
                size_t elem_w = (dst->path == ENG_ANIM_PATH_ROT) ? 4u : 3u;
                cgltf_accessor_read_float(ch->sampler->output, k, dst->values + k * elem_w, elem_w);
            }
        }
    }

    cgltf_free(data);
    return out_skel->bone_count > 0;
}

void eng_anim_pose_reset(const eng_skeleton_t *skel, eng_anim_pose_t *pose) {
    if (!skel || !pose) return;
    for (uint32_t i = 0; i < skel->bone_count; i++) {
        pose->local_pos[i] = skel->bones[i].rest_pos;
        pose->local_rot[i] = skel->bones[i].rest_rot;
        pose->local_scale[i] = skel->bones[i].rest_scale;
        pose->world_mats[i] = eng_mat4_identity();
        pose->skin_mats[i] = eng_mat4_identity();
    }
}

void eng_anim_sample_clip(const eng_skeleton_t *skel, const eng_anim_clip_t *clip,
                          float time_sec, bool loop, eng_anim_pose_t *out_pose) {
    if (!skel || !out_pose) return;
    eng_anim_pose_reset(skel, out_pose);
    if (!clip || clip->channel_count == 0) return;

    float t = time_sec;
    if (clip->duration > 1e-4f) {
        if (loop) {
            t = fmodf(t, clip->duration);
            if (t < 0.0f) t += clip->duration;
        } else {
            t = eng_clampf(t, 0.0f, clip->duration);
        }
    }

    for (size_t c = 0; c < clip->channel_count; c++) {
        const eng_anim_channel_t *ch = &clip->channels[c];
        if (ch->key_count == 0 || ch->bone_idx >= skel->bone_count) continue;

        size_t k0 = 0;
        while (k0 + 1 < ch->key_count && ch->times[k0 + 1] <= t) k0++;
        size_t k1 = (k0 + 1 < ch->key_count) ? (k0 + 1) : k0;
        float dt = ch->times[k1] - ch->times[k0];
        float alpha = (ch->interp == ENG_INTERP_STEP || dt <= 1e-5f) ? 0.0f : eng_clampf((t - ch->times[k0]) / dt, 0.0f, 1.0f);

        if (ch->path == ENG_ANIM_PATH_ROT) {
            size_t stride = (ch->interp == ENG_INTERP_CUBIC) ? 12u : 4u;
            size_t off = (ch->interp == ENG_INTERP_CUBIC) ? 4u : 0u;
            const float *v0 = ch->values + k0 * stride + off;
            const float *v1 = ch->values + k1 * stride + off;
            eng_quat_t q0 = {v0[0], v0[1], v0[2], v0[3]};
            eng_quat_t q1 = {v1[0], v1[1], v1[2], v1[3]};
            out_pose->local_rot[ch->bone_idx] = eng_quat_slerp(q0, q1, alpha);
        } else {
            size_t stride = (ch->interp == ENG_INTERP_CUBIC) ? 9u : 3u;
            eng_vec3_t res;
            if (ch->interp == ENG_INTERP_CUBIC && k1 > k0) {
                /* Cubic Hermite spline: in-tangent(0..2), value(3..5), out-tangent(6..8) */
                const float *p0 = ch->values + k0 * 9u + 3u;
                const float *m0 = ch->values + k0 * 9u + 6u;
                const float *m1 = ch->values + k1 * 9u + 0u;
                const float *p1 = ch->values + k1 * 9u + 3u;
                float s = alpha, s2 = s * s, s3 = s2 * s;
                float h00 = 2.0f * s3 - 3.0f * s2 + 1.0f;
                float h10 = s3 - 2.0f * s2 + s;
                float h01 = -2.0f * s3 + 3.0f * s2;
                float h11 = s3 - s2;
                res = eng_v3(
                    h00 * p0[0] + h10 * dt * m0[0] + h01 * p1[0] + h11 * dt * m1[0],
                    h00 * p0[1] + h10 * dt * m0[1] + h01 * p1[1] + h11 * dt * m1[1],
                    h00 * p0[2] + h10 * dt * m0[2] + h01 * p1[2] + h11 * dt * m1[2]
                );
            } else {
                const float *v0 = ch->values + k0 * stride;
                const float *v1 = ch->values + k1 * stride;
                res = eng_v3_lerp(eng_v3(v0[0], v0[1], v0[2]), eng_v3(v1[0], v1[1], v1[2]), alpha);
            }
            if (ch->path == ENG_ANIM_PATH_POS) out_pose->local_pos[ch->bone_idx] = res;
            else out_pose->local_scale[ch->bone_idx] = res;
        }
    }
}

void eng_anim_blend_poses(const eng_skeleton_t *skel, const eng_anim_pose_t *a,
                          const eng_anim_pose_t *b, float weight,
                          uint64_t bone_mask, eng_anim_pose_t *out_pose) {
    if (!skel || !a || !b || !out_pose) return;
    float w = eng_clampf(weight, 0.0f, 1.0f);
    uint64_t mask = bone_mask ? bone_mask : ~0ULL;
    for (uint32_t i = 0; i < skel->bone_count; i++) {
        float bw = (mask & (1ULL << i)) ? w : 0.0f;
        out_pose->local_pos[i] = eng_v3_lerp(a->local_pos[i], b->local_pos[i], bw);
        out_pose->local_rot[i] = eng_quat_slerp(a->local_rot[i], b->local_rot[i], bw);
        out_pose->local_scale[i] = eng_v3_lerp(a->local_scale[i], b->local_scale[i], bw);
    }
}

void eng_anim_compute_skin_matrices(const eng_skeleton_t *skel, eng_anim_pose_t *pose) {
    if (!skel || !pose) return;
    for (uint32_t i = 0; i < skel->bone_count; i++) {
        eng_mat4_t loc = eng_mat4_trs(pose->local_pos[i], pose->local_rot[i], pose->local_scale[i]);
        int p = skel->bones[i].parent_idx;
        pose->world_mats[i] = (p >= 0) ? eng_mat4_mul(&pose->world_mats[p], &loc) : loc;
        pose->skin_mats[i] = eng_mat4_mul(&pose->world_mats[i], &skel->bones[i].inv_bind);
    }
}

static eng_quat_t quat_from_to(eng_vec3_t from, eng_vec3_t to) {
    eng_vec3_t f = eng_v3_norm(from);
    eng_vec3_t t = eng_v3_norm(to);
    float d = eng_v3_dot(f, t);
    if (d >= 0.9999f) return eng_quat_identity();
    if (d <= -0.9999f) {
        eng_vec3_t axis = eng_v3_cross(eng_v3(1, 0, 0), f);
        if (eng_v3_dot(axis, axis) < 0.01f) axis = eng_v3_cross(eng_v3(0, 0, 1), f);
        return eng_quat_from_axis_angle(eng_v3_norm(axis), ENG_PI);
    }
    eng_vec3_t c = eng_v3_cross(f, t);
    float s = sqrtf((1.0f + d) * 2.0f);
    return eng_quat_norm((eng_quat_t){c.x / s, c.y / s, c.z / s, 0.5f * s});
}

bool eng_anim_ik_two_bone(const eng_skeleton_t *skel, eng_anim_pose_t *pose,
                          uint32_t hip_idx, uint32_t knee_idx, uint32_t ankle_idx,
                          eng_vec3_t target_pos, eng_vec3_t pole_dir) {
    if (!skel || !pose || hip_idx >= skel->bone_count || knee_idx >= skel->bone_count || ankle_idx >= skel->bone_count) {
        return false;
    }
    eng_anim_compute_skin_matrices(skel, pose);

    eng_vec3_t p_hip   = eng_v3(pose->world_mats[hip_idx].m[12],   pose->world_mats[hip_idx].m[13],   pose->world_mats[hip_idx].m[14]);
    eng_vec3_t p_knee  = eng_v3(pose->world_mats[knee_idx].m[12],  pose->world_mats[knee_idx].m[13],  pose->world_mats[knee_idx].m[14]);
    eng_vec3_t p_ankle = eng_v3(pose->world_mats[ankle_idx].m[12], pose->world_mats[ankle_idx].m[13], pose->world_mats[ankle_idx].m[14]);

    float l1 = eng_v3_len(eng_v3_sub(p_knee, p_hip));
    float l2 = eng_v3_len(eng_v3_sub(p_ankle, p_knee));
    if (l1 < 1e-4f || l2 < 1e-4f) return false;

    eng_vec3_t to_tgt = eng_v3_sub(target_pos, p_hip);
    float dist = eng_v3_len(to_tgt);
    float min_d = fabsf(l1 - l2) + 1e-3f;
    float max_d = (l1 + l2) - 1e-3f;
    float cd = eng_clampf(dist, min_d, max_d);
    eng_vec3_t dir = dist > 1e-4f ? eng_v3_scale(to_tgt, 1.0f / dist) : eng_v3(0.0f, -1.0f, 0.0f);

    /* Law of cosines for triangle (l1, l2, cd) */
    float cos_hip = eng_clampf((l1 * l1 + cd * cd - l2 * l2) / (2.0f * l1 * cd), -1.0f, 1.0f);
    float ang_hip = acosf(cos_hip);

    eng_vec3_t pole = eng_v3_norm(pole_dir);
    if (eng_v3_dot(pole, pole) < 0.1f) pole = eng_v3(0.0f, 0.0f, 1.0f);
    eng_vec3_t bend_axis = eng_v3_norm(eng_v3_cross(dir, pole));
    if (eng_v3_dot(bend_axis, bend_axis) < 0.1f) bend_axis = eng_v3(1.0f, 0.0f, 0.0f);

    eng_quat_t bend_q = eng_quat_from_axis_angle(bend_axis, -ang_hip);
    eng_vec3_t desired_upper = eng_v3_scale(eng_quat_rotate_v3(bend_q, dir), l1);
    eng_vec3_t new_knee = eng_v3_add(p_hip, desired_upper);
    eng_vec3_t desired_lower = eng_v3_sub(eng_v3_add(p_hip, eng_v3_scale(dir, cd)), new_knee);

    /* Convert desired bone vectors into parent-local rotations */
    int hp = skel->bones[hip_idx].parent_idx;
    eng_mat4_t inv_hp = eng_mat4_identity();
    if (hp >= 0) eng_mat4_invert(&pose->world_mats[hp], &inv_hp);
    eng_vec3_t local_upper_target = eng_v3(
        inv_hp.m[0] * desired_upper.x + inv_hp.m[4] * desired_upper.y + inv_hp.m[8]  * desired_upper.z,
        inv_hp.m[1] * desired_upper.x + inv_hp.m[5] * desired_upper.y + inv_hp.m[9]  * desired_upper.z,
        inv_hp.m[2] * desired_upper.x + inv_hp.m[6] * desired_upper.y + inv_hp.m[10] * desired_upper.z
    );
    pose->local_rot[hip_idx] = quat_from_to(skel->bones[knee_idx].rest_pos, local_upper_target);
    eng_anim_compute_skin_matrices(skel, pose);

    eng_mat4_t inv_hip;
    eng_mat4_invert(&pose->world_mats[hip_idx], &inv_hip);
    eng_vec3_t local_lower_target = eng_v3(
        inv_hip.m[0] * desired_lower.x + inv_hip.m[4] * desired_lower.y + inv_hip.m[8]  * desired_lower.z,
        inv_hip.m[1] * desired_lower.x + inv_hip.m[5] * desired_lower.y + inv_hip.m[9]  * desired_lower.z,
        inv_hip.m[2] * desired_lower.x + inv_hip.m[6] * desired_lower.y + inv_hip.m[10] * desired_lower.z
    );
    pose->local_rot[knee_idx] = quat_from_to(skel->bones[ankle_idx].rest_pos, local_lower_target);
    eng_anim_compute_skin_matrices(skel, pose);
    return true;
}

bool eng_anim_ik_fabrik(const eng_skeleton_t *skel, eng_anim_pose_t *pose,
                        const uint32_t *chain_bones, size_t chain_len,
                        eng_vec3_t target_pos, int iterations) {
    if (!skel || !pose || !chain_bones || chain_len < 2 || chain_len > ENG_MAX_BONES) return false;
    eng_anim_compute_skin_matrices(skel, pose);

    eng_vec3_t pts[ENG_MAX_BONES];
    float lens[ENG_MAX_BONES];
    for (size_t i = 0; i < chain_len; i++) {
        uint32_t b = chain_bones[i];
        if (b >= skel->bone_count) return false;
        pts[i] = eng_v3(pose->world_mats[b].m[12], pose->world_mats[b].m[13], pose->world_mats[b].m[14]);
        if (i > 0) lens[i - 1] = fmaxf(eng_v3_len(eng_v3_sub(pts[i], pts[i - 1])), 1e-3f);
    }

    eng_vec3_t root_pos = pts[0];
    int iters = iterations > 0 ? iterations : 6;
    for (int it = 0; it < iters; it++) {
        /* Backward pass: tip -> root */
        pts[chain_len - 1] = target_pos;
        for (size_t i = chain_len - 1; i > 0; i--) {
            eng_vec3_t d = eng_v3_norm(eng_v3_sub(pts[i - 1], pts[i]));
            if (eng_v3_dot(d, d) < 0.1f) d = eng_v3(0, 1, 0);
            pts[i - 1] = eng_v3_add(pts[i], eng_v3_scale(d, lens[i - 1]));
        }
        /* Forward pass: root -> tip */
        pts[0] = root_pos;
        for (size_t i = 0; i + 1 < chain_len; i++) {
            eng_vec3_t d = eng_v3_norm(eng_v3_sub(pts[i + 1], pts[i]));
            if (eng_v3_dot(d, d) < 0.1f) d = eng_v3(0, 1, 0);
            pts[i + 1] = eng_v3_add(pts[i], eng_v3_scale(d, lens[i]));
        }
    }

    /* Update local bone rotations along chain */
    for (size_t i = 0; i + 1 < chain_len; i++) {
        uint32_t bi = chain_bones[i];
        uint32_t child = chain_bones[i + 1];
        eng_vec3_t world_dir = eng_v3_sub(pts[i + 1], pts[i]);
        int par = skel->bones[bi].parent_idx;
        eng_mat4_t inv_p = eng_mat4_identity();
        if (par >= 0) eng_mat4_invert(&pose->world_mats[par], &inv_p);
        eng_vec3_t loc_dir = eng_v3(
            inv_p.m[0] * world_dir.x + inv_p.m[4] * world_dir.y + inv_p.m[8]  * world_dir.z,
            inv_p.m[1] * world_dir.x + inv_p.m[5] * world_dir.y + inv_p.m[9]  * world_dir.z,
            inv_p.m[2] * world_dir.x + inv_p.m[6] * world_dir.y + inv_p.m[10] * world_dir.z
        );
        pose->local_rot[bi] = quat_from_to(skel->bones[child].rest_pos, loc_dir);
        eng_anim_compute_skin_matrices(skel, pose);
    }
    return true;
}

void eng_anim_step_gait(const eng_skeleton_t *skel, const eng_gait_cfg_t *gait,
                        float phase_time, float speed_01, eng_anim_pose_t *pose) {
    if (!skel || !gait || !pose) return;
    float spd = eng_clampf(speed_01, 0.0f, 1.5f);
    float base_phase = phase_time * (gait->cycle_hz > 0.1f ? gait->cycle_hz : 1.8f);

    /* Subtle spine/root bob proportional to gait speed */
    if (skel->bone_count > 0) {
        pose->local_pos[0].y = skel->bones[0].rest_pos.y + sinf(base_phase * 4.0f * ENG_PI) * 0.03f * spd;
    }

    for (uint32_t l = 0; l < gait->limb_count && l < ENG_MAX_GAIT_LIMBS; l++) {
        float ph = fmodf(base_phase + gait->phase_offset[l], 1.0f);
        if (ph < 0.0f) ph += 1.0f;

        float z_off = 0.0f, y_lift = 0.0f;
        if (ph < 0.5f) {
            /* Swing phase: parabolic foot lift moving forward (-Z) */
            float s = ph * 2.0f;
            z_off = eng_lerpf(0.5f, -0.5f, s) * gait->stride_length * spd;
            y_lift = sinf(s * ENG_PI) * gait->step_height * spd;
        } else {
            /* Stance phase: foot planted sweeping backward (+Z) */
            float s = (ph - 0.5f) * 2.0f;
            z_off = eng_lerpf(-0.5f, 0.5f, s) * gait->stride_length * spd;
        }
        eng_vec3_t target = eng_v3(
            gait->rest_foot_offset[l].x,
            gait->rest_foot_offset[l].y + y_lift,
            gait->rest_foot_offset[l].z + z_off
        );
        eng_anim_ik_two_bone(skel, pose, gait->hip_bone[l], gait->knee_bone[l], gait->ankle_bone[l],
                             target, gait->pole_dir[l]);
    }
}
