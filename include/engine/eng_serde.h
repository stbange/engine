#ifndef ENG_SERDE_H
#define ENG_SERDE_H

#include "eng_math.h"
#include "eng_mem.h"
#include "eng_vfs.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------------------
 * Arena-allocated JSON DOM + Strict Key Schema Validator
 * -------------------------------------------------------------------------- */
typedef enum {
    ENG_JSON_NULL = 0,
    ENG_JSON_BOOL,
    ENG_JSON_NUM,
    ENG_JSON_STR,
    ENG_JSON_ARR,
    ENG_JSON_OBJ
} eng_json_type_t;

typedef struct eng_json_val_s eng_json_val_t;

typedef struct {
    const char *key;
    eng_json_val_t *val;
    int line;
} eng_json_kv_t;

struct eng_json_val_s {
    eng_json_type_t type;
    int line;
    union {
        bool bval;
        double nval;
        const char *sval;
        struct {
            eng_json_val_t **items;
            size_t len;
        } arr;
        struct {
            eng_json_kv_t *pairs;
            size_t len;
        } obj;
    } u;
};

eng_json_val_t *eng_json_parse(eng_arena_t *arena, const char *src, char *err_buf, size_t err_cap);

const eng_json_val_t *eng_json_get(const eng_json_val_t *obj, const char *key);
const char *eng_json_get_str(const eng_json_val_t *obj, const char *key, const char *fallback);
double eng_json_get_num(const eng_json_val_t *obj, const char *key, double fallback);
bool eng_json_get_bool(const eng_json_val_t *obj, const char *key, bool fallback);
eng_vec3_t eng_json_get_v3(const eng_json_val_t *obj, const char *key, eng_vec3_t fallback);

/* Reject unknown keys on a JSON object, suggesting closest valid key via Levenshtein distance. */
bool eng_json_validate_keys(const eng_json_val_t *obj, const char *const *valid_keys,
                            size_t valid_count, char *err_buf, size_t err_cap);

/* --------------------------------------------------------------------------
 * Versioned ENGB Binary Serializer & Save-Slot Helpers
 * -------------------------------------------------------------------------- */
#define ENG_BIN_MAGIC 0x42474E45u /* "ENGB" little-endian */

typedef struct {
    uint8_t *buf;
    size_t size;
    size_t cap;
    bool failed;
} eng_bin_writer_t;

typedef struct {
    const uint8_t *buf;
    size_t size;
    size_t pos;
    uint32_t version;
} eng_bin_reader_t;

bool eng_bin_writer_init(eng_bin_writer_t *w, uint32_t schema_version, size_t initial_cap);
void eng_bin_writer_destroy(eng_bin_writer_t *w);
bool eng_bin_write_u32(eng_bin_writer_t *w, uint32_t v);
bool eng_bin_write_f32(eng_bin_writer_t *w, float v);
bool eng_bin_write_str(eng_bin_writer_t *w, const char *s);
bool eng_bin_write_bytes(eng_bin_writer_t *w, const void *data, size_t len);

bool eng_bin_reader_init(eng_bin_reader_t *r, const void *data, size_t size, uint32_t expected_version);
bool eng_bin_read_u32(eng_bin_reader_t *r, uint32_t *out);
bool eng_bin_read_f32(eng_bin_reader_t *r, float *out);
bool eng_bin_read_str(eng_bin_reader_t *r, char *out_buf, size_t out_cap);
bool eng_bin_read_bytes(eng_bin_reader_t *r, void *out_buf, size_t len);

bool eng_save_write(eng_vfs_t *vfs, const char *slot_name, uint32_t schema_version, const void *payload, size_t len);
void *eng_save_read(const eng_vfs_t *vfs, const char *slot_name, uint32_t expected_version, size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* ENG_SERDE_H */
