-- 019_zombie_barricade: Cabin holdout repairing wooden plank barricades (interact) while blasting waves through windows
local S = game.state

local WIN_XS = { -2.8, 0.0, 2.8 }

local function sync_window_planks(w)
    for p = 1, 3 do
        local py = (p <= w.planks) and (0.92 + (p - 1) * 0.42) or -4.0
        eng.scene.set_pos(w.plank_ents[p], w.x, py, -3.96)
    end
end

local function spawn_wave(wave_idx)
    S.wave = wave_idx
    local count = 2 + wave_idx
    for i = 1, count do
        local w_idx = ((wave_idx + i - 2) % 3) + 1
        local wx = WIN_XS[w_idx] + ((i % 2 == 0) and 0.25 or -0.25)
        local wz = -9.5 - (i - 1) * 1.35
        local ze = eng.scene.spawn("zombie_w" .. tostring(wave_idx) .. "_" .. tostring(i))
        eng.scene.set_pos(ze, wx, 0.9, wz)
        eng.scene.set_rot_deg(ze, 0.0, 180.0, 0.0)
        eng.procgen.person(ze, S.seed + wave_idx * 83 + i * 31)
        local bid = eng.physics.add_body(ze, { shape = "aabb", motion = "kinematic", half_extents = {0.55, 0.95, 0.55}, trigger = true })
        S.zombies[#S.zombies + 1] = {
            ent = ze, body = bid, win_idx = w_idx,
            x = wx, z = wz, hp = 2,
            speed = 2.4 + wave_idx * 0.25,
            claw_cd = 0.5, alive = true
        }
    end
end

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.024 })
    eng.render.set_sky(0.03, 0.05, 0.09, 0.12, 0.14, 0.18)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {1.1, 1.25, 1.55}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 2.6, 0.0}, color = {2.6, 1.75, 0.95}, range = 16.0 })
    eng.render.add_light({ type = "point", pos = {0.0, 3.2, -7.5}, color = {0.9, 1.4, 2.0}, range = 20.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    local wood_tex = eng.procgen.texture("wood_grain", S.seed, 64)
    local grass_tex = eng.procgen.texture("grass", S.seed + 11, 64)
    local stone_tex = eng.procgen.texture("stone_brick", S.seed + 23, 64)

    S.sfx_shot = eng.audio.synth("noise", 310, 0.11, 85)
    S.sfx_hammer = eng.audio.synth("square", 260, 0.09, 420)
    S.sfx_claw = eng.audio.synth("saw", 180, 0.14, 90)

    -- Misty exterior forest ground + interior cabin floorboards
    local yard = eng.scene.spawn("forest_ground")
    eng.scene.set_pos(yard, 0.0, -0.25, -5.0)
    eng.scene.set_scale(yard, 32.0, 0.5, 28.0)
    eng.scene.set_mesh(yard, S.box_mesh, { tex = grass_tex, color = {0.26, 0.34, 0.28, 1.0} })
    eng.physics.add_body(yard, { shape = "aabb", motion = "static", half_extents = {16.0, 0.25, 14.0} })

    local floor_e = eng.scene.spawn("cabin_floor")
    eng.scene.set_pos(floor_e, 0.0, 0.03, 0.0)
    eng.scene.set_scale(floor_e, 9.2, 0.08, 8.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = wood_tex, color = {0.55, 0.38, 0.24, 1.0} })

    -- Front cabin wall columns + sills + lintel framing 3 open shooting windows at z = -4.0
    local col_xs = { -4.2, -1.4, 1.4, 4.2 }
    for i = 1, #col_xs do
        local ce = eng.scene.spawn("cabin_post_" .. tostring(i))
        eng.scene.set_pos(ce, col_xs[i], 1.35, -4.0)
        eng.scene.set_scale(ce, 0.85, 2.7, 0.35)
        eng.scene.set_mesh(ce, S.box_mesh, { tex = stone_tex, color = {0.46, 0.42, 0.38, 1.0}, cast_shadow = true })
        eng.physics.add_body(ce, { shape = "aabb", motion = "static", half_extents = {0.42, 1.35, 0.18} })
    end
    local sill = eng.scene.spawn("cabin_sill")
    eng.scene.set_pos(sill, 0.0, 0.35, -4.0)
    eng.scene.set_scale(sill, 9.2, 0.70, 0.35)
    eng.scene.set_mesh(sill, S.box_mesh, { tex = wood_tex, color = {0.48, 0.34, 0.22, 1.0} })
    eng.physics.add_body(sill, { shape = "aabb", motion = "static", half_extents = {4.6, 0.35, 0.18} })

    local lintel = eng.scene.spawn("cabin_lintel")
    eng.scene.set_pos(lintel, 0.0, 2.45, -4.0)
    eng.scene.set_scale(lintel, 9.2, 0.50, 0.35)
    eng.scene.set_mesh(lintel, S.box_mesh, { tex = wood_tex, color = {0.48, 0.34, 0.22, 1.0} })

    -- Atmospheric deadwood pines in the misty yard
    local tree_mesh = eng.procgen.tree(S.seed + 41, 2, 2.8, 0.20)
    local tree_xs = { -7.0, -4.6, 4.6, 7.0 }
    for i = 1, #tree_xs do
        local te = eng.scene.spawn("pine_" .. tostring(i))
        eng.scene.set_pos(te, tree_xs[i], 0.0, -11.5 - (i % 2) * 2.0)
        eng.scene.set_mesh(te, tree_mesh, { cast_shadow = true })
    end

    -- 3 Barricaded Windows with wooden planks (start partially damaged so player can repair!)
    S.windows = {}
    local start_planks = { 1, 2, 2 }
    for i = 1, 3 do
        local wx = WIN_XS[i]
        local p_ents = {}
        for p = 1, 3 do
            local pe = eng.scene.spawn("win_" .. tostring(i) .. "_plank_" .. tostring(p))
            eng.scene.set_scale(pe, 1.85, 0.16, 0.10)
            eng.scene.set_rot_deg(pe, 0.0, 0.0, (p == 2) and -4.0 or 3.0)
            eng.scene.set_mesh(pe, S.box_mesh, { tex = wood_tex, color = {0.76, 0.56, 0.30, 1.0} })
            p_ents[p] = pe
        end
        S.windows[i] = { x = wx, z = -4.0, planks = start_planks[i], plank_ents = p_ents }
        sync_window_planks(S.windows[i])
    end

    S.flash_ent = eng.scene.spawn("shotgun_tracer")
    eng.scene.set_pos(S.flash_ent, 0.0, -5.0, 0.0)
    eng.scene.set_scale(S.flash_ent, 0.12, 0.12, 0.12)
    eng.scene.set_mesh(S.flash_ent, S.box_mesh, { color = {1.0, 0.88, 0.35, 1.0} })
    S.flash_timer = 0.0

    S.px, S.py, S.pz = -2.6, 1.35, -2.2
    S.yaw, S.pitch = 0.0, 0.0
    S.fire_cd = 0.0
    S.repair_cd = 0.0
    S.hp = 100
    S.repairs = 0
    S.kills = 0
    S.score = 0
    S.won = false
    S.lost = false
    S.zombies = {}

    eng.input.set_mouse_lock(true)
    spawn_wave(1)
    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
    eng.mod.emit("post_init")
end

local function fire_cabin_shotgun()
    local ox, oy, oz = S.px, 1.25, S.pz
    local ry, rp = math.rad(S.yaw or 0.0), math.rad(S.pitch or 0.0)
    local cp = math.cos(rp)
    local dx, dy, dz = -math.sin(ry) * cp, math.sin(rp), -math.cos(ry) * cp
    local best_d = 24.0
    local locked = eng.input.is_mouse_locked()
    for i = 1, #S.zombies do
        local z = S.zombies[i]
        if z.alive then
            local zx, zy, zz = z.x - ox, 1.0 - oy, z.z - oz
            local d = math.sqrt(zx * zx + zy * zy + zz * zz)
            if d > 0.1 and d < best_d then
                local dot = (zx / d) * dx + (zy / d) * dy + (zz / d) * dz
                if (not locked) or dot > 0.94 then
                    best_d = d
                    dx, dy, dz = zx / d, zy / d, zz / d
                end
            end
        end
    end

    eng.audio.play(S.sfx_shot, ox, oy, oz, 0)
    local hit = eng.physics.raycast(0, ox, oy, oz, dx, dy, dz, 26.0)
    local hx, hy, hz = ox + dx * 12.0, oy + dy * 12.0, oz + dz * 12.0
    if hit then
        hx, hy, hz = hit.point[1], hit.point[2], hit.point[3]
        for i = 1, #S.zombies do
            local z = S.zombies[i]
            if z.alive and z.ent == hit.entity then
                z.hp = z.hp - 2
                if z.hp <= 0 then
                    z.alive = false
                    eng.scene.despawn(z.ent)
                    S.kills = S.kills + 1
                    S.score = S.score + 125
                end
                break
            end
        end
    end

    eng.scene.set_pos(S.flash_ent, (ox + hx) * 0.5, (oy + hy) * 0.5, (oz + hz) * 0.5)
    eng.scene.set_scale(S.flash_ent, math.max(0.10, math.abs(hx - ox)), 0.10, math.max(0.10, math.abs(hz - oz)))
    S.flash_timer = 0.05
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.repair_cd = math.max(0.0, S.repair_cd - dt)

    if S.flash_timer > 0.0 then
        S.flash_timer = S.flash_timer - dt
        if S.flash_timer <= 0.0 then
            eng.scene.set_pos(S.flash_ent, 0.0, -5.0, 0.0)
            eng.scene.set_scale(S.flash_ent, 0.12, 0.12, 0.12)
        end
    end

    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw or 0.0, S.pitch or 0.0, 9.5, dt)
    local nx, nz = eng.physics.slide_move(0, S.px, 0.5, S.pz, dx, dz, 0.42)
    S.px = eng.math.clamp(nx, -3.6, 3.6)
    S.pz = eng.math.clamp(nz, -3.4, 2.5)

    -- Repair nearest damaged window barricade with interact
    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.repair_cd <= 0.0 then
        for i = 1, #S.windows do
            local w = S.windows[i]
            if w.planks < 3 and eng.math.dist3(S.px, 0.0, S.pz, w.x, 0.0, w.z) < 2.5 then
                w.planks = w.planks + 1
                sync_window_planks(w)
                S.repair_cd = 0.24
                S.repairs = S.repairs + 1
                S.score = S.score + 50
                eng.audio.play(S.sfx_hammer, w.x, 1.3, w.z, 0)
                break
            end
        end
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
        S.fire_cd = 0.18
        fire_cabin_shotgun()
    end

    -- Step shambling zombies toward cabin windows
    local living = 0
    for i = 1, #S.zombies do
        local z = S.zombies[i]
        if z.alive then
            living = living + 1
            if z.z < -4.65 then
                z.z = z.z + z.speed * dt
                eng.scene.set_pos(z.ent, z.x, 0.9, z.z)
            else
                z.claw_cd = z.claw_cd - dt
                if z.claw_cd <= 0.0 then
                    z.claw_cd = 1.05
                    local w = S.windows[z.win_idx]
                    eng.audio.play(S.sfx_claw, w.x, 1.2, w.z, 0)
                    if w.planks > 0 then
                        w.planks = w.planks - 1
                        sync_window_planks(w)
                    else
                        S.hp = math.max(0, S.hp - 15)
                    end
                end
            end
        end
    end

    if S.hp <= 0 then
        S.lost = true
    elseif living == 0 then
        if S.wave < 3 then
            eng.save.write("zombie_barricade", "wave_" .. tostring(S.wave + 1))
            spawn_wave(S.wave + 1)
        else
            S.won = true
            S.score = S.score + S.hp * 4
            eng.save.write("zombie_barricade", "clear")
        end
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
end

function draw()
    for i = 1, #S.zombies do
        local z = S.zombies[i]
        if z.alive then eng.render.draw_sprite(z.x, 2.05, z.z, 0.5, 0.5, S.orb_tex) end
    end
    local total_planks = S.windows[1].planks + S.windows[2].planks + S.windows[3].planks
    local x, y = eng.ui.anchor("top_left", 16, 14, 600, 56, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | WAVE " .. S.wave .. "/3 | PLANKS " .. total_planks .. "/9 | REPAIRS " .. S.repairs))
    eng.ui.label(x, y, msg, 1.0, {0.95, 0.85, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 200, S.hp / 100.0, "CABIN ")
end
