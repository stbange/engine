#include "engine/eng_xr.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

#include <stdlib.h>
#include <string.h>

struct eng_xr_s {
    eng_xr_mode_t mode;
    float diorama_scale;
    bool supported;
    bool active;
    uint32_t xr_fbo;
    eng_xr_pose_t head;
    eng_xr_eye_t raw_eyes[2];
    eng_xr_eye_t world_eyes[2];
    eng_xr_hand_t hands[2];
};

eng_xr_t *eng_xr_create(void) {
    eng_xr_t *xr = (eng_xr_t *)calloc(1, sizeof(eng_xr_t));
    if (!xr) return NULL;
    xr->mode = ENG_XR_DIORAMA;
    xr->diorama_scale = 12.0f; /* 1 meter in VR = 12 world meters in tabletop diorama mode */
    xr->head.rot = eng_quat_identity();
    for (int i = 0; i < 2; i++) {
        xr->hands[i].pose.rot = eng_quat_identity();
        xr->raw_eyes[i].view = eng_mat4_identity();
        xr->raw_eyes[i].proj = eng_mat4_perspective(90.0f * ENG_DEG2RAD, 1.0f, 0.05f, 200.0f);
        xr->raw_eyes[i].viewport[0] = i * 1024;
        xr->raw_eyes[i].viewport[1] = 0;
        xr->raw_eyes[i].viewport[2] = 1024;
        xr->raw_eyes[i].viewport[3] = 1024;
        xr->world_eyes[i] = xr->raw_eyes[i];
    }
#ifdef __EMSCRIPTEN__
    xr->supported = emscripten_run_script_int(
        "(typeof navigator !== 'undefined' && !!navigator.xr) ? 1 : 0") != 0;
#else
    xr->supported = false;
#endif
    return xr;
}

void eng_xr_destroy(eng_xr_t *xr) {
    free(xr);
}

void eng_xr_set_mode(eng_xr_t *xr, eng_xr_mode_t mode) { if (xr) xr->mode = mode; }
eng_xr_mode_t eng_xr_get_mode(const eng_xr_t *xr) { return xr ? xr->mode : ENG_XR_DIORAMA; }

void eng_xr_set_diorama_scale(eng_xr_t *xr, float world_units_per_meter) {
    if (xr && world_units_per_meter > 0.01f && eng_math_is_finite(world_units_per_meter)) {
        xr->diorama_scale = world_units_per_meter;
    }
}

bool eng_xr_is_supported(const eng_xr_t *xr) { return xr ? xr->supported : false; }
bool eng_xr_is_active(const eng_xr_t *xr) { return xr ? xr->active : false; }
uint32_t eng_xr_framebuffer(const eng_xr_t *xr) { return (xr && xr->active) ? xr->xr_fbo : 0u; }

bool eng_xr_request_session(eng_xr_t *xr) {
    if (!xr) return false;
#ifdef __EMSCRIPTEN__
    emscripten_run_script(
        "if (window.engRequestWebXR) { window.engRequestWebXR(); }");
#endif
    xr->active = true;
    return true;
}

void eng_xr_end_session(eng_xr_t *xr) {
    if (!xr) return;
#ifdef __EMSCRIPTEN__
    emscripten_run_script(
        "if (window.engEndWebXR) { window.engEndWebXR(); }");
#endif
    xr->active = false;
    xr->xr_fbo = 0u;
}

void eng_xr_submit_frame_state(eng_xr_t *xr, uint32_t xr_fbo,
                               const eng_xr_pose_t *head,
                               const eng_xr_eye_t eyes_raw[2],
                               const eng_xr_hand_t hands[2]) {
    if (!xr) return;
    xr->active = true;
    xr->xr_fbo = xr_fbo;
    if (head && eng_v3_is_finite(head->pos) && eng_quat_is_finite(head->rot)) {
        xr->head = *head;
    }
    if (eyes_raw) {
        xr->raw_eyes[0] = eyes_raw[0];
        xr->raw_eyes[1] = eyes_raw[1];
    }
    if (hands) {
        xr->hands[0] = hands[0];
        xr->hands[1] = hands[1];
    }
}

void eng_xr_sync_frame(eng_xr_t *xr, eng_vec3_t base_cam_pos, eng_quat_t base_cam_rot, eng_input_t *inp) {
    if (!xr || !xr->active) return;

    float rig_scale = (xr->mode == ENG_XR_DIORAMA) ? xr->diorama_scale : 1.0f;
    eng_mat4_t rig_world = eng_mat4_trs(base_cam_pos, base_cam_rot, eng_v3(rig_scale, rig_scale, rig_scale));
    eng_mat4_t rig_inv;
    if (!eng_mat4_invert(&rig_world, &rig_inv)) {
        rig_inv = eng_mat4_identity();
    }

    for (int i = 0; i < 2; i++) {
        xr->world_eyes[i].proj = xr->raw_eyes[i].proj;
        memcpy(xr->world_eyes[i].viewport, xr->raw_eyes[i].viewport, sizeof(int) * 4);
        xr->world_eyes[i].view = eng_mat4_mul(&xr->raw_eyes[i].view, &rig_inv);
    }

    if (inp) {
        /* Left thumbstick -> locomotion; Right trigger / A button -> fire / jump */
        if (xr->hands[0].pose.tracked) {
            eng_input_inject_axis(inp, "move_x", xr->hands[0].thumbstick.x);
            eng_input_inject_axis(inp, "move_y", xr->hands[0].thumbstick.y);
        }
        if (xr->hands[1].pose.tracked) {
            eng_input_inject_action(inp, "fire", xr->hands[1].trigger > 0.5f);
            eng_input_inject_action(inp, "jump", (xr->hands[1].button_mask & 1u) != 0);
        }
    }
}

const eng_xr_eye_t *eng_xr_get_eye(const eng_xr_t *xr, int eye_index) {
    if (!xr || eye_index < 0 || eye_index > 1) return NULL;
    return &xr->world_eyes[eye_index];
}

const eng_xr_pose_t *eng_xr_get_head(const eng_xr_t *xr) {
    return xr ? &xr->head : NULL;
}

const eng_xr_hand_t *eng_xr_get_hand(const eng_xr_t *xr, int hand_index) {
    if (!xr || hand_index < 0 || hand_index > 1) return NULL;
    return &xr->hands[hand_index];
}
