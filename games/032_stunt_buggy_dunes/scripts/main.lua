-- 032_stunt_buggy_dunes: Procedural noise desert dunes stunt park with airtime backflips & sky rings
local S = game.state

local function dune_y(x, z)
    local n1 = eng.procgen.noise2d(x * 0.065, z * 0.065, S.seed)
    local n2 = eng.procgen.noise2d(x * 0.15, z * 0.15, S.seed + 31)
    return n1 * 1.8 + n2 * 0.55
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.012 })
    eng.render.set_sky(0.18, 0.48, 0.88, 0.95, 0.74, 0.45)
    eng.render.add_light({ type = "dir", dir = {-0.4, -1.0, -0.35}, color = {2.3, 2.05, 1.65}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 12.0, -20.0}, color = {1.8, 1.4, 0.9}, range = 55.0 })

    S.seed = math.floor(eng.math.range(100, 50000))
    local sand_tex = eng.procgen.texture("marble", S.seed, 64)
    local wood_tex = eng.procgen.texture("wood_planks", S.seed + 5, 64)
    local tile_mesh = eng.asset.box(6.2, 1.4, 6.2)
    local ramp_mesh = eng.asset.box(3.8, 0.45, 4.4)
    local body_mesh = eng.asset.box(1.5, 0.55, 2.3)
    local wheel_mesh = eng.asset.cylinder(0.36, 0.36, 0.32, 10)
    local arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    local crys_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_jump = eng.audio.synth("saw", 190, 0.16, 520)
    S.sfx_ring = eng.audio.synth("triangle", 640, 0.18, 1180)
    S.sfx_land = eng.audio.synth("square", 260, 0.15, 580)

    -- Build procedural noise desert dune tiles along stunt corridor
    S.dune_samples = 0
    for gx = -3, 3 do
        for gz = 1, -9, -1 do
            local wx, wz = gx * 6.0, gz * 6.0
            local wy = dune_y(wx, wz)
            S.dune_samples = S.dune_samples + 1
            local t = eng.scene.spawn("dune_" .. tostring(S.dune_samples))
            eng.scene.set_pos(t, wx, wy - 0.7, wz)
            eng.scene.set_mesh(t, tile_mesh, { tex = sand_tex, color = {0.92, 0.76, 0.46, 1.0}, roughness = 0.9 })
        end
    end

    -- 3 Stunt Ramps + Elevated Sky Score Rings
    local ramp_coords = { {0.0, -10.0}, {4.5, -25.0}, {-3.5, -40.0} }
    S.ramps = {}
    S.rings = {}
    for i = 1, #ramp_coords do
        local rx, rz = ramp_coords[i][1], ramp_coords[i][2]
        local ry = dune_y(rx, rz)
        local re = eng.scene.spawn("stunt_ramp_" .. tostring(i))
        eng.scene.set_pos(re, rx, ry + 0.55, rz)
        eng.scene.set_rot_deg(re, 26.0, 0.0, 0.0)
        eng.scene.set_mesh(re, ramp_mesh, { tex = wood_tex, color = {0.85, 0.42, 0.18, 1.0}, cast_shadow = true })
        S.ramps[i] = { x = rx, y = ry + 0.55, z = rz }

        local rgx, rgz = rx, rz - 4.8
        local rgy = ry + 4.4
        local ge = eng.scene.spawn("sky_ring_" .. tostring(i))
        eng.scene.set_pos(ge, rgx, rgy - 1.1, rgz)
        eng.scene.set_scale(ge, 1.5, 1.3, 1.2)
        eng.scene.set_mesh(ge, arch_mesh, { color = {1.0, 0.86, 0.18, 1.0} })

        local ce = eng.scene.spawn("ring_gem_" .. tostring(i))
        eng.scene.set_pos(ce, rgx, rgy, rgz)
        eng.scene.set_mesh(ce, crys_mesh, { color = {1.0, 0.95, 0.30, 1.0} })
        S.rings[i] = { x = rgx, y = rgy, z = rgz, gem = ce, hit = false }
    end

    -- Spawn Stunt Buggy + 4 wheels
    S.buggy = eng.scene.spawn("stunt_buggy")
    eng.scene.set_mesh(S.buggy, body_mesh, { color = {0.95, 0.22, 0.16, 1.0}, metallic = 0.4, roughness = 0.4, cast_shadow = true })
    local woffs = { {-0.85, -0.22, -0.8}, {0.85, -0.22, -0.8}, {-0.85, -0.22, 0.8}, {0.85, -0.22, 0.8} }
    for i = 1, 4 do
        local w = eng.scene.spawn("wheel_" .. tostring(i))
        eng.scene.set_parent(w, S.buggy)
        eng.scene.set_pos(w, woffs[i][1], woffs[i][2], woffs[i][3])
        eng.scene.set_rot_deg(w, 0.0, 0.0, 90.0)
        eng.scene.set_mesh(w, wheel_mesh, { color = {0.18, 0.18, 0.20, 1.0} })
    end

    S.bx, S.bz = 0.0, 2.0
    S.by = dune_y(S.bx, S.bz) + 0.6
    S.yaw = 0.0
    S.pitch = 0.0
    S.spd = 0.0
    S.vy = 0.0
    S.grounded = true
    S.ramp_cd = 0.0
    S.flip_deg = 0.0
    S.flips_landed = 0
    S.rings_hit = 0
    S.score = 0
    S.won = false

    sync_buggy_cam()
    eng.mod.emit("post_init")
end

function sync_buggy_cam()
    eng.scene.set_pos(S.buggy, S.bx, S.by, S.bz)
    eng.scene.set_rot_deg(S.buggy, S.pitch, S.yaw, 0.0)
    local rad = math.rad(S.yaw)
    local fx, fz = -math.sin(rad), -math.cos(rad)
    eng.camera.look_at(S.bx - fx * 7.5, S.by + 3.8, S.bz - fz * 7.5, S.bx + fx * 4.0, S.by + 0.8, S.bz + fz * 4.0, 0)
end

function update(dt)
    if S.won then return end
    S.ramp_cd = math.max(0.0, S.ramp_cd - dt)

    local steer, thr = eng.input.axis2d("left", "right", "down", "up")
    if S.grounded then
        S.yaw = S.yaw - steer * 95.0 * dt
        if thr > 0.05 then
            S.spd = math.min(24.0, S.spd + 26.0 * thr * dt)
        elseif thr < -0.05 then
            S.spd = math.max(-6.0, S.spd + 22.0 * thr * dt)
        else
            S.spd = S.spd * math.max(0.0, 1.0 - 2.5 * dt)
        end
    else
        S.yaw = S.yaw - steer * 45.0 * dt
        if eng.input.down("jump") or eng.input.down("fire") then
            local dflip = 430.0 * dt
            S.flip_deg = S.flip_deg + dflip
            S.pitch = S.flip_deg
        end
    end

    local rad = math.rad(S.yaw)
    local fx, fz = -math.sin(rad), -math.cos(rad)
    S.bx = eng.math.clamp(S.bx + fx * S.spd * dt, -18.0, 18.0)
    S.bz = eng.math.clamp(S.bz + fz * S.spd * dt, -52.0, 6.0)

    -- Check ramp launch
    if S.grounded and S.ramp_cd <= 0.0 and S.spd > 9.0 then
        for i = 1, #S.ramps do
            local r = S.ramps[i]
            if math.abs(S.bx - r.x) < 2.2 and math.abs(S.bz - r.z) < 2.3 then
                S.grounded = false
                S.ramp_cd = 0.75
                S.vy = 11.8 + S.spd * 0.14
                S.flip_deg = 0.0
                eng.audio.play(S.sfx_jump, S.bx, S.by, S.bz, 0)
                break
            end
        end
    end

    local ground_h = dune_y(S.bx, S.bz) + 0.6
    if not S.grounded then
        S.vy = S.vy - 18.5 * dt
        S.by = S.by + S.vy * dt
        if S.by <= ground_h and S.vy <= 0.0 then
            S.by = ground_h
            S.vy = 0.0
            S.grounded = true
            if S.flip_deg >= 270.0 then
                local nflips = math.max(1, math.floor((S.flip_deg + 90.0) / 360.0))
                S.flips_landed = S.flips_landed + nflips
                S.score = S.score + nflips * 300
                eng.audio.play(S.sfx_land, S.bx, S.by, S.bz, 0)
            end
            S.flip_deg = 0.0
        end
    else
        S.by = ground_h
        local ahead_h = dune_y(S.bx + fx * 1.2, S.bz + fz * 1.2) + 0.6
        S.pitch = eng.math.clamp(math.deg(math.atan2(ahead_h - ground_h, 1.2)), -25.0, 25.0)
    end

    -- Check elevated stunt score rings
    for i = 1, #S.rings do
        local rg = S.rings[i]
        if not rg.hit and eng.math.dist3(S.bx, S.by, S.bz, rg.x, rg.y, rg.z) < 3.4 then
            rg.hit = true
            eng.scene.despawn(rg.gem)
            S.rings_hit = S.rings_hit + 1
            S.score = S.score + 250
            eng.audio.play(S.sfx_ring, rg.x, rg.y, rg.z, 0)
        end
    end

    if S.grounded and S.rings_hit >= 2 and S.flips_landed >= 2 then
        S.won = true
        eng.save.write("stunt_dunes_score", tostring(S.score))
    end

    sync_buggy_cam()
end

function draw()
    for i = 1, #S.rings do
        local rg = S.rings[i]
        if not rg.hit then eng.render.draw_sprite(rg.x, rg.y + 0.9, rg.z, 0.9, 0.9, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 52, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | RINGS %d/3 | FLIPS %d | SCORE %d", S.rings_hit, S.flips_landed, S.score), 1.0, {1.0, 0.92, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 220, math.min(1.0, S.spd / 24.0), "TURBO ")
end
