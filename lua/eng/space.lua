-- One-call "Bigger on the Inside" Pocket Space & Doorway builders (eng.space)
local M = {}

function M.cut_wall_with_door(eng_root, pocket_name, wall_pos, wall_size, door_size, mesh_id, color)
    local parts = eng_root.portal.cut_doorway(wall_size[1], wall_size[2], wall_size[3], door_size[1], door_size[2])
    local pid = eng_root.scene.register_pocket(pocket_name or "world")
    local spawned = {}
    for i = 1, #parts do
        local b = parts[i]
        local cx = wall_pos[1] + (b.min[1] + b.max[1]) * 0.5
        local cy = wall_pos[2] + (b.min[2] + b.max[2]) * 0.5
        local cz = wall_pos[3] + (b.min[3] + b.max[3]) * 0.5
        local sx = b.max[1] - b.min[1]
        local sy = b.max[2] - b.min[2]
        local sz = b.max[3] - b.min[3]
        local e = eng_root.scene.spawn("door_wall_" .. tostring(i))
        eng_root.scene.set_pocket(e, pid)
        eng_root.scene.set_pos(e, cx, cy, cz)
        eng_root.scene.set_scale(e, sx, sy, sz)
        eng_root.scene.set_mesh(e, mesh_id, { color = color or {0.65, 0.62, 0.58, 1.0}, cast_shadow = true })
        eng_root.physics.add_body(e, { shape = "aabb", motion = "static", pocket = pid, half_extents = {sx * 0.5, sy * 0.5, sz * 0.5} })
        spawned[#spawned + 1] = e
    end
    return spawned
end

function M.create_pocket_building(eng_root, cfg)
    local ext_p = cfg.exterior_pos or {0, 0, -6}
    local ext_s = cfg.exterior_size or {3.0, 3.0, 3.0}
    local int_s = cfg.interior_size or {20.0, 8.0, 24.0}
    local door_s = cfg.door_size or {1.2, 2.2}
    local p_out = eng_root.scene.register_pocket(cfg.outer_pocket or "world")
    local p_in = eng_root.scene.register_pocket(cfg.pocket or "inside")
    local box_mesh = cfg.mesh_id or eng_root.asset.box(1, 1, 1)

    -- Exterior front wall split cleanly around doorway
    local front_z = ext_p[3] + ext_s[3] * 0.5
    M.cut_wall_with_door(eng_root, cfg.outer_pocket or "world",
                         {ext_p[1], ext_p[2], front_z}, {ext_s[1], ext_s[2], 0.2}, door_s, box_mesh, cfg.exterior_color)

    -- Exterior back/roof shell
    local shell = eng_root.scene.spawn((cfg.pocket or "hut") .. "_shell")
    eng_root.scene.set_pocket(shell, p_out)
    eng_root.scene.set_pos(shell, ext_p[1], ext_p[2] + ext_s[2] * 0.5, ext_p[3] - 0.15)
    eng_root.scene.set_scale(shell, ext_s[1], ext_s[2], ext_s[3] - 0.3)
    eng_root.scene.set_mesh(shell, box_mesh, { color = cfg.exterior_color or {0.6, 0.35, 0.22, 1.0}, cast_shadow = true })

    -- Oversized interior floor centered around (0, 0, 0) in isolated pocket
    local floor_e = eng_root.scene.spawn((cfg.pocket or "hut") .. "_floor")
    eng_root.scene.set_pocket(floor_e, p_in)
    eng_root.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng_root.scene.set_scale(floor_e, int_s[1], 0.5, int_s[3])
    eng_root.scene.set_mesh(floor_e, box_mesh, { color = cfg.interior_color or {0.35, 0.42, 0.52, 1.0} })
    eng_root.physics.add_body(floor_e, { shape = "aabb", motion = "static", pocket = p_in, half_extents = {int_s[1] * 0.5, 0.25, int_s[3] * 0.5} })

    -- Link exterior & interior portal entities
    local d_ext = eng_root.scene.spawn((cfg.pocket or "hut") .. "_door_ext")
    eng_root.scene.set_pocket(d_ext, p_out)
    eng_root.scene.set_pos(d_ext, ext_p[1], ext_p[2] + door_s[2] * 0.5, front_z)

    local d_int = eng_root.scene.spawn((cfg.pocket or "hut") .. "_door_int")
    eng_root.scene.set_pocket(d_int, p_in)
    eng_root.scene.set_pos(d_int, 0.0, door_s[2] * 0.5, int_s[3] * 0.5 - 0.2)
    eng_root.scene.set_rot_deg(d_int, 0.0, 180.0, 0.0)

    local portal_idx = eng_root.portal.link(d_ext, d_int, door_s[1], door_s[2], cfg.scale_ratio or 1.0, true, true)
    return { pocket_id = p_in, door_ext = d_ext, door_int = d_int, portal = portal_idx }
end

function M.attach_vehicle_interior(eng_root, vehicle_ent, cfg)
    local p_out = eng_root.scene.get_pocket(vehicle_ent)
    local p_in = eng_root.scene.register_pocket(cfg.pocket or "vehicle_cabin")
    local door_s = cfg.door_size or {1.1, 2.0}
    local int_s = cfg.interior_size or {12.0, 5.0, 18.0}
    local dlp = cfg.door_local_pos or {0.0, 1.0, 1.5}
    local box_mesh = cfg.mesh_id or eng_root.asset.box(1, 1, 1)

    local d_ext = eng_root.scene.spawn((cfg.pocket or "veh") .. "_hatch_ext")
    eng_root.scene.set_pocket(d_ext, p_out)
    eng_root.scene.set_parent(d_ext, vehicle_ent)
    eng_root.scene.set_pos(d_ext, dlp[1], dlp[2], dlp[3])

    local deck = eng_root.scene.spawn((cfg.pocket or "veh") .. "_deck")
    eng_root.scene.set_pocket(deck, p_in)
    eng_root.scene.set_pos(deck, 0.0, -0.25, 0.0)
    eng_root.scene.set_scale(deck, int_s[1], 0.5, int_s[3])
    eng_root.scene.set_mesh(deck, box_mesh, { color = {0.28, 0.32, 0.38, 1.0} })
    eng_root.physics.add_body(deck, { shape = "aabb", motion = "static", pocket = p_in, half_extents = {int_s[1] * 0.5, 0.25, int_s[3] * 0.5} })

    local d_int = eng_root.scene.spawn((cfg.pocket or "veh") .. "_hatch_int")
    eng_root.scene.set_pocket(d_int, p_in)
    eng_root.scene.set_pos(d_int, 0.0, door_s[2] * 0.5, int_s[3] * 0.5 - 0.2)
    eng_root.scene.set_rot_deg(d_int, 0.0, 180.0, 0.0)

    local pidx = eng_root.portal.link(d_ext, d_int, door_s[1], door_s[2], 1.0, true, true)
    return { pocket_id = p_in, door_ext = d_ext, door_int = d_int, portal = pidx }
end

function M.set_helm_input(veh, throttle, turn_rate)
    veh.throttle = math.max(-1.0, math.min(1.0, throttle or 0.0))
    veh.turn_input = math.max(-1.0, math.min(1.0, turn_rate or 0.0))
end

function M.find_station(veh, x, z, radius)
    local r = radius or 1.8
    local r2 = r * r
    for i = 1, #veh.stations do
        local st = veh.stations[i]
        local dx, dz = x - st.x, z - st.z
        if dx * dx + dz * dz <= r2 then
            return st.name, st
        end
    end
    return nil, nil
end

function M.step_vehicle(eng_root, veh, dt)
    local target_v = veh.throttle * veh.max_speed
    local dv = target_v - veh.speed
    local max_dv = veh.accel * dt
    if math.abs(dv) > max_dv then
        dv = (dv > 0.0) and max_dv or -max_dv
    end
    local prev_speed = veh.speed
    veh.speed = veh.speed + dv
    local lin_acc = (veh.speed - prev_speed) / math.max(dt, 0.001)

    local yaw_rate_deg = -veh.turn_input * veh.max_turn_deg
    veh.yaw_deg = veh.yaw_deg + yaw_rate_deg * dt
    local yr = veh.yaw_deg * (math.pi / 180.0)
    local fx, fz = -math.sin(yr), -math.cos(yr)
    veh.pos_x = veh.pos_x + fx * veh.speed * dt
    veh.pos_z = veh.pos_z + fz * veh.speed * dt

    local move_frac = math.min(1.0, (math.abs(veh.speed) + math.abs(veh.turn_input) * 1.5) / math.max(veh.max_speed, 0.1))
    veh.step_phase = veh.step_phase + dt * veh.step_bob_hz * (2.0 * math.pi) * move_frac
    local bob_y = math.abs(math.sin(veh.step_phase)) * veh.step_bob_amp * move_frac
    eng_root.scene.set_pos(veh.entity, veh.pos_x, veh.base_y + bob_y, veh.pos_z)
    eng_root.scene.set_rot_deg(veh.entity, 0.0, veh.yaw_deg, 0.0)
    eng_root.portal.sync_kinematics(dt)

    local sway = veh.inertial_sway
    local lat_acc = veh.speed * (yaw_rate_deg * math.pi / 180.0)
    local gait_x = math.sin(veh.step_phase) * veh.step_bob_amp * 4.0 * move_frac
    local gx = math.max(-2.5, math.min(2.5, (lat_acc + gait_x) * sway))
    local gz = math.max(-2.5, math.min(2.5, lin_acc * sway))
    local gy = -9.81 + math.cos(veh.step_phase * 2.0) * veh.step_bob_amp * 3.0 * move_frac * sway
    eng_root.physics.set_gravity(veh.pocket_id, gx, gy, gz)
    return fx, fz
end

function M.step_vehicle_method(veh, dt)
    return M.step_vehicle(veh.eng, veh, dt)
end

function M.spawn_box_wall(eng_root, pid, name, pos, sz, mesh_id, col)
    local e = eng_root.scene.spawn(name)
    eng_root.scene.set_pocket(e, pid)
    eng_root.scene.set_pos(e, pos[1], pos[2], pos[3])
    eng_root.scene.set_scale(e, sz[1], sz[2], sz[3])
    eng_root.scene.set_mesh(e, mesh_id, { color = col, roughness = 0.65 })
    eng_root.physics.add_body(e, { shape = "aabb", motion = "static", pocket = pid, half_extents = {sz[1] * 0.5, sz[2] * 0.5, sz[3] * 0.5} })
    return e
end

function M.create_steerable_vehicle(eng_root, vehicle_ent, cfg)
    local pname = cfg.pocket or "vehicle_bridge"
    local p_out = eng_root.scene.get_pocket(vehicle_ent)
    local p_in = eng_root.scene.register_pocket(pname)
    local int_s = cfg.interior_size or {14.0, 5.5, 18.0}
    local door_s = cfg.door_size or {1.8, 2.4}
    local hlp = cfg.hatch_local_pos or {0.0, 1.2, 3.0}
    local wlp = cfg.windshield_local_pos or {0.0, 8.0, -2.5}
    local win_s = cfg.windshield_size or {6.0, 2.6}
    local box_mesh = cfg.mesh_id or eng_root.asset.box(1, 1, 1)
    local wall_col = cfg.wall_color or {0.22, 0.26, 0.32, 1.0}
    local deck_col = cfg.deck_color or {0.28, 0.33, 0.39, 1.0}

    M.spawn_box_wall(eng_root, p_in, pname .. "_deck", {0.0, -0.25, 0.0}, {int_s[1], 0.5, int_s[3] + 1.0}, box_mesh, deck_col)
    M.spawn_box_wall(eng_root, p_in, pname .. "_ceil", {0.0, int_s[2] + 0.2, -int_s[3] * 0.45}, {int_s[1], 0.4, 1.6}, box_mesh, wall_col)
    M.spawn_box_wall(eng_root, p_in, pname .. "_front", {0.0, int_s[2] * 0.5, -int_s[3] * 0.5}, {int_s[1], int_s[2], 0.4}, box_mesh, wall_col)
    M.spawn_box_wall(eng_root, p_in, pname .. "_port", {-int_s[1] * 0.5, int_s[2] * 0.5, 0.0}, {0.4, int_s[2], int_s[3]}, box_mesh, wall_col)
    M.spawn_box_wall(eng_root, p_in, pname .. "_stbd", {int_s[1] * 0.5, int_s[2] * 0.5, 0.0}, {0.4, int_s[2], int_s[3]}, box_mesh, wall_col)
    M.cut_wall_with_door(eng_root, pname, {0.0, 0.0, int_s[3] * 0.5}, {int_s[1], int_s[2], 0.3}, door_s, box_mesh, wall_col)

    eng_root.render.add_light({
        type = "point", pocket = p_in,
        pos = {0.0, int_s[2] - 0.6, 0.0},
        color = {1.15, 1.2, 1.3}, range = math.max(int_s[1], int_s[3]) * 1.6
    })

    -- 1. Passable boarding hatch portal (parented to exterior vehicle hull)
    local h_ext = eng_root.scene.spawn(pname .. "_hatch_ext")
    eng_root.scene.set_pocket(h_ext, p_out)
    eng_root.scene.set_parent(h_ext, vehicle_ent)
    eng_root.scene.set_pos(h_ext, hlp[1], hlp[2], hlp[3])
    eng_root.scene.set_rot_deg(h_ext, 0.0, cfg.hatch_yaw or 0.0, 0.0)

    local h_int = eng_root.scene.spawn(pname .. "_hatch_int")
    eng_root.scene.set_pocket(h_int, p_in)
    eng_root.scene.set_pos(h_int, 0.0, door_s[2] * 0.5, int_s[3] * 0.5 - 0.15)
    eng_root.scene.set_rot_deg(h_int, 0.0, 180.0, 0.0)
    local hatch_pidx = eng_root.portal.link(h_ext, h_int, door_s[1], door_s[2], 1.0, true, true)

    -- 2. Non-passable panoramic cockpit windshield portal
    local win_y = cfg.windshield_y or (1.2 + win_s[2] * 0.5)
    local w_int = eng_root.scene.spawn(pname .. "_win_int")
    eng_root.scene.set_pocket(w_int, p_in)
    eng_root.scene.set_pos(w_int, 0.0, win_y, -int_s[3] * 0.5 + 0.25)

    local w_ext = eng_root.scene.spawn(pname .. "_win_ext")
    eng_root.scene.set_pocket(w_ext, p_out)
    eng_root.scene.set_parent(w_ext, vehicle_ent)
    eng_root.scene.set_pos(w_ext, wlp[1], wlp[2], wlp[3])
    eng_root.scene.set_rot_deg(w_ext, 0.0, 180.0, 0.0)
    local win_pidx = eng_root.portal.link(w_int, w_ext, win_s[1], win_s[2], 1.0, false, true)

    -- 3. Optional port & starboard side window portals
    if cfg.side_windows ~= false then
        local swo = cfg.side_window_offset or {2.4, wlp[2], 0.0}
        local sws = cfg.side_window_size or {3.6, 2.0}
        local sy = 1.3 + sws[2] * 0.5
        local p_int_e = eng_root.scene.spawn(pname .. "_port_win_int")
        eng_root.scene.set_pocket(p_int_e, p_in)
        eng_root.scene.set_pos(p_int_e, -int_s[1] * 0.5 + 0.25, sy, 0.0)
        eng_root.scene.set_rot_deg(p_int_e, 0.0, 90.0, 0.0)
        local p_ext_e = eng_root.scene.spawn(pname .. "_port_win_ext")
        eng_root.scene.set_pocket(p_ext_e, p_out)
        eng_root.scene.set_parent(p_ext_e, vehicle_ent)
        eng_root.scene.set_pos(p_ext_e, -swo[1], swo[2], swo[3])
        eng_root.scene.set_rot_deg(p_ext_e, 0.0, -90.0, 0.0)
        eng_root.portal.link(p_int_e, p_ext_e, sws[1], sws[2], 1.0, false, true)

        local s_int_e = eng_root.scene.spawn(pname .. "_stbd_win_int")
        eng_root.scene.set_pocket(s_int_e, p_in)
        eng_root.scene.set_pos(s_int_e, int_s[1] * 0.5 - 0.25, sy, 0.0)
        eng_root.scene.set_rot_deg(s_int_e, 0.0, -90.0, 0.0)
        local s_ext_e = eng_root.scene.spawn(pname .. "_stbd_win_ext")
        eng_root.scene.set_pocket(s_ext_e, p_out)
        eng_root.scene.set_parent(s_ext_e, vehicle_ent)
        eng_root.scene.set_pos(s_ext_e, swo[1], swo[2], swo[3])
        eng_root.scene.set_rot_deg(s_ext_e, 0.0, 90.0, 0.0)
        eng_root.portal.link(s_int_e, s_ext_e, sws[1], sws[2], 1.0, false, true)
    end

    -- 4. Multi-crew interactive interior bridge stations
    local st_defs = cfg.stations or {{ name = "helm", pos = {0.0, 0.0, -int_s[3] * 0.35} }}
    local st_list = {}
    for i = 1, #st_defs do
        local sd = st_defs[i]
        local sp = sd.pos or {0.0, 0.0, 0.0}
        local col = sd.color or {0.2, 0.75, 0.95, 1.0}
        local ped = eng_root.scene.spawn(pname .. "_station_" .. sd.name)
        eng_root.scene.set_pocket(ped, p_in)
        eng_root.scene.set_pos(ped, sp[1], sp[2] + 0.45, sp[3])
        eng_root.scene.set_scale(ped, 1.1, 0.9, 0.8)
        eng_root.scene.set_mesh(ped, box_mesh, { color = col, metallic = 0.4, roughness = 0.3 })
        st_list[#st_list + 1] = { name = sd.name, x = sp[1], y = sp[2], z = sp[3], ent = ped }
    end

    local vx, vy, vz = eng_root.scene.get_pos(vehicle_ent)
    return {
        eng = eng_root,
        entity = vehicle_ent,
        pocket_id = p_in,
        hatch_ext = h_ext,
        hatch_int = h_int,
        hatch_portal = hatch_pidx,
        windshield_portal = win_pidx,
        stations = st_list,
        pos_x = vx,
        base_y = vy,
        pos_z = vz,
        yaw_deg = cfg.yaw_deg or 0.0,
        speed = 0.0,
        throttle = 0.0,
        turn_input = 0.0,
        max_speed = cfg.max_speed or 8.0,
        max_turn_deg = cfg.max_turn_deg or 55.0,
        accel = cfg.accel or 12.0,
        inertial_sway = cfg.inertial_sway or 0.18,
        step_bob_amp = cfg.step_bob_amp or 0.0,
        step_bob_hz = cfg.step_bob_hz or 1.6,
        step_phase = 0.0,
        set_helm_input = M.set_helm_input,
        find_station = M.find_station,
        step = M.step_vehicle_method
    }
end

return M
