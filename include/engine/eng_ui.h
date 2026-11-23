#ifndef ENG_UI_H
#define ENG_UI_H

#include "eng_input.h"
#include "eng_lua.h"
#include "eng_profiler.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_UI_TOP_LEFT = 0,
    ENG_UI_TOP_RIGHT,
    ENG_UI_BOTTOM_LEFT,
    ENG_UI_BOTTOM_RIGHT,
    ENG_UI_CENTER
} eng_ui_anchor_t;

typedef struct {
    float x, y, w, h;
} eng_ui_rect_t;

struct nk_context;
typedef struct eng_ui_s eng_ui_t;

eng_ui_t *eng_ui_create(void);
void eng_ui_destroy(eng_ui_t *ui);

struct nk_context *eng_ui_nk(eng_ui_t *ui);
int eng_ui_width(const eng_ui_t *ui);
int eng_ui_height(const eng_ui_t *ui);

/* Resolution-independent anchored rectangle helper (reference 1280x720, clamped on-screen). */
eng_ui_rect_t eng_ui_resolve_anchor(eng_ui_anchor_t anchor, float offset_x, float offset_y,
                                    float w, float h, int actual_w, int actual_h);

/* Begin Nuklear UI frame and feed mouse/touch pointer state. */
void eng_ui_begin_frame(eng_ui_t *ui, int win_w, int win_h,
                        float mouse_x, float mouse_y, bool mouse_down, float wheel);

/* Immediate-mode anchored In-Game HUD widgets */
void eng_ui_hud_label(eng_ui_t *ui, const char *id, eng_ui_anchor_t anchor,
                      float x, float y, float w, float h, const char *text);
bool eng_ui_hud_button(eng_ui_t *ui, const char *id, eng_ui_anchor_t anchor,
                       float x, float y, float w, float h, const char *label);
void eng_ui_hud_bar(eng_ui_t *ui, const char *id, eng_ui_anchor_t anchor,
                    float x, float y, float w, float h, float fraction, const char *caption);
void eng_ui_hud_touch_overlay(eng_ui_t *ui, eng_input_t *inp);

/* Drop-down ~ Console + CVars + Live Sandboxed Lua REPL */
void eng_ui_toggle_console(eng_ui_t *ui);
bool eng_ui_is_console_open(const eng_ui_t *ui);
bool eng_ui_console_submit(eng_ui_t *ui, eng_runtime_t *rt, const char *line,
                           char *out_reply, size_t reply_cap);
size_t eng_ui_console_history_count(const eng_ui_t *ui);
const char *eng_ui_console_history_get(const eng_ui_t *ui, size_t idx);
void eng_ui_draw_console(eng_ui_t *ui, eng_runtime_t *rt);

/* Toggleable H On-Screen Game Help Overlay */
void eng_ui_toggle_help(eng_ui_t *ui);
bool eng_ui_is_help_open(const eng_ui_t *ui);
void eng_ui_draw_help(eng_ui_t *ui, const eng_runtime_t *rt);

/* Nuklear Profiler Overlay */
void eng_ui_draw_profiler(eng_ui_t *ui, const eng_profiler_t *prof);

/* Convert Nuklear draw lists and render over OpenGL 3.3 Core / GLES 3.0 (WebGL2). */
uint32_t eng_ui_render(eng_ui_t *ui);

#ifdef __cplusplus
}
#endif

#endif /* ENG_UI_H */
