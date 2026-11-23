-- 090_joust_sky_knights: Flap a Winged Avian Mount Over Lava Platforms & Win Higher-Y Lance Collisions
local S = game.state

local WRAP_X = 13.0
local GRAV = -15.5
local Y_CEIL = 9.8

local function wrap_x(x)
    if x > WRAP_X then return x - WRAP_X * 2.0 end
    if x < -WRAP_X then return x + WRAP_X * 2.0 end
    return x
end

local function wrap_dx(dx)
    if dx > WRAP_X then return dx - WRAP_X * 2.0 end
    if dx < -WRAP_X then return dx + WRAP_X * 2.0 end
    return dx
end

local function spawn_sky_knight(name, seed, armor_col, lance_col)
    local mount = eng.scene.spawn(name)
    eng.procgen.animal(mount, seed, "avian")

    local rider = eng.scene.spawn(name .. "_rider")
    eng.scene.set_parent(rider, mount)
    eng.scene.set_pos(rider, 0.0, 1.18, -0.04)
    eng.scene.set_scale(rider, 0.36, 0.50, 0.36)
    eng.scene.set_mesh(rider, S.box_mesh, { color = armor_col, cast_shadow = true })

    local helm = eng.scene.spawn(name .. "_helm")
    eng.scene.set_parent(helm, mount)
    eng.scene.set_pos(helm, 0.0, 1.54, -0.04)
    eng.scene.set_scale(helm, 0.28, 0.26, 0.30)
    eng.scene.set_mesh(helm, S.box_mesh, { color = {0.92, 0.94, 0.98, 1.0} })

    local lance = eng.scene.spawn(name .. "_lance")
    eng.scene.set_parent(lance, mount)
    eng.scene.set_pos(lance, 0.24, 1.16, -0.92)
    eng.scene.set_scale(lance, 0.10, 0.10, 1.65)
    eng.scene.set_mesh(lance, S.box_mesh, { color = lance_col, metallic = 0.65, roughness = 0.25 })

    return { mount = mount, rider = rider, helm = helm, lance = lance }
end

local function despawn_knight_rig(rig)
    eng.scene.despawn(rig.lance)
    eng.scene.despawn(rig.helm)
    eng.scene.despawn(rig.rider)
    eng.scene.despawn(rig.mount)
end

local function land_on_platforms(prev_y, x, y, vy)
    if vy <= 0.0 then
        for i = 1, #S.platforms do
            local p = S.platforms[i]
            if math.abs(x - p.x) <= p.hw and prev_y >= (p.top - 0.16) and y <= (p.top + 0.05) then
                return p.top, 0.0, true
            end
        end
    end
    return y, vy, false
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.010 })
    eng.render.set_sky(0.08, 0.03, 0.06, 0.32, 0.11, 0.06)
    eng.render.add_light({ type = "dir", dir = {-0.30, -0.85, -0.50}, color = {2.2, 2.0, 1.8}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 1.5, 1.5}, color = {2.8, 1.1, 0.35}, range = 34.0 })

    local seed_base = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.egg_mesh = eng.asset.sphere(0.46, 10, 14)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.stone_tex = eng.procgen.texture("stone_brick", seed_base, 64)
    S.lava_tex = eng.procgen.texture("rust_metal", seed_base + 17, 64)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_flap = eng.audio.synth("triangle", 260, 0.07, 420)
    S.sfx_lance = eng.audio.synth("noise", 340, 0.13, 95)
    S.sfx_clang = eng.audio.synth("square", 620, 0.08, 480)
    S.sfx_egg = eng.audio.synth("square", 540, 0.15, 960)

    -- Bubbling Molten Lava Sea + Volcanic Backdrop Pillars
    local lava = eng.scene.spawn("molten_lava_sea")
    eng.scene.set_pos(lava, 0.0, -0.35, 0.0)
    eng.scene.set_scale(lava, 28.0, 0.55, 4.6)
    eng.scene.set_mesh(lava, S.box_mesh, { tex = S.lava_tex, color = {1.0, 0.28, 0.08, 1.0}, roughness = 0.35 })

    local bg_xs = { -10.5, -3.5, 3.5, 10.5 }
    for i = 1, #bg_xs do
        local pe = eng.scene.spawn("cavern_pillar_" .. tostring(i))
        eng.scene.set_pos(pe, bg_xs[i], -0.2, -3.2)
        eng.scene.set_scale(pe, 1.1, 3.4, 1.1)
        eng.scene.set_mesh(pe, S.pillar_mesh, { tex = S.stone_tex, color = {0.38, 0.28, 0.26, 1.0} })
    end

    -- 4 Floating Stone Sky-Platforms over the Lava
    S.platforms = {
        { x =  0.0, y = 0.45, w = 9.2, h = 0.52, hw = 4.6, top = 0.71 },
        { x = -7.6, y = 3.55, w = 6.0, h = 0.46, hw = 3.0, top = 3.78 },
        { x =  7.6, y = 3.55, w = 6.0, h = 0.46, hw = 3.0, top = 3.78 },
        { x =  0.0, y = 6.55, w = 6.8, h = 0.46, hw = 3.4, top = 6.78 }
    }
    for i = 1, #S.platforms do
        local p = S.platforms[i]
        local pe = eng.scene.spawn("lava_ledge_" .. tostring(i))
        eng.scene.set_pos(pe, p.x, p.y, 0.0)
        eng.scene.set_scale(pe, p.w, p.h, 2.1)
        eng.scene.set_mesh(pe, S.box_mesh, { tex = S.stone_tex, color = {0.62, 0.54, 0.48, 1.0}, cast_shadow = true })
    end

    -- Player Winged Avian Mount + Knight + Lance
    S.player_rig = spawn_sky_knight("player_avian_knight", seed_base + 7, {0.20, 0.76, 1.0, 1.0}, {1.0, 0.92, 0.38, 1.0})
    S.px, S.py = 0.0, 0.71
    S.vx, S.vy = 0.0, 0.0
    S.facing = 1
    S.flap_cd = 0.0
    S.invuln = 0.0
    S.lives = 3
    S.score = 0
    S.flaps = 0
    S.jousts_won = 0
    S.eggs_collected = 0
    S.won = false

    eng.scene.set_pos(S.player_rig.mount, S.px, S.py, 0.0)
    eng.scene.set_rot_deg(S.player_rig.mount, 0.0, -90.0, 0.0)

    -- 4 Enemy Bounder Sky Knights on Avian Mounts
    S.enemies = {}
    local en_specs = {
        { x = -7.6, y = 3.78, vx =  4.2, cruise_y = 3.6 },
        { x =  7.6, y = 3.78, vx = -4.4, cruise_y = 4.2 },
        { x = -4.6, y = 6.85, vx =  4.8, cruise_y = 6.4 },
        { x =  5.2, y = 5.30, vx = -4.6, cruise_y = 5.1 }
    }
    S.total_knights = #en_specs
    for i = 1, #en_specs do
        local es = en_specs[i]
        local rig = spawn_sky_knight("enemy_avian_" .. tostring(i), seed_base + 40 + i * 23,
                                     {0.92, 0.18, 0.22, 1.0}, {0.95, 0.45, 0.25, 1.0})
        eng.scene.set_pos(rig.mount, es.x, es.y, 0.0)
        eng.scene.set_rot_deg(rig.mount, 0.0, (es.vx > 0) and -90.0 or 90.0, 0.0)
        S.enemies[i] = {
            rig = rig, x = es.x, y = es.y, vx = es.vx, vy = 0.0,
            cruise_y = es.cruise_y, flap_t = i * 0.08, alive = true
        }
    end

    S.eggs = {}
    eng.camera.look_at(0.0, 5.4, 18.8, 0.0, 4.2, 0.0, 0)
    eng.mod.emit("post_init")
end

local function spawn_dropped_egg(x, y, vx)
    local ee = eng.scene.spawn("knight_egg")
    eng.scene.set_pos(ee, x, y, 0.0)
    eng.scene.set_scale(ee, 0.78, 1.02, 0.78)
    eng.scene.set_mesh(ee, S.egg_mesh, { color = {0.42, 1.0, 0.55, 1.0}, metallic = 0.35, roughness = 0.22, cast_shadow = true })
    S.eggs[#S.eggs + 1] = { ent = ee, x = x, y = y, vx = vx, vy = 2.6, alive = true }
end

function update(dt)
    if S.won then return end
    S.flap_cd = math.max(0.0, S.flap_cd - dt)
    S.invuln = math.max(0.0, S.invuln - dt)

    local mx, _ = eng.input.axis2d("left", "right", "down", "up")
    if mx > 0.1 then S.facing = 1 elseif mx < -0.1 then S.facing = -1 end
    S.vx = S.vx + mx * 21.0 * dt
    S.vx = S.vx * math.max(0.0, 1.0 - 0.55 * dt)
    S.vx = eng.math.clamp(S.vx, -9.2, 9.2)

    local want_flap = eng.input.pressed("jump") or eng.input.pressed("up")
                   or ((eng.input.down("jump") or eng.input.down("up")) and S.flap_cd <= 0.0)
    if want_flap and S.flap_cd <= 0.0 then
        S.flap_cd = 0.085
        S.vy = eng.math.clamp(math.max(S.vy + 4.8, 5.2), -10.0, 8.8)
        S.flaps = S.flaps + 1
        eng.audio.play(S.sfx_flap, S.px, S.py, 0.0, 0)
    end

    local prev_py = S.py
    S.vy = S.vy + GRAV * dt
    S.px = wrap_x(S.px + S.vx * dt)
    S.py = S.py + S.vy * dt
    if S.py > Y_CEIL then S.py = Y_CEIL; S.vy = -math.abs(S.vy) * 0.45 end
    S.py, S.vy = land_on_platforms(prev_py, S.px, S.py, S.vy)

    -- Molten lava hazard outside central bridge
    if S.py < 0.20 then
        if S.invuln <= 0.0 then
            S.lives = math.max(1, S.lives - 1)
            S.invuln = 1.0
            eng.audio.play(S.sfx_lance, S.px, 0.2, 0.0, 0)
        end
        S.py = 0.85
        S.vy = 6.8
    end

    local pitch_bob = eng.math.clamp(-S.vy * 2.2, -16.0, 16.0)
    eng.scene.set_pos(S.player_rig.mount, S.px, S.py, 0.0)
    eng.scene.set_rot_deg(S.player_rig.mount, pitch_bob, (S.facing > 0) and -90.0 or 90.0, 0.0)

    -- Step Enemy Avian Sky Knights & Altitude Lance Collisions
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            en.flap_t = en.flap_t - dt
            local target_y = en.cruise_y + math.sin(i * 1.7 + en.x * 0.25) * 0.65
            if en.y < target_y and en.flap_t <= 0.0 then
                en.flap_t = 0.18
                en.vy = math.max(en.vy + 4.6, 4.4)
            end

            local p_ey = en.y
            en.vy = en.vy + GRAV * dt
            en.x = wrap_x(en.x + en.vx * dt)
            en.y = en.y + en.vy * dt
            if en.y > Y_CEIL - 0.4 then en.y = Y_CEIL - 0.4; en.vy = -1.5 end
            en.y, en.vy = land_on_platforms(p_ey, en.x, en.y, en.vy)
            if en.y < 1.1 then en.y = 1.1; en.vy = 5.4 end

            eng.scene.set_pos(en.rig.mount, en.x, en.y, 0.0)
            eng.scene.set_rot_deg(en.rig.mount, 0.0, (en.vx > 0) and -90.0 or 90.0, 0.0)

            local dx = wrap_dx(S.px - en.x)
            local dy = S.py - en.y
            if math.abs(dx) < 1.52 and math.abs(dy) < 1.28 then
                if dy > 0.16 then
                    -- Player strikes from higher Y altitude: unseat enemy knight & drop egg!
                    en.alive = false
                    despawn_knight_rig(en.rig)
                    spawn_dropped_egg(en.x, en.y + 0.45, en.vx * 0.30)
                    S.jousts_won = S.jousts_won + 1
                    S.score = S.score + 250
                    S.vy = math.max(S.vy, 3.2)
                    eng.audio.play(S.sfx_lance, en.x, en.y + 0.8, 0.0, 0)
                elseif dy >= -0.16 then
                    -- Equal-altitude lance clang!
                    local push = (dx >= 0.0) and 5.5 or -5.5
                    S.vx = push
                    en.vx = -push
                    S.vy = 2.6
                    en.vy = 2.6
                    eng.audio.play(S.sfx_clang, en.x, en.y + 1.0, 0.0, 0)
                else
                    -- Struck from below!
                    if S.invuln <= 0.0 then
                        S.lives = math.max(1, S.lives - 1)
                        S.invuln = 1.1
                        eng.audio.play(S.sfx_lance, S.px, S.py + 0.8, 0.0, 0)
                    end
                    S.vx = (dx >= 0.0) and 6.0 or -6.0
                    S.vy = 3.4
                end
            end
        end
    end

    -- Step Dropped Eggs & Player Collection
    local active_eggs = 0
    for ei = #S.eggs, 1, -1 do
        local eg = S.eggs[ei]
        if eg.alive then
            local pey = eg.y
            eg.vy = eg.vy + GRAV * 0.85 * dt
            eg.x = wrap_x(eg.x + eg.vx * dt)
            eg.y = eg.y + eg.vy * dt
            local ly, lvy, landed = land_on_platforms(pey, eg.x, eg.y - 0.35, eg.vy)
            if landed then
                eg.y = ly + 0.35
                eg.vy = (math.abs(eg.vy) > 1.8) and (math.abs(eg.vy) * 0.35) or 0.0
                eg.vx = eg.vx * math.max(0.0, 1.0 - 3.5 * dt)
            else
                eg.vy = lvy
            end
            -- Thermal updraft keeps dropped eggs above open lava so they remain collectible
            if eg.y < 0.65 then
                eg.y = 0.65
                eg.vy = 5.4
                eg.vx = (eg.x >= 0.0) and -3.4 or 3.4
            end
            eng.scene.set_pos(eg.ent, eg.x, eg.y, 0.0)

            local edx = wrap_dx(S.px - eg.x)
            if math.abs(edx) < 1.50 and math.abs((S.py + 0.65) - eg.y) < 1.38 then
                eg.alive = false
                eng.scene.despawn(eg.ent)
                table.remove(S.eggs, ei)
                S.eggs_collected = S.eggs_collected + 1
                S.score = S.score + 300
                eng.audio.play(S.sfx_egg, eg.x, eg.y, 0.0, 0)
            else
                active_eggs = active_eggs + 1
            end
        end
    end

    if S.jousts_won >= S.total_knights and active_eggs == 0 and S.eggs_collected >= S.total_knights then
        S.won = true
        S.score = S.score + 500
    end

    eng.camera.look_at(S.px * 0.14, 5.4, 18.8, S.px * 0.10, 4.2, 0.0, 0)
end

function draw()
    for i = 1, #S.eggs do
        local eg = S.eggs[i]
        eng.render.draw_sprite(eg.x, eg.y + 0.55, 0.25, 0.50, 0.50, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | JOUSTS " .. S.jousts_won .. "/" .. S.total_knights .. " | EGGS " .. S.eggs_collected .. "/" .. S.total_knights .. " | SCORE " .. S.score, 1.0, {1.0, 0.88, 0.42, 1.0})
    eng.ui.bar(x, y + 26, 180, S.lives / 3.0, "MOUNT ")
end
