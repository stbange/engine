#include "engine/eng_profiler.h"
#include "engine/eng_gl.h"

#include <SDL3/SDL_timer.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define ENG_MAX_SCOPES 32
#define ENG_MAX_DEBUG_VERTS 16384

typedef struct {
    char name[32];
    uint64_t t0;
    float last_ms;
} eng_prof_scope_t;

typedef struct {
    float x, y, z;
    float r, g, b, a;
} eng_dbg_vert_t;

struct eng_profiler_s {
    uint64_t freq;
    uint64_t frame_t0;
    float frame_ms;
    float fps;
    size_t arena_used;
    size_t arena_cap;

    eng_prof_scope_t scopes[ENG_MAX_SCOPES];
    uint32_t scope_count;

    eng_dbg_vert_t verts[ENG_MAX_DEBUG_VERTS];
    uint32_t vert_count;

    bool gl_ready;
    GLuint prog;
    GLint u_vp;
    GLuint vao;
    GLuint vbo;
    GLuint gpu_query;
    bool query_active;
};

static GLuint compile_dbg_prog(const eng_gl_api_t *gl) {
    const char *vs_core =
        "#version 330 core\n"
        "layout(location=0) in vec3 a_pos;\n"
        "layout(location=1) in vec4 a_col;\n"
        "uniform mat4 u_vp;\n"
        "out vec4 v_col;\n"
        "void main(){ v_col = a_col; gl_Position = u_vp * vec4(a_pos, 1.0); }\n";
    const char *fs_core =
        "#version 330 core\n"
        "in vec4 v_col;\n"
        "out vec4 o_col;\n"
        "void main(){ o_col = v_col; }\n";
    const char *vs_es =
        "#version 300 es\n"
        "layout(location=0) in vec3 a_pos;\n"
        "layout(location=1) in vec4 a_col;\n"
        "uniform mat4 u_vp;\n"
        "out vec4 v_col;\n"
        "void main(){ v_col = a_col; gl_Position = u_vp * vec4(a_pos, 1.0); }\n";
    const char *fs_es =
        "#version 300 es\n"
        "precision mediump float;\n"
        "in vec4 v_col;\n"
        "out vec4 o_col;\n"
        "void main(){ o_col = v_col; }\n";

    const char *vs_src = gl->is_gles ? vs_es : vs_core;
    const char *fs_src = gl->is_gles ? fs_es : fs_core;

    GLuint vs = gl->CreateShader(ENG_GL_VERTEX_SHADER);
    gl->ShaderSource(vs, 1, &vs_src, NULL);
    gl->CompileShader(vs);

    GLuint fs = gl->CreateShader(ENG_GL_FRAGMENT_SHADER);
    gl->ShaderSource(fs, 1, &fs_src, NULL);
    gl->CompileShader(fs);

    GLuint p = gl->CreateProgram();
    gl->AttachShader(p, vs);
    gl->AttachShader(p, fs);
    gl->LinkProgram(p);
    gl->DeleteShader(vs);
    gl->DeleteShader(fs);
    return p;
}

static void ensure_gl(eng_profiler_t *prof) {
    if (prof->gl_ready) return;
    const eng_gl_api_t *gl = eng_gl();
    if (!gl || !gl->CreateProgram) return;
    prof->prog = compile_dbg_prog(gl);
    prof->u_vp = gl->GetUniformLocation(prof->prog, "u_vp");
    gl->GenVertexArrays(1, &prof->vao);
    gl->GenBuffers(1, &prof->vbo);
    gl->BindVertexArray(prof->vao);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, prof->vbo);
    gl->BufferData(ENG_GL_ARRAY_BUFFER, (GLsizeiptr)sizeof(prof->verts), NULL, ENG_GL_DYNAMIC_DRAW);
    gl->EnableVertexAttribArray(0);
    gl->VertexAttribPointer(0, 3, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_dbg_vert_t), (const void *)0);
    gl->EnableVertexAttribArray(1);
    gl->VertexAttribPointer(1, 4, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_dbg_vert_t), (const void *)(3 * sizeof(float)));
    gl->BindVertexArray(0);
    if (gl->GenQueries) gl->GenQueries(1, &prof->gpu_query);
    prof->gl_ready = true;
}

eng_profiler_t *eng_profiler_create(void) {
    eng_profiler_t *p = (eng_profiler_t *)calloc(1, sizeof(*p));
    if (!p) return NULL;
    p->freq = SDL_GetPerformanceFrequency();
    if (p->freq == 0) p->freq = 1000000000ull;
    p->frame_ms = 16.67f;
    p->fps = 60.0f;
    return p;
}

void eng_profiler_destroy(eng_profiler_t *prof) {
    if (!prof) return;
    if (prof->gl_ready) {
        const eng_gl_api_t *gl = eng_gl();
        if (gl && gl->DeleteProgram) {
            if (prof->gpu_query && gl->DeleteQueries) gl->DeleteQueries(1, &prof->gpu_query);
            gl->DeleteBuffers(1, &prof->vbo);
            gl->DeleteVertexArrays(1, &prof->vao);
            gl->DeleteProgram(prof->prog);
        }
    }
    free(prof);
}

static eng_prof_scope_t *find_or_add_scope(eng_profiler_t *prof, const char *name) {
    for (uint32_t i = 0; i < prof->scope_count; i++) {
        if (strcmp(prof->scopes[i].name, name) == 0) return &prof->scopes[i];
    }
    if (prof->scope_count >= ENG_MAX_SCOPES) return NULL;
    eng_prof_scope_t *s = &prof->scopes[prof->scope_count++];
    memset(s, 0, sizeof(*s));
    strncpy(s->name, name, sizeof(s->name) - 1);
    return s;
}

void eng_profiler_begin_frame(eng_profiler_t *prof) {
    if (!prof) return;
    prof->frame_t0 = SDL_GetPerformanceCounter();
    prof->vert_count = 0;
}

void eng_profiler_end_frame(eng_profiler_t *prof) {
    if (!prof) return;
    uint64_t dt_ticks = SDL_GetPerformanceCounter() - prof->frame_t0;
    float ms = (float)((double)dt_ticks * 1000.0 / (double)prof->freq);
    prof->frame_ms = ms;
    prof->fps = (ms > 0.0001f) ? (1000.0f / ms) : 1000.0f;
}

void eng_profiler_begin_scope(eng_profiler_t *prof, const char *name) {
    if (!prof || !name) return;
    eng_prof_scope_t *s = find_or_add_scope(prof, name);
    if (s) s->t0 = SDL_GetPerformanceCounter();
}

void eng_profiler_end_scope(eng_profiler_t *prof, const char *name) {
    if (!prof || !name) return;
    eng_prof_scope_t *s = find_or_add_scope(prof, name);
    if (s && s->t0 > 0) {
        uint64_t ticks = SDL_GetPerformanceCounter() - s->t0;
        s->last_ms = (float)((double)ticks * 1000.0 / (double)prof->freq);
    }
}

float eng_profiler_frame_ms(const eng_profiler_t *prof) { return prof ? prof->frame_ms : 0.0f; }
float eng_profiler_fps(const eng_profiler_t *prof) { return prof ? prof->fps : 0.0f; }

float eng_profiler_scope_ms(const eng_profiler_t *prof, const char *name) {
    if (!prof || !name) return 0.0f;
    for (uint32_t i = 0; i < prof->scope_count; i++) {
        if (strcmp(prof->scopes[i].name, name) == 0) return prof->scopes[i].last_ms;
    }
    return 0.0f;
}

uint32_t eng_profiler_scope_count(const eng_profiler_t *prof) { return prof ? prof->scope_count : 0u; }

const char *eng_profiler_scope_name(const eng_profiler_t *prof, uint32_t idx, float *out_ms) {
    if (!prof || idx >= prof->scope_count) return NULL;
    if (out_ms) *out_ms = prof->scopes[idx].last_ms;
    return prof->scopes[idx].name;
}

void eng_profiler_set_arena_stats(eng_profiler_t *prof, size_t used_bytes, size_t cap_bytes) {
    if (!prof) return;
    prof->arena_used = used_bytes;
    prof->arena_cap = cap_bytes;
}

void eng_profiler_get_arena_stats(const eng_profiler_t *prof, size_t *out_used, size_t *out_cap) {
    if (!prof) return;
    if (out_used) *out_used = prof->arena_used;
    if (out_cap) *out_cap = prof->arena_cap;
}

void eng_debug_line(eng_profiler_t *prof, eng_vec3_t a, eng_vec3_t b, eng_vec4_t color) {
    if (!prof || prof->vert_count + 2 > ENG_MAX_DEBUG_VERTS) return;
    prof->verts[prof->vert_count++] = (eng_dbg_vert_t){a.x, a.y, a.z, color.x, color.y, color.z, color.w};
    prof->verts[prof->vert_count++] = (eng_dbg_vert_t){b.x, b.y, b.z, color.x, color.y, color.z, color.w};
}

void eng_debug_aabb(eng_profiler_t *prof, eng_aabb_t box, eng_vec4_t color) {
    eng_vec3_t c[8] = {
        {box.min.x, box.min.y, box.min.z}, {box.max.x, box.min.y, box.min.z},
        {box.max.x, box.max.y, box.min.z}, {box.min.x, box.max.y, box.min.z},
        {box.min.x, box.min.y, box.max.z}, {box.max.x, box.min.y, box.max.z},
        {box.max.x, box.max.y, box.max.z}, {box.min.x, box.max.y, box.max.z},
    };
    static const uint8_t edges[12][2] = {
        {0, 1}, {1, 2}, {2, 3}, {3, 0},
        {4, 5}, {5, 6}, {6, 7}, {7, 4},
        {0, 4}, {1, 5}, {2, 6}, {3, 7}
    };
    for (int i = 0; i < 12; i++) {
        eng_debug_line(prof, c[edges[i][0]], c[edges[i][1]], color);
    }
}

void eng_debug_sphere(eng_profiler_t *prof, eng_vec3_t center, float r, eng_vec4_t color) {
    const int segs = 12;
    for (int i = 0; i < segs; i++) {
        float a0 = (float)i * (6.2831853f / (float)segs);
        float a1 = (float)(i + 1) * (6.2831853f / (float)segs);
        eng_debug_line(prof,
                       eng_v3(center.x + cosf(a0) * r, center.y, center.z + sinf(a0) * r),
                       eng_v3(center.x + cosf(a1) * r, center.y, center.z + sinf(a1) * r), color);
        eng_debug_line(prof,
                       eng_v3(center.x + cosf(a0) * r, center.y + sinf(a0) * r, center.z),
                       eng_v3(center.x + cosf(a1) * r, center.y + sinf(a1) * r, center.z), color);
    }
}

void eng_debug_portal(eng_profiler_t *prof, eng_vec3_t pos, eng_quat_t rot, float w, float h, eng_vec4_t color) {
    float hw = w * 0.5f, hh = h * 0.5f;
    eng_vec3_t local[4] = {{-hw, -hh, 0.0f}, {hw, -hh, 0.0f}, {hw, hh, 0.0f}, {-hw, hh, 0.0f}};
    eng_vec3_t world[4];
    for (int i = 0; i < 4; i++) world[i] = eng_v3_add(pos, eng_quat_rotate_v3(rot, local[i]));
    for (int i = 0; i < 4; i++) eng_debug_line(prof, world[i], world[(i + 1) & 3], color);
    eng_vec3_t fwd = eng_quat_rotate_v3(rot, eng_v3(0.0f, 0.0f, -0.5f));
    eng_debug_line(prof, pos, eng_v3_add(pos, fwd), color);
}

void eng_debug_skeleton(eng_profiler_t *prof, const eng_vec3_t *joint_world_pos,
                        const int32_t *parent_idx, uint32_t joint_count, eng_vec4_t color) {
    if (!prof || !joint_world_pos || !parent_idx) return;
    for (uint32_t i = 0; i < joint_count; i++) {
        int32_t p = parent_idx[i];
        if (p >= 0 && (uint32_t)p < joint_count) {
            eng_debug_line(prof, joint_world_pos[p], joint_world_pos[i], color);
        }
    }
}

void eng_debug_navpath(eng_profiler_t *prof, const eng_vec3_t *waypoints, uint32_t count, eng_vec4_t color) {
    if (!prof || !waypoints || count < 2) return;
    for (uint32_t i = 0; i + 1 < count; i++) {
        eng_debug_line(prof, waypoints[i], waypoints[i + 1], color);
    }
}

uint32_t eng_profiler_debug_vertex_count(const eng_profiler_t *prof) {
    return prof ? prof->vert_count : 0u;
}

void eng_profiler_render_debug_lines(eng_profiler_t *prof, const eng_mat4_t *view_proj) {
    if (!prof || !view_proj || prof->vert_count == 0) return;
    ensure_gl(prof);
    if (!prof->gl_ready) return;
    const eng_gl_api_t *gl = eng_gl();
    if (prof->gpu_query && gl->BeginQuery) {
        gl->BeginQuery(ENG_GL_ANY_SAMPLES_PASSED_CONSERVATIVE, prof->gpu_query);
        prof->query_active = true;
    }
    gl->UseProgram(prof->prog);
    gl->UniformMatrix4fv(prof->u_vp, 1, ENG_GL_FALSE, view_proj->m);
    gl->BindVertexArray(prof->vao);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, prof->vbo);
    gl->BufferSubData(ENG_GL_ARRAY_BUFFER, 0, (GLsizeiptr)(prof->vert_count * sizeof(eng_dbg_vert_t)), prof->verts);
    gl->DrawArrays(ENG_GL_LINES, 0, (GLsizei)prof->vert_count);
    gl->BindVertexArray(0);
    if (prof->query_active && gl->EndQuery) {
        gl->EndQuery(ENG_GL_ANY_SAMPLES_PASSED_CONSERVATIVE);
        GLuint passed = 0;
        if (gl->GetQueryObjectuiv) gl->GetQueryObjectuiv(prof->gpu_query, ENG_GL_QUERY_RESULT_AVAILABLE, &passed);
        prof->query_active = false;
    }
    prof->vert_count = 0;
}
