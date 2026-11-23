-- 072_cyber_pinball_3d: Sloped 3D Neon Pinball with Plunger, Flippers, Jet Bumpers & Pocket Upper Deck
local S = game.state

local BUMPERS = {
    { x = -0.35, z = -2.1, r = 0.44, color = {1.0, 0.20, 0.75, 1.0}, pts = 250 },
    { x =  1.05, z = -2.3, r = 0.44, color = {0.20, 0.95, 1.0, 1.0}, pts = 250 },
    { x =  0.35, z = -0.8, r = 0.44, color = {1.0, 0.85, 0.15, 1.0}, pts = 300 }
}

local UPPER_BUMPERS = {
    { x = -0.75, z = -1.8, r = 0.48, pts = 600 },
    { x =  0.75, z = -1.8, r = 0.48, pts = 600 }
}

local function add_wall(pk, name, x, y, z, sx, sy, sz, mesh, opts, rest)
    local e = eng.scene.spawn(name)
    eng.scene.set_pocket(e, pk)
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_scale(e, sx, sy, sz)
    eng.scene.set_mesh(e, mesh, opts)
    eng.physics.add_body(e, { shape = "aabb", motion = "static", pocket = pk, half_extents = {sx * 0.5, sy * 0.5, sz * 0.5}, restitution = rest or 0.85 })
    return e
end

local function spawn_ball_in_shooter()
    if S.ball_ent then eng.scene.despawn(S.ball_ent) end
    S.in_shooter = true
    S.plunge_charge = 0.0
    S.ball_ent = eng.scene.spawn("pinball_chrome")
    eng.scene.set_pocket(S.ball_ent, 0)
    eng.scene.set_pos(S.ball_ent, 2.95, 0.18, 4.35)
    eng.scene.set_mesh(S.ball_ent, S.ball_mesh, { color = {0.92, 0.96, 1.0, 1.0}, metallic = 0.95, roughness = 0.08, cast_shadow = true })
    S.ball_body = eng.physics.add_body(S.ball_ent, {
        shape = "sphere", motion = "dynamic", pocket = 0, radius = 0.17, restitution = 0.84
    })
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.03, 0.02, 0.08, 0.12, 0.04, 0.22)
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.2, -1.0, -0.35}, color = {1.4, 1.4, 1.8}, shadow = true })
    eng.render.add_light({ type = "point", pocket = 0, pos = {0.0, 4.0, -1.5}, color = {2.5, 0.8, 2.2}, range = 18.0 })
    eng.render.add_light({ type = "point", pocket = 0, pos = {0.0, 3.5, 3.5}, color = {0.6, 2.0, 2.5}, range = 14.0 })

    S.upper_pocket = eng.scene.register_pocket("upper_deck")
    eng.render.add_light({ type = "dir", pocket = S.upper_pocket, dir = {-0.2, -1.0, -0.3}, color = {1.6, 1.5, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pocket = S.upper_pocket, pos = {0.0, 3.5, 0.0}, color = {2.6, 1.8, 0.5}, range = 16.0 })

    -- Sloped pinball gravity (+Z toward player flippers, mild -Y to minimize floor sliding drag)
    eng.physics.set_gravity(0, 0.0, -1.2, 6.2)
    eng.physics.set_gravity(S.upper_pocket, 0.0, -1.2, 5.6)

    local seed = math.floor(eng.math.range(10, 50000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ball_mesh = eng.asset.sphere(0.17, 12, 16)
    S.bumper_mesh = eng.asset.cylinder(0.38, 0.42, 0.45, 16)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.table_tex = eng.procgen.texture("sci_fi_panel", seed, 64)

    S.sfx_plunge = eng.audio.synth("saw", 180, 0.14, 540)
    S.sfx_flip = eng.audio.synth("square", 310, 0.06, 520)
    S.sfx_bumper = eng.audio.synth("triangle", 620, 0.10, 980)
    S.sfx_jackpot = eng.audio.synth("sine", 480, 0.22, 1120)

    -- Main table bed & cabinet walls
    add_wall(0, "playfield_bed", 0.2, -0.25, 0.0, 6.8, 0.5, 12.0, S.box_mesh, { tex = S.table_tex, color = {0.16, 0.18, 0.32, 1.0} }, 0.0)
    add_wall(0, "wall_left",   -3.1, 0.35, 0.0, 0.35, 0.7, 12.0, S.box_mesh, { color = {0.95, 0.20, 0.65, 1.0} }, 0.90)
    add_wall(0, "wall_right",   3.45, 0.35, 0.0, 0.35, 0.7, 12.0, S.box_mesh, { color = {0.20, 0.85, 1.0, 1.0} }, 0.90)
    add_wall(0, "wall_top",     0.2, 0.35, -5.85, 6.9, 0.7, 0.35, S.box_mesh, { color = {0.75, 0.30, 1.0, 1.0} }, 0.90)
    add_wall(0, "shooter_div",  2.45, 0.30, 0.8, 0.24, 0.6, 8.8, S.box_mesh, { color = {0.30, 0.75, 0.95, 1.0} }, 0.85)
    add_wall(0, "plunger_stop", 2.95, 0.30, 4.95, 0.75, 0.6, 0.35, S.box_mesh, { color = {1.0, 0.55, 0.15, 1.0} }, 0.20)

    -- Inlane funnel walls guiding ball cleanly onto Left & Right flippers
    add_wall(0, "funnel_l", -2.15, 0.28, 3.55, 1.55, 0.55, 0.45, S.box_mesh, { color = {0.95, 0.35, 0.80, 1.0} }, 0.85)
    add_wall(0, "funnel_r",  1.65, 0.28, 3.55, 1.35, 0.55, 0.45, S.box_mesh, { color = {0.25, 0.90, 0.95, 1.0} }, 0.85)

    -- Left & Right Flippers
    S.flip_l = eng.scene.spawn("flipper_left")
    eng.scene.set_pos(S.flip_l, -0.82, 0.22, 4.55)
    eng.scene.set_scale(S.flip_l, 1.25, 0.32, 0.26)
    eng.scene.set_mesh(S.flip_l, S.box_mesh, { color = {1.0, 0.90, 0.20, 1.0}, cast_shadow = true })

    S.flip_r = eng.scene.spawn("flipper_right")
    eng.scene.set_pos(S.flip_r, 0.52, 0.22, 4.55)
    eng.scene.set_scale(S.flip_r, 1.25, 0.32, 0.26)
    eng.scene.set_mesh(S.flip_r, S.box_mesh, { color = {1.0, 0.90, 0.20, 1.0}, cast_shadow = true })

    -- Spawn 3 Main Jet Bumpers
    for i = 1, #BUMPERS do
        local b = BUMPERS[i]
        local e = eng.scene.spawn("jet_bumper_" .. tostring(i))
        eng.scene.set_pos(e, b.x, 0.24, b.z)
        eng.scene.set_mesh(e, S.bumper_mesh, { color = b.color, cast_shadow = true })
    end

    -- Upper Bonus Deck in isolated pocket "upper_deck" linked via Neon Ramp Portal
    local ramp_arch = eng.scene.spawn("upper_ramp_gate")
    eng.scene.set_pos(ramp_arch, -1.95, 0.0, -4.2)
    eng.scene.set_scale(ramp_arch, 0.75, 0.75, 0.75)
    eng.scene.set_mesh(ramp_arch, S.arch_mesh, { color = {1.0, 0.85, 0.25, 1.0} })

    add_wall(S.upper_pocket, "upper_bed", 0.0, -0.25, 0.0, 4.4, 0.5, 8.0, S.box_mesh, { tex = S.table_tex, color = {0.28, 0.14, 0.36, 1.0} }, 0.0)
    add_wall(S.upper_pocket, "upper_wl", -2.1, 0.30, 0.0, 0.3, 0.6, 8.0, S.box_mesh, { color = {1.0, 0.75, 0.2, 1.0} }, 0.90)
    add_wall(S.upper_pocket, "upper_wr",  2.1, 0.30, 0.0, 0.3, 0.6, 8.0, S.box_mesh, { color = {1.0, 0.75, 0.2, 1.0} }, 0.90)
    add_wall(S.upper_pocket, "upper_wt",  0.0, 0.30, -3.9, 4.4, 0.6, 0.3, S.box_mesh, { color = {1.0, 0.35, 0.8, 1.0} }, 0.92)

    for i = 1, #UPPER_BUMPERS do
        local ub = UPPER_BUMPERS[i]
        local ue = eng.scene.spawn("upper_bumper_" .. tostring(i))
        eng.scene.set_pocket(ue, S.upper_pocket)
        eng.scene.set_pos(ue, ub.x, 0.24, ub.z)
        eng.scene.set_mesh(ue, S.bumper_mesh, { color = {1.0, 0.88, 0.22, 1.0}, cast_shadow = true })
    end

    local p_src = eng.scene.spawn("pinball_portal_src")
    eng.scene.set_pocket(p_src, 0)
    eng.scene.set_pos(p_src, -1.95, 0.85, -4.2)

    local p_dst = eng.scene.spawn("pinball_portal_dst")
    eng.scene.set_pocket(p_dst, S.upper_pocket)
    eng.scene.set_pos(p_dst, 0.0, 0.85, 3.1)
    eng.scene.set_rot_deg(p_dst, 0.0, 180.0, 0.0)
    eng.portal.link(p_src, p_dst, 1.6, 1.6, 1.0, true, true)

    S.score = 0
    S.balls_left = 3
    S.bumper_hits = 0
    S.upper_visits = 0
    S.flipper_hits = 0
    S.flip_l_ang = -22.0
    S.flip_r_ang = 22.0
    S.won = false
    spawn_ball_in_shooter()
    eng.camera.look_at(0.2, 8.8, 8.2, 0.0, 0.0, -0.8, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    local l_act = eng.input.down("left") or eng.input.down("fire")
    local r_act = eng.input.down("right") or eng.input.down("interact")
    local l_swing = eng.input.pressed("left") or eng.input.pressed("fire")

    S.flip_l_ang = l_act and 28.0 or -22.0
    S.flip_r_ang = r_act and -28.0 or 22.0
    eng.scene.set_rot_deg(S.flip_l, 0.0, S.flip_l_ang, 0.0)
    eng.scene.set_rot_deg(S.flip_r, 0.0, S.flip_r_ang, 0.0)

    local pk = eng.scene.get_pocket(S.ball_ent)
    local bx, by, bz = eng.scene.get_pos(S.ball_ent)
    local vx, vy, vz = eng.physics.get_vel(S.ball_body)

    -- Spring plunger launch in shooter lane
    if pk == 0 and bx > 2.50 and bz > 3.5 then
        if eng.input.down("jump") or eng.input.pressed("jump") or l_swing then
            S.in_shooter = false
            eng.physics.set_vel(S.ball_body, 0.0, 0.0, -18.5)
            eng.audio.play(S.sfx_plunge, bx, by, bz, 0)
            return
        end
    end

    -- Top shooter arch curve deflecting launched ball into Jet Bumpers
    if pk == 0 and bx > 2.2 and bz < -4.5 and vz < 0.0 then
        eng.physics.set_vel(S.ball_body, -7.8, 0.0, 3.2)
        return
    end

    -- Track upper bonus pocket entry & jackpot bumpers
    if pk == S.upper_pocket then
        if not S.was_upper then
            S.was_upper = true
            S.upper_visits = S.upper_visits + 1
            S.score = S.score + 1200
            eng.audio.play(S.sfx_jackpot, bx, by, bz, pk)
        end
        for i = 1, #UPPER_BUMPERS do
            local ub = UPPER_BUMPERS[i]
            local dx, dz = bx - ub.x, bz - ub.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d < ub.r + 0.18 and d > 0.001 then
                eng.physics.set_vel(S.ball_body, (dx / d) * 8.5, 0.0, (dz / d) * 8.5 + 2.5)
                S.score = S.score + 750
                S.bumper_hits = S.bumper_hits + 1
                eng.audio.play(S.sfx_jackpot, bx, by, bz, pk)
            end
        end
    else
        S.was_upper = false
    end

    -- Main playfield Neon Jet Bumpers
    if pk == 0 then
        for i = 1, #BUMPERS do
            local b = BUMPERS[i]
            local dx, dz = bx - b.x, bz - b.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d < b.r + 0.18 and d > 0.001 then
                eng.physics.set_vel(S.ball_body, (dx / d) * 9.5, 0.0, math.max((dz / d) * 9.5, 3.5))
                S.score = S.score + 400
                S.bumper_hits = S.bumper_hits + 1
                eng.audio.play(S.sfx_bumper, bx, by, bz, 0)
            end
        end

        -- Funnel slide toward flippers
        if bz > 2.9 and bz < 4.2 and bx < -1.05 then
            eng.physics.set_vel(S.ball_body, 4.2, 0.0, math.max(vz, 3.0))
        elseif bz > 2.9 and bz < 4.2 and bx > 0.85 and bx < 2.35 then
            eng.physics.set_vel(S.ball_body, -4.2, 0.0, math.max(vz, 3.0))
        end

        -- Left & Right Flipper active bat impulse
        if bz > 3.85 and bz < 5.15 then
            if bx >= -1.75 and bx <= 0.05 and l_act then
                local tx = (S.upper_visits == 0) and -1.95 or 0.35
                eng.physics.set_vel(S.ball_body, (tx - bx) * 1.75, 0.0, -17.8)
                S.flipper_hits = S.flipper_hits + 1
                S.score = S.score + 200
                eng.audio.play(S.sfx_flip, bx, by, bz, 0)
            elseif bx > 0.05 and bx <= 1.55 and r_act then
                local tx = (S.upper_visits == 0) and -1.95 or -0.35
                eng.physics.set_vel(S.ball_body, (tx - bx) * 1.75, 0.0, -17.8)
                S.flipper_hits = S.flipper_hits + 1
                S.score = S.score + 200
                eng.audio.play(S.sfx_flip, bx, by, bz, 0)
            end
        end

        -- Drain check & ball saver / respawn
        if bz > 5.8 or by < -1.0 then
            if S.balls_left > 1 then
                S.balls_left = S.balls_left - 1
            end
            spawn_ball_in_shooter()
            return
        end
    end

    if S.score >= 2500 and S.bumper_hits >= 2 and S.upper_visits >= 1 then
        S.won = true
        eng.save.write("pinball_best", tostring(S.score))
        return
    end

    if pk == S.upper_pocket then
        eng.camera.look_at(0.0, 6.2, 6.2, 0.0, 0.0, -1.0, S.upper_pocket)
    else
        eng.camera.look_at(0.2, 8.8, 8.2, 0.0, 0.0, -0.8, 0)
    end
end

function draw()
    for i = 1, #BUMPERS do
        eng.render.draw_sprite(BUMPERS[i].x, 0.72, BUMPERS[i].z, 0.55, 0.55, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | SCORE " .. S.score .. "/2500 | BALLS " .. S.balls_left, 1.0, {0.4, 0.95, 1.0, 1.0})
end
