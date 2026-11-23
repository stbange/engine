-- 027_ant_colony_3d: Pheromone trail simulation guiding procedural insectoid worker ants between food crystals & nest
local S = game.state

local GRID = 11
local CELL = 1.1

local function w2g(wx, wz)
    return eng.math.clamp(math.floor((wx / CELL) + 6.5), 1, GRID),
           eng.math.clamp(math.floor((wz / CELL) + 6.5), 1, GRID)
end

local function g2w(gx, gz)
    return (gx - 6) * CELL, (gz - 6) * CELL
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.016 })
    eng.render.set_sky(0.09, 0.07, 0.05, 0.28, 0.20, 0.12)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {2.1, 1.95, 1.75}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.5, 0.0}, color = {2.0, 1.6, 1.0}, range = 26.0 })

    local seed = math.floor(eng.math.range(100, 99999))
    local soil_tex = eng.procgen.texture("cobble", seed, 64)
    local box_mesh = eng.asset.box(1, 1, 1)
    local crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local mound_vox = eng.asset.voxel_ascii({
        "3333\n3333\n3333\n3333",
        ".33.\n3663\n3663\n.33.",
        "....\n.66.\n.66.\n...."
    }, 4, 3, 4, 0.45)

    local rock_vox = eng.asset.voxel_ascii({
        "111\n111\n111",
        ".1.\n111\n.1."
    }, 3, 2, 3, 0.45)

    S.sfx_pher = eng.audio.synth("sine", 580, 0.05, 760)
    S.sfx_store = eng.audio.synth("triangle", 480, 0.12, 920)

    local floor = eng.scene.spawn("colony_soil")
    eng.scene.set_pos(floor, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor, 16.0, 0.5, 16.0)
    eng.scene.set_mesh(floor, box_mesh, { tex = soil_tex, color = {0.48, 0.36, 0.26, 1.0} })
    eng.physics.add_body(floor, { shape = "aabb", motion = "static", half_extents = {8.0, 0.25, 8.0} })

    -- Queen's Voxel Nest Mound
    S.nest_x, S.nest_z = -4.4, -4.4
    local nest = eng.scene.spawn("queen_nest")
    eng.scene.set_pos(nest, S.nest_x - 0.9, 0.0, S.nest_z - 0.9)
    eng.scene.set_mesh(nest, mound_vox, { cast_shadow = true })

    -- Voxel Rock Outcrop in center forcing curved pheromone highways
    local rock = eng.scene.spawn("cavern_boulder")
    eng.scene.set_pos(rock, -0.68, 0.0, -0.68)
    eng.scene.set_mesh(rock, rock_vox, { cast_shadow = true })

    -- 3 Food Crystal Clusters
    local c_spots = {{4.4, -3.3}, {-3.3, 4.4}, {4.4, 4.4}}
    S.crystals = {}
    for i = 1, #c_spots do
        local cx, cz = c_spots[i][1], c_spots[i][2]
        local ce = eng.scene.spawn("food_crystal_" .. i)
        eng.scene.set_pos(ce, cx, 0.0, cz)
        eng.scene.set_scale(ce, 0.95, 1.15, 0.95)
        eng.scene.set_mesh(ce, crystal_mesh, { color = {0.35, 1.0, 0.65, 1.0} })
        S.crystals[i] = { ent = ce, x = cx, z = cz, stock = 5 }
    end

    -- Pheromone matrices: pher_food leads outward to crystals, pher_nest leads home
    S.pher_food = {}
    S.pher_nest = {}
    for gz = 1, GRID do
        S.pher_food[gz] = {}
        S.pher_nest[gz] = {}
        for gx = 1, GRID do
            S.pher_food[gz][gx] = 0.0
            local wx, wz = g2w(gx, gz)
            local dn = eng.math.dist3(wx, 0, wz, S.nest_x, 0, S.nest_z)
            S.pher_nest[gz][gx] = math.max(0.0, 1.0 - dn / 10.0)
        end
    end

    -- Spawn 6 articulated insectoid worker ants
    S.ants = {}
    for i = 1, 6 do
        local ax = S.nest_x + ((i - 1) % 3) * 0.65
        local az = S.nest_z + math.floor((i - 1) / 3) * 0.65
        local ae = eng.scene.spawn("worker_ant_" .. i)
        eng.scene.set_pos(ae, ax, 0.0, az)
        eng.scene.set_scale(ae, 0.55, 0.55, 0.55)
        eng.procgen.animal(ae, seed + i * 19, "insectoid")

        local morsel = eng.scene.spawn("ant_morsel_" .. i)
        eng.scene.set_parent(morsel, ae)
        eng.scene.set_pos(morsel, 0.0, 0.65, -0.35)
        eng.scene.set_scale(morsel, 0.05, 0.05, 0.05)
        eng.scene.set_mesh(morsel, crystal_mesh, { color = {0.35, 1.0, 0.65, 1.0} })

        S.ants[i] = {
            ent = ae,
            morsel = morsel,
            x = ax,
            z = az,
            ang = (i - 1) * 0.45,
            carrying = false
        }
    end
    S.ant_count = #S.ants

    S.bx, S.bz = S.nest_x, S.nest_z
    S.brush_ent = eng.scene.spawn("pheromone_brush")
    eng.scene.set_pos(S.brush_ent, S.bx, 1.2, S.bz)
    eng.scene.set_scale(S.brush_ent, 0.4, 0.4, 0.4)
    eng.scene.set_mesh(S.brush_ent, crystal_mesh, { color = {0.3, 0.9, 1.0, 1.0} })

    S.pheromone_laid = 0
    S.food_stored = 0
    S.target_food = 6
    S.sfx_cd = 0.0
    S.won = false

    eng.camera.look_at(0.0, 11.2, 8.8, 0.0, 0.0, -0.4, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.sfx_cd = math.max(0.0, S.sfx_cd - dt)

    -- Evaporate pheromones slowly
    local decay = math.max(0.0, 1.0 - 0.06 * dt)
    for gz = 1, GRID do
        for gx = 1, GRID do
            S.pher_food[gz][gx] = S.pher_food[gz][gx] * decay
        end
    end

    -- Player pheromone brush movement & trail painting
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.bx = eng.math.clamp(S.bx + mx * 9.5 * dt, -5.5, 5.5)
    S.bz = eng.math.clamp(S.bz - my * 9.5 * dt, -5.5, 5.5)
    eng.scene.set_pos(S.brush_ent, S.bx, 1.2, S.bz)

    if eng.input.down("fire") or eng.input.pressed("fire") then
        local bgx, bgz = w2g(S.bx, S.bz)
        if S.pher_food[bgz][bgx] < 0.8 then S.pheromone_laid = S.pheromone_laid + 1 end
        -- Increasing trail gradient along brush stroke so ants follow outward toward crystals
        S.pher_food[bgz][bgx] = math.min(5.0, S.pher_food[bgz][bgx] + 1.4 + (S.pheromone_laid * 0.08))
        if S.sfx_cd <= 0.0 then
            S.sfx_cd = 0.25
            eng.audio.play(S.sfx_pher, S.bx, 0.4, S.bz, 0)
        end
    end

    if eng.input.pressed("interact") then
        for gz = 1, GRID do
            for gx = 1, GRID do
                local wx, wz = g2w(gx, gz)
                local dn = eng.math.dist3(wx, 0, wz, S.nest_x, 0, S.nest_z)
                S.pher_nest[gz][gx] = math.min(3.0, S.pher_nest[gz][gx] + math.max(0.0, 1.2 - dn / 9.0))
            end
        end
    end

    -- Simulate worker ants following pheromone gradients
    for i = 1, #S.ants do
        local a = S.ants[i]
        local agx, agz = w2g(a.x, a.z)

        if not a.carrying then
            S.pher_nest[agz][agx] = math.min(3.0, S.pher_nest[agz][agx] + 0.8 * dt)

            -- Sample best forward/neighbor pher_food cell or nearby crystal scent
            local best_score = -1.0
            local tx, tz = a.x + math.sin(a.ang) * 1.5, a.z + math.cos(a.ang) * 1.5

            for c = 1, #S.crystals do
                local cr = S.crystals[c]
                local dc = eng.math.dist3(a.x, 0, a.z, cr.x, 0, cr.z)
                if cr.stock > 0 and dc < 2.8 then
                    best_score = 99.0
                    tx, tz = cr.x, cr.z
                end
            end

            if best_score < 90.0 then
                for dz = -1, 1 do
                    for dx = -1, 1 do
                        if dx ~= 0 or dz ~= 0 then
                            local nx, nz = agx + dx, agz + dz
                            if nx >= 1 and nx <= GRID and nz >= 1 and nz <= GRID then
                                local wx, wz = g2w(nx, nz)
                                -- Avoid center rock obstacle
                                if eng.math.dist3(wx, 0, wz, 0, 0, 0) > 1.1 then
                                    local pf = S.pher_food[nz][nx]
                                    local fwd_dot = (wx - a.x) * math.sin(a.ang) + (wz - a.z) * math.cos(a.ang)
                                    local sc = pf * 3.0 + (fwd_dot > -0.2 and 0.25 or 0.0)
                                    if pf > 0.05 and sc > best_score then
                                        best_score = sc
                                        tx, tz = wx, wz
                                    end
                                end
                            end
                        end
                    end
                end
            end

            a.ang = math.atan2(tx - a.x, tz - a.z)
            a.x = eng.math.clamp(a.x + math.sin(a.ang) * 5.8 * dt, -5.6, 5.6)
            a.z = eng.math.clamp(a.z + math.cos(a.ang) * 5.8 * dt, -5.6, 5.6)

            for c = 1, #S.crystals do
                local cr = S.crystals[c]
                if cr.stock > 0 and eng.math.dist3(a.x, 0, a.z, cr.x, 0, cr.z) < 1.15 then
                    cr.stock = cr.stock - 1
                    a.carrying = true
                    a.ang = a.ang + math.pi
                    eng.scene.set_scale(a.morsel, 0.35, 0.35, 0.35)
                    break
                end
            end
        else
            -- Reinforce food trail on return trip & follow nest gradient home
            S.pher_food[agz][agx] = math.min(5.0, S.pher_food[agz][agx] + 1.8 * dt)
            local dx, dz = S.nest_x - a.x, S.nest_z - a.z
            -- Curve around central rock if near (0,0)
            if eng.math.dist3(a.x, 0, a.z, 0, 0, 0) < 1.5 then
                dx, dz = dx - 2.0, dz - 2.0
            end
            a.ang = math.atan2(dx, dz)
            a.x = eng.math.clamp(a.x + math.sin(a.ang) * 6.2 * dt, -5.6, 5.6)
            a.z = eng.math.clamp(a.z + math.cos(a.ang) * 6.2 * dt, -5.6, 5.6)

            if eng.math.dist3(a.x, 0, a.z, S.nest_x, 0, S.nest_z) < 1.35 then
                a.carrying = false
                a.ang = a.ang + math.pi
                eng.scene.set_scale(a.morsel, 0.05, 0.05, 0.05)
                S.food_stored = S.food_stored + 1
                eng.audio.play(S.sfx_store, S.nest_x, 0.5, S.nest_z, 0)
            end
        end

        eng.scene.set_pos(a.ent, a.x, 0.0, a.z)
        eng.scene.set_rot_deg(a.ent, 0.0, math.deg(math.atan2(-math.sin(a.ang), -math.cos(a.ang))), 0.0)
    end

    if S.food_stored >= S.target_food then
        S.won = true
        eng.save.write("ant_colony_progress", "clear")
    end
end

function draw()
    for gz = 1, GRID do
        for gx = 1, GRID do
            local pf = S.pher_food[gz][gx]
            if pf > 0.25 then
                local wx, wz = g2w(gx, gz)
                eng.render.draw_sprite(wx, 0.22, wz, 0.42, 0.42, S.orb_tex)
            end
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | ANTS %d | TRAILS %d | FOOD %d/%d",
        eng.i18n.t("title"), S.ant_count, S.pheromone_laid, S.food_stored, S.target_food), 1.0, {0.55, 1.0, 0.65, 1.0})
    eng.ui.bar(x, y + 26, 220, S.food_stored / S.target_food, "NEST ")
end
