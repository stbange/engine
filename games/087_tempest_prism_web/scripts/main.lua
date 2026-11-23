-- 087_tempest_prism_web: Claw Blaster on a 12-Lane 3D Geometric Prism Tube
local S = game.state

local NUM_LANES = 12
local TWO_PI = math.pi * 2.0
local R_TUBE = 4.2
local R_MID = R_TUBE * math.cos(math.pi / NUM_LANES)
local CHORD_W = 2.0 * R_TUBE * math.sin(math.pi / NUM_LANES)
local WELL_DEPTH = 20.0

local function lane_angle(lane_idx)
    return lane_idx * (TWO_PI / NUM_LANES) - math.pi * 0.5
end

local function lane_pose(lane_idx, z)
    local a = lane_angle(lane_idx)
    return R_MID * math.cos(a), R_MID * math.sin(a), z, math.deg(a) + 90.0
end

local function recolor_web()
    local base_col = (S.wave == 1) and {0.16, 0.52, 1.0, 1.0} or {0.86, 0.22, 0.98, 1.0}
    local hi_col = {1.0, 0.92, 0.22, 1.0}
    for k = 0, NUM_LANES - 1 do
        local is_active = (k == S.lane)
        eng.scene.set_mesh(S.rim_segs[k + 1], S.box_mesh, { tex = S.prism_tex, color = is_active and hi_col or base_col })
        local strut_hi = (k == S.lane) or (((k - 1) % NUM_LANES) == S.lane)
        eng.scene.set_mesh(S.struts[k + 1], S.box_mesh, { tex = S.prism_tex, color = strut_hi and hi_col or base_col })
    end
end

local function spawn_flipper(lane, z, vz, flip_dir)
    local root = eng.scene.spawn("flipper_bowtie")
    local wing_a = eng.scene.spawn("flipper_wing_a")
    local wing_b = eng.scene.spawn("flipper_wing_b")
    eng.scene.set_parent(wing_a, root)
    eng.scene.set_parent(wing_b, root)
    eng.scene.set_pos(wing_a, 0.0, 0.16, 0.0)
    eng.scene.set_pos(wing_b, 0.0, 0.16, 0.0)
    eng.scene.set_rot_deg(wing_a, 0.0, 0.0, 26.0)
    eng.scene.set_rot_deg(wing_b, 0.0, 0.0, -26.0)
    eng.scene.set_scale(wing_a, 1.45, 0.14, 0.36)
    eng.scene.set_scale(wing_b, 1.45, 0.14, 0.36)
    eng.scene.set_mesh(wing_a, S.box_mesh, { color = {1.0, 0.20, 0.28, 1.0} })
    eng.scene.set_mesh(wing_b, S.box_mesh, { color = {1.0, 0.42, 0.18, 1.0} })

    local x, y, pz, roll = lane_pose(lane, z)
    eng.scene.set_pos(root, x, y, pz)
    eng.scene.set_rot_deg(root, 0.0, 0.0, roll)

    S.flippers[#S.flippers + 1] = {
        ent = root, w1 = wing_a, w2 = wing_b,
        lane = lane, prev_lane = lane, flip_anim = 0.0,
        z = z, vz = vz,
        flip_cd = 0.55 + (lane % 3) * 0.22,
        dir = flip_dir,
        alive = true
    }
end

local function despawn_flipper(fl)
    if not fl.alive then return end
    fl.alive = false
    eng.scene.despawn(fl.w1)
    eng.scene.despawn(fl.w2)
    eng.scene.despawn(fl.ent)
end

local function start_wave(w)
    S.wave = w
    S.zapper = 1
    S.flippers = {}
    local count = (w == 1) and 6 or 8
    for i = 1, count do
        local ln = ((i - 1) * 2 + math.floor(eng.math.range(0, 2))) % NUM_LANES
        local z0 = -WELL_DEPTH + 0.6 + (i - 1) * 1.15
        local vz = (w == 1 and 4.4 or 5.3) + (i % 3) * 0.35
        local fdir = ((i % 2) == 0) and 1 or -1
        spawn_flipper(ln, z0, vz, fdir)
    end
    recolor_web()
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, crt = 0.16, fog_density = 0.014 })
    eng.render.set_sky(0.01, 0.01, 0.05, 0.05, 0.02, 0.14)
    eng.render.add_light({ type = "dir", dir = {-0.25, -0.55, -0.80}, color = {1.9, 1.95, 2.2}, shadow = false })
    eng.render.add_light({ type = "point", pos = {0.0, 0.0, -7.0}, color = {1.4, 2.0, 3.2}, range = 32.0 })

    local seed_base = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.bolt_mesh = eng.asset.box(0.20, 0.20, 0.95)
    S.prism_tex = eng.procgen.texture("sci_fi_panel", seed_base, 64)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_shot = eng.audio.synth("saw", 820, 0.07, 280)
    S.sfx_hit = eng.audio.synth("noise", 300, 0.12, 85)
    S.sfx_zap = eng.audio.synth("square", 320, 0.20, 1080)

    -- 12 longitudinal prism struts + 4 polygonal depth rings
    S.struts = {}
    S.rim_segs = {}
    for k = 0, NUM_LANES - 1 do
        local ba = (k - 0.5) * (TWO_PI / NUM_LANES) - math.pi * 0.5
        local se = eng.scene.spawn("prism_strut_" .. tostring(k))
        eng.scene.set_pos(se, R_TUBE * math.cos(ba), R_TUBE * math.sin(ba), -WELL_DEPTH * 0.5)
        eng.scene.set_scale(se, 0.11, 0.11, WELL_DEPTH)
        eng.scene.set_mesh(se, S.box_mesh, { tex = S.prism_tex, color = {0.16, 0.52, 1.0, 1.0} })
        S.struts[k + 1] = se
    end

    local ring_zs = { 0.0, -6.5, -13.0, -WELL_DEPTH }
    for ri = 1, #ring_zs do
        local rz = ring_zs[ri]
        for k = 0, NUM_LANES - 1 do
            local cx, cy, cz, roll = lane_pose(k, rz)
            local ce = eng.scene.spawn("prism_ring_" .. tostring(ri) .. "_" .. tostring(k))
            eng.scene.set_pos(ce, cx, cy, cz)
            eng.scene.set_rot_deg(ce, 0.0, 0.0, roll)
            eng.scene.set_scale(ce, CHORD_W + 0.06, (ri == 1) and 0.14 or 0.09, (ri == 1) and 0.16 or 0.09)
            eng.scene.set_mesh(ce, S.box_mesh, { tex = S.prism_tex, color = {0.14, 0.38, 0.86, 1.0} })
            if ri == 1 then S.rim_segs[k + 1] = ce end
        end
    end

    -- Yellow 3D Claw Blaster on the 12-lane rim
    S.claw_root = eng.scene.spawn("claw_blaster")
    local claw_parts = {
        { 0.0,   0.08,  0.10, 0.0,   1.30, 0.18, 0.42 },
        { -0.52, 0.36, -0.14, -28.0, 0.18, 0.62, 0.38 },
        {  0.52, 0.36, -0.14,  28.0, 0.18, 0.62, 0.38 }
    }
    for i = 1, #claw_parts do
        local p = claw_parts[i]
        local pe = eng.scene.spawn("claw_prong_" .. tostring(i))
        eng.scene.set_parent(pe, S.claw_root)
        eng.scene.set_pos(pe, p[1], p[2], p[3])
        eng.scene.set_rot_deg(pe, 0.0, 0.0, p[4])
        eng.scene.set_scale(pe, p[5], p[6], p[7])
        eng.scene.set_mesh(pe, S.box_mesh, { color = {1.0, 0.90, 0.16, 1.0} })
    end

    S.lane_f = 0.0
    S.lane = 0
    S.bolts = {}
    S.lives = 3
    S.invuln = 0.0
    S.cooldown = 0.0
    S.score = 0
    S.flippers_destroyed = 0
    S.lanes_visited = { [0] = true }
    S.unique_lanes = 1
    S.won = false

    local px, py, pz, proll = lane_pose(0, 0.0)
    eng.scene.set_pos(S.claw_root, px, py, pz)
    eng.scene.set_rot_deg(S.claw_root, 0.0, 0.0, proll)

    start_wave(1)
    eng.camera.look_at(px * 0.25, py * 0.25, 8.8, 0.0, 0.0, -10.0, 0)
    eng.mod.emit("post_init")
end

local function fire_bolt()
    local bx, by, bz, broll = lane_pose(S.lane, -0.45)
    local be = eng.scene.spawn("claw_bolt")
    eng.scene.set_pos(be, bx, by + 0.18 * math.sin(lane_angle(S.lane) + math.pi), bz)
    eng.scene.set_rot_deg(be, 0.0, 0.0, broll)
    eng.scene.set_mesh(be, S.bolt_mesh, { color = {0.55, 1.0, 0.92, 1.0} })
    S.bolts[#S.bolts + 1] = { ent = be, lane = S.lane, z = bz, prev_z = 0.0, vz = -38.0 }
    eng.audio.play(S.sfx_shot, bx, by, bz, 0)
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)
    S.invuln = math.max(0.0, S.invuln - dt)

    local mx, _ = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 then
        S.lane_f = (S.lane_f + mx * 16.0 * dt) % NUM_LANES
        local nl = math.floor(S.lane_f + 0.5) % NUM_LANES
        if nl ~= S.lane then
            S.lane = nl
            if not S.lanes_visited[nl] then
                S.lanes_visited[nl] = true
                S.unique_lanes = S.unique_lanes + 1
            end
            recolor_web()
        end
    end

    local px, py, pz, proll = lane_pose(S.lane_f, 0.0)
    eng.scene.set_pos(S.claw_root, px, py, pz)
    eng.scene.set_rot_deg(S.claw_root, 0.0, 0.0, proll)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        S.cooldown = 0.085
        fire_bolt()
    end

    -- Superzapper clears up to 2 flippers once per wave
    if eng.input.pressed("jump") and S.zapper > 0 then
        S.zapper = S.zapper - 1
        eng.audio.play(S.sfx_zap, 0.0, 0.0, -4.0, 0)
        local zapped = 0
        for i = 1, #S.flippers do
            local fl = S.flippers[i]
            if fl.alive and zapped < 2 then
                despawn_flipper(fl)
                S.flippers_destroyed = S.flippers_destroyed + 1
                S.score = S.score + 150
                zapped = zapped + 1
            end
        end
    end

    -- Step bolts down-well
    for bi = #S.bolts, 1, -1 do
        local b = S.bolts[bi]
        b.prev_z = b.z
        b.z = b.z + b.vz * dt
        local bx, by, bz, broll = lane_pose(b.lane, b.z)
        eng.scene.set_pos(b.ent, bx, by, bz)
        eng.scene.set_rot_deg(b.ent, 0.0, 0.0, broll)
        if b.z < -WELL_DEPTH - 0.5 then
            eng.scene.despawn(b.ent)
            table.remove(S.bolts, bi)
        end
    end

    -- Step climbing flippers & swept bolt collisions
    local living = 0
    for i = 1, #S.flippers do
        local fl = S.flippers[i]
        if fl.alive then
            fl.z = math.min(0.0, fl.z + fl.vz * dt)
            fl.flip_anim = math.max(0.0, fl.flip_anim - dt * 5.0)
            fl.flip_cd = fl.flip_cd - dt

            if fl.flip_cd <= 0.0 then
                fl.prev_lane = fl.lane
                if fl.z >= -0.05 then
                    local diff = (S.lane - fl.lane) % NUM_LANES
                    if diff ~= 0 then
                        local step = (diff <= 6) and 1 or -1
                        fl.lane = (fl.lane + step) % NUM_LANES
                    end
                    fl.flip_cd = 0.38
                else
                    fl.lane = (fl.lane + fl.dir) % NUM_LANES
                    fl.flip_cd = 0.72
                end
                fl.flip_anim = 1.0
            end

            -- Swept bolt check on current lane
            local hit_bi = 0
            for bi = #S.bolts, 1, -1 do
                local b = S.bolts[bi]
                if b.lane == fl.lane and b.z <= (fl.z + 0.75) and b.prev_z >= (fl.z - 0.95) then
                    hit_bi = bi
                    break
                end
            end

            if hit_bi > 0 then
                local b = S.bolts[hit_bi]
                eng.scene.despawn(b.ent)
                table.remove(S.bolts, hit_bi)
                local fx, fy, fz = lane_pose(fl.lane, fl.z)
                eng.audio.play(S.sfx_hit, fx, fy, fz, 0)
                despawn_flipper(fl)
                S.flippers_destroyed = S.flippers_destroyed + 1
                S.score = S.score + 150
            elseif fl.z >= -0.05 and fl.lane == S.lane then
                if S.invuln <= 0.0 then
                    S.lives = math.max(1, S.lives - 1)
                    S.invuln = 1.0
                end
                despawn_flipper(fl)
                S.flippers_destroyed = S.flippers_destroyed + 1
                eng.audio.play(S.sfx_hit, px, py, 0.0, 0)
            else
                living = living + 1
                local interp_lane = fl.lane
                if fl.flip_anim > 0.0 then
                    local d = ((fl.prev_lane - fl.lane + 6) % NUM_LANES) - 6
                    interp_lane = (fl.lane + d * fl.flip_anim) % NUM_LANES
                end
                local fx, fy, fz, froll = lane_pose(interp_lane, fl.z)
                eng.scene.set_pos(fl.ent, fx, fy, fz)
                eng.scene.set_rot_deg(fl.ent, 0.0, 0.0, froll + fl.flip_anim * 180.0)
            end
        end
    end

    if living == 0 then
        for bi = #S.bolts, 1, -1 do
            eng.scene.despawn(S.bolts[bi].ent)
            table.remove(S.bolts, bi)
        end
        if S.wave < 2 then
            S.score = S.score + 300
            start_wave(S.wave + 1)
        else
            S.won = true
            S.score = S.score + 500
        end
    end

    eng.camera.look_at(px * 0.25, py * 0.25, 8.8, 0.0, 0.0, -10.0, 0)
end

function draw()
    for i = 1, #S.bolts do
        local b = S.bolts[i]
        local bx, by, bz = lane_pose(b.lane, b.z)
        eng.render.draw_sprite(bx, by, bz, 0.55, 0.55, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | WAVE " .. S.wave .. "/2 | SCORE " .. S.score, 1.0, {1.0, 0.92, 0.35, 1.0})
    eng.ui.bar(x, y + 26, 180, S.lives / 3.0, "CLAW ")
end
