-- 015_sniper_watchtower: Watchtower ballistics with crosswind drift, bullet drop & procedural NPCs
local S = game.state

local EYE_X, EYE_Y, EYE_Z = 0.0, 9.6, 15.5
local MUZZLE_VEL = 80.0

local function ray_from_angles(yaw_deg, pitch_deg)
    local yr, pr = math.rad(yaw_deg), math.rad(pitch_deg)
    local cp = math.cos(pr)
    return -math.sin(yr) * cp, math.sin(pr), -math.cos(yr) * cp
end

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.012 })
    eng.render.set_sky(0.14, 0.24, 0.42, 0.55, 0.48, 0.36)
    eng.render.add_light({ type = "dir", dir = {-0.4, -1.0, -0.3}, color = {2.1, 1.95, 1.75}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, 6.0}, color = {2.2, 1.5, 0.8}, range = 32.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.bullet_mesh = eng.asset.sphere(0.14, 6, 8)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    local grass_tex = eng.procgen.texture("grass", S.seed, 64)
    local wood_tex = eng.procgen.texture("wood_planks", S.seed + 3, 64)
    local tree_mesh = eng.procgen.tree(S.seed + 9, 2, 3.8, 0.24)

    S.sfx_rifle = eng.audio.synth("noise", 360, 0.14, 65)
    S.sfx_spot = eng.audio.synth("sine", 740, 0.09, 1080)
    S.sfx_hit = eng.audio.synth("triangle", 480, 0.12, 220)

    local floor_e = eng.scene.spawn("valley_ground")
    eng.scene.set_pos(floor_e, 0.0, -0.25, -4.0)
    eng.scene.set_scale(floor_e, 68.0, 0.5, 68.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = grass_tex, roughness = 0.9 })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {34.0, 0.25, 34.0} })

    -- Watchtower deck & Compound Gate
    local deck_e = eng.scene.spawn("watchtower_deck")
    eng.scene.set_pos(deck_e, 0.0, 8.0, 15.5)
    eng.scene.set_scale(deck_e, 4.0, 0.4, 4.0)
    eng.scene.set_mesh(deck_e, S.box_mesh, { tex = wood_tex })

    local gate_e = eng.scene.spawn("compound_gate")
    eng.scene.set_pos(gate_e, 0.0, 0.0, 6.0)
    eng.scene.set_scale(gate_e, 1.8, 1.4, 1.4)
    eng.scene.set_mesh(gate_e, S.arch_mesh, { color = {0.72, 0.68, 0.62, 1.0}, cast_shadow = true })

    -- Perimeter L-system trees along outer flanks (leaving central sightlines clear)
    local pts = eng.procgen.scatter_poisson(S.seed, 54.0, 40.0, 8.0, 18)
    for i = 1, #pts do
        local tx, tz = pts[i][1] - 27.0, pts[i][2] - 28.0
        if math.abs(tx) > 13.5 then
            local te = eng.scene.spawn("valley_pine_" .. tostring(i))
            eng.scene.set_pos(te, tx, 0.0, tz)
            eng.scene.set_mesh(te, tree_mesh, { cast_shadow = true })
        end
    end

    -- Deterministic crosswind acceleration (m/s^2)
    S.wind_ax = ((S.seed % 2 == 0) and 1.0 or -1.0) * 4.5
    S.yaw = 0.0
    S.pitch = -16.0
    S.sway_t = 0.0
    S.bolt_cd = 0.0
    S.spot_cd = 0.0
    S.gate_hp = 100
    S.score = 0
    S.kills = 0
    S.shots_fired = 0
    S.spotter_scans = 0
    S.friendly_hits = 0
    S.won = false
    S.lost = false
    S.bullets = {}
    S.npcs = {}

    -- 5 Hostile Saboteur Infiltrators (procedural rigged humanoids advancing on compound gate)
    local inf_lanes = { -9.5, -4.8, 0.0, 4.8, 9.5 }
    for i = 1, 5 do
        local nx = inf_lanes[i]
        local nz = -18.0 - (i - 1) * 2.8
        local ne = eng.scene.spawn("infiltrator_" .. tostring(i))
        eng.scene.set_pos(ne, nx, 0.0, nz)
        local pinfo = eng.procgen.person(ne, S.seed + i * 29)
        S.npcs[#S.npcs + 1] = {
            ent = ne, x = nx, z = nz, vx = 0.0, vz = 1.45,
            hostile = true, alive = true, height = pinfo.height or 1.75
        }
    end

    -- 2 Friendly Compound Sentries patrolling laterally near outer walls
    for i = 1, 2 do
        local sx = (i == 1) and -12.0 or 12.0
        local sz = 3.5
        local se = eng.scene.spawn("sentry_" .. tostring(i))
        eng.scene.set_pos(se, sx, 0.0, sz)
        local pinfo = eng.procgen.person(se, S.seed + 200 + i * 17)
        S.npcs[#S.npcs + 1] = {
            ent = se, x = sx, z = sz, vx = (i == 1) and 1.2 or -1.2, vz = 0.0,
            hostile = false, alive = true, height = pinfo.height or 1.75
        }
    end

    local dx, dy, dz = ray_from_angles(S.yaw, S.pitch)
    eng.camera.look_at(EYE_X, EYE_Y, EYE_Z, EYE_X + dx * 25.0, EYE_Y + dy * 25.0, EYE_Z + dz * 25.0, 0)
    eng.mod.emit("post_init")
end

local function fire_sniper_round(eff_yaw, eff_pitch)
    local dx, dy, dz = ray_from_angles(eff_yaw, eff_pitch)
    S.shots_fired = S.shots_fired + 1
    eng.audio.play(S.sfx_rifle, EYE_X, EYE_Y, EYE_Z, 0)
    local be = eng.scene.spawn("sniper_round")
    eng.scene.set_pos(be, EYE_X + dx * 0.8, EYE_Y + dy * 0.8, EYE_Z + dz * 0.8)
    eng.scene.set_mesh(be, S.bullet_mesh, { color = {1.0, 0.92, 0.35, 1.0} })
    S.bullets[#S.bullets + 1] = {
        ent = be,
        x = EYE_X + dx * 0.8, y = EYE_Y + dy * 0.8, z = EYE_Z + dz * 0.8,
        vx = dx * MUZZLE_VEL, vy = dy * MUZZLE_VEL, vz = dz * MUZZLE_VEL,
        life = 1.4
    }
end

function update(dt)
    if S.won or S.lost then return end
    S.bolt_cd = math.max(0.0, S.bolt_cd - dt)
    S.spot_cd = math.max(0.0, S.spot_cd - dt)
    S.sway_t = S.sway_t + dt

    local steady = eng.input.down("jump")
    eng.input.set_mouse_lock(true)
    local mdx, mdy = eng.input.mouse_delta()
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local pan_spd = steady and 18.0 or 44.0
    local msens = steady and 0.09 or 0.18
    S.yaw = eng.math.clamp(S.yaw - mx * pan_spd * dt - mdx * msens, -42.0, 42.0)
    S.pitch = eng.math.clamp(S.pitch + my * pan_spd * dt - mdy * msens, -36.0, -3.0)

    local sway_yaw = steady and 0.0 or (math.sin(S.sway_t * 2.6) * 0.65)
    local sway_pitch = steady and 0.0 or (math.cos(S.sway_t * 3.4) * 0.45)
    local eff_yaw = S.yaw + sway_yaw
    local eff_pitch = S.pitch + sway_pitch

    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.spot_cd <= 0.0 then
        S.spot_cd = 0.6
        S.spotter_scans = S.spotter_scans + 1
        eng.audio.play(S.sfx_spot, EYE_X, EYE_Y, EYE_Z, 0)
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.bolt_cd <= 0.0 then
        S.bolt_cd = 0.36
        fire_sniper_round(eff_yaw, eff_pitch)
    end

    -- Step NPCs
    local hostiles_alive = 0
    for i = 1, #S.npcs do
        local npc = S.npcs[i]
        if npc.alive then
            npc.x = npc.x + npc.vx * dt
            npc.z = npc.z + npc.vz * dt
            if not npc.hostile then
                if math.abs(npc.x) > 13.5 or math.abs(npc.x) < 8.5 then npc.vx = -npc.vx end
            else
                hostiles_alive = hostiles_alive + 1
                if npc.z >= 5.8 then
                    npc.alive = false
                    eng.scene.despawn(npc.ent)
                    hostiles_alive = hostiles_alive - 1
                    S.gate_hp = math.max(0, S.gate_hp - 40)
                    if S.gate_hp <= 0 then S.lost = true end
                end
            end
            if npc.alive then
                eng.scene.set_pos(npc.ent, npc.x, 0.0, npc.z)
                eng.scene.set_rot_deg(npc.ent, 0.0, math.deg(math.atan2(-npc.vx, -npc.vz)), 0.0)
            end
        end
    end

    -- Sub-step ballistic bullets with gravity drop + crosswind deflection
    for i = #S.bullets, 1, -1 do
        local b = S.bullets[i]
        b.life = b.life - dt
        local dead = (b.life <= 0.0)
        local sub_dt = dt * 0.25
        for _ = 1, 4 do
            if dead then break end
            b.vx = b.vx + S.wind_ax * sub_dt
            b.vy = b.vy - 9.81 * sub_dt
            b.x = b.x + b.vx * sub_dt
            b.y = b.y + b.vy * sub_dt
            b.z = b.z + b.vz * sub_dt
            if b.y <= 0.0 then dead = true; break end
            for j = 1, #S.npcs do
                local npc = S.npcs[j]
                if npc.alive then
                    local dx, dz = b.x - npc.x, b.z - npc.z
                    if (dx * dx + dz * dz) < 0.72 and b.y >= 0.1 and b.y <= (npc.height + 0.35) then
                        dead = true
                        npc.alive = false
                        eng.scene.despawn(npc.ent)
                        eng.audio.play(S.sfx_hit, npc.x, 1.2, npc.z, 0)
                        if npc.hostile then
                            S.kills = S.kills + 1
                            S.score = S.score + 300
                        else
                            S.friendly_hits = S.friendly_hits + 1
                            S.gate_hp = math.max(0, S.gate_hp - 50)
                            if S.gate_hp <= 0 then S.lost = true end
                        end
                        break
                    end
                end
            end
        end
        if dead then
            eng.scene.despawn(b.ent)
            table.remove(S.bullets, i)
        else
            eng.scene.set_pos(b.ent, b.x, b.y, b.z)
        end
    end

    if S.kills >= 5 and not S.lost then
        S.won = true
        S.score = S.score + S.gate_hp * 4
        eng.save.write("sniper_watch_clear", tostring(S.score))
    end

    local dx, dy, dz = ray_from_angles(eff_yaw, eff_pitch)
    eng.camera.look_at(EYE_X, EYE_Y, EYE_Z, EYE_X + dx * 25.0, EYE_Y + dy * 25.0, EYE_Z + dz * 25.0, 0)
end

function draw()
    -- Spotter tags over hostile infiltrators + 3D reticle marker along line of sight
    for i = 1, #S.npcs do
        local npc = S.npcs[i]
        if npc.alive and npc.hostile then
            eng.render.draw_sprite(npc.x, npc.height + 0.55, npc.z, 0.55, 0.55, S.orb_tex)
        end
    end
    local dx, dy, dz = ray_from_angles(S.yaw, S.pitch)
    eng.render.draw_sprite(EYE_X + dx * 12.0, EYE_Y + dy * 12.0, EYE_Z + dz * 12.0, 0.28, 0.28, S.orb_tex)

    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 60, 1280, 720)
    local wind_dir = (S.wind_ax > 0) and ">>" or "<<"
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | TARGETS " .. S.kills .. "/5 | WIND " .. string.format("%+.1f", S.wind_ax) .. wind_dir .. " | SCORE " .. S.score))
    eng.ui.label(x, y, msg, 1.0, {0.95, 0.92, 0.65, 1.0})
    eng.ui.bar(x, y + 26, 220, S.gate_hp / 100.0, "GATE ")
end
