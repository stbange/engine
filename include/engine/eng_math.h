#ifndef ENG_MATH_H
#define ENG_MATH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENG_PI 3.14159265358979323846f
#define ENG_DEG2RAD (ENG_PI / 180.0f)
#define ENG_RAD2DEG (180.0f / ENG_PI)
#define ENG_EPSILON 1e-6f

typedef struct { float x, y; } eng_vec2_t;
typedef struct { float x, y, z; } eng_vec3_t;
typedef struct { float x, y, z, w; } eng_vec4_t;
typedef struct { float x, y, z, w; } eng_quat_t;
/* Column-major 4x4 matrix matching OpenGL / GLSL layout (m[col*4 + row]). */
typedef struct { float m[16]; } eng_mat4_t;

typedef struct {
    eng_vec3_t min;
    eng_vec3_t max;
} eng_aabb_t;

typedef struct {
    eng_vec3_t normal;
    float d;
} eng_plane_t;

typedef struct {
    eng_plane_t planes[6]; /* left, right, bottom, top, near, far */
} eng_frustum_t;

typedef struct {
    uint32_t s[4];
} eng_rng_t;

/* Scalar & NaN/Inf validation */
bool eng_math_is_finite(float x);
float eng_clampf(float x, float lo, float hi);
float eng_lerpf(float a, float b, float t);

/* Vec3 (+X right, +Y up, -Z forward) */
eng_vec3_t eng_v3(float x, float y, float z);
bool eng_v3_is_finite(eng_vec3_t v);
eng_vec3_t eng_v3_add(eng_vec3_t a, eng_vec3_t b);
eng_vec3_t eng_v3_sub(eng_vec3_t a, eng_vec3_t b);
eng_vec3_t eng_v3_scale(eng_vec3_t v, float s);
float eng_v3_dot(eng_vec3_t a, eng_vec3_t b);
eng_vec3_t eng_v3_cross(eng_vec3_t a, eng_vec3_t b);
float eng_v3_len(eng_vec3_t v);
eng_vec3_t eng_v3_norm(eng_vec3_t v); /* Returns (0,0,0) safely on zero-length input */
eng_vec3_t eng_v3_lerp(eng_vec3_t a, eng_vec3_t b, float t);

/* Quaternion */
eng_quat_t eng_quat_identity(void);
bool eng_quat_is_finite(eng_quat_t q);
eng_quat_t eng_quat_from_axis_angle(eng_vec3_t axis, float angle_rad);
eng_quat_t eng_quat_from_euler_deg(eng_vec3_t pitch_yaw_roll_deg);
eng_quat_t eng_quat_mul(eng_quat_t a, eng_quat_t b);
eng_quat_t eng_quat_norm(eng_quat_t q);
eng_quat_t eng_quat_slerp(eng_quat_t a, eng_quat_t b, float t);
eng_vec3_t eng_quat_rotate_v3(eng_quat_t q, eng_vec3_t v);

/* Mat4 (OpenGL right-handed clip space [-1, 1]) */
eng_mat4_t eng_mat4_identity(void);
bool eng_mat4_is_finite(const eng_mat4_t *m);
eng_mat4_t eng_mat4_mul(const eng_mat4_t *a, const eng_mat4_t *b);
eng_mat4_t eng_mat4_trs(eng_vec3_t pos, eng_quat_t rot, eng_vec3_t scale);
eng_mat4_t eng_mat4_perspective(float fov_y_rad, float aspect, float z_near, float z_far);
eng_mat4_t eng_mat4_ortho(float left, float right, float bottom, float top, float z_near, float z_far);
eng_mat4_t eng_mat4_look_at(eng_vec3_t eye, eng_vec3_t target, eng_vec3_t up);
bool eng_mat4_invert(const eng_mat4_t *in, eng_mat4_t *out);
eng_vec3_t eng_mat4_transform_point(const eng_mat4_t *m, eng_vec3_t p);

/* AABB, Ray & Frustum culling */
eng_aabb_t eng_aabb_transform(eng_aabb_t local, const eng_mat4_t *world);
bool eng_aabb_overlaps(eng_aabb_t a, eng_aabb_t b, float *out_penetration);
bool eng_aabb_ray_hit(eng_aabb_t box, eng_vec3_t origin, eng_vec3_t dir, float max_dist, float *out_t);
eng_frustum_t eng_frustum_from_mat4(const eng_mat4_t *vp);
bool eng_frustum_test_aabb(const eng_frustum_t *f, eng_aabb_t box);
bool eng_frustum_test_sphere(const eng_frustum_t *f, eng_vec3_t center, float radius);

/* Deterministic xoshiro128++ PRNG */
void eng_rng_seed(eng_rng_t *rng, uint64_t seed);
uint32_t eng_rng_u32(eng_rng_t *rng);
float eng_rng_float01(eng_rng_t *rng);
float eng_rng_rangef(eng_rng_t *rng, float lo, float hi);

/* Levenshtein distance & closest-symbol suggestion for LLM typo diagnostics */
size_t eng_str_levenshtein(const char *a, const char *b);
const char *eng_str_suggest(const char *typo, const char *const *candidates, size_t count, size_t max_dist);

#ifdef __cplusplus
}
#endif

#endif /* ENG_MATH_H */
