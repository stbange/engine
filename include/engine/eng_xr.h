#ifndef ENG_XR_H
#define ENG_XR_H

#include "eng_input.h"
#include "eng_math.h"

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_XR_DIORAMA = 0,     /* Scaled stereo tabletop overview (works for all 3rd-person/top-down games) */
    ENG_XR_COCKPIT,         /* 1:1 head tracking anchored inside vehicle/starfighter cockpit */
    ENG_XR_FIRST_PERSON,    /* 1:1 room/player-anchored stereo camera */
    ENG_XR_6DOF             /* Full dual-hand 6DoF motion-controller interaction */
} eng_xr_mode_t;

typedef struct {
    eng_vec3_t pos;
    eng_quat_t rot;
    bool tracked;
} eng_xr_pose_t;

typedef struct {
    eng_xr_pose_t pose;
    float trigger;
    float grip;
    eng_vec2_t thumbstick;
    uint32_t button_mask;
} eng_xr_hand_t;

typedef struct {
    eng_mat4_t view;
    eng_mat4_t proj;
    int viewport[4]; /* x, y, w, h inside XRWebGLLayer framebuffer */
} eng_xr_eye_t;

typedef struct eng_xr_s eng_xr_t;

eng_xr_t *eng_xr_create(void);
void eng_xr_destroy(eng_xr_t *xr);

void eng_xr_set_mode(eng_xr_t *xr, eng_xr_mode_t mode);
eng_xr_mode_t eng_xr_get_mode(const eng_xr_t *xr);
void eng_xr_set_diorama_scale(eng_xr_t *xr, float world_units_per_meter);

bool eng_xr_is_supported(const eng_xr_t *xr);
bool eng_xr_is_active(const eng_xr_t *xr);
uint32_t eng_xr_framebuffer(const eng_xr_t *xr);

/* Request entering/exiting WebXR immersive-vr session (wired to navigator.xr on Web). */
bool eng_xr_request_session(eng_xr_t *xr);
void eng_xr_end_session(eng_xr_t *xr);

/* Inject/receive frame pose data (called by WebXR JS frame callback or unit tests). */
void eng_xr_submit_frame_state(eng_xr_t *xr, uint32_t xr_fbo,
                               const eng_xr_pose_t *head,
                               const eng_xr_eye_t eyes_raw[2],
                               const eng_xr_hand_t hands[2]);

/* Compute world-space eye matrices anchored around base_cam_pos/rot and forward hand inputs to eng_input. */
void eng_xr_sync_frame(eng_xr_t *xr, eng_vec3_t base_cam_pos, eng_quat_t base_cam_rot, eng_input_t *inp);

const eng_xr_eye_t *eng_xr_get_eye(const eng_xr_t *xr, int eye_index);
const eng_xr_pose_t *eng_xr_get_head(const eng_xr_t *xr);
const eng_xr_hand_t *eng_xr_get_hand(const eng_xr_t *xr, int hand_index);

#ifdef __cplusplus
}
#endif

#endif /* ENG_XR_H */
