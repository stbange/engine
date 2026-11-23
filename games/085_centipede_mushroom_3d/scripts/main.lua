-- 085_centipede_mushroom_3d: Multi-Segment Procedural Serpent (`eng.procgen.animal` "serpentine") in 3D Mushroom Patches (`eng.procgen.tree`)
local S = game.state

local function spawn_mushroom(x, z, color_idx)
    if #S.mushrooms >= 36 then return end
    local m_mesh = S.shroom_trees[((color_idx - 1) % #S.shroom_trees) + 1]
    local stalk = eng.scene.spawn("mushroom_stalk")
    eng.scene.set_pos(stalk, x, 0.0, z)
    eng.scene.set_mesh(stalk, m_mesh, { color = {0.92, 0.86, 0.74, 1.0}, cast_shadow = true })

    local cap_colors = {
        {1.0, 0.24, 0.46, 1.0},
        {0.68, 0.32, 1.0, 1.0},
        {0.22, 0.92, 0.76, 1.0}
    }
    local cap = eng.scene.spawn("mushroom_cap")
    eng.scene.set_pos(cap, x, 1.05, z)
    eng.scene.set_mesh(cap, S.cap_mesh, { color = cap_colors[((color_idx - 1) % #cap_colors) + 1], roughness = 0.30, cast_shadow = true })

    S.mushrooms[#S.mushrooms + 1] = { stalk = stalk, cap = cap, x = x, z = z, hp = 3, alive = true }
end

local function spawn_serpent_wave(wave_idx)
    S.wave = wave_idx
    S.segs = {}
    local count = (wave_idx == 1) and 6 or 7
    S.segments_alive = count
    local base_seed = S.seed_base + wave_idx * 197
    for i = 1, count do
        local sx = -1.5 - (i - 1) * 1.25
        local sz = -13.2
        local se = eng.scene.spawn("serpent_seg_" .. wave_idx .. "_" .. i)
        eng.scene.set_pos(se, sx, 0.0, sz)
        eng.scene.set_scale(se, 0.72, 0.72, 0.72)
        eng.scene.set_rot_deg(se, 0.0, -90.0, 0.0)
        eng.procgen.animal(se, base_seed + i * 17, "serpentine")
        S.serpent_segments_spawned = S.serpent_segments_spawned + 1
        S.segs[i] = {
            ent = se, x = sx, z = sz, dir_x = 1.0, drop_rem = 0.0,
            is_head = (i == 1), alive = true
        }
    end
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.04, 0.09, 0.14, 0.12, 0.26, 0.22)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.9, 1.95, 1.75}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.0, -5.0}, color = {1.4, 2.2, 1.6}, range = 30.0 })

    S.seed_base = math.floor(eng.math.range(50, 60000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cap_mesh = eng.asset.cylinder(0.58, 0.14, 0.40, 14)
    S.bolt_mesh = eng.asset.cylinder(0.09, 0.09, 0.65, 8)
    S.ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.moss_tex = eng.procgen.texture("grass", S.seed_base, 64)

    -- Procedural L-system mushroom stalks (`eng.procgen.tree`)
    S.shroom_trees = {
        eng.procgen.tree(S.seed_base + 5, 1, 1.15, 0.24),
        eng.procgen.tree(S.seed_base + 19, 1, 1.25, 0.26),
        eng.procgen.tree(S.seed_base + 37, 1, 1.10, 0.22)
    }

    S.sfx_pew = eng.audio.synth("square", 680, 0.05, 310)
    S.sfx_hit = eng.audio.synth("noise", 360, 0.09, 120)
    S.sfx_split = eng.audio.synth("triangle", 440, 0.13, 820)
    S.sfx_shroom = eng.audio.synth("sine", 320, 0.05, 220)

    -- Bioluminescent Forest Floor
    local flr = eng.scene.spawn("garden_floor")
    eng.scene.set_pos(flr, 0.0, -0.25, -4.5)
    eng.scene.set_scale(flr, 20.0, 0.5, 23.0)
    eng.scene.set_mesh(flr, S.box_mesh, { tex = S.moss_tex, color = {0.26, 0.58, 0.34, 1.0}, roughness = 0.85 })
    eng.physics.add_body(flr, { shape = "aabb", motion = "static", half_extents = {10.0, 0.25, 11.5} })

    -- Scatter 3D Mushroom Patches across garden
    S.mushrooms = {}
    local pts = eng.procgen.scatter_poisson(S.seed_base + 71, 13.5, 9.5, 2.55, 13)
    for i = 1, #pts do
        local mx = pts[i][1] - 6.75
        local mz = pts[i][2] - 11.2
        spawn_mushroom(mx, mz, i)
    end

    -- Player Garden Bug-Blaster
    S.px, S.pz = 0.0, 3.6
    S.ship_ent = eng.scene.spawn("garden_blaster")
    eng.scene.set_pos(S.ship_ent, S.px, 0.55, S.pz)
    eng.scene.set_scale(S.ship_ent, 0.55, 0.65, 0.55)
    eng.scene.set_mesh(S.ship_ent, S.ship_mesh, { color = {0.35, 1.0, 0.62, 1.0}, roughness = 0.25, cast_shadow = true })

    S.bolts = {}
    S.cooldown = 0.0
    S.lives = 3
    S.score = 0
    S.serpent_segments_spawned = 0
    S.segments_blasted = 0
    S.splits_triggered = 0
    S.mushrooms_damaged = 0
    S.mushrooms_cleared = 0
    S.won = false

    spawn_serpent_wave(1)
    eng.camera.look_at(0.0, 15.8, 11.2, 0.0, 0.0, -5.2, 0)
    eng.mod.emit("post_init")
end

local function fire_bolt()
    S.cooldown = 0.085
    local be = eng.scene.spawn("plasma_bolt")
    eng.scene.set_pos(be, S.px, 0.60, S.pz - 0.7)
    eng.scene.set_rot_deg(be, 90.0, 0.0, 0.0)
    eng.scene.set_mesh(be, S.bolt_mesh, { color = {1.0, 0.95, 0.28, 1.0} })
    S.bolts[#S.bolts + 1] = { ent = be, x = S.px, z = S.pz - 0.7, alive = true }
    eng.audio.play(S.sfx_pew, S.px, 0.6, S.pz, 0)
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)

    -- Player movement in bottom blaster zone
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.px = eng.math.clamp(S.px + mx * 13.5 * dt, -8.2, 8.2)
    S.pz = eng.math.clamp(S.pz - my * 8.5 * dt, 1.4, 4.6)
    eng.scene.set_pos(S.ship_ent, S.px, 0.55, S.pz)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        fire_bolt()
    end

    -- Step descending & mushroom-weaving serpent segments
    local seg_spd = 6.6 + (S.wave - 1) * 1.1
    for i = 1, #S.segs do
        local s = S.segs[i]
        if s.alive then
            if s.drop_rem > 0.0 then
                local dz = math.min(s.drop_rem, seg_spd * dt)
                s.z = s.z + dz
                s.drop_rem = s.drop_rem - dz
                eng.scene.set_rot_deg(s.ent, 0.0, 180.0, 0.0)
                if s.z > 4.2 then
                    -- Reached bottom garden: bounce back up a row
                    s.z = 1.6
                    s.drop_rem = 0.0
                end
            else
                s.x = s.x + s.dir_x * seg_spd * dt
                eng.scene.set_rot_deg(s.ent, 0.0, s.dir_x > 0 and -90.0 or 90.0, 0.0)

                local hit_obs = (s.x * s.dir_x >= 7.8)
                if not hit_obs then
                    for m = 1, #S.mushrooms do
                        local sh = S.mushrooms[m]
                        if sh.alive and math.abs(s.z - sh.z) < 0.72 then
                            local ahead = (sh.x - s.x) * s.dir_x
                            if ahead > 0.0 and ahead < 0.92 then
                                hit_obs = true
                                break
                            end
                        end
                    end
                end
                if hit_obs then
                    s.x = eng.math.clamp(s.x, -7.8, 7.8)
                    s.dir_x = -s.dir_x
                    s.drop_rem = 1.45
                end
            end
            eng.scene.set_pos(s.ent, s.x, 0.0, s.z)

            if eng.math.dist3(S.px, 0, S.pz, s.x, 0, s.z) < 0.90 then
                S.lives = math.max(1, S.lives - 1)
                S.px, S.pz = 0.0, 3.8
                eng.scene.set_pos(S.ship_ent, S.px, 0.55, S.pz)
            end
        end
    end

    -- Step plasma bolts vs Serpent Segments & 3D Mushrooms
    for b = #S.bolts, 1, -1 do
        local bl = S.bolts[b]
        bl.z = bl.z - 30.0 * dt
        local consumed = (bl.z < -15.5)

        if not consumed then
            for i = 1, #S.segs do
                local s = S.segs[i]
                if s.alive and eng.math.dist3(bl.x, 0, bl.z, s.x, 0, s.z) < 0.82 then
                    s.alive = false
                    eng.scene.despawn(s.ent)
                    S.segments_alive = S.segments_alive - 1
                    S.segments_blasted = S.segments_blasted + 1
                    S.score = S.score + (s.is_head and 150 or 100)
                    eng.audio.play(S.sfx_hit, s.x, 0.5, s.z, 0)

                    -- Mid-body hit splits trailing serpent & blooms a new 3D mushroom!
                    local nxt = S.segs[i + 1]
                    if nxt and nxt.alive then
                        nxt.is_head = true
                        S.splits_triggered = S.splits_triggered + 1
                        eng.audio.play(S.sfx_split, s.x, 0.6, s.z, 0)
                    end
                    if s.z < 1.0 then
                        spawn_mushroom(s.x, s.z, i + S.wave)
                    end
                    consumed = true
                    break
                end
            end
        end

        if not consumed then
            for m = 1, #S.mushrooms do
                local sh = S.mushrooms[m]
                if sh.alive and eng.math.dist3(bl.x, 0, bl.z, sh.x, 0, sh.z) < 0.66 then
                    sh.hp = sh.hp - 1
                    S.mushrooms_damaged = S.mushrooms_damaged + 1
                    S.score = S.score + 5
                    eng.audio.play(S.sfx_shroom, sh.x, 0.6, sh.z, 0)
                    if sh.hp <= 0 then
                        sh.alive = false
                        eng.scene.despawn(sh.stalk)
                        eng.scene.despawn(sh.cap)
                        S.mushrooms_cleared = S.mushrooms_cleared + 1
                        S.score = S.score + 20
                    else
                        local sc = 0.50 + sh.hp * 0.16
                        eng.scene.set_scale(sh.cap, sc, sc, sc)
                    end
                    consumed = true
                    break
                end
            end
        end

        if consumed then
            eng.scene.despawn(bl.ent)
            table.remove(S.bolts, b)
        else
            eng.scene.set_pos(bl.ent, bl.x, 0.60, bl.z)
        end
    end

    if S.segments_alive <= 0 then
        if S.wave < 2 then
            spawn_serpent_wave(S.wave + 1)
        else
            S.won = true
            S.score = S.score + 500
            eng.save.write("centipede_highscore", tostring(S.score))
        end
    end
end

function draw()
    -- Highlight active serpent heads with glowing spore sprites
    for i = 1, #S.segs do
        local s = S.segs[i]
        if s.alive and s.is_head then
            eng.render.draw_sprite(s.x, 1.05, s.z, 0.42, 0.42, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | WAVE " .. S.wave .. "/2 | SEGS " .. S.segments_alive .. " | SCORE " .. S.score, 1.0, {0.48, 1.0, 0.68, 1.0})
    eng.ui.bar(x, y + 26, 180, S.lives / 3.0, "LIVES ")
end
