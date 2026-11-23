-- 026_ice_carver: Chisel excess blocks from a 4x4x4 3D ice cube to match target voxel sculpture (>=90% accuracy)
local S = game.state

local BLUEPRINT_ASCII = {
    "5555\n5555\n5555\n5555",
    "5..5\n.55.\n.55.\n5..5",
    "....\n.55.\n.55.\n....",
    "....\n.55.\n.55.\n...."
}

local STEP = 0.52

local function cell_world_pos(cx, cy, cz)
    return 1.8 + (cx - 2.5) * STEP, 0.85 + (cy - 1) * STEP, -2.0 + (cz - 2.5) * STEP
end

local function compute_accuracy()
    local match = 0
    for y = 1, 4 do
        for z = 1, 4 do
            for x = 1, 4 do
                local has_ice = (S.ice[y][z][x] ~= nil) and 1 or 0
                if has_ice == S.blueprint[y][z][x] then
                    match = match + 1
                end
            end
        end
    end
    return match / 64.0
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.012 })
    eng.render.set_sky(0.08, 0.16, 0.28, 0.42, 0.62, 0.80)
    eng.render.add_light({ type = "dir", dir = {-0.35, -1.0, -0.45}, color = {2.2, 2.25, 2.35}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.5, 1.5}, color = {1.4, 1.8, 2.2}, range = 20.0 })

    local seed = math.floor(eng.math.range(100, 99999))
    local floor_tex = eng.procgen.texture("stone_brick", seed, 64)
    local box_mesh = eng.asset.box(1, 1, 1)
    S.sub_vox = eng.asset.voxel_ascii({"5"}, 1, 1, 1, 0.46)
    local ref_vox = eng.asset.voxel_ascii(BLUEPRINT_ASCII, 4, 4, 4, STEP)

    S.sfx_chisel = eng.audio.synth("triangle", 880, 0.06, 1320)
    S.sfx_pack = eng.audio.synth("sine", 420, 0.08, 620)

    local floor = eng.scene.spawn("studio_floor")
    eng.scene.set_pos(floor, 0.0, -0.25, -2.0)
    eng.scene.set_scale(floor, 16.0, 0.5, 12.0)
    eng.scene.set_mesh(floor, box_mesh, { tex = floor_tex, color = {0.52, 0.58, 0.66, 1.0} })
    eng.physics.add_body(floor, { shape = "aabb", motion = "static", half_extents = {8.0, 0.25, 6.0} })

    local ped_l = eng.scene.spawn("blueprint_pedestal")
    eng.scene.set_pos(ped_l, -2.2, 0.3, -2.0)
    eng.scene.set_scale(ped_l, 2.6, 0.6, 2.6)
    eng.scene.set_mesh(ped_l, box_mesh, { color = {0.35, 0.40, 0.48, 1.0} })

    local ref_ent = eng.scene.spawn("blueprint_sculpture")
    eng.scene.set_pos(ref_ent, -2.2 - 2.0 * STEP, 0.62, -2.0 - 2.0 * STEP)
    eng.scene.set_mesh(ref_ent, ref_vox, { color = {0.45, 0.95, 0.85, 1.0}, roughness = 0.25, cast_shadow = true })

    local ped_r = eng.scene.spawn("carving_pedestal")
    eng.scene.set_pos(ped_r, 1.8, 0.3, -2.0)
    eng.scene.set_scale(ped_r, 2.6, 0.6, 2.6)
    eng.scene.set_mesh(ped_r, box_mesh, { color = {0.35, 0.40, 0.48, 1.0} })

    -- Parse blueprint & spawn full 4x4x4 working ice block (starts at 50% accuracy)
    S.blueprint = {}
    S.ice = {}
    for y = 1, 4 do
        S.blueprint[y] = {}
        S.ice[y] = {}
        local row_idx = 1
        local layer_str = BLUEPRINT_ASCII[y]
        for row in string.gmatch(layer_str, "[^\n]+") do
            S.blueprint[y][row_idx] = {}
            S.ice[y][row_idx] = {}
            for x = 1, 4 do
                local ch = string.sub(row, x, x)
                S.blueprint[y][row_idx][x] = (ch ~= ".") and 1 or 0

                local wx, wy, wz = cell_world_pos(x, y, row_idx)
                local ie = eng.scene.spawn(string.format("ice_%d_%d_%d", x, y, row_idx))
                eng.scene.set_pos(ie, wx - 0.23, wy - 0.23, wz - 0.23)
                eng.scene.set_mesh(ie, S.sub_vox, { color = {0.72, 0.90, 1.0, 1.0}, roughness = 0.18, cast_shadow = true })
                S.ice[y][row_idx][x] = ie
            end
            row_idx = row_idx + 1
        end
    end

    S.cx, S.cy, S.cz = 1, 4, 1
    S.cursor_ent = eng.scene.spawn("chisel_cursor")
    local kx, ky, kz = cell_world_pos(S.cx, S.cy, S.cz)
    eng.scene.set_pos(S.cursor_ent, kx, ky, kz)
    eng.scene.set_scale(S.cursor_ent, 0.54, 0.54, 0.54)
    eng.scene.set_mesh(S.cursor_ent, box_mesh, { color = {1.0, 0.85, 0.2, 1.0} })

    S.chiseled_count = 0
    S.accuracy = compute_accuracy()
    S.won = false

    eng.camera.look_at(-0.2, 3.8, 3.6, -0.2, 1.4, -2.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    local _ = dt
    if S.won then return end

    if eng.input.pressed("left") then S.cx = (S.cx > 1) and (S.cx - 1) or 4 end
    if eng.input.pressed("right") then S.cx = (S.cx < 4) and (S.cx + 1) or 1 end
    if eng.input.pressed("up") then S.cz = (S.cz > 1) and (S.cz - 1) or 4 end
    if eng.input.pressed("down") then S.cz = (S.cz < 4) and (S.cz + 1) or 1 end
    if eng.input.pressed("jump") then S.cy = (S.cy < 4) and (S.cy + 1) or 1 end

    local kx, ky, kz = cell_world_pos(S.cx, S.cy, S.cz)
    eng.scene.set_pos(S.cursor_ent, kx, ky, kz)

    -- Chisel away ice block
    if eng.input.pressed("fire") then
        local ent = S.ice[S.cy][S.cz][S.cx]
        if ent then
            eng.scene.despawn(ent)
            S.ice[S.cy][S.cz][S.cx] = nil
            S.chiseled_count = S.chiseled_count + 1
            eng.audio.play(S.sfx_chisel, kx, ky, kz, 0)
            S.accuracy = compute_accuracy()
        end
    end

    -- Restore/pack ice block on mistake
    if eng.input.pressed("interact") then
        if not S.ice[S.cy][S.cz][S.cx] then
            local ie = eng.scene.spawn("ice_restored")
            eng.scene.set_pos(ie, kx - 0.23, ky - 0.23, kz - 0.23)
            eng.scene.set_mesh(ie, S.sub_vox, { color = {0.72, 0.90, 1.0, 1.0}, roughness = 0.18, cast_shadow = true })
            S.ice[S.cy][S.cz][S.cx] = ie
            eng.audio.play(S.sfx_pack, kx, ky, kz, 0)
            S.accuracy = compute_accuracy()
        end
    end

    if S.accuracy >= 0.90 and S.chiseled_count >= 26 then
        S.won = true
        eng.save.write("ice_carver_progress", "masterpiece")
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | LAYER Y=%d | CHISELED %d | MATCH %.0f%% (GOAL 90%%)",
        eng.i18n.t("title"), S.cy, S.chiseled_count, S.accuracy * 100.0), 1.0, {0.75, 0.96, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.accuracy / 0.90, "MATCH ")
end
