-- 011_cyber_tank_battle: Battlezone-style retro 3D tank combat with radar, turret slew & shell ballistics
local S = game.state

local function fwd_from_yaw(yaw_deg)
    local r = math.rad(yaw_deg)
    return -math.sin(r), -math.cos(r)
end

local function wrap_deg(a)
    while a > 180.0 do a = a - 360.0 end
    while a < -180.0 do a = a + 360.0 end
    return a
end

local function blocked_by_obstacle(x, z, radius)
    for i = 1, #S.obstacles do
        local ob = S.obstacles[i]
        local dx, dz = x - ob.x, z - ob.z
        if (dx * dx + dz * dz) < (ob.r + radius) * (ob.r + radius) then
            return true
        end
    end
    return false
end

local function spawn_tank_visual(name, x, z, hull_col, tur_col)
    local hull = eng.scene.spawn(name .. "_hull")
    eng.scene.set_pos(hull, x, 0.45, z)
    eng.scene.set_scale(hull, 1.8, 0.7, 2.4)
    eng.scene.set_mesh(hull, S.box_mesh, { color = hull_col, metallic = 0.6, roughness = 0.35, cast_shadow = true })

    local tur = eng.scene.spawn(name .. "_turret")
    eng.scene.set_parent(tur, hull)
    eng.scene.set_pos(tur, 0.0, 0.75, 0.0)
    eng.scene.set_scale(tur, 0.62, 0.55, 0.62)
    eng.scene.set_mesh(tur, S.box_mesh, { color = tur_col, metallic = 0.7, roughness = 0.3 })

    local barrel = eng.scene.spawn(name .. "_barrel")
    eng.scene.set_parent(barrel, tur)
    eng.scene.set_pos(barrel, 0.0, 0.1, -1.1)
    eng.scene.set_scale(barrel, 0.22, 0.22, 1.6)
    eng.scene.set_mesh(barrel, S.box_mesh, { color = tur_col, metallic = 0.8, roughness = 0.25 })
    return hull, tur, barrel
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 4, fog_density = 0.014, crt = 0.22 })
    eng.render.set_sky(0.01, 0.05, 0.03, 0.04, 0.22, 0.12)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {1.2, 2.2, 1.5}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 12.0, 0.0}, color = {0.5, 2.4, 1.4}, range = 65.0 })

    local seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.28, 8, 10)
    S.pyr_mesh = eng.asset.cylinder(1.1, 0.05, 2.4, 4)
    S.grid_tex = eng.asset.load_texture("assets/shared/textures/checker.png", true)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_cannon = eng.audio.synth("noise", 220, 0.16, 55)
    S.sfx_ping = eng.audio.synth("sine", 880, 0.12, 1320)
    S.sfx_boom = eng.audio.synth("saw", 150, 0.24, 38)

    local floor_e = eng.scene.spawn("cyber_grid_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 84.0, 0.5, 84.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = S.grid_tex, color = {0.08, 0.36, 0.20, 1.0}, roughness = 0.85 })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {42.0, 0.25, 42.0} })

    S.px, S.pz = 0.0, 22.0
    S.hull_yaw = 0.0
    S.turret_rel_yaw = 0.0
    S.shield = 100
    S.score = 0
    S.kills = 0
    S.shots_fired = 0
    S.radar_pings = 0
    S.radar_bearing = 0
    S.radar_range = 0
    S.locked_idx = 0
    S.fire_cd = 0.0
    S.ping_cd = 0.0
    S.won = false
    S.lost = false
    S.shells = {}
    S.flashes = {}
    S.obstacles = {}
    S.enemies = {}

    S.player_hull, S.player_tur, S.player_barrel = spawn_tank_visual("player_tank", S.px, S.pz,
        {0.15, 0.95, 0.55, 1.0}, {0.35, 1.0, 0.75, 1.0})

    local enemy_slots = { {-18.0, -14.0}, {-6.5, -22.0}, {7.0, -20.0}, {18.5, -12.0} }
    for i = 1, #enemy_slots do
        local ex = enemy_slots[i][1] + eng.math.range(-1.5, 1.5)
        local ez = enemy_slots[i][2] + eng.math.range(-1.5, 1.5)
        local eh, et, eb = spawn_tank_visual("enemy_tank_" .. tostring(i), ex, ez,
            {0.95, 0.28, 0.18, 1.0}, {1.0, 0.55, 0.20, 1.0})
        S.enemies[#S.enemies + 1] = {
            hull = eh, tur = et, barrel = eb, x = ex, z = ez, vx = 0.0, vz = 0.0, yaw = 180.0,
            hp = 2, alive = true, fire_t = 1.4 + i * 0.55, strafe_dir = (i % 2 == 0) and 1.0 or -1.0
        }
    end

    local pts = eng.procgen.scatter_poisson(seed, 56.0, 56.0, 9.5, 16)
    for i = 1, #pts do
        local ox, oz = pts[i][1] - 28.0, pts[i][2] - 28.0
        local safe = eng.math.dist3(ox, 0, oz, S.px, 0, S.pz) > 7.5
        for j = 1, #S.enemies do
            if eng.math.dist3(ox, 0, oz, S.enemies[j].x, 0, S.enemies[j].z) < 6.0 then safe = false end
        end
        if safe then
            local oe = eng.scene.spawn("radar_ob_" .. tostring(i))
            local is_pyr = (i % 2) == 0
            eng.scene.set_pos(oe, ox, 1.0, oz)
            if is_pyr then
                eng.scene.set_mesh(oe, S.pyr_mesh, { color = {0.15, 0.85, 0.45, 1.0}, cast_shadow = true })
            else
                eng.scene.set_scale(oe, 2.0, 2.0, 2.0)
                eng.scene.set_mesh(oe, S.box_mesh, { color = {0.12, 0.72, 0.52, 1.0}, cast_shadow = true })
            end
            eng.physics.add_body(oe, { shape = "aabb", motion = "static", half_extents = {1.0, 1.0, 1.0} })
            S.obstacles[#S.obstacles + 1] = { ent = oe, x = ox, z = oz, r = 1.35 }
        end
    end

    local fx, fz = fwd_from_yaw(0.0)
    eng.camera.look_at(S.px - fx * 3.8, 2.4, S.pz - fz * 3.8, S.px + fx * 16.0, 1.1, S.pz + fz * 16.0, 0)
    eng.mod.emit("post_init")
end

local function spawn_shell(ox, oy, oz, vx, vy, vz, from_player)
    local se = eng.scene.spawn(from_player and "player_shell" or "enemy_shell")
    eng.scene.set_pos(se, ox, oy, oz)
    local col = from_player and {0.4, 1.0, 0.65, 1.0} or {1.0, 0.35, 0.2, 1.0}
    eng.scene.set_mesh(se, S.sphere_mesh, { color = col })
    S.shells[#S.shells + 1] = {
        ent = se, x = ox, y = oy, z = oz, vx = vx, vy = vy, vz = vz,
        from_player = from_player, life = 3.2, alive = true
    }
end

local function fire_player_shell()
    local world_tur_yaw = S.hull_yaw + S.turret_rel_yaw
    local dx, dz = fwd_from_yaw(world_tur_yaw)
    local speed = 42.0
    local vy = 3.5
    -- Ballistic rangefinder & lead solution when aimed near a living target
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local d0 = eng.math.dist3(S.px, 0, S.pz, en.x, 0, en.z)
            local t0 = math.max(0.08, (d0 - 1.5) / speed)
            local lx, lz = en.x + en.vx * t0, en.z + en.vz * t0
            local to_yaw = math.deg(math.atan2(-(lx - S.px), -(lz - S.pz)))
            if math.abs(wrap_deg(to_yaw - world_tur_yaw)) < 18.0 then
                local ldx, ldz = lx - S.px, lz - S.pz
                local ld = math.max(0.1, math.sqrt(ldx * ldx + ldz * ldz))
                dx, dz = ldx / ld, ldz / ld
                local tf = math.max(0.08, (ld - 1.5) / speed)
                vy = 0.5 * 9.81 * tf
                break
            end
        end
    end
    S.shots_fired = S.shots_fired + 1
    eng.audio.play(S.sfx_cannon, S.px, 1.1, S.pz, 0)
    spawn_shell(S.px + dx * 1.5, 1.05, S.pz + dz * 1.5, dx * speed, vy, dz * speed, true)
end

local function ping_radar()
    S.radar_pings = S.radar_pings + 1
    eng.audio.play(S.sfx_ping, S.px, 1.2, S.pz, 0)
    local best_d = 999.0
    S.locked_idx = 0
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local d = eng.math.dist3(S.px, 0, S.pz, en.x, 0, en.z)
            if d < best_d then
                best_d = d
                S.locked_idx = i
                local brg = math.deg(math.atan2(-(en.x - S.px), -(en.z - S.pz)))
                S.radar_bearing = math.floor(wrap_deg(brg - S.hull_yaw) + 0.5)
                S.radar_range = math.floor(d + 0.5)
            end
        end
    end
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.ping_cd = math.max(0.0, S.ping_cd - dt)

    local steer, throttle = eng.input.axis2d("left", "right", "down", "up")
    local overdrive = eng.input.down("jump")
    S.hull_yaw = S.hull_yaw - steer * 92.0 * dt

    -- Turret slews toward radar-locked enemy when jump (target-track) is held, else recenters smoothly
    if S.locked_idx > 0 and S.enemies[S.locked_idx] and S.enemies[S.locked_idx].alive then
        local en = S.enemies[S.locked_idx]
        local desired_world = math.deg(math.atan2(-(en.x - S.px), -(en.z - S.pz)))
        local desired_rel = eng.math.clamp(wrap_deg(desired_world - S.hull_yaw), -75.0, 75.0)
        local slew = overdrive and 160.0 or 75.0
        local diff = wrap_deg(desired_rel - S.turret_rel_yaw)
        S.turret_rel_yaw = S.turret_rel_yaw + eng.math.clamp(diff, -slew * dt, slew * dt)
    else
        S.turret_rel_yaw = S.turret_rel_yaw * math.max(0.0, 1.0 - 3.0 * dt)
    end

    local fx, fz = fwd_from_yaw(S.hull_yaw)
    local spd = (overdrive and 13.5 or 9.0) * throttle
    if math.abs(spd) > 0.01 then
        local nx = eng.math.clamp(S.px + fx * spd * dt, -37.0, 37.0)
        local nz = eng.math.clamp(S.pz + fz * spd * dt, -37.0, 37.0)
        if not blocked_by_obstacle(nx, nz, 1.2) then
            S.px, S.pz = nx, nz
        end
    end
    eng.scene.set_pos(S.player_hull, S.px, 0.45, S.pz)
    eng.scene.set_rot_deg(S.player_hull, 0.0, S.hull_yaw, 0.0)
    eng.scene.set_rot_deg(S.player_tur, 0.0, S.turret_rel_yaw, 0.0)

    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.ping_cd <= 0.0 then
        S.ping_cd = 0.35
        ping_radar()
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
        S.fire_cd = 0.28
        fire_player_shell()
    end

    -- Enemy vector tank AI: strafe around obstacles & lob ballistic shells
    local alive_count = 0
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            alive_count = alive_count + 1
            local to_px, to_pz = S.px - en.x, S.pz - en.z
            local dist = math.sqrt(to_px * to_px + to_pz * to_pz)
            local aim_yaw = math.deg(math.atan2(-to_px, -to_pz))
            en.yaw = aim_yaw

            local sx, sz = math.cos(math.rad(aim_yaw)) * en.strafe_dir, -math.sin(math.rad(aim_yaw)) * en.strafe_dir
            local ex_n = eng.math.clamp(en.x + sx * 3.0 * dt, -36.0, 36.0)
            local ez_n = eng.math.clamp(en.z + sz * 3.0 * dt, -36.0, 36.0)
            if not blocked_by_obstacle(ex_n, ez_n, 1.3) then
                en.vx, en.vz = sx * 3.0, sz * 3.0
                en.x, en.z = ex_n, ez_n
            else
                en.vx, en.vz = 0.0, 0.0
                en.strafe_dir = -en.strafe_dir
            end
            eng.scene.set_pos(en.hull, en.x, 0.45, en.z)
            eng.scene.set_rot_deg(en.hull, 0.0, en.yaw, 0.0)

            en.fire_t = en.fire_t - dt
            if en.fire_t <= 0.0 and dist < 52.0 then
                en.fire_t = 2.6
                local edx, edz = fwd_from_yaw(aim_yaw)
                local espd = 24.0
                local et = math.max(0.1, dist / espd)
                spawn_shell(en.x + edx * 1.5, 1.05, en.z + edz * 1.5, edx * espd, 0.5 * 9.81 * et, edz * espd, false)
            end
        end
    end

    -- Step parabolic shell ballistics
    for i = #S.shells, 1, -1 do
        local sh = S.shells[i]
        sh.life = sh.life - dt
        sh.vy = sh.vy - 9.81 * dt
        sh.x = sh.x + sh.vx * dt
        sh.y = sh.y + sh.vy * dt
        sh.z = sh.z + sh.vz * dt
        eng.scene.set_pos(sh.ent, sh.x, sh.y, sh.z)

        local hit_ob = (sh.y < 1.85) and blocked_by_obstacle(sh.x, sh.z, 0.15)
        local remove_sh = (sh.life <= 0.0 or sh.y <= 0.08 or hit_ob)
        if not remove_sh and sh.from_player then
            for j = 1, #S.enemies do
                local en = S.enemies[j]
                if en.alive and eng.math.dist3(sh.x, sh.y, sh.z, en.x, 0.85, en.z) < 2.35 then
                    remove_sh = true
                    en.hp = en.hp - 1
                    S.flashes[#S.flashes + 1] = { x = en.x, y = 1.5, z = en.z, t = 0.22 }
                    eng.audio.play(S.sfx_boom, en.x, 1.0, en.z, 0)
                    if en.hp <= 0 then
                        en.alive = false
                        eng.scene.despawn(en.barrel)
                        eng.scene.despawn(en.tur)
                        eng.scene.despawn(en.hull)
                        S.kills = S.kills + 1
                        S.score = S.score + 250
                    end
                    break
                end
            end
        elseif not remove_sh and not sh.from_player then
            if eng.math.dist3(sh.x, sh.y, sh.z, S.px, 0.85, S.pz) < 1.65 then
                remove_sh = true
                S.shield = math.max(0, S.shield - 20)
                eng.audio.play(S.sfx_boom, S.px, 1.0, S.pz, 0)
                if S.shield <= 0 then S.lost = true end
            end
        end

        if remove_sh then
            eng.scene.despawn(sh.ent)
            table.remove(S.shells, i)
        end
    end

    for i = #S.flashes, 1, -1 do
        S.flashes[i].t = S.flashes[i].t - dt
        if S.flashes[i].t <= 0.0 then table.remove(S.flashes, i) end
    end

    if alive_count == 0 or S.kills >= #S.enemies then
        S.won = true
        S.score = S.score + S.shield * 5
        eng.save.write("cyber_tank_best", tostring(S.score))
    end

    local vfx, vfz = fwd_from_yaw(S.hull_yaw + S.turret_rel_yaw * 0.5)
    eng.camera.look_at(S.px - vfx * 3.8, 2.4, S.pz - vfz * 3.8, S.px + vfx * 16.0, 1.1, S.pz + vfz * 16.0, 0)
end

function draw()
    for i = 1, #S.flashes do
        local fl = S.flashes[i]
        eng.render.draw_sprite(fl.x, fl.y, fl.z, 1.8, 1.8, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 60, 1280, 720)
    local status = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | KILLS " .. S.kills .. "/4 | RADAR " .. S.radar_bearing .. "d " .. S.radar_range .. "m | SCORE " .. S.score))
    eng.ui.label(x, y, status, 1.0, {0.35, 1.0, 0.55, 1.0})
    eng.ui.bar(x, y + 26, 220, S.shield / 100.0, "SHIELD ")
end
