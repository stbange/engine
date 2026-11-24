-- 096_net_tag_arena: Jetpack + Portal Arena Tag ("Pass the IT Crown")
local S = game.state

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_sky(0.08, 0.16, 0.36, 0.28, 0.48, 0.72)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.4}, color = {2.1, 2.0, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, 0.0}, color = {1.5, 2.0, 2.6}, range = 26.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crown_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local floor_tex = eng.procgen.texture("sci_fi_panel", seed, 64)

    -- Main Tag Arena (pocket 0) + Jetpack Jump Platforms
    local floor_e = eng.scene.spawn("tag_arena_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 22.0, 0.5, 22.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = floor_tex, color = {0.26, 0.34, 0.46, 1.0}, roughness = 0.45 })

    for side = -1, 1, 2 do
        local pad = eng.scene.spawn("jet_pad_" .. tostring(side))
        eng.scene.set_pos(pad, side * 5.0, 1.1, -1.0)
        eng.scene.set_scale(pad, 3.2, 0.4, 3.2)
        eng.scene.set_mesh(pad, S.box_mesh, { color = {0.35, 0.75, 0.95, 1.0}, roughness = 0.3 })
    end

    -- Warp Tunnel Pocket connecting North Arena Archway (0, 1.3, -7.5) -> South Arena Archway (0, 1.3, 7.5)
    S.warp_id = eng.scene.register_pocket("warp_corridor")
    eng.render.add_light({ type = "point", pocket = "warp_corridor", pos = {0.0, 3.5, 0.0}, color = {2.4, 0.8, 3.0}, range = 18.0 })

    local w_floor = eng.scene.spawn("warp_corridor_floor")
    eng.scene.set_pocket(w_floor, S.warp_id)
    eng.scene.set_pos(w_floor, 0.0, -0.25, 0.0)
    eng.scene.set_scale(w_floor, 6.0, 0.5, 10.0)
    eng.scene.set_mesh(w_floor, S.box_mesh, { tex = floor_tex, color = {0.42, 0.18, 0.55, 1.0}, roughness = 0.3 })

    local arch_n = eng.scene.spawn("warp_arch_north")
    eng.scene.set_pos(arch_n, 0.0, 0.0, -7.5)
    eng.scene.set_scale(arch_n, 1.3, 1.15, 1.0)
    eng.scene.set_mesh(arch_n, S.arch_mesh, { color = {0.85, 0.35, 1.0, 1.0} })

    local arch_s = eng.scene.spawn("warp_arch_south")
    eng.scene.set_pos(arch_s, 0.0, 0.0, 7.5)
    eng.scene.set_scale(arch_s, 1.3, 1.15, 1.0)
    eng.scene.set_mesh(arch_s, S.arch_mesh, { color = {0.25, 0.95, 1.0, 1.0} })

    -- North Portal: World (0, 1.3, -7.5) -> Warp Corridor (0, 1.3, 3.5)
    local pn_src = eng.scene.spawn("tag_portal_n_src")
    eng.scene.set_pos(pn_src, 0.0, 1.3, -7.5)
    local pn_dst = eng.scene.spawn("tag_portal_n_dst")
    eng.scene.set_pocket(pn_dst, S.warp_id)
    eng.scene.set_pos(pn_dst, 0.0, 1.3, 3.5)
    eng.scene.set_rot_deg(pn_dst, 0.0, 180.0, 0.0)
    eng.portal.link(pn_src, pn_dst, 2.4, 2.6, 1.0, true, true)

    -- South Exit Portal: Warp Corridor (0, 1.3, -3.5) -> World (0, 1.3, 7.5) facing -Z into arena!
    local ps_src = eng.scene.spawn("tag_portal_s_src")
    eng.scene.set_pocket(ps_src, S.warp_id)
    eng.scene.set_pos(ps_src, 0.0, 1.3, -3.5)
    local ps_dst = eng.scene.spawn("tag_portal_s_dst")
    eng.scene.set_pos(ps_dst, 0.0, 1.3, 7.5)
    eng.scene.set_rot_deg(ps_dst, 0.0, 180.0, 0.0)
    eng.portal.link(ps_src, ps_dst, 2.4, 2.6, 1.0, true, true)

    -- 4 Competitors: [1] = Local Player, [2..4] = Replicated Bot Runners
    S.runners = {
        { is_player = true, pocket = 0, x = 0.0, y = 1.25, z = -2.5, vy = 0.0 },
        { ent = eng.scene.spawn("tag_bot_2"), pocket = 0, x =  0.0, y = 0.0, z =  4.8, vx =  2.2, vz =  0.5 },
        { ent = eng.scene.spawn("tag_bot_3"), pocket = 0, x = -3.8, y = 0.0, z = -3.5, vx =  0.8, vz =  2.4 },
        { ent = eng.scene.spawn("tag_bot_4"), pocket = 0, x =  3.8, y = 0.0, z = -4.2, vx = -1.8, vz =  1.6 }
    }
    for i = 2, 4 do
        local r = S.runners[i]
        eng.scene.set_pos(r.ent, r.x, r.y, r.z)
        eng.procgen.person(r.ent, seed + i * 29)
    end

    -- Glowing golden "IT" Crown entity
    S.crown_ent = eng.scene.spawn("it_crown")
    eng.scene.set_scale(S.crown_ent, 0.65, 0.65, 0.65)
    eng.scene.set_mesh(S.crown_ent, S.crown_mesh, { color = {1.0, 0.85, 0.15, 1.0}, roughness = 0.15 })

    S.sfx_tag = eng.audio.synth("square", 540, 0.14, 880)
    S.sfx_jet = eng.audio.synth("noise", 240, 0.06, 180)
    S.sfx_round = eng.audio.synth("triangle", 660, 0.22, 990)

    S.it_holder = 1
    S.tag_cd = 0.0
    S.round_timer = 1.65
    S.rounds_won = 0
    S.tags_made = 0
    S.jetpack_used = false
    S.used_portal = false
    S.yaw, S.pitch = 0.0, 0.0
    S.won = false

    eng.input.set_mouse_lock(true)
    sync_crown_and_cam()
    eng.mod.emit("post_init")
end

function sync_crown_and_cam()
    local holder = S.runners[S.it_holder]
    eng.scene.set_pocket(S.crown_ent, holder.pocket)
    local cy = holder.is_player and (holder.y + 0.9) or 2.25
    eng.scene.set_pos(S.crown_ent, holder.x, cy, holder.z)

    local p = S.runners[1]
    eng.camera.set(p.x, p.y + 0.35, p.z, S.pitch or 0.0, S.yaw or 0.0, 0.0, p.pocket)
end

function update(dt)
    if S.won then return end
    S.tag_cd = math.max(0.0, S.tag_cd - dt)
    S.round_timer = S.round_timer - dt

    -- Step Player #1 movement + Jetpack + Portal Crossing
    local p = S.runners[1]
    local spd = (eng.input.down("fire") or eng.input.pressed("fire")) and 13.5 or 9.0
    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw or 0.0, S.pitch or 0.0, spd, dt)

    if eng.input.down("jump") or eng.input.pressed("jump") then
        p.vy = math.min(6.5, p.vy + 24.0 * dt)
        S.jetpack_used = true
    else
        p.vy = p.vy - 14.0 * dt
    end
    local ny = eng.math.clamp(p.y + p.vy * dt, 1.25, 3.8)
    if ny <= 1.25 and p.vy < 0.0 then p.vy = 0.0 end

    local nx = eng.math.clamp(p.x + dx, -9.0, 9.0)
    local nz = eng.math.clamp(p.z + dz, -9.2, 9.2)
    local dst_p, wx, wy, wz = eng.portal.check_crossing(p.pocket, p.x, p.y, p.z, nx, ny, nz)
    if dst_p then
        p.pocket = dst_p
        p.x, p.y, p.z = wx, eng.math.clamp(wy, 1.25, 2.3), wz
        S.used_portal = true
    else
        p.x, p.y, p.z = nx, ny, nz
    end

    -- Step Bot Runners #2..#4
    for i = 2, 4 do
        local b = S.runners[i]
        if S.it_holder == 1 and p.pocket == 0 then
            -- Evade slightly but stay inside arena bounds
            local dx, dz = b.x - p.x, b.z - p.z
            local d = math.sqrt(dx * dx + dz * dz) + 0.001
            b.x = eng.math.clamp(b.x + (dx / d) * 2.6 * dt, -6.5, 6.5)
            b.z = eng.math.clamp(b.z + (dz / d) * 2.6 * dt, -6.0, 6.0)
        elseif S.it_holder == i then
            -- Bot with IT crown chases nearest non-IT runner
            local tx, tz = S.runners[3].x, S.runners[3].z
            if i == 3 then tx, tz = S.runners[4].x, S.runners[4].z end
            local dx, dz = tx - b.x, tz - b.z
            local d = math.sqrt(dx * dx + dz * dz) + 0.001
            b.x = eng.math.clamp(b.x + (dx / d) * 3.8 * dt, -6.5, 6.5)
            b.z = eng.math.clamp(b.z + (dz / d) * 3.8 * dt, -6.0, 6.0)
        else
            b.x = eng.math.clamp(b.x + b.vx * dt, -6.5, 6.5)
            b.z = eng.math.clamp(b.z + b.vz * dt, -6.0, 6.0)
            if math.abs(b.x) >= 6.4 then b.vx = -b.vx end
            if math.abs(b.z) >= 5.9 then b.vz = -b.vz end
        end
        eng.scene.set_pos(b.ent, b.x, 0.0, b.z)
    end

    -- Crown Tag Transfer Check
    if S.tag_cd <= 0.0 then
        local holder = S.runners[S.it_holder]
        for i = 1, 4 do
            if i ~= S.it_holder then
                local r = S.runners[i]
                if r.pocket == holder.pocket and eng.math.dist3(holder.x, 0.0, holder.z, r.x, 0.0, r.z) < 2.1 then
                    if S.it_holder == 1 then S.tags_made = S.tags_made + 1 end
                    S.it_holder = i
                    S.tag_cd = 0.55
                    eng.audio.play(S.sfx_tag, r.x, 1.4, r.z, r.pocket)
                    break
                end
            end
        end
    end

    -- Round Timer Resolution
    if S.round_timer <= 0.0 then
        if S.it_holder ~= 1 then
            S.rounds_won = S.rounds_won + 1
            eng.audio.play(S.sfx_round, p.x, p.y, p.z, p.pocket)
            if S.rounds_won >= 2 then
                S.won = true
                eng.save.write("net_tag_wins", tostring(S.rounds_won))
            else
                -- Start Round 2 with IT crown back on player!
                S.it_holder = 1
                S.round_timer = 1.45
                S.tag_cd = 0.25
            end
        else
            S.round_timer = 1.45
        end
    end

    sync_crown_and_cam()
end

function draw()
    local holder = S.runners[S.it_holder]
    if holder.pocket == S.runners[1].pocket then
        eng.render.draw_sprite(holder.x, 2.55, holder.z, 0.85, 0.85, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    local st = (S.it_holder == 1) and "YOU ARE IT!" or ("BOT #" .. S.it_holder .. " IS IT")
    eng.ui.label(x, y, eng.i18n.t("title") .. " | " .. st .. " | ROUNDS " .. S.rounds_won .. "/2", 1.0, {1.0, 0.9, 0.35, 1.0})
    eng.ui.bar(x, y + 26, 220, math.max(0.0, S.round_timer / 1.65), "TIMER ")
end
