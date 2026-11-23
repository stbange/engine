-- 012_rail_harrier: Space Harrier-style high-speed 3D rail shooter over scrolling checker plains
local S = game.state

local function pillar_lane_x(idx, seed)
    return eng.procgen.noise2d(idx * 0.73, 1.37, seed) * 9.5
end

local function spawn_squadron_member(idx)
    local bx = ((idx % 4) - 1.5) * 3.4
    local by = 2.0 + (idx % 3) * 1.4
    local bz = -22.0 - (idx % 5) * 6.5
    local e = eng.scene.spawn("squad_foe_" .. tostring(idx))
    eng.scene.set_pos(e, bx, by, bz)
    eng.scene.set_scale(e, 0.65, 0.65, 0.65)
    eng.scene.set_rot_deg(e, 0.0, 180.0, 0.0)
    eng.scene.set_mesh(e, S.fighter_mesh, { color = {1.0, 0.35, 0.65, 1.0}, metallic = 0.5, roughness = 0.3, cast_shadow = true })
    return { ent = e, base_x = bx, base_y = by, x = bx, y = by, z = bz, phase = idx * 1.1, hp = 1, alive = true, shot_t = 0.8 + (idx % 3) * 0.5 }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.016 })
    eng.render.set_sky(0.22, 0.36, 0.90, 0.96, 0.54, 0.74)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.35}, color = {2.3, 2.1, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.0, -10.0}, color = {2.0, 1.2, 2.2}, range = 45.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.bolt_mesh = eng.asset.sphere(0.24, 6, 8)
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.fighter_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.checker_tex = eng.asset.load_texture("assets/shared/textures/checker.png", true)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_shot = eng.audio.synth("square", 680, 0.07, 260)
    S.sfx_homing = eng.audio.synth("triangle", 420, 0.14, 960)
    S.sfx_hit = eng.audio.synth("noise", 260, 0.14, 70)
    S.sfx_roll = eng.audio.synth("sine", 340, 0.12, 680)

    -- 3 leapfrogging checkerboard ground slabs for high-speed horizon scroll
    S.slabs = {}
    for i = 1, 3 do
        local sz = 10.0 - (i - 1) * 26.0
        local se = eng.scene.spawn("checker_slab_" .. tostring(i))
        eng.scene.set_pos(se, 0.0, -0.25, sz)
        eng.scene.set_scale(se, 28.0, 0.5, 26.0)
        eng.scene.set_mesh(se, S.box_mesh, { tex = S.checker_tex, color = {0.42, 0.92, 0.58, 1.0}, roughness = 0.8 })
        S.slabs[i] = { ent = se, z = sz }
    end

    S.px, S.py = 0.0, 2.6
    S.hp = 100
    S.score = 0
    S.kills = 0
    S.dist = 0.0
    S.pillars_dodged = 0
    S.barrel_rolls = 0
    S.roll_timer = 0.0
    S.fire_cd = 0.0
    S.homing_cd = 0.0
    S.won = false
    S.lost = false
    S.bolts = {}
    S.enemy_orbs = {}

    S.player_ent = eng.scene.spawn("harrier_jet")
    eng.scene.set_pos(S.player_ent, S.px, S.py, 0.0)
    eng.scene.set_scale(S.player_ent, 0.55, 0.55, 0.55)
    eng.scene.set_mesh(S.player_ent, S.fighter_mesh, { color = {0.25, 0.85, 1.0, 1.0}, metallic = 0.6, roughness = 0.25, cast_shadow = true })

    S.pillar_seq = 6
    S.pillars = {}
    for i = 1, 6 do
        local lx = pillar_lane_x(i, S.seed)
        local lz = -10.0 - (i - 1) * 8.5
        local pe = eng.scene.spawn("rail_pillar_" .. tostring(i))
        eng.scene.set_pos(pe, lx, 0.0, lz)
        eng.scene.set_scale(pe, 1.25, 2.2, 1.25)
        eng.scene.set_mesh(pe, S.pillar_mesh, { color = {0.92, 0.84, 0.72, 1.0}, cast_shadow = true })
        S.pillars[i] = { ent = pe, x = lx, z = lz, scored = false }
    end

    S.spawned_foes = 6
    S.foes = {}
    for i = 1, 6 do
        S.foes[i] = spawn_squadron_member(i)
    end

    eng.camera.look_at(0.0, 4.4, 7.2, 0.0, 2.2, -18.0, 0)
    eng.mod.emit("post_init")
end

local function fire_bolt(homing_target)
    local be = eng.scene.spawn("photon_bolt")
    eng.scene.set_pos(be, S.px, S.py, -1.0)
    local col = homing_target and {1.0, 0.95, 0.25, 1.0} or {0.3, 1.0, 0.95, 1.0}
    eng.scene.set_mesh(be, S.bolt_mesh, { color = col })
    S.bolts[#S.bolts + 1] = {
        ent = be, x = S.px, y = S.py, z = -1.0,
        vx = 0.0, vy = 0.0, vz = -64.0, target = homing_target, life = 1.1
    }
end

function update(dt)
    if S.won or S.lost then return end
    S.fire_cd = math.max(0.0, S.fire_cd - dt)
    S.homing_cd = math.max(0.0, S.homing_cd - dt)
    S.roll_timer = math.max(0.0, S.roll_timer - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local move_spd = (S.roll_timer > 0.0) and 18.0 or 13.5
    S.px = eng.math.clamp(S.px + mx * move_spd * dt, -7.8, 7.8)
    S.py = eng.math.clamp(S.py + my * 11.5 * dt, 1.0, 6.2)

    if eng.input.pressed("jump") and S.roll_timer <= 0.0 then
        S.roll_timer = 0.42
        S.barrel_rolls = S.barrel_rolls + 1
        eng.audio.play(S.sfx_roll, S.px, S.py, 0.0, 0)
    end

    local roll_deg = (S.roll_timer > 0.0) and (S.roll_timer / 0.42 * 360.0) or (-mx * 26.0)
    eng.scene.set_pos(S.player_ent, S.px, S.py, 0.0)
    eng.scene.set_rot_deg(S.player_ent, my * 14.0, 0.0, roll_deg)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.fire_cd <= 0.0 then
        S.fire_cd = 0.11
        eng.audio.play(S.sfx_shot, S.px, S.py, 0.0, 0)
        fire_bolt(nil)
    end

    if (eng.input.pressed("interact") or eng.input.down("interact")) and S.homing_cd <= 0.0 then
        S.homing_cd = 0.9
        eng.audio.play(S.sfx_homing, S.px, S.py, 0.0, 0)
        for i = 1, #S.foes do
            if S.foes[i].alive then
                fire_bolt(S.foes[i])
                break
            end
        end
    end

    local rail_spd = 28.0
    S.dist = S.dist + rail_spd * dt

    -- Scroll checker floor slabs
    for i = 1, #S.slabs do
        local sl = S.slabs[i]
        sl.z = sl.z + rail_spd * dt
        if sl.z > 24.0 then sl.z = sl.z - 78.0 end
        eng.scene.set_pos(sl.ent, 0.0, -0.25, sl.z)
    end

    -- Stream procedural stone pillars
    for i = 1, #S.pillars do
        local p = S.pillars[i]
        p.z = p.z + rail_spd * dt
        if not p.scored and math.abs(p.z) < 0.9 then
            p.scored = true
            if math.abs(S.px - p.x) < 1.15 and S.py < 6.4 and S.roll_timer <= 0.0 then
                S.hp = math.max(0, S.hp - 25)
                eng.audio.play(S.sfx_hit, S.px, S.py, 0.0, 0)
                if S.hp <= 0 then S.lost = true end
            else
                S.pillars_dodged = S.pillars_dodged + 1
                S.score = S.score + 40
            end
        end
        if p.z > 6.5 then
            S.pillar_seq = S.pillar_seq + 1
            p.x = pillar_lane_x(S.pillar_seq, S.seed)
            p.z = p.z - 51.0
            p.scored = false
        end
        eng.scene.set_pos(p.ent, p.x, 0.0, p.z)
    end

    -- Update flying squadron fighters & spawn waves up to 12 total
    for i = 1, #S.foes do
        local fn = S.foes[i]
        if fn.alive then
            fn.phase = fn.phase + dt * 2.8
            fn.z = fn.z + 9.5 * dt
            fn.x = eng.math.clamp(fn.base_x + math.sin(fn.phase) * 2.4, -7.2, 7.2)
            fn.y = eng.math.clamp(fn.base_y + math.cos(fn.phase * 1.3) * 1.1, 1.3, 5.8)
            eng.scene.set_pos(fn.ent, fn.x, fn.y, fn.z)

            fn.shot_t = fn.shot_t - dt
            if fn.shot_t <= 0.0 and fn.z < -8.0 then
                fn.shot_t = 1.6
                local dx, dy, dz = S.px - fn.x, S.py - fn.y, 0.0 - fn.z
                local len = math.max(0.01, math.sqrt(dx * dx + dy * dy + dz * dz))
                S.enemy_orbs[#S.enemy_orbs + 1] = {
                    x = fn.x, y = fn.y, z = fn.z,
                    vx = (dx / len) * 22.0, vy = (dy / len) * 22.0, vz = (dz / len) * 22.0
                }
            end

            if fn.z > 3.5 then
                fn.z = -44.0
            end
        elseif S.spawned_foes < 12 then
            S.spawned_foes = S.spawned_foes + 1
            S.foes[i] = spawn_squadron_member(S.spawned_foes)
        end
    end

    -- Step player photon bolts & homing micro-missiles
    for i = #S.bolts, 1, -1 do
        local b = S.bolts[i]
        b.life = b.life - dt
        if b.target and b.target.alive then
            local dx, dy, dz = b.target.x - b.x, b.target.y - b.y, b.target.z - b.z
            local len = math.max(0.01, math.sqrt(dx * dx + dy * dy + dz * dz))
            b.vx, b.vy, b.vz = (dx / len) * 58.0, (dy / len) * 58.0, (dz / len) * 58.0
        end
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.z = b.z + b.vz * dt
        eng.scene.set_pos(b.ent, b.x, b.y, b.z)

        local dead = (b.life <= 0.0 or b.z < -60.0)
        if not dead then
            for j = 1, #S.foes do
                local fn = S.foes[j]
                if fn.alive and eng.math.dist3(b.x, b.y, b.z, fn.x, fn.y, fn.z) < 1.85 then
                    dead = true
                    fn.alive = false
                    eng.scene.despawn(fn.ent)
                    S.kills = S.kills + 1
                    S.score = S.score + 200
                    eng.audio.play(S.sfx_hit, fn.x, fn.y, fn.z, 0)
                    break
                end
            end
        end
        if dead then
            eng.scene.despawn(b.ent)
            table.remove(S.bolts, i)
        end
    end

    -- Step enemy plasma sprite orbs
    for i = #S.enemy_orbs, 1, -1 do
        local ob = S.enemy_orbs[i]
        ob.x = ob.x + ob.vx * dt
        ob.y = ob.y + ob.vy * dt
        ob.z = ob.z + ob.vz * dt
        if eng.math.dist3(ob.x, ob.y, ob.z, S.px, S.py, 0.0) < 0.95 and S.roll_timer <= 0.0 then
            S.hp = math.max(0, S.hp - 15)
            table.remove(S.enemy_orbs, i)
            if S.hp <= 0 then S.lost = true end
        elseif ob.z > 4.0 then
            table.remove(S.enemy_orbs, i)
        end
    end

    if S.kills >= 8 and S.dist >= 110.0 then
        S.won = true
        S.score = S.score + 500
        eng.save.write("rail_harrier_clear", tostring(S.score))
    end

    eng.camera.look_at(S.px * 0.45, S.py * 0.35 + 3.4, 7.2, S.px * 0.65, S.py * 0.5 + 1.4, -18.0, 0)
end

function draw()
    for i = 1, #S.foes do
        local fn = S.foes[i]
        if fn.alive then eng.render.draw_sprite(fn.x, fn.y + 0.75, fn.z, 0.9, 0.9, S.orb_tex) end
    end
    for i = 1, #S.enemy_orbs do
        local ob = S.enemy_orbs[i]
        eng.render.draw_sprite(ob.x, ob.y, ob.z, 0.65, 0.65, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 60, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | SQUADRON " .. S.kills .. "/8 | DIST " .. math.floor(S.dist) .. "m | SCORE " .. S.score))
    eng.ui.label(x, y, msg, 1.0, {1.0, 0.92, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 220, S.hp / 100.0, "SHIELD ")
end
