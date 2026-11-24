#include "engine/eng_platform.h"
#include "engine/eng_gl.h"
#include "engine/eng_log.h"

#include <SDL3/SDL.h>
#ifdef __EMSCRIPTEN__
#include <emscripten/html5.h>
#endif
#include <stdlib.h>
#include <string.h>

struct eng_platform_s {
    SDL_Window *window;
    SDL_GLContext gl_ctx;
    int width;
    int height;
    int pixel_w;
    int pixel_h;
    int vsync;
    bool fullscreen;
    bool headless;
    bool quit_requested;
    bool want_mouse_lock;
    bool mouse_locked;
    uint64_t last_counter;
    uint64_t counter_freq;
};

eng_platform_config_t eng_platform_default_config(void) {
    eng_platform_config_t cfg = {
        "Engine", 1280, 720, false, false, 1, 0, false
    };
    return cfg;
}

eng_platform_t *eng_platform_create(const eng_platform_config_t *cfg_in) {
    eng_platform_config_t cfg = cfg_in ? *cfg_in : eng_platform_default_config();
    if (cfg.width <= 0) cfg.width = 1280;
    if (cfg.height <= 0) cfg.height = 720;

    eng_platform_t *p = (eng_platform_t *)calloc(1, sizeof(eng_platform_t));
    if (!p) return NULL;
    p->width = cfg.width;
    p->height = cfg.height;
    p->pixel_w = cfg.width;
    p->pixel_h = cfg.height;
    p->vsync = cfg.vsync;
    p->fullscreen = cfg.fullscreen;
    p->headless = cfg.headless;

    if (cfg.headless) {
        SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "dummy");
        SDL_SetHint(SDL_HINT_AUDIO_DRIVER, "dummy");
    }

    if (!SDL_InitSubSystem(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
        /* Graceful fallback to dummy headless driver on displayless hosts */
        SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "dummy");
        SDL_InitSubSystem(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
        p->headless = true;
    }

    p->counter_freq = SDL_GetPerformanceFrequency();
    p->last_counter = SDL_GetPerformanceCounter();

    if (p->headless) {
        p->window = SDL_CreateWindow(cfg.title ? cfg.title : "Engine", p->width, p->height, SDL_WINDOW_HIDDEN);
        eng_gl_init_software_mock();
        return p;
    }

#ifdef __EMSCRIPTEN__
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    bool want_gles = true;
#else
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
#ifdef __APPLE__
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
#endif
    bool want_gles = false;
#endif
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

    SDL_WindowFlags flags = SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;
    if (cfg.fullscreen) flags |= SDL_WINDOW_FULLSCREEN;
    if (cfg.borderless) flags |= SDL_WINDOW_BORDERLESS;

    p->window = SDL_CreateWindow(cfg.title ? cfg.title : "Engine", p->width, p->height, flags);
    if (p->window) {
        if (cfg.display_index > 0) {
            eng_platform_move_to_display(p, cfg.display_index);
        }
        p->gl_ctx = SDL_GL_CreateContext(p->window);
#ifdef __EMSCRIPTEN__
        if (p->gl_ctx) {
            EMSCRIPTEN_WEBGL_CONTEXT_HANDLE wctx = emscripten_webgl_get_current_context();
            if (wctx > 0) {
                emscripten_webgl_enable_extension(wctx, "EXT_color_buffer_float");
                emscripten_webgl_enable_extension(wctx, "EXT_color_buffer_half_float");
            }
        }
#endif
    }

    if (!p->window || !p->gl_ctx || !eng_gl_load((eng_gl_load_fn)SDL_GL_GetProcAddress, want_gles)) {
        ENG_LOGW("platform", "Falling back to software GL mock (%s)", SDL_GetError());
        p->headless = true;
        eng_gl_init_software_mock();
    } else {
        eng_platform_set_vsync(p, cfg.vsync);
        SDL_GetWindowSizeInPixels(p->window, &p->pixel_w, &p->pixel_h);
    }
    return p;
}

void eng_platform_destroy(eng_platform_t *plat) {
    if (!plat) return;
    if (plat->gl_ctx) SDL_GL_DestroyContext(plat->gl_ctx);
    if (plat->window) SDL_DestroyWindow(plat->window);
    SDL_QuitSubSystem(SDL_INIT_VIDEO);
    free(plat);
}

bool eng_platform_is_headless(const eng_platform_t *plat) { return plat ? plat->headless : true; }
bool eng_platform_should_quit(const eng_platform_t *plat) { return plat ? plat->quit_requested : true; }
void eng_platform_request_quit(eng_platform_t *plat) { if (plat) plat->quit_requested = true; }

void eng_platform_get_size(const eng_platform_t *plat, int *out_w, int *out_h) {
    if (out_w) *out_w = plat ? plat->width : 0;
    if (out_h) *out_h = plat ? plat->height : 0;
}

void eng_platform_get_pixel_size(const eng_platform_t *plat, int *out_pw, int *out_ph) {
    if (out_pw) *out_pw = plat ? plat->pixel_w : 0;
    if (out_ph) *out_ph = plat ? plat->pixel_h : 0;
}

float eng_platform_dpi_scale(const eng_platform_t *plat) {
    if (!plat || plat->width <= 0) return 1.0f;
    return (float)plat->pixel_w / (float)plat->width;
}

bool eng_platform_set_size(eng_platform_t *plat, int w, int h) {
    if (!plat || w <= 0 || h <= 0) return false;
    plat->width = w;
    plat->height = h;
    plat->pixel_w = w;
    plat->pixel_h = h;
    if (plat->window) {
        SDL_SetWindowSize(plat->window, w, h);
        SDL_GetWindowSizeInPixels(plat->window, &plat->pixel_w, &plat->pixel_h);
    }
    return true;
}

bool eng_platform_set_fullscreen(eng_platform_t *plat, bool fullscreen) {
    if (!plat) return false;
    plat->fullscreen = fullscreen;
    if (plat->window && !plat->headless) {
        return SDL_SetWindowFullscreen(plat->window, fullscreen);
    }
    return true;
}

bool eng_platform_set_vsync(eng_platform_t *plat, int vsync) {
    if (!plat) return false;
    plat->vsync = vsync;
    if (plat->gl_ctx && !plat->headless) {
        if (!SDL_GL_SetSwapInterval(vsync) && vsync < 0) {
            return SDL_GL_SetSwapInterval(1);
        }
    }
    return true;
}

bool eng_platform_set_mouse_lock(eng_platform_t *plat, bool locked) {
    if (!plat) return false;
    plat->want_mouse_lock = locked;
#ifdef __EMSCRIPTEN__
    if (!locked) {
        plat->mouse_locked = false;
        if (plat->window && !plat->headless) SDL_SetWindowRelativeMouseMode(plat->window, false);
    }
    return true;
#else
    plat->mouse_locked = locked;
    if (plat->window && !plat->headless) return SDL_SetWindowRelativeMouseMode(plat->window, locked);
    return true;
#endif
}

void eng_platform_sync_mouse_lock(eng_platform_t *plat, bool active) {
    if (!plat) return;
    plat->mouse_locked = active;
#ifndef __EMSCRIPTEN__
    if (plat->window && !plat->headless) SDL_SetWindowRelativeMouseMode(plat->window, active);
#endif
}

bool eng_platform_wants_mouse_lock(const eng_platform_t *plat) { return plat ? plat->want_mouse_lock : false; }
bool eng_platform_is_mouse_lock(const eng_platform_t *plat) { return plat ? plat->mouse_locked : false; }

int eng_platform_display_count(void) {
    int count = 0;
    SDL_DisplayID *ids = SDL_GetDisplays(&count);
    SDL_free(ids);
    return count;
}

bool eng_platform_move_to_display(eng_platform_t *plat, int display_index) {
    if (!plat || !plat->window || display_index < 0) return false;
    int count = 0;
    SDL_DisplayID *ids = SDL_GetDisplays(&count);
    if (!ids || display_index >= count) {
        SDL_free(ids);
        return false;
    }
    SDL_Rect bounds = {0, 0, 1280, 720};
    bool ok = SDL_GetDisplayBounds(ids[display_index], &bounds) &&
              SDL_SetWindowPosition(plat->window,
                                    bounds.x + (bounds.w - plat->width) / 2,
                                    bounds.y + (bounds.h - plat->height) / 2);
    SDL_free(ids);
    return ok;
}

float eng_platform_begin_frame(eng_platform_t *plat) {
    if (!plat) return 1.0f / 60.0f;
    if (plat->headless) {
        if (plat->window) {
            SDL_GetWindowSize(plat->window, &plat->width, &plat->height);
            plat->pixel_w = plat->width;
            plat->pixel_h = plat->height;
        }
        return 1.0f / 60.0f;
    }
    if (plat->window) {
        SDL_GetWindowSize(plat->window, &plat->width, &plat->height);
        SDL_GetWindowSizeInPixels(plat->window, &plat->pixel_w, &plat->pixel_h);
    }
    uint64_t now = SDL_GetPerformanceCounter();
    double dt = (plat->counter_freq > 0) ? ((double)(now - plat->last_counter) / (double)plat->counter_freq) : (1.0 / 60.0);
    plat->last_counter = now;
    if (dt <= 0.0 || dt > 0.1) dt = 1.0 / 60.0;
    return (float)dt;
}

void eng_platform_swap(eng_platform_t *plat) {
    if (plat && plat->window && plat->gl_ctx && !plat->headless) {
        SDL_GL_SwapWindow(plat->window);
    }
}
