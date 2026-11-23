-- 004_chrono_kart_64: 3-Cup Arcade Kart Racer with Poisson Flora & Rubber-Band AI
local S = game.state

local TRACK_TEX_RECIPES = { "cobble", "stone_brick", "marble" }
local NUM_WPS = 8

local function track_point(idx, rx, rz)
    local ang = ((idx - 1) / NUM_WPS) * 2.0 * math.pi
    return math.cos(ang) * rx, math.sin(ang) * rz
end

local function clear_cup_entities()
    if S.cup_ents then
        for i = 1, #S.cup_ents do eng.scene.despawn(S.cup_ents[i]) end
    end
    S.cup_ents = {}
    S.ai_karts = {}
    S.waypoints = {}
end

local function build_cup(cup_idx)
    clear_cup_entities()
    S.stage = cup_idx
    local seed_base = math.floor(eng.math.range(300, 700000)) + cup_idx * 409

    local rx = 18.0 + cup_idx * 2.0
    local rz = 13.0 + cup_idx * 1.5
    S.rx, S.rz = rx, rz

    local grass_tex = eng.procgen.texture("grass", seed_base, 64)
    local road_tex = eng.procgen.texture(TRACK_TEX_RECIPES[((cup_idx - 1) % #TRACK_TEX_RECIPES) + 1], seed_base + 5, 64)

    -- Infield/outfield meadow ground
    local ground = eng.scene.spawn("cup_meadow_" .. tostring(cup_idx))
    eng.scene.set_pos(ground, 0.0, -0.3, 0.0)
    eng.scene.set_scale(ground, 84.0, 0.5, 84.0)
    eng.scene.set_mesh(ground, S.box_mesh, { tex = grass_tex, roughness = 0.9 })
    S.cup_ents[#S.cup_ents + 1] = ground

    -- Build 8-segment 3D oval circuit + checkpoint arches
    for i = 1, NUM_WPS do
        local x0, z0 = track_point(i, rx, rz)
        local x1, z1 = track_point((i % NUM_WPS) + 1, rx, rz)
        S.waypoints[i] = { x = x0, z = z0 }

        local mx, mz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
        local dx, dz = x1 - x0, z1 - z0
        local seg_len = math.sqrt(dx * dx + dz * dz) + 2.2
        local yaw = math.deg(math.atan2(-dx, -dz))

        local seg = eng.scene.spawn("track_seg_" .. tostring(i))
        eng.scene.set_pos(seg, mx, 0.02, mz)
        eng.scene.set_rot_deg(seg, 0.0, yaw, 0.0)
        eng.scene.set_scale(seg, 5.5, 0.12, seg_len)
        eng.scene.set_mesh(seg, S.box_mesh, { tex = road_tex, roughness = 0.72 })
        S.cup_ents[#S.cup_ents + 1] = seg

        if i == 1 or i == 5 then
            local gate = eng.scene.spawn("finish_gate_" .. tostring(i))
            eng.scene.set_pos(gate, x0, 0.0, z0)
            eng.scene.set_rot_deg(gate, 0.0, yaw, 0.0)
            eng.scene.set_scale(gate, 2.2, 1.6, 1.4)
            eng.scene.set_mesh(gate, S.arch_mesh, { color = (i == 1) and {1.0, 0.85, 0.2, 1.0} or {0.35, 0.85, 1.0, 1.0} })
            S.cup_ents[#S.cup_ents + 1] = gate
        end
    end

    -- Roadside Poisson-disk scattered L-system trees
    local tree_mesh = eng.procgen.tree(seed_base + 99, 2, 3.2, 0.24)
    local pts = eng.procgen.scatter_poisson(seed_base + 33, 68.0, 68.0, 7.5, 28)
    S.tree_count = 0
    for i = 1, #pts do
        local tx = pts[i][1] - 34.0
        local tz = pts[i][2] - 34.0
        -- Keep trees clear of the asphalt oval ribbon (ellipse norm distance ~= 1.0)
        local en = math.sqrt((tx / rx) * (tx / rx) + (tz / rz) * (tz / rz))
        if en < 0.65 or en > 1.32 then
            local te = eng.scene.spawn("flora_tree_" .. tostring(i))
            eng.scene.set_pos(te, tx, 0.0, tz)
            eng.scene.set_mesh(te, tree_mesh, { color = {0.28, 0.72, 0.30, 1.0}, cast_shadow = true })
            S.cup_ents[#S.cup_ents + 1] = te
            S.tree_count = S.tree_count + 1
        end
    end

    -- Place player kart & 3 rubber-band AI karts on grid at waypoint 1 heading toward waypoint 2
    local sx, sz = S.waypoints[1].x, S.waypoints[1].z
    local nx, nz = S.waypoints[2].x, S.waypoints[2].z
    S.px, S.pz = sx, sz
    S.yaw = math.deg(math.atan2(-(nx - sx), -(nz - sz)))
    S.speed = 0.0
    S.boost_timer = 0.0
    S.next_wp = 2
    S.checkpoints_hit = 0

    if not S.player_ent then
        S.player_ent = eng.scene.spawn("player_kart")
    end
    eng.scene.set_pos(S.player_ent, S.px, 0.35, S.pz)
    eng.scene.set_rot_deg(S.player_ent, 0.0, S.yaw, 0.0)
    eng.scene.set_scale(S.player_ent, 0.9, 0.8, 1.1)
    eng.scene.set_mesh(S.player_ent, S.fighter_mesh, { color = {1.0, 0.22, 0.22, 1.0}, metallic = 0.4, roughness = 0.35 })

    local ai_colors = {
        {0.2, 0.55, 1.0, 1.0},
        {0.25, 0.9, 0.35, 1.0},
        {0.95, 0.45, 0.95, 1.0}
    }
    for k = 1, 3 do
        local ke = eng.scene.spawn("rival_kart_" .. tostring(k))
        local kx = sx + (k - 2) * 1.4
        local kz = sz - 1.2 * k
        eng.scene.set_pos(ke, kx, 0.35, kz)
        eng.scene.set_scale(ke, 0.85, 0.75, 1.05)
        eng.scene.set_mesh(ke, S.fighter_mesh, { color = ai_colors[k], metallic = 0.4, roughness = 0.4 })
        S.cup_ents[#S.cup_ents + 1] = ke
        S.ai_karts[k] = { ent = ke, x = kx, z = kz, wp = 2, prog = 0, base_spd = 13.5 + k * 0.6, stun = 0.0 }
    end

    local rad = math.rad(S.yaw)
    eng.camera.look_at(S.px + math.sin(rad) * 6.5, 3.2, S.pz + math.cos(rad) * 6.5, S.px, 0.8, S.pz, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 320, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.20, 0.52, 0.95, 0.78, 0.88, 0.98)
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.4, -1.0, -0.35}, color = {2.2, 2.1, 1.9}, shadow = true })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.fighter_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_boost = eng.audio.synth("saw", 300, 0.16, 680)
    S.sfx_pulse = eng.audio.synth("square", 520, 0.14, 200)
    S.sfx_lap = eng.audio.synth("triangle", 480, 0.22, 960)

    S.chrono_charge = 1.0
    S.cups_won = 0
    S.total_checkpoints = 0
    S.rank = 1
    S.won = false

    build_cup(1)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    local steer, throttle = eng.input.axis2d("left", "right", "down", "up")
    S.yaw = S.yaw - steer * 135.0 * dt

    if eng.input.pressed("jump") then
        S.boost_timer = 0.55
        eng.audio.play(S.sfx_boost, S.px, 0.5, S.pz, 0)
    end
    if (eng.input.pressed("fire") or eng.input.pressed("interact")) and S.chrono_charge >= 0.5 then
        S.chrono_charge = 0.0
        S.boost_timer = 0.75
        eng.audio.play(S.sfx_pulse, S.px, 0.5, S.pz, 0)
        for k = 1, #S.ai_karts do S.ai_karts[k].stun = 0.8 end
    end
    S.chrono_charge = math.min(1.0, S.chrono_charge + 0.35 * dt)
    S.boost_timer = math.max(0.0, S.boost_timer - dt)

    local max_spd = (S.boost_timer > 0.0) and 48.0 or 24.0
    if throttle > 0.05 then
        S.speed = math.min(max_spd, S.speed + 55.0 * throttle * dt)
    elseif throttle < -0.05 then
        S.speed = math.max(0.0, S.speed - 40.0 * dt)
    else
        S.speed = math.max(0.0, S.speed - 14.0 * dt)
    end

    local rad = math.rad(S.yaw)
    S.px = S.px - math.sin(rad) * S.speed * dt
    S.pz = S.pz - math.cos(rad) * S.speed * dt
    eng.scene.set_pos(S.player_ent, S.px, 0.35, S.pz)
    eng.scene.set_rot_deg(S.player_ent, 0.0, S.yaw, -steer * 10.0)

    -- Checkpoint & cup finish detection
    local wp = S.waypoints[S.next_wp]
    if eng.math.dist3(S.px, 0, S.pz, wp.x, 0, wp.z) < 5.5 then
        S.checkpoints_hit = S.checkpoints_hit + 1
        S.total_checkpoints = S.total_checkpoints + 1
        S.next_wp = (S.next_wp % NUM_WPS) + 1
        if S.checkpoints_hit >= NUM_WPS then
            eng.audio.play(S.sfx_lap, S.px, 1.0, S.pz, 0)
            S.cups_won = S.cups_won + 1
            if S.stage < 3 then
                eng.save.write("chrono_kart_progress", "cup_" .. tostring(S.stage + 1))
                build_cup(S.stage + 1)
                return
            else
                S.won = true
                eng.save.write("chrono_kart_progress", "clear")
                return
            end
        end
    end

    -- Rubber-band AI rival karts
    local ahead = 0
    for k = 1, #S.ai_karts do
        local ai = S.ai_karts[k]
        ai.stun = math.max(0.0, ai.stun - dt)
        local awp = S.waypoints[ai.wp]
        local dx, dz = awp.x - ai.x, awp.z - ai.z
        local d = math.sqrt(dx * dx + dz * dz)
        -- Rubber-band: speed up if behind player, ease off if ahead
        local diff = S.checkpoints_hit - ai.prog
        local rubber = eng.math.clamp(1.0 + diff * 0.14, 0.72, 1.28)
        local spd = ai.base_spd * rubber * ((ai.stun > 0.0) and 0.45 or 1.0)
        if d > 0.2 then
            ai.x = ai.x + (dx / d) * spd * dt
            ai.z = ai.z + (dz / d) * spd * dt
        end
        if d < 3.5 then
            ai.prog = ai.prog + 1
            ai.wp = (ai.wp % NUM_WPS) + 1
        end
        local ayaw = math.deg(math.atan2(-dx, -dz))
        eng.scene.set_pos(ai.ent, ai.x, 0.35, ai.z)
        eng.scene.set_rot_deg(ai.ent, 0.0, ayaw, 0.0)
        if ai.prog > S.checkpoints_hit then ahead = ahead + 1 end
    end
    S.rank = 1 + ahead

    eng.camera.look_at(S.px + math.sin(rad) * 6.5, 3.2, S.pz + math.cos(rad) * 6.5, S.px, 0.8, S.pz, 0)
end

function draw()
    local wp = S.waypoints[S.next_wp]
    if wp then eng.render.draw_sprite(wp.x, 2.4, wp.z, 1.1, 1.1, S.orb_tex) end
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | CUP " .. S.stage .. "/3 | POS " .. S.rank .. "/4 | CP " .. S.checkpoints_hit .. "/8", 1.0, {1.0, 0.9, 0.35, 1.0})
    eng.ui.bar(x, y + 26, 200, S.chrono_charge, "CHRONO ")
end
