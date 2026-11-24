-- 038_submarine_trench: Deep-sea submarine with walkable Bigger-on-the-Inside control room, vents & aquatic leviathans
local S = game.state

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.018 })
    eng.render.set_sky(0.01, 0.05, 0.13, 0.03, 0.16, 0.28)

    eng.render.add_light({ type = "dir", pocket = "world", dir = {-0.25, -1.0, -0.35}, color = {1.2, 1.65, 2.1}, shadow = true })
    eng.render.add_light({ type = "point", pocket = "world", pos = {0.0, 5.0, -11.0}, color = {2.4, 1.35, 0.65}, range = 36.0 })
    eng.render.add_light({ type = "dir", pocket = "sub_control_room", dir = {-0.2, -1.0, -0.3}, color = {1.3, 1.55, 1.85} })
    eng.render.add_light({ type = "point", pocket = "sub_control_room", pos = {0.0, 4.2, 0.0}, color = {1.4, 2.4, 2.8}, range = 32.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    local caustic_tex = eng.procgen.texture("water_caustics", S.seed, 64)
    local vent_tex = eng.procgen.texture("lava_cracks", S.seed + 13, 64)
    local hull_tex = eng.procgen.texture("metal_rivets", S.seed + 29, 64)

    S.box_mesh = eng.asset.box(1, 1, 1)
    local hull_mesh = eng.asset.cylinder(0.85, 0.78, 3.2, 12)
    local dome_mesh = eng.asset.sphere(0.76, 10, 12)
    local cone_mesh = eng.asset.cylinder(1.25, 0.55, 2.6, 10)
    local crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    local pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_ping = eng.audio.synth("sine", 740, 0.18, 420)
    S.sfx_hatch = eng.audio.synth("triangle", 320, 0.15, 580)
    S.sfx_uplink = eng.audio.synth("sine", 540, 0.25, 1080)

    -- Abyssal seabed & flanking trench cliff walls in outer pocket (0)
    local seabed = eng.scene.spawn("trench_seabed")
    eng.scene.set_pos(seabed, 0.0, -0.25, -8.0)
    eng.scene.set_scale(seabed, 42.0, 0.5, 48.0)
    eng.scene.set_mesh(seabed, S.box_mesh, { tex = caustic_tex, color = {0.16, 0.30, 0.42, 1.0}, roughness = 0.85 })
    eng.physics.add_body(seabed, { shape = "aabb", motion = "static", half_extents = {21.0, 0.25, 24.0} })

    for side = -1, 1, 2 do
        local cliff = eng.scene.spawn("trench_wall_" .. tostring(side))
        eng.scene.set_pos(cliff, side * 16.5, 4.5, -8.0)
        eng.scene.set_scale(cliff, 4.0, 9.5, 46.0)
        eng.scene.set_mesh(cliff, S.box_mesh, { tex = caustic_tex, color = {0.12, 0.22, 0.34, 1.0} })
    end

    -- 2 Abyssal Hydrothermal Vents
    local vent_xz = { {-8.2, -6.5}, {8.2, -9.5} }
    S.vents = {}
    for i = 1, #vent_xz do
        local vx, vz = vent_xz[i][1], vent_xz[i][2]
        local ve = eng.scene.spawn("hydrothermal_vent_" .. tostring(i))
        eng.scene.set_pos(ve, vx, 1.3, vz)
        eng.scene.set_mesh(ve, cone_mesh, { tex = vent_tex, color = {0.55, 0.32, 0.24, 1.0}, cast_shadow = true })

        local spire = eng.scene.spawn("vent_spire_" .. tostring(i))
        eng.scene.set_pos(spire, vx, 2.4, vz)
        eng.scene.set_mesh(spire, crystal_mesh, { color = {1.0, 0.52, 0.18, 1.0} })
        S.vents[i] = { ent = ve, x = vx, y = 2.0, z = vz, scanned = false }
    end

    -- 2 Procedural "aquatic" Abyssal Leviathans (eng.procgen.animal)
    local lev_bases = { {-5.2, 3.0, -15.5}, {5.2, 3.4, -17.5} }
    S.leviathans = {}
    for i = 1, #lev_bases do
        local bx, by, bz = lev_bases[i][1], lev_bases[i][2], lev_bases[i][3]
        local le = eng.scene.spawn("abyssal_leviathan_" .. tostring(i))
        eng.scene.set_pos(le, bx, by, bz)
        eng.scene.set_scale(le, 1.85, 1.85, 1.85)
        local info = eng.procgen.animal(le, S.seed + i * 47, "aquatic")
        S.leviathans[i] = {
            ent = le, bx = bx, by = by, bz = bz,
            x = bx, y = by, z = bz,
            phase = i * 1.4, height = info.height, scanned = false
        }
    end

    -- Compact Deep-Sea Submarine (axis-aligned root for clean hatch portal + tilted visual hull child)
    S.sx, S.sy, S.sz = 0.0, 3.0, 6.0
    S.sub_ent = eng.scene.spawn("deep_submersible")
    eng.scene.set_pos(S.sub_ent, S.sx, S.sy, S.sz)

    S.sub_vis = eng.scene.spawn("sub_vis_root")
    eng.scene.set_parent(S.sub_vis, S.sub_ent)

    local hull = eng.scene.spawn("sub_pressure_hull")
    eng.scene.set_parent(hull, S.sub_vis)
    eng.scene.set_rot_deg(hull, 90.0, 0.0, 0.0)
    eng.scene.set_mesh(hull, hull_mesh, { tex = hull_tex, color = {0.95, 0.76, 0.18, 1.0}, cast_shadow = true })

    local sail = eng.scene.spawn("sub_conning_tower")
    eng.scene.set_parent(sail, S.sub_vis)
    eng.scene.set_pos(sail, 0.0, 0.95, -0.2)
    eng.scene.set_scale(sail, 0.72, 0.85, 1.15)
    eng.scene.set_mesh(sail, S.box_mesh, { tex = hull_tex, color = {0.92, 0.68, 0.15, 1.0} })

    local bow = eng.scene.spawn("sub_bow_dome")
    eng.scene.set_parent(bow, S.sub_vis)
    eng.scene.set_pos(bow, 0.0, 0.0, -1.65)
    eng.scene.set_mesh(bow, dome_mesh, { color = {0.35, 0.88, 1.0, 1.0}, roughness = 0.15 })

    S.prop_ent = eng.scene.spawn("sub_propeller")
    eng.scene.set_parent(S.prop_ent, S.sub_vis)
    eng.scene.set_pos(S.prop_ent, 0.0, 0.0, 1.72)
    eng.scene.set_scale(S.prop_ent, 0.95, 0.18, 0.14)
    eng.scene.set_mesh(S.prop_ent, S.box_mesh, { color = {0.72, 0.75, 0.80, 1.0} })

    -- Attach Walkable 16m x 5.5m x 22m Control Room to compact submersible!
    -- Exterior hatch d_ext at local (0.0, 0.6, 2.4); interior hatch d_int at (0.0, 1.1, 10.8)
    S.bridge = eng.space.attach_vehicle_interior(eng, S.sub_ent, {
        pocket = "sub_control_room",
        interior_size = {16.0, 5.5, 22.0},
        door_size = {1.4, 2.2},
        door_local_pos = {0.0, 0.6, 2.4},
        mesh_id = S.box_mesh
    })
    S.bridge_pocket = S.bridge.pocket_id

    -- Furnish oversized submarine Control Room (bulkheads, periscope, Sonar Holo-Table, Telemetry Uplink Console)
    for side = -1, 1, 2 do
        local bw = eng.scene.spawn("bridge_bulkhead_" .. tostring(side))
        eng.scene.set_pocket(bw, S.bridge_pocket)
        eng.scene.set_pos(bw, side * 7.7, 2.5, 0.0)
        eng.scene.set_scale(bw, 0.5, 5.0, 21.4)
        eng.scene.set_mesh(bw, S.box_mesh, { tex = hull_tex, color = {0.26, 0.34, 0.44, 1.0} })
        eng.physics.add_body(bw, { shape = "aabb", motion = "static", pocket = S.bridge_pocket, half_extents = {0.25, 2.5, 10.7} })

        local rib = eng.scene.spawn("bridge_rib_" .. tostring(side))
        eng.scene.set_pocket(rib, S.bridge_pocket)
        eng.scene.set_pos(rib, side * 5.2, 0.0, -2.0)
        eng.scene.set_scale(rib, 1.0, 1.8, 1.0)
        eng.scene.set_mesh(rib, pillar_mesh, { color = {0.48, 0.58, 0.68, 1.0} })
    end

    local holo = eng.scene.spawn("sonar_holo_table")
    eng.scene.set_pocket(holo, S.bridge_pocket)
    eng.scene.set_pos(holo, -2.8, 0.55, 2.5)
    eng.scene.set_scale(holo, 2.2, 1.1, 2.2)
    eng.scene.set_mesh(holo, S.box_mesh, { color = {0.18, 0.55, 0.72, 1.0} })
    eng.physics.add_body(holo, { shape = "aabb", motion = "static", pocket = S.bridge_pocket, half_extents = {1.1, 0.55, 1.1} })

    S.console_x, S.console_z = 0.0, -3.5
    S.uplink_ent = eng.scene.spawn("telemetry_uplink_console")
    eng.scene.set_pocket(S.uplink_ent, S.bridge_pocket)
    eng.scene.set_pos(S.uplink_ent, S.console_x, 0.25, S.console_z)
    eng.scene.set_scale(S.uplink_ent, 1.6, 1.6, 1.6)
    eng.scene.set_mesh(S.uplink_ent, crystal_mesh, { color = {0.25, 0.98, 0.85, 1.0} })

    -- Walkable Captain avatar inside the Control Room
    S.crew_ent = eng.scene.spawn("sub_captain")
    eng.scene.set_pocket(S.crew_ent, S.bridge_pocket)
    eng.scene.set_pos(S.crew_ent, 0.0, 0.0, 9.6)
    eng.procgen.person(S.crew_ent, S.seed + 71)

    S.in_bridge = false
    S.cx, S.cz = 0.0, 9.6
    S.prop_ang = 0.0
    S.ping_cd = 0.0
    S.hatch_cd = 0.0
    S.vents_scanned = 0
    S.leviathans_scanned = 0
    S.raw_scans = 0
    S.analyzed_scans = 0
    S.portal_trips = 0
    S.score = 0
    S.won = false

    sync_sub_cam()
    eng.mod.emit("post_init")
end

local function toggle_hatch_portal()
    if not S.in_bridge then
        local dst_pk, wx, _, wz = eng.portal.check_crossing(0,
            S.sx, S.sy + 0.6, S.sz + 2.9,
            S.sx, S.sy + 0.6, S.sz + 1.9)
        if dst_pk then
            S.in_bridge = true
            S.cx, S.cz = wx, math.min(10.2, wz)
            S.portal_trips = S.portal_trips + 1
            eng.scene.set_pos(S.crew_ent, S.cx, 0.0, S.cz)
            eng.audio.play(S.sfx_hatch, S.cx, 1.2, S.cz, dst_pk)
        end
    else
        local dst_pk = eng.portal.check_crossing(S.bridge_pocket, 0.0, 1.1, 10.3, 0.0, 1.1, 11.3)
        if dst_pk then
            S.in_bridge = false
            S.portal_trips = S.portal_trips + 1
            eng.audio.play(S.sfx_hatch, S.sx, S.sy, S.sz, 0)
        end
    end
end

function sync_sub_cam()
    eng.scene.set_pos(S.sub_ent, S.sx, S.sy, S.sz)
    if S.in_bridge then
        eng.camera.set(S.cx, 1.75, S.cz, S.br_pitch or 0.0, S.br_yaw or 0.0, 0.0, S.bridge_pocket)
    else
        eng.camera.look_at(S.sx, S.sy + 4.8, S.sz + 9.5, S.sx, S.sy - 0.6, S.sz - 7.5, 0)
    end
end

function update(dt)
    if S.won then return end
    S.ping_cd = math.max(0.0, S.ping_cd - dt)
    S.hatch_cd = math.max(0.0, S.hatch_cd - dt)
    S.prop_ang = (S.prop_ang + 520.0 * dt) % 360.0
    eng.scene.set_rot_deg(S.prop_ent, 0.0, 0.0, S.prop_ang)
    eng.scene.set_rot_deg(S.uplink_ent, 0.0, S.prop_ang * 0.25, 0.0)

    -- Animate swimming "aquatic" leviathans
    for i = 1, #S.leviathans do
        local lv = S.leviathans[i]
        lv.phase = lv.phase + 1.35 * dt
        lv.x = lv.bx + math.cos(lv.phase) * 1.4
        lv.y = lv.by + math.sin(lv.phase * 1.5) * 0.35
        lv.z = lv.bz + math.sin(lv.phase) * 1.1
        eng.scene.set_pos(lv.ent, lv.x, lv.y, lv.z)
        eng.scene.set_rot_deg(lv.ent, 0.0, math.deg(lv.phase) + 90.0, 0.0)
    end

    local ix, iy = eng.input.axis2d("left", "right", "down", "up")

    if eng.input.pressed("interact") and S.hatch_cd <= 0.0 then
        S.hatch_cd = 0.35
        toggle_hatch_portal()
    end

    if not S.in_bridge then
        -- Exterior Submarine Helm Controls
        local target_y = eng.input.down("jump") and 4.4 or 3.0
        S.sy = S.sy + (target_y - S.sy) * math.min(1.0, 5.0 * dt)
        S.sx = eng.math.clamp(S.sx + ix * 16.5 * dt, -12.5, 12.5)
        S.sz = eng.math.clamp(S.sz - iy * 16.5 * dt, -22.0, 12.0)
        eng.scene.set_rot_deg(S.sub_vis, iy * 6.0, -ix * 10.0, -ix * 8.0)

        -- Active Sonar Ping scans nearby Hydrothermal Vents & Aquatic Leviathans
        if (eng.input.pressed("fire") or eng.input.down("fire")) and S.ping_cd <= 0.0 then
            S.ping_cd = 0.16
            eng.audio.play(S.sfx_ping, S.sx, S.sy, S.sz, 0)
            for i = 1, #S.vents do
                local v = S.vents[i]
                if not v.scanned and eng.math.dist3(S.sx, 0, S.sz, v.x, 0, v.z) < 5.2 then
                    v.scanned = true
                    S.vents_scanned = S.vents_scanned + 1
                    S.raw_scans = S.raw_scans + 1
                    S.score = S.score + 200
                end
            end
            for i = 1, #S.leviathans do
                local lv = S.leviathans[i]
                if not lv.scanned and eng.math.dist3(S.sx, 0, S.sz, lv.x, 0, lv.z) < 5.6 then
                    lv.scanned = true
                    S.leviathans_scanned = S.leviathans_scanned + 1
                    S.raw_scans = S.raw_scans + 1
                    S.score = S.score + 300
                end
            end
        end
    else
        -- Walkable Bigger-on-the-Inside Submarine Control Room (16m x 22m)!
        local prev_z = S.cz
        local dx, dz
        S.br_yaw, S.br_pitch, dx, dz = eng.camera.fps_steer(S.br_yaw or 0.0, S.br_pitch or 0.0, 11.5, dt)
        local nx, nz = eng.physics.slide_move(S.bridge_pocket, S.cx, 0.8, S.cz, dx, dz, 0.42)
        S.cx = eng.math.clamp(nx, -6.5, 6.5)
        S.cz = eng.math.clamp(nz, -9.5, 11.4)
        eng.scene.set_pos(S.crew_ent, S.cx, 0.0, S.cz)
        if math.abs(ix) > 0.01 or math.abs(iy) > 0.01 then
            eng.scene.set_rot_deg(S.crew_ent, 0.0, math.deg(math.atan2(-ix, iy)), 0.0)
        end

        -- Walk naturally back out the aft hatch portal at z = 10.8
        if prev_z < 10.8 and S.cz >= 10.8 and math.abs(S.cx) < 0.65 then
            local dst_pk = eng.portal.check_crossing(S.bridge_pocket, S.cx, 1.1, prev_z, S.cx, 1.1, S.cz)
            if dst_pk then
                S.in_bridge = false
                S.portal_trips = S.portal_trips + 1
                eng.audio.play(S.sfx_hatch, S.sx, S.sy, S.sz, 0)
            end
        end

        -- Decode & transmit abyssal sonar logs at the Telemetry Uplink Console
        if S.raw_scans > 0 and eng.math.dist3(S.cx, 0, S.cz, S.console_x, 0, S.console_z) < 2.6 then
            if eng.input.pressed("fire") or eng.input.down("fire") then
                S.analyzed_scans = S.analyzed_scans + S.raw_scans
                S.score = S.score + S.raw_scans * 250
                S.raw_scans = 0
                eng.audio.play(S.sfx_uplink, S.console_x, 1.2, S.console_z, S.bridge_pocket)
            end
        end
    end

    if S.vents_scanned >= 2 and S.leviathans_scanned >= 2 and S.analyzed_scans >= 4 and not S.in_bridge and S.portal_trips >= 2 then
        S.won = true
        eng.save.write("submarine_trench_clear", tostring(S.score))
    end

    sync_sub_cam()
end

function draw()
    if not S.in_bridge then
        for i = 1, #S.vents do
            local v = S.vents[i]
            eng.render.draw_sprite(v.x, 3.4, v.z, v.scanned and 0.45 or 0.85, v.scanned and 0.45 or 0.85, S.orb_tex)
        end
        for i = 1, #S.leviathans do
            local lv = S.leviathans[i]
            if not lv.scanned then
                eng.render.draw_sprite(lv.x, lv.y + 1.8, lv.z, 0.75, 0.75, S.orb_tex)
            end
        end
    else
        eng.render.draw_sprite(S.console_x, 2.3, S.console_z, 0.65, 0.65, S.orb_tex)
    end

    local mode = S.in_bridge and "[CONTROL ROOM 16x22m]" or "[ABYSS HELM]"
    local x, y = eng.ui.anchor("top_left", 16, 14, 600, 54, 1280, 720)
    local label = S.won and eng.i18n.t("victory") or string.format(
        "%s %s | VENTS %d/2 | LEVIATHANS %d/2 | UPLINK %d/4",
        eng.i18n.t("title"), mode, S.vents_scanned, S.leviathans_scanned, S.analyzed_scans)
    eng.ui.label(x, y, label, 1.0, {0.42, 0.96, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.analyzed_scans / 4.0, "SONAR ")
end
