#include "engine/eng_math.h"

#include <float.h>
#include <math.h>
#include <string.h>

bool eng_math_is_finite(float x) {
    return isfinite(x) != 0;
}

float eng_clampf(float x, float lo, float hi) {
    return x < lo ? lo : (x > hi ? hi : x);
}

float eng_lerpf(float a, float b, float t) {
    return a + (b - a) * t;
}

eng_vec3_t eng_v3(float x, float y, float z) {
    eng_vec3_t r = {x, y, z};
    return r;
}

bool eng_v3_is_finite(eng_vec3_t v) {
    return eng_math_is_finite(v.x) && eng_math_is_finite(v.y) && eng_math_is_finite(v.z);
}

eng_vec3_t eng_v3_add(eng_vec3_t a, eng_vec3_t b) {
    return eng_v3(a.x + b.x, a.y + b.y, a.z + b.z);
}

eng_vec3_t eng_v3_sub(eng_vec3_t a, eng_vec3_t b) {
    return eng_v3(a.x - b.x, a.y - b.y, a.z - b.z);
}

eng_vec3_t eng_v3_scale(eng_vec3_t v, float s) {
    return eng_v3(v.x * s, v.y * s, v.z * s);
}

float eng_v3_dot(eng_vec3_t a, eng_vec3_t b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

eng_vec3_t eng_v3_cross(eng_vec3_t a, eng_vec3_t b) {
    return eng_v3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    );
}

float eng_v3_len(eng_vec3_t v) {
    return sqrtf(eng_v3_dot(v, v));
}

eng_vec3_t eng_v3_norm(eng_vec3_t v) {
    float len2 = eng_v3_dot(v, v);
    if (len2 <= ENG_EPSILON * ENG_EPSILON || !eng_math_is_finite(len2)) {
        return eng_v3(0.0f, 0.0f, 0.0f);
    }
    return eng_v3_scale(v, 1.0f / sqrtf(len2));
}

eng_vec3_t eng_v3_lerp(eng_vec3_t a, eng_vec3_t b, float t) {
    return eng_v3(eng_lerpf(a.x, b.x, t), eng_lerpf(a.y, b.y, t), eng_lerpf(a.z, b.z, t));
}

eng_quat_t eng_quat_identity(void) {
    eng_quat_t q = {0.0f, 0.0f, 0.0f, 1.0f};
    return q;
}

bool eng_quat_is_finite(eng_quat_t q) {
    return eng_math_is_finite(q.x) && eng_math_is_finite(q.y) &&
           eng_math_is_finite(q.z) && eng_math_is_finite(q.w);
}

eng_quat_t eng_quat_norm(eng_quat_t q) {
    float len2 = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w;
    if (len2 <= ENG_EPSILON * ENG_EPSILON || !eng_math_is_finite(len2)) {
        return eng_quat_identity();
    }
    float inv = 1.0f / sqrtf(len2);
    eng_quat_t r = {q.x * inv, q.y * inv, q.z * inv, q.w * inv};
    return r;
}

eng_quat_t eng_quat_from_axis_angle(eng_vec3_t axis, float angle_rad) {
    eng_vec3_t n = eng_v3_norm(axis);
    float half = 0.5f * angle_rad;
    float s = sinf(half);
    eng_quat_t q = {n.x * s, n.y * s, n.z * s, cosf(half)};
    return eng_quat_norm(q);
}

eng_quat_t eng_quat_from_euler_deg(eng_vec3_t pyr_deg) {
    eng_quat_t qx = eng_quat_from_axis_angle(eng_v3(1.0f, 0.0f, 0.0f), pyr_deg.x * ENG_DEG2RAD);
    eng_quat_t qy = eng_quat_from_axis_angle(eng_v3(0.0f, 1.0f, 0.0f), pyr_deg.y * ENG_DEG2RAD);
    eng_quat_t qz = eng_quat_from_axis_angle(eng_v3(0.0f, 0.0f, 1.0f), pyr_deg.z * ENG_DEG2RAD);
    /* Intrinsic Y (yaw) -> X (pitch) -> Z (roll) standard 3D game convention */
    return eng_quat_norm(eng_quat_mul(eng_quat_mul(qy, qx), qz));
}

eng_quat_t eng_quat_mul(eng_quat_t a, eng_quat_t b) {
    eng_quat_t r = {
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    };
    return r;
}

eng_quat_t eng_quat_slerp(eng_quat_t a, eng_quat_t b, float t) {
    float cos_om = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    if (cos_om < 0.0f) {
        cos_om = -cos_om;
        b.x = -b.x; b.y = -b.y; b.z = -b.z; b.w = -b.w;
    }
    float s0 = 1.0f - t;
    float s1 = t;
    if (1.0f - cos_om > 1e-4f) {
        float om = acosf(eng_clampf(cos_om, -1.0f, 1.0f));
        float inv_sin = 1.0f / sinf(om);
        s0 = sinf((1.0f - t) * om) * inv_sin;
        s1 = sinf(t * om) * inv_sin;
    }
    eng_quat_t r = {
        s0 * a.x + s1 * b.x,
        s0 * a.y + s1 * b.y,
        s0 * a.z + s1 * b.z,
        s0 * a.w + s1 * b.w
    };
    return eng_quat_norm(r);
}

eng_vec3_t eng_quat_rotate_v3(eng_quat_t q, eng_vec3_t v) {
    eng_vec3_t qv = eng_v3(q.x, q.y, q.z);
    eng_vec3_t t = eng_v3_scale(eng_v3_cross(qv, v), 2.0f);
    return eng_v3_add(v, eng_v3_add(eng_v3_scale(t, q.w), eng_v3_cross(qv, t)));
}

eng_mat4_t eng_mat4_identity(void) {
    eng_mat4_t r;
    memset(&r, 0, sizeof(r));
    r.m[0] = r.m[5] = r.m[10] = r.m[15] = 1.0f;
    return r;
}

bool eng_mat4_is_finite(const eng_mat4_t *m) {
    if (!m) return false;
    for (int i = 0; i < 16; i++) {
        if (!eng_math_is_finite(m->m[i])) return false;
    }
    return true;
}

eng_mat4_t eng_mat4_mul(const eng_mat4_t *a, const eng_mat4_t *b) {
    eng_mat4_t r;
    for (int col = 0; col < 4; col++) {
        for (int row = 0; row < 4; row++) {
            r.m[col * 4 + row] =
                a->m[0 * 4 + row] * b->m[col * 4 + 0] +
                a->m[1 * 4 + row] * b->m[col * 4 + 1] +
                a->m[2 * 4 + row] * b->m[col * 4 + 2] +
                a->m[3 * 4 + row] * b->m[col * 4 + 3];
        }
    }
    return r;
}

eng_mat4_t eng_mat4_trs(eng_vec3_t pos, eng_quat_t rot, eng_vec3_t scale) {
    eng_quat_t q = eng_quat_norm(rot);
    float xx = q.x * q.x, yy = q.y * q.y, zz = q.z * q.z;
    float xy = q.x * q.y, xz = q.x * q.z, yz = q.y * q.z;
    float wx = q.w * q.x, wy = q.w * q.y, wz = q.w * q.z;

    eng_mat4_t r = eng_mat4_identity();
    r.m[0] = (1.0f - 2.0f * (yy + zz)) * scale.x;
    r.m[1] = (2.0f * (xy + wz)) * scale.x;
    r.m[2] = (2.0f * (xz - wy)) * scale.x;

    r.m[4] = (2.0f * (xy - wz)) * scale.y;
    r.m[5] = (1.0f - 2.0f * (xx + zz)) * scale.y;
    r.m[6] = (2.0f * (yz + wx)) * scale.y;

    r.m[8]  = (2.0f * (xz + wy)) * scale.z;
    r.m[9]  = (2.0f * (yz - wx)) * scale.z;
    r.m[10] = (1.0f - 2.0f * (xx + yy)) * scale.z;

    r.m[12] = pos.x;
    r.m[13] = pos.y;
    r.m[14] = pos.z;
    return r;
}

eng_mat4_t eng_mat4_perspective(float fov_y_rad, float aspect, float z_near, float z_far) {
    eng_mat4_t r;
    memset(&r, 0, sizeof(r));
    float f = 1.0f / tanf(0.5f * fov_y_rad);
    float inv_nf = 1.0f / (z_near - z_far);
    r.m[0]  = f / aspect;
    r.m[5]  = f;
    r.m[10] = (z_far + z_near) * inv_nf;
    r.m[11] = -1.0f;
    r.m[14] = (2.0f * z_far * z_near) * inv_nf;
    return r;
}

eng_mat4_t eng_mat4_ortho(float left, float right, float bottom, float top, float z_near, float z_far) {
    eng_mat4_t r = eng_mat4_identity();
    r.m[0]  = 2.0f / (right - left);
    r.m[5]  = 2.0f / (top - bottom);
    r.m[10] = -2.0f / (z_far - z_near);
    r.m[12] = -(right + left) / (right - left);
    r.m[13] = -(top + bottom) / (top - bottom);
    r.m[14] = -(z_far + z_near) / (z_far - z_near);
    return r;
}

eng_mat4_t eng_mat4_look_at(eng_vec3_t eye, eng_vec3_t target, eng_vec3_t up) {
    eng_vec3_t f = eng_v3_norm(eng_v3_sub(target, eye));
    eng_vec3_t s = eng_v3_norm(eng_v3_cross(f, up));
    eng_vec3_t u = eng_v3_cross(s, f);

    eng_mat4_t r = eng_mat4_identity();
    r.m[0] = s.x;  r.m[4] = s.y;  r.m[8]  = s.z;  r.m[12] = -eng_v3_dot(s, eye);
    r.m[1] = u.x;  r.m[5] = u.y;  r.m[9]  = u.z;  r.m[13] = -eng_v3_dot(u, eye);
    r.m[2] = -f.x; r.m[6] = -f.y; r.m[10] = -f.z; r.m[14] = eng_v3_dot(f, eye);
    return r;
}

bool eng_mat4_invert(const eng_mat4_t *in, eng_mat4_t *out) {
    const float *m = in->m;
    float inv[16];
    inv[0] = m[5]  * m[10] * m[15] - m[5]  * m[11] * m[14] - m[9]  * m[6]  * m[15] +
             m[9]  * m[7]  * m[14] + m[13] * m[6]  * m[11] - m[13] * m[7]  * m[10];
    inv[4] = -m[4]  * m[10] * m[15] + m[4]  * m[11] * m[14] + m[8]  * m[6]  * m[15] -
              m[8]  * m[7]  * m[14] - m[12] * m[6]  * m[11] + m[12] * m[7]  * m[10];
    inv[8] = m[4]  * m[9] * m[15] - m[4]  * m[11] * m[13] - m[8]  * m[5] * m[15] +
             m[8]  * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    inv[12] = -m[4]  * m[9] * m[14] + m[4]  * m[10] * m[13] + m[8]  * m[5] * m[14] -
               m[8]  * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    inv[1] = -m[1]  * m[10] * m[15] + m[1]  * m[11] * m[14] + m[9]  * m[2] * m[15] -
              m[9]  * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    inv[5] = m[0]  * m[10] * m[15] - m[0]  * m[11] * m[14] - m[8]  * m[2] * m[15] +
             m[8]  * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    inv[9] = -m[0]  * m[9] * m[15] + m[0]  * m[11] * m[13] + m[8]  * m[1] * m[15] -
              m[8]  * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    inv[13] = m[0]  * m[9] * m[14] - m[0]  * m[10] * m[13] - m[8]  * m[1] * m[14] +
              m[8]  * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    inv[2] = m[1]  * m[6] * m[15] - m[1]  * m[7] * m[14] - m[5]  * m[2] * m[15] +
             m[5]  * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    inv[6] = -m[0]  * m[6] * m[15] + m[0]  * m[7] * m[14] + m[4]  * m[2] * m[15] -
              m[4]  * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    inv[10] = m[0]  * m[5] * m[15] - m[0]  * m[7] * m[13] - m[4]  * m[1] * m[15] +
              m[4]  * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    inv[14] = -m[0]  * m[5] * m[14] + m[0]  * m[6] * m[13] + m[4]  * m[1] * m[14] -
               m[4]  * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] -
              m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] +
             m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] -
               m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] +
              m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];

    float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
    if (fabsf(det) <= 1e-12f) {
        return false;
    }
    float inv_det = 1.0f / det;
    for (int i = 0; i < 16; i++) {
        out->m[i] = inv[i] * inv_det;
    }
    return true;
}

eng_vec3_t eng_mat4_transform_point(const eng_mat4_t *m, eng_vec3_t p) {
    float x = m->m[0] * p.x + m->m[4] * p.y + m->m[8]  * p.z + m->m[12];
    float y = m->m[1] * p.x + m->m[5] * p.y + m->m[9]  * p.z + m->m[13];
    float z = m->m[2] * p.x + m->m[6] * p.y + m->m[10] * p.z + m->m[14];
    float w = m->m[3] * p.x + m->m[7] * p.y + m->m[11] * p.z + m->m[15];
    if (fabsf(w) > ENG_EPSILON && fabsf(w - 1.0f) > ENG_EPSILON) {
        float inv_w = 1.0f / w;
        return eng_v3(x * inv_w, y * inv_w, z * inv_w);
    }
    return eng_v3(x, y, z);
}

eng_aabb_t eng_aabb_transform(eng_aabb_t local, const eng_mat4_t *world) {
    eng_aabb_t res = {eng_v3(FLT_MAX, FLT_MAX, FLT_MAX), eng_v3(-FLT_MAX, -FLT_MAX, -FLT_MAX)};
    for (int i = 0; i < 8; i++) {
        eng_vec3_t corner = eng_v3(
            (i & 1) ? local.max.x : local.min.x,
            (i & 2) ? local.max.y : local.min.y,
            (i & 4) ? local.max.z : local.min.z
        );
        eng_vec3_t p = eng_mat4_transform_point(world, corner);
        if (p.x < res.min.x) res.min.x = p.x;
        if (p.y < res.min.y) res.min.y = p.y;
        if (p.z < res.min.z) res.min.z = p.z;
        if (p.x > res.max.x) res.max.x = p.x;
        if (p.y > res.max.y) res.max.y = p.y;
        if (p.z > res.max.z) res.max.z = p.z;
    }
    return res;
}

bool eng_aabb_overlaps(eng_aabb_t a, eng_aabb_t b, float *out_penetration) {
    float ox = fminf(a.max.x, b.max.x) - fmaxf(a.min.x, b.min.x);
    float oy = fminf(a.max.y, b.max.y) - fmaxf(a.min.y, b.min.y);
    float oz = fminf(a.max.z, b.max.z) - fmaxf(a.min.z, b.min.z);
    if (ox <= 0.0f || oy <= 0.0f || oz <= 0.0f) {
        return false;
    }
    if (out_penetration) {
        *out_penetration = fminf(ox, fminf(oy, oz));
    }
    return true;
}

bool eng_aabb_ray_hit(eng_aabb_t box, eng_vec3_t origin, eng_vec3_t dir, float max_dist, float *out_t) {
    float tmin = 0.0f;
    float tmax = max_dist;
    const float o[3] = {origin.x, origin.y, origin.z};
    const float d[3] = {dir.x, dir.y, dir.z};
    const float bmin[3] = {box.min.x, box.min.y, box.min.z};
    const float bmax[3] = {box.max.x, box.max.y, box.max.z};

    for (int i = 0; i < 3; i++) {
        if (fabsf(d[i]) < ENG_EPSILON) {
            if (o[i] < bmin[i] || o[i] > bmax[i]) return false;
        } else {
            float inv_d = 1.0f / d[i];
            float t1 = (bmin[i] - o[i]) * inv_d;
            float t2 = (bmax[i] - o[i]) * inv_d;
            if (t1 > t2) { float tmp = t1; t1 = t2; t2 = tmp; }
            if (t1 > tmin) tmin = t1;
            if (t2 < tmax) tmax = t2;
            if (tmin > tmax) return false;
        }
    }
    if (out_t) *out_t = tmin;
    return true;
}

static eng_plane_t norm_plane(float a, float b, float c, float d) {
    float len = sqrtf(a * a + b * b + c * c);
    float inv = (len > ENG_EPSILON) ? (1.0f / len) : 0.0f;
    eng_plane_t p = {eng_v3(a * inv, b * inv, c * inv), d * inv};
    return p;
}

eng_frustum_t eng_frustum_from_mat4(const eng_mat4_t *vp) {
    const float *m = vp->m;
    eng_frustum_t f;
    f.planes[0] = norm_plane(m[3] + m[0], m[7] + m[4], m[11] + m[8],  m[15] + m[12]); /* left */
    f.planes[1] = norm_plane(m[3] - m[0], m[7] - m[4], m[11] - m[8],  m[15] - m[12]); /* right */
    f.planes[2] = norm_plane(m[3] + m[1], m[7] + m[5], m[11] + m[9],  m[15] + m[13]); /* bottom */
    f.planes[3] = norm_plane(m[3] - m[1], m[7] - m[5], m[11] - m[9],  m[15] - m[13]); /* top */
    f.planes[4] = norm_plane(m[3] + m[2], m[7] + m[6], m[11] + m[10], m[15] + m[14]); /* near */
    f.planes[5] = norm_plane(m[3] - m[2], m[7] - m[6], m[11] - m[10], m[15] - m[14]); /* far */
    return f;
}

bool eng_frustum_test_aabb(const eng_frustum_t *f, eng_aabb_t box) {
    for (int i = 0; i < 6; i++) {
        eng_plane_t p = f->planes[i];
        eng_vec3_t pv = eng_v3(
            p.normal.x >= 0.0f ? box.max.x : box.min.x,
            p.normal.y >= 0.0f ? box.max.y : box.min.y,
            p.normal.z >= 0.0f ? box.max.z : box.min.z
        );
        if (eng_v3_dot(p.normal, pv) + p.d < 0.0f) {
            return false;
        }
    }
    return true;
}

bool eng_frustum_test_sphere(const eng_frustum_t *f, eng_vec3_t center, float radius) {
    for (int i = 0; i < 6; i++) {
        if (eng_v3_dot(f->planes[i].normal, center) + f->planes[i].d < -radius) {
            return false;
        }
    }
    return true;
}

static uint64_t splitmix64_next(uint64_t *state) {
    uint64_t z = (*state += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

static uint32_t rotl32(uint32_t x, int k) {
    return (x << k) | (x >> (32 - k));
}

void eng_rng_seed(eng_rng_t *rng, uint64_t seed) {
    uint64_t sm = seed ? seed : 1ULL;
    uint64_t a = splitmix64_next(&sm);
    uint64_t b = splitmix64_next(&sm);
    rng->s[0] = (uint32_t)a;
    rng->s[1] = (uint32_t)(a >> 32);
    rng->s[2] = (uint32_t)b;
    rng->s[3] = (uint32_t)(b >> 32);
}

uint32_t eng_rng_u32(eng_rng_t *rng) {
    uint32_t result = rotl32(rng->s[0] + rng->s[3], 7) + rng->s[0];
    uint32_t t = rng->s[1] << 9;
    rng->s[2] ^= rng->s[0];
    rng->s[3] ^= rng->s[1];
    rng->s[1] ^= rng->s[2];
    rng->s[0] ^= rng->s[3];
    rng->s[2] ^= t;
    rng->s[3] = rotl32(rng->s[3], 11);
    return result;
}

float eng_rng_float01(eng_rng_t *rng) {
    return (float)(eng_rng_u32(rng) >> 8) * (1.0f / 16777216.0f);
}

float eng_rng_rangef(eng_rng_t *rng, float lo, float hi) {
    return lo + (hi - lo) * eng_rng_float01(rng);
}

size_t eng_str_levenshtein(const char *a, const char *b) {
    if (!a || !b) return 999;
    size_t la = strlen(a), lb = strlen(b);
    if (la > 63) la = 63;
    if (lb > 63) lb = 63;
    size_t row[64];
    for (size_t j = 0; j <= lb; j++) row[j] = j;
    for (size_t i = 1; i <= la; i++) {
        size_t prev = row[0];
        row[0] = i;
        for (size_t j = 1; j <= lb; j++) {
            size_t cost = (a[i - 1] == b[j - 1]) ? 0 : 1;
            size_t del = row[j] + 1;
            size_t ins = row[j - 1] + 1;
            size_t sub = prev + cost;
            prev = row[j];
            size_t m = del < ins ? del : ins;
            row[j] = m < sub ? m : sub;
        }
    }
    return row[lb];
}

const char *eng_str_suggest(const char *typo, const char *const *candidates, size_t count, size_t max_dist) {
    if (!typo || !candidates || count == 0) return NULL;
    const char *best = NULL;
    size_t best_d = max_dist + 1;
    for (size_t i = 0; i < count; i++) {
        if (!candidates[i]) continue;
        size_t d = eng_str_levenshtein(typo, candidates[i]);
        if (d < best_d) {
            best_d = d;
            best = candidates[i];
        }
    }
    return best;
}
