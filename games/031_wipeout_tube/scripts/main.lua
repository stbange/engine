-- 031_wipeout_tube: High-speed anti-gravity neon track racer with banking, speed pads & shield boost
local S = game.state

local RX, RZ = 22.0, 32.0
local TWO_PI = math.pi * 2.0

local function track_frame(th)
    local cx = math.sin(th) * RX
    local cz = -math.cos(th) * RZ
    local cy = 1.6 + 1.4 * math.sin(th * 2.0)
    local tx = math.cos(th) * RX
    local tz = math.sin(th) * RZ
    local tl = math.sqrt(tx * tx + tz * tz)
    tx, tz = tx / tl, tz / tl
    -- Right vector perpendicular to forward tangent (tx, 0, tz) in XZ plane
    local rx, rz = -tz, tx
    return cx, cy, cz, tx, tz, rx, rz
end

local function track_pos(th, lat, hover)
    local cx, cy, cz, tx, tz, rx, rz = track_frame(th)
    return cx + rx * lat, cy + (hover or 0.0), cz + rz * lat, tx, tz
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.014 })
    eng.render.set_sky(0.03, 0.02, 0.12, 0.14, 0.05, 0.28)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.6, 1.7, 2.2}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 10.0, 0.0}, color = {0.8, 2.2, 2.8}, range = 65.0 })

    local seed = math.floor(eng.math.range(100, 90000))
    local panel_tex = eng.procgen.texture("sci_fi_panel", seed, 64)
    local slab_mesh = eng.asset.box(8.0, 0.4, 7.6)
    local rail_mesh = eng.asset.box(0.35, 0.85, 7.6)
    local pad_mesh = eng.asset.box(1.8, 0.15, 2.4)
    local ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    local arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    local crys_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_pad = eng.audio.synth("saw", 380, 0.14, 960)
    S.sfx_hit = eng.audio.synth("noise", 220, 0.16, 70)
    S.sfx_lap = eng.audio.synth("triangle", 520, 0.24, 1040)

    -- Spawn 28 neon anti-gravity tube segments & rails
    local segs = 28
    for i = 0, segs - 1 do
        local th = (i / segs) * TWO_PI
        local cx, cy, cz, tx, tz, rx, rz = track_frame(th)
        local yaw = math.deg(math.atan2(-tx, -tz))
        local bank = math.sin(th) * 16.0
        local seg = eng.scene.spawn("tube_seg_" .. tostring(i))
        eng.scene.set_pos(seg, cx, cy - 0.25, cz)
        eng.scene.set_rot_deg(seg, 0.0, yaw, bank)
        eng.scene.set_mesh(seg, slab_mesh, { tex = panel_tex, color = {0.22, 0.30, 0.55, 1.0}, metallic = 0.6, roughness = 0.35 })

        for side = -1, 1, 2 do
            local rl = eng.scene.spawn("rail_" .. tostring(i) .. "_" .. tostring(side))
            eng.scene.set_pos(rl, cx + rx * (side * 4.1), cy + 0.25, cz + rz * (side * 4.1))
            eng.scene.set_rot_deg(rl, 0.0, yaw, bank)
            local rc = (side < 0) and {0.15, 0.95, 1.0, 1.0} or {1.0, 0.20, 0.85, 1.0}
            eng.scene.set_mesh(rl, rail_mesh, { color = rc })
        end
    end

    -- Start / Finish neon gate
    local gx, gy, gz, gtx, gtz = track_pos(0.0, 0.0, 0.0)
    local gate = eng.scene.spawn("finish_gate")
    eng.scene.set_pos(gate, gx, gy, gz)
    eng.scene.set_rot_deg(gate, 0.0, math.deg(math.atan2(-gtx, -gtz)), 0.0)
    eng.scene.set_scale(gate, 3.2, 2.2, 1.8)
    eng.scene.set_mesh(gate, arch_mesh, { color = {0.3, 1.0, 0.95, 1.0} })

    -- 6 Speed Pads + 4 Hazard Energy Mines
    S.pads = {}
    for i = 1, 6 do
        local th = (i / 6.0) * TWO_PI - 0.35
        local lat = ((i % 2 == 0) and 1.6 or -1.6)
        local px, py, pz, tx, tz = track_pos(th, lat, 0.08)
        local pe = eng.scene.spawn("speed_pad_" .. tostring(i))
        eng.scene.set_pos(pe, px, py, pz)
        eng.scene.set_rot_deg(pe, 0.0, math.deg(math.atan2(-tx, -tz)), 0.0)
        eng.scene.set_mesh(pe, pad_mesh, { color = {0.1, 1.0, 0.95, 1.0} })
        S.pads[i] = { ent = pe, th = th % TWO_PI, lat = lat, x = px, y = py, z = pz, cd = 0.0 }
    end

    S.mines = {}
    for i = 1, 4 do
        local th = ((i - 0.5) / 4.0) * TWO_PI
        local lat = ((i % 2 == 1) and 1.8 or -1.8)
        local mx, my, mz = track_pos(th, lat, 0.35)
        local me = eng.scene.spawn("mine_" .. tostring(i))
        eng.scene.set_pos(me, mx, my, mz)
        eng.scene.set_mesh(me, crys_mesh, { color = {1.0, 0.22, 0.30, 1.0} })
        S.mines[i] = { ent = me, th = th % TWO_PI, lat = lat, x = mx, y = my, z = mz, active = true }
    end

    S.ship = eng.scene.spawn("ag_craft")
    eng.scene.set_mesh(S.ship, ship_mesh, { color = {0.85, 0.95, 1.0, 1.0}, metallic = 0.8, roughness = 0.25, cast_shadow = true })

    S.theta = 0.05
    S.lat = 0.0
    S.speed = 18.0
    S.bank = 0.0
    S.shield = 100.0
    S.boost_t = 0.0
    S.laps = 0
    S.pads_hit = 0
    S.score = 0
    S.won = false
    S.ticks = 0

    sync_ship_and_cam(0.0)
    eng.mod.emit("post_init")
end

function sync_ship_and_cam(bob)
    local sx, sy, sz, tx, tz = track_pos(S.theta, S.lat, 0.65 + bob)
    S.sx, S.sy, S.sz = sx, sy, sz
    local yaw = math.deg(math.atan2(-tx, -tz))
    local track_bank = math.sin(S.theta) * 16.0
    eng.scene.set_pos(S.ship, sx, sy, sz)
    eng.scene.set_rot_deg(S.ship, 0.0, yaw, track_bank + S.bank)
    eng.camera.look_at(sx - tx * 5.2, sy + 1.9, sz - tz * 5.2, sx + tx * 4.0, sy + 0.3, sz + tz * 4.0, 0)
end

function update(dt)
    S.ticks = S.ticks + 1
    if S.won then return end

    local steer, thr = eng.input.axis2d("left", "right", "down", "up")
    S.boost_t = math.max(0.0, S.boost_t - dt)

    -- Shield hyperboost on jump/fire
    if (eng.input.pressed("fire") or eng.input.pressed("jump")) and S.shield >= 25.0 and S.boost_t <= 0.05 then
        S.shield = S.shield - 15.0
        S.boost_t = 0.85
        S.speed = math.max(S.speed, 54.0)
        eng.audio.play(S.sfx_pad, S.sx, S.sy, S.sz, 0)
    end

    local max_spd = (S.boost_t > 0.0) and 60.0 or 42.0
    if thr > 0.05 then
        S.speed = math.min(max_spd, S.speed + 34.0 * thr * dt)
    elseif thr < -0.05 then
        S.speed = math.max(10.0, S.speed + 28.0 * thr * dt)
    else
        S.speed = math.max(14.0, S.speed - 8.0 * dt)
    end

    S.lat = eng.math.clamp(S.lat + steer * 11.5 * dt, -3.2, 3.2)
    if math.abs(S.lat) >= 3.18 then
        S.shield = math.max(5.0, S.shield - 12.0 * dt)
    end
    local target_bank = -steer * 36.0
    S.bank = S.bank + (target_bank - S.bank) * math.min(1.0, dt * 10.0)

    local prev_th = S.theta
    S.theta = S.theta + (S.speed / 26.5) * dt
    if math.floor(S.theta / TWO_PI) > math.floor(prev_th / TWO_PI) then
        S.laps = S.laps + 1
        S.score = S.score + 400
        eng.audio.play(S.sfx_lap, S.sx, S.sy, S.sz, 0)
        if S.laps >= 2 then
            S.won = true
            eng.save.write("wipeout_best", tostring(S.score))
        end
    end

    sync_ship_and_cam(math.sin(S.ticks * 0.18) * 0.08)

    for i = 1, #S.pads do
        local p = S.pads[i]
        p.cd = math.max(0.0, p.cd - dt)
        if p.cd <= 0.0 and eng.math.dist3(S.sx, S.sy, S.sz, p.x, p.y, p.z) < 2.6 then
            p.cd = 1.0
            S.boost_t = 0.75
            S.speed = math.min(64.0, S.speed + 14.0)
            S.shield = math.min(100.0, S.shield + 16.0)
            S.pads_hit = S.pads_hit + 1
            S.score = S.score + 150
            eng.audio.play(S.sfx_pad, p.x, p.y, p.z, 0)
        end
    end

    for i = 1, #S.mines do
        local m = S.mines[i]
        if m.active and eng.math.dist3(S.sx, S.sy, S.sz, m.x, m.y, m.z) < 1.7 then
            m.active = false
            eng.scene.despawn(m.ent)
            S.shield = math.max(5.0, S.shield - 22.0)
            S.speed = math.max(16.0, S.speed * 0.65)
            eng.audio.play(S.sfx_hit, m.x, m.y, m.z, 0)
        end
    end
end

function draw()
    for i = 1, #S.pads do
        local p = S.pads[i]
        eng.render.draw_sprite(p.x, p.y + 0.6, p.z, 0.8, 0.8, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 56, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | LAP %d/2 | SPD %d | SCORE %d", math.min(2, S.laps + 1), math.floor(S.speed * 12), S.score), 1.0, {0.4, 0.98, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.shield / 100.0, "SHIELD ")
end
