-- 076_billiards_lounge: 3D Pool Table Impulse & 6-Pocket Collision Physics (Sink All Object Balls Without Scratching)
local S = game.state

local POCKETS = {
    { -1.30, -2.48 }, {  1.30, -2.48 },
    { -1.36,  0.00 }, {  1.36,  0.00 },
    { -1.30,  2.48 }, {  1.30,  2.48 }
}

local BALL_COLORS = {
    {1.00, 0.85, 0.12, 1.0}, -- 1 Yellow
    {0.18, 0.42, 0.95, 1.0}, -- 2 Blue
    {0.92, 0.20, 0.20, 1.0}, -- 3 Red
    {0.62, 0.22, 0.85, 1.0}, -- 4 Purple
    {1.00, 0.50, 0.12, 1.0}, -- 5 Orange
    {0.15, 0.78, 0.35, 1.0}  -- 6 Green
}

local function add_cushion(name, x, z, sx, sz, tex)
    local e = eng.scene.spawn(name)
    eng.scene.set_pos(e, x, 0.92, z)
    eng.scene.set_scale(e, sx, 0.24, sz)
    eng.scene.set_mesh(e, S.box_mesh, { tex = tex, color = {0.55, 0.30, 0.16, 1.0}, cast_shadow = true })
    eng.physics.add_body(e, { shape = "aabb", motion = "static", half_extents = {sx * 0.5, 0.12, sz * 0.5}, restitution = 0.92 })
end

local function spawn_cue_ball()
    if S.cue_ent then eng.scene.despawn(S.cue_ent) end
    S.cue_ent = eng.scene.spawn("cue_ball")
    eng.scene.set_pos(S.cue_ent, 0.0, 0.91, 1.35)
    eng.scene.set_mesh(S.cue_ent, S.ball_mesh, { color = {0.98, 0.98, 0.95, 1.0}, roughness = 0.12, cast_shadow = true })
    S.cue_body = eng.physics.add_body(S.cue_ent, { shape = "sphere", motion = "dynamic", radius = 0.11, restitution = 0.94 })
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.05, 0.04, 0.06, 0.16, 0.11, 0.09)
    eng.render.add_light({ type = "dir", dir = {-0.2, -1.0, -0.25}, color = {1.5, 1.45, 1.35}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 3.2, 0.0}, color = {2.4, 2.1, 1.6}, range = 14.0 })

    -- Calibrated felt rolling resistance
    eng.physics.set_gravity(0, 0.0, -4.2, 0.0)

    local seed = math.floor(eng.math.range(10, 40000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ball_mesh = eng.asset.sphere(0.11, 14, 18)
    S.pocket_mesh = eng.asset.cylinder(0.24, 0.24, 0.05, 16)
    S.stick_mesh = eng.asset.cylinder(0.025, 0.04, 1.4, 10)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.felt_tex = eng.procgen.texture("grass", seed, 64)
    S.wood_tex = eng.procgen.texture("wood_planks", seed + 11, 64)

    S.sfx_cue = eng.audio.synth("triangle", 320, 0.06, 180)
    S.sfx_clack = eng.audio.synth("square", 640, 0.04, 420)
    S.sfx_pocket = eng.audio.synth("sine", 280, 0.16, 560)
    S.sfx_scratch = eng.audio.synth("saw", 220, 0.22, 95)

    -- Emerald felt bed (top at y = 0.80)
    local bed = eng.scene.spawn("pool_slate_bed")
    eng.scene.set_pos(bed, 0.0, 0.40, 0.0)
    eng.scene.set_scale(bed, 3.0, 0.80, 5.4)
    eng.scene.set_mesh(bed, S.box_mesh, { tex = S.felt_tex, color = {0.10, 0.58, 0.34, 1.0}, roughness = 0.85 })
    eng.physics.add_body(bed, { shape = "aabb", motion = "static", half_extents = {1.5, 0.40, 2.7}, restitution = 0.0 })

    -- Split mahogany cushion rails leaving 6 open pocket jaws
    add_cushion("rail_top",  0.00, -2.62, 1.96, 0.22, S.wood_tex)
    add_cushion("rail_bot",  0.00,  2.62, 1.96, 0.22, S.wood_tex)
    add_cushion("rail_ul",  -1.48, -1.24, 0.22, 1.88, S.wood_tex)
    add_cushion("rail_ll",  -1.48,  1.24, 0.22, 1.88, S.wood_tex)
    add_cushion("rail_ur",   1.48, -1.24, 0.22, 1.88, S.wood_tex)
    add_cushion("rail_lr",   1.48,  1.24, 0.22, 1.88, S.wood_tex)

    for i = 1, #POCKETS do
        local pe = eng.scene.spawn("pocket_cup_" .. tostring(i))
        eng.scene.set_pos(pe, POCKETS[i][1], 0.81, POCKETS[i][2])
        eng.scene.set_mesh(pe, S.pocket_mesh, { color = {0.05, 0.05, 0.06, 1.0} })
        POCKETS[i][3] = pe
    end

    -- 3-Row 6-Ball Triangle Rack (zero initial collider overlap: spacing 0.25m > 0.22m)
    S.balls = {}
    local n = 0
    for row = 1, 3 do
        local z = -0.85 - (row - 1) * 0.23
        local x0 = -(row - 1) * 0.125
        for col = 1, row do
            n = n + 1
            local x = x0 + (col - 1) * 0.25
            local be = eng.scene.spawn("obj_ball_" .. tostring(n))
            eng.scene.set_pos(be, x, 0.91, z)
            eng.scene.set_mesh(be, S.ball_mesh, { color = BALL_COLORS[n], roughness = 0.14, cast_shadow = true })
            local bid = eng.physics.add_body(be, { shape = "sphere", motion = "dynamic", radius = 0.11, restitution = 0.94 })
            S.balls[n] = { id = n, ent = be, body = bid, sunk = false }
        end
    end

    spawn_cue_ball()

    S.stick_ent = eng.scene.spawn("cue_stick")
    eng.scene.set_pos(S.stick_ent, 0.0, 1.05, 2.2)
    eng.scene.set_rot_deg(S.stick_ent, 82.0, 0.0, 0.0)
    eng.scene.set_mesh(S.stick_ent, S.stick_mesh, { tex = S.wood_tex, color = {0.88, 0.68, 0.42, 1.0} })

    S.aim_yaw = 0.0
    S.shot_power = 0.75
    S.balls_moving = false
    S.shots = 0
    S.sunk_count = 0
    S.scratches = 0
    S.score = 0
    S.POCKETS = POCKETS
    S.won = false

    eng.camera.look_at(0.0, 4.4, 3.8, 0.0, 0.8, -0.4, 0)
    eng.mod.emit("post_init")
end

local function near_any_pocket(x, z, rad)
    for i = 1, #POCKETS do
        local dx, dz = x - POCKETS[i][1], z - POCKETS[i][2]
        if (dx * dx + dz * dz) <= rad * rad then return true end
    end
    return false
end

function strike_cue(spd_override)
    if S.balls_moving or S.won then return end
    local rad = math.rad(S.aim_yaw)
    local spd = spd_override or (6.5 + S.shot_power * 12.5)
    eng.physics.set_vel(S.cue_body, -math.sin(rad) * spd, 0.0, -math.cos(rad) * spd)
    S.balls_moving = true
    S.shots = S.shots + 1
    local cx, cy, cz = eng.scene.get_pos(S.cue_ent)
    eng.audio.play(S.sfx_cue, cx, cy, cz, 0)
end

function update(dt)
    if S.won then return end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local cx, cy, cz = eng.scene.get_pos(S.cue_ent)

    if not S.balls_moving then
        S.aim_yaw = S.aim_yaw - mx * 95.0 * dt
        S.shot_power = eng.math.clamp(S.shot_power + my * 0.8 * dt, 0.20, 1.0)
        local rad = math.rad(S.aim_yaw)
        eng.scene.set_pos(S.stick_ent, cx + math.sin(rad) * 0.95, 1.02, cz + math.cos(rad) * 0.95)
        eng.scene.set_rot_deg(S.stick_ent, 82.0, S.aim_yaw, 0.0)

        if eng.input.pressed("fire") or eng.input.pressed("jump") then
            eng.scene.set_pos(S.stick_ent, 0.0, -5.0, 0.0)
            strike_cue()
        end
        return
    end

    -- Check object ball pocketing
    for i = 1, #S.balls do
        local b = S.balls[i]
        if not b.sunk then
            local bx, by, bz = eng.scene.get_pos(b.ent)
            if near_any_pocket(bx, bz, 0.34) or by < 0.55 then
                b.sunk = true
                eng.scene.despawn(b.ent)
                S.sunk_count = S.sunk_count + 1
                S.score = S.score + 200
                eng.audio.play(S.sfx_pocket, bx, 0.85, bz, 0)
            else
                local vx, vy, vz = eng.physics.get_vel(b.body)
                if math.sqrt(vx * vx + vz * vz) < 0.32 then
                    eng.physics.set_vel(b.body, 0.0, vy, 0.0)
                end
            end
        end
    end

    -- Check cue ball scratch!
    cx, cy, cz = eng.scene.get_pos(S.cue_ent)
    if near_any_pocket(cx, cz, 0.25) or cy < 0.55 then
        S.scratches = S.scratches + 1
        S.score = math.max(0, S.score - 100)
        eng.audio.play(S.sfx_scratch, cx, 0.85, cz, 0)
        spawn_cue_ball()
        cx, cy, cz = eng.scene.get_pos(S.cue_ent)
    end

    if S.sunk_count >= #S.balls then
        S.won = true
        eng.save.write("billiards_clear", tostring(S.score))
        return
    end

    -- Check if all remaining balls have settled to rest
    local any_moving = false
    local cvx, cvy, cvz = eng.physics.get_vel(S.cue_body)
    if math.sqrt(cvx * cvx + cvz * cvz) < 0.32 then
        eng.physics.set_vel(S.cue_body, 0.0, cvy, 0.0)
    else
        any_moving = true
    end
    for i = 1, #S.balls do
        local b = S.balls[i]
        if not b.sunk then
            local vx, _, vz = eng.physics.get_vel(b.body)
            if math.sqrt(vx * vx + vz * vz) >= 0.32 then any_moving = true end
        end
    end
    S.balls_moving = any_moving
end

function draw()
    if not S.balls_moving and not S.won then
        local cx, _, cz = eng.scene.get_pos(S.cue_ent)
        local rad = math.rad(S.aim_yaw)
        eng.render.draw_sprite(cx - math.sin(rad) * 0.85, 0.96, cz - math.cos(rad) * 0.85, 0.14, 0.14, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | SUNK " .. S.sunk_count .. "/6 | SCRATCHES " .. S.scratches .. " | SCORE " .. S.score, 1.0, {0.55, 1.0, 0.72, 1.0})
end
