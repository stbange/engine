-- 042_rogue_spire_3d: Procedural Spire Climb with DNA Animal Monsters, ATK/DEF Chests & Boss Altar
local S = game.state

local ARCHETYPES = { "quadruped", "insectoid", "biped" }
local STYLES = { "bsp", "wfc", "cave" }

local function clear_floor()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
    S.chests = {}
    S.monsters = {}
end

local function spawn_tracked(name)
    local e = eng.scene.spawn(name)
    S.ents[#S.ents + 1] = e
    return e
end

local function build_floor(fl)
    clear_floor()
    S.floor = fl
    local seed = S.run_seed + fl * 173
    local d = eng.procgen.dungeon(16, 16, seed, STYLES[((fl - 1) % #STYLES) + 1], 2.0, 3.0)
    S.solvable = d.solvable

    local wall_tex = eng.procgen.texture(fl == 3 and "lava_cracks" or "stone_brick", seed, 64)
    local d_ent = spawn_tracked("spire_dungeon_" .. fl)
    eng.scene.set_mesh(d_ent, d.mesh_id, { tex = wall_tex, roughness = 0.8 })

    local floor_e = spawn_tracked("spire_floor_" .. fl)
    eng.scene.set_pos(floor_e, 16.0, -0.2, 16.0)
    eng.scene.set_scale(floor_e, 36.0, 0.4, 36.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = wall_tex, color = {0.5, 0.48, 0.54, 1.0} })
    eng.ai.set_grid(0, 2.0, 16, 16)

    S.px, S.pz = d.start_x, d.start_z
    S.ex, S.ez = d.exit_x, d.exit_z
    -- Ensure start and exit have comfortable separation
    if eng.math.dist3(S.px, 0, S.pz, S.ex, 0, S.ez) < 6.0 then
        S.px, S.pz = 6.0, 24.0
        S.ex, S.ez = 24.0, 8.0
    end

    S.hero_ent = spawn_tracked("spire_hero")
    eng.scene.set_pos(S.hero_ent, S.px, 0.0, S.pz)
    eng.procgen.person(S.hero_ent, S.run_seed + 5)

    -- 2 Upgrade Chests along the spire route: [1] = +ATK, [2] = +DEF
    local kinds = { "atk", "def" }
    for i = 1, 2 do
        local t = 0.25 * i
        local cx = S.px + (S.ex - S.px) * t + (i == 1 and -1.8 or 1.8)
        local cz = S.pz + (S.ez - S.pz) * t
        local ce = spawn_tracked("chest_" .. i)
        eng.scene.set_pos(ce, cx, 0.0, cz)
        local col = (kinds[i] == "atk") and {1.0, 0.45, 0.25, 1.0} or {0.3, 0.75, 1.0, 1.0}
        eng.scene.set_mesh(ce, S.chest_mesh, { color = col, cast_shadow = true })
        S.chests[i] = { ent = ce, x = cx, z = cz, kind = kinds[i], opened = false }
    end

    -- 2 Procedural DNA Animal Monsters + Apex Boss on Floor 3
    local count = (fl == 3) and 3 or 2
    for i = 1, count do
        local is_boss = (fl == 3 and i == 3)
        local t = is_boss and 0.88 or (0.38 + i * 0.20)
        local mx = S.px + (S.ex - S.px) * t + ((i % 2 == 0) and 1.4 or -1.4)
        local mz = S.pz + (S.ez - S.pz) * t
        if is_boss then mx, mz = S.ex, S.ez end
        local me = spawn_tracked(is_boss and "spire_boss" or ("beast_" .. i))
        eng.scene.set_pos(me, mx, 0.0, mz)
        if is_boss then eng.scene.set_scale(me, 1.65, 1.65, 1.65) end
        local arch = ARCHETYPES[((fl + i - 1) % #ARCHETYPES) + 1]
        eng.procgen.animal(me, seed + i * 41, arch)
        S.monsters[i] = {
            ent = me, x = mx, z = mz, boss = is_boss,
            hp = is_boss and 28 or (10 + fl * 3),
            atk = is_boss and 9 or (5 + fl),
            cd = 0.4, alive = true
        }
    end

    -- Exit Stairway (floors 1-2) or Boss Altar (floor 3)
    local altar = spawn_tracked(fl == 3 and "boss_altar" or "spire_stairs")
    eng.scene.set_pos(altar, S.ex, 0.0, S.ez)
    eng.scene.set_mesh(altar, fl == 3 and S.arch_mesh or S.pillar_mesh,
                       { color = fl == 3 and {1.0, 0.3, 0.65, 1.0} or {0.45, 0.9, 1.0, 1.0} })
    if fl == 3 then
        S.altar_gem = spawn_tracked("altar_gem")
        eng.scene.set_pos(S.altar_gem, S.ex, 0.9, S.ez)
        eng.scene.set_mesh(S.altar_gem, S.crystal_mesh, { color = {1.0, 0.85, 0.25, 1.0} })
    end

    eng.camera.look_at(S.px, 6.2, S.pz + 6.8, S.px, 0.8, S.pz - 1.5, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.016 })
    eng.render.set_sky(0.08, 0.05, 0.16, 0.24, 0.12, 0.22)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.1, 1.95, 1.8}, shadow = true })
    eng.render.add_light({ type = "point", pos = {16.0, 6.0, 16.0}, color = {2.2, 1.4, 2.5}, range = 36.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_loot = eng.audio.synth("triangle", 480, 0.16, 880)
    S.sfx_slash = eng.audio.synth("saw", 260, 0.10, 110)

    S.run_seed = math.floor(eng.math.range(200, 800000))
    S.hp = 100
    S.max_hp = 100
    S.atk = 5
    S.def = 1
    S.chests_opened = 0
    S.kills = 0
    S.boss_slain = false
    S.atk_cd = 0.0
    S.won = false

    build_floor(1)
    eng.mod.emit("post_init")
end

local function swing_weapon()
    eng.audio.play(S.sfx_slash, S.px, 1.0, S.pz, 0)
    for i = 1, #S.monsters do
        local m = S.monsters[i]
        if m.alive and eng.math.dist3(S.px, 0, S.pz, m.x, 0, m.z) < 3.2 then
            m.hp = m.hp - S.atk
            if m.hp <= 0 then
                m.alive = false
                if m.boss then S.boss_slain = true end
                S.kills = S.kills + 1
                eng.scene.despawn(m.ent)
            end
        end
    end
end

function update(dt)
    if S.won then return end
    S.atk_cd = math.max(0.0, S.atk_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.px = eng.math.clamp(S.px + mx * 7.5 * dt, 1.5, 30.5)
        S.pz = eng.math.clamp(S.pz - my * 7.5 * dt, 1.5, 30.5)
        eng.scene.set_rot_deg(S.hero_ent, 0.0, math.deg(math.atan2(-mx, my)), 0.0)
    end
    eng.scene.set_pos(S.hero_ent, S.px, 0.0, S.pz)

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.atk_cd <= 0.0 then
        S.atk_cd = 0.18
        swing_weapon()
    end

    -- Loot chests for permanent ATK / DEF upgrades
    for i = 1, #S.chests do
        local c = S.chests[i]
        if not c.opened and eng.math.dist3(S.px, 0, S.pz, c.x, 0, c.z) < 2.2 then
            c.opened = true
            S.chests_opened = S.chests_opened + 1
            if c.kind == "atk" then S.atk = S.atk + 3 else S.def = S.def + 2 end
            eng.audio.play(S.sfx_loot, c.x, 0.8, c.z, 0)
            eng.scene.set_scale(c.ent, 0.8, 0.35, 0.8)
        end
    end

    -- Monster A* pursuit & melee counter-hits mitigated by DEF
    local boss_alive = false
    for i = 1, #S.monsters do
        local m = S.monsters[i]
        if m.alive then
            if m.boss then boss_alive = true end
            m.cd = m.cd - dt
            local dist = eng.math.dist3(S.px, 0, S.pz, m.x, 0, m.z)
            if dist > 1.3 and dist < 18.0 then
                local path = eng.ai.find_path(0, m.x, 0, m.z, 0, S.px, 0, S.pz)
                local tx, tz = S.px, S.pz
                if path and #path >= 2 then tx, tz = path[2][1], path[2][3] end
                local dx, dz = tx - m.x, tz - m.z
                local dl = math.sqrt(dx * dx + dz * dz)
                if dl > 0.05 then
                    m.x = m.x + (dx / dl) * 2.8 * dt
                    m.z = m.z + (dz / dl) * 2.8 * dt
                    eng.scene.set_pos(m.ent, m.x, 0.0, m.z)
                end
            elseif dist <= 1.8 and m.cd <= 0.0 then
                m.cd = 0.65
                local dmg = math.max(1, m.atk - S.def)
                S.hp = math.max(15, S.hp - dmg)
            end
        end
    end

    -- Floor climb or Boss Altar sanctification
    if eng.math.dist3(S.px, 0, S.pz, S.ex, 0, S.ez) < 2.3 then
        if S.floor < 3 then
            build_floor(S.floor + 1)
        elseif not boss_alive then
            S.won = true
            eng.save.write("spire_progress", "altar_sanctified")
        end
    end

    eng.camera.look_at(S.px, 6.2, S.pz + 6.8, S.px, 0.8, S.pz - 1.5, 0)
end

function draw()
    for i = 1, #S.monsters do
        local m = S.monsters[i]
        if m.alive then
            eng.render.draw_sprite(m.x, m.boss and 2.6 or 1.6, m.z, 0.55, 0.55, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | FLOOR " .. S.floor .. "/3 | ATK " .. S.atk .. " DEF " .. S.def .. " | KILLS " .. S.kills, 1.0, {1.0, 0.88, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 200, S.hp / S.max_hp, "HP ")
end
