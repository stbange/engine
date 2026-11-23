#include "engine/eng_i18n.h"
#include "engine/eng_serde.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_I18N_MAX_ENTRIES 256

typedef struct {
    char key[64];
    char val[256];
} i18n_kv_t;

typedef struct {
    char lang[16];
    i18n_kv_t entries[ENG_I18N_MAX_ENTRIES];
    size_t count;
} i18n_table_t;

struct eng_i18n_s {
    eng_vfs_t *vfs;
    i18n_table_t fallback;
    i18n_table_t active;
};

static bool load_table(const eng_vfs_t *vfs, const char *lang, i18n_table_t *out) {
    if (!vfs || !lang || !out) return false;
    char vpath[64];
    snprintf(vpath, sizeof(vpath), "locales/%s.json", lang);
    char *raw = (char *)eng_vfs_read_all(vfs, vpath, NULL);
    if (!raw) return false;

    eng_arena_t arena;
    if (!eng_arena_init(&arena, 65536)) {
        free(raw);
        return false;
    }
    char err[128] = {0};
    eng_json_val_t *root = eng_json_parse(&arena, raw, err, sizeof(err));
    free(raw);
    if (!root || root->type != ENG_JSON_OBJ) {
        eng_arena_destroy(&arena);
        return false;
    }

    memset(out, 0, sizeof(*out));
    snprintf(out->lang, sizeof(out->lang), "%s", lang);
    for (size_t i = 0; i < root->u.obj.len && out->count < ENG_I18N_MAX_ENTRIES; i++) {
        const eng_json_kv_t *kv = &root->u.obj.pairs[i];
        if (kv->val && kv->val->type == ENG_JSON_STR) {
            snprintf(out->entries[out->count].key, sizeof(out->entries[0].key), "%s", kv->key);
            snprintf(out->entries[out->count].val, sizeof(out->entries[0].val), "%s", kv->val->u.sval);
            out->count++;
        }
    }
    eng_arena_destroy(&arena);
    return true;
}

static const char *find_in_table(const i18n_table_t *t, const char *key) {
    for (size_t i = 0; i < t->count; i++) {
        if (strcmp(t->entries[i].key, key) == 0) return t->entries[i].val;
    }
    return NULL;
}

eng_i18n_t *eng_i18n_create(eng_vfs_t *vfs, const char *fallback_lang) {
    eng_i18n_t *i18n = (eng_i18n_t *)calloc(1, sizeof(eng_i18n_t));
    if (!i18n) return NULL;
    i18n->vfs = vfs;
    const char *fb = (fallback_lang && fallback_lang[0]) ? fallback_lang : "en";
    snprintf(i18n->fallback.lang, sizeof(i18n->fallback.lang), "%s", fb);
    snprintf(i18n->active.lang, sizeof(i18n->active.lang), "%s", fb);
    if (vfs) {
        if (load_table(vfs, fb, &i18n->fallback)) {
            i18n->active = i18n->fallback;
        }
    }
    return i18n;
}

void eng_i18n_destroy(eng_i18n_t *i18n) {
    free(i18n);
}

bool eng_i18n_set_lang(eng_i18n_t *i18n, const char *lang) {
    if (!i18n || !lang || !lang[0]) return false;
    if (i18n->fallback.count == 0 && i18n->fallback.lang[0]) {
        load_table(i18n->vfs, i18n->fallback.lang, &i18n->fallback);
    }
    return load_table(i18n->vfs, lang, &i18n->active);
}

const char *eng_i18n_get_lang(const eng_i18n_t *i18n) {
    return i18n ? i18n->active.lang : "en";
}

const char *eng_i18n_get(const eng_i18n_t *i18n, const char *key) {
    if (!key) return "";
    if (!i18n) return key;
    const char *v = find_in_table(&i18n->active, key);
    if (!v) v = find_in_table(&i18n->fallback, key);
    return v ? v : key;
}

size_t eng_i18n_format(const eng_i18n_t *i18n, const char *key,
                       const eng_i18n_param_t *params, size_t param_count,
                       char *out_buf, size_t out_cap) {
    if (!out_buf || out_cap == 0) return 0;
    const char *tmpl = eng_i18n_get(i18n, key);
    size_t w = 0;

    for (const char *p = tmpl; *p && w + 1 < out_cap;) {
        if (*p == '{') {
            const char *end = strchr(p + 1, '}');
            if (end && (size_t)(end - (p + 1)) < 64u) {
                char pname[64];
                size_t nlen = (size_t)(end - (p + 1));
                memcpy(pname, p + 1, nlen);
                pname[nlen] = '\0';

                const char *rep = NULL;
                for (size_t k = 0; k < param_count && params; k++) {
                    if (params[k].name && strcmp(params[k].name, pname) == 0) {
                        rep = params[k].value ? params[k].value : "";
                        break;
                    }
                }
                if (rep) {
                    size_t rlen = strlen(rep);
                    size_t copy = (w + rlen < out_cap) ? rlen : (out_cap - 1u - w);
                    memcpy(out_buf + w, rep, copy);
                    w += copy;
                    p = end + 1;
                    continue;
                }
            }
        }
        out_buf[w++] = *p++;
    }
    out_buf[w] = '\0';
    return w;
}
