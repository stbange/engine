-- 056_sheepdog_herder: Boids flocking physics + bark repulsion + procedural quadruped sheep
local S = game.state

local PEN_Z_MIN, PEN_Z_MAX = -13.0, -7.2
local PEN_HALF_W = 4.2

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.010 })
    eng.render.set_sky(0.24, 0.58, 0.92, 0.78, 0.88, 0.96)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.4}, color = {2.2, 2.15, 1.95}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.0, -8.0}, color = {1.6, 1.5, 1.1}, range = 32.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.hill_mesh = eng.asset.sphere(1.0, 10, 14)
    S.tree_mesh = eng.procgen.tree(seed_base + 17, 2, 3.0, 0.22)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.grass_tex = eng.procgen.texture("grass", seed_base, 64)
    S.wood_tex = eng.procgen.texture("wood_planks", seed_base + 5, 64)

    S.sfx_bark = eng.audio.synth("saw", 390, 0.11, 210)
    S.sfx_pen = eng.audio.synth("triangle", 520, 0.16, 840)

    local meadow = eng.scene.spawn("meadow_ground")
    eng.scene.set_pos(meadow, 0.0, -0.25, 0.0)
    eng.scene.set_scale(meadow, 34.0, 0.5, 34.0)
    eng.scene.set_mesh(meadow, S.box_mesh, { tex = S.grass_tex, color = {0.42, 0.78, 0.34, 1.0} })

    -- Gentle meadow hills & boundary shade trees
    local hills = { {-10.5, -2.0, 4.2}, {10.5, -1.5, 4.0}, {-9.5, 7.5, 3.6}, {9.5, 7.0, 3.8} }
    for i = 1, #hills do
        local h = hills[i]
        local kh = eng.scene.spawn("meadow_hill_" .. tostring(i))
        eng.scene.set_pos(kh, h[1], -0.4, h[2])
        eng.scene.set_scale(kh, h[3], 1.3, h[3])
        eng.scene.set_mesh(kh, S.hill_mesh, { tex = S.grass_tex, color = {0.38, 0.74, 0.30, 1.0} })

        local tr = eng.scene.spawn("meadow_tree_" .. tostring(i))
        eng.scene.set_pos(tr, h[1], 0.6, h[2])
        eng.scene.set_mesh(tr, S.tree_mesh, { color = {0.26, 0.68, 0.28, 1.0}, cast_shadow = true })
    end

    -- Wooden Sheep Pen Corral at north meadow (open south gate facing +Z)
    local fences = {
        { 0.0, PEN_Z_MIN, PEN_HALF_W * 2.0, 0.25 },
        { -PEN_HALF_W, (PEN_Z_MIN + PEN_Z_MAX) * 0.5, 0.25, PEN_Z_MAX - PEN_Z_MIN },
        {  PEN_HALF_W, (PEN_Z_MIN + PEN_Z_MAX) * 0.5, 0.25, PEN_Z_MAX - PEN_Z_MIN }
    }
    for i = 1, #fences do
        local fc = fences[i]
        local fe = eng.scene.spawn("pen_fence_" .. tostring(i))
        eng.scene.set_pos(fe, fc[1], 0.55, fc[2])
        eng.scene.set_scale(fe, fc[3], 1.1, fc[4])
        eng.scene.set_mesh(fe, S.box_mesh, { tex = S.wood_tex, color = {0.72, 0.48, 0.26, 1.0}, cast_shadow = true })
    end

    local pen_pad = eng.scene.spawn("pen_straw_floor")
    eng.scene.set_pos(pen_pad, 0.0, 0.02, (PEN_Z_MIN + PEN_Z_MAX) * 0.5)
    eng.scene.set_scale(pen_pad, PEN_HALF_W * 1.9, 0.05, PEN_Z_MAX - PEN_Z_MIN - 0.2)
    eng.scene.set_mesh(pen_pad, S.box_mesh, { color = {0.86, 0.76, 0.42, 1.0} })

    -- Border Collie Sheepdog
    S.dx, S.dz = 0.0, 9.2
    S.dog_ent = eng.scene.spawn("sheepdog")
    eng.scene.set_pos(S.dog_ent, S.dx, 0.0, S.dz)
    eng.procgen.animal(S.dog_ent, seed_base + 3, "quadruped")
    eng.scene.set_scale(S.dog_ent, 0.85, 0.85, 0.95)

    -- 7 Procedural Quadruped Sheep with Boids state
    S.sheep = {}
    local start_pts = {
        {-3.2, 2.5}, {0.0, 3.4}, {3.2, 2.4},
        {-2.0, 0.4}, {2.1, 0.6}, {-0.8, -1.2}, {1.2, -1.0}
    }
    for i = 1, #start_pts do
        local sx, sz = start_pts[i][1], start_pts[i][2]
        local se = eng.scene.spawn("sheep_" .. tostring(i))
        eng.scene.set_pos(se, sx, 0.0, sz)
        eng.procgen.animal(se, seed_base + 20 + i, "quadruped")
        S.sheep[i] = { ent = se, x = sx, z = sz, vx = 0.0, vz = 0.0, penned = false }
    end

    S.barks = 0
    S.bark_timer = 0.0
    S.bark_cd = 0.0
    S.penned_count = 0
    S.target_sheep = 6
    S.time_left = 45.0
    S.won = false
    S.lost = false

    eng.camera.look_at(0.0, 20.5, 18.5, 0.0, 0.5, -2.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or S.lost then return end
    S.time_left = S.time_left - dt
    S.bark_timer = math.max(0.0, S.bark_timer - dt)
    S.bark_cd = math.max(0.0, S.bark_cd - dt)

    local sprinting = eng.input.down("jump") or eng.input.pressed("jump")
    local dog_speed = sprinting and 15.0 or 10.0
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.dx = eng.math.clamp(S.dx + mx * dog_speed * dt, -13.5, 13.5)
        S.dz = eng.math.clamp(S.dz - my * dog_speed * dt, -8.5, 13.5)
        eng.scene.set_pos(S.dog_ent, S.dx, 0.0, S.dz)
        eng.scene.set_rot_deg(S.dog_ent, 0.0, math.deg(math.atan2(-mx, my)), 0.0)
    end

    -- Bark impulse (fire)
    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.bark_cd <= 0.0 then
        S.bark_cd = 0.24
        S.bark_timer = 0.35
        S.barks = S.barks + 1
        eng.audio.play(S.sfx_bark, S.dx, 0.8, S.dz, 0)
    end

    -- Boids Flocking Update: Separation + Alignment + Cohesion + Dog/Bark Repulsion
    local penned_now = 0
    for i = 1, #S.sheep do
        local s = S.sheep[i]
        if s.penned then
            penned_now = penned_now + 1
            s.vx = s.vx * 0.88
            s.vz = s.vz * 0.88
            s.x = eng.math.clamp(s.x + s.vx * dt, -PEN_HALF_W + 0.7, PEN_HALF_W - 0.7)
            s.z = eng.math.clamp(s.z + s.vz * dt, PEN_Z_MIN + 0.8, PEN_Z_MAX - 0.5)
            eng.scene.set_pos(s.ent, s.x, 0.0, s.z)
        else
            local sep_x, sep_z = 0.0, 0.0
            local ali_x, ali_z = 0.0, 0.0
            local coh_x, coh_z = 0.0, 0.0
            local n_cnt = 0

            for j = 1, #S.sheep do
                if i ~= j and (not S.sheep[j].penned) then
                    local o = S.sheep[j]
                    local dx, dz = s.x - o.x, s.z - o.z
                    local d = math.sqrt(dx * dx + dz * dz)
                    if d > 0.001 and d < 2.0 then
                        sep_x = sep_x + (dx / d) * (2.0 - d)
                        sep_z = sep_z + (dz / d) * (2.0 - d)
                    end
                    if d < 6.8 then
                        ali_x = ali_x + o.vx
                        ali_z = ali_z + o.vz
                        coh_x = coh_x + o.x
                        coh_z = coh_z + o.z
                        n_cnt = n_cnt + 1
                    end
                end
            end

            local ax, az = sep_x * 6.5, sep_z * 6.5
            if n_cnt > 0 then
                ali_x, ali_z = ali_x / n_cnt, ali_z / n_cnt
                coh_x, coh_z = (coh_x / n_cnt) - s.x, (coh_z / n_cnt) - s.z
                ax = ax + (ali_x - s.vx) * 1.4 + coh_x * 1.8
                az = az + (ali_z - s.vz) * 1.4 + coh_z * 1.8
            end

            -- Flee from Border Collie (stronger & wider radius when barking!)
            local f_rad = (S.bark_timer > 0.0) and 13.5 or 8.0
            local f_gain = (S.bark_timer > 0.0) and 32.0 or 14.0
            local ddx, ddz = s.x - S.dx, s.z - S.dz
            local dd = math.sqrt(ddx * ddx + ddz * ddz)
            if dd > 0.01 and dd < f_rad then
                local push = (1.0 - dd / f_rad) * f_gain
                ax = ax + (ddx / dd) * push
                az = az + (ddz / dd) * push
            end

            -- Funnel awareness near open corral gate
            if math.abs(s.x) < 5.2 and s.z < -3.0 then
                ax = ax + (0.0 - s.x) * 3.2
                az = az - 4.0
            end

            s.vx = (s.vx + ax * dt) * 0.94
            s.vz = (s.vz + az * dt) * 0.94
            local sp = math.sqrt(s.vx * s.vx + s.vz * s.vz)
            if sp > 9.5 then
                s.vx = (s.vx / sp) * 9.5
                s.vz = (s.vz / sp) * 9.5
            end

            s.x = eng.math.clamp(s.x + s.vx * dt, -11.5, 11.5)
            local min_z = (math.abs(s.x) < (PEN_HALF_W - 0.35)) and (PEN_Z_MIN + 0.8) or (PEN_Z_MAX + 0.25)
            s.z = eng.math.clamp(s.z + s.vz * dt, min_z, 11.5)
            if s.z <= min_z + 0.05 and math.abs(s.x) >= (PEN_HALF_W - 0.35) then
                s.vx = s.vx - (s.x > 0 and 4.0 or -4.0) * dt
            end
            eng.scene.set_pos(s.ent, s.x, 0.0, s.z)
            if sp > 0.25 then
                eng.scene.set_rot_deg(s.ent, 0.0, math.deg(math.atan2(-s.vx, -s.vz)), 0.0)
            end

            if math.abs(s.x) < (PEN_HALF_W - 0.35) and s.z < PEN_Z_MAX then
                s.penned = true
                penned_now = penned_now + 1
                eng.audio.play(S.sfx_pen, s.x, 1.0, s.z, 0)
            end
        end
    end

    S.penned_count = penned_now
    if S.penned_count >= S.target_sheep then
        S.won = true
        eng.save.write("sheepdog_herder_clear", tostring(S.penned_count))
    elseif S.time_left <= 0.0 then
        S.lost = true
    end
end

function draw()
    if S.bark_timer > 0.0 then
        eng.render.draw_sprite(S.dx, 1.8, S.dz, 1.4, 1.4, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 54, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or (S.lost and (" | " .. eng.i18n.t("defeat")) or "")
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | TIME: %.1fs | BARKS: %d%s", math.max(0.0, S.time_left), S.barks, status), 1.0, {1.0, 0.96, 0.65, 1.0})
    eng.ui.bar(x, y + 24, 240, S.penned_count / S.target_sheep, "PENNED " .. S.penned_count .. "/" .. S.target_sheep .. " ")
end
