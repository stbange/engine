#include "engine/eng_jobs.h"

#include <SDL3/SDL_mutex.h>
#include <SDL3/SDL_thread.h>
#include <SDL3/SDL_timer.h>
#include <stdlib.h>
#include <string.h>

#define ENG_JOB_QUEUE_CAP 256
#define ENG_MAX_WORKERS 16

typedef struct {
    eng_job_fn fn;
    void *userdata;
    uint32_t index;
    eng_job_counter_t *counter;
} eng_job_item_t;

struct eng_jobs_s {
    SDL_Thread *threads[ENG_MAX_WORKERS];
    int worker_count;
    SDL_Mutex *mutex;
    SDL_Condition *cond_work;
    SDL_Condition *cond_space;
    eng_job_item_t queue[ENG_JOB_QUEUE_CAP];
    uint32_t head;
    uint32_t tail;
    uint32_t count;
    bool stop;
};

static bool pop_and_run_one(eng_jobs_t *jobs) {
    SDL_LockMutex(jobs->mutex);
    if (jobs->count == 0) {
        SDL_UnlockMutex(jobs->mutex);
        return false;
    }
    eng_job_item_t item = jobs->queue[jobs->head];
    jobs->head = (jobs->head + 1u) % ENG_JOB_QUEUE_CAP;
    jobs->count--;
    SDL_SignalCondition(jobs->cond_space);
    SDL_UnlockMutex(jobs->mutex);

    item.fn(item.index, item.userdata);
    if (item.counter) {
        SDL_AddAtomicInt(&item.counter->pending, -1);
    }
    return true;
}

static int SDLCALL worker_main(void *arg) {
    eng_jobs_t *jobs = (eng_jobs_t *)arg;
    for (;;) {
        SDL_LockMutex(jobs->mutex);
        while (jobs->count == 0 && !jobs->stop) {
            SDL_WaitCondition(jobs->cond_work, jobs->mutex);
        }
        if (jobs->stop && jobs->count == 0) {
            SDL_UnlockMutex(jobs->mutex);
            break;
        }
        eng_job_item_t item = jobs->queue[jobs->head];
        jobs->head = (jobs->head + 1u) % ENG_JOB_QUEUE_CAP;
        jobs->count--;
        SDL_SignalCondition(jobs->cond_space);
        SDL_UnlockMutex(jobs->mutex);

        item.fn(item.index, item.userdata);
        if (item.counter) {
            SDL_AddAtomicInt(&item.counter->pending, -1);
        }
    }
    return 0;
}

eng_jobs_t *eng_jobs_create(int num_workers) {
    eng_jobs_t *jobs = (eng_jobs_t *)calloc(1, sizeof(eng_jobs_t));
    if (!jobs) return NULL;

#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
    num_workers = 0;
#endif
    if (num_workers < 0) num_workers = 0;
    if (num_workers > ENG_MAX_WORKERS) num_workers = ENG_MAX_WORKERS;

    if (num_workers == 0) {
        return jobs;
    }

    jobs->mutex = SDL_CreateMutex();
    jobs->cond_work = SDL_CreateCondition();
    jobs->cond_space = SDL_CreateCondition();
    for (int i = 0; i < num_workers; i++) {
        SDL_Thread *t = SDL_CreateThread(worker_main, "eng_worker", jobs);
        if (!t) break;
        jobs->threads[jobs->worker_count++] = t;
    }
    return jobs;
}

void eng_jobs_destroy(eng_jobs_t *jobs) {
    if (!jobs) return;
    if (jobs->worker_count > 0) {
        SDL_LockMutex(jobs->mutex);
        jobs->stop = true;
        SDL_BroadcastCondition(jobs->cond_work);
        SDL_UnlockMutex(jobs->mutex);
        for (int i = 0; i < jobs->worker_count; i++) {
            SDL_WaitThread(jobs->threads[i], NULL);
        }
        SDL_DestroyCondition(jobs->cond_space);
        SDL_DestroyCondition(jobs->cond_work);
        SDL_DestroyMutex(jobs->mutex);
    }
    free(jobs);
}

int eng_jobs_worker_count(const eng_jobs_t *jobs) {
    return jobs ? jobs->worker_count : 0;
}

void eng_jobs_dispatch(eng_jobs_t *jobs, uint32_t count, eng_job_fn fn, void *userdata, eng_job_counter_t *counter) {
    if (!fn || count == 0) return;
    if (!jobs || jobs->worker_count == 0) {
        for (uint32_t i = 0; i < count; i++) {
            fn(i, userdata);
        }
        return;
    }

    if (counter) {
        SDL_AddAtomicInt(&counter->pending, (int)count);
    }

    for (uint32_t i = 0; i < count; i++) {
        SDL_LockMutex(jobs->mutex);
        while (jobs->count == ENG_JOB_QUEUE_CAP) {
            SDL_WaitCondition(jobs->cond_space, jobs->mutex);
        }
        eng_job_item_t *slot = &jobs->queue[jobs->tail];
        slot->fn = fn;
        slot->userdata = userdata;
        slot->index = i;
        slot->counter = counter;
        jobs->tail = (jobs->tail + 1u) % ENG_JOB_QUEUE_CAP;
        jobs->count++;
        SDL_SignalCondition(jobs->cond_work);
        SDL_UnlockMutex(jobs->mutex);
    }
}

void eng_jobs_wait(eng_jobs_t *jobs, eng_job_counter_t *counter) {
    if (!counter) return;
    while (SDL_GetAtomicInt(&counter->pending) > 0) {
        if (!jobs || jobs->worker_count == 0 || !pop_and_run_one(jobs)) {
            SDL_DelayNS(50000); /* 50us yield while worker finishes in-flight task */
        }
    }
}
