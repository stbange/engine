#include "shaders/common.glsl"

in vec3 v_world_pos;
in vec3 v_norm;
in vec2 v_uv;
in vec4 v_color;
in vec4 v_shadow_coord;

uniform sampler2D u_albedo_tex;
uniform sampler2D u_shadow_tex;
uniform vec4 u_tint;
uniform vec3 u_mat_mr; /* x = metallic, y = roughness */
uniform vec3 u_cam_pos;
uniform vec3 u_ambient;
uniform vec4 u_fog; /* rgb = color, w = density */

/* Up to 8 active lights per pocket: pos_type.w: 0=dir, 1=point, 2=spot */
uniform int u_light_count;
uniform vec4 u_light_pos_type[8];
uniform vec4 u_light_dir_range[8];
uniform vec4 u_light_color_cone[8];
uniform int u_has_shadow;

layout(location = 0) out vec4 o_color;

float sample_shadow(vec4 sc) {
    if (u_has_shadow == 0) return 1.0;
    vec3 proj = sc.xyz / max(sc.w, 0.0001);
    proj = proj * 0.5 + 0.5;
    if (proj.x < 0.0 || proj.x > 1.0 || proj.y < 0.0 || proj.y > 1.0 || proj.z > 1.0) {
        return 1.0;
    }
    float closest = texture(u_shadow_tex, proj.xy).r;
    return (proj.z - 0.003 > closest) ? 0.30 : 1.0;
}

void main() {
    vec4 tex = texture(u_albedo_tex, v_uv) * v_color * u_tint;
    if (tex.a < 0.1) discard;

    vec3 N = normalize(v_norm);
    vec3 V = normalize(u_cam_pos - v_world_pos);
    vec3 albedo = tex.rgb;
    float metallic = u_mat_mr.x;
    float roughness = u_mat_mr.y;

    vec3 Lo = u_ambient * albedo;
    float sh = sample_shadow(v_shadow_coord);

    for (int i = 0; i < 8; i++) {
        if (i >= u_light_count) break;
        float ltype = u_light_pos_type[i].w;
        vec3 L;
        float atten = 1.0;
        if (ltype < 0.5) {
            L = normalize(-u_light_dir_range[i].xyz);
            atten = sh;
        } else {
            vec3 to_l = u_light_pos_type[i].xyz - v_world_pos;
            float dist = length(to_l);
            float range = max(u_light_dir_range[i].w, 0.1);
            L = to_l / max(dist, 0.0001);
            float fall = clamp(1.0 - (dist / range), 0.0, 1.0);
            atten = fall * fall;
            if (ltype > 1.5) {
                float cos_ang = dot(-L, normalize(u_light_dir_range[i].xyz));
                atten *= smoothstep(u_light_color_cone[i].w, u_light_color_cone[i].w + 0.1, cos_ang);
            }
        }
        Lo += eng_pbr_eval(N, V, L, albedo, metallic, roughness, u_light_color_cone[i].rgb * atten);
    }

    float dist_cam = length(u_cam_pos - v_world_pos);
    float fog_f = 1.0 - exp(-u_fog.w * dist_cam);
    vec3 col = mix(Lo, u_fog.rgb, clamp(fog_f, 0.0, 1.0));
    o_color = vec4(col, tex.a);
}
