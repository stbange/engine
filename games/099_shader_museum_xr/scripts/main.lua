-- 099_shader_museum_xr: Deferred Pipeline + Bigger-on-the-Inside Architectural Gallery
local S = game.state

function init()
    eng.render.set_pipeline("deferred")
    eng.xr.set_mode("first_person")
    eng.render.set_sky(0.10, 0.16, 0.28, 0.42, 0.50, 0.62)
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

    -- Exterior Courtyard Plaza (pocket 0)
    local plaza = eng.scene.spawn("courtyard_plaza")
    eng.scene.set_pos(plaza, 0.0, -0.25, -2.0)
    eng.scene.set_scale(plaza, 16.0, 0.5, 14.0)
    eng.scene.set_mesh(plaza, S.box_mesh, { tex = marble_tex, roughness = 0.3 })

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
    eng.render.add_light({ type = "point", pocket = "museum_hall", pos = { 0.0, 5.5, -2.0}, color = {2.4, 1.5, 2.6}, range = 24.0 })

    -- Helper to spawn marble exhibit plinth + status crystal inside museum_hall
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
        eng.scene.set_mesh(ce, S.crystal_mesh, { color = {0.45, 0.50, 0.60, 1.0} })
        return { idx = idx, name = name, x = x, z = z, beacon = ce, inspected = false }
    end

    S.exhibits = {
        add_plinth(1, "PBR SPHERES",   -4.6,  8.5),
        add_plinth(2, "PS1 DITHER",     4.6,  8.5),
        add_plinth(3, "AO VOXELS",     -4.6,  2.5),
        add_plinth(4, "SPRITE FOUNT",   4.6,  2.5),
        add_plinth(5, "PORTAL VAULT",   0.0, -3.5)
    }

    -- Exhibit 1: Metallic/Roughness PBR Sphere Array
    local pbr_cols = { {1.0, 0.84, 0.25, 1.0}, {0.92, 0.94, 0.98, 1.0}, {0.95, 0.48, 0.28, 1.0} }
    for s = 1, 3 do
        local sp = eng.scene.spawn("pbr_sphere_" .. tostring(s))
        eng.scene.set_pocket(sp, S.hall_id)
        eng.scene.set_pos(sp, -4.6 + (s - 2) * 0.95, 1.38, 8.5)
        eng.scene.set_mesh(sp, S.sphere_mesh, {
            color = pbr_cols[s],
            metallic = (s == 3) and 0.1 or 0.95,
            roughness = 0.08 + (s - 1) * 0.35,
            cast_shadow = true
        })
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

    -- Exhibit 4: Caustic Pedestal for Billboard Sprite Constellation
    local fp = eng.scene.spawn("caustic_basin")
    eng.scene.set_pocket(fp, S.hall_id)
    eng.scene.set_pos(fp, 4.6, 0.96, 2.5)
    eng.scene.set_scale(fp, 2.0, 0.12, 1.3)
    eng.scene.set_mesh(fp, S.box_mesh, { tex = caustic_tex, roughness = 0.12 })

    -- Exhibit 5: Secondary Pocket Portal Alcove peering into an Infinity Light Vault
    local vault_id = eng.scene.register_pocket("infinity_vault")
    eng.render.add_light({ type = "point", pocket = "infinity_vault", pos = {0.0, 3.0, 0.0}, color = {2.8, 1.8, 0.6}, range = 16.0 })
    local vf = eng.scene.spawn("vault_floor")
    eng.scene.set_pocket(vf, vault_id)
    eng.scene.set_pos(vf, 0.0, -0.25, 0.0)
    eng.scene.set_scale(vf, 8.0, 0.5, 8.0)
    eng.scene.set_mesh(vf, S.box_mesh, { tex = marble_tex, color = {0.95, 0.78, 0.30, 1.0} })
    local vc = eng.scene.spawn("vault_relic")
    eng.scene.set_pocket(vc, vault_id)
    eng.scene.set_pos(vc, 0.0, 1.0, -1.5)
    eng.scene.set_mesh(vc, S.crystal_mesh, { color = {1.0, 0.9, 0.3, 1.0} })

    local pa = eng.scene.spawn("alcove_arch")
    eng.scene.set_pocket(pa, S.hall_id)
    eng.scene.set_pos(pa, 0.0, 0.9, -3.5)
    eng.scene.set_mesh(pa, S.arch_mesh, { color = {0.9, 0.85, 0.95, 1.0} })

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
    S.spin = 0.0
    S.retro_timer = 0.0
    S.entered_gallery = false
    S.inspected_count = 0
    S.won = false

    eng.camera.look_at(S.px, S.py, S.pz, 0.0, 1.35, -4.0, S.pocket)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.spin = (S.spin + 55.0 * dt) % 360.0
    eng.scene.set_rot_deg(S.retro_ent, 0.0, S.spin, 0.0)

    if S.retro_timer > 0.0 then
        S.retro_timer = S.retro_timer - dt
        if S.retro_timer <= 0.0 then
            eng.render.set_retro(false)
        end
    end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        local nx = eng.math.clamp(S.px + mx * 11.5 * dt, -10.0, 10.0)
        local nz = S.pz - my * 12.0 * dt
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
                eng.scene.set_mesh(ex.beacon, S.crystal_mesh, { color = {0.25, 1.0, 0.55, 1.0}, roughness = 0.1 })
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

    local tx = (S.pocket == S.hall_id) and 0.0 or 0.0
    local tz = (S.pocket == S.hall_id) and -3.5 or -4.0
    eng.camera.look_at(S.px, S.py, S.pz, tx, 1.35, tz, S.pocket)
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
