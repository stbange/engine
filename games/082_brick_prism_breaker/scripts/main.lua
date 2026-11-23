-- 082_brick_prism_breaker: 3D Corridor Arkanoid / Curveball
local S = game.state

local HX, HY = 5.4, 3.4
local PADDLE_Z = -2.0
local BACK_Z = -16.5

local function spawn_ball(x, y, z, vx, vy, vz, sx, sy)
    local e = eng.scene.spawn("energy_sphere")
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_mesh(e, S.ball_mesh, { color = {1.0, 0.95, 0.45, 1.0}, roughness = 0.12 })
    S.balls[#S.balls + 1] = { ent = e, x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, sx = sx or 0.0, sy = sy or 0.0 }
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, crt = 0.12, fog_density = 0.014 })
    eng.render.set_sky(0.03, 0.04, 0.11, 0.10, 0.18, 0.30)
    eng.render.add_light({ type = "dir", dir = {-0.25, -0.7, -0.8}, color = {1.9, 1.95, 2.2}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 0.0, -10.0}, color = {1.6, 2.2, 2.8}, range = 28.0 })

    local seed_base = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ball_mesh = eng.asset.sphere(0.42, 10, 14)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.wall_tex = eng.procgen.texture("sci_fi_panel", seed_base, 64)
    S.glass_tex = eng.procgen.texture("marble", seed_base + 19, 64)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_pad = eng.audio.synth("triangle", 420, 0.08, 660)
    S.sfx_brk = eng.audio.synth("square", 640, 0.10, 980)

    -- 3D Tunnel Corridor (left, right, floor, ceiling, back wall)
    local walls = {
        { -HX - 0.25, 0.0, -9.2, 0.4, HY * 2.1, 15.6, {0.16, 0.30, 0.46, 1.0} },
        {  HX + 0.25, 0.0, -9.2, 0.4, HY * 2.1, 15.6, {0.16, 0.30, 0.46, 1.0} },
        { 0.0, -HY - 0.25, -9.2, HX * 2.1, 0.4, 15.6, {0.12, 0.22, 0.36, 1.0} },
        { 0.0,  HY + 0.25, -9.2, HX * 2.1, 0.4, 15.6, {0.12, 0.22, 0.36, 1.0} },
        { 0.0, 0.0, BACK_Z - 0.3, HX * 2.1, HY * 2.1, 0.4, {0.20, 0.35, 0.55, 1.0} }
    }
    for i = 1, #walls do
        local w = walls[i]
        local we = eng.scene.spawn("tunnel_wall_" .. tostring(i))
        eng.scene.set_pos(we, w[1], w[2], w[3])
        eng.scene.set_scale(we, w[4], w[5], w[6])
        eng.scene.set_mesh(we, S.box_mesh, { tex = S.wall_tex, color = w[7], roughness = 0.35 })
    end

    -- Layered 3D Glass & Crystal Prism Brick Walls (3 layers x 3 cols x 2 rows = 18 bricks)
    S.bricks = {}
    local layer_colors = {
        {0.35, 0.90, 1.00, 1.0},
        {0.95, 0.42, 0.90, 1.0},
        {1.00, 0.82, 0.28, 1.0}
    }
    for l = 1, 3 do
        local bz = -9.8 - (l - 1) * 2.1
        for r = 1, 2 do
            local by = (r == 1) and -1.55 or 1.55
            for c = 1, 3 do
                local bx = (c - 2) * 3.45
                local be = eng.scene.spawn("prism_brick")
                eng.scene.set_pos(be, bx, by, bz)
                eng.scene.set_scale(be, 3.25, 2.85, 0.75)
                eng.scene.set_mesh(be, S.box_mesh, { tex = S.glass_tex, color = layer_colors[l], metallic = 0.25, roughness = 0.18 })

                local ce = eng.scene.spawn("prism_core")
                eng.scene.set_pos(ce, bx, by - 0.45, bz + 0.35)
                eng.scene.set_scale(ce, 0.8, 0.75, 0.8)
                eng.scene.set_mesh(ce, S.crystal_mesh, { color = layer_colors[l] })

                S.bricks[#S.bricks + 1] = {
                    ent = be, core = ce, x = bx, y = by, z = bz,
                    hx = 1.68, hy = 1.48, hz = 0.48,
                    multiball = (c == 2), alive = true
                }
            end
        end
    end
    S.total_bricks = #S.bricks
    S.bricks_broken = 0

    -- Translucent/Framed 3D Paddle at Z = PADDLE_Z (4 frame bars so camera sees straight down corridor!)
    S.paddle_root = eng.scene.spawn("paddle_root")
    S.pw, S.ph = 2.8, 2.0
    eng.scene.set_pos(S.paddle_root, 0.0, 0.0, PADDLE_Z)
    local bars = {
        { 0.0,  S.ph * 0.5, 0.0, S.pw, 0.16, 0.18 },
        { 0.0, -S.ph * 0.5, 0.0, S.pw, 0.16, 0.18 },
        { -S.pw * 0.5, 0.0, 0.0, 0.16, S.ph, 0.18 },
        {  S.pw * 0.5, 0.0, 0.0, 0.16, S.ph, 0.18 }
    }
    for i = 1, #bars do
        local b = bars[i]
        local pe = eng.scene.spawn("paddle_bar_" .. tostring(i))
        eng.scene.set_parent(pe, S.paddle_root)
        eng.scene.set_pos(pe, b[1], b[2], b[3])
        eng.scene.set_scale(pe, b[4], b[5], b[6])
        eng.scene.set_mesh(pe, S.box_mesh, { color = {0.3, 1.0, 0.65, 1.0} })
    end

    S.px, S.py = 0.0, 0.0
    S.pvx, S.pvy = 0.0, 0.0
    S.balls = {}
    S.paddle_hits = 0
    S.spin_bounces = 0
    S.lives = 3
    S.score = 0
    S.won = false

    spawn_ball(0.0, 0.0, PADDLE_Z - 0.8, 3.2, 2.1, -19.5, 0.0, 0.0)
    eng.camera.look_at(0.0, 0.4, 4.8, 0.0, 0.0, -13.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local npx = eng.math.clamp(S.px + mx * 13.5 * dt, -HX + S.pw * 0.5, HX - S.pw * 0.5)
    local npy = eng.math.clamp(S.py + my * 11.5 * dt, -HY + S.ph * 0.5, HY - S.ph * 0.5)
    S.pvx = (dt > 0.0001) and ((npx - S.px) / dt) or 0.0
    S.pvy = (dt > 0.0001) and ((npy - S.py) / dt) or 0.0
    S.px, S.py = npx, npy
    eng.scene.set_pos(S.paddle_root, S.px, S.py, PADDLE_Z)

    for bi = #S.balls, 1, -1 do
        local b = S.balls[bi]
        -- Apply Curveball Magnus spin acceleration
        b.vx = b.vx + b.sx * dt
        b.vy = b.vy + b.sy * dt
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.z = b.z + b.vz * dt

        if b.x > HX - 0.42 then b.x = HX - 0.42; b.vx = -math.abs(b.vx) end
        if b.x < -HX + 0.42 then b.x = -HX + 0.42; b.vx = math.abs(b.vx) end
        if b.y > HY - 0.42 then b.y = HY - 0.42; b.vy = -math.abs(b.vy) end
        if b.y < -HY + 0.42 then b.y = -HY + 0.42; b.vy = math.abs(b.vy) end
        if b.z < BACK_Z + 0.45 then b.z = BACK_Z + 0.45; b.vz = math.abs(b.vz) end

        -- Paddle bounce & Curveball spin transfer
        if b.vz > 0.0 and b.z >= PADDLE_Z - 0.48 and b.z <= PADDLE_Z + 0.70 then
            if math.abs(b.x - S.px) <= (S.pw * 0.5 + 0.55) and math.abs(b.y - S.py) <= (S.ph * 0.5 + 0.55) then
                b.z = PADDLE_Z - 0.50
                b.vz = -23.0
                b.vx = (b.x - S.px) * 7.5 + S.pvx * 0.25
                b.vy = (b.y - S.py) * 6.5 + S.pvy * 0.25
                b.sx = -S.pvx * 0.55
                b.sy = -S.pvy * 0.55
                S.paddle_hits = S.paddle_hits + 1
                if math.abs(b.sx) + math.abs(b.sy) > 0.4 then S.spin_bounces = S.spin_bounces + 1 end
                eng.audio.play(S.sfx_pad, b.x, b.y, b.z, 0)
            end
        end

        -- Prism brick shattering
        for k = 1, #S.bricks do
            local br = S.bricks[k]
            if br.alive and math.abs(b.z - br.z) <= (br.hz + 0.42)
               and math.abs(b.x - br.x) <= (br.hx + 0.42)
               and math.abs(b.y - br.y) <= (br.hy + 0.42) then
                br.alive = false
                eng.scene.despawn(br.ent)
                eng.scene.despawn(br.core)
                S.bricks_broken = S.bricks_broken + 1
                S.score = S.score + 150
                b.vz = -b.vz
                eng.audio.play(S.sfx_brk, br.x, br.y, br.z, 0)

                if br.multiball and #S.balls < 3 then
                    spawn_ball(br.x, br.y, br.z + 0.4, -5.2, 3.6, 18.5, 2.0, -1.5)
                    spawn_ball(br.x, br.y, br.z + 0.4, 5.2, -3.6, 18.5, -2.0, 1.5)
                end
                break
            end
        end

        eng.scene.set_pos(b.ent, b.x, b.y, b.z)

        if b.z > 1.5 then
            eng.scene.despawn(b.ent)
            table.remove(S.balls, bi)
        end
    end

    if #S.balls == 0 and S.bricks_broken < S.total_bricks then
        S.lives = math.max(1, S.lives - 1)
        spawn_ball(S.px, S.py, PADDLE_Z - 0.6, 3.6, -2.4, -19.5, 0.0, 0.0)
    end

    if S.bricks_broken >= S.total_bricks then
        S.won = true
        S.score = S.score + 500
    end

    eng.camera.look_at(S.px * 0.22, 0.35 + S.py * 0.22, 4.8, S.px * 0.1, S.py * 0.1, -13.0, 0)
end

function draw()
    for i = 1, #S.balls do
        local b = S.balls[i]
        eng.render.draw_sprite(b.x, b.y, b.z + 0.35, 0.75, 0.75, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | PRISMS " .. S.bricks_broken .. "/" .. S.total_bricks .. " | SCORE " .. S.score, 1.0, {0.75, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 180, S.lives / 3.0, "BALLS ")
end
