in vec3 v_ray_dir;

uniform vec3 u_sky_zenith;
uniform vec3 u_sky_horizon;
uniform vec3 u_sky_ground;
uniform vec3 u_sun_dir;
uniform vec3 u_sun_color;
uniform vec3 u_cloud_color;
uniform vec3 u_cam_pos;

/* x=sun_size, y=sun_glow, z=sun_banded, w=time */
uniform vec4 u_sun_params;
/* x=clouds, y=cloud_speed, z=cloud_scale, w=stars */
uniform vec4 u_sky_fx;
/* x=star_scale, y=pixel_snap, z=tex_mode (0=proc,1=equirect,2=cube), w=plx_count */
uniform vec4 u_sky_fx2;

uniform sampler2D u_sky_tex;
uniform samplerCube u_sky_cube;

/* Up to 4 retro parallax horizon layers */
uniform vec4 u_plx_p0[4];   /* style, parallax, move_parallax, scroll_speed */
uniform vec4 u_plx_p1[4];   /* height, offset, scale, fog_blend */
uniform vec4 u_plx_tint[4]; /* rgba */
uniform vec4 u_plx_acc[4];  /* accent.rgb, has_tex */
uniform sampler2D u_plx_tex0;
uniform sampler2D u_plx_tex1;
uniform sampler2D u_plx_tex2;
uniform sampler2D u_plx_tex3;

layout(location = 0) out vec4 o_color;

const float PI = 3.14159265;
const float TAU = 6.28318530;

float sky_hash1(float n) {
    return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float sky_hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float sky_noise1(float x) {
    float i = floor(x);
    float f = fract(x);
    float u = f * f * (3.0 - 2.0 * f);
    return mix(sky_hash1(i), sky_hash1(i + 1.0), u);
}

float sky_noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = sky_hash2(i);
    float b = sky_hash2(i + vec2(1.0, 0.0));
    float c = sky_hash2(i + vec2(0.0, 1.0));
    float d = sky_hash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float sky_fbm2(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * sky_noise2(p);
        p = p * 2.07 + vec2(17.3, 9.1);
        a *= 0.5;
    }
    return v;
}

vec4 sample_plx_tex(int idx, vec2 uv) {
    if (idx == 0) return texture(u_plx_tex0, uv);
    if (idx == 1) return texture(u_plx_tex1, uv);
    if (idx == 2) return texture(u_plx_tex2, uv);
    return texture(u_plx_tex3, uv);
}

void main() {
    vec3 d = normalize(v_ray_dir);
    float az = atan(d.x, -d.z);
    float el = asin(clamp(d.y, -1.0, 1.0));

    /* Optional retro spherical pixel quantization */
    float psnap = u_sky_fx2.y;
    if (psnap > 1.0) {
        float step_ang = PI / psnap;
        el = floor(el / step_ang + 0.5) * step_ang;
        az = floor(az / step_ang + 0.5) * step_ang;
        float ce = cos(el);
        d = normalize(vec3(sin(az) * ce, sin(el), -cos(az) * ce));
    }

    float time = u_sun_params.w;
    int tex_mode = int(u_sky_fx2.z + 0.5);

    /* 1. Base Sky (Procedural gradient, Equirectangular 2D panorama, or 6-face Cubemap) */
    vec3 sky;
    if (tex_mode == 2) {
        sky = texture(u_sky_cube, d).rgb;
    } else if (tex_mode == 1) {
        vec2 euv = vec2(az / TAU + 0.5, clamp(0.5 - el / PI, 0.001, 0.999));
        sky = texture(u_sky_tex, euv).rgb;
    } else {
        float up_t = clamp(d.y, 0.0001, 1.0);
        float dn_t = clamp(-d.y, 0.0001, 1.0);
        sky = mix(u_sky_horizon, u_sky_zenith, pow(up_t, 0.6));
        sky = mix(sky, u_sky_ground, pow(dn_t, 0.5));
    }

    /* 2. Twinkling Procedural Starfield */
    float stars_amt = u_sky_fx.w;
    if (stars_amt > 0.001 && d.y > 0.01) {
        float sc = max(u_sky_fx2.x, 20.0);
        vec2 sg = vec2(az / PI * sc, el / PI * sc);
        vec2 sid = floor(sg);
        vec2 sf = fract(sg) - 0.5;
        float h = sky_hash2(sid);
        if (h > 0.985) {
            float h2 = sky_hash2(sid + vec2(37.2, 11.9));
            float tw = 0.62 + 0.38 * sin(time * (1.8 + h2 * 4.2) + h * 90.0);
            float dist = length(sf);
            float pt = smoothstep(0.38, 0.05, dist) * smoothstep(0.01, 0.22, d.y);
            vec3 scol = mix(vec3(0.75, 0.86, 1.0), vec3(1.0, 0.92, 0.76), h2);
            sky += scol * pt * tw * stars_amt * 1.6;
        }
    }

    /* 3. Dynamic / Retro Banded Sun or Moon Disc + Glow */
    vec3 sdir = normalize(-u_sun_dir);
    float sdot = max(dot(d, sdir), 0.0001);
    float sun_glow = u_sun_params.y;
    if (sun_glow > 0.001) {
        sky += u_sun_color * pow(sdot, 96.0) * sun_glow;
    }
    float sun_size = u_sun_params.x;
    if (sun_size > 0.001) {
        float ang = acos(clamp(dot(d, sdir), -1.0, 1.0));
        float disc = 1.0 - smoothstep(sun_size * 0.86, sun_size, ang);
        if (disc > 0.001) {
            vec3 dcol = u_sun_color * 1.75;
            if (u_sun_params.z > 0.5) {
                float dy = clamp((d.y - sdir.y) / max(sun_size, 0.001), -1.0, 1.0);
                dcol = mix(vec3(1.0, 0.16, 0.52), u_sun_color * 1.9, clamp((dy + 0.85) * 0.6, 0.0, 1.0));
                if (dy < 0.18) {
                    float stripe = fract((dy + 1.0) * 5.5);
                    float cut = mix(0.46, 0.06, clamp((dy + 1.0) / 1.18, 0.0, 1.0));
                    disc *= step(cut, stripe);
                }
            }
            sky = mix(sky, dcol, disc);
        }
    }

    /* 4. Procedural Drifting Clouds */
    float cloud_amt = u_sky_fx.x;
    if (cloud_amt > 0.001 && d.y > 0.015) {
        vec2 cuv = d.xz / (d.y + 0.16) * max(u_sky_fx.z, 0.25)
                 + vec2(time * u_sky_fx.y, time * u_sky_fx.y * 0.35);
        float n = sky_fbm2(cuv);
        float mask = smoothstep(0.42, 0.72, n);
        if (psnap > 1.0) mask = floor(mask * 3.0 + 0.5) / 3.0;
        float hfade = smoothstep(0.015, 0.22, d.y);
        float lit = clamp(0.55 + 0.45 * pow(sdot, 3.0), 0.0, 1.0);
        vec3 ccol = mix(u_sky_horizon * 0.85, u_cloud_color, lit);
        sky = mix(sky, ccol, mask * hfade * cloud_amt);
    }

    /* 5. Retro Multi-Layer Parallax Horizon Bands (up to 4 layers, back-to-front) */
    int plx_count = int(u_sky_fx2.w + 0.5);
    if (plx_count > 0) {
        float az_n = az / TAU + 0.5;
        vec2 horiz_d = vec2(d.x, d.z);
        float hd_len = length(horiz_d);
        vec2 right_xz = (hd_len > 0.001) ? vec2(-horiz_d.y, horiz_d.x) / hd_len : vec2(1.0, 0.0);
        float lateral = dot(u_cam_pos.xz, right_xz) * 0.016;

        for (int i = 0; i < 4; i++) {
            if (i >= plx_count) break;
            int style = int(u_plx_p0[i].x + 0.5);
            if (style <= 0) continue;
            float p_yaw = u_plx_p0[i].y;
            float p_mov = u_plx_p0[i].z;
            float p_scr = u_plx_p0[i].w;
            float l_h   = max(u_plx_p1[i].x, 0.01);
            float l_off = u_plx_p1[i].y;
            float l_scl = max(u_plx_p1[i].z, 0.1);
            float l_fog = clamp(u_plx_p1[i].w, 0.0, 1.0);
            vec4 tint   = u_plx_tint[i];
            vec3 acc    = u_plx_acc[i].xyz;
            float u = (az_n * p_yaw + lateral * p_mov) * l_scl + time * p_scr;
            float vy = (el - l_off) / l_h;

            float alpha = 0.0;
            vec3 col = tint.rgb;
            float gfade = smoothstep(l_off - 0.12, l_off + 0.01, el);

            if (style == 1) {
                /* Custom panoramic alpha texture strip */
                if (vy >= 0.0 && vy <= 1.0) {
                    vec4 ts = sample_plx_tex(i, vec2(fract(u), 1.0 - vy));
                    col = ts.rgb * tint.rgb;
                    alpha = ts.a;
                }
            } else if (style == 2) {
                /* Organic jagged mountain peaks + snow caps (3 non-harmonic ridge octaves) */
                float r1 = 1.0 - abs(sky_noise1(u * 1.7 + 0.4) * 2.0 - 1.0);
                float r2 = 1.0 - abs(sky_noise1(u * 3.9 + 5.2) * 2.0 - 1.0);
                float r3 = 1.0 - abs(sky_noise1(u * 8.3 + 11.7) * 2.0 - 1.0);
                float h = clamp(0.14 + r1 * r1 * 0.56 + r2 * 0.24 + r3 * 0.12, 0.0, 1.0);
                if (vy <= h && gfade > 0.001) {
                    alpha = gfade;
                    float snow = smoothstep(h - 0.22, h - 0.04, vy) * step(0.46, h);
                    col = mix(tint.rgb, acc, snow * 0.85);
                }
            } else if (style == 3) {
                /* Rolling retro hills + sunlit crest */
                float h = 0.24 + 0.36 * sin(u * TAU * 0.85) * 0.5 + 0.42 * sky_noise1(u * 2.3 + 1.3);
                h = clamp(h, 0.08, 1.0);
                if (vy <= h && gfade > 0.001) {
                    alpha = gfade;
                    float rim = smoothstep(h - 0.14, h, vy);
                    col = mix(tint.rgb, acc, rim * 0.35);
                }
            } else if (style == 4) {
                /* Retro cyberpunk / synthwave city skyline with lit pixel windows */
                float bx = floor(u * 4.5);
                float bf = fract(u * 4.5);
                float bh = 0.18 + 0.78 * sky_hash1(bx * 1.37 + float(i) * 19.0);
                float gap = step(0.08, bf) * step(bf, 0.92);
                float h = bh * gap;
                if (vy <= h && gfade > 0.001) {
                    alpha = gfade;
                    if (vy > 0.04 && bf > 0.18 && bf < 0.82 && vy < h - 0.05) {
                        vec2 wcell = floor(vec2(bf * 8.0, vy * 14.0));
                        vec2 wf = fract(vec2(bf * 8.0, vy * 14.0));
                        float lit = step(0.62, sky_hash2(wcell + vec2(bx * 7.0, float(i) * 13.0)));
                        float box = step(0.24, wf.x) * step(wf.x, 0.76) * step(0.26, wf.y) * step(wf.y, 0.74);
                        col = mix(tint.rgb, acc, lit * box);
                    }
                }
            } else if (style == 5) {
                /* Jagged pine forest treeline */
                float base_h = 0.22 + 0.28 * sky_noise1(u * 2.0 + 3.1);
                float pine = (1.0 - abs(fract(u * 9.0) * 2.0 - 1.0)) * (0.25 + 0.25 * sky_hash1(floor(u * 9.0)));
                float h = clamp(base_h + pine, 0.0, 1.0);
                if (vy <= h && gfade > 0.001) {
                    alpha = gfade;
                    col = mix(tint.rgb, acc, smoothstep(h - 0.18, h, vy) * 0.25);
                }
            } else if (style == 6) {
                /* Sweeping desert dunes */
                float w1 = sin(u * TAU * 1.5);
                float w2 = cos(u * TAU * 3.0 + 1.1);
                float h = clamp(0.32 + 0.34 * (w1 * 0.6 + w2 * 0.4) + 0.18 * sky_noise1(u * 1.8), 0.06, 1.0);
                if (vy <= h && gfade > 0.001) {
                    alpha = gfade;
                    float slope = clamp(cos(u * TAU * 1.5) * 0.5 + 0.5, 0.0, 1.0);
                    col = mix(tint.rgb, acc, slope * smoothstep(h - 0.30, h, vy) * 0.55);
                }
            } else if (style == 7) {
                /* Floating retro cloud bank strip */
                if (vy >= 0.0 && vy <= 1.0) {
                    float top_h = 0.48 + 0.44 * sky_noise1(u * 3.5 + 2.1);
                    float bot_h = 0.08 + 0.16 * sky_noise1(u * 2.4 + 7.7);
                    float m = smoothstep(bot_h, bot_h + 0.18, vy) * (1.0 - smoothstep(top_h - 0.18, top_h, vy));
                    if (psnap > 1.0) m = floor(m * 3.0 + 0.5) / 3.0;
                    alpha = m;
                    col = mix(tint.rgb, acc, clamp((vy - bot_h) / max(top_h - bot_h, 0.05), 0.0, 1.0));
                }
            }

            if (alpha > 0.001) {
                vec3 lcol = mix(col, u_sky_horizon, l_fog);
                sky = mix(sky, lcol, alpha * tint.a);
            }
        }
    }

    o_color = vec4(sky, 1.0);
}
