-- 101: Titan Janitor — 3-Player Walkable Steerable Giant Bipedal Cleaning Robot
local S = game.state

local function spawn_part(pocket, parent, name, pos, sz, mesh, col, metal, rough)
    local e = eng.scene.spawn(name)
    eng.scene.set_pocket(e, pocket)
    if parent then eng.scene.set_parent(e, parent) end
    eng.scene.set_pos(e, pos[1], pos[2], pos[3])
    eng.scene.set_scale(e, sz[1], sz[2], sz[3])
    eng.scene.set_mesh(e, mesh, { color = col, metallic = metal or 0.35, roughness = rough or 0.55, cast_shadow = true })
    return e
end

function init()
    S.frame = 0
    S.won = false
    S.cam_mode = 0 -- 0 = Bridge Panorama, 1..3 = Crew Follow, 4 = Exterior Giant Mech Cam
    S.split_view = (eng.input.gamepad_count() >= 2)
    if S.split_view then eng.camera.set_split(3, "top2_bot1") end
    S.active_crew = 1
    for gi = 1, 3 do eng.input.set_player_device(gi, "gamepad", gi - 1) end
    S.cruise_throttle = 0.0
    S.hopper_load = 0
    S.hopper_cap = 2
    S.recycled_count = 0
    S.scrubbed_count = 0
    S.core_collected = false
    S.eva_visited_world = false
    S.eva_reboarded = false
    S.eva_galilean_vz = 0.0
    S.vac_pulse = 0.0
    S.scrub_pulse = 0.0
    S.fun = eng.fun.new_tracker()

    eng.render.set_sky(0.16, 0.44, 0.78, 0.68, 0.80, 0.90)
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.35, -1.0, -0.45}, color = {1.35, 1.30, 1.20}, shadow = true })

    local box_m = eng.asset.box(1, 1, 1)
    local cyl_m = eng.asset.cylinder(0.5, 0.5, 1.0, 12)
    local sph_m = eng.asset.sphere(0.5, 10, 12)
    local street_tex = eng.procgen.texture("stone_brick", 101, 64)
    local hull_tex = eng.procgen.texture("metal_rivets", 202, 64)

    -- 1. Exterior City Plaza (pocket 0)
    local ground = eng.scene.spawn("plaza_ground")
    eng.scene.set_pocket(ground, 0)
    eng.scene.set_pos(ground, 0.0, -0.5, 0.0)
    eng.scene.set_scale(ground, 84.0, 1.0, 96.0)
    eng.scene.set_mesh(ground, box_m, { tex = street_tex, color = {0.55, 0.58, 0.62, 1.0} })
    eng.physics.add_body(ground, { shape = "aabb", motion = "static", pocket = 0, half_extents = {42.0, 0.5, 48.0} })

    for i = 1, 6 do
        local bz = 24.0 - (i - 1) * 11.0
        local h_l = 9.0 + (i % 3) * 4.5
        local h_r = 11.0 + ((i + 1) % 3) * 4.0
        spawn_part(0, nil, "bldg_l_" .. i, {-16.0, h_l * 0.5, bz}, {6.0, h_l, 7.5}, box_m, {0.42, 0.48, 0.58, 1.0}, 0.2, 0.7)
        spawn_part(0, nil, "bldg_r_" .. i, { 16.0, h_r * 0.5, bz}, {6.0, h_r, 7.5}, box_m, {0.52, 0.46, 0.44, 1.0}, 0.2, 0.7)
    end

    -- Trash Piles (for Vacuum + Recycler) & Toxic Sludge Spills (for Hydro-Scrubber)
    local trash_coords = {{-2.4, 10.0}, {2.4, 2.0}, {-2.0, -6.0}, {2.2, -14.0}}
    S.trash = {}
    for i = 1, #trash_coords do
        local tc = trash_coords[i]
        local te = spawn_part(0, nil, "trash_" .. i, {tc[1], 0.65, tc[2]}, {1.6, 1.3, 1.6}, sph_m, {0.58, 0.44, 0.26, 1.0}, 0.1, 0.9)
        S.trash[i] = { ent = te, x = tc[1], z = tc[2], active = true }
    end

    local spill_coords = {{2.2, 6.0}, {-2.2, -1.0}, {2.4, -8.0}, {-1.8, -15.0}}
    S.spills = {}
    for i = 1, #spill_coords do
        local sc = spill_coords[i]
        local se = spawn_part(0, nil, "sludge_" .. i, {sc[1], 0.08, sc[2]}, {3.2, 0.16, 3.2}, cyl_m, {0.35, 0.95, 0.18, 1.0}, 0.1, 0.25)
        S.spills[i] = { ent = se, x = sc[1], z = sc[2], active = true }
    end

    -- External Overdrive Power Cell on the street (for EVA ramp exit & moving-ramp scoop!)
    S.core_ent = spawn_part(0, nil, "overdrive_core", {0.0, 0.9, 13.5}, {0.9, 1.2, 0.9}, cyl_m, {1.0, 0.88, 0.15, 1.0}, 0.8, 0.2)

    -- 2. Giant 14m Articulated Bipedal Cleaning Robot (exterior world entity)
    local mech = eng.scene.spawn("titan_cleaner_mech")
    eng.scene.set_pocket(mech, 0)
    eng.scene.set_pos(mech, 0.0, 0.0, 20.0)
    S.mech_ent = mech

    local yellow = {0.94, 0.74, 0.16, 1.0}
    local slate  = {0.26, 0.32, 0.38, 1.0}
    local cyan   = {0.18, 0.86, 0.96, 1.0}

    local torso = spawn_part(0, mech, "mech_torso", {0.0, 8.2, 0.0}, {5.0, 4.4, 3.6}, box_m, yellow, 0.5, 0.4)
    eng.scene.set_mesh(torso, box_m, { tex = hull_tex, color = yellow, metallic = 0.5, roughness = 0.4, cast_shadow = true })
    spawn_part(0, mech, "mech_pelvis", {0.0, 5.4, 0.0}, {4.2, 1.1, 2.8}, box_m, slate, 0.6, 0.45)
    spawn_part(0, mech, "mech_head", {0.0, 11.3, -0.4}, {3.8, 1.9, 2.8}, box_m, yellow, 0.5, 0.35)
    spawn_part(0, mech, "mech_ramp_apron", {0.0, 0.18, -2.2}, {2.3, 0.25, 1.3}, box_m, yellow, 0.4, 0.5)

    -- Articulated Left & Right Bipedal Legs
    S.hip_l = eng.scene.spawn("hip_l"); eng.scene.set_pocket(S.hip_l, 0); eng.scene.set_parent(S.hip_l, mech); eng.scene.set_pos(S.hip_l, -2.1, 5.2, 0.0)
    spawn_part(0, S.hip_l, "thigh_l", {0.0, -1.3, 0.0}, {1.15, 2.6, 1.25}, box_m, yellow, 0.5, 0.45)
    S.knee_l = eng.scene.spawn("knee_l"); eng.scene.set_pocket(S.knee_l, 0); eng.scene.set_parent(S.knee_l, S.hip_l); eng.scene.set_pos(S.knee_l, 0.0, -2.6, 0.0)
    spawn_part(0, S.knee_l, "shin_l", {0.0, -1.3, 0.0}, {0.95, 2.6, 1.05}, box_m, slate, 0.6, 0.4)
    spawn_part(0, S.knee_l, "boot_l", {0.0, -2.45, -0.35}, {1.5, 0.55, 2.2}, box_m, yellow, 0.5, 0.5)

    S.hip_r = eng.scene.spawn("hip_r"); eng.scene.set_pocket(S.hip_r, 0); eng.scene.set_parent(S.hip_r, mech); eng.scene.set_pos(S.hip_r, 2.1, 5.2, 0.0)
    spawn_part(0, S.hip_r, "thigh_r", {0.0, -1.3, 0.0}, {1.15, 2.6, 1.25}, box_m, yellow, 0.5, 0.45)
    S.knee_r = eng.scene.spawn("knee_r"); eng.scene.set_pocket(S.knee_r, 0); eng.scene.set_parent(S.knee_r, S.hip_r); eng.scene.set_pos(S.knee_r, 0.0, -2.6, 0.0)
    spawn_part(0, S.knee_r, "shin_r", {0.0, -1.3, 0.0}, {0.95, 2.6, 1.05}, box_m, slate, 0.6, 0.4)
    spawn_part(0, S.knee_r, "boot_r", {0.0, -2.45, -0.35}, {1.5, 0.55, 2.2}, box_m, yellow, 0.5, 0.5)

    -- Left Vortex Vacuum Arm & Right Hydro-Scrubber Arm (mounted below shoulder observation windows)
    S.arm_vac = spawn_part(0, mech, "arm_vac", {-3.2, 6.6, -1.5}, {0.9, 0.9, 3.4}, cyl_m, cyan, 0.6, 0.3)
    S.arm_scrub = spawn_part(0, mech, "arm_scrub", {3.2, 6.6, -1.5}, {0.9, 0.9, 3.4}, cyl_m, {0.22, 0.92, 0.52, 1.0}, 0.6, 0.3)
    S.scrub_disc = spawn_part(0, S.arm_scrub, "scrub_disc", {0.0, -0.4, -1.6}, {2.0, 0.3, 2.0}, cyl_m, {0.85, 0.98, 0.92, 1.0}, 0.2, 0.3)

    S.foam_emitter = eng.particles.create({ pos = {3.2, 3.0, 16.0}, dir = {0.0, -1.0, -0.5}, spread = 0.8, speed = 6.0, rate = 0.0, life = 0.6 })

    -- 3. Walkable Multi-Station Interior Bridge via eng.space.create_steerable_vehicle
    S.veh = eng.space.create_steerable_vehicle(eng, mech, {
        pocket = "mech_bridge",
        interior_size = {16.0, 5.5, 18.0},
        door_size = {2.4, 2.6},
        hatch_local_pos = {0.0, 1.3, -2.8},
        hatch_yaw = 180.0,
        windshield_local_pos = {0.0, 11.3, -1.95},
        windshield_size = {7.2, 2.6},
        windshield_y = 2.5,
        side_windows = true,
        side_window_offset = {2.65, 8.6, 0.0},
        side_window_size = {4.2, 2.0},
        max_speed = 9.0,
        max_turn_deg = 52.0,
        accel = 18.0,
        inertial_sway = 0.20,
        step_bob_amp = 0.14,
        step_bob_hz = 1.8,
        stations = {
            { name = "helm",     pos = { 0.0, 0.0, -6.2}, color = {0.95, 0.78, 0.18, 1.0} },
            { name = "vacuum",   pos = {-5.0, 0.0, -2.0}, color = {0.18, 0.85, 0.98, 1.0} },
            { name = "scrubber", pos = { 5.0, 0.0, -2.0}, color = {0.22, 0.92, 0.52, 1.0} },
            { name = "recycler", pos = { 0.0, 0.0,  3.6}, color = {0.96, 0.45, 0.16, 1.0} }
        }
    })
    S.bridge_pocket = S.veh.pocket_id
    S.hopper_bar = spawn_part(S.bridge_pocket, nil, "hopper_gauge", {1.4, 0.6, 3.6}, {0.45, 0.2, 0.45}, box_m, cyan, 0.3, 0.3)

    -- 4. Spawn 3 Simultaneous Playable Crew Members Inside the Bridge
    local crew_spawns = {
        { name = "Pilot_Ada", pos = { 0.0, 0.90, -4.8}, badge = {0.98, 0.82, 0.18, 1.0}, seed = 101, prefix = "p1" },
        { name = "Tech_Bo",   pos = {-4.0, 0.90, -2.0}, badge = {0.18, 0.88, 0.98, 1.0}, seed = 202, prefix = "p2" },
        { name = "Scout_Cy",  pos = { 0.0, 0.90,  7.2}, badge = {0.22, 0.95, 0.52, 1.0}, seed = 303, prefix = "p3" }
    }
    S.crew = {}
    for i = 1, 3 do
        local cs = crew_spawns[i]
        local col_e = eng.scene.spawn(cs.name)
        eng.scene.set_pocket(col_e, S.bridge_pocket)
        eng.scene.set_pos(col_e, cs.pos[1], cs.pos[2], cs.pos[3])
        local bid = eng.physics.add_body(col_e, {
            shape = "capsule", motion = "kinematic", pocket = S.bridge_pocket,
            radius = 0.35, half_height = 0.55
        })

        local vis_e = eng.scene.spawn(cs.name .. "_rig")
        eng.scene.set_pocket(vis_e, S.bridge_pocket)
        eng.scene.set_parent(vis_e, col_e)
        eng.scene.set_pos(vis_e, 0.0, -0.90, 0.0)
        eng.procgen.person(vis_e, cs.seed)

        local hat_e = spawn_part(S.bridge_pocket, vis_e, cs.name .. "_hat", {0.0, 1.92, 0.0}, {0.36, 0.18, 0.36}, sph_m, cs.badge, 0.2, 0.3)
        S.crew[i] = {
            name = cs.name, prefix = cs.prefix, ent = col_e, body = bid,
            vis = vis_e, hat = hat_e, pocket = S.bridge_pocket,
            at_helm_lock = false, station = nil, yaw = 0.0,
            ext_vx = 0.0, ext_vz = 0.0
        }
    end

    S.sfx_act = eng.audio.synth("triangle", 360, 0.10, 620)
    S.sfx_win = eng.audio.synth("square", 440, 0.25, 880)

    -- Initial panoramic bridge camera showing all 3 crew + stations + exterior plaza through stencil visor!
    eng.camera.look_at(0.0, 3.9, 6.4, 0.0, 1.9, -9.0, S.bridge_pocket)
end

local function crew_axes_and_act(idx, c)
    local p = c.prefix
    local lx = (eng.input.down(p .. "_right") and 1.0 or 0.0) - (eng.input.down(p .. "_left") and 1.0 or 0.0)
    local lz = (eng.input.down(p .. "_down") and 1.0 or 0.0) - (eng.input.down(p .. "_up") and 1.0 or 0.0)
    local act = eng.input.pressed(p .. "_act")
    local gmx, gmy = eng.input.player_move(idx)
    lx = eng.math.clamp(lx + gmx, -1.0, 1.0)
    lz = eng.math.clamp(lz - gmy, -1.0, 1.0)
    if eng.input.player_pressed(idx, "interact") or eng.input.player_pressed(idx, "jump") or eng.input.player_pressed(idx, "fire") then
        act = true
    end
    return lx, lz, act
end

local function trigger_vacuum()
    S.vac_pulse = 0.35
    eng.audio.play(S.sfx_act, -5.0, 1.0, -2.0, S.bridge_pocket)
    if S.hopper_load >= S.hopper_cap then return false end
    local mx, _, mz = S.veh.pos_x, S.veh.base_y, S.veh.pos_z
    for i = 1, #S.trash do
        local t = S.trash[i]
        if t.active then
            local dx, dz = t.x - mx, t.z - mz
            if dx * dx + dz * dz <= 15.0 * 15.0 and S.hopper_load < S.hopper_cap then
                t.active = false
                eng.scene.despawn(t.ent)
                S.hopper_load = S.hopper_load + 1
                eng.fun.record_action(S.fun, true)
            end
        end
    end
    return true
end

local function trigger_scrubber()
    S.scrub_pulse = 0.35
    eng.particles.burst(S.foam_emitter, 14)
    eng.audio.play(S.sfx_act, 5.0, 1.0, -2.0, S.bridge_pocket)
    local mx, mz = S.veh.pos_x, S.veh.pos_z
    for i = 1, #S.spills do
        local sp = S.spills[i]
        if sp.active then
            local dx, dz = sp.x - mx, sp.z - mz
            if dx * dx + dz * dz <= 15.0 * 15.0 then
                sp.active = false
                eng.scene.despawn(sp.ent)
                S.scrubbed_count = S.scrubbed_count + 1
                eng.fun.record_action(S.fun, true)
            end
        end
    end
end

local function trigger_recycler()
    if S.hopper_load > 0 then
        S.recycled_count = S.recycled_count + S.hopper_load
        S.hopper_load = 0
        eng.audio.play(S.sfx_act, 0.0, 1.0, 3.6, S.bridge_pocket)
        eng.fun.record_action(S.fun, true)
    end
end

function update(dt)
    S.frame = S.frame + 1
    if eng.input.pressed("switch_crew") then
        S.active_crew = (S.active_crew % 3) + 1
        S.cam_mode = S.active_crew
    end
    if eng.input.pressed("toggle_cam") then
        S.cam_mode = (S.cam_mode == 4) and 0 or 4
    end
    if eng.input.pressed("toggle_split") then
        S.split_view = not S.split_view
        if S.split_view then eng.camera.set_split(3, "top2_bot1") else eng.camera.set_split(1) end
    end

    -- 1. Gather helm steering from whichever crew member has Helm Lock active (plus persistent cruise!)
    local throttle = S.cruise_throttle
    local turn_in = 0.0
    for i = 1, 3 do
        local c = S.crew[i]
        if c.at_helm_lock and c.pocket == S.bridge_pocket then
            local lx, lz = crew_axes_and_act(i, c)
            if lz < -0.1 then S.cruise_throttle = 1.0 elseif lz > 0.1 then S.cruise_throttle = -0.6 end
            throttle = S.cruise_throttle
            turn_in = lx
        end
    end

    local speed_scale = S.core_collected and 1.25 or 1.0
    S.veh.max_speed = 9.0 * speed_scale
    S.veh:set_helm_input(throttle, turn_in)
    S.veh:step(dt)
    eng.fun.record_position(S.fun, S.veh.pos_x, S.veh.pos_z, 3.0)

    -- Animate exterior giant bipedal legs & cleaning arms
    local sp = S.veh.step_phase
    local swing = math.sin(sp) * 28.0
    eng.scene.set_rot_deg(S.hip_l,  swing, 0.0, 0.0)
    eng.scene.set_rot_deg(S.knee_l, -math.max(0.0, swing) * 0.85, 0.0, 0.0)
    eng.scene.set_rot_deg(S.hip_r, -swing, 0.0, 0.0)
    eng.scene.set_rot_deg(S.knee_r, -math.max(0.0, -swing) * 0.85, 0.0, 0.0)

    S.vac_pulse = math.max(0.0, S.vac_pulse - dt)
    S.scrub_pulse = math.max(0.0, S.scrub_pulse - dt)
    eng.scene.set_rot_deg(S.arm_vac, -12.0 - S.vac_pulse * 35.0, 10.0, 0.0)
    eng.scene.set_rot_deg(S.arm_scrub, -15.0 - S.scrub_pulse * 30.0, -10.0, 0.0)
    eng.scene.set_rot_deg(S.scrub_disc, 0.0, S.frame * 14.0, 0.0)
    eng.scene.set_scale(S.hopper_bar, 0.45, 0.2 + (S.hopper_load / S.hopper_cap) * 1.6, 0.45)

    -- 2. Move all 3 crew members & process station interactions + Galilean boarding ramp!
    local all_aboard = true
    for i = 1, 3 do
        local c = S.crew[i]
        local lx, lz, act = crew_axes_and_act(i, c)
        local cx, cy, cz = eng.scene.get_pos(c.ent)
        local prev_pk = eng.scene.get_pocket(c.ent)

        if prev_pk == S.bridge_pocket then
            c.station = S.veh:find_station(cx, cz, 2.0)
            if act then
                if c.station == "helm" then
                    c.at_helm_lock = not c.at_helm_lock
                    if c.at_helm_lock and math.abs(S.cruise_throttle) < 0.1 then
                        S.cruise_throttle = 1.0
                    end
                    eng.audio.play(S.sfx_act, cx, cy, cz, prev_pk)
                elseif c.station == "vacuum" then
                    trigger_vacuum()
                elseif c.station == "scrubber" then
                    trigger_scrubber()
                elseif c.station == "recycler" then
                    trigger_recycler()
                end
            end
        else
            c.at_helm_lock = false
            c.station = "EVA_OUTSIDE"
        end

        local walk_x, walk_z = 0.0, 0.0
        if not c.at_helm_lock then
            local len = math.sqrt(lx * lx + lz * lz)
            if len > 0.01 then
                walk_x = (lx / len) * 5.8
                walk_z = (lz / len) * 5.8
                c.yaw = math.atan2(-walk_x, -walk_z) * (180.0 / math.pi)
            end
        end

        if prev_pk == S.bridge_pocket then
            -- Seed body velocity prior to move_character so exiting the moving ramp warps exact Galilean momentum
            eng.physics.set_vel(c.body, walk_x, 0.0, walk_z)
            eng.physics.move_character(c.body, walk_x * dt, -9.81 * dt, walk_z * dt, 0.4)
            local now_pk = eng.scene.get_pocket(c.ent)
            if now_pk ~= prev_pk then
                local gvx, _, gvz = eng.physics.get_vel(c.body)
                c.ext_vx, c.ext_vz = gvx, gvz
                S.eva_visited_world = true
                S.eva_galilean_vz = gvz
            end
            eng.physics.set_vel(c.body, 0.0, 0.0, 0.0)
        else
            local damp = math.exp(-3.2 * dt)
            c.ext_vx = c.ext_vx * damp
            c.ext_vz = c.ext_vz * damp
            eng.physics.set_vel(c.body, 0.0, 0.0, 0.0)
            eng.physics.move_character(c.body, (c.ext_vx + walk_x) * dt, -9.81 * dt, (c.ext_vz + walk_z) * dt, 0.4)
            local now_pk = eng.scene.get_pocket(c.ent)
            if now_pk == S.bridge_pocket then
                c.ext_vx, c.ext_vz = 0.0, 0.0
                S.eva_reboarded = true
            end
        end

        c.pocket = eng.scene.get_pocket(c.ent)
        eng.scene.set_pocket(c.vis, c.pocket)
        eng.scene.set_pocket(c.hat, c.pocket)
        eng.scene.set_rot_deg(c.vis, 0.0, c.yaw, 0.0)
        eng.anim.set_gait_speed(c.vis, (math.abs(walk_x) + math.abs(walk_z) > 0.1) and 1.6 or 0.0)

        if c.pocket ~= S.bridge_pocket then
            all_aboard = false
            if not S.core_collected then
                local ex, _, ez = eng.scene.get_pos(c.ent)
                local dx, dz = ex - 0.0, ez - 13.5
                if dx * dx + dz * dz <= 4.2 * 4.2 then
                    S.core_collected = true
                    eng.scene.despawn(S.core_ent)
                    eng.audio.play(S.sfx_act, ex, 1.0, ez, 0)
                end
            end
        end
    end

    -- 3. Victory check
    if not S.won and S.recycled_count >= 4 and S.scrubbed_count >= 4 and S.core_collected and all_aboard then
        S.won = true
        eng.audio.play(S.sfx_win)
        eng.fun.record_outcome(S.fun, true)
    end

    -- 4. Update active camera(s)
    if S.split_view then
        for i = 1, 3 do
            local fc = S.crew[i]
            local px, py, pz = eng.scene.get_pos(fc.ent)
            eng.camera.look_at_view(i, px, py + 2.2, pz + 3.6, px, py + 0.6, pz - 4.0, fc.pocket)
        end
    elseif S.cam_mode == 0 then
        eng.camera.look_at(0.0, 3.9, 6.4, 0.0, 1.9, -9.0, S.bridge_pocket)
    elseif S.cam_mode >= 1 and S.cam_mode <= 3 then
        local fc = S.crew[S.cam_mode]
        local px, py, pz = eng.scene.get_pos(fc.ent)
        eng.camera.look_at(px, py + 2.2, pz + 3.6, px, py + 0.6, pz - 4.0, fc.pocket)
    else
        eng.camera.look_at(S.veh.pos_x + 11.0, 9.5, S.veh.pos_z + 14.0, S.veh.pos_x, 6.0, S.veh.pos_z - 4.0, 0)
    end
end

function draw()
    eng.ui.label(16, 14, eng.i18n.t("title"), 1.25)
    eng.ui.label(16, 38, eng.i18n.t("controls"), 0.9)
    eng.ui.bar(16, 62, 220, (S.recycled_count + S.scrubbed_count) / 8.0,
               string.format("CLEANUP %d/8 | HOPPER %d/%d", S.recycled_count + S.scrubbed_count, S.hopper_load, S.hopper_cap))
    local st_line = string.format("MECH %.1fm/s | P1:%s P2:%s P3:%s | CORE:%s",
        S.veh.speed,
        S.crew[1].station or "deck",
        S.crew[2].station or "deck",
        S.crew[3].station or "deck",
        S.core_collected and "YES" or "NO")
    eng.ui.label(16, 92, st_line, 0.9)
    if S.won then
        eng.ui.label(16, 122, eng.i18n.t("victory"), 1.2)
    end
end
