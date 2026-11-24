/* Shared PBR + Retro 3D lighting helpers (GLSL 330 Core & GLSL ES 300) */
const float ENG_PI_GLSL = 3.14159265359;

float eng_bayer2(vec2 a) {
    a = floor(a);
    return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float eng_bayer4(vec2 a) {
    return eng_bayer2(0.5 * a) * 0.25 + eng_bayer2(a);
}

vec3 eng_pbr_eval(vec3 N, vec3 V, vec3 L, vec3 albedo, float metallic, float roughness, vec3 radiance) {
    vec3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.001);
    float NdotH = max(dot(N, H), 0.0);
    float HdotV = max(dot(H, V), 0.0);

    float r = clamp(roughness, 0.05, 1.0);
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

vec3 eng_env_ibl(vec3 N, vec3 V, vec3 albedo, float metallic, float roughness,
                 vec3 sky_z, vec3 sky_h, vec3 sky_g, vec3 amb) {
    float NdotV = max(dot(N, V), 0.001);
    vec3 R = reflect(-V, N);
    vec3 env_hi = mix(sky_h, sky_z, pow(clamp(R.y, 0.0001, 1.0), 0.6));
    vec3 env = mix(env_hi, sky_g, pow(clamp(-R.y, 0.0001, 1.0), 0.5));
    float sun_d = max(dot(R, normalize(vec3(0.4, 0.8, 0.4))), 0.0001);
    float shine = mix(48.0, 4.0, clamp(roughness, 0.0, 1.0));
    env += vec3(1.0, 0.94, 0.82) * pow(sun_d, shine) * max(1.2 - roughness, 0.0);
    vec3 avg_env = mix(sky_g, sky_h, 0.55);
    env = mix(env, avg_env, clamp(roughness * roughness, 0.0, 1.0));
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 F = F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(max(1.0 - NdotV, 0.0001), 5.0);
    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
    return kD * amb * albedo + F * env * (0.95 - 0.45 * roughness);
}

float eng_fog_factor(vec3 cam_pos, vec3 world_pos, float density, float fog_h) {
    float d = length(cam_pos - world_pos);
    float h_mul = (fog_h > 0.01) ? exp(-max(world_pos.y, 0.0) / fog_h) : 1.0;
    return clamp(1.0 - exp(-density * d * h_mul), 0.0, 1.0);
}

vec4 eng_snap_vertex(vec4 clip_pos, float snap_res) {
    if (snap_res > 1.0 && clip_pos.w > 0.001) {
        vec2 ndc = clip_pos.xy / clip_pos.w;
        ndc = floor(ndc * snap_res + 0.5) / snap_res;
        clip_pos.xy = ndc * clip_pos.w;
    }
    return clip_pos;
}
