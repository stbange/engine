-- 088_elevator_heist_3d: Multi-Floor 3D Spy Tower with Elevators, Red Doors, procgen.person Agents & Getaway Car
local S = game.state

local FLOOR_H = 3.2
local GRAV = -24.0
local SHAFT_1_X = -3.5
local SHAFT_2_X =  3.5
local SHAFT_HW = 1.05

local function spawn_slab(x, y, z, w, h, d, tex, col)
    local e = eng.scene.spawn("tower_slab")
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_scale(e, w, h, d)
    eng.scene.set_mesh(e, S.box_mesh, { tex = tex, color = col, roughness = 0.72 })
    return e
end

local function solid_floor_under(px, floor_idx)
    if floor_idx == 0 then return true end
    if math.abs(px - SHAFT_1_X) < SHAFT_HW then return false end
    if floor_idx <= 3 and math.abs(px - SHAFT_2_X) < SHAFT_HW then return false end
    return true
end

local function spawn_elevator_cab(idx, x, min_f, max_f, start_f)
    local y0 = start_f * FLOOR_H
    local root = eng.scene.spawn("elevator_cab_" .. tostring(idx))
    eng.scene.set_pos(root, x, y0, 0.0)

    local parts = {
        { 0.0,  -0.10,  0.0,  1.95, 0.20, 2.1, {0.88, 0.76, 0.24, 1.0} },
        { 0.0,   2.35,  0.0,  1.95, 0.16, 2.1, {0.88, 0.76, 0.24, 1.0} },
        { -0.90, 1.12, -0.85, 0.12, 2.35, 0.14, {0.35, 0.85, 1.00, 1.0} },
        {  0.90, 1.12, -0.85, 0.12, 2.35, 0.14, {0.35, 0.85, 1.00, 1.0} }
    }
    for i = 1, #parts do
        local p = parts[i]
        local pe = eng.scene.spawn("cab_frame_" .. tostring(idx) .. "_" .. tostring(i))
        eng.scene.set_parent(pe, root)
        eng.scene.set_pos(pe, p[1], p[2], p[3])
        eng.scene.set_scale(pe, p[4], p[5], p[6])
        eng.scene.set_mesh(pe, S.box_mesh, { tex = S.panel_tex, color = p[7] })
    end

    return {
        ent = root, x = x, y = y0, vy = 0.0,
        min_y = min_f * FLOOR_H, max_y = max_f * FLOOR_H
    }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.03, 0.05, 0.12, 0.10, 0.16, 0.28)
    eng.render.add_light({ type = "dir", dir = {-0.25, -0.65, -0.75}, color = {2.1, 2.05, 1.95}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.0, 6.0}, color = {1.5, 1.8, 2.4}, range = 36.0 })

    local seed_base = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.panel_tex = eng.procgen.texture("sci_fi_panel", seed_base, 64)
    S.wall_tex = eng.procgen.texture("stone_brick", seed_base + 9, 64)
    S.marble_tex = eng.procgen.texture("marble", seed_base + 21, 64)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_doc = eng.audio.synth("triangle", 520, 0.16, 960)
    S.sfx_stun = eng.audio.synth("saw", 680, 0.09, 260)
    S.sfx_car = eng.audio.synth("square", 260, 0.24, 620)

    -- Back cutaway tower wall, side walls, roof, and 5 floor decks with shaft cutouts
    spawn_slab(0.0, 8.0, -1.9, 20.6, 16.8, 0.35, S.wall_tex, {0.20, 0.24, 0.32, 1.0})
    spawn_slab(-10.2, 8.0, -0.2, 0.4, 16.8, 3.2, S.panel_tex, {0.28, 0.34, 0.44, 1.0})
    spawn_slab( 10.2, 8.0, -0.2, 0.4, 16.8, 3.2, S.panel_tex, {0.28, 0.34, 0.44, 1.0})
    spawn_slab(0.0, 16.2, -0.2, 20.8, 0.4, 3.2, S.panel_tex, {0.30, 0.36, 0.48, 1.0})

    -- F0 Basement full floor; F1..F3 3-segment floors; F4 2-segment penthouse floor
    spawn_slab(0.0, -0.15, 0.0, 20.0, 0.30, 2.8, S.marble_tex, {0.32, 0.35, 0.40, 1.0})
    for f = 1, 3 do
        local fy = f * FLOOR_H - 0.15
        spawn_slab(-7.28, fy, 0.0, 5.45, 0.28, 2.6, S.marble_tex, {0.46, 0.50, 0.58, 1.0})
        spawn_slab( 0.00, fy, 0.0, 4.90, 0.28, 2.6, S.marble_tex, {0.46, 0.50, 0.58, 1.0})
        spawn_slab( 7.28, fy, 0.0, 5.45, 0.28, 2.6, S.marble_tex, {0.46, 0.50, 0.58, 1.0})
    end
    spawn_slab(-7.28, 4 * FLOOR_H - 0.15, 0.0, 5.45, 0.28, 2.6, S.marble_tex, {0.50, 0.54, 0.62, 1.0})
    spawn_slab( 3.78, 4 * FLOOR_H - 0.15, 0.0, 12.45, 0.28, 2.6, S.marble_tex, {0.50, 0.54, 0.62, 1.0})

    -- Vertical elevator shaft guide rails
    local rails = {
        { SHAFT_1_X - 1.02, 8.0, 9.8 }, { SHAFT_1_X + 1.02, 8.0, 9.8 },
        { SHAFT_2_X - 1.02, 4.8, 9.8 }, { SHAFT_2_X + 1.02, 4.8, 9.8 }
    }
    for i = 1, #rails do
        local r = rails[i]
        spawn_slab(r[1], r[2], -1.1, 0.09, r[3], 0.09, S.panel_tex, {0.28, 0.62, 0.85, 1.0})
    end

    -- 2 3D Elevators (Left shaft F1..F4, Right shaft F0..F3)
    S.cabs = {
        spawn_elevator_cab(1, SHAFT_1_X, 1, 4, 4),
        spawn_elevator_cab(2, SHAFT_2_X, 0, 3, 3)
    }

    -- 3 Crimson Secret Dossier Doors
    S.doors = {}
    local door_specs = {
        { x = -8.4, f = 4 },
        { x =  8.4, f = 3 },
        { x = -8.4, f = 1 }
    }
    for i = 1, #door_specs do
        local ds = door_specs[i]
        local dy = ds.f * FLOOR_H
        local de = eng.scene.spawn("red_door_" .. tostring(i))
        eng.scene.set_pos(de, ds.x, dy + 1.15, -1.58)
        eng.scene.set_scale(de, 1.35, 2.30, 0.22)
        eng.scene.set_mesh(de, S.box_mesh, { color = {0.96, 0.16, 0.20, 1.0} })

        local fe = eng.scene.spawn("secret_dossier_" .. tostring(i))
        eng.scene.set_pos(fe, ds.x, dy + 0.85, -0.35)
        eng.scene.set_scale(fe, 0.65, 0.65, 0.65)
        eng.scene.set_mesh(fe, S.crystal_mesh, { color = {1.0, 0.88, 0.22, 1.0} })

        S.doors[i] = { ent = de, doc_ent = fe, x = ds.x, y = dy, taken = false }
    end

    -- Basement Getaway Car at (X = 8.0, Y = 0.0)
    S.car_root = eng.scene.spawn("basement_getaway_car")
    eng.scene.set_pos(S.car_root, 8.0, 0.0, 0.0)
    local car_parts = {
        { 0.0,  0.42, 0.0, 2.70, 0.52, 1.35, {0.15, 0.82, 0.96, 1.0} },
        { -0.2, 0.88, 0.0, 1.45, 0.44, 1.18, {0.82, 0.94, 1.00, 1.0} },
        { 1.36, 0.46, 0.38, 0.12, 0.20, 0.26, {1.00, 0.95, 0.35, 1.0} },
        { 1.36, 0.46, -0.38, 0.12, 0.20, 0.26, {1.00, 0.95, 0.35, 1.0} }
    }
    for i = 1, #car_parts do
        local cp = car_parts[i]
        local ce = eng.scene.spawn("car_part_" .. tostring(i))
        eng.scene.set_parent(ce, S.car_root)
        eng.scene.set_pos(ce, cp[1], cp[2], cp[3])
        eng.scene.set_scale(ce, cp[4], cp[5], cp[6])
        eng.scene.set_mesh(ce, S.box_mesh, { color = cp[7] })
    end

    -- Player Spy + 3 Patrolling Security Agents via eng.procgen.person
    S.spy_ent = eng.scene.spawn("spy_operative")
    eng.procgen.person(S.spy_ent, seed_base + 7)
    local hat = eng.scene.spawn("spy_visor")
    eng.scene.set_parent(hat, S.spy_ent)
    eng.scene.set_pos(hat, 0.0, 1.78, 0.0)
    eng.scene.set_scale(hat, 0.38, 0.12, 0.38)
    eng.scene.set_mesh(hat, S.box_mesh, { color = {0.22, 0.95, 1.0, 1.0} })

    S.agents = {}
    local ag_floors = { 3, 2, 1 }
    for i = 1, #ag_floors do
        local af = ag_floors[i]
        local ax = (i == 2) and -1.2 or 0.9
        local ae = eng.scene.spawn("patrol_agent_" .. tostring(i))
        eng.procgen.person(ae, seed_base + 30 + i * 19)
        eng.scene.set_pos(ae, ax, af * FLOOR_H, 0.0)
        local badge = eng.scene.spawn("agent_alert_" .. tostring(i))
        eng.scene.set_parent(badge, ae)
        eng.scene.set_pos(badge, 0.0, 1.85, 0.0)
        eng.scene.set_scale(badge, 0.24, 0.24, 0.24)
        eng.scene.set_mesh(badge, S.box_mesh, { color = {1.0, 0.20, 0.20, 1.0} })

        S.agents[i] = {
            ent = ae, floor = af, x = ax, y = af * FLOOR_H,
            vx = ((i % 2) == 1) and -2.6 or 2.6,
            stun_t = 0.0, evaded_counted = false
        }
    end

    S.px, S.py = -1.0, 4 * FLOOR_H
    S.vy = 0.0
    S.facing = -1
    S.grounded = true
    S.riding_cab = 0
    S.cooldown = 0.0
    S.invuln = 0.0
    S.lives = 3
    S.score = 0
    S.dossiers = 0
    S.total_dossiers = #S.doors
    S.elevator_rides = 0
    S.agents_evaded = 0
    S.escaped = false
    S.won = false

    eng.scene.set_pos(S.spy_ent, S.px, S.py, 0.0)
    eng.scene.set_rot_deg(S.spy_ent, 0.0, 90.0, 0.0)
    eng.camera.look_at(0.0, 7.6, 19.2, 0.0, 6.6, -0.5, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)
    S.invuln = math.max(0.0, S.invuln - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if mx > 0.1 then S.facing = 1 elseif mx < -0.1 then S.facing = -1 end

    -- Check if spy is standing inside an elevator cab
    local active_cab = 0
    for ci = 1, #S.cabs do
        local c = S.cabs[ci]
        if math.abs(S.px - c.x) <= 0.92 and math.abs(S.py - c.y) <= 0.42 and S.vy <= 0.5 then
            active_cab = ci
            break
        end
    end

    -- Step elevators
    for ci = 1, #S.cabs do
        local c = S.cabs[ci]
        if ci == active_cab then
            if math.abs(my) > 0.1 then
                local prev_y = c.y
                c.y = eng.math.clamp(c.y + my * 11.5 * dt, c.min_y, c.max_y)
                if math.abs(c.y - prev_y) > 0.001 then
                    S.elevator_rides = S.elevator_rides + 1
                end
            else
                local near_y = eng.math.clamp(math.floor(c.y / FLOOR_H + 0.5) * FLOOR_H, c.min_y, c.max_y)
                local dy = near_y - c.y
                if math.abs(dy) <= 9.0 * dt then c.y = near_y
                else c.y = c.y + ((dy > 0) and 1.0 or -1.0) * 9.0 * dt end
            end
            S.py = c.y
            S.vy = 0.0
            S.grounded = true
        else
            -- Unoccupied cab gently aligns toward nearest floor
            local want_y = eng.math.clamp(math.floor(S.py / FLOOR_H + 0.5) * FLOOR_H, c.min_y, c.max_y)
            local dy = want_y - c.y
            if math.abs(dy) > 0.04 then
                local step = math.min(math.abs(dy), 5.5 * dt)
                c.y = c.y + ((dy > 0) and step or -step)
            end
        end
        eng.scene.set_pos(c.ent, c.x, c.y, 0.0)
    end

    -- Spy horizontal move, jump, and floor/cab landing
    S.px = eng.math.clamp(S.px + mx * 10.5 * dt, -9.4, 9.4)
    if (eng.input.pressed("jump") or eng.input.down("jump")) and S.grounded then
        S.vy = 7.4
        S.grounded = false
        active_cab = 0
    end

    if active_cab == 0 then
        local prev_y = S.py
        S.vy = S.vy + GRAV * dt
        S.py = S.py + S.vy * dt
        S.grounded = false

        -- Land on solid floor slabs
        if S.vy <= 0.0 then
            for f = 0, 4 do
                local fy = f * FLOOR_H
                if prev_y >= fy - 0.12 and S.py <= fy + 0.05 and solid_floor_under(S.px, f) then
                    S.py = fy
                    S.vy = 0.0
                    S.grounded = true
                    break
                end
            end
            -- Or land inside / on roof of an elevator cab
            if not S.grounded then
                for ci = 1, #S.cabs do
                    local c = S.cabs[ci]
                    if math.abs(S.px - c.x) <= 0.96 then
                        if prev_y >= c.y - 0.15 and S.py <= c.y + 0.10 then
                            S.py = c.y; S.vy = 0.0; S.grounded = true; break
                        end
                    end
                end
            end
        end
        if S.py < 0.0 then S.py = 0.0; S.vy = 0.0; S.grounded = true end
    end

    eng.scene.set_pos(S.spy_ent, S.px, S.py, 0.0)
    eng.scene.set_rot_deg(S.spy_ent, 0.0, (S.facing > 0) and -90.0 or 90.0, 0.0)

    -- Silenced stun dart ("fire")
    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        S.cooldown = 0.24
        eng.audio.play(S.sfx_stun, S.px, S.py + 1.0, 0.0, 0)
        for i = 1, #S.agents do
            local ag = S.agents[i]
            local dx = (ag.x - S.px) * S.facing
            if ag.stun_t <= 0.0 and math.abs(ag.y - S.py) < 1.1 and dx > -0.3 and dx < 7.5 then
                ag.stun_t = 3.2
                S.agents_evaded = S.agents_evaded + 1
                S.score = S.score + 100
                break
            end
        end
    end

    -- Grab secret dossiers from Red Doors
    for i = 1, #S.doors do
        local d = S.doors[i]
        if not d.taken then
            eng.scene.set_rot_deg(d.doc_ent, 0.0, (S.score + i * 45) + dt * 120.0, 0.0)
            if math.abs(S.px - d.x) < 1.25 and math.abs(S.py - d.y) < 1.1 then
                d.taken = true
                S.dossiers = S.dossiers + 1
                S.score = S.score + 300
                eng.scene.despawn(d.doc_ent)
                eng.scene.set_mesh(d.ent, S.box_mesh, { color = {0.22, 0.55, 0.34, 1.0} })
                eng.audio.play(S.sfx_doc, d.x, d.y + 1.0, 0.0, 0)
            end
        end
    end

    -- Step patrolling procgen.person security agents
    for i = 1, #S.agents do
        local ag = S.agents[i]
        if ag.stun_t > 0.0 then
            ag.stun_t = math.max(0.0, ag.stun_t - dt)
            eng.scene.set_rot_deg(ag.ent, 0.0, ag.stun_t * 360.0, 14.0)
        else
            ag.x = ag.x + ag.vx * dt
            if ag.x > 2.05 then ag.x = 2.05; ag.vx = -math.abs(ag.vx) end
            if ag.x < -2.05 then ag.x = -2.05; ag.vx = math.abs(ag.vx) end
            eng.scene.set_pos(ag.ent, ag.x, ag.y, 0.0)
            eng.scene.set_rot_deg(ag.ent, 0.0, (ag.vx > 0) and -90.0 or 90.0, 0.0)

            -- Leap-over evasion check vs close contact
            if math.abs(S.px - ag.x) < 0.72 then
                local dy = S.py - ag.y
                if dy >= 0.72 and dy <= 2.0 and not ag.evaded_counted then
                    ag.evaded_counted = true
                    S.agents_evaded = S.agents_evaded + 1
                    S.score = S.score + 75
                elseif math.abs(dy) < 0.68 and S.invuln <= 0.0 then
                    S.lives = math.max(1, S.lives - 1)
                    S.invuln = 1.1
                end
            end
        end
    end

    -- Escape at the Basement Getaway Car once all 3 dossiers are stolen!
    if S.dossiers >= S.total_dossiers and S.py < 0.85 and math.abs(S.px - 8.0) < 1.65 then
        S.escaped = true
        S.won = true
        S.score = S.score + 500
        eng.audio.play(S.sfx_car, 8.0, 0.5, 0.0, 0)
        eng.scene.set_pos(S.spy_ent, 8.0, 0.35, 0.0)
    end

    eng.camera.look_at(S.px * 0.12, 7.4, 19.2, S.px * 0.08, 6.5, -0.5, 0)
end

function draw()
    for i = 1, #S.doors do
        local d = S.doors[i]
        if not d.taken then
            eng.render.draw_sprite(d.x, d.y + 1.55, -0.2, 0.55, 0.55, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 500, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | DOSSIERS " .. S.dossiers .. "/" .. S.total_dossiers .. " | SCORE " .. S.score, 1.0, {0.55, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 180, S.lives / 3.0, "COVER ")
end
