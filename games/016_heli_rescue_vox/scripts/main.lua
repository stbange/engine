-- 016_heli_rescue_vox: Voxel rescue chopper with a Bigger-on-the-Inside medevac cabin (eng.space.attach_vehicle_interior)
local S = game.state

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.012 })
    eng.render.set_sky(0.10, 0.28, 0.56, 0.45, 0.68, 0.85)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {2.2, 2.1, 1.95}, shadow = true })
    eng.render.add_light({ type = "dir", pocket = "medevac_cabin", dir = {-0.2, -1.0, -0.3}, color = {1.5, 1.6, 1.8} })
    eng.render.add_light({ type = "point", pocket = "medevac_cabin", pos = {0.0, 4.2, 0.0}, color = {2.2, 2.5, 2.8}, range = 30.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.mine_mesh = eng.asset.sphere(0.65, 8, 10)
    S.flare_mesh = eng.asset.sphere(0.22, 6, 8)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    local sea_tex = eng.procgen.texture("water_caustics", S.seed, 64)

    S.sfx_winch = eng.audio.synth("triangle", 460, 0.16, 860)
    S.sfx_heal = eng.audio.synth("sine", 540, 0.22, 1080)
    S.sfx_flare = eng.audio.synth("square", 380, 0.09, 180)
    S.sfx_portal = eng.audio.synth("sine", 320, 0.14, 640)

    -- Voxel rescue chopper fuselage & spinning rotor built from ASCII layers
    local heli_vox = eng.asset.voxel_ascii({
        "..44..\n.4444.\n.4774.\n.4774.\n.4444.\n..11..",
        "..44..\n.4554.\n.4..4.\n.4..4.\n.4..4.\n..44..",
        "..77..\n.7777.\n.7777.\n.7777.\n..44..\n..44.."
    }, 6, 3, 6, 0.45)
    local rotor_vox = eng.asset.voxel_ascii({
        "...1...\n...1...\n...1...\n1117111\n...1...\n...1...\n...1..."
    }, 7, 1, 7, 0.42)
    local island_vox = eng.asset.voxel_ascii({
        "333333\n333333\n333333\n333333\n333333\n333333",
        ".2222.\n226622\n266662\n266662\n226622\n.2222."
    }, 6, 2, 6, 0.9)

    local sea_e = eng.scene.spawn("flooded_sea")
    eng.scene.set_pos(sea_e, 0.0, -0.35, 0.0)
    eng.scene.set_scale(sea_e, 90.0, 0.5, 90.0)
    eng.scene.set_mesh(sea_e, S.box_mesh, { tex = sea_tex, roughness = 0.2 })
    eng.physics.add_body(sea_e, { shape = "aabb", motion = "static", half_extents = {45.0, 0.25, 45.0} })

    -- Base Helipad at (0, 0, 12) + 2 Stranded Voxel Islands
    S.base_x, S.base_z = 0.0, 12.0
    local pad_e = eng.scene.spawn("base_helipad")
    eng.scene.set_pos(pad_e, S.base_x - 2.7, 0.0, S.base_z - 2.7)
    eng.scene.set_mesh(pad_e, island_vox, { color = {0.85, 0.9, 0.95, 1.0}, cast_shadow = true })

    S.hx, S.hy, S.hz = 0.0, 2.2, 12.0
    S.rotor_ang = 0.0
    S.heli_ent = eng.scene.spawn("rescue_chopper")
    eng.scene.set_pos(S.heli_ent, S.hx, S.hy, S.hz)
    eng.scene.set_mesh(S.heli_ent, heli_vox, { cast_shadow = true })

    S.rotor_ent = eng.scene.spawn("chopper_rotor")
    eng.scene.set_parent(S.rotor_ent, S.heli_ent)
    eng.scene.set_pos(S.rotor_ent, -1.4, 1.45, -1.2)
    eng.scene.set_mesh(S.rotor_ent, rotor_vox)

    -- Attach Bigger-on-the-Inside 14m x 5m x 20m Medevac Cabin to compact voxel chopper!
    S.cabin = eng.space.attach_vehicle_interior(eng, S.heli_ent, {
        pocket = "medevac_cabin",
        interior_size = {14.0, 5.0, 20.0},
        door_size = {1.5, 2.2},
        door_local_pos = {0.0, 0.5, 2.8},
        mesh_id = S.box_mesh
    })

    -- Furnish oversized medevac cabin interior with walls & Bio-Stabilizer Bay
    local wall_l = eng.scene.spawn("cabin_wall_l")
    eng.scene.set_pocket(wall_l, S.cabin.pocket_id)
    eng.scene.set_pos(wall_l, -6.8, 2.4, 0.0)
    eng.scene.set_scale(wall_l, 0.4, 4.8, 19.6)
    eng.scene.set_mesh(wall_l, S.box_mesh, { color = {0.75, 0.82, 0.88, 1.0} })

    local wall_r = eng.scene.spawn("cabin_wall_r")
    eng.scene.set_pocket(wall_r, S.cabin.pocket_id)
    eng.scene.set_pos(wall_r, 6.8, 2.4, 0.0)
    eng.scene.set_scale(wall_r, 0.4, 4.8, 19.6)
    eng.scene.set_mesh(wall_r, S.box_mesh, { color = {0.75, 0.82, 0.88, 1.0} })

    S.med_station = eng.scene.spawn("bio_stabilizer")
    eng.scene.set_pocket(S.med_station, S.cabin.pocket_id)
    eng.scene.set_pos(S.med_station, 0.0, 0.2, -3.5)
    eng.scene.set_scale(S.med_station, 1.5, 1.5, 1.5)
    eng.scene.set_mesh(S.med_station, S.crystal_mesh, { color = {0.25, 1.0, 0.55, 1.0} })

    for b = 1, 2 do
        local bed = eng.scene.spawn("med_stretcher_" .. tostring(b))
        eng.scene.set_pocket(bed, S.cabin.pocket_id)
        eng.scene.set_pos(bed, (b == 1) and -3.0 or 3.0, 0.35, -2.5)
        eng.scene.set_scale(bed, 1.4, 0.5, 2.6)
        eng.scene.set_mesh(bed, S.box_mesh, { color = {0.92, 0.95, 0.98, 1.0} })
    end

    -- Spawn 2 stranded islands with survivors + 2 aerial storm mines
    S.survivors = {}
    local coords = { {-11.0, -9.0}, {11.0, -12.0} }
    for i = 1, 2 do
        local ix, iz = coords[i][1], coords[i][2]
        local ie = eng.scene.spawn("stranded_island_" .. tostring(i))
        eng.scene.set_pos(ie, ix - 2.7, 0.0, iz - 2.7)
        eng.scene.set_mesh(ie, island_vox, { cast_shadow = true })

        local pe = eng.scene.spawn("survivor_" .. tostring(i))
        eng.scene.set_pos(pe, ix, 1.5, iz)
        eng.procgen.person(pe, S.seed + i * 31)
        S.survivors[i] = { ent = pe, x = ix, z = iz, state = "stranded" }
    end

    S.mines = {}
    for i = 1, 2 do
        local mx = (i == 1) and -5.5 or 5.5
        local mz = -2.0 - i * 2.5
        local me = eng.scene.spawn("storm_mine_" .. tostring(i))
        eng.scene.set_pos(me, mx, 2.4, mz)
        eng.scene.set_mesh(me, S.mine_mesh, { color = {0.95, 0.25, 0.2, 1.0} })
        S.mines[i] = { ent = me, x = mx, z = mz, dir = (i == 1) and 1.0 or -1.0, alive = true }
    end

    S.hull = 100
    S.score = 0
    S.onboard = 0
    S.stabilized = 0
    S.rescued = 0
    S.portal_trips = 0
    S.in_cabin = false
    S.mx, S.mz = 0.0, 6.0
    S.fire_cd = 0.0
    S.portal_cd = 0.0
    S.won = false
    S.lost = false
    S.flares = {}

    eng.camera.look_at(S.hx, S.hy + 6.5, S.hz + 11.0, S.hx, S.hy, S.hz - 6.0, 0)
    eng.mod.emit("post_init")
end

local function step_through_cabin_portal()
    if not S.in_cabin then
        -- Walk across rear ramp portal d_ext (z = hz + 2.8) from +Z into -Z
        local dst_pk, wx, _, wz = eng.portal.check_crossing(0,
            S.hx, S.hy + 0.5, S.hz + 3.3,
            S.hx, S.hy + 0.5, S.hz + 2.3)
        if dst_pk then
            S.in_cabin = true
            S.mx, S.mz = wx, wz
            S.portal_trips = S.portal_trips + 1
            eng.audio.play(S.sfx_portal, 0.0, 1.2, 0.0, dst_pk)
        end
    else
        -- Walk back out interior hatch d_int (z = 9.8, rotated 180 deg) from z=9.3 to z=10.3
        local dst_pk = eng.portal.check_crossing(S.cabin.pocket_id,
            0.0, 1.1, 9.3,
            0.0, 1.1, 10.3)
        if dst_pk then
            S.in_cabin = false
            S.portal_trips = S.portal_trips + 1
            eng.audio.play(S.sfx_portal, S.hx, S.hy, S.hz, 0)
        end
    end
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.portal_cd = math.max(0.0, S.portal_cd - dt)
    S.rotor_ang = S.rotor_ang + 580.0 * dt
    eng.scene.set_rot_deg(S.rotor_ent, 0.0, S.rotor_ang, 0.0)
    eng.scene.set_rot_deg(S.med_station, 0.0, S.rotor_ang * 0.25, 0.0)

    local ix, iy = eng.input.axis2d("left", "right", "down", "up")

    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.portal_cd <= 0.0 then
        S.portal_cd = 0.45
        step_through_cabin_portal()
    end

    if not S.in_cabin then
        -- Exterior voxel helicopter flight controls
        local climb = eng.input.down("jump") and 3.8 or 2.2
        S.hy = S.hy + (climb - S.hy) * math.min(1.0, 5.0 * dt)
        S.hx = eng.math.clamp(S.hx + ix * 15.0 * dt, -32.0, 32.0)
        S.hz = eng.math.clamp(S.hz - iy * 15.0 * dt, -32.0, 32.0)
        eng.scene.set_pos(S.heli_ent, S.hx, S.hy, S.hz)
        eng.scene.set_rot_deg(S.heli_ent, -iy * 10.0, 0.0, -ix * 12.0)

        -- Fire flare cannon to clear storm mines
        if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
            S.fire_cd = 0.22
            eng.audio.play(S.sfx_flare, S.hx, S.hy, S.hz, 0)
            local fe = eng.scene.spawn("rescue_flare")
            eng.scene.set_pos(fe, S.hx, S.hy, S.hz - 1.5)
            eng.scene.set_mesh(fe, S.flare_mesh, { color = {1.0, 0.85, 0.25, 1.0} })
            S.flares[#S.flares + 1] = { ent = fe, x = S.hx, y = S.hy, z = S.hz - 1.5, vz = -38.0, life = 0.9 }
        end

        -- Winch stranded survivors into the bigger-on-the-inside medevac cabin!
        for i = 1, #S.survivors do
            local sv = S.survivors[i]
            if sv.state == "stranded" and eng.math.dist3(S.hx, 0, S.hz, sv.x, 0, sv.z) < 4.2 then
                sv.state = "onboard"
                S.onboard = S.onboard + 1
                S.score = S.score + 150
                eng.audio.play(S.sfx_winch, sv.x, 2.0, sv.z, 0)
                -- Relocate survivor entity into oversized medevac_cabin stretcher!
                eng.scene.set_pocket(sv.ent, S.cabin.pocket_id)
                eng.scene.set_pos(sv.ent, (i == 1) and -3.0 or 3.0, 0.65, -2.5)
            end
        end

        -- Deliver stabilized survivors at Base Helipad
        if S.stabilized > 0 and eng.math.dist3(S.hx, 0, S.hz, S.base_x, 0, S.base_z) < 4.5 then
            S.rescued = S.rescued + S.stabilized
            S.score = S.score + S.stabilized * 300
            S.onboard = S.onboard - S.stabilized
            S.stabilized = 0
            for i = 1, #S.survivors do
                if S.survivors[i].state == "stabilized" then
                    S.survivors[i].state = "rescued"
                    eng.scene.despawn(S.survivors[i].ent)
                end
            end
            eng.audio.play(S.sfx_heal, S.base_x, 2.0, S.base_z, 0)
        end
    else
        -- Inside Bigger-on-the-Inside Medevac Cabin!
        local prev_z = S.mz
        S.mx = eng.math.clamp(S.mx + ix * 9.5 * dt, -5.8, 5.8)
        S.mz = eng.math.clamp(S.mz - iy * 9.5 * dt, -8.5, 10.4)

        -- Also support walking naturally back out the rear portal threshold
        if prev_z < 9.8 and S.mz >= 9.8 then
            local dst_pk = eng.portal.check_crossing(S.cabin.pocket_id, S.mx, 1.1, prev_z, S.mx, 1.1, S.mz)
            if dst_pk then
                S.in_cabin = false
                S.portal_trips = S.portal_trips + 1
                eng.audio.play(S.sfx_portal, S.hx, S.hy, S.hz, 0)
            end
        end

        -- Activate Bio-Stabilizer console inside medevac cabin
        if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
            S.fire_cd = 0.25
            if eng.math.dist3(S.mx, 0, S.mz, 0.0, 0, -3.5) < 4.5 and S.onboard > S.stabilized then
                for i = 1, #S.survivors do
                    if S.survivors[i].state == "onboard" then
                        S.survivors[i].state = "stabilized"
                        S.stabilized = S.stabilized + 1
                        S.score = S.score + 200
                    end
                end
                eng.audio.play(S.sfx_heal, 0.0, 1.2, -3.5, S.cabin.pocket_id)
            end
        end
    end

    -- Step storm mines & flares
    for i = 1, #S.mines do
        local mn = S.mines[i]
        if mn.alive then
            mn.x = mn.x + mn.dir * 3.5 * dt
            if math.abs(mn.x) > 14.0 then mn.dir = -mn.dir end
            eng.scene.set_pos(mn.ent, mn.x, 2.4, mn.z)
            if not S.in_cabin and eng.math.dist3(S.hx, S.hy, S.hz, mn.x, 2.4, mn.z) < 2.0 then
                mn.alive = false
                eng.scene.despawn(mn.ent)
                S.hull = math.max(0, S.hull - 35)
                if S.hull <= 0 then S.lost = true end
            end
        end
    end

    for i = #S.flares, 1, -1 do
        local fl = S.flares[i]
        fl.life = fl.life - dt
        fl.z = fl.z + fl.vz * dt
        eng.scene.set_pos(fl.ent, fl.x, fl.y, fl.z)
        local dead = (fl.life <= 0.0)
        if not dead then
            for j = 1, #S.mines do
                local mn = S.mines[j]
                if mn.alive and eng.math.dist3(fl.x, fl.y, fl.z, mn.x, 2.4, mn.z) < 2.2 then
                    dead = true
                    mn.alive = false
                    eng.scene.despawn(mn.ent)
                    S.score = S.score + 100
                    break
                end
            end
        end
        if dead then
            eng.scene.despawn(fl.ent)
            table.remove(S.flares, i)
        end
    end

    if S.rescued >= 2 and S.portal_trips >= 2 and not S.lost then
        S.won = true
        eng.save.write("heli_rescue_clear", tostring(S.score))
    end

    if S.in_cabin then
        eng.camera.look_at(S.mx, 1.8, S.mz + 2.5, 0.0, 1.0, -3.5, S.cabin.pocket_id)
    else
        eng.camera.look_at(S.hx, S.hy + 6.5, S.hz + 11.0, S.hx, S.hy, S.hz - 6.0, 0)
    end
end

function draw()
    if not S.in_cabin then
        for i = 1, #S.survivors do
            local sv = S.survivors[i]
            if sv.state == "stranded" then
                eng.render.draw_sprite(sv.x, 3.6, sv.z, 0.9, 0.9, S.orb_tex)
            end
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 60, 1280, 720)
    local loc = S.in_cabin and "[MEDEVAC CABIN 14x20m]" or "[FLIGHT]"
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " " .. loc .. " | RESCUED " .. S.rescued .. "/2 | STABLE " .. S.stabilized .. "/" .. S.onboard))
    eng.ui.label(x, y, msg, 1.0, {0.45, 0.98, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.hull / 100.0, "HULL ")
end
