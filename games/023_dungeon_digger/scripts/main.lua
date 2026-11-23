-- 023_dungeon_digger: Underground keeper RTS-lite mining gold-vein blocks and hiring imps to claim shrines
local S = game.state

local GRID_N = 9
local CELL = 1.5

local function g2w(gx, gz)
    return (gx - 5) * CELL, (gz - 5) * CELL
end

local function spawn_imp(seed_val, sx, sz)
    local ent = eng.scene.spawn("keeper_imp_" .. tostring(#S.imps + 1))
    eng.scene.set_pos(ent, sx, 0.0, sz)
    eng.scene.set_scale(ent, 0.72, 0.72, 0.72)
    local info = eng.procgen.person(ent, seed_val)
    S.imps[#S.imps + 1] = {
        ent = ent,
        name = info and info.name or "Imp",
        x = sx,
        z = sz,
        work_t = 0.0
    }
end

local function rebuild_nav()
    local walk = {}
    for gz = 1, GRID_N do
        for gx = 1, GRID_N do
            local blk = S.cells[gz][gx]
            walk[(gz - 1) * GRID_N + gx] = (blk == nil) and 1 or 0
        end
    end
    eng.ai.set_grid(0, CELL, GRID_N, GRID_N, walk)
end

local function is_exposed(gx, gz)
    local dirs = {{1,0}, {-1,0}, {0,1}, {0,-1}}
    for i = 1, 4 do
        local nx, nz = gx + dirs[i][1], gz + dirs[i][2]
        if nx >= 1 and nx <= GRID_N and nz >= 1 and nz <= GRID_N and S.cells[nz][nx] == nil then
            return true
        end
    end
    return false
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.018 })
    eng.render.set_sky(0.05, 0.03, 0.08, 0.16, 0.09, 0.20)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.7, 1.55, 1.4}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.5, 0.0}, color = {2.6, 1.6, 0.7}, range = 26.0 })

    S.seed = math.floor(eng.math.range(100, 99999))
    local floor_tex = eng.procgen.texture("stone_brick", S.seed, 64)
    local box_mesh = eng.asset.box(1, 1, 1)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")

    S.dirt_vox = eng.asset.voxel_ascii({
        "333\n333\n333",
        "333\n313\n333",
        "333\n333\n333"
    }, 3, 3, 3, 0.46)
    S.gold_vox = eng.asset.voxel_ascii({
        "363\n666\n363",
        "666\n676\n666",
        "363\n666\n363"
    }, 3, 3, 3, 0.46)

    S.sfx_mine = eng.audio.synth("noise", 360, 0.09, 140)
    S.sfx_hire = eng.audio.synth("triangle", 420, 0.16, 780)
    S.sfx_shrine = eng.audio.synth("sine", 540, 0.22, 980)

    local floor = eng.scene.spawn("cavern_floor")
    eng.scene.set_pos(floor, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor, 18.0, 0.5, 18.0)
    eng.scene.set_mesh(floor, box_mesh, { tex = floor_tex, color = {0.42, 0.38, 0.44, 1.0} })
    eng.physics.add_body(floor, { shape = "aabb", motion = "static", half_extents = {9.0, 0.25, 9.0} })

    local heart = eng.scene.spawn("dungeon_heart")
    eng.scene.set_pos(heart, 0.0, 0.0, 0.0)
    eng.scene.set_scale(heart, 1.1, 1.3, 1.1)
    eng.scene.set_mesh(heart, S.crystal_mesh, { color = {1.0, 0.25, 0.55, 1.0} })

    -- Shrine positions at 3 outer alcoves
    local shrine_cells = {{2, 5}, {8, 5}, {5, 2}}
    local shrine_map = {}
    for i = 1, #shrine_cells do
        shrine_map[shrine_cells[i][2] * 100 + shrine_cells[i][1]] = i
    end

    -- Deterministic gold vein cells surrounding the central 3x3 chamber
    local gold_map = {
        [5 * 100 + 3] = true, [5 * 100 + 7] = true,
        [3 * 100 + 5] = true, [4 * 100 + 3] = true,
        [4 * 100 + 7] = true, [3 * 100 + 4] = true
    }

    S.cells = {}
    for gz = 1, GRID_N do
        S.cells[gz] = {}
        for gx = 1, GRID_N do
            local in_center = (gx >= 4 and gx <= 6 and gz >= 4 and gz <= 6)
            local is_shrine = shrine_map[gz * 100 + gx] ~= nil
            if not in_center and not is_shrine then
                local wx, wz = g2w(gx, gz)
                local is_gold = gold_map[gz * 100 + gx] == true
                local be = eng.scene.spawn((is_gold and "gold_vein_" or "dirt_") .. gx .. "_" .. gz)
                eng.scene.set_pos(be, wx - 0.69, 0.0, wz - 0.69)
                eng.scene.set_mesh(be, is_gold and S.gold_vox or S.dirt_vox, {
                    color = is_gold and {1.15, 0.95, 0.35, 1.0} or {0.65, 0.48, 0.36, 1.0},
                    cast_shadow = true
                })
                S.cells[gz][gx] = { ent = be, gx = gx, gz = gz, wx = wx, wz = wz, gold = is_gold, tagged = false }
            end
        end
    end

    S.shrines = {}
    for i = 1, #shrine_cells do
        local gx, gz = shrine_cells[i][1], shrine_cells[i][2]
        local wx, wz = g2w(gx, gz)
        local se = eng.scene.spawn("ancient_shrine_" .. i)
        eng.scene.set_pos(se, wx, 0.0, wz)
        eng.scene.set_scale(se, 0.65, 0.65, 0.65)
        eng.scene.set_mesh(se, S.arch_mesh, { color = {0.45, 0.85, 1.0, 1.0} })
        S.shrines[i] = { ent = se, gx = gx, gz = gz, wx = wx, wz = wz, claimed = false, progress = 0.0 }
    end

    S.imps = {}
    spawn_imp(S.seed + 11, -1.2, 0.8)
    rebuild_nav()

    S.cx, S.cz = 3, 5
    S.cursor_ent = eng.scene.spawn("keeper_cursor")
    local kx, kz = g2w(S.cx, S.cz)
    eng.scene.set_pos(S.cursor_ent, kx, 1.55, kz)
    eng.scene.set_scale(S.cursor_ent, 0.45, 0.45, 0.45)
    eng.scene.set_mesh(S.cursor_ent, S.crystal_mesh, { color = {0.3, 1.0, 0.45, 1.0} })

    S.gold = 40
    S.blocks_mined = 0
    S.shrines_claimed = 0
    S.move_cd = 0.0
    S.won = false

    eng.camera.look_at(0.0, 11.5, 9.2, 0.0, 0.0, -0.5, 0)
    eng.mod.emit("post_init")
end

local function find_imp_job(imp)
    local best_blk, best_d = nil, 999.0
    for gz = 1, GRID_N do
        for gx = 1, GRID_N do
            local c = S.cells[gz][gx]
            if c and c.tagged and is_exposed(gx, gz) then
                local d = eng.math.dist3(imp.x, 0, imp.z, c.wx, 0, c.wz)
                if d < best_d then best_d = d; best_blk = c end
            end
        end
    end
    if best_blk then return "mine", best_blk end

    for i = 1, #S.shrines do
        local sh = S.shrines[i]
        if not sh.claimed and is_exposed(sh.gx, sh.gz) then
            return "shrine", sh
        end
    end
    return nil, nil
end

function update(dt)
    if S.won then return end
    S.move_cd = math.max(0.0, S.move_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if (math.abs(mx) > 0.4 or math.abs(my) > 0.4) and S.move_cd <= 0.0 then
        S.move_cd = 0.12
        if math.abs(mx) >= math.abs(my) then
            S.cx = eng.math.clamp(S.cx + (mx > 0 and 1 or -1), 1, GRID_N)
        else
            S.cz = eng.math.clamp(S.cz + (my > 0 and -1 or 1), 1, GRID_N)
        end
    end

    local kx, kz = g2w(S.cx, S.cz)
    eng.scene.set_pos(S.cursor_ent, kx, 1.55, kz)

    -- Tag block for mining
    if eng.input.pressed("fire") or eng.input.down("fire") then
        local blk = S.cells[S.cz][S.cx]
        if blk and not blk.tagged then
            blk.tagged = true
            eng.scene.set_mesh(blk.ent, blk.gold and S.gold_vox or S.dirt_vox, {
                color = {1.0, 0.35, 0.25, 1.0},
                cast_shadow = true
            })
        end
    end

    -- Hire procedural imp worker
    if eng.input.pressed("interact") and S.gold >= 60 and #S.imps < 4 then
        S.gold = S.gold - 60
        spawn_imp(S.seed + 37 * (#S.imps + 1), (#S.imps - 1) * 0.7, 0.9)
        eng.audio.play(S.sfx_hire, 0.0, 0.8, 0.0, 0)
    end

    -- Step all imp workers
    for i = 1, #S.imps do
        local imp = S.imps[i]
        local kind, tgt = find_imp_job(imp)
        if tgt then
            local dx, dz = tgt.wx - imp.x, tgt.wz - imp.z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist > 1.35 then
                local spd = 5.6 * dt
                imp.x = imp.x + (dx / dist) * spd
                imp.z = imp.z + (dz / dist) * spd
                eng.scene.set_pos(imp.ent, imp.x, 0.0, imp.z)
                eng.scene.set_rot_deg(imp.ent, 0.0, math.deg(math.atan2(-dx, -dz)), 0.0)
            elseif kind == "mine" and S.cells[tgt.gz][tgt.gx] == tgt then
                imp.work_t = imp.work_t + dt
                if imp.work_t >= 0.18 then
                    imp.work_t = 0.0
                    S.gold = S.gold + (tgt.gold and 45 or 10)
                    S.blocks_mined = S.blocks_mined + 1
                    eng.audio.play(S.sfx_mine, tgt.wx, 0.6, tgt.wz, 0)
                    eng.scene.despawn(tgt.ent)
                    S.cells[tgt.gz][tgt.gx] = nil
                    rebuild_nav()
                end
            elseif kind == "shrine" and not tgt.claimed then
                tgt.progress = tgt.progress + dt
                if tgt.progress >= 0.28 then
                    tgt.claimed = true
                    S.shrines_claimed = S.shrines_claimed + 1
                    eng.audio.play(S.sfx_shrine, tgt.wx, 0.8, tgt.wz, 0)
                    eng.scene.set_mesh(tgt.ent, S.arch_mesh, { color = {1.0, 0.85, 0.2, 1.0} })
                end
            end
        end
    end

    if S.shrines_claimed >= 3 then
        S.won = true
        eng.save.write("dungeon_digger_progress", "clear")
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | GOLD %d | IMPS %d | SHRINES %d/3",
        eng.i18n.t("title"), S.gold, #S.imps, S.shrines_claimed), 1.0, {1.0, 0.88, 0.35, 1.0})
    eng.ui.bar(x, y + 26, 220, S.shrines_claimed / 3.0, "CLAIM ")
end
