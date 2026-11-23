-- 074_voxel_bowling: Oiled Alley Hook Spin & 10 Physics-Simulated Voxel Bowling Pins across 3 Frames
local S = game.state

local function despawn_pins()
    if S.pins then
        for i = 1, #S.pins do
            if S.pins[i].vis then eng.scene.despawn(S.pins[i].vis) end
            if S.pins[i].ent then eng.scene.despawn(S.pins[i].ent) end
        end
    end
    S.pins = {}
end

local function rack_pins()
    despawn_pins()
    local idx = 0
    for row = 1, 4 do
        local z = -11.4 - (row - 1) * 0.36
        local x0 = -(row - 1) * 0.19
        for col = 1, row do
            idx = idx + 1
            local x = x0 + (col - 1) * 0.38
            local pe = eng.scene.spawn("pin_" .. tostring(idx))
            eng.scene.set_pos(pe, x, 0.15, z)
            local bid = eng.physics.add_body(pe, { shape = "sphere", motion = "dynamic", radius = 0.14, restitution = 0.68 })

            local ve = eng.scene.spawn("pin_vox_" .. tostring(idx))
            eng.scene.set_parent(ve, pe)
            eng.scene.set_pos(ve, -0.12, -0.15, -0.12)
            eng.scene.set_mesh(ve, S.pin_vox_mesh, { cast_shadow = true })

            S.pins[#S.pins + 1] = { ent = pe, vis = ve, body = bid, home_x = x, home_z = z, down = false }
        end
    end
end

local function reset_ball_on_approach()
    if S.ball_ent then eng.scene.despawn(S.ball_ent) end
    S.rolling = false
    S.roll_timer = 0.0
    S.in_gutter = false
    S.ball_ent = eng.scene.spawn("bowling_ball")
    eng.scene.set_pos(S.ball_ent, S.stance_x, 0.23, 3.6)
    eng.scene.set_mesh(S.ball_ent, S.ball_mesh, { color = {0.18, 0.32, 0.92, 1.0}, metallic = 0.45, roughness = 0.15, cast_shadow = true })
    S.ball_body = eng.physics.add_body(S.ball_ent, { shape = "sphere", motion = "dynamic", radius = 0.22, restitution = 0.55 })
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.06, 0.05, 0.12, 0.18, 0.12, 0.22)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {1.9, 1.8, 1.65}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 3.5, -11.8}, color = {2.4, 2.1, 1.6}, range = 16.0 })

    -- Slick oiled lane physics
    eng.physics.set_gravity(0, 0.0, -0.8, 0.0)

    local seed = math.floor(eng.math.range(10, 50000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ball_mesh = eng.asset.sphere(0.22, 14, 18)
    S.wood_tex = eng.procgen.texture("wood_planks", seed, 64)
    S.oil_tex = eng.procgen.texture("marble", seed + 13, 64)

    -- 3x6x3 White ('7') & Red-Neck ('4') Voxel Bowling Pin!
    S.pin_vox_mesh = eng.asset.voxel_ascii({
        "777\n777\n777",
        "777\n777\n777",
        "777\n777\n777",
        ".4.\n444\n.4.",
        ".7.\n777\n.7.",
        ".7.\n777\n.7."
    }, 3, 6, 3, 0.08)

    S.arch_vox = eng.asset.voxel_ascii({
        "6..6\n6..6",
        "6..6\n6..6",
        "6446\n6446"
    }, 4, 3, 2, 0.85)

    S.sfx_roll = eng.audio.synth("triangle", 150, 0.12, 110)
    S.sfx_pins = eng.audio.synth("noise", 420, 0.18, 160)
    S.sfx_strike = eng.audio.synth("saw", 440, 0.24, 880)

    -- Oiled hardwood lane + left/right gutters + pin pit backstop
    local lane = eng.scene.spawn("hardwood_lane")
    eng.scene.set_pos(lane, 0.0, -0.25, -5.2)
    eng.scene.set_scale(lane, 2.2, 0.5, 19.6)
    eng.scene.set_mesh(lane, S.box_mesh, { tex = S.wood_tex, roughness = 0.18 })
    eng.physics.add_body(lane, { shape = "aabb", motion = "static", half_extents = {1.5, 0.25, 9.8}, restitution = 0.0 })

    local oil = eng.scene.spawn("oil_pattern_sheen")
    eng.scene.set_pos(oil, 0.0, 0.01, -1.8)
    eng.scene.set_scale(oil, 1.85, 0.02, 11.0)
    eng.scene.set_mesh(oil, S.box_mesh, { tex = S.oil_tex, color = {0.85, 0.72, 0.48, 1.0}, roughness = 0.06 })

    local gl = eng.scene.spawn("gutter_wall_l")
    eng.scene.set_pos(gl, -1.48, 0.22, -5.2)
    eng.scene.set_scale(gl, 0.22, 0.45, 19.6)
    eng.scene.set_mesh(gl, S.box_mesh, { color = {0.22, 0.24, 0.30, 1.0} })
    eng.physics.add_body(gl, { shape = "aabb", motion = "static", half_extents = {0.11, 0.225, 9.8}, restitution = 0.2 })

    local gr = eng.scene.spawn("gutter_wall_r")
    eng.scene.set_pos(gr, 1.48, 0.22, -5.2)
    eng.scene.set_scale(gr, 0.22, 0.45, 19.6)
    eng.scene.set_mesh(gr, S.box_mesh, { color = {0.22, 0.24, 0.30, 1.0} })
    eng.physics.add_body(gr, { shape = "aabb", motion = "static", half_extents = {0.11, 0.225, 9.8}, restitution = 0.2 })

    local sign = eng.scene.spawn("voxel_lane_header")
    eng.scene.set_pos(sign, -1.7, 0.0, -14.2)
    eng.scene.set_mesh(sign, S.arch_vox, { cast_shadow = true })

    S.frame = 1
    S.roll_in_frame = 1
    S.score = 0
    S.total_knocked = 0
    S.strikes = 0
    S.stance_x = 0.48
    S.aim_yaw = 0.0
    S.hook_spin = -2.8
    S.hook_applied = 0
    S.won = false

    rack_pins()
    reset_ball_on_approach()
    eng.camera.look_at(0.0, 2.6, 6.8, 0.0, 0.4, -11.5, 0)
    eng.mod.emit("post_init")
end

local function knock_pin(p, pitch, yaw, roll)
    if p.down then return end
    p.down = true
    S.roll_knocked = (S.roll_knocked or 0) + 1
    S.total_knocked = S.total_knocked + 1
    S.score = S.score + 10
    if p.ent then eng.scene.set_rot_deg(p.ent, pitch or 80.0, yaw or 25.0, roll or 30.0) end
end

local function score_and_advance()
    local standing = 0
    for i = 1, #S.pins do
        local p = S.pins[i]
        if not p.down and p.ent then
            local px, _, pz = eng.scene.get_pos(p.ent)
            if eng.math.dist3(px, 0, pz, p.home_x, 0, p.home_z) > 0.14 then
                knock_pin(p, 82.0, 25.0, 0.0)
            else
                standing = standing + 1
            end
        end
    end

    if standing == 0 and S.roll_in_frame == 1 then
        S.strikes = S.strikes + 1
        S.score = S.score + 20
        eng.audio.play(S.sfx_strike, 0.0, 0.5, -12.0, 0)
    end
    S.roll_knocked = 0

    if standing == 0 or S.roll_in_frame >= 2 then
        if S.frame >= 3 then
            S.won = true
            eng.save.write("bowling_score", tostring(S.score))
            return
        end
        S.frame = S.frame + 1
        S.roll_in_frame = 1
        rack_pins()
    else
        S.roll_in_frame = 2
        for i = 1, #S.pins do
            if S.pins[i].down and S.pins[i].ent then
                eng.scene.despawn(S.pins[i].vis)
                eng.scene.despawn(S.pins[i].ent)
                S.pins[i].ent = nil
            end
        end
    end
    reset_ball_on_approach()
end

function update(dt)
    if S.won then return end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if not S.rolling then
        S.stance_x = eng.math.clamp(S.stance_x + mx * 2.4 * dt, -0.92, 0.92)
        S.hook_spin = eng.math.clamp(S.hook_spin + my * 4.5 * dt, -4.5, 4.5)
        eng.scene.set_pos(S.ball_ent, S.stance_x, 0.23, 3.6)

        if eng.input.pressed("fire") or eng.input.pressed("jump") then
            S.rolling = true
            S.roll_timer = 0.0
            local rad = math.rad(S.aim_yaw)
            eng.physics.set_vel(S.ball_body, -math.sin(rad) * 16.5, 0.0, -math.cos(rad) * 16.5)
            eng.audio.play(S.sfx_roll, S.stance_x, 0.25, 3.6, 0)
        end
        eng.camera.look_at(S.stance_x * 0.4, 2.5, 6.6, 0.0, 0.35, -11.8, 0)
        return
    end

    S.roll_timer = S.roll_timer + dt
    local bx, by, bz = eng.scene.get_pos(S.ball_ent)
    local vx, vy, vz = eng.physics.get_vel(S.ball_body)

    -- Gutter capture if ball drifts off 2.1m lane surface
    if math.abs(bx) > 1.08 and bz > -11.2 then
        S.in_gutter = true
        bx = (bx > 0) and 1.20 or -1.20
        eng.scene.set_pos(S.ball_ent, bx, 0.18, bz)
        vx = 0.0
    end

    -- Oil pattern: slick front lane (z > -6.5) -> dry backend hook bite (z <= -6.5)
    if not S.in_gutter then
        local bite = (bz <= -6.5) and 3.6 or 0.35
        vx = vx + S.hook_spin * bite * dt
        if bz <= -6.5 and math.abs(S.hook_spin) > 0.5 then S.hook_applied = S.hook_applied + 1 end
    end
    eng.physics.set_vel(S.ball_body, vx, vy, vz)

    -- Heavy 16lb bowling ball plow-through impulse + pin-to-pin scatter!
    for i = 1, #S.pins do
        local p = S.pins[i]
        if p.ent and not p.down then
            local px, py, pz = eng.scene.get_pos(p.ent)
            local d = eng.math.dist3(bx, 0, bz, px, 0, pz)
            if d < 0.48 then
                local sx = (px - bx) * 14.0 + S.hook_spin * 1.2
                knock_pin(p, 78.0, sx * 8.0, 35.0)
                eng.physics.set_vel(p.body, sx, 1.2, -9.5)
                eng.physics.set_vel(S.ball_body, vx * 0.94, 0.0, math.min(vz * 0.96, -13.5))
                eng.audio.play(S.sfx_pins, px, py, pz, 0)
            elseif eng.math.dist3(px, 0, pz, p.home_x, 0, p.home_z) > 0.13 then
                knock_pin(p, 80.0, 20.0, 30.0)
            end
        end
    end

    -- Pin-to-pin domino chain scatter from flying knocked pins
    for i = 1, #S.pins do
        local a = S.pins[i]
        if a.ent and a.down then
            local ax, _, az = eng.scene.get_pos(a.ent)
            for j = 1, #S.pins do
                local b = S.pins[j]
                if i ~= j and b.ent and not b.down then
                    local qx, _, qz = eng.scene.get_pos(b.ent)
                    if eng.math.dist3(ax, 0, az, qx, 0, qz) < 0.45 then
                        knock_pin(b, 82.0, -30.0, 25.0)
                        eng.physics.set_vel(b.body, (qx - ax) * 12.0, 0.8, -7.5)
                    end
                end
            end
        end
    end

    if bz < -14.2 or S.roll_timer > 1.45 then
        score_and_advance()
        return
    end

    eng.camera.look_at(bx * 0.35, 2.2, math.max(-8.5, bz + 3.4), 0.0, 0.3, -12.2, 0)
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | FRAME " .. S.frame .. "/3 | PINS " .. S.total_knocked .. " | SCORE " .. S.score, 1.0, {1.0, 0.88, 0.45, 1.0})
end
