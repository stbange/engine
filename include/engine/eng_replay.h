#ifndef ENG_REPLAY_H
#define ENG_REPLAY_H

#include "eng_input.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_REPLAY_SCHEMA_VERSION 1u

typedef struct {
    uint32_t frame;
    float time_sec;
    char label[48];
} eng_replay_bookmark_t;

typedef struct eng_replay_s eng_replay_t;

eng_replay_t *eng_replay_create(const char *game_id, uint64_t seed, uint16_t target_fps);
void eng_replay_destroy(eng_replay_t *rep);

/* Record one simulation frame of user inputs (actions, axes, mouse deltas, 4P sticks/buttons). */
bool eng_replay_record_frame(eng_replay_t *rep, const eng_input_t *inp, float dt);

/* Drop a highlight bookmark at the current recorded frame & timestamp. */
bool eng_replay_add_bookmark(eng_replay_t *rep, const char *label);

/* Serialize / deserialize compact binary .engrep files (ENGB versioned container). */
bool eng_replay_save_file(const eng_replay_t *rep, const char *host_path);
eng_replay_t *eng_replay_load_file(const char *host_path);

/* Deterministic playback: injects next recorded frame into inp and writes recorded dt. Returns false at EOF. */
bool eng_replay_step_playback(eng_replay_t *rep, eng_input_t *inp, float *out_dt);
void eng_replay_rewind(eng_replay_t *rep);

/* Inspection & metadata */
size_t eng_replay_frame_count(const eng_replay_t *rep);
size_t eng_replay_cursor(const eng_replay_t *rep);
float eng_replay_duration(const eng_replay_t *rep);
uint64_t eng_replay_seed(const eng_replay_t *rep);
uint16_t eng_replay_target_fps(const eng_replay_t *rep);
const char *eng_replay_game_id(const eng_replay_t *rep);
size_t eng_replay_bookmark_count(const eng_replay_t *rep);
const eng_replay_bookmark_t *eng_replay_bookmark_get(const eng_replay_t *rep, size_t idx);
const eng_replay_bookmark_t *eng_replay_find_bookmark(const eng_replay_t *rep, const char *label);

#ifdef __cplusplus
}
#endif

#endif /* ENG_REPLAY_H */
