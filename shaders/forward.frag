#include "shaders/common.glsl"

in vec3 v_world_pos;
in vec3 v_norm;
in vec2 v_uv;
in vec4 v_color;
in vec4 v_shadow_coord;

uniform sampler2D u_albedo_tex;
uniform sampler2D u_shadow_tex;
uniform sampler2D u_norm_rough_tex;
uniform sampler2D u_scene_depth_tex;
uniform vec4 u_tint;
uniform vec3 u_mat_mr;     /* x = metallic, y = roughness, z = mode (0=opaque, 1=translucent Fresnel, -1=unlit/additive FX) */
uniform vec4 u_mat_extra;  /* x = has_norm_map, y = wetness, z = soft_particle_radius, w = has_scene_snap */
uniform vec4 u_fb_depth;   /* xy = inv_fb_size, z = z_near, w = z_far */
uniform vec3 u_emissive;   /* linear HDR emissive RGB */
uniform vec3 u_cam_pos;
uniform vec3 u_ambient;
uniform vec3 u_sky_zenith;
uniform vec3 u_sky_horizon;
uniform vec3 u_sky_ground;
uniform vec3 u_sun_to_sky; /* unit vector toward sun */
uniform vec3 u_sun_color;
uniform vec4 u_fog;        /* rgb = color, w = density */
uniform float u_fog_height;
uniform float u_fog_mie;

/* Up to 8 active lights per pocket: pos_type.w: 0=dir, 1=point, 2=spot */
uniform int u_light_count;
uniform vec4 u_light_pos_type[8];
uniform vec4 u_light_dir_range[8];
uniform vec4 u_light_color_cone[8];
uniform int u_has_shadow;

layout(location = 0) out vec4 o_color;

void main() {
    vec4 tex = texture(u_albedo_tex, v_uv) * v_color * u_tint;
    float alpha_cut = (abs(u_mat_mr.z) > 0.1) ? 0.005 : 0.1;
    if (tex.a < alpha_cut) discard;

    /* Soft depth-fade against scene depth snapshot (eliminates hard fire/smoke/mist clipping) */
    float soft_fade = 1.0;
    if (u_mat_extra.z > 0.005 && u_mat_extra.w > 0.5) {
        vec2 suv = gl_FragCoord.xy * u_fb_depth.xy;
        float sd_buf = texture(u_scene_depth_tex, suv).r;
        float scene_z = eng_linear_depth(sd_buf, u_fb_depth.z, u_fb_depth.w);
        float frag_z = eng_linear_depth(gl_FragCoord.z, u_fb_depth.z, u_fb_depth.w);
        soft_fade = clamp((scene_z - frag_z) / u_mat_extra.z, 0.0, 1.0);
        if (soft_fade < 0.005) discard;
    }

    if (u_mat_mr.z < -0.5) {
        /* Self-emissive / blackbody flame / spark particle */
        float fog_f = eng_fog_factor(u_cam_pos, v_world_pos, u_fog.w, u_fog_height);
        vec3 fx_col = tex.rgb * (1.0 + u_emissive.r) * (1.0 - fog_f);
        o_color = vec4(fx_col * soft_fade, tex.a * soft_fade);
        return;
    }

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

    vec3 V = normalize(u_cam_pos - v_world_pos);
    vec3 Lo = eng_env_ibl_sun(N, V, albedo, metallic, roughness,
                              u_sky_zenith, u_sky_horizon, u_sky_ground, u_ambient,
                              u_sun_to_sky, u_sun_color) + u_emissive;

    for (int i = 0; i < 8; i++) {
        if (i >= u_light_count) break;
        float ltype = u_light_pos_type[i].w;
        vec3 L;
        float atten = 1.0;
        if (ltype < 0.5) {
            L = normalize(-u_light_dir_range[i].xyz);
            atten = (u_has_shadow != 0) ? eng_sample_shadow_pcf(u_shadow_tex, v_shadow_coord, N, L, gl_FragCoord.xy) : 1.0;
        } else {
            vec3 to_l = u_light_pos_type[i].xyz - v_world_pos;
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

    float out_a = tex.a * soft_fade;
    if (u_mat_mr.z > 0.5) {
        /* Translucent crystal/glass Fresnel rim & sky-glint */
        float rim = pow(max(1.0 - max(dot(N, V), 0.0), 0.0001), 2.8);
        Lo += mix(u_sky_horizon, u_sun_color, 0.35) * rim * max(0.75 - 0.40 * roughness, 0.10);
        out_a = clamp(out_a + rim * 0.45 * soft_fade, 0.0, 1.0);
    }

    vec3 col = eng_apply_mie_fog(Lo, u_cam_pos, v_world_pos, u_fog, u_fog_height, u_sun_to_sky, u_sun_color, u_fog_mie);
    o_color = vec4(col, out_a);
}
