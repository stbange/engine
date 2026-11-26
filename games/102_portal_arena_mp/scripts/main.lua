-- 102: Portal Arena Cross-Play — 1-4P Split-Screen + Gamepads + Cross-Platform Dedicated Server
local S = game.state

local PLAYER_COLORS = {
    {0.18, 0.88, 0.98, 1.0}, -- P1 Cyan
    {0.98, 0.52, 0.18, 1.0}, -- P2 Amber
    {0.30, 0.96, 0.44, 1.0}, -- P3 Emerald
    {0.96, 0.34, 0.78, 1.0}, -- P4 Magenta
}

local SPAWNS = {
    { x = -3.2, y = 1.45, z =  4.5, yaw =  0.0 },
    { x =  3.2, y = 1.45, z =  4.5, yaw =  0.0 },
    { x = -6.0, y = 1.45, z =  7.5, yaw = -20.0 },
    { x =  6.0, y = 1.45, z =  7.5, yaw =  20.0 },
}

local function spawn_wall(name, x, y, z, sx, sy, sz, mesh, mat)
    local e = eng.scene.spawn(name)
    eng.scene.set_pocket(e, 0)
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_scale(e, sx, sy, sz)
    eng.scene.set_mesh(e, mesh, mat)
    eng.physics.add_body(e, { shape = "aabb", motion = "static", pocket = 0, half_extents = {sx * 0.5, sy * 0.5, sz * 0.5} })
    return e
end

local function apply_split_mode(n)
    S.split_count = n
    if n <= 1 then
        eng.camera.set_split(1)
    elseif n == 2 then
        eng.camera.set_split(2, "vertical")
    else
        eng.camera.set_split(4, "grid4")
    end
end

local function step_player_sim(p, dx, dz, dt)
    local nx, nz = eng.physics.slide_move(p.pk, p.x, p.y, p.z, dx, dz, 0.38)
    local dp, wx, wy, wz = eng.portal.check_crossing(p.pk, p.x, p.y, p.z, nx, p.y, nz)
    if dp then
        p.pk, p.x, p.y, p.z = dp, wx, math.max(1.45, wy), wz
        if dp == S.vault_pk then S.entered_vault = true end
    else
        p.x, p.z = nx, nz
    end
    for j = 1, #S.gems do
        local g = S.gems[j]
        if g.active and g.pk == p.pk then
            local gx, gz = p.x - g.x, p.z - g.z
            if gx * gx + gz * gz <= 1.35 * 1.35 then
                g.active = false
                g.respawn = 6.0
                p.sc = (p.sc or 0) + g.val
                if g.ent then eng.scene.set_pos(g.ent, g.x, -40.0, g.z) end
                if not eng.net.is_server() then
                    eng.audio.play(S.sfx_gem, g.x, 1.4, g.z, g.pk)
                end
            end
        end
    end
end

function init()
    S.ticks = 0
    S.entered_vault = false
    S.remote_ents = {}
    S.remote_pos = {}
    S.local_players = {}
    eng.math.seed(102)

    eng.fx.sky(eng, "alpine_day")
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.35, -1.0, -0.4}, color = {1.85, 1.78, 1.65}, shadow = true })
    eng.render.add_light({ type = "point", pocket = 0, pos = {0, 5.5, 0}, color = {1.5, 1.1, 0.6}, range = 28 })

    local box_m = eng.asset.box(1, 1, 1)
    local cyl_m = eng.asset.cylinder(0.45, 0.45, 1.0, 12)
    local sph_m = eng.asset.sphere(0.45, 10, 14)
    local stone_tex = eng.procgen.texture("stone_brick", 102, 64)
    local marble_tex = eng.procgen.texture("marble", 204, 64)
    S.avatar_mesh = cyl_m
    S.head_mesh = sph_m

    -- Courtyard floor + perimeter walls (pocket 0)
    local floor = eng.scene.spawn("courtyard_floor")
    eng.scene.set_pocket(floor, 0)
    eng.scene.set_pos(floor, 0, -0.5, 0)
    eng.scene.set_scale(floor, 32, 1, 32)
    eng.scene.set_mesh(floor, box_m, { tex = stone_tex, color = {0.42, 0.46, 0.52, 1.0}, roughness = 0.75 })
    eng.physics.add_body(floor, { shape = "aabb", motion = "static", pocket = 0, half_extents = {16, 0.5, 16} })

    local wall_mat = { tex = marble_tex, color = {0.58, 0.62, 0.68, 1.0}, roughness = 0.6 }
    spawn_wall("wall_n",  0, 2.0, -15.5, 32, 4.0, 1.0, box_m, wall_mat)
    spawn_wall("wall_s",  0, 2.0,  15.5, 32, 4.0, 1.0, box_m, wall_mat)
    spawn_wall("wall_w", -15.5, 2.0, 0,  1.0, 4.0, 32, box_m, wall_mat)
    spawn_wall("wall_e",  15.5, 2.0, 0,  1.0, 4.0, 32, box_m, wall_mat)

    -- 4 Metallic Pillars + Fire & Smoke Braziers
    local gold_mat = eng.fx.material("gold", { cast_shadow = true })
    local chrome_mat = eng.fx.material("chrome", { cast_shadow = true })
    local corners = { {-9.0, -9.0}, {9.0, -9.0}, {-9.0, 9.0}, {9.0, 9.0} }
    for i = 1, 4 do
        local cx, cz = corners[i][1], corners[i][2]
        spawn_wall("pillar_" .. i, cx, 2.2, cz, 1.6, 4.4, 1.6, box_m, (i % 2 == 1) and gold_mat or chrome_mat)
        if not eng.net.is_server() then
            eng.fx.spawn(eng, "fire", cx, 4.5, cz, 0, { rate = 14, seed = 100 + i })
            eng.fx.spawn(eng, "smoke", cx, 5.1, cz, 0, { rate = 6, seed = 200 + i })
        end
    end

    -- Central "Bigger on the Inside" Crystal Vault (pocket 1)
    S.vault = eng.space.create_pocket_building(eng, {
        exterior_pos = {0, 0, -5.0},
        exterior_size = {4.2, 3.6, 4.2},
        interior_size = {20.0, 7.5, 20.0},
        door_size = {2.0, 2.6},
        pocket = "crystal_vault"
    })
    S.vault_pk = S.vault.pocket_id
    eng.fx.sky(eng, "starry_night", { pocket = S.vault_pk })
    eng.render.add_light({ type = "point", pocket = S.vault_pk, pos = {0, 5.2, 0}, color = {1.4, 2.2, 2.8}, range = 34 })
    eng.render.add_light({ type = "point", pocket = S.vault_pk, pos = {-5, 3.0, -4}, color = {2.4, 0.7, 1.6}, range = 22 })

    -- Collectible Translucent Emissive Crystals (courtyard + crystal vault)
    local gem_specs = {
        { pk = 0, x = -4.5, z =  1.0, val = 1, mat = "ruby" },
        { pk = 0, x =  4.5, z =  1.0, val = 1, mat = "emerald" },
        { pk = 0, x = -6.0, z = -3.0, val = 1, mat = "crystal" },
        { pk = 0, x =  6.0, z = -3.0, val = 1, mat = "gold" },
        { pk = S.vault_pk, x =  0.0, z =  5.5, val = 2, mat = "crystal" },
        { pk = S.vault_pk, x = -4.5, z =  0.0, val = 2, mat = "ruby" },
        { pk = S.vault_pk, x =  4.5, z =  0.0, val = 2, mat = "emerald" },
    }
    S.gems = {}
    for i = 1, #gem_specs do
        local gs = gem_specs[i]
        local ge = eng.scene.spawn("gem_" .. i)
        eng.scene.set_pocket(ge, gs.pk)
        eng.scene.set_pos(ge, gs.x, 1.35, gs.z)
        eng.scene.set_scale(ge, 0.75, 1.1, 0.75)
        eng.scene.set_mesh(ge, sph_m, eng.fx.material(gs.mat))
        S.gems[i] = { ent = ge, pk = gs.pk, x = gs.x, z = gs.z, val = gs.val, active = true, respawn = 0.0 }
    end

    -- Spawn 4 Local Player Avatars (visible to each other across split-screen viewports!)
    for i = 1, 4 do
        local sp = SPAWNS[i]
        local body = eng.scene.spawn("local_p" .. i)
        eng.scene.set_pocket(body, 0)
        eng.scene.set_pos(body, sp.x, 0.75, sp.z)
        eng.scene.set_scale(body, 0.75, 1.35, 0.75)
        eng.scene.set_mesh(body, cyl_m, { color = PLAYER_COLORS[i], metallic = 0.45, roughness = 0.35, cast_shadow = true })
        local head = eng.scene.spawn("local_p" .. i .. "_head")
        eng.scene.set_pocket(head, 0)
        eng.scene.set_parent(head, body)
        eng.scene.set_pos(head, 0, 0.85, 0)
        eng.scene.set_scale(head, 0.65, 0.65, 0.65)
        eng.scene.set_mesh(head, sph_m, eng.fx.material("chrome", { color = PLAYER_COLORS[i] }))
        S.local_players[i] = {
            id = i, ent = body, head = head,
            x = sp.x, y = sp.y, z = sp.z, yaw = sp.yaw, pitch = -6.0, pk = 0, sc = 0
        }
    end

    S.sfx_gem = eng.audio.synth("triangle", 520, 0.14, 1040)

    -- Authoritative Server Mode (--server) vs Client / Local Split-Screen Mode
    if eng.net.is_server() then
        S.srv = eng.mp.create_server(eng, {
            seed = 102,
            snapshot_hz = 20,
            on_join = function(cid, p)
                local sp = SPAWNS[((cid - 1) % 4) + 1]
                p.x, p.y, p.z, p.yaw, p.pk, p.sc = sp.x, sp.y, sp.z, sp.yaw, 0, 0
                eng.log.info("Client #" .. cid .. " joined Portal Arena")
            end,
            on_input = function(cid, p, pkt, dt)
                local mx = eng.math.clamp(pkt.mx or 0, -1, 1)
                local my = eng.math.clamp(pkt.my or 0, -1, 1)
                local yaw = pkt.yaw or p.yaw or 0
                p.yaw = yaw
                local rad = yaw * (math.pi / 180.0)
                local fx, fz = -math.sin(rad), -math.cos(rad)
                local rx, rz = math.cos(rad), -math.sin(rad)
                local step_dt = math.min(0.1, math.max(dt, 1.0 / 30.0))
                step_player_sim(p, (fx * my + rx * mx) * 7.0 * step_dt, (fz * my + rz * mx) * 7.0 * step_dt, step_dt)
            end
        })
    else
        S.cli = eng.mp.create_client(eng, {
            input_hz = 30,
            on_welcome = function(id, seed)
                eng.log.info("Connected to server as player #" .. id .. " (seed=" .. seed .. ")")
            end,
            on_event = function(pkt)
                if pkt.t == "leave" and pkt.id and S.remote_ents[pkt.id] then
                    eng.scene.despawn(S.remote_ents[pkt.id])
                    S.remote_ents[pkt.id] = nil
                    S.remote_pos[pkt.id] = nil
                end
            end
        })
        if S.cli.url then
            S.cli:connect()
            apply_split_mode(1)
        elseif eng.input.gamepad_count() >= 3 then
            apply_split_mode(4)
        else
            apply_split_mode(2)
        end
    end
end

local function update_remote_avatars(dt)
    if not S.cli then return end
    for cid, rp in pairs(S.cli.players) do
        if cid ~= S.cli.local_id then
            local ent = S.remote_ents[cid]
            if not ent then
                ent = eng.scene.spawn("remote_p" .. cid)
                local col = PLAYER_COLORS[((cid - 1) % 4) + 1]
                eng.scene.set_scale(ent, 0.8, 1.5, 0.8)
                eng.scene.set_mesh(ent, S.avatar_mesh, eng.fx.material("gold", { color = col, emissive = {col[1]*0.3, col[2]*0.3, col[3]*0.3} }))
                S.remote_ents[cid] = ent
                S.remote_pos[cid] = { x = rp.x or 0, y = rp.y or 1.45, z = rp.z or 4 }
            end
            local cur = S.remote_pos[cid]
            cur.x = eng.mp.lerp(cur.x, rp.x or cur.x, dt, 14.0)
            cur.y = eng.mp.lerp(cur.y, rp.y or cur.y, dt, 14.0)
            cur.z = eng.mp.lerp(cur.z, rp.z or cur.z, dt, 14.0)
            eng.scene.set_pocket(ent, rp.pk or 0)
            eng.scene.set_pos(ent, cur.x, cur.y - 0.65, cur.z)
        end
    end
end

function update(dt)
    S.ticks = S.ticks + 1

    -- Spin & respawn collectible crystals
    for i = 1, #S.gems do
        local g = S.gems[i]
        if g.active then
            local bob = 1.35 + math.sin(S.ticks * 0.06 + i) * 0.18
            eng.scene.set_pos(g.ent, g.x, bob, g.z)
            eng.scene.set_rot_deg(g.ent, 15, S.ticks * 2.5 + i * 40, 0)
        else
            g.respawn = g.respawn - dt
            if g.respawn <= 0.0 then
                g.active = true
                eng.scene.set_pos(g.ent, g.x, 1.35, g.z)
            end
        end
    end

    if S.srv then
        S.srv:step(dt)
        return
    end

    -- Runtime split-screen switching: [1], [2], [4], or [V] cycle
    if eng.input.pressed("split_1") then apply_split_mode(1)
    elseif eng.input.pressed("split_2") then apply_split_mode(2)
    elseif eng.input.pressed("split_4") then apply_split_mode(4)
    elseif eng.input.pressed("toggle_split") then
        local nxt = (S.split_count == 1) and 2 or ((S.split_count == 2) and 4 or 1)
        apply_split_mode(nxt)
    end

    -- Step all active local players (each with independent keyboard zone / gamepad + pocket!)
    for i = 1, S.split_count do
        local p = S.local_players[i]
        local dx, dz, fx, fz
        p.yaw, p.pitch, dx, dz, fx, fz = eng.camera.fps_steer_player(i, p.yaw, p.pitch, 7.0, dt, 125.0)
        step_player_sim(p, dx, dz, dt)
        eng.scene.set_pocket(p.ent, p.pk)
        eng.scene.set_pocket(p.head, p.pk)
        eng.scene.set_pos(p.ent, p.x, p.y - 0.70, p.z)
        eng.scene.set_rot_deg(p.ent, 0, p.yaw, 0)
        local cx, cz = eng.physics.slide_move(p.pk, p.x, p.y + 0.9, p.z, -fx * 2.6, -fz * 2.6, 0.30)
        eng.camera.set_view(i, cx, p.y + 1.15, cz, p.pitch - 12.0, p.yaw, 0, p.pk)
    end

    -- Online WebSocket / Loopback synchronization
    if S.cli then
        local mx, my = eng.input.player_move(1)
        local p1 = S.local_players[1]
        S.cli:step(dt, { mx = mx, my = my, yaw = p1.yaw })
        update_remote_avatars(dt)
    end
end

function draw()
    if S.srv then return end
    for i = 1, S.split_count do
        local p = S.local_players[i]
        local vp = eng.camera.get_view_rect(i)
        local hx, hy = eng.ui.viewport_anchor(vp, "top_left", 14, 12, 320, 26)
        local pad_tag = eng.input.player_has_gamepad(i) and "PAD" or ("KB" .. i)
        local pk_tag = (p.pk == S.vault_pk) and "VAULT" or "PLAZA"
        local net_tag = (i == 1 and S.cli and S.cli.connected) and (" | " .. eng.i18n.t("online_status") .. " #" .. tostring(S.cli.local_id or "?")) or ""
        eng.ui.label(hx, hy, string.format("P%d[%s] SCORE:%d [%s]%s", i, pad_tag, p.sc, pk_tag, net_tag), 1.0, PLAYER_COLORS[i])
    end
    eng.ui.label(16, 44, eng.i18n.t("title") .. " | " .. eng.i18n.t("vault_hint"), 0.9)
end
