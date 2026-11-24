-- 001_catacomb_blitz: 3-Stage Retro Boomer FPS (BSP -> Cave -> WFC Catacombs)
local S = game.state

local STYLES = { "bsp", "cave", "wfc" }
local TEX_RECIPES = { "stone_brick", "cobble", "lava_cracks" }

local function clear_entities()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
    S.enemies = {}
end

local function snap_walkable(d, x, z)
    local bx, bz, bd = d.start_x, d.start_z, 1e9
    for gy = 1, d.height do
        for gx = 1, d.width do
            if d.walkable[(gy - 1) * d.width + gx] == 1 then
                local wx, wz = (gx - 0.5) * d.tile_size, (gy - 0.5) * d.tile_size
                local dist = (wx - x) * (wx - x) + (wz - z) * (wz - z)
                if dist < bd then bd, bx, bz = dist, wx, wz end
            end
        end
    end
    return bx, bz
end

local function build_stage(stage_idx)
    clear_entities()
    S.stage = stage_idx
    local seed_base = math.floor(eng.math.range(100, 900000)) + stage_idx * 131
    local style = STYLES[((stage_idx - 1) % #STYLES) + 1]
    local d = eng.procgen.dungeon(18, 18, seed_base, style, 2.0, 3.2)
    S.solvable = d.solvable

    local d_ent = eng.scene.spawn("catacomb_stage_" .. tostring(stage_idx))
    local tex = eng.procgen.texture(TEX_RECIPES[((stage_idx - 1) % #TEX_RECIPES) + 1], seed_base, 64)
    eng.scene.set_mesh(d_ent, d.mesh_id, { tex = tex, roughness = 0.85 })
    eng.physics.add_body(d_ent, { shape = "voxel", motion = "static", voxel_id = d.voxel_id })
    S.ents[#S.ents + 1] = d_ent

    -- Physics-only floor collider (d_ent already renders floor tiles, preventing coplanar Z-fighting)
    local floor_e = eng.scene.spawn("catacomb_floor")
    eng.scene.set_pos(floor_e, 18.0, -0.25, 18.0)
    eng.physics.add_body(floor_e, { shape = "aabb", motion = "static", half_extents = {20.0, 0.25, 20.0} })
    S.ents[#S.ents + 1] = floor_e
    eng.ai.set_grid(0, 2.0, 18, 18, d.walkable)

    S.px, S.py, S.pz = d.start_x, 1.4, d.start_z
    S.ex, S.ez = d.exit_x, d.exit_z
    S.yaw = math.deg(math.atan2(S.px - S.ex, S.pz - S.ez))
    S.pitch = 0.0

    -- Exit Shrine Crystal + Relic Key on guaranteed walkable cells
    local exit_e = eng.scene.spawn("exit_portal_pillar")
    eng.scene.set_pos(exit_e, S.ex, 0.0, S.ez)
    eng.scene.set_mesh(exit_e, S.arch_mesh, { color = {0.35, 0.9, 1.0, 1.0} })
    S.ents[#S.ents + 1] = exit_e

    S.kx, S.kz = d.key_x, d.key_z
    S.has_key = false
    S.key_ent = eng.scene.spawn("relic_key")
    eng.scene.set_pos(S.key_ent, S.kx, 0.8, S.kz)
    eng.scene.set_mesh(S.key_ent, S.crystal_mesh, { color = {1.0, 0.85, 0.2, 1.0} })
    S.ents[#S.ents + 1] = S.key_ent

    -- Spawn 3 catacomb guardians on walkable cells with raycast hitboxes
    for i = 1, 3 do
        local t = i / 4.0
        local gx, gz = snap_walkable(d, S.px + (S.ex - S.px) * t + (i - 2) * 1.6, S.pz + (S.ez - S.pz) * t)
        local ge = eng.scene.spawn("ghoul_" .. tostring(i))
        eng.scene.set_pos(ge, gx, 0.9, gz)
        eng.scene.set_scale(ge, 0.8, 1.6, 0.8)
        eng.scene.set_mesh(ge, S.crate_mesh, { color = {0.9, 0.25, 0.25, 1.0} })
        local bid = eng.physics.add_body(ge, { shape = "aabb", motion = "kinematic", half_extents = {0.45, 0.85, 0.45} })
        S.ents[#S.ents + 1] = ge
        S.enemies[#S.enemies + 1] = { ent = ge, body = bid, x = gx, z = gz, hp = 2, alive = true }
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
end

function init()
    eng.xr.set_mode("first_person")
    eng.input.set_mouse_lock(true)
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.022 })
    eng.render.set_sky(0.06, 0.04, 0.10, 0.20, 0.10, 0.14)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.8, 1.65, 1.45}, shadow = true })
    eng.render.add_light({ type = "point", pos = {18.0, 5.0, 18.0}, color = {2.4, 1.4, 0.7}, range = 38.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.sfx_shot = eng.audio.synth("noise", 320, 0.11, 90)
    S.sfx_key = eng.audio.synth("triangle", 520, 0.18, 920)

    S.hp = 100
    S.score = 0
    S.kills = 0
    S.won = false
    S.cooldown = 0.0
    build_stage(1)
    eng.mod.emit("post_init")
end

function fire_shotgun()
    local rad = math.rad(S.yaw or 0.0)
    local dx, dz = -math.sin(rad), -math.cos(rad)
    -- Aim along view ray (cone snap once mouse-aimed, smart target for keyboard/playtest)
    local best_d = 22.0
    local manual = (S.manual_aimed == true)
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local ex, ez = en.x - S.px, en.z - S.pz
            local d = math.sqrt(ex * ex + ez * ez)
            if d > 0.01 and d < best_d then
                local dot = (ex / d) * dx + (ez / d) * dz
                if (not manual) or dot > 0.94 then
                    best_d = d; dx = ex / d; dz = ez / d
                end
            end
        end
    end

    eng.audio.play(S.sfx_shot, S.px, S.py, S.pz, 0)
    local hit = eng.physics.raycast(0, S.px, 0.9, S.pz, dx, 0.0, dz, 30.0)
    if hit then
        for i = 1, #S.enemies do
            local en = S.enemies[i]
            if en.alive and en.ent == hit.entity then
                en.hp = en.hp - 2
                if en.hp <= 0 then
                    en.alive = false
                    eng.scene.despawn(en.ent)
                    S.kills = S.kills + 1
                    S.score = S.score + 150
                end
            end
        end
    end
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)

    local mdx, mdy = eng.input.mouse_delta()
    if math.abs(mdx) > 0.01 or math.abs(mdy) > 0.01 then S.manual_aimed = true end
    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw or 0.0, S.pitch or 0.0, 7.5, dt)
    if math.abs(dx) > 1e-4 or math.abs(dz) > 1e-4 then
        local nx, nz = eng.physics.slide_move(0, S.px, S.py, S.pz, dx, dz, 0.38)
        S.px = eng.math.clamp(nx, 1.5, 34.5)
        S.pz = eng.math.clamp(nz, 1.5, 34.5)
    end

    if (eng.input.pressed("fire") or eng.input.down("fire")) and S.cooldown <= 0.0 then
        S.cooldown = 0.22
        fire_shotgun()
    end

    -- Relic key pickup
    if not S.has_key and eng.math.dist3(S.px, 0, S.pz, S.kx, 0, S.kz) < 2.2 then
        S.has_key = true
        S.score = S.score + 250
        eng.audio.play(S.sfx_key, S.kx, 1.0, S.kz, 0)
        eng.scene.despawn(S.key_ent)
    end

    -- A* pursuit for living enemies
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local path = eng.ai.find_path(0, en.x, 0.0, en.z, 0, S.px, 0.0, S.pz)
            local tx, tz = S.px, S.pz
            if path and #path >= 2 then tx, tz = path[2][1], path[2][3] end
            local vx, vz = tx - en.x, tz - en.z
            local vl = math.sqrt(vx * vx + vz * vz)
            if vl > 0.4 then
                en.x, en.z = eng.physics.slide_move(0, en.x, 0.9, en.z, (vx / vl) * 2.4 * dt, (vz / vl) * 2.4 * dt, 0.42)
                eng.scene.set_pos(en.ent, en.x, 0.9, en.z)
            end
        end
    end

    -- Stage exit check
    if S.has_key and eng.math.dist3(S.px, 0, S.pz, S.ex, 0, S.ez) < 2.4 then
        if S.stage < 3 then
            eng.save.write("catacomb_progress", tostring(S.stage + 1))
            build_stage(S.stage + 1)
        else
            S.won = true
            S.score = S.score + 500
            eng.save.write("catacomb_progress", "clear")
        end
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
end

function draw()
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then eng.render.draw_sprite(en.x, 1.9, en.z, 0.7, 0.7, S.orb_tex) end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 420, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | STAGE " .. S.stage .. "/3 | SCORE " .. S.score, 1.0, {1.0, 0.9, 0.5, 1.0})
    eng.ui.bar(x, y + 26, 200, S.hp / 100.0, "HP ")
end
