#ifndef ENG_DOCTOR_H
#define ENG_DOCTOR_H

#include "eng_lua.h"

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int warnings;
    int errors;
    char summary[2048];
} eng_doctor_report_t;

/* Audit an active runtime scene for empty camera frustums, unlit scenes, blocked portals,
 * deep collider overlaps, and extreme entity scale mismatches. Returns true if 0 errors & 0 warnings. */
bool eng_doctor_audit(eng_runtime_t *rt, eng_doctor_report_t *out_report);

/* Audit a game directory across N distinct procedural seeds (1..num_seeds). */
bool eng_doctor_fuzz_game(const char *repo_root, const char *game_dir, const char *mod_dir,
                          int num_seeds, eng_doctor_report_t *out_report);

/* Render a 2x2 Multimodal Contact Sheet (Active Camera, 45° Isometric, Top-Down Map, Close/Portal View) to PNG. */
bool eng_doctor_capture_sheet(eng_runtime_t *rt, const char *out_png_path);

/* Scaffold a complete runnable external game directory (game.json, scripts/main.lua, locales/en.json, tests/playtest.lua).
 * Supported templates: "fps", "voxel", "pocket_house", "procgen_roguelike", "planet_explorer", "xr". */
bool eng_scaffold_game(const char *target_dir, const char *template_name, char *err_buf, size_t err_cap);

#ifdef __cplusplus
}
#endif

#endif /* ENG_DOCTOR_H */
