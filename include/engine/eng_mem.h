#ifndef ENG_MEM_H
#define ENG_MEM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_HANDLE_INVALID 0ULL

/* Linear bump arena allocator for O(1) frame scratch and level allocations. */
typedef struct {
    uint8_t *buf;
    size_t capacity;
    size_t offset;
    size_t high_water;
    bool owns_buf;
} eng_arena_t;

bool eng_arena_init(eng_arena_t *arena, size_t capacity);
void eng_arena_init_buffer(eng_arena_t *arena, void *backing_buf, size_t capacity);
void eng_arena_destroy(eng_arena_t *arena);
void *eng_arena_alloc_aligned(eng_arena_t *arena, size_t size, size_t align);
void *eng_arena_alloc(eng_arena_t *arena, size_t size);
char *eng_arena_strdup(eng_arena_t *arena, const char *str);
size_t eng_arena_mark(const eng_arena_t *arena);
void eng_arena_reset_to(eng_arena_t *arena, size_t mark);
void eng_arena_reset(eng_arena_t *arena);

/* Generational fixed-stride pool allocator (handle = (gen << 32) | idx). */
typedef struct {
    uint8_t *slots;
    uint32_t *generations;
    uint32_t *free_indices;
    bool *alive;
    size_t stride;
    uint32_t capacity;
    uint32_t free_top;
    uint32_t alive_count;
} eng_pool_t;

bool eng_pool_init(eng_pool_t *pool, size_t elem_stride, uint32_t capacity);
void eng_pool_destroy(eng_pool_t *pool);
uint64_t eng_pool_alloc(eng_pool_t *pool, void **out_ptr);
bool eng_pool_free(eng_pool_t *pool, uint64_t handle);
void *eng_pool_get(const eng_pool_t *pool, uint64_t handle);
bool eng_pool_is_valid(const eng_pool_t *pool, uint64_t handle);
uint32_t eng_pool_count(const eng_pool_t *pool);

#ifdef __cplusplus
}
#endif

#endif /* ENG_MEM_H */
