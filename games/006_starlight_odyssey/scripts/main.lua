-- 006_starlight_odyssey: 3-World Spherical Planetoid Collectathon + Bigger-on-the-Inside Toyhouse
local S = game.state

local PLANET_R = 10.0

local function sphere_pos(lat, lon, alt)
    local r = PLANET_R + (alt or 0.0)
    local cl = math.cos(lat)
    return r * cl * math.sin(lon), r * math.sin(lat), r * cl * math.cos(lon)
end

local function clear_world_entities()
    if S.w_ents then
        for i = 1, #S.w_ents do eng.scene.despawn(S.w_ents[i]) end
    end
    S.w_ents = {}
    S.shards = {}
end

local function build_world(w_idx)
    clear_world_entities()
    S.stage = w_idx
    local seed_base = math.floor(eng.math.range(500, 900000)) + w_idx * 433

    -- Spherical mini-planetoid + radial gravity
    local pmesh = eng.procgen.planet(seed_base, PLANET_R, 18, 0.0)
    local pent = eng.scene.spawn("planetoid_w" .. tostring(w_idx))
    eng.scene.set_pocket(pent, 0)
    eng.scene.set_pos(pent, 0.0, 0.0, 0.0)
    eng.scene.set_mesh(pent, pmesh, { roughness = 0.82 })
    eng.physics.set_planet_gravity(0, 0.0, 0.0, 0.0, 9.81, seed_base, PLANET_R)
    S.w_ents[#S.w_ents + 1] = pent

    -- 3 surface Star Shards placed around spherical latitudes/longitudes
    local shard_angles = {
        { 0.35,  0.9 },
        { -0.25, 2.3 },
        { 0.20, -1.4 }
    }
    for i = 1, 3 do
        local lat, lon = shard_angles[i][1], shard_angles[i][2] + w_idx * 0.4
        local sx, sy, sz = sphere_pos(lat, lon, 1.3)
        local se = eng.scene.spawn("star_shard_" .. tostring(i))
        eng.scene.set_pocket(se, 0)
        eng.scene.set_pos(se, sx, sy, sz)
        eng.scene.set_mesh(se, S.crystal_mesh, { color = {1.0, 0.92, 0.25, 1.0}, roughness = 0.2 })
        S.w_ents[#S.w_ents + 1] = se
        S.shards[#S.shards + 1] = { ent = se, pocket = 0, x = sx, y = sy, z = sz, lat = lat, lon = lon, active = true }
    end

    -- 1 Bonus Grand Star Shard inside the Bigger-on-the-Inside Toyhouse pocket!
    local be = eng.scene.spawn("toyhouse_bonus_shard")
    eng.scene.set_pocket(be, S.toyhouse.pocket_id)
    eng.scene.set_pos(be, 0.0, 0.8, 0.0)
    eng.scene.set_scale(be, 1.3, 1.3, 1.3)
    eng.scene.set_mesh(be, S.crystal_mesh, { color = {1.0, 0.45, 0.95, 1.0}, roughness = 0.15 })
    S.w_ents[#S.w_ents + 1] = be
    S.shards[#S.shards + 1] = { ent = be, pocket = S.toyhouse.pocket_id, x = 0.0, y = 0.8, z = 0.0, active = true }

    -- Planetoid Boss Guardian at South-Equatorial Crater (vulnerable once >= 3 shards collected)
    local bx, by, bz = sphere_pos(-0.15, 3.14, 1.4)
    local boss_e = eng.scene.spawn("planet_boss_w" .. tostring(w_idx))
    eng.scene.set_pocket(boss_e, 0)
    eng.scene.set_pos(boss_e, bx, by, bz)
    eng.scene.set_scale(boss_e, 1.5, 1.5, 1.5)
    eng.procgen.animal(boss_e, seed_base + 77, "biped")
    local bid = eng.physics.add_body(boss_e, { shape = "sphere", motion = "kinematic", pocket = 0, radius = 1.6 })
    S.w_ents[#S.w_ents + 1] = boss_e
    S.boss = { ent = boss_e, body = bid, x = bx, y = by, z = bz, lat = -0.15, lon = 3.14, hp = 2, alive = true }

    S.stage_shards = 0
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 320, dither = true, color_bits = 6, fog_density = 0.006 })
    eng.render.set_sky(0.05, 0.06, 0.18, 0.22, 0.16, 0.38)
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.45, -0.9, -0.35}, color = {2.3, 2.2, 2.0}, shadow = true })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_star = eng.audio.synth("triangle", 580, 0.18, 1080)
    S.sfx_spin = eng.audio.synth("square", 360, 0.12, 620)
    S.sfx_boss = eng.audio.synth("noise", 280, 0.20, 90)

    -- Bigger-on-the-Inside Toyhouse Bonus Room perched on the North Pole of the planetoid!
    -- Exterior 3.2m cube -> Interior 20x8x22m whimsical bonus hall!
    S.toyhouse = eng.space.create_pocket_building(eng, {
        exterior_pos = {0.0, PLANET_R + 0.5, 0.0},
        exterior_size = {3.2, 3.0, 3.2},
        interior_size = {20.0, 8.0, 22.0},
        door_size = {1.4, 2.2},
        pocket = "toyhouse_bonus",
        exterior_color = {0.95, 0.38, 0.52, 1.0},
        interior_color = {0.42, 0.34, 0.68, 1.0}
    })
    eng.physics.set_gravity(S.toyhouse.pocket_id, 0.0, -9.81, 0.0)
    eng.render.add_light({
        type = "point", pocket = "toyhouse_bonus",
        pos = {0.0, 5.5, 0.0}, color = {2.8, 2.4, 2.9}, range = 34.0
    })

    local toy_chest = eng.scene.spawn("toyhouse_treasure")
    eng.scene.set_pocket(toy_chest, S.toyhouse.pocket_id)
    eng.scene.set_pos(toy_chest, 0.0, 0.0, -4.0)
    eng.scene.set_scale(toy_chest, 1.5, 1.5, 1.5)
    eng.scene.set_mesh(toy_chest, S.chest_mesh, { color = {1.0, 0.82, 0.22, 1.0} })

    S.hero_ent = eng.scene.spawn("star_explorer")
    eng.procgen.person(S.hero_ent, 2026)

    S.pocket = 0
    S.lat, S.lon = 1.15, 0.0
    S.jump_alt, S.jump_vel = 0.0, 0.0
    S.px, S.py, S.pz = sphere_pos(S.lat, S.lon, 1.2)
    eng.scene.set_pos(S.hero_ent, S.px, S.py, S.pz)

    S.hp = 100
    S.total_shards = 0
    S.bonus_rooms_visited = 0
    S.bosses_defeated = 0
    S.won = false

    build_world(1)
    eng.camera.look_at(0.0, PLANET_R + 7.5, 12.0, 0.0, PLANET_R + 1.0, 0.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local prev_x, prev_y, prev_z = S.px, S.py, S.pz

    if eng.input.pressed("jump") and S.jump_alt <= 0.05 then
        S.jump_vel = 6.5
    end
    S.jump_alt = S.jump_alt + S.jump_vel * dt
    if S.jump_alt > 0.0 then
        S.jump_vel = S.jump_vel - 16.0 * dt
    else
        S.jump_alt = 0.0
        S.jump_vel = 0.0
    end

    if S.pocket == 0 then
        -- Walk along spherical mini-planetoid surface (or near North Pole Toyhouse plaza)
        if S.north_plaza_mode then
            S.px = S.px + mx * 7.5 * dt
            S.pz = S.pz - my * 7.5 * dt
            S.py = PLANET_R + 1.5 + S.jump_alt
        else
            S.lon = S.lon + mx * 2.2 * dt
            S.lat = eng.math.clamp(S.lat + my * 1.8 * dt, -1.35, 1.45)
            S.px, S.py, S.pz = sphere_pos(S.lat, S.lon, 1.2 + S.jump_alt)
        end
    else
        -- Inside the flat Euclidean Bigger-on-the-Inside Toyhouse Bonus Room!
        S.px = eng.math.clamp(S.px + mx * 8.5 * dt, -8.5, 8.5)
        S.pz = eng.math.clamp(S.pz - my * 8.5 * dt, -9.5, 11.6)
        S.py = 1.1 + S.jump_alt
    end

    -- Seamless portal crossing into & out of North Pole Toyhouse (`door_ext` at (0, PLANET_R+1.6, 1.6))
    local dst_pk, wx, wy, wz = eng.portal.check_crossing(S.pocket, prev_x, prev_y, prev_z, S.px, S.py, S.pz)
    if dst_pk ~= nil then
        S.pocket = dst_pk
        S.px, S.py, S.pz = wx, wy, wz
        eng.scene.set_pocket(S.hero_ent, S.pocket)
        if S.pocket == S.toyhouse.pocket_id then
            S.bonus_rooms_visited = S.bonus_rooms_visited + 1
        else
            S.north_plaza_mode = false
            S.lat, S.lon = 1.15, 0.0
        end
    end

    eng.scene.set_pos(S.hero_ent, S.px, S.py, S.pz)

    -- Collect Star Shards in active pocket
    for i = 1, #S.shards do
        local sh = S.shards[i]
        if sh.active and sh.pocket == S.pocket and eng.math.dist3(S.px, S.py, S.pz, sh.x, sh.y, sh.z) < 2.6 then
            sh.active = false
            eng.scene.despawn(sh.ent)
            S.stage_shards = S.stage_shards + 1
            S.total_shards = S.total_shards + 1
            eng.audio.play(S.sfx_star, sh.x, sh.y, sh.z, S.pocket)
        end
    end

    -- Star-Spin Attack against Planetoid Boss Guardian
    if (eng.input.pressed("fire") or eng.input.pressed("interact")) and S.pocket == 0 and S.boss and S.boss.alive then
        eng.audio.play(S.sfx_spin, S.px, S.py, S.pz, 0)
        if S.stage_shards >= 3 then
            local d = eng.math.dist3(S.px, S.py, S.pz, S.boss.x, S.boss.y, S.boss.z)
            local hit_boss = (d < 4.5)
            if not hit_boss and d < 18.0 and d > 0.01 then
                local h = eng.physics.raycast(0, S.px, S.py, S.pz,
                    (S.boss.x - S.px) / d, (S.boss.y - S.py) / d, (S.boss.z - S.pz) / d, 20.0)
                if h and h.entity == S.boss.ent then hit_boss = true end
            end
            if hit_boss then
                S.boss.hp = S.boss.hp - 2
                if S.boss.hp <= 0 then
                    S.boss.alive = false
                    eng.scene.despawn(S.boss.ent)
                    S.bosses_defeated = S.bosses_defeated + 1
                    eng.audio.play(S.sfx_boss, S.boss.x, S.boss.y, S.boss.z, 0)
                    if S.stage < 3 then
                        eng.save.write("starlight_odyssey_progress", "world_" .. tostring(S.stage + 1))
                        build_world(S.stage + 1)
                        return
                    else
                        S.won = true
                        eng.save.write("starlight_odyssey_progress", "clear")
                        return
                    end
                end
            end
        end
    end

    if S.pocket == S.toyhouse.pocket_id then
        eng.camera.look_at(S.px, S.py + 3.0, S.pz + 5.5, S.px, S.py + 0.5, S.pz - 2.0, S.pocket)
    else
        -- Radial orbital follow camera above spherical planetoid
        local len = math.max(0.1, math.sqrt(S.px * S.px + S.py * S.py + S.pz * S.pz))
        local ux, uy, uz = S.px / len, S.py / len, S.pz / len
        eng.camera.look_at(S.px + ux * 7.0, S.py + uy * 7.0 + 3.0, S.pz + uz * 7.0 + 6.0, S.px, S.py, S.pz, 0)
    end
end

function draw()
    for i = 1, #S.shards do
        local sh = S.shards[i]
        if sh.active and sh.pocket == S.pocket then
            eng.render.draw_sprite(sh.x, sh.y + 1.2, sh.z, 0.7, 0.7, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | WORLD " .. S.stage .. "/3 | STARS " .. S.total_shards, 1.0, {1.0, 0.92, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 200, math.min(1.0, S.stage_shards / 3.0), "SHARDS ")
end
