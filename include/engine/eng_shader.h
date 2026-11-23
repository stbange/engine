#ifndef ENG_SHADER_H
#define ENG_SHADER_H

#include "eng_gl.h"
#include "eng_math.h"
#include "eng_vfs.h"

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    GLuint program;
    char vs_vpath[128];
    char fs_vpath[128];
    bool valid;
} eng_shader_t;

/* Compile vertex + fragment GLSL source strings, automatically injecting
 * "#version 330 core" (Desktop) or "#version 300 es" + precision (WebGL2)
 * and expanding #include "<vpath>" from vfs (if non-NULL). */
bool eng_shader_compile(eng_shader_t *out, const eng_vfs_t *vfs,
                        const char *vs_src, const char *fs_src);

bool eng_shader_load_vfs(eng_shader_t *out, eng_vfs_t *vfs,
                         const char *vs_vpath, const char *fs_vpath);

bool eng_shader_reload(eng_shader_t *sh, const eng_vfs_t *vfs);
void eng_shader_destroy(eng_shader_t *sh);

void eng_shader_bind(const eng_shader_t *sh);
void eng_shader_set_int(const eng_shader_t *sh, const char *name, int v);
void eng_shader_set_float(const eng_shader_t *sh, const char *name, float v);
void eng_shader_set_v3(const eng_shader_t *sh, const char *name, eng_vec3_t v);
void eng_shader_set_v4(const eng_shader_t *sh, const char *name, eng_vec4_t v);
void eng_shader_set_mat4(const eng_shader_t *sh, const char *name, const eng_mat4_t *m);

#ifdef __cplusplus
}
#endif

#endif /* ENG_SHADER_H */
