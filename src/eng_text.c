#include "engine/eng_text.h"
#include "stb_truetype.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define ENG_FONT_ATLAS_W 512
#define ENG_FONT_ATLAS_H 512
#define ENG_FONT_MAX_GLYPHS 256

typedef struct {
    uint32_t codepoint;
    float u0, v0, u1, v1;
    float xoff, yoff, w, h;
    float xadvance;
    bool valid;
} glyph_info_t;

struct eng_font_s {
    uint32_t tex_id;
    float line_height;
    glyph_info_t glyphs[ENG_FONT_MAX_GLYPHS];
    size_t glyph_count;
};

uint32_t eng_utf8_next(const char **cursor) {
    if (!cursor || !*cursor || !**cursor) return 0;
    const uint8_t *s = (const uint8_t *)(*cursor);
    uint8_t c0 = s[0];
    if (c0 < 0x80u) {
        *cursor += 1;
        return c0;
    }
    if ((c0 & 0xE0u) == 0xC0u && (s[1] & 0xC0u) == 0x80u) {
        uint32_t cp = ((uint32_t)(c0 & 0x1Fu) << 6) | (uint32_t)(s[1] & 0x3Fu);
        *cursor += 2;
        return cp >= 0x80u ? cp : 0xFFFDu;
    }
    if ((c0 & 0xF0u) == 0xE0u && (s[1] & 0xC0u) == 0x80u && (s[2] & 0xC0u) == 0x80u) {
        uint32_t cp = ((uint32_t)(c0 & 0x0Fu) << 12) | ((uint32_t)(s[1] & 0x3Fu) << 6) | (uint32_t)(s[2] & 0x3Fu);
        *cursor += 3;
        return cp >= 0x800u ? cp : 0xFFFDu;
    }
    if ((c0 & 0xF8u) == 0xF0u && (s[1] & 0xC0u) == 0x80u && (s[2] & 0xC0u) == 0x80u && (s[3] & 0xC0u) == 0x80u) {
        uint32_t cp = ((uint32_t)(c0 & 0x07u) << 18) | ((uint32_t)(s[1] & 0x3Fu) << 12) |
                      ((uint32_t)(s[2] & 0x3Fu) << 6) | (uint32_t)(s[3] & 0x3Fu);
        *cursor += 4;
        return (cp >= 0x10000u && cp <= 0x10FFFFu) ? cp : 0xFFFDu;
    }
    *cursor += 1;
    return 0xFFFDu;
}

static const glyph_info_t *find_glyph(const eng_font_t *f, uint32_t cp) {
    for (size_t i = 0; i < f->glyph_count; i++) {
        if (f->glyphs[i].codepoint == cp) return &f->glyphs[i];
    }
    for (size_t i = 0; i < f->glyph_count; i++) {
        if (f->glyphs[i].codepoint == '?') return &f->glyphs[i];
    }
    return f->glyph_count > 0 ? &f->glyphs[0] : NULL;
}

eng_font_t *eng_font_create_builtin(eng_asset_cache_t *assets) {
    if (!assets) return NULL;
    eng_font_t *f = (eng_font_t *)calloc(1, sizeof(eng_font_t));
    if (!f) return NULL;

    /* Procedural crisp 128x64 monochrome glyph sheet covering printable ASCII 32..126 */
    const int aw = 128, ah = 64;
    uint8_t rgba[128 * 64 * 4];
    memset(rgba, 0, sizeof(rgba));
    f->line_height = 10.0f;

    for (uint32_t cp = 32; cp <= 126; cp++) {
        int idx = (int)(cp - 32);
        int gx = (idx % 16) * 8;
        int gy = (idx / 16) * 10;
        for (int y = 1; y < 8; y++) {
            for (int x = 1; x < 6; x++) {
                bool on = false;
                if (cp != ' ') {
                    /* Deterministic distinct pixel glyph pattern + border stem for fallback readability */
                    uint32_t h = cp * 2654435761u ^ (uint32_t)(x * 37 + y * 97);
                    on = (x == 1 || y == 1 || y == 7 || ((h >> 12) & 1u) != 0);
                }
                if (on) {
                    int p = ((gy + y) * aw + (gx + x)) * 4;
                    rgba[p + 0] = 255; rgba[p + 1] = 255; rgba[p + 2] = 255; rgba[p + 3] = 255;
                }
            }
        }
        glyph_info_t *g = &f->glyphs[f->glyph_count++];
        g->codepoint = cp;
        g->u0 = (float)gx / (float)aw;
        g->v0 = (float)gy / (float)ah;
        g->u1 = (float)(gx + 7) / (float)aw;
        g->v1 = (float)(gy + 9) / (float)ah;
        g->xoff = 0.0f;
        g->yoff = 0.0f;
        g->w = 7.0f;
        g->h = 9.0f;
        g->xadvance = 7.0f;
        g->valid = true;
    }

    f->tex_id = eng_asset_create_texture_rgba(assets, "__builtin_font", aw, ah, rgba, true);
    return f;
}

eng_font_t *eng_font_load_ttf(eng_asset_cache_t *assets, const eng_vfs_t *vfs,
                              const char *vpath, float pixel_height) {
    if (!assets || !vfs || !vpath || pixel_height < 6.0f) return NULL;
    size_t sz = 0;
    uint8_t *ttf = (uint8_t *)eng_vfs_read_all(vfs, vpath, &sz);
    if (!ttf) return NULL;

    stbtt_fontinfo info;
    if (!stbtt_InitFont(&info, ttf, stbtt_GetFontOffsetForIndex(ttf, 0))) {
        free(ttf);
        return NULL;
    }

    eng_font_t *f = (eng_font_t *)calloc(1, sizeof(eng_font_t));
    uint8_t *rgba = (uint8_t *)calloc((size_t)(ENG_FONT_ATLAS_W * ENG_FONT_ATLAS_H * 4), 1);
    if (!f || !rgba) {
        free(f); free(rgba); free(ttf);
        return NULL;
    }

    float scale = stbtt_ScaleForPixelHeight(&info, pixel_height);
    int ascent = 0, descent = 0, line_gap = 0;
    stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);
    f->line_height = (float)(ascent - descent + line_gap) * scale;
    if (f->line_height < pixel_height) f->line_height = pixel_height;

    int pen_x = 2, pen_y = 2, row_h = 0;
    /* Bake ASCII 32..126 + Latin-1 160..255 via stbtt_GetCodepointSDF */
    for (int pass = 0; pass < 2; pass++) {
        uint32_t c_start = (pass == 0) ? 32u : 160u;
        uint32_t c_end   = (pass == 0) ? 126u : 255u;
        for (uint32_t cp = c_start; cp <= c_end && f->glyph_count < ENG_FONT_MAX_GLYPHS; cp++) {
            int adv = 0, lsb = 0;
            stbtt_GetCodepointHMetrics(&info, (int)cp, &adv, &lsb);

            int gw = 0, gh = 0, xoff = 0, yoff = 0;
            unsigned char *sdf = stbtt_GetCodepointSDF(&info, scale, (int)cp, 3, 128, 42.0f, &gw, &gh, &xoff, &yoff);
            if (pen_x + gw + 2 >= ENG_FONT_ATLAS_W) {
                pen_x = 2;
                pen_y += row_h + 2;
                row_h = 0;
            }
            if (pen_y + gh + 2 >= ENG_FONT_ATLAS_H) {
                if (sdf) stbtt_FreeSDF(sdf, NULL);
                break;
            }

            if (sdf && gw > 0 && gh > 0) {
                for (int y = 0; y < gh; y++) {
                    for (int x = 0; x < gw; x++) {
                        uint8_t s = sdf[y * gw + x];
                        /* Convert SDF edge around 128 into smooth alpha for universal forward/UI rendering */
                        float a = eng_clampf(((float)s - 108.0f) / 40.0f, 0.0f, 1.0f);
                        int dst = ((pen_y + y) * ENG_FONT_ATLAS_W + (pen_x + x)) * 4;
                        rgba[dst + 0] = 255;
                        rgba[dst + 1] = 255;
                        rgba[dst + 2] = 255;
                        rgba[dst + 3] = (uint8_t)(a * 255.0f);
                    }
                }
                if (gh > row_h) row_h = gh;
            }
            if (sdf) stbtt_FreeSDF(sdf, NULL);

            glyph_info_t *g = &f->glyphs[f->glyph_count++];
            g->codepoint = cp;
            g->u0 = (float)pen_x / (float)ENG_FONT_ATLAS_W;
            g->v0 = (float)pen_y / (float)ENG_FONT_ATLAS_H;
            g->u1 = (float)(pen_x + gw) / (float)ENG_FONT_ATLAS_W;
            g->v1 = (float)(pen_y + gh) / (float)ENG_FONT_ATLAS_H;
            g->xoff = (float)xoff;
            g->yoff = (float)yoff;
            g->w = (float)gw;
            g->h = (float)gh;
            g->xadvance = (float)adv * scale;
            g->valid = true;

            pen_x += gw + 2;
        }
    }

    f->tex_id = eng_asset_create_texture_rgba(assets, vpath, ENG_FONT_ATLAS_W, ENG_FONT_ATLAS_H, rgba, false);
    free(rgba);
    free(ttf);
    return f;
}

void eng_font_destroy(eng_font_t *font) {
    free(font);
}

uint32_t eng_font_texture_id(const eng_font_t *font) {
    return font ? font->tex_id : 0;
}

eng_vec2_t eng_text_measure(const eng_font_t *font, const char *utf8_text, float scale) {
    if (!font || !utf8_text || scale <= 0.0f) return (eng_vec2_t){0, 0};
    float max_w = 0.0f, cur_w = 0.0f;
    int lines = 1;
    const char *p = utf8_text;
    while (*p) {
        uint32_t cp = eng_utf8_next(&p);
        if (cp == '\n') {
            if (cur_w > max_w) max_w = cur_w;
            cur_w = 0.0f;
            lines++;
            continue;
        }
        const glyph_info_t *g = find_glyph(font, cp);
        if (g) cur_w += g->xadvance * scale;
    }
    if (cur_w > max_w) max_w = cur_w;
    return (eng_vec2_t){max_w, (float)lines * font->line_height * scale};
}

size_t eng_text_build_mesh(const eng_font_t *font, const char *utf8_text,
                           eng_vec3_t origin, float scale, eng_vec4_t color,
                           eng_mesh_data_t *out_mesh) {
    if (!out_mesh) return 0;
    eng_mesh_data_init(out_mesh);
    if (!font || !utf8_text || scale <= 0.0f) return 0;

    size_t max_chars = strlen(utf8_text);
    if (max_chars == 0) return 0;
    out_mesh->verts = (eng_vertex_t *)malloc(max_chars * 4u * sizeof(eng_vertex_t));
    out_mesh->indices = (uint32_t *)malloc(max_chars * 6u * sizeof(uint32_t));
    if (!out_mesh->verts || !out_mesh->indices) {
        eng_mesh_data_free(out_mesh);
        return 0;
    }
    out_mesh->vert_cap = max_chars * 4u;
    out_mesh->idx_cap = max_chars * 6u;

    float pen_x = origin.x;
    float pen_y = origin.y;
    size_t quads = 0;
    const char *p = utf8_text;
    while (*p) {
        uint32_t cp = eng_utf8_next(&p);
        if (cp == '\n') {
            pen_x = origin.x;
            pen_y -= font->line_height * scale;
            continue;
        }
        const glyph_info_t *g = find_glyph(font, cp);
        if (!g) continue;
        if (g->w > 0.0f && g->h > 0.0f && cp != ' ') {
            float x0 = pen_x + g->xoff * scale;
            float y1 = pen_y - g->yoff * scale;
            float x1 = x0 + g->w * scale;
            float y0 = y1 - g->h * scale;

            float pos[4][3] = {
                {x0, y0, origin.z}, {x1, y0, origin.z},
                {x1, y1, origin.z}, {x0, y1, origin.z}
            };
            float uv[4][2] = {
                {g->u0, g->v1}, {g->u1, g->v1},
                {g->u1, g->v0}, {g->u0, g->v0}
            };
            uint32_t base = (uint32_t)out_mesh->vert_count;
            for (int k = 0; k < 4; k++) {
                eng_vertex_t vt;
                memset(&vt, 0, sizeof(vt));
                vt.pos[0] = pos[k][0]; vt.pos[1] = pos[k][1]; vt.pos[2] = pos[k][2];
                vt.norm[2] = 1.0f;
                vt.uv[0] = uv[k][0]; vt.uv[1] = uv[k][1];
                vt.color[0] = color.x; vt.color[1] = color.y; vt.color[2] = color.z; vt.color[3] = color.w;
                vt.weights[0] = 1.0f;
                out_mesh->verts[out_mesh->vert_count++] = vt;
            }
            out_mesh->indices[out_mesh->idx_count++] = base + 0;
            out_mesh->indices[out_mesh->idx_count++] = base + 1;
            out_mesh->indices[out_mesh->idx_count++] = base + 2;
            out_mesh->indices[out_mesh->idx_count++] = base + 0;
            out_mesh->indices[out_mesh->idx_count++] = base + 2;
            out_mesh->indices[out_mesh->idx_count++] = base + 3;
            quads++;
        }
        pen_x += g->xadvance * scale;
    }
    return quads;
}
