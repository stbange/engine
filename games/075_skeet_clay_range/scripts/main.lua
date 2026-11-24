-- 075_skeet_clay_range: First-Person Parabolic Clay Targets & 7-Pellet Shotgun Spread Raycasts
local S = game.state

local PELLET_OFFSETS = {
    { 0.000,  0.000},
    {-0.022,  0.012}, { 0.022,  0.012},
    {-0.022, -0.012}, { 0.022, -0.012},
    { 0.000,  0.026}, { 0.000, -0.026}
}

local function launch_clay(from_left)
    local x0 = from_left and -9.5 or 9.5
    local y0 = from_left and 3.4 or 1.8
    local z0 = -12.5
    local vx = from_left and eng.math.range(7.2, 8.6) or eng.math.range(-8.6, -7.2)
    local vy = from_left and eng.math.range(4.2, 5.0) or eng.math.range(5.4, 6.2)
    local vz = eng.math.range(0.6, 1.6)

    local e = eng.scene.spawn("clay_disc")
    eng.scene.set_pos(e, x0, y0, z0)
    eng.scene.set_mesh(e, S.clay_mesh, { color = {1.0, 0.42, 0.08, 1.0}, cast_shadow = true })
    local bid = eng.physics.add_body(e, {
        shape = "sphere", motion = "dynamic", radius = 0.45, vel = {vx, vy, vz}, trigger = true
    })
    S.clays[#S.clays + 1] = { ent = e, body = bid, alive = true, house = from_left and "left" or "right" }
    S.launched = S.launched + 1
    eng.audio.play(S.sfx_pull, x0, y0, z0, 0)
end

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_sky(0.24, 0.52, 0.88, 0.78, 0.86, 0.94)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.2, 2.1, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.0, 2.0}, color = {1.2, 1.1, 1.0}, range = 18.0 })

    -- Ballistic gravity for smooth clay saucer flight arcs
    eng.physics.set_gravity(0, 0.0, -5.2, 0.0)

    local seed = math.floor(eng.math.range(10, 50000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.clay_mesh = eng.asset.cylinder(0.36, 0.30, 0.12, 16)
    S.tree_mesh = eng.procgen.tree(seed + 5, 2, 4.2, 0.24)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.grass_tex = eng.procgen.texture("grass", seed, 64)
    S.wood_tex = eng.procgen.texture("wood_planks", seed + 9, 64)

    S.sfx_pull = eng.audio.synth("triangle", 340, 0.07, 520)
    S.sfx_shot = eng.audio.synth("noise", 260, 0.12, 80)
    S.sfx_shatter = eng.audio.synth("square", 680, 0.10, 220)

    -- Range meadow floor & wooden shooting station fence
    local ground = eng.scene.spawn("range_meadow")
    eng.scene.set_pos(ground, 0.0, -0.25, -10.0)
    eng.scene.set_scale(ground, 48.0, 0.5, 42.0)
    eng.scene.set_mesh(ground, S.box_mesh, { tex = S.grass_tex })
    eng.physics.add_body(ground, { shape = "aabb", motion = "static", half_extents = {24.0, 0.25, 21.0} })

    -- Left High House & Right Low House towers
    local hh = eng.scene.spawn("left_high_house")
    eng.scene.set_pos(hh, -10.2, 2.0, -12.5)
    eng.scene.set_scale(hh, 2.0, 4.0, 2.0)
    eng.scene.set_mesh(hh, S.box_mesh, { tex = S.wood_tex, cast_shadow = true })

    local lh = eng.scene.spawn("right_low_house")
    eng.scene.set_pos(lh, 10.2, 1.1, -12.5)
    eng.scene.set_scale(lh, 2.0, 2.2, 2.0)
    eng.scene.set_mesh(lh, S.box_mesh, { tex = S.wood_tex, cast_shadow = true })

    local fence = eng.scene.spawn("station_rail")
    eng.scene.set_pos(fence, 0.0, 0.55, 2.2)
    eng.scene.set_scale(fence, 5.0, 1.1, 0.2)
    eng.scene.set_mesh(fence, S.box_mesh, { tex = S.wood_tex })

    for i = -3, 3 do
        if i ~= 0 then
            local te = eng.scene.spawn("bg_tree_" .. tostring(i + 4))
            eng.scene.set_pos(te, i * 4.2, 0.0, -21.0)
            eng.scene.set_mesh(te, S.tree_mesh, { color = {0.28, 0.68, 0.30, 1.0}, cast_shadow = true })
        end
    end

    S.cam_x, S.cam_y, S.cam_z = 0.0, 1.65, 4.0
    S.aim_x, S.aim_y, S.aim_z = 0.0, 3.6, -12.0
    S.clays = {}
    S.shards = {}
    S.launched = 0
    S.clays_hit = 0
    S.left_hits = 0
    S.right_hits = 0
    S.shots_fired = 0
    S.score = 0
    S.cooldown = 0.0
    S.wave_timer = 0.0
    S.won = false

    launch_clay(true)
    launch_clay(false)
    eng.input.set_mouse_lock(true)
    eng.camera.look_at(S.cam_x, S.cam_y, S.cam_z, S.aim_x, S.aim_y, S.aim_z, 0)
    eng.mod.emit("post_init")
end

local function fire_shotgun_spread()
    S.shots_fired = S.shots_fired + 1
    eng.audio.play(S.sfx_shot, S.cam_x, S.cam_y, S.cam_z, 0)

    local dx = S.aim_x - S.cam_x
    local dy = S.aim_y - S.cam_y
    local dz = S.aim_z - S.cam_z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then return end
    dx, dy, dz = dx / len, dy / len, dz / len

    -- Orthogonal right & up basis for 7-pellet shotgun choke cone
    local rx, rz = -dz, dx
    local rl = math.sqrt(rx * rx + rz * rz)
    if rl > 0.001 then rx, rz = rx / rl, rz / rl else rx, rz = 1.0, 0.0 end

    for p = 1, #PELLET_OFFSETS do
        local ox, oy = PELLET_OFFSETS[p][1], PELLET_OFFSETS[p][2]
        local pdx = dx + rx * ox
        local pdy = dy + oy
        local pdz = dz + rz * ox
        local hit = eng.physics.raycast(0, S.cam_x, S.cam_y, S.cam_z, pdx, pdy, pdz, 42.0)
        if hit then
            for i = 1, #S.clays do
                local c = S.clays[i]
                if c.alive and c.ent == hit.entity then
                    c.alive = false
                    local cx, cy, cz = eng.scene.get_pos(c.ent)
                    eng.scene.despawn(c.ent)
                    S.clays_hit = S.clays_hit + 1
                    if c.house == "left" then S.left_hits = S.left_hits + 1 else S.right_hits = S.right_hits + 1 end
                    S.score = S.score + 150
                    S.shards[#S.shards + 1] = { x = cx, y = cy, z = cz, ttl = 0.35 }
                    eng.audio.play(S.sfx_shatter, cx, cy, cz, 0)
                    break
                end
            end
        end
    end
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local mdx, mdy = eng.input.mouse_delta()
    S.aim_x = eng.math.clamp(S.aim_x + mx * 16.0 * dt + mdx * 0.045, -12.0, 12.0)
    S.aim_y = eng.math.clamp(S.aim_y + my * 12.0 * dt - mdy * 0.035, 0.8, 9.0)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        S.cooldown = 0.16
        fire_shotgun_spread()
    end

    -- Cleanup grounded clays & launch crossing pairs
    local active_cnt = 0
    for i = 1, #S.clays do
        local c = S.clays[i]
        if c.alive then
            local cx, cy, cz = eng.scene.get_pos(c.ent)
            if cy < 0.35 or math.abs(cx) > 13.5 or cz > 1.0 then
                c.alive = false
                eng.scene.despawn(c.ent)
            else
                active_cnt = active_cnt + 1
            end
        end
    end

    for i = #S.shards, 1, -1 do
        S.shards[i].ttl = S.shards[i].ttl - dt
        S.shards[i].y = S.shards[i].y - 1.5 * dt
        if S.shards[i].ttl <= 0.0 then table.remove(S.shards, i) end
    end

    if S.clays_hit >= 8 then
        S.won = true
        eng.save.write("skeet_clear", tostring(S.score))
        return
    end

    if active_cnt == 0 then
        launch_clay(true)
        launch_clay(false)
    end

    eng.camera.look_at(S.cam_x, S.cam_y, S.cam_z, S.aim_x, S.aim_y, S.aim_z, 0)
end

function draw()
    -- 3D Shotgun front bead sight along aim ray + shatter particles
    local dx, dy, dz = S.aim_x - S.cam_x, S.aim_y - S.cam_y, S.aim_z - S.cam_z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len > 0.01 then
        eng.render.draw_sprite(S.cam_x + (dx / len) * 3.0, S.cam_y + (dy / len) * 3.0, S.cam_z + (dz / len) * 3.0, 0.09, 0.09, S.orb_tex)
    end
    for i = 1, #S.shards do
        local sh = S.shards[i]
        eng.render.draw_sprite(sh.x, sh.y, sh.z, 0.45, 0.45, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | CLAYS " .. S.clays_hit .. "/8 | SCORE " .. S.score, 1.0, {1.0, 0.85, 0.45, 1.0})
end
