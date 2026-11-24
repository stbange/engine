-- 044_potion_alchemist: Bigger-on-the-Inside Roadside Cart & Grand Alchemist Hall
local S = game.state

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.010 })
    eng.render.set_sky(0.24, 0.48, 0.82, 0.68, 0.78, 0.88)

    -- Exterior sunlight + Grand Hall interior point lights
    eng.render.add_light({ type = "dir", pocket = "world", dir = {-0.35, -1.0, -0.45}, color = {2.2, 2.1, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pocket = "alchemist_hall", pos = {0.0, 6.0, 2.0}, color = {2.6, 2.1, 1.5}, range = 34.0 })
    eng.render.add_light({ type = "point", pocket = "alchemist_hall", pos = {0.0, 3.5, -5.0}, color = {1.2, 2.5, 1.8}, range = 24.0 })

    local seed = math.floor(eng.math.range(100, 700000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.5, 0.5, 1.0, 14)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_herb = eng.audio.synth("triangle", 520, 0.12, 780)
    S.sfx_brew = eng.audio.synth("sine", 300, 0.22, 640)
    S.sfx_portal = eng.audio.synth("sine", 420, 0.18, 560)

    -- Meadow floor & roadside L-system trees in outer "world" pocket (0)
    local grass_tex = eng.procgen.texture("grass", seed, 64)
    local wood_tex = eng.procgen.texture("wood_grain", seed + 9, 64)
    local meadow = eng.scene.spawn("meadow_floor")
    eng.scene.set_pos(meadow, 0.0, -0.25, -2.0)
    eng.scene.set_scale(meadow, 36.0, 0.5, 36.0)
    eng.scene.set_mesh(meadow, S.box_mesh, { tex = grass_tex, color = {0.48, 0.76, 0.38, 1.0} })

    local tree_mesh = eng.procgen.tree(seed + 15, 2, 3.4, 0.22)
    local tree_pts = { {-7.5, -3.0}, {7.5, -3.0}, {-6.5, -9.5}, {6.5, -9.5}, {-8.0, 3.0}, {8.0, 3.0} }
    for i = 1, #tree_pts do
        local te = eng.scene.spawn("meadow_tree_" .. i)
        eng.scene.set_pos(te, tree_pts[i][1], 0.0, tree_pts[i][2])
        eng.scene.set_mesh(te, tree_mesh, { color = {0.35, 0.68, 0.32, 1.0}, cast_shadow = true })
    end

    -- Tiny 2.8m x 2.6m x 2.8m Roadside Wooden Cart -> 22m x 9m x 26m Grand Alchemist Hall!
    S.cart = eng.space.create_pocket_building(eng, {
        exterior_pos = {0.0, 0.0, -5.0},
        exterior_size = {2.8, 2.6, 2.8},
        interior_size = {22.0, 9.0, 26.0},
        door_size = {1.3, 2.1},
        outer_pocket = "world",
        pocket = "alchemist_hall",
        mesh_id = S.box_mesh,
        exterior_color = {0.58, 0.36, 0.20, 1.0},
        interior_color = {0.32, 0.26, 0.42, 1.0}
    })
    S.hall_pocket = S.cart.pocket_id

    -- 4 Wooden Cart Wheels on exterior roadside cart
    local woffs = { {-1.5, -4.1}, {1.5, -4.1}, {-1.5, -5.9}, {1.5, -5.9} }
    for i = 1, #woffs do
        local we = eng.scene.spawn("cart_wheel_" .. i)
        eng.scene.set_pos(we, woffs[i][1], 0.48, woffs[i][2])
        eng.scene.set_rot_deg(we, 0.0, 0.0, 90.0)
        eng.scene.set_scale(we, 0.95, 0.18, 0.95)
        eng.scene.set_mesh(we, S.cyl_mesh, { tex = wood_tex, color = {0.42, 0.26, 0.14, 1.0} })
    end

    -- Wild Herbs outside in meadow (pocket 0)
    local herb_coords = { {-2.4, 1.8}, {2.4, 1.8}, {-2.8, -0.8}, {2.8, -0.8} }
    local herb_cols = { {0.95, 0.35, 0.45, 1.0}, {0.35, 0.95, 0.65, 1.0}, {1.0, 0.85, 0.25, 1.0}, {0.55, 0.75, 1.0, 1.0} }
    S.herb_nodes = {}
    for i = 1, #herb_coords do
        local hx, hz = herb_coords[i][1], herb_coords[i][2]
        local he = eng.scene.spawn("wild_herb_" .. i)
        eng.scene.set_pos(he, hx, 0.0, hz)
        eng.scene.set_scale(he, 0.75, 0.75, 0.75)
        eng.scene.set_mesh(he, S.crystal_mesh, { color = herb_cols[i] })
        S.herb_nodes[i] = { ent = he, x = hx, z = hz, picked = false }
    end

    -- Grand Alchemist Hall interior props (columns, glowing cauldron, apothecary shelves & 3 customers)
    for z = -8, 8, 8 do
        for side = -1, 1, 2 do
            local col = eng.scene.spawn("hall_col_" .. z .. "_" .. side)
            eng.scene.set_pocket(col, S.hall_pocket)
            eng.scene.set_pos(col, side * 8.0, 0.0, z)
            eng.scene.set_scale(col, 1.2, 2.2, 1.2)
            eng.scene.set_mesh(col, S.pillar_mesh, { color = {0.72, 0.68, 0.82, 1.0} })
        end
    end

    S.cauldron_x, S.cauldron_z = 0.0, 3.0
    local caul = eng.scene.spawn("grand_cauldron")
    eng.scene.set_pocket(caul, S.hall_pocket)
    eng.scene.set_pos(caul, S.cauldron_x, 0.65, S.cauldron_z)
    eng.scene.set_scale(caul, 1.8, 1.3, 1.8)
    eng.scene.set_mesh(caul, S.cyl_mesh, { color = {0.22, 0.24, 0.28, 1.0}, metallic = 0.7, roughness = 0.35 })

    local brew_top = eng.scene.spawn("cauldron_liquid")
    eng.scene.set_pocket(brew_top, S.hall_pocket)
    eng.scene.set_pos(brew_top, S.cauldron_x, 1.28, S.cauldron_z)
    eng.scene.set_scale(brew_top, 1.55, 0.12, 1.55)
    eng.scene.set_mesh(brew_top, S.cyl_mesh, { color = {0.25, 1.0, 0.58, 1.0} })

    local cust_pos = { {-3.2, -3.5}, {0.0, -5.0}, {3.2, -3.5} }
    S.customers = {}
    for i = 1, 3 do
        local cx, cz = cust_pos[i][1], cust_pos[i][2]
        local ce = eng.scene.spawn("customer_" .. i)
        eng.scene.set_pocket(ce, S.hall_pocket)
        eng.scene.set_pos(ce, cx, 0.0, cz)
        local info = eng.procgen.person(ce, seed + i * 53)
        S.customers[i] = { ent = ce, x = cx, z = cz, name = info.name, served = false }
    end

    S.pocket = 0
    S.px, S.py, S.pz = 0.0, 1.1, 4.2
    S.yaw, S.pitch = 0.0, 0.0
    S.herbs = 0
    S.herbs_foraged = 0
    S.potions = 0
    S.potions_brewed = 0
    S.customers_served = 0
    S.portal_crossings = 0
    S.gold = 0
    S.won = false

    eng.input.set_mouse_lock(true)
    eng.camera.set(S.px, 1.5, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw, S.pitch, 7.2, dt)
    if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
        local ox, oy, oz = S.px, S.py, S.pz
        local nx = ox + dx
        local nz = oz + dz
        local dst_pk, wx, wy, wz = eng.portal.check_crossing(S.pocket, ox, oy, oz, nx, oy, nz)
        if dst_pk ~= nil then
            S.pocket = dst_pk
            S.px, S.py, S.pz = wx, 1.1, wz
            S.portal_crossings = S.portal_crossings + 1
            eng.audio.play(S.sfx_portal, wx, 1.1, wz, dst_pk)
        else
            S.px, S.pz = nx, nz
        end
    end

    local act = eng.input.pressed("interact") or eng.input.pressed("fire") or eng.input.down("fire")

    if S.pocket == 0 then
        -- Forage wild herbs in outer meadow
        for i = 1, #S.herb_nodes do
            local h = S.herb_nodes[i]
            if not h.picked and eng.math.dist3(S.px, 0, S.pz, h.x, 0, h.z) < 1.9 then
                h.picked = true
                S.herbs = S.herbs + 1
                S.herbs_foraged = S.herbs_foraged + 1
                eng.audio.play(S.sfx_herb, h.x, 0.6, h.z, 0)
                eng.scene.despawn(h.ent)
            end
        end
    elseif S.pocket == S.hall_pocket then
        -- Brew herbs into potions at the Grand Cauldron
        if S.herbs > 0 and (act or eng.math.dist3(S.px, 0, S.pz, S.cauldron_x, 0, S.cauldron_z) < 2.3) then
            if eng.math.dist3(S.px, 0, S.pz, S.cauldron_x, 0, S.cauldron_z) < 2.6 then
                S.potions = S.potions + S.herbs
                S.potions_brewed = S.potions_brewed + S.herbs
                S.herbs = 0
                eng.audio.play(S.sfx_brew, S.cauldron_x, 1.2, S.cauldron_z, S.hall_pocket)
            end
        end

        -- Serve brewed potions to waiting procedural customers
        for i = 1, #S.customers do
            local c = S.customers[i]
            if not c.served and S.potions > 0 and eng.math.dist3(S.px, 0, S.pz, c.x, 0, c.z) < 2.4 then
                c.served = true
                S.potions = S.potions - 1
                S.customers_served = S.customers_served + 1
                S.gold = S.gold + 40
                eng.audio.play(S.sfx_brew, c.x, 1.2, c.z, S.hall_pocket)
            end
        end

        if S.customers_served >= 3 then
            S.won = true
            eng.save.write("alchemist_progress", "master_brewer")
        end
    end

    eng.camera.set(S.px, 1.5, S.pz, S.pitch, S.yaw, 0.0, S.pocket)
end

function draw()
    if S.pocket == S.hall_pocket then
        for i = 1, #S.customers do
            local c = S.customers[i]
            if not c.served then
                eng.render.draw_sprite(c.x, 2.05, c.z, 0.45, 0.45, S.orb_tex)
            end
        end
    end
    local loc = (S.pocket == S.hall_pocket) and "GRAND HALL" or "ROADSIDE"
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " [" .. loc .. "] | HERBS " .. S.herbs .. " | POTIONS " .. S.potions .. " | SERVED " .. S.customers_served .. "/3", 1.0, {0.65, 1.0, 0.78, 1.0})
    eng.ui.bar(x, y + 26, 200, S.customers_served / 3.0, "ORDERS ")
end
