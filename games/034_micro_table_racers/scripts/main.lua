-- 034_micro_table_racers: Top-down diorama toy car racing around books, mugs & rulers on a tabletop
local S = game.state

local WAYPOINTS = {
    { 9.0, -5.5 }, { 9.5, 5.0 }, { 1.5, 7.2 },
    { -9.0, 5.2 }, { -9.5, -5.0 }, { -0.5, -7.2 }
}

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.24, 0.30, 0.44, 0.65, 0.60, 0.52)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {2.2, 2.05, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 14.0, 0.0}, color = {1.8, 1.6, 1.3}, range = 45.0 })

    local seed = math.floor(eng.math.range(100, 70000))
    local desk_tex = eng.procgen.texture("wood_planks", seed, 64)
    local ruler_tex = eng.procgen.texture("marble", seed + 7, 64)

    local desk_mesh = eng.asset.box(34.0, 0.8, 26.0)
    local book_mesh = eng.asset.box(5.4, 1.1, 3.6)
    local mug_mesh = eng.asset.cylinder(1.5, 1.6, 2.8, 14)
    local ruler_mesh = eng.asset.box(7.5, 0.16, 1.4)
    local car_mesh = eng.asset.box(0.85, 0.45, 1.35)
    local sugar_mesh = eng.asset.box(0.55, 0.55, 0.55)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_boost = eng.audio.synth("saw", 420, 0.12, 920)
    S.sfx_lap = eng.audio.synth("triangle", 580, 0.22, 1160)

    local desk = eng.scene.spawn("tabletop")
    eng.scene.set_pos(desk, 0.0, -0.4, 0.0)
    eng.scene.set_mesh(desk, desk_mesh, { tex = desk_tex, color = {0.72, 0.48, 0.28, 1.0}, roughness = 0.7 })

    -- Infield stack of hardcover books
    local book_cols = { {0.82, 0.20, 0.22, 1.0}, {0.18, 0.42, 0.78, 1.0}, {0.20, 0.65, 0.36, 1.0} }
    for i = 1, 3 do
        local b = eng.scene.spawn("book_" .. tostring(i))
        eng.scene.set_pos(b, -1.5 + (i - 2) * 0.4, (i - 0.5) * 1.1, 0.2)
        eng.scene.set_rot_deg(b, 0.0, (i - 2) * 14.0, 0.0)
        eng.scene.set_mesh(b, book_mesh, { color = book_cols[i], cast_shadow = true })
    end

    -- Giant ceramic coffee mugs at circuit corners
    local mug_pts = { {4.6, -1.8}, {-5.2, 1.8}, {13.2, 0.0} }
    for i = 1, #mug_pts do
        local m = eng.scene.spawn("coffee_mug_" .. tostring(i))
        eng.scene.set_pos(m, mug_pts[i][1], 1.4, mug_pts[i][2])
        eng.scene.set_mesh(m, mug_mesh, { color = {0.95, 0.92, 0.86, 1.0}, roughness = 0.25, cast_shadow = true })
    end

    -- Yellow wooden rulers framing straightaways
    for i = -1, 1, 2 do
        local r = eng.scene.spawn("ruler_" .. tostring(i))
        eng.scene.set_pos(r, i * 4.5, 0.08, i * 9.6)
        eng.scene.set_mesh(r, ruler_mesh, { tex = ruler_tex, color = {0.96, 0.84, 0.22, 1.0} })
    end

    -- Sugar-cube turbo pickups along circuit
    S.sugars = {}
    for i = 1, 3 do
        local wp = WAYPOINTS[i * 2 - 1]
        local se = eng.scene.spawn("sugar_turbo_" .. tostring(i))
        eng.scene.set_pos(se, wp[1], 0.3, wp[2])
        eng.scene.set_mesh(se, sugar_mesh, { color = {1.0, 1.0, 1.0, 1.0} })
        S.sugars[i] = { ent = se, x = wp[1], z = wp[2], cd = 0.0 }
    end

    -- Player Micro Toy Car + 2 AI Rival Micro Cars
    S.car = eng.scene.spawn("player_micro_car")
    eng.scene.set_mesh(S.car, car_mesh, { color = {1.0, 0.24, 0.18, 1.0}, metallic = 0.5, roughness = 0.3, cast_shadow = true })

    S.rivals = {}
    local rcols = { {0.20, 0.78, 1.0, 1.0}, {0.98, 0.82, 0.15, 1.0} }
    for i = 1, 2 do
        local re = eng.scene.spawn("rival_micro_car_" .. tostring(i))
        eng.scene.set_mesh(re, car_mesh, { color = rcols[i], metallic = 0.5, roughness = 0.3, cast_shadow = true })
        S.rivals[i] = { ent = re, x = 1.0 + i * 1.1, z = -7.2, yaw = -90.0, wp = 1, laps = 0, spd = 19.5 + i * 1.8 }
        eng.scene.set_pos(re, S.rivals[i].x, 0.25, S.rivals[i].z)
    end

    S.cx, S.cz = -0.5, -7.2
    S.yaw = -90.0
    S.spd = 0.0
    S.boost_t = 0.0
    S.drift_charge = 0.0
    S.wp_idx = 1
    S.laps = 0
    S.turbos = 0
    S.rank = 1
    S.score = 0
    S.won = false

    sync_table_cam()
    eng.mod.emit("post_init")
end

function sync_table_cam()
    eng.scene.set_pos(S.car, S.cx, 0.25, S.cz)
    eng.scene.set_rot_deg(S.car, 0.0, S.yaw, 0.0)
    -- Overhead diorama camera framing the tabletop, books, mugs & toy cars
    eng.camera.look_at(S.cx * 0.35, 17.5, S.cz * 0.35 + 12.5, S.cx * 0.45, 0.4, S.cz * 0.45, 0)
end

function update(dt)
    if S.won then return end
    S.boost_t = math.max(0.0, S.boost_t - dt)

    local steer, thr = eng.input.axis2d("left", "right", "down", "up")
    local turn_rate = (eng.input.down("jump") or eng.input.down("fire")) and 360.0 or 295.0
    S.yaw = S.yaw - steer * turn_rate * dt

    if math.abs(steer) > 0.2 and (eng.input.down("jump") or eng.input.down("fire")) then
        S.drift_charge = math.min(1.0, S.drift_charge + 2.4 * dt)
    elseif S.drift_charge >= 0.35 then
        S.drift_charge = 0.0
        S.boost_t = 0.7
        S.turbos = S.turbos + 1
        eng.audio.play(S.sfx_boost, S.cx, 0.3, S.cz, 0)
    end

    local top = (S.boost_t > 0.0) and 36.0 or 29.0
    if thr > 0.05 then
        S.spd = math.min(top, S.spd + 48.0 * thr * dt)
    elseif thr < -0.05 then
        S.spd = math.max(-8.0, S.spd + 35.0 * thr * dt)
    else
        S.spd = S.spd * math.max(0.0, 1.0 - 3.5 * dt)
    end

    local rad = math.rad(S.yaw)
    S.cx = eng.math.clamp(S.cx - math.sin(rad) * S.spd * dt, -15.5, 15.5)
    S.cz = eng.math.clamp(S.cz - math.cos(rad) * S.spd * dt, -11.5, 11.5)

    -- Sugar-cube turbo pickups
    for i = 1, #S.sugars do
        local sg = S.sugars[i]
        sg.cd = math.max(0.0, sg.cd - dt)
        if sg.cd <= 0.0 and eng.math.dist3(S.cx, 0.0, S.cz, sg.x, 0.0, sg.z) < 2.6 then
            sg.cd = 1.5
            S.boost_t = 0.75
            S.spd = 36.0
            S.turbos = S.turbos + 1
            S.score = S.score + 120
            eng.audio.play(S.sfx_boost, sg.x, 0.3, sg.z, 0)
        end
    end

    -- Player waypoint & lap progression
    local wp = WAYPOINTS[S.wp_idx]
    if eng.math.dist3(S.cx, 0.0, S.cz, wp[1], 0.0, wp[2]) < 3.8 then
        S.wp_idx = S.wp_idx + 1
        S.score = S.score + 75
        if S.wp_idx > #WAYPOINTS then
            S.wp_idx = 1
            S.laps = S.laps + 1
            eng.audio.play(S.sfx_lap, S.cx, 0.3, S.cz, 0)
        end
    end

    -- Step AI rival micro cars
    local player_prog = S.laps * #WAYPOINTS + S.wp_idx
    local ahead = 0
    for i = 1, #S.rivals do
        local rv = S.rivals[i]
        local rwp = WAYPOINTS[rv.wp]
        local dx, dz = rwp[1] - rv.x, rwp[2] - rv.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 0.2 then
            rv.x = rv.x + (dx / d) * rv.spd * dt
            rv.z = rv.z + (dz / d) * rv.spd * dt
            rv.yaw = math.deg(math.atan2(-dx, -dz))
        end
        if d < 2.2 then
            rv.wp = rv.wp + 1
            if rv.wp > #WAYPOINTS then rv.wp = 1; rv.laps = rv.laps + 1 end
        end
        eng.scene.set_pos(rv.ent, rv.x, 0.25, rv.z)
        eng.scene.set_rot_deg(rv.ent, 0.0, rv.yaw, 0.0)
        if (rv.laps * #WAYPOINTS + rv.wp) > player_prog then ahead = ahead + 1 end
    end
    S.rank = 1 + ahead

    if S.laps >= 2 then
        S.won = true
        S.score = S.score + (S.rank == 1 and 500 or 200)
        eng.save.write("micro_table_cup", tostring(S.rank))
    end

    sync_table_cam()
end

function draw()
    local wp = WAYPOINTS[S.wp_idx]
    eng.render.draw_sprite(wp[1], 1.1, wp[2], 0.85, 0.85, S.orb_tex)
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 52, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | POS %d/3 | LAP %d/2 | SCORE %d", S.rank, math.min(2, S.laps + 1), S.score), 1.0, {1.0, 0.88, 0.35, 1.0})
    eng.ui.bar(x, y + 26, 220, math.min(1.0, S.spd / 38.0), "SPEED ")
end
