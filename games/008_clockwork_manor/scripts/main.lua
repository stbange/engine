-- 008_clockwork_manor: 3-Wing Non-Euclidean Stealth Mansion (Deferred Spotlights + Markov Guests & Guards)
local S = game.state

local WINGS_CFG = {
    { key = "ballroom_wing",   label = "BALLROOM",   ext_x = -4.8, ext_z = -4.5, ext_col = {0.52, 0.28, 0.24, 1.0}, int_col = {0.36, 0.24, 0.28, 1.0}, spot_col = {2.8, 2.2, 1.2} },
    { key = "gallery_wing",    label = "GALLERY",    ext_x =  0.0, ext_z = -5.5, ext_col = {0.26, 0.36, 0.50, 1.0}, int_col = {0.24, 0.30, 0.42, 1.0}, spot_col = {1.5, 2.4, 2.9} },
    { key = "clocktower_wing", label = "CLOCKTOWER", ext_x =  4.8, ext_z = -4.5, ext_col = {0.46, 0.38, 0.22, 1.0}, int_col = {0.34, 0.30, 0.22, 1.0}, spot_col = {2.6, 1.7, 2.8} },
}

function init()
    eng.render.set_pipeline("deferred")
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 320, dither = true, color_bits = 6, fog_density = 0.014 })
    eng.render.set_sky(0.03, 0.05, 0.14, 0.10, 0.12, 0.24)

    -- Courtyard directional moonlight + getaway coach spotlight
    eng.render.add_light({ type = "dir", pocket = "world", dir = {-0.25, -1.0, -0.35}, color = {1.35, 1.45, 1.85}, shadow = true })
    eng.render.add_light({ type = "spot", pocket = "world", pos = {0.0, 5.5, 4.0}, dir = {0.0, -1.0, 0.0}, color = {2.4, 2.0, 1.3}, range = 18.0, shadow = true })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local cobble_tex = eng.procgen.texture("cobble", S.seed, 64)
    local marble_tex = eng.procgen.texture("marble", S.seed + 17, 64)

    S.sfx_warp = eng.audio.synth("sine", 340, 0.14, 620)
    S.sfx_heist = eng.audio.synth("triangle", 540, 0.22, 1080)
    S.sfx_alert = eng.audio.synth("saw", 640, 0.24, 220)

    -- Pocket 0 ("world"): Manor Courtyard + Getaway Gate
    local yard = eng.scene.spawn("manor_courtyard")
    eng.scene.set_pocket(yard, "world")
    eng.scene.set_pos(yard, 0.0, -0.25, 0.0)
    eng.scene.set_scale(yard, 26.0, 0.5, 24.0)
    eng.scene.set_mesh(yard, S.box_mesh, { tex = cobble_tex, color = {0.42, 0.45, 0.52, 1.0} })
    eng.physics.add_body(yard, { shape = "aabb", motion = "static", pocket = 0, half_extents = {13.0, 0.25, 12.0} })

    S.exit_x, S.exit_z = 0.0, 4.0
    local gate = eng.scene.spawn("getaway_arch")
    eng.scene.set_pocket(gate, "world")
    eng.scene.set_pos(gate, S.exit_x, 0.0, S.exit_z)
    eng.scene.set_mesh(gate, S.arch_mesh, { color = {0.80, 0.68, 0.34, 1.0}, cast_shadow = true })

    S.wings = {}
    S.pocket_labels = { [0] = "COURTYARD" }
    S.guests = {}
    S.guards = {}
    S.heirlooms = {}
    S.spotlights_added = 1

    for i = 1, #WINGS_CFG do
        local wc = WINGS_CFG[i]
        local bld = eng.space.create_pocket_building(eng, {
            outer_pocket = "world",
            pocket = wc.key,
            exterior_pos = {wc.ext_x, 0.0, wc.ext_z},
            exterior_size = {2.8, 3.0, 2.8},
            interior_size = {16.0, 7.5, 14.0},
            door_size = {1.3, 2.2},
            scale_ratio = 1.0,
            exterior_color = wc.ext_col,
            interior_color = wc.int_col,
            mesh_id = S.box_mesh
        })
        local pid = bld.pocket_id
        S.wings[i] = { cfg = wc, bld = bld, pocket_id = pid, door_z = wc.ext_z + 1.4 }
        S.pocket_labels[pid] = wc.label

        -- Chandelier + Security Spotlight over heirloom vault pedestal
        eng.render.add_light({ type = "point", pocket = wc.key, pos = {0.0, 5.8, 2.5}, color = {2.0, 1.7, 1.3}, range = 22.0 })
        eng.render.add_light({ type = "spot", pocket = wc.key, pos = {0.0, 5.6, -3.8}, dir = {0.0, -1.0, 0.0}, color = wc.spot_col, range = 16.0, shadow = true })
        S.spotlights_added = S.spotlights_added + 1

        -- Marble stealth cover pillars (block guard sightline raycasts)
        for side = -1, 1, 2 do
            local col = eng.scene.spawn(wc.key .. "_cover_" .. tostring(side))
            eng.scene.set_pocket(col, pid)
            eng.scene.set_pos(col, side * 2.3, 0.0, 1.6)
            eng.scene.set_scale(col, 1.1, 1.4, 1.1)
            eng.scene.set_mesh(col, S.pillar_mesh, { tex = marble_tex, color = {0.76, 0.75, 0.82, 1.0}, cast_shadow = true })
            eng.physics.add_body(col, { shape = "aabb", motion = "static", pocket = pid, half_extents = {0.55, 1.8, 0.55} })
        end

        -- Markov-named Gala Guests conversing near side alcoves
        local guest_count = (i == 1) and 2 or 1
        for g = 1, guest_count do
            local gx = (g == 1) and 4.4 or -4.4
            local gz = (g == 1) and 2.8 or -2.2
            local ge = eng.scene.spawn(wc.key .. "_guest_" .. tostring(g))
            eng.scene.set_pocket(ge, pid)
            eng.scene.set_pos(ge, gx, 0.0, gz)
            eng.scene.set_rot_deg(ge, 0.0, (g == 1) and -90.0 or 90.0, 0.0)
            local pinfo = eng.procgen.person(ge, S.seed + i * 71 + g * 19)
            S.guests[#S.guests + 1] = { ent = ge, pocket_id = pid, name = pinfo.name, role = pinfo.role, x = gx, z = gz }
        end

        -- Patrolling Clockwork Guard with Markov name & forward spotlight cone
        local grd_e = eng.scene.spawn(wc.key .. "_guard")
        eng.scene.set_pocket(grd_e, pid)
        local start_gx = (i % 2 == 1) and 2.8 or -2.8
        local dir_x = (i % 2 == 1) and 1.0 or -1.0
        eng.scene.set_pos(grd_e, start_gx, 0.0, -0.8)
        local ginfo = eng.procgen.person(grd_e, S.seed + i * 137 + 5)
        S.guards[#S.guards + 1] = {
            ent = grd_e, pocket_id = pid, name = ginfo.name,
            x = start_gx, z = -0.8, dir_x = dir_x, speed = 2.6
        }

        -- Heirloom Vault Pedestal + Priceless Clockwork Heirloom
        local ped = eng.scene.spawn(wc.key .. "_pedestal")
        eng.scene.set_pocket(ped, pid)
        eng.scene.set_pos(ped, 0.0, 0.45, -3.8)
        eng.scene.set_scale(ped, 1.0, 0.9, 1.0)
        eng.scene.set_mesh(ped, S.chest_mesh, { color = {0.72, 0.56, 0.24, 1.0}, cast_shadow = true })

        local hl = eng.scene.spawn(wc.key .. "_heirloom")
        eng.scene.set_pocket(hl, pid)
        eng.scene.set_pos(hl, 0.0, 1.05, -3.8)
        eng.scene.set_scale(hl, 0.85, 0.85, 0.85)
        eng.scene.set_mesh(hl, S.crystal_mesh, { color = {1.0, 0.86, 0.25, 1.0}, metallic = 0.85, roughness = 0.15 })
        S.heirlooms[i] = { ent = hl, pocket_id = pid, x = 0.0, z = -3.8, stolen = false }
    end

    S.wings_built = #S.wings
    S.pocket = 0
    S.px, S.py, S.pz = 0.0, 0.9, 2.2
    S.yaw, S.pitch = 0.0, 0.0
    S.cloaked = false
    S.suspicion = 0.0
    S.alerts = 0
    S.portal_hops = 0
    S.heirlooms_stolen = 0
    S.last_guest = S.guests[1] and S.guests[1].name or "Guest"
    S.score = 0
    S.won = false

    eng.input.set_mouse_lock(true)
    eng.camera.set(S.px, S.py + 0.55, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    S.cloaked = eng.input.down("interact") or eng.input.down("jump")
    local speed = S.cloaked and 12.5 or 14.5
    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw or 0.0, S.pitch or 0.0, speed, dt)
    if math.abs(dx) > 1e-4 or math.abs(dz) > 1e-4 then
        local nx, nz = eng.physics.slide_move(S.pocket, S.px, S.py, S.pz, dx, dz, 0.32)
        local dst_pk, wx, wy, wz = eng.portal.check_crossing(S.pocket, S.px, S.py, S.pz, nx, S.py, nz)
        if dst_pk ~= nil then
            S.pocket = dst_pk
            S.px, S.py, S.pz = wx, wy, wz
            S.portal_hops = S.portal_hops + 1
            eng.audio.play(S.sfx_warp, S.px, S.py, S.pz, S.pocket)
        else
            local lim_x = (S.pocket == 0) and 11.0 or 7.2
            local lim_z = (S.pocket == 0) and 10.0 or 6.9
            S.px = eng.math.clamp(nx, -lim_x, lim_x)
            S.pz = eng.math.clamp(nz, -lim_z, lim_z)
        end
    end

    -- Overhear Markov-named gala guests when nearby
    for i = 1, #S.guests do
        local g = S.guests[i]
        if g.pocket_id == S.pocket and eng.math.dist3(S.px, 0.0, S.pz, g.x, 0.0, g.z) < 3.5 then
            S.last_guest = g.name
        end
    end

    -- Step patrolling guards & check stealth detection cones via raycast
    local spotted = false
    for i = 1, #S.guards do
        local gr = S.guards[i]
        gr.x = gr.x + gr.dir_x * gr.speed * dt
        if gr.x > 4.6 then gr.x = 4.6; gr.dir_x = -1.0
        elseif gr.x < -4.6 then gr.x = -4.6; gr.dir_x = 1.0 end
        eng.scene.set_pos(gr.ent, gr.x, 0.0, gr.z)
        eng.scene.set_rot_deg(gr.ent, 0.0, (gr.dir_x > 0) and -90.0 or 90.0, 0.0)

        if gr.pocket_id == S.pocket then
            local dx, dz = S.px - gr.x, S.pz - gr.z
            local dist = math.sqrt(dx * dx + dz * dz)
            local detect_r = S.cloaked and 1.65 or 6.2
            if dist > 0.05 and dist < detect_r then
                local fwd_dot = (dx / dist) * gr.dir_x
                if fwd_dot > 0.35 or dist < 1.1 then
                    local blk = eng.physics.raycast(S.pocket, gr.x, 1.1, gr.z, dx / dist, 0.0, dz / dist, dist)
                    if not blk then spotted = true end
                end
            end
        end
    end

    if spotted then
        S.suspicion = S.suspicion + 95.0 * dt
        if S.suspicion >= 100.0 then
            S.alerts = S.alerts + 1
            S.suspicion = 35.0
            S.px, S.pz = 0.0, 5.4
            eng.audio.play(S.sfx_alert, S.px, S.py, S.pz, S.pocket)
        end
    else
        S.suspicion = math.max(0.0, S.suspicion - 40.0 * dt)
    end

    -- Steal heirloom in active wing
    for i = 1, #S.heirlooms do
        local hl = S.heirlooms[i]
        if not hl.stolen and hl.pocket_id == S.pocket then
            if eng.math.dist3(S.px, 0.0, S.pz, hl.x, 0.0, hl.z) < 1.85 then
                hl.stolen = true
                S.heirlooms_stolen = S.heirlooms_stolen + 1
                S.score = S.score + 350
                eng.audio.play(S.sfx_heist, hl.x, 1.0, hl.z, S.pocket)
                eng.scene.despawn(hl.ent)
                eng.save.write("clockwork_manor", "heirlooms_" .. tostring(S.heirlooms_stolen))
            end
        end
    end

    -- Courtyard getaway escape with all 3 heirlooms
    if S.pocket == 0 and S.heirlooms_stolen == 3 then
        if eng.math.dist3(S.px, 0.0, S.pz, S.exit_x, 0.0, S.exit_z) < 2.2 then
            S.won = true
            S.score = S.score + math.max(0, 500 - S.alerts * 150)
            eng.audio.play(S.sfx_heist, S.exit_x, 1.5, S.exit_z, 0)
            eng.save.write("clockwork_manor", "clear")
        end
    end

    eng.camera.set(S.px, S.py + 0.55, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
end

function draw()
    if S.pocket == 0 and S.heirlooms_stolen == 3 then
        eng.render.draw_sprite(S.exit_x, 1.8, S.exit_z, 0.9, 0.9, S.orb_tex)
    end
    local loc = S.pocket_labels[S.pocket] or "WING"
    local clk = S.cloaked and (" | " .. eng.i18n.t("cloak")) or ""
    local x, y = eng.ui.anchor("top_left", 16, 14, 620, 56, 1280, 720)
    local line = S.won and eng.i18n.t("victory") or
        (eng.i18n.t("title") .. " | " .. loc .. " | HEIRLOOMS " .. S.heirlooms_stolen .. "/3 | GUEST: " .. S.last_guest .. clk)
    eng.ui.label(x, y, line, 1.0, {0.92, 0.85, 0.55, 1.0})
    eng.ui.bar(x, y + 26, 220, S.suspicion / 100.0, "ALERT ")
end
