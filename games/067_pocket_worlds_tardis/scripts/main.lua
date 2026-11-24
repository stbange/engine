-- 067_pocket_worlds_tardis: Nested bigger-on-the-inside puzzle (world -> grand_hall -> chest_vault [scale_ratio=0.5] -> outer obelisk)
local S = game.state
local POCKET_NAMES = { [0] = "COURTYARD", [1] = "GRAND HALL", [2] = "MINI CHEST VAULT" }

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.05, 0.10, 0.24, 0.20, 0.28, 0.44)

    -- Lighting across all 3 nested pocket spaces
    eng.render.add_light({ type = "dir", pocket = "world", dir = {-0.3, -1.0, -0.4}, color = {2.1, 2.0, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pocket = "grand_hall", pos = {0.0, 6.5, 0.0}, color = {2.6, 2.2, 1.7}, range = 36.0 })
    eng.render.add_light({ type = "point", pocket = "chest_vault", pos = {0.0, 4.0, 0.0}, color = {2.2, 1.4, 2.8}, range = 24.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.sfx_warp = eng.audio.synth("sine", 360, 0.18, 720)
    S.sfx_key = eng.audio.synth("triangle", 580, 0.22, 1080)

    local seed_base = math.floor(eng.math.range(100, 9000))
    local stone_tex = eng.procgen.texture("stone_brick", seed_base, 64)

    -- Pocket 0 ("world"): Courtyard + Tiny Blue Booth + Locked Outer Time Obelisk
    local yard = eng.scene.spawn("courtyard_floor")
    eng.scene.set_pocket(yard, "world")
    eng.scene.set_pos(yard, 0.0, -0.25, 0.0)
    eng.scene.set_scale(yard, 26.0, 0.5, 26.0)
    eng.scene.set_mesh(yard, S.box_mesh, { tex = stone_tex, color = {0.48, 0.52, 0.56, 1.0} })
    eng.physics.add_body(yard, { shape = "aabb", motion = "static", pocket = 0, half_extents = {13.0, 0.25, 13.0} })

    S.booth = eng.space.create_pocket_building(eng, {
        outer_pocket = "world",
        pocket = "grand_hall",
        exterior_pos = {0.0, 0.0, -5.0},
        exterior_size = {2.4, 2.8, 2.4},
        interior_size = {22.0, 9.0, 26.0},
        door_size = {1.2, 2.2},
        scale_ratio = 1.0,
        exterior_color = {0.10, 0.28, 0.80, 1.0},
        interior_color = {0.30, 0.34, 0.46, 1.0},
        mesh_id = S.box_mesh
    })

    local lamp = eng.scene.spawn("booth_beacon")
    eng.scene.set_pocket(lamp, "world")
    eng.scene.set_pos(lamp, 0.0, 2.9, -5.0)
    eng.scene.set_scale(lamp, 0.4, 0.45, 0.4)
    eng.scene.set_mesh(lamp, S.crystal_mesh, { color = {0.75, 0.92, 1.0, 1.0} })

    S.obelisk_x, S.obelisk_z = 5.0, -4.0
    S.obelisk = eng.scene.spawn("outer_time_obelisk")
    eng.scene.set_pocket(S.obelisk, "world")
    eng.scene.set_pos(S.obelisk, S.obelisk_x, 0.0, S.obelisk_z)
    eng.scene.set_scale(S.obelisk, 1.2, 1.35, 1.2)
    eng.scene.set_mesh(S.obelisk, S.pillar_mesh, { color = {0.75, 0.58, 0.22, 1.0}, cast_shadow = true })

    S.obelisk_gem = eng.scene.spawn("obelisk_crown")
    eng.scene.set_pocket(S.obelisk_gem, "world")
    eng.scene.set_pos(S.obelisk_gem, S.obelisk_x, 4.1, S.obelisk_z)
    eng.scene.set_mesh(S.obelisk_gem, S.crystal_mesh, { color = {0.9, 0.25, 0.3, 1.0} })

    -- Pocket 1 ("grand_hall"): Vast cathedral colonnade + Nested Miniature Chest (scale_ratio = 0.5!)
    for i = -1, 1 do
        for side = -1, 1, 2 do
            local col = eng.scene.spawn("hall_column_" .. tostring(i) .. "_" .. tostring(side))
            eng.scene.set_pocket(col, S.booth.pocket_id)
            eng.scene.set_pos(col, side * 5.5, 0.0, i * 6.5)
            eng.scene.set_scale(col, 1.2, 1.8, 1.2)
            eng.scene.set_mesh(col, S.pillar_mesh, { tex = stone_tex, color = {0.78, 0.76, 0.84, 1.0} })
        end
    end

    S.chest = eng.space.create_pocket_building(eng, {
        outer_pocket = "grand_hall",
        pocket = "chest_vault",
        exterior_pos = {0.0, 0.0, -6.0},
        exterior_size = {1.8, 1.8, 1.8},
        interior_size = {14.0, 6.0, 16.0},
        door_size = {1.0, 1.6},
        scale_ratio = 0.5,
        exterior_color = {0.72, 0.50, 0.16, 1.0},
        interior_color = {0.42, 0.24, 0.52, 1.0},
        mesh_id = S.box_mesh
    })

    -- Pocket 2 ("chest_vault"): Miniature chest vault holding the Chrono-Key + 2-hop raycast shrine
    local shrine = eng.scene.spawn("vault_shrine")
    eng.scene.set_pocket(shrine, S.chest.pocket_id)
    eng.scene.set_pos(shrine, 0.0, 1.0, -4.5)
    eng.scene.set_scale(shrine, 1.2, 2.0, 1.2)
    eng.scene.set_mesh(shrine, S.box_mesh, { color = {0.65, 0.45, 0.88, 1.0} })
    eng.physics.add_body(shrine, { shape = "aabb", motion = "static", pocket = S.chest.pocket_id, half_extents = {0.6, 1.0, 0.6} })

    S.key_x, S.key_z = 0.0, -1.5
    S.key_ent = eng.scene.spawn("chrono_key")
    eng.scene.set_pocket(S.key_ent, S.chest.pocket_id)
    eng.scene.set_pos(S.key_ent, S.key_x, 0.45, S.key_z)
    eng.scene.set_scale(S.key_ent, 0.7, 0.7, 0.7)
    eng.scene.set_mesh(S.key_ent, S.crystal_mesh, { color = {1.0, 0.88, 0.22, 1.0} })

    local ornament = eng.scene.spawn("vault_relic_chest")
    eng.scene.set_pocket(ornament, S.chest.pocket_id)
    eng.scene.set_pos(ornament, -2.5, 0.0, -2.0)
    eng.scene.set_mesh(ornament, S.chest_mesh, { color = {0.85, 0.62, 0.24, 1.0} })

    -- Verify 2-hop cross-portal sightline right from Courtyard -> Grand Hall -> Mini Chest Vault!
    local ray = eng.physics.raycast(0, 0.0, 0.9, 1.0, 0.0, 0.0, -1.0, 60.0)
    S.two_hop_sightline = (ray ~= nil and ray.portal_hops >= 2 and ray.pocket_id == S.chest.pocket_id)

    S.pocket = 0
    S.px, S.py, S.pz = 0.0, 0.85, 2.2
    S.yaw, S.pitch = 0.0, 0.0
    S.player_scale = 1.0
    S.portal_hops = 0
    S.visited_hall = false
    S.visited_vault = false
    S.has_chrono_key = false
    S.won = false

    eng.input.set_mouse_lock(true)
    eng.camera.set(S.px, S.py + 0.45, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    local speed = 9.5 * S.player_scale
    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw, S.pitch, speed, dt)
    if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
        local nx = S.px + dx
        local nz = S.pz + dz

        local dst_pk, wx, wy, wz = eng.portal.check_crossing(S.pocket, S.px, S.py, S.pz, nx, S.py, nz)
        if dst_pk ~= nil then
            if S.pocket == S.booth.pocket_id and dst_pk == S.chest.pocket_id then
                S.player_scale = S.player_scale * 0.5
            elseif S.pocket == S.chest.pocket_id and dst_pk == S.booth.pocket_id then
                S.player_scale = S.player_scale * 2.0
            end
            S.pocket = dst_pk
            S.px, S.py, S.pz = wx, wy, wz
            S.portal_hops = S.portal_hops + 1
            if dst_pk == S.booth.pocket_id then S.visited_hall = true end
            if dst_pk == S.chest.pocket_id then S.visited_vault = true end
            eng.audio.play(S.sfx_warp, S.px, S.py, S.pz, S.pocket)
        else
            S.px, S.pz = nx, nz
        end
    end

    if S.pocket == S.chest.pocket_id and not S.has_chrono_key then
        if eng.math.dist3(S.px, 0.0, S.pz, S.key_x, 0.0, S.key_z) < 1.2 then
            S.has_chrono_key = true
            eng.audio.play(S.sfx_key, S.key_x, 0.5, S.key_z, S.pocket)
            eng.scene.despawn(S.key_ent)
            eng.save.write("pocket_worlds_tardis", "chrono_key")
        end
    end

    if S.pocket == 0 and S.has_chrono_key then
        if eng.math.dist3(S.px, 0.0, S.pz, S.obelisk_x, 0.0, S.obelisk_z) < 2.2 then
            S.won = true
            eng.scene.set_mesh(S.obelisk_gem, S.crystal_mesh, { color = {0.25, 1.0, 0.65, 1.0} })
            eng.audio.play(S.sfx_key, S.obelisk_x, 2.0, S.obelisk_z, 0)
            eng.save.write("pocket_worlds_tardis", "clear")
        end
    end

    eng.camera.set(S.px, S.py + 0.4 * S.player_scale, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
end

function draw()
    local pk_label = POCKET_NAMES[S.pocket] or ("POCKET " .. tostring(S.pocket))
    local key_str = S.has_chrono_key and "KEY: YES" or "KEY: NO"
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | " .. pk_label .. " | SCALE " .. string.format("%.1fx", S.player_scale) .. " | " .. key_str, 1.0, {0.65, 0.92, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.won and 1.0 or (S.has_chrono_key and 0.66 or (S.visited_hall and 0.33 or 0.1)), "QUEST ")
end
