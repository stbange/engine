#ifndef ENG_VFS_H
#define ENG_VFS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct eng_vfs_s eng_vfs_t;
typedef void (*eng_vfs_reload_fn)(const char *vpath, void *userdata);

eng_vfs_t *eng_vfs_create(void);
void eng_vfs_destroy(eng_vfs_t *vfs);

/* Mount a host/MEMFS directory. Higher priority shadows lower priority on reads. */
bool eng_vfs_mount(eng_vfs_t *vfs, const char *root_dir, int priority, bool writable);

/* Validate and normalize a virtual relative path (rejects '..', leading '/', ':', control chars). */
bool eng_vfs_sanitize_path(const char *vpath, char *out_clean, size_t out_cap);

bool eng_vfs_exists(const eng_vfs_t *vfs, const char *vpath);
bool eng_vfs_resolve_read(const eng_vfs_t *vfs, const char *vpath, char *out_host_path, size_t out_cap);

/* Read entire file into a NUL-terminated malloc() buffer; caller frees with free(). */
void *eng_vfs_read_all(const eng_vfs_t *vfs, const char *vpath, size_t *out_size);
bool eng_vfs_write_all(const eng_vfs_t *vfs, const char *vpath, const void *data, size_t size);

/* Hot-reload file modification watcher */
bool eng_vfs_watch(eng_vfs_t *vfs, const char *vpath, eng_vfs_reload_fn cb, void *userdata);
size_t eng_vfs_poll_reloads(eng_vfs_t *vfs);

#ifdef __cplusplus
}
#endif

#endif /* ENG_VFS_H */
