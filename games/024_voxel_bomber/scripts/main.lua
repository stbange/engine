-- 024_voxel_bomber: 3D grid Bomberman with destructible voxel crates, chain-detonating bombs & AI rivals
local S = game.state

local GRID = 7
local CELL = 1.4

local function g2w(gx, gz)
    return (gx - 4) * CELL, (gz - 4) * CELL
end

local function w2g(wx, wz)
    return eng.math.clamp(math.floor((wx / CELL) + 4.5), 1, GRID),
           eng.math.clamp(math.floor((wz / CELL) + 4.5), 1, GRID)
end

local function cell_blocked(gx, gz, ignore_bombs)
    if gx < 1 or gx > GRID or gz < 1 or gz > GRID then return true end
    if (gx % 2 == 0) and (gz % 2 == 0) then return true end
    if S.crates[gz * 10 + gx] ~= nil then return true end
    if not ignore_bombs then
        for i = 1, #S.bombs do
            local b = S.bombs[i]
            if not b.exploded and b.gx == gx and b.gz == gz then return true end
        end
    end
    return false
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.014 })
    eng.render.set_sky(0.08, 0.12, 0.22, 0.22, 0.30, 0.42)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.1, 2.0, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, 0.0}, color = {1.6, 1.5, 1.3}, range = 24.0 })

    local seed = math.floor(eng.math.range(100, 99999))
    local floor_tex = eng.procgen.texture("stone_brick", seed, 64)
    local box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.45, 10, 12)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.pillar_vox = eng.asset.voxel_ascii({
        "111\n111\n111",
        "171\n777\n171",
        "111\n111\n111"
    }, 3, 3, 3, 0.42)
    S.crate_vox = eng.asset.voxel_ascii({
        "333\n363\n333",
        "363\n636\n363",
        "333\n363\n333"
    }, 3, 3, 3, 0.40)

    S.sfx_drop = eng.audio.synth("triangle", 340, 0.08, 220)
    S.sfx_boom = eng.audio.synth("noise", 260, 0.22, 70)

    local floor = eng.scene.spawn("arena_floor")
    eng.scene.set_pos(floor, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor, 13.0, 0.5, 13.0)
    eng.scene.set_mesh(floor, box_mesh, { tex = floor_tex, color = {0.46, 0.52, 0.48, 1.0} })
    eng.physics.add_body(floor, { shape = "aabb", motion = "static", half_extents = {6.5, 0.25, 6.5} })

    -- Indestructible stone voxel pillars on even coordinates
    for gz = 2, 6, 2 do
        for gx = 2, 6, 2 do
            local wx, wz = g2w(gx, gz)
            local pe = eng.scene.spawn("stone_pillar_" .. gx .. "_" .. gz)
            eng.scene.set_pos(pe, wx - 0.63, 0.0, wz - 0.63)
            eng.scene.set_mesh(pe, S.pillar_vox, { cast_shadow = true })
        end
    end

    -- Destructible wooden voxel crates
    local crate_coords = {
        {3, 1}, {5, 1}, {1, 3}, {3, 3}, {5, 3}, {3, 5}, {5, 5}, {1, 5}
    }
    S.crates = {}
    for i = 1, #crate_coords do
        local gx, gz = crate_coords[i][1], crate_coords[i][2]
        local wx, wz = g2w(gx, gz)
        local ce = eng.scene.spawn("voxel_crate_" .. i)
        eng.scene.set_pos(ce, wx - 0.60, 0.0, wz - 0.60)
        eng.scene.set_mesh(ce, S.crate_vox, { color = {0.95, 0.68, 0.35, 1.0}, cast_shadow = true })
        S.crates[gz * 10 + gx] = { ent = ce, gx = gx, gz = gz }
    end

    -- Player bomber at (1, 1)
    S.px, S.pz = g2w(1, 1)
    S.player_ent = eng.scene.spawn("player_bomber")
    eng.scene.set_pos(S.player_ent, S.px, 0.55, S.pz)
    eng.scene.set_scale(S.player_ent, 0.7, 1.1, 0.7)
    eng.scene.set_mesh(S.player_ent, box_mesh, { color = {0.25, 0.85, 1.0, 1.0}, cast_shadow = true })

    -- 2 Rival AI Bombers at (7, 1) and (7, 7)
    S.rivals = {}
    local r_starts = {{7, 1}, {7, 7}}
    for i = 1, #r_starts do
        local rx, rz = g2w(r_starts[i][1], r_starts[i][2])
        local re = eng.scene.spawn("rival_bomber_" .. i)
        eng.scene.set_pos(re, rx, 0.55, rz)
        eng.scene.set_scale(re, 0.7, 1.1, 0.7)
        eng.scene.set_mesh(re, box_mesh, { color = {1.0, 0.28, 0.32, 1.0}, cast_shadow = true })
        S.rivals[i] = { ent = re, gx = r_starts[i][1], gz = r_starts[i][2], x = rx, z = rz, dir = -1, alive = true, bomb_cd = 1.6 + i }
    end

    S.bombs = {}
    S.flames = {}
    S.bomb_range = 3
    S.crates_blasted = 0
    S.chain_detonations = 0
    S.enemies_defeated = 0
    S.player_hits = 0
    S.drop_cd = 0.0
    S.won = false

    eng.camera.look_at(0.0, 11.2, 8.6, 0.0, 0.0, -0.3, 0)
    eng.mod.emit("post_init")
end

local function place_bomb(gx, gz, owner)
    for i = 1, #S.bombs do
        local b = S.bombs[i]
        if not b.exploded and b.gx == gx and b.gz == gz then return false end
    end
    local wx, wz = g2w(gx, gz)
    local be = eng.scene.spawn("voxel_bomb")
    eng.scene.set_pos(be, wx, 0.45, wz)
    eng.scene.set_mesh(be, S.sphere_mesh, { color = {0.15, 0.15, 0.18, 1.0}, roughness = 0.3 })
    eng.audio.play(S.sfx_drop, wx, 0.5, wz, 0)
    S.bombs[#S.bombs + 1] = { ent = be, gx = gx, gz = gz, fuse = 1.45, range = S.bomb_range, owner = owner, exploded = false }
    return true
end

local function explode_bomb(b, from_chain)
    if b.exploded then return end
    b.exploded = true
    if from_chain then S.chain_detonations = S.chain_detonations + 1 end
    local bx, bz = g2w(b.gx, b.gz)
    eng.audio.play(S.sfx_boom, bx, 0.5, bz, 0)
    eng.scene.despawn(b.ent)

    local blast_cells = {{b.gx, b.gz}}
    local dirs = {{1,0}, {-1,0}, {0,1}, {0,-1}}
    for d = 1, 4 do
        for step = 1, b.range do
            local tx, tz = b.gx + dirs[d][1] * step, b.gz + dirs[d][2] * step
            if tx < 1 or tx > GRID or tz < 1 or tz > GRID then break end
            if (tx % 2 == 0) and (tz % 2 == 0) then break end
            blast_cells[#blast_cells + 1] = {tx, tz}

            local cr = S.crates[tz * 10 + tx]
            if cr then
                eng.scene.despawn(cr.ent)
                S.crates[tz * 10 + tx] = nil
                S.crates_blasted = S.crates_blasted + 1
                break
            end
        end
    end

    local pgx, pgz = w2g(S.px, S.pz)
    for i = 1, #blast_cells do
        local cx, cz = blast_cells[i][1], blast_cells[i][2]
        local wx, wz = g2w(cx, cz)
        S.flames[#S.flames + 1] = { x = wx, z = wz, ttl = 0.22 }

        if cx == pgx and cz == pgz then
            S.player_hits = S.player_hits + 1
            S.px, S.pz = g2w(1, 1)
            eng.scene.set_pos(S.player_ent, S.px, 0.55, S.pz)
        end

        for r = 1, #S.rivals do
            local rv = S.rivals[r]
            if rv.alive then
                local rgx, rgz = w2g(rv.x, rv.z)
                if rgx == cx and rgz == cz then
                    rv.alive = false
                    S.enemies_defeated = S.enemies_defeated + 1
                    eng.scene.despawn(rv.ent)
                end
            end
        end

        -- Trigger immediate chain detonation on any bomb caught in blast ray
        for k = 1, #S.bombs do
            local ob = S.bombs[k]
            if not ob.exploded and ob.gx == cx and ob.gz == cz then
                explode_bomb(ob, true)
            end
        end
    end
end

function update(dt)
    if S.won then return end
    S.drop_cd = math.max(0.0, S.drop_cd - dt)

    -- Smooth grid-aware player movement
    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local spd = 6.2 * dt
    local cur_gx, cur_gz = w2g(S.px, S.pz)
    if math.abs(mx) > 0.05 then
        local nx = eng.math.clamp(S.px + mx * spd, -3.0 * CELL, 3.0 * CELL)
        local tgx, tgz = w2g(nx + (mx > 0 and 0.32 or -0.32), S.pz)
        if (tgx == cur_gx and tgz == cur_gz) or not cell_blocked(tgx, tgz, false) then
            S.px = nx
        end
    end
    if math.abs(my) > 0.05 then
        local nz = eng.math.clamp(S.pz - my * spd, -3.0 * CELL, 3.0 * CELL)
        local tgx, tgz = w2g(S.px, nz + (-my > 0 and 0.32 or -0.32))
        if (tgx == cur_gx and tgz == cur_gz) or not cell_blocked(tgx, tgz, false) then
            S.pz = nz
        end
    end
    eng.scene.set_pos(S.player_ent, S.px, 0.55, S.pz)

    if eng.input.pressed("fire") and S.drop_cd <= 0.0 then
        local pgx, pgz = w2g(S.px, S.pz)
        if place_bomb(pgx, pgz, "player") then
            S.drop_cd = 0.14
        end
    end

    -- Rival AI patrol along open outer col/row
    for i = 1, #S.rivals do
        local rv = S.rivals[i]
        if rv.alive then
            local nz = rv.z + rv.dir * 2.2 * dt
            local rgx, rgz = w2g(rv.x, nz + rv.dir * 0.35)
            local cur_rgx, cur_rgz = w2g(rv.x, rv.z)
            if nz < -3.0 * CELL or nz > 3.0 * CELL or ((rgx ~= cur_rgx or rgz ~= cur_rgz) and cell_blocked(rgx, rgz, false)) then
                rv.dir = -rv.dir
            else
                rv.z = nz
                eng.scene.set_pos(rv.ent, rv.x, 0.55, rv.z)
            end
        end
    end

    for i = 1, #S.bombs do
        local b = S.bombs[i]
        if not b.exploded then
            b.fuse = b.fuse - dt
            if b.fuse <= 0.0 then explode_bomb(b, false) end
        end
    end

    for i = #S.flames, 1, -1 do
        S.flames[i].ttl = S.flames[i].ttl - dt
        if S.flames[i].ttl <= 0.0 then table.remove(S.flames, i) end
    end

    if S.enemies_defeated >= 2 and S.crates_blasted >= 2 then
        S.won = true
        eng.save.write("voxel_bomber_progress", "clear")
    end
end

function draw()
    for i = 1, #S.flames do
        local fl = S.flames[i]
        eng.render.draw_sprite(fl.x, 0.75, fl.z, 1.15, 1.15, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | CRATES %d | CHAINS %d | RIVALS %d/2",
        eng.i18n.t("title"), S.crates_blasted, S.chain_detonations, S.enemies_defeated), 1.0, {1.0, 0.88, 0.4, 1.0})
    eng.ui.bar(x, y + 26, 220, S.enemies_defeated / 2.0, "CLEAR ")
end
