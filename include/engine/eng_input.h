#ifndef ENG_INPUT_H
#define ENG_INPUT_H

#include "eng_math.h"
#include "eng_platform.h"

#include <SDL3/SDL_events.h>
#include <SDL3/SDL_gamepad.h>
#include <SDL3/SDL_scancode.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_TOUCH_DUAL_STICK = 0,
    ENG_TOUCH_DPAD_BUTTONS,
    ENG_TOUCH_TAP_DRAG,
    ENG_TOUCH_STEERING
} eng_touch_preset_t;

typedef struct eng_input_s eng_input_t;

eng_input_t *eng_input_create(void);
void eng_input_destroy(eng_input_t *inp);

/* Advance frame state (clears per-frame pressed/released/deltas, ticks input buffers). */
void eng_input_begin_frame(eng_input_t *inp, float dt);
void eng_input_process_event(eng_input_t *inp, eng_platform_t *plat, const SDL_Event *ev);
void eng_input_poll_sdl(eng_input_t *inp, eng_platform_t *plat);

/* Rebindable logical actions & axes */
bool eng_input_bind_key(eng_input_t *inp, const char *action, SDL_Scancode key);
bool eng_input_bind_mouse_button(eng_input_t *inp, const char *action, uint8_t button);
bool eng_input_bind_gamepad_button(eng_input_t *inp, const char *action, SDL_GamepadButton button);
bool eng_input_bind_axis_keys(eng_input_t *inp, const char *axis_name, SDL_Scancode neg_key, SDL_Scancode pos_key);
bool eng_input_bind_axis_gamepad(eng_input_t *inp, const char *axis_name, SDL_GamepadAxis axis, float scale);

bool eng_input_down(const eng_input_t *inp, const char *action);
bool eng_input_pressed(const eng_input_t *inp, const char *action);
bool eng_input_released(const eng_input_t *inp, const char *action);
float eng_input_axis(const eng_input_t *inp, const char *axis_name);

/* Mouse & Touch state */
eng_vec2_t eng_input_mouse_pos(const eng_input_t *inp);
eng_vec2_t eng_input_mouse_delta(const eng_input_t *inp);
float eng_input_mouse_wheel(const eng_input_t *inp);

void eng_input_set_touch_preset(eng_input_t *inp, eng_touch_preset_t preset);
eng_touch_preset_t eng_input_get_touch_preset(const eng_input_t *inp);
bool eng_input_is_touch_active(const eng_input_t *inp);

/* Game-feel helpers: Input Buffer (120ms) & Coyote Time (100ms) */
bool eng_input_buffered(const eng_input_t *inp, const char *action, float buffer_window_sec);
void eng_input_consume_buffer(eng_input_t *inp, const char *action);
bool eng_input_update_coyote(float *coyote_timer, bool is_grounded, float dt, float grace_sec);

/* Synthetic test/XR injection */
void eng_input_inject_action(eng_input_t *inp, const char *action, bool down);
void eng_input_inject_axis(eng_input_t *inp, const char *axis_name, float value);
void eng_input_inject_mouse_delta(eng_input_t *inp, float dx, float dy);

/* JSON serialization for rebindable controls */
size_t eng_input_save_bindings_json(const eng_input_t *inp, char *out_buf, size_t out_cap);
bool eng_input_load_bindings_json(eng_input_t *inp, const char *json_src, char *err_buf, size_t err_cap);

#ifdef __cplusplus
}
#endif

#endif /* ENG_INPUT_H */
