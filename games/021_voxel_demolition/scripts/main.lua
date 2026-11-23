-- 021_voxel_demolition: Timed C4 charges on structural voxel columns to collapse a tower below target height
local S = game.state

local PILLAR_COORDS = {
    {-1.6, -5.2},
    { 1.6, -5.2},
    {-1.6, -2.8},
    { 1.6, -2.8}
}

local function spawn_vox_centered(name, mesh_id, px, py, pz, ox, oy, oz, opts)
    local root = eng.scene.spawn(name)
    eng.scene.set_pos(root, px, py, pz)
    local vis = eng.scene.spawn(name .. "_vis")
    eng.scene.set_parent(vis, root)
    eng.scene.set_pos(vis, ox, oy, oz)
    eng.scene.set_mesh(vis, mesh_id, opts)
    return root, vis
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.015 })
    eng.render.set_sky(0.10, 0.16, 0.28, 0.36, 0.42, 0.50)
    eng.render.add_light({ type = "dir", dir = {-0.4, -1.0, -0.5}, color = {2.1, 2.0, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.0, -1.0}, color = {1.8, 1.4, 0.9}, range = 22.0 })

    local seed = math.floor(eng.math.range(100, 99999))
    local ground_tex = eng.procgen.texture("cobble", seed, 64)
    local box_mesh = eng.asset.box(1, 1, 1)

    -- Greedy-meshed AO voxel structural parts
    local col_layer = "11\n11"
    S.col_vox = eng.asset.voxel_ascii({col_layer, col_layer, col_layer, col_layer, col_layer, col_layer}, 2, 6, 2, 0.4)
    local beam_layer = "77777777\n77777777"
    S.beam_vox = eng.asset.voxel_ascii({beam_layer, beam_layer}, 8, 2, 2, 0.5)
    local cap_layer = "4444\n4664\n4664\n4444"
    local spire_layer = "....\n.66.\n.66.\n...."
    S.cap_vox = eng.asset.voxel_ascii({cap_layer, cap_layer, spire_layer}, 4, 3, 4, 0.5)
    S.charge_mesh = eng.asset.box(0.36, 0.28, 0.36)

    S.sfx_plant = eng.audio.synth("square", 620, 0.09, 880)
    S.sfx_boom = eng.audio.synth("noise", 220, 0.28, 55)

    local ground = eng.scene.spawn("blast_pad")
    eng.scene.set_pos(ground, 0.0, -0.25, -4.0)
    eng.scene.set_scale(ground, 20.0, 0.5, 20.0)
    eng.scene.set_mesh(ground, box_mesh, { tex = ground_tex, color = {0.48, 0.50, 0.52, 1.0} })
    eng.physics.add_body(ground, { shape = "aabb", motion = "static", half_extents = {10.0, 0.25, 10.0} })

    S.target_y = 3.8
    local laser_line = eng.scene.spawn("target_height_line")
    eng.scene.set_pos(laser_line, 0.0, S.target_y, -4.0)
    eng.scene.set_scale(laser_line, 6.2, 0.08, 0.08)
    eng.scene.set_mesh(laser_line, box_mesh, { color = {0.2, 1.0, 0.45, 1.0}, roughness = 0.2 })

    S.pillars = {}
    S.upper_blocks = {}
    S.charges = {}

    for i = 1, 4 do
        local px, pz = PILLAR_COORDS[i][1], PILLAR_COORDS[i][2]
        local p_ent, p_vis = spawn_vox_centered("base_col_" .. i, S.col_vox, px, 1.22, pz, -0.4, -1.2, -0.4, { cast_shadow = true })
        local p_bid = eng.physics.add_body(p_ent, { shape = "aabb", motion = "static", half_extents = {0.42, 1.20, 0.42} })
        S.pillars[i] = { ent = p_ent, vis = p_vis, body = p_bid, x = px, y = 1.22, z = pz, intact = true, has_charge = false }

        local u_ent, u_vis = spawn_vox_centered("mid_col_" .. i, S.col_vox, px, 3.68, pz, -0.4, -1.2, -0.4, { cast_shadow = true })
        local u_bid = eng.physics.add_body(u_ent, { shape = "aabb", motion = "dynamic", half_extents = {0.42, 1.20, 0.42} })
        S.upper_blocks[#S.upper_blocks + 1] = { ent = u_ent, vis = u_vis, body = u_bid, hy = 1.20, dir_x = px > 0 and 1 or -1, dir_z = pz > -4.0 and 1 or -1 }
    end

    for b = 1, 2 do
        local bz = (b == 1) and -5.2 or -2.8
        local b_ent, b_vis = spawn_vox_centered("cross_beam_" .. b, S.beam_vox, 0.0, 5.44, bz, -2.0, -0.5, -0.5, { cast_shadow = true })
        local b_bid = eng.physics.add_body(b_ent, { shape = "aabb", motion = "dynamic", half_extents = {2.0, 0.50, 0.50} })
        S.upper_blocks[#S.upper_blocks + 1] = { ent = b_ent, vis = b_vis, body = b_bid, hy = 0.50, dir_x = (b == 1) and -1 or 1, dir_z = (b == 1) and -1 or 1 }
    end

    local c_ent, c_vis = spawn_vox_centered("tower_spire", S.cap_vox, 0.0, 6.75, -4.0, -1.0, -0.75, -1.0, { cast_shadow = true })
    local c_bid = eng.physics.add_body(c_ent, { shape = "aabb", motion = "dynamic", half_extents = {1.0, 0.75, 1.0} })
    S.upper_blocks[#S.upper_blocks + 1] = { ent = c_ent, vis = c_vis, body = c_bid, hy = 0.75, dir_x = 0.5, dir_z = 0.8 }

    S.sel_idx = 1
    S.cursor_ent = eng.scene.spawn("charge_cursor")
    eng.scene.set_pos(S.cursor_ent, PILLAR_COORDS[1][1], 1.1, PILLAR_COORDS[1][2] + 0.55)
    eng.scene.set_mesh(S.cursor_ent, S.charge_mesh, { color = {1.0, 0.9, 0.2, 1.0} })

    S.charges_planted = 0
    S.charges_blown = 0
    S.peak_y = 7.50
    S.settle_timer = 0.0
    S.step_cd = 0.0
    S.won = false

    eng.camera.look_at(0.0, 4.8, 5.2, 0.0, 3.0, -4.0, 0)
    eng.mod.emit("post_init")
end

local function detonate_charge(ch)
    if ch.blown then return end
    ch.blown = true
    S.charges_blown = S.charges_blown + 1
    eng.audio.play(S.sfx_boom, ch.x, ch.y, ch.z, 0)
    eng.scene.despawn(ch.ent)

    -- Blast destroys structural columns within 2.0m
    for i = 1, #S.pillars do
        local p = S.pillars[i]
        if p.intact and eng.math.dist3(ch.x, ch.y, ch.z, p.x, p.y, p.z) < 2.0 then
            p.intact = false
            eng.scene.despawn(p.vis)
            eng.scene.despawn(p.ent)
        end
    end

    -- Shockwave pushes upper dynamic blocks outward so tower pancakes instead of staying stacked
    for i = 1, #S.upper_blocks do
        local ub = S.upper_blocks[i]
        local ux, uy, uz = eng.scene.get_pos(ub.ent)
        if eng.math.dist3(ch.x, ch.y, ch.z, ux, uy, uz) < 5.5 then
            eng.physics.set_vel(ub.body, ub.dir_x * 2.8, -1.8, ub.dir_z * 2.8)
        end
    end
end

function update(dt)
    if S.won then return end
    S.step_cd = math.max(0.0, S.step_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if (math.abs(mx) > 0.4 or math.abs(my) > 0.4) and S.step_cd <= 0.0 then
        S.step_cd = 0.16
        S.sel_idx = (S.sel_idx % #S.pillars) + 1
    end

    local cur_p = S.pillars[S.sel_idx]
    if cur_p then
        eng.scene.set_pos(S.cursor_ent, cur_p.x, 1.1, cur_p.z + 0.55)
    end

    if eng.input.pressed("fire") and cur_p and cur_p.intact and not cur_p.has_charge and S.charges_planted < 4 then
        cur_p.has_charge = true
        S.charges_planted = S.charges_planted + 1
        local ce = eng.scene.spawn("c4_charge_" .. S.charges_planted)
        eng.scene.set_pos(ce, cur_p.x, 1.1, cur_p.z + 0.48)
        eng.scene.set_mesh(ce, S.charge_mesh, { color = {1.0, 0.2, 0.15, 1.0} })
        eng.audio.play(S.sfx_plant, cur_p.x, 1.1, cur_p.z, 0)
        S.charges[#S.charges + 1] = { ent = ce, x = cur_p.x, y = 1.1, z = cur_p.z, fuse = 0.9, blown = false }
    end

    local force_boom = eng.input.pressed("interact") or eng.input.pressed("jump")
    for i = 1, #S.charges do
        local ch = S.charges[i]
        if not ch.blown then
            ch.fuse = ch.fuse - dt
            if force_boom or ch.fuse <= 0.0 then
                detonate_charge(ch)
            end
        end
    end

    local highest = 0.0
    for i = 1, #S.upper_blocks do
        local ub = S.upper_blocks[i]
        local _, uy, _ = eng.scene.get_pos(ub.ent)
        if uy + ub.hy > highest then highest = uy + ub.hy end
    end
    for i = 1, #S.pillars do
        if S.pillars[i].intact and 2.42 > highest then highest = 2.42 end
    end
    S.peak_y = highest

    if S.charges_blown >= 2 and S.peak_y < S.target_y then
        S.settle_timer = S.settle_timer + dt
        if S.settle_timer >= 0.35 then
            S.won = true
            eng.save.write("demolition_progress", "clear")
        end
    else
        S.settle_timer = 0.0
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | C4 %d/4 | PEAK %.2fm (TARGET < %.1fm)",
        eng.i18n.t("title"), S.charges_planted, S.peak_y, S.target_y), 1.0, {1.0, 0.9, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 220, eng.math.clamp(S.target_y / math.max(0.5, S.peak_y), 0.0, 1.0), "DROP ")
end
