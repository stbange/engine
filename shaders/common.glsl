/* Shared PBR, Soft PCF Shadows, Normal/Wetness, Blackbody & Atmospheric Helpers (GLSL 330 Core & GLSL ES 300) */
const float ENG_PI_GLSL = 3.14159265359;

float eng_bayer2(vec2 a) {
    a = floor(a);
    return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float eng_bayer4(vec2 a) {
    return eng_bayer2(0.5 * a) * 0.25 + eng_bayer2(a);
}

float eng_linear_depth(float d_buf, float zn, float zf) {
    float z_ndc = d_buf * 2.0 - 1.0;
    return (2.0 * zn * zf) / max(zf + zn - z_ndc * (zf - zn), 0.0001);
}

/* Calibrated Planck blackbody linear HDR radiance for T in [700K .. 10000K] */
vec3 eng_blackbody(float temp_k) {
    float t = clamp(temp_k, 700.0, 10000.0) * 0.01;
    vec3 c;
    c.r = (t <= 66.0) ? 1.0 : clamp(1.292936 * pow(max(t - 60.0, 0.01), -0.133205), 0.0, 1.0);
    c.g = (t <= 66.0)
        ? clamp(0.390082 * log(max(t, 1.0)) - 0.631841, 0.0, 1.0)
        : clamp(1.129891 * pow(max(t - 60.0, 0.01), -0.075515), 0.0, 1.0);
    c.b = (t >= 66.0) ? 1.0 : ((t <= 19.0) ? 0.0 : clamp(0.543207 * log(max(t - 10.0, 1.0)) - 1.196254, 0.0, 1.0));
    /* Convert sRGB fit to linear HDR scaled by Stefan-Boltzmann perceptual glow */
    vec3 lin = pow(max(c, vec3(0.0001)), vec3(2.2));
    float glow = clamp((temp_k - 700.0) / 1400.0, 0.05, 3.2);
    return lin * glow;
}

/* Physical windowed inverse-square attenuation (no singularity at d=0, smooth 0 at d=range) */
float eng_light_atten(float dist, float range) {
    float R = max(range, 0.1);
    float q = clamp(dist / R, 0.0, 1.0);
    float q2 = q * q;
    float win = max(1.0 - q2 * q2, 0.0);
    win *= win;
    return win / (1.0 + 2.4 * (dist * dist) / max(R, 1.0));
}

/* Physical porous wetting: internal reflection darkens diffuse albedo while water film smooths roughness */
void eng_apply_wetness(inout vec3 albedo, inout float roughness, float metallic, float wetness) {
    float w = clamp(wetness, 0.0, 1.0);
    if (w > 0.001) {
        float porosity = (1.0 - metallic) * clamp(roughness * 1.15, 0.15, 1.0);
        albedo *= mix(1.0, 0.42, w * porosity);
        roughness = mix(roughness, 0.07, w * 0.88);
    }
}

#ifdef ENG_STAGE_FRAG
/* Derivative screen-space cotangent normal perturbation (zero vertex tangent buffer required) */
vec3 eng_perturb_normal(vec3 N, vec3 world_pos, vec2 uv, vec3 map_ts, float strength) {
    vec3 dp1 = dFdx(world_pos);
    vec3 dp2 = dFdy(world_pos);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);
    float uv_area = dot(duv1, duv1) + dot(duv2, duv2);
    if (uv_area < 1e-8 || dot(dp1, dp1) + dot(dp2, dp2) < 1e-10) return N;

    vec3 dp2perp = cross(dp2, N);
    vec3 dp1perp = cross(N, dp1);
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
    float invmax = inversesqrt(max(dot(T, T), dot(B, B)) + 1e-8);
    vec3 tsn = vec3(map_ts.xy * strength, max(map_ts.z, 0.1));
    return normalize(T * (tsn.x * invmax) + B * (tsn.y * invmax) + N * tsn.z);
}
#endif

/* Slope-scaled bias + 5-tap Bayer-rotated Poisson soft shadow PCF (0.0 in umbra, 1.0 lit) */
float eng_sample_shadow_pcf(sampler2D sh_tex, vec4 sc, vec3 N, vec3 L, vec2 frag_xy) {
    vec3 proj = (sc.xyz / max(sc.w, 0.0001)) * 0.5 + 0.5;
    if (proj.x <= 0.001 || proj.x >= 0.999 || proj.y <= 0.001 || proj.y >= 0.999 || proj.z > 1.0) {
        return 1.0;
    }
    float ndl = max(dot(N, L), 0.0);
    float bias = clamp(0.0022 * (1.0 - ndl), 0.00045, 0.004);
    vec2 texel = 1.45 / vec2(textureSize(sh_tex, 0));
    float ang = eng_bayer4(frag_xy) * 6.2831853;
    float cs = cos(ang), sn = sin(ang);
    mat2 rot = mat2(cs, -sn, sn, cs);

    float vis = (proj.z - bias <= texture(sh_tex, proj.xy).r) ? 1.0 : 0.0;
    vec2 o0 = rot * vec2(-0.70, -0.45) * texel;
    vec2 o1 = rot * vec2( 0.72, -0.42) * texel;
    vec2 o2 = rot * vec2(-0.38,  0.76) * texel;
    vec2 o3 = rot * vec2( 0.44,  0.70) * texel;
    vis += (proj.z - bias <= texture(sh_tex, proj.xy + o0).r) ? 1.0 : 0.0;
    vis += (proj.z - bias <= texture(sh_tex, proj.xy + o1).r) ? 1.0 : 0.0;
    vis += (proj.z - bias <= texture(sh_tex, proj.xy + o2).r) ? 1.0 : 0.0;
    vis += (proj.z - bias <= texture(sh_tex, proj.xy + o3).r) ? 1.0 : 0.0;
    return vis * 0.2;
}

vec3 eng_pbr_eval(vec3 N, vec3 V, vec3 L, vec3 albedo, float metallic, float roughness, vec3 radiance) {
    vec3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.001);
    float NdotH = max(dot(N, H), 0.0);
    float HdotV = max(dot(H, V), 0.0);

    float r = clamp(roughness, 0.045, 1.0);
    float a = r * r;
    float a2 = a * a;
    float denom = (NdotH * NdotH * (a2 - 1.0) + 1.0);
    float D = a2 / max(ENG_PI_GLSL * denom * denom, 0.0001);

    float k = ((r + 1.0) * (r + 1.0)) * 0.125;
    float Gv = NdotV / (NdotV * (1.0 - k) + k);
    float Gl = NdotL / (NdotL * (1.0 - k) + k);
    float G = Gv * Gl;

    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 F = F0 + (1.0 - F0) * pow(max(1.0 - HdotV, 0.0001), 5.0);

    vec3 spec = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);
    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
    return (kD * albedo / ENG_PI_GLSL + spec) * radiance * NdotL;
}

vec3 eng_env_ibl_sun(vec3 N, vec3 V, vec3 albedo, float metallic, float roughness,
                     vec3 sky_z, vec3 sky_h, vec3 sky_g, vec3 amb, vec3 to_sun, vec3 sun_col) {
    float NdotV = max(dot(N, V), 0.001);
    vec3 R = reflect(-V, N);
    vec3 env_hi = mix(sky_h, sky_z, pow(clamp(R.y, 0.0001, 1.0), 0.6));
    vec3 env = mix(env_hi, sky_g, pow(clamp(-R.y, 0.0001, 1.0), 0.5));
    float sun_d = max(dot(R, to_sun), 0.0001);
    float shine = mix(64.0, 4.0, clamp(roughness, 0.0, 1.0));
    env += sun_col * pow(sun_d, shine) * max(1.15 - roughness, 0.0) * 0.65;
    vec3 avg_env = mix(sky_g, sky_h, 0.55);
    env = mix(env, avg_env, clamp(roughness * roughness, 0.0, 1.0));
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 F = F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(max(1.0 - NdotV, 0.0001), 5.0);
    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
    return kD * amb * albedo + F * env * (0.95 - 0.45 * roughness);
}

vec3 eng_env_ibl(vec3 N, vec3 V, vec3 albedo, float metallic, float roughness,
                 vec3 sky_z, vec3 sky_h, vec3 sky_g, vec3 amb) {
    return eng_env_ibl_sun(N, V, albedo, metallic, roughness, sky_z, sky_h, sky_g, amb,
                           normalize(vec3(0.4, 0.8, 0.4)), vec3(1.0, 0.94, 0.82));
}

/* Closed-form line-integral exponential height fog + Henyey-Greenstein Mie sun in-scattering */
float eng_fog_factor(vec3 cam_pos, vec3 world_pos, float density, float fog_h) {
    vec3 ray = world_pos - cam_pos;
    float d = length(ray);
    if (density <= 0.00001 || d <= 0.001) return 0.0;
    if (fog_h <= 0.01) return clamp(1.0 - exp(-density * d), 0.0, 1.0);

    float inv_h = 1.0 / fog_h;
    float h0 = max(cam_pos.y, -20.0) * inv_h;
    float dh = ray.y * inv_h;
    float base = exp(-clamp(h0, -4.0, 20.0));
    float seg = (abs(dh) > 0.005) ? ((1.0 - exp(-clamp(dh, -20.0, 20.0))) / dh) : 1.0;
    float tau = density * d * base * max(seg, 0.0);
    return clamp(1.0 - exp(-tau), 0.0, 1.0);
}

vec3 eng_apply_mie_fog(vec3 surf_col, vec3 cam_pos, vec3 world_pos, vec4 fog_cd, float fog_h,
                       vec3 to_sun, vec3 sun_col, float mie_amt) {
    float f = eng_fog_factor(cam_pos, world_pos, fog_cd.w, fog_h);
    if (f <= 0.0001) return surf_col;
    vec3 view_dir = normalize(world_pos - cam_pos);
    float cos_t = clamp(dot(view_dir, to_sun), -1.0, 1.0);
    float g = 0.74;
    float hg = (1.0 - g * g) / (4.0 * ENG_PI_GLSL * pow(max(1.0 + g * g - 2.0 * g * cos_t, 0.001), 1.5));
    vec3 fog_rgb = fog_cd.rgb + sun_col * clamp(hg * mie_amt * 1.6, 0.0, 1.8);
    return mix(surf_col, fog_rgb, f);
}

vec4 eng_snap_vertex(vec4 clip_pos, float snap_res) {
    if (snap_res > 1.0 && clip_pos.w > 0.001) {
        vec2 ndc = clip_pos.xy / clip_pos.w;
        ndc = floor(ndc * snap_res + 0.5) / snap_res;
        clip_pos.xy = ndc * clip_pos.w;
    }
    return clip_pos;
}
