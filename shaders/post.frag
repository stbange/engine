#include "shaders/common.glsl"

in vec2 v_uv;

uniform sampler2D u_hdr_tex;
uniform sampler2D u_bloom_tex;
uniform sampler2D u_scene_depth_tex;
uniform sampler2D u_shadow_tex;

uniform vec3 u_inv_res;         /* xy = 1 / internal_res, z = sharp_upscale (0=linear, 1=sharp_pixel, 2=nearest) */
uniform vec4 u_fb_depth;        /* xy = internal_res, z = z_near, w = z_far */
uniform int u_pass_mode;        /* 0 = Kawase bloom downsample, 1 = Lens upscale + SSAO + VolFog + Underwater + Tonemap */
uniform float u_bloom_amt;
uniform int u_dither_bayer;
uniform float u_color_levels;
uniform float u_crt_scanline;

/* Realism post parameters */
uniform vec4 u_post_fx;         /* x = ssao_strength, y = volumetric_fog, z = has_depth_fx, w = time */
uniform mat4 u_inv_vp;
uniform mat4 u_light_vp;
uniform vec3 u_cam_pos;
uniform vec3 u_sun_to_sky;
uniform vec3 u_sun_color;
uniform vec4 u_fog;
uniform float u_fog_height;
uniform int u_has_shadow;
uniform int u_vol_light_count;
uniform vec4 u_vol_light_pos_r[4];
uniform vec4 u_vol_light_col[4];
uniform vec4 u_underwater;      /* x = active (0/1), y = submerge_depth, zw = unused */
uniform vec3 u_water_absorb;
uniform vec3 u_water_scatter;

layout(location = 0) out vec4 o_color;

vec3 aces_tonemap(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

/* Bandlimited sharp-bilinear / nearest low-res lens UV filter */
vec2 sample_lens_uv(vec2 uv) {
    if (u_inv_res.z < 0.5) return uv;
    vec2 res = max(u_fb_depth.xy, vec2(1.0));
    vec2 px = uv * res;
    vec2 fl = floor(px - 0.5) + 0.5;
    if (u_inv_res.z > 1.5) return fl / res;
    vec2 fr = px - fl;
    vec2 aa = fwidth(px);
    fr = clamp((fr - 0.5) / max(aa, vec2(0.001)) + 0.5, 0.0, 1.0);
    return (fl + fr) / res;
}

float compute_ssao(vec2 uv, float center_d, vec2 frag_xy) {
    if (center_d >= 0.9998) return 1.0;
    float cz = eng_linear_depth(center_d, u_fb_depth.z, u_fb_depth.w);
    float rad_px = clamp(5.5 / max(cz * 0.28, 0.6), 1.5, 9.0);
    float ang0 = eng_bayer4(frag_xy) * 6.2831853;
    float occ = 0.0;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float a = ang0 + fi * 0.7853982;
        float r = rad_px * (0.35 + 0.65 * ((fi + 0.5) / 8.0));
        vec2 suv = uv + vec2(cos(a), sin(a)) * r * u_inv_res.xy;
        float sd = texture(u_scene_depth_tex, suv).r;
        float sz = eng_linear_depth(sd, u_fb_depth.z, u_fb_depth.w);
        float dz = cz - sz;
        float range_chk = smoothstep(0.0, 1.0, 1.4 / (abs(dz) + 0.35));
        occ += ((dz > 0.025 && dz < 2.2) ? 1.0 : 0.0) * range_chk;
    }
    return clamp(1.0 - (occ / 8.0) * u_post_fx.x * 1.45, 0.18, 1.0);
}

vec3 compute_volumetric_fog(vec2 uv, float depth_buf, vec2 frag_xy) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth_buf * 2.0 - 1.0, 1.0);
    vec4 wp4 = u_inv_vp * clip;
    vec3 end_pos = wp4.xyz / max(wp4.w, 0.00001);
    vec3 ray = end_pos - u_cam_pos;
    float max_d = min(length(ray), 65.0);
    if (max_d < 0.15) return vec3(0.0);
    vec3 dir = ray / max(length(ray), 0.0001);

    float cos_t = clamp(dot(dir, u_sun_to_sky), -1.0, 1.0);
    float g = 0.72;
    float hg = (1.0 - g * g) / (4.0 * ENG_PI_GLSL * pow(max(1.0 + g * g - 2.0 * g * cos_t, 0.001), 1.5));
    float sun_phase = clamp(0.18 + hg * 1.85, 0.0, 2.8);

    float jitter = eng_bayer4(frag_xy);
    float step_len = max_d / 10.0;
    vec3 accum = vec3(0.0);
    float inv_h = (u_fog_height > 0.01) ? (1.0 / u_fog_height) : 0.0;

    for (int s = 0; s < 10; s++) {
        float dist = (float(s) + jitter) * step_len;
        vec3 p = u_cam_pos + dir * dist;
        float dens = (inv_h > 0.0) ? exp(-max(p.y, 0.0) * inv_h) : 1.0;

        float sh = 1.0;
        if (u_has_shadow != 0) {
            vec4 sc = u_light_vp * vec4(p, 1.0);
            vec3 pj = (sc.xyz / max(sc.w, 0.0001)) * 0.5 + 0.5;
            if (pj.x > 0.0 && pj.x < 1.0 && pj.y > 0.0 && pj.y < 1.0 && pj.z < 1.0) {
                sh = (pj.z - 0.0015 <= texture(u_shadow_tex, pj.xy).r) ? 1.0 : 0.0;
            }
        }
        vec3 step_rad = u_sun_color * (sh * sun_phase * 0.45);

        for (int li = 0; li < 4; li++) {
            if (li >= u_vol_light_count) break;
            vec3 to_l = u_vol_light_pos_r[li].xyz - p;
            float ld = length(to_l);
            float att = eng_light_atten(ld, u_vol_light_pos_r[li].w);
            step_rad += u_vol_light_col[li].rgb * (att * 0.28);
        }
        accum += step_rad * dens * step_len;
    }
    return accum * u_post_fx.y * max(u_fog.w * 2.5, 0.018);
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

    vec2 base_uv = v_uv;
    if (u_underwater.x > 0.5) {
        float wt = u_post_fx.w;
        base_uv += vec2(sin(v_uv.y * 18.0 + wt * 2.4), cos(v_uv.x * 16.0 + wt * 2.0)) * 0.0035;
        base_uv = clamp(base_uv, vec2(0.002), vec2(0.998));
    }

    vec2 lens_uv = sample_lens_uv(base_uv);
    vec2 low_px = floor(base_uv * max(u_fb_depth.xy, vec2(1.0)));

    vec3 hdr = texture(u_hdr_tex, lens_uv).rgb;
    float d_buf = (u_post_fx.z > 0.5) ? texture(u_scene_depth_tex, lens_uv).r : 1.0;

    if (u_post_fx.z > 0.5 && u_post_fx.x > 0.001) {
        hdr *= compute_ssao(lens_uv, d_buf, low_px);
    }
    if (u_post_fx.z > 0.5 && u_post_fx.y > 0.001) {
        hdr += compute_volumetric_fog(lens_uv, d_buf, low_px);
    }
    if (u_underwater.x > 0.5) {
        float wz = (u_post_fx.z > 0.5) ? min(eng_linear_depth(d_buf, u_fb_depth.z, u_fb_depth.w), 40.0) : 6.0;
        vec3 uw_tr = exp(-u_water_absorb * (wz * 0.65 + u_underwater.y * 0.5));
        vec3 uw_sc = u_water_scatter * (0.35 + 0.65 * exp(-u_underwater.y * 0.18));
        float vig = 1.0 - 0.28 * dot(v_uv - 0.5, v_uv - 0.5) * 2.0;
        hdr = (hdr * uw_tr + uw_sc * (vec3(1.0) - uw_tr)) * vig;
    }

    hdr += texture(u_bloom_tex, base_uv).rgb * u_bloom_amt;
    vec3 ldr = pow(max(aces_tonemap(hdr), vec3(0.0001)), vec3(1.0 / 2.2));

    if (u_color_levels > 1.0) {
        float d = (u_dither_bayer != 0) ? (eng_bayer4(low_px) - 0.5) / u_color_levels : 0.0;
        ldr = floor(clamp(ldr + d, 0.0, 1.0) * u_color_levels + 0.5) / u_color_levels;
    } else if (u_dither_bayer != 0) {
        /* Subtle 8-bit ordered dither in low-res pixel space eliminates HDR fog/shadow Mach banding */
        ldr = clamp(ldr + (eng_bayer4(low_px) - 0.5) / 192.0, 0.0, 1.0);
    }
    if (u_crt_scanline > 0.001) {
        float scan = 1.0 - u_crt_scanline * (0.5 + 0.5 * sin(gl_FragCoord.y * 3.14159265));
        ldr *= scan;
    }
    o_color = vec4(ldr, 1.0);
}
