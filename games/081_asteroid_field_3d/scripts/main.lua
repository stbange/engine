-- 081_asteroid_field_3d: 3D Space Fighter blasting splitting asteroids
local S = game.state

local BOUND = 15.0
local TIER_SCALE  = { 0.72, 1.30, 2.15 }
local TIER_RADIUS = { 0.65, 1.05, 1.65 }
local TIER_SCORE  = { 250, 150, 100 }
local TIER_SPEED  = { 5.4, 3.8, 2.4 }

local function wrap_coord(v)
    if v > BOUND then return v - BOUND * 2.0 end
    if v < -BOUND then return v + BOUND * 2.0 end
    return v
end

local function spawn_rock(tier, x, z, vx, vz)
    local ent = eng.scene.spawn("asteroid_t" .. tostring(tier))
    local s = TIER_SCALE[tier]
    eng.scene.set_pos(ent, x, 0.0, z)
    eng.scene.set_scale(ent, s, s * 0.82, s * 0.94)
    local tint = (tier == 3) and {0.72, 0.66, 0.58, 1.0}
              or (tier == 2 and {0.82, 0.72, 0.55, 1.0} or {0.95, 0.80, 0.52, 1.0})
    eng.scene.set_mesh(ent, S.rock_mesh, { tex = S.rock_tex, color = tint, roughness = 0.88, cast_shadow = true })
    local r = {
        ent = ent, tier = tier, x = x, z = z, vx = vx, vz = vz,
        rx = eng.math.range(0, 360), ry = eng.math.range(0, 360), rz = eng.math.range(0, 360),
         sx = eng.math.range(35, 95), sy = eng.math.range(40, 110), sz = eng.math.range(25, 85),
        alive = true
    }
    S.rocks[#S.rocks + 1] = r
    return r
end

local function spawn_sector()
    S.rocks = {}
    S.bolts = {}
    for i = 1, 3 do
        local ang = (i - 1) * (2.0 * math.pi / 3.0) + eng.math.range(-0.25, 0.25)
        local dist = eng.math.range(8.5, 11.5)
        local x = math.cos(ang) * dist
        local z = math.sin(ang) * dist
        local hdg = ang + 1.35 + eng.math.range(-0.3, 0.3)
        spawn_rock(3, x, z, math.cos(hdg) * TIER_SPEED[3], math.sin(hdg) * TIER_SPEED[3])
    end
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, crt = 0.15, fog_density = 0.008 })
    eng.render.set_sky(0.02, 0.02, 0.06, 0.08, 0.05, 0.16)
    eng.render.add_light({ type = "dir", dir = {-0.45, -1.0, -0.35}, color = {2.1, 2.0, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.0, 0.0}, color = {1.1, 1.5, 2.4}, range = 42.0 })

    local seed_base = math.floor(eng.math.range(100, 90000))
    S.ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.rock_mesh = eng.asset.sphere(0.68, 7, 9)
    S.bolt_mesh = eng.asset.box(0.18, 0.18, 0.85)
    S.frame_mesh = eng.asset.box(1.0, 0.3, 1.0)
    S.rock_tex = eng.procgen.texture("cobble", seed_base, 64)
    S.hull_tex = eng.procgen.texture("sci_fi_panel", seed_base + 7, 64)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_laser = eng.audio.synth("saw", 780, 0.09, 220)
    S.sfx_boom = eng.audio.synth("noise", 240, 0.16, 65)

    -- Neon orbital perimeter buoys so sector bounds are crisp in 3D
    for i = 1, 4 do
        local b = eng.scene.spawn("sector_rail_" .. tostring(i))
        if i <= 2 then
            eng.scene.set_pos(b, 0.0, -0.8, (i == 1) and -BOUND - 0.6 or BOUND + 0.6)
            eng.scene.set_scale(b, BOUND * 2.1, 0.25, 0.25)
        else
            eng.scene.set_pos(b, (i == 3) and -BOUND - 0.6 or BOUND + 0.6, -0.8, 0.0)
            eng.scene.set_scale(b, 0.25, 0.25, BOUND * 2.1)
        end
        eng.scene.set_mesh(b, S.frame_mesh, { color = {0.18, 0.55, 0.95, 1.0} })
    end

    S.ship = eng.scene.spawn("player_starfighter")
    eng.scene.set_pos(S.ship, 0.0, 0.0, 0.0)
    eng.scene.set_scale(S.ship, 0.72, 0.72, 0.72)
    eng.scene.set_mesh(S.ship, S.ship_mesh, { tex = S.hull_tex, color = {0.88, 0.94, 1.0, 1.0}, metallic = 0.45, roughness = 0.35, cast_shadow = true })

    S.px, S.pz = 0.0, 0.0
    S.vx, S.vz = 0.0, 0.0
    S.yaw = 0.0
    S.lives = 3
    S.invuln = 1.5
    S.cooldown = 0.0
    S.score = 0
    S.medium_spawned = 0
    S.small_spawned = 0
    S.rocks_destroyed = 0
    S.won = false

    spawn_sector()
    eng.camera.look_at(0.0, 26.0, 13.5, 0.0, 0.0, 0.0, 0)
    eng.mod.emit("post_init")
end

local function fire_bolt()
    local rad = math.rad(S.yaw)
    local fx, fz = -math.sin(rad), -math.cos(rad)
    local bx, bz = S.px + fx * 1.4, S.pz + fz * 1.4
    local ent = eng.scene.spawn("plasma_bolt")
    eng.scene.set_pos(ent, bx, 0.0, bz)
    eng.scene.set_rot_deg(ent, 0.0, S.yaw, 0.0)
    eng.scene.set_mesh(ent, S.bolt_mesh, { color = {0.35, 1.0, 0.85, 1.0} })
    S.bolts[#S.bolts + 1] = { ent = ent, x = bx, z = bz, vx = fx * 30.0 + S.vx * 0.25, vz = fz * 30.0 + S.vz * 0.25, ttl = 0.95, alive = true }
    eng.audio.play(S.sfx_laser, bx, 0.0, bz, 0)
end

local function split_or_destroy_rock(r, hit_vx, hit_vz)
    r.alive = false
    eng.scene.despawn(r.ent)
    S.rocks_destroyed = S.rocks_destroyed + 1
    S.score = S.score + TIER_SCORE[r.tier]
    eng.audio.play(S.sfx_boom, r.x, 0.0, r.z, 0)

    if r.tier > 1 then
        local nt = r.tier - 1
        local len = math.sqrt(hit_vx * hit_vx + hit_vz * hit_vz)
        local nx, nz = 1.0, 0.0
        if len > 0.001 then nx, nz = -hit_vz / len, hit_vx / len end
        local spd = TIER_SPEED[nt]
        for side = -1, 1, 2 do
            local cvx = nx * side * spd + r.vx * 0.35
            local cvz = nz * side * spd + r.vz * 0.35
            spawn_rock(nt, wrap_coord(r.x + nx * side * 0.65), wrap_coord(r.z + nz * side * 0.65), cvx, cvz)
            if nt == 2 then S.medium_spawned = S.medium_spawned + 1 else S.small_spawned = S.small_spawned + 1 end
        end
    end
end

local function wrapped_dist(x1, z1, x2, z2)
    local dx = wrap_coord(x1 - x2)
    local dz = wrap_coord(z1 - z2)
    return math.sqrt(dx * dx + dz * dz)
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)
    S.invuln = math.max(0.0, S.invuln - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.yaw = S.yaw - mx * 240.0 * dt
    local rad = math.rad(S.yaw)
    local fx, fz = -math.sin(rad), -math.cos(rad)

    if math.abs(my) > 0.01 then
        S.vx = S.vx + fx * my * 18.0 * dt
        S.vz = S.vz + fz * my * 18.0 * dt
    end
    local drag = math.max(0.0, 1.0 - 0.95 * dt)
    S.vx, S.vz = S.vx * drag, S.vz * drag
    local spd = math.sqrt(S.vx * S.vx + S.vz * S.vz)
    if spd > 13.0 then S.vx = (S.vx / spd) * 13.0; S.vz = (S.vz / spd) * 13.0 end

    S.px = wrap_coord(S.px + S.vx * dt)
    S.pz = wrap_coord(S.pz + S.vz * dt)
    eng.scene.set_pos(S.ship, S.px, 0.0, S.pz)
    eng.scene.set_rot_deg(S.ship, my * -6.0, S.yaw, mx * -24.0)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        S.cooldown = 0.09
        fire_bolt()
    end

    -- Step plasma bolts
    for i = #S.bolts, 1, -1 do
        local b = S.bolts[i]
        b.ttl = b.ttl - dt
        b.x = wrap_coord(b.x + b.vx * dt)
        b.z = wrap_coord(b.z + b.vz * dt)
        eng.scene.set_pos(b.ent, b.x, 0.0, b.z)
        if b.ttl <= 0.0 then
            eng.scene.despawn(b.ent)
            table.remove(S.bolts, i)
        end
    end

    -- Step tumbling rocks & check collisions
    local living = 0
    for i = 1, #S.rocks do
        local r = S.rocks[i]
        if r.alive then
            r.x = wrap_coord(r.x + r.vx * dt)
            r.z = wrap_coord(r.z + r.vz * dt)
            r.rx = r.rx + r.sx * dt
            r.ry = r.ry + r.sy * dt
            r.rz = r.rz + r.sz * dt
            eng.scene.set_pos(r.ent, r.x, 0.0, r.z)
            eng.scene.set_rot_deg(r.ent, r.rx, r.ry, r.rz)

            local hit_bolt = nil
            local hit_idx = 0
            local rad_hit = TIER_RADIUS[r.tier] + 0.55
            for bi = #S.bolts, 1, -1 do
                local b = S.bolts[bi]
                if wrapped_dist(b.x, b.z, r.x, r.z) <= rad_hit then
                    hit_bolt = b
                    hit_idx = bi
                    break
                end
            end

            if hit_bolt then
                local hvx, hvz = hit_bolt.vx, hit_bolt.vz
                eng.scene.despawn(hit_bolt.ent)
                table.remove(S.bolts, hit_idx)
                split_or_destroy_rock(r, hvx, hvz)
            else
                living = living + 1
                if S.invuln <= 0.0 and eng.math.dist3(S.px, 0, S.pz, r.x, 0, r.z) < (TIER_RADIUS[r.tier] + 0.85) then
                    S.lives = math.max(1, S.lives - 1)
                    S.invuln = 1.6
                    S.vx, S.vz = -r.vx * 0.8, -r.vz * 0.8
                    eng.audio.play(S.sfx_boom, S.px, 0.0, S.pz, 0)
                end
            end
        end
    end

    if living == 0 then
        S.won = true
        S.score = S.score + 500
    end

    eng.camera.look_at(S.px * 0.15, 26.0, 13.5 + S.pz * 0.15, S.px * 0.25, 0.0, S.pz * 0.25, 0)
end

function draw()
    for i = 1, #S.bolts do
        local b = S.bolts[i]
        eng.render.draw_sprite(b.x, 0.25, b.z, 0.55, 0.55, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | ROCKS DESTROYED " .. S.rocks_destroyed .. " | SCORE " .. S.score, 1.0, {0.65, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 180, S.lives / 3.0, "SHIELD ")
end
