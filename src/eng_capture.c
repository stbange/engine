#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "engine/eng_capture.h"
#include "engine/eng_asset.h"
#include "engine/eng_log.h"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <direct.h>
#include <windows.h>
#elif !defined(__EMSCRIPTEN__)
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#else
#include <sys/stat.h>
#endif

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
    CAP_FMT_MP4 = 0,
    CAP_FMT_WEBM = 1,
    CAP_FMT_GIF = 2,
    CAP_FMT_FALLBACK = 3
} cap_fmt_t;

struct eng_capture_s {
    char out_path[512];
    char tmp_vid_path[540];
    char wav_path[560];
    char fallback_dir[540];
    int width;
    int height;
    int fps;
    float speed;
    cap_fmt_t fmt;
    bool using_ffmpeg;

    uint8_t *rgba_buf;
    uint32_t frame_count;

    /* Streaming 48 kHz 16-bit stereo RIFF WAV */
    FILE *wav_fp;
    int sample_rate;
    uint64_t audio_frames;

    /* External ffmpeg video encoder process (zero shell invocation) */
#ifdef _WIN32
    HANDLE ff_stdin;
    HANDLE ff_proc;
#elif !defined(__EMSCRIPTEN__)
    int ff_fd;
    pid_t ff_pid;
#endif
};

static bool path_is_safe(const char *p) {
    if (!p || !p[0] || strlen(p) >= 500u) return false;
    for (const unsigned char *s = (const unsigned char *)p; *s; s++) {
        if (*s < 0x20u || *s == 0x7Fu) return false;
    }
    return true;
}

static void cap_mkdir_one(const char *dir) {
#ifdef _WIN32
    (void)_mkdir(dir);
#else
    (void)mkdir(dir, 0755);
#endif
}

static void cap_ensure_parents(const char *path) {
    if (!path) return;
    char tmp[600];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/' || *p == '\\') {
            char saved = *p;
            *p = '\0';
            cap_mkdir_one(tmp);
            *p = saved;
        }
    }
}

static bool ends_with_ci(const char *s, const char *suf) {
    size_t ls = strlen(s), lf = strlen(suf);
    if (ls < lf) return false;
    s += ls - lf;
    for (size_t i = 0; i < lf; i++) {
        if (tolower((unsigned char)s[i]) != tolower((unsigned char)suf[i])) return false;
    }
    return true;
}

/* --------------------------------------------------------------------------
 * Pure-C11 Streaming 16-bit Stereo RIFF WAV Writer
 * -------------------------------------------------------------------------- */
static void wr_le16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
}

static void wr_le32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static void wav_write_header(FILE *fp, int sample_rate, uint32_t data_bytes) {
    uint8_t hdr[44];
    uint32_t sr = sample_rate > 0 ? (uint32_t)sample_rate : 48000u;
    memcpy(hdr + 0, "RIFF", 4);
    wr_le32(hdr + 4, 36u + data_bytes);
    memcpy(hdr + 8, "WAVEfmt ", 8);
    wr_le32(hdr + 16, 16u);        /* PCM fmt chunk size */
    wr_le16(hdr + 20, 1u);         /* PCM format */
    wr_le16(hdr + 22, 2u);         /* Stereo */
    wr_le32(hdr + 24, sr);         /* Sample rate */
    wr_le32(hdr + 28, sr * 4u);    /* Byte rate (2ch * 16-bit) */
    wr_le16(hdr + 32, 4u);         /* Block align */
    wr_le16(hdr + 34, 16u);        /* Bits per sample */
    memcpy(hdr + 36, "data", 4);
    wr_le32(hdr + 40, data_bytes);
    (void)fwrite(hdr, 1u, sizeof(hdr), fp);
}

static void wav_close_and_patch(eng_capture_t *cap) {
    if (!cap || !cap->wav_fp) return;
    uint64_t bytes = cap->audio_frames * 4ull;
    if (bytes > 0xFFFFFF00ull) bytes = 0xFFFFFF00ull;
    if (fseek(cap->wav_fp, 0, SEEK_SET) == 0) {
        wav_write_header(cap->wav_fp, cap->sample_rate, (uint32_t)bytes);
    }
    fclose(cap->wav_fp);
    cap->wav_fp = NULL;
}

/* --------------------------------------------------------------------------
 * Safe External ffmpeg Subprocess Helpers (Zero Shell Invocation)
 * -------------------------------------------------------------------------- */
#ifdef _WIN32
static bool win_spawn_ffmpeg(char *const argv[], bool pipe_stdin, HANDLE *out_stdin, HANDLE *out_proc) {
    char cmd[2048];
    size_t pos = 0;
    for (int i = 0; argv[i]; i++) {
        if (i > 0 && pos + 1 < sizeof(cmd)) cmd[pos++] = ' ';
        if (pos + 1 < sizeof(cmd)) cmd[pos++] = '"';
        for (const char *s = argv[i]; *s && pos + 2 < sizeof(cmd); s++) {
            if (*s == '"') cmd[pos++] = '\\';
            cmd[pos++] = *s;
        }
        if (pos + 1 < sizeof(cmd)) cmd[pos++] = '"';
    }
    cmd[pos] = '\0';

    HANDLE rd = NULL, wr = NULL;
    SECURITY_ATTRIBUTES sa = { sizeof(sa), NULL, TRUE };
    if (pipe_stdin) {
        if (!CreatePipe(&rd, &wr, &sa, 0)) return false;
        SetHandleInformation(wr, HANDLE_FLAG_INHERIT, 0);
    }
    HANDLE nul = CreateFileA("NUL", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    memset(&pi, 0, sizeof(pi));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = pipe_stdin ? rd : (nul != INVALID_HANDLE_VALUE ? nul : GetStdHandle(STD_INPUT_HANDLE));
    si.hStdOutput = nul != INVALID_HANDLE_VALUE ? nul : GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = nul != INVALID_HANDLE_VALUE ? nul : GetStdHandle(STD_ERROR_HANDLE);

    BOOL ok = CreateProcessA(NULL, cmd, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
    if (rd) CloseHandle(rd);
    if (nul != INVALID_HANDLE_VALUE) CloseHandle(nul);
    if (!ok) {
        if (wr) CloseHandle(wr);
        return false;
    }
    CloseHandle(pi.hThread);
    if (out_stdin) *out_stdin = wr;
    if (out_proc) *out_proc = pi.hProcess;
    return true;
}

static bool run_ffmpeg_sync(char *const argv[]) {
    HANDLE proc = NULL;
    if (!win_spawn_ffmpeg(argv, false, NULL, &proc)) return false;
    WaitForSingleObject(proc, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(proc, &code);
    CloseHandle(proc);
    return code == 0;
}
#elif !defined(__EMSCRIPTEN__)
static bool posix_spawn_ffmpeg(char *const argv[], bool pipe_stdin, int *out_fd, pid_t *out_pid) {
    int fds[2] = {-1, -1};
    if (pipe_stdin && pipe(fds) != 0) return false;
    pid_t pid = fork();
    if (pid < 0) {
        if (pipe_stdin) { close(fds[0]); close(fds[1]); }
        return false;
    }
    if (pid == 0) {
        int dn = open("/dev/null", O_RDWR);
        if (pipe_stdin) {
            dup2(fds[0], STDIN_FILENO);
            close(fds[0]);
            close(fds[1]);
        } else if (dn >= 0) {
            dup2(dn, STDIN_FILENO);
        }
        if (dn >= 0) {
            dup2(dn, STDOUT_FILENO);
            dup2(dn, STDERR_FILENO);
            close(dn);
        }
        execvp("ffmpeg", argv);
        _exit(127);
    }
    if (pipe_stdin) {
        close(fds[0]);
        if (out_fd) *out_fd = fds[1];
    }
    if (out_pid) *out_pid = pid;
    return true;
}

static bool run_ffmpeg_sync(char *const argv[]) {
    pid_t pid = -1;
    if (!posix_spawn_ffmpeg(argv, false, NULL, &pid)) return false;
    int st = 0;
    if (waitpid(pid, &st, 0) < 0) return false;
    return WIFEXITED(st) && WEXITSTATUS(st) == 0;
}
#endif

static bool write_all_pipe(eng_capture_t *cap, const uint8_t *data, size_t len) {
#ifdef _WIN32
    size_t off = 0;
    while (off < len) {
        DWORD wr = 0;
        if (!WriteFile(cap->ff_stdin, data + off, (DWORD)(len - off), &wr, NULL) || wr == 0) return false;
        off += (size_t)wr;
    }
    return true;
#elif !defined(__EMSCRIPTEN__)
    size_t off = 0;
    while (off < len) {
        ssize_t wr = write(cap->ff_fd, data + off, len - off);
        if (wr <= 0) return false;
        off += (size_t)wr;
    }
    return true;
#else
    (void)cap; (void)data; (void)len;
    return false;
#endif
}

/* --------------------------------------------------------------------------
 * Public API: Presets, Screenshots, atempo & Streaming Capture
 * -------------------------------------------------------------------------- */
bool eng_capture_resolve_preset(const char *preset_name, int *out_w, int *out_h, int *out_fps) {
    if (!preset_name || !preset_name[0]) return false;
    int w = 0, h = 0, fps = 60;
    if (strcmp(preset_name, "youtube") == 0 || strcmp(preset_name, "landscape") == 0) {
        w = 1920; h = 1080; fps = 60;
    } else if (strcmp(preset_name, "youtube4k") == 0 || strcmp(preset_name, "4k") == 0) {
        w = 3840; h = 2160; fps = 60;
    } else if (strcmp(preset_name, "reel") == 0 || strcmp(preset_name, "shorts") == 0 ||
               strcmp(preset_name, "tiktok") == 0 || strcmp(preset_name, "vertical") == 0) {
        w = 1080; h = 1920; fps = 60;
    } else if (strcmp(preset_name, "square") == 0 || strcmp(preset_name, "instagram") == 0) {
        w = 1080; h = 1080; fps = 60;
    } else if (strcmp(preset_name, "gif") == 0) {
        w = 640; h = 360; fps = 24;
    } else {
        return false;
    }
    if (out_w) *out_w = w;
    if (out_h) *out_h = h;
    if (out_fps) *out_fps = fps;
    return true;
}

bool eng_capture_screenshot(const eng_renderer_t *r, const char *png_path) {
    if (!r || !path_is_safe(png_path)) return false;
    int w = 0, h = 0;
    eng_renderer_get_size(r, &w, &h);
    if (w <= 0 || h <= 0) return false;
    uint8_t *px = (uint8_t *)malloc((size_t)w * (size_t)h * 4u);
    if (!px) return false;
    bool ok = eng_renderer_read_pixels(r, px, w, h);
    if (ok) {
        cap_ensure_parents(png_path);
        ok = eng_asset_write_png(png_path, w, h, px);
    }
    free(px);
    return ok;
}

bool eng_capture_ffmpeg_available(void) {
#ifdef __EMSCRIPTEN__
    return false;
#else
    char *argv[] = {"ffmpeg", "-version", NULL};
    return run_ffmpeg_sync(argv);
#endif
}

bool eng_capture_build_atempo(float speed, char *out_buf, size_t cap) {
    if (!out_buf || cap < 16u || fabsf(speed - 1.0f) < 0.001f) return false;
    float s = eng_clampf(speed, 0.25f, 4.0f);
    size_t pos = 0;
    out_buf[0] = '\0';
    while (s < 0.5f - 1e-4f) {
        pos += (size_t)snprintf(out_buf + pos, cap - pos, "%satempo=0.5", pos ? "," : "");
        s *= 2.0f;
    }
    while (s > 2.0f + 1e-4f) {
        pos += (size_t)snprintf(out_buf + pos, cap - pos, "%satempo=2.0", pos ? "," : "");
        s *= 0.5f;
    }
    snprintf(out_buf + pos, cap - pos, "%satempo=%.4f", pos ? "," : "", (double)s);
    return true;
}

eng_capture_cfg_t eng_capture_default_cfg(const char *out_path, int width, int height, int fps) {
    return (eng_capture_cfg_t){
        .out_path = out_path,
        .width = width > 0 ? width : 1280,
        .height = height > 0 ? height : 720,
        .fps = fps > 0 ? fps : 60,
        .speed = 1.0f,
        .fast_live = false,
        .force_fallback = false
    };
}

eng_capture_t *eng_capture_start(const eng_capture_cfg_t *cfg) {
    if (!cfg || !path_is_safe(cfg->out_path) || cfg->width <= 0 || cfg->height <= 0) return NULL;
    eng_capture_t *cap = (eng_capture_t *)calloc(1, sizeof(eng_capture_t));
    if (!cap) return NULL;

    /* H.264/VP9 yuv420p requires even dimensions */
    cap->width = cfg->width & ~1;
    cap->height = cfg->height & ~1;
    if (cap->width < 2) cap->width = 2;
    if (cap->height < 2) cap->height = 2;
    cap->fps = (cfg->fps > 0 && cfg->fps <= 240) ? cfg->fps : 60;
    cap->speed = cfg->speed > 0.05f ? cfg->speed : 1.0f;
    cap->sample_rate = 48000;
#ifndef _WIN32
#ifndef __EMSCRIPTEN__
    cap->ff_fd = -1;
    cap->ff_pid = -1;
#endif
#endif

    snprintf(cap->out_path, sizeof(cap->out_path), "%s", cfg->out_path);
    cap->rgba_buf = (uint8_t *)malloc((size_t)cap->width * (size_t)cap->height * 4u);
    if (!cap->rgba_buf) { free(cap); return NULL; }

    bool want_ff = !cfg->force_fallback && eng_capture_ffmpeg_available();
    if (want_ff) {
        if (ends_with_ci(cap->out_path, ".gif")) cap->fmt = CAP_FMT_GIF;
        else if (ends_with_ci(cap->out_path, ".webm")) cap->fmt = CAP_FMT_WEBM;
        else cap->fmt = CAP_FMT_MP4;
    } else {
        cap->fmt = CAP_FMT_FALLBACK;
    }

    cap_ensure_parents(cap->out_path);

#ifndef __EMSCRIPTEN__
    if (want_ff) {
        char sz_str[32], fps_str[16];
        snprintf(sz_str, sizeof(sz_str), "%dx%d", cap->width, cap->height);
        snprintf(fps_str, sizeof(fps_str), "%d", cap->fps);
        if (cap->fmt == CAP_FMT_GIF) {
            snprintf(cap->tmp_vid_path, sizeof(cap->tmp_vid_path), "%s", cap->out_path);
        } else {
            snprintf(cap->tmp_vid_path, sizeof(cap->tmp_vid_path), "%s.vidtmp%s",
                     cap->out_path, cap->fmt == CAP_FMT_WEBM ? ".webm" : ".mp4");
            snprintf(cap->wav_path, sizeof(cap->wav_path), "%s.audtmp.wav", cap->out_path);
        }

        char *argv[24];
        int ac = 0;
        argv[ac++] = "ffmpeg"; argv[ac++] = "-y";
        argv[ac++] = "-f"; argv[ac++] = "rawvideo";
        argv[ac++] = "-pix_fmt"; argv[ac++] = "rgba";
        argv[ac++] = "-s"; argv[ac++] = sz_str;
        argv[ac++] = "-r"; argv[ac++] = fps_str;
        argv[ac++] = "-i"; argv[ac++] = "-";
        if (cap->fmt == CAP_FMT_GIF) {
            argv[ac++] = "-vf";
            argv[ac++] = "vflip,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer";
        } else if (cap->fmt == CAP_FMT_WEBM) {
            argv[ac++] = "-vf"; argv[ac++] = "vflip";
            argv[ac++] = "-c:v"; argv[ac++] = "libvpx-vp9";
            argv[ac++] = "-crf"; argv[ac++] = "30";
            argv[ac++] = "-b:v"; argv[ac++] = "0";
            argv[ac++] = "-pix_fmt"; argv[ac++] = "yuv420p";
        } else {
            argv[ac++] = "-vf"; argv[ac++] = "vflip";
            argv[ac++] = "-c:v"; argv[ac++] = "libx264";
            argv[ac++] = "-preset"; argv[ac++] = cfg->fast_live ? "ultrafast" : "medium";
            argv[ac++] = "-crf"; argv[ac++] = "18";
            argv[ac++] = "-pix_fmt"; argv[ac++] = "yuv420p";
        }
        argv[ac++] = cap->tmp_vid_path;
        argv[ac] = NULL;

#ifdef _WIN32
        cap->using_ffmpeg = win_spawn_ffmpeg(argv, true, &cap->ff_stdin, &cap->ff_proc);
#else
        cap->using_ffmpeg = posix_spawn_ffmpeg(argv, true, &cap->ff_fd, &cap->ff_pid);
#endif
        if (!cap->using_ffmpeg) cap->fmt = CAP_FMT_FALLBACK;
    }
#endif

    if (cap->fmt == CAP_FMT_FALLBACK) {
        snprintf(cap->fallback_dir, sizeof(cap->fallback_dir), "%s_frames", cap->out_path);
        cap_ensure_parents(cap->fallback_dir);
        cap_mkdir_one(cap->fallback_dir);
        snprintf(cap->wav_path, sizeof(cap->wav_path), "%s/audio.wav", cap->fallback_dir);
    }

    if (cap->wav_path[0]) {
        cap->wav_fp = fopen(cap->wav_path, "wb");
        if (cap->wav_fp) wav_write_header(cap->wav_fp, cap->sample_rate, 0u);
    }
    return cap;
}

bool eng_capture_push_video_frame(eng_capture_t *cap, const eng_renderer_t *r) {
    if (!cap || !r || !cap->rgba_buf) return false;
    if (!eng_renderer_read_pixels(r, cap->rgba_buf, cap->width, cap->height)) return false;

    if (cap->using_ffmpeg) {
        if (!write_all_pipe(cap, cap->rgba_buf, (size_t)cap->width * (size_t)cap->height * 4u)) {
            return false;
        }
    } else {
        char fpath[600];
        snprintf(fpath, sizeof(fpath), "%s/frame_%06u.png", cap->fallback_dir, (unsigned)cap->frame_count);
        if (!eng_asset_write_png(fpath, cap->width, cap->height, cap->rgba_buf)) return false;
    }
    cap->frame_count++;
    return true;
}

void eng_capture_push_audio(const float *stereo_lr, size_t frames, int sample_rate, void *user_data) {
    eng_capture_t *cap = (eng_capture_t *)user_data;
    if (!cap || !cap->wav_fp || !stereo_lr || frames == 0) return;
    if (sample_rate > 0) cap->sample_rate = sample_rate;
    uint8_t pcm[2048];
    size_t i = 0;
    while (i < frames) {
        size_t batch = frames - i;
        if (batch > 512u) batch = 512u;
        for (size_t k = 0; k < batch; k++) {
            float l = eng_clampf(stereo_lr[(i + k) * 2u + 0], -1.0f, 1.0f);
            float r = eng_clampf(stereo_lr[(i + k) * 2u + 1], -1.0f, 1.0f);
            int16_t il = (int16_t)(l * 32767.0f);
            int16_t ir = (int16_t)(r * 32767.0f);
            wr_le16(pcm + k * 4u + 0, (uint16_t)il);
            wr_le16(pcm + k * 4u + 2, (uint16_t)ir);
        }
        if (fwrite(pcm, 1u, batch * 4u, cap->wav_fp) == batch * 4u) {
            cap->audio_frames += batch;
        }
        i += batch;
    }
}

bool eng_capture_stop(eng_capture_t *cap) {
    if (!cap) return false;
    bool ok = true;

    wav_close_and_patch(cap);

    if (cap->using_ffmpeg) {
#ifdef _WIN32
        if (cap->ff_stdin) { CloseHandle(cap->ff_stdin); cap->ff_stdin = NULL; }
        if (cap->ff_proc) {
            WaitForSingleObject(cap->ff_proc, INFINITE);
            DWORD code = 1;
            GetExitCodeProcess(cap->ff_proc, &code);
            CloseHandle(cap->ff_proc);
            cap->ff_proc = NULL;
            if (code != 0) ok = false;
        }
#elif !defined(__EMSCRIPTEN__)
        if (cap->ff_fd >= 0) { close(cap->ff_fd); cap->ff_fd = -1; }
        if (cap->ff_pid > 0) {
            int st = 0;
            if (waitpid(cap->ff_pid, &st, 0) < 0 || !WIFEXITED(st) || WEXITSTATUS(st) != 0) ok = false;
            cap->ff_pid = -1;
        }
#endif

#ifndef __EMSCRIPTEN__
        if (ok && cap->fmt != CAP_FMT_GIF) {
            char *argv[24];
            int ac = 0;
            char atempo[96];
            bool has_atempo = eng_capture_build_atempo(cap->speed, atempo, sizeof(atempo));
            argv[ac++] = "ffmpeg"; argv[ac++] = "-y";
            argv[ac++] = "-i"; argv[ac++] = cap->tmp_vid_path;
            if (cap->audio_frames > 0 && cap->wav_path[0]) {
                argv[ac++] = "-i"; argv[ac++] = cap->wav_path;
                argv[ac++] = "-c:v"; argv[ac++] = "copy";
                if (has_atempo) { argv[ac++] = "-af"; argv[ac++] = atempo; }
                if (cap->fmt == CAP_FMT_WEBM) {
                    argv[ac++] = "-c:a"; argv[ac++] = "libopus";
                    argv[ac++] = "-b:a"; argv[ac++] = "160k";
                } else {
                    argv[ac++] = "-c:a"; argv[ac++] = "aac";
                    argv[ac++] = "-b:a"; argv[ac++] = "192k";
                    argv[ac++] = "-movflags"; argv[ac++] = "+faststart";
                }
                argv[ac++] = "-shortest";
            } else {
                argv[ac++] = "-c:v"; argv[ac++] = "copy";
                if (cap->fmt == CAP_FMT_MP4) { argv[ac++] = "-movflags"; argv[ac++] = "+faststart"; }
            }
            argv[ac++] = cap->out_path;
            argv[ac] = NULL;
            ok = run_ffmpeg_sync(argv);
            remove(cap->tmp_vid_path);
            if (cap->wav_path[0]) remove(cap->wav_path);
        }
#endif
    } else if (cap->frame_count > 0) {
        ENG_LOGI("capture", "Saved %u PNG frames + WAV to %s (install ffmpeg for direct MP4/GIF muxing)",
                 (unsigned)cap->frame_count, cap->fallback_dir);
    }

    free(cap->rgba_buf);
    free(cap);
    return ok;
}

uint32_t eng_capture_frame_count(const eng_capture_t *cap) { return cap ? cap->frame_count : 0u; }
uint64_t eng_capture_audio_frames(const eng_capture_t *cap) { return cap ? cap->audio_frames : 0ull; }
bool eng_capture_is_using_ffmpeg(const eng_capture_t *cap) { return cap ? cap->using_ffmpeg : false; }
const char *eng_capture_output_path(const eng_capture_t *cap) { return cap ? cap->out_path : ""; }
