#ifndef ENG_VERSION_H
#define ENG_VERSION_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_VERSION_MAJOR 0
#define ENG_VERSION_MINOR 2
#define ENG_VERSION_PATCH 0
#define ENG_VERSION_STRING "0.2.0"

/* Return the Engine semantic version string ("MAJOR.MINOR.PATCH"). */
const char *eng_version_string(void);

/* Check whether a game.json "engine_version" ("MAJOR.MINOR" or "MAJOR.MINOR.PATCH")
 * is compatible with the running engine binary. */
bool eng_version_check(const char *required_version);

/* Return the active embedded Lua runtime identifier ("LuaJIT 2.1..." or "Lua 5.1.5+bitop"). */
const char *eng_lua_runtime_name(void);

/* Run a minimal self-check of SDL3 + Lua 5.1 + bit.* + lua/eng/init.lua, optionally
 * writing Lua line coverage in LCOV format to lua_lcov_out_path (if non-NULL). */
bool eng_bootstrap_selfcheck(const char *repo_root, const char *lua_lcov_out_path);

/* Execute the Engine command-line runner with standard main(argc, argv) arguments. */
int eng_cli_run(int argc, char **argv);

#ifdef __cplusplus
}
#endif

#endif /* ENG_VERSION_H */
