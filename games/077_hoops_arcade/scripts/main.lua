-- 077_hoops_arcade: Charge Shot Arc (fire) & Laterally Moving Backboard/Rim Streak Multipliers
local S = game.state

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.05, 0.04, 0.12, 0.18, 0.10, 0.24)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {1.8, 1.7, 1.55}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.0, -1.5}, color = {2.4, 1.5, 0.8}, range = 20.0 })

    eng.physics.set_gravity(0, 0.0, -9.81, 0.0)

    local seed = math.floor(eng.math.range(10, 50000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ball_mesh = eng.asset.sphere(0.17, 14, 18)
    S.rim_mesh = eng.asset.cylinder(0.38, 0.36, 0.08, 18)
    S.net_mesh = eng.asset.cylinder(0.34, 0.22, 0.42, 14)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.court_tex = eng.procgen.texture("wood_planks", seed, 64)
    S.cage_tex = eng.procgen.texture("sci_fi_panel", seed + 9, 64)

    S.sfx_release = eng.audio.synth("triangle", 280, 0.07, 420)
    S.sfx_rim = eng.audio.synth("square", 390, 0.06, 210)
    S.sfx_swish = eng.audio.synth("noise", 680, 0.12, 320)
    S.sfx_streak = eng.audio.synth("sine", 520, 0.16, 980)

    -- Hardwood arcade cabinet court & side rails
    local court = eng.scene.spawn("arcade_court")
    eng.scene.set_pos(court, 0.0, -0.25, 0.0)
    eng.scene.set_scale(court, 6.4, 0.5, 10.4)
    eng.scene.set_mesh(court, S.box_mesh, { tex = S.court_tex, roughness = 0.25 })
    eng.physics.add_body(court, { shape = "aabb", motion = "static", half_extents = {3.2, 0.25, 5.2}, restitution = 0.65 })

    local wl = eng.scene.spawn("cage_left")
    eng.scene.set_pos(wl, -3.1, 1.4, 0.0)
    eng.scene.set_scale(wl, 0.2, 2.8, 10.4)
    eng.scene.set_mesh(wl, S.box_mesh, { tex = S.cage_tex, color = {0.22, 0.30, 0.55, 1.0} })

    local wr = eng.scene.spawn("cage_right")
    eng.scene.set_pos(wr, 3.1, 1.4, 0.0)
    eng.scene.set_scale(wr, 0.2, 2.8, 10.4)
    eng.scene.set_mesh(wr, S.box_mesh, { tex = S.cage_tex, color = {0.22, 0.30, 0.55, 1.0} })

    -- Laterally moving Backboard, Orange Rim & White Net
    S.hoop_x = 0.0
    S.hoop_phase = 0.0
    S.board_ent = eng.scene.spawn("moving_backboard")
    eng.scene.set_pos(S.board_ent, 0.0, 3.55, -4.05)
    eng.scene.set_scale(S.board_ent, 1.85, 1.25, 0.12)
    eng.scene.set_mesh(S.board_ent, S.box_mesh, { color = {0.92, 0.96, 1.0, 1.0}, cast_shadow = true })
    S.board_body = eng.physics.add_body(S.board_ent, { shape = "aabb", motion = "kinematic", half_extents = {0.925, 0.625, 0.06}, restitution = 0.68 })

    S.rim_ent = eng.scene.spawn("orange_rim")
    eng.scene.set_pos(S.rim_ent, 0.0, 3.05, -3.55)
    eng.scene.set_mesh(S.rim_ent, S.rim_mesh, { color = {1.0, 0.36, 0.08, 1.0}, cast_shadow = true })

    S.net_ent = eng.scene.spawn("hoop_net")
    eng.scene.set_pos(S.net_ent, 0.0, 2.80, -3.55)
    eng.scene.set_mesh(S.net_ent, S.net_mesh, { color = {0.92, 0.92, 0.95, 1.0} })

    -- Held preview basketball at shooter hands
    S.held_ent = eng.scene.spawn("held_basketball")
    eng.scene.set_pos(S.held_ent, 0.0, 1.35, 3.60)
    eng.scene.set_mesh(S.held_ent, S.ball_mesh, { color = {0.96, 0.44, 0.10, 1.0}, roughness = 0.65, cast_shadow = true })

    S.aim_x = 0.0
    S.charge = 0.0
    S.charging = false
    S.cooldown = 0.0
    S.shots = {}
    S.baskets = 0
    S.streak = 0
    S.max_streak = 0
    S.score = 0
    S.won = false

    eng.camera.look_at(0.0, 2.8, 6.8, 0.0, 2.4, -3.6, 0)
    eng.mod.emit("post_init")
end

local function release_shot()
    S.cooldown = 0.22
    -- Flight time T scales smoothly with charge (sweet spot charge = 0.75 -> T = 0.85s)
    local pwr = eng.math.clamp(S.charge, 0.25, 1.0)
    local flight_t = 0.85
    local vx = (S.aim_x - 0.0) / flight_t
    local vz = (-3.55 - 3.60) / flight_t * (0.68 + pwr * 0.4267)
    local vy = 3.93 + pwr * 3.05

    local be = eng.scene.spawn("shot_ball_" .. tostring(#S.shots + 1))
    eng.scene.set_pos(be, 0.0, 1.35, 3.60)
    eng.scene.set_mesh(be, S.ball_mesh, { color = {0.96, 0.44, 0.10, 1.0}, roughness = 0.65, cast_shadow = true })
    local bid = eng.physics.add_body(be, {
        shape = "sphere", motion = "dynamic", radius = 0.17, vel = {vx, vy, vz}, restitution = 0.70
    })
    S.shots[#S.shots + 1] = { ent = be, body = bid, prev_y = 1.35, scored = false, alive = true, rim_hit = false }
    S.charge = 0.0
    eng.audio.play(S.sfx_release, 0.0, 1.35, 3.60, 0)
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)

    -- Laterally oscillate Backboard & Rim across cabinet
    local prev_hx = S.hoop_x
    local omega = 1.25 + math.min(S.baskets, 5) * 0.12
    S.hoop_phase = S.hoop_phase + omega * dt
    S.hoop_x = math.sin(S.hoop_phase) * 1.75
    if dt > 0.0 then
        eng.physics.set_vel(S.board_body, (S.hoop_x - prev_hx) / dt, 0.0, 0.0)
    end
    eng.scene.set_pos(S.board_ent, S.hoop_x, 3.55, -4.05)
    eng.scene.set_pos(S.rim_ent, S.hoop_x, 3.05, -3.55)
    eng.scene.set_pos(S.net_ent, S.hoop_x, 2.80, -3.55)

    local mx, _ = eng.input.axis2d("left", "right", "down", "up")
    S.aim_x = eng.math.clamp(S.aim_x + mx * 7.5 * dt, -2.5, 2.5)

    if eng.input.down("fire") and S.cooldown <= 0.0 then
        S.charging = true
        S.charge = math.min(1.0, S.charge + 2.8 * dt)
    elseif S.charging then
        S.charging = false
        release_shot()
    end

    eng.scene.set_pos(S.held_ent, S.aim_x * 0.12, 1.35 + S.charge * 0.30, 3.60)

    -- Track airborne basketballs & check rim rattle / clean swish!
    for i = #S.shots, 1, -1 do
        local sh = S.shots[i]
        if sh.alive then
            local bx, by, bz = eng.scene.get_pos(sh.ent)
            local vx, vy, vz = eng.physics.get_vel(sh.body)

            -- Check downward crossing of rim plane y = 3.05 at z = -3.55
            if not sh.scored and sh.prev_y >= 3.00 and by < 3.05 and vy < 0.0 then
                local rdist = eng.math.dist3(bx, 0, bz, S.hoop_x, 0, -3.55)
                if rdist < 0.42 then
                    sh.scored = true
                    S.baskets = S.baskets + 1
                    S.streak = S.streak + 1
                    if S.streak > S.max_streak then S.max_streak = S.streak end
                    local mult = math.min(4, S.streak)
                    S.score = S.score + 100 * mult
                    eng.physics.set_vel(sh.body, vx * 0.25, vy * 0.65, vz * 0.25)
                    eng.audio.play(S.sfx_swish, S.hoop_x, 3.05, -3.55, 0)
                    if S.streak >= 2 then eng.audio.play(S.sfx_streak, S.hoop_x, 3.2, -3.55, 0) end
                elseif rdist < 0.56 then
                    sh.rim_hit = true
                    eng.physics.set_vel(sh.body, (bx - S.hoop_x) * 4.0, 3.2, (bz + 3.55) * 4.0)
                    eng.audio.play(S.sfx_rim, bx, by, bz, 0)
                end
            end
            sh.prev_y = by

            if by < 0.25 or bz < -5.2 or bz > 5.5 then
                if not sh.scored then S.streak = 0 end
                sh.alive = false
                eng.scene.despawn(sh.ent)
                table.remove(S.shots, i)
            end
        end
    end

    if S.baskets >= 5 and S.max_streak >= 3 then
        S.won = true
        eng.save.write("hoops_highscore", tostring(S.score))
    end
end

function draw()
    -- Aim arc preview marker at rim height
    eng.render.draw_sprite(S.aim_x, 3.10, -3.55, 0.28, 0.28, S.orb_tex)
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 28, 1280, 720)
    local mult = math.max(1, math.min(4, S.streak))
    eng.ui.label(x, y, eng.i18n.t("title") .. " | BASKETS " .. S.baskets .. "/5 | STREAK x" .. mult .. " | SCORE " .. S.score, 1.0, {1.0, 0.72, 0.25, 1.0})
    eng.ui.bar(x, y + 26, 200, S.charge, "ARC ")
end
