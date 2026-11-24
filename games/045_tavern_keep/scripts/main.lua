-- 045_tavern_keep: Behavior-Tree (eng.bt) Tavern Management with Markov-Named Patrons
local S = game.state

local function build_patron_bt()
    local bt = eng.bt
    local is_seated = bt.action(function(p)
        return p.seated and bt.SUCCESS or bt.FAILURE
    end)

    -- 1. Happy served patron walks back to tavern door
    local leave_happy = bt.sequence({
        bt.action(function(p) return p.served and bt.SUCCESS or bt.FAILURE end),
        bt.action(function(p, dt)
            local dx, dz = 0.0 - p.x, 7.2 - p.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d < 0.4 then
                p.done = true
                return bt.SUCCESS
            end
            p.x = p.x + (dx / d) * 5.2 * dt
            p.z = p.z + (dz / d) * 5.2 * dt
            eng.scene.set_pos(p.ent, p.x, 0.0, p.z)
            return bt.RUNNING
        end)
    })

    -- 2. Unseated patron walks from door to assigned tavern table (uses bt.inverter)
    local walk_to_table = bt.sequence({
        bt.inverter(is_seated),
        bt.action(function(p, dt)
            local dx, dz = p.tx - p.x, p.tz - p.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d < 0.35 then
                p.seated = true
                p.x, p.z = p.tx, p.tz
                eng.scene.set_pos(p.ent, p.x, 0.0, p.z)
                return bt.SUCCESS
            end
            p.x = p.x + (dx / d) * 4.8 * dt
            p.z = p.z + (dz / d) * 4.8 * dt
            eng.scene.set_pos(p.ent, p.x, 0.0, p.z)
            return bt.RUNNING
        end)
    })

    -- 3. Seated patron waits for mug as patience ticks down
    local wait_for_ale = bt.action(function(p, dt)
        p.patience = p.patience - dt * 6.5
        if p.patience <= 0.0 then
            p.done = true
            S.lost = S.lost + 1
            return bt.FAILURE
        end
        return bt.RUNNING
    end)

    return bt.selector({ leave_happy, walk_to_table, wait_for_ale })
end

local function spawn_patron(slot_idx)
    S.patron_seq = S.patron_seq + 1
    local tbl = S.tables[slot_idx]
    local pe = eng.scene.spawn("patron_" .. S.patron_seq)
    local sx = (slot_idx % 2 == 0) and 1.2 or -1.2
    local sz = 6.2
    eng.scene.set_pos(pe, sx, 0.0, sz)
    local info = eng.procgen.person(pe, S.seed + S.patron_seq * 37)
    S.patrons[slot_idx] = {
        ent = pe, x = sx, z = sz,
        tx = tbl.x, tz = tbl.z + 1.0,
        name = info.name, role = info.role,
        seated = false, served = false, done = false,
        patience = 100.0
    }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.12, 0.08, 0.06, 0.30, 0.18, 0.10)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {1.8, 1.6, 1.35}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.8, 0.0}, color = {2.8, 1.9, 1.0}, range = 28.0 })

    S.seed = math.floor(eng.math.range(100, 600000))
    local wood_tex = eng.procgen.texture("wood_grain", S.seed, 64)
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.5, 0.5, 1.0, 12)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_pour = eng.audio.synth("noise", 380, 0.10, 220)
    S.sfx_serve = eng.audio.synth("triangle", 460, 0.15, 780)

    local floor_e = eng.scene.spawn("tavern_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.5)
    eng.scene.set_scale(floor_e, 18.0, 0.5, 18.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = wood_tex, color = {0.58, 0.40, 0.24, 1.0} })

    local door_arch = eng.scene.spawn("tavern_door")
    eng.scene.set_pos(door_arch, 0.0, 0.0, 7.6)
    eng.scene.set_mesh(door_arch, S.arch_mesh, { color = {0.65, 0.52, 0.38, 1.0} })

    -- Bar counter & 2 Ale Kegs
    local bar = eng.scene.spawn("bar_counter")
    eng.scene.set_pos(bar, 0.0, 0.55, -3.8)
    eng.scene.set_scale(bar, 8.0, 1.1, 0.9)
    eng.scene.set_mesh(bar, S.box_mesh, { tex = wood_tex, color = {0.46, 0.28, 0.16, 1.0} })
    eng.physics.add_body(bar, { shape = "aabb", motion = "static", half_extents = {4.0, 0.55, 0.38} })

    S.kegs = { { x = -2.6, z = -5.2 }, { x = 2.6, z = -5.2 } }
    for i = 1, #S.kegs do
        local ke = eng.scene.spawn("ale_keg_" .. i)
        eng.scene.set_pos(ke, S.kegs[i].x, 0.65, S.kegs[i].z)
        eng.scene.set_rot_deg(ke, 90.0, 0.0, 0.0)
        eng.scene.set_scale(ke, 1.0, 1.2, 1.0)
        eng.scene.set_mesh(ke, S.cyl_mesh, { tex = wood_tex, color = {0.72, 0.46, 0.22, 1.0} })
    end

    -- 3 Tavern Tables
    S.tables = { { x = -4.2, z = 0.0 }, { x = 0.0, z = 1.2 }, { x = 4.2, z = 0.0 } }
    for i = 1, #S.tables do
        local te = eng.scene.spawn("table_" .. i)
        eng.scene.set_pos(te, S.tables[i].x, 0.45, S.tables[i].z)
        eng.scene.set_scale(te, 1.6, 0.9, 1.6)
        eng.scene.set_mesh(te, S.cyl_mesh, { tex = wood_tex, color = {0.62, 0.42, 0.25, 1.0} })
        eng.physics.add_body(te, { shape = "aabb", motion = "static", half_extents = {0.65, 0.45, 0.65} })
    end

    S.px, S.pz = 0.0, -2.4
    S.keeper_ent = eng.scene.spawn("tavern_keeper")
    eng.scene.set_pos(S.keeper_ent, S.px, 0.0, S.pz)
    eng.procgen.person(S.keeper_ent, S.seed + 1)

    S.patron_bt = build_patron_bt()
    S.patrons = {}
    S.patron_seq = 0
    for i = 1, 3 do spawn_patron(i) end

    S.mugs = 2
    S.served = 0
    S.lost = 0
    S.gold = 0
    S.bt_ticks = 0
    S.last_served_name = ""
    S.won = false

    eng.camera.look_at(0.0, 10.0, 11.5, 0.0, 0.6, 0.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        local nx, nz = eng.physics.slide_move(0, S.px, 0.5, S.pz, mx * 7.8 * dt, -my * 7.8 * dt, 0.38)
        S.px = eng.math.clamp(nx, -7.5, 7.5)
        S.pz = eng.math.clamp(nz, -6.5, 6.5)
        eng.scene.set_pos(S.keeper_ent, S.px, 0.0, S.pz)
    end

    -- Pour foamy mugs when near either Ale Keg (or across the bar counter)
    if S.mugs < 2 then
        for i = 1, #S.kegs do
            if eng.math.dist3(S.px, 0, S.pz, S.kegs[i].x, 0, S.kegs[i].z) < 2.5 then
                S.mugs = 2
                eng.audio.play(S.sfx_pour, S.kegs[i].x, 1.0, S.kegs[i].z, 0)
            end
        end
    end

    -- Tick Behavior Tree for every active patron & serve seated patrons
    for i = 1, 3 do
        local p = S.patrons[i]
        if p then
            S.patron_bt(p, dt)
            S.bt_ticks = S.bt_ticks + 1

            if p.seated and not p.served and S.mugs > 0 and eng.math.dist3(S.px, 0, S.pz, p.x, 0, p.z) < 2.5 then
                p.served = true
                S.mugs = S.mugs - 1
                S.served = S.served + 1
                S.gold = S.gold + 15
                S.last_served_name = p.name
                eng.audio.play(S.sfx_serve, p.x, 1.2, p.z, 0)
            end

            if p.done then
                eng.scene.despawn(p.ent)
                if S.served < 5 then
                    spawn_patron(i)
                else
                    S.patrons[i] = nil
                end
            end
        end
    end

    if S.served >= 5 then
        S.won = true
        eng.save.write("tavern_keep", "five_star_inn")
    end

    eng.camera.look_at(0.0, 10.0, 11.5, 0.0, 0.6, 0.0, 0)
end

function draw()
    for i = 1, 3 do
        local p = S.patrons[i]
        if p and p.seated and not p.served then
            eng.render.draw_sprite(p.x, 2.05, p.z, 0.45, 0.45, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | MUGS " .. S.mugs .. "/2 | SERVED " .. S.served .. "/5 | LAST: " .. S.last_served_name, 1.0, {1.0, 0.88, 0.52, 1.0})
    eng.ui.bar(x, y + 26, 200, S.served / 5.0, "SHIFT ")
end
