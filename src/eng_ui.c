#include "engine/eng_ui.h"
#include "engine/eng_gl.h"
#include "engine/eng_log.h"

#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_STANDARD_IO
#define NK_INCLUDE_STANDARD_VARARGS
#define NK_INCLUDE_DEFAULT_ALLOCATOR
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_DEFAULT_FONT
#include "nuklear.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_UI_MAX_VBUF (256 * 1024)
#define ENG_UI_MAX_EBUF (64 * 1024)
#define ENG_UI_HIST_MAX 64

typedef struct {
    float pos[2];
    float uv[2];
    nk_byte col[4];
} eng_nk_vertex_t;

struct eng_ui_s {
    struct nk_context ctx;
    struct nk_font_atlas atlas;
    struct nk_buffer cmds;
    struct nk_draw_null_texture tex_null;
    struct nk_font *default_font;

    int win_w;
    int win_h;

    bool console_open;
    char console_input[256];
    int console_input_len;
    char history[ENG_UI_HIST_MAX][256];
    size_t history_count;

    bool gl_ready;
    GLuint prog;
    GLint u_proj;
    GLint u_tex;
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLuint font_tex;
    GLuint null_tex;
    uint8_t *vbuf_cpu;
    uint8_t *ebuf_cpu;
};

static GLuint compile_ui_prog(const eng_gl_api_t *gl) {
    const char *vs_core =
        "#version 330 core\n"
        "layout(location=0) in vec2 a_pos;\n"
        "layout(location=1) in vec2 a_uv;\n"
        "layout(location=2) in vec4 a_col;\n"
        "uniform mat4 u_proj;\n"
        "out vec2 v_uv;\n"
        "out vec4 v_col;\n"
        "void main(){ v_uv = a_uv; v_col = a_col; gl_Position = u_proj * vec4(a_pos.xy, 0.0, 1.0); }\n";
    const char *fs_core =
        "#version 330 core\n"
        "uniform sampler2D u_tex;\n"
        "in vec2 v_uv;\n"
        "in vec4 v_col;\n"
        "out vec4 o_col;\n"
        "void main(){ o_col = v_col * texture(u_tex, v_uv); }\n";
    const char *vs_es =
        "#version 300 es\n"
        "layout(location=0) in vec2 a_pos;\n"
        "layout(location=1) in vec2 a_uv;\n"
        "layout(location=2) in vec4 a_col;\n"
        "uniform mat4 u_proj;\n"
        "out vec2 v_uv;\n"
        "out vec4 v_col;\n"
        "void main(){ v_uv = a_uv; v_col = a_col; gl_Position = u_proj * vec4(a_pos.xy, 0.0, 1.0); }\n";
    const char *fs_es =
        "#version 300 es\n"
        "precision mediump float;\n"
        "uniform sampler2D u_tex;\n"
        "in vec2 v_uv;\n"
        "in vec4 v_col;\n"
        "out vec4 o_col;\n"
        "void main(){ o_col = v_col * texture(u_tex, v_uv); }\n";

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

static void init_gl_backend(eng_ui_t *ui, const void *atlas_rgba, int aw, int ah) {
    const eng_gl_api_t *gl = eng_gl();
    if (!gl || !gl->CreateProgram) return;

    ui->prog = compile_ui_prog(gl);
    ui->u_proj = gl->GetUniformLocation(ui->prog, "u_proj");
    ui->u_tex = gl->GetUniformLocation(ui->prog, "u_tex");

    gl->GenTextures(1, &ui->font_tex);
    gl->BindTexture(ENG_GL_TEXTURE_2D, ui->font_tex);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MIN_FILTER, ENG_GL_LINEAR);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MAG_FILTER, ENG_GL_LINEAR);
    gl->TexImage2D(ENG_GL_TEXTURE_2D, 0, ENG_GL_RGBA8, aw, ah, 0, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, atlas_rgba);

    uint32_t white = 0xFFFFFFFFu;
    gl->GenTextures(1, &ui->null_tex);
    gl->BindTexture(ENG_GL_TEXTURE_2D, ui->null_tex);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MIN_FILTER, ENG_GL_NEAREST);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MAG_FILTER, ENG_GL_NEAREST);
    gl->TexImage2D(ENG_GL_TEXTURE_2D, 0, ENG_GL_RGBA8, 1, 1, 0, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, &white);

    gl->GenVertexArrays(1, &ui->vao);
    gl->GenBuffers(1, &ui->vbo);
    gl->GenBuffers(1, &ui->ebo);

    gl->BindVertexArray(ui->vao);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, ui->vbo);
    gl->BufferData(ENG_GL_ARRAY_BUFFER, ENG_UI_MAX_VBUF, NULL, ENG_GL_DYNAMIC_DRAW);
    gl->BindBuffer(ENG_GL_ELEMENT_ARRAY_BUFFER, ui->ebo);
    gl->BufferData(ENG_GL_ELEMENT_ARRAY_BUFFER, ENG_UI_MAX_EBUF, NULL, ENG_GL_DYNAMIC_DRAW);

    gl->EnableVertexAttribArray(0);
    gl->VertexAttribPointer(0, 2, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_nk_vertex_t),
                            (const void *)offsetof(eng_nk_vertex_t, pos));
    gl->EnableVertexAttribArray(1);
    gl->VertexAttribPointer(1, 2, ENG_GL_FLOAT, ENG_GL_FALSE, sizeof(eng_nk_vertex_t),
                            (const void *)offsetof(eng_nk_vertex_t, uv));
    gl->EnableVertexAttribArray(2);
    gl->VertexAttribPointer(2, 4, ENG_GL_UNSIGNED_BYTE, ENG_GL_TRUE, sizeof(eng_nk_vertex_t),
                            (const void *)offsetof(eng_nk_vertex_t, col));
    gl->BindVertexArray(0);
    ui->gl_ready = true;
}

eng_ui_t *eng_ui_create(void) {
    eng_ui_t *ui = (eng_ui_t *)calloc(1, sizeof(*ui));
    if (!ui) return NULL;
    ui->win_w = 1280;
    ui->win_h = 720;
    ui->vbuf_cpu = (uint8_t *)malloc(ENG_UI_MAX_VBUF);
    ui->ebuf_cpu = (uint8_t *)malloc(ENG_UI_MAX_EBUF);

    nk_font_atlas_init_default(&ui->atlas);
    nk_font_atlas_begin(&ui->atlas);
    ui->default_font = nk_font_atlas_add_default(&ui->atlas, 13.0f, NULL);
    int aw = 0, ah = 0;
    const void *img = nk_font_atlas_bake(&ui->atlas, &aw, &ah, NK_FONT_ATLAS_RGBA32);
    init_gl_backend(ui, img, aw, ah);
    nk_font_atlas_end(&ui->atlas, nk_handle_id((int)ui->font_tex), &ui->tex_null);
    ui->tex_null.texture = nk_handle_id((int)(ui->null_tex ? ui->null_tex : 1));

    nk_init_default(&ui->ctx, &ui->default_font->handle);
    nk_buffer_init_default(&ui->cmds);
    return ui;
}

void eng_ui_destroy(eng_ui_t *ui) {
    if (!ui) return;
    if (ui->gl_ready) {
        const eng_gl_api_t *gl = eng_gl();
        if (gl && gl->DeleteProgram) {
            gl->DeleteTextures(1, &ui->font_tex);
            gl->DeleteTextures(1, &ui->null_tex);
            gl->DeleteBuffers(1, &ui->vbo);
            gl->DeleteBuffers(1, &ui->ebo);
            gl->DeleteVertexArrays(1, &ui->vao);
            gl->DeleteProgram(ui->prog);
        }
    }
    nk_font_atlas_clear(&ui->atlas);
    nk_buffer_free(&ui->cmds);
    nk_free(&ui->ctx);
    free(ui->vbuf_cpu);
    free(ui->ebuf_cpu);
    free(ui);
}

struct nk_context *eng_ui_nk(eng_ui_t *ui) { return ui ? &ui->ctx : NULL; }
int eng_ui_width(const eng_ui_t *ui) { return ui ? ui->win_w : 0; }
int eng_ui_height(const eng_ui_t *ui) { return ui ? ui->win_h : 0; }

eng_ui_rect_t eng_ui_resolve_anchor(eng_ui_anchor_t anchor, float offset_x, float offset_y,
                                    float w, float h, int actual_w, int actual_h) {
    float sw = (actual_w > 0) ? ((float)actual_w / 1280.0f) : 1.0f;
    float sh = (actual_h > 0) ? ((float)actual_h / 720.0f) : 1.0f;
    float s = (sw < sh) ? sw : sh;
    if (s < 0.25f) s = 0.25f;

    float rw = w * s;
    float rh = h * s;
    float ox = offset_x * sw;
    float oy = offset_y * sh;
    float rx = ox, ry = oy;
    float fw = (float)(actual_w > 0 ? actual_w : 1280);
    float fh = (float)(actual_h > 0 ? actual_h : 720);

    switch (anchor) {
        case ENG_UI_TOP_LEFT:     rx = ox; ry = oy; break;
        case ENG_UI_TOP_RIGHT:    rx = fw - rw - ox; ry = oy; break;
        case ENG_UI_BOTTOM_LEFT:  rx = ox; ry = fh - rh - oy; break;
        case ENG_UI_BOTTOM_RIGHT: rx = fw - rw - ox; ry = fh - rh - oy; break;
        case ENG_UI_CENTER:       rx = (fw - rw) * 0.5f + ox; ry = (fh - rh) * 0.5f + oy; break;
    }

    if (rw > fw) rw = fw;
    if (rh > fh) rh = fh;
    if (rx < 0.0f) rx = 0.0f;
    if (ry < 0.0f) ry = 0.0f;
    if (rx + rw > fw) rx = fw - rw;
    if (ry + rh > fh) ry = fh - rh;

    return (eng_ui_rect_t){rx, ry, rw, rh};
}

void eng_ui_begin_frame(eng_ui_t *ui, int win_w, int win_h,
                        float mouse_x, float mouse_y, bool mouse_down, float wheel) {
    if (!ui) return;
    ui->win_w = (win_w > 0) ? win_w : 1280;
    ui->win_h = (win_h > 0) ? win_h : 720;

    nk_input_begin(&ui->ctx);
    nk_input_motion(&ui->ctx, (int)mouse_x, (int)mouse_y);
    nk_input_button(&ui->ctx, NK_BUTTON_LEFT, (int)mouse_x, (int)mouse_y, mouse_down ? 1 : 0);
    nk_input_scroll(&ui->ctx, nk_vec2(0.0f, wheel));
    nk_input_end(&ui->ctx);
}

void eng_ui_hud_label(eng_ui_t *ui, const char *id, eng_ui_anchor_t anchor,
                      float x, float y, float w, float h, const char *text) {
    if (!ui || !id || !text) return;
    eng_ui_rect_t r = eng_ui_resolve_anchor(anchor, x, y, w, h, ui->win_w, ui->win_h);
    if (nk_begin(&ui->ctx, id, nk_rect(r.x, r.y, r.w, r.h),
                 NK_WINDOW_NO_SCROLLBAR | NK_WINDOW_NO_INPUT | NK_WINDOW_BACKGROUND)) {
        nk_layout_row_dynamic(&ui->ctx, r.h - 8.0f, 1);
        nk_label(&ui->ctx, text, NK_TEXT_LEFT);
    }
    nk_end(&ui->ctx);
}

bool eng_ui_hud_button(eng_ui_t *ui, const char *id, eng_ui_anchor_t anchor,
                       float x, float y, float w, float h, const char *label) {
    if (!ui || !id || !label) return false;
    bool clicked = false;
    eng_ui_rect_t r = eng_ui_resolve_anchor(anchor, x, y, w, h, ui->win_w, ui->win_h);
    if (nk_begin(&ui->ctx, id, nk_rect(r.x, r.y, r.w, r.h), NK_WINDOW_NO_SCROLLBAR)) {
        nk_layout_row_dynamic(&ui->ctx, r.h - 8.0f, 1);
        if (nk_button_label(&ui->ctx, label)) clicked = true;
    }
    nk_end(&ui->ctx);
    return clicked;
}

void eng_ui_hud_bar(eng_ui_t *ui, const char *id, eng_ui_anchor_t anchor,
                    float x, float y, float w, float h, float fraction, const char *caption) {
    if (!ui || !id) return;
    if (fraction < 0.0f) fraction = 0.0f;
    if (fraction > 1.0f) fraction = 1.0f;
    eng_ui_rect_t r = eng_ui_resolve_anchor(anchor, x, y, w, h, ui->win_w, ui->win_h);
    if (nk_begin(&ui->ctx, id, nk_rect(r.x, r.y, r.w, r.h), NK_WINDOW_NO_SCROLLBAR | NK_WINDOW_NO_INPUT)) {
        nk_layout_row_dynamic(&ui->ctx, (r.h - 10.0f) * 0.5f, 1);
        if (caption) nk_label(&ui->ctx, caption, NK_TEXT_LEFT);
        nk_size cur = (nk_size)(fraction * 1000.0f);
        nk_progress(&ui->ctx, &cur, 1000, NK_FIXED);
    }
    nk_end(&ui->ctx);
}

void eng_ui_hud_touch_overlay(eng_ui_t *ui, eng_input_t *inp) {
    if (!ui || !inp || !eng_input_is_touch_active(inp)) return;
    if (eng_ui_hud_button(ui, "touch_act_a", ENG_UI_BOTTOM_RIGHT, 24.0f, 24.0f, 96.0f, 56.0f, "ACT / JUMP")) {
        eng_input_inject_action(inp, "jump", true);
    }
    eng_ui_hud_label(ui, "touch_pad_l", ENG_UI_BOTTOM_LEFT, 24.0f, 24.0f, 120.0f, 56.0f, "[ TOUCH MOVE ]");
}

static void push_history(eng_ui_t *ui, const char *line) {
    if (!line || !line[0]) return;
    if (ui->history_count < ENG_UI_HIST_MAX) {
        snprintf(ui->history[ui->history_count++], 256, "%s", line);
    } else {
        memmove(ui->history[0], ui->history[1], (ENG_UI_HIST_MAX - 1) * 256);
        snprintf(ui->history[ENG_UI_HIST_MAX - 1], 256, "%s", line);
    }
}

void eng_ui_toggle_console(eng_ui_t *ui) {
    if (ui) ui->console_open = !ui->console_open;
}

bool eng_ui_is_console_open(const eng_ui_t *ui) {
    return ui ? ui->console_open : false;
}

bool eng_ui_console_submit(eng_ui_t *ui, eng_runtime_t *rt, const char *line,
                           char *out_reply, size_t reply_cap) {
    if (out_reply && reply_cap > 0) out_reply[0] = '\0';
    if (!ui || !line) return false;
    while (*line == ' ' || *line == '\t') line++;
    if (!*line) return true;

    char echo[256];
    snprintf(echo, sizeof(echo), "> %s", line);
    push_history(ui, echo);

    char reply[512] = {0};
    bool ok = false;

    /* 1. Explicit CVar assignment: set <name> <val> */
    if (strncmp(line, "set ", 4) == 0) {
        char cname[64] = {0}, cval[64] = {0};
        if (sscanf(line + 4, "%63s %63s", cname, cval) == 2 && eng_cvar_set_string(cname, cval)) {
            snprintf(reply, sizeof(reply), "%s = %s", cname, cval);
            ok = true;
        }
    }

    /* 2. Registered C console command (unless expression starts with '=' or 'lua ') */
    if (!ok && line[0] != '=' && strncmp(line, "lua ", 4) != 0) {
        if (eng_cmd_exec(line, reply, sizeof(reply))) ok = true;
    }

    /* 3. Live Sandboxed Lua REPL */
    if (!ok && rt) {
        char lua_src[512];
        const char *expr = line;
        if (expr[0] == '=') {
            snprintf(lua_src, sizeof(lua_src), "return %s", expr + 1);
        } else if (strncmp(expr, "lua ", 4) == 0) {
            snprintf(lua_src, sizeof(lua_src), "%s", expr + 4);
        } else {
            snprintf(lua_src, sizeof(lua_src), "%s", expr);
        }
        ok = eng_runtime_exec_lua(rt, "=console", lua_src, reply, sizeof(reply));
    }

    if (reply[0]) {
        push_history(ui, reply);
        if (out_reply && reply_cap > 0) snprintf(out_reply, reply_cap, "%s", reply);
    }
    return ok;
}

size_t eng_ui_console_history_count(const eng_ui_t *ui) { return ui ? ui->history_count : 0u; }

const char *eng_ui_console_history_get(const eng_ui_t *ui, size_t idx) {
    if (!ui || idx >= ui->history_count) return NULL;
    return ui->history[idx];
}

void eng_ui_draw_console(eng_ui_t *ui, eng_runtime_t *rt) {
    if (!ui || !ui->console_open) return;
    float h = (float)ui->win_h * 0.45f;
    if (nk_begin(&ui->ctx, "Engine Console (~)", nk_rect(0.0f, 0.0f, (float)ui->win_w, h),
                 NK_WINDOW_BORDER | NK_WINDOW_TITLE)) {
        nk_layout_row_dynamic(&ui->ctx, 18.0f, 1);
        size_t nlog = eng_log_recent_count();
        size_t start = (nlog > 8) ? (nlog - 8) : 0;
        for (size_t i = start; i < nlog; i++) {
            const eng_log_entry_t *e = eng_log_recent_get(i);
            if (e) {
                char buf[320];
                snprintf(buf, sizeof(buf), "[%s] %s", e->category, e->message);
                nk_label(&ui->ctx, buf, NK_TEXT_LEFT);
            }
        }
        for (size_t i = 0; i < ui->history_count; i++) {
            nk_label(&ui->ctx, ui->history[i], NK_TEXT_LEFT);
        }
        nk_layout_row_dynamic(&ui->ctx, 26.0f, 2);
        nk_edit_string(&ui->ctx, NK_EDIT_SIMPLE, ui->console_input, &ui->console_input_len, 255, nk_filter_default);
        if (nk_button_label(&ui->ctx, "Run") && ui->console_input_len > 0) {
            ui->console_input[ui->console_input_len] = '\0';
            eng_ui_console_submit(ui, rt, ui->console_input, NULL, 0);
            ui->console_input_len = 0;
            ui->console_input[0] = '\0';
        }
    }
    nk_end(&ui->ctx);
}

void eng_ui_draw_profiler(eng_ui_t *ui, const eng_profiler_t *prof) {
    if (!ui || !prof) return;
    eng_ui_rect_t r = eng_ui_resolve_anchor(ENG_UI_TOP_RIGHT, 12.0f, 12.0f, 260.0f, 180.0f, ui->win_w, ui->win_h);
    if (nk_begin(&ui->ctx, "Profiler", nk_rect(r.x, r.y, r.w, r.h), NK_WINDOW_BORDER | NK_WINDOW_TITLE | NK_WINDOW_NO_SCROLLBAR)) {
        char line[128];
        nk_layout_row_dynamic(&ui->ctx, 18.0f, 1);
        snprintf(line, sizeof(line), "FPS: %.1f (%.2f ms)", eng_profiler_fps(prof), eng_profiler_frame_ms(prof));
        nk_label(&ui->ctx, line, NK_TEXT_LEFT);

        size_t used = 0, cap = 0;
        eng_profiler_get_arena_stats(prof, &used, &cap);
        snprintf(line, sizeof(line), "Arena: %zu / %zu KB", used / 1024u, cap / 1024u);
        nk_label(&ui->ctx, line, NK_TEXT_LEFT);

        uint32_t sc = eng_profiler_scope_count(prof);
        for (uint32_t i = 0; i < sc && i < 5; i++) {
            float ms = 0.0f;
            const char *nm = eng_profiler_scope_name(prof, i, &ms);
            snprintf(line, sizeof(line), "%s: %.3f ms", nm ? nm : "?", ms);
            nk_label(&ui->ctx, line, NK_TEXT_LEFT);
        }
    }
    nk_end(&ui->ctx);
}

uint32_t eng_ui_render(eng_ui_t *ui) {
    if (!ui) return 0u;
    static const struct nk_draw_vertex_layout_element vertex_layout[] = {
        {NK_VERTEX_POSITION, NK_FORMAT_FLOAT, offsetof(eng_nk_vertex_t, pos)},
        {NK_VERTEX_TEXCOORD, NK_FORMAT_FLOAT, offsetof(eng_nk_vertex_t, uv)},
        {NK_VERTEX_COLOR, NK_FORMAT_R8G8B8A8, offsetof(eng_nk_vertex_t, col)},
        {NK_VERTEX_LAYOUT_END}
    };

    struct nk_convert_config cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.vertex_layout = vertex_layout;
    cfg.vertex_size = sizeof(eng_nk_vertex_t);
    cfg.vertex_alignment = NK_ALIGNOF(eng_nk_vertex_t);
    cfg.tex_null = ui->tex_null;
    cfg.circle_segment_count = 16;
    cfg.curve_segment_count = 16;
    cfg.arc_segment_count = 16;
    cfg.global_alpha = 1.0f;
    cfg.shape_AA = NK_ANTI_ALIASING_ON;
    cfg.line_AA = NK_ANTI_ALIASING_ON;

    struct nk_buffer vbuf, ebuf;
    nk_buffer_init_fixed(&vbuf, ui->vbuf_cpu, ENG_UI_MAX_VBUF);
    nk_buffer_init_fixed(&ebuf, ui->ebuf_cpu, ENG_UI_MAX_EBUF);
    nk_convert(&ui->ctx, &ui->cmds, &vbuf, &ebuf, &cfg);

    uint32_t draws = 0;
    const eng_gl_api_t *gl = eng_gl();
    if (ui->gl_ready && gl && gl->DrawElements) {
        float ortho[16] = {
            2.0f / (float)ui->win_w, 0.0f, 0.0f, 0.0f,
            0.0f, -2.0f / (float)ui->win_h, 0.0f, 0.0f,
            0.0f, 0.0f, -1.0f, 0.0f,
            -1.0f, 1.0f, 0.0f, 1.0f
        };
        gl->Enable(ENG_GL_BLEND);
        gl->BlendFunc(ENG_GL_SRC_ALPHA, ENG_GL_ONE_MINUS_SRC_ALPHA);
        gl->Disable(ENG_GL_CULL_FACE);
        gl->Disable(ENG_GL_DEPTH_TEST);
        gl->Enable(ENG_GL_SCISSOR_TEST);

        gl->UseProgram(ui->prog);
        gl->Uniform1i(ui->u_tex, 0);
        gl->UniformMatrix4fv(ui->u_proj, 1, ENG_GL_FALSE, ortho);
        gl->ActiveTexture(ENG_GL_TEXTURE0);
        gl->BindVertexArray(ui->vao);
        gl->BindBuffer(ENG_GL_ARRAY_BUFFER, ui->vbo);
        gl->BufferSubData(ENG_GL_ARRAY_BUFFER, 0, (GLsizeiptr)vbuf.allocated, ui->vbuf_cpu);
        gl->BindBuffer(ENG_GL_ELEMENT_ARRAY_BUFFER, ui->ebo);
        gl->BufferSubData(ENG_GL_ELEMENT_ARRAY_BUFFER, 0, (GLsizeiptr)ebuf.allocated, ui->ebuf_cpu);

        const nk_draw_index *offset = NULL;
        const struct nk_draw_command *cmd = NULL;
        nk_draw_foreach(cmd, &ui->ctx, &ui->cmds) {
            if (!cmd->elem_count) continue;
            gl->BindTexture(ENG_GL_TEXTURE_2D, (GLuint)cmd->texture.id);
            int sy = (int)((float)ui->win_h - (cmd->clip_rect.y + cmd->clip_rect.h));
            if (sy < 0) sy = 0;
            gl->Scissor((GLint)cmd->clip_rect.x, (GLint)sy,
                        (GLsizei)(cmd->clip_rect.w > 0 ? cmd->clip_rect.w : 0),
                        (GLsizei)(cmd->clip_rect.h > 0 ? cmd->clip_rect.h : 0));
            gl->DrawElements(ENG_GL_TRIANGLES, (GLsizei)cmd->elem_count, ENG_GL_UNSIGNED_SHORT, offset);
            offset += cmd->elem_count;
            draws++;
        }
        gl->Disable(ENG_GL_SCISSOR_TEST);
        gl->Enable(ENG_GL_DEPTH_TEST);
        gl->BindVertexArray(0);
    }

    nk_clear(&ui->ctx);
    nk_buffer_clear(&ui->cmds);
    return draws;
}
