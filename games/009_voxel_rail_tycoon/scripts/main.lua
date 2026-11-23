-- 009_voxel_rail_tycoon: 4-Stage Voxel Minecart Logistics + Upgradable Crystal Turret Siege Defense
local S = game.state

local PAD_COORDS = {
    { x = 2.2, z = -2.8 },
    { x = 2.2, z =  2.8 },
    { x = 5.8, z = -2.8 },
    { x = 5.8, z =  2.8 },
}

local LEVEL_COLORS = {
    { 0.30, 0.90, 1.00, 1.0 },
    { 0.85, 0.35, 1.00, 1.0 },
    { 1.00, 0.88, 0.25, 1.0 },
}

local function spawn_stage(stage_idx)
    S.stage = stage_idx
    local count = 2 + stage_idx
    for i = 1, count do
        local rx = 10.2 + (i - 1) * 1.35
        local rz = ((i % 3) - 1) * 1.15
        local re = eng.scene.spawn("insectoid_w" .. tostring(stage_idx) .. "_" .. tostring(i))
        eng.scene.set_pos(re, rx, 0.55, rz)
        eng.scene.set_rot_deg(re, 0.0, 90.0, 0.0)
        local info = eng.procgen.animal(re, S.seed + stage_idx * 97 + i * 29, "insectoid")
        local bid = eng.physics.add_body(re, { shape = "sphere", motion = "kinematic", radius = 0.75, trigger = true })
        S.raiders[#S.raiders + 1] = {
            ent = re, body = bid, x = rx, z = rz,
            hp = 2 + stage_idx, max_hp = 2 + stage_idx,
            speed = 2.2 + stage_idx * 0.28,
            height = info.height or 1.0,
            alive = true
        }
        S.insectoids_spawned = S.insectoids_spawned + 1
    end
end

local function update_cursor()
    local p = S.pads[S.sel_pad]
    if p and S.cursor_ent then
        eng.scene.set_pos(S.cursor_ent, p.x, 2.35, p.z)
    end
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 320, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.14, 0.26, 0.48, 0.46, 0.34, 0.26)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.4}, color = {2.2, 2.05, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {-8.8, 4.0, 0.0}, color = {1.2, 2.2, 2.8}, range = 20.0 })
    eng.render.add_light({ type = "point", pos = {-1.2, 4.5, 0.0}, color = {2.6, 1.7, 0.8}, range = 22.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.5, 10, 12)
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local dirt_tex = eng.procgen.texture("cobble", S.seed, 64)
    local metal_tex = eng.procgen.texture("metal_rivets", S.seed + 19, 64)

    S.sfx_deliver = eng.audio.synth("triangle", 520, 0.14, 880)
    S.sfx_build = eng.audio.synth("sine", 440, 0.16, 920)
    S.sfx_zap = eng.audio.synth("square", 680, 0.07, 260)
    S.sfx_hit = eng.audio.synth("noise", 220, 0.15, 70)

    -- Canyon floor
    local floor_e = eng.scene.spawn("canyon_floor")
    eng.scene.set_pos(floor_e, 1.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 32.0, 0.5, 16.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = dirt_tex, color = {0.52, 0.42, 0.34, 1.0} })
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {16.0, 0.25, 8.0} })

    -- Voxel Crystal Minehead (west) & Voxel Refinery Core (center)
    local mine_vox = eng.asset.voxel_ascii({
        "22222\n22222\n22222\n22222\n22222",
        "2...2\n2.3.2\n..3..\n2.3.2\n2...2",
        "22222\n23332\n23332\n23332\n22222"
    }, 5, 3, 5, 0.75)
    local mine_e = eng.scene.spawn("voxel_minehead")
    eng.scene.set_pos(mine_e, -11.2, 0.0, -1.9)
    eng.scene.set_mesh(mine_e, mine_vox, { color = {0.55, 0.78, 0.95, 1.0}, cast_shadow = true })

    local core_vox = eng.asset.voxel_ascii({
        "1111\n1111\n1111\n1111",
        "1..1\n.44.\n.44.\n1..1",
        "1111\n1441\n1441\n1111",
        ".11.\n1441\n1441\n.11."
    }, 4, 4, 4, 0.7)
    local core_e = eng.scene.spawn("voxel_refinery_core")
    eng.scene.set_pos(core_e, -2.4, 0.0, -1.4)
    eng.scene.set_mesh(core_e, core_vox, { color = {0.95, 0.72, 0.35, 1.0}, cast_shadow = true })

    -- Dual steel rail tracks + wooden ties from Minehead (-8.6) to Refinery (-1.8)
    local rail_zs = { -1.8, 1.8 }
    for r = 1, 2 do
        local rz = rail_zs[r]
        for side = -1, 1, 2 do
            local bar = eng.scene.spawn("steel_rail_" .. tostring(r) .. "_" .. tostring(side))
            eng.scene.set_pos(bar, -5.2, 0.06, rz + side * 0.28)
            eng.scene.set_scale(bar, 7.2, 0.08, 0.08)
            eng.scene.set_mesh(bar, S.box_mesh, { tex = metal_tex, color = {0.72, 0.76, 0.82, 1.0} })
        end
    end

    -- 2 Ore Minecarts hauling crystal ore from Minehead to Smelter
    S.carts = {}
    for r = 1, 2 do
        local rz = rail_zs[r]
        local start_x = (r == 1) and -8.2 or -4.8
        local ce = eng.scene.spawn("minecart_" .. tostring(r))
        eng.scene.set_pos(ce, start_x, 0.12, rz)
        eng.scene.set_scale(ce, 0.85, 0.65, 0.75)
        eng.scene.set_mesh(ce, S.crate_mesh, { color = {0.48, 0.36, 0.24, 1.0}, cast_shadow = true })

        local ore_e = eng.scene.spawn("minecart_ore_" .. tostring(r))
        eng.scene.set_pos(ore_e, start_x, 0.72, rz)
        eng.scene.set_scale(ore_e, 0.55, 0.55, 0.55)
        eng.scene.set_mesh(ore_e, S.crystal_mesh, { color = {0.35, 0.92, 1.0, 1.0} })

        S.carts[r] = { ent = ce, ore_ent = ore_e, x = start_x, z = rz, dir = 1.0, loaded = true }
    end

    -- 4 Buildable / Upgradable Turret Socket Pads
    S.pads = {}
    for i = 1, #PAD_COORDS do
        local pc = PAD_COORDS[i]
        local pe = eng.scene.spawn("turret_socket_" .. tostring(i))
        eng.scene.set_pos(pe, pc.x, 0.12, pc.z)
        eng.scene.set_scale(pe, 1.35, 0.24, 1.35)
        eng.scene.set_mesh(pe, S.box_mesh, { tex = metal_tex, color = {0.42, 0.46, 0.54, 1.0} })
        S.pads[i] = { x = pc.x, z = pc.z, pad_ent = pe, base_ent = nil, gem_ent = nil, level = 0, cd = 0.0 }
    end

    S.cursor_ent = eng.scene.spawn("pad_cursor")
    eng.scene.set_scale(S.cursor_ent, 0.42, 0.42, 0.42)
    eng.scene.set_mesh(S.cursor_ent, S.sphere_mesh, { color = {1.0, 0.92, 0.25, 1.0} })

    S.beam_ent = eng.scene.spawn("turret_beam")
    eng.scene.set_pos(S.beam_ent, 0.0, -5.0, 0.0)
    eng.scene.set_scale(S.beam_ent, 0.12, 0.12, 0.12)
    eng.scene.set_mesh(S.beam_ent, S.box_mesh, { color = {0.35, 1.0, 0.92, 1.0} })
    S.beam_timer = 0.0

    S.sel_pad = 1
    S.ore = 60
    S.core_hp = 100
    S.deliveries = 0
    S.turrets_built = 0
    S.upgrades = 0
    S.raycast_shots = 0
    S.kills = 0
    S.insectoids_spawned = 0
    S.score = 0
    S.won = false
    S.lost = false
    S.raiders = {}

    update_cursor()
    spawn_stage(1)
    eng.camera.look_at(0.5, 12.5, 12.5, 0.5, 0.8, 0.0, 0)
    eng.mod.emit("post_init")
end

local function build_or_upgrade_selected()
    local p = S.pads[S.sel_pad]
    if not p or p.level >= 3 then return end
    local cost = (p.level == 0) and 25 or ((p.level == 1) and 35 or 45)
    if S.ore < cost then return end

    S.ore = S.ore - cost
    p.level = p.level + 1
    local col = LEVEL_COLORS[p.level]
    if p.level == 1 then
        S.turrets_built = S.turrets_built + 1
        p.base_ent = eng.scene.spawn("turret_base_" .. tostring(S.sel_pad))
        eng.scene.set_pos(p.base_ent, p.x, 0.24, p.z)
        eng.scene.set_scale(p.base_ent, 0.9, 0.55, 0.9)
        eng.scene.set_mesh(p.base_ent, S.pillar_mesh, { color = {0.62, 0.66, 0.74, 1.0}, cast_shadow = true })

        p.gem_ent = eng.scene.spawn("turret_crystal_" .. tostring(S.sel_pad))
        eng.scene.set_pos(p.gem_ent, p.x, 1.65, p.z)
        eng.scene.set_scale(p.gem_ent, 0.85, 0.85, 0.85)
        eng.scene.set_mesh(p.gem_ent, S.crystal_mesh, { color = col, cast_shadow = true })
    else
        S.upgrades = S.upgrades + 1
        local sc = 0.85 + (p.level - 1) * 0.22
        eng.scene.set_scale(p.gem_ent, sc, sc, sc)
        eng.scene.set_mesh(p.gem_ent, S.crystal_mesh, { color = col, cast_shadow = true })
    end
    eng.audio.play(S.sfx_build, p.x, 1.5, p.z, 0)
end

function update(dt)
    if S.won or S.lost then return end

    if S.beam_timer > 0.0 then
        S.beam_timer = S.beam_timer - dt
        if S.beam_timer <= 0.0 then
            eng.scene.set_pos(S.beam_ent, 0.0, -5.0, 0.0)
            eng.scene.set_scale(S.beam_ent, 0.12, 0.12, 0.12)
        end
    end

    if eng.input.pressed("left") then
        S.sel_pad = ((S.sel_pad - 2) % #S.pads) + 1
        update_cursor()
    elseif eng.input.pressed("right") then
        S.sel_pad = (S.sel_pad % #S.pads) + 1
        update_cursor()
    end
    if eng.input.pressed("fire") or eng.input.pressed("up") then
        build_or_upgrade_selected()
    end

    -- Step minecarts along dual rails (interact boosts rail overdrive!)
    local overdrive = eng.input.down("interact") or eng.input.pressed("interact")
    local cart_spd = overdrive and 13.5 or 8.2
    for i = 1, #S.carts do
        local c = S.carts[i]
        c.x = c.x + c.dir * cart_spd * dt
        if c.x >= -1.8 then
            c.x = -1.8
            c.dir = -1.0
            if c.loaded then
                c.loaded = false
                S.ore = S.ore + 30
                S.deliveries = S.deliveries + 1
                S.score = S.score + 60
                eng.audio.play(S.sfx_deliver, c.x, 0.8, c.z, 0)
            end
        elseif c.x <= -8.5 then
            c.x = -8.5
            c.dir = 1.0
            c.loaded = true
        end
        eng.scene.set_pos(c.ent, c.x, 0.12, c.z)
        eng.scene.set_pos(c.ore_ent, c.x, c.loaded and 0.72 or -3.0, c.z)
    end

    -- Auto-targeting crystal turrets shoot insectoid raiders via raycast
    for i = 1, #S.pads do
        local p = S.pads[i]
        if p.level > 0 then
            p.cd = math.max(0.0, p.cd - dt)
            if p.cd <= 0.0 then
                local best_r = nil
                local best_d = 12.5
                for j = 1, #S.raiders do
                    local r = S.raiders[j]
                    if r.alive then
                        local d = eng.math.dist3(p.x, 0.0, p.z, r.x, 0.0, r.z)
                        if d < best_d then best_d = d; best_r = r end
                    end
                end
                if best_r then
                    p.cd = 0.24 / (0.65 + 0.35 * p.level)
                    local ox, oy, oz = p.x, 1.65, p.z
                    local dx, dy, dz = best_r.x - ox, 0.55 - oy, best_r.z - oz
                    local len = math.max(0.01, math.sqrt(dx * dx + dy * dy + dz * dz))
                    local hit = eng.physics.raycast(0, ox, oy, oz, dx / len, dy / len, dz / len, 15.0)
                    S.raycast_shots = S.raycast_shots + 1

                    local tgt = best_r
                    if hit then
                        for j = 1, #S.raiders do
                            if S.raiders[j].alive and S.raiders[j].ent == hit.entity then
                                tgt = S.raiders[j]
                                break
                            end
                        end
                    end

                    -- Position visible beam pulse
                    eng.scene.set_pos(S.beam_ent, (ox + tgt.x) * 0.5, (oy + 0.55) * 0.5, (oz + tgt.z) * 0.5)
                    eng.scene.set_scale(S.beam_ent, math.max(0.12, math.abs(tgt.x - ox)), 0.12, math.max(0.12, math.abs(tgt.z - oz)))
                    S.beam_timer = 0.06
                    eng.audio.play(S.sfx_zap, ox, oy, oz, 0)

                    tgt.hp = tgt.hp - (1 + p.level)
                    if tgt.hp <= 0 and tgt.alive then
                        tgt.alive = false
                        eng.scene.despawn(tgt.ent)
                        S.kills = S.kills + 1
                        S.ore = S.ore + 14
                        S.score = S.score + 120
                    end
                end
            end
        end
    end

    -- Step living insectoid raiders toward the Refinery Core
    local living = 0
    for i = 1, #S.raiders do
        local r = S.raiders[i]
        if r.alive then
            living = living + 1
            r.x = r.x - r.speed * dt
            eng.scene.set_pos(r.ent, r.x, 0.55, r.z)
            if r.x <= -0.9 then
                r.alive = false
                living = living - 1
                eng.scene.despawn(r.ent)
                S.core_hp = math.max(0, S.core_hp - 20)
                eng.audio.play(S.sfx_hit, -1.0, 1.0, r.z, 0)
            end
        end
    end

    if S.core_hp <= 0 then
        S.lost = true
    elseif living == 0 then
        if S.stage < 4 then
            eng.save.write("voxel_rail_tycoon", "stage_" .. tostring(S.stage + 1))
            spawn_stage(S.stage + 1)
        else
            S.won = true
            S.score = S.score + S.core_hp * 5
            eng.save.write("voxel_rail_tycoon", "clear")
        end
    end
end

function draw()
    for i = 1, #S.raiders do
        local r = S.raiders[i]
        if r.alive then eng.render.draw_sprite(r.x, r.height + 0.85, r.z, 0.5, 0.5, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 620, 56, 1280, 720)
    local msg = S.won and eng.i18n.t("victory") or (S.lost and eng.i18n.t("defeat") or
        (eng.i18n.t("title") .. " | STAGE " .. S.stage .. "/4 | ORE " .. S.ore .. " | DELIVERIES " .. S.deliveries))
    eng.ui.label(x, y, msg, 1.0, {0.55, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.core_hp / 100.0, "CORE ")
end
