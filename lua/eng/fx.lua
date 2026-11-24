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
    fire   = { dir = { 0, 1, 0 }, rate = 28, speed = 1.35, spread = 0.42, life = 0.65, gravity = { 0, 1.6, 0 }, drag = 0.35, size_start = 0.42, size_end = 0.08, color_start = { 1.0, 0.88, 0.32, 0.95 }, color_end = { 0.95, 0.14, 0.02, 0.0 }, additive = true },
    smoke  = { dir = { 0, 1, 0 }, rate = 12, speed = 0.85, spread = 0.35, life = 1.90, gravity = { 0, 0.45, 0 }, drag = 0.55, size_start = 0.32, size_end = 1.15, color_start = { 0.28, 0.28, 0.30, 0.45 }, color_end = { 0.18, 0.18, 0.22, 0.0 }, additive = false },
    sparks = { dir = { 0, 1, 0 }, rate = 18, speed = 2.60, spread = 0.85, life = 0.55, gravity = { 0, -4.5, 0 }, drag = 0.15, size_start = 0.14, size_end = 0.03, color_start = { 1.0, 0.94, 0.52, 1.0 }, color_end = { 1.0, 0.32, 0.04, 0.0 }, additive = true },
    dust   = { dir = { 0, 1, 0 }, rate = 10, speed = 0.35, spread = 1.40, life = 2.60, gravity = { 0, 0.05, 0 }, drag = 0.80, size_start = 0.12, size_end = 0.24, color_start = { 0.88, 0.84, 0.72, 0.30 }, color_end = { 0.88, 0.84, 0.72, 0.0 }, additive = false },
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

return M
