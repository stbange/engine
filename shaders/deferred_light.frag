#include "shaders/common.glsl"

in vec2 v_uv;

uniform sampler2D u_gb_albedo_met;
uniform sampler2D u_gb_norm_rough;
uniform sampler2D u_gb_pos_ao;
uniform sampler2D u_shadow_tex;
uniform mat4 u_light_vp;
uniform vec3 u_cam_pos;
uniform vec3 u_ambient;
uniform vec3 u_sky_zenith;
uniform vec3 u_sky_horizon;
uniform vec3 u_sky_ground;
uniform vec4 u_fog;
uniform float u_fog_height;
uniform int u_light_count;
uniform vec4 u_light_pos_type[8];
uniform vec4 u_light_dir_range[8];
uniform vec4 u_light_color_cone[8];
uniform int u_has_shadow;

layout(location = 0) out vec4 o_color;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec4 pa = texelFetch(u_gb_pos_ao, px, 0);
    if (pa.w < 0.5) discard;
    vec4 am = texelFetch(u_gb_albedo_met, px, 0);
    vec4 nr = texelFetch(u_gb_norm_rough, px, 0);

    vec3 world_pos = pa.xyz;
    vec3 N = normalize(nr.xyz * 2.0 - 1.0);
    vec3 V = normalize(u_cam_pos - world_pos);
    vec3 albedo = am.rgb;
    float metallic = am.w;
    float roughness = nr.w;

    float sh = 1.0;
    if (u_has_shadow != 0) {
        vec4 sc = u_light_vp * vec4(world_pos, 1.0);
        vec3 proj = (sc.xyz / max(sc.w, 0.0001)) * 0.5 + 0.5;
        if (proj.x >= 0.0 && proj.x <= 1.0 && proj.y >= 0.0 && proj.y <= 1.0 && proj.z <= 1.0) {
            sh = (proj.z - 0.003 > texture(u_shadow_tex, proj.xy).r) ? 0.30 : 1.0;
        }
    }

    vec3 Lo = eng_env_ibl(N, V, albedo, metallic, roughness, u_sky_zenith, u_sky_horizon, u_sky_ground, u_ambient);
    for (int i = 0; i < 8; i++) {
        if (i >= u_light_count) break;
        float ltype = u_light_pos_type[i].w;
        vec3 L;
        float atten = 1.0;
        if (ltype < 0.5) {
            L = normalize(-u_light_dir_range[i].xyz);
            atten = sh;
        } else {
            vec3 to_l = u_light_pos_type[i].xyz - world_pos;
            float dist = length(to_l);
            L = to_l / max(dist, 0.0001);
            float fall = clamp(1.0 - (dist / max(u_light_dir_range[i].w, 0.1)), 0.0, 1.0);
            atten = fall * fall;
        }
        Lo += eng_pbr_eval(N, V, L, albedo, metallic, roughness, u_light_color_cone[i].rgb * atten);
    }

    float fog_f = eng_fog_factor(u_cam_pos, world_pos, u_fog.w, u_fog_height);
    o_color = vec4(mix(Lo, u_fog.rgb, fog_f), 1.0);
}
