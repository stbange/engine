#ifndef ENG_LOG_H
#define ENG_LOG_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_LOG_TRACE = 0,
    ENG_LOG_DEBUG = 1,
    ENG_LOG_INFO  = 2,
    ENG_LOG_WARN  = 3,
    ENG_LOG_ERROR = 4
} eng_log_level_t;

typedef struct {
    eng_log_level_t level;
    char category[32];
    char message[256];
    int repeat_count;
} eng_log_entry_t;

typedef void (*eng_log_sink_fn)(const char *formatted_line, void *userdata);
typedef bool (*eng_cmd_fn)(int argc, const char *const *argv, char *out_reply, size_t reply_cap);

void eng_log_init(void);
void eng_log_shutdown(void);
void eng_log_set_min_level(eng_log_level_t level);
void eng_log_set_json_mode(bool enabled);
void eng_log_set_sink(eng_log_sink_fn sink, void *userdata);
void eng_log_write(eng_log_level_t level, const char *category, const char *fmt, ...);
void eng_log_flush(void);

size_t eng_log_recent_count(void);
const eng_log_entry_t *eng_log_recent_get(size_t index_oldest_first);

#define ENG_LOGI(cat, ...) eng_log_write(ENG_LOG_INFO, (cat), __VA_ARGS__)
#define ENG_LOGW(cat, ...) eng_log_write(ENG_LOG_WARN, (cat), __VA_ARGS__)
#define ENG_LOGE(cat, ...) eng_log_write(ENG_LOG_ERROR, (cat), __VA_ARGS__)

/* Console Variables (CVars) & Console Commands */
bool eng_cvar_register_float(const char *name, float default_val);
bool eng_cvar_register_int(const char *name, int default_val);
bool eng_cvar_register_bool(const char *name, bool default_val);
bool eng_cvar_set_string(const char *name, const char *value_str);
float eng_cvar_get_float(const char *name, float fallback);
int eng_cvar_get_int(const char *name, int fallback);
bool eng_cvar_get_bool(const char *name, bool fallback);

bool eng_cmd_register(const char *name, eng_cmd_fn fn);
bool eng_cmd_exec(const char *command_line, char *out_reply, size_t reply_cap);

#ifdef __cplusplus
}
#endif

#endif /* ENG_LOG_H */
