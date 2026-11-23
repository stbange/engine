#if !defined(_WIN32) && !defined(_XOPEN_SOURCE)
#define _XOPEN_SOURCE 700
#endif

#include "engine/eng_vfs.h"
#include "engine/eng_log.h"

#include <SDL3/SDL_filesystem.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_VFS_MAX_MOUNTS 16
#define ENG_VFS_MAX_WATCHES 128

typedef struct {
    char root[512];
    int priority;
    bool writable;
} eng_vfs_mount_t;

typedef struct {
    char vpath[256];
    int64_t last_mtime;
    eng_vfs_reload_fn cb;
    void *userdata;
} eng_vfs_watch_t;

struct eng_vfs_s {
    eng_vfs_mount_t mounts[ENG_VFS_MAX_MOUNTS];
    size_t mount_count;
    eng_vfs_watch_t watches[ENG_VFS_MAX_WATCHES];
    size_t watch_count;
};

eng_vfs_t *eng_vfs_create(void) {
    return (eng_vfs_t *)calloc(1, sizeof(eng_vfs_t));
}

void eng_vfs_destroy(eng_vfs_t *vfs) {
    free(vfs);
}

bool eng_vfs_mount(eng_vfs_t *vfs, const char *root_dir, int priority, bool writable) {
    if (!vfs || !root_dir || root_dir[0] == '\0' || vfs->mount_count >= ENG_VFS_MAX_MOUNTS) {
        return false;
    }
    eng_vfs_mount_t m;
    snprintf(m.root, sizeof(m.root), "%s", root_dir);
    size_t len = strlen(m.root);
    while (len > 1 && (m.root[len - 1] == '/' || m.root[len - 1] == '\\')) {
        m.root[--len] = '\0';
    }
    m.priority = priority;
    m.writable = writable;

    /* Insert sorted descending by priority so index 0 is highest priority */
    size_t pos = vfs->mount_count;
    while (pos > 0 && vfs->mounts[pos - 1].priority < priority) {
        vfs->mounts[pos] = vfs->mounts[pos - 1];
        pos--;
    }
    vfs->mounts[pos] = m;
    vfs->mount_count++;
    return true;
}

bool eng_vfs_sanitize_path(const char *vpath, char *out_clean, size_t out_cap) {
    if (!vpath || !out_clean || out_cap < 2 || vpath[0] == '\0' ||
        vpath[0] == '/' || vpath[0] == '\\') {
        return false;
    }
    for (const char *p = vpath; *p; p++) {
        if ((unsigned char)*p < 32 || *p == ':') {
            return false;
        }
    }

    size_t out_len = 0;
    const char *p = vpath;
    while (*p) {
        while (*p == '/' || *p == '\\') p++;
        if (!*p) break;
        const char *seg = p;
        while (*p && *p != '/' && *p != '\\') p++;
        size_t seg_len = (size_t)(p - seg);
        if (seg_len == 1 && seg[0] == '.') {
            continue;
        }
        if (seg_len == 2 && seg[0] == '.' && seg[1] == '.') {
            ENG_LOGE("vfs", "Path traversal rejected: %s", vpath);
            return false;
        }
        if (out_len > 0) {
            if (out_len + 1 >= out_cap) return false;
            out_clean[out_len++] = '/';
        }
        if (out_len + seg_len >= out_cap) return false;
        memcpy(out_clean + out_len, seg, seg_len);
        out_len += seg_len;
    }
    if (out_len == 0) return false;
    out_clean[out_len] = '\0';
    return true;
}

#if !defined(_WIN32) && !defined(__EMSCRIPTEN__)
static bool verify_no_symlink_escape(const char *mount_root, const char *candidate_path) {
    char real_root[PATH_MAX];
    char real_cand[PATH_MAX];
    if (!realpath(mount_root, real_root) || !realpath(candidate_path, real_cand)) {
        return false;
    }
    size_t rlen = strlen(real_root);
    return strncmp(real_cand, real_root, rlen) == 0 &&
           (real_cand[rlen] == '/' || real_cand[rlen] == '\0');
}
#endif

bool eng_vfs_resolve_read(const eng_vfs_t *vfs, const char *vpath, char *out_host_path, size_t out_cap) {
    char clean[256];
    if (!vfs || !out_host_path || !eng_vfs_sanitize_path(vpath, clean, sizeof(clean))) {
        return false;
    }
    for (size_t i = 0; i < vfs->mount_count; i++) {
        char candidate[1024];
        snprintf(candidate, sizeof(candidate), "%s/%s", vfs->mounts[i].root, clean);
        SDL_PathInfo info;
        if (SDL_GetPathInfo(candidate, &info) && info.type == SDL_PATHTYPE_FILE) {
#if !defined(_WIN32) && !defined(__EMSCRIPTEN__)
            if (!verify_no_symlink_escape(vfs->mounts[i].root, candidate)) {
                ENG_LOGE("vfs", "Symlink escape rejected: %s", vpath);
                return false;
            }
#endif
            snprintf(out_host_path, out_cap, "%s", candidate);
            return true;
        }
    }
    return false;
}

bool eng_vfs_exists(const eng_vfs_t *vfs, const char *vpath) {
    char host[1024];
    return eng_vfs_resolve_read(vfs, vpath, host, sizeof(host));
}

void *eng_vfs_read_all(const eng_vfs_t *vfs, const char *vpath, size_t *out_size) {
    if (out_size) *out_size = 0;
    char host[1024];
    if (!eng_vfs_resolve_read(vfs, vpath, host, sizeof(host))) {
        return NULL;
    }
    FILE *f = fopen(host, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long len = ftell(f);
    if (len < 0 || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return NULL;
    }
    char *buf = (char *)malloc((size_t)len + 1u);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    size_t nread = (len > 0) ? fread(buf, 1, (size_t)len, f) : 0;
    fclose(f);
    buf[nread] = '\0';
    if (out_size) *out_size = nread;
    return buf;
}

bool eng_vfs_write_all(const eng_vfs_t *vfs, const char *vpath, const void *data, size_t size) {
    char clean[256];
    if (!vfs || (!data && size > 0) || !eng_vfs_sanitize_path(vpath, clean, sizeof(clean))) {
        return false;
    }
    const eng_vfs_mount_t *target = NULL;
    for (size_t i = 0; i < vfs->mount_count; i++) {
        if (vfs->mounts[i].writable) {
            target = &vfs->mounts[i];
            break;
        }
    }
    if (!target) return false;

    char full[1024];
    snprintf(full, sizeof(full), "%s/%s", target->root, clean);
    char dir[1024];
    snprintf(dir, sizeof(dir), "%s", full);
    char *slash = strrchr(dir, '/');
    if (slash && !SDL_CreateDirectory(
        (*slash = '\0', dir))) {
        return false;
    }

    FILE *f = fopen(full, "wb");
    if (!f) return false;
    bool ok = (size == 0) || (fwrite(data, 1, size, f) == size);
    fclose(f);
    return ok;
}

static int64_t query_mtime(const eng_vfs_t *vfs, const char *vpath) {
    char host[1024];
    SDL_PathInfo info;
    if (eng_vfs_resolve_read(vfs, vpath, host, sizeof(host)) && SDL_GetPathInfo(host, &info)) {
        return (int64_t)info.modify_time;
    }
    return -1;
}

bool eng_vfs_watch(eng_vfs_t *vfs, const char *vpath, eng_vfs_reload_fn cb, void *userdata) {
    char clean[256];
    if (!vfs || !cb || vfs->watch_count >= ENG_VFS_MAX_WATCHES ||
        !eng_vfs_sanitize_path(vpath, clean, sizeof(clean))) {
        return false;
    }
    eng_vfs_watch_t *w = &vfs->watches[vfs->watch_count++];
    snprintf(w->vpath, sizeof(w->vpath), "%s", clean);
    w->last_mtime = query_mtime(vfs, clean);
    w->cb = cb;
    w->userdata = userdata;
    return true;
}

size_t eng_vfs_poll_reloads(eng_vfs_t *vfs) {
    if (!vfs) return 0;
    size_t triggered = 0;
    for (size_t i = 0; i < vfs->watch_count; i++) {
        eng_vfs_watch_t *w = &vfs->watches[i];
        int64_t now_mtime = query_mtime(vfs, w->vpath);
        if (now_mtime > 0 && now_mtime != w->last_mtime) {
            w->last_mtime = now_mtime;
            w->cb(w->vpath, w->userdata);
            triggered++;
        }
    }
    return triggered;
}
