#include "shaders/common.glsl"

in vec3 v_world_pos;
in vec3 v_norm;
in vec2 v_uv;
in vec4 v_shadow_coord;
in float v_crest;

uniform sampler2D u_scene_color_tex;
uniform sampler2D u_scene_depth_tex;
uniform sampler2D u_shadow_tex;

uniform vec4 u_fb_depth;      /* xy = inv_fb_size, z = z_near, w = z_far */
uniform vec4 u_water_wave;    /* x = level_y, y = amp, z = freq, w = time */
uniform vec4 u_water_wind;    /* xy = wind_dir, z = choppiness, w = flow_speed */
uniform vec3 u_water_absorb;  /* Beer-Lambert RGB extinction per meter, e.g. (0.42, 0.09, 0.04) */
uniform vec3 u_water_scatter; /* Deep water multiple-scattering RGB tint */
uniform vec4 u_water_opt;     /* x = roughness, y = foam_width, z = refract_strength, w = caustics_strength */

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
uniform int u_has_shadow;
uniform int u_has_scene_snap;

layout(location = 0) out vec4 o_color;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float caustics_pattern(vec2 p, float t) {
    vec2 uv1 = p * 1.9 + vec2(t * 0.45, -t * 0.32);
    vec2 uv2 = p * 2.3 - vec2(t * 0.38, t * 0.51);
    float n1 = abs(vnoise(uv1) * 2.0 - 1.0);
    float n2 = abs(vnoise(uv2) * 2.0 - 1.0);
    return pow(max(1.0 - min(n1, n2), 0.001), 5.0);
}

void main() {
    float t = u_water_wave.w;
    vec2 flow = normalize(length(u_water_wind.xy) > 0.01 ? u_water_wind.xy : vec2(0.8, 0.6)) * u_water_wind.w;

    /* Dual-layer capillary micro-ripples */
    vec2 ruv1 = v_world_pos.xz * 1.65 - flow * t * 0.9;
    vec2 ruv2 = v_world_pos.xz * 3.10 + vec2(flow.y, -flow.x) * t * 0.65;
    float h0 = vnoise(ruv1) + 0.5 * vnoise(ruv2);
    float hx = vnoise(ruv1 + vec2(0.08, 0.0)) + 0.5 * vnoise(ruv2 + vec2(0.08, 0.0));
    float hz = vnoise(ruv1 + vec2(0.0, 0.08)) + 0.5 * vnoise(ruv2 + vec2(0.0, 0.08));
    vec3 ripple = vec3((h0 - hx) * 1.8, 1.0, (h0 - hz) * 1.8);
    vec3 N = normalize(v_norm + vec3(ripple.x, 0.0, ripple.z) * 0.24);
    if (u_cam_pos.y < v_world_pos.y) N = -N;

    vec3 V = normalize(u_cam_pos - v_world_pos);
    float NdotV = max(dot(N, V), 0.002);

    float sh = (u_has_shadow != 0) ? eng_sample_shadow_pcf(u_shadow_tex, v_shadow_coord, vec3(0.0, 1.0, 0.0), u_sun_to_sky, gl_FragCoord.xy) : 1.0;

    vec2 suv = gl_FragCoord.xy * u_fb_depth.xy;
    float frag_z = eng_linear_depth(gl_FragCoord.z, u_fb_depth.z, u_fb_depth.w);
    float water_depth = 2.5;
    vec3 refr_bed = u_water_scatter * (u_ambient + u_sun_color * 0.35 * sh);

    if (u_has_scene_snap != 0) {
        float raw_sd = texture(u_scene_depth_tex, suv).r;
        float scene_z = eng_linear_depth(raw_sd, u_fb_depth.z, u_fb_depth.w);
        water_depth = max(scene_z - frag_z, 0.0);

        vec2 refr_off = N.xz * u_water_opt.z * clamp(water_depth * 0.55, 0.0, 1.0) / max(frag_z * 0.25, 1.0);
        vec2 ruv = clamp(suv + refr_off, vec2(0.002), vec2(0.998));
        float r_sd = texture(u_scene_depth_tex, ruv).r;
        float r_z = eng_linear_depth(r_sd, u_fb_depth.z, u_fb_depth.w);
        if (r_z < frag_z) {
            ruv = suv;
        } else {
            water_depth = max(r_z - frag_z, 0.0);
        }
        refr_bed = texture(u_scene_color_tex, ruv).rgb;
    }

    /* Beer-Lambert spectral absorption + shallow underwater caustics + volume scatter */
    float optical_path = water_depth / max(abs(V.y), 0.22);
    vec3 transmittance = exp(-u_water_absorb * optical_path);

    if (u_water_opt.w > 0.001 && water_depth < 8.0) {
        float caust = caustics_pattern(v_world_pos.xz - u_sun_to_sky.xz * water_depth * 0.4, t);
        float c_fade = exp(-water_depth * 0.45) * clamp(water_depth * 2.5, 0.0, 1.0);
        refr_bed += u_sun_color * caust * u_water_opt.w * c_fade * sh;
    }

    vec3 scatter_rad = u_water_scatter * (u_ambient * 1.1 + u_sun_color * max(u_sun_to_sky.y, 0.06) * (0.35 + 0.65 * sh));
    vec3 sub_col = refr_bed * transmittance + scatter_rad * (vec3(1.0) - transmittance);

    /* Schlick Fresnel (water IOR 1.333 -> F0 = 0.02) + sky reflection + GGX sun glitter */
    float F = 0.02 + 0.98 * pow(max(1.0 - NdotV, 0.0001), 5.0);
    vec3 R = reflect(-V, N);
    vec3 sky_refl = mix(u_sky_horizon, u_sky_zenith, pow(clamp(R.y, 0.0001, 1.0), 0.65));

    vec3 H = normalize(V + u_sun_to_sky);
    float r = clamp(u_water_opt.x, 0.03, 0.5);
    float a2 = r * r * r * r;
    float nh = max(dot(N, H), 0.0);
    float denom = nh * nh * (a2 - 1.0) + 1.0;
    float D = a2 / max(ENG_PI_GLSL * denom * denom, 0.0001);
    vec3 sun_spec = u_sun_color * min(D * 0.22, 12.0) * max(dot(N, u_sun_to_sky), 0.0) * sh;

    vec3 col = mix(sub_col, sky_refl, F) + sun_spec;

    /* Frothy shoreline contact foam & steep Gerstner whitecaps */
    float f_noise = vnoise(v_world_pos.xz * 3.8 + flow * t * 1.2) * 0.55 + 0.45;
    float shore_foam = (u_water_opt.y > 0.001)
        ? smoothstep(u_water_opt.y, 0.0, water_depth) * smoothstep(0.28, 0.72, f_noise + (1.0 - water_depth / max(u_water_opt.y, 0.01)) * 0.35)
        : 0.0;
    float crest_foam = smoothstep(0.38, 0.85, v_crest * f_noise * 1.35);
    float foam = clamp(max(shore_foam, crest_foam), 0.0, 1.0);
    vec3 foam_col = (u_ambient + u_sun_color * (0.25 + 0.75 * sh)) * 0.88;
    col = mix(col, foam_col, foam * 0.85);

    /* Ultra-shallow meniscus feather (0..3cm) so water edge never stair-steps harshly on gentle slopes */
    float edge_alpha = (u_has_scene_snap != 0) ? clamp(water_depth / 0.03 + F + foam, 0.0, 1.0) : 0.88;
    col = eng_apply_mie_fog(col, u_cam_pos, v_world_pos, u_fog, u_fog_height, u_sun_to_sky, u_sun_color, u_fog_mie);
    o_color = vec4(col, edge_alpha);
}
