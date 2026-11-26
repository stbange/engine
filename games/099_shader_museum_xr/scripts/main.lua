-- 099_shader_museum_xr: Deferred Pipeline + Bigger-on-the-Inside Architectural Gallery
local S = game.state

function init()
    eng.render.set_pipeline("deferred")
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ bloom = 0.45, fog_density = 0.008, fog_color = {0.36, 0.24, 0.28}, fog_height = 4.0 })
    eng.fx.sky(eng, "sunset_mountains")
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.45}, color = {2.0, 1.95, 1.85}, shadow = true })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.45, 16, 20)
    S.ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.checker_tex = eng.asset.load_texture("assets/shared/textures/checker.png", true)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local marble_tex = eng.procgen.texture("marble", seed, 64)
    local caustic_tex = eng.procgen.texture("water_caustics", seed + 17, 64)

    -- Exterior Courtyard Plaza (pocket 0) with live Gold, Chrome, Crystal & Fire showcase
    local plaza = eng.scene.spawn("courtyard_plaza")
    eng.scene.set_pos(plaza, 0.0, -0.25, -2.0)
    eng.scene.set_scale(plaza, 16.0, 0.5, 14.0)
    eng.scene.set_mesh(plaza, S.box_mesh, { tex = marble_tex, roughness = 0.3 })

    local c_gold = eng.scene.spawn("courtyard_gold")
    eng.scene.set_pos(c_gold, -3.2, 0.55, -2.2)
    eng.scene.set_mesh(c_gold, S.sphere_mesh, eng.fx.material("gold", { cast_shadow = true }))
    local c_chrome = eng.scene.spawn("courtyard_chrome")
    eng.scene.set_pos(c_chrome, 3.2, 0.55, -2.2)
    eng.scene.set_mesh(c_chrome, S.sphere_mesh, eng.fx.material("chrome", { cast_shadow = true }))
    local c_crys = eng.scene.spawn("courtyard_crystal")
    eng.scene.set_pos(c_crys, -3.2, 1.35, -2.2)
    eng.scene.set_scale(c_crys, 0.65, 0.65, 0.65)
    eng.scene.set_mesh(c_crys, S.crystal_mesh, eng.fx.material("crystal"))
    eng.fx.spawn(eng, "fire", 3.2, 1.05, -2.2, 0, { rate = 24, size_start = 0.35 })
    eng.fx.spawn(eng, "smoke", 3.2, 1.45, -2.2, 0, { rate = 10, size_start = 0.28 })
    S.courtyard_fire_light = eng.render.add_light({ type = "point", pocket = 0, pos = {3.2, 1.8, -2.2}, color = {2.4, 1.25, 0.45}, range = 10.0 })

    -- Compact 3.8m Exterior Pavilion -> Grand 26m x 9m x 28m Bigger-on-the-Inside Museum Hall!
    local museum = eng.space.create_pocket_building(eng, {
        exterior_pos = {0.0, 0.0, -5.0},
        exterior_size = {3.8, 3.4, 2.8},
        interior_size = {26.0, 9.0, 28.0},
        door_size = {1.8, 2.5},
        pocket = "museum_hall",
        mesh_id = S.box_mesh,
        exterior_color = {0.88, 0.86, 0.82, 1.0},
        interior_color = {0.22, 0.24, 0.30, 1.0}
    })
    S.hall_id = museum.pocket_id

    -- Deferred multi-light illumination inside Museum Hall
    eng.render.add_light({ type = "point", pocket = "museum_hall", pos = {-5.0, 5.5, 8.0}, color = {2.6, 2.2, 1.7}, range = 22.0 })
    eng.render.add_light({ type = "point", pocket = "museum_hall", pos = { 5.0, 5.5, 8.0}, color = {1.5, 2.2, 2.8}, range = 22.0 })
    S.brazier_light = eng.render.add_light({ type = "point", pocket = "museum_hall", pos = { 4.6, 2.4, 2.5}, color = {2.8, 1.5, 0.55}, range = 16.0 })

    -- Helper to spawn marble exhibit plinth + translucent status crystal inside museum_hall
    local function add_plinth(idx, name, x, z)
        local pe = eng.scene.spawn("plinth_" .. tostring(idx))
        eng.scene.set_pocket(pe, S.hall_id)
        eng.scene.set_pos(pe, x, 0.45, z)
        eng.scene.set_scale(pe, 2.8, 0.9, 1.8)
        eng.scene.set_mesh(pe, S.box_mesh, { tex = marble_tex, roughness = 0.22 })

        local ce = eng.scene.spawn("beacon_" .. tostring(idx))
        eng.scene.set_pocket(ce, S.hall_id)
        eng.scene.set_pos(ce, x, 2.35, z)
        eng.scene.set_scale(ce, 0.4, 0.4, 0.4)
        eng.scene.set_mesh(ce, S.crystal_mesh, eng.fx.material("glass"))
        return { idx = idx, name = name, x = x, z = z, beacon = ce, inspected = false }
    end

    S.exhibits = {
        add_plinth(1, "GOLD & CHROME", -4.6,  8.5),
        add_plinth(2, "PS1 DITHER",     4.6,  8.5),
        add_plinth(3, "AO VOXELS",     -4.6,  2.5),
        add_plinth(4, "FIRE & SMOKE",   4.6,  2.5),
        add_plinth(5, "PORTAL VAULT",   0.0, -3.5)
    }

    -- Exhibit 1: Gold, Chrome & Translucent Fresnel Crystal Material Array
    local mat_names = { "gold", "chrome", "crystal" }
    for s = 1, 3 do
        local sp = eng.scene.spawn("pbr_sphere_" .. tostring(s))
        eng.scene.set_pocket(sp, S.hall_id)
        eng.scene.set_pos(sp, -4.6 + (s - 2) * 0.95, 1.38, 8.5)
        local opts = eng.fx.material(mat_names[s])
        if s < 3 then opts.cast_shadow = true end
        eng.scene.set_mesh(sp, (s == 3) and S.crystal_mesh or S.sphere_mesh, opts)
    end

    -- Exhibit 2: Retro PS1 Vertex-Snap & Bayer Dither Starfighter Plinth
    S.retro_ent = eng.scene.spawn("ps1_starfighter")
    eng.scene.set_pocket(S.retro_ent, S.hall_id)
    eng.scene.set_pos(S.retro_ent, 4.6, 1.35, 8.5)
    eng.scene.set_scale(S.retro_ent, 0.65, 0.65, 0.65)
    eng.scene.set_mesh(S.retro_ent, S.ship_mesh, { tex = S.checker_tex, roughness = 0.5, cast_shadow = true })

    -- Exhibit 3: Greedy-Meshed AO Voxel Monument
    local vox_mesh = eng.asset.voxel_ascii({
        "1111\n1111\n1111\n1111",
        "1..1\n....\n....\n1..1",
        "1111\n1..1\n1..1\n1111",
        ".11.\n.11.\n.11.\n.11."
    }, 4, 4, 4, 0.36)
    local ve = eng.scene.spawn("ao_voxel_monument")
    eng.scene.set_pocket(ve, S.hall_id)
    eng.scene.set_pos(ve, -5.3, 0.9, 1.8)
    eng.scene.set_mesh(ve, vox_mesh, { color = {0.35, 0.92, 0.72, 1.0}, cast_shadow = true })

    -- Exhibit 4: Caustic Pedestal + Live Fire & Smoke Brazier
    local fp = eng.scene.spawn("caustic_basin")
    eng.scene.set_pocket(fp, S.hall_id)
    eng.scene.set_pos(fp, 4.6, 0.96, 2.5)
    eng.scene.set_scale(fp, 2.0, 0.12, 1.3)
    eng.scene.set_mesh(fp, S.box_mesh, { tex = caustic_tex, roughness = 0.12 })
    eng.fx.spawn(eng, "fire", 4.6, 1.08, 2.5, S.hall_id)
    eng.fx.spawn(eng, "smoke", 4.6, 1.55, 2.5, S.hall_id)

    -- Exhibit 5: Secondary Pocket Portal Alcove peering into an Infinity Light Vault with a Synthwave City sky!
    local vault_id = eng.scene.register_pocket("infinity_vault")
    eng.fx.sky(eng, "synthwave_city", { pocket = vault_id })
    eng.render.add_light({ type = "point", pocket = "infinity_vault", pos = {0.0, 3.0, 0.0}, color = {2.8, 1.8, 0.6}, range = 16.0 })
    local vf = eng.scene.spawn("vault_floor")
    eng.scene.set_pocket(vf, vault_id)
    eng.scene.set_pos(vf, 0.0, -0.25, 0.0)
    eng.scene.set_scale(vf, 8.0, 0.5, 8.0)
    eng.scene.set_mesh(vf, S.box_mesh, { tex = marble_tex, color = {0.95, 0.78, 0.30, 1.0} })
    local vc = eng.scene.spawn("vault_relic")
    eng.scene.set_pocket(vc, vault_id)
    eng.scene.set_pos(vc, 0.0, 1.0, -1.5)
    eng.scene.set_mesh(vc, S.crystal_mesh, eng.fx.material("ruby"))

    local pa = eng.scene.spawn("alcove_arch")
    eng.scene.set_pocket(pa, S.hall_id)
    eng.scene.set_pos(pa, 0.0, 0.9, -3.5)
    eng.scene.set_mesh(pa, S.arch_mesh, eng.fx.material("copper"))

    local p_src = eng.scene.spawn("vault_portal_src")
    eng.scene.set_pocket(p_src, S.hall_id)
    eng.scene.set_pos(p_src, 0.0, 2.0, -3.5)
    local p_dst = eng.scene.spawn("vault_portal_dst")
    eng.scene.set_pocket(p_dst, vault_id)
    eng.scene.set_pos(p_dst, 0.0, 1.5, 2.5)
    eng.scene.set_rot_deg(p_dst, 0.0, 180.0, 0.0)
    eng.portal.link(p_src, p_dst, 1.4, 2.2, 1.0, false, false)

    S.sfx_inspect = eng.audio.synth("triangle", 540, 0.16, 860)
    S.sfx_fanfare = eng.audio.synth("sine", 660, 0.28, 1320)

    S.pocket = 0
    S.px, S.py, S.pz = 0.0, 1.35, 1.8
    S.yaw, S.pitch = 0.0, 0.0
    S.spin = 0.0
    S.fx_t = 0.0
    S.retro_timer = 0.0
    S.entered_gallery = false
    S.inspected_count = 0
    S.won = false

    eng.input.set_mouse_lock(true)
    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.spin = (S.spin + 55.0 * dt) % 360.0
    S.fx_t = (S.fx_t or 0.0) + dt
    eng.scene.set_rot_deg(S.retro_ent, 0.0, S.spin, 0.0)
    local flk = 0.88 + 0.16 * math.sin(S.fx_t * 11.0) + 0.08 * math.sin(S.fx_t * 23.0)
    eng.render.set_light(S.brazier_light, { color = {2.8 * flk, 1.5 * flk, 0.55 * flk} })
    eng.render.set_light(S.courtyard_fire_light, { color = {2.4 * flk, 1.25 * flk, 0.45 * flk} })

    if S.retro_timer > 0.0 then
        S.retro_timer = S.retro_timer - dt
        if S.retro_timer <= 0.0 then
            eng.render.set_retro({ vertex_snap = 0, dither = false, color_bits = 8, bloom = 0.45 })
        end
    end

    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw, S.pitch, 11.8, dt)
    if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
        local nx, nz = eng.physics.slide_move(S.pocket, S.px, S.py, S.pz, dx, dz, 0.32)
        nx = eng.math.clamp(nx, -10.0, 10.0)
        local dst_p, wx, wy, wz = eng.portal.check_crossing(S.pocket, S.px, S.py, S.pz, nx, S.py, nz)
        if dst_p then
            S.pocket = dst_p
            S.px, S.py, S.pz = wx, wy, wz
            if S.pocket == S.hall_id then S.entered_gallery = true end
        else
            S.px, S.pz = nx, nz
        end
    end

    if S.pocket == S.hall_id and (eng.input.pressed("fire") or eng.input.down("fire") or eng.input.pressed("interact")) then
        for i = 1, #S.exhibits do
            local ex = S.exhibits[i]
            if not ex.inspected and eng.math.dist3(S.px, 0.0, S.pz, ex.x, 0.0, ex.z) < 2.7 then
                ex.inspected = true
                S.inspected_count = S.inspected_count + 1
                eng.scene.set_mesh(ex.beacon, S.crystal_mesh, eng.fx.material("emerald"))
                eng.audio.play(S.sfx_inspect, ex.x, 1.5, ex.z, S.hall_id)
                if ex.idx == 2 then
                    eng.render.set_retro({ vertex_snap = 200, dither = true, color_bits = 5 })
                    S.retro_timer = 0.25
                end
                if S.inspected_count >= 5 then
                    eng.render.set_retro(false)
                    eng.audio.play(S.sfx_fanfare, S.px, S.py, S.pz, S.hall_id)
                    S.won = true
                    eng.save.write("shader_museum_tour", "5_exhibits")
                end
            end
        end
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
end

function draw()
    if S.pocket == S.hall_id then
        -- Exhibit 4 animated billboard sprite fountain
        for k = 0, 2 do
            local a = math.rad(S.spin * 2.0 + k * 120.0)
            eng.render.draw_sprite(4.6 + math.cos(a) * 0.55, 1.55 + math.sin(a * 2.0) * 0.15, 2.5 + math.sin(a) * 0.45, 0.5, 0.5, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | DEFERRED PBR | EXHIBITS " .. S.inspected_count .. "/5", 1.0, {0.85, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.inspected_count / 5.0, "TOUR ")
end
