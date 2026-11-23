#ifndef ENG_ANIM_H
#define ENG_ANIM_H

#include "eng_math.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_MAX_BONES 64
#define ENG_MAX_GAIT_LIMBS 8

typedef enum {
    ENG_ANIM_PATH_POS = 0,
    ENG_ANIM_PATH_ROT = 1,
    ENG_ANIM_PATH_SCALE = 2
} eng_anim_path_t;

typedef enum {
    ENG_INTERP_STEP = 0,
    ENG_INTERP_LINEAR = 1,
    ENG_INTERP_CUBIC = 2
} eng_interp_mode_t;

typedef struct {
    char name[32];
    int parent_idx; /* -1 = root */
    eng_vec3_t rest_pos;
    eng_quat_t rest_rot;
    eng_vec3_t rest_scale;
    eng_mat4_t inv_bind;
} eng_bone_t;

typedef struct {
    eng_bone_t bones[ENG_MAX_BONES];
    uint32_t bone_count;
} eng_skeleton_t;

typedef struct {
    eng_vec3_t local_pos[ENG_MAX_BONES];
    eng_quat_t local_rot[ENG_MAX_BONES];
    eng_vec3_t local_scale[ENG_MAX_BONES];
    eng_mat4_t world_mats[ENG_MAX_BONES];
    eng_mat4_t skin_mats[ENG_MAX_BONES]; /* world_mats[i] * inv_bind[i] */
} eng_anim_pose_t;

typedef struct {
    uint32_t bone_idx;
    eng_anim_path_t path;
    eng_interp_mode_t interp;
    float *times;
    float *values; /* 3 floats/key for pos/scale, 4 floats/key for rot (x3 for cubic) */
    size_t key_count;
} eng_anim_channel_t;

typedef struct {
    char name[32];
    float duration;
    eng_anim_channel_t *channels;
    size_t channel_count;
} eng_anim_clip_t;

typedef struct {
    uint32_t limb_count;
    uint8_t hip_bone[ENG_MAX_GAIT_LIMBS];
    uint8_t knee_bone[ENG_MAX_GAIT_LIMBS];
    uint8_t ankle_bone[ENG_MAX_GAIT_LIMBS];
    eng_vec3_t rest_foot_offset[ENG_MAX_GAIT_LIMBS]; /* model-space neutral stance offset */
    eng_vec3_t pole_dir[ENG_MAX_GAIT_LIMBS];
    float phase_offset[ENG_MAX_GAIT_LIMBS]; /* 0.0 .. 1.0 */
    float stride_length;
    float step_height;
    float cycle_hz;
} eng_gait_cfg_t;

void eng_skeleton_init(eng_skeleton_t *skel);
int eng_skeleton_add_bone(eng_skeleton_t *skel, const char *name, int parent_idx,
                          eng_vec3_t rest_pos, eng_quat_t rest_rot, eng_vec3_t rest_scale);
void eng_skeleton_compute_inv_bind(eng_skeleton_t *skel);

void eng_anim_clip_free(eng_anim_clip_t *clip);
bool eng_anim_load_gltf(const void *bytes, size_t byte_len,
                        eng_skeleton_t *out_skel, eng_anim_clip_t *out_clip);

void eng_anim_pose_reset(const eng_skeleton_t *skel, eng_anim_pose_t *pose);
void eng_anim_sample_clip(const eng_skeleton_t *skel, const eng_anim_clip_t *clip,
                          float time_sec, bool loop, eng_anim_pose_t *out_pose);
void eng_anim_blend_poses(const eng_skeleton_t *skel, const eng_anim_pose_t *a,
                          const eng_anim_pose_t *b, float weight,
                          uint64_t bone_mask, eng_anim_pose_t *out_pose);
void eng_anim_compute_skin_matrices(const eng_skeleton_t *skel, eng_anim_pose_t *pose);

/* Analytical 2-bone limb IK (hip->knee->ankle) in model space with pole-vector bend direction. */
bool eng_anim_ik_two_bone(const eng_skeleton_t *skel, eng_anim_pose_t *pose,
                          uint32_t hip_idx, uint32_t knee_idx, uint32_t ankle_idx,
                          eng_vec3_t target_model_pos, eng_vec3_t pole_model_dir);

/* Multi-joint FABRIK chain solver for tentacles, tails, and serpentine spines. */
bool eng_anim_ik_fabrik(const eng_skeleton_t *skel, eng_anim_pose_t *pose,
                        const uint32_t *chain_bones, size_t chain_len,
                        eng_vec3_t target_model_pos, int iterations);

/* Advance procedural multi-limb gait (biped, quadruped, insectoid, serpentine) and solve IK. */
void eng_anim_step_gait(const eng_skeleton_t *skel, const eng_gait_cfg_t *gait,
                        float phase_time, float speed_01, eng_anim_pose_t *pose);

#ifdef __cplusplus
}
#endif

#endif /* ENG_ANIM_H */
