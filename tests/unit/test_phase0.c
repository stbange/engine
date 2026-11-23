#include "engine/engine.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    /* 1. Version & Lua runtime identifier checks */
    assert(strcmp(eng_version_string(), "0.2.0") == 0);
    assert(eng_lua_runtime_name() != NULL && strlen(eng_lua_runtime_name()) > 0);

    /* 2. SemVer compatibility validation (positive & negative edge cases) */
    assert(eng_version_check("0.1") == true);
    assert(eng_version_check("0.1.0") == true);
    assert(eng_version_check("0.2") == true);
    assert(eng_version_check("0.2.0") == true);
    assert(eng_version_check(NULL) == false);
    assert(eng_version_check("") == false);
    assert(eng_version_check("invalid") == false);
    assert(eng_version_check("0.x") == false);
    assert(eng_version_check("0.1.x") == false);
    assert(eng_version_check("0.1.0.2") == false);
    assert(eng_version_check("999999.1.0") == false);
    assert(eng_version_check("1.0.0") == false);
    assert(eng_version_check("0.3.0") == false);
    assert(eng_version_check("0.2.1") == false);

    /* 3. Bootstrap self-check + LCOV Lua coverage output */
    assert(eng_bootstrap_selfcheck(NULL, NULL) == false);
    assert(eng_bootstrap_selfcheck("/nonexistent_repo_root", NULL) == false);
    assert(eng_bootstrap_selfcheck(ENG_SOURCE_DIR, "/nonexistent_dir/lua_cov.info") == false);

    const char *lua_cov_path = ENG_BINARY_DIR "/lua_coverage.info";
    assert(eng_bootstrap_selfcheck(ENG_SOURCE_DIR, lua_cov_path) == true);

    /* 4. CLI dispatch paths */
    char *args_default[] = {(char *)"engine"};
    assert(eng_cli_run(1, args_default) == 0);

    char *args_ver[] = {(char *)"engine", (char *)"--version"};
    assert(eng_cli_run(2, args_ver) == 0);

    char *args_self_ok[] = {(char *)"engine", (char *)"--selfcheck", (char *)ENG_SOURCE_DIR};
    assert(eng_cli_run(3, args_self_ok) == 0);

    char *args_self_bad[] = {(char *)"engine", (char *)"--selfcheck", (char *)"/bad_root"};
    assert(eng_cli_run(3, args_self_bad) == 1);

    printf("[PASS] Phase 0 unit tests succeeded (%s)\n", eng_lua_runtime_name());
    return 0;
}
