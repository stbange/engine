-- 058_medieval_catapult_command: Pike/archer formations & siege trebuchet vs cavalry waves
local S = game.state

local function spawn_cavalry_wave(wave_num)
    S.wave = wave_num
    for i = 1, 3 do
        local rx = (i - 2) * 3.8 + ((wave_num % 2 == 0) and 1.2 or -1.2)
        local rz = -13.5 - (i - 1) * 1.4
        local horse = eng.scene.spawn("cavalry_horse_" .. tostring(wave_num) .. "_" .. tostring(i))
        eng.scene.set_pos(horse, rx, 0.0, rz)
        eng.scene.set_rot_deg(horse, 0.0, 180.0, 0.0)
        eng.procgen.animal(horse, S.seed_base + wave_num * 31 + i, "quadruped")
        eng.scene.set_scale(horse, 1.15, 1.15, 1.25)

        local rider = eng.scene.spawn("cavalry_rider_" .. tostring(wave_num) .. "_" .. tostring(i))
        eng.scene.set_parent(rider, horse)
        eng.scene.set_pos(rider, 0.0, 0.95, 0.0)
        eng.scene.set_scale(rider, 0.48, 0.85, 0.48)
        eng.scene.set_mesh(rider, S.box_mesh, { color = {0.88, 0.18, 0.18, 1.0}, cast_shadow = true })

        S.cavalry[#S.cavalry + 1] = { ent = horse, x = rx, z = rz, hp = 2, alive = true }
    end
end

local function update_formation_positions()
    for i = 1, #S.troops do
        local tr = S.troops[i]
        local ox = (i - 3.5) * 1.55
        local oz = (S.stance == "PIKE") and 4.6 or 5.8
        tr.x = S.form_x + ox
        tr.z = oz
        eng.scene.set_pos(tr.ent, tr.x, 0.0, tr.z)
    end
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.012 })
    eng.render.set_sky(0.18, 0.36, 0.62, 0.62, 0.56, 0.46)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.4}, color = {2.15, 2.05, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, 8.0}, color = {2.0, 1.5, 0.9}, range = 28.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.seed_base = seed_base
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.boulder_mesh = eng.asset.sphere(0.58, 10, 12)
    S.ring_mesh = eng.asset.cylinder(1.8, 1.8, 0.16, 12)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.grass_tex = eng.procgen.texture("grass", seed_base, 64)
    S.stone_tex = eng.procgen.texture("stone_brick", seed_base + 5, 64)
    S.wood_tex = eng.procgen.texture("wood_planks", seed_base + 11, 64)

    S.sfx_launch = eng.audio.synth("saw", 180, 0.16, 90)
    S.sfx_boom = eng.audio.synth("noise", 200, 0.20, 65)
    S.sfx_horn = eng.audio.synth("triangle", 340, 0.16, 520)

    local valley = eng.scene.spawn("siege_valley")
    eng.scene.set_pos(valley, 0.0, -0.25, 0.0)
    eng.scene.set_scale(valley, 34.0, 0.5, 36.0)
    eng.scene.set_mesh(valley, S.box_mesh, { tex = S.grass_tex, color = {0.42, 0.68, 0.34, 1.0} })

    -- Castle Ramparts & Gatehouse at Z = +10.2
    for side = -1, 1, 2 do
        local wall = eng.scene.spawn("castle_wall_" .. tostring(side))
        eng.scene.set_pos(wall, side * 7.5, 1.8, 10.2)
        eng.scene.set_scale(wall, 11.0, 3.6, 1.8)
        eng.scene.set_mesh(wall, S.box_mesh, { tex = S.stone_tex, color = {0.68, 0.66, 0.62, 1.0}, cast_shadow = true })

        local tw = eng.scene.spawn("castle_tower_" .. tostring(side))
        eng.scene.set_pos(tw, side * 2.4, 0.0, 10.0)
        eng.scene.set_scale(tw, 1.3, 1.4, 1.3)
        eng.scene.set_mesh(tw, S.pillar_mesh, { tex = S.stone_tex, color = {0.74, 0.72, 0.68, 1.0}, cast_shadow = true })
    end

    local gate = eng.scene.spawn("castle_gatehouse")
    eng.scene.set_pos(gate, 0.0, 0.0, 10.2)
    eng.scene.set_scale(gate, 1.8, 1.5, 1.6)
    eng.scene.set_mesh(gate, S.arch_mesh, { tex = S.stone_tex, color = {0.75, 0.72, 0.66, 1.0}, cast_shadow = true })

    -- 3D Siege Trebuchet at (0, 0, 8.0) with articulating throwing arm
    local base = eng.scene.spawn("trebuchet_frame")
    eng.scene.set_pos(base, 0.0, 0.65, 8.0)
    eng.scene.set_scale(base, 1.6, 1.3, 2.2)
    eng.scene.set_mesh(base, S.box_mesh, { tex = S.wood_tex, color = {0.65, 0.44, 0.24, 1.0}, cast_shadow = true })

    S.arm_pivot = eng.scene.spawn("trebuchet_pivot")
    eng.scene.set_pos(S.arm_pivot, 0.0, 1.45, 8.0)
    local beam = eng.scene.spawn("trebuchet_beam")
    eng.scene.set_parent(beam, S.arm_pivot)
    eng.scene.set_pos(beam, 0.0, 0.0, -0.8)
    eng.scene.set_scale(beam, 0.26, 0.26, 3.6)
    eng.scene.set_mesh(beam, S.box_mesh, { tex = S.wood_tex, color = {0.78, 0.54, 0.28, 1.0}, cast_shadow = true })

    -- Pike & Archer Shieldwall Squad (6 procedural defenders)
    S.form_x = 0.0
    S.stance = "PIKE"
    S.troops = {}
    for i = 1, 6 do
        local te = eng.scene.spawn("defender_" .. tostring(i))
        eng.procgen.person(te, seed_base + 80 + i)
        local pike = eng.scene.spawn("pike_spear_" .. tostring(i))
        eng.scene.set_parent(pike, te)
        eng.scene.set_pos(pike, 0.25, 0.9, -0.7)
        eng.scene.set_scale(pike, 0.09, 0.09, 1.8)
        eng.scene.set_mesh(pike, S.box_mesh, { color = {0.75, 0.78, 0.85, 1.0} })
        S.troops[i] = { ent = te, x = 0.0, z = 4.6 }
    end
    update_formation_positions()

    -- Trebuchet Aim Reticle
    S.ax, S.az = 0.0, -5.0
    S.reticle_ent = eng.scene.spawn("trebuchet_reticle")
    eng.scene.set_pos(S.reticle_ent, S.ax, 0.12, S.az)
    eng.scene.set_mesh(S.reticle_ent, S.ring_mesh, { color = {1.0, 0.42, 0.16, 1.0} })

    S.cavalry = {}
    S.boulders = {}
    S.gate_hp = 100
    S.kills = 0
    S.orders = 0
    S.shots_fired = 0
    S.windup = 0.0
    S.fire_cd = 0.0
    S.order_cd = 0.0
    S.won = false
    S.lost = false

    spawn_cavalry_wave(1)
    eng.camera.look_at(0.0, 19.5, 20.5, 0.0, 1.0, -1.5, 0)
    eng.mod.emit("post_init")
end

local function count_living_cavalry()
    local n = 0
    for i = 1, #S.cavalry do
        if S.cavalry[i].alive then n = n + 1 end
    end
    return n
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.order_cd = math.max(0.0, S.order_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.ax = eng.math.clamp(S.ax + mx * 14.0 * dt, -11.0, 11.0)
        S.az = eng.math.clamp(S.az - my * 14.0 * dt, -14.0, 3.5)
        eng.scene.set_pos(S.reticle_ent, S.ax, 0.12, S.az)
    end

    -- Interact: Rally Pike/Archer formation & loose arrow volley
    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.order_cd <= 0.0 then
        S.order_cd = 0.35
        S.orders = S.orders + 1
        S.stance = (S.stance == "PIKE") and "ARCHER" or "PIKE"
        S.form_x = eng.math.clamp(S.ax, -6.0, 6.0)
        update_formation_positions()
        eng.audio.play(S.sfx_horn, S.form_x, 1.5, 5.0, 0)

        -- Archer volley strikes nearest rider
        for i = 1, #S.cavalry do
            local c = S.cavalry[i]
            if c.alive and c.z > -12.0 then
                c.hp = c.hp - 1
                if c.hp <= 0 then
                    c.alive = false
                    eng.scene.despawn(c.ent)
                    S.kills = S.kills + 1
                end
                break
            end
        end
    end

    -- Wind up & launch Trebuchet Boulder (fire)
    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
        S.windup = math.min(1.0, S.windup + dt * 6.5)
        eng.scene.set_rot_deg(S.arm_pivot, -38.0 * S.windup, 0.0, 0.0)
        if S.windup >= 0.35 then
            S.fire_cd = 0.26
            S.windup = 0.0
            S.shots_fired = S.shots_fired + 1
            eng.scene.set_rot_deg(S.arm_pivot, 42.0, 0.0, 0.0)

            local be = eng.scene.spawn("siege_boulder")
            eng.scene.set_pos(be, 0.0, 2.8, 7.2)
            eng.scene.set_mesh(be, S.boulder_mesh, { color = {1.0, 0.55, 0.18, 1.0}, cast_shadow = true })
            S.boulders[#S.boulders + 1] = {
                ent = be, sx = 0.0, sz = 7.2, tx = S.ax, tz = S.az, t = 0.0, dur = 0.38
            }
            eng.audio.play(S.sfx_launch, 0.0, 2.5, 8.0, 0)
        end
    else
        S.windup = math.max(0.0, S.windup - dt * 3.0)
        eng.scene.set_rot_deg(S.arm_pivot, -15.0 * S.windup, 0.0, 0.0)
    end

    -- Advance flying trebuchet boulders & AoE impact
    for i = #S.boulders, 1, -1 do
        local b = S.boulders[i]
        b.t = b.t + dt / b.dur
        local u = math.min(1.0, b.t)
        local bx = b.sx + (b.tx - b.sx) * u
        local bz = b.sz + (b.tz - b.sz) * u
        local by = 2.8 * (1.0 - u) + math.sin(u * 3.14159) * 5.2
        eng.scene.set_pos(b.ent, bx, by, bz)

        if b.t >= 1.0 then
            eng.audio.play(S.sfx_boom, b.tx, 0.8, b.tz, 0)
            for j = 1, #S.cavalry do
                local c = S.cavalry[j]
                if c.alive and eng.math.dist3(b.tx, 0, b.tz, c.x, 0, c.z) < 4.8 then
                    c.alive = false
                    eng.scene.despawn(c.ent)
                    S.kills = S.kills + 1
                end
            end
            eng.scene.despawn(b.ent)
            table.remove(S.boulders, i)
        end
    end

    -- Advance charging cavalry riders
    for i = 1, #S.cavalry do
        local c = S.cavalry[i]
        if c.alive then
            c.z = c.z + 6.4 * dt
            eng.scene.set_pos(c.ent, c.x, 0.0, c.z)

            -- Pike shieldwall interception
            if math.abs(c.z - 4.6) < 1.1 and math.abs(c.x - S.form_x) < 4.8 then
                c.alive = false
                eng.scene.despawn(c.ent)
                S.kills = S.kills + 1
            elseif c.z >= 9.6 then
                c.alive = false
                eng.scene.despawn(c.ent)
                S.gate_hp = math.max(0, S.gate_hp - 35)
            end
        end
    end

    if S.gate_hp <= 0 then
        S.lost = true
        eng.save.write("catapult_siege_result", "breached")
    elseif count_living_cavalry() == 0 then
        if S.wave < 3 then
            spawn_cavalry_wave(S.wave + 1)
        else
            S.won = true
            eng.save.write("catapult_siege_result", "repelled")
        end
    end
end

function draw()
    for i = 1, #S.boulders do
        local b = S.boulders[i]
        local u = math.min(1.0, b.t)
        eng.render.draw_sprite(b.sx + (b.tx - b.sx) * u, 3.2, b.sz + (b.tz - b.sz) * u, 1.0, 1.0, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 54, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or (S.lost and (" | " .. eng.i18n.t("defeat")) or "")
    eng.ui.label(x, y, eng.i18n.t("title") .. " | WAVE " .. S.wave .. "/3 | STANCE: " .. S.stance .. " | KILLS: " .. S.kills .. status, 1.0, {1.0, 0.90, 0.50, 1.0})
    eng.ui.bar(x, y + 24, 240, S.gate_hp / 100.0, "GATE HP ")
end
