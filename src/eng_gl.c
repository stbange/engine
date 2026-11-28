#include "engine/eng_gl.h"

#ifdef __EMSCRIPTEN__
#include <GLES3/gl3.h>
#endif

#include <string.h>

static eng_gl_api_t g_gl;
static uint32_t g_mock_next_id = 1;
static uint32_t g_mock_draws = 0;
static float g_mock_clear[4] = {0.1f, 0.12f, 0.16f, 1.0f};

static void mock_gen_ids(GLsizei n, GLuint *ids) {
    for (GLsizei i = 0; i < n && ids; i++) ids[i] = g_mock_next_id++;
}
static void mock_del_ids(GLsizei n, const GLuint *ids) { (void)n; (void)ids; }
static void mock_viewport(GLint x, GLint y, GLsizei w, GLsizei h) { (void)x; (void)y; (void)w; (void)h; }
static void mock_clear_color(GLfloat r, GLfloat g, GLfloat b, GLfloat a) {
    g_mock_clear[0] = r; g_mock_clear[1] = g; g_mock_clear[2] = b; g_mock_clear[3] = a;
}
static void mock_clear_stencil(GLint s) { (void)s; }
static void mock_clear(GLbitfield m) { (void)m; }
static void mock_enum1(GLenum e) { (void)e; }
static void mock_color_mask(GLboolean r, GLboolean g, GLboolean b, GLboolean a) { (void)r; (void)g; (void)b; (void)a; }
static void mock_depth_mask(GLboolean b) { (void)b; }
static void mock_stencil_func(GLenum f, GLint r, GLuint m) { (void)f; (void)r; (void)m; }
static void mock_stencil_op(GLenum sf, GLenum zf, GLenum zp) { (void)sf; (void)zf; (void)zp; }
static void mock_blend_func(GLenum s, GLenum d) { (void)s; (void)d; }
static void mock_bind_buf(GLenum t, GLuint b) { (void)t; (void)b; }
static void mock_buf_data(GLenum t, GLsizeiptr s, const void *d, GLenum u) { (void)t; (void)s; (void)d; (void)u; }
static void mock_buf_sub(GLenum t, GLintptr o, GLsizeiptr s, const void *d) { (void)t; (void)o; (void)s; (void)d; }
static void mock_bind_base(GLenum t, GLuint i, GLuint b) { (void)t; (void)i; (void)b; }
static void mock_uint1(GLuint v) { (void)v; }
static void mock_attrib_ptr(GLuint i, GLint s, GLenum t, GLboolean n, GLsizei st, const void *p) {
    (void)i; (void)s; (void)t; (void)n; (void)st; (void)p;
}
static void mock_attrib_div(GLuint i, GLuint d) { (void)i; (void)d; }
static GLuint mock_create_shader(GLenum t) { (void)t; return g_mock_next_id++; }
static void mock_shader_src(GLuint s, GLsizei c, const GLchar *const *str, const GLint *l) {
    (void)s; (void)c; (void)str; (void)l;
}
static void mock_get_iv(GLuint o, GLenum p, GLint *params) { (void)o; (void)p; if (params) *params = 1; }
static void mock_info_log(GLuint o, GLsizei cap, GLsizei *len, GLchar *log) {
    (void)o;
    if (len) *len = 0;
    if (log && cap > 0) log[0] = '\0';
}
static GLuint mock_create_prog(void) { return g_mock_next_id++; }
static void mock_attach(GLuint p, GLuint s) { (void)p; (void)s; }
static GLint mock_uniform_loc(GLuint p, const GLchar *n) { (void)p; return n ? 0 : -1; }
static GLuint mock_ublock_idx(GLuint p, const GLchar *n) { (void)p; (void)n; return 0; }
static void mock_ublock_bind(GLuint p, GLuint i, GLuint b) { (void)p; (void)i; (void)b; }
static void mock_u1i(GLint l, GLint v) { (void)l; (void)v; }
static void mock_u1f(GLint l, GLfloat v) { (void)l; (void)v; }
static void mock_ufv(GLint l, GLsizei c, const GLfloat *v) { (void)l; (void)c; (void)v; }
static void mock_um4(GLint l, GLsizei c, GLboolean t, const GLfloat *v) { (void)l; (void)c; (void)t; (void)v; }
static void mock_tex_img(GLenum t, GLint l, GLint ifmt, GLsizei w, GLsizei h, GLint b, GLenum fmt, GLenum tp, const void *px) {
    (void)t; (void)l; (void)ifmt; (void)w; (void)h; (void)b; (void)fmt; (void)tp; (void)px;
}
static void mock_tex_sub(GLenum t, GLint l, GLint x, GLint y, GLsizei w, GLsizei h, GLenum fmt, GLenum tp, const void *px) {
    (void)t; (void)l; (void)x; (void)y; (void)w; (void)h; (void)fmt; (void)tp; (void)px;
}
static void mock_tex_param(GLenum t, GLenum p, GLint v) { (void)t; (void)p; (void)v; }
static void mock_fbo_tex(GLenum t, GLenum a, GLenum tt, GLuint tx, GLint l) {
    (void)t; (void)a; (void)tt; (void)tx; (void)l;
}
static void mock_draw_bufs(GLsizei n, const GLenum *b) { (void)n; (void)b; }
static GLenum mock_check_fbo(GLenum t) { (void)t; return ENG_GL_FRAMEBUFFER_COMPLETE; }
static void mock_read_pixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum fmt, GLenum tp, void *px) {
    (void)x; (void)y; (void)fmt; (void)tp;
    if (!px || w <= 0 || h <= 0) return;
    uint8_t *out = (uint8_t *)px;
    uint8_t r = (uint8_t)(g_mock_clear[0] * 255.0f);
    uint8_t g = (uint8_t)(g_mock_clear[1] * 255.0f);
    uint8_t b = (uint8_t)(g_mock_clear[2] * 255.0f);
    for (int i = 0; i < w * h; i++) {
        out[i * 4 + 0] = r;
        out[i * 4 + 1] = g;
        out[i * 4 + 2] = b;
        out[i * 4 + 3] = 255;
    }
}
static void mock_blit_fbo(GLint sx0, GLint sy0, GLint sx1, GLint sy1, GLint dx0, GLint dy0, GLint dx1, GLint dy1, GLbitfield m, GLenum f) {
    (void)sx0; (void)sy0; (void)sx1; (void)sy1; (void)dx0; (void)dy0; (void)dx1; (void)dy1; (void)m; (void)f;
}
static void mock_draw_arrays(GLenum m, GLint f, GLsizei c) { (void)m; (void)f; (void)c; g_mock_draws++; }
static void mock_draw_elems(GLenum m, GLsizei c, GLenum t, const void *idx) { (void)m; (void)c; (void)t; (void)idx; g_mock_draws++; }
static void mock_draw_inst(GLenum m, GLsizei c, GLenum t, const void *idx, GLsizei inst) {
    (void)m; (void)c; (void)t; (void)idx; (void)inst; g_mock_draws++;
}
static void mock_begin_query(GLenum t, GLuint id) { (void)t; (void)id; }
static void mock_get_query(GLuint id, GLenum p, GLuint *out) { (void)id; (void)p; if (out) *out = 1u; }
static GLenum mock_get_err(void) { return 0; }

void eng_gl_init_software_mock(void) {
    memset(&g_gl, 0, sizeof(g_gl));
    g_gl.is_mock = true;
    g_mock_next_id = 1;
    g_mock_draws = 0;

    g_gl.Viewport = mock_viewport;
    g_gl.Scissor = mock_viewport;
    g_gl.ClearColor = mock_clear_color;
    g_gl.ClearStencil = mock_clear_stencil;
    g_gl.Clear = mock_clear;
    g_gl.Enable = mock_enum1;
    g_gl.Disable = mock_enum1;
    g_gl.ColorMask = mock_color_mask;
    g_gl.DepthFunc = mock_enum1;
    g_gl.DepthMask = mock_depth_mask;
    g_gl.StencilFunc = mock_stencil_func;
    g_gl.StencilOp = mock_stencil_op;
    g_gl.StencilMask = mock_uint1;
    g_gl.BlendFunc = mock_blend_func;
    g_gl.CullFace = mock_enum1;

    g_gl.GenBuffers = mock_gen_ids;
    g_gl.DeleteBuffers = mock_del_ids;
    g_gl.BindBuffer = mock_bind_buf;
    g_gl.BufferData = mock_buf_data;
    g_gl.BufferSubData = mock_buf_sub;
    g_gl.BindBufferBase = mock_bind_base;

    g_gl.GenVertexArrays = mock_gen_ids;
    g_gl.DeleteVertexArrays = mock_del_ids;
    g_gl.BindVertexArray = mock_uint1;
    g_gl.EnableVertexAttribArray = mock_uint1;
    g_gl.VertexAttribPointer = mock_attrib_ptr;
    g_gl.VertexAttribDivisor = mock_attrib_div;

    g_gl.CreateShader = mock_create_shader;
    g_gl.ShaderSource = mock_shader_src;
    g_gl.CompileShader = mock_uint1;
    g_gl.GetShaderiv = mock_get_iv;
    g_gl.GetShaderInfoLog = mock_info_log;
    g_gl.DeleteShader = mock_uint1;

    g_gl.CreateProgram = mock_create_prog;
    g_gl.AttachShader = mock_attach;
    g_gl.LinkProgram = mock_uint1;
    g_gl.GetProgramiv = mock_get_iv;
    g_gl.GetProgramInfoLog = mock_info_log;
    g_gl.UseProgram = mock_uint1;
    g_gl.DeleteProgram = mock_uint1;
    g_gl.GetUniformLocation = mock_uniform_loc;
    g_gl.GetUniformBlockIndex = mock_ublock_idx;
    g_gl.UniformBlockBinding = mock_ublock_bind;
    g_gl.Uniform1i = mock_u1i;
    g_gl.Uniform1f = mock_u1f;
    g_gl.Uniform3fv = mock_ufv;
    g_gl.Uniform4fv = mock_ufv;
    g_gl.UniformMatrix4fv = mock_um4;

    g_gl.ActiveTexture = mock_enum1;
    g_gl.GenTextures = mock_gen_ids;
    g_gl.DeleteTextures = mock_del_ids;
    g_gl.BindTexture = mock_bind_buf;
    g_gl.TexImage2D = mock_tex_img;
    g_gl.TexSubImage2D = mock_tex_sub;
    g_gl.TexParameteri = mock_tex_param;
    g_gl.GenerateMipmap = mock_enum1;

    g_gl.GenFramebuffers = mock_gen_ids;
    g_gl.DeleteFramebuffers = mock_del_ids;
    g_gl.BindFramebuffer = mock_bind_buf;
    g_gl.FramebufferTexture2D = mock_fbo_tex;
    g_gl.DrawBuffers = mock_draw_bufs;
    g_gl.ReadBuffer = mock_enum1;
    g_gl.CheckFramebufferStatus = mock_check_fbo;
    g_gl.ReadPixels = mock_read_pixels;
    g_gl.BlitFramebuffer = mock_blit_fbo;

    g_gl.DrawArrays = mock_draw_arrays;
    g_gl.DrawElements = mock_draw_elems;
    g_gl.DrawElementsInstanced = mock_draw_inst;

    g_gl.GenQueries = mock_gen_ids;
    g_gl.DeleteQueries = mock_del_ids;
    g_gl.BeginQuery = mock_begin_query;
    g_gl.EndQuery = mock_enum1;
    g_gl.GetQueryObjectuiv = mock_get_query;
    g_gl.GetError = mock_get_err;
}

bool eng_gl_load(eng_gl_load_fn loader, bool is_gles) {
    if (!loader) return false;
    /* Start with safe fallback pointers so optional query extensions never dereference NULL */
    eng_gl_init_software_mock();
    g_gl.is_mock = false;
    g_gl.is_gles = is_gles;

#define LOAD_REQ(field) do { \
        eng_gl_proc_t fn = loader("gl" #field); \
        if (!fn) return false; \
        memcpy(&g_gl.field, &fn, sizeof(fn)); \
    } while (0)
#define LOAD_OPT(field) do { \
        eng_gl_proc_t fn = loader("gl" #field); \
        if (fn) memcpy(&g_gl.field, &fn, sizeof(fn)); \
    } while (0)

    LOAD_REQ(Viewport);
    LOAD_REQ(Scissor);
    LOAD_REQ(ClearColor);
    LOAD_REQ(ClearStencil);
    LOAD_REQ(Clear);
    LOAD_REQ(Enable);
    LOAD_REQ(Disable);
    LOAD_REQ(ColorMask);
    LOAD_REQ(DepthFunc);
    LOAD_REQ(DepthMask);
    LOAD_REQ(StencilFunc);
    LOAD_REQ(StencilOp);
    LOAD_REQ(StencilMask);
    LOAD_REQ(BlendFunc);
    LOAD_REQ(CullFace);

    LOAD_REQ(GenBuffers);
    LOAD_REQ(DeleteBuffers);
    LOAD_REQ(BindBuffer);
    LOAD_REQ(BufferData);
    LOAD_REQ(BufferSubData);
    LOAD_REQ(BindBufferBase);

    LOAD_REQ(GenVertexArrays);
    LOAD_REQ(DeleteVertexArrays);
    LOAD_REQ(BindVertexArray);
    LOAD_REQ(EnableVertexAttribArray);
    LOAD_REQ(VertexAttribPointer);
    LOAD_REQ(VertexAttribDivisor);

    LOAD_REQ(CreateShader);
    LOAD_REQ(ShaderSource);
    LOAD_REQ(CompileShader);
    LOAD_REQ(GetShaderiv);
    LOAD_REQ(GetShaderInfoLog);
    LOAD_REQ(DeleteShader);

    LOAD_REQ(CreateProgram);
    LOAD_REQ(AttachShader);
    LOAD_REQ(LinkProgram);
    LOAD_REQ(GetProgramiv);
    LOAD_REQ(GetProgramInfoLog);
    LOAD_REQ(UseProgram);
    LOAD_REQ(DeleteProgram);
    LOAD_REQ(GetUniformLocation);
    LOAD_REQ(GetUniformBlockIndex);
    LOAD_REQ(UniformBlockBinding);
    LOAD_REQ(Uniform1i);
    LOAD_REQ(Uniform1f);
    LOAD_REQ(Uniform3fv);
    LOAD_REQ(Uniform4fv);
    LOAD_REQ(UniformMatrix4fv);

    LOAD_REQ(ActiveTexture);
    LOAD_REQ(GenTextures);
    LOAD_REQ(DeleteTextures);
    LOAD_REQ(BindTexture);
    LOAD_REQ(TexImage2D);
    LOAD_REQ(TexSubImage2D);
    LOAD_REQ(TexParameteri);
    LOAD_REQ(GenerateMipmap);

    LOAD_REQ(GenFramebuffers);
    LOAD_REQ(DeleteFramebuffers);
    LOAD_REQ(BindFramebuffer);
    LOAD_REQ(FramebufferTexture2D);
    LOAD_REQ(DrawBuffers);
    LOAD_REQ(ReadBuffer);
    LOAD_REQ(CheckFramebufferStatus);
    LOAD_REQ(ReadPixels);
    LOAD_OPT(BlitFramebuffer);

    LOAD_REQ(DrawArrays);
    LOAD_REQ(DrawElements);
    LOAD_REQ(DrawElementsInstanced);

    LOAD_OPT(GenQueries);
    LOAD_OPT(DeleteQueries);
    LOAD_OPT(BeginQuery);
    LOAD_OPT(EndQuery);
    LOAD_OPT(GetQueryObjectuiv);
    LOAD_REQ(GetError);

#undef LOAD_REQ
#undef LOAD_OPT
    return true;
}

const eng_gl_api_t *eng_gl(void) {
    return &g_gl;
}

uint32_t eng_gl_mock_draw_calls(void) {
    return g_mock_draws;
}

void eng_gl_mock_reset_stats(void) {
    g_mock_draws = 0;
}
