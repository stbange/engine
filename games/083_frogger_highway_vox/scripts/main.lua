-- 083_frogger_highway_vox: Voxel Hopper across 3D Trucks & Floating River Logs
local S = game.state

local WRAP_X = 16.0
local STEP_Z = 2.0
local ALCOVE_X = { -4.5, 0.0, 4.5 }

local function wrap_x(x)
    if x > WRAP_X then return x - WRAP_X * 2.0 end
    if x < -WRAP_X then return x + WRAP_X * 2.0 end
    return x
end

local function reset_frog()
    S.fx = 0.0
    S.fz = 0.0
    S.lane = 0
    S.hop_t = 0.0
    eng.scene.set_pos(S.frog, S.fx - 0.5, 0.35, S.fz - 0.5)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.012 })
    eng.render.set_sky(0.18, 0.42, 0.78, 0.55, 0.78, 0.95)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.2, 2.1, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 9.0, -8.0}, color = {1.3, 1.5, 1.8}, range = 36.0 })

    local seed_base = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.grass_tex = eng.procgen.texture("grass", seed_base, 64)
    S.road_tex = eng.procgen.texture("cobble", seed_base + 5, 64)
    S.water_tex = eng.procgen.texture("water_caustics", seed_base + 11, 64)
    S.wood_tex = eng.procgen.texture("wood_planks", seed_base + 17, 64)
    S.sfx_hop = eng.audio.synth("triangle", 340, 0.08, 580)
    S.sfx_goal = eng.audio.synth("square", 520, 0.16, 880)
    S.sfx_splash = eng.audio.synth("noise", 220, 0.14, 70)

    -- Build ASCII Voxel Meshes for Frog, 3D Trucks, Floating Logs, and Lily Pads
    S.vox_frog = eng.asset.voxel_ascii({
        "1..1\n1111\n1111\n1..1",
        ".11.\n1111\n1111\n....",
        "....\n2..2\n....\n...."
    }, 4, 3, 4, 0.26)

    S.vox_truck = eng.asset.voxel_ascii({
        "11111111\n11111111\n11111111",
        "22.33333\n22.33333\n22.33333",
        "22.33333\n22.33333\n22.33333"
    }, 8, 3, 3, 0.36)

    S.vox_log = eng.asset.voxel_ascii({
        ".1111111111.\n111111111111\n.1111111111.",
        "111111111111\n122222222221\n111111111111"
    }, 12, 2, 3, 0.38)

    S.vox_lily = eng.asset.voxel_ascii({
        ".1111.\n111111\n1111.1\n111111\n.1111."
    }, 6, 1, 5, 0.36)

    -- Terrain strips: Start Bank (Z=0), Highway (Z=-2..-6), Median (Z=-8), River (Z=-10..-14), Goal Bank (Z=-16)
    local strips = {
        { 0.0, 0.0,  0.0, 28.0, 0.6, 2.2, S.grass_tex, {0.42, 0.85, 0.38, 1.0} },
        { 0.0, -0.05, -4.0, 28.0, 0.5, 6.0, S.road_tex, {0.32, 0.33, 0.36, 1.0} },
        { 0.0, 0.0, -8.0, 28.0, 0.6, 2.2, S.grass_tex, {0.55, 0.78, 0.42, 1.0} },
        { 0.0, -0.25, -12.0, 28.0, 0.4, 6.0, S.water_tex, {0.22, 0.65, 0.98, 1.0} },
        { 0.0, 0.0, -16.2, 28.0, 0.6, 2.4, S.grass_tex, {0.30, 0.72, 0.35, 1.0} }
    }
    for i = 1, #strips do
        local st = strips[i]
        local se = eng.scene.spawn("terrain_strip_" .. tostring(i))
        eng.scene.set_pos(se, st[1], st[2], st[3])
        eng.scene.set_scale(se, st[4], st[5], st[6])
        eng.scene.set_mesh(se, S.box_mesh, { tex = st[7], color = st[8] })
    end

    -- Spawn 3 Highway Lanes of 3D Voxel Trucks (lanes 1, 2, 3 -> Z = -2, -4, -6)
    S.trucks = {}
    local t_cfg = {
        { lane = 1, z = -2.0, vx =  3.8, color = {0.95, 0.32, 0.28, 1.0} },
        { lane = 2, z = -4.0, vx = -3.2, color = {0.95, 0.78, 0.22, 1.0} },
        { lane = 3, z = -6.0, vx =  4.4, color = {0.32, 0.75, 0.98, 1.0} }
    }
    for li = 1, #t_cfg do
        local c = t_cfg[li]
        for k = 1, 2 do
            local tx = (k - 1.5) * 13.5 + li * 1.7
            local te = eng.scene.spawn("vox_truck")
            eng.scene.set_pos(te, tx - 1.4, 0.28, c.z - 0.54)
            eng.scene.set_mesh(te, S.vox_truck, { color = c.color, cast_shadow = true })
            S.trucks[#S.trucks + 1] = { ent = te, lane = c.lane, x = tx, z = c.z, vx = c.vx, hw = 1.45 }
        end
    end

    -- Spawn 3 River Lanes of Floating Voxel Logs (lanes 5, 6, 7 -> Z = -10, -12, -14)
    S.logs = {}
    local l_cfg = {
        { lane = 5, z = -10.0, vx =  3.4 },
        { lane = 6, z = -12.0, vx = -3.0 },
        { lane = 7, z = -14.0, vx =  3.6 }
    }
    for li = 1, #l_cfg do
        local c = l_cfg[li]
        for k = 1, 3 do
            local lx = (k - 2) * 10.6 + (li - 2) * 2.1
            local le = eng.scene.spawn("vox_log")
            eng.scene.set_pos(le, lx - 2.28, 0.02, c.z - 0.57)
            eng.scene.set_mesh(le, S.vox_log, { tex = S.wood_tex, color = {0.72, 0.46, 0.24, 1.0}, cast_shadow = true })
            S.logs[#S.logs + 1] = { ent = le, lane = c.lane, x = lx, z = c.z, vx = c.vx, hw = 2.28 }
        end
    end

    -- Spawn 3 Lily Alcoves at Lane 8 (Z = -16.0)
    S.alcoves = {}
    for i = 1, 3 do
        local ax = ALCOVE_X[i]
        local ae = eng.scene.spawn("vox_lily_" .. tostring(i))
        eng.scene.set_pos(ae, ax - 1.08, 0.28, -16.0 - 0.90)
        eng.scene.set_mesh(ae, S.vox_lily, { color = {0.35, 0.95, 0.45, 1.0} })
        S.alcoves[i] = { ent = ae, x = ax, z = -16.0, filled = false }
    end

    S.frog = eng.scene.spawn("vox_frog_player")
    eng.scene.set_mesh(S.frog, S.vox_frog, { color = {0.28, 0.95, 0.35, 1.0}, cast_shadow = true })

    S.hop_cd = 0.0
    S.lives = 5
    S.score = 0
    S.alcoves_filled = 0
    S.logs_ridden = 0
    S.won = false
    reset_frog()

    eng.camera.look_at(0.0, 15.5, 8.5, 0.0, 0.0, -8.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.hop_cd = math.max(0.0, S.hop_cd - dt)
    S.hop_t = math.max(0.0, S.hop_t - dt * 7.5)

    -- Move trucks
    for i = 1, #S.trucks do
        local t = S.trucks[i]
        t.x = wrap_x(t.x + t.vx * dt)
        eng.scene.set_pos(t.ent, t.x - 1.4, 0.28, t.z - 0.54)
    end

    -- Move river logs
    for i = 1, #S.logs do
        local l = S.logs[i]
        l.x = wrap_x(l.x + l.vx * dt)
        eng.scene.set_pos(l.ent, l.x - 2.28, 0.02, l.z - 0.57)
    end

    -- Discrete arcade hop input
    if S.hop_cd <= 0.0 then
        local dx, d_lane = 0.0, 0
        if eng.input.pressed("up") or eng.input.down("up") then d_lane = 1
        elseif eng.input.pressed("down") or eng.input.down("down") then d_lane = -1
        elseif eng.input.pressed("left") or eng.input.down("left") then dx = -1.5
        elseif eng.input.pressed("right") or eng.input.down("right") then dx = 1.5 end

        if d_lane ~= 0 or dx ~= 0.0 then
            local nl = eng.math.clamp(S.lane + d_lane, 0, 8)
            local nx = eng.math.clamp(S.fx + dx, -11.5, 11.5)
            if nl ~= S.lane or math.abs(nx - S.fx) > 0.01 then
                S.lane = nl
                S.fx = nx
                S.fz = -S.lane * STEP_Z
                S.hop_cd = 0.10
                S.hop_t = 1.0
                if d_lane > 0 then S.score = S.score + 10 end
                eng.audio.play(S.sfx_hop, S.fx, 0.5, S.fz, 0)
            end
        end
    end

    -- Highway truck collision (lanes 1..3)
    if S.lane >= 1 and S.lane <= 3 then
        for i = 1, #S.trucks do
            local t = S.trucks[i]
            if t.lane == S.lane and math.abs(S.fx - t.x) < (t.hw + 0.42) then
                S.lives = math.max(1, S.lives - 1)
                eng.audio.play(S.sfx_splash, S.fx, 0.4, S.fz, 0)
                reset_frog()
                break
            end
        end
    end

    -- River log riding (lanes 5..7)
    if S.lane >= 5 and S.lane <= 7 then
        local on_log = nil
        for i = 1, #S.logs do
            local l = S.logs[i]
            if l.lane == S.lane and math.abs(S.fx - l.x) <= (l.hw + 0.22) then
                on_log = l
                break
            end
        end
        if on_log then
            S.fx = S.fx + on_log.vx * dt
            S.logs_ridden = S.logs_ridden + 1
            if math.abs(S.fx) > 12.2 then
                S.lives = math.max(1, S.lives - 1)
                reset_frog()
            end
        else
            S.lives = math.max(1, S.lives - 1)
            eng.audio.play(S.sfx_splash, S.fx, 0.2, S.fz, 0)
            reset_frog()
        end
    end

    -- Lily Alcove goal check (lane 8)
    if S.lane == 8 then
        local landed = false
        for i = 1, #S.alcoves do
            local a = S.alcoves[i]
            if not a.filled and math.abs(S.fx - a.x) <= 1.45 then
                a.filled = true
                landed = true
                S.alcoves_filled = S.alcoves_filled + 1
                S.score = S.score + 300
                eng.audio.play(S.sfx_goal, a.x, 0.6, a.z, 0)
                local trophy = eng.scene.spawn("lily_trophy_" .. tostring(i))
                eng.scene.set_pos(trophy, a.x - 0.5, 0.55, a.z - 0.5)
                eng.scene.set_mesh(trophy, S.vox_frog, { color = {1.0, 0.88, 0.22, 1.0}, cast_shadow = true })
                break
            end
        end
        if S.alcoves_filled >= 3 then
            S.won = true
            S.score = S.score + 500
        else
            if not landed then S.lives = math.max(1, S.lives - 1) end
            reset_frog()
        end
    end

    local hop_arc = math.sin(S.hop_t * math.pi) * 0.55
    eng.scene.set_pos(S.frog, S.fx - 0.5, 0.35 + hop_arc, S.fz - 0.5)
    eng.camera.look_at(S.fx * 0.2, 15.5, 8.5, S.fx * 0.15, 0.0, -8.0, 0)
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | LILIES " .. S.alcoves_filled .. "/3 | SCORE " .. S.score, 1.0, {0.55, 1.0, 0.62, 1.0})
    eng.ui.bar(x, y + 26, 180, S.lives / 5.0, "LIVES ")
end
