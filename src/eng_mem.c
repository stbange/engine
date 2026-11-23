#include "engine/eng_mem.h"

#include <stdlib.h>
#include <string.h>

bool eng_arena_init(eng_arena_t *arena, size_t capacity) {
    if (!arena || capacity == 0) return false;
    memset(arena, 0, sizeof(*arena));
    arena->buf = (uint8_t *)malloc(capacity);
    if (!arena->buf) return false;
    arena->capacity = capacity;
    arena->owns_buf = true;
    return true;
}

void eng_arena_init_buffer(eng_arena_t *arena, void *backing_buf, size_t capacity) {
    memset(arena, 0, sizeof(*arena));
    arena->buf = (uint8_t *)backing_buf;
    arena->capacity = backing_buf ? capacity : 0;
    arena->owns_buf = false;
}

void eng_arena_destroy(eng_arena_t *arena) {
    if (!arena) return;
    if (arena->owns_buf && arena->buf) {
        free(arena->buf);
    }
    memset(arena, 0, sizeof(*arena));
}

void *eng_arena_alloc_aligned(eng_arena_t *arena, size_t size, size_t align) {
    if (!arena || !arena->buf || size == 0 || align == 0 || (align & (align - 1)) != 0) {
        return NULL;
    }
    size_t mask = align - 1;
    size_t aligned = (arena->offset + mask) & ~mask;
    if (aligned > arena->capacity || size > arena->capacity - aligned) {
        return NULL;
    }
    void *ptr = arena->buf + aligned;
    memset(ptr, 0, size);
    arena->offset = aligned + size;
    if (arena->offset > arena->high_water) {
        arena->high_water = arena->offset;
    }
    return ptr;
}

void *eng_arena_alloc(eng_arena_t *arena, size_t size) {
    return eng_arena_alloc_aligned(arena, size, 16);
}

char *eng_arena_strdup(eng_arena_t *arena, const char *str) {
    if (!arena || !str) return NULL;
    size_t len = strlen(str);
    char *copy = (char *)eng_arena_alloc_aligned(arena, len + 1, 1);
    if (copy) {
        memcpy(copy, str, len + 1);
    }
    return copy;
}

size_t eng_arena_mark(const eng_arena_t *arena) {
    return arena ? arena->offset : 0;
}

void eng_arena_reset_to(eng_arena_t *arena, size_t mark) {
    if (arena && mark <= arena->offset) {
        arena->offset = mark;
    }
}

void eng_arena_reset(eng_arena_t *arena) {
    if (arena) {
        arena->offset = 0;
    }
}

bool eng_pool_init(eng_pool_t *pool, size_t elem_stride, uint32_t capacity) {
    if (!pool || elem_stride == 0 || capacity == 0) return false;
    memset(pool, 0, sizeof(*pool));
    size_t aligned_stride = (elem_stride + 15u) & ~(size_t)15u;
    pool->slots = (uint8_t *)calloc(capacity, aligned_stride);
    pool->generations = (uint32_t *)calloc(capacity, sizeof(uint32_t));
    pool->free_indices = (uint32_t *)malloc(capacity * sizeof(uint32_t));
    pool->alive = (bool *)calloc(capacity, sizeof(bool));
    if (!pool->slots || !pool->generations || !pool->free_indices || !pool->alive) {
        eng_pool_destroy(pool);
        return false;
    }
    pool->stride = aligned_stride;
    pool->capacity = capacity;
    pool->free_top = capacity;
    for (uint32_t i = 0; i < capacity; i++) {
        pool->generations[i] = 1u; /* Non-zero so handle 0 is always invalid */
        pool->free_indices[i] = capacity - 1u - i;
    }
    return true;
}

void eng_pool_destroy(eng_pool_t *pool) {
    if (!pool) return;
    free(pool->slots);
    free(pool->generations);
    free(pool->free_indices);
    free(pool->alive);
    memset(pool, 0, sizeof(*pool));
}

uint64_t eng_pool_alloc(eng_pool_t *pool, void **out_ptr) {
    if (!pool || pool->free_top == 0) {
        if (out_ptr) *out_ptr = NULL;
        return ENG_HANDLE_INVALID;
    }
    uint32_t idx = pool->free_indices[--pool->free_top];
    pool->alive[idx] = true;
    pool->alive_count++;
    void *ptr = pool->slots + ((size_t)idx * pool->stride);
    memset(ptr, 0, pool->stride);
    if (out_ptr) *out_ptr = ptr;
    return ((uint64_t)pool->generations[idx] << 32) | (uint64_t)idx;
}

bool eng_pool_is_valid(const eng_pool_t *pool, uint64_t handle) {
    if (!pool || handle == ENG_HANDLE_INVALID) return false;
    uint32_t idx = (uint32_t)(handle & 0xFFFFFFFFu);
    uint32_t gen = (uint32_t)(handle >> 32);
    return idx < pool->capacity && pool->alive[idx] && pool->generations[idx] == gen;
}

void *eng_pool_get(const eng_pool_t *pool, uint64_t handle) {
    if (!eng_pool_is_valid(pool, handle)) return NULL;
    uint32_t idx = (uint32_t)(handle & 0xFFFFFFFFu);
    return pool->slots + ((size_t)idx * pool->stride);
}

bool eng_pool_free(eng_pool_t *pool, uint64_t handle) {
    if (!eng_pool_is_valid(pool, handle)) return false;
    uint32_t idx = (uint32_t)(handle & 0xFFFFFFFFu);
    pool->alive[idx] = false;
    pool->generations[idx]++;
    if (pool->generations[idx] == 0) {
        pool->generations[idx] = 1u;
    }
    pool->free_indices[pool->free_top++] = idx;
    pool->alive_count--;
    return true;
}

uint32_t eng_pool_count(const eng_pool_t *pool) {
    return pool ? pool->alive_count : 0;
}
