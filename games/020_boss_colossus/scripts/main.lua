-- 020_boss_colossus: Arena duel against a towering eng.procgen.animal quadruped colossus with 3 weak-point crystals
local S = game.state

local WEAK_POINTS_CFG = {
    { name = "left_shoulder_crystal",  ox = -2.1, oy = 2.4, oz = -0.4, col = {0.25, 0.95, 1.0, 1.0} },
    { name = "right_shoulder_crystal", ox =  2.1, oy = 2.4, oz = -0.4, col = {1.0, 0.35, 0.85, 1.0} },
    { name = "crown_spine_crystal",    ox =  0.0, oy = 3.8, oz =  0.5, col = {1.0, 0.88, 0.25, 1.0} },
}

local function sync_weak_points()
    local rad = math.rad(S.byaw)
    local cs, sn = math.cos(rad), math.sin(rad)
    for i = 1, #S.weak_points do
        local wp = S.weak_points[i]
        if wp.intact then
            local wx = S.bx + wp.ox * cs + wp.oz * sn
            local wy = wp.oy
            local wz = S.bz - wp.ox * sn + wp.oz * cs
            wp.wx, wp.wy, wp.wz = wx, wy, wz
            eng.scene.set_pos(wp.ent, wx, wy, wz)
        end
    end
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.010 })
    eng.render.set_sky(0.18, 0.24, 0.34, 0.56, 0.44, 0.32)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.4}, color = {2.2, 2.0, 1.75}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 7.5, -2.0}, color = {1.4, 2.1, 2.6}, range = 34.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(1.0, 1.0, 0.2, 20)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    local stone_tex = eng.procgen.texture("stone_brick", S.seed, 64)

    S.sfx_bow = eng.audio.synth("triangle", 620, 0.08, 980)
    S.sfx_shatter = eng.audio.synth("sine", 740, 0.24, 1380)
    S.sfx_stomp = eng.audio.synth("noise", 160, 0.22, 48)
    S.sfx_dash = eng.audio.synth("square", 380, 0.09, 640)

    -- Ancient ruined colosseum floor + monolith ring
    local floor_e = eng.scene.spawn("colosseum_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 36.0, 0.5, 36.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = stone_tex, color = {0.58, 0.54, 0.48, 1.0} })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {18.0, 0.25, 18.0} })

    for i = 1, 8 do
        local ang = (i - 1) * (math.pi * 0.25)
        local pe = eng.scene.spawn("arena_monolith_" .. tostring(i))
        eng.scene.set_pos(pe, math.cos(ang) * 14.5, 0.0, math.sin(ang) * 14.5)
        eng.scene.set_scale(pe, 1.4, 1.8, 1.4)
        eng.scene.set_mesh(pe, S.pillar_mesh, { tex = stone_tex, color = {0.64, 0.60, 0.54, 1.0}, cast_shadow = true })
    end

    -- Towering Quadruped Colossus (eng.procgen.animal + 4.2x scale!)
    S.bx, S.bz, S.byaw = 0.0, -4.0, 0.0
    S.boss_ent = eng.scene.spawn("quadruped_colossus")
    eng.scene.set_pos(S.boss_ent, S.bx, 0.0, S.bz)
    eng.scene.set_scale(S.boss_ent, 4.2, 4.2, 4.2)
    local binfo = eng.procgen.animal(S.boss_ent, S.seed + 77, "quadruped")
    S.colossus_height = (binfo.height or 1.3) * 4.2

    -- 3 Weak-Point Crystals mounted on the Colossus
    S.weak_points = {}
    for i = 1, #WEAK_POINTS_CFG do
        local wc = WEAK_POINTS_CFG[i]
        local we = eng.scene.spawn(wc.name)
        eng.scene.set_pos(we, S.bx + wc.ox, wc.oy, S.bz + wc.oz)
        eng.scene.set_scale(we, 1.15, 1.15, 1.15)
        eng.scene.set_mesh(we, S.crystal_mesh, { color = wc.col, cast_shadow = true })
        local bid = eng.physics.add_body(we, { shape = "sphere", motion = "kinematic", radius = 0.95, trigger = true })
        S.weak_points[i] = {
            ent = we, body = bid, ox = wc.ox, oy = wc.oy, oz = wc.oz,
            wx = S.bx + wc.ox, wy = wc.oy, wz = S.bz + wc.oz,
            hp = 4, intact = true
        }
    end
    sync_weak_points()

    -- Hunter avatar + Shockwave ring + Arcane bow beam
    S.hunter_ent = eng.scene.spawn("colossus_hunter")
    eng.scene.set_pos(S.hunter_ent, 0.0, 0.0, 6.5)
    eng.procgen.person(S.hunter_ent, S.seed + 19)

    S.ring_ent = eng.scene.spawn("seismic_shockwave")
    eng.scene.set_pos(S.ring_ent, 0.0, -4.0, 0.0)
    eng.scene.set_scale(S.ring_ent, 0.5, 0.2, 0.5)
    eng.scene.set_mesh(S.ring_ent, S.cyl_mesh, { color = {1.0, 0.55, 0.20, 1.0} })

    S.beam_ent = eng.scene.spawn("arcane_lance")
    eng.scene.set_pos(S.beam_ent, 0.0, -5.0, 0.0)
    eng.scene.set_scale(S.beam_ent, 0.12, 0.12, 0.12)
    eng.scene.set_mesh(S.beam_ent, S.box_mesh, { color = {0.45, 1.0, 0.92, 1.0} })
    S.beam_timer = 0.0

    S.px, S.py, S.pz = 0.0, 1.2, 6.5
    S.boss_phase = 0.0
    S.stomp_timer = 1.6
    S.wave_r = 0.0
    S.wave_active = false
    S.fire_cd = 0.0
    S.dodge_cd = 0.0
    S.dodge_iframes = 0.0
    S.dodges = 0
    S.hp = 100
    S.boss_hp = 120
    S.crystals_broken = 0
    S.weak_hits = 0
    S.score = 0
    S.won = false
    S.lost = false

    eng.camera.look_at(S.px, 4.8, S.pz + 6.5, S.bx, 2.4, S.bz, 0)
    eng.mod.emit("post_init")
end

local function fire_arcane_lance()
    local ox, oy, oz = S.px, 1.55, S.pz
    local dx, dy, dz = 0.0, 0.1, -1.0
    local best_d = 32.0
    for i = 1, #S.weak_points do
        local wp = S.weak_points[i]
        if wp.intact then
            local vx, vy, vz = wp.wx - ox, wp.wy - oy, wp.wz - oz
            local d = math.sqrt(vx * vx + vy * vy + vz * vz)
            if d > 0.1 and d < best_d then
                best_d = d
                dx, dy, dz = vx / d, vy / d, vz / d
            end
        end
    end

    eng.audio.play(S.sfx_bow, ox, oy, oz, 0)
    local hit = eng.physics.raycast(0, ox, oy, oz, dx, dy, dz, 34.0)
    local hx, hy, hz = ox + dx * 16.0, oy + dy * 16.0, oz + dz * 16.0
    if hit then
        hx, hy, hz = hit.point[1], hit.point[2], hit.point[3]
        for i = 1, #S.weak_points do
            local wp = S.weak_points[i]
            if wp.intact and wp.ent == hit.entity then
                wp.hp = wp.hp - 1
                S.weak_hits = S.weak_hits + 1
                S.boss_hp = math.max(0, S.boss_hp - 10)
                S.score = S.score + 100
                if wp.hp <= 0 then
                    wp.intact = false
                    eng.scene.despawn(wp.ent)
                    S.crystals_broken = S.crystals_broken + 1
                    S.score = S.score + 300
                    eng.audio.play(S.sfx_shatter, wp.wx, wp.wy, wp.wz, 0)
                end
                break
            end
        end
    end

    eng.scene.set_pos(S.beam_ent, (ox + hx) * 0.5, (oy + hy) * 0.5, (oz + hz) * 0.5)
    eng.scene.set_scale(S.beam_ent, math.max(0.12, math.abs(hx - ox)), math.max(0.12, math.abs(hy - oy)), math.max(0.12, math.abs(hz - oz)))
    S.beam_timer = 0.06
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.dodge_cd = math.max(0.0, S.dodge_cd - dt)
    S.dodge_iframes = math.max(0.0, S.dodge_iframes - dt)

    if S.beam_timer > 0.0 then
        S.beam_timer = S.beam_timer - dt
        if S.beam_timer <= 0.0 then
            eng.scene.set_pos(S.beam_ent, 0.0, -5.0, 0.0)
            eng.scene.set_scale(S.beam_ent, 0.12, 0.12, 0.12)
        end
    end

    -- Hunter movement + dodge roll (jump / interact)
    local ix, iy = eng.input.axis2d("left", "right", "down", "up")
    if (eng.input.pressed("jump") or eng.input.pressed("interact")) and S.dodge_cd <= 0.0 then
        S.dodge_cd = 0.55
        S.dodge_iframes = 0.45
        S.dodges = S.dodges + 1
        eng.audio.play(S.sfx_dash, S.px, 1.0, S.pz, 0)
    end
    local spd = (S.dodge_iframes > 0.0) and 15.0 or 9.5
    S.px = eng.math.clamp(S.px + ix * spd * dt, -12.0, 12.0)
    S.pz = eng.math.clamp(S.pz - iy * spd * dt, -12.0, 12.0)
    eng.scene.set_pos(S.hunter_ent, S.px, 0.0, S.pz)
    eng.scene.set_rot_deg(S.hunter_ent, 0.0, math.deg(math.atan2(-(S.bx - S.px), -(S.bz - S.pz))), 0.0)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
        S.fire_cd = 0.15
        fire_arcane_lance()
    end

    -- Towering Quadruped Colossus figure-8 arena prowl + seismic stomp shockwave
    S.boss_phase = S.boss_phase + 0.9 * dt
    local nx = math.sin(S.boss_phase) * 3.8
    local nz = -3.8 + math.cos(S.boss_phase * 2.0) * 1.6
    S.byaw = math.deg(math.atan2(-(nx - S.bx), -(nz - S.bz)))
    S.bx, S.bz = nx, nz
    eng.scene.set_pos(S.boss_ent, S.bx, 0.0, S.bz)
    eng.scene.set_rot_deg(S.boss_ent, 0.0, S.byaw, 0.0)
    sync_weak_points()

    S.stomp_timer = S.stomp_timer - dt
    if S.stomp_timer <= 0.0 then
        S.stomp_timer = 2.4
        S.wave_active = true
        S.wave_r = 1.0
        S.wave_x, S.wave_z = S.bx, S.bz
        S.wave_hit_player = false
        eng.audio.play(S.sfx_stomp, S.bx, 0.5, S.bz, 0)
    end

    if S.wave_active then
        S.wave_r = S.wave_r + 11.0 * dt
        eng.scene.set_pos(S.ring_ent, S.wave_x, 0.12, S.wave_z)
        eng.scene.set_scale(S.ring_ent, S.wave_r, 0.18, S.wave_r)
        local pd = eng.math.dist3(S.px, 0.0, S.pz, S.wave_x, 0.0, S.wave_z)
        if not S.wave_hit_player and math.abs(pd - S.wave_r) < 0.75 and S.dodge_iframes <= 0.0 then
            S.wave_hit_player = true
            S.hp = math.max(0, S.hp - 20)
        end
        if S.wave_r > 13.0 then
            S.wave_active = false
            eng.scene.set_pos(S.ring_ent, 0.0, -4.0, 0.0)
        end
    end

    if S.hp <= 0 then
        S.lost = true
    elseif S.crystals_broken >= 3 then
        S.won = true
        S.boss_hp = 0
        eng.scene.set_rot_deg(S.boss_ent, 0.0, S.byaw, 85.0)
        eng.save.write("boss_colossus", "clear")
    end

    eng.camera.look_at(S.px, 4.8, S.pz + 6.5, S.bx, 2.4, S.bz, 0)
end

function draw()
    for i = 1, #S.weak_points do
        local wp = S.weak_points[i]
        if wp.intact then eng.render.draw_sprite(wp.wx, wp.wy + 0.85, wp.wz, 0.65, 0.65, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 600, 56, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | CRYSTALS SHATTERED " .. S.crystals_broken .. "/3 | HP " .. S.hp))
    eng.ui.label(x, y, msg, 1.0, {1.0, 0.86, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 220, S.boss_hp / 120.0, "BOSS ")
end
