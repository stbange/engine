-- 005_iron_bastion_tactics: 3-Mission Turn-Based Tactical Mechs (Voxel Cover + A* Grid + IK Bipeds)
local S = game.state

local GRID_W, GRID_D = 10, 10
local CELL = 2.0

local function cell_world(gx, gz)
    return (gx - 0.5) * CELL, (gz - 0.5) * CELL
end

local function clear_mission_entities()
    if S.m_ents then
        for i = 1, #S.m_ents do eng.scene.despawn(S.m_ents[i]) end
    end
    S.m_ents = {}
    S.enemies = {}
end

local function build_mission(m_idx)
    clear_mission_entities()
    S.stage = m_idx
    local seed_base = math.floor(eng.math.range(400, 800000)) + m_idx * 311

    local floor_tex = eng.procgen.texture("rust_metal", seed_base, 64)
    local board = eng.scene.spawn("tactical_board_" .. tostring(m_idx))
    eng.scene.set_pos(board, 10.0, -0.25, 10.0)
    eng.scene.set_scale(board, 22.0, 0.5, 22.0)
    eng.scene.set_mesh(board, S.box_mesh, { tex = floor_tex, roughness = 0.78 })
    S.m_ents[#S.m_ents + 1] = board

    local cover_cells = {
        {3, 5}, {6, 4}, {8, 6}, {4, 7}
    }
    for i = 1, #cover_cells do
        local cx, cz = cover_cells[i][1], cover_cells[i][2]
        local wx, wz = cell_world(cx, cz)
        local cov = eng.scene.spawn("voxel_bunker_" .. tostring(i))
        eng.scene.set_pos(cov, wx - 0.6, 0.0, wz - 0.6)
        eng.scene.set_mesh(cov, S.cover_vox, { cast_shadow = true, roughness = 0.85 })
        S.m_ents[#S.m_ents + 1] = cov
    end

    -- Player vanguard bipedal IK mech
    S.pgx, S.pgz = 2, 2
    S.cursor_gx, S.cursor_gz = 5, 6
    local px, pz = cell_world(S.pgx, S.pgz)
    S.p_ent = eng.scene.spawn("vanguard_mech")
    eng.scene.set_pos(S.p_ent, px, 0.0, pz)
    eng.scene.set_scale(S.p_ent, 1.3, 1.3, 1.3)
    eng.procgen.animal(S.p_ent, seed_base + 11, "biped")
    S.m_ents[#S.m_ents + 1] = S.p_ent

    -- Spawn hostile bipedal mechs with raycast cannon hitboxes
    local enemy_Coords = { {5, 8}, {8, 8}, {9, 4} }
    local count = (m_idx == 3) and 3 or 2
    for i = 1, count do
        local egx, egz = enemy_Coords[i][1], enemy_Coords[i][2]
        local ex, ez = cell_world(egx, egz)
        local ee = eng.scene.spawn("hostile_mech_" .. tostring(i))
        eng.scene.set_pos(ee, ex, 0.9, ez)
        eng.scene.set_scale(ee, 1.25, 1.25, 1.25)
        eng.procgen.animal(ee, seed_base + 50 + i * 19, "biped")
        local bid = eng.physics.add_body(ee, { shape = "aabb", motion = "kinematic", pocket = 0, half_extents = {0.75, 1.1, 0.75} })
        S.m_ents[#S.m_ents + 1] = ee
        S.enemies[#S.enemies + 1] = { ent = ee, body = bid, gx = egx, gz = egz, x = ex, z = ez, hp = 2, alive = true }
    end

    S.ap = 2
    eng.camera.look_at(10.0, 14.5, 22.5, 10.0, 0.5, 9.5, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 320, dither = true, color_bits = 6, fog_density = 0.01 })
    eng.render.set_sky(0.10, 0.14, 0.20, 0.34, 0.38, 0.44)
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.4, -1.0, -0.45}, color = {2.2, 2.05, 1.85}, shadow = true })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.cover_vox = eng.asset.voxel_ascii({
        "111\n141\n111",
        "1.1\n...\n1.1"
    }, 3, 2, 3, 0.45)

    local walk = {}
    for i = 1, GRID_W * GRID_D do walk[i] = 1 end
    local blocked = { {3, 5}, {6, 4}, {8, 6}, {4, 7} }
    for i = 1, #blocked do walk[(blocked[i][2] - 1) * GRID_W + blocked[i][1]] = 0 end
    eng.ai.set_grid(0, CELL, GRID_W, GRID_D, walk)

    S.sfx_step = eng.audio.synth("triangle", 190, 0.09, 130)
    S.sfx_cannon = eng.audio.synth("noise", 380, 0.14, 80)

    S.hp = 100
    S.turns = 0
    S.kills = 0
    S.paths_computed = 0
    S.input_cd = 0.0
    S.won = false

    build_mission(1)
    eng.mod.emit("post_init")
end

local function run_enemy_turn()
    S.turns = S.turns + 1
    local px, pz = cell_world(S.pgx, S.pgz)
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local path = eng.ai.find_path(0, en.x, 0.0, en.z, 0, px, 0.0, pz)
            if path and #path >= 2 then
                S.paths_computed = S.paths_computed + 1
                local dx, dz = path[2][1] - en.x, path[2][3] - en.z
                local d = math.sqrt(dx * dx + dz * dz)
                if d > 2.2 then
                    local step = math.min(CELL, d - 2.0)
                    en.x = en.x + (dx / d) * step
                    en.z = en.z + (dz / d) * step
                    eng.scene.set_pos(en.ent, en.x, 0.9, en.z)
                end
            end
            if eng.math.dist3(en.x, 0, en.z, px, 0, pz) < 10.0 then
                S.hp = math.max(25, S.hp - 4)
            end
        end
    end
    S.ap = 2
end

local function order_move_mech()
    local sx, sz = cell_world(S.pgx, S.pgz)
    local tx, tz = cell_world(S.cursor_gx, S.cursor_gz)
    local path = eng.ai.find_path(0, sx, 0.0, sz, 0, tx, 0.0, tz)
    if path and #path >= 2 then
        S.paths_computed = S.paths_computed + 1
        local dx, dz = path[2][1] - sx, path[2][3] - sz
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 2.1 then
            local step = math.min(CELL * 1.5, d - 2.0)
            local nx, nz = sx + (dx / d) * step, sz + (dz / d) * step
            S.pgx = eng.math.clamp(math.floor(nx / CELL) + 1, 1, GRID_W)
            S.pgz = eng.math.clamp(math.floor(nz / CELL) + 1, 1, GRID_D)
            local wx, wz = cell_world(S.pgx, S.pgz)
            eng.scene.set_pos(S.p_ent, wx, 0.0, wz)
            eng.audio.play(S.sfx_step, wx, 0.5, wz, 0)
        end
    end
    S.ap = S.ap - 1
end

local function order_fire_cannon()
    local px, pz = cell_world(S.pgx, S.pgz)
    local best_e = nil
    local best_d = 40.0
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local d = eng.math.dist3(px, 0, pz, en.x, 0, en.z)
            if d < best_d then best_d = d; best_e = en end
        end
    end
    if not best_e then S.ap = S.ap - 1; return end

    local dx, dz = best_e.x - px, best_e.z - pz
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 0.01 then dx, dz, len = 0.0, 1.0, 1.0 end
    eng.scene.set_rot_deg(S.p_ent, 0.0, math.deg(math.atan2(-dx, -dz)), 0.0)
    eng.audio.play(S.sfx_cannon, px, 1.2, pz, 0)

    local hit = eng.physics.raycast(0, px, 1.1, pz, dx / len, 0.0, dz / len, 36.0)
    if hit then
        for i = 1, #S.enemies do
            local en = S.enemies[i]
            if en.alive and en.ent == hit.entity then
                en.hp = en.hp - 2
                if en.hp <= 0 then
                    en.alive = false
                    eng.scene.despawn(en.ent)
                    S.kills = S.kills + 1
                end
            end
        end
    end
    S.ap = S.ap - 1
end

function update(dt)
    if S.won then return end
    S.input_cd = math.max(0.0, S.input_cd - dt)

    if S.input_cd <= 0.0 then
        local mx, my = eng.input.axis2d("left", "right", "down", "up")
        if math.abs(mx) > 0.5 or math.abs(my) > 0.5 then
            S.cursor_gx = eng.math.clamp(S.cursor_gx + (mx > 0.5 and 1 or (mx < -0.5 and -1 or 0)), 1, GRID_W)
            S.cursor_gz = eng.math.clamp(S.cursor_gz + (my > 0.5 and 1 or (my < -0.5 and -1 or 0)), 1, GRID_D)
            S.input_cd = 0.08
        end
    end

    if (eng.input.pressed("jump") or eng.input.pressed("interact")) and S.ap > 0 then
        order_move_mech()
    end
    if eng.input.pressed("fire") and S.ap > 0 then
        order_fire_cannon()
    end

    local remaining = 0
    for i = 1, #S.enemies do
        if S.enemies[i].alive then remaining = remaining + 1 end
    end
    if remaining == 0 then
        if S.stage < 3 then
            eng.save.write("iron_bastion_progress", "mission_" .. tostring(S.stage + 1))
            build_mission(S.stage + 1)
            return
        else
            S.won = true
            eng.save.write("iron_bastion_progress", "clear")
            return
        end
    end

    if S.ap <= 0 then
        run_enemy_turn()
    end

    eng.camera.look_at(10.0, 14.5, 22.5, 10.0, 0.5, 9.5, 0)
end

function draw()
    local cx, cz = cell_world(S.cursor_gx, S.cursor_gz)
    eng.render.draw_sprite(cx, 1.8, cz, 0.8, 0.8, S.orb_tex)
    local x, y = eng.ui.anchor("top_left", 16, 14, 460, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | MISSION " .. S.stage .. "/3 | AP " .. S.ap .. " | KILLS " .. S.kills, 1.0, {0.85, 0.92, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.hp / 100.0, "ARMOR ")
end
