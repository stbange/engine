-- 041_grid_grimrock: Step-based 90-degree-turn first-person BSP dungeon crawler
local S = game.state

-- Cardinal directions: 0 = North (-Z), 1 = East (+X), 2 = South (+Z), 3 = West (-X)
local DIR_DX = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
local DIR_DZ = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 } -- grid gz increases North (-Z)
local DIR_YAW = { [0] = 0.0, [1] = -90.0, [2] = 180.0, [3] = 90.0 }
local CELL = 2.4

local function cell_world(gx, gz)
    return S.origin_x + gx * CELL, S.origin_z - gz * CELL
end

local function key_of(gx, gz)
    return tostring(gx) .. ":" .. tostring(gz)
end

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.025 })
    eng.render.set_sky(0.04, 0.03, 0.08, 0.14, 0.09, 0.12)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {1.6, 1.45, 1.25}, shadow = true })

    local seed = math.floor(eng.math.range(100, 90000))
    local d = eng.procgen.dungeon(14, 14, seed, "bsp", 2.0, 3.4)
    S.solvable = d.solvable
    S.origin_x, S.origin_z = 14.0, 24.0

    eng.render.add_light({ type = "point", pos = {14.0, 3.2, 18.0}, color = {2.5, 1.6, 0.8}, range = 28.0 })
    eng.render.add_light({ type = "point", pos = {14.0, 3.2, 8.0}, color = {1.4, 2.0, 2.4}, range = 24.0 })

    local wall_tex = eng.procgen.texture("stone_brick", seed, 64)
    local floor_tex = eng.procgen.texture("cobble", seed + 7, 64)
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_step = eng.audio.synth("noise", 160, 0.06, 90)
    S.sfx_plate = eng.audio.synth("square", 260, 0.16, 520)
    S.sfx_hit = eng.audio.synth("saw", 220, 0.12, 85)

    -- Outer procedural BSP dungeon hall backdrop
    local d_ent = eng.scene.spawn("bsp_dungeon")
    eng.scene.set_pos(d_ent, 0.0, -0.05, 0.0)
    eng.scene.set_mesh(d_ent, d.mesh_id, { tex = wall_tex, roughness = 0.85 })

    -- Walkable grid cells: central spine (0, 0..7) + East plate alcove (1, 2) + West plate alcove (-1, 5)
    S.walkable = {}
    local cells = {
        {0, 0}, {0, 1}, {0, 2}, {1, 2}, {0, 3}, {0, 4}, {0, 5}, {-1, 5}, {0, 6}, {0, 7}
    }
    for i = 1, #cells do
        local gx, gz = cells[i][1], cells[i][2]
        S.walkable[key_of(gx, gz)] = true
        local wx, wz = cell_world(gx, gz)
        local tile = eng.scene.spawn("tile_" .. i)
        eng.scene.set_pos(tile, wx, -0.1, wz)
        eng.scene.set_scale(tile, CELL * 0.98, 0.2, CELL * 0.98)
        eng.scene.set_mesh(tile, S.box_mesh, { tex = floor_tex, color = {0.65, 0.62, 0.58, 1.0} })

        -- Flanking pillars along corridor
        if gx == 0 and (gz % 2 == 1) then
            for side = -1, 1, 2 do
                local pe = eng.scene.spawn("col_" .. gz .. "_" .. side)
                eng.scene.set_pos(pe, wx + side * (CELL * 0.52), 0.0, wz)
                eng.scene.set_scale(pe, 0.5, 1.0, 0.5)
                eng.scene.set_mesh(pe, S.pillar_mesh, { tex = wall_tex, color = {0.72, 0.70, 0.66, 1.0} })
            end
        end
    end

    -- 2 Pressure Plates & 2 Linked Iron Gates
    S.plates = {
        { gx = 1, gz = 2, pressed = false, gate_idx = 1 },
        { gx = -1, gz = 5, pressed = false, gate_idx = 2 }
    }
    S.gates = {
        { gx = 0, gz = 3, open = false },
        { gx = 0, gz = 6, open = false }
    }
    for i = 1, #S.plates do
        local p = S.plates[i]
        local wx, wz = cell_world(p.gx, p.gz)
        p.ent = eng.scene.spawn("pressure_plate_" .. i)
        eng.scene.set_pos(p.ent, wx, 0.08, wz)
        eng.scene.set_scale(p.ent, 1.1, 0.14, 1.1)
        eng.scene.set_mesh(p.ent, S.box_mesh, { color = {0.95, 0.75, 0.22, 1.0} })
    end
    for i = 1, #S.gates do
        local g = S.gates[i]
        local wx, wz = cell_world(g.gx, g.gz)
        local frame = eng.scene.spawn("gate_arch_" .. i)
        eng.scene.set_pos(frame, wx, 0.0, wz)
        eng.scene.set_mesh(frame, S.arch_mesh, { tex = wall_tex, color = {0.6, 0.6, 0.65, 1.0} })
        g.bars_ent = eng.scene.spawn("gate_bars_" .. i)
        eng.scene.set_pos(g.bars_ent, wx, 1.25, wz)
        eng.scene.set_scale(g.bars_ent, 1.5, 2.4, 0.18)
        eng.scene.set_mesh(g.bars_ent, S.box_mesh, { color = {0.32, 0.35, 0.40, 1.0}, metallic = 0.8, roughness = 0.3 })
    end

    -- 2 Skeleton Guardians (bone-ivory procedural humanoids with raycast/grid hitboxes)
    S.skeletons = {}
    local skel_coords = { {0, 2}, {0, 5} }
    for i = 1, #skel_coords do
        local gx, gz = skel_coords[i][1], skel_coords[i][2]
        local wx, wz = cell_world(gx, gz)
        local se = eng.scene.spawn("skeleton_" .. i)
        eng.scene.set_pos(se, wx, 0.0, wz)
        eng.scene.set_mesh(se, S.box_mesh, { color = {0.92, 0.90, 0.82, 1.0} })
        local info = eng.procgen.person(se, seed + i * 31)
        local bid = eng.physics.add_body(se, { shape = "aabb", motion = "kinematic", half_extents = {0.45, 0.9, 0.45} })
        S.skeletons[i] = { ent = se, body = bid, gx = gx, gz = gz, hp = 2, alive = true, name = info.name }
    end

    -- Exit Shrine at (0, 7)
    local ex, ez = cell_world(0, 7)
    local exit_e = eng.scene.spawn("exit_shrine")
    eng.scene.set_pos(exit_e, ex, 0.4, ez)
    eng.scene.set_mesh(exit_e, S.crystal_mesh, { color = {0.3, 0.95, 1.0, 1.0} })

    S.gx, S.gz = 0, 0
    S.dir = 0
    S.vis_x, S.vis_z = cell_world(0, 0)
    S.vis_yaw = 0.0
    S.hp = 100
    S.xp = 0
    S.kills = 0
    S.plates_pressed = 0
    S.gates_opened = 0
    S.steps_taken = 0
    S.turns_90 = 0
    S.step_cd = 0.0
    S.won = false

    local tx, tz = cell_world(0, 2)
    eng.camera.look_at(S.vis_x, 1.45, S.vis_z, tx, 1.25, tz, 0)
    eng.mod.emit("post_init")
end

local function skeleton_at(gx, gz)
    for i = 1, #S.skeletons do
        local sk = S.skeletons[i]
        if sk.alive and sk.gx == gx and sk.gz == gz then return sk end
    end
    return nil
end

local function gate_blocking(gx, gz)
    for i = 1, #S.gates do
        local g = S.gates[i]
        if not g.open and g.gx == gx and g.gz == gz then return true end
    end
    return false
end

local function check_plates()
    for i = 1, #S.plates do
        local p = S.plates[i]
        if not p.pressed and S.gx == p.gx and S.gz == p.gz then
            p.pressed = true
            S.plates_pressed = S.plates_pressed + 1
            local wx, wz = cell_world(p.gx, p.gz)
            eng.scene.set_pos(p.ent, wx, 0.01, wz)
            eng.scene.set_mesh(p.ent, S.box_mesh, { color = {0.25, 0.95, 0.45, 1.0} })
            eng.audio.play(S.sfx_plate, wx, 0.5, wz, 0)

            local g = S.gates[p.gate_idx]
            if g and not g.open then
                g.open = true
                S.gates_opened = S.gates_opened + 1
                local gx_w, gz_w = cell_world(g.gx, g.gz)
                eng.scene.set_pos(g.bars_ent, gx_w, 3.6, gz_w)
            end
        end
    end
end

local function try_step(sign)
    local tgx = S.gx + DIR_DX[S.dir] * sign
    local tgz = S.gz + DIR_DZ[S.dir] * sign
    if not S.walkable[key_of(tgx, tgz)] then return end
    if gate_blocking(tgx, tgz) or skeleton_at(tgx, tgz) then return end
    S.gx, S.gz = tgx, tgz
    S.steps_taken = S.steps_taken + 1
    local wx, wz = cell_world(S.gx, S.gz)
    eng.audio.play(S.sfx_step, wx, 1.0, wz, 0)
    check_plates()
    if S.gx == 0 and S.gz == 7 then
        S.won = true
        S.xp = S.xp + 200
        eng.save.write("grimrock_progress", "escaped")
    end
end

local function melee_strike()
    local tgx = S.gx + DIR_DX[S.dir]
    local tgz = S.gz + DIR_DZ[S.dir]
    local sk = skeleton_at(tgx, tgz)
    local wx, wz = cell_world(S.gx, S.gz)
    eng.audio.play(S.sfx_hit, wx, 1.2, wz, 0)
    if sk then
        sk.hp = sk.hp - 1
        if sk.hp <= 0 then
            sk.alive = false
            eng.scene.despawn(sk.ent)
            S.kills = S.kills + 1
            S.xp = S.xp + 75
        else
            S.hp = math.max(10, S.hp - 8) -- skeleton counter-slash
        end
    end
end

function update(dt)
    if S.won then return end
    S.step_cd = math.max(0.0, S.step_cd - dt)

    if S.step_cd <= 0.0 then
        if eng.input.pressed("left") then
            S.dir = (S.dir + 3) % 4
            S.turns_90 = S.turns_90 + 1
            S.step_cd = 0.05
        elseif eng.input.pressed("right") then
            S.dir = (S.dir + 1) % 4
            S.turns_90 = S.turns_90 + 1
            S.step_cd = 0.05
        elseif eng.input.pressed("up") then
            try_step(1)
            S.step_cd = 0.05
        elseif eng.input.pressed("down") then
            try_step(-1)
            S.step_cd = 0.05
        elseif eng.input.pressed("fire") then
            melee_strike()
            S.step_cd = 0.06
        end
    end

    local tx_pos, tz_pos = cell_world(S.gx, S.gz)
    local blend = math.min(1.0, dt * 18.0)
    S.vis_x = S.vis_x + (tx_pos - S.vis_x) * blend
    S.vis_z = S.vis_z + (tz_pos - S.vis_z) * blend

    local look_x = S.vis_x + DIR_DX[S.dir] * 4.0
    local look_z = S.vis_z - DIR_DZ[S.dir] * 4.0
    eng.camera.look_at(S.vis_x, 1.45, S.vis_z, look_x, 1.3, look_z, 0)
end

function draw()
    for i = 1, #S.skeletons do
        local sk = S.skeletons[i]
        if sk.alive then
            local wx, wz = cell_world(sk.gx, sk.gz)
            eng.render.draw_sprite(wx, 2.05, wz, 0.45, 0.45, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | PLATES " .. S.plates_pressed .. "/2 | GATES " .. S.gates_opened .. "/2 | XP " .. S.xp, 1.0, {1.0, 0.9, 0.55, 1.0})
    eng.ui.bar(x, y + 26, 200, S.hp / 100.0, "PARTY HP ")
end
