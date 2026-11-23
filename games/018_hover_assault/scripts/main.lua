-- 018_hover_assault: Low-friction inertial hovercraft combat arena with jump-ramps, boost pads, drift jets & twin plasma cannons
local S = game.state

local BOOST_PADS = {
    { x = 0.0,  z =  2.0 },
    { x = -6.5, z = -5.0 },
    { x =  6.5, z = -5.0 },
}

local RAMPS = {
    { x = 0.0, z = -3.0, pitch =  18.0 },
    { x = 0.0, z = -11.0, pitch = -18.0 },
}

local function spawn_wave(w)
    S.wave = w
    for i = 1, 3 do
        local ex = (i - 2) * 5.5
        local ez = -10.5 - w * 1.5
        local ee = eng.scene.spawn("skimmer_w" .. tostring(w) .. "_" .. tostring(i))
        eng.scene.set_pos(ee, ex, 1.1, ez)
        eng.scene.set_scale(ee, 0.9, 0.9, 0.9)
        eng.scene.set_rot_deg(ee, 0.0, 180.0, 0.0)
        eng.scene.set_mesh(ee, S.ship_mesh, { color = {1.0, 0.28, 0.32, 1.0}, metallic = 0.7, roughness = 0.25, cast_shadow = true })
        local bid = eng.physics.add_body(ee, { shape = "sphere", motion = "kinematic", radius = 1.45, trigger = true })
        S.enemies[#S.enemies + 1] = {
            ent = ee, body = bid, base_x = ex, x = ex, y = 1.1, z = ez,
            phase = i * 1.2 + w, hp = 2, alive = true
        }
    end
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.012 })
    eng.render.set_sky(0.05, 0.08, 0.22, 0.28, 0.14, 0.34)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {2.0, 1.9, 2.2}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 7.0, -5.0}, color = {0.8, 2.2, 2.8}, range = 36.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    local grid_tex = eng.asset.load_texture("assets/shared/textures/checker.png", true)
    local metal_tex = eng.procgen.texture("metal_rivets", S.seed, 64)

    S.sfx_plasma = eng.audio.synth("saw", 640, 0.08, 210)
    S.sfx_boost = eng.audio.synth("triangle", 360, 0.16, 880)
    S.sfx_boom = eng.audio.synth("noise", 220, 0.18, 65)

    local floor_e = eng.scene.spawn("hover_arena_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, -4.0)
    eng.scene.set_scale(floor_e, 40.0, 0.5, 40.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = grid_tex, color = {0.28, 0.34, 0.48, 1.0} })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {20.0, 0.25, 20.0} })

    for i = 1, #BOOST_PADS do
        local bp = BOOST_PADS[i]
        local pe = eng.scene.spawn("turbo_pad_" .. tostring(i))
        eng.scene.set_pos(pe, bp.x, 0.05, bp.z)
        eng.scene.set_scale(pe, 2.4, 0.10, 2.8)
        eng.scene.set_mesh(pe, S.box_mesh, { color = {0.20, 0.95, 1.0, 1.0} })
    end

    for i = 1, #RAMPS do
        local rp = RAMPS[i]
        local re = eng.scene.spawn("jump_ramp_" .. tostring(i))
        eng.scene.set_pos(re, rp.x, 0.35, rp.z)
        eng.scene.set_scale(re, 3.4, 0.25, 3.6)
        eng.scene.set_rot_deg(re, rp.pitch, 0.0, 0.0)
        eng.scene.set_mesh(re, S.box_mesh, { tex = metal_tex, color = {0.88, 0.65, 0.22, 1.0}, cast_shadow = true })
    end

    S.craft = eng.scene.spawn("player_hovercraft")
    eng.scene.set_pos(S.craft, 0.0, 0.9, 6.5)
    eng.scene.set_mesh(S.craft, S.ship_mesh, { color = {0.25, 0.85, 1.0, 1.0}, metallic = 0.8, roughness = 0.2, cast_shadow = true })

    S.bolt_ent = eng.scene.spawn("twin_plasma_beam")
    eng.scene.set_pos(S.bolt_ent, 0.0, -5.0, 0.0)
    eng.scene.set_scale(S.bolt_ent, 0.12, 0.12, 0.12)
    eng.scene.set_mesh(S.bolt_ent, S.box_mesh, { color = {0.35, 1.0, 0.65, 1.0} })
    S.bolt_timer = 0.0

    S.px, S.py, S.pz = 0.0, 0.9, 6.5
    S.vx, S.vy, S.vz = 0.0, 0.0, 0.0
    S.yaw = 0.0
    S.fire_cd = 0.0
    S.boost_cd = 0.0
    S.ramp_cd = 0.0
    S.drift_cd = 0.0
    S.wing_side = 1.0
    S.hp = 100
    S.boosts_used = 0
    S.ramps_launched = 0
    S.drifts_used = 0
    S.kills = 0
    S.score = 0
    S.won = false
    S.enemies = {}

    spawn_wave(1)
    eng.camera.look_at(S.px, S.py + 1.8, S.pz + 4.5, S.px, S.py + 0.4, S.pz - 6.0, 0)
    eng.mod.emit("post_init")
end

local function fire_twin_plasma()
    S.wing_side = -S.wing_side
    local rad = math.rad(S.yaw)
    local fwd_x, fwd_z = -math.sin(rad), -math.cos(rad)
    local rgt_x, rgt_z = math.cos(rad), -math.sin(rad)

    local ox = S.px + rgt_x * S.wing_side * 0.95
    local oy = S.py + 0.15
    local oz = S.pz + rgt_z * S.wing_side * 0.95

    -- Converge twin plasma cannons onto nearest skimmer inside forward combat cone
    local dx, dy, dz = fwd_x, 0.0, fwd_z
    local best_d = 28.0
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local ex, ey, ez = en.x - ox, en.y - oy, en.z - oz
            local d = math.sqrt(ex * ex + ey * ey + ez * ez)
            if d > 0.1 and d < best_d then
                local dot = (ex / d) * fwd_x + (ez / d) * fwd_z
                if dot > 0.45 then
                    best_d = d
                    dx, dy, dz = ex / d, ey / d, ez / d
                end
            end
        end
    end

    eng.audio.play(S.sfx_plasma, ox, oy, oz, 0)
    local hit = eng.physics.raycast(0, ox, oy, oz, dx, dy, dz, 32.0)
    local hx, hy, hz = ox + dx * 16.0, oy + dy * 16.0, oz + dz * 16.0
    if hit then
        hx, hy, hz = hit.point[1], hit.point[2], hit.point[3]
        for i = 1, #S.enemies do
            local en = S.enemies[i]
            if en.alive and en.ent == hit.entity then
                en.hp = en.hp - 1
                if en.hp <= 0 then
                    en.alive = false
                    eng.scene.despawn(en.ent)
                    S.kills = S.kills + 1
                    S.score = S.score + 200
                    eng.audio.play(S.sfx_boom, en.x, en.y, en.z, 0)
                end
                break
            end
        end
    end

    eng.scene.set_pos(S.bolt_ent, (ox + hx) * 0.5, (oy + hy) * 0.5, (oz + hz) * 0.5)
    eng.scene.set_scale(S.bolt_ent, math.max(0.12, math.abs(hx - ox)), math.max(0.12, math.abs(hy - oy)), math.max(0.12, math.abs(hz - oz)))
    S.bolt_timer = 0.06
end

function update(dt)
    if S.won then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.boost_cd = math.max(0.0, S.boost_cd - dt)
    S.ramp_cd = math.max(0.0, S.ramp_cd - dt)
    S.drift_cd = math.max(0.0, S.drift_cd - dt)

    if S.bolt_timer > 0.0 then
        S.bolt_timer = S.bolt_timer - dt
        if S.bolt_timer <= 0.0 then
            eng.scene.set_pos(S.bolt_ent, 0.0, -5.0, 0.0)
            eng.scene.set_scale(S.bolt_ent, 0.12, 0.12, 0.12)
        end
    end

    local steer, thrust = eng.input.axis2d("left", "right", "down", "up")
    S.yaw = S.yaw - steer * 95.0 * dt
    local rad = math.rad(S.yaw)
    local fwd_x, fwd_z = -math.sin(rad), -math.cos(rad)
    local rgt_x, rgt_z = math.cos(rad), -math.sin(rad)

    -- Low-friction inertial hovercraft thrust + lateral drift jets
    S.vx = (S.vx + fwd_x * thrust * 24.0 * dt) * (1.0 - 1.4 * dt)
    S.vz = (S.vz + fwd_z * thrust * 24.0 * dt) * (1.0 - 1.4 * dt)

    if (eng.input.pressed("jump") or eng.input.pressed("interact")) and S.drift_cd <= 0.0 then
        S.drift_cd = 0.45
        local side = (math.abs(steer) > 0.1) and steer or 1.0
        S.vx = S.vx + rgt_x * side * 7.5
        S.vz = S.vz + rgt_z * side * 7.5
        S.drifts_used = S.drifts_used + 1
        eng.audio.play(S.sfx_boost, S.px, S.py, S.pz, 0)
    end

    -- Turbo boost pads
    if S.boost_cd <= 0.0 then
        for i = 1, #BOOST_PADS do
            local bp = BOOST_PADS[i]
            if eng.math.dist3(S.px, 0.0, S.pz, bp.x, 0.0, bp.z) < 2.1 then
                S.boost_cd = 0.6
                S.vx = S.vx + fwd_x * 9.0
                S.vz = S.vz + fwd_z * 9.0
                S.boosts_used = S.boosts_used + 1
                S.score = S.score + 50
                eng.audio.play(S.sfx_boost, bp.x, 0.5, bp.z, 0)
                break
            end
        end
    end

    -- Sloped jump-ramps
    if S.ramp_cd <= 0.0 and S.py <= 1.1 then
        for i = 1, #RAMPS do
            local rp = RAMPS[i]
            if eng.math.dist3(S.px, 0.0, S.pz, rp.x, 0.0, rp.z) < 2.2 then
                S.ramp_cd = 0.8
                S.vy = 6.2
                S.ramps_launched = S.ramps_launched + 1
                eng.audio.play(S.sfx_boost, rp.x, 0.8, rp.z, 0)
                break
            end
        end
    end

    S.vy = S.vy - 14.0 * dt
    S.px = eng.math.clamp(S.px + S.vx * dt, -16.5, 16.5)
    S.pz = eng.math.clamp(S.pz + S.vz * dt, -19.5, 12.5)
    S.py = S.py + S.vy * dt
    if S.py < 0.9 then S.py = 0.9; S.vy = 0.0 end

    eng.scene.set_pos(S.craft, S.px, S.py, S.pz)
    eng.scene.set_rot_deg(S.craft, eng.math.clamp(S.vy * 2.5, -15.0, 20.0), S.yaw, -steer * 18.0)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
        S.fire_cd = 0.14
        fire_twin_plasma()
    end

    -- Step enemy hover-skimmers
    local living = 0
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            living = living + 1
            en.phase = en.phase + 1.8 * dt
            en.x = en.base_x + math.sin(en.phase) * 2.6
            en.y = 1.15 + math.cos(en.phase * 1.5) * 0.25
            eng.scene.set_pos(en.ent, en.x, en.y, en.z)
        end
    end

    if living == 0 then
        if S.wave < 2 then
            eng.save.write("hover_assault", "wave_2")
            spawn_wave(S.wave + 1)
        else
            S.won = true
            S.score = S.score + 400
            eng.save.write("hover_assault", "clear")
        end
    end

    eng.camera.look_at(S.px - fwd_x * 4.5, S.py + 1.8, S.pz - fwd_z * 4.5, S.px + fwd_x * 8.0, S.py + 0.3, S.pz + fwd_z * 8.0, 0)
end

function draw()
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then eng.render.draw_sprite(en.x, en.y + 0.9, en.z, 0.65, 0.65, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 56, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or
        (eng.i18n.t("title") .. " | WAVE " .. S.wave .. "/2 | KILLS " .. S.kills .. "/6 | BOOSTS " .. S.boosts_used)
    eng.ui.label(x, y, msg, 1.0, {0.45, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.kills / 6.0, "ASSAULT ")
end
