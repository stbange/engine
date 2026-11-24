#include "engine/eng_shader.h"
#include "engine/eng_log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *preprocess_glsl(const eng_vfs_t *vfs, const char *src, bool is_frag) {
    const eng_gl_api_t *gl = eng_gl();
    size_t cap = 65536;
    char *out = (char *)malloc(cap);
    if (!out) return NULL;
    size_t len = 0;

    if (gl->is_gles) {
        len += (size_t)snprintf(out + len, cap - len,
                                "#version 300 es\nprecision highp float;\nprecision highp int;\n%s",
                                is_frag ? "" : "");
    } else {
        len += (size_t)snprintf(out + len, cap - len, "#version 330 core\n");
    }

    const char *p = src;
    if (strncmp(p, "#version", 8) == 0) {
        while (*p && *p != '\n') p++;
        if (*p == '\n') p++;
    }

    while (*p && len + 256 < cap) {
        if (strncmp(p, "#include \"", 10) == 0 && vfs) {
            p += 10;
            char inc_path[128];
            size_t k = 0;
            while (*p && *p != '"' && *p != '\n' && k + 1 < sizeof(inc_path)) {
                inc_path[k++] = *p++;
            }
            inc_path[k] = '\0';
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;

            size_t inc_sz = 0;
            char *inc_txt = (char *)eng_vfs_read_all(vfs, inc_path, &inc_sz);
            if (inc_txt) {
                if (len + inc_sz + 2 < cap) {
                    memcpy(out + len, inc_txt, inc_sz);
                    len += inc_sz;
                    out[len++] = '\n';
                }
                free(inc_txt);
            }
        } else {
            out[len++] = *p++;
        }
    }
    out[len] = '\0';
    return out;
}

static GLuint compile_stage(GLenum type, const char *full_src) {
    const eng_gl_api_t *gl = eng_gl();
    GLuint s = gl->CreateShader(type);
    gl->ShaderSource(s, 1, &full_src, NULL);
    gl->CompileShader(s);
    GLint ok = 0;
    gl->GetShaderiv(s, ENG_GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512] = {0};
        gl->GetShaderInfoLog(s, sizeof(log), NULL, log);
        ENG_LOGE("shader", "Compile error: %s", log);
        fprintf(stderr, "[shader] Compile error: %s\n", log);
        gl->DeleteShader(s);
        return 0;
    }
    return s;
}

bool eng_shader_compile(eng_shader_t *out, const eng_vfs_t *vfs,
                        const char *vs_src, const char *fs_src) {
    if (!out || !vs_src || !fs_src) return false;
    const eng_gl_api_t *gl = eng_gl();

    char *vs_full = preprocess_glsl(vfs, vs_src, false);
    char *fs_full = preprocess_glsl(vfs, fs_src, true);
    if (!vs_full || !fs_full) {
        free(vs_full);
        free(fs_full);
        return false;
    }

    GLuint vs = compile_stage(ENG_GL_VERTEX_SHADER, vs_full);
    GLuint fs = vs ? compile_stage(ENG_GL_FRAGMENT_SHADER, fs_full) : 0;
    free(vs_full);
    free(fs_full);
    if (!vs || !fs) {
        if (vs) gl->DeleteShader(vs);
        return false;
    }

    GLuint prog = gl->CreateProgram();
    gl->AttachShader(prog, vs);
    gl->AttachShader(prog, fs);
    gl->LinkProgram(prog);
    gl->DeleteShader(vs);
    gl->DeleteShader(fs);

    GLint linked = 0;
    gl->GetProgramiv(prog, ENG_GL_LINK_STATUS, &linked);
    if (!linked) {
        char log[512] = {0};
        gl->GetProgramInfoLog(prog, sizeof(log), NULL, log);
        ENG_LOGE("shader", "Link error: %s", log);
        fprintf(stderr, "[shader] Link error: %s\n", log);
        gl->DeleteProgram(prog);
        return false;
    }

    if (out->valid && out->program) {
        gl->DeleteProgram(out->program);
    }
    out->program = prog;
    out->valid = true;
    return true;
}

bool eng_shader_load_vfs(eng_shader_t *out, eng_vfs_t *vfs,
                         const char *vs_vpath, const char *fs_vpath) {
    if (!out || !vfs || !vs_vpath || !fs_vpath) return false;
    memset(out, 0, sizeof(*out));
    snprintf(out->vs_vpath, sizeof(out->vs_vpath), "%s", vs_vpath);
    snprintf(out->fs_vpath, sizeof(out->fs_vpath), "%s", fs_vpath);
    return eng_shader_reload(out, vfs);
}

bool eng_shader_reload(eng_shader_t *sh, const eng_vfs_t *vfs) {
    if (!sh || !vfs || sh->vs_vpath[0] == '\0' || sh->fs_vpath[0] == '\0') return false;
    char *vs_txt = (char *)eng_vfs_read_all(vfs, sh->vs_vpath, NULL);
    char *fs_txt = (char *)eng_vfs_read_all(vfs, sh->fs_vpath, NULL);
    bool ok = false;
    if (vs_txt && fs_txt) {
        ok = eng_shader_compile(sh, vfs, vs_txt, fs_txt);
    }
    free(vs_txt);
    free(fs_txt);
    return ok;
}

void eng_shader_destroy(eng_shader_t *sh) {
    if (sh && sh->valid && sh->program) {
        eng_gl()->DeleteProgram(sh->program);
    }
    if (sh) memset(sh, 0, sizeof(*sh));
}

void eng_shader_bind(const eng_shader_t *sh) {
    if (sh && sh->valid) eng_gl()->UseProgram(sh->program);
}

void eng_shader_set_int(const eng_shader_t *sh, const char *name, int v) {
    if (!sh || !sh->valid) return;
    GLint loc = eng_gl()->GetUniformLocation(sh->program, name);
    if (loc >= 0) eng_gl()->Uniform1i(loc, v);
}

void eng_shader_set_float(const eng_shader_t *sh, const char *name, float v) {
    if (!sh || !sh->valid) return;
    GLint loc = eng_gl()->GetUniformLocation(sh->program, name);
    if (loc >= 0) eng_gl()->Uniform1f(loc, v);
}

void eng_shader_set_v3(const eng_shader_t *sh, const char *name, eng_vec3_t v) {
    if (!sh || !sh->valid) return;
    GLint loc = eng_gl()->GetUniformLocation(sh->program, name);
    if (loc >= 0) eng_gl()->Uniform3fv(loc, 1, &v.x);
}

void eng_shader_set_v4(const eng_shader_t *sh, const char *name, eng_vec4_t v) {
    if (!sh || !sh->valid) return;
    GLint loc = eng_gl()->GetUniformLocation(sh->program, name);
    if (loc >= 0) eng_gl()->Uniform4fv(loc, 1, &v.x);
}

void eng_shader_set_mat4(const eng_shader_t *sh, const char *name, const eng_mat4_t *m) {
    if (!sh || !sh->valid || !m) return;
    GLint loc = eng_gl()->GetUniformLocation(sh->program, name);
    if (loc >= 0) eng_gl()->UniformMatrix4fv(loc, 1, ENG_GL_FALSE, m->m);
}
