-- 013_mech_siege: Biped walker defense (eng.procgen.animal "biped") protecting a Reactor Core from flanking sappers
local S = game.state

local LANES = { {-17.0, -4.0}, {17.0, 4.0}, {-4.0, -17.0}, {4.0, 17.0} }

local function spawn_sapper_wave(wave_num)
    S.wave = wave_num
    for i = 1, 3 do
        local ln = LANES[((wave_num * 3 + i - 1) % #LANES) + 1]
        local sx = ln[1] + eng.math.range(-2.0, 2.0)
        local sz = ln[2] + eng.math.range(-2.0, 2.0)
        local se = eng.scene.spawn("sapper_" .. tostring(wave_num) .. "_" .. tostring(i))
        eng.scene.set_pos(se, sx, 0.0, sz)
        eng.procgen.animal(se, S.seed + wave_num * 37 + i * 13, "insectoid")
        eng.scene.set_scale(se, 1.15, 1.15, 1.15)
        S.sappers[#S.sappers + 1] = {
            ent = se, x = sx, z = sz, hp = 2, alive = true,
            flank_sign = (i % 2 == 0) and 1.0 or -1.0
        }
    end
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.015 })
    eng.render.set_sky(0.08, 0.09, 0.14, 0.32, 0.20, 0.15)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.35}, color = {2.0, 1.85, 1.65}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.5, 0.0}, color = {0.5, 2.2, 2.8}, range = 36.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(1.5, 1.3, 2.6, 12)
    S.tracer_mesh = eng.asset.sphere(0.22, 6, 8)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    local metal_tex = eng.procgen.texture("rust_metal", S.seed, 64)

    S.sfx_auto = eng.audio.synth("square", 260, 0.08, 120)
    S.sfx_slam = eng.audio.synth("noise", 160, 0.22, 42)
    S.sfx_vent = eng.audio.synth("triangle", 580, 0.15, 290)

    local floor_e = eng.scene.spawn("siege_courtyard")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 50.0, 0.5, 50.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = metal_tex, roughness = 0.75 })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {25.0, 0.25, 25.0} })

    -- Central Reactor Core pedestal + glowing crystal spire
    S.core_base = eng.scene.spawn("reactor_pedestal")
    eng.scene.set_pos(S.core_base, 0.0, 1.3, 0.0)
    eng.scene.set_mesh(S.core_base, S.cyl_mesh, { color = {0.32, 0.38, 0.46, 1.0}, metallic = 0.7, roughness = 0.3, cast_shadow = true })

    S.core_spire = eng.scene.spawn("reactor_crystal")
    eng.scene.set_pos(S.core_spire, 0.0, 2.5, 0.0)
    eng.scene.set_scale(S.core_spire, 1.6, 1.8, 1.6)
    eng.scene.set_mesh(S.core_spire, S.crystal_mesh, { color = {0.25, 0.92, 1.0, 1.0} })

    -- 4 perimeter steel pylons
    local pylons = { {-9.0, -9.0}, {9.0, -9.0}, {-9.0, 9.0}, {9.0, 9.0} }
    for i = 1, 4 do
        local pe = eng.scene.spawn("pylon_" .. tostring(i))
        eng.scene.set_pos(pe, pylons[i][1], 1.5, pylons[i][2])
        eng.scene.set_scale(pe, 1.4, 3.0, 1.4)
        eng.scene.set_mesh(pe, S.box_mesh, { tex = metal_tex, cast_shadow = true })
    end

    -- Biped Walker Mech rigged with procedural IK gait!
    S.px, S.py, S.pz = 0.0, 0.0, 5.5
    S.vy = 0.0
    S.yaw = 0.0
    S.mech_ent = eng.scene.spawn("biped_siege_mech")
    eng.scene.set_pos(S.mech_ent, S.px, S.py, S.pz)
    eng.procgen.animal(S.mech_ent, S.seed + 7, "biped")
    eng.scene.set_scale(S.mech_ent, 1.75, 1.75, 1.75)

    S.pod_l = eng.scene.spawn("mech_pod_l")
    eng.scene.set_parent(S.pod_l, S.mech_ent)
    eng.scene.set_pos(S.pod_l, -0.55, 1.15, -0.15)
    eng.scene.set_scale(S.pod_l, 0.28, 0.28, 0.75)
    eng.scene.set_mesh(S.pod_l, S.box_mesh, { color = {0.85, 0.65, 0.2, 1.0}, metallic = 0.8 })

    S.pod_r = eng.scene.spawn("mech_pod_r")
    eng.scene.set_parent(S.pod_r, S.mech_ent)
    eng.scene.set_pos(S.pod_r, 0.55, 1.15, -0.15)
    eng.scene.set_scale(S.pod_r, 0.28, 0.28, 0.75)
    eng.scene.set_mesh(S.pod_r, S.box_mesh, { color = {0.85, 0.65, 0.2, 1.0}, metallic = 0.8 })

    S.core_hp = 100
    S.mech_hp = 100
    S.heat = 0.0
    S.overheated = false
    S.fire_cd = 0.0
    S.vent_cd = 0.0
    S.score = 0
    S.kills = 0
    S.stomp_slams = 0
    S.vents_used = 0
    S.won = false
    S.lost = false
    S.tracers = {}
    S.sappers = {}

    spawn_sapper_wave(1)
    eng.camera.look_at(0.0, 14.5, 17.5, 0.0, 1.2, 0.0, 0)
    eng.mod.emit("post_init")
end

local function fire_autocannon()
    local dx, dz = -math.sin(math.rad(S.yaw)), -math.cos(math.rad(S.yaw))
    local best_d = 28.0
    for i = 1, #S.sappers do
        local sp = S.sappers[i]
        if sp.alive then
            local d = eng.math.dist3(S.px, 0, S.pz, sp.x, 0, sp.z)
            if d < best_d then
                best_d = d
                dx, dz = sp.x - S.px, sp.z - S.pz
            end
        end
    end
    local len = math.max(0.001, math.sqrt(dx * dx + dz * dz))
    dx, dz = dx / len, dz / len
    S.yaw = math.deg(math.atan2(-dx, -dz))

    S.heat = math.min(100.0, S.heat + 13.0)
    if S.heat >= 100.0 then S.overheated = true end
    eng.audio.play(S.sfx_auto, S.px, 1.6, S.pz, 0)

    local te = eng.scene.spawn("autocannon_tracer")
    eng.scene.set_pos(te, S.px + dx * 1.1, S.py + 1.5, S.pz + dz * 1.1)
    eng.scene.set_mesh(te, S.tracer_mesh, { color = {1.0, 0.85, 0.25, 1.0} })
    S.tracers[#S.tracers + 1] = {
        ent = te, x = S.px + dx * 1.1, y = S.py + 1.5, z = S.pz + dz * 1.1,
        vx = dx * 44.0, vz = dz * 44.0, life = 0.75
    }
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.vent_cd = math.max(0.0, S.vent_cd - dt)
    S.heat = math.max(0.0, S.heat - 24.0 * dt)
    if S.overheated and S.heat < 45.0 then S.overheated = false end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        local nx = eng.math.clamp(S.px + mx * 9.2 * dt, -20.0, 20.0)
        local nz = eng.math.clamp(S.pz - my * 9.2 * dt, -20.0, 20.0)
        -- Keep outside central reactor pedestal radius
        local r = math.sqrt(nx * nx + nz * nz)
        if r < 2.5 and r > 0.001 then
            nx, nz = (nx / r) * 2.5, (nz / r) * 2.5
        end
        S.px, S.pz = nx, nz
        S.yaw = math.deg(math.atan2(-mx, my))
    end

    -- Jump-Jet leap & seismic landing shockwave
    if eng.input.pressed("jump") and S.py <= 0.02 then
        S.vy = 8.8
    end
    if S.py > 0.0 or S.vy ~= 0.0 then
        local was_air = S.py > 0.05
        S.vy = S.vy - 22.0 * dt
        S.py = S.py + S.vy * dt
        if S.py <= 0.0 then
            S.py = 0.0
            S.vy = 0.0
            if was_air then
                S.stomp_slams = S.stomp_slams + 1
                eng.audio.play(S.sfx_slam, S.px, 0.2, S.pz, 0)
                for i = 1, #S.sappers do
                    local sp = S.sappers[i]
                    if sp.alive and eng.math.dist3(S.px, 0, S.pz, sp.x, 0, sp.z) < 6.5 then
                        sp.hp = sp.hp - 2
                        if sp.hp <= 0 then
                            sp.alive = false
                            eng.scene.despawn(sp.ent)
                            S.kills = S.kills + 1
                            S.score = S.score + 180
                        end
                    end
                end
            end
        end
    end

    eng.scene.set_pos(S.mech_ent, S.px, S.py, S.pz)
    eng.scene.set_rot_deg(S.mech_ent, 0.0, S.yaw, 0.0)
    eng.scene.set_rot_deg(S.core_spire, 0.0, S.yaw * 0.5 + S.kills * 25.0, 0.0)

    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.vent_cd <= 0.0 then
        S.vent_cd = 1.6
        S.vents_used = S.vents_used + 1
        S.heat = math.max(0.0, S.heat - 60.0)
        S.overheated = false
        S.core_hp = math.min(100, S.core_hp + 8)
        eng.audio.play(S.sfx_vent, S.px, 1.5, S.pz, 0)
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 and not S.overheated then
        S.fire_cd = 0.15
        fire_autocannon()
    end

    -- Step autocannon tracers
    for i = #S.tracers, 1, -1 do
        local tr = S.tracers[i]
        tr.life = tr.life - dt
        tr.x = tr.x + tr.vx * dt
        tr.z = tr.z + tr.vz * dt
        eng.scene.set_pos(tr.ent, tr.x, tr.y, tr.z)
        local dead = (tr.life <= 0.0)
        if not dead then
            for j = 1, #S.sappers do
                local sp = S.sappers[j]
                if sp.alive and eng.math.dist3(tr.x, 0, tr.z, sp.x, 0, sp.z) < 1.75 then
                    dead = true
                    sp.hp = sp.hp - 1
                    if sp.hp <= 0 then
                        sp.alive = false
                        eng.scene.despawn(sp.ent)
                        S.kills = S.kills + 1
                        S.score = S.score + 150
                    end
                    break
                end
            end
        end
        if dead then
            eng.scene.despawn(tr.ent)
            table.remove(S.tracers, i)
        end
    end

    -- Step flanking sappers spiraling toward Reactor Core (0, 0, 0)
    local living = 0
    for i = 1, #S.sappers do
        local sp = S.sappers[i]
        if sp.alive then
            living = living + 1
            local rx, rz = -sp.x, -sp.z
            local dist = math.max(0.01, math.sqrt(rx * rx + rz * rz))
            rx, rz = rx / dist, rz / dist
            local tx, tz = -rz * sp.flank_sign, rx * sp.flank_sign
            local flank_w = (dist > 6.5) and 0.65 or 0.15
            local vx = (rx + tx * flank_w) * 3.8
            local vz = (rz + tz * flank_w) * 3.8
            sp.x = sp.x + vx * dt
            sp.z = sp.z + vz * dt
            eng.scene.set_pos(sp.ent, sp.x, 0.0, sp.z)
            eng.scene.set_rot_deg(sp.ent, 0.0, math.deg(math.atan2(-vx, -vz)), 0.0)

            if dist < 2.05 then
                sp.alive = false
                eng.scene.despawn(sp.ent)
                living = living - 1
                S.core_hp = math.max(0, S.core_hp - 30)
                eng.audio.play(S.sfx_slam, 0.0, 1.5, 0.0, 0)
                if S.core_hp <= 0 then S.lost = true end
            end
        end
    end

    if living == 0 and not S.lost then
        if S.wave < 3 then
            spawn_sapper_wave(S.wave + 1)
        else
            S.won = true
            S.score = S.score + S.core_hp * 5
            eng.save.write("mech_siege_clear", tostring(S.score))
        end
    end

    eng.camera.look_at(S.px * 0.4, 14.5, S.pz * 0.4 + 16.0, 0.0, 1.2, 0.0, 0)
end

function draw()
    for i = 1, #S.sappers do
        local sp = S.sappers[i]
        if sp.alive then eng.render.draw_sprite(sp.x, 1.5, sp.z, 0.65, 0.65, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 80, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | WAVE " .. S.wave .. "/3 | KILLS " .. S.kills .. " | SCORE " .. S.score))
    eng.ui.label(x, y, msg, 1.0, {1.0, 0.88, 0.42, 1.0})
    eng.ui.bar(x, y + 24, 220, S.core_hp / 100.0, "CORE ")
    eng.ui.bar(x, y + 48, 220, (100.0 - S.heat) / 100.0, "COOL ")
end
