#include "engine/eng_input.h"
#include "engine/eng_mem.h"
#include "engine/eng_serde.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_ACTIONS 64
#define ENG_MAX_AXES 32

typedef struct {
    char name[48];
    SDL_Scancode key;
    SDL_Scancode alt_key;
    uint8_t mouse_btn;
    int gamepad_btn; /* -1 if unbound */
    bool injected_down;
    bool prev_down;
    bool curr_down;
    float time_since_pressed;
} eng_action_slot_t;

typedef struct {
    char name[48];
    SDL_Scancode neg_key;
    SDL_Scancode pos_key;
    int gamepad_axis; /* -1 if unbound */
    float gamepad_scale;
    float injected_val;
    bool has_injected;
} eng_axis_slot_t;

typedef struct {
    bool active;
    SDL_FingerID id;
    float start_x;
    float start_y;
    float curr_x;
    float curr_y;
} eng_touch_stick_t;

typedef struct {
    SDL_Gamepad *pad;
    SDL_JoystickID pad_id;
    bool connected;
    bool btns[SDL_GAMEPAD_BUTTON_COUNT];
    float axes[SDL_GAMEPAD_AXIS_COUNT];
} eng_gp_slot_t;

typedef struct {
    eng_player_dev_t dev_mode;
    int pad_slot;
    uint8_t inj_mask;
    uint8_t prev_mask;
    uint8_t curr_mask;
} eng_player_slot_t;

struct eng_input_s {
    bool keys[SDL_SCANCODE_COUNT];
    bool mouse_btns[8];
    bool gp_btns[SDL_GAMEPAD_BUTTON_COUNT];
    float gp_axes[SDL_GAMEPAD_AXIS_COUNT];

    bool split_kb;
    eng_gp_slot_t gps[ENG_MAX_PLAYERS];
    eng_player_slot_t players[ENG_MAX_PLAYERS];

    eng_vec2_t mouse_pos;
    eng_vec2_t mouse_delta;
    float wheel_y;

    eng_touch_preset_t touch_preset;
    bool touch_active;
    eng_touch_stick_t left_touch;
    eng_touch_stick_t right_touch;
    bool touch_btn_jump;
    bool touch_btn_fire;

    eng_action_slot_t actions[ENG_MAX_ACTIONS];
    size_t action_count;
    eng_axis_slot_t axes[ENG_MAX_AXES];
    size_t axis_count;
};

static int player_action_bit(const char *action) {
    if (!action) return -1;
    if (strcmp(action, "up") == 0) return 0;
    if (strcmp(action, "down") == 0) return 1;
    if (strcmp(action, "left") == 0) return 2;
    if (strcmp(action, "right") == 0) return 3;
    if (strcmp(action, "jump") == 0) return 4;
    if (strcmp(action, "fire") == 0) return 5;
    if (strcmp(action, "interact") == 0) return 6;
    return -1;
}

static int find_gp_slot(const eng_input_t *inp, SDL_JoystickID id) {
    for (int i = 0; i < ENG_MAX_PLAYERS; i++) {
        if (inp->gps[i].connected && inp->gps[i].pad_id == id) return i;
    }
    return -1;
}

static int attach_gamepad(eng_input_t *inp, SDL_JoystickID id) {
    int existing = find_gp_slot(inp, id);
    if (existing >= 0) return existing;
    for (int i = 0; i < ENG_MAX_PLAYERS; i++) {
        if (!inp->gps[i].connected) {
            memset(&inp->gps[i], 0, sizeof(inp->gps[i]));
            inp->gps[i].pad_id = id;
            inp->gps[i].connected = true;
            inp->gps[i].pad = SDL_OpenGamepad(id);
            return i;
        }
    }
    return -1;
}

static void detach_gamepad(eng_input_t *inp, SDL_JoystickID id) {
    int s = find_gp_slot(inp, id);
    if (s < 0) return;
    if (inp->gps[s].pad) SDL_CloseGamepad(inp->gps[s].pad);
    memset(&inp->gps[s], 0, sizeof(inp->gps[s]));
}

static uint8_t eval_player_kb_mask(const eng_input_t *inp, int p) {
    uint8_t m = 0;
    const bool *k = inp->keys;
    if (p == 0) {
        bool up = k[SDL_SCANCODE_W] || (!inp->split_kb && k[SDL_SCANCODE_UP]);
        bool dn = k[SDL_SCANCODE_S] || (!inp->split_kb && k[SDL_SCANCODE_DOWN]);
        bool lt = k[SDL_SCANCODE_A] || (!inp->split_kb && k[SDL_SCANCODE_LEFT]);
        bool rt = k[SDL_SCANCODE_D] || (!inp->split_kb && k[SDL_SCANCODE_RIGHT]);
        bool jp = k[SDL_SCANCODE_SPACE];
        bool fr = k[SDL_SCANCODE_LSHIFT] || inp->mouse_btns[1] || (!inp->split_kb && k[SDL_SCANCODE_RETURN]);
        bool it = k[SDL_SCANCODE_E];
        if (up) m |= (1u << 0);
        if (dn) m |= (1u << 1);
        if (lt) m |= (1u << 2);
        if (rt) m |= (1u << 3);
        if (jp) m |= (1u << 4);
        if (fr) m |= (1u << 5);
        if (it) m |= (1u << 6);
    } else if (p == 1) {
        if (k[SDL_SCANCODE_UP]) m |= (1u << 0);
        if (k[SDL_SCANCODE_DOWN]) m |= (1u << 1);
        if (k[SDL_SCANCODE_LEFT]) m |= (1u << 2);
        if (k[SDL_SCANCODE_RIGHT]) m |= (1u << 3);
        if (k[SDL_SCANCODE_RSHIFT]) m |= (1u << 4);
        if (k[SDL_SCANCODE_RETURN]) m |= (1u << 5);
        if (k[SDL_SCANCODE_RCTRL] || k[SDL_SCANCODE_SLASH]) m |= (1u << 6);
    } else if (p == 2) {
        if (k[SDL_SCANCODE_I]) m |= (1u << 0);
        if (k[SDL_SCANCODE_K]) m |= (1u << 1);
        if (k[SDL_SCANCODE_J]) m |= (1u << 2);
        if (k[SDL_SCANCODE_L]) m |= (1u << 3);
        if (k[SDL_SCANCODE_P]) m |= (1u << 4);
        if (k[SDL_SCANCODE_O]) m |= (1u << 5);
        if (k[SDL_SCANCODE_U]) m |= (1u << 6);
    } else if (p == 3) {
        if (k[SDL_SCANCODE_T] || k[SDL_SCANCODE_KP_8]) m |= (1u << 0);
        if (k[SDL_SCANCODE_G] || k[SDL_SCANCODE_KP_5]) m |= (1u << 1);
        if (k[SDL_SCANCODE_F] || k[SDL_SCANCODE_KP_4]) m |= (1u << 2);
        if (k[SDL_SCANCODE_H] || k[SDL_SCANCODE_KP_6]) m |= (1u << 3);
        if (k[SDL_SCANCODE_V] || k[SDL_SCANCODE_KP_0]) m |= (1u << 4);
        if (k[SDL_SCANCODE_Y] || k[SDL_SCANCODE_KP_ENTER]) m |= (1u << 5);
        if (k[SDL_SCANCODE_R] || k[SDL_SCANCODE_KP_PLUS]) m |= (1u << 6);
    }
    return m;
}

static uint8_t eval_player_gp_mask(const eng_input_t *inp, int slot) {
    if (slot < 0 || slot >= ENG_MAX_PLAYERS || !inp->gps[slot].connected) return 0;
    const eng_gp_slot_t *g = &inp->gps[slot];
    uint8_t m = 0;
    if (g->btns[SDL_GAMEPAD_BUTTON_DPAD_UP] || g->axes[SDL_GAMEPAD_AXIS_LEFTY] < -0.35f) m |= (1u << 0);
    if (g->btns[SDL_GAMEPAD_BUTTON_DPAD_DOWN] || g->axes[SDL_GAMEPAD_AXIS_LEFTY] > 0.35f) m |= (1u << 1);
    if (g->btns[SDL_GAMEPAD_BUTTON_DPAD_LEFT] || g->axes[SDL_GAMEPAD_AXIS_LEFTX] < -0.35f) m |= (1u << 2);
    if (g->btns[SDL_GAMEPAD_BUTTON_DPAD_RIGHT] || g->axes[SDL_GAMEPAD_AXIS_LEFTX] > 0.35f) m |= (1u << 3);
    if (g->btns[SDL_GAMEPAD_BUTTON_SOUTH]) m |= (1u << 4);
    if (g->btns[SDL_GAMEPAD_BUTTON_WEST] || g->btns[SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER] || g->axes[SDL_GAMEPAD_AXIS_RIGHT_TRIGGER] > 0.35f) m |= (1u << 5);
    if (g->btns[SDL_GAMEPAD_BUTTON_EAST] || g->btns[SDL_GAMEPAD_BUTTON_NORTH]) m |= (1u << 6);
    return m;
}

static eng_action_slot_t *get_or_add_action(eng_input_t *inp, const char *name) {
    if (!inp || !name || name[0] == '\0') return NULL;
    for (size_t i = 0; i < inp->action_count; i++) {
        if (strcmp(inp->actions[i].name, name) == 0) return &inp->actions[i];
    }
    if (inp->action_count >= ENG_MAX_ACTIONS) return NULL;
    eng_action_slot_t *a = &inp->actions[inp->action_count++];
    memset(a, 0, sizeof(*a));
    snprintf(a->name, sizeof(a->name), "%s", name);
    a->gamepad_btn = -1;
    a->time_since_pressed = 999.0f;
    return a;
}

static const eng_action_slot_t *find_action(const eng_input_t *inp, const char *name) {
    if (!inp || !name) return NULL;
    for (size_t i = 0; i < inp->action_count; i++) {
        if (strcmp(inp->actions[i].name, name) == 0) return &inp->actions[i];
    }
    return NULL;
}

static eng_axis_slot_t *get_or_add_axis(eng_input_t *inp, const char *name) {
    if (!inp || !name || name[0] == '\0') return NULL;
    for (size_t i = 0; i < inp->axis_count; i++) {
        if (strcmp(inp->axes[i].name, name) == 0) return &inp->axes[i];
    }
    if (inp->axis_count >= ENG_MAX_AXES) return NULL;
    eng_axis_slot_t *ax = &inp->axes[inp->axis_count++];
    memset(ax, 0, sizeof(*ax));
    snprintf(ax->name, sizeof(ax->name), "%s", name);
    ax->gamepad_axis = -1;
    ax->gamepad_scale = 1.0f;
    return ax;
}

static const eng_axis_slot_t *find_axis(const eng_input_t *inp, const char *name) {
    if (!inp || !name) return NULL;
    for (size_t i = 0; i < inp->axis_count; i++) {
        if (strcmp(inp->axes[i].name, name) == 0) return &inp->axes[i];
    }
    return NULL;
}

static void refresh_actions(eng_input_t *inp) {
    for (size_t i = 0; i < inp->action_count; i++) {
        eng_action_slot_t *a = &inp->actions[i];
        bool d = a->injected_down;
        if (a->key != SDL_SCANCODE_UNKNOWN && a->key < SDL_SCANCODE_COUNT && inp->keys[a->key]) d = true;
        if (a->alt_key != SDL_SCANCODE_UNKNOWN && a->alt_key < SDL_SCANCODE_COUNT && inp->keys[a->alt_key]) d = true;
        if (a->mouse_btn > 0 && a->mouse_btn < 8 && inp->mouse_btns[a->mouse_btn]) d = true;
        if (a->gamepad_btn >= 0 && a->gamepad_btn < SDL_GAMEPAD_BUTTON_COUNT && inp->gp_btns[a->gamepad_btn]) d = true;
        if (inp->touch_active) {
            if (strcmp(a->name, "jump") == 0 && inp->touch_btn_jump) d = true;
            if (strcmp(a->name, "fire") == 0 && inp->touch_btn_fire) d = true;
        }
        if (d && !a->curr_down && !a->prev_down) {
            a->time_since_pressed = 0.0f;
        }
        a->curr_down = d;
    }
    for (int p = 0; p < ENG_MAX_PLAYERS; p++) {
        eng_player_slot_t *ps = &inp->players[p];
        uint8_t m = ps->inj_mask;
        if (ps->dev_mode != ENG_PDEV_GAMEPAD) m |= eval_player_kb_mask(inp, p);
        if (ps->dev_mode != ENG_PDEV_KEYBOARD) m |= eval_player_gp_mask(inp, ps->pad_slot);
        ps->curr_mask = m;
    }
}

eng_input_t *eng_input_create(void) {
    eng_input_t *inp = (eng_input_t *)calloc(1, sizeof(eng_input_t));
    if (!inp) return NULL;
    inp->touch_preset = ENG_TOUCH_DUAL_STICK;
    for (int p = 0; p < ENG_MAX_PLAYERS; p++) {
        inp->players[p].dev_mode = ENG_PDEV_AUTO;
        inp->players[p].pad_slot = p;
    }
    int gp_n = 0;
    SDL_JoystickID *gp_ids = SDL_GetGamepads(&gp_n);
    if (gp_ids) {
        for (int i = 0; i < gp_n && i < ENG_MAX_PLAYERS; i++) attach_gamepad(inp, gp_ids[i]);
        SDL_free(gp_ids);
    }

#ifdef __EMSCRIPTEN__
    int max_tp = emscripten_run_script_int(
        "(typeof navigator !== 'undefined' && navigator.maxTouchPoints > 0) ? navigator.maxTouchPoints : 0");
    if (max_tp > 0) inp->touch_active = true;
#endif

    /* Sensible default retro 3D bindings */
    eng_input_bind_axis_keys(inp, "move_x", SDL_SCANCODE_A, SDL_SCANCODE_D);
    eng_input_bind_axis_gamepad(inp, "move_x", SDL_GAMEPAD_AXIS_LEFTX, 1.0f);
    eng_input_bind_axis_keys(inp, "move_y", SDL_SCANCODE_S, SDL_SCANCODE_W);
    eng_input_bind_axis_gamepad(inp, "move_y", SDL_GAMEPAD_AXIS_LEFTY, -1.0f);
    eng_input_bind_key(inp, "jump", SDL_SCANCODE_SPACE);
    eng_input_bind_gamepad_button(inp, "jump", SDL_GAMEPAD_BUTTON_SOUTH);
    eng_input_bind_mouse_button(inp, "fire", 1);
    eng_input_bind_gamepad_button(inp, "fire", SDL_GAMEPAD_BUTTON_WEST);
    return inp;
}

void eng_input_destroy(eng_input_t *inp) {
    if (!inp) return;
    for (int i = 0; i < ENG_MAX_PLAYERS; i++) {
        if (inp->gps[i].pad) SDL_CloseGamepad(inp->gps[i].pad);
    }
    free(inp);
}

void eng_input_begin_frame(eng_input_t *inp, float dt) {
    if (!inp) return;
    inp->mouse_delta = (eng_vec2_t){0.0f, 0.0f};
    inp->wheel_y = 0.0f;
    for (size_t i = 0; i < inp->action_count; i++) {
        inp->actions[i].prev_down = inp->actions[i].curr_down;
        inp->actions[i].time_since_pressed += (dt > 0.0f ? dt : 0.0f);
    }
    for (int p = 0; p < ENG_MAX_PLAYERS; p++) {
        inp->players[p].prev_mask = inp->players[p].curr_mask;
    }
    for (size_t i = 0; i < inp->axis_count; i++) {
        inp->axes[i].has_injected = false;
    }
    refresh_actions(inp);
}

void eng_input_process_event(eng_input_t *inp, eng_platform_t *plat, const SDL_Event *ev) {
    if (!inp || !ev) return;
    switch (ev->type) {
        case SDL_EVENT_QUIT:
        case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
            if (plat) eng_platform_request_quit(plat);
            break;
        case SDL_EVENT_KEY_DOWN:
        case SDL_EVENT_KEY_UP:
            if (ev->key.scancode < SDL_SCANCODE_COUNT) {
                inp->keys[ev->key.scancode] = (ev->type == SDL_EVENT_KEY_DOWN);
            }
            break;
        case SDL_EVENT_MOUSE_MOTION:
            inp->mouse_pos.x = ev->motion.x;
            inp->mouse_pos.y = ev->motion.y;
            inp->mouse_delta.x += ev->motion.xrel;
            inp->mouse_delta.y += ev->motion.yrel;
            break;
        case SDL_EVENT_MOUSE_BUTTON_DOWN:
        case SDL_EVENT_MOUSE_BUTTON_UP:
            if (ev->button.button < 8) {
                inp->mouse_btns[ev->button.button] = (ev->type == SDL_EVENT_MOUSE_BUTTON_DOWN);
            }
            break;
        case SDL_EVENT_MOUSE_WHEEL:
            inp->wheel_y += ev->wheel.y;
            break;
        case SDL_EVENT_GAMEPAD_ADDED:
            attach_gamepad(inp, ev->gdevice.which);
            break;
        case SDL_EVENT_GAMEPAD_REMOVED:
            detach_gamepad(inp, ev->gdevice.which);
            break;
        case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
        case SDL_EVENT_GAMEPAD_BUTTON_UP:
            if (ev->gbutton.button < SDL_GAMEPAD_BUTTON_COUNT) {
                bool down = (ev->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN);
                inp->gp_btns[ev->gbutton.button] = down;
                int s = find_gp_slot(inp, ev->gbutton.which);
                if (s < 0 && ev->gbutton.which != 0) s = attach_gamepad(inp, ev->gbutton.which);
                if (s >= 0) inp->gps[s].btns[ev->gbutton.button] = down;
            }
            break;
        case SDL_EVENT_GAMEPAD_AXIS_MOTION:
            if (ev->gaxis.axis < SDL_GAMEPAD_AXIS_COUNT) {
                float v = (float)ev->gaxis.value / 32767.0f;
                float nv = (fabsf(v) < 0.12f) ? 0.0f : eng_clampf(v, -1.0f, 1.0f);
                inp->gp_axes[ev->gaxis.axis] = nv;
                int s = find_gp_slot(inp, ev->gaxis.which);
                if (s < 0 && ev->gaxis.which != 0) s = attach_gamepad(inp, ev->gaxis.which);
                if (s >= 0) inp->gps[s].axes[ev->gaxis.axis] = nv;
            }
            break;
        case SDL_EVENT_FINGER_DOWN: {
            inp->touch_active = true;
            float fx = ev->tfinger.x, fy = ev->tfinger.y;
            if (fx < 0.5f && !inp->left_touch.active) {
                inp->left_touch = (eng_touch_stick_t){true, ev->tfinger.fingerID, fx, fy, fx, fy};
            } else {
                inp->right_touch = (eng_touch_stick_t){true, ev->tfinger.fingerID, fx, fy, fx, fy};
                /* Bottom-right quadrant virtual buttons: lower-right = jump, mid-right = fire */
                if (fy > 0.75f && fx > 0.75f) inp->touch_btn_jump = true;
                else if (fy > 0.55f && fx > 0.75f) inp->touch_btn_fire = true;
            }
            break;
        }
        case SDL_EVENT_FINGER_MOTION:
            inp->touch_active = true;
            if (inp->left_touch.active && ev->tfinger.fingerID == inp->left_touch.id) {
                inp->left_touch.curr_x = ev->tfinger.x;
                inp->left_touch.curr_y = ev->tfinger.y;
            } else if (inp->right_touch.active && ev->tfinger.fingerID == inp->right_touch.id) {
                inp->right_touch.curr_x = ev->tfinger.x;
                inp->right_touch.curr_y = ev->tfinger.y;
                inp->mouse_delta.x += ev->tfinger.dx * 400.0f;
                inp->mouse_delta.y += ev->tfinger.dy * 400.0f;
            }
            break;
        case SDL_EVENT_FINGER_UP:
            if (inp->left_touch.active && ev->tfinger.fingerID == inp->left_touch.id) {
                inp->left_touch.active = false;
            }
            if (inp->right_touch.active && ev->tfinger.fingerID == inp->right_touch.id) {
                inp->right_touch.active = false;
                inp->touch_btn_jump = false;
                inp->touch_btn_fire = false;
            }
            break;
        default:
            break;
    }
    refresh_actions(inp);
}

void eng_input_poll_sdl(eng_input_t *inp, eng_platform_t *plat) {
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
        eng_input_process_event(inp, plat, &ev);
    }
}

bool eng_input_bind_key(eng_input_t *inp, const char *action, SDL_Scancode key) {
    eng_action_slot_t *a = get_or_add_action(inp, action);
    if (!a) return false;
    if (a->key == SDL_SCANCODE_UNKNOWN || a->key == key) a->key = key;
    else a->alt_key = key;
    refresh_actions(inp);
    return true;
}

bool eng_input_bind_mouse_button(eng_input_t *inp, const char *action, uint8_t button) {
    eng_action_slot_t *a = get_or_add_action(inp, action);
    if (!a || button >= 8) return false;
    a->mouse_btn = button;
    refresh_actions(inp);
    return true;
}

bool eng_input_bind_gamepad_button(eng_input_t *inp, const char *action, SDL_GamepadButton button) {
    eng_action_slot_t *a = get_or_add_action(inp, action);
    if (!a || button < 0 || button >= SDL_GAMEPAD_BUTTON_COUNT) return false;
    a->gamepad_btn = (int)button;
    refresh_actions(inp);
    return true;
}

bool eng_input_bind_axis_keys(eng_input_t *inp, const char *axis_name, SDL_Scancode neg_key, SDL_Scancode pos_key) {
    eng_axis_slot_t *ax = get_or_add_axis(inp, axis_name);
    if (!ax) return false;
    ax->neg_key = neg_key;
    ax->pos_key = pos_key;
    return true;
}

bool eng_input_bind_axis_gamepad(eng_input_t *inp, const char *axis_name, SDL_GamepadAxis axis, float scale) {
    eng_axis_slot_t *ax = get_or_add_axis(inp, axis_name);
    if (!ax || axis < 0 || axis >= SDL_GAMEPAD_AXIS_COUNT) return false;
    ax->gamepad_axis = (int)axis;
    ax->gamepad_scale = scale;
    return true;
}

bool eng_input_down(const eng_input_t *inp, const char *action) {
    const eng_action_slot_t *a = find_action(inp, action);
    return a ? a->curr_down : false;
}

bool eng_input_pressed(const eng_input_t *inp, const char *action) {
    const eng_action_slot_t *a = find_action(inp, action);
    return a ? (a->curr_down && !a->prev_down) : false;
}

bool eng_input_released(const eng_input_t *inp, const char *action) {
    const eng_action_slot_t *a = find_action(inp, action);
    return a ? (!a->curr_down && a->prev_down) : false;
}

float eng_input_axis(const eng_input_t *inp, const char *axis_name) {
    const eng_axis_slot_t *ax = find_axis(inp, axis_name);
    if (!ax) return 0.0f;
    if (ax->has_injected) return eng_clampf(ax->injected_val, -1.0f, 1.0f);

    float v = 0.0f;
    if (ax->neg_key != SDL_SCANCODE_UNKNOWN && inp->keys[ax->neg_key]) v -= 1.0f;
    if (ax->pos_key != SDL_SCANCODE_UNKNOWN && inp->keys[ax->pos_key]) v += 1.0f;
    if (ax->gamepad_axis >= 0) {
        v += inp->gp_axes[ax->gamepad_axis] * ax->gamepad_scale;
    }
    if (inp->touch_active && inp->left_touch.active) {
        if (strcmp(axis_name, "move_x") == 0) {
            v += (inp->left_touch.curr_x - inp->left_touch.start_x) * 8.0f;
        } else if (strcmp(axis_name, "move_y") == 0) {
            v -= (inp->left_touch.curr_y - inp->left_touch.start_y) * 8.0f;
        }
    }
    return eng_clampf(v, -1.0f, 1.0f);
}

eng_vec2_t eng_input_mouse_pos(const eng_input_t *inp) { return inp ? inp->mouse_pos : (eng_vec2_t){0, 0}; }
eng_vec2_t eng_input_mouse_delta(const eng_input_t *inp) { return inp ? inp->mouse_delta : (eng_vec2_t){0, 0}; }
float eng_input_mouse_wheel(const eng_input_t *inp) { return inp ? inp->wheel_y : 0.0f; }

void eng_input_set_touch_preset(eng_input_t *inp, eng_touch_preset_t preset) { if (inp) inp->touch_preset = preset; }
eng_touch_preset_t eng_input_get_touch_preset(const eng_input_t *inp) { return inp ? inp->touch_preset : ENG_TOUCH_DUAL_STICK; }
bool eng_input_is_touch_active(const eng_input_t *inp) { return inp ? inp->touch_active : false; }

bool eng_input_buffered(const eng_input_t *inp, const char *action, float buffer_window_sec) {
    const eng_action_slot_t *a = find_action(inp, action);
    return a ? (a->time_since_pressed <= buffer_window_sec) : false;
}

void eng_input_consume_buffer(eng_input_t *inp, const char *action) {
    eng_action_slot_t *a = get_or_add_action(inp, action);
    if (a) a->time_since_pressed = 999.0f;
}

bool eng_input_update_coyote(float *coyote_timer, bool is_grounded, float dt, float grace_sec) {
    if (!coyote_timer) return is_grounded;
    if (is_grounded) {
        *coyote_timer = grace_sec;
    } else if (*coyote_timer > 0.0f) {
        *coyote_timer -= dt;
    }
    return *coyote_timer > 0.0f;
}

void eng_input_inject_action(eng_input_t *inp, const char *action, bool down) {
    eng_action_slot_t *a = get_or_add_action(inp, action);
    if (!a) return;
    a->injected_down = down;
    refresh_actions(inp);
}

void eng_input_inject_axis(eng_input_t *inp, const char *axis_name, float value) {
    eng_axis_slot_t *ax = get_or_add_axis(inp, axis_name);
    if (!ax) return;
    ax->injected_val = value;
    ax->has_injected = true;
}

void eng_input_inject_mouse_delta(eng_input_t *inp, float dx, float dy) {
    if (!inp) return;
    inp->mouse_delta.x += dx;
    inp->mouse_delta.y += dy;
}

void eng_input_set_split_keyboard(eng_input_t *inp, bool enabled) {
    if (!inp) return;
    inp->split_kb = enabled;
    refresh_actions(inp);
}

bool eng_input_is_split_keyboard(const eng_input_t *inp) {
    return inp ? inp->split_kb : false;
}

void eng_input_set_player_device(eng_input_t *inp, int player_idx, eng_player_dev_t mode, int pad_slot) {
    if (!inp || player_idx < 0 || player_idx >= ENG_MAX_PLAYERS) return;
    inp->players[player_idx].dev_mode = mode;
    if (pad_slot >= 0 && pad_slot < ENG_MAX_PLAYERS) inp->players[player_idx].pad_slot = pad_slot;
    refresh_actions(inp);
}

int eng_input_gamepad_count(const eng_input_t *inp) {
    if (!inp) return 0;
    int n = 0;
    for (int i = 0; i < ENG_MAX_PLAYERS; i++) if (inp->gps[i].connected) n++;
    return n;
}

bool eng_input_player_has_gamepad(const eng_input_t *inp, int player_idx) {
    if (!inp || player_idx < 0 || player_idx >= ENG_MAX_PLAYERS) return false;
    int s = inp->players[player_idx].pad_slot;
    return (s >= 0 && s < ENG_MAX_PLAYERS) ? inp->gps[s].connected : false;
}

bool eng_input_player_down(const eng_input_t *inp, int player_idx, const char *action) {
    int bit = player_action_bit(action);
    if (!inp || player_idx < 0 || player_idx >= ENG_MAX_PLAYERS || bit < 0) return false;
    return (inp->players[player_idx].curr_mask & (1u << bit)) != 0;
}

bool eng_input_player_pressed(const eng_input_t *inp, int player_idx, const char *action) {
    int bit = player_action_bit(action);
    if (!inp || player_idx < 0 || player_idx >= ENG_MAX_PLAYERS || bit < 0) return false;
    uint8_t m = (uint8_t)(1u << bit);
    return ((inp->players[player_idx].curr_mask & m) != 0) && ((inp->players[player_idx].prev_mask & m) == 0);
}

eng_vec2_t eng_input_player_move(const eng_input_t *inp, int player_idx) {
    if (!inp || player_idx < 0 || player_idx >= ENG_MAX_PLAYERS) return (eng_vec2_t){0, 0};
    const eng_player_slot_t *ps = &inp->players[player_idx];
    float x = ((ps->curr_mask & (1u << 3)) ? 1.0f : 0.0f) - ((ps->curr_mask & (1u << 2)) ? 1.0f : 0.0f);
    float y = ((ps->curr_mask & (1u << 0)) ? 1.0f : 0.0f) - ((ps->curr_mask & (1u << 1)) ? 1.0f : 0.0f);
    if (ps->dev_mode != ENG_PDEV_KEYBOARD && ps->pad_slot >= 0 && ps->pad_slot < ENG_MAX_PLAYERS &&
        inp->gps[ps->pad_slot].connected) {
        float gx = inp->gps[ps->pad_slot].axes[SDL_GAMEPAD_AXIS_LEFTX];
        float gy = -inp->gps[ps->pad_slot].axes[SDL_GAMEPAD_AXIS_LEFTY];
        if (fabsf(gx) > fabsf(x)) x = gx;
        if (fabsf(gy) > fabsf(y)) y = gy;
    }
    float len = sqrtf(x * x + y * y);
    if (len > 1.0f) { x /= len; y /= len; }
    return (eng_vec2_t){x, y};
}

eng_vec2_t eng_input_player_look(const eng_input_t *inp, int player_idx) {
    if (!inp || player_idx < 0 || player_idx >= ENG_MAX_PLAYERS) return (eng_vec2_t){0, 0};
    const eng_player_slot_t *ps = &inp->players[player_idx];
    float lx = 0.0f, ly = 0.0f;
    if (ps->dev_mode != ENG_PDEV_KEYBOARD && ps->pad_slot >= 0 && ps->pad_slot < ENG_MAX_PLAYERS &&
        inp->gps[ps->pad_slot].connected) {
        lx += inp->gps[ps->pad_slot].axes[SDL_GAMEPAD_AXIS_RIGHTX];
        ly += inp->gps[ps->pad_slot].axes[SDL_GAMEPAD_AXIS_RIGHTY];
    }
    if (ps->dev_mode != ENG_PDEV_GAMEPAD) {
        static const SDL_Scancode turn_l[4] = {SDL_SCANCODE_Q, SDL_SCANCODE_COMMA, SDL_SCANCODE_N, SDL_SCANCODE_KP_7};
        static const SDL_Scancode turn_r[4] = {SDL_SCANCODE_C, SDL_SCANCODE_PERIOD, SDL_SCANCODE_M, SDL_SCANCODE_KP_9};
        if (inp->keys[turn_l[player_idx]]) lx -= 1.0f;
        if (inp->keys[turn_r[player_idx]]) lx += 1.0f;
    }
    return (eng_vec2_t){eng_clampf(lx, -1.0f, 1.0f), eng_clampf(ly, -1.0f, 1.0f)};
}

void eng_input_inject_player_action(eng_input_t *inp, int player_idx, const char *action, bool down) {
    int bit = player_action_bit(action);
    if (!inp || player_idx < 0 || player_idx >= ENG_MAX_PLAYERS || bit < 0) return;
    if (down) inp->players[player_idx].inj_mask |= (uint8_t)(1u << bit);
    else inp->players[player_idx].inj_mask &= (uint8_t)~(1u << bit);
    refresh_actions(inp);
}

size_t eng_input_save_bindings_json(const eng_input_t *inp, char *out_buf, size_t out_cap) {
    if (!out_buf || out_cap == 0) return 0;
    out_buf[0] = '\0';
    if (!inp) return 0;
    size_t pos = (size_t)snprintf(out_buf, out_cap, "{\n  \"actions\": [\n");
    for (size_t i = 0; i < inp->action_count && pos + 112 < out_cap; i++) {
        const eng_action_slot_t *a = &inp->actions[i];
        pos += (size_t)snprintf(
            out_buf + pos, out_cap - pos,
            "    {\"name\": \"%s\", \"key\": %d, \"alt_key\": %d, \"mouse\": %u, \"gamepad\": %d}%s\n",
            a->name, (int)a->key, (int)a->alt_key, (unsigned)a->mouse_btn, a->gamepad_btn,
            (i + 1 < inp->action_count) ? "," : ""
        );
    }
    if (pos + 8 < out_cap) pos += (size_t)snprintf(out_buf + pos, out_cap - pos, "  ]\n}\n");
    return pos;
}

static const char *const k_bind_root_keys[] = {"actions"};
static const char *const k_bind_item_keys[] = {"name", "key", "alt_key", "mouse", "gamepad"};

bool eng_input_load_bindings_json(eng_input_t *inp, const char *json_src, char *err_buf, size_t err_cap) {
    if (!inp || !json_src) return false;
    eng_arena_t arena;
    if (!eng_arena_init(&arena, 32768)) return false;
    eng_json_val_t *root = eng_json_parse(&arena, json_src, err_buf, err_cap);
    if (!root || !eng_json_validate_keys(root, k_bind_root_keys, 1, err_buf, err_cap)) {
        eng_arena_destroy(&arena);
        return false;
    }
    const eng_json_val_t *arr = eng_json_get(root, "actions");
    if (!arr || arr->type != ENG_JSON_ARR) {
        eng_arena_destroy(&arena);
        return false;
    }
    for (size_t i = 0; i < arr->u.arr.len; i++) {
        const eng_json_val_t *it = arr->u.arr.items[i];
        if (!eng_json_validate_keys(it, k_bind_item_keys, 5, err_buf, err_cap)) {
            eng_arena_destroy(&arena);
            return false;
        }
        const char *name = eng_json_get_str(it, "name", NULL);
        if (!name) {
            eng_arena_destroy(&arena);
            return false;
        }
        eng_action_slot_t *a = get_or_add_action(inp, name);
        if (a) {
            a->key = (SDL_Scancode)(int)eng_json_get_num(it, "key", (double)a->key);
            a->alt_key = (SDL_Scancode)(int)eng_json_get_num(it, "alt_key", (double)a->alt_key);
            a->mouse_btn = (uint8_t)eng_json_get_num(it, "mouse", (double)a->mouse_btn);
            a->gamepad_btn = (int)eng_json_get_num(it, "gamepad", (double)a->gamepad_btn);
        }
    }
    eng_arena_destroy(&arena);
    refresh_actions(inp);
    return true;
}
