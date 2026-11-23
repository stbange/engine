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
    vec3 F = F0 + (1.0 - F0) * pow(1.0 - HdotV, 5.0);

    vec3 spec = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);
    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
    return (kD * albedo / ENG_PI_GLSL + spec) * radiance * NdotL;
}

vec4 eng_snap_vertex(vec4 clip_pos, float snap_res) {
    if (snap_res > 1.0 && clip_pos.w > 0.001) {
        vec2 ndc = clip_pos.xy / clip_pos.w;
        ndc = floor(ndc * snap_res + 0.5) / snap_res;
        clip_pos.xy = ndc * clip_pos.w;
    }
    return clip_pos;
}
