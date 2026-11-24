-- 100_engine_meta_arcade: Celebratory #100 3D Retro Arcade with Bigger-on-the-Inside Cabinet Portals!
local S = game.state

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_sky(0.04, 0.02, 0.12, 0.18, 0.06, 0.28)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.4}, color = {1.9, 1.85, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.5, -5.0}, color = {2.4, 1.8, 2.8}, range = 26.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.85, 1.0, 0.85, 18)
    S.ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.checker_tex = eng.asset.load_texture("assets/shared/textures/checker.png", true)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local dungeon_tex = eng.procgen.texture("stone_brick", seed, 64)
    local scifi_tex = eng.procgen.texture("sci_fi_panel", seed + 19, 64)
    local grass_tex = eng.procgen.texture("grass", seed + 37, 64)

    -- Grand Neon Arcade Hall Floor (pocket 0)
    local hall_floor = eng.scene.spawn("arcade_carpet")
    eng.scene.set_pos(hall_floor, 0.0, -0.25, -6.0)
    eng.scene.set_scale(hall_floor, 22.0, 0.5, 22.0)
    eng.scene.set_mesh(hall_floor, S.box_mesh, { tex = S.checker_tex, color = {0.32, 0.22, 0.52, 1.0}, roughness = 0.35 })

    -- Voxel Crown Sign above the Arcade Hall ("100")
    local vox_sign = eng.asset.voxel_ascii({
        "1.111.111\n1.1.1.1.1\n1.1.1.1.1\n1.1.1.1.1\n1.111.111"
    }, 9, 1, 5, 0.42)
    local sign_e = eng.scene.spawn("arcade_100_marquee")
    eng.scene.set_pos(sign_e, -1.9, 4.4, -10.5)
    eng.scene.set_rot_deg(sign_e, 90.0, 0.0, 0.0)
    eng.scene.set_mesh(sign_e, vox_sign, { color = {1.0, 0.86, 0.22, 1.0} })

    -- Cheering NPC Arcade Visitors
    for k = 1, 2 do
        local pe = eng.scene.spawn("arcade_guest_" .. tostring(k))
        eng.scene.set_pos(pe, (k == 1) and -3.2 or 3.2, 0.0, -2.5)
        eng.procgen.person(pe, seed + k * 41)
    end

    -- Centerpiece Golden Master #100 Trophy Pedestal at (0, 0, -3.2)
    S.trophy_x, S.trophy_z = 0.0, -3.2
    local ped = eng.scene.spawn("trophy_pedestal")
    eng.scene.set_pos(ped, S.trophy_x, 0.42, S.trophy_z)
    eng.scene.set_mesh(ped, S.cyl_mesh, { color = {0.35, 0.32, 0.44, 1.0}, metallic = 0.6, roughness = 0.3 })

    S.trophy_ent = eng.scene.spawn("golden_master_trophy")
    eng.scene.set_pos(S.trophy_ent, S.trophy_x, 0.9, S.trophy_z)
    eng.scene.set_mesh(S.trophy_ent, S.chest_mesh, { color = {0.45, 0.45, 0.52, 1.0}, metallic = 0.8, roughness = 0.3 })

    -- 3 Glowing Arcade Cabinets whose screens are Bigger-on-the-Inside Pocket Portals!
    -- Note: exterior_size = {2.6, 3.1, 2.2}, so front_z = ext_z + 1.1; interior_size = {16, 7, 16}, so d_int_z = +7.8
    local cab_defs = {
        { name = "cab_dungeon", title = "CATACOMB CAB", x = -5.2, z = -8.2, ext_col = {0.85, 0.25, 0.35, 1.0}, int_col = {0.32, 0.28, 0.26, 1.0}, lcol = {2.4, 1.5, 0.8}, tex = dungeon_tex },
        { name = "cab_star",    title = "STARFIGHTER",  x =  0.0, z = -9.2, ext_col = {0.20, 0.72, 0.98, 1.0}, int_col = {0.14, 0.22, 0.36, 1.0}, lcol = {0.8, 2.2, 3.0}, tex = scifi_tex   },
        { name = "cab_safari",  title = "CRITTER ZOO",  x =  5.2, z = -8.2, ext_col = {0.25, 0.88, 0.48, 1.0}, int_col = {0.20, 0.44, 0.22, 1.0}, lcol = {1.8, 2.4, 1.4}, tex = grass_tex   }
    }

    S.cabinets = {}
    for i = 1, 3 do
        local d = cab_defs[i]
        local b = eng.space.create_pocket_building(eng, {
            exterior_pos = {d.x, 0.0, d.z},
            exterior_size = {2.6, 3.1, 2.2},
            interior_size = {16.0, 7.0, 16.0},
            door_size = {1.6, 2.3},
            pocket = d.name,
            mesh_id = S.box_mesh,
            exterior_color = d.ext_col,
            interior_color = d.int_col
        })
        eng.render.add_light({ type = "point", pocket = d.name, pos = {0.0, 4.5, 2.0}, color = d.lcol, range = 24.0 })

        -- Mini-game token target at (0, 0.9, 4.2) inside the oversized pocket cabinet world!
        local obj_e = eng.scene.spawn(d.name .. "_token_target")
        eng.scene.set_pocket(obj_e, b.pocket_id)
        if i == 1 then
            eng.scene.set_pos(obj_e, 0.0, 0.8, 4.2)
            eng.scene.set_mesh(obj_e, S.crystal_mesh, { color = {1.0, 0.85, 0.2, 1.0}, roughness = 0.15 })
        elseif i == 2 then
            eng.scene.set_pos(obj_e, 0.0, 1.2, 4.2)
            eng.scene.set_scale(obj_e, 0.75, 0.75, 0.75)
            eng.scene.set_mesh(obj_e, S.ship_mesh, { color = {0.25, 0.95, 1.0, 1.0}, metallic = 0.6, roughness = 0.2 })
        else
            eng.scene.set_pos(obj_e, 0.0, 0.0, 4.2)
            eng.procgen.animal(obj_e, seed + 202, "quadruped")
        end

        S.cabinets[i] = {
            idx = i, pocket_id = b.pocket_id, x = d.x, front_z = d.z + 1.1,
            obj_ent = obj_e, obj_z = 4.2, exit_z = 7.8,
            entered = false, won_token = false
        }
    end

    S.sfx_token = eng.audio.synth("triangle", 587.33, 0.18, 1174.66)
    S.sfx_trophy = eng.audio.synth("saw", 523.25, 0.35, 1046.50)

    S.pocket = 0
    S.px, S.py, S.pz = 0.0, 1.35, 2.2
    S.yaw, S.pitch = 0.0, 0.0
    S.spin = 0.0
    S.tokens = 0
    S.cabinets_entered = 0
    S.trophy_unlocked = false
    S.won = false

    eng.input.set_mouse_lock(true)
    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.spin = (S.spin + 90.0 * dt) % 360.0
    if S.trophy_unlocked then
        eng.scene.set_rot_deg(S.trophy_ent, 0.0, S.spin, 0.0)
    end

    local spd = (eng.input.down("fire") or eng.input.down("jump")) and 15.5 or 10.0
    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw, S.pitch, spd, dt)
    if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
        local nx, nz = eng.physics.slide_move(S.pocket, S.px, S.py, S.pz, dx, dz, 0.32)
        nx = eng.math.clamp(nx, -9.5, 9.5)
        local dst_p, wx, wy, wz = eng.portal.check_crossing(S.pocket, S.px, S.py, S.pz, nx, S.py, nz)
        if dst_p then
            S.pocket = dst_p
            S.px, S.py, S.pz = wx, wy, wz
            for i = 1, 3 do
                local c = S.cabinets[i]
                if c.pocket_id == S.pocket and not c.entered then
                    c.entered = true
                    S.cabinets_entered = S.cabinets_entered + 1
                end
            end
        else
            S.px, S.pz = nx, nz
        end
    end

    -- Check mini-cabinet token win when inside a cabinet pocket
    for i = 1, 3 do
        local c = S.cabinets[i]
        if S.pocket == c.pocket_id and not c.won_token then
            if eng.math.dist3(S.px, 0.0, S.pz, 0.0, 0.0, c.obj_z) < 2.2 then
                c.won_token = true
                S.tokens = S.tokens + 1
                eng.audio.play(S.sfx_token, 0.0, 1.2, c.obj_z, c.pocket_id)
                eng.scene.despawn(c.obj_ent)
                if S.tokens >= 3 then
                    S.trophy_unlocked = true
                    eng.scene.set_mesh(S.trophy_ent, S.crystal_mesh, { color = {1.0, 0.86, 0.15, 1.0}, metallic = 0.9, roughness = 0.1 })
                end
            end
        end
    end

    -- Claim Golden Master #100 Trophy back in main Arcade Hall!
    if S.pocket == 0 and S.trophy_unlocked then
        if eng.math.dist3(S.px, 0.0, S.pz, S.trophy_x, 0.0, S.trophy_z) < 2.2 then
            eng.audio.play(S.sfx_trophy, S.trophy_x, 1.4, S.trophy_z, 0)
            S.won = true
            eng.save.write("engine_meta_arcade_100", "golden_master")
        end
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
end

function draw()
    if S.pocket == 0 and S.trophy_unlocked then
        eng.render.draw_sprite(S.trophy_x, 2.35, S.trophy_z, 0.95, 0.95, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | TOKENS " .. S.tokens .. "/3 | CABINETS " .. S.cabinets_entered .. "/3", 1.0, {1.0, 0.88, 0.30, 1.0})
    eng.ui.bar(x, y + 26, 220, S.tokens / 3.0, "ARCADE ")
end
