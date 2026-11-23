-- 078_curling_ice_sheet: Granite Stone Curl & Broom Sweeping (interact/jump) Lowering Pebbled Ice Friction
local S = game.state

local HOUSE_Z = -7.5

local function spawn_stone(name, x, z, handle_col, team)
    local e = eng.scene.spawn(name)
    eng.scene.set_pos(e, x, 0.14, z)
    eng.scene.set_mesh(e, S.granite_mesh, { color = {0.62, 0.64, 0.68, 1.0}, roughness = 0.22, cast_shadow = true })
    local bid = eng.physics.add_body(e, { shape = "sphere", motion = "dynamic", radius = 0.23, restitution = 0.88 })

    local he = eng.scene.spawn(name .. "_handle")
    eng.scene.set_parent(he, e)
    eng.scene.set_pos(he, 0.0, 0.11, 0.0)
    eng.scene.set_mesh(he, S.handle_mesh, { color = handle_col })

    local st = { ent = e, handle = he, body = bid, team = team }
    S.stones[#S.stones + 1] = st
    return st
end

local function prepare_next_delivery()
    if S.stones_thrown >= 2 then
        -- Measure closest stone to the Button (0, -7.5)
        S.best_player = 99.0
        S.best_opp = 99.0
        for i = 1, #S.stones do
            local st = S.stones[i]
            local sx, _, sz = eng.scene.get_pos(st.ent)
            local d = eng.math.dist3(sx, 0, sz, 0.0, 0, HOUSE_Z)
            if st.team == "player" and d < S.best_player then S.best_player = d end
            if st.team == "opp" and d < S.best_opp then S.best_opp = d end
        end
        if S.best_player < S.best_opp and S.best_player < 1.85 then
            S.score = 0
            for i = 1, #S.stones do
                local st = S.stones[i]
                if st.team == "player" then
                    local sx, _, sz = eng.scene.get_pos(st.ent)
                    local d = eng.math.dist3(sx, 0, sz, 0.0, 0, HOUSE_Z)
                    if d < S.best_opp and d < 1.85 then S.score = S.score + 1 end
                end
            end
            S.won = true
            eng.save.write("curling_end", tostring(S.score))
        else
            -- Allow sudden-death hammer stone if behind
            S.stones_thrown = 1
        end
        if S.won then return end
    end

    S.stones_thrown = S.stones_thrown + 1
    S.sliding = false
    S.aim_x = -0.32
    S.curl_dir = 1.0
    S.power = 0.72
    S.active_stone = spawn_stone("player_stone_" .. tostring(S.stones_thrown), S.aim_x, 5.2, {0.95, 0.20, 0.20, 1.0}, "player")
    eng.scene.set_pos(S.broom_ent, 0.0, -4.0, 0.0)
    eng.camera.look_at(0.0, 3.2, 8.4, 0.0, 0.2, -5.5, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.14, 0.22, 0.36, 0.65, 0.78, 0.90)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {2.0, 2.05, 2.2}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.5, HOUSE_Z}, color = {1.6, 1.8, 2.2}, range = 18.0 })

    -- Low normal load so Lua controls pebbled vs swept ice friction cleanly
    eng.physics.set_gravity(0, 0.0, -0.3, 0.0)

    local seed = math.floor(eng.math.range(10, 50000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.granite_mesh = eng.asset.cylinder(0.23, 0.21, 0.16, 18)
    S.handle_mesh = eng.asset.cylinder(0.11, 0.11, 0.07, 12)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.ice_tex = eng.procgen.texture("marble", seed, 64)

    S.sfx_slide = eng.audio.synth("triangle", 190, 0.10, 150)
    S.sfx_sweep = eng.audio.synth("noise", 760, 0.05, 520)
    S.sfx_clack = eng.audio.synth("square", 520, 0.08, 290)

    -- Pebbled Olympic Ice Sheet
    local sheet = eng.scene.spawn("pebbled_ice_sheet")
    eng.scene.set_pos(sheet, 0.0, -0.25, -1.8)
    eng.scene.set_scale(sheet, 4.4, 0.5, 18.4)
    eng.scene.set_mesh(sheet, S.box_mesh, { tex = S.ice_tex, color = {0.86, 0.94, 1.0, 1.0}, roughness = 0.08 })
    eng.physics.add_body(sheet, { shape = "aabb", motion = "static", half_extents = {2.2, 0.25, 9.2}, restitution = 0.0 })

    -- Side & back boards
    for s = -1, 1, 2 do
        local sb = eng.scene.spawn("board_" .. tostring(s))
        eng.scene.set_pos(sb, s * 2.25, 0.20, -1.8)
        eng.scene.set_scale(sb, 0.2, 0.4, 18.4)
        eng.scene.set_mesh(sb, S.box_mesh, { color = {0.18, 0.30, 0.52, 1.0} })
        eng.physics.add_body(sb, { shape = "aabb", motion = "static", half_extents = {0.1, 0.2, 9.2}, restitution = 0.5 })
    end
    local bb = eng.scene.spawn("back_hack_bumper")
    eng.scene.set_pos(bb, 0.0, 0.20, -10.9)
    eng.scene.set_scale(bb, 4.6, 0.4, 0.3)
    eng.scene.set_mesh(bb, S.box_mesh, { color = {0.18, 0.30, 0.52, 1.0} })
    eng.physics.add_body(bb, { shape = "aabb", motion = "static", half_extents = {2.3, 0.2, 0.15}, restitution = 0.3 })

    -- Concentric Target House Rings (12ft Blue, 8ft White, 4ft Red, Button)
    local rings = {
        { r = 1.80, y = 0.010, col = {0.15, 0.45, 0.92, 1.0} },
        { r = 1.20, y = 0.018, col = {0.96, 0.97, 0.99, 1.0} },
        { r = 0.60, y = 0.026, col = {0.92, 0.18, 0.20, 1.0} },
        { r = 0.20, y = 0.034, col = {0.98, 0.98, 1.00, 1.0} }
    }
    for i = 1, #rings do
        local rm = eng.asset.cylinder(rings[i].r, rings[i].r, 0.02, 24)
        local re = eng.scene.spawn("house_ring_" .. tostring(i))
        eng.scene.set_pos(re, 0.0, rings[i].y, HOUSE_Z)
        eng.scene.set_mesh(re, rm, { color = rings[i].col })
    end

    -- Animated 3D Sweeper Broom head
    S.broom_ent = eng.scene.spawn("sweeper_broom")
    eng.scene.set_pos(S.broom_ent, 0.0, -4.0, 0.0)
    eng.scene.set_scale(S.broom_ent, 0.55, 0.10, 0.16)
    eng.scene.set_mesh(S.broom_ent, S.box_mesh, { color = {1.0, 0.85, 0.15, 1.0}, cast_shadow = true })

    S.stones = {}
    -- Opponent Yellow guard + Yellow shot stone sitting 0.62m off the Button!
    spawn_stone("opp_guard", -0.68, -4.2, {0.98, 0.85, 0.12, 1.0}, "opp")
    spawn_stone("opp_shot",   0.52, -7.15, {0.98, 0.85, 0.12, 1.0}, "opp")

    S.stones_thrown = 0
    S.sweep_ticks = 0
    S.score = 0
    S.best_player = 99.0
    S.best_opp = 0.62
    S.phase = 0.0
    S.won = false

    prepare_next_delivery()
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.phase = S.phase + dt

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local st = S.active_stone

    if not S.sliding then
        S.aim_x = eng.math.clamp(S.aim_x + mx * 2.2 * dt, -1.5, 1.5)
        S.power = eng.math.clamp(S.power + my * 0.7 * dt, 0.30, 1.0)
        eng.scene.set_pos(st.ent, S.aim_x, 0.14, 5.2)

        if eng.input.pressed("fire") then
            S.sliding = true
            local spd = 6.2 + S.power * 3.6
            eng.physics.set_vel(st.body, 0.0, 0.0, -spd)
            eng.audio.play(S.sfx_slide, S.aim_x, 0.14, 5.2, 0)
        end
        return
    end

    --Sweeping (`interact` or `jump`) warms ice film, cutting deceleration from 4.4 m/s^2 down to 1.65 m/s^2!
    local sweeping = eng.input.down("interact") or eng.input.down("jump") or eng.input.pressed("interact") or eng.input.pressed("jump")
    local sx, sy, sz = eng.scene.get_pos(st.ent)
    if sweeping then
        S.sweep_ticks = S.sweep_ticks + 1
        eng.scene.set_pos(S.broom_ent, sx + math.sin(S.phase * 38.0) * 0.28, 0.10, sz - 0.52)
        if (S.sweep_ticks % 8) == 1 then eng.audio.play(S.sfx_sweep, sx, sy, sz - 0.5, 0) end
    else
        eng.scene.set_pos(S.broom_ent, 0.0, -4.0, 0.0)
    end

    local any_moving = false
    for i = 1, #S.stones do
        local s = S.stones[i]
        local vx, vy, vz = eng.physics.get_vel(s.body)
        local hspd = math.sqrt(vx * vx + vz * vz)
        if hspd > 0.12 then
            local decel = (s == st and sweeping) and 1.65 or 4.40
            local new_spd = math.max(0.0, hspd - decel * dt)
            local scale = new_spd / hspd
            vx, vz = vx * scale, vz * scale
            -- Subtle ice curl turn on active stone (reduced while sweeping!)
            if s == st and new_spd > 0.25 then
                local curl_a = sweeping and 0.18 or 0.42
                vx = vx + S.curl_dir * curl_a * dt
            end
            eng.physics.set_vel(s.body, vx, vy, vz)
            if new_spd > 0.12 then any_moving = true end
        else
            eng.physics.set_vel(s.body, 0.0, vy, 0.0)
        end
    end

    if not any_moving then
        prepare_next_delivery()
        return
    end

    eng.camera.look_at(sx * 0.4, 2.8, math.max(-4.5, sz + 3.8), 0.0, 0.1, HOUSE_Z, 0)
end

function draw()
    if not S.sliding and not S.won and S.active_stone then
        local sx, _, sz = eng.scene.get_pos(S.active_stone.ent)
        eng.render.draw_sprite(sx, 0.35, sz - 1.4, 0.25, 0.25, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | STONE " .. S.stones_thrown .. "/2 | SWEEPS " .. S.sweep_ticks, 1.0, {0.75, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.power, "WEIGHT ")
end
