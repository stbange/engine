-- 061_sokoban_ruins_3d: Multi-elevation 3D stone crate pushing puzzle with ramps & sunken glyph switches
local S = game.state
local CELL = 2.0

local function cell_world(gx, gz)
    return (gx - 4) * CELL, (gz - 4) * CELL
end

local function clear_stage()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
    S.crates = {}
    S.switches = {}
    S.grid_wall = {}
    S.grid_elev = {}
end

local function set_cell(gx, gz, wall, elev)
    local k = gx * 16 + gz
    S.grid_wall[k] = wall
    S.grid_elev[k] = elev
end

local function is_wall(gx, gz)
    if gx < 1 or gx > 7 or gz < 1 or gz > 7 then return true end
    return S.grid_wall[gx * 16 + gz] == true
end

local function get_elev(gx, gz)
    return S.grid_elev[gx * 16 + gz] or 0.0
end

local function crate_at(gx, gz)
    for i = 1, #S.crates do
        if S.crates[i].gx == gx and S.crates[i].gz == gz then return S.crates[i] end
    end
    return nil
end

local function sync_visuals()
    local px, pz = cell_world(S.pgx, S.pgz)
    local pe = get_elev(S.pgx, S.pgz)
    eng.scene.set_pos(S.player_ent, px, pe + 0.55, pz)

    local lit = 0
    for i = 1, #S.crates do
        local c = S.crates[i]
        local cx, cz = cell_world(c.gx, c.gz)
        local ce = get_elev(c.gx, c.gz)
        c.elev = ce
        eng.scene.set_pos(c.ent, cx, ce + 0.02, cz)
    end
    for i = 1, #S.switches do
        local sw = S.switches[i]
        local c = crate_at(sw.gx, sw.gz)
        sw.active = (c ~= nil)
        if sw.active then
            lit = lit + 1
            eng.scene.set_mesh(sw.ent, S.box_mesh, { color = {0.2, 1.0, 0.55, 1.0} })
        else
            eng.scene.set_mesh(sw.ent, S.box_mesh, { color = {1.0, 0.55, 0.15, 1.0} })
        end
    end
    S.active_switches = lit
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    local seed_base = math.floor(eng.math.range(100, 9000)) + idx * 97
    local stone_tex = eng.procgen.texture("stone_brick", seed_base, 64)
    local cobble_tex = eng.procgen.texture("cobble", seed_base + 31, 64)

    local base = eng.scene.spawn("ruin_courtyard")
    eng.scene.set_pos(base, 0.0, -0.25, 0.0)
    eng.scene.set_scale(base, 16.0, 0.5, 16.0)
    eng.scene.set_mesh(base, S.box_mesh, { tex = cobble_tex, color = {0.62, 0.58, 0.52, 1.0} })
    eng.physics.add_body(base, { shape = "aabb", motion = "static", half_extents = {8.0, 0.25, 8.0} })
    S.ents[#S.ents + 1] = base

    for gx = 1, 7 do
        for gz = 1, 7 do
            local border = (gx == 1 or gx == 7 or gz == 1 or gz == 7)
            set_cell(gx, gz, border, 0.0)
            if border then
                local wx, wz = cell_world(gx, gz)
                local p = eng.scene.spawn("ruin_pillar")
                eng.scene.set_pos(p, wx, 0.0, wz)
                eng.scene.set_scale(p, 0.9, 0.75, 0.9)
                eng.scene.set_mesh(p, S.pillar_mesh, { tex = stone_tex, color = {0.55, 0.52, 0.48, 1.0}, cast_shadow = true })
                S.ents[#S.ents + 1] = p
            end
        end
    end

    local ramps, crates_cfg, sw_cfg = {}, {}, {}
    if idx == 1 then
        for gx = 2, 6 do set_cell(gx, 2, false, 1.0) end
        set_cell(2, 3, true, 0.0)
        set_cell(6, 3, true, 0.0)
        set_cell(4, 3, false, 0.5)
        ramps = { {4, 3} }
        S.pgx, S.pgz = 4, 6
        crates_cfg = { {4, 4}, {3, 5} }
        sw_cfg = { {4, 2}, {2, 5} }
    else
        set_cell(2, 2, false, 1.0)
        local terrace = { {6,3}, {5,3}, {4,3}, {6,2}, {5,2}, {4,2} }
        for i = 1, #terrace do set_cell(terrace[i][1], terrace[i][2], false, 1.0) end
        set_cell(2, 3, false, 0.5)
        set_cell(6, 4, false, 0.5)
        ramps = { {2, 3}, {6, 4} }
        S.pgx, S.pgz = 2, 5
        crates_cfg = { {2, 4}, {5, 3}, {4, 3} }
        sw_cfg = { {2, 2}, {6, 3}, {4, 4} }
    end

    for gx = 2, 6 do
        for gz = 2, 6 do
            local wx, wz = cell_world(gx, gz)
            local el = get_elev(gx, gz)
            if is_wall(gx, gz) then
                local w = eng.scene.spawn("inner_block")
                eng.scene.set_pos(w, wx, 0.0, wz)
                eng.scene.set_scale(w, 1.1, 0.8, 1.1)
                eng.scene.set_mesh(w, S.pillar_mesh, { tex = stone_tex, color = {0.48, 0.45, 0.42, 1.0}, cast_shadow = true })
                S.ents[#S.ents + 1] = w
            elseif el > 0.9 then
                local t = eng.scene.spawn("terrace_slab")
                eng.scene.set_pos(t, wx, 0.5, wz)
                eng.scene.set_scale(t, CELL, 1.0, CELL)
                eng.scene.set_mesh(t, S.box_mesh, { tex = stone_tex, color = {0.72, 0.68, 0.60, 1.0}, cast_shadow = true })
                eng.physics.add_body(t, { shape = "aabb", motion = "static", half_extents = {1.0, 0.5, 1.0} })
                S.ents[#S.ents + 1] = t
            end
        end
    end

    for i = 1, #ramps do
        local wx, wz = cell_world(ramps[i][1], ramps[i][2])
        local r = eng.scene.spawn("stone_ramp_" .. tostring(i))
        eng.scene.set_pos(r, wx, 0.42, wz)
        eng.scene.set_rot_deg(r, 26.5, 0.0, 0.0)
        eng.scene.set_scale(r, 1.85, 0.35, 2.15)
        eng.scene.set_mesh(r, S.box_mesh, { tex = stone_tex, color = {0.80, 0.74, 0.58, 1.0}, cast_shadow = true })
        S.ents[#S.ents + 1] = r
    end

    for i = 1, #sw_cfg do
        local gx, gz = sw_cfg[i][1], sw_cfg[i][2]
        local wx, wz = cell_world(gx, gz)
        local el = get_elev(gx, gz)
        local sw = eng.scene.spawn("glyph_switch_" .. tostring(i))
        eng.scene.set_pos(sw, wx, el + 0.05, wz)
        eng.scene.set_scale(sw, 1.35, 0.10, 1.35)
        eng.scene.set_mesh(sw, S.box_mesh, { color = {1.0, 0.55, 0.15, 1.0} })
        S.ents[#S.ents + 1] = sw
        S.switches[#S.switches + 1] = { ent = sw, gx = gx, gz = gz, active = false }
    end

    for i = 1, #crates_cfg do
        local gx, gz = crates_cfg[i][1], crates_cfg[i][2]
        local wx, wz = cell_world(gx, gz)
        local el = get_elev(gx, gz)
        local ce = eng.scene.spawn("stone_crate_" .. tostring(i))
        eng.scene.set_pos(ce, wx, el + 0.02, wz)
        eng.scene.set_scale(ce, 1.15, 1.0, 1.15)
        eng.scene.set_mesh(ce, S.crate_mesh, { tex = stone_tex, color = {0.86, 0.78, 0.56, 1.0}, cast_shadow = true })
        S.ents[#S.ents + 1] = ce
        S.crates[#S.crates + 1] = { ent = ce, gx = gx, gz = gz, elev = el }
    end

    S.player_ent = eng.scene.spawn("explorer")
    eng.scene.set_scale(S.player_ent, 0.75, 1.1, 0.75)
    eng.scene.set_mesh(S.player_ent, S.crystal_mesh, { color = {0.30, 0.85, 1.0, 1.0}, cast_shadow = true })
    S.ents[#S.ents + 1] = S.player_ent

    sync_visuals()
    eng.camera.look_at(0.0, 11.5, 11.5, 0.0, 0.5, -0.5, 0)
end

local function try_step(dgx, dgz)
    local ngx, ngz = S.pgx + dgx, S.pgz + dgz
    if is_wall(ngx, ngz) then return false end
    local pe = get_elev(S.pgx, S.pgz)
    local ne = get_elev(ngx, ngz)
    -- Climbing requires stone ramp (delta <= 0.55); stepping down a 1m ledge is allowed
    if (ne - pe) > 0.55 then return false end

    local blk = crate_at(ngx, ngz)
    if blk then
        local cgx, cgz = ngx + dgx, ngz + dgz
        if is_wall(cgx, cgz) or crate_at(cgx, cgz) ~= nil then return false end
        local ce = get_elev(cgx, cgz)
        if (ce - ne) > 0.55 then return false end
        blk.gx, blk.gz = cgx, cgz
        if ce > ne + 0.1 then S.ramp_pushes = S.ramp_pushes + 1 end
        if ce < ne - 0.1 then S.ledge_drops = S.ledge_drops + 1 end
        S.pushes = S.pushes + 1
        eng.audio.play(S.sfx_push, 0.0, 1.0, 0.0, 0)
    end

    S.pgx, S.pgz = ngx, ngz
    S.moves = S.moves + 1
    sync_visuals()

    if S.active_switches == #S.switches then
        eng.audio.play(S.sfx_win, 0.0, 1.5, 0.0, 0)
        if S.stage < 2 then
            eng.save.write("sokoban_ruins_3d", "stage_2")
            build_stage(S.stage + 1)
        else
            S.won = true
            eng.save.write("sokoban_ruins_3d", "clear")
        end
    end
    return true
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.015 })
    eng.render.set_sky(0.10, 0.16, 0.28, 0.36, 0.28, 0.22)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.1, 1.95, 1.70}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, 0.0}, color = {1.4, 1.2, 0.9}, range = 24.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.sfx_push = eng.audio.synth("noise", 190, 0.09, 110)
    S.sfx_win = eng.audio.synth("triangle", 480, 0.22, 880)

    S.moves = 0
    S.pushes = 0
    S.ramp_pushes = 0
    S.ledge_drops = 0
    S.cooldown = 0.0
    S.won = false
    build_stage(1)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end
    S.cooldown = math.max(0.0, S.cooldown - dt)
    if eng.input.pressed("interact") then
        build_stage(S.stage)
        return
    end
    if S.cooldown > 0.0 then return end

    local dx, dz = 0, 0
    if eng.input.pressed("left") or eng.input.down("left") then dx = -1
    elseif eng.input.pressed("right") or eng.input.down("right") then dx = 1
    elseif eng.input.pressed("up") or eng.input.down("up") then dz = -1
    elseif eng.input.pressed("down") or eng.input.down("down") then dz = 1 end

    if dx ~= 0 or dz ~= 0 then
        S.cooldown = 0.08
        try_step(dx, dz)
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | TEMPLE " .. S.stage .. "/2 | GLYPHS " .. S.active_switches .. "/" .. #S.switches, 1.0, {1.0, 0.92, 0.55, 1.0})
    eng.ui.bar(x, y + 26, 200, S.active_switches / math.max(1, #S.switches), "GLYPH ")
end
