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

struct eng_input_s {
    bool keys[SDL_SCANCODE_COUNT];
    bool mouse_btns[8];
    bool gp_btns[SDL_GAMEPAD_BUTTON_COUNT];
    float gp_axes[SDL_GAMEPAD_AXIS_COUNT];

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
}

eng_input_t *eng_input_create(void) {
    eng_input_t *inp = (eng_input_t *)calloc(1, sizeof(eng_input_t));
    if (!inp) return NULL;
    inp->touch_preset = ENG_TOUCH_DUAL_STICK;

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
        case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
        case SDL_EVENT_GAMEPAD_BUTTON_UP:
            if (ev->gbutton.button < SDL_GAMEPAD_BUTTON_COUNT) {
                inp->gp_btns[ev->gbutton.button] = (ev->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN);
            }
            break;
        case SDL_EVENT_GAMEPAD_AXIS_MOTION:
            if (ev->gaxis.axis < SDL_GAMEPAD_AXIS_COUNT) {
                float v = (float)ev->gaxis.value / 32767.0f;
                inp->gp_axes[ev->gaxis.axis] = (fabsf(v) < 0.12f) ? 0.0f : eng_clampf(v, -1.0f, 1.0f);
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
    a->key = key;
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

size_t eng_input_save_bindings_json(const eng_input_t *inp, char *out_buf, size_t out_cap) {
    if (!out_buf || out_cap == 0) return 0;
    out_buf[0] = '\0';
    if (!inp) return 0;
    size_t pos = (size_t)snprintf(out_buf, out_cap, "{\n  \"actions\": [\n");
    for (size_t i = 0; i < inp->action_count && pos + 96 < out_cap; i++) {
        const eng_action_slot_t *a = &inp->actions[i];
        pos += (size_t)snprintf(
            out_buf + pos, out_cap - pos,
            "    {\"name\": \"%s\", \"key\": %d, \"mouse\": %u, \"gamepad\": %d}%s\n",
            a->name, (int)a->key, (unsigned)a->mouse_btn, a->gamepad_btn,
            (i + 1 < inp->action_count) ? "," : ""
        );
    }
    if (pos + 8 < out_cap) pos += (size_t)snprintf(out_buf + pos, out_cap - pos, "  ]\n}\n");
    return pos;
}

static const char *const k_bind_root_keys[] = {"actions"};
static const char *const k_bind_item_keys[] = {"name", "key", "mouse", "gamepad"};

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
        if (!eng_json_validate_keys(it, k_bind_item_keys, 4, err_buf, err_cap)) {
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
            a->mouse_btn = (uint8_t)eng_json_get_num(it, "mouse", (double)a->mouse_btn);
            a->gamepad_btn = (int)eng_json_get_num(it, "gamepad", (double)a->gamepad_btn);
        }
    }
    eng_arena_destroy(&arena);
    refresh_actions(inp);
    return true;
}
