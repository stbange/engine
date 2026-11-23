#include "shaders/common.glsl"

in vec2 v_uv;

uniform sampler2D u_hdr_tex;
uniform sampler2D u_bloom_tex;
uniform vec3 u_inv_res;
uniform int u_pass_mode;      /* 0 = Kawase bloom downsample/blur, 1 = Final tone-map + retro post */
uniform float u_bloom_amt;
uniform int u_dither_bayer;
uniform float u_color_levels; /* e.g., 31.0 for 5-bit PS1 RGB555, 0.0 = disabled */
uniform float u_crt_scanline;

layout(location = 0) out vec4 o_color;

vec3 aces_tonemap(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main() {
    if (u_pass_mode == 0) {
        /* 5-tap Dual-Kawase bloom filter + threshold */
        vec3 c = texture(u_hdr_tex, v_uv).rgb * 4.0;
        c += texture(u_hdr_tex, v_uv + vec2(-u_inv_res.x, -u_inv_res.y)).rgb;
        c += texture(u_hdr_tex, v_uv + vec2( u_inv_res.x, -u_inv_res.y)).rgb;
        c += texture(u_hdr_tex, v_uv + vec2(-u_inv_res.x,  u_inv_res.y)).rgb;
        c += texture(u_hdr_tex, v_uv + vec2( u_inv_res.x,  u_inv_res.y)).rgb;
        c *= (1.0 / 8.0);
        float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
        o_color = vec4(c * max(lum - 0.85, 0.0), 1.0);
        return;
    }

    vec3 hdr = texture(u_hdr_tex, v_uv).rgb + texture(u_bloom_tex, v_uv).rgb * u_bloom_amt;
    vec3 ldr = pow(aces_tonemap(hdr), vec3(1.0 / 2.2));

    if (u_color_levels > 1.0) {
        float d = (u_dither_bayer != 0) ? (eng_bayer4(gl_FragCoord.xy) - 0.5) / u_color_levels : 0.0;
        ldr = floor(clamp(ldr + d, 0.0, 1.0) * u_color_levels + 0.5) / u_color_levels;
    }
    if (u_crt_scanline > 0.001) {
        float scan = 1.0 - u_crt_scanline * (0.5 + 0.5 * sin(gl_FragCoord.y * 3.14159265));
        ldr *= scan;
    }
    o_color = vec4(ldr, 1.0);
}
