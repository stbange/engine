#ifndef ENG_PROFILER_H
#define ENG_PROFILER_H

#include "eng_math.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct eng_profiler_s eng_profiler_t;

eng_profiler_t *eng_profiler_create(void);
void eng_profiler_destroy(eng_profiler_t *prof);

/* Frame & scoped CPU/GPU timing */
void eng_profiler_begin_frame(eng_profiler_t *prof);
void eng_profiler_end_frame(eng_profiler_t *prof);

void eng_profiler_begin_scope(eng_profiler_t *prof, const char *name);
void eng_profiler_end_scope(eng_profiler_t *prof, const char *name);

float eng_profiler_frame_ms(const eng_profiler_t *prof);
float eng_profiler_fps(const eng_profiler_t *prof);
float eng_profiler_scope_ms(const eng_profiler_t *prof, const char *name);
uint32_t eng_profiler_scope_count(const eng_profiler_t *prof);
const char *eng_profiler_scope_name(const eng_profiler_t *prof, uint32_t idx, float *out_ms);

/* Memory arena meter telemetry */
void eng_profiler_set_arena_stats(eng_profiler_t *prof, size_t used_bytes, size_t cap_bytes);
void eng_profiler_get_arena_stats(const eng_profiler_t *prof, size_t *out_used, size_t *out_cap);

/* Batched 3D debug wireframe/collider/portal/skeleton/navmesh line drawing */
void eng_debug_line(eng_profiler_t *prof, eng_vec3_t a, eng_vec3_t b, eng_vec4_t color);
void eng_debug_aabb(eng_profiler_t *prof, eng_aabb_t box, eng_vec4_t color);
void eng_debug_sphere(eng_profiler_t *prof, eng_vec3_t center, float radius, eng_vec4_t color);
void eng_debug_portal(eng_profiler_t *prof, eng_vec3_t pos, eng_quat_t rot, float w, float h, eng_vec4_t color);
void eng_debug_skeleton(eng_profiler_t *prof, const eng_vec3_t *joint_world_pos,
                        const int32_t *parent_idx, uint32_t joint_count, eng_vec4_t color);
void eng_debug_navpath(eng_profiler_t *prof, const eng_vec3_t *waypoints, uint32_t count, eng_vec4_t color);

uint32_t eng_profiler_debug_vertex_count(const eng_profiler_t *prof);
void eng_profiler_render_debug_lines(eng_profiler_t *prof, const eng_mat4_t *view_proj);

#ifdef __cplusplus
}
#endif

#endif /* ENG_PROFILER_H */
