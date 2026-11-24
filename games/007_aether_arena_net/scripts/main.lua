-- 007_aether_arena_net: 3-Round Portal Arena Blaster (Cross-Portal Railgun + Behavior Tree Bots)
local S = game.state
local bt = eng.bt

local function clear_round_bots()
    if S.bots then
        for i = 1, #S.bots do
            if S.bots[i].alive then eng.scene.despawn(S.bots[i].ent) end
        end
    end
    S.bots = {}
end

local function build_bot_tree()
    local retreat_low_hp = bt.sequence({
        bt.action(function(b)
            return (b.hp <= 1) and bt.SUCCESS or bt.FAILURE
        end),
        bt.action(function(b, dt)
            -- Retreat toward health shrine at (8, 0)
            local dx, dz = 8.0 - b.x, 0.0 - b.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d > 0.5 then
                b.x = b.x + (dx / d) * 4.5 * dt
                b.z = b.z + (dz / d) * 4.5 * dt
            end
            return bt.SUCCESS
        end)
    })

    local strafe_duel = bt.sequence({
        bt.action(function(b)
            return (eng.math.dist3(b.x, 0, b.z, S.px, 0, S.pz) < 15.0) and bt.SUCCESS or bt.FAILURE
        end),
        bt.action(function(b, dt)
            b.phase = b.phase + dt * 2.2
            b.x = eng.math.clamp(b.x + math.cos(b.phase) * 2.0 * dt, -13.0, 13.0)
            return bt.SUCCESS
        end)
    })

    local patrol_lane = bt.action(function(b, dt)
        b.phase = b.phase + dt * 1.5
        b.z = eng.math.clamp(b.home_z + math.sin(b.phase) * 1.5, -8.5, 8.5)
        return bt.SUCCESS
    end)

    return bt.selector({ retreat_low_hp, strafe_duel, patrol_lane })
end

local function spawn_round(r_idx)
    clear_round_bots()
    S.stage = r_idx
    local seed_base = math.floor(eng.math.range(600, 800000)) + r_idx * 271

    -- Bot #1 stands in the South Portal firing lane (0, 1.1, 5.0) so firing North (-Z) into p_north hits through portal!
    local spawns = {
        { 0.0,  5.0 },
        { -5.5, -3.5 },
        {  5.5, -4.0 }
    }
    for i = 1, 3 do
        local bx, bz = spawns[i][1], spawns[i][2]
        local be = eng.scene.spawn("arena_bot_r" .. tostring(r_idx) .. "_" .. tostring(i))
        eng.scene.set_pocket(be, 0)
        eng.scene.set_pos(be, bx, 0.9, bz)
        eng.procgen.person(be, seed_base + i * 29)
        local bid = eng.physics.add_body(be, { shape = "aabb", motion = "kinematic", pocket = 0, half_extents = {0.75, 1.1, 0.75} })
        S.bots[#S.bots + 1] = {
            ent = be, body = bid, x = bx, z = bz, home_z = bz,
            hp = 2, alive = true, phase = i * 1.3, lock_lane = (i == 1)
        }
    end
end

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.014 })
    eng.render.set_sky(0.06, 0.03, 0.14, 0.24, 0.08, 0.32)
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.3, -1.0, -0.4}, color = {2.0, 1.85, 2.2}, shadow = true })
    eng.render.add_light({ type = "point", pocket = 0, pos = {0.0, 6.0, 0.0}, color = {1.8, 2.4, 3.0}, range = 36.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_rail = eng.audio.synth("saw", 740, 0.14, 180)
    S.sfx_portal_frag = eng.audio.synth("triangle", 440, 0.22, 1120)

    local floor_tex = eng.procgen.texture("sci_fi_panel", 707, 64)
    local floor_e = eng.scene.spawn("aether_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 34.0, 0.5, 34.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = floor_tex, metallic = 0.35, roughness = 0.55 })

    -- Side pillars framing the arena
    for sx = -1, 1, 2 do
        for sz = -1, 1, 2 do
            local pil = eng.scene.spawn("arena_pillar_" .. tostring(sx) .. "_" .. tostring(sz))
            eng.scene.set_pos(pil, sx * 11.0, 0.0, sz * 9.0)
            eng.scene.set_mesh(pil, S.pillar_mesh, { tex = floor_tex, color = {0.55, 0.75, 1.0, 1.0} })
        end
    end

    -- Bidirectional North <-> South Arena Shortcut Portals!
    -- Shooting -Z into p_north (z = -10) emerges from p_south (z = +10) heading -Z!
    local arch_n = eng.scene.spawn("portal_arch_north")
    eng.scene.set_pos(arch_n, 0.0, 0.0, -10.0)
    eng.scene.set_scale(arch_n, 1.6, 1.2, 1.0)
    eng.scene.set_mesh(arch_n, S.arch_mesh, { color = {0.2, 0.9, 1.0, 1.0} })

    local arch_s = eng.scene.spawn("portal_arch_south")
    eng.scene.set_pos(arch_s, 0.0, 0.0, 10.0)
    eng.scene.set_scale(arch_s, 1.6, 1.2, 1.0)
    eng.scene.set_mesh(arch_s, S.arch_mesh, { color = {1.0, 0.45, 0.2, 1.0} })

    S.p_north = eng.scene.spawn("shortcut_portal_north")
    eng.scene.set_pocket(S.p_north, 0)
    eng.scene.set_pos(S.p_north, 0.0, 1.4, -10.0)

    S.p_south = eng.scene.spawn("shortcut_portal_south")
    eng.scene.set_pocket(S.p_south, 0)
    eng.scene.set_pos(S.p_south, 0.0, 1.4, 10.0)
    eng.scene.set_rot_deg(S.p_south, 0.0, 180.0, 0.0)

    eng.portal.link(S.p_north, S.p_south, 2.8, 2.6, 1.0, true, true)

    S.bot_bt = build_bot_tree()
    S.px, S.py, S.pz = 0.0, 1.3, -3.5
    S.yaw = 0.0
    S.pitch = 0.0
    S.hp = 100
    S.score = 0
    S.frags = 0
    S.portal_frags = 0
    S.bt_ticks = 0
    S.cooldown = 0.0
    S.won = false

    eng.input.set_mouse_lock(true)
    spawn_round(1)
    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
    eng.mod.emit("post_init")
end

local function fire_railgun()
    local ry, rp = math.rad(S.yaw or 0.0), math.rad(S.pitch or 0.0)
    local cp = math.cos(rp)
    local dx, dy, dz = -math.sin(ry) * cp, math.sin(rp), -math.cos(ry) * cp
    eng.audio.play(S.sfx_rail, S.px, S.py, S.pz, 0)

    local hit = eng.physics.raycast(0, S.px, 1.1, S.pz, dx, dy, dz, 45.0)
    if hit then
        for i = 1, #S.bots do
            local b = S.bots[i]
            if b.alive and b.ent == hit.entity then
                local is_portal = (hit.portal_hops or 0) >= 1
                b.hp = b.hp - (is_portal and 2 or 2)
                if b.hp <= 0 then
                    b.alive = false
                    eng.scene.despawn(b.ent)
                    S.frags = S.frags + 1
                    if is_portal then
                        S.portal_frags = S.portal_frags + 1
                        S.score = S.score + 300
                        eng.audio.play(S.sfx_portal_frag, b.x, 1.2, b.z, 0)
                    else
                        S.score = S.score + 100
                    end
                end
            end
        end
    end
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)

    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw or 0.0, S.pitch or 0.0, 9.0, dt)
    local prev_x, prev_y, prev_z = S.px, S.py, S.pz
    S.px = eng.math.clamp(S.px + dx, -14.0, 14.0)
    S.pz = eng.math.clamp(S.pz + dz, -12.0, 12.0)

    if eng.input.pressed("jump") or eng.input.pressed("interact") then
        S.hp = math.min(100, S.hp + 10)
    end

    local dst_pk, wx, wy, wz = eng.portal.check_crossing(0, prev_x, prev_y, prev_z, S.px, S.py, S.pz)
    if dst_pk ~= nil then
        S.px, S.py, S.pz = wx, 1.3, wz
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        S.cooldown = 0.14
        fire_railgun()
    end

    -- Tick Behavior Tree AI for all living bots
    local alive_n = 0
    for i = 1, #S.bots do
        local b = S.bots[i]
        if b.alive then
            alive_n = alive_n + 1
            if not b.lock_lane then
                S.bot_bt(b, dt)
            else
                S.bot_bt(b, 0.0) -- Evaluates BT nodes while holding portal lane x=0
            end
            S.bt_ticks = S.bt_ticks + 1
            eng.scene.set_pos(b.ent, b.x, 0.9, b.z)
        end
    end

    if alive_n == 0 then
        if S.stage < 3 then
            eng.save.write("aether_arena_progress", "round_" .. tostring(S.stage + 1))
            spawn_round(S.stage + 1)
            return
        else
            S.won = true
            eng.save.write("aether_arena_progress", "clear")
            return
        end
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
end

function draw()
    for i = 1, #S.bots do
        local b = S.bots[i]
        if b.alive then eng.render.draw_sprite(b.x, 2.3, b.z, 0.7, 0.7, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | ROUND " .. S.stage .. "/3 | PORTAL FRAGS " .. S.portal_frags .. " | SCORE " .. S.score, 1.0, {0.5, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.hp / 100.0, "SHIELD ")
end
