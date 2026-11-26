#ifndef ENG_CAPTURE_H
#define ENG_CAPTURE_H

#include "eng_audio.h"
#include "eng_render.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *out_path;   /* Target .mp4, .webm, .gif, or directory/prefix for PNG+WAV fallback */
    int width;              /* Frame width (pixels, rounded to even for H.264/VP9) */
    int height;             /* Frame height (pixels, rounded to even for H.264/VP9) */
    int fps;                /* Output video frame rate (default 60) */
    float speed;            /* Time-scale for audio atempo (default 1.0) */
    bool fast_live;         /* Use ultrafast x264 preset for interactive live F9 capture */
    bool force_fallback;    /* Force pure-C PNG+WAV output without invoking ffmpeg */
} eng_capture_cfg_t;

typedef struct eng_capture_s eng_capture_t;

/* Resolve named social-media presets: youtube, youtube4k, reel/shorts/tiktok, square, gif. */
bool eng_capture_resolve_preset(const char *preset_name, int *out_w, int *out_h, int *out_fps);

/* Instant high-res PNG screenshot from renderer's active output framebuffer (FBO 0 or offscreen capture FBO). */
bool eng_capture_screenshot(const eng_renderer_t *r, const char *png_path);

/* Check whether an external ffmpeg CLI binary is reachable on PATH (cached). */
bool eng_capture_ffmpeg_available(void);

/* Build chained ffmpeg atempo filter string for speed in [0.25 .. 4.0] (returns false if speed == 1.0). */
bool eng_capture_build_atempo(float speed, char *out_buf, size_t cap);

/* Streaming Video + 48 kHz Stereo Audio Capture Session */
eng_capture_cfg_t eng_capture_default_cfg(const char *out_path, int width, int height, int fps);
eng_capture_t *eng_capture_start(const eng_capture_cfg_t *cfg);
bool eng_capture_push_video_frame(eng_capture_t *cap, const eng_renderer_t *r);
void eng_capture_push_audio(const float *stereo_lr, size_t frames, int sample_rate, void *user_data);
bool eng_capture_stop(eng_capture_t *cap);

uint32_t eng_capture_frame_count(const eng_capture_t *cap);
uint64_t eng_capture_audio_frames(const eng_capture_t *cap);
bool eng_capture_is_using_ffmpeg(const eng_capture_t *cap);
const char *eng_capture_output_path(const eng_capture_t *cap);

#ifdef __cplusplus
}
#endif

#endif /* ENG_CAPTURE_H */
