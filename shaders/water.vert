#include "shaders/common.glsl"

layout(location = 0) in vec3 a_pos;

uniform mat4 u_vp;
uniform mat4 u_light_vp;
uniform vec4 u_water_bounds; /* xy = center_xz, zw = size_xz */
uniform vec4 u_water_wave;   /* x = level_y, y = amp, z = freq, w = time */
uniform vec4 u_water_wind;   /* xy = wind_dir, z = choppiness, w = flow_speed */
uniform float u_vertex_snap;

out vec3 v_world_pos;
out vec3 v_norm;
out vec2 v_uv;
out vec4 v_shadow_coord;
out float v_crest;

void add_gerstner(vec2 base_xz, vec2 dir, float amp, float freq, float steep, float spd, float t,
                  inout vec3 disp, inout vec3 d_dx, inout vec3 d_dz, inout float crest) {
    vec2 d = normalize(dir);
    float ph = dot(d, base_xz) * freq + t * spd;
    float s = sin(ph), c = cos(ph);
    float qa = steep * amp;
    disp.x += d.x * qa * c;
    disp.z += d.y * qa * c;
    disp.y += amp * s;

    float wa = freq * amp;
    float qwa = steep * wa;
    d_dx += vec3(-d.x * d.x * qwa * s, d.x * wa * c, -d.x * d.y * qwa * s);
    d_dz += vec3(-d.x * d.y * qwa * s, d.y * wa * c, -d.y * d.y * qwa * s);
    crest += qwa * max(s, 0.0);
}

void main() {
    vec2 xz = u_water_bounds.xy + a_pos.xz * u_water_bounds.zw;
    float amp = u_water_wave.y;
    float freq = max(u_water_wave.z, 0.05);
    float t = u_water_wave.w;
    float chop = clamp(u_water_wind.z, 0.0, 1.2);
    vec2 w0 = (length(u_water_wind.xy) > 0.01) ? normalize(u_water_wind.xy) : vec2(0.8, 0.6);
    vec2 w1 = vec2(w0.x * 0.82 - w0.y * 0.57, w0.x * 0.57 + w0.y * 0.82);
    vec2 w2 = vec2(w0.x * 0.64 + w0.y * 0.77, -w0.x * 0.77 + w0.y * 0.64);
    vec2 w3 = vec2(-w0.y, w0.x);

    vec3 disp = vec3(0.0);
    vec3 d_dx = vec3(1.0, 0.0, 0.0);
    vec3 d_dz = vec3(0.0, 0.0, 1.0);
    float crest = 0.0;

    if (amp > 0.0005) {
        float c0 = sqrt(9.81 * freq);
        add_gerstner(xz, w0, amp * 0.50, freq * 1.00, chop * 0.45, c0 * 1.00, t, disp, d_dx, d_dz, crest);
        add_gerstner(xz, w1, amp * 0.26, freq * 1.73, chop * 0.40, c0 * 1.31, t, disp, d_dx, d_dz, crest);
        add_gerstner(xz, w2, amp * 0.15, freq * 2.85, chop * 0.35, c0 * 1.68, t, disp, d_dx, d_dz, crest);
        add_gerstner(xz, w3, amp * 0.09, freq * 4.30, chop * 0.28, c0 * 2.07, t, disp, d_dx, d_dz, crest);
    }

    vec4 wp = vec4(xz.x + disp.x, u_water_wave.x + disp.y, xz.y + disp.z, 1.0);
    v_world_pos = wp.xyz;
    v_norm = normalize(cross(d_dz, d_dx));
    v_uv = xz * 0.25;
    v_shadow_coord = u_light_vp * wp;
    v_crest = clamp(crest * 1.35, 0.0, 1.0);
    gl_Position = eng_snap_vertex(u_vp * wp, u_vertex_snap);
}
