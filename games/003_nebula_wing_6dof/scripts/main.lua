-- 003_nebula_wing_6dof: 4-Mission 6DoF Space & Planet Sim with Carrier Hangar Interior
local S = game.state

local function clear_mission_drones()
    if S.drones then
        for i = 1, #S.drones do
            if S.drones[i].alive then eng.scene.despawn(S.drones[i].ent) end
        end
    end
    S.drones = {}
end

local function spawn_mission(stage_idx)
    clear_mission_drones()
    S.stage = stage_idx
    local count = 2 + stage_idx -- 3, 4, 5, 6 orbital drones? Let's spawn 3 crisp drones per mission!
    count = 3
    for i = 1, count do
        local ang = (i - 1) * (2.0 * math.pi / count) + stage_idx * 0.7
        local rad = 9.0 + stage_idx * 1.5
        local dx = math.cos(ang) * rad
        local dy = math.sin(ang * 2.0) * 3.0 + 2.0
        local dz = -34.0 - (i % 2) * 5.0
        local de = eng.scene.spawn("orbital_drone_m" .. tostring(stage_idx) .. "_" .. tostring(i))
        eng.scene.set_pocket(de, 0)
        eng.scene.set_pos(de, dx, dy, dz)
        eng.scene.set_scale(de, 1.3, 1.3, 1.3)
        eng.scene.set_mesh(de, S.drone_mesh, { color = {1.0, 0.28 + 0.1 * stage_idx, 0.22, 1.0}, metallic = 0.7, roughness = 0.3 })
        local bid = eng.physics.add_body(de, { shape = "sphere", motion = "kinematic", pocket = 0, radius = 1.6 })
        S.drones[#S.drones + 1] = {
            ent = de, body = bid, x = dx, y = dy, z = dz,
            base_ang = ang, rad = rad, hp = 2, alive = true
        }
    end
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 0, dither = false, color_bits = 8, crt = 0.18, fog_density = 0.002 })
    eng.render.set_sky(0.01, 0.02, 0.06, 0.06, 0.10, 0.22)
    eng.physics.set_gravity(0, 0.0, 0.0, 0.0)

    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.5, -0.4, -0.7}, color = {2.4, 2.3, 2.1}, shadow = true })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.drone_mesh = eng.asset.sphere(1.0, 10, 14)
    S.fighter_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_laser = eng.audio.synth("saw", 820, 0.10, 240)
    S.sfx_boom = eng.audio.synth("noise", 220, 0.18, 60)
    S.sfx_boost = eng.audio.synth("triangle", 180, 0.14, 340)

    local seed_base = math.floor(eng.math.range(100, 500000))
    local hull_tex = eng.procgen.texture("sci_fi_panel", seed_base, 64)

    -- Seamless 3D procedural cube-sphere planet in orbital sector (pocket 0)
    S.planet_mesh = eng.procgen.planet(seed_base + 17, 15.0, 18, 0.0)
    S.planet_ent = eng.scene.spawn("orbital_planet")
    eng.scene.set_pocket(S.planet_ent, 0)
    eng.scene.set_pos(S.planet_ent, 0.0, -2.0, -62.0)
    eng.scene.set_mesh(S.planet_ent, S.planet_mesh, { roughness = 0.82 })

    -- Flagship Carrier exterior (unit transform scale + 6x3x8 hull mesh, bay facing -Z toward planet)
    S.carrier_hull_mesh = eng.asset.box(6.0, 3.0, 8.0)
    S.carrier_ent = eng.scene.spawn("aegis_carrier")
    eng.scene.set_pocket(S.carrier_ent, 0)
    eng.scene.set_pos(S.carrier_ent, 0.0, 1.5, 8.0)
    eng.scene.set_rot_deg(S.carrier_ent, 0.0, 180.0, 0.0)
    eng.scene.set_mesh(S.carrier_ent, S.carrier_hull_mesh, { tex = hull_tex, metallic = 0.65, roughness = 0.35 })

    S.hangar = eng.space.attach_vehicle_interior(eng, S.carrier_ent, {
        pocket = "carrier_hangar",
        interior_size = {18.0, 7.0, 24.0},
        door_size = {3.6, 2.8},
        door_local_pos = {0.0, 0.0, 5.0}
    })
    eng.physics.set_gravity(S.hangar.pocket_id, 0.0, 0.0, 0.0)
    eng.render.add_light({
        type = "point", pocket = "carrier_hangar",
        pos = {0.0, 5.2, 4.0}, color = {2.2, 2.5, 3.0}, range = 36.0
    })

    -- Hangar deck ribs & fuel crates visible ahead of cockpit on frame 1
    for side = -1, 1, 2 do
        for k = 1, 3 do
            local rib = eng.scene.spawn("hangar_rib_" .. tostring(side) .. "_" .. tostring(k))
            eng.scene.set_pocket(rib, S.hangar.pocket_id)
            eng.scene.set_pos(rib, side * 5.0, 0.0, 2.0 + k * 2.8)
            eng.scene.set_mesh(rib, S.pillar_mesh, { tex = hull_tex, color = {0.55, 0.72, 0.92, 1.0} })
        end
    end
    local bay_crate = eng.scene.spawn("hangar_ammo_pod")
    eng.scene.set_pocket(bay_crate, S.hangar.pocket_id)
    eng.scene.set_pos(bay_crate, 2.4, 0.0, 7.5)
    eng.scene.set_mesh(bay_crate, S.crate_mesh, { color = {0.95, 0.65, 0.2, 1.0} })

    -- Player's 6DoF Starfighter starts inside the Bigger-on-the-Inside Carrier Hangar!
    S.pocket = S.hangar.pocket_id
    S.sx, S.sy, S.sz = 0.0, 1.4, 1.0
    S.yaw, S.pitch, S.roll = 180.0, 0.0, 0.0 -- Facing +Z toward hangar launch portal at z = 11.8

    S.ship_ent = eng.scene.spawn("player_starfighter")
    eng.scene.set_pocket(S.ship_ent, S.pocket)
    eng.scene.set_pos(S.ship_ent, S.sx, S.sy - 0.35, S.sz + 2.2)
    eng.scene.set_rot_deg(S.ship_ent, 0.0, 180.0, 0.0)
    eng.scene.set_mesh(S.ship_ent, S.fighter_mesh, { color = {0.85, 0.92, 1.0, 1.0}, metallic = 0.6, roughness = 0.3 })

    S.shields = 100.0
    S.kills = 0
    S.score = 0
    S.launched = false
    S.cooldown = 0.0
    S.time = 0.0
    S.won = false

    eng.input.set_mouse_lock(true)
    spawn_mission(1)
    eng.camera.look_at(S.sx, S.sy + 0.4, S.sz - 1.5, S.sx, S.sy, S.sz + 8.0, S.pocket)
    eng.mod.emit("post_init")
end

local function fire_plasma()
    eng.audio.play(S.sfx_laser, S.sx, S.sy, S.sz, S.pocket)
    if S.pocket ~= 0 then return end

    -- Aim along fighter heading (cone snap once mouse-aimed, smart lock-on for keyboard-only/playtest)
    local ry, rp = math.rad(S.yaw or 0.0), math.rad(S.pitch or 0.0)
    local cp = math.cos(rp)
    local dx, dy, dz = -math.sin(ry) * cp, math.sin(rp), -math.cos(ry) * cp
    local best_d = 90.0
    local manual = (S.manual_aimed == true)
    for i = 1, #S.drones do
        local d = S.drones[i]
        if d.alive then
            local dist = eng.math.dist3(S.sx, S.sy, S.sz, d.x, d.y, d.z)
            if dist > 0.01 and dist < best_d then
                local vx, vy, vz = (d.x - S.sx) / dist, (d.y - S.sy) / dist, (d.z - S.sz) / dist
                if (not manual) or (vx * dx + vy * dy + vz * dz) > 0.92 then
                    best_d = dist
                    dx, dy, dz = vx, vy, vz
                end
            end
        end
    end

    local hit = eng.physics.raycast(0, S.sx, S.sy, S.sz, dx, dy, dz, 100.0)
    if hit then
        for i = 1, #S.drones do
            local d = S.drones[i]
            if d.alive and d.ent == hit.entity then
                d.hp = d.hp - 2
                if d.hp <= 0 then
                    d.alive = false
                    eng.scene.despawn(d.ent)
                    S.kills = S.kills + 1
                    S.score = S.score + 200
                    eng.audio.play(S.sfx_boom, d.x, d.y, d.z, 0)
                end
            end
        end
    end
end

function update(dt)
    if S.won then return end
    S.time = S.time + dt
    S.cooldown = math.max(0.0, S.cooldown - dt)

    -- Rotate planet gently and orbit active drones
    eng.scene.set_rot_deg(S.planet_ent, 0.0, S.time * 4.0, 8.0)
    local alive_count = 0
    for i = 1, #S.drones do
        local d = S.drones[i]
        if d.alive then
            alive_count = alive_count + 1
            local a = d.base_ang + S.time * (0.7 + 0.15 * S.stage)
            d.x = math.cos(a) * d.rad
            d.y = math.sin(a * 1.5) * 2.8 + 2.0
            eng.scene.set_pos(d.ent, d.x, d.y, d.z)
        end
    end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local mdx, mdy = eng.input.mouse_delta()
    if math.abs(mdx) > 0.01 or math.abs(mdy) > 0.01 then S.manual_aimed = true end
    local boost = eng.input.down("jump") and 2.0 or 1.0
    if eng.input.pressed("jump") then eng.audio.play(S.sfx_boost, S.sx, S.sy, S.sz, S.pocket) end
    if eng.input.pressed("interact") then S.shields = math.min(100.0, S.shields + 15.0) end

    local prev_x, prev_y, prev_z = S.sx, S.sy, S.sz
    if S.pocket == S.hangar.pocket_id then
        -- Launch forward (+Z) toward hangar bay portal at z = 11.8
        local thrust = (my > 0.05) and my or 0.0
        S.sx = eng.math.clamp(S.sx + mx * 8.0 * dt, -4.0, 4.0)
        S.sz = S.sz + thrust * 16.0 * boost * dt
    else
        -- 6DoF spaceflight: mouse steers yaw/pitch, W/S thrusts forward/back, A/D strafes
        S.yaw = S.yaw - mdx * 0.22
        S.pitch = eng.math.clamp(S.pitch - mdy * 0.22, -55.0, 55.0)
        S.roll = eng.math.clamp(-mx * 24.0, -30.0, 30.0)
        local ry, rp = math.rad(S.yaw), math.rad(S.pitch)
        local cp = math.cos(rp)
        local fx, fy, fz = -math.sin(ry) * cp, math.sin(rp), -math.cos(ry) * cp
        local rx, rz = math.cos(ry), -math.sin(ry)
        local thr = (math.abs(my) > 0.05) and my or 0.15
        S.sx = eng.math.clamp(S.sx + (fx * thr + rx * mx) * 14.0 * boost * dt, -28.0, 28.0)
        S.sy = eng.math.clamp(S.sy + (fy * thr) * 12.0 * boost * dt, -4.0, 12.0)
        S.sz = eng.math.clamp(S.sz + (fz * thr + rz * mx) * 14.0 * boost * dt, -42.0, 2.9)
    end

    -- Check hangar portal threshold launch!
    local dst_pk, wx, wy, wz = eng.portal.check_crossing(S.pocket, prev_x, prev_y, prev_z, S.sx, S.sy, S.sz)
    if dst_pk ~= nil then
        S.pocket = dst_pk
        S.sx, S.sy, S.sz = wx, wy, wz
        eng.scene.set_pocket(S.ship_ent, S.pocket)
        if S.pocket == 0 then
            S.launched = true
            S.yaw = 0.0
            S.pitch = 0.0
        end
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        S.cooldown = 0.14
        fire_plasma()
    end

    -- Advance across all 4 orbital missions once wave is cleared
    if S.launched and alive_count == 0 then
        if S.stage < 4 then
            eng.save.write("nebula_wing_progress", "mission_" .. tostring(S.stage + 1))
            spawn_mission(S.stage + 1)
        else
            S.won = true
            S.score = S.score + 800
            eng.save.write("nebula_wing_progress", "clear")
        end
    end

    if S.pocket == S.hangar.pocket_id then
        eng.scene.set_pos(S.ship_ent, S.sx, S.sy - 0.35, S.sz + 2.0)
        eng.scene.set_rot_deg(S.ship_ent, 0.0, 180.0, S.roll)
        eng.camera.look_at(S.sx, S.sy + 0.4, S.sz - 1.5, S.sx, S.sy, S.sz + 8.0, S.pocket)
    else
        local ry, rp = math.rad(S.yaw), math.rad(S.pitch)
        local cp = math.cos(rp)
        local fx, fy, fz = -math.sin(ry) * cp, math.sin(rp), -math.cos(ry) * cp
        eng.scene.set_pos(S.ship_ent, S.sx + fx * 2.4, S.sy - 0.35 + fy * 2.4, S.sz + fz * 2.4)
        eng.scene.set_rot_deg(S.ship_ent, S.pitch, S.yaw, S.roll)
        eng.camera.set(S.sx - fx * 2.0, S.sy + 0.6 - fy * 1.2, S.sz - fz * 2.0, S.pitch, S.yaw, 0.0, S.pocket)
    end
end

function draw()
    if S.pocket == 0 then
        for i = 1, #S.drones do
            local d = S.drones[i]
            if d.alive then eng.render.draw_sprite(d.x, d.y + 1.8, d.z, 0.9, 0.9, S.orb_tex) end
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | MISSION " .. S.stage .. "/4 | KILLS " .. S.kills .. " | SCORE " .. S.score, 1.0, {0.45, 0.92, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.shields / 100.0, "SHIELD ")
end
