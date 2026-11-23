-- 080_disc_golf_island: Aerodynamic Gliding Frisbees (Lift & Fade Curve) through Procedural Tree Fairways
local S = game.state

local HOLES = {
    { tee = {0.0, 1.25, 6.0}, basket = { 0.0, 0.0, -10.0}, guard_trees = { {0.0, -2.0}, {-2.6, -5.5}, {2.8, -6.0} } },
    { tee = {0.0, 1.25, 6.0}, basket = {-1.2, 0.0, -11.0}, guard_trees = { {-0.4, -2.5}, {2.4, -4.5}, {-3.2, -6.5} } },
    { tee = {0.0, 1.25, 6.0}, basket = { 1.2, 0.0, -11.5}, guard_trees = { {0.4, -2.8}, {-2.4, -5.0}, {3.2, -7.0} } }
}

local function clear_hole_props()
    if S.props then
        for i = 1, #S.props do eng.scene.despawn(S.props[i]) end
    end
    S.props = {}
    S.trunks = {}
end

local function build_hole(idx)
    clear_hole_props()
    S.hole = idx
    local h = HOLES[idx]

    -- Spawn guardian fairway trees (`eng.procgen.tree`) + Poisson perimeter pines
    for i = 1, #h.guard_trees do
        local tx, tz = h.guard_trees[i][1], h.guard_trees[i][2]
        local te = eng.scene.spawn("fairway_tree_" .. tostring(i))
        eng.scene.set_pos(te, tx, 0.0, tz)
        eng.scene.set_mesh(te, S.tree_meshes[((i + idx) % #S.tree_meshes) + 1], { color = {0.24, 0.68, 0.30, 1.0}, cast_shadow = true })
        S.props[#S.props + 1] = te
        S.trunks[#S.trunks + 1] = { x = tx, z = tz, r = 0.38 }
    end

    local pts = eng.procgen.scatter_poisson(100 + idx * 37, 16.0, 16.0, 3.6, 18)
    for i = 1, #pts do
        local px = pts[i][1] - 8.0
        local pz = pts[i][2] - 11.0
        if math.abs(px) > 4.2 then
            local pe = eng.scene.spawn("island_pine_" .. tostring(i))
            eng.scene.set_pos(pe, px, 0.0, pz)
            eng.scene.set_mesh(pe, S.tree_meshes[(i % #S.tree_meshes) + 1], { color = {0.20, 0.60, 0.28, 1.0}, cast_shadow = true })
            S.props[#S.props + 1] = pe
        end
    end

    -- 3D Disc Golf Chain Basket (Center pole + Yellow top band + Hanging Chains + Basket Tray)
    local bx, bz = h.basket[1], h.basket[3]
    local pole = eng.scene.spawn("basket_pole")
    eng.scene.set_pos(pole, bx, 0.85, bz)
    eng.scene.set_mesh(pole, S.pole_mesh, { color = {0.72, 0.76, 0.80, 1.0} })
    S.props[#S.props + 1] = pole

    local tray = eng.scene.spawn("basket_tray")
    eng.scene.set_pos(tray, bx, 0.72, bz)
    eng.scene.set_mesh(tray, S.tray_mesh, { color = {0.82, 0.85, 0.90, 1.0}, cast_shadow = true })
    S.props[#S.props + 1] = tray

    local chains = eng.scene.spawn("basket_chains")
    eng.scene.set_pos(chains, bx, 1.18, bz)
    eng.scene.set_mesh(chains, S.chain_mesh, { color = {0.86, 0.88, 0.92, 1.0}, metallic = 0.85, roughness = 0.25 })
    S.props[#S.props + 1] = chains

    local band = eng.scene.spawn("basket_band")
    eng.scene.set_pos(band, bx, 1.54, bz)
    eng.scene.set_mesh(band, S.band_mesh, { color = {1.0, 0.84, 0.12, 1.0}, cast_shadow = true })
    S.props[#S.props + 1] = band

    -- Reset Frisbee at Tee Pad
    if S.disc_ent then eng.scene.despawn(S.disc_ent) end
    S.flying = false
    S.dx, S.dy, S.dz = h.tee[1], h.tee[2], h.tee[3]
    S.aim_yaw = 0.0
    S.hyzer = -1.0
    S.disc_ent = eng.scene.spawn("gliding_frisbee")
    eng.scene.set_pos(S.disc_ent, S.dx, S.dy, S.dz)
    eng.scene.set_mesh(S.disc_ent, S.disc_mesh, { color = {1.0, 0.28, 0.52, 1.0}, roughness = 0.25, cast_shadow = true })

    eng.camera.look_at(0.0, 3.6, 10.2, bx * 0.5, 1.0, -6.0, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.20, 0.52, 0.88, 0.72, 0.88, 0.96)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.2, 2.1, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, -2.0}, color = {1.4, 1.5, 1.3}, range = 28.0 })

    local seed = math.floor(eng.math.range(10, 50000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.disc_mesh = eng.asset.cylinder(0.24, 0.19, 0.05, 18)
    S.pole_mesh = eng.asset.cylinder(0.05, 0.05, 1.70, 10)
    S.tray_mesh = eng.asset.cylinder(0.52, 0.44, 0.22, 16)
    S.chain_mesh = eng.asset.cylinder(0.38, 0.28, 0.68, 14)
    S.band_mesh = eng.asset.cylinder(0.46, 0.46, 0.12, 16)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.grass_tex = eng.procgen.texture("grass", seed, 64)
    S.water_tex = eng.procgen.texture("water_caustics", seed + 17, 64)
    S.stone_tex = eng.procgen.texture("cobble", seed + 31, 64)

    S.tree_meshes = {
        eng.procgen.tree(seed + 3, 2, 4.2, 0.24),
        eng.procgen.tree(seed + 11, 2, 4.8, 0.26),
        eng.procgen.tree(seed + 23, 2, 3.8, 0.22)
    }

    S.sfx_throw = eng.audio.synth("triangle", 280, 0.08, 460)
    S.sfx_tree = eng.audio.synth("square", 210, 0.08, 120)
    S.sfx_chains = eng.audio.synth("noise", 820, 0.18, 380)

    -- Surrounding Ocean + Emerald Fairway Island + Concrete Tee Pad
    local ocean = eng.scene.spawn("island_ocean")
    eng.scene.set_pos(ocean, 0.0, -0.55, -3.0)
    eng.scene.set_scale(ocean, 60.0, 0.4, 60.0)
    eng.scene.set_mesh(ocean, S.box_mesh, { tex = S.water_tex, roughness = 0.08 })

    local island = eng.scene.spawn("fairway_island")
    eng.scene.set_pos(island, 0.0, -0.25, -3.0)
    eng.scene.set_scale(island, 18.0, 0.5, 24.0)
    eng.scene.set_mesh(island, S.box_mesh, { tex = S.grass_tex, roughness = 0.85 })
    eng.physics.add_body(island, { shape = "aabb", motion = "static", half_extents = {9.0, 0.25, 12.0} })

    local tee = eng.scene.spawn("tee_pad")
    eng.scene.set_pos(tee, 0.0, 0.02, 6.0)
    eng.scene.set_scale(tee, 1.6, 0.05, 2.4)
    eng.scene.set_mesh(tee, S.box_mesh, { tex = S.stone_tex })

    S.throws = 0
    S.chain_hits = 0
    S.glide_ticks = 0
    S.score = 0
    S.spin_yaw = 0.0
    S.won = false

    build_hole(1)
    eng.mod.emit("post_init")
end

function throw_disc(spd_override)
    if S.flying or S.won then return end
    S.flying = true
    S.throws = S.throws + 1
    local spd = spd_override or 18.8
    local rad = math.rad(S.aim_yaw)
    S.vx = -math.sin(rad) * spd
    S.vy = 0.28
    S.vz = -math.cos(rad) * spd
    eng.audio.play(S.sfx_throw, S.dx, S.dy, S.dz, 0)
end

function update(dt)
    if S.won then return end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local h = HOLES[S.hole]

    if not S.flying then
        S.aim_yaw = eng.math.clamp(S.aim_yaw - mx * 75.0 * dt, -45.0, 45.0)
        S.hyzer = eng.math.clamp(S.hyzer + my * 2.2 * dt, -1.5, 1.5)
        eng.scene.set_rot_deg(S.disc_ent, 4.0, S.aim_yaw, S.hyzer * 22.0)

        if eng.input.pressed("fire") or eng.input.pressed("jump") then
            throw_disc()
        end
        return
    end

    -- Aerodynamic Frisbee Lift + Gyroscopic Hyzer/Fade Lateral Curve!
    local hspd = math.sqrt(S.vx * S.vx + S.vz * S.vz)
    local lift_ay = math.min(9.45, hspd * 0.525)
    S.vy = S.vy + (-9.81 + lift_ay) * dt
    S.glide_ticks = S.glide_ticks + 1

    -- Fade acceleration increases gently as disc slows (classic low-speed fade!)
    local fade_mult = (hspd < 14.0) and 6.2 or 5.2
    S.vx = S.vx + S.hyzer * fade_mult * dt
    S.vx = S.vx * (1.0 - 0.14 * dt)
    S.vz = S.vz * (1.0 - 0.14 * dt)

    S.dx = S.dx + S.vx * dt
    S.dy = S.dy + S.vy * dt
    S.dz = S.dz + S.vz * dt

    S.spin_yaw = (S.spin_yaw + 720.0 * dt) % 360.0
    eng.scene.set_pos(S.disc_ent, S.dx, S.dy, S.dz)
    eng.scene.set_rot_deg(S.disc_ent, 3.0, S.spin_yaw, S.hyzer * 20.0)

    -- Tree trunk deflection check
    for i = 1, #S.trunks do
        local tr = S.trunks[i]
        if S.dy < 3.6 and eng.math.dist3(S.dx, 0, S.dz, tr.x, 0, tr.z) < tr.r + 0.22 then
            eng.audio.play(S.sfx_tree, S.dx, S.dy, S.dz, 0)
            S.flying = false
            -- Drop to fairway lie below tree
            S.dy = 1.15
            S.dz = S.dz + 0.65
            eng.scene.set_pos(S.disc_ent, S.dx, S.dy, S.dz)
            return
        end
    end

    -- Chain Basket Capture Check!
    local bx, bz = h.basket[1], h.basket[3]
    if S.dy >= 0.55 and S.dy <= 1.75 and eng.math.dist3(S.dx, 0, S.dz, bx, 0, bz) < 0.68 then
        S.chain_hits = S.chain_hits + 1
        S.score = S.score + 300
        eng.audio.play(S.sfx_chains, bx, 1.2, bz, 0)
        if S.hole < 3 then
            eng.save.write("disc_golf_hole", tostring(S.hole + 1))
            build_hole(S.hole + 1)
            return
        else
            S.won = true
            eng.save.write("disc_golf_hole", "clear")
            return
        end
    end

    -- Ground settle / OB water reset
    if S.dy <= 0.12 or math.abs(S.dx) > 10.5 or S.dz < -15.0 then
        S.flying = false
        if math.abs(S.dx) > 8.8 or S.dz < -14.2 then
            S.dx, S.dy, S.dz = h.tee[1], h.tee[2], h.tee[3]
        else
            S.dy = 1.15
        end
        eng.scene.set_pos(S.disc_ent, S.dx, S.dy, S.dz)
        return
    end

    eng.camera.look_at(S.dx * 0.4, 3.2, math.max(-6.5, S.dz + 4.2), bx, 1.1, bz, 0)
end

function draw()
    if not S.flying and not S.won then
        local rad = math.rad(S.aim_yaw)
        eng.render.draw_sprite(S.dx - math.sin(rad) * 1.5, S.dy, S.dz - math.cos(rad) * 1.5, 0.26, 0.26, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | HOLE " .. S.hole .. "/3 | THROWS " .. S.throws .. " | SCORE " .. S.score, 1.0, {0.55, 1.0, 0.68, 1.0})
end
