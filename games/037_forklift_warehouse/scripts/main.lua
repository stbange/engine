-- 037_forklift_warehouse: Load crate.obj pallets into a compact delivery truck that is Bigger on the Inside
local S = game.state

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.010 })
    eng.render.set_sky(0.28, 0.50, 0.78, 0.72, 0.78, 0.84)

    eng.render.add_light({ type = "dir", pocket = "world", dir = {-0.35, -1.0, -0.45}, color = {2.2, 2.1, 1.95}, shadow = true })
    eng.render.add_light({ type = "dir", pocket = "truck_cargo_bay", dir = {-0.2, -1.0, -0.3}, color = {1.5, 1.55, 1.7} })
    eng.render.add_light({ type = "point", pocket = "truck_cargo_bay", pos = {0.0, 6.2, 4.0}, color = {2.6, 2.4, 2.0}, range = 34.0 })

    local seed = math.floor(eng.math.range(100, 90000))
    local asphalt_tex = eng.procgen.texture("cobble", seed, 64)
    local metal_tex = eng.procgen.texture("metal_rivets", seed + 11, 64)
    local wood_tex = eng.procgen.texture("wood_grain", seed + 23, 64)

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.wheel_mesh = eng.asset.cylinder(0.45, 0.45, 0.24, 12)
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_lift = eng.audio.synth("triangle", 320, 0.14, 580)
    S.sfx_drop = eng.audio.synth("sine", 480, 0.18, 860)
    S.sfx_portal = eng.audio.synth("sine", 360, 0.15, 620)

    -- Loading yard concrete apron in outer "world" pocket (0)
    local yard = eng.scene.spawn("warehouse_yard")
    eng.scene.set_pos(yard, 0.0, -0.25, -2.0)
    eng.scene.set_scale(yard, 34.0, 0.5, 32.0)
    eng.scene.set_mesh(yard, S.box_mesh, { tex = asphalt_tex, color = {0.52, 0.54, 0.58, 1.0}, roughness = 0.85 })
    eng.physics.add_body(yard, { shape = "aabb", motion = "static", half_extents = {17.0, 0.25, 16.0} })

    -- Compact 3.2m x 2.9m x 4.2m Delivery Truck -> 20m x 8m x 24m Pocket Cargo Megabay!
    -- Rear doorway d_ext is at (0.0, 1.15, -3.4); interior d_int is at (0.0, 1.15, 11.8)
    S.truck = eng.space.create_pocket_building(eng, {
        exterior_pos = {0.0, 0.0, -5.5},
        exterior_size = {3.2, 2.9, 4.2},
        interior_size = {20.0, 8.0, 24.0},
        door_size = {2.1, 2.3},
        outer_pocket = "world",
        pocket = "truck_cargo_bay",
        mesh_id = S.box_mesh,
        exterior_color = {0.92, 0.72, 0.18, 1.0},
        interior_color = {0.30, 0.35, 0.42, 1.0}
    })
    S.bay_pocket = S.truck.pocket_id

    -- Exterior truck cab, rear loading ramp lip (visual, flush near ground), and 4 wheels
    local cab = eng.scene.spawn("truck_cab")
    eng.scene.set_pos(cab, 0.0, 1.05, -8.5)
    eng.scene.set_scale(cab, 2.8, 2.1, 1.8)
    eng.scene.set_mesh(cab, S.box_mesh, { tex = metal_tex, color = {0.20, 0.45, 0.85, 1.0}, cast_shadow = true })

    local ramp = eng.scene.spawn("truck_rear_ramp")
    eng.scene.set_pos(ramp, 0.0, 0.04, -2.75)
    eng.scene.set_scale(ramp, 2.1, 0.08, 1.3)
    eng.scene.set_mesh(ramp, S.box_mesh, { tex = metal_tex, color = {0.62, 0.65, 0.70, 1.0} })

    local wheel_xz = { {-1.72, -4.3}, {1.72, -4.3}, {-1.72, -7.8}, {1.72, -7.8} }
    for i = 1, #wheel_xz do
        local w = eng.scene.spawn("truck_wheel_" .. tostring(i))
        eng.scene.set_pos(w, wheel_xz[i][1], 0.45, wheel_xz[i][2])
        eng.scene.set_rot_deg(w, 0.0, 0.0, 90.0)
        eng.scene.set_mesh(w, S.wheel_mesh, { color = {0.16, 0.17, 0.20, 1.0} })
    end

    -- Oversized Cargo Megabay interior columns & 3 wide-spaced Drop-Off Slots (wider than exterior truck!)
    for side = -1, 1, 2 do
        for z = -6, 6, 6 do
            local col = eng.scene.spawn("bay_pillar_" .. tostring(side) .. "_" .. tostring(z))
            eng.scene.set_pocket(col, S.bay_pocket)
            eng.scene.set_pos(col, side * 8.2, 0.0, z)
            eng.scene.set_scale(col, 1.1, 2.4, 1.1)
            eng.scene.set_mesh(col, S.pillar_mesh, { color = {0.68, 0.72, 0.78, 1.0} })
        end
    end

    local slot_xz = { {-4.2, 5.2}, {0.0, 3.0}, {4.2, 5.2} }
    S.slots = {}
    for i = 1, #slot_xz do
        local sx, sz = slot_xz[i][1], slot_xz[i][2]
        local pad = eng.scene.spawn("cargo_slot_" .. tostring(i))
        eng.scene.set_pocket(pad, S.bay_pocket)
        eng.scene.set_pos(pad, sx, 0.04, sz)
        eng.scene.set_scale(pad, 1.6, 0.08, 1.6)
        eng.scene.set_mesh(pad, S.box_mesh, { color = {0.22, 0.95, 0.55, 1.0} })
        S.slots[i] = { x = sx, z = sz, filled = false, pad_ent = pad }
    end

    -- 3 Warehouse Crate Pallets in outer yard
    local pal_xz = { {-3.8, 1.6}, {3.8, 1.6}, {-3.4, -0.8} }
    S.pallets = {}
    for i = 1, #pal_xz do
        local px, pz = pal_xz[i][1], pal_xz[i][2]
        local pe = eng.scene.spawn("pallet_" .. tostring(i))
        eng.scene.set_pos(pe, px, 0.0, pz)

        local skid = eng.scene.spawn("pallet_skid_" .. tostring(i))
        eng.scene.set_parent(skid, pe)
        eng.scene.set_pos(skid, 0.0, 0.07, 0.0)
        eng.scene.set_scale(skid, 1.15, 0.14, 1.15)
        eng.scene.set_mesh(skid, S.box_mesh, { tex = wood_tex, color = {0.68, 0.48, 0.26, 1.0} })

        local cr = eng.scene.spawn("pallet_crate_" .. tostring(i))
        eng.scene.set_parent(cr, pe)
        eng.scene.set_pos(cr, 0.0, 0.14, 0.0)
        eng.scene.set_mesh(cr, S.crate_mesh, { color = {0.88, 0.66, 0.34, 1.0}, cast_shadow = true })

        S.pallets[i] = { ent = pe, x = px, z = pz, state = "yard" }
    end

    -- Forklift vehicle rig (chassis + mast + forks + carried crate preview)
    S.fork_ent = eng.scene.spawn("forklift")
    local body = eng.scene.spawn("forklift_chassis")
    eng.scene.set_parent(body, S.fork_ent)
    eng.scene.set_pos(body, 0.0, 0.52, 0.15)
    eng.scene.set_scale(body, 1.05, 0.85, 1.45)
    eng.scene.set_mesh(body, S.box_mesh, { tex = metal_tex, color = {0.98, 0.55, 0.12, 1.0}, cast_shadow = true })

    local mast = eng.scene.spawn("forklift_mast")
    eng.scene.set_parent(mast, S.fork_ent)
    eng.scene.set_pos(mast, 0.0, 0.95, -0.62)
    eng.scene.set_scale(mast, 0.85, 1.65, 0.12)
    eng.scene.set_mesh(mast, S.box_mesh, { color = {0.22, 0.24, 0.28, 1.0} })

    S.tines_ent = eng.scene.spawn("forklift_tines")
    eng.scene.set_parent(S.tines_ent, S.fork_ent)
    eng.scene.set_pos(S.tines_ent, 0.0, 0.18, -1.05)
    eng.scene.set_scale(S.tines_ent, 0.82, 0.08, 0.95)
    eng.scene.set_mesh(S.tines_ent, S.box_mesh, { color = {0.32, 0.35, 0.40, 1.0} })

    S.pocket = 0
    S.fx, S.fz = 0.0, 3.6
    S.yaw = 0.0
    S.carrying = nil
    S.delivered = 0
    S.portal_crossings = 0
    S.score = 0
    S.won = false

    sync_forklift_cam()
    eng.mod.emit("post_init")
end

function sync_forklift_cam()
    eng.scene.set_pocket(S.fork_ent, S.pocket)
    eng.scene.set_pos(S.fork_ent, S.fx, 0.0, S.fz)
    eng.scene.set_rot_deg(S.fork_ent, 0.0, S.yaw, 0.0)
    if S.pocket == 0 then
        eng.camera.look_at(S.fx, 6.2, S.fz + 7.2, S.fx, 0.9, S.fz - 3.0, 0)
    else
        eng.camera.look_at(S.fx, 5.6, math.min(11.4, S.fz + 6.2), S.fx, 0.9, S.fz - 3.0, S.bay_pocket)
    end
end

function update(dt)
    if S.won then return end

    local ix, iy = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(ix) > 0.01 or math.abs(iy) > 0.01 then
        local speed = 14.0
        local ox, oz = S.fx, S.fz
        local nx = ox + ix * speed * dt
        local nz = oz - iy * speed * dt
        S.yaw = math.deg(math.atan2(-ix, iy))

        local dst_pk, wx, _, wz = eng.portal.check_crossing(S.pocket, ox, 1.0, oz, nx, 1.0, nz)
        if dst_pk ~= nil then
            S.pocket = dst_pk
            S.fx, S.fz = wx, wz
            S.portal_crossings = S.portal_crossings + 1
            if S.carrying then
                eng.scene.set_pocket(S.pallets[S.carrying].ent, dst_pk)
            end
            eng.audio.play(S.sfx_portal, wx, 1.0, wz, dst_pk)
        else
            local sx, sz = eng.physics.slide_move(S.pocket, ox, 1.0, oz, nx - ox, nz - oz, 0.50)
            if S.pocket == 0 then
                S.fx = eng.math.clamp(sx, -12.0, 12.0)
                S.fz = eng.math.clamp(sz, -4.2, 10.0)
            else
                S.fx = eng.math.clamp(sx, -8.5, 8.5)
                S.fz = eng.math.clamp(sz, -10.5, 12.4)
            end
        end
    end

    if S.pocket == 0 and S.carrying == nil then
        for i = 1, #S.pallets do
            local p = S.pallets[i]
            if p.state == "yard" and eng.math.dist3(S.fx, 0, S.fz, p.x, 0, p.z) < 1.55 then
                p.state = "carried"
                S.carrying = i
                eng.scene.set_parent(p.ent, S.fork_ent)
                eng.scene.set_pos(p.ent, 0.0, 0.42, -1.05)
                eng.scene.set_pos(S.tines_ent, 0.0, 0.40, -1.05)
                S.score = S.score + 100
                eng.audio.play(S.sfx_lift, p.x, 0.8, p.z, 0)
                break
            end
        end
    elseif S.pocket == S.bay_pocket and S.carrying ~= nil then
        for i = 1, #S.slots do
            local sl = S.slots[i]
            if not sl.filled and eng.math.dist3(S.fx, 0, S.fz, sl.x, 0, sl.z) < 1.65 then
                local p = S.pallets[S.carrying]
                sl.filled = true
                p.state = "stowed"
                S.carrying = nil
                S.delivered = S.delivered + 1
                S.score = S.score + 300
                eng.scene.set_parent(p.ent)
                eng.scene.set_pocket(p.ent, S.bay_pocket)
                eng.scene.set_pos(p.ent, sl.x, 0.08, sl.z)
                eng.scene.set_rot_deg(p.ent, 0.0, 0.0, 0.0)
                eng.scene.set_pos(S.tines_ent, 0.0, 0.18, -1.05)
                eng.audio.play(S.sfx_drop, sl.x, 0.8, sl.z, S.bay_pocket)
                if S.delivered >= 3 then
                    S.won = true
                    eng.save.write("forklift_warehouse_clear", tostring(S.score))
                end
                break
            end
        end
    end

    sync_forklift_cam()
end

function draw()
    if S.pocket == 0 and S.carrying == nil then
        for i = 1, #S.pallets do
            local p = S.pallets[i]
            if p.state == "yard" then
                eng.render.draw_sprite(p.x, 1.65, p.z, 0.55, 0.55, S.orb_tex)
            end
        end
    elseif S.pocket == S.bay_pocket and S.carrying ~= nil then
        for i = 1, #S.slots do
            local sl = S.slots[i]
            if not sl.filled then
                eng.render.draw_sprite(sl.x, 1.45, sl.z, 0.60, 0.60, S.orb_tex)
            end
        end
    end

    local loc = (S.pocket == S.bay_pocket) and "[TRUCK MEGABAY 20x24m]" or "[YARD]"
    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 54, 1280, 720)
    local label = S.won and eng.i18n.t("victory") or
        string.format("%s %s | STOWED %d/3 | SCORE %d", eng.i18n.t("title"), loc, S.delivered, S.score)
    eng.ui.label(x, y, label, 1.0, {1.0, 0.88, 0.36, 1.0})
    eng.ui.bar(x, y + 26, 220, S.delivered / 3.0, "CARGO ")
end
