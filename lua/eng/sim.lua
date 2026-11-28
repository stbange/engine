-- Systemic chemistry, thermodynamics, flora & biology helpers (eng.sim_ext / eng.sim helpers)
local M = {}

M.densities = {
    cork = 240, pine = 520, wood = 600, oil = 800, ice = 917,
    water = 1000, flesh = 1040, bone = 1850, stone = 2600, iron = 7800, lead = 11340,
}

function M.update_firelight(eng_root, light_id, t, pocket)
    local count, fx, fy, fz = eng_root.sim.active_fires(pocket)
    if count > 0 then
        local flick = 1.0 + 0.22 * math.sin(t * 17.3) + 0.14 * math.cos(t * 29.1)
        local boost = math.min(count, 8) * 0.45 * flick
        eng_root.render.set_light(light_id, {
            pos = { fx, fy + 0.75, fz },
            color = { 3.2 * boost, 1.45 * boost, 0.38 * boost },
            range = 7.0 + math.min(count, 10) * 1.1,
            pocket = pocket,
        })
    else
        eng_root.render.set_light(light_id, { color = { 0, 0, 0 }, range = 0.5 })
    end
    return count
end

function M.plant_scale_for_stage(stage, growth)
    local base = 0.20 + 0.80 * (growth or 0.1)
    if stage == "dead" then return base * 0.45 end
    if stage == "seeding" then return base * 1.15 end
    return base
end

return M
