-- 035_lunar_lander_3d: 6DoF attitude & thruster fuel management across a cratered procedural moon
local S = game.state

local function moon_h(x, z)
    local n = eng.procgen.noise2d(x * 0.09, z * 0.09, S.seed) * 1.4
    -- Sculpt a central crater rim around (1.5, -6.0)
    local dx, dz = x - 1.5, z + 6.0
    local r = math.sqrt(dx * dx + dz * dz)
    local crater = (r < 5.5) and (-0.9 * (1.0 - r / 5.5)) or ((r < 7.5) and 0.65 or 0.0)
    return n + crater
end

function init()
    eng.xr.set_mode("6dof")
    eng.physics.set_gravity(0, 0.0, -1.62, 0.0)
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.004 })
    eng.render.set_sky(0.01, 0.01, 0.03, 0.04, 0.05, 0.09)
    eng.render.add_light({ type = "dir", dir = {-0.55, -0.85, -0.25}, color = {2.4, 2.35, 2.25}, shadow = true })
    eng.render.add_light({ type = "point", pos = {2.0, 9.0, -6.0}, color = {0.8, 1.6, 2.2}, range = 45.0 })

    S.seed = math.floor(eng.math.range(100, 80000))
    local reg_tex = eng.procgen.texture("stone_brick", S.seed, 64)
    local pad_tex = eng.procgen.texture("sci_fi_panel", S.seed + 11, 64)

    local tile_mesh = eng.asset.box(4.6, 1.5, 4.6)
    local pad_mesh = eng.asset.cylinder(2.2, 2.4, 0.4, 14)
    local hull_mesh = eng.asset.cylinder(0.95, 0.72, 1.3, 10)
    local leg_mesh = eng.asset.box(0.16, 0.9, 0.16)
    local crys_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_thr = eng.audio.synth("noise", 160, 0.08, 95)
    S.sfx_pad = eng.audio.synth("triangle", 480, 0.24, 980)

    for gx = -4, 4 do
        for gz = 1, -4, -1 do
            local wx, wz = gx * 4.4, gz * 4.4
            local wy = moon_h(wx, wz)
            local t = eng.scene.spawn("regolith_" .. tostring(gx) .. "_" .. tostring(gz))
            eng.scene.set_pos(t, wx, wy - 0.75, wz)
            eng.scene.set_mesh(t, tile_mesh, { tex = reg_tex, color = {0.62, 0.63, 0.66, 1.0}, roughness = 0.92 })
        end
    end

    -- 2 Lunar Landing Pads (Alpha Refuel Pad -> Bravo Lunar Base Pad)
    local pad_xy = { {-3.5, -3.0}, {4.5, -8.5} }
    S.pads = {}
    for i = 1, 2 do
        local px, pz = pad_xy[i][1], pad_xy[i][2]
        local py = moon_h(px, pz) + 0.35
        local pe = eng.scene.spawn("lunar_pad_" .. tostring(i))
        eng.scene.set_pos(pe, px, py, pz)
        eng.scene.set_mesh(pe, pad_mesh, { tex = pad_tex, color = (i == 1) and {0.25, 0.95, 0.85, 1.0} or {1.0, 0.82, 0.22, 1.0} })

        local be = eng.scene.spawn("pad_beacon_" .. tostring(i))
        eng.scene.set_pos(be, px + 2.1, py + 0.2, pz)
        eng.scene.set_mesh(be, crys_mesh, { color = {0.3, 1.0, 0.65, 1.0} })
        S.pads[i] = { x = px, y = py + 0.2, z = pz, landed = false }
    end

    -- Spawn 6DoF Lunar Excursion Module + 4 landing struts
    S.lander = eng.scene.spawn("lunar_module")
    eng.scene.set_mesh(S.lander, hull_mesh, { color = {0.92, 0.84, 0.42, 1.0}, metallic = 0.75, roughness = 0.3, cast_shadow = true })
    local loffs = { {-0.85, -0.65, -0.85}, {0.85, -0.65, -0.85}, {-0.85, -0.65, 0.85}, {0.85, -0.65, 0.85} }
    for i = 1, 4 do
        local lg = eng.scene.spawn("strut_" .. tostring(i))
        eng.scene.set_parent(lg, S.lander)
        eng.scene.set_pos(lg, loffs[i][1], loffs[i][2], loffs[i][3])
        eng.scene.set_mesh(lg, leg_mesh, { color = {0.75, 0.76, 0.80, 1.0} })
    end

    S.lx, S.ly, S.lz = -8.0, 6.2, 0.5
    S.vx, S.vy, S.vz = 1.8, -0.5, -1.2
    S.pitch = 0.0
    S.roll = 0.0
    S.yaw = 0.0
    S.fuel = 100.0
    S.hull = 100.0
    S.pads_landed = 0
    S.thrusting = false
    S.sfx_cd = 0.0
    S.score = 0
    S.won = false

    sync_lander_cam()
    eng.mod.emit("post_init")
end

function sync_lander_cam()
    eng.scene.set_pos(S.lander, S.lx, S.ly, S.lz)
    eng.scene.set_rot_deg(S.lander, S.pitch, S.yaw, -S.roll)
    eng.camera.look_at(S.lx - 1.5, S.ly + 4.8, S.lz + 10.5, S.lx + 1.5, S.ly - 0.8, S.lz - 2.0, 0)
end

function update(dt)
    if S.won then return end
    S.sfx_cd = math.max(0.0, S.sfx_cd - dt)

    local tx_in, tz_in = eng.input.axis2d("left", "right", "down", "up")
    if eng.input.down("interact") then
        S.roll = S.roll * math.max(0.0, 1.0 - 12.0 * dt)
        S.pitch = S.pitch * math.max(0.0, 1.0 - 12.0 * dt)
    else
        S.roll = eng.math.clamp(S.roll + tx_in * 115.0 * dt, -32.0, 32.0)
        S.pitch = eng.math.clamp(S.pitch - tz_in * 115.0 * dt, -32.0, 32.0)
        if (math.abs(tx_in) > 0.05 or math.abs(tz_in) > 0.05) and S.fuel > 0.0 then
            S.fuel = math.max(0.0, S.fuel - 1.5 * dt)
            S.vx = S.vx + tx_in * 3.8 * dt
            S.vz = S.vz - tz_in * 3.8 * dt
        end
        if math.abs(tx_in) < 0.05 then S.roll = S.roll * math.max(0.0, 1.0 - 4.5 * dt) end
        if math.abs(tz_in) < 0.05 then S.pitch = S.pitch * math.max(0.0, 1.0 - 4.5 * dt) end
    end

    -- Lunar gravity + 6DoF vectored main descent thruster
    S.vy = S.vy - 3.6 * dt
    S.thrusting = (eng.input.down("jump") or eng.input.down("fire")) and S.fuel > 0.0
    if S.thrusting then
        S.fuel = math.max(0.0, S.fuel - 8.5 * dt)
        local pr, rr = math.rad(S.pitch), math.rad(S.roll)
        local thrust = 9.4
        S.vx = S.vx + math.sin(rr) * thrust * dt
        S.vz = S.vz + math.sin(pr) * thrust * dt
        S.vy = S.vy + math.cos(rr) * math.cos(pr) * thrust * dt
        if S.sfx_cd <= 0.0 then
            S.sfx_cd = 0.14
            eng.audio.play(S.sfx_thr, S.lx, S.ly, S.lz, 0)
        end
    end

    S.lx = eng.math.clamp(S.lx + S.vx * dt, -16.0, 16.0)
    S.ly = math.min(18.0, S.ly + S.vy * dt)
    S.lz = eng.math.clamp(S.lz + S.vz * dt, -17.0, 5.0)

    -- Check lunar pad touchdown first, else regolith floor
    local active_pad = S.pads[math.min(2, S.pads_landed + 1)]
    local pdist = math.sqrt((S.lx - active_pad.x) ^ 2 + (S.lz - active_pad.z) ^ 2)
    local surf_y = (pdist < 2.35) and (active_pad.y + 0.95) or (moon_h(S.lx, S.lz) + 1.05)
    S.alt = S.ly - surf_y

    if S.ly <= surf_y and S.vy <= 0.0 then
        local hspd = math.sqrt(S.vx * S.vx + S.vz * S.vz)
        local tilt = math.max(math.abs(S.roll), math.abs(S.pitch))
        S.ly = surf_y
        if pdist < 2.35 and not active_pad.landed and math.abs(S.vy) < 3.8 and hspd < 3.4 and tilt < 22.0 then
            active_pad.landed = true
            S.pads_landed = S.pads_landed + 1
            S.score = S.score + 500 + math.floor(S.fuel * 3)
            eng.audio.play(S.sfx_pad, S.lx, S.ly, S.lz, 0)
            S.vx, S.vz, S.roll, S.pitch = 0.0, 0.0, 0.0, 0.0
            if S.pads_landed == 1 then
                S.fuel = math.min(100.0, S.fuel + 35.0)
                S.vy = 2.8 -- Ascent hop toward Pad Bravo
            else
                S.vy = 0.0
                S.won = true
                eng.save.write("lunar_lander_clear", tostring(S.score))
            end
        else
            S.hull = math.max(10.0, S.hull - 18.0)
            S.vy = 1.8
            S.vx, S.vz = S.vx * 0.4, S.vz * 0.4
        end
    end

    sync_lander_cam()
end

function draw()
    if S.thrusting then
        eng.render.draw_sprite(S.lx, S.ly - 1.15, S.lz, 0.85, 0.85, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 52, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | PADS %d/2 | VY %.1f | SCORE %d", S.pads_landed, S.vy, S.score), 1.0, {0.75, 0.96, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.fuel / 100.0, "FUEL ")
end
