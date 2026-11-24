-- 050_skyship_trader: Floating Islands Airship & Bigger-on-the-Inside Cargo Hold
local S = game.state

local ISLANDS = {
    { name = "Spice Atoll",      x =   0.0, y = 0.0, z = -14.0, price = 20, col = {0.42, 0.78, 0.38, 1.0} },
    { name = "Cloudspire Port",  x =  15.0, y = 1.0, z = -28.0, price = 70, col = {0.55, 0.72, 0.88, 1.0} },
    { name = "Sunstone Citadel", x = -15.0, y = 1.5, z = -28.0, price = 85, col = {0.92, 0.75, 0.38, 1.0} }
}

local function sync_cargo_crates()
    for i = 1, #S.crate_ents do
        eng.scene.despawn(S.crate_ents[i])
    end
    S.crate_ents = {}
    for i = 1, S.cargo do
        local ce = eng.scene.spawn("spice_crate_" .. i)
        eng.scene.set_pocket(ce, S.hold_pocket)
        local col_x = ((i - 1) % 3 - 1) * 1.6
        local row_z = 1.0 - math.floor((i - 1) / 3) * 1.6
        eng.scene.set_pos(ce, col_x, 0.0, row_z)
        eng.scene.set_mesh(ce, S.crate_mesh, { color = {0.92, 0.58, 0.22, 1.0}, cast_shadow = true })
        S.crate_ents[#S.crate_ents + 1] = ce
    end
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.006 })
    eng.render.set_sky(0.22, 0.52, 0.92, 0.78, 0.86, 0.96)

    -- Sky sunlight in "world" + warm lanterns inside "cargo_hold"
    eng.render.add_light({ type = "dir", pocket = "world", dir = {-0.35, -1.0, -0.4}, color = {2.3, 2.2, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pocket = "cargo_hold", pos = {0.0, 4.8, 2.0}, color = {2.6, 2.0, 1.3}, range = 28.0 })
    eng.render.add_light({ type = "point", pocket = "cargo_hold", pos = {0.0, 4.0, -6.0}, color = {1.8, 2.1, 2.5}, range = 22.0 })

    local seed = math.floor(eng.math.range(100, 700000))
    local wood_tex = eng.procgen.texture("wood_grain", seed, 64)
    local rock_tex = eng.procgen.texture("cobble", seed + 17, 64)
    local tree_mesh = eng.procgen.tree(seed + 31, 2, 3.0, 0.20)

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(1.0, 12, 16)
    S.cyl_mesh = eng.asset.cylinder(0.5, 0.5, 1.0, 16)
    S.ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_trade = eng.audio.synth("triangle", 520, 0.16, 880)
    S.sfx_portal = eng.audio.synth("sine", 400, 0.16, 580)

    -- 3 Floating Sky Islands
    for i = 1, #ISLANDS do
        local isl = ISLANDS[i]
        local rock = eng.scene.spawn("sky_island_" .. i)
        eng.scene.set_pos(rock, isl.x, isl.y - 1.2, isl.z)
        eng.scene.set_scale(rock, 9.5, 2.4, 9.5)
        eng.scene.set_mesh(rock, S.cyl_mesh, { tex = rock_tex, color = isl.col, cast_shadow = true })

        local dock = eng.scene.spawn("island_dock_" .. i)
        eng.scene.set_pos(dock, isl.x, isl.y, isl.z + 3.2)
        eng.scene.set_mesh(dock, S.arch_mesh, { color = {0.88, 0.82, 0.68, 1.0} })

        local te = eng.scene.spawn("island_tree_" .. i)
        eng.scene.set_pos(te, isl.x - 2.2, isl.y, isl.z - 1.5)
        eng.scene.set_mesh(te, tree_mesh, { color = {0.35, 0.72, 0.35, 1.0} })
    end

    -- Airship Exterior (pocket 0) + Bigger-on-the-Inside Cargo Hold!
    S.ship_x, S.ship_y, S.ship_z = 0.0, 2.0, 0.0
    S.ship_ent = eng.scene.spawn("skyship")
    eng.scene.set_pos(S.ship_ent, S.ship_x, S.ship_y, S.ship_z)

    local hull = eng.scene.spawn("skyship_hull")
    eng.scene.set_parent(hull, S.ship_ent)
    eng.scene.set_pos(hull, 0.0, -0.2, 0.5)
    eng.scene.set_scale(hull, 3.2, 0.5, 6.8)
    eng.scene.set_mesh(hull, S.box_mesh, { tex = wood_tex, color = {0.56, 0.36, 0.20, 1.0}, cast_shadow = true })

    local prow = eng.scene.spawn("skyship_prow")
    eng.scene.set_parent(prow, S.ship_ent)
    eng.scene.set_pos(prow, 0.0, 0.1, -2.6)
    eng.scene.set_mesh(prow, S.ship_mesh, { color = {0.72, 0.52, 0.28, 1.0} })

    local balloon = eng.scene.spawn("skyship_balloon")
    eng.scene.set_parent(balloon, S.ship_ent)
    eng.scene.set_pos(balloon, 0.0, 4.4, 0.4)
    eng.scene.set_scale(balloon, 2.4, 1.7, 4.4)
    eng.scene.set_mesh(balloon, S.sphere_mesh, { color = {0.92, 0.84, 0.68, 1.0} })

    S.hold = eng.space.attach_vehicle_interior(eng, S.ship_ent, {
        pocket = "cargo_hold",
        interior_size = {16.0, 6.0, 22.0},
        door_size = {1.4, 2.2},
        door_local_pos = {0.0, 1.1, 1.5},
        mesh_id = S.box_mesh
    })
    S.hold_pocket = S.hold.pocket_id

    -- Interior Cargo Hold Quartermaster & Rib Beams
    for z = -6, 6, 6 do
        for side = -1, 1, 2 do
            local rib = eng.scene.spawn("hold_rib_" .. z .. "_" .. side)
            eng.scene.set_pocket(rib, S.hold_pocket)
            eng.scene.set_pos(rib, side * 6.5, 0.0, z)
            eng.scene.set_scale(rib, 0.9, 1.8, 0.9)
            eng.scene.set_mesh(rib, S.pillar_mesh, { tex = wood_tex, color = {0.52, 0.34, 0.20, 1.0} })
            local rcol = eng.scene.spawn("hold_rib_col_" .. z .. "_" .. side)
            eng.scene.set_pocket(rcol, S.hold_pocket)
            eng.scene.set_pos(rcol, side * 6.5, 1.8, z)
            eng.physics.add_body(rcol, { shape = "aabb", motion = "static", pocket = S.hold_pocket, half_extents = {0.5, 1.8, 0.5} })
        end
    end

    S.qm_x, S.qm_z = 0.0, 4.2
    local qm = eng.scene.spawn("quartermaster")
    eng.scene.set_pocket(qm, S.hold_pocket)
    eng.scene.set_pos(qm, S.qm_x, 0.0, S.qm_z)
    eng.procgen.person(qm, seed + 55)

    S.pocket = 0
    S.piloting = true
    S.deck_x, S.deck_z = 0.0, 2.8 -- aft quarterdeck behind hatch at z=1.5
    S.px, S.py, S.pz = S.ship_x + S.deck_x, S.ship_y + 1.1, S.ship_z + S.deck_z
    S.yaw, S.pitch = 0.0, 0.0

    S.gold = 100
    S.cargo = 0
    S.max_cargo = 6
    S.crate_ents = {}
    S.crates_bought = 0
    S.crates_sold = 0
    S.portal_crossings = 0
    S.trade_cd = 0.0
    S.won = false

    eng.camera.look_at(S.ship_x, S.ship_y + 3.2, S.ship_z + 7.5, S.ship_x, S.ship_y + 0.6, S.ship_z - 10.0, 0)
    eng.mod.emit("post_init")
end

local function docked_island()
    for i = 1, #ISLANDS do
        local isl = ISLANDS[i]
        if eng.math.dist3(S.ship_x, 0, S.ship_z, isl.x, 0, isl.z + 6.0) < 6.5 then
            return isl
        end
    end
    return nil
end

function update(dt)
    if S.won then return end
    S.trade_cd = math.max(0.0, S.trade_cd - dt)

    if S.pocket == 0 and eng.input.pressed("jump") then
        S.piloting = not S.piloting
    end

    if S.pocket == 0 and S.piloting then
        eng.input.set_mouse_lock(false)
        local mx, my = eng.input.axis2d("left", "right", "down", "up")
        -- Fly airship across floating islands
        if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
            S.ship_x = eng.math.clamp(S.ship_x + mx * 16.0 * dt, -26.0, 26.0)
            S.ship_z = eng.math.clamp(S.ship_z - my * 16.0 * dt, -34.0, 8.0)
            eng.scene.set_pos(S.ship_ent, S.ship_x, S.ship_y, S.ship_z)
        end
        S.px, S.py, S.pz = S.ship_x + S.deck_x, S.ship_y + 1.1, S.ship_z + S.deck_z
        eng.camera.look_at(S.ship_x, S.ship_y + 3.2, S.ship_z + 7.5, S.ship_x, S.ship_y + 0.6, S.ship_z - 10.0, 0)
    else
        -- Walk on airship quarterdeck OR inside the bigger-on-the-inside cargo hold!
        local dx, dz
        S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw or 0.0, S.pitch or 0.0, 8.0, dt)
        if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
            local ox, oy, oz = S.px, S.py, S.pz
            local nx = ox + dx
            local nz = oz + dz
            local dst_pk, wx, wy, wz = eng.portal.check_crossing(S.pocket, ox, oy, oz, nx, oy, nz)
            if dst_pk ~= nil then
                S.pocket = dst_pk
                S.px, S.pz = wx, wz
                S.py = (dst_pk == 0) and (S.ship_y + 1.1) or 1.1
                if dst_pk == 0 then
                    S.deck_x = S.px - S.ship_x
                    S.deck_z = S.pz - S.ship_z
                end
                S.portal_crossings = S.portal_crossings + 1
                eng.audio.play(S.sfx_portal, wx, S.py, wz, dst_pk)
            else
                S.px, S.pz = eng.physics.slide_move(S.pocket, ox, oy, oz, dx, dz, 0.40)
                if S.pocket == 0 then
                    S.deck_x = S.px - S.ship_x
                    S.deck_z = S.pz - S.ship_z
                end
            end
        end

        if S.pocket == S.hold_pocket then
            local isl = docked_island()
            local act = eng.input.pressed("fire") or eng.input.pressed("interact") or eng.input.down("fire")
            if isl and act and S.trade_cd <= 0.0 and eng.math.dist3(S.px, 0, S.pz, S.qm_x, 0, S.qm_z) < 2.8 then
                if isl.price <= 30 and S.gold >= isl.price and S.cargo < S.max_cargo then
                    S.gold = S.gold - isl.price
                    S.cargo = S.cargo + 1
                    S.crates_bought = S.crates_bought + 1
                    S.trade_cd = 0.06
                    sync_cargo_crates()
                    eng.audio.play(S.sfx_trade, S.qm_x, 1.2, S.qm_z, S.hold_pocket)
                elseif isl.price > 30 and S.cargo > 0 then
                    S.gold = S.gold + isl.price
                    S.cargo = S.cargo - 1
                    S.crates_sold = S.crates_sold + 1
                    S.trade_cd = 0.06
                    sync_cargo_crates()
                    eng.audio.play(S.sfx_trade, S.qm_x, 1.2, S.qm_z, S.hold_pocket)
                end
            end
            if S.gold >= 260 and S.cargo == 0 then
                S.won = true
                eng.save.write("skyship_trader", "guild_charter")
            end
        end
        eng.camera.set(S.px, S.py + 0.5, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
    end
end

function draw()
    if S.pocket == S.hold_pocket then
        eng.render.draw_sprite(S.qm_x, 2.05, S.qm_z, 0.45, 0.45, S.orb_tex)
    end
    local isl = docked_island()
    local port_txt = isl and (isl.name .. " (" .. isl.price .. "g)") or "OPEN SKY"
    local mode_txt = (S.pocket == S.hold_pocket) and "CARGO HOLD" or (S.piloting and "HELM" or "DECK")
    local x, y = eng.ui.anchor("top_left", 16, 14, 620, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " [" .. mode_txt .. "] | " .. port_txt .. " | GOLD " .. S.gold .. "g | SPICE " .. S.cargo, 1.0, {1.0, 0.90, 0.52, 1.0})
    eng.ui.bar(x, y + 24, 200, S.gold / 260.0, "CHARTER ")
end
