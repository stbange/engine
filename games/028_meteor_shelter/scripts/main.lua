-- 028_meteor_shelter: Gather stone blocks & build overhead voxel roof tiles verified by eng.physics.raycast sky check
local S = game.state

local ROOF_SLOTS = {
    { 0.0,  0.0}, {-1.25,  0.0}, { 1.25,  0.0},
    { 0.0, -1.25}, { 0.0,  1.25}, {-1.25, -1.25},
    { 1.25, -1.25}, {-1.25,  1.25}, { 1.25,  1.25}
}

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.018 })
    eng.render.set_sky(0.12, 0.06, 0.14, 0.42, 0.18, 0.12)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.0, 1.75, 1.55}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.5, 0.0}, color = {2.2, 1.5, 0.8}, range = 26.0 })

    local seed = math.floor(eng.math.range(100, 99999))
    local ground_tex = eng.procgen.texture("cobble", seed, 64)
    local box_mesh = eng.asset.box(1, 1, 1)
    S.meteor_mesh = eng.asset.sphere(0.42, 10, 12)

    S.boulder_vox = eng.asset.voxel_ascii({
        "111\n171\n111",
        ".1.\n171\n.1."
    }, 3, 2, 3, 0.42)

    S.roof_vox = eng.asset.voxel_ascii({
        "777\n717\n777"
    }, 3, 1, 3, 0.40)

    local pillar_vox = eng.asset.voxel_ascii({
        "11\n11", "11\n11", "11\n11", "11\n11", "11\n11", "11\n11"
    }, 2, 6, 2, 0.42)

    S.sfx_mine = eng.audio.synth("square", 320, 0.08, 190)
    S.sfx_build = eng.audio.synth("triangle", 520, 0.09, 760)
    S.sfx_impact = eng.audio.synth("noise", 240, 0.20, 65)

    local floor = eng.scene.spawn("crater_floor")
    eng.scene.set_pos(floor, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor, 22.0, 0.5, 22.0)
    eng.scene.set_mesh(floor, box_mesh, { tex = ground_tex, color = {0.46, 0.40, 0.38, 1.0} })
    eng.physics.add_body(floor, { shape = "aabb", motion = "static", half_extents = {11.0, 0.25, 11.0} })

    -- 4 Shelter Support Corner Pillars
    local corners = {{-2.2, -2.2}, {2.2, -2.2}, {-2.2, 2.2}, {2.2, 2.2}}
    for i = 1, 4 do
        local pe = eng.scene.spawn("shelter_post_" .. i)
        eng.scene.set_pos(pe, corners[i][1] - 0.42, 0.0, corners[i][2] - 0.42)
        eng.scene.set_mesh(pe, pillar_vox, { cast_shadow = true })
    end

    -- 6 Harvestable Stone Boulders around clearing
    S.boulders = {}
    for i = 1, 6 do
        local ang = (i - 1) * (math.pi * 2.0 / 6.0)
        local bx = math.cos(ang) * 4.8
        local bz = math.sin(ang) * 4.8
        local be = eng.scene.spawn("stone_boulder_" .. i)
        eng.scene.set_pos(be, bx - 0.63, 0.0, bz - 0.63)
        eng.scene.set_mesh(be, S.boulder_vox, { cast_shadow = true })
        S.boulders[i] = { ent = be, x = bx, z = bz, intact = true }
    end

    S.px, S.pz = 0.0, 0.0
    S.player_ent = eng.scene.spawn("survivor_builder")
    eng.scene.set_pos(S.player_ent, S.px, 0.55, S.pz)
    eng.scene.set_scale(S.player_ent, 0.65, 1.1, 0.65)
    eng.scene.set_mesh(S.player_ent, box_mesh, { color = {0.3, 0.9, 1.0, 1.0}, cast_shadow = true })

    S.stone = 2
    S.stone_gathered = 0
    S.roofs = {}
    S.roofs_built = 0
    S.player_sheltered = false
    S.hp = 100
    S.elapsed = 0.0
    S.meteors = {}
    S.meteors_spawned = 0
    S.meteors_resolved = 0
    S.meteors_blocked = 0
    S.total_meteors = 8
    S.won = false

    eng.camera.look_at(0.0, 9.2, 10.4, 0.0, 1.2, 0.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.elapsed = S.elapsed + dt

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.px = eng.math.clamp(S.px + mx * 7.8 * dt, -7.5, 7.5)
    S.pz = eng.math.clamp(S.pz - my * 7.8 * dt, -7.5, 7.5)
    eng.scene.set_pos(S.player_ent, S.px, 0.55, S.pz)

    if eng.input.pressed("fire") or eng.input.pressed("interact") then
        -- 1. Try harvesting nearby stone boulder
        local mined = false
        for i = 1, #S.boulders do
            local b = S.boulders[i]
            if b.intact and eng.math.dist3(S.px, 0, S.pz, b.x, 0, b.z) < 1.85 then
                b.intact = false
                S.stone = S.stone + 3
                S.stone_gathered = S.stone_gathered + 3
                eng.audio.play(S.sfx_mine, b.x, 0.5, b.z, 0)
                eng.scene.despawn(b.ent)
                mined = true
                break
            end
        end

        -- 2. Try placing overhead voxel roof slab when near shelter
        if not mined and S.stone >= 1 and S.roofs_built < #ROOF_SLOTS and eng.math.dist3(S.px, 0, S.pz, 0, 0, 0) < 2.6 then
            S.stone = S.stone - 1
            S.roofs_built = S.roofs_built + 1
            local slot = ROOF_SLOTS[S.roofs_built]
            local re = eng.scene.spawn("voxel_roof_" .. S.roofs_built)
            eng.scene.set_pos(re, slot[1], 2.8, slot[2])
            local rv = eng.scene.spawn("voxel_roof_vis_" .. S.roofs_built)
            eng.scene.set_parent(rv, re)
            eng.scene.set_pos(rv, -0.60, -0.20, -0.60)
            eng.scene.set_mesh(rv, S.roof_vox, { cast_shadow = true })
            local rb = eng.physics.add_body(re, { shape = "aabb", motion = "static", half_extents = {0.58, 0.22, 0.58} })
            S.roofs[S.roofs_built] = { ent = re, vis = rv, body = rb }
            eng.audio.play(S.sfx_build, slot[1], 2.8, slot[2], 0)
        end
    end

    -- Real upward sky check via eng.physics.raycast (+Y)
    local sky_hit = eng.physics.raycast(0, S.px, 1.15, S.pz, 0.0, 1.0, 0.0, 12.0)
    S.player_sheltered = (sky_hit ~= nil)

    -- Spawn 3D meteor shower after initial gather window (t >= 2.1s)
    if S.elapsed >= 2.1 and S.meteors_spawned < S.total_meteors then
        local next_t = 2.1 + S.meteors_spawned * 0.26
        if S.elapsed >= next_t then
            S.meteors_spawned = S.meteors_spawned + 1
            local slot = ROOF_SLOTS[((S.meteors_spawned - 1) % 5) + 1]
            local me = eng.scene.spawn("meteor_" .. S.meteors_spawned)
            eng.scene.set_pos(me, slot[1], 12.5, slot[2])
            eng.scene.set_mesh(me, S.meteor_mesh, { color = {1.6, 0.45, 0.12, 1.0}, roughness = 0.3 })
            S.meteors[#S.meteors + 1] = { ent = me, x = slot[1], y = 12.5, z = slot[2], active = true }
        end
    end

    -- Step falling meteors & test downward raycast against overhead voxel roof colliders
    for i = 1, #S.meteors do
        local m = S.meteors[i]
        if m.active then
            local step_y = 16.5 * dt
            local hit = eng.physics.raycast(0, m.x, m.y, m.z, 0.0, -1.0, 0.0, step_y + 0.35)
            m.y = m.y - step_y
            eng.scene.set_pos(m.ent, m.x, m.y, m.z)

            if hit and hit.point[2] > 1.8 then
                m.active = false
                S.meteors_blocked = S.meteors_blocked + 1
                S.meteors_resolved = S.meteors_resolved + 1
                eng.audio.play(S.sfx_impact, m.x, 2.9, m.z, 0)
                eng.scene.despawn(m.ent)
            elseif m.y <= 0.35 then
                m.active = false
                S.meteors_resolved = S.meteors_resolved + 1
                if not S.player_sheltered and eng.math.dist3(S.px, 0, S.pz, m.x, 0, m.z) < 2.5 then
                    S.hp = math.max(0, S.hp - 35)
                end
                eng.audio.play(S.sfx_impact, m.x, 0.3, m.z, 0)
                eng.scene.despawn(m.ent)
            end
        end
    end

    if S.meteors_resolved >= S.total_meteors and S.hp > 0 and S.player_sheltered and S.meteors_blocked >= 4 then
        S.won = true
        eng.save.write("meteor_shelter_progress", "survived")
    end
end

function draw()
    local sky_txt = S.player_sheltered and "ROOFED" or "EXPOSED"
    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | STONE %d | ROOF %d/9 (%s) | BLOCKED %d/%d",
        eng.i18n.t("title"), S.stone, S.roofs_built, sky_txt, S.meteors_blocked, S.total_meteors), 1.0, {1.0, 0.85, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 220, S.hp / 100.0, "HP ")
end
