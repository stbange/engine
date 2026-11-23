-- 046_relic_hunter_traps: Swinging Pendulums, Poison Dart Traps & Rolling Boulder Escape
local S = game.state

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.016 })
    eng.render.set_sky(0.10, 0.08, 0.05, 0.32, 0.22, 0.12)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {2.0, 1.8, 1.45}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.5, 0.0}, color = {2.6, 1.7, 0.8}, range = 28.0 })
    eng.render.add_light({ type = "point", pos = {0.0, 4.0, -11.0}, color = {2.8, 2.2, 0.7}, range = 18.0 })

    local seed = math.floor(eng.math.range(100, 600000))
    local stone_tex = eng.procgen.texture("stone_brick", seed, 64)
    local rock_tex = eng.procgen.texture("cobble", seed + 13, 64)
    S.rock_tex = rock_tex

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.boulder_mesh = eng.asset.sphere(1.45, 14, 18)
    S.cyl_mesh = eng.asset.cylinder(0.12, 0.12, 1.0, 10)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_idol = eng.audio.synth("triangle", 440, 0.22, 880)
    S.sfx_rumble = eng.audio.synth("noise", 110, 0.35, 65)
    S.sfx_jump = eng.audio.synth("sine", 300, 0.10, 520)

    -- Temple corridor floor & flanking columns
    local floor_e = eng.scene.spawn("temple_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, -1.0)
    eng.scene.set_scale(floor_e, 8.0, 0.5, 34.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = stone_tex, color = {0.66, 0.58, 0.44, 1.0} })

    for z = -12, 12, 4 do
        for side = -1, 1, 2 do
            local pe = eng.scene.spawn("temple_col_" .. z .. "_" .. side)
            eng.scene.set_pos(pe, side * 3.6, 0.0, z)
            eng.scene.set_scale(pe, 0.9, 1.25, 0.9)
            eng.scene.set_mesh(pe, S.pillar_mesh, { tex = stone_tex, color = {0.74, 0.65, 0.50, 1.0} })
        end
    end

    local exit_arch = eng.scene.spawn("escape_arch")
    eng.scene.set_pos(exit_arch, 0.0, 0.0, 11.2)
    eng.scene.set_scale(exit_arch, 1.3, 1.2, 1.2)
    eng.scene.set_mesh(exit_arch, S.arch_mesh, { color = {0.55, 0.92, 0.68, 1.0} })

    -- Golden Idol Pedestal at z = -11.0
    local ped = eng.scene.spawn("idol_pedestal")
    eng.scene.set_pos(ped, 0.0, 0.45, -11.0)
    eng.scene.set_scale(ped, 1.1, 0.9, 1.1)
    eng.scene.set_mesh(ped, S.box_mesh, { tex = stone_tex, color = {0.8, 0.72, 0.55, 1.0} })

    S.idol_ent = eng.scene.spawn("golden_idol")
    eng.scene.set_pos(S.idol_ent, 0.0, 0.95, -11.0)
    eng.scene.set_mesh(S.idol_ent, S.crystal_mesh, { color = {1.0, 0.85, 0.15, 1.0}, metallic = 0.85, roughness = 0.2 })

    -- 3 Swinging Pendulum Axes
    local pzs = { 5.0, 0.0, -5.0 }
    S.pendulums = {}
    for i = 1, #pzs do
        local pivot = eng.scene.spawn("pend_pivot_" .. i)
        eng.scene.set_pos(pivot, 0.0, 4.1, pzs[i])

        local arm = eng.scene.spawn("pend_arm_" .. i)
        eng.scene.set_parent(arm, pivot)
        eng.scene.set_pos(arm, 0.0, -1.6, 0.0)
        eng.scene.set_scale(arm, 1.0, 3.1, 1.0)
        eng.scene.set_mesh(arm, S.cyl_mesh, { color = {0.45, 0.42, 0.38, 1.0} })

        local blade = eng.scene.spawn("pend_blade_" .. i)
        eng.scene.set_parent(blade, pivot)
        eng.scene.set_pos(blade, 0.0, -3.2, 0.0)
        eng.scene.set_scale(blade, 1.35, 0.65, 0.18)
        eng.scene.set_mesh(blade, S.box_mesh, { color = {0.82, 0.85, 0.90, 1.0}, metallic = 0.9, roughness = 0.25 })

        S.pendulums[i] = { pivot = pivot, z = pzs[i], phase = i * 1.35, blade_x = 0.0 }
    end

    -- 2 Poison Wall Dart Traps
    local dzs = { 2.5, -2.5 }
    S.darts = {}
    for i = 1, #dzs do
        local de = eng.scene.spawn("poison_dart_" .. i)
        local start_x = -3.4 + (i - 1) * 3.2
        eng.scene.set_pos(de, start_x, 0.62, dzs[i])
        eng.scene.set_rot_deg(de, 0.0, 0.0, 90.0)
        eng.scene.set_scale(de, 0.5, 0.7, 0.5)
        eng.scene.set_mesh(de, S.cyl_mesh, { color = {0.35, 1.0, 0.35, 1.0} })
        S.darts[i] = { ent = de, x = start_x, z = dzs[i], speed = 7.5 }
    end

    -- Relic Hunter Hero
    S.px, S.py, S.pz = 0.0, 0.0, 10.5
    S.vy = 0.0
    S.hero_ent = eng.scene.spawn("relic_hunter")
    eng.scene.set_pos(S.hero_ent, S.px, S.py, S.pz)
    eng.procgen.person(S.hero_ent, seed + 21)

    S.time = 0.0
    S.hp = 100
    S.hit_cd = 0.0
    S.jumps = 0
    S.has_idol = false
    S.boulder_spawned = false
    S.boulder_ent = nil
    S.boulder_z = -16.5
    S.won = false

    eng.camera.look_at(S.px, 5.2, S.pz + 5.8, S.px, 1.1, S.pz - 5.0, 0)
    eng.mod.emit("post_init")
end

local function trigger_boulder()
    S.has_idol = true
    S.boulder_spawned = true
    eng.scene.despawn(S.idol_ent)
    eng.audio.play(S.sfx_idol, S.px, 1.2, S.pz, 0)
    eng.audio.play(S.sfx_rumble, 0.0, 1.5, -15.0, 0)

    S.boulder_z = -16.2
    S.boulder_ent = eng.scene.spawn("rolling_boulder")
    eng.scene.set_pos(S.boulder_ent, 0.0, 1.45, S.boulder_z)
    eng.scene.set_mesh(S.boulder_ent, S.boulder_mesh, { tex = S.rock_tex, color = {0.62, 0.56, 0.48, 1.0}, cast_shadow = true })
end

function update(dt)
    if S.won then return end
    S.time = S.time + dt
    S.hit_cd = math.max(0.0, S.hit_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.px = eng.math.clamp(S.px + mx * 8.5 * dt, -2.9, 2.9)
        S.pz = eng.math.clamp(S.pz - my * 11.8 * dt, -12.0, 11.5)
        eng.scene.set_rot_deg(S.hero_ent, 0.0, math.deg(math.atan2(-mx, my)), 0.0)
    end

    if eng.input.pressed("jump") and S.py <= 0.02 then
        S.vy = 6.2
        S.jumps = S.jumps + 1
        eng.audio.play(S.sfx_jump, S.px, 1.0, S.pz, 0)
    end
    S.vy = S.vy - 17.5 * dt
    S.py = math.max(0.0, S.py + S.vy * dt)
    if S.py <= 0.0 then S.vy = 0.0 end
    eng.scene.set_pos(S.hero_ent, S.px, S.py, S.pz)

    -- Update Swinging Pendulums
    for i = 1, #S.pendulums do
        local p = S.pendulums[i]
        local ang = math.sin(S.time * 3.1 + p.phase) * 48.0
        eng.scene.set_rot_deg(p.pivot, 0.0, 0.0, ang)
        p.blade_x = math.sin(math.rad(ang)) * 3.2
        if S.hit_cd <= 0.0 and math.abs(S.pz - p.z) < 0.55 and math.abs(S.px - p.blade_x) < 0.75 then
            S.hp = math.max(15, S.hp - 15)
            S.hit_cd = 0.45
        end
    end

    -- Update Poison Wall Darts (jumpable!)
    for i = 1, #S.darts do
        local d = S.darts[i]
        d.x = d.x + d.speed * dt
        if d.x > 3.5 then d.x = -3.5 end
        eng.scene.set_pos(d.ent, d.x, 0.62, d.z)
        if S.hit_cd <= 0.0 and S.py < 0.75 and math.abs(S.pz - d.z) < 0.45 and math.abs(S.px - d.x) < 0.55 then
            S.hp = math.max(15, S.hp - 12)
            S.hit_cd = 0.45
        end
    end

    -- Grab Golden Idol -> Trigger Rolling Boulder!
    if not S.has_idol and eng.math.dist3(S.px, 0, S.pz, 0.0, 0, -11.0) < 1.8 then
        trigger_boulder()
    end

    if S.boulder_spawned and S.boulder_ent then
        S.boulder_z = S.boulder_z + 8.6 * dt
        eng.scene.set_pos(S.boulder_ent, 0.0, 1.45, S.boulder_z)
        eng.scene.set_rot_deg(S.boulder_ent, S.boulder_z * 42.0, 0.0, 0.0)
        if math.abs(S.pz - S.boulder_z) < 1.25 and math.abs(S.px) < 1.35 and S.hit_cd <= 0.0 then
            S.hp = math.max(10, S.hp - 25)
            S.hit_cd = 0.4
        end
    end

    if S.has_idol and S.pz >= 10.6 then
        S.won = true
        eng.save.write("relic_hunter", "idol_secured")
    end

    local cam_z = S.has_idol and (S.pz + 6.2) or (S.pz + 5.8)
    local look_z = S.has_idol and (S.pz - 3.5) or (S.pz - 5.0)
    eng.camera.look_at(S.px * 0.5, 5.2, cam_z, S.px * 0.4, 1.1, look_z, 0)
end

function draw()
    if not S.has_idol then
        eng.render.draw_sprite(0.0, 2.3, -11.0, 0.6, 0.6, S.orb_tex)
    end
    local status = S.has_idol and "BOULDER ESCAPE!" or "GRAB GOLDEN IDOL"
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | " .. status, 1.0, {1.0, 0.86, 0.32, 1.0})
    eng.ui.bar(x, y + 26, 200, S.hp / 100.0, "HP ")
end
