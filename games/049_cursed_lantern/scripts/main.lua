-- 049_cursed_lantern: Dark L-System Forest Survival with Voxel Lantern Radius & 4 Beacons
local S = game.state

local function build_lantern_mesh()
    local m = eng.asset.load_mesh("assets/shared/voxels/lantern.vox")
    if m ~= 0 then return m end
    -- Greedy-meshed 4x6x4 voxel lantern matching lantern.vox palette
    return eng.asset.voxel_ascii({
        "3333\n3773\n3773\n3333",
        ".77.\n7667\n7667\n.77.",
        ".77.\n7667\n7667\n.77.",
        ".77.\n7667\n7667\n.77.",
        "3333\n3333\n3333\n3333",
        "..3.\n.3.3\n..3.\n...."
    }, 4, 6, 4, 0.12)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.028 })
    eng.render.set_sky(0.02, 0.03, 0.08, 0.06, 0.08, 0.16)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {0.75, 0.85, 1.25}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 3.0, 0.0}, color = {2.4, 1.7, 0.8}, range = 16.0 })

    local seed = math.floor(eng.math.range(100, 700000))
    local moss_tex = eng.procgen.texture("grass", seed, 64)
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.5, 0.5, 0.08, 18)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.lantern_mesh = build_lantern_mesh()
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_oil = eng.audio.synth("triangle", 480, 0.12, 740)
    S.sfx_beacon = eng.audio.synth("sine", 340, 0.25, 860)
    S.sfx_repel = eng.audio.synth("noise", 260, 0.08, 420)

    local floor_e = eng.scene.spawn("forest_ground")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 38.0, 0.5, 38.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = moss_tex, color = {0.22, 0.34, 0.26, 1.0} })

    -- Procedural L-system dark forest scattered via Poisson disk
    local tree_a = eng.procgen.tree(seed + 11, 2, 3.6, 0.24)
    local tree_b = eng.procgen.tree(seed + 29, 2, 4.2, 0.26)
    local pts = eng.procgen.scatter_poisson(seed, 30.0, 30.0, 5.0, 24)
    for i = 1, #pts do
        local tx, tz = pts[i][1] - 15.0, pts[i][2] - 15.0
        if eng.math.dist3(tx, 0, tz, 0, 0, 0) > 3.2 then
            local te = eng.scene.spawn("cursed_tree_" .. i)
            eng.scene.set_pos(te, tx, 0.0, tz)
            eng.scene.set_mesh(te, (i % 2 == 0) and tree_a or tree_b, { color = {0.20, 0.36, 0.28, 1.0}, cast_shadow = true })
        end
    end

    -- 4 Unlit Stone Beacons + 4 Oil Flasks + 4 Shadow Wraiths
    local bcoords = { {-7.5, -7.5}, {7.5, -7.5}, {7.5, 7.5}, {-7.5, 7.5} }
    S.beacons = {}
    S.oils = {}
    S.wraiths = {}
    for i = 1, 4 do
        local bx, bz = bcoords[i][1], bcoords[i][2]
        local base = eng.scene.spawn("beacon_pillar_" .. i)
        eng.scene.set_pos(base, bx, 0.0, bz)
        eng.scene.set_scale(base, 0.85, 0.65, 0.85)
        eng.scene.set_mesh(base, S.pillar_mesh, { color = {0.48, 0.50, 0.56, 1.0} })

        local flame = eng.scene.spawn("beacon_gem_" .. i)
        eng.scene.set_pos(flame, bx, 1.85, bz)
        eng.scene.set_mesh(flame, S.crystal_mesh, { color = {0.28, 0.32, 0.42, 1.0} })
        S.beacons[i] = { x = bx, z = bz, gem = flame, lit = false }

        local ox, oz = bx * 0.52, bz * 0.52
        local oe = eng.scene.spawn("lantern_oil_" .. i)
        eng.scene.set_pos(oe, ox, 0.2, oz)
        eng.scene.set_scale(oe, 0.6, 0.6, 0.6)
        eng.scene.set_mesh(oe, S.lantern_mesh, { color = {1.0, 0.82, 0.28, 1.0} })
        S.oils[i] = { ent = oe, x = ox, z = oz, taken = false }

        local wx, wz = bx * 0.82, bz * 0.82
        local we = eng.scene.spawn("shadow_wraith_" .. i)
        eng.scene.set_pos(we, wx, 0.0, wz)
        eng.scene.set_mesh(we, S.box_mesh, { color = {0.26, 0.20, 0.48, 1.0} })
        eng.procgen.person(we, seed + 80 + i * 23)
        S.wraiths[i] = { ent = we, x = wx, z = wz, repel_cd = 0.0 }
    end

    -- Keeper + Held Voxel Lantern + Visible Light Radius Ring
    S.px, S.pz = 0.0, 0.0
    S.hero_ent = eng.scene.spawn("lantern_bearer")
    eng.scene.set_pos(S.hero_ent, S.px, 0.0, S.pz)
    eng.procgen.person(S.hero_ent, seed + 3)

    S.lantern_ent = eng.scene.spawn("voxel_lantern")
    eng.scene.set_parent(S.lantern_ent, S.hero_ent)
    eng.scene.set_pos(S.lantern_ent, 0.45, 0.95, -0.35)
    eng.scene.set_mesh(S.lantern_ent, S.lantern_mesh, { color = {1.0, 0.88, 0.35, 1.0} })

    S.aura_ent = eng.scene.spawn("lantern_radius_ring")
    eng.scene.set_pos(S.aura_ent, S.px, 0.04, S.pz)
    eng.scene.set_scale(S.aura_ent, 8.0, 0.4, 8.0)
    eng.scene.set_mesh(S.aura_ent, S.cyl_mesh, { color = {0.95, 0.72, 0.25, 1.0} })

    S.hp = 100
    S.fuel = 72.0
    S.lantern_radius = 6.5
    S.fuel_collected = 0
    S.wraiths_repelled = 0
    S.beacons_lit = 0
    S.won = false

    eng.camera.look_at(S.px, 9.5, S.pz + 9.5, S.px, 0.6, S.pz - 1.5, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    S.fuel = math.max(0.0, S.fuel - 4.8 * dt)
    S.lantern_radius = 2.2 + (S.fuel / 100.0) * 6.2

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.px = eng.math.clamp(S.px + mx * 8.4 * dt, -14.0, 14.0)
        S.pz = eng.math.clamp(S.pz - my * 8.4 * dt, -14.0, 14.0)
        eng.scene.set_pos(S.hero_ent, S.px, 0.0, S.pz)
    end

    eng.scene.set_pos(S.aura_ent, S.px, 0.04, S.pz)
    local diam = S.lantern_radius * 2.0
    eng.scene.set_scale(S.aura_ent, diam, 0.4, diam)

    -- Collect Lantern Oil flasks to expand light radius
    for i = 1, #S.oils do
        local o = S.oils[i]
        if not o.taken and eng.math.dist3(S.px, 0, S.pz, o.x, 0, o.z) < 2.0 then
            o.taken = true
            S.fuel = math.min(100.0, S.fuel + 36.0)
            S.fuel_collected = S.fuel_collected + 1
            eng.audio.play(S.sfx_oil, o.x, 0.8, o.z, 0)
            eng.scene.despawn(o.ent)
        end
    end

    -- Shadow Wraiths stalk in darkness, but are repelled by Lantern Light Radius!
    for i = 1, #S.wraiths do
        local w = S.wraiths[i]
        w.repel_cd = math.max(0.0, w.repel_cd - dt)
        local dx, dz = S.px - w.x, S.pz - w.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 0.05 then
            if d < S.lantern_radius and S.fuel > 5.0 then
                w.x = eng.math.clamp(w.x - (dx / d) * 6.8 * dt, -15.0, 15.0)
                w.z = eng.math.clamp(w.z - (dz / d) * 6.8 * dt, -15.0, 15.0)
                if w.repel_cd <= 0.0 then
                    w.repel_cd = 0.6
                    S.wraiths_repelled = S.wraiths_repelled + 1
                    eng.audio.play(S.sfx_repel, w.x, 1.0, w.z, 0)
                end
            else
                w.x = w.x + (dx / d) * 3.5 * dt
                w.z = w.z + (dz / d) * 3.5 * dt
                if d < 1.3 then S.hp = math.max(10, S.hp - 18.0 * dt) end
            end
            eng.scene.set_pos(w.ent, w.x, 0.0, w.z)
        end
    end

    -- Ignite the 4 Ancient Forest Beacons (spawns dynamic point light per beacon!)
    for i = 1, #S.beacons do
        local b = S.beacons[i]
        if not b.lit and S.fuel >= 15.0 and eng.math.dist3(S.px, 0, S.pz, b.x, 0, b.z) < 2.4 then
            b.lit = true
            S.fuel = math.max(10.0, S.fuel - 10.0)
            S.beacons_lit = S.beacons_lit + 1
            eng.scene.set_mesh(b.gem, S.crystal_mesh, { color = {1.0, 0.86, 0.25, 1.0} })
            eng.render.add_light({ type = "point", pos = {b.x, 2.6, b.z}, color = {2.8, 1.9, 0.75}, range = 16.0 })
            eng.audio.play(S.sfx_beacon, b.x, 2.0, b.z, 0)
        end
    end

    if S.beacons_lit >= 4 then
        S.won = true
        eng.save.write("cursed_lantern", "dawn_restored")
    end

    eng.camera.look_at(S.px, 9.5, S.pz + 9.5, S.px, 0.6, S.pz - 1.5, 0)
end

function draw()
    for i = 1, #S.wraiths do
        local w = S.wraiths[i]
        eng.render.draw_sprite(w.x, 1.95, w.z, 0.45, 0.45, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | BEACONS " .. S.beacons_lit .. "/4 | REPELLED " .. S.wraiths_repelled, 1.0, {1.0, 0.85, 0.42, 1.0})
    eng.ui.bar(x, y + 24, 200, S.fuel / 100.0, "FUEL ")
end
