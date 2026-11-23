#include "engine/eng_serde.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    eng_arena_t *arena;
    const char *p;
    int line;
    char *err;
    size_t err_cap;
} json_parser_t;

static void json_set_err(json_parser_t *jp, const char *msg) {
    if (jp->err && jp->err_cap > 0 && jp->err[0] == '\0') {
        snprintf(jp->err, jp->err_cap, "line %d: %s", jp->line, msg);
    }
}

static void skip_ws(json_parser_t *jp) {
    while (*jp->p) {
        if (*jp->p == '\n') {
            jp->line++;
            jp->p++;
        } else if (isspace((unsigned char)*jp->p)) {
            jp->p++;
        } else {
            break;
        }
    }
}

static const char *parse_raw_str(json_parser_t *jp) {
    if (*jp->p != '"') {
        json_set_err(jp, "expected '\"'");
        return NULL;
    }
    jp->p++;
    const char *start = jp->p;
    size_t max_len = 0;
    while (jp->p[max_len] && jp->p[max_len] != '"') {
        if (jp->p[max_len] == '\n') jp->line++;
        if (jp->p[max_len] == '\\' && jp->p[max_len + 1]) max_len += 2;
        else max_len++;
    }
    if (jp->p[max_len] != '"') {
        json_set_err(jp, "unterminated string");
        return NULL;
    }
    char *out = (char *)eng_arena_alloc_aligned(jp->arena, max_len + 1, 1);
    if (!out) {
        json_set_err(jp, "arena out of memory");
        return NULL;
    }
    size_t w = 0;
    const char *c = start;
    const char *end = start + max_len;
    while (c < end) {
        if (*c == '\\') {
            c++;
            switch (*c) {
                case '"':  out[w++] = '"'; break;
                case '\\': out[w++] = '\\'; break;
                case '/':  out[w++] = '/'; break;
                case 'n':  out[w++] = '\n'; break;
                case 'r':  out[w++] = '\r'; break;
                case 't':  out[w++] = '\t'; break;
                default:   out[w++] = *c; break;
            }
            c++;
        } else {
            out[w++] = *c++;
        }
    }
    out[w] = '\0';
    jp->p = end + 1;
    return out;
}

static eng_json_val_t *parse_value(json_parser_t *jp);

static eng_json_val_t *alloc_val(json_parser_t *jp, eng_json_type_t type) {
    eng_json_val_t *v = (eng_json_val_t *)eng_arena_alloc(jp->arena, sizeof(eng_json_val_t));
    if (!v) {
        json_set_err(jp, "arena out of memory");
        return NULL;
    }
    v->type = type;
    v->line = jp->line;
    return v;
}

static eng_json_val_t *parse_array(json_parser_t *jp) {
    eng_json_val_t *v = alloc_val(jp, ENG_JSON_ARR);
    if (!v) return NULL;
    jp->p++; /* '[' */
    skip_ws(jp);
    if (*jp->p == ']') {
        jp->p++;
        return v;
    }
    eng_json_val_t *temp[512];
    size_t count = 0;
    for (;;) {
        skip_ws(jp);
        if (count >= 512) { json_set_err(jp, "array exceeds 512 items"); return NULL; }
        eng_json_val_t *elem = parse_value(jp);
        if (!elem) return NULL;
        temp[count++] = elem;
        skip_ws(jp);
        if (*jp->p == ',') {
            jp->p++;
        } else if (*jp->p == ']') {
            jp->p++;
            break;
        } else {
            json_set_err(jp, "expected ',' or ']' in array");
            return NULL;
        }
    }
    v->u.arr.items = (eng_json_val_t **)eng_arena_alloc(jp->arena, count * sizeof(eng_json_val_t *));
    if (!v->u.arr.items) { json_set_err(jp, "arena out of memory"); return NULL; }
    memcpy(v->u.arr.items, temp, count * sizeof(eng_json_val_t *));
    v->u.arr.len = count;
    return v;
}

static eng_json_val_t *parse_object(json_parser_t *jp) {
    eng_json_val_t *v = alloc_val(jp, ENG_JSON_OBJ);
    if (!v) return NULL;
    jp->p++; /* '{' */
    skip_ws(jp);
    if (*jp->p == '}') {
        jp->p++;
        return v;
    }
    eng_json_kv_t temp[256];
    size_t count = 0;
    for (;;) {
        skip_ws(jp);
        if (count >= 256) { json_set_err(jp, "object exceeds 256 keys"); return NULL; }
        int key_line = jp->line;
        const char *k = parse_raw_str(jp);
        if (!k) return NULL;
        skip_ws(jp);
        if (*jp->p != ':') {
            json_set_err(jp, "expected ':' after object key");
            return NULL;
        }
        jp->p++;
        skip_ws(jp);
        eng_json_val_t *val = parse_value(jp);
        if (!val) return NULL;
        temp[count].key = k;
        temp[count].val = val;
        temp[count].line = key_line;
        count++;
        skip_ws(jp);
        if (*jp->p == ',') {
            jp->p++;
        } else if (*jp->p == '}') {
            jp->p++;
            break;
        } else {
            json_set_err(jp, "expected ',' or '}' in object");
            return NULL;
        }
    }
    v->u.obj.pairs = (eng_json_kv_t *)eng_arena_alloc(jp->arena, count * sizeof(eng_json_kv_t));
    if (!v->u.obj.pairs) { json_set_err(jp, "arena out of memory"); return NULL; }
    memcpy(v->u.obj.pairs, temp, count * sizeof(eng_json_kv_t));
    v->u.obj.len = count;
    return v;
}

static eng_json_val_t *parse_value(json_parser_t *jp) {
    skip_ws(jp);
    char c = *jp->p;
    if (c == '{') return parse_object(jp);
    if (c == '[') return parse_array(jp);
    if (c == '"') {
        eng_json_val_t *v = alloc_val(jp, ENG_JSON_STR);
        if (!v) return NULL;
        v->u.sval = parse_raw_str(jp);
        return v->u.sval ? v : NULL;
    }
    if (strncmp(jp->p, "true", 4) == 0 && !isalnum((unsigned char)jp->p[4])) {
        eng_json_val_t *v = alloc_val(jp, ENG_JSON_BOOL);
        if (v) v->u.bval = true;
        jp->p += 4;
        return v;
    }
    if (strncmp(jp->p, "false", 5) == 0 && !isalnum((unsigned char)jp->p[5])) {
        eng_json_val_t *v = alloc_val(jp, ENG_JSON_BOOL);
        if (v) v->u.bval = false;
        jp->p += 5;
        return v;
    }
    if (strncmp(jp->p, "null", 4) == 0 && !isalnum((unsigned char)jp->p[4])) {
        eng_json_val_t *v = alloc_val(jp, ENG_JSON_NULL);
        jp->p += 4;
        return v;
    }
    if (c == '-' || isdigit((unsigned char)c)) {
        char *end = NULL;
        double num = strtod(jp->p, &end);
        if (end == jp->p) {
            json_set_err(jp, "invalid number");
            return NULL;
        }
        eng_json_val_t *v = alloc_val(jp, ENG_JSON_NUM);
        if (v) v->u.nval = num;
        jp->p = end;
        return v;
    }
    json_set_err(jp, "unexpected token");
    return NULL;
}

eng_json_val_t *eng_json_parse(eng_arena_t *arena, const char *src, char *err_buf, size_t err_cap) {
    if (err_buf && err_cap > 0) err_buf[0] = '\0';
    if (!arena || !src) {
        if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "null arena or json source");
        return NULL;
    }
    json_parser_t jp = {arena, src, 1, err_buf, err_cap};
    eng_json_val_t *root = parse_value(&jp);
    if (!root) return NULL;
    skip_ws(&jp);
    if (*jp.p != '\0') {
        json_set_err(&jp, "trailing characters after root value");
        return NULL;
    }
    return root;
}

const eng_json_val_t *eng_json_get(const eng_json_val_t *obj, const char *key) {
    if (!obj || obj->type != ENG_JSON_OBJ || !key) return NULL;
    for (size_t i = 0; i < obj->u.obj.len; i++) {
        if (strcmp(obj->u.obj.pairs[i].key, key) == 0) {
            return obj->u.obj.pairs[i].val;
        }
    }
    return NULL;
}

const char *eng_json_get_str(const eng_json_val_t *obj, const char *key, const char *fallback) {
    const eng_json_val_t *v = eng_json_get(obj, key);
    return (v && v->type == ENG_JSON_STR) ? v->u.sval : fallback;
}

double eng_json_get_num(const eng_json_val_t *obj, const char *key, double fallback) {
    const eng_json_val_t *v = eng_json_get(obj, key);
    return (v && v->type == ENG_JSON_NUM) ? v->u.nval : fallback;
}

bool eng_json_get_bool(const eng_json_val_t *obj, const char *key, bool fallback) {
    const eng_json_val_t *v = eng_json_get(obj, key);
    return (v && v->type == ENG_JSON_BOOL) ? v->u.bval : fallback;
}

eng_vec3_t eng_json_get_v3(const eng_json_val_t *obj, const char *key, eng_vec3_t fallback) {
    const eng_json_val_t *v = eng_json_get(obj, key);
    if (!v || v->type != ENG_JSON_ARR || v->u.arr.len != 3) return fallback;
    for (int i = 0; i < 3; i++) {
        if (v->u.arr.items[i]->type != ENG_JSON_NUM) return fallback;
    }
    return eng_v3((float)v->u.arr.items[0]->u.nval,
                  (float)v->u.arr.items[1]->u.nval,
                  (float)v->u.arr.items[2]->u.nval);
}

bool eng_json_validate_keys(const eng_json_val_t *obj, const char *const *valid_keys,
                            size_t valid_count, char *err_buf, size_t err_cap) {
    if (!obj || obj->type != ENG_JSON_OBJ) {
        if (err_buf && err_cap > 0) snprintf(err_buf, err_cap, "expected JSON object");
        return false;
    }
    for (size_t i = 0; i < obj->u.obj.len; i++) {
        const char *k = obj->u.obj.pairs[i].key;
        bool found = false;
        for (size_t j = 0; j < valid_count; j++) {
            if (strcmp(k, valid_keys[j]) == 0) {
                found = true;
                break;
            }
        }
        if (!found) {
            const char *hint = eng_str_suggest(k, valid_keys, valid_count, 3);
            if (err_buf && err_cap > 0) {
                if (hint) {
                    snprintf(err_buf, err_cap, "line %d: unknown key '%s' — did you mean '%s'?",
                             obj->u.obj.pairs[i].line, k, hint);
                } else {
                    snprintf(err_buf, err_cap, "line %d: unknown key '%s'",
                             obj->u.obj.pairs[i].line, k);
                }
            }
            return false;
        }
    }
    return true;
}

static bool bin_reserve(eng_bin_writer_t *w, size_t add) {
    if (w->failed) return false;
    if (w->size + add <= w->cap) return true;
    size_t new_cap = w->cap ? w->cap * 2 : 64;
    while (new_cap < w->size + add) new_cap *= 2;
    uint8_t *nb = (uint8_t *)realloc(w->buf, new_cap);
    if (!nb) {
        w->failed = true;
        return false;
    }
    w->buf = nb;
    w->cap = new_cap;
    return true;
}

bool eng_bin_writer_init(eng_bin_writer_t *w, uint32_t schema_version, size_t initial_cap) {
    if (!w) return false;
    memset(w, 0, sizeof(*w));
    if (!bin_reserve(w, initial_cap ? initial_cap : 64)) return false;
    return eng_bin_write_u32(w, ENG_BIN_MAGIC) && eng_bin_write_u32(w, schema_version);
}

void eng_bin_writer_destroy(eng_bin_writer_t *w) {
    if (!w) return;
    free(w->buf);
    memset(w, 0, sizeof(*w));
}

bool eng_bin_write_u32(eng_bin_writer_t *w, uint32_t v) {
    if (!w || !bin_reserve(w, 4)) return false;
    w->buf[w->size++] = (uint8_t)(v & 0xFFu);
    w->buf[w->size++] = (uint8_t)((v >> 8) & 0xFFu);
    w->buf[w->size++] = (uint8_t)((v >> 16) & 0xFFu);
    w->buf[w->size++] = (uint8_t)((v >> 24) & 0xFFu);
    return true;
}

bool eng_bin_write_f32(eng_bin_writer_t *w, float v) {
    uint32_t bits = 0;
    memcpy(&bits, &v, sizeof(bits));
    return eng_bin_write_u32(w, bits);
}

bool eng_bin_write_bytes(eng_bin_writer_t *w, const void *data, size_t len) {
    if (!w || (!data && len > 0) || !bin_reserve(w, len)) return false;
    if (len > 0) {
        memcpy(w->buf + w->size, data, len);
        w->size += len;
    }
    return true;
}

bool eng_bin_write_str(eng_bin_writer_t *w, const char *s) {
    uint32_t len = s ? (uint32_t)strlen(s) : 0u;
    return eng_bin_write_u32(w, len) && eng_bin_write_bytes(w, s, len);
}

bool eng_bin_reader_init(eng_bin_reader_t *r, const void *data, size_t size, uint32_t expected_version) {
    if (!r || !data || size < 8) return false;
    r->buf = (const uint8_t *)data;
    r->size = size;
    r->pos = 0;
    uint32_t magic = 0;
    if (!eng_bin_read_u32(r, &magic) || magic != ENG_BIN_MAGIC) return false;
    if (!eng_bin_read_u32(r, &r->version) || r->version != expected_version) return false;
    return true;
}

bool eng_bin_read_u32(eng_bin_reader_t *r, uint32_t *out) {
    if (!r || !out || r->pos + 4 > r->size) return false;
    *out = (uint32_t)r->buf[r->pos] |
           ((uint32_t)r->buf[r->pos + 1] << 8) |
           ((uint32_t)r->buf[r->pos + 2] << 16) |
           ((uint32_t)r->buf[r->pos + 3] << 24);
    r->pos += 4;
    return true;
}

bool eng_bin_read_f32(eng_bin_reader_t *r, float *out) {
    uint32_t bits = 0;
    if (!out || !eng_bin_read_u32(r, &bits)) return false;
    memcpy(out, &bits, sizeof(*out));
    return true;
}

bool eng_bin_read_bytes(eng_bin_reader_t *r, void *out_buf, size_t len) {
    if (!r || (!out_buf && len > 0) || r->pos + len > r->size) return false;
    if (len > 0) {
        memcpy(out_buf, r->buf + r->pos, len);
        r->pos += len;
    }
    return true;
}

bool eng_bin_read_str(eng_bin_reader_t *r, char *out_buf, size_t out_cap) {
    uint32_t len = 0;
    if (!out_buf || out_cap == 0 || !eng_bin_read_u32(r, &len)) return false;
    if ((size_t)len + 1 > out_cap || !eng_bin_read_bytes(r, out_buf, len)) return false;
    out_buf[len] = '\0';
    return true;
}

bool eng_save_write(eng_vfs_t *vfs, const char *slot_name, uint32_t schema_version, const void *payload, size_t len) {
    if (!vfs || !slot_name || slot_name[0] == '\0') return false;
    eng_bin_writer_t w;
    if (!eng_bin_writer_init(&w, schema_version, len + 16)) return false;
    bool ok = eng_bin_write_u32(&w, (uint32_t)len) && eng_bin_write_bytes(&w, payload, len);
    if (ok) {
        char path[256];
        snprintf(path, sizeof(path), "saves/%s.engb", slot_name);
        ok = eng_vfs_write_all(vfs, path, w.buf, w.size);
#ifdef __EMSCRIPTEN__
        if (ok) {
            emscripten_run_script("if (typeof FS !== 'undefined' && FS.syncfs) { FS.syncfs(false, function(){}); }");
        }
#endif
    }
    eng_bin_writer_destroy(&w);
    return ok;
}

void *eng_save_read(const eng_vfs_t *vfs, const char *slot_name, uint32_t expected_version, size_t *out_len) {
    if (out_len) *out_len = 0;
    if (!vfs || !slot_name || slot_name[0] == '\0') return NULL;
    char path[256];
    snprintf(path, sizeof(path), "saves/%s.engb", slot_name);
    size_t raw_size = 0;
    void *raw = eng_vfs_read_all(vfs, path, &raw_size);
    if (!raw) return NULL;
    eng_bin_reader_t r;
    uint32_t payload_len = 0;
    if (!eng_bin_reader_init(&r, raw, raw_size, expected_version) ||
        !eng_bin_read_u32(&r, &payload_len) || r.pos + payload_len != r.size) {
        free(raw);
        return NULL;
    }
    uint8_t *out = (uint8_t *)malloc((size_t)payload_len + 1u);
    if (out) {
        eng_bin_read_bytes(&r, out, payload_len);
        out[payload_len] = '\0';
        if (out_len) *out_len = payload_len;
    }
    free(raw);
    return out;
}
