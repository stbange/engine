#ifndef ENG_TEXT_H
#define ENG_TEXT_H

#include "eng_asset.h"
#include "eng_math.h"
#include "eng_vfs.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct eng_font_s eng_font_t;

/* Decode next UTF-8 codepoint from *cursor, advancing *cursor; returns 0 at end, 0xFFFD on invalid sequence. */
uint32_t eng_utf8_next(const char **cursor);

/* Create built-in crisp 5x7 SDF fallback font (works before any .ttf file is loaded). */
eng_font_t *eng_font_create_builtin(eng_asset_cache_t *assets);

/* Bake a TrueType (.ttf) SDF font atlas (ASCII + Latin-1 + common symbols) from VFS. */
eng_font_t *eng_font_load_ttf(eng_asset_cache_t *assets, const eng_vfs_t *vfs,
                              const char *vpath, float pixel_height);

void eng_font_destroy(eng_font_t *font);
uint32_t eng_font_texture_id(const eng_font_t *font);

/* Measure UTF-8 string width and height in scaled units. */
eng_vec2_t eng_text_measure(const eng_font_t *font, const char *utf8_text, float scale);

/* Append 3D/2D textured quads for UTF-8 text on the XY plane starting at origin (+X right, +Y up). */
size_t eng_text_build_mesh(const eng_font_t *font, const char *utf8_text,
                           eng_vec3_t origin, float scale, eng_vec4_t color,
                           eng_mesh_data_t *out_mesh);

#ifdef __cplusplus
}
#endif

#endif /* ENG_TEXT_H */
