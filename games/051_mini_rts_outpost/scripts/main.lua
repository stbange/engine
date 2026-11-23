-- 051_mini_rts_outpost: Command crystal harvesters & deploy light tanks vs Rival HQ
local S = game.state

local function spawn_tank(is_enemy, x, z)
    local hull = eng.scene.spawn(is_enemy and "raider_tank" or "light_tank")
    eng.scene.set_pos(hull, x, 0.45, z)
    eng.scene.set_scale(hull, 1.3, 0.7, 1.7)
    local col = is_enemy and {0.92, 0.24, 0.20, 1.0} or {0.22, 0.62, 0.96, 1.0}
    eng.scene.set_mesh(hull, S.box_mesh, { tex = S.metal_tex, color = col, cast_shadow = true })

    local tur = eng.scene.spawn(is_enemy and "raider_turret" or "tank_turret")
    eng.scene.set_parent(tur, hull)
    eng.scene.set_pos(tur, 0.0, 0.65, -0.1)
    eng.scene.set_scale(tur, 0.65, 0.55, 0.95)
    eng.scene.set_mesh(tur, S.box_mesh, { color = is_enemy and {1.0, 0.45, 0.3, 1.0} or {0.45, 0.82, 1.0, 1.0} })

    local list = is_enemy and S.raiders or S.tanks
    list[#list + 1] = {
        ent = hull, x = x, z = z,
        hp = is_enemy and 24 or 42,
        cd = 0.0, alive = true
    }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.012 })
    eng.render.set_sky(0.08, 0.14, 0.26, 0.36, 0.28, 0.20)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.1, 1.95, 1.75}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.0, 0.0}, color = {1.2, 1.6, 2.2}, range = 36.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.6, 0.6, 1.0, 10)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.ground_tex = eng.procgen.texture("cobble", seed_base, 64)
    S.metal_tex = eng.procgen.texture("sci_fi_panel", seed_base + 7, 64)
    S.sfx_deploy = eng.audio.synth("square", 280, 0.14, 520)
    S.sfx_cannon = eng.audio.synth("noise", 220, 0.10, 80)
    S.sfx_harvest = eng.audio.synth("triangle", 600, 0.12, 880)

    local ground = eng.scene.spawn("canyon_floor")
    eng.scene.set_pos(ground, 0.0, -0.25, 0.0)
    eng.scene.set_scale(ground, 38.0, 0.5, 28.0)
    eng.scene.set_mesh(ground, S.box_mesh, { tex = S.ground_tex, color = {0.72, 0.65, 0.52, 1.0} })
    eng.physics.add_body(ground, { shape = "aabb", motion = "static", half_extents = {19.0, 0.25, 14.0} })
    eng.ai.set_grid(0, 2.0, 18, 14)

    -- Canyon rock ridges
    for i = 1, 4 do
        local rx = (i <= 2) and (-7.0 + (i - 1) * 14.0) or (-6.0 + (i - 3) * 12.0)
        local rz = (i <= 2) and -11.5 or 11.5
        local rock = eng.scene.spawn("ridge_" .. tostring(i))
        eng.scene.set_pos(rock, rx, 1.2, rz)
        eng.scene.set_scale(rock, 6.0, 2.4, 2.2)
        eng.scene.set_mesh(rock, S.box_mesh, { tex = S.ground_tex, color = {0.48, 0.42, 0.36, 1.0}, cast_shadow = true })
    end

    -- Player HQ & Rival HQ
    S.hq_x, S.hq_z = -12.5, 5.5
    S.hq_hp = 100
    S.hq_ent = eng.scene.spawn("player_hq")
    eng.scene.set_pos(S.hq_ent, S.hq_x, 1.4, S.hq_z)
    eng.scene.set_scale(S.hq_ent, 3.2, 2.8, 3.2)
    eng.scene.set_mesh(S.hq_ent, S.box_mesh, { tex = S.metal_tex, color = {0.20, 0.58, 0.95, 1.0}, cast_shadow = true })

    S.enemy_x, S.enemy_z = 12.5, -5.5
    S.enemy_hp = 100
    S.enemy_ent = eng.scene.spawn("rival_hq")
    eng.scene.set_pos(S.enemy_ent, S.enemy_x, 1.5, S.enemy_z)
    eng.scene.set_scale(S.enemy_ent, 3.4, 3.0, 3.4)
    eng.scene.set_mesh(S.enemy_ent, S.box_mesh, { tex = S.metal_tex, color = {0.90, 0.22, 0.22, 1.0}, cast_shadow = true })

    -- 3 Crystal Fields
    local node_coords = { {-6.5, -1.5}, {-1.5, 4.0}, {1.5, -3.5} }
    S.nodes = {}
    for i = 1, #node_coords do
        local nx, nz = node_coords[i][1], node_coords[i][2]
        local ce = eng.scene.spawn("crystal_field_" .. tostring(i))
        eng.scene.set_pos(ce, nx, 0.0, nz)
        eng.scene.set_scale(ce, 1.6, 1.8, 1.6)
        eng.scene.set_mesh(ce, S.crystal_mesh, { color = {0.25, 0.95, 0.85, 1.0}, cast_shadow = true })
        S.nodes[i] = { ent = ce, x = nx, z = nz, reserve = 300 }
    end

    -- 2 Crystal Harvesters
    S.harvesters = {}
    for i = 1, 2 do
        local hx, hz = S.hq_x + 2.6, S.hq_z - (i - 1) * 2.4
        local he = eng.scene.spawn("harvester_" .. tostring(i))
        eng.scene.set_pos(he, hx, 0.5, hz)
        eng.scene.set_scale(he, 1.3, 0.9, 1.5)
        eng.scene.set_mesh(he, S.crate_mesh, { color = {0.95, 0.80, 0.20, 1.0}, cast_shadow = true })
        S.harvesters[i] = { ent = he, x = hx, z = hz, node_idx = i, cargo = 0, returning = false }
    end

    -- Command Cursor
    S.cx, S.cz = -3.0, 0.0
    S.rally_x, S.rally_z = S.enemy_x, S.enemy_z
    S.cursor_ent = eng.scene.spawn("command_cursor")
    eng.scene.set_pos(S.cursor_ent, S.cx, 0.15, S.cz)
    eng.scene.set_scale(S.cursor_ent, 1.6, 0.25, 1.6)
    eng.scene.set_mesh(S.cursor_ent, S.cyl_mesh, { color = {0.3, 1.0, 0.45, 1.0} })

    S.crystals = 70
    S.harvested_total = 0
    S.tanks_deployed = 0
    S.kills = 0
    S.tanks = {}
    S.raiders = {}
    S.shots = {}
    S.fire_cd = 0.0
    S.order_cd = 0.0
    S.raider_timer = 1.8
    S.won = false
    S.lost = false

    spawn_tank(false, S.hq_x + 3.2, S.hq_z + 1.2)
    S.tanks_deployed = 1
    spawn_tank(true, S.enemy_x - 3.5, S.enemy_z + 1.0)

    eng.camera.look_at(0.0, 21.0, 18.5, 0.0, 0.5, -1.0, 0)
    eng.mod.emit("post_init")
end

local function step_toward(u, tx, tz, speed, dt)
    local dx, dz = tx - u.x, tz - u.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d > 0.25 then
        u.x = u.x + (dx / d) * speed * dt
        u.z = u.z + (dz / d) * speed * dt
        eng.scene.set_pos(u.ent, u.x, 0.45, u.z)
        eng.scene.set_rot_deg(u.ent, 0.0, math.deg(math.atan2(-dx, -dz)), 0.0)
    end
    return d
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.order_cd = math.max(0.0, S.order_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.cx = eng.math.clamp(S.cx + mx * 14.0 * dt, -15.0, 15.0)
        S.cz = eng.math.clamp(S.cz - my * 14.0 * dt, -10.5, 10.5)
        eng.scene.set_pos(S.cursor_ent, S.cx, 0.15, S.cz)
    end

    -- Interact: assign harvesters to nearest crystal node & set tank rally + overdrive pulse
    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.order_cd <= 0.0 then
        S.order_cd = 0.45
        S.rally_x, S.rally_z = S.cx, S.cz
        local best_i, best_d = 1, 999.0
        for i = 1, #S.nodes do
            local d = eng.math.dist3(S.cx, 0, S.cz, S.nodes[i].x, 0, S.nodes[i].z)
            if d < best_d then best_d = d; best_i = i end
        end
        if best_d < 7.0 then
            S.harvesters[1].node_idx = best_i
        end
        S.crystals = S.crystals + 12
        S.harvested_total = S.harvested_total + 12
        eng.audio.play(S.sfx_harvest, S.cx, 1.0, S.cz, 0)
    end

    -- Fire: deploy Light Tank from Player HQ (cost 30 crystals)
    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 and S.crystals >= 30 then
        S.fire_cd = 0.28
        S.crystals = S.crystals - 30
        local offset_z = ((S.tanks_deployed % 3) - 1) * 1.9
        spawn_tank(false, S.hq_x + 3.2, S.hq_z + offset_z)
        S.tanks_deployed = S.tanks_deployed + 1
        eng.audio.play(S.sfx_deploy, S.hq_x, 1.5, S.hq_z, 0)
    end

    -- Harvester shuttle loop
    for i = 1, #S.harvesters do
        local h = S.harvesters[i]
        local nd = S.nodes[h.node_idx]
        if not h.returning then
            if step_toward(h, nd.x, nd.z, 6.8, dt) < 1.5 then
                h.cargo = 25
                h.returning = true
            end
        else
            if step_toward(h, S.hq_x + 2.0, S.hq_z, 6.8, dt) < 1.8 then
                S.crystals = S.crystals + h.cargo
                S.harvested_total = S.harvested_total + h.cargo
                h.cargo = 0
                h.returning = false
                eng.audio.play(S.sfx_harvest, S.hq_x, 1.2, S.hq_z, 0)
            end
        end
    end

    -- Rival HQ spawns raiders periodically
    S.raider_timer = S.raider_timer - dt
    if S.raider_timer <= 0.0 and #S.raiders < 6 then
        S.raider_timer = 2.6
        spawn_tank(true, S.enemy_x - 3.2, S.enemy_z + eng.math.range(-2.0, 2.0))
    end

    -- Update Player Light Tanks
    for i = 1, #S.tanks do
        local tk = S.tanks[i]
        if tk.alive then
            tk.cd = math.max(0.0, tk.cd - dt)
            local target_r = nil
            local best_d = 9.5
            for j = 1, #S.raiders do
                local r = S.raiders[j]
                if r.alive then
                    local d = eng.math.dist3(tk.x, 0, tk.z, r.x, 0, r.z)
                    if d < best_d then best_d = d; target_r = r end
                end
            end

            if target_r then
                if best_d > 5.5 then step_toward(tk, target_r.x, target_r.z, 6.5, dt) end
                if tk.cd <= 0.0 then
                    tk.cd = 0.35
                    target_r.hp = target_r.hp - 14
                    S.shots[#S.shots + 1] = { x = target_r.x, z = target_r.z, ttl = 0.14 }
                    eng.audio.play(S.sfx_cannon, tk.x, 0.8, tk.z, 0)
                    if target_r.hp <= 0 then
                        target_r.alive = false
                        eng.scene.despawn(target_r.ent)
                        S.kills = S.kills + 1
                        S.crystals = S.crystals + 15
                    end
                end
            else
                local d_hq = eng.math.dist3(tk.x, 0, tk.z, S.enemy_x, 0, S.enemy_z)
                if d_hq > 5.2 then
                    step_toward(tk, S.enemy_x, S.enemy_z, 7.2, dt)
                elseif tk.cd <= 0.0 then
                    tk.cd = 0.32
                    S.enemy_hp = math.max(0, S.enemy_hp - 14)
                    S.shots[#S.shots + 1] = { x = S.enemy_x - 1.2, z = S.enemy_z + 1.0, ttl = 0.16 }
                    eng.audio.play(S.sfx_cannon, tk.x, 0.8, tk.z, 0)
                end
            end
        end
    end

    -- Update Rival Raiders
    for i = 1, #S.raiders do
        local r = S.raiders[i]
        if r.alive then
            r.cd = math.max(0.0, r.cd - dt)
            local target_t = nil
            local best_d = 8.5
            for j = 1, #S.tanks do
                local tk = S.tanks[j]
                if tk.alive then
                    local d = eng.math.dist3(r.x, 0, r.z, tk.x, 0, tk.z)
                    if d < best_d then best_d = d; target_t = tk end
                end
            end
            if target_t then
                if best_d > 5.0 then step_toward(r, target_t.x, target_t.z, 5.2, dt) end
                if r.cd <= 0.0 then
                    r.cd = 0.55
                    target_t.hp = target_t.hp - 7
                    if target_t.hp <= 0 then
                        target_t.alive = false
                        eng.scene.despawn(target_t.ent)
                    end
                end
            else
                local d_hq = eng.math.dist3(r.x, 0, r.z, S.hq_x, 0, S.hq_z)
                if d_hq > 4.8 then
                    step_toward(r, S.hq_x, S.hq_z, 5.0, dt)
                elseif r.cd <= 0.0 then
                    r.cd = 0.65
                    S.hq_hp = math.max(0, S.hq_hp - 8)
                end
            end
        end
    end

    for i = #S.shots, 1, -1 do
        S.shots[i].ttl = S.shots[i].ttl - dt
        if S.shots[i].ttl <= 0.0 then table.remove(S.shots, i) end
    end

    if S.enemy_hp <= 0 then
        S.won = true
        eng.scene.despawn(S.enemy_ent)
        eng.save.write("rts_outpost_status", "victory")
    elseif S.hq_hp <= 0 then
        S.lost = true
        eng.save.write("rts_outpost_status", "defeat")
    end
end

function draw()
    for i = 1, #S.shots do
        eng.render.draw_sprite(S.shots[i].x, 1.4, S.shots[i].z, 1.1, 1.1, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 64, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or (S.lost and (" | " .. eng.i18n.t("defeat")) or "")
    eng.ui.label(x, y, eng.i18n.t("title") .. " | CRYSTALS: " .. S.crystals .. " | TANKS: " .. S.tanks_deployed .. status, 1.0, {0.85, 0.96, 1.0, 1.0})
    eng.ui.bar(x, y + 24, 220, S.hq_hp / 100.0, "ALLY HQ  ")
    eng.ui.bar(x, y + 46, 220, S.enemy_hp / 100.0, "RIVAL HQ ")
end
