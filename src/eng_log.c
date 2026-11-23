#include "engine/eng_log.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_LOG_RING_CAP 64
#define ENG_CVAR_CAP 64
#define ENG_CMD_CAP 64

typedef enum { CVAR_FLOAT, CVAR_INT, CVAR_BOOL } cvar_type_t;

typedef struct {
    char name[48];
    cvar_type_t type;
    float fval;
    int ival;
    bool bval;
} eng_cvar_t;

typedef struct {
    char name[48];
    eng_cmd_fn fn;
} eng_cmd_entry_t;

static struct {
    eng_log_level_t min_level;
    bool json_mode;
    eng_log_sink_fn sink;
    void *sink_ud;
    eng_log_entry_t ring[ENG_LOG_RING_CAP];
    size_t ring_head;
    size_t ring_count;
    bool has_pending_dup;
    eng_log_entry_t last_entry;
    eng_cvar_t cvars[ENG_CVAR_CAP];
    size_t cvar_count;
    eng_cmd_entry_t cmds[ENG_CMD_CAP];
    size_t cmd_count;
} g_log;

static const char *level_name(eng_log_level_t lvl) {
    switch (lvl) {
        case ENG_LOG_TRACE: return "TRACE";
        case ENG_LOG_DEBUG: return "DEBUG";
        case ENG_LOG_INFO:  return "INFO";
        case ENG_LOG_WARN:  return "WARN";
        default:            return "ERROR";
    }
}

static void emit_line(const char *line) {
    if (g_log.sink) {
        g_log.sink(line, g_log.sink_ud);
    } else {
        fprintf(stderr, "%s\n", line);
    }
}

static void format_and_emit(eng_log_level_t lvl, const char *cat, const char *msg, int repeats) {
    char out[512];
    if (g_log.json_mode) {
        char escaped[300];
        size_t j = 0;
        for (size_t i = 0; msg[i] && j + 2 < sizeof(escaped); i++) {
            char c = msg[i];
            if (c == '"' || c == '\\') escaped[j++] = '\\';
            escaped[j++] = (c == '\n' || c == '\r') ? ' ' : c;
        }
        escaped[j] = '\0';
        snprintf(out, sizeof(out), "{\"level\":\"%s\",\"cat\":\"%s\",\"msg\":\"%s\",\"repeats\":%d}",
                 level_name(lvl), cat, escaped, repeats);
    } else if (repeats > 1) {
        snprintf(out, sizeof(out), "[%s][%s] %s [repeated %dx]", level_name(lvl), cat, msg, repeats);
    } else {
        snprintf(out, sizeof(out), "[%s][%s] %s", level_name(lvl), cat, msg);
    }
    emit_line(out);
}

void eng_log_init(void) {
    memset(&g_log, 0, sizeof(g_log));
    g_log.min_level = ENG_LOG_INFO;
}

void eng_log_flush(void) {
    if (g_log.has_pending_dup && g_log.last_entry.repeat_count > 1) {
        format_and_emit(g_log.last_entry.level, g_log.last_entry.category,
                        g_log.last_entry.message, g_log.last_entry.repeat_count);
    }
    g_log.has_pending_dup = false;
    g_log.last_entry.repeat_count = 0;
}

void eng_log_shutdown(void) {
    eng_log_flush();
    memset(&g_log, 0, sizeof(g_log));
}

void eng_log_set_min_level(eng_log_level_t level) {
    g_log.min_level = level;
}

void eng_log_set_json_mode(bool enabled) {
    g_log.json_mode = enabled;
}

void eng_log_set_sink(eng_log_sink_fn sink, void *userdata) {
    g_log.sink = sink;
    g_log.sink_ud = userdata;
}

void eng_log_write(eng_log_level_t level, const char *category, const char *fmt, ...) {
    if (level < g_log.min_level || !fmt) return;
    const char *cat = category ? category : "core";
    char msg[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    if (g_log.has_pending_dup && g_log.last_entry.level == level &&
        strcmp(g_log.last_entry.category, cat) == 0 &&
        strcmp(g_log.last_entry.message, msg) == 0) {
        g_log.last_entry.repeat_count++;
        size_t last_idx = (g_log.ring_head + ENG_LOG_RING_CAP - 1) % ENG_LOG_RING_CAP;
        g_log.ring[last_idx].repeat_count = g_log.last_entry.repeat_count;
        return;
    }

    eng_log_flush();

    eng_log_entry_t entry;
    entry.level = level;
    snprintf(entry.category, sizeof(entry.category), "%s", cat);
    snprintf(entry.message, sizeof(entry.message), "%s", msg);
    entry.repeat_count = 1;

    g_log.last_entry = entry;
    g_log.has_pending_dup = true;

    g_log.ring[g_log.ring_head] = entry;
    g_log.ring_head = (g_log.ring_head + 1) % ENG_LOG_RING_CAP;
    if (g_log.ring_count < ENG_LOG_RING_CAP) {
        g_log.ring_count++;
    }

    format_and_emit(level, entry.category, entry.message, 1);
}

size_t eng_log_recent_count(void) {
    return g_log.ring_count;
}

const eng_log_entry_t *eng_log_recent_get(size_t index_oldest_first) {
    if (index_oldest_first >= g_log.ring_count) return NULL;
    size_t oldest = (g_log.ring_count == ENG_LOG_RING_CAP) ? g_log.ring_head : 0;
    size_t idx = (oldest + index_oldest_first) % ENG_LOG_RING_CAP;
    return &g_log.ring[idx];
}

static eng_cvar_t *find_cvar(const char *name) {
    if (!name) return NULL;
    for (size_t i = 0; i < g_log.cvar_count; i++) {
        if (strcmp(g_log.cvars[i].name, name) == 0) return &g_log.cvars[i];
    }
    return NULL;
}

static eng_cvar_t *alloc_cvar(const char *name, cvar_type_t type) {
    if (!name || name[0] == '\0' || find_cvar(name) || g_log.cvar_count >= ENG_CVAR_CAP) {
        return NULL;
    }
    eng_cvar_t *cv = &g_log.cvars[g_log.cvar_count++];
    memset(cv, 0, sizeof(*cv));
    snprintf(cv->name, sizeof(cv->name), "%s", name);
    cv->type = type;
    return cv;
}

bool eng_cvar_register_float(const char *name, float default_val) {
    eng_cvar_t *cv = alloc_cvar(name, CVAR_FLOAT);
    if (!cv) return false;
    cv->fval = default_val;
    return true;
}

bool eng_cvar_register_int(const char *name, int default_val) {
    eng_cvar_t *cv = alloc_cvar(name, CVAR_INT);
    if (!cv) return false;
    cv->ival = default_val;
    return true;
}

bool eng_cvar_register_bool(const char *name, bool default_val) {
    eng_cvar_t *cv = alloc_cvar(name, CVAR_BOOL);
    if (!cv) return false;
    cv->bval = default_val;
    return true;
}

bool eng_cvar_set_string(const char *name, const char *value_str) {
    eng_cvar_t *cv = find_cvar(name);
    if (!cv || !value_str) return false;
    char *end = NULL;
    if (cv->type == CVAR_FLOAT) {
        float v = strtof(value_str, &end);
        if (end == value_str || *end != '\0') return false;
        cv->fval = v;
    } else if (cv->type == CVAR_INT) {
        long v = strtol(value_str, &end, 10);
        if (end == value_str || *end != '\0') return false;
        cv->ival = (int)v;
    } else {
        if (strcmp(value_str, "1") == 0 || strcmp(value_str, "true") == 0) cv->bval = true;
        else if (strcmp(value_str, "0") == 0 || strcmp(value_str, "false") == 0) cv->bval = false;
        else return false;
    }
    return true;
}

float eng_cvar_get_float(const char *name, float fallback) {
    eng_cvar_t *cv = find_cvar(name);
    return (cv && cv->type == CVAR_FLOAT) ? cv->fval : fallback;
}

int eng_cvar_get_int(const char *name, int fallback) {
    eng_cvar_t *cv = find_cvar(name);
    return (cv && cv->type == CVAR_INT) ? cv->ival : fallback;
}

bool eng_cvar_get_bool(const char *name, bool fallback) {
    eng_cvar_t *cv = find_cvar(name);
    return (cv && cv->type == CVAR_BOOL) ? cv->bval : fallback;
}

bool eng_cmd_register(const char *name, eng_cmd_fn fn) {
    if (!name || name[0] == '\0' || !fn || g_log.cmd_count >= ENG_CMD_CAP) return false;
    for (size_t i = 0; i < g_log.cmd_count; i++) {
        if (strcmp(g_log.cmds[i].name, name) == 0) return false;
    }
    snprintf(g_log.cmds[g_log.cmd_count].name, sizeof(g_log.cmds[0].name), "%s", name);
    g_log.cmds[g_log.cmd_count].fn = fn;
    g_log.cmd_count++;
    return true;
}

bool eng_cmd_exec(const char *command_line, char *out_reply, size_t reply_cap) {
    if (out_reply && reply_cap > 0) out_reply[0] = '\0';
    if (!command_line) return false;
    char buf[256];
    snprintf(buf, sizeof(buf), "%s", command_line);
    const char *argv[16];
    int argc = 0;
    char *p = buf;
    while (*p && argc < 16) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        argv[argc++] = p;
        while (*p && !isspace((unsigned char)*p)) p++;
        if (*p) *p++ = '\0';
    }
    if (argc == 0) return false;

    if (strcmp(argv[0], "set") == 0 && argc == 3) {
        bool ok = eng_cvar_set_string(argv[1], argv[2]);
        if (out_reply && reply_cap > 0) {
            snprintf(out_reply, reply_cap, ok ? "ok" : "invalid cvar or value");
        }
        return ok;
    }

    for (size_t i = 0; i < g_log.cmd_count; i++) {
        if (strcmp(g_log.cmds[i].name, argv[0]) == 0) {
            return g_log.cmds[i].fn(argc, argv, out_reply, reply_cap);
        }
    }
    if (out_reply && reply_cap > 0) {
        snprintf(out_reply, reply_cap, "unknown command: %s", argv[0]);
    }
    return false;
}
