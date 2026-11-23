#include "engine/eng_version.h"

#include <SDL3/SDL.h>
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#ifdef ENG_USING_LUAJIT
#include <luajit.h>
#endif

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef ENG_USING_LUAJIT
int luaopen_bit(lua_State *L);
#endif

typedef struct {
    bool active[1024];
    int hits[1024];
} eng_lua_cov_t;

static eng_lua_cov_t g_lua_cov;

static void eng_lua_line_hook(lua_State *L, lua_Debug *ar) {
    if (ar->event == LUA_HOOKLINE && ar->currentline > 0 && ar->currentline < 1024) {
        if (lua_getinfo(L, "S", ar) && ar->source[0] == '@' && strstr(ar->source + 1, "lua/eng/") != NULL) {
            g_lua_cov.hits[ar->currentline]++;
        }
    }
}

static void eng_mark_func_active_lines(lua_State *L) {
    lua_Debug ar;
    lua_pushvalue(L, -1);
    if (lua_getinfo(L, ">L", &ar) && lua_istable(L, -1)) {
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            if (lua_isnumber(L, -2)) {
                int ln = (int)lua_tointeger(L, -2);
                if (ln > 0 && ln < 1024) {
                    g_lua_cov.active[ln] = true;
                }
            }
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
}

static bool eng_write_lua_lcov(const char *script_path, const char *out_path) {
    FILE *out = fopen(out_path, "w");
    if (!out) {
        return false;
    }
    fprintf(out, "TN:\nSF:%s\n", script_path);
    for (int ln = 1; ln < 1024; ln++) {
        if (g_lua_cov.active[ln]) {
            fprintf(out, "DA:%d,%d\n", ln, g_lua_cov.hits[ln]);
        }
    }
    fprintf(out, "end_of_record\n");
    fclose(out);
    return true;
}

const char *eng_version_string(void) {
    return ENG_VERSION_STRING;
}

static bool parse_uint_part(const char **cursor, int *out_val) {
    if (!isdigit((unsigned char)**cursor)) {
        return false;
    }
    long v = 0;
    while (isdigit((unsigned char)**cursor)) {
        v = v * 10 + (**cursor - '0');
        if (v > 99999) {
            return false;
        }
        (*cursor)++;
    }
    *out_val = (int)v;
    return true;
}

bool eng_version_check(const char *required_version) {
    if (!required_version || required_version[0] == '\0') {
        return false;
    }
    const char *p = required_version;
    int req_major = 0, req_minor = 0, req_patch = 0;
    if (!parse_uint_part(&p, &req_major) || *p != '.') {
        return false;
    }
    p++;
    if (!parse_uint_part(&p, &req_minor)) {
        return false;
    }
    if (*p == '.') {
        p++;
        if (!parse_uint_part(&p, &req_patch)) {
            return false;
        }
    }
    if (*p != '\0') {
        return false;
    }
    if (req_major != ENG_VERSION_MAJOR) {
        return false;
    }
    return req_minor == ENG_VERSION_MINOR && req_patch <= ENG_VERSION_PATCH;
}

const char *eng_lua_runtime_name(void) {
#ifdef LUAJIT_VERSION
    return LUAJIT_VERSION;
#else
    return LUA_RELEASE "+bitop";
#endif
}

bool eng_bootstrap_selfcheck(const char *repo_root, const char *lua_lcov_out_path) {
    if (!repo_root || SDL_GetVersion() <= 0) {
        return false;
    }
    lua_State *L = luaL_newstate();
    if (!L) {
        return false;
    }
    luaL_openlibs(L);
#ifndef ENG_USING_LUAJIT
    lua_pushcfunction(L, luaopen_bit);
    lua_pushstring(L, "bit");
    lua_call(L, 1, 1);
    lua_pop(L, 1);
#endif

    memset(&g_lua_cov, 0, sizeof(g_lua_cov));
    if (lua_lcov_out_path) {
        lua_sethook(L, eng_lua_line_hook, LUA_MASKLINE, 0);
    }

    char init_script[1024];
    snprintf(init_script, sizeof(init_script), "%s/lua/eng/init.lua", repo_root);
    bool ok = (luaL_loadfile(L, init_script) == 0);
    if (ok) {
        eng_mark_func_active_lines(L);
        ok = (lua_pcall(L, 0, 1, 0) == 0) && lua_istable(L, -1);
    }
    if (ok) {
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            if (lua_isfunction(L, -1)) {
                eng_mark_func_active_lines(L);
            }
            lua_pop(L, 1);
        }

        lua_getfield(L, -1, "mask_combine");
        lua_pushinteger(L, 0x1234);
        lua_pushinteger(L, 0xABCD);
        ok = (lua_pcall(L, 2, 1, 0) == 0);
        if (ok) {
            lua_Number combined = lua_tonumber(L, -1);
            lua_pop(L, 1);
            lua_getfield(L, -1, "is_finite");
            lua_pushnumber(L, 42.5);
            ok = (lua_pcall(L, 1, 1, 0) == 0) && lua_toboolean(L, -1) &&
                 ((unsigned int)combined == 0xABCD1234u);
            lua_pop(L, 1);
        }
    }

    lua_close(L);
    if (ok && lua_lcov_out_path) {
        ok = eng_write_lua_lcov(init_script, lua_lcov_out_path);
    }
    return ok;
}
