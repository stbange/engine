-- 039_marble_gyro_run: Tilt gravity vector (eng.physics.set_gravity) to roll a dynamic sphere across narrow catwalks
local S = game.state

local MARBLE_R = 0.42
local MAX_TILT_G = 16.0

local function spawn_catwalk(name, cx, cy, cz, hx, hy, hz, tex, col)
    local e = eng.scene.spawn(name)
    eng.scene.set_pos(e, cx, cy, cz)
    eng.scene.set_scale(e, hx * 2.0, hy * 2.0, hz * 2.0)
    eng.scene.set_mesh(e, S.box_mesh, { tex = tex, color = col, roughness = 0.45, cast_shadow = true })
    eng.physics.add_body(e, { shape = "aabb", motion = "static", half_extents = {hx, hy, hz}, restitution = 0.1 })
    return e
end

local function spawn_marble()
    if S.marble_ent then
        eng.scene.despawn(S.marble_ent)
    end
    S.marble_ent = eng.scene.spawn("gyro_marble")
    eng.scene.set_pos(S.marble_ent, -4.0, MARBLE_R + 0.03, 3.2)
    eng.scene.set_mesh(S.marble_ent, S.sphere_mesh, {
        tex = S.marble_tex,
        color = {0.35, 0.92, 1.0, 1.0},
        metallic = 0.85,
        roughness = 0.18,
        cast_shadow = true
    })
    S.marble_body = eng.physics.add_body(S.marble_ent, {
        shape = "sphere",
        motion = "dynamic",
        radius = MARBLE_R,
        restitution = 0.15
    })
end

function init()
    eng.xr.set_mode("diorama")
    eng.physics.set_gravity(0, 0.0, -9.81, 0.0)
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.009 })
    eng.render.set_sky(0.06, 0.10, 0.24, 0.18, 0.34, 0.56)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.2, 2.15, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.5, -4.5}, color = {1.5, 2.1, 2.6}, range = 34.0 })

    local seed = math.floor(eng.math.range(100, 90000))
    local track_tex = eng.procgen.texture("sci_fi_panel", seed, 64)
    S.marble_tex = eng.procgen.texture("marble", seed + 17, 64)

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(MARBLE_R, 14, 16)
    local cup_mesh = eng.asset.cylinder(0.95, 1.15, 0.36, 16)
    local crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    local pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_gem = eng.audio.synth("triangle", 580, 0.14, 960)
    S.sfx_fall = eng.audio.synth("saw", 240, 0.18, 110)
    S.sfx_goal = eng.audio.synth("sine", 520, 0.28, 1120)

    -- Suspended S-Bend Narrow Catwalk Course (top surface flush at y = 0.0)
    -- 1) West Start Catwalk: x in [-5.1, -2.9], z in [-4.5, 4.5]
    spawn_catwalk("catwalk_start", -4.0, -0.25, 0.0, 1.1, 0.25, 4.5, track_tex, {0.32, 0.44, 0.62, 1.0})
    -- 2) Narrow Center Cross-Bridge: x in [-5.1, 5.1], z in [-4.5, -2.5]
    spawn_catwalk("catwalk_bridge", 0.0, -0.25, -3.5, 5.1, 0.25, 1.0, track_tex, {0.38, 0.52, 0.70, 1.0})
    -- 3) East Final Catwalk: x in [2.9, 5.1], z in [-12.5, -2.5]
    spawn_catwalk("catwalk_goal", 4.0, -0.25, -7.5, 1.1, 0.25, 5.0, track_tex, {0.32, 0.44, 0.62, 1.0})

    -- Support struts beneath suspended catwalks for strong 3D depth cues
    local strut_xz = { {-4.0, 3.0}, {-4.0, -3.5}, {0.0, -3.5}, {4.0, -3.5}, {4.0, -11.0} }
    for i = 1, #strut_xz do
        local st = eng.scene.spawn("catwalk_pillar_" .. tostring(i))
        eng.scene.set_pos(st, strut_xz[i][1], -3.5, strut_xz[i][2])
        eng.scene.set_scale(st, 0.9, 1.0, 0.9)
        eng.scene.set_mesh(st, pillar_mesh, { color = {0.26, 0.30, 0.40, 1.0} })
    end

    -- Golden Goal Cup at (4.0, 0.0, -11.0) with 3-sided backstop rim so the dynamic sphere settles inside
    S.goal_x, S.goal_z = 4.0, -11.0
    local cup = eng.scene.spawn("goal_cup_ring")
    eng.scene.set_pos(cup, S.goal_x, 0.16, S.goal_z)
    eng.scene.set_mesh(cup, cup_mesh, { color = {1.0, 0.84, 0.20, 1.0}, metallic = 0.8, roughness = 0.25 })

    spawn_catwalk("cup_rim_back", S.goal_x, 0.35, S.goal_z - 1.15, 1.1, 0.35, 0.18, track_tex, {1.0, 0.82, 0.22, 1.0})
    spawn_catwalk("cup_rim_west", S.goal_x - 1.05, 0.35, S.goal_z - 0.15, 0.15, 0.35, 1.0, track_tex, {1.0, 0.82, 0.22, 1.0})
    spawn_catwalk("cup_rim_east", S.goal_x + 1.05, 0.35, S.goal_z - 0.15, 0.15, 0.35, 1.0, track_tex, {1.0, 0.82, 0.22, 1.0})

    -- 2 Corner Gyro Gems guiding the S-curve catwalk turns
    local gem_xz = { {-4.0, -3.5}, {4.0, -3.5} }
    S.gems = {}
    for i = 1, #gem_xz do
        local gx, gz = gem_xz[i][1], gem_xz[i][2]
        local ge = eng.scene.spawn("gyro_gem_" .. tostring(i))
        eng.scene.set_pos(ge, gx, 0.25, gz)
        eng.scene.set_scale(ge, 0.7, 0.7, 0.7)
        eng.scene.set_mesh(ge, crystal_mesh, { color = {0.35, 1.0, 0.68, 1.0} })
        S.gems[i] = { ent = ge, x = gx, z = gz, collected = false }
    end

    S.tilt_x = 0.0
    S.tilt_z = 0.0
    S.gx, S.gy, S.gz = 0.0, -9.81, 0.0
    S.max_tilt_used = 0.0
    S.gems_collected = 0
    S.falls = 0
    S.spin_ang = 0.0
    S.score = 0
    S.won = false

    spawn_marble()
    eng.camera.look_at(-4.0, 7.2, 10.2, -2.5, 0.0, -2.5, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.spin_ang = (S.spin_ang + 140.0 * dt) % 360.0

    local ix, iy = eng.input.axis2d("left", "right", "down", "up")
    S.tilt_x = S.tilt_x + (ix - S.tilt_x) * math.min(1.0, 9.0 * dt)
    S.tilt_z = S.tilt_z + (iy - S.tilt_z) * math.min(1.0, 9.0 * dt)

    S.gx = S.tilt_x * MAX_TILT_G
    S.gy = -9.81
    S.gz = -S.tilt_z * MAX_TILT_G
    eng.physics.set_gravity(0, S.gx, S.gy, S.gz)

    local tilt_mag = math.sqrt(S.gx * S.gx + S.gz * S.gz)
    if tilt_mag > S.max_tilt_used then S.max_tilt_used = tilt_mag end

    local mx, my, mz = eng.scene.get_pos(S.marble_ent)
    local vx, vy, vz = eng.physics.get_vel(S.marble_body)
    -- Visual rolling rotation driven by velocity
    eng.scene.set_rot_deg(S.marble_ent, mz * 65.0, 0.0, -mx * 65.0)

    -- Respawn marble on start catwalk if it rolls off into the abyss
    if my < -2.6 then
        S.falls = S.falls + 1
        S.tilt_x, S.tilt_z = 0.0, 0.0
        eng.physics.set_gravity(0, 0.0, -9.81, 0.0)
        eng.audio.play(S.sfx_fall, mx, 0.0, mz, 0)
        spawn_marble()
        mx, my, mz = eng.scene.get_pos(S.marble_ent)
    end

    for i = 1, #S.gems do
        local g = S.gems[i]
        if not g.collected then
            eng.scene.set_rot_deg(g.ent, 0.0, S.spin_ang, 0.0)
            if eng.math.dist3(mx, 0, mz, g.x, 0, g.z) < 0.95 and my > -0.2 then
                g.collected = true
                S.gems_collected = S.gems_collected + 1
                S.score = S.score + 250
                eng.audio.play(S.sfx_gem, g.x, 0.6, g.z, 0)
                eng.scene.despawn(g.ent)
            end
        end
    end

    -- Check Goal Cup capture
    if eng.math.dist3(mx, 0, mz, S.goal_x, 0, S.goal_z) < 0.85 and my > 0.1 and math.abs(vy) < 2.5 then
        local hspd = math.sqrt(vx * vx + vz * vz)
        if hspd < 4.5 then
            S.won = true
            S.score = S.score + 600
            eng.physics.set_gravity(0, 0.0, -9.81, 0.0)
            eng.physics.set_vel(S.marble_body, 0.0, 0.0, 0.0)
            eng.audio.play(S.sfx_goal, S.goal_x, 0.6, S.goal_z, 0)
            eng.save.write("marble_gyro_clear", tostring(S.score))
        end
    end

    eng.camera.look_at(mx * 0.65, 6.8, mz + 7.2, mx * 0.85, 0.2, mz - 2.6, 0)
end

function draw()
    local mx, my, mz = eng.scene.get_pos(S.marble_ent)
    -- Gyro gravity vector indicator orb ahead of marble + beacon above Goal Cup
    eng.render.draw_sprite(mx + S.tilt_x * 0.9, my + 0.65, mz - S.tilt_z * 0.9, 0.35, 0.35, S.orb_tex)
    eng.render.draw_sprite(S.goal_x, 1.35, S.goal_z, 0.65, 0.65, S.orb_tex)

    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 54, 1280, 720)
    local label = S.won and eng.i18n.t("victory") or string.format(
        "%s | GRAV (%.1f, %.1f) | GEMS %d/2 | SCORE %d",
        eng.i18n.t("title"), S.gx, S.gz, S.gems_collected, S.score)
    eng.ui.label(x, y, label, 1.0, {0.55, 0.98, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, (S.gems_collected + (S.won and 1 or 0)) / 3.0, "COURSE ")
end
