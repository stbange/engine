-- 098_creature_zoo_lab: Procedural Planet Globe + All 6 IK Animal Archetypes + Keepers
local S = game.state

local ARCHETYPES = { "quadruped", "biped", "avian", "insectoid", "aquatic", "serpentine" }

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_sky(0.20, 0.52, 0.88, 0.72, 0.86, 0.94)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.4}, color = {2.2, 2.1, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, -10.0}, color = {1.2, 2.0, 2.5}, range = 26.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(1.4, 1.6, 1.2, 18)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local grass_tex = eng.procgen.texture("grass", seed, 64)
    local marble_tex = eng.procgen.texture("marble", seed + 13, 64)

    -- Safari Biodome Lawn + Marble Research Plaza
    local lawn = eng.scene.spawn("safari_lawn")
    eng.scene.set_pos(lawn, 0.0, -0.25, -8.0)
    eng.scene.set_scale(lawn, 28.0, 0.5, 26.0)
    eng.scene.set_mesh(lawn, S.box_mesh, { tex = grass_tex, roughness = 0.88 })

    local walkway = eng.scene.spawn("dna_plaza")
    eng.scene.set_pos(walkway, 0.0, 0.02, -8.0)
    eng.scene.set_scale(walkway, 9.0, 0.08, 12.0)
    eng.scene.set_mesh(walkway, S.box_mesh, { tex = marble_tex, roughness = 0.3 })

    -- Centerpiece Live Procedural 3D Planet Globe on Marble Pedestal
    local ped = eng.scene.spawn("planet_pedestal")
    eng.scene.set_pos(ped, 0.0, 0.6, -13.5)
    eng.scene.set_mesh(ped, S.cyl_mesh, { tex = marble_tex, roughness = 0.25 })
    eng.physics.add_body(ped, { shape = "aabb", motion = "static", half_extents = {1.5, 0.9, 1.5} })

    S.planet_mesh = eng.procgen.planet(seed + 77, 2.4, 16, 0.0)
    S.planet_ent = eng.scene.spawn("holo_planet_globe")
    eng.scene.set_pos(S.planet_ent, 0.0, 4.4, -13.5)
    eng.scene.set_mesh(S.planet_ent, S.planet_mesh, { roughness = 0.75, cast_shadow = true })

    -- Poisson-scattered L-system Safari Trees around perimeter
    local tree_mesh = eng.procgen.tree(seed + 31, 2, 2.5, 0.18)
    local pts = eng.procgen.scatter_poisson(seed + 5, 20.0, 6.0, 4.2, 8)
    for i = 1, #pts do
        local tx, tz = pts[i][1] - 10.0, -16.0 - pts[i][2] * 0.4
        local te = eng.scene.spawn("safari_tree_" .. tostring(i))
        eng.scene.set_pos(te, tx, 0.0, tz)
        eng.scene.set_mesh(te, tree_mesh, { cast_shadow = true })
        local tc = eng.scene.spawn("safari_tree_col_" .. tostring(i))
        eng.scene.set_pos(tc, tx, 1.2, tz)
        eng.physics.add_body(tc, { shape = "aabb", motion = "static", half_extents = {0.35, 1.2, 0.35} })
    end

    -- Spawn ALL 6 DNA Animal Archetypes walking patrol loops with procedural IK gaits!
    local bases = {
        {-5.2, -4.5}, {-3.2, -8.5}, {0.0, -6.2},
        { 3.2, -8.5}, { 5.2, -4.5}, {0.0, -10.5}
    }
    S.creatures = {}
    for i = 1, #ARCHETYPES do
        local arch = ARCHETYPES[i]
        local ce = eng.scene.spawn("zoo_" .. arch)
        local bx, bz = bases[i][1], bases[i][2]
        eng.scene.set_pos(ce, bx, 0.0, bz)
        local info = eng.procgen.animal(ce, seed + i * 101, arch)
        S.creatures[i] = {
            ent = ce, archetype = arch, cx = bx, cz = bz,
            x = bx, z = bz, phase = i * 1.05,
            height = info.height, cataloged = false
        }
    end
    S.archetypes_spawned = #S.creatures

    -- Spawn 2 Modular Rigged Zoo Keepers (eng.procgen.person)
    S.keepers = {}
    for k = 1, 2 do
        local ke = eng.scene.spawn("zoo_keeper_" .. tostring(k))
        local kx = (k == 1) and -2.4 or 2.4
        eng.scene.set_pos(ke, kx, 0.0, -3.2)
        local pinfo = eng.procgen.person(ke, seed + k * 53)
        S.keepers[k] = { ent = ke, name = pinfo.name, role = pinfo.role, x = kx, z = -3.2 }
    end
    S.keepers_spawned = #S.keepers

    S.sfx_scan = eng.audio.synth("triangle", 580, 0.16, 960)
    S.sfx_grant = eng.audio.synth("sine", 660, 0.26, 1320)

    S.px, S.py, S.pz = 0.0, 1.8, 1.5
    S.yaw, S.pitch = 0.0, 0.0
    S.globe_yaw = 0.0
    S.scan_cd = 0.0
    S.cataloged_count = 0
    S.last_scanned = "NONE"
    S.won = false

    eng.input.set_mouse_lock(true)
    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.scan_cd = math.max(0.0, S.scan_cd - dt)
    S.globe_yaw = (S.globe_yaw + 28.0 * dt) % 360.0
    eng.scene.set_rot_deg(S.planet_ent, 14.0, S.globe_yaw, 0.0)

    -- Animate walking safari patrol circles for all 6 archetypes
    for i = 1, #S.creatures do
        local c = S.creatures[i]
        c.phase = c.phase + 1.3 * dt
        c.x = c.cx + math.cos(c.phase) * 0.85
        c.z = c.cz + math.sin(c.phase) * 0.85
        eng.scene.set_pos(c.ent, c.x, 0.0, c.z)
        eng.scene.set_rot_deg(c.ent, 0.0, math.deg(c.phase) + 90.0, 0.0)
    end

    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw, S.pitch, 11.5, dt)
    local nx, nz = eng.physics.slide_move(0, S.px, 0.8, S.pz, dx, dz, 0.42)
    S.px = eng.math.clamp(nx, -9.0, 9.0)
    S.pz = eng.math.clamp(nz, -13.0, 2.5)

    if (eng.input.pressed("fire") or eng.input.down("fire") or eng.input.pressed("interact")) and S.scan_cd <= 0.0 then
        for i = 1, #S.creatures do
            local c = S.creatures[i]
            if not c.cataloged and eng.math.dist3(S.px, 0.0, S.pz, c.x, 0.0, c.z) < 2.6 then
                c.cataloged = true
                S.cataloged_count = S.cataloged_count + 1
                S.last_scanned = string.upper(c.archetype)
                S.scan_cd = 0.14
                eng.audio.play(S.sfx_scan, c.x, 1.0, c.z, 0)
                if S.cataloged_count >= 5 then
                    eng.audio.play(S.sfx_grant, S.px, S.py, S.pz, 0)
                    S.won = true
                    eng.save.write("zoo_codex_species", tostring(S.cataloged_count))
                end
                break
            end
        end
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
end

function draw()
    for i = 1, #S.creatures do
        local c = S.creatures[i]
        if c.cataloged then
            eng.render.draw_sprite(c.x, c.height + 0.65, c.z, 0.55, 0.55, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | CATALOGED " .. S.cataloged_count .. "/5 | LAST: " .. S.last_scanned, 1.0, {0.5, 1.0, 0.65, 1.0})
    eng.ui.bar(x, y + 26, 220, S.cataloged_count / 5.0, "CODEX ")
end
