-- 017_turret_command: 3D orbital dome defense intercepting incoming meteors over 3 city batteries
local S = game.state

local CITY_X = { -10.5, 0.0, 10.5 }

local function spawn_meteor_wave(wave_num)
    S.wave = wave_num
    local count = 4
    for i = 1, count do
        local sx = -12.0 + (i - 1) * 8.0 + eng.math.range(-2.0, 2.0)
        local sy = 16.5 + (i % 2) * 2.2
        -- Aim toward one of the 3 city batteries
        local tgt_x = CITY_X[((wave_num + i - 1) % 3) + 1]
        local dx, dy = tgt_x - sx, 0.8 - sy
        local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        local spd = 4.6 + wave_num * 0.55
        local me = eng.scene.spawn("meteor_" .. tostring(wave_num) .. "_" .. tostring(i))
        eng.scene.set_pos(me, sx, sy, 0.0)
        eng.scene.set_scale(me, 0.9, 0.9, 0.9)
        eng.scene.set_mesh(me, S.unit_sphere, { color = {1.0, 0.35, 0.15, 1.0} })
        S.meteors[#S.meteors + 1] = {
            ent = me, x = sx, y = sy,
            vx = (dx / len) * spd, vy = (dy / len) * spd,
            alive = true
        }
    end
end

local function spawn_flak_sphere(x, y, max_r)
    local fe = eng.scene.spawn("flak_blast")
    eng.scene.set_pos(fe, x, y, 0.0)
    eng.scene.set_scale(fe, 0.5, 0.5, 0.5)
    eng.scene.set_mesh(fe, S.unit_sphere, { color = {0.95, 0.92, 0.35, 1.0} })
    eng.audio.play(S.sfx_flak, x, y, 0.0, 0)
    S.flaks[#S.flaks + 1] = { ent = fe, x = x, y = y, r = 0.25, max_r = max_r, t = 0.0, dur = 0.65 }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.008, crt = 0.18 })
    eng.render.set_sky(0.02, 0.03, 0.10, 0.14, 0.08, 0.24)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {2.0, 1.9, 2.2}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 10.0, 4.0}, color = {1.4, 1.8, 2.6}, range = 48.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.unit_sphere = eng.asset.sphere(0.5, 10, 12)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    local lunar_tex = eng.procgen.texture("marble", S.seed, 64)

    S.sfx_launch = eng.audio.synth("saw", 520, 0.10, 220)
    S.sfx_flak = eng.audio.synth("noise", 240, 0.20, 55)
    S.sfx_supply = eng.audio.synth("triangle", 480, 0.14, 880)
    S.sfx_emp = eng.audio.synth("sine", 720, 0.18, 190)

    local ridge_e = eng.scene.spawn("lunar_ridge")
    eng.scene.set_pos(ridge_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(ridge_e, 46.0, 0.5, 18.0)
    eng.scene.set_mesh(ridge_e, S.box_mesh, { tex = lunar_tex, color = {0.45, 0.48, 0.62, 1.0} })
    eng.physics.add_body(ridge_e, { shape = "aabb", motion = "static", half_extents = {23.0, 0.25, 9.0} })

    S.cities = {}
    for i = 1, 3 do
        local cx = CITY_X[i]
        local dome = eng.scene.spawn("city_dome_" .. tostring(i))
        eng.scene.set_pos(dome, cx, 0.6, 0.0)
        eng.scene.set_scale(dome, 3.2, 2.4, 3.2)
        eng.scene.set_mesh(dome, S.unit_sphere, { color = {0.25, 0.85, 1.0, 1.0}, metallic = 0.4, roughness = 0.2 })

        local spire = eng.scene.spawn("city_spire_" .. tostring(i))
        eng.scene.set_pos(spire, cx, 1.4, 0.0)
        eng.scene.set_mesh(spire, S.crystal_mesh, { color = {0.5, 1.0, 0.85, 1.0} })

        local tur = eng.scene.spawn("city_turret_" .. tostring(i))
        eng.scene.set_pos(tur, cx, 1.9, 0.8)
        eng.scene.set_scale(tur, 0.28, 1.1, 0.28)
        eng.scene.set_mesh(tur, S.box_mesh, { color = {0.95, 0.82, 0.30, 1.0} })

        S.cities[i] = { x = cx, dome = dome, spire = spire, tur = tur, ammo = 10, alive = true }
    end

    S.rx, S.ry = 0.0, 9.0
    S.fire_cd = 0.0
    S.supply_cd = 0.0
    S.emp_cd = 0.0
    S.score = 0
    S.intercepts = 0
    S.resupplies = 0
    S.emps_used = 0
    S.won = false
    S.lost = false
    S.interceptors = {}
    S.flaks = {}
    S.meteors = {}

    spawn_meteor_wave(1)
    eng.camera.look_at(0.0, 8.2, 22.5, 0.0, 7.2, 0.0, 0)
    eng.mod.emit("post_init")
end

local function launch_interceptor()
    local best_c = nil
    local best_d = 999.0
    for i = 1, 3 do
        local c = S.cities[i]
        if c.alive and c.ammo > 0 then
            local d = math.abs(S.rx - c.x)
            if d < best_d then best_d = d; best_c = c end
        end
    end
    if not best_c then return end
    best_c.ammo = best_c.ammo - 1

    local ox, oy = best_c.x, 2.1
    local dx, dy = S.rx - ox, S.ry - oy
    local len = math.max(0.1, math.sqrt(dx * dx + dy * dy))
    local spd = 48.0
    eng.audio.play(S.sfx_launch, ox, oy, 0.0, 0)

    local ie = eng.scene.spawn("counter_missile")
    eng.scene.set_pos(ie, ox, oy, 0.0)
    eng.scene.set_scale(ie, 0.35, 0.35, 0.35)
    eng.scene.set_mesh(ie, S.unit_sphere, { color = {0.35, 1.0, 0.75, 1.0} })
    S.interceptors[#S.interceptors + 1] = {
        ent = ie, x = ox, y = oy, tx = S.rx, ty = S.ry,
        vx = (dx / len) * spd, vy = (dy / len) * spd,
        rem = len / spd
    }
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.supply_cd = math.max(0.0, S.supply_cd - dt)
    S.emp_cd = math.max(0.0, S.emp_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.rx = eng.math.clamp(S.rx + mx * 22.0 * dt, -14.5, 14.5)
    S.ry = eng.math.clamp(S.ry + my * 18.0 * dt, 3.0, 16.0)

    -- Rotate surviving battery turrets toward sky reticle
    for i = 1, 3 do
        local c = S.cities[i]
        if c.alive then
            local ang = math.deg(math.atan2(-(S.rx - c.x), math.max(0.5, S.ry - 1.9)))
            eng.scene.set_rot_deg(c.tur, 0.0, 0.0, ang)
        end
    end

    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.supply_cd <= 0.0 then
        S.supply_cd = 1.8
        S.resupplies = S.resupplies + 1
        for i = 1, 3 do
            if S.cities[i].alive then S.cities[i].ammo = math.min(12, S.cities[i].ammo + 4) end
        end
        eng.audio.play(S.sfx_supply, 0.0, 2.0, 0.0, 0)
    end

    if eng.input.pressed("jump") and S.emp_cd <= 0.0 then
        S.emp_cd = 2.8
        S.emps_used = S.emps_used + 1
        eng.audio.play(S.sfx_emp, 0.0, 6.0, 0.0, 0)
        for i = 1, #S.meteors do
            local m = S.meteors[i]
            if m.alive then
                m.vx, m.vy = m.vx * 0.72, m.vy * 0.72
            end
        end
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
        S.fire_cd = 0.20
        launch_interceptor()
    end

    -- Step counter-missiles to target coordinates -> detonate 3D Flak Sphere
    for i = #S.interceptors, 1, -1 do
        local ic = S.interceptors[i]
        ic.rem = ic.rem - dt
        ic.x = ic.x + ic.vx * dt
        ic.y = ic.y + ic.vy * dt
        if ic.rem <= 0.0 then
            spawn_flak_sphere(ic.tx, ic.ty, 3.8)
            eng.scene.despawn(ic.ent)
            table.remove(S.interceptors, i)
        else
            eng.scene.set_pos(ic.ent, ic.x, ic.y, 0.0)
        end
    end

    -- Expand & decay 3D Flak Blast Spheres (chain-vaporizing meteors inside radius!)
    for i = #S.flaks, 1, -1 do
        local fl = S.flaks[i]
        fl.t = fl.t + dt
        local frac = math.sin(math.min(1.0, fl.t / fl.dur) * math.pi)
        fl.r = math.max(0.2, fl.max_r * frac)
        eng.scene.set_scale(fl.ent, fl.r * 2.0, fl.r * 2.0, fl.r * 2.0)

        for j = 1, #S.meteors do
            local m = S.meteors[j]
            if m.alive then
                local dx, dy = m.x - fl.x, m.y - fl.y
                if (dx * dx + dy * dy) <= (fl.r + 0.5) * (fl.r + 0.5) then
                    m.alive = false
                    eng.scene.despawn(m.ent)
                    S.intercepts = S.intercepts + 1
                    S.score = S.score + 150
                    spawn_flak_sphere(m.x, m.y, 2.2)
                end
            end
        end

        if fl.t >= fl.dur then
            eng.scene.despawn(fl.ent)
            table.remove(S.flaks, i)
        end
    end

    -- Step orbital meteors & check city dome impacts
    local active_meteors = 0
    for i = 1, #S.meteors do
        local m = S.meteors[i]
        if m.alive then
            active_meteors = active_meteors + 1
            m.x = m.x + m.vx * dt
            m.y = m.y + m.vy * dt
            eng.scene.set_pos(m.ent, m.x, m.y, 0.0)
            if m.y <= 1.3 then
                m.alive = false
                eng.scene.despawn(m.ent)
                active_meteors = active_meteors - 1
                for c = 1, 3 do
                    local ct = S.cities[c]
                    if ct.alive and math.abs(m.x - ct.x) < 2.5 then
                        ct.alive = false
                        eng.scene.despawn(ct.dome)
                        eng.scene.despawn(ct.spire)
                        eng.scene.despawn(ct.tur)
                        eng.audio.play(S.sfx_flak, ct.x, 1.0, 0.0, 0)
                    end
                end
            end
        end
    end

    local cities_standing = 0
    local total_ammo = 0
    for i = 1, 3 do
        if S.cities[i].alive then
            cities_standing = cities_standing + 1
            total_ammo = total_ammo + S.cities[i].ammo
        end
    end
    S.cities_standing = cities_standing
    S.total_ammo = total_ammo

    if cities_standing == 0 then
        S.lost = true
    elseif active_meteors == 0 then
        if S.wave < 3 then
            spawn_meteor_wave(S.wave + 1)
        else
            S.won = true
            S.score = S.score + cities_standing * 400
            eng.save.write("turret_cmd_best", tostring(S.score))
        end
    end
end

function draw()
    eng.render.draw_sprite(S.rx, S.ry, 0.5, 1.1, 1.1, S.orb_tex)
    for i = 1, #S.meteors do
        local m = S.meteors[i]
        if m.alive then eng.render.draw_sprite(m.x, m.y + 0.6, 0.0, 0.7, 0.7, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 60, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | WAVE " .. S.wave .. "/3 | INTERCEPTS " .. S.intercepts .. " | AMMO " .. (S.total_ammo or 0)))
    eng.ui.label(x, y, msg, 1.0, {0.45, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, (S.cities_standing or 3) / 3.0, "CITIES ")
end
