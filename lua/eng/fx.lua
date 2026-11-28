-- Material & atmospheric particle presets (eng.fx)
local M = {}

M.materials = {
    gold     = { color = { 1.00, 0.78, 0.28, 1.0 }, metallic = 0.96, roughness = 0.18 },
    chrome   = { color = { 0.92, 0.94, 0.98, 1.0 }, metallic = 1.00, roughness = 0.06 },
    copper   = { color = { 0.95, 0.56, 0.36, 1.0 }, metallic = 0.94, roughness = 0.24 },
    obsidian = { color = { 0.08, 0.09, 0.13, 1.0 }, metallic = 0.12, roughness = 0.08 },
    crystal  = { color = { 0.42, 0.88, 1.00, 0.52 }, metallic = 0.05, roughness = 0.06, emissive = { 0.18, 0.55, 0.85 }, cast_shadow = false },
    ruby     = { color = { 0.96, 0.16, 0.26, 0.58 }, metallic = 0.05, roughness = 0.07, emissive = { 0.72, 0.08, 0.16 }, cast_shadow = false },
    emerald  = { color = { 0.18, 0.92, 0.48, 0.56 }, metallic = 0.05, roughness = 0.07, emissive = { 0.10, 0.62, 0.26 }, cast_shadow = false },
    ice      = { color = { 0.74, 0.92, 1.00, 0.62 }, metallic = 0.00, roughness = 0.10, emissive = { 0.08, 0.16, 0.24 }, cast_shadow = false },
    glass    = { color = { 0.88, 0.96, 1.00, 0.32 }, metallic = 0.00, roughness = 0.05, cast_shadow = false },
    lava     = { color = { 1.00, 0.28, 0.04, 1.0 }, metallic = 0.00, roughness = 0.65, emissive = { 2.40, 0.65, 0.08 } },
}

M.emitters = {
    fire   = { dir = { 0, 1, 0 }, rate = 34, speed = 1.45, spread = 0.36, life = 0.85, gravity = { 0, 1.8, 0 }, drag = 0.45, size_start = 0.36, size_end = 0.58, color_start = { 1.0, 0.92, 0.65, 0.95 }, color_end = { 0.14, 0.12, 0.12, 0.0 }, additive = true, blackbody = true, temp_start = 3400, temp_end = 520, turbulence = 2.4 },
    smoke  = { dir = { 0, 1, 0 }, rate = 12, speed = 0.85, spread = 0.35, life = 1.90, gravity = { 0, 0.45, 0 }, drag = 0.55, size_start = 0.32, size_end = 1.15, color_start = { 0.28, 0.28, 0.30, 0.45 }, color_end = { 0.18, 0.18, 0.22, 0.0 }, additive = false, turbulence = 1.1 },
    sparks = { dir = { 0, 1, 0 }, rate = 18, speed = 2.60, spread = 0.85, life = 0.55, gravity = { 0, -4.5, 0 }, drag = 0.15, size_start = 0.14, size_end = 0.03, color_start = { 1.0, 0.94, 0.52, 1.0 }, color_end = { 1.0, 0.32, 0.04, 0.0 }, additive = true, blackbody = true, temp_start = 3600, temp_end = 1400, turbulence = 1.6 },
    dust   = { dir = { 0, 1, 0 }, rate = 10, speed = 0.35, spread = 1.40, life = 2.60, gravity = { 0, 0.05, 0 }, drag = 0.80, size_start = 0.12, size_end = 0.24, color_start = { 0.88, 0.84, 0.72, 0.30 }, color_end = { 0.88, 0.84, 0.72, 0.0 }, additive = false, turbulence = 0.5 },
}

M.waters = {
    coastal_clear = { enabled = true, level = 0.0, wave_amp = 0.14, wave_freq = 0.65, choppiness = 0.55, wave_speed = 1.15, absorption = { 0.42, 0.09, 0.04 }, scatter = { 0.02, 0.14, 0.18 }, foam_width = 0.55, refraction = 0.035, caustics = 0.40 },
    alpine_river  = { enabled = true, level = 0.0, wave_amp = 0.07, wave_freq = 1.10, choppiness = 0.45, wave_speed = 1.65, absorption = { 0.36, 0.10, 0.05 }, scatter = { 0.02, 0.12, 0.15 }, foam_width = 0.45, refraction = 0.030, caustics = 0.45, flow = { 1.2, 0.0 } },
    murky_swamp   = { enabled = true, level = 0.0, wave_amp = 0.03, wave_freq = 0.80, choppiness = 0.20, wave_speed = 0.55, absorption = { 0.85, 0.62, 0.95 }, scatter = { 0.05, 0.09, 0.03 }, foam_width = 0.20, refraction = 0.018, caustics = 0.05 },
}

M.skies = {
    alpine_day = {
        reset = true,
        zenith = { 0.10, 0.34, 0.78 }, horizon = { 0.62, 0.80, 0.96 }, ground = { 0.18, 0.22, 0.16 },
        sun_color = { 1.00, 0.95, 0.80 }, sun_size = 0.055, sun_glow = 1.4,
        clouds = 0.62, cloud_speed = 0.035, cloud_scale = 2.2, cloud_color = { 1.0, 0.99, 0.97 },
        parallax = {
            { style = "clouds",    parallax = 0.30, move_parallax = 0.10, scroll_speed = 0.015, height = 0.24, offset = 0.18, scale = 1.6, tint = { 0.86, 0.92, 0.99, 0.65 }, accent = { 1.00, 1.00, 1.00 }, fog_blend = 0.32 },
            { style = "mountains", parallax = 0.55, move_parallax = 0.25, height = 0.38, offset = 0.00, scale = 1.5, tint = { 0.20, 0.28, 0.44, 1.0 }, accent = { 0.96, 0.98, 1.00 }, fog_blend = 0.36 },
            { style = "trees",     parallax = 0.95, move_parallax = 0.70, height = 0.16, offset = -0.02, scale = 2.6, tint = { 0.10, 0.24, 0.16, 1.0 }, accent = { 0.22, 0.42, 0.26 }, fog_blend = 0.16 },
        },
    },
    sunset_mountains = {
        reset = true,
        zenith = { 0.12, 0.10, 0.30 }, horizon = { 0.98, 0.48, 0.24 }, ground = { 0.14, 0.08, 0.12 },
        sun_dir = { 0.15, -0.26, 0.95 }, sun_color = { 1.00, 0.72, 0.28 }, sun_size = 0.09, sun_glow = 1.8,
        clouds = 0.45, cloud_speed = 0.025, cloud_scale = 2.0, cloud_color = { 1.0, 0.68, 0.46 },
        stars = 0.25, star_scale = 140.0,
        parallax = {
            { style = "mountains", parallax = 0.45, move_parallax = 0.20, height = 0.36, offset = -0.01, scale = 1.5, tint = { 0.34, 0.18, 0.34, 1.0 }, accent = { 0.98, 0.58, 0.34 }, fog_blend = 0.42 },
            { style = "hills",     parallax = 0.75, move_parallax = 0.48, height = 0.22, offset = -0.02, scale = 2.1, tint = { 0.20, 0.10, 0.24, 1.0 }, accent = { 0.62, 0.26, 0.30 }, fog_blend = 0.22 },
            { style = "trees",     parallax = 1.10, move_parallax = 0.85, height = 0.12, offset = -0.02, scale = 3.2, tint = { 0.09, 0.05, 0.12, 1.0 }, accent = { 0.28, 0.12, 0.22 }, fog_blend = 0.06 },
        },
    },
    synthwave_city = {
        reset = true,
        zenith = { 0.05, 0.02, 0.16 }, horizon = { 0.88, 0.16, 0.56 }, ground = { 0.06, 0.02, 0.12 },
        sun_dir = { 0.0, -0.22, 0.97 }, sun_color = { 1.00, 0.82, 0.22 }, sun_size = 0.13, sun_glow = 1.6, sun_banded = true,
        stars = 0.95, star_scale = 160.0, pixel_snap = 180.0,
        parallax = {
            { style = "mountains", parallax = 0.45, move_parallax = 0.22, height = 0.24, offset = -0.01, scale = 1.6, tint = { 0.16, 0.05, 0.28, 1.0 }, accent = { 0.98, 0.22, 0.72 }, fog_blend = 0.28 },
            { style = "city",      parallax = 0.75, move_parallax = 0.52, height = 0.22, offset = -0.02, scale = 2.2, tint = { 0.09, 0.04, 0.18, 1.0 }, accent = { 0.24, 0.92, 1.00 }, fog_blend = 0.15 },
            { style = "city",      parallax = 1.15, move_parallax = 0.92, height = 0.14, offset = -0.03, scale = 3.2, tint = { 0.04, 0.02, 0.10, 1.0 }, accent = { 1.00, 0.34, 0.82 }, fog_blend = 0.05 },
        },
    },
    starry_night = {
        reset = true,
        zenith = { 0.02, 0.04, 0.11 }, horizon = { 0.08, 0.14, 0.26 }, ground = { 0.03, 0.04, 0.07 },
        sun_dir = { -0.35, -0.58, 0.73 }, sun_color = { 0.82, 0.90, 1.00 }, sun_size = 0.05, sun_glow = 0.65,
        stars = 1.0, star_scale = 180.0,
        parallax = {
            { style = "mountains", parallax = 0.50, move_parallax = 0.22, height = 0.26, offset = -0.02, scale = 1.5, tint = { 0.05, 0.08, 0.16, 1.0 }, accent = { 0.32, 0.44, 0.64 }, fog_blend = 0.35 },
            { style = "trees",     parallax = 0.95, move_parallax = 0.68, height = 0.14, offset = -0.03, scale = 2.8, tint = { 0.02, 0.04, 0.08, 1.0 }, accent = { 0.10, 0.16, 0.24 }, fog_blend = 0.12 },
        },
    },
    overcast_forest = {
        reset = true,
        zenith = { 0.26, 0.32, 0.38 }, horizon = { 0.56, 0.62, 0.66 }, ground = { 0.14, 0.16, 0.14 },
        sun_color = { 0.88, 0.92, 0.96 }, sun_size = 0.0, sun_glow = 0.35,
        clouds = 0.88, cloud_speed = 0.05, cloud_scale = 1.9, cloud_color = { 0.76, 0.80, 0.84 },
        parallax = {
            { style = "hills", parallax = 0.50, move_parallax = 0.22, height = 0.22, offset = -0.02, scale = 1.6, tint = { 0.24, 0.30, 0.32, 1.0 }, accent = { 0.46, 0.52, 0.56 }, fog_blend = 0.58 },
            { style = "trees", parallax = 0.85, move_parallax = 0.55, height = 0.17, offset = -0.03, scale = 2.4, tint = { 0.14, 0.22, 0.20, 1.0 }, accent = { 0.28, 0.38, 0.36 }, fog_blend = 0.34 },
            { style = "trees", parallax = 1.15, move_parallax = 0.85, height = 0.12, offset = -0.03, scale = 3.4, tint = { 0.08, 0.14, 0.12, 1.0 }, accent = { 0.16, 0.24, 0.22 }, fog_blend = 0.14 },
        },
    },
    mars_dunes = {
        reset = true,
        zenith = { 0.42, 0.20, 0.12 }, horizon = { 0.88, 0.52, 0.30 }, ground = { 0.30, 0.14, 0.08 },
        sun_dir = { -0.40, -0.45, 0.80 }, sun_color = { 1.00, 0.88, 0.72 }, sun_size = 0.045, sun_glow = 1.2,
        clouds = 0.28, cloud_speed = 0.06, cloud_scale = 2.8, cloud_color = { 0.94, 0.68, 0.48 },
        parallax = {
            { style = "dunes", parallax = 0.45, move_parallax = 0.20, height = 0.24, offset = -0.02, scale = 1.4, tint = { 0.56, 0.26, 0.14, 1.0 }, accent = { 0.92, 0.58, 0.34 }, fog_blend = 0.50 },
            { style = "dunes", parallax = 0.80, move_parallax = 0.52, height = 0.17, offset = -0.03, scale = 2.1, tint = { 0.44, 0.19, 0.10, 1.0 }, accent = { 0.82, 0.44, 0.24 }, fog_blend = 0.28 },
            { style = "dunes", parallax = 1.15, move_parallax = 0.88, height = 0.11, offset = -0.03, scale = 3.0, tint = { 0.32, 0.13, 0.07, 1.0 }, accent = { 0.66, 0.32, 0.16 }, fog_blend = 0.10 },
        },
    },
}

local function copy_merge(base, overrides)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    if overrides then
        for k, v in pairs(overrides) do out[k] = v end
    end
    return out
end

function M.material(name, overrides)
    local preset = M.materials[name] or M.materials.crystal
    return copy_merge(preset, overrides)
end

function M.spawn(eng_root, preset, x, y, z, pocket, opts)
    local cfg = copy_merge(M.emitters[preset] or M.emitters.fire, opts)
    cfg.pos = { x or 0, y or 0, z or 0 }
    if pocket then cfg.pocket = pocket end
    return eng_root.particles.create(cfg)
end

function M.sky(eng_root, name, overrides)
    local cfg = copy_merge(M.skies[name] or M.skies.alpine_day, overrides)
    eng_root.render.set_sky_fx(cfg)
    return cfg
end

function M.water(eng_root, name, overrides)
    local cfg = copy_merge(M.waters[name] or M.waters.coastal_clear, overrides)
    eng_root.render.set_water(cfg)
    return cfg
end

return M
