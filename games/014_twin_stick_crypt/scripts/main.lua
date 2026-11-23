-- 014_twin_stick_crypt: Top-down 3D procedural BSP crypt arena blasting swarmers & grabbing powerups
local S = game.state

local function spawn_swarmer(idx, x, z)
    local e = eng.scene.spawn("crypt_swarmer_" .. tostring(idx))
    eng.scene.set_pos(e, x, 0.0, z)
    eng.procgen.animal(e, S.seed + idx * 19, "insectoid")
    eng.scene.set_scale(e, 0.9, 0.9, 0.9)
    return { ent = e, x = x, z = z, hp = 2, alive = true, is_obelisk = false }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.018 })
    eng.render.set_sky(0.05, 0.03, 0.09, 0.16, 0.08, 0.22)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.3}, color = {1.7, 1.55, 2.0}, shadow = true })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.bolt_mesh = eng.asset.sphere(0.20, 6, 8)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_bolt = eng.audio.synth("square", 540, 0.06, 280)
    S.sfx_power = eng.audio.synth("triangle", 440, 0.18, 980)
    S.sfx_nova = eng.audio.synth("saw", 320, 0.20, 95)

    local d = eng.procgen.dungeon(18, 18, S.seed, "bsp", 2.0, 2.2)
    S.solvable = d.solvable
    local brick_tex = eng.procgen.texture("stone_brick", S.seed, 64)

    local crypt_e = eng.scene.spawn("bsp_crypt")
    eng.scene.set_mesh(crypt_e, d.mesh_id, { tex = brick_tex, roughness = 0.85 })

    local floor_e = eng.scene.spawn("crypt_floor")
    eng.scene.set_pos(floor_e, 18.0, -0.25, 18.0)
    eng.scene.set_scale(floor_e, 40.0, 0.5, 40.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = brick_tex, color = {0.42, 0.38, 0.52, 1.0} })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {20.0, 0.25, 20.0} })
    eng.ai.set_grid(0, 2.0, 18, 18)

    S.px, S.pz = d.start_x, d.start_z
    S.ex, S.ez = d.exit_x, d.exit_z
    eng.render.add_light({ type = "point", pos = {S.px, 7.0, S.pz}, color = {2.4, 1.8, 1.1}, range = 36.0 })

    S.hunter_ent = eng.scene.spawn("crypt_hunter")
    eng.scene.set_pos(S.hunter_ent, S.px, 0.0, S.pz)
    eng.procgen.person(S.hunter_ent, S.seed + 5)

    S.hp = 100
    S.score = 0
    S.kills = 0
    S.weapon_lvl = 1
    S.powerups_grabbed = 0
    S.novas_cast = 0
    S.aim_yaw = 0.0
    S.fire_cd = 0.0
    S.dash_cd = 0.0
    S.nova_cd = 0.0
    S.won = false
    S.lost = false
    S.bolts = {}
    S.powerups = {}
    S.targets = {}

    -- Spawn 2 weapon powerup crystals along the BSP route
    for i = 1, 2 do
        local t = i * 0.32
        local ux = S.px + (S.ex - S.px) * t
        local uz = S.pz + (S.ez - S.pz) * t
        local pe = eng.scene.spawn("crypt_powerup_" .. tostring(i))
        eng.scene.set_pos(pe, ux, 0.35, uz)
        eng.scene.set_mesh(pe, (i == 1) and S.crystal_mesh or S.chest_mesh, { color = {0.3, 1.0, 0.65, 1.0} })
        S.powerups[i] = { ent = pe, x = ux, z = uz, taken = false }
    end

    -- Spawn 2 Spawner Obelisks + 6 Crypt Swarmers
    local ob_coords = {
        { S.px + (S.ex - S.px) * 0.55, S.pz + (S.ez - S.pz) * 0.55 },
        { S.ex, S.ez }
    }
    for i = 1, 2 do
        local oe = eng.scene.spawn("crypt_obelisk_" .. tostring(i))
        eng.scene.set_pos(oe, ob_coords[i][1], 0.0, ob_coords[i][2])
        eng.scene.set_mesh(oe, S.arch_mesh, { color = {0.9, 0.25, 0.95, 1.0}, cast_shadow = true })
        S.targets[#S.targets + 1] = { ent = oe, x = ob_coords[i][1], z = ob_coords[i][2], hp = 4, alive = true, is_obelisk = true }
    end

    for i = 1, 6 do
        local t = 0.25 + i * 0.11
        local sx = eng.math.clamp(S.px + (S.ex - S.px) * t + ((i % 2 == 0) and 2.2 or -2.2), 2.5, 33.5)
        local sz = eng.math.clamp(S.pz + (S.ez - S.pz) * t, 2.5, 33.5)
        S.targets[#S.targets + 1] = spawn_swarmer(i, sx, sz)
    end

    eng.camera.look_at(S.px, 15.0, S.pz + 9.0, S.px, 0.5, S.pz, 0)
    eng.mod.emit("post_init")
end

local function fire_twin_stick()
    local dx, dz = 0.0, -1.0
    local best_d = 999.0
    for i = 1, #S.targets do
        local tg = S.targets[i]
        if tg.alive then
            local d = eng.math.dist3(S.px, 0, S.pz, tg.x, 0, tg.z)
            if d < best_d then
                best_d = d
                dx, dz = tg.x - S.px, tg.z - S.pz
            end
        end
    end
    local base_ang = math.atan2(dx, dz)
    S.aim_yaw = math.deg(math.atan2(-dx, -dz))
    eng.audio.play(S.sfx_bolt, S.px, 1.0, S.pz, 0)

    local count = math.min(3, S.weapon_lvl)
    for k = 1, count do
        local spread = (k - (count + 1) * 0.5) * 0.14
        local a = base_ang + spread
        local vx, vz = math.sin(a) * 34.0, math.cos(a) * 34.0
        local be = eng.scene.spawn("crypt_bolt")
        eng.scene.set_pos(be, S.px, 0.9, S.pz)
        eng.scene.set_mesh(be, S.bolt_mesh, { color = {0.4, 1.0, 0.85, 1.0} })
        S.bolts[#S.bolts + 1] = { ent = be, x = S.px, z = S.pz, vx = vx, vz = vz, life = 0.9 }
    end
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.dash_cd = math.max(0.0, S.dash_cd - dt)
    S.nova_cd = math.max(0.0, S.nova_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local spd = 9.5
    if eng.input.pressed("jump") and S.dash_cd <= 0.0 then
        S.dash_cd = 0.75
        spd = 26.0
    end
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.px = eng.math.clamp(S.px + mx * spd * dt, 2.0, 34.0)
        S.pz = eng.math.clamp(S.pz - my * spd * dt, 2.0, 34.0)
        S.aim_yaw = math.deg(math.atan2(-mx, my))
    end

    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.nova_cd <= 0.0 then
        S.nova_cd = 1.8
        S.novas_cast = S.novas_cast + 1
        eng.audio.play(S.sfx_nova, S.px, 1.0, S.pz, 0)
        for i = 1, #S.targets do
            local tg = S.targets[i]
            if tg.alive and eng.math.dist3(S.px, 0, S.pz, tg.x, 0, tg.z) < 5.0 then
                tg.hp = tg.hp - 2
                if tg.hp <= 0 then
                    tg.alive = false
                    eng.scene.despawn(tg.ent)
                    S.kills = S.kills + 1
                    S.score = S.score + 150
                end
            end
        end
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
        S.fire_cd = (S.weapon_lvl >= 3) and 0.11 or 0.16
        fire_twin_stick()
    end

    eng.scene.set_pos(S.hunter_ent, S.px, 0.0, S.pz)
    eng.scene.set_rot_deg(S.hunter_ent, 0.0, S.aim_yaw, 0.0)

    -- Powerup pickups
    for i = 1, #S.powerups do
        local pu = S.powerups[i]
        if not pu.taken then
            eng.scene.set_rot_deg(pu.ent, 0.0, S.kills * 35.0 + i * 90.0, 0.0)
            if eng.math.dist3(S.px, 0, S.pz, pu.x, 0, pu.z) < 2.2 then
                pu.taken = true
                S.powerups_grabbed = S.powerups_grabbed + 1
                S.weapon_lvl = S.weapon_lvl + 1
                S.hp = math.min(100, S.hp + 20)
                S.score = S.score + 200
                eng.audio.play(S.sfx_power, pu.x, 0.8, pu.z, 0)
                eng.scene.despawn(pu.ent)
            end
        end
    end

    -- Step bolts
    for i = #S.bolts, 1, -1 do
        local b = S.bolts[i]
        b.life = b.life - dt
        b.x = b.x + b.vx * dt
        b.z = b.z + b.vz * dt
        eng.scene.set_pos(b.ent, b.x, 0.9, b.z)
        local dead = (b.life <= 0.0)
        if not dead then
            for j = 1, #S.targets do
                local tg = S.targets[j]
                if tg.alive and eng.math.dist3(b.x, 0, b.z, tg.x, 0, tg.z) < 1.65 then
                    dead = true
                    tg.hp = tg.hp - 1
                    if tg.hp <= 0 then
                        tg.alive = false
                        eng.scene.despawn(tg.ent)
                        S.kills = S.kills + 1
                        S.score = S.score + (tg.is_obelisk and 300 or 120)
                    end
                    break
                end
            end
        end
        if dead then
            eng.scene.despawn(b.ent)
            table.remove(S.bolts, i)
        end
    end

    -- Step A* swarmers
    local remaining = 0
    for i = 1, #S.targets do
        local tg = S.targets[i]
        if tg.alive then
            remaining = remaining + 1
            if not tg.is_obelisk then
                local path = eng.ai.find_path(0, tg.x, 0.0, tg.z, 0, S.px, 0.0, S.pz)
                local tx, tz = S.px, S.pz
                if path and #path >= 2 then tx, tz = path[2][1], path[2][3] end
                local vx, vz = tx - tg.x, tz - tg.z
                local vl = math.sqrt(vx * vx + vz * vz)
                if vl > 0.35 then
                    tg.x = tg.x + (vx / vl) * 3.6 * dt
                    tg.z = tg.z + (vz / vl) * 3.6 * dt
                    eng.scene.set_pos(tg.ent, tg.x, 0.0, tg.z)
                    eng.scene.set_rot_deg(tg.ent, 0.0, math.deg(math.atan2(-vx, -vz)), 0.0)
                else
                    S.hp = math.max(0, S.hp - 18.0 * dt)
                    if S.hp <= 0 then S.lost = true end
                end
            end
        end
    end

    if remaining == 0 and S.powerups_grabbed >= 1 and not S.lost then
        S.won = true
        S.score = S.score + 500
        eng.save.write("twin_crypt_best", tostring(S.score))
    end

    eng.camera.look_at(S.px, 15.0, S.pz + 9.0, S.px, 0.5, S.pz, 0)
end

function draw()
    for i = 1, #S.targets do
        local tg = S.targets[i]
        if tg.alive then
            eng.render.draw_sprite(tg.x, tg.is_obelisk and 3.1 or 1.4, tg.z, 0.7, 0.7, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 60, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | LVL " .. S.weapon_lvl .. " | KILLS " .. S.kills .. "/8 | SCORE " .. S.score))
    eng.ui.label(x, y, msg, 1.0, {0.55, 1.0, 0.85, 1.0})
    eng.ui.bar(x, y + 26, 220, S.hp / 100.0, "HP ")
end
