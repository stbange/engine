#include "shaders/common.glsl"

in vec3 v_world_pos;
in vec3 v_norm;
in vec2 v_uv;
in vec4 v_color;

uniform sampler2D u_albedo_tex;
uniform sampler2D u_norm_rough_tex;
uniform vec4 u_tint;
uniform vec3 u_mat_mr;
uniform vec4 u_mat_extra; /* x = has_norm_map, y = wetness */

layout(location = 0) out vec4 o_gb_albedo_met;
layout(location = 1) out vec4 o_gb_norm_rough;
layout(location = 2) out vec4 o_gb_pos_ao;

void main() {
    vec4 tex = texture(u_albedo_tex, v_uv) * v_color * u_tint;
    if (tex.a < 0.1) discard;
    vec3 N = normalize(v_norm);
    vec3 albedo = tex.rgb;
    float metallic = u_mat_mr.x;
    float roughness = u_mat_mr.y;
    if (u_mat_extra.x > 0.5) {
        vec4 nr_map = texture(u_norm_rough_tex, v_uv);
        N = eng_perturb_normal(N, v_world_pos, v_uv, nr_map.xyz * 2.0 - 1.0, 0.85);
        roughness = clamp(mix(roughness, nr_map.w, 0.65), 0.045, 1.0);
    }
    eng_apply_wetness(albedo, roughness, metallic, u_mat_extra.y);
    o_gb_albedo_met = vec4(albedo, metallic);
    o_gb_norm_rough = vec4(N * 0.5 + 0.5, roughness);
    o_gb_pos_ao = vec4(v_world_pos, 1.0);
}
