-- 043_necromancer_flock: Summon skeletal minion swarm to defeat paladins and convert shrines
local S = game.state

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.018 })
    eng.render.set_sky(0.05, 0.03, 0.12, 0.15, 0.08, 0.22)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.5, 1.4, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.5, -5.0}, color = {1.8, 0.9, 2.6}, range = 30.0 })

    local seed = math.floor(eng.math.range(100, 500000))
    S.seed = seed
    local floor_tex = eng.procgen.texture("cobble", seed, 64)
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_summon = eng.audio.synth("triangle", 220, 0.16, 460)
    S.sfx_convert = eng.audio.synth("sine", 340, 0.25, 760)

    local floor_e = eng.scene.spawn("crypt_courtyard")
    eng.scene.set_pos(floor_e, 0.0, -0.25, -4.0)
    eng.scene.set_scale(floor_e, 28.0, 0.5, 28.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = floor_tex, color = {0.42, 0.38, 0.48, 1.0} })

    for i = -2, 2 do
        local p = eng.scene.spawn("wall_pillar_" .. tostring(i))
        eng.scene.set_pos(p, i * 5.5, 0.0, -15.0)
        eng.scene.set_mesh(p, S.pillar_mesh, { color = {0.5, 0.46, 0.58, 1.0} })
        local pc = eng.scene.spawn("wall_pillar_col_" .. i)
        eng.scene.set_pos(pc, i * 5.5, 1.5, -15.0)
        eng.physics.add_body(pc, { shape = "aabb", motion = "static", half_extents = {0.55, 1.5, 0.55} })
    end

    S.px, S.pz = 0.0, 5.0
    S.necro_ent = eng.scene.spawn("necromancer")
    eng.scene.set_pos(S.necro_ent, S.px, 0.0, S.pz)
    eng.scene.set_mesh(S.necro_ent, S.box_mesh, { color = {0.65, 0.28, 0.95, 1.0} })
    eng.procgen.person(S.necro_ent, seed + 3)

    -- 3 Holy Shrines & 3 Enemy Paladins
    local coords = { {-7.0, -3.5}, {0.0, -9.5}, {7.0, -3.5} }
    S.shrines = {}
    S.paladins = {}
    for i = 1, 3 do
        local sx, sz = coords[i][1], coords[i][2]
        local arch = eng.scene.spawn("shrine_arch_" .. i)
        eng.scene.set_pos(arch, sx, 0.0, sz)
        eng.scene.set_mesh(arch, S.arch_mesh, { color = {0.82, 0.78, 0.65, 1.0} })

        local gem = eng.scene.spawn("shrine_gem_" .. i)
        eng.scene.set_pos(gem, sx, 0.8, sz)
        eng.scene.set_mesh(gem, S.crystal_mesh, { color = {1.0, 0.88, 0.30, 1.0} })
        S.shrines[i] = { x = sx, z = sz, gem = gem, progress = 0.0, converted = false }

        local px, pz = sx, sz + 2.2
        local pe = eng.scene.spawn("paladin_" .. i)
        eng.scene.set_pos(pe, px, 0.0, pz)
        eng.scene.set_mesh(pe, S.box_mesh, { color = {1.0, 0.85, 0.35, 1.0} })
        eng.procgen.person(pe, seed + 30 + i * 17)
        S.paladins[i] = { ent = pe, x = px, z = pz, shrine_idx = i, hp = 32.0, alive = true }
    end

    S.minions = {}
    S.mana = 100.0
    S.summon_cd = 0.0
    S.summoned_total = 0
    S.paladins_slain = 0
    S.shrines_converted = 0
    S.won = false

    eng.camera.look_at(0.0, 11.5, 13.5, 0.0, 0.8, -3.5, 0)
    eng.mod.emit("post_init")
end

local function active_minion_count()
    local n = 0
    for i = 1, #S.minions do if S.minions[i].alive then n = n + 1 end end
    return n
end

local function summon_skeleton()
    if S.mana < 18.0 or active_minion_count() >= 9 then return end
    S.mana = S.mana - 18.0
    S.summoned_total = S.summoned_total + 1
    local ang = S.summoned_total * 1.9
    local mx = S.px + math.cos(ang) * 1.3
    local mz = S.pz + math.sin(ang) * 1.3
    local me = eng.scene.spawn("skeleton_minion_" .. S.summoned_total)
    eng.scene.set_pos(me, mx, 0.0, mz)
    eng.scene.set_scale(me, 0.85, 0.85, 0.85)
    eng.scene.set_mesh(me, S.box_mesh, { color = {0.72, 1.0, 0.82, 1.0} })
    eng.procgen.person(me, S.seed + 100 + S.summoned_total)
    eng.audio.play(S.sfx_summon, mx, 1.0, mz, 0)
    S.minions[#S.minions + 1] = { ent = me, x = mx, z = mz, hp = 18.0, alive = true }
end

local function pick_swarm_target(mx, mz)
    local best_d = 999.0
    local tx, tz, pal = S.px, S.pz - 2.0, nil
    for i = 1, #S.paladins do
        local p = S.paladins[i]
        if p.alive then
            local d = eng.math.dist3(mx, 0, mz, p.x, 0, p.z)
            if d < best_d then best_d = d; tx, tz = p.x, p.z; pal = p end
        end
    end
    if pal then return tx, tz, pal end
    for i = 1, #S.shrines do
        local sh = S.shrines[i]
        if not sh.converted then
            local d = eng.math.dist3(mx, 0, mz, sh.x, 0, sh.z)
            if d < best_d then best_d = d; tx, tz = sh.x, sh.z end
        end
    end
    return tx, tz, nil
end

function update(dt)
    if S.won then return end
    S.mana = math.min(100.0, S.mana + 30.0 * dt)
    S.summon_cd = math.max(0.0, S.summon_cd - dt)

    local ix, iy = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(ix) > 0.01 or math.abs(iy) > 0.01 then
        local nx, nz = eng.physics.slide_move(0, S.px, 0.9, S.pz, ix * 6.5 * dt, -iy * 6.5 * dt, 0.40)
        S.px = eng.math.clamp(nx, -11.5, 11.5)
        S.pz = eng.math.clamp(nz, -12.5, 9.5)
        eng.scene.set_pos(S.necro_ent, S.px, 0.0, S.pz)
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.summon_cd <= 0.0 then
        S.summon_cd = 0.14
        summon_skeleton()
    end

    -- Boids Swarm AI for skeletal minions (separation + target seek + swarm DPS)
    for i = 1, #S.minions do
        local m = S.minions[i]
        if m.alive then
            local tx, tz, pal = pick_swarm_target(m.x, m.z)
            local sx, sz = 0.0, 0.0
            for j = 1, #S.minions do
                if i ~= j and S.minions[j].alive then
                    local ox, oz = m.x - S.minions[j].x, m.z - S.minions[j].z
                    local od = math.sqrt(ox * ox + oz * oz)
                    if od > 0.01 and od < 1.1 then
                        sx = sx + (ox / od) * 1.6
                        sz = sz + (oz / od) * 1.6
                    end
                end
            end
            local dx, dz = (tx - m.x) + sx, (tz - m.z) + sz
            local dl = math.sqrt(dx * dx + dz * dz)
            if dl > 0.25 then
                m.x = m.x + (dx / dl) * 5.8 * dt
                m.z = m.z + (dz / dl) * 5.8 * dt
                eng.scene.set_pos(m.ent, m.x, 0.0, m.z)
                eng.scene.set_rot_deg(m.ent, 0.0, math.deg(math.atan2(-dx, -dz)), 0.0)
            end
            if pal and eng.math.dist3(m.x, 0, m.z, pal.x, 0, pal.z) < 2.0 then
                pal.hp = pal.hp - 22.0 * dt
                m.hp = m.hp - 3.0 * dt
                if m.hp <= 0.0 then
                    m.alive = false
                    eng.scene.despawn(m.ent)
                end
                if pal.hp <= 0.0 and pal.alive then
                    pal.alive = false
                    S.paladins_slain = S.paladins_slain + 1
                    S.mana = math.min(100.0, S.mana + 40.0)
                    eng.scene.despawn(pal.ent)
                end
            end
        end
    end

    -- Shrine conversion when guarding paladin has fallen and flock surrounds shrine
    for i = 1, #S.shrines do
        local sh = S.shrines[i]
        if not sh.converted and not S.paladins[i].alive then
            local flock_near = 0
            for j = 1, #S.minions do
                local m = S.minions[j]
                if m.alive and eng.math.dist3(m.x, 0, m.z, sh.x, 0, sh.z) < 3.4 then
                    flock_near = flock_near + 1
                end
            end
            if flock_near >= 1 then
                sh.progress = math.min(1.0, sh.progress + (0.55 + flock_near * 0.25) * dt)
                if sh.progress >= 1.0 then
                    sh.converted = true
                    S.shrines_converted = S.shrines_converted + 1
                    eng.scene.set_mesh(sh.gem, S.crystal_mesh, { color = {0.75, 0.22, 1.0, 1.0} })
                    eng.audio.play(S.sfx_convert, sh.x, 1.2, sh.z, 0)
                end
            end
        end
    end

    if S.shrines_converted >= 3 then
        S.won = true
        eng.save.write("necro_flock", "dominion")
    end

    eng.camera.look_at(S.px * 0.35, 11.5, 13.5, S.px * 0.25, 0.8, -3.5, 0)
end

function draw()
    for i = 1, #S.minions do
        local m = S.minions[i]
        if m.alive then eng.render.draw_sprite(m.x, 1.85, m.z, 0.35, 0.35, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | FLOCK " .. active_minion_count() .. " | SHRINES " .. S.shrines_converted .. "/3", 1.0, {0.82, 0.55, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.mana / 100.0, "MANA ")
end
