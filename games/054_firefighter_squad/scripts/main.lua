-- 054_firefighter_squad: Cellular-automata voxel flames & pressurized water cannon rescue
local S = game.state

local GRID_N = 8
local CELL_SZ = 2.6

local function cell_world(gx, gz)
    return (gx - 4.5) * CELL_SZ, (gz - 4.5) * CELL_SZ
end

local function cell_idx(gx, gz)
    return (gz - 1) * GRID_N + gx
end

local function ignite_cell(gx, gz)
    if gx < 1 or gx > GRID_N or gz < 1 or gz > GRID_N then return end
    local c = S.grid[cell_idx(gx, gz)]
    if c.burning or c.wetness > 20.0 then return end
    c.burning = true
    c.heat = 100.0
    local fe = eng.scene.spawn("voxel_flame_" .. tostring(gx) .. "_" .. tostring(gz))
    eng.scene.set_pos(fe, c.x - 0.55, c.bldg and 1.8 or 0.05, c.z - 0.55)
    eng.scene.set_mesh(fe, S.flame_vox, { color = {1.0, 0.48, 0.12, 1.0} })
    c.flame_ent = fe
end

local function douse_cell(gx, gz)
    if gx < 1 or gx > GRID_N or gz < 1 or gz > GRID_N then return end
    local c = S.grid[cell_idx(gx, gz)]
    c.wetness = 95.0
    c.heat = 0.0
    if c.burning then
        c.burning = false
        if c.flame_ent then
            eng.scene.despawn(c.flame_ent)
            c.flame_ent = nil
        end
        S.extinguished = S.extinguished + 1
    end
end

local function count_active_fires()
    local n = 0
    for i = 1, #S.grid do
        if S.grid[i].burning then n = n + 1 end
    end
    return n
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.014 })
    eng.render.set_sky(0.14, 0.10, 0.16, 0.48, 0.24, 0.14)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.9, 1.8, 1.7}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, -1.0}, color = {2.6, 1.3, 0.5}, range = 30.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.32, 8, 10)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.grass_tex = eng.procgen.texture("grass", seed_base, 64)
    S.brick_tex = eng.procgen.texture("stone_brick", seed_base + 9, 64)

    -- Greedy-meshed AO Voxel Building & Voxel Flame meshes
    S.house_vox = eng.asset.voxel_ascii({
        "1111\n1111\n1111\n1111",
        "1111\n1..1\n1..1\n1111",
        "1111\n1..1\n1..1\n1111",
        ".11.\n1111\n1111\n.11."
    }, 4, 4, 4, 0.52)

    S.flame_vox = eng.asset.voxel_ascii({
        "111\n111\n111",
        ".1.\n111\n.1.",
        ".1.\n.1.\n..."
    }, 3, 3, 3, 0.42)

    S.sfx_water = eng.audio.synth("noise", 520, 0.09, 280)
    S.sfx_flare = eng.audio.synth("saw", 180, 0.14, 90)
    S.sfx_refill = eng.audio.synth("sine", 420, 0.15, 760)

    local ground = eng.scene.spawn("town_ground")
    eng.scene.set_pos(ground, 0.0, -0.25, 0.0)
    eng.scene.set_scale(ground, 26.0, 0.5, 26.0)
    eng.scene.set_mesh(ground, S.box_mesh, { tex = S.grass_tex, color = {0.42, 0.62, 0.36, 1.0} })

    -- Initialize 8x8 Cellular Automata grid
    S.grid = {}
    for gz = 1, GRID_N do
        for gx = 1, GRID_N do
            local wx, wz = cell_world(gx, gz)
            S.grid[#S.grid + 1] = {
                gx = gx, gz = gz, x = wx, z = wz,
                burning = false, heat = 0.0, wetness = 0.0, bldg = false, flame_ent = nil
            }
        end
    end

    -- Place 6 voxel town cottages
    local bldg_cells = { {2, 2}, {6, 2}, {3, 4}, {6, 4}, {2, 6}, {5, 6} }
    for i = 1, #bldg_cells do
        local gx, gz = bldg_cells[i][1], bldg_cells[i][2]
        local c = S.grid[cell_idx(gx, gz)]
        c.bldg = true
        local he = eng.scene.spawn("town_building_" .. tostring(i))
        eng.scene.set_pos(he, c.x - 1.0, 0.0, c.z - 1.0)
        eng.scene.set_mesh(he, S.house_vox, { tex = S.brick_tex, color = {0.86, 0.78, 0.68, 1.0}, cast_shadow = true })
    end

    -- Town Hydrant at south plaza
    S.hydrant_x, S.hydrant_z = 0.0, 8.8
    local hyd = eng.scene.spawn("fire_hydrant")
    eng.scene.set_pos(hyd, S.hydrant_x, 0.55, S.hydrant_z)
    eng.scene.set_scale(hyd, 0.55, 1.1, 0.55)
    eng.scene.set_mesh(hyd, S.box_mesh, { color = {0.95, 0.85, 0.15, 1.0}, cast_shadow = true })

    -- Firefighter Squad Fire Engine + Water Cannon
    S.px, S.pz = 0.0, 7.2
    S.truck_ent = eng.scene.spawn("fire_engine")
    eng.scene.set_pos(S.truck_ent, S.px, 0.55, S.pz)
    eng.scene.set_scale(S.truck_ent, 1.35, 0.95, 2.1)
    eng.scene.set_mesh(S.truck_ent, S.box_mesh, { color = {0.92, 0.16, 0.16, 1.0}, cast_shadow = true })

    local nozzle = eng.scene.spawn("water_cannon")
    eng.scene.set_parent(nozzle, S.truck_ent)
    eng.scene.set_pos(nozzle, 0.0, 0.72, -0.2)
    eng.scene.set_scale(nozzle, 0.35, 0.35, 0.85)
    eng.scene.set_mesh(nozzle, S.box_mesh, { color = {0.85, 0.92, 1.0, 1.0} })

    -- Initial CA fire outbreak
    ignite_cell(2, 2)
    ignite_cell(3, 2)
    ignite_cell(6, 4)
    ignite_cell(5, 6)
    ignite_cell(6, 2)

    S.town_hp = 100.0
    S.water = 100.0
    S.extinguished = 0
    S.ca_timer = 0.55
    S.jet_cd = 0.0
    S.jets = {}
    S.secondary_wave = false
    S.elapsed = 0.0
    S.won = false
    S.lost = false

    eng.camera.look_at(0.0, 19.5, 17.5, 0.0, 0.6, 0.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or S.lost then return end
    S.elapsed = S.elapsed + dt
    S.jet_cd = math.max(0.0, S.jet_cd - dt)

    -- Secondary ember gust early in mission so CA spread is tested
    if (not S.secondary_wave) and S.elapsed >= 0.65 then
        S.secondary_wave = true
        ignite_cell(3, 4)
        ignite_cell(2, 6)
        eng.audio.play(S.sfx_flare, 0.0, 1.5, 0.0, 0)
    end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.px = eng.math.clamp(S.px + mx * 11.5 * dt, -10.5, 10.5)
        S.pz = eng.math.clamp(S.pz - my * 11.5 * dt, -10.5, 10.5)
        eng.scene.set_pos(S.truck_ent, S.px, 0.55, S.pz)
        eng.scene.set_rot_deg(S.truck_ent, 0.0, math.deg(math.atan2(-mx, my)), 0.0)
    end

    -- Hydrant pressure boost / passive water regen
    S.water = math.min(100.0, S.water + 18.0 * dt)
    if eng.input.pressed("interact") or eng.math.dist3(S.px, 0, S.pz, S.hydrant_x, 0, S.hydrant_z) < 3.2 then
        S.water = math.min(100.0, S.water + 45.0 * dt)
        if eng.input.pressed("interact") then
            S.water = 100.0
            eng.audio.play(S.sfx_refill, S.px, 1.0, S.pz, 0)
        end
    end

    -- Fire Water Jet toward nearest burning cell within 11.5m
    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.jet_cd <= 0.0 and S.water >= 6.0 then
        S.jet_cd = 0.14
        S.water = S.water - 6.0

        local best_c = nil
        local best_d = 11.5
        for i = 1, #S.grid do
            local c = S.grid[i]
            if c.burning then
                local d = eng.math.dist3(S.px, 0, S.pz, c.x, 0, c.z)
                if d < best_d then best_d = d; best_c = c end
            end
        end

        local tx, tz = S.px, S.pz - 5.0
        if best_c then
            tx, tz = best_c.x, best_c.z
            eng.scene.set_rot_deg(S.truck_ent, 0.0, math.deg(math.atan2(-(tx - S.px), -(tz - S.pz))), 0.0)
            for dx = -1, 1 do
                for dz = -1, 1 do
                    douse_cell(best_c.gx + dx, best_c.gz + dz)
                end
            end
        end

        -- Spawn 3D pressurized water jet arc droplets
        for k = 1, 3 do
            local t = k / 3.0
            local jx = S.px + (tx - S.px) * t
            local jz = S.pz + (tz - S.pz) * t
            local jy = 1.1 + math.sin(t * 3.14159) * 1.6
            local je = eng.scene.spawn("water_drop")
            eng.scene.set_pos(je, jx, jy, jz)
            eng.scene.set_mesh(je, S.sphere_mesh, { color = {0.25, 0.78, 1.0, 1.0} })
            S.jets[#S.jets + 1] = { ent = je, ttl = 0.16 }
        end
        eng.audio.play(S.sfx_water, S.px, 1.2, S.pz, 0)
    end

    for i = #S.jets, 1, -1 do
        S.jets[i].ttl = S.jets[i].ttl - dt
        if S.jets[i].ttl <= 0.0 then
            eng.scene.despawn(S.jets[i].ent)
            table.remove(S.jets, i)
        end
    end

    -- Cellular Automata fire spread & town integrity step
    S.ca_timer = S.ca_timer - dt
    if S.ca_timer <= 0.0 then
        S.ca_timer = 0.55
        local to_ignite = {}
        local dirs = { {1, 0}, {-1, 0}, {0, 1}, {0, -1} }
        for i = 1, #S.grid do
            local c = S.grid[i]
            c.wetness = math.max(0.0, c.wetness - 15.0)
            if c.burning then
                S.town_hp = math.max(0.0, S.town_hp - (c.bldg and 2.8 or 1.0))
                for d = 1, 4 do
                    local nx, nz = c.gx + dirs[d][1], c.gz + dirs[d][2]
                    if nx >= 1 and nx <= GRID_N and nz >= 1 and nz <= GRID_N then
                        local nb = S.grid[cell_idx(nx, nz)]
                        if (not nb.burning) and nb.wetness <= 5.0 then
                            nb.heat = nb.heat + 48.0
                            if nb.heat >= 95.0 then
                                to_ignite[#to_ignite + 1] = { nx, nz }
                            end
                        end
                    end
                end
            end
        end
        for i = 1, #to_ignite do
            ignite_cell(to_ignite[i][1], to_ignite[i][2])
        end
    end

    local active = count_active_fires()
    if S.town_hp <= 0.0 then
        S.lost = true
        eng.save.write("firefighter_status", "burned")
    elseif S.secondary_wave and active == 0 then
        S.won = true
        eng.save.write("firefighter_status", "saved")
    end
end

function draw()
    for i = 1, #S.grid do
        local c = S.grid[i]
        if c.burning then
            eng.render.draw_sprite(c.x, c.bldg and 3.6 or 1.9, c.z, 0.95, 1.15, S.orb_tex)
        end
    end
    local active = count_active_fires()
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 68, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or (S.lost and (" | " .. eng.i18n.t("defeat")) or "")
    eng.ui.label(x, y, eng.i18n.t("title") .. " | BLAZES: " .. active .. " | DOUSED: " .. S.extinguished .. status, 1.0, {1.0, 0.88, 0.45, 1.0})
    eng.ui.bar(x, y + 24, 220, S.town_hp / 100.0, "TOWN HP ")
    eng.ui.bar(x, y + 46, 220, S.water / 100.0,   "WATER   ")
end
