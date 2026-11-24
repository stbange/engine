-- 002_sky_islands_vox: 3-Stage Voxel Survival + Bigger-on-the-Inside Workshop Tent
local S = game.state

local ARCHETYPES = { "quadruped", "avian", "biped" }

local function clear_stage_entities()
    if S.stage_ents then
        for i = 1, #S.stage_ents do eng.scene.despawn(S.stage_ents[i]) end
    end
    S.stage_ents = {}
    S.crystals = {}
    S.wildlife = {}
end

local function spawn_voxel_island(name, x, y, z, vox_mesh)
    local e = eng.scene.spawn(name)
    eng.scene.set_pocket(e, 0)
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_mesh(e, vox_mesh, { cast_shadow = true, roughness = 0.85 })
    S.stage_ents[#S.stage_ents + 1] = e
    return e
end

local function build_stage(stage_idx)
    clear_stage_entities()
    S.stage = stage_idx
    S.harvested_this_stage = 0
    S.stage_goal = 3
    S.upgraded_this_stage = false

    local seed_base = math.floor(eng.math.range(200, 800000)) + stage_idx * 257

    -- 3 satellite floating voxel islands around the central island
    local offsets = {
        { -7.5, 0.2 * stage_idx, -2.0 },
        {  7.5, 0.3 * stage_idx, -2.0 },
        {  0.0, 0.25 * stage_idx, 7.0 }
    }
    for i = 1, 3 do
        local ox, oy, oz = offsets[i][1], offsets[i][2], offsets[i][3]
        spawn_voxel_island("sky_isle_" .. tostring(i), ox - 2.4, oy - 1.6, oz - 2.4, S.sub_island_vox)

        -- Sky crystal node with raycast hitbox + proximity harvest
        local ce = eng.scene.spawn("sky_crystal_" .. tostring(i))
        eng.scene.set_pocket(ce, 0)
        eng.scene.set_pos(ce, ox, oy + 0.2, oz)
        eng.scene.set_mesh(ce, S.crystal_mesh, { color = {0.3 + 0.2 * stage_idx, 0.85, 1.0, 1.0}, roughness = 0.2 })
        local bid = eng.physics.add_body(ce, { shape = "aabb", motion = "kinematic", pocket = 0, half_extents = {0.45, 0.7, 0.45} })
        S.stage_ents[#S.stage_ents + 1] = ce
        S.crystals[#S.crystals + 1] = { ent = ce, body = bid, x = ox, y = oy + 0.2, z = oz, active = true }

        -- Procedural IK-animated island wildlife
        local we = eng.scene.spawn("island_fauna_" .. tostring(i))
        eng.scene.set_pocket(we, 0)
        local wx, wz = ox + 1.1, oz + 0.9
        eng.scene.set_pos(we, wx, oy, wz)
        local arch = ARCHETYPES[((stage_idx + i - 2) % #ARCHETYPES) + 1]
        eng.procgen.animal(we, seed_base + i * 31, arch)
        S.stage_ents[#S.stage_ents + 1] = we
        S.wildlife[#S.wildlife + 1] = { ent = we, cx = ox, cy = oy, cz = oz, phase = i * 2.1 }
    end
end

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 320, dither = true, color_bits = 6, fog_density = 0.012 })
    eng.render.set_sky(0.18, 0.48, 0.86, 0.72, 0.86, 0.96)
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.35, -1.0, -0.45}, color = {2.1, 2.0, 1.85}, shadow = true })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_mine = eng.audio.synth("triangle", 640, 0.14, 980)
    S.sfx_forge = eng.audio.synth("square", 330, 0.22, 660)
    S.sfx_jump = eng.audio.synth("sine", 260, 0.10, 420)

    -- Greedy-meshed AO voxel chunks for central & satellite floating islands
    S.hub_island_vox = eng.asset.voxel_ascii({
        "........\n..1111..\n.111111.\n.111111.\n.111111.\n.111111.\n..1111..\n........",
        "..3333..\n.333333.\n33311333\n33111133\n33111133\n33311333\n.333333.\n..3333..",
        ".222222.\n22222222\n22266222\n22666622\n22666622\n22266222\n22222222\n.222222."
    }, 8, 3, 8, 2.0)

    S.sub_island_vox = eng.asset.voxel_ascii({
        "......\n..11..\n.1111.\n.1111.\n..11..\n......",
        ".2222.\n223322\n233332\n233332\n223322\n.2222."
    }, 6, 2, 6, 0.8)

    local hub = eng.scene.spawn("central_sky_island")
    eng.scene.set_pocket(hub, 0)
    eng.scene.set_pos(hub, -8.0, -6.0, -10.0)
    eng.scene.set_mesh(hub, S.hub_island_vox, { cast_shadow = true, roughness = 0.88 })

    -- Bigger-on-the-Inside Workshop Tent: 3.6m exterior -> 22x8x26m interior pocket!
    S.tent = eng.space.create_pocket_building(eng, {
        exterior_pos = {0.0, 0.0, -7.0},
        exterior_size = {3.6, 3.2, 3.6},
        interior_size = {22.0, 8.0, 26.0},
        door_size = {1.4, 2.2},
        pocket = "tent_workshop",
        exterior_color = {0.78, 0.42, 0.20, 1.0},
        interior_color = {0.36, 0.30, 0.24, 1.0}
    })
    eng.render.add_light({
        type = "point", pocket = "tent_workshop",
        pos = {0.0, 5.5, 0.0}, color = {2.8, 2.2, 1.5}, range = 34.0
    })

    -- Workshop interior forge & storage props
    local anvil = eng.scene.spawn("workshop_forge")
    eng.scene.set_pocket(anvil, S.tent.pocket_id)
    eng.scene.set_pos(anvil, 0.0, 0.0, 2.0)
    eng.scene.set_scale(anvil, 1.6, 1.2, 1.2)
    eng.scene.set_mesh(anvil, S.chest_mesh, { color = {0.95, 0.72, 0.25, 1.0} })

    for i = -1, 1, 2 do
        local rack = eng.scene.spawn("workshop_crate_" .. tostring(i))
        eng.scene.set_pocket(rack, S.tent.pocket_id)
        eng.scene.set_pos(rack, i * 4.5, 0.0, 0.0)
        eng.scene.set_mesh(rack, S.crate_mesh, { color = {0.65, 0.48, 0.30, 1.0} })
    end

    S.pocket = 0
    S.px, S.py, S.pz = 0.0, 1.2, 2.5
    S.yaw, S.pitch = 0.0, 0.0
    S.vy = 0.0
    S.stamina = 100.0
    S.gear_tier = 0
    S.total_crystals = 0
    S.tent_visits = 0
    S.won = false
    S.time = 0.0

    eng.input.set_mouse_lock(true)
    build_stage(1)
    eng.camera.set(S.px, S.py + 0.4, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
    eng.mod.emit("post_init")
end

local function try_harvest_crystal()
    for i = 1, #S.crystals do
        local c = S.crystals[i]
        if c.active and S.pocket == 0 then
            local dx, dz = c.x - S.px, c.z - S.pz
            local d = math.sqrt(dx * dx + dz * dz)
            local hit_ok = (d < 2.3)
            if not hit_ok and d < 12.0 and d > 0.01 then
                local h = eng.physics.raycast(0, S.px, 0.8, S.pz, dx / d, 0.0, dz / d, 12.0)
                if h and h.entity == c.ent then hit_ok = true end
            end
            if hit_ok then
                c.active = false
                eng.scene.despawn(c.ent)
                S.harvested_this_stage = S.harvested_this_stage + 1
                S.total_crystals = S.total_crystals + 1
                eng.audio.play(S.sfx_mine, c.x, c.y, c.z, 0)
                return
            end
        end
    end
end

function update(dt)
    if S.won then return end
    S.time = S.time + dt

    -- Animate roaming IK island wildlife
    for i = 1, #S.wildlife do
        local w = S.wildlife[i]
        local ang = S.time * 1.4 + w.phase
        eng.scene.set_pos(w.ent, w.cx + math.cos(ang) * 1.2, w.cy, w.cz + math.sin(ang) * 1.2)
        eng.scene.set_rot_deg(w.ent, 0.0, math.deg(-ang), 0.0)
    end

    local prev_x, prev_y, prev_z = S.px, S.py, S.pz
    local spd = 7.5 + S.gear_tier * 1.5
    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw or 0.0, S.pitch or 0.0, spd, dt)
    S.px = S.px + dx
    S.pz = S.pz + dz

    if eng.input.pressed("jump") and S.py <= 1.25 then
        S.vy = 5.2
        eng.audio.play(S.sfx_jump, S.px, S.py, S.pz, S.pocket)
    end
    S.py = S.py + S.vy * dt
    if S.py > 1.2 then
        S.vy = S.vy - 14.0 * dt
    else
        S.py = 1.2
        S.vy = 0.0
    end

    -- Check seamless portal threshold crossing between Archipelago (0) and Workshop Tent
    local dst_pk, wx, wy, wz = eng.portal.check_crossing(S.pocket, prev_x, prev_y, prev_z, S.px, S.py, S.pz)
    if dst_pk ~= nil then
        S.pocket = dst_pk
        S.px, S.py, S.pz = wx, 1.2, wz
        if S.pocket == S.tent.pocket_id then
            S.tent_visits = S.tent_visits + 1
        end
    end

    if eng.input.pressed("fire") or eng.input.down("fire") or eng.input.pressed("interact") then
        try_harvest_crystal()
    end
    -- Also allow walk-over crystal pickup when close
    for i = 1, #S.crystals do
        local c = S.crystals[i]
        if c.active and S.pocket == 0 and eng.math.dist3(S.px, 0, S.pz, c.x, 0, c.z) < 1.8 then
            c.active = false
            eng.scene.despawn(c.ent)
            S.harvested_this_stage = S.harvested_this_stage + 1
            S.total_crystals = S.total_crystals + 1
            eng.audio.play(S.sfx_mine, c.x, c.y, c.z, 0)
        end
    end

    -- Inside the Bigger-on-the-Inside Workshop Tent: forge upgrade at workbench (0, 0, 2)
    if S.pocket == S.tent.pocket_id and S.harvested_this_stage >= S.stage_goal and not S.upgraded_this_stage then
        if eng.math.dist3(S.px, 0, S.pz, 0.0, 0, 2.0) < 3.0 or eng.input.pressed("interact") then
            S.upgraded_this_stage = true
            S.gear_tier = S.stage
            S.stamina = 100.0
            eng.audio.play(S.sfx_forge, 0.0, 1.0, 2.0, S.tent.pocket_id)
            if S.stage < 3 then
                eng.save.write("sky_islands_progress", "stage_" .. tostring(S.stage + 1))
                build_stage(S.stage + 1)
            else
                S.won = true
                eng.save.write("sky_islands_progress", "clear")
            end
        end
    end

    eng.camera.set(S.px, S.py + 0.4, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
end

function draw()
    if S.pocket == 0 then
        for i = 1, #S.crystals do
            local c = S.crystals[i]
            if c.active then eng.render.draw_sprite(c.x, c.y + 1.5, c.z, 0.6, 0.6, S.orb_tex) end
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | STAGE " .. S.stage .. "/3 | CRYSTALS " .. S.total_crystals .. " | GEAR T" .. S.gear_tier, 1.0, {0.95, 0.95, 0.6, 1.0})
    eng.ui.bar(x, y + 26, 200, S.harvested_this_stage / S.stage_goal, "FORGE ")
end
