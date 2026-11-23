#ifndef ENG_JOBS_H
#define ENG_JOBS_H

#include <SDL3/SDL_atomic.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*eng_job_fn)(uint32_t job_index, void *userdata);

typedef struct {
    SDL_AtomicInt pending;
} eng_job_counter_t;

typedef struct eng_jobs_s eng_jobs_t;

/* Initialize worker pool. Pass num_workers == 0 for single-threaded inline execution
 * (automatically forced on non-pthread Emscripten Web builds). */
eng_jobs_t *eng_jobs_create(int num_workers);
void eng_jobs_destroy(eng_jobs_t *jobs);
int eng_jobs_worker_count(const eng_jobs_t *jobs);

void eng_jobs_dispatch(eng_jobs_t *jobs, uint32_t count, eng_job_fn fn, void *userdata, eng_job_counter_t *counter);
void eng_jobs_wait(eng_jobs_t *jobs, eng_job_counter_t *counter);

#ifdef __cplusplus
}
#endif

#endif /* ENG_JOBS_H */
