#ifndef ENG_I18N_H
#define ENG_I18N_H

#include "eng_vfs.h"

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *name;
    const char *value;
} eng_i18n_param_t;

typedef struct eng_i18n_s eng_i18n_t;

eng_i18n_t *eng_i18n_create(eng_vfs_t *vfs, const char *fallback_lang);
void eng_i18n_destroy(eng_i18n_t *i18n);

/* Load locales/<lang>.json from VFS and set as active language. */
bool eng_i18n_set_lang(eng_i18n_t *i18n, const char *lang);
const char *eng_i18n_get_lang(const eng_i18n_t *i18n);

/* Lookup UTF-8 translation (falls back to fallback_lang, then returns key itself). */
const char *eng_i18n_get(const eng_i18n_t *i18n, const char *key);

/* Lookup and substitute {param} placeholders into out_buf (always NUL-terminated). */
size_t eng_i18n_format(const eng_i18n_t *i18n, const char *key,
                       const eng_i18n_param_t *params, size_t param_count,
                       char *out_buf, size_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* ENG_I18N_H */
