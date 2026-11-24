-- 092_spatial_echo_blind: Dark Cavern Echolocation & Cross-Portal 3D Audio Pings
local S = game.state

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ dither = true, fog_density = 0.038 })
    eng.render.set_sky(0.01, 0.02, 0.04, 0.03, 0.06, 0.10)
    -- Subtle bioluminescent cavern light so Spatial Doctor verifies silhouette visibility
    eng.render.add_light({ type = "dir", dir = {-0.2, -1.0, -0.3}, color = {0.45, 0.65, 0.90}, shadow = true })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ring_mesh = eng.asset.cylinder(0.65, 0.65, 0.07, 20)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local rock_tex = eng.procgen.texture("cobble", seed, 64)

    -- Outer dark cavern floor & stalagmite pillars (pocket 0)
    local floor_out = eng.scene.spawn("cavern_floor")
    eng.scene.set_pos(floor_out, 0.0, -0.25, -2.0)
    eng.scene.set_scale(floor_out, 16.0, 0.5, 20.0)
    eng.scene.set_mesh(floor_out, S.box_mesh, { tex = rock_tex, color = {0.14, 0.18, 0.24, 1.0}, roughness = 0.9 })
    eng.physics.add_body(floor_out, { shape = "aabb", motion = "static", half_extents = {8.0, 0.25, 10.0} })

    for i = 1, 4 do
        local side = (i % 2 == 0) and 1 or -1
        local st = eng.scene.spawn("stalagmite_" .. tostring(i))
        local sx, sz = side * 2.8, 1.5 - i * 2.1
        eng.scene.set_pos(st, sx, 0.0, sz)
        eng.scene.set_mesh(st, S.pillar_mesh, { color = {0.18, 0.26, 0.36, 1.0}, roughness = 0.85 })
    end

    -- Bigger-on-the-inside Sanctum Cavern behind stone portal doorway at z = -8.5
    local sanctum = eng.space.create_pocket_building(eng, {
        exterior_pos = {0.0, 0.0, -8.5},
        exterior_size = {4.2, 3.6, 2.4},
        interior_size = {18.0, 8.0, 20.0},
        door_size = {1.8, 2.5},
        pocket = "echo_sanctum",
        mesh_id = S.box_mesh,
        exterior_color = {0.16, 0.24, 0.34, 1.0},
        interior_color = {0.12, 0.22, 0.30, 1.0}
    })
    S.sanctum_id = sanctum.pocket_id
    eng.render.add_light({ type = "point", pocket = "echo_sanctum", pos = {0.0, 4.0, 0.0}, color = {0.6, 1.8, 2.2}, range = 26.0 })

    -- Exit Chime Shrine inside echo_sanctum at (0, 0, 1.5) (d_int is at z = +9.8)
    S.chime_x, S.chime_z = 0.0, 1.5
    local arch = eng.scene.spawn("chime_arch")
    eng.scene.set_pocket(arch, S.sanctum_id)
    eng.scene.set_pos(arch, S.chime_x, 0.0, S.chime_z)
    eng.scene.set_mesh(arch, S.arch_mesh, { color = {0.3, 0.95, 1.0, 1.0} })

    S.chime_ent = eng.scene.spawn("exit_chime_crystal")
    eng.scene.set_pocket(S.chime_ent, S.sanctum_id)
    eng.scene.set_pos(S.chime_ent, S.chime_x, 0.7, S.chime_z)
    eng.scene.set_mesh(S.chime_ent, S.crystal_mesh, { color = {1.0, 0.90, 0.35, 1.0}, roughness = 0.15 })
    eng.physics.add_body(S.chime_ent, {
        shape = "aabb", motion = "static", pocket = S.sanctum_id,
        half_extents = {0.5, 0.8, 0.5}
    })

    S.sfx_sonar = eng.audio.synth("sine", 780, 0.14, 390)
    S.sfx_chime = eng.audio.synth("triangle", 660, 0.24, 990)

    S.pocket = 0
    S.px, S.py, S.pz = 0.0, 1.25, 2.5
    S.yaw, S.pitch = 0.0, 0.0
    S.pulses = 0
    S.cross_pings = 0
    S.echo_hits = 0
    S.crossed_portal = false
    S.cooldown = 0.0
    S.rings = {}
    S.won = false

    eng.input.set_mouse_lock(true)
    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
    eng.mod.emit("post_init")
end

function emit_sonar()
    S.pulses = S.pulses + 1
    eng.audio.play(S.sfx_sonar, S.px, S.py, S.pz, S.pocket)
    -- Cross-portal 3D audio response from Exit Chime inside echo_sanctum!
    eng.audio.play(S.sfx_chime, S.chime_x, 1.3, S.chime_z, S.sanctum_id)
    S.cross_pings = S.cross_pings + 1

    local re = eng.scene.spawn("sonar_ring_" .. tostring(S.pulses))
    eng.scene.set_pocket(re, S.pocket)
    eng.scene.set_pos(re, S.px, 0.18, S.pz)
    eng.scene.set_scale(re, 1.0, 1.0, 1.0)
    eng.scene.set_mesh(re, S.ring_mesh, { color = {0.25, 0.98, 1.0, 1.0}, roughness = 0.1 })
    S.rings[#S.rings + 1] = { ent = re, age = 0.0, x = S.px, z = S.pz }

    -- Cross-portal echolocation raycast along active look direction
    local rad = math.rad(S.yaw or 0.0)
    local hit = eng.physics.raycast(S.pocket, S.px, 1.1, S.pz, -math.sin(rad), 0.0, -math.cos(rad), 26.0)
    if hit then
        S.echo_hits = S.echo_hits + 1
    end
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        S.cooldown = 0.28
        emit_sonar()
    end

    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw, S.pitch, 7.8, dt)
    if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
        local nx, nz = eng.physics.slide_move(S.pocket, S.px, S.py, S.pz, dx, dz, 0.32)
        nx = eng.math.clamp(nx, -6.5, 6.5)
        local dst_p, wx, wy, wz = eng.portal.check_crossing(S.pocket, S.px, S.py, S.pz, nx, S.py, nz)
        if dst_p then
            S.pocket = dst_p
            S.px, S.py, S.pz = wx, wy, wz
            if S.pocket == S.sanctum_id then S.crossed_portal = true end
        else
            S.px, S.pz = nx, nz
        end
    end

    for i = #S.rings, 1, -1 do
        local r = S.rings[i]
        r.age = r.age + dt
        if r.age >= 0.55 then
            eng.scene.despawn(r.ent)
            table.remove(S.rings, i)
        else
            local rad = 1.0 + (r.age / 0.55) * 7.5
            eng.scene.set_scale(r.ent, rad, 1.0, rad)
        end
    end

    if S.pocket == S.sanctum_id and eng.math.dist3(S.px, 0.0, S.pz, S.chime_x, 0.0, S.chime_z) < 2.1 then
        eng.audio.play(S.sfx_chime, S.chime_x, 1.3, S.chime_z, S.sanctum_id)
        S.won = true
        eng.save.write("echo_blind_clear", "sanctum_reached")
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
end

function draw()
    if S.pocket == S.sanctum_id then
        eng.render.draw_sprite(S.chime_x, 2.2, S.chime_z, 0.9, 0.9, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | PULSES " .. S.pulses .. " | ECHOES " .. S.echo_hits, 1.0, {0.45, 0.95, 1.0, 1.0})
end
