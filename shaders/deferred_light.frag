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
uniform vec3 u_sun_to_sky;
uniform vec3 u_sun_color;
uniform vec4 u_fog;
uniform float u_fog_height;
uniform float u_fog_mie;
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

    vec4 sc = u_light_vp * vec4(world_pos, 1.0);
    vec3 Lo = eng_env_ibl_sun(N, V, albedo, metallic, roughness,
                              u_sky_zenith, u_sky_horizon, u_sky_ground, u_ambient,
                              u_sun_to_sky, u_sun_color);

    for (int i = 0; i < 8; i++) {
        if (i >= u_light_count) break;
        float ltype = u_light_pos_type[i].w;
        vec3 L;
        float atten = 1.0;
        if (ltype < 0.5) {
            L = normalize(-u_light_dir_range[i].xyz);
            atten = (u_has_shadow != 0) ? eng_sample_shadow_pcf(u_shadow_tex, sc, N, L, gl_FragCoord.xy) : 1.0;
        } else {
            vec3 to_l = u_light_pos_type[i].xyz - world_pos;
            float dist = length(to_l);
            L = to_l / max(dist, 0.0001);
            atten = eng_light_atten(dist, u_light_dir_range[i].w);
            if (ltype > 1.5) {
                float cos_ang = dot(-L, normalize(u_light_dir_range[i].xyz));
                atten *= smoothstep(u_light_color_cone[i].w, u_light_color_cone[i].w + 0.1, cos_ang);
            }
        }
        if (atten > 0.0005) {
            Lo += eng_pbr_eval(N, V, L, albedo, metallic, roughness, u_light_color_cone[i].rgb * atten);
        }
    }

    vec3 col = eng_apply_mie_fog(Lo, u_cam_pos, world_pos, u_fog, u_fog_height, u_sun_to_sky, u_sun_color, u_fog_mie);
    o_color = vec4(col, 1.0);
}
