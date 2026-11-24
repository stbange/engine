#ifndef ENG_PLATFORM_H
#define ENG_PLATFORM_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *title;
    int width;
    int height;
    bool fullscreen;
    bool borderless;
    int vsync;        /* 0 = off, 1 = on, -1 = adaptive */
    int display_index;
    bool headless;
} eng_platform_config_t;

typedef struct eng_platform_s eng_platform_t;

eng_platform_config_t eng_platform_default_config(void);
eng_platform_t *eng_platform_create(const eng_platform_config_t *cfg);
void eng_platform_destroy(eng_platform_t *plat);

bool eng_platform_is_headless(const eng_platform_t *plat);
bool eng_platform_should_quit(const eng_platform_t *plat);
void eng_platform_request_quit(eng_platform_t *plat);

void eng_platform_get_size(const eng_platform_t *plat, int *out_w, int *out_h);
void eng_platform_get_pixel_size(const eng_platform_t *plat, int *out_pw, int *out_ph);
float eng_platform_dpi_scale(const eng_platform_t *plat);

bool eng_platform_set_size(eng_platform_t *plat, int w, int h);
bool eng_platform_set_fullscreen(eng_platform_t *plat, bool fullscreen);
bool eng_platform_set_vsync(eng_platform_t *plat, int vsync);
bool eng_platform_set_mouse_lock(eng_platform_t *plat, bool locked);
void eng_platform_sync_mouse_lock(eng_platform_t *plat, bool active);
bool eng_platform_wants_mouse_lock(const eng_platform_t *plat);
bool eng_platform_is_mouse_lock(const eng_platform_t *plat);
int eng_platform_display_count(void);
bool eng_platform_move_to_display(eng_platform_t *plat, int display_index);

/* Advance timing, return clamped frame dt in seconds (fixed 1/60s in headless mode). */
float eng_platform_begin_frame(eng_platform_t *plat);
void eng_platform_swap(eng_platform_t *plat);

#ifdef __cplusplus
}
#endif

#endif /* ENG_PLATFORM_H */
