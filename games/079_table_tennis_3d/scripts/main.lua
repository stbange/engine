-- 079_table_tennis_3d: 6DoF Ping-Pong Rally Physics with Magnus Topspin Dip & Slice Bounce vs Agile AI
local S = game.state

local TABLE_Y = 0.76
local HALF_W = 1.10
local HALF_L = 1.92

local function serve_rally(to_player)
    S.bx = 0.0
    S.by = 1.06
    S.bz = to_player and -1.2 or 1.2
    S.bvx = (S.player_pts % 2 == 0) and 0.45 or -0.45
    S.bvy = 0.85
    S.bvz = to_player and 7.6 or -7.6
    S.spin = 1.5
    S.last_hitter = to_player and "ai" or "player"
    S.bounced_target = false
    eng.scene.set_pos(S.ball_ent, S.bx, S.by, S.bz)
end

function init()
    eng.xr.set_mode("6dof")
    eng.render.set_sky(0.08, 0.12, 0.22, 0.24, 0.30, 0.42)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {2.0, 1.95, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 3.4, 0.0}, color = {1.8, 1.9, 2.2}, range = 14.0 })

    local seed = math.floor(eng.math.range(10, 40000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ball_mesh = eng.asset.sphere(0.065, 12, 16)
    S.paddle_mesh = eng.asset.cylinder(0.18, 0.18, 0.04, 16)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.floor_tex = eng.procgen.texture("wood_planks", seed, 64)

    S.sfx_pong = eng.audio.synth("triangle", 580, 0.04, 420)
    S.sfx_bounce = eng.audio.synth("square", 720, 0.03, 640)
    S.sfx_point = eng.audio.synth("sine", 480, 0.16, 920)

    -- Gym hardwood floor & pedestal
    local gym = eng.scene.spawn("gym_floor")
    eng.scene.set_pos(gym, 0.0, -0.25, 0.0)
    eng.scene.set_scale(gym, 12.0, 0.5, 14.0)
    eng.scene.set_mesh(gym, S.box_mesh, { tex = S.floor_tex, roughness = 0.35 })
    eng.physics.add_body(gym, { shape = "aabb", motion = "static", half_extents = {6.0, 0.25, 7.0} })

    local ped = eng.scene.spawn("table_pedestal")
    eng.scene.set_pos(ped, 0.0, 0.35, 0.0)
    eng.scene.set_scale(ped, 1.2, 0.70, 2.2)
    eng.scene.set_mesh(ped, S.box_mesh, { color = {0.20, 0.22, 0.26, 1.0} })

    -- Regulation-proportioned Royal Blue Table Top (y = 0.76) + White Center Line + Taut Net
    local tbl = eng.scene.spawn("pingpong_table")
    eng.scene.set_pos(tbl, 0.0, TABLE_Y - 0.04, 0.0)
    eng.scene.set_scale(tbl, HALF_W * 2.0, 0.08, HALF_L * 2.0)
    eng.scene.set_mesh(tbl, S.box_mesh, { color = {0.12, 0.36, 0.78, 1.0}, roughness = 0.28, cast_shadow = true })

    local line = eng.scene.spawn("center_stripe")
    eng.scene.set_pos(line, 0.0, TABLE_Y + 0.008, 0.0)
    eng.scene.set_scale(line, 0.04, 0.02, HALF_L * 1.98)
    eng.scene.set_mesh(line, S.box_mesh, { color = {0.96, 0.96, 0.98, 1.0} })

    local net = eng.scene.spawn("table_net")
    eng.scene.set_pos(net, 0.0, TABLE_Y + 0.09, 0.0)
    eng.scene.set_scale(net, HALF_W * 2.08, 0.18, 0.03)
    eng.scene.set_mesh(net, S.box_mesh, { color = {0.90, 0.92, 0.96, 1.0}, cast_shadow = true })

    -- Player Red Paddle & AI Black Paddle (rotated upright facing +/-Z)
    S.px, S.py, S.pz = 0.0, 1.02, 1.86
    S.ax, S.ay, S.az = 0.0, 1.02, -1.86

    S.pp_ent = eng.scene.spawn("player_paddle")
    eng.scene.set_pos(S.pp_ent, S.px, S.py, S.pz)
    eng.scene.set_rot_deg(S.pp_ent, 90.0, 0.0, 0.0)
    eng.scene.set_mesh(S.pp_ent, S.paddle_mesh, { color = {0.92, 0.18, 0.20, 1.0}, cast_shadow = true })

    S.ap_ent = eng.scene.spawn("ai_paddle")
    eng.scene.set_pos(S.ap_ent, S.ax, S.ay, S.az)
    eng.scene.set_rot_deg(S.ap_ent, 90.0, 0.0, 0.0)
    eng.scene.set_mesh(S.ap_ent, S.paddle_mesh, { color = {0.16, 0.18, 0.22, 1.0}, cast_shadow = true })

    -- 3D Ping-Pong Ball
    S.ball_ent = eng.scene.spawn("pingpong_ball")
    eng.scene.set_mesh(S.ball_ent, S.ball_mesh, { color = {1.0, 0.62, 0.12, 1.0}, cast_shadow = true })

    S.player_pts = 0
    S.ai_pts = 0
    S.rallies = 0
    S.topspin_hits = 0
    S.slice_hits = 0
    S.rally_exchange = 0
    S.won = false

    serve_rally(true)
    eng.camera.look_at(0.0, 1.95, 3.35, 0.0, 0.85, -0.5, 0)
    eng.mod.emit("post_init")
end

local function award_point(player_won)
    if player_won then
        S.player_pts = S.player_pts + 1
        eng.audio.play(S.sfx_point, 0.0, 1.0, 0.0, 0)
        if S.player_pts >= 5 then
            S.won = true
            eng.save.write("pingpong_match", "5-" .. tostring(S.ai_pts))
            return
        end
    else
        S.ai_pts = S.ai_pts + 1
    end
    S.rally_exchange = 0
    serve_rally(true)
end

function update(dt)
    if S.won then return end

    -- 6DoF / Gamepad Paddle Positioning
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.px = eng.math.clamp(S.px + mx * 5.6 * dt, -1.35, 1.35)
    S.py = eng.math.clamp(S.py + my * 2.5 * dt, 0.84, 1.35)
    eng.scene.set_pos(S.pp_ent, S.px, S.py, S.pz)

    -- Agile AI Paddle tracking ball x & height
    local ai_spd = 2.0 * dt
    S.ax = eng.math.clamp(S.ax + eng.math.clamp(S.bx - S.ax, -ai_spd, ai_spd), -1.25, 1.25)
    S.ay = eng.math.clamp(S.by, 0.86, 1.30)
    eng.scene.set_pos(S.ap_ent, S.ax, S.ay, S.az)

    -- Aerodynamic Magnus spin acceleration (topspin > 0 dips sharply; slice < 0 floats!)
    local prev_z = S.bz
    local magnus_ay = -S.spin * 1.85
    S.bvy = S.bvy + (-9.81 + magnus_ay) * dt
    S.bx = S.bx + S.bvx * dt
    S.by = S.by + S.bvy * dt
    S.bz = S.bz + S.bvz * dt

    -- Net cord collision at z = 0
    if (prev_z > 0.0 and S.bz <= 0.0) or (prev_z < 0.0 and S.bz >= 0.0) then
        if S.by < TABLE_Y + 0.18 and math.abs(S.bx) <= HALF_W * 1.04 then
            award_point(S.last_hitter == "ai")
            return
        end
    end

    -- Table bounce with topspin kick / backspin slice check!
    if S.by <= TABLE_Y + 0.065 and S.bvy < 0.0 and math.abs(S.bx) <= HALF_W + 0.04 and math.abs(S.bz) <= HALF_L + 0.04 then
        S.by = TABLE_Y + 0.065
        local rest = (S.spin > 2.0) and 0.78 or 0.90
        S.bvy = math.abs(S.bvy) * rest
        -- Spin friction kick along flight direction
        local dir_z = (S.bvz >= 0.0) and 1.0 or -1.0
        S.bvz = S.bvz + dir_z * S.spin * 0.32
        if (S.last_hitter == "player" and S.bz < 0.0) or (S.last_hitter == "ai" and S.bz > 0.0) then
            S.bounced_target = true
        end
        eng.audio.play(S.sfx_bounce, S.bx, S.by, S.bz, 0)
    end

    -- Player paddle strike zone near z = +1.86
    if S.bvz > 0.0 and S.bz >= 1.55 and S.bz <= 2.05 then
        if math.abs(S.bx - S.px) < 0.36 and math.abs(S.by - S.py) < 0.34 then
            local use_slice = eng.input.down("interact") or eng.input.pressed("interact")
            local use_top = eng.input.down("fire") or eng.input.pressed("fire") or (not use_slice)
            S.last_hitter = "player"
            S.bounced_target = false
            S.rallies = S.rallies + 1
            S.rally_exchange = S.rally_exchange + 1

            -- Cross-court angled placement based on paddle offset / input
            local aim_corner = (S.ax >= 0.0) and -0.96 or 0.96
            local target_x = (S.rally_exchange >= 2) and aim_corner or (mx * 0.15)
            S.by = eng.math.clamp(S.by, 0.95, 1.06)
            if use_slice then
                S.spin = -2.0
                S.slice_hits = S.slice_hits + 1
                S.bvz = -7.0
                S.bvy = 0.75 - (S.by - 1.00) * 2.0
            elseif use_top then
                S.spin = 5.5
                S.topspin_hits = S.topspin_hits + 1
                S.bvz = -10.8
                S.bvy = 1.85 - (S.by - 0.98) * 3.5
            end
            S.bvx = (target_x - S.bx) / (3.1 / math.abs(S.bvz))
            S.bz = 1.54
            eng.audio.play(S.sfx_pong, S.px, S.py, S.pz, 0)
        end
    end

    -- AI paddle return zone near z = -1.86
    if S.bvz < 0.0 and S.bz <= -1.55 and S.bz >= -2.05 then
        if math.abs(S.bx - S.ax) < 0.34 and math.abs(S.by - S.ay) < 0.34 then
            S.last_hitter = "ai"
            S.bounced_target = false
            S.rallies = S.rallies + 1
            S.by = eng.math.clamp(S.by, 0.93, 1.04)
            S.spin = 2.0
            S.bvz = 8.4
            S.bvy = 1.65 - (S.by - 0.96) * 3.0
            S.bvx = (-S.bx * 0.35) / (3.1 / 8.4)
            S.bz = -1.54
            eng.audio.play(S.sfx_pong, S.ax, S.ay, S.az, 0)
        end
    end

    -- Out / missed ball point resolution
    if S.bz < -2.45 or S.bz > 2.45 or S.by < 0.25 then
        if S.last_hitter == "player" then
            award_point(S.bounced_target == true)
        else
            award_point(S.bounced_target == false)
        end
        return
    end

    eng.scene.set_pos(S.ball_ent, S.bx, S.by, S.bz)
end

function draw()
    eng.render.draw_sprite(S.bx, TABLE_Y + 0.02, S.bz, 0.14, 0.14, S.orb_tex)
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | YOU " .. S.player_pts .. " - " .. S.ai_pts .. " AI | RALLIES " .. S.rallies, 1.0, {0.45, 0.92, 1.0, 1.0})
end
