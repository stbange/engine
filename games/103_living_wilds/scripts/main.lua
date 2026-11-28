-- 103_living_wilds: Low-Res Realism Lens (360p PBR, Soft PCF Shadows, SSAO, Volumetric God-Rays)
-- + Gerstner Refractive Water & Buoyancy + Planck Blackbody Fire + 6-DOF Joints & Voxel Fracture
-- + Systemic Chemistry, Thermodynamics, Electricity, Flora & Scent-Driven Wildlife + Pocket Mill

local TOOLS = { "torch", "shock", "acid", "blast" }

local function spawn_static_box(pk, name, mesh, x, y, z, sx, sy, sz, opts)
    local e = eng.scene.spawn(name)
    eng.scene.set_pocket(e, pk)
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_scale(e, sx, sy, sz)
    if mesh then
        eng.scene.set_mesh(e, mesh, opts)
    end
    local bid = eng.physics.add_body(e, {
        shape = "aabb",
        motion = "static",
        pocket = pk,
        half_extents = { sx * 0.5, sy * 0.5, sz * 0.5 },
    })
    return e, bid
end

function init()
    local S = game.state
    eng.math.seed(103)
    eng.xr.set_mode("first_person")
    eng.input.set_mouse_lock(true)

    S.time = 0.0
    S.yaw = 0.25
    S.pitch = -0.10
    S.overlook = false
    S.raining = false
    S.tool_idx = 1
    S.arch_fractured = false
    S.vy = 0.0

    local box_mesh = eng.asset.box(1, 1, 1)
    local sph_mesh = eng.asset.sphere(0.5, 14, 18)
    local cyl_mesh = eng.asset.cylinder(0.22, 0.22, 1.0, 12)
    local tree_mesh = eng.procgen.tree(1031, 3, 2.6, 0.18)

    local cobble_tex = eng.procgen.texture("cobble", 42, 64)
    local grass_tex  = eng.procgen.texture("grass", 43, 64)
    local wood_tex   = eng.procgen.texture("wood_planks", 44, 64)
    local stone_tex  = eng.procgen.texture("stone_brick", 45, 64)

    S.sfx_splash = eng.audio.synth("noise", 220, 0.16, 90)
    S.sfx_spark  = eng.audio.synth("saw", 520, 0.12, 180)
    S.sfx_crack  = eng.audio.synth("square", 140, 0.22, 48)

    -- 1. Atmospheric Sky, Sun Shadows & Gerstner Alpine River
    eng.fx.sky(eng, "alpine_day")
    eng.render.add_light({
        type = "directional",
        pocket = 0,
        dir = { -0.42, -0.74, -0.52 },
        color = { 1.35, 1.24, 1.04 },
        shadow = true,
    })
    eng.fx.water(eng, "alpine_river", {
        pocket = 0,
        level = 0.0,
        flow = { 0.0, 0.85 },
        wave_amp = 0.055,
        refraction = 0.032,
        caustics = 0.48,
    })

    -- 2. Valley Riverbed, Wet Cobble Shorelines, Grassy Banks & Timber Footbridge
    spawn_static_box(0, "riverbed", box_mesh, 0.0, -1.45, 0.0, 48.0, 0.50, 48.0, {
        tex = cobble_tex, normal_tex = cobble_tex, color = { 0.58, 0.56, 0.52, 1.0 }, roughness = 0.65, wetness = 0.96,
    })
    spawn_static_box(0, "west_bank", box_mesh, -13.8, -0.40, 0.0, 20.0, 1.40, 46.0, {
        tex = grass_tex, normal_tex = grass_tex, color = { 0.44, 0.64, 0.34, 1.0 }, roughness = 0.86,
    })
    spawn_static_box(0, "east_bank", box_mesh, 13.8, -0.40, 0.0, 20.0, 1.40, 46.0, {
        tex = grass_tex, normal_tex = grass_tex, color = { 0.46, 0.65, 0.36, 1.0 }, roughness = 0.86,
    })

    S.shore_ents = {}
    S.shore_ents[1] = spawn_static_box(0, "west_shore", box_mesh, -3.35, -0.18, -3.0, 1.1, 0.55, 28.0, {
        tex = cobble_tex, normal_tex = cobble_tex, color = { 0.62, 0.60, 0.56, 1.0 }, roughness = 0.72, wetness = 0.88,
    })
    S.shore_ents[2] = spawn_static_box(0, "east_shore", box_mesh, 3.35, -0.18, -3.0, 1.1, 0.55, 28.0, {
        tex = cobble_tex, normal_tex = cobble_tex, color = { 0.62, 0.60, 0.56, 1.0 }, roughness = 0.72, wetness = 0.88,
    })

    -- Walkable wooden footbridge across the Gerstner river at z = 3.0
    spawn_static_box(0, "bridge_deck", box_mesh, 0.0, 0.36, 3.0, 8.2, 0.22, 2.4, {
        tex = wood_tex, normal_tex = wood_tex, color = { 0.64, 0.46, 0.28, 1.0 }, roughness = 0.78, cast_shadow = true,
    })

    -- Sunlit stone columns along West ridge to cast crisp volumetric god-ray shafts
    for i = 1, 4 do
        spawn_static_box(0, "sun_pillar_" .. tostring(i), box_mesh, -15.5, 2.6, -12.0 + i * 4.5, 0.9, 4.6, 0.9, {
            tex = stone_tex, normal_tex = stone_tex, color = { 0.68, 0.66, 0.62, 1.0 }, roughness = 0.82, cast_shadow = true,
        })
    end

    -- Invisible basin perimeter walls
    spawn_static_box(0, "bound_n", nil, 0, 3, -22.5, 48, 8, 0.5)
    spawn_static_box(0, "bound_s", nil, 0, 3,  22.5, 48, 8, 0.5)
    spawn_static_box(0, "bound_w", nil, -22.5, 3, 0, 0.5, 8, 48)
    spawn_static_box(0, "bound_e", nil,  22.5, 3, 0, 0.5, 8, 48)

    -- 3. "Bigger on the Inside" Alchemist's Pocket Mill on the East Bank (x = 9.0, z = -6.0)
    local mill = eng.space.create_pocket_building(eng, {
        exterior_pos = { 9.0, 0.30, -6.0 },
        exterior_size = { 4.2, 3.5, 4.0 },
        interior_size = { 18.0, 8.0, 22.0 },
        door_size = { 1.6, 2.4 },
        pocket = "mill_inside",
        mesh_id = box_mesh,
        exterior_color = { 0.56, 0.52, 0.48, 1.0 },
        interior_color = { 0.30, 0.28, 0.26, 1.0 },
    })
    S.mill_pocket = mill.pocket_id
    eng.fx.sky(eng, "starry_night", { pocket = S.mill_pocket })
    eng.render.add_light({
        type = "point", pocket = S.mill_pocket,
        pos = { 0.0, 5.5, 0.0 }, color = { 2.2, 1.75, 1.25 }, range = 22.0,
    })
    eng.render.add_light({
        type = "point", pocket = S.mill_pocket,
        pos = { -4.5, 2.2, -5.0 }, color = { 2.8, 1.1, 0.35 }, range = 12.0,
    })
    spawn_static_box(S.mill_pocket, "mill_bench", box_mesh, 0.0, 0.55, -4.5, 4.0, 1.1, 1.4, {
        tex = wood_tex, normal_tex = wood_tex, color = { 0.55, 0.38, 0.22, 1.0 }, roughness = 0.72,
    })
    local retort = eng.scene.spawn("mill_retort")
    eng.scene.set_pocket(retort, S.mill_pocket)
    eng.scene.set_pos(retort, 0.0, 1.45, -4.5)
    eng.scene.set_scale(retort, 0.75, 0.75, 0.75)
    eng.scene.set_mesh(retort, sph_mesh, eng.fx.material("emerald"))

    -- 4. 6-DOF Physics: Buoyant Cedar Logs vs Sinking Granite Boulder, Swinging Joint Lantern & Fracturable Voxel Arch
    S.log_bodies = {}
    for i = 1, 3 do
        local lg = eng.scene.spawn("cedar_log_" .. tostring(i))
        eng.scene.set_pos(lg, -1.4 + (i - 1) * 1.35, 0.35, -7.5 + i * 2.2)
        eng.scene.set_scale(lg, 0.42, 0.42, 1.55)
        eng.scene.set_mesh(lg, box_mesh, {
            tex = wood_tex, normal_tex = wood_tex, color = { 0.58, 0.38, 0.20, 1.0 }, roughness = 0.75, wetness = 0.75, cast_shadow = true,
        })
        S.log_bodies[i] = eng.physics.add_body(lg, {
            shape = "aabb", motion = "dynamic",
            half_extents = { 0.21, 0.21, 0.775 },
            density = eng.sim_ext.densities.pine,
            linear_damping = 0.35, angular_damping = 0.45, freeze_rot = false,
        })
    end

    local boulder = eng.scene.spawn("river_boulder")
    eng.scene.set_pos(boulder, 0.6, 0.30, -3.2)
    eng.scene.set_scale(boulder, 0.75, 0.75, 0.75)
    eng.scene.set_mesh(boulder, sph_mesh, {
        tex = cobble_tex, normal_tex = cobble_tex, color = { 0.45, 0.46, 0.48, 1.0 }, roughness = 0.85, wetness = 0.90, cast_shadow = true,
    })
    S.boulder_body = eng.physics.add_body(boulder, {
        shape = "sphere", motion = "dynamic", radius = 0.375,
        density = eng.sim_ext.densities.stone, freeze_rot = false,
    })

    -- Timber post + swinging copper lantern suspended on a breakable distance joint
    local _, post_bid = spawn_static_box(0, "lantern_post", cyl_mesh, -4.6, 1.65, -1.5, 0.7, 2.7, 0.7, {
        tex = wood_tex, normal_tex = wood_tex, color = { 0.48, 0.32, 0.18, 1.0 }, roughness = 0.82, cast_shadow = true,
    })
    S.lantern_ent = eng.scene.spawn("hanging_lantern")
    eng.scene.set_pos(S.lantern_ent, -4.05, 2.05, -1.5)
    eng.scene.set_scale(S.lantern_ent, 0.34, 0.44, 0.34)
    eng.scene.set_mesh(S.lantern_ent, box_mesh, eng.fx.material("copper", { emissive = { 1.4, 0.85, 0.28 } }))
    S.lantern_body = eng.physics.add_body(S.lantern_ent, {
        shape = "aabb", motion = "dynamic", half_extents = { 0.17, 0.22, 0.17 },
        density = 1600, linear_damping = 0.20, angular_damping = 0.30, freeze_rot = false,
    })
    S.lantern_joint = eng.physics.add_joint({
        type = "distance",
        body_a = post_bid, body_b = S.lantern_body,
        anchor_a = { 0.55, 1.25, 0.0 }, anchor_b = { 0.0, 0.22, 0.0 },
        rest_length = 0.80, break_force = 520.0,
    })
    eng.physics.apply_impulse(S.lantern_body, 0.0, 0.0, 1.8)
    S.lantern_light = eng.render.add_light({
        type = "point", pocket = 0, pos = { -4.05, 2.0, -1.5 }, color = { 1.8, 1.15, 0.45 }, range = 7.5,
    })

    -- Destructible ancient voxel stone arch on West bank (severing left leg drops upper lintel as a 6-DOF island!)
    local arch_layers = {
        "##....##\n##....##",
        "##....##\n##....##",
        "##....##\n##....##",
        "########\n########",
        ".######.\n.######.",
    }
    local arch_mesh, arch_vox = eng.asset.voxel_ascii(arch_layers, 8, 5, 2, 0.36)
    S.arch_ent = eng.scene.spawn("ruin_arch")
    eng.scene.set_pos(S.arch_ent, -11.2, 0.30, -2.2)
    eng.scene.set_mesh(S.arch_ent, arch_mesh, {
        tex = stone_tex, normal_tex = stone_tex, color = { 0.66, 0.63, 0.58, 1.0 }, roughness = 0.86, cast_shadow = true,
    })
    eng.physics.add_body(S.arch_ent, { shape = "voxel", motion = "static", voxel_id = arch_vox })
    S.arch_vox = arch_vox

    -- 5. Systemic Chemistry, Thermodynamics, Electricity, Flora & Scent Wildlife (14x8x14 @ 0.45m)
    eng.sim.init({
        pocket = 0, gx = 14, gy = 8, gz = 14, cell_size = 0.45,
        origin = { -10.2, 0.30, -11.5 }, ambient_c = 19.0, seed = 103,
    })
    eng.sim.set_sun_dir(0.42, 0.74, 0.52, 0)
    eng.sim.set_wind(1.35, 0.0, 0.35, 0)

    -- Soil terrace + campfire wood stack + floating oil-on-water basin + copper/salt_water conductor
    eng.sim.fill_box(0, 0, 0, 13, 0, 13, "soil", 0)
    eng.sim.fill_box(2, 1, 2, 4, 1, 4, "water", 0)
    eng.sim.fill_box(2, 2, 2, 4, 2, 4, "oil", 0)
    eng.sim.fill_box(5, 1, 3, 7, 2, 5, "wood", 0)
    eng.sim.ignite(6, 2, 4, 0)
    eng.sim.ignite(3, 2, 3, 0)

    eng.sim.fill_box(9, 1, 2, 12, 1, 2, "copper", 0)
    eng.sim.fill_box(11, 1, 3, 12, 1, 5, "salt_water", 0)

    -- Saplings rooted in fertile soil beside the firepit (ash fertilizes them!)
    S.plants = {}
    local plant_coords = { { 2, 0, 9 }, { 6, 0, 10 }, { 10, 0, 9 } }
    for i = 1, #plant_coords do
        local pc = plant_coords[i]
        local pe = eng.scene.spawn("sapling_" .. tostring(i))
        local wx = -10.2 + (pc[1] + 0.5) * 0.45
        local wz = -11.5 + (pc[3] + 0.5) * 0.45
        eng.scene.set_pos(pe, wx, 0.75, wz)
        eng.scene.set_scale(pe, 0.35, 0.35, 0.35)
        eng.scene.set_mesh(pe, tree_mesh, { color = { 0.30, 0.62, 0.24, 1.0 }, roughness = 0.85, cast_shadow = true })
        local pid = eng.sim.add_plant(pc[1], pc[2], pc[3], pe, 0)
        S.plants[i] = { id = pid, ent = pe, wx = wx, wz = wz }
    end

    S.sim_ent = eng.scene.spawn("sim_cells")
    eng.scene.set_pos(S.sim_ent, -10.2, 0.30, -11.5)
    eng.scene.set_scale(S.sim_ent, 0.45, 0.45, 0.45)
    local sm = eng.sim.build_mesh(true, 0)
    eng.scene.set_mesh(S.sim_ent, sm, { roughness = 0.78, cast_shadow = true })
    S.sim_mesh_timer = 0.0

    -- Planck blackbody flame emitter + flickering inverse-square firelight
    S.fire_emitter = eng.fx.spawn(eng, "fire", -7.3, 1.15, -9.5, 0, { wind = { 1.35, 0.0, 0.35 } })
    S.fire_light = eng.render.add_light({
        type = "point", pocket = 0, pos = { -7.3, 1.8, -9.5 }, color = { 3.0, 1.4, 0.4 }, range = 10.0,
    })

    -- Scent-aware mountain stag grazing on the West meadow
    S.stag_ent = eng.scene.spawn("mountain_stag")
    eng.scene.set_pos(S.stag_ent, -6.2, 0.32, 0.8)
    eng.procgen.animal(S.stag_ent, 77, "quadruped")
    eng.anim.set_gait_speed(S.stag_ent, 1.2)
    S.stag_bio = eng.sim.add_bio(-6.2, 0.65, 0.8, false, 1.2, S.stag_ent, 0)
    S.stag_x, S.stag_z = -6.2, 0.8

    -- 6. Player Capsule Character Body & Homeostasis
    S.player_ent = eng.scene.spawn("explorer")
    eng.scene.set_pos(S.player_ent, -5.2, 1.25, 3.0)
    S.player_body = eng.physics.add_body(S.player_ent, {
        shape = "capsule", motion = "kinematic", radius = 0.36, half_height = 0.55,
    })
    S.player_bio = eng.sim.add_bio(-5.2, 1.25, 3.0, false, 0.8, S.player_ent, 0)
    S.px, S.py, S.pz, S.pocket = -5.2, 1.25, 3.0, 0
end

local function apply_active_tool(S)
    local tool = TOOLS[S.tool_idx]
    eng.audio.play(S.sfx_spark, S.px, S.py, S.pz, S.pocket)
    if tool == "torch" then
        eng.sim.set_temp(6, 2, 4, 520.0, 0)
        eng.sim.ignite(6, 2, 4, 0)
        eng.physics.apply_impulse(S.lantern_body, 1.4, 0.3, -0.9, -4.05, 2.25, -1.5)
    elseif tool == "shock" then
        eng.sim.set_voltage(9, 1, 2, 36.0, 0)
    elseif tool == "acid" then
        eng.sim.fill_box(8, 2, 6, 9, 2, 7, "acid", 0)
    elseif tool == "blast" then
        if not S.arch_fractured then
            -- Sever both pillars of the ancient arch so the top lintel detaches as a 6-DOF voxel island!
            eng.physics.fracture_voxel(S.arch_ent, S.arch_vox, 0.35, 0.55, 0.35, 0.85)
            eng.physics.fracture_voxel(S.arch_ent, S.arch_vox, 2.45, 0.55, 0.35, 0.85)
            S.arch_fractured = true
            eng.audio.play(S.sfx_crack, -10.0, 1.2, -2.2, 0)
        end
        eng.physics.blast(0, -4.0, 1.2, -2.0, 6.0, 18.0)
    end
end

function update(dt)
    local S = game.state
    S.time = S.time + dt

    if eng.input.pressed("toggle_cam") then
        S.overlook = not S.overlook
    end
    if eng.input.pressed("switch_crew") then
        S.tool_idx = (S.tool_idx % #TOOLS) + 1
    end
    if eng.input.pressed("interact") then
        S.raining = not S.raining
        eng.audio.play(S.sfx_splash, S.px, S.py, S.pz, S.pocket)
    end
    if eng.input.pressed("fire") then
        apply_active_tool(S)
    end

    -- First-person movement + gravity/buoyancy + portal-traversing character controller
    local yaw, pitch, dx, dz = eng.camera.fps_steer(S.yaw, S.pitch, 5.4, dt)
    S.yaw, S.pitch = yaw, pitch

    S.vy = S.vy - 9.81 * dt
    if S.pocket == 0 then
        local wh, wen = eng.render.water_height(S.px, S.pz, 0)
        if wen and (S.py - 0.75) < wh then
            local sub = math.min((wh - (S.py - 0.75)) / 1.3, 1.2)
            S.vy = S.vy + 13.5 * sub * dt
            S.vy = S.vy * math.max(0.0, 1.0 - 3.0 * dt)
        end
    end
    if eng.input.pressed("jump") and S.vy > -1.5 and S.vy < 2.0 then
        S.vy = 4.8
    end

    local grounded = eng.physics.move_character(S.player_body, dx, S.vy * dt, dz, 0.38)
    if grounded and S.vy < 0.0 then
        S.vy = 0.0
    end
    S.px, S.py, S.pz = eng.scene.get_pos(S.player_ent)
    S.pocket = eng.scene.get_pocket(S.player_ent)

    -- Advance systemic chemistry, rain, Planck firelight & sapling growth
    if S.raining then
        eng.sim.rain(0.85, dt, 0)
        eng.scene.set_wetness(S.shore_ents[1], 1.0)
        eng.scene.set_wetness(S.shore_ents[2], 1.0)
    end
    eng.sim.step(dt, 0)

    local fires, fx, fy, fz = eng.sim.active_fires(0)
    eng.sim_ext.update_firelight(eng, S.fire_light, S.time, 0)
    if fires > 0 then
        eng.particles.set_pos(S.fire_emitter, fx, fy + 0.25, fz, 0)
        eng.particles.set_rate(S.fire_emitter, math.min(14 + fires * 6, 48))
    else
        eng.particles.set_rate(S.fire_emitter, 0)
    end

    for i = 1, #S.plants do
        local pl = S.plants[i]
        local info = eng.sim.get_plant(pl.id, 0)
        if info then
            local sc = eng.sim_ext.plant_scale_for_stage(info.stage, info.growth)
            eng.scene.set_scale(pl.ent, sc, sc, sc)
        end
    end

    S.sim_mesh_timer = S.sim_mesh_timer + dt
    if S.sim_mesh_timer >= 0.12 then
        S.sim_mesh_timer = 0.0
        eng.sim.build_mesh(true, 0)
    end

    -- Sync dynamic lantern light to swinging 6-DOF lantern entity
    local lx, ly, lz = eng.scene.get_pos(S.lantern_ent)
    eng.render.set_light(S.lantern_light, { pos = { lx, ly - 0.1, lz }, pocket = 0 })

    -- Scent-driven wildlife AI: avoid downwind smoke plumes, otherwise patrol riverbank meadow
    local smoke_scent = eng.sim.sample_scent(S.stag_x, 0.8, S.stag_z, 0)
    local vx = (smoke_scent > 0.08) and -1.6 or (math.cos(S.time * 0.45) * 0.75)
    local vz = (smoke_scent > 0.08) and  1.1 or (math.sin(S.time * 0.35) * 0.75)
    S.stag_x = eng.math.clamp(S.stag_x + vx * dt, -15.0, -4.8)
    S.stag_z = eng.math.clamp(S.stag_z + vz * dt, -4.0, 8.0)
    eng.scene.set_pos(S.stag_ent, S.stag_x, 0.32, S.stag_z)
    eng.scene.set_rot_deg(S.stag_ent, 0.0, math.deg(math.atan2(-vx, -vz)), 0.0)

    -- Update camera (first-person explorer or elevated valley overlook)
    if S.overlook and S.pocket == 0 then
        eng.camera.set(S.px - 4.0, S.py + 5.5, S.pz + 7.5, -24.0, 22.0, 0.0, 0)
    else
        eng.camera.set(S.px, S.py + 0.52, S.pz, math.deg(S.pitch), math.deg(S.yaw), 0.0, S.pocket)
    end
end

function draw()
    local S = game.state
    local fires = eng.sim.active_fires(0)
    local bio = eng.sim.get_bio(S.player_bio, 0)
    local core_t = bio and bio.core_temp_c or 37.0
    local wx = S.raining and "RAINING" or "CLEAR"
    local loc_tag = (S.pocket == S.mill_pocket) and (" | " .. eng.i18n.t("mill_hint")) or ""

    eng.ui.label(18, 16, eng.i18n.t("title") .. loc_tag, 1.0, 0.96, 0.82, 1.0)
    eng.ui.label(18, 40, string.format("Tool: %s | Weather: %s | Fires: %d | Core: %.1f C",
        string.upper(TOOLS[S.tool_idx]), wx, fires, core_t), 0.82, 0.92, 1.0, 0.95)
end
