#ifndef ENG_GL_H
#define ENG_GL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Portable OpenGL 3.3 Core / GLES 3.0 (WebGL2) types & constants (MIT, zero Khronos XML generator needed). */
typedef uint32_t GLenum;
typedef uint8_t  GLboolean;
typedef uint32_t GLbitfield;
typedef int32_t  GLint;
typedef uint32_t GLuint;
typedef int32_t  GLsizei;
typedef float    GLfloat;
typedef char     GLchar;
typedef ptrdiff_t GLsizeiptr;
typedef ptrdiff_t GLintptr;

#define ENG_GL_FALSE                 0
#define ENG_GL_TRUE                  1
#define ENG_GL_DEPTH_BUFFER_BIT      0x00000100u
#define ENG_GL_STENCIL_BUFFER_BIT    0x00000400u
#define ENG_GL_COLOR_BUFFER_BIT      0x00004000u
#define ENG_GL_LINES                 0x0001u
#define ENG_GL_TRIANGLES             0x0004u
#define ENG_GL_SRC_ALPHA             0x0302u
#define ENG_GL_ONE_MINUS_SRC_ALPHA   0x0303u
#define ENG_GL_FRONT                 0x0404u
#define ENG_GL_BACK                  0x0405u
#define ENG_GL_CULL_FACE             0x0B44u
#define ENG_GL_DEPTH_TEST            0x0B71u
#define ENG_GL_BLEND                 0x0BE2u
#define ENG_GL_SCISSOR_TEST          0x0C11u
#define ENG_GL_TEXTURE_2D            0x0DE1u
#define ENG_GL_UNSIGNED_BYTE         0x1401u
#define ENG_GL_UNSIGNED_SHORT        0x1403u
#define ENG_GL_UNSIGNED_INT          0x1405u
#define ENG_GL_FLOAT                 0x1406u
#define ENG_GL_DEPTH_COMPONENT       0x1902u
#define ENG_GL_RGBA                  0x1908u
#define ENG_GL_NEAREST               0x2600u
#define ENG_GL_LINEAR                0x2601u
#define ENG_GL_LINEAR_MIPMAP_LINEAR  0x2703u
#define ENG_GL_TEXTURE_MAG_FILTER    0x2800u
#define ENG_GL_TEXTURE_MIN_FILTER    0x2801u
#define ENG_GL_TEXTURE_WRAP_S        0x2802u
#define ENG_GL_TEXTURE_WRAP_T        0x2803u
#define ENG_GL_TEXTURE_WRAP_R        0x8072u
#define ENG_GL_REPEAT                0x2901u
#define ENG_GL_CLAMP_TO_EDGE         0x812Fu
#define ENG_GL_RGBA8                 0x8058u
#define ENG_GL_RGBA16F               0x881Au
#define ENG_GL_DEPTH_COMPONENT24     0x81A6u
#define ENG_GL_TEXTURE0              0x84C0u
#define ENG_GL_TEXTURE_CUBE_MAP      0x8513u
#define ENG_GL_TEXTURE_CUBE_MAP_POSITIVE_X 0x8515u
#define ENG_GL_ARRAY_BUFFER          0x8892u
#define ENG_GL_ELEMENT_ARRAY_BUFFER  0x8893u
#define ENG_GL_UNIFORM_BUFFER        0x8A11u
#define ENG_GL_STATIC_DRAW           0x88E4u
#define ENG_GL_DYNAMIC_DRAW          0x88E8u
#define ENG_GL_FRAGMENT_SHADER       0x8B30u
#define ENG_GL_VERTEX_SHADER         0x8B31u
#define ENG_GL_COMPILE_STATUS        0x8B81u
#define ENG_GL_LINK_STATUS           0x8B82u
#define ENG_GL_FRAMEBUFFER           0x8D40u
#define ENG_GL_READ_FRAMEBUFFER      0x8CA8u
#define ENG_GL_DRAW_FRAMEBUFFER      0x8CA9u
#define ENG_GL_COLOR_ATTACHMENT0     0x8CE0u
#define ENG_GL_DEPTH_ATTACHMENT      0x8D00u
#define ENG_GL_FRAMEBUFFER_COMPLETE  0x8CD5u
#define ENG_GL_DEPTH24_STENCIL8      0x88F0u
#define ENG_GL_DEPTH_STENCIL         0x84F9u
#define ENG_GL_UNSIGNED_INT_24_8     0x84FAu
#define ENG_GL_DEPTH_STENCIL_ATTACHMENT 0x821Au
#define ENG_GL_COLOR_ATTACHMENT1     0x8CE1u
#define ENG_GL_COLOR_ATTACHMENT2     0x8CE2u
#define ENG_GL_STENCIL_TEST          0x0B90u
#define ENG_GL_KEEP                  0x1E00u
#define ENG_GL_REPLACE               0x1E01u
#define ENG_GL_INCR                  0x1E02u
#define ENG_GL_DECR                  0x1E03u
#define ENG_GL_EQUAL                 0x0202u
#define ENG_GL_LEQUAL                0x0203u
#define ENG_GL_LESS                  0x0201u
#define ENG_GL_ALWAYS                0x0207u
#define ENG_GL_ZERO                  0u
#define ENG_GL_ONE                   1u
#define ENG_GL_ANY_SAMPLES_PASSED_CONSERVATIVE 0x8D6Au
#define ENG_GL_QUERY_RESULT          0x8866u
#define ENG_GL_QUERY_RESULT_AVAILABLE 0x8867u

typedef struct {
    bool is_gles;
    bool is_mock;
    void (*Viewport)(GLint x, GLint y, GLsizei w, GLsizei h);
    void (*Scissor)(GLint x, GLint y, GLsizei w, GLsizei h);
    void (*ClearColor)(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
    void (*ClearStencil)(GLint s);
    void (*Clear)(GLbitfield mask);
    void (*Enable)(GLenum cap);
    void (*Disable)(GLenum cap);
    void (*ColorMask)(GLboolean r, GLboolean g, GLboolean b, GLboolean a);
    void (*DepthFunc)(GLenum func);
    void (*DepthMask)(GLboolean flag);
    void (*StencilFunc)(GLenum func, GLint ref, GLuint mask);
    void (*StencilOp)(GLenum fail, GLenum zfail, GLenum zpass);
    void (*StencilMask)(GLuint mask);
    void (*BlendFunc)(GLenum sfactor, GLenum dfactor);
    void (*CullFace)(GLenum mode);

    void (*GenBuffers)(GLsizei n, GLuint *buffers);
    void (*DeleteBuffers)(GLsizei n, const GLuint *buffers);
    void (*BindBuffer)(GLenum target, GLuint buffer);
    void (*BufferData)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
    void (*BufferSubData)(GLenum target, GLintptr offset, GLsizeiptr size, const void *data);
    void (*BindBufferBase)(GLenum target, GLuint index, GLuint buffer);

    void (*GenVertexArrays)(GLsizei n, GLuint *arrays);
    void (*DeleteVertexArrays)(GLsizei n, const GLuint *arrays);
    void (*BindVertexArray)(GLuint array);
    void (*EnableVertexAttribArray)(GLuint index);
    void (*VertexAttribPointer)(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer);
    void (*VertexAttribDivisor)(GLuint index, GLuint divisor);

    GLuint (*CreateShader)(GLenum type);
    void (*ShaderSource)(GLuint shader, GLsizei count, const GLchar *const *string, const GLint *length);
    void (*CompileShader)(GLuint shader);
    void (*GetShaderiv)(GLuint shader, GLenum pname, GLint *params);
    void (*GetShaderInfoLog)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
    void (*DeleteShader)(GLuint shader);

    GLuint (*CreateProgram)(void);
    void (*AttachShader)(GLuint program, GLuint shader);
    void (*LinkProgram)(GLuint program);
    void (*GetProgramiv)(GLuint program, GLenum pname, GLint *params);
    void (*GetProgramInfoLog)(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
    void (*UseProgram)(GLuint program);
    void (*DeleteProgram)(GLuint program);
    GLint (*GetUniformLocation)(GLuint program, const GLchar *name);
    GLuint (*GetUniformBlockIndex)(GLuint program, const GLchar *blockName);
    void (*UniformBlockBinding)(GLuint program, GLuint blockIndex, GLuint blockBinding);
    void (*Uniform1i)(GLint location, GLint v0);
    void (*Uniform1f)(GLint location, GLfloat v0);
    void (*Uniform3fv)(GLint location, GLsizei count, const GLfloat *value);
    void (*Uniform4fv)(GLint location, GLsizei count, const GLfloat *value);
    void (*UniformMatrix4fv)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);

    void (*ActiveTexture)(GLenum texture);
    void (*GenTextures)(GLsizei n, GLuint *textures);
    void (*DeleteTextures)(GLsizei n, const GLuint *textures);
    void (*BindTexture)(GLenum target, GLuint texture);
    void (*TexImage2D)(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
    void (*TexSubImage2D)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const void *pixels);
    void (*TexParameteri)(GLenum target, GLenum pname, GLint param);
    void (*GenerateMipmap)(GLenum target);

    void (*GenFramebuffers)(GLsizei n, GLuint *framebuffers);
    void (*DeleteFramebuffers)(GLsizei n, const GLuint *framebuffers);
    void (*BindFramebuffer)(GLenum target, GLuint framebuffer);
    void (*FramebufferTexture2D)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
    void (*DrawBuffers)(GLsizei n, const GLenum *bufs);
    void (*ReadBuffer)(GLenum src);
    GLenum (*CheckFramebufferStatus)(GLenum target);
    void (*ReadPixels)(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels);
    void (*BlitFramebuffer)(GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1, GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1, GLbitfield mask, GLenum filter);

    void (*DrawArrays)(GLenum mode, GLint first, GLsizei count);
    void (*DrawElements)(GLenum mode, GLsizei count, GLenum type, const void *indices);
    void (*DrawElementsInstanced)(GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount);

    void (*GenQueries)(GLsizei n, GLuint *ids);
    void (*DeleteQueries)(GLsizei n, const GLuint *ids);
    void (*BeginQuery)(GLenum target, GLuint id);
    void (*EndQuery)(GLenum target);
    void (*GetQueryObjectuiv)(GLuint id, GLenum pname, GLuint *params);
    GLenum (*GetError)(void);
} eng_gl_api_t;

typedef void (*eng_gl_proc_t)(void);
typedef eng_gl_proc_t (*eng_gl_load_fn)(const char *name);

/* Load real OpenGL 3.3 Core / GLES 3.0 functions via SDL_GL_GetProcAddress (or custom loader). */
bool eng_gl_load(eng_gl_load_fn loader, bool is_gles);

/* Initialize deterministic headless software GL mock (used in GPU-less CI / unit tests). */
void eng_gl_init_software_mock(void);

const eng_gl_api_t *eng_gl(void);
uint32_t eng_gl_mock_draw_calls(void);
void eng_gl_mock_reset_stats(void);

#ifdef __cplusplus
}
#endif

#endif /* ENG_GL_H */
