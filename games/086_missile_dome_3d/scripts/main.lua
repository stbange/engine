-- 086_missile_dome_3d: Protect 4 Crystal Dome Cities on a Curved Planet Horizon with Flak Shockwaves
local S = game.state

local CITY_X = { -7.0, -2.9, 2.9, 7.0 }
local PLANE_Z = -6.0

local function start_wave(w_idx)
    S.wave = w_idx
    S.to_spawn = 3 + w_idx -- Wave 1: 4, Wave 2: 5, Wave 3: 6 (15 warheads total)
    S.spawn_timer = 0.08
end

local function spawn_shockwave(x, y, max_r, color)
    local se = eng.scene.spawn("flak_shockwave")
    eng.scene.set_pos(se, x, y, PLANE_Z)
    eng.scene.set_scale(se, 0.42, 0.42, 0.42)
    eng.scene.set_mesh(se, S.unit_sphere, { color = color or {1.0, 0.78, 0.25, 1.0}, roughness = 0.15 })
    S.shocks[#S.shocks + 1] = { ent = se, x = x, y = y, r = 0.42, max_r = max_r, age = 0.0, dur = 0.50 }
end

local function spawn_warhead()
    -- Aim at a living Crystal Dome City
    local live_cities = {}
    for i = 1, #S.cities do
        if S.cities[i].alive then live_cities[#live_cities + 1] = S.cities[i] end
    end
    if #live_cities == 0 then return end
    local tgt = live_cities[math.floor(eng.math.range(1, #live_cities + 0.99))]

    S.next_wid = S.next_wid + 1
    local sx = eng.math.range(-8.6, 8.6)
    local sy = 13.0
    local dx, dy = tgt.x - sx, (tgt.y + 0.55) - sy
    local len = math.sqrt(dx * dx + dy * dy)
    local spd = 5.6 + (S.wave - 1) * 0.65
    local vx, vy = (dx / len) * spd, (dy / len) * spd

    local we = eng.scene.spawn("warhead_" .. tostring(S.next_wid))
    eng.scene.set_pos(we, sx, sy, PLANE_Z)
    local roll = math.deg(math.atan2(-vx, vy))
    eng.scene.set_rot_deg(we, 0.0, 0.0, roll)
    eng.scene.set_mesh(we, S.warhead_mesh, { color = {1.0, 0.22, 0.18, 1.0}, roughness = 0.30, cast_shadow = true })

    S.warheads[#S.warheads + 1] = {
        id = S.next_wid, ent = we, x = sx, y = sy, vx = vx, vy = vy,
        target_city = tgt, alive = true
    }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.02, 0.03, 0.11, 0.14, 0.08, 0.26)
    eng.render.add_light({ type = "dir", dir = {-0.35, -0.9, -0.4}, color = {2.0, 1.9, 1.8}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 7.0, -3.0}, color = {1.3, 1.8, 2.5}, range = 32.0 })

    local seed = math.floor(eng.math.range(20, 60000))
    S.unit_sphere = eng.asset.sphere(1.0, 14, 18)
    S.shell_mesh = eng.asset.sphere(0.18, 8, 10)
    S.warhead_mesh = eng.asset.cylinder(0.20, 0.04, 0.85, 10)
    S.pad_mesh = eng.asset.cylinder(1.45, 1.60, 0.36, 16)
    S.barrel_mesh = eng.asset.cylinder(0.16, 0.12, 1.15, 10)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.metal_tex = eng.procgen.texture("sci_fi_panel", seed + 7, 64)

    S.sfx_launch = eng.audio.synth("triangle", 340, 0.07, 640)
    S.sfx_flak = eng.audio.synth("noise", 420, 0.16, 95)
    S.sfx_intercept = eng.audio.synth("sine", 540, 0.12, 920)
    S.sfx_shatter = eng.audio.synth("saw", 240, 0.22, 70)

    -- Curved 3D Procedural Planet Horizon (`eng.procgen.planet`)
    local planet_r = 28.0
    S.planet_mesh = eng.procgen.planet(seed, planet_r, 22, 0.0)
    S.planet_ent = eng.scene.spawn("curved_horizon_planet")
    eng.scene.set_pos(S.planet_ent, 0.0, -31.2, PLANE_Z)
    eng.scene.set_mesh(S.planet_ent, S.planet_mesh, { roughness = 0.82 })

    -- 4 Crystal Dome Cities perched along the curved planetary horizon
    local dome_tints = {
        {0.25, 0.92, 1.0, 1.0},
        {0.42, 1.0, 0.68, 1.0},
        {0.78, 0.48, 1.0, 1.0},
        {1.0, 0.82, 0.30, 1.0}
    }
    S.cities = {}
    for i = 1, 4 do
        local cx = CITY_X[i]
        local cy = 0.55 - (cx * cx) * 0.022
        local tilt_deg = -math.deg(math.atan2(cx, 28.0))

        local pad = eng.scene.spawn("city_pad_" .. i)
        eng.scene.set_pos(pad, cx, cy, PLANE_Z)
        eng.scene.set_rot_deg(pad, 0.0, 0.0, tilt_deg)
        eng.scene.set_mesh(pad, S.pad_mesh, { tex = S.metal_tex, color = {0.42, 0.48, 0.58, 1.0}, cast_shadow = true })

        local spire = eng.scene.spawn("crystal_spire_" .. i)
        eng.scene.set_pos(spire, cx, cy + 0.18, PLANE_Z)
        eng.scene.set_rot_deg(spire, 0.0, i * 35.0, tilt_deg)
        eng.scene.set_scale(spire, 1.15, 1.35, 1.15)
        eng.scene.set_mesh(spire, S.crystal_mesh, { color = dome_tints[i], roughness = 0.12, cast_shadow = true })

        local dome = eng.scene.spawn("crystal_dome_" .. i)
        eng.scene.set_pos(dome, cx, cy + 0.42, PLANE_Z)
        eng.scene.set_scale(dome, 1.22, 0.95, 1.22)
        eng.scene.set_mesh(dome, S.unit_sphere, { color = dome_tints[i], metallic = 0.25, roughness = 0.10 })

        S.cities[i] = { x = cx, y = cy, dome = dome, spire = spire, alive = true }
    end

    -- Central Flak Defense Battery at Planet Crest
    local base = eng.scene.spawn("flak_battery_base")
    eng.scene.set_pos(base, 0.0, 0.72, PLANE_Z)
    eng.scene.set_scale(base, 0.85, 1.1, 0.85)
    eng.scene.set_mesh(base, S.pad_mesh, { tex = S.metal_tex, color = {0.75, 0.80, 0.88, 1.0}, cast_shadow = true })

    S.turret_ent = eng.scene.spawn("flak_barrel")
    eng.scene.set_pos(S.turret_ent, 0.0, 1.25, PLANE_Z)
    eng.scene.set_mesh(S.turret_ent, S.barrel_mesh, { color = {1.0, 0.78, 0.25, 1.0}, cast_shadow = true })

    S.rx, S.ry = 0.0, 7.2
    S.cooldown = 0.0
    S.shells = {}
    S.shocks = {}
    S.warheads = {}
    S.next_wid = 0
    S.cities_alive = 4
    S.flak_detonated = 0
    S.intercepted = 0
    S.score = 0
    S.won = false
    S.lost = false

    start_wave(1)
    eng.camera.look_at(0.0, 6.2, 13.0, 0.0, 4.8, PLANE_Z, 0)
    eng.mod.emit("post_init")
end

local function launch_flak(tx, ty)
    S.cooldown = 0.14
    local ox, oy = 0.0, 1.35
    local dx, dy = tx - ox, ty - oy
    local dist = math.max(0.2, math.sqrt(dx * dx + dy * dy))
    local spd = 32.0
    local se = eng.scene.spawn("flak_shell")
    eng.scene.set_pos(se, ox, oy, PLANE_Z)
    eng.scene.set_mesh(se, S.shell_mesh, { color = {0.45, 1.0, 0.95, 1.0} })
    S.shells[#S.shells + 1] = {
        ent = se, x = ox, y = oy, tx = tx, ty = ty,
        vx = (dx / dist) * spd, vy = (dy / dist) * spd, rem = dist / spd
    }
    eng.audio.play(S.sfx_launch, ox, oy, PLANE_Z, 0)
end

function update(dt)
    if S.won or S.lost then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)

    -- Aim sky reticle & rotate central Flak barrel
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.rx = eng.math.clamp(S.rx + mx * 22.0 * dt, -9.8, 9.8)
    S.ry = eng.math.clamp(S.ry + my * 18.0 * dt, 2.2, 12.2)

    local aim_deg = -math.deg(math.atan2(S.rx, math.max(0.5, S.ry - 1.25)))
    eng.scene.set_rot_deg(S.turret_ent, 0.0, 0.0, aim_deg)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        launch_flak(S.rx, S.ry)
    end

    -- Spawn wave warheads
    if S.to_spawn > 0 then
        S.spawn_timer = S.spawn_timer - dt
        if S.spawn_timer <= 0.0 then
            S.to_spawn = S.to_spawn - 1
            S.spawn_timer = 0.24
            spawn_warhead()
        end
    end

    -- Advance interceptor shells -> detonate into Flak Shockwaves!
    for i = #S.shells, 1, -1 do
        local sh = S.shells[i]
        sh.rem = sh.rem - dt
        sh.x = sh.x + sh.vx * dt
        sh.y = sh.y + sh.vy * dt
        if sh.rem <= 0.0 then
            eng.scene.despawn(sh.ent)
            S.flak_detonated = S.flak_detonated + 1
            spawn_shockwave(sh.tx, sh.ty, 2.65, {1.0, 0.80, 0.24, 1.0})
            eng.audio.play(S.sfx_flak, sh.tx, sh.ty, PLANE_Z, 0)
            table.remove(S.shells, i)
        else
            eng.scene.set_pos(sh.ent, sh.x, sh.y, PLANE_Z)
        end
    end

    -- Expand & expire 3D Flak Shockwaves
    for i = #S.shocks, 1, -1 do
        local sk = S.shocks[i]
        sk.age = sk.age + dt
        if sk.age >= sk.dur then
            eng.scene.despawn(sk.ent)
            table.remove(S.shocks, i)
        else
            local frac = math.sin((sk.age / sk.dur) * math.pi * 0.85)
            sk.r = math.max(0.35, sk.max_r * frac)
            eng.scene.set_scale(sk.ent, sk.r, sk.r, sk.r)
        end
    end

    -- Step incoming warheads & test shockwave interception / dome impact
    for i = #S.warheads, 1, -1 do
        local w = S.warheads[i]
        w.x = w.x + w.vx * dt
        w.y = w.y + w.vy * dt

        local hit_flak = false
        for k = 1, #S.shocks do
            local sk = S.shocks[k]
            local dx, dy = w.x - sk.x, w.y - sk.y
            if (dx * dx + dy * dy) <= (sk.r + 0.34) * (sk.r + 0.34) then
                hit_flak = true
                break
            end
        end

        if hit_flak then
            eng.scene.despawn(w.ent)
            S.intercepted = S.intercepted + 1
            S.score = S.score + 125
            -- Secondary chain-detonation pulse!
            spawn_shockwave(w.x, w.y, 1.55, {0.35, 0.95, 1.0, 1.0})
            eng.audio.play(S.sfx_intercept, w.x, w.y, PLANE_Z, 0)
            table.remove(S.warheads, i)
        elseif w.y <= w.target_city.y + 0.65 then
            eng.scene.despawn(w.ent)
            local c = w.target_city
            if c.alive then
                c.alive = false
                S.cities_alive = S.cities_alive - 1
                eng.scene.despawn(c.dome)
                eng.scene.despawn(c.spire)
                eng.audio.play(S.sfx_shatter, c.x, c.y + 0.5, PLANE_Z, 0)
            end
            table.remove(S.warheads, i)
            if S.cities_alive <= 0 then S.lost = true end
        else
            eng.scene.set_pos(w.ent, w.x, w.y, PLANE_Z)
        end
    end

    -- Wave progression & Victory check
    if S.to_spawn == 0 and #S.warheads == 0 and S.cities_alive > 0 then
        if S.wave < 3 then
            start_wave(S.wave + 1)
        else
            S.won = true
            S.score = S.score + S.cities_alive * 250
            eng.save.write("missile_dome_clear", tostring(S.score))
        end
    end
end

function draw()
    -- Draw sky targeting reticle & warhead exhaust glints
    eng.render.draw_sprite(S.rx, S.ry, PLANE_Z + 0.3, 0.55, 0.55, S.orb_tex)
    for i = 1, #S.warheads do
        local w = S.warheads[i]
        eng.render.draw_sprite(w.x, w.y + 0.45, PLANE_Z, 0.38, 0.38, S.orb_tex)
    end

    local x, y = eng.ui.anchor("top_left", 16, 14, 580, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | WAVE " .. S.wave .. "/3 | DOMES " .. S.cities_alive .. "/4 | SCORE " .. S.score, 1.0, {0.45, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.cities_alive / 4.0, "CITIES ")
end
