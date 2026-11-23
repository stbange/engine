-- 073_air_hockey_neon: High-Speed 3D Neon Air-Hockey Mallet vs Reactive AI Defender (First to 5 Goals)
local S = game.state

local function spawn_rail(name, x, y, z, sx, sy, sz, color, rest)
    local e = eng.scene.spawn(name)
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_scale(e, sx, sy, sz)
    eng.scene.set_mesh(e, S.box_mesh, { color = color, cast_shadow = true })
    eng.physics.add_body(e, { shape = "aabb", motion = "static", half_extents = {sx * 0.5, sy * 0.5, sz * 0.5}, restitution = rest or 0.96 })
    return e
end

local function serve_puck(toward_player)
    eng.scene.set_pos(S.puck_ent, 0.0, 0.14, toward_player and 1.5 or -1.5)
    eng.physics.set_vel(S.puck_body, 0.0, 0.0, 0.0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.02, 0.03, 0.08, 0.08, 0.12, 0.24)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {1.5, 1.6, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.0, 0.0}, color = {0.8, 2.0, 2.6}, range = 20.0 })

    -- Near-frictionless air-cushion table
    eng.physics.set_gravity(0, 0.0, -0.35, 0.0)

    local seed = math.floor(eng.math.range(10, 40000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.puck_mesh = eng.asset.cylinder(0.28, 0.28, 0.12, 18)
    S.mallet_mesh = eng.asset.cylinder(0.40, 0.34, 0.26, 18)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.rink_tex = eng.procgen.texture("sci_fi_panel", seed, 64)

    S.sfx_hit = eng.audio.synth("triangle", 480, 0.06, 760)
    S.sfx_wall = eng.audio.synth("square", 320, 0.05, 420)
    S.sfx_goal = eng.audio.synth("saw", 380, 0.22, 880)

    -- Rink floor (5.6m x 10.0m, z in [-5, +5]) + center red line
    local rink = eng.scene.spawn("air_rink")
    eng.scene.set_pos(rink, 0.0, -0.25, 0.0)
    eng.scene.set_scale(rink, 5.6, 0.5, 10.0)
    eng.scene.set_mesh(rink, S.box_mesh, { tex = S.rink_tex, color = {0.10, 0.16, 0.28, 1.0}, roughness = 0.15 })
    eng.physics.add_body(rink, { shape = "aabb", motion = "static", half_extents = {2.8, 0.25, 5.0}, restitution = 0.0 })

    local cline = eng.scene.spawn("center_line")
    eng.scene.set_pos(cline, 0.0, 0.02, 0.0)
    eng.scene.set_scale(cline, 5.4, 0.03, 0.10)
    eng.scene.set_mesh(cline, S.box_mesh, { color = {1.0, 0.25, 0.55, 1.0} })

    -- Side rails & split goal end-walls (goal mouth x in [-1.55, +1.55] open!)
    spawn_rail("rail_l", -2.95, 0.22, 0.0, 0.30, 0.45, 10.4, {0.20, 0.90, 1.0, 1.0}, 0.96)
    spawn_rail("rail_r",  2.95, 0.22, 0.0, 0.30, 0.45, 10.4, {0.20, 0.90, 1.0, 1.0}, 0.96)
    spawn_rail("top_l",  -2.20, 0.22, -5.05, 1.30, 0.45, 0.30, {1.0, 0.25, 0.65, 1.0}, 0.96)
    spawn_rail("top_r",   2.20, 0.22, -5.05, 1.30, 0.45, 0.30, {1.0, 0.25, 0.65, 1.0}, 0.96)
    spawn_rail("bot_l",  -2.20, 0.22,  5.05, 1.30, 0.45, 0.30, {0.25, 1.0, 0.65, 1.0}, 0.96)
    spawn_rail("bot_r",   2.20, 0.22,  5.05, 1.30, 0.45, 0.30, {0.25, 1.0, 0.65, 1.0}, 0.96)

    -- Dynamic Neon Puck
    S.puck_ent = eng.scene.spawn("neon_puck")
    eng.scene.set_pos(S.puck_ent, 0.0, 0.14, 1.5)
    eng.scene.set_mesh(S.puck_ent, S.puck_mesh, { color = {1.0, 0.95, 0.25, 1.0}, cast_shadow = true })
    S.puck_body = eng.physics.add_body(S.puck_ent, { shape = "sphere", motion = "dynamic", radius = 0.28, restitution = 0.96 })

    -- Player & AI Mallets
    S.px, S.pz = 0.0, 3.6
    S.ax, S.az = -0.9, -2.8
    S.pm_ent = eng.scene.spawn("player_mallet")
    eng.scene.set_pos(S.pm_ent, S.px, 0.15, S.pz)
    eng.scene.set_mesh(S.pm_ent, S.mallet_mesh, { color = {0.20, 1.0, 0.65, 1.0}, cast_shadow = true })

    S.am_ent = eng.scene.spawn("ai_mallet")
    eng.scene.set_pos(S.am_ent, S.ax, 0.15, S.az)
    eng.scene.set_mesh(S.am_ent, S.mallet_mesh, { color = {1.0, 0.25, 0.55, 1.0}, cast_shadow = true })

    S.player_goals = 0
    S.ai_goals = 0
    S.mallet_hits = 0
    S.won = false

    eng.camera.look_at(0.0, 6.8, 8.2, 0.0, 0.0, -0.6, 0)
    eng.mod.emit("post_init")
end

local function collide_mallet(mx, mz, mvx, mvz)
    local kx, ky, kz = eng.scene.get_pos(S.puck_ent)
    local dx, dz = kx - mx, kz - mz
    local d = math.sqrt(dx * dx + dz * dz)
    local min_d = 0.68
    if d < min_d then
        local nx, nz = 0.0, -1.0
        if d > 0.001 then nx, nz = dx / d, dz / d end
        kx = mx + nx * (min_d + 0.02)
        kz = mz + nz * (min_d + 0.02)
        eng.scene.set_pos(S.puck_ent, kx, 0.14, kz)

        local vx, _, vz = eng.physics.get_vel(S.puck_body)
        local rvx, rvz = vx - mvx, vz - mvz
        local vn = rvx * nx + rvz * nz
        if vn < 0.0 then
            vx = vx - 1.92 * vn * nx + mvx * 0.45
            vz = vz - 1.92 * vn * nz + mvz * 0.45
        else
            vx = mvx * 1.25 + nx * 7.5
            vz = mvz * 1.25 + nz * 7.5
        end
        local spd = math.sqrt(vx * vx + vz * vz)
        if spd > 24.0 then vx, vz = (vx / spd) * 24.0, (vz / spd) * 24.0 end
        eng.physics.set_vel(S.puck_body, vx, 0.0, vz)
        S.mallet_hits = S.mallet_hits + 1
        eng.audio.play(S.sfx_hit, kx, ky, kz, 0)
    end
end

function update(dt)
    if S.won then return end

    -- Player mallet control in lower rink [0.45, 4.55]
    local ix, iy = eng.input.axis2d("left", "right", "down", "up")
    local prev_px, prev_pz = S.px, S.pz
    S.px = eng.math.clamp(S.px + ix * 9.0 * dt, -2.35, 2.35)
    S.pz = eng.math.clamp(S.pz - iy * 17.5 * dt, 0.45, 4.55)
    local pvx, pvz = (S.px - prev_px) / dt, (S.pz - prev_pz) / dt
    eng.scene.set_pos(S.pm_ent, S.px, 0.15, S.pz)

    -- Reactive AI defender in upper rink [-4.45, -0.45]
    local kx, _, kz = eng.scene.get_pos(S.puck_ent)
    local vx, _, vz = eng.physics.get_vel(S.puck_body)
    local prev_ax, prev_az = S.ax, S.az
    local tgt_x = eng.math.clamp(kx, -2.0, 2.0)
    local tgt_z = (kz < -0.15 and vz > -5.0) and math.min(-0.45, kz + 0.25) or -3.0
    local dax, daz = tgt_x - S.ax, tgt_z - S.az
    local max_ai = 2.8 * dt
    S.ax = eng.math.clamp(S.ax + eng.math.clamp(dax, -max_ai, max_ai), -2.35, 2.35)
    S.az = eng.math.clamp(S.az + eng.math.clamp(daz, -max_ai, max_ai), -4.45, -0.45)
    local avx, avz = (S.ax - prev_ax) / dt, (S.az - prev_az) / dt
    eng.scene.set_pos(S.am_ent, S.ax, 0.15, S.az)

    collide_mallet(S.px, S.pz, pvx, pvz)
    collide_mallet(S.ax, S.az, avx, avz)

    -- Goal detection at z < -4.85 (AI goal) and z > 4.85 (Player goal)
    kx, _, kz = eng.scene.get_pos(S.puck_ent)
    if kz < -4.85 and math.abs(kx) < 1.56 then
        S.player_goals = S.player_goals + 1
        eng.audio.play(S.sfx_goal, kx, 0.2, kz, 0)
        if S.player_goals >= 5 then
            S.won = true
            eng.save.write("air_hockey_champ", "5")
            return
        end
        S.px, S.pz = 0.0, 3.6
        S.ax, S.az = (S.player_goals % 2 == 1) and 0.95 or -0.95, -2.8
        eng.scene.set_pos(S.pm_ent, S.px, 0.15, S.pz)
        eng.scene.set_pos(S.am_ent, S.ax, 0.15, S.az)
        serve_puck(true)
    elseif kz > 4.85 and math.abs(kx) < 1.56 then
        S.ai_goals = S.ai_goals + 1
        eng.audio.play(S.sfx_wall, kx, 0.2, kz, 0)
        serve_puck(true)
    elseif math.abs(kx) > 3.2 or math.abs(kz) > 5.6 then
        serve_puck(true)
    end
end

function draw()
    local kx, _, kz = eng.scene.get_pos(S.puck_ent)
    eng.render.draw_sprite(kx, 0.35, kz, 0.45, 0.45, S.orb_tex)
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | YOU " .. S.player_goals .. " - " .. S.ai_goals .. " AI (FIRST TO 5)", 1.0, {0.35, 1.0, 0.85, 1.0})
end
