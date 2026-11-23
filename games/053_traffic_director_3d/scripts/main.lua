-- 053_traffic_director_3d: WFC city intersection & 3D signal phase controller
local S = game.state

local CX, CZ, DECK_Y = 16.0, 16.0, 3.0

local function refresh_signals()
    local ns_green = (S.phase == "NS")
    local g_col = {0.15, 1.0, 0.35, 1.0}
    local r_col = {1.0, 0.18, 0.18, 1.0}
    for i = 1, #S.ns_lamps do
        eng.scene.set_mesh(S.ns_lamps[i], S.sphere_mesh, { color = ns_green and g_col or r_col })
    end
    for i = 1, #S.ew_lamps do
        eng.scene.set_mesh(S.ew_lamps[i], S.sphere_mesh, { color = (not ns_green) and g_col or r_col })
    end
end

local function spawn_car(axis, dir_sign, palette_idx)
    -- axis 1 = NS (moves along Z), axis 2 = EW (moves along X)
    local lane_off = (dir_sign > 0) and 1.1 or -1.1
    local x, z, yaw
    if axis == 1 then
        x = CX + lane_off
        z = CZ - dir_sign * 13.5
        yaw = (dir_sign > 0) and 180.0 or 0.0
    else
        x = CX - dir_sign * 13.5
        z = CZ - lane_off
        yaw = (dir_sign > 0) and -90.0 or 90.0
    end

    -- Ensure spawn slot has clearance
    for i = 1, #S.cars do
        local o = S.cars[i]
        if o.active and eng.math.dist3(x, 0, z, o.x, 0, o.z) < 2.8 then return false end
    end

    local colors = {
        {0.95, 0.78, 0.18, 1.0},
        {0.22, 0.68, 0.96, 1.0},
        {0.92, 0.30, 0.36, 1.0},
        {0.35, 0.90, 0.58, 1.0}
    }
    local ent = eng.scene.spawn("city_car_" .. tostring(S.spawned_total + 1))
    eng.scene.set_pos(ent, x, DECK_Y + 0.45, z)
    eng.scene.set_rot_deg(ent, 0.0, yaw, 0.0)
    eng.scene.set_scale(ent, 0.95, 0.65, 1.65)
    eng.scene.set_mesh(ent, S.box_mesh, { color = colors[(palette_idx % #colors) + 1], cast_shadow = true })

    local cab = eng.scene.spawn("car_cabin_" .. tostring(S.spawned_total + 1))
    eng.scene.set_parent(cab, ent)
    eng.scene.set_pos(cab, 0.0, 0.65, 0.05)
    eng.scene.set_scale(cab, 0.78, 0.55, 0.55)
    eng.scene.set_mesh(cab, S.box_mesh, { color = {0.85, 0.94, 1.0, 1.0} })

    S.spawned_total = S.spawned_total + 1
    S.cars[#S.cars + 1] = {
        ent = ent, axis = axis, dir = dir_sign, lane = lane_off,
        x = x, z = z, wait = 0.0, active = true
    }
    return true
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.011 })
    eng.render.set_sky(0.10, 0.16, 0.32, 0.45, 0.34, 0.42)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.4}, color = {2.1, 2.0, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {CX, DECK_Y + 7.0, CZ}, color = {2.2, 1.9, 1.4}, range = 32.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.42, 10, 12)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    -- WFC City District surrounding and framing the elevated 4-way expressway crossroads
    local wfc = eng.procgen.dungeon(16, 16, seed_base, "wfc", 2.0, 2.6)
    S.wfc_solvable = wfc.solvable
    local city_tex = eng.procgen.texture("sci_fi_panel", seed_base, 64)
    local road_tex = eng.procgen.texture("cobble", seed_base + 11, 64)

    local city_ent = eng.scene.spawn("wfc_city_blocks")
    eng.scene.set_mesh(city_ent, wfc.mesh_id, { tex = city_tex, color = {0.62, 0.68, 0.78, 1.0} })

    -- Elevated 4-way asphalt intersection decks
    local ns_road = eng.scene.spawn("road_ns")
    eng.scene.set_pos(ns_road, CX, DECK_Y - 0.15, CZ)
    eng.scene.set_scale(ns_road, 4.8, 0.3, 30.0)
    eng.scene.set_mesh(ns_road, S.box_mesh, { tex = road_tex, color = {0.26, 0.28, 0.32, 1.0} })

    local ew_road = eng.scene.spawn("road_ew")
    eng.scene.set_pos(ew_road, CX, DECK_Y - 0.14, CZ)
    eng.scene.set_scale(ew_road, 30.0, 0.3, 4.8)
    eng.scene.set_mesh(ew_road, S.box_mesh, { tex = road_tex, color = {0.26, 0.28, 0.32, 1.0} })

    -- 4 Signal Gantries at intersection corners
    S.ns_lamps = {}
    S.ew_lamps = {}
    local corners = { {-3.0, -3.0, true}, {3.0, 3.0, true}, {-3.0, 3.0, false}, {3.0, -3.0, false} }
    for i = 1, #corners do
        local c = corners[i]
        local post = eng.scene.spawn("signal_post_" .. tostring(i))
        eng.scene.set_pos(post, CX + c[1], DECK_Y + 1.4, CZ + c[2])
        eng.scene.set_scale(post, 0.28, 2.8, 0.28)
        eng.scene.set_mesh(post, S.box_mesh, { color = {0.2, 0.22, 0.25, 1.0}, cast_shadow = true })

        local lamp = eng.scene.spawn("signal_lamp_" .. tostring(i))
        eng.scene.set_pos(lamp, CX + c[1], DECK_Y + 2.95, CZ + c[2])
        if c[3] then S.ns_lamps[#S.ns_lamps + 1] = lamp else S.ew_lamps[#S.ew_lamps + 1] = lamp end
    end

    S.sfx_toggle = eng.audio.synth("triangle", 520, 0.10, 780)
    S.sfx_clear = eng.audio.synth("sine", 660, 0.12, 920)
    S.sfx_crash = eng.audio.synth("noise", 160, 0.25, 60)

    S.phase = "NS"
    S.toggles = 0
    S.cleared = 0
    S.target_clear = 12
    S.crashes = 0
    S.spawned_total = 0
    S.spawn_cd = 0.05
    S.toggle_cd = 0.0
    S.boost_timer = 0.0
    S.cars = {}
    S.won = false
    S.lost = false

    refresh_signals()
    spawn_car(1, 1, 0)
    spawn_car(2, 1, 1)

    eng.camera.look_at(CX + 0.5, DECK_Y + 18.5, CZ + 15.5, CX, DECK_Y, CZ, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or S.lost then return end
    S.toggle_cd = math.max(0.0, S.toggle_cd - dt)
    S.boost_timer = math.max(0.0, S.boost_timer - dt)

    if (eng.input.pressed("interact") or eng.input.pressed("fire")) and S.toggle_cd <= 0.0 then
        S.toggle_cd = 0.18
        S.phase = (S.phase == "NS") and "EW" or "NS"
        S.toggles = S.toggles + 1
        refresh_signals()
        eng.audio.play(S.sfx_toggle, CX, DECK_Y + 2.0, CZ, 0)
    end

    if eng.input.pressed("jump") or eng.input.down("jump") then
        S.boost_timer = 0.6
    end

    -- Deterministic rush-hour waves across NS and EW approaches
    S.spawn_cd = S.spawn_cd - dt
    if S.spawn_cd <= 0.0 and S.spawned_total < 18 then
        local idx = S.spawned_total
        local axis = ((math.floor(idx / 3) % 2) == 0) and 1 or 2
        local dir_sign = ((idx % 2) == 0) and 1 or -1
        if spawn_car(axis, dir_sign, idx) then
            S.spawn_cd = 0.22
        else
            S.spawn_cd = 0.12
        end
    end

    local speed_base = (S.boost_timer > 0.0) and 16.5 or 12.8
    for i = 1, #S.cars do
        local c = S.cars[i]
        if c.active then
            local signed_d = (c.axis == 1) and ((CZ - c.z) * c.dir) or ((CX - c.x) * c.dir)
            local green = (c.axis == 1 and S.phase == "NS") or (c.axis == 2 and S.phase == "EW")

            -- Check red signal stop line unless impatient road-rage exceeds 5.5s
            local must_stop = false
            if (not green) and signed_d > 2.5 and signed_d < 4.4 and c.wait < 5.5 then
                must_stop = true
            end

            -- Check spacing behind car ahead in same lane & direction
            for j = 1, #S.cars do
                if i ~= j and S.cars[j].active then
                    local o = S.cars[j]
                    if o.axis == c.axis and o.dir == c.dir then
                        local gap = (c.axis == 1) and ((o.z - c.z) * c.dir) or ((o.x - c.x) * c.dir)
                        if gap > 0.0 and gap < 2.6 then
                            must_stop = true
                            break
                        end
                    end
                end
            end

            if must_stop then
                c.wait = c.wait + dt
            else
                c.wait = 0.0
                if c.axis == 1 then
                    c.z = c.z + c.dir * speed_base * dt
                else
                    c.x = c.x + c.dir * speed_base * dt
                end
                eng.scene.set_pos(c.ent, c.x, DECK_Y + 0.45, c.z)
            end

            -- Cleared exit check
            if math.abs(c.x - CX) > 14.2 or math.abs(c.z - CZ) > 14.2 then
                c.active = false
                eng.scene.despawn(c.ent)
                S.cleared = S.cleared + 1
                eng.audio.play(S.sfx_clear, CX, DECK_Y + 1.0, CZ, 0)
            end
        end
    end

    -- Check cross-traffic collisions inside central intersection box
    for i = 1, #S.cars do
        local a = S.cars[i]
        if a.active and math.abs(a.x - CX) < 2.2 and math.abs(a.z - CZ) < 2.2 then
            for j = i + 1, #S.cars do
                local b = S.cars[j]
                if b.active and a.axis ~= b.axis and eng.math.dist3(a.x, 0, a.z, b.x, 0, b.z) < 1.35 then
                    a.active = false
                    b.active = false
                    eng.scene.despawn(a.ent)
                    eng.scene.despawn(b.ent)
                    S.crashes = S.crashes + 1
                    eng.audio.play(S.sfx_crash, CX, DECK_Y + 1.0, CZ, 0)
                    break
                end
            end
        end
    end

    if S.crashes >= 2 then
        S.lost = true
        eng.save.write("traffic_director_result", "pileup")
    elseif S.cleared >= S.target_clear then
        S.won = true
        eng.save.write("traffic_director_result", "clear_12")
    end
end

function draw()
    local lamp_y = DECK_Y + 3.55
    eng.render.draw_sprite(CX - 3.0, lamp_y, CZ - 3.0, 0.55, 0.55, S.orb_tex)
    eng.render.draw_sprite(CX + 3.0, lamp_y, CZ + 3.0, 0.55, 0.55, S.orb_tex)

    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 54, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or (S.lost and (" | " .. eng.i18n.t("defeat")) or "")
    eng.ui.label(x, y, eng.i18n.t("title") .. " | GREEN: " .. S.phase .. " | CRASHES: " .. S.crashes .. "/2" .. status, 1.0, {1.0, 0.92, 0.45, 1.0})
    eng.ui.bar(x, y + 24, 240, S.cleared / S.target_clear, "CLEARED " .. S.cleared .. "/12 ")
end
