in vec3 v_ray_dir;

uniform vec3 u_sky_zenith;
uniform vec3 u_sky_horizon;
uniform vec3 u_sky_ground;
uniform vec3 u_sun_dir;

layout(location = 0) out vec4 o_color;

void main() {
    vec3 d = normalize(v_ray_dir);
    float up_t = clamp(d.y, 0.0, 1.0);
    float dn_t = clamp(-d.y, 0.0, 1.0);
    vec3 sky = mix(u_sky_horizon, u_sky_zenith, pow(up_t, 0.6));
    sky = mix(sky, u_sky_ground, pow(dn_t, 0.5));
    float sun = max(dot(d, normalize(-u_sun_dir)), 0.0);
    sky += vec3(1.0, 0.92, 0.72) * pow(sun, 128.0) * 1.5;
    o_color = vec4(sky, 1.0);
}
