-- 022_magma_riser: Vertical platforming climb up a procedural cellular cave outrunning rising magma
local S = game.state

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.024 })
    eng.render.set_sky(0.14, 0.04, 0.03, 0.45, 0.14, 0.05)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.5, 1.35, 1.25}, shadow = true })
    eng.render.add_light({ type = "point", pos = {12.0, 3.5, 12.0}, color = {2.8, 1.2, 0.35}, range = 34.0 })

    local seed = math.floor(eng.math.range(100, 99999))
    local cave_tex = eng.procgen.texture("cobble", seed, 64)
    local lava_tex = eng.procgen.texture("lava_cracks", seed + 17, 64)

    -- Procedural cellular cave enclosure
    local d = eng.procgen.dungeon(12, 12, seed, "cave", 2.0, 18.0)
    S.cave_solvable = d.solvable
    local cave_ent = eng.scene.spawn("volcanic_cave")
    eng.scene.set_mesh(cave_ent, d.mesh_id, { tex = cave_tex, color = {0.55, 0.42, 0.38, 1.0}, roughness = 0.9 })

    local box_mesh = eng.asset.box(1, 1, 1)
    local crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    local ledge_vox = eng.asset.voxel_ascii({
        "3333\n3333\n3333\n3333",
        "1111\n1771\n1771\n1111"
    }, 4, 2, 4, 0.45)

    S.sfx_jump = eng.audio.synth("triangle", 280, 0.12, 540)
    S.sfx_gem = eng.audio.synth("sine", 660, 0.15, 1020)

    -- Rising glowing magma plane
    S.magma_y = -1.4
    S.magma_ent = eng.scene.spawn("rising_magma")
    eng.scene.set_pos(S.magma_ent, 12.0, S.magma_y, 12.0)
    eng.scene.set_scale(S.magma_ent, 26.0, 0.4, 26.0)
    eng.scene.set_mesh(S.magma_ent, box_mesh, { tex = lava_tex, color = {1.8, 0.65, 0.15, 1.0}, roughness = 0.3 })

    -- Spiral voxel ledges ascending from y=0.6m to y=10.4m
    S.ledges = {}
    S.gems = {}
    local cx, cz = 12.0, 12.0
    for i = 1, 8 do
        local ang = (i - 1) * 0.72
        local r = 2.6
        local lx = cx + math.sin(ang) * r
        local lz = cz + math.cos(ang) * r
        local ly = 0.6 + (i - 1) * 1.40

        local le = eng.scene.spawn("voxel_ledge_" .. i)
        eng.scene.set_pos(le, lx, ly - 0.45, lz)
        local lv = eng.scene.spawn("voxel_ledge_vis_" .. i)
        eng.scene.set_parent(lv, le)
        eng.scene.set_pos(lv, -0.9, -0.45, -0.9)
        eng.scene.set_mesh(lv, ledge_vox, { cast_shadow = true })
        eng.physics.add_body(le, { shape = "aabb", motion = "static", half_extents = {0.95, 0.45, 0.95} })
        S.ledges[i] = { x = lx, top_y = ly, z = lz, hx = 1.05, hz = 1.05 }

        if i % 2 == 0 and i < 8 then
            local ge = eng.scene.spawn("vent_gem_" .. i)
            eng.scene.set_pos(ge, lx, ly + 0.35, lz)
            eng.scene.set_scale(ge, 0.45, 0.45, 0.45)
            eng.scene.set_mesh(ge, crystal_mesh, { color = {0.3, 0.95, 1.0, 1.0} })
            S.gems[#S.gems + 1] = { ent = ge, x = lx, y = ly + 0.35, z = lz, taken = false }
        end
    end

    local top = S.ledges[8]
    S.goal_x, S.goal_y, S.goal_z = top.x, top.top_y + 0.2, top.z
    local beacon = eng.scene.spawn("summit_crystal")
    eng.scene.set_pos(beacon, S.goal_x, top.top_y, S.goal_z)
    eng.scene.set_mesh(beacon, crystal_mesh, { color = {1.0, 0.9, 0.25, 1.0} })

    -- Climber avatar starts securely on Ledge #1
    local start = S.ledges[1]
    S.px, S.py, S.pz = start.x, start.top_y + 0.02, start.z
    S.vy = 0.0
    S.grounded = true
    S.current_ledge = 1
    S.max_alt = S.py
    S.gems_collected = 0
    S.burns = 0
    S.won = false

    S.player_ent = eng.scene.spawn("climber_marker")
    eng.scene.set_pos(S.player_ent, S.px, S.py + 0.35, S.pz)
    eng.scene.set_scale(S.player_ent, 0.45, 0.7, 0.45)
    eng.scene.set_mesh(S.player_ent, box_mesh, { color = {0.25, 0.85, 1.0, 1.0} })

    eng.camera.look_at(12.0, 3.6, 19.2, 12.0, 3.2, 12.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    -- Rising glowing magma
    S.magma_y = S.magma_y + 0.95 * dt
    eng.scene.set_pos(S.magma_ent, 12.0, S.magma_y, 12.0)

    -- 3D horizontal movement
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.px = eng.math.clamp(S.px + mx * 6.8 * dt, 6.0, 18.0)
    S.pz = eng.math.clamp(S.pz - my * 6.8 * dt, 6.0, 18.0)

    if (eng.input.pressed("jump") or eng.input.down("jump")) and S.grounded then
        S.vy = 9.2
        S.grounded = false
        eng.audio.play(S.sfx_jump, S.px, S.py, S.pz, 0)
    end

    local prev_y = S.py
    S.vy = S.vy - 18.0 * dt
    S.py = S.py + S.vy * dt
    S.grounded = false

    -- Ledge landing & mantle check
    for i = 1, #S.ledges do
        local ld = S.ledges[i]
        if math.abs(S.px - ld.x) <= ld.hx and math.abs(S.pz - ld.z) <= ld.hz then
            if S.vy <= 0.0 and prev_y >= ld.top_y - 0.32 and S.py <= ld.top_y + 0.06 then
                S.py = ld.top_y
                S.vy = 0.0
                S.grounded = true
                if i > S.current_ledge then S.current_ledge = i end
            end
        end
    end

    -- Magma thermal updraft bounce if touched
    if S.py <= S.magma_y + 0.25 then
        S.burns = S.burns + 1
        S.py = S.magma_y + 0.35
        S.vy = 9.2
    end

    if S.py > S.max_alt then S.max_alt = S.py end
    eng.scene.set_pos(S.player_ent, S.px, S.py + 0.35, S.pz)

    for i = 1, #S.gems do
        local g = S.gems[i]
        if not g.taken and eng.math.dist3(S.px, S.py + 0.35, S.pz, g.x, g.y, g.z) < 1.35 then
            g.taken = true
            S.gems_collected = S.gems_collected + 1
            eng.audio.play(S.sfx_gem, g.x, g.y, g.z, 0)
            eng.scene.despawn(g.ent)
        end
    end

    if S.py >= S.ledges[8].top_y - 0.05 and eng.math.dist3(S.px, S.py, S.pz, S.goal_x, S.ledges[8].top_y, S.goal_z) < 1.35 and S.py > S.magma_y + 0.5 then
        S.won = true
        eng.save.write("magma_riser_progress", "summit")
    end

    eng.camera.look_at(12.0, S.py + 3.2, 19.5, S.px, S.py + 1.0, S.pz, 0)
end

function draw()
    local lead = math.max(0.0, S.py - S.magma_y)
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | ALT %.1fm / 10.4m | MAGMA +%.1fm | GEMS %d",
        eng.i18n.t("title"), S.py, S.magma_y, S.gems_collected), 1.0, {1.0, 0.78, 0.35, 1.0})
    eng.ui.bar(x, y + 26, 220, eng.math.clamp(lead / 6.0, 0.0, 1.0), "LEAD ")
end
