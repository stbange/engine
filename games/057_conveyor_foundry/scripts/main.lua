-- 057_conveyor_foundry: Rotate directional 3D conveyor belts (Ore -> Smelter -> Shipping Crate)
local S = game.state

local GW, GH = 5, 4
local CS = 2.5
-- dir: 0 = East (+X), 1 = South (+Z), 2 = West (-X), 3 = North (-Z)
local DIR_DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local DIR_DZ = { [0] = 0, [1] = 1, [2] =  0, [3] = -1 }
local DIR_YAW = { [0] = -90.0, [1] = 180.0, [2] = 90.0, [3] = 0.0 }

local function cell_pos(gx, gz)
    return (gx - 3.0) * CS, (gz - 2.5) * CS
end

local function cell_idx(gx, gz)
    return (gz - 1) * GW + gx
end

local function refresh_belt_rot(c)
    if c.arrow_ent then
        eng.scene.set_rot_deg(c.arrow_ent, 0.0, DIR_YAW[c.dir], 0.0)
    end
end

local function spawn_ore()
    local c = S.cells[cell_idx(1, 1)]
    local ent = eng.scene.spawn("ore_item_" .. tostring(S.spawned + 1))
    eng.scene.set_pos(ent, c.x, 0.68, c.z)
    eng.scene.set_scale(ent, 0.65, 0.55, 0.65)
    eng.scene.set_mesh(ent, S.crystal_mesh, { color = {0.30, 0.82, 1.0, 1.0}, cast_shadow = true })
    S.spawned = S.spawned + 1
    S.items[#S.items + 1] = {
        ent = ent, gx = 1, gz = 1, prog = 0.0, smelted = false, active = true
    }
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.011 })
    eng.render.set_sky(0.08, 0.09, 0.13, 0.28, 0.18, 0.12)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {1.9, 1.85, 1.75}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.5, -1.2}, color = {2.8, 1.4, 0.5}, range = 26.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.85, 0.85, 0.2, 10)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.crate_mesh = eng.asset.load_mesh("assets/shared/meshes/crate.obj")
    S.chest_mesh = eng.asset.load_mesh("assets/shared/meshes/chest.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.floor_tex = eng.procgen.texture("rust_metal", seed_base, 64)
    S.panel_tex = eng.procgen.texture("sci_fi_panel", seed_base + 7, 64)
    S.sfx_rot = eng.audio.synth("square", 460, 0.08, 640)
    S.sfx_smelt = eng.audio.synth("saw", 240, 0.14, 480)
    S.sfx_ship = eng.audio.synth("triangle", 580, 0.16, 920)
    S.sfx_scrap = eng.audio.synth("noise", 160, 0.15, 70)

    local floor_e = eng.scene.spawn("foundry_floor")
    eng.scene.set_pos(floor_e, 0.0, -0.25, 0.0)
    eng.scene.set_scale(floor_e, 18.0, 0.5, 15.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = S.floor_tex, color = {0.46, 0.44, 0.48, 1.0} })

    S.cells = {}
    for gz = 1, GH do
        for gx = 1, GW do
            local wx, wz = cell_pos(gx, gz)
            local kind = "belt"
            local dir = 0
            if gx == 1 and gz == 1 then kind = "extractor"; dir = 0
            elseif gx == 3 and gz == 2 then kind = "smelter"; dir = 0
            elseif gx == 5 and gz == 3 then kind = "crate"; dir = 0
            elseif gx == 2 and gz == 1 then dir = 3 -- misaligned! needs 1 (South)
            elseif gx == 2 and gz == 2 then dir = 2 -- misaligned! needs 0 (East)
            elseif gx == 4 and gz == 2 then dir = 3 -- misaligned! needs 1 (South)
            elseif gx == 4 and gz == 3 then dir = 2 -- misaligned! needs 0 (East)
            end

            local base = eng.scene.spawn("tile_" .. tostring(gx) .. "_" .. tostring(gz))
            eng.scene.set_pos(base, wx, 0.15, wz)
            eng.scene.set_scale(base, 2.1, 0.3, 2.1)

            local arrow_ent = nil
            if kind == "extractor" then
                eng.scene.set_mesh(base, S.box_mesh, { tex = S.panel_tex, color = {0.25, 0.68, 0.92, 1.0}, cast_shadow = true })
                local drill = eng.scene.spawn("extractor_head")
                eng.scene.set_pos(drill, wx, 0.85, wz)
                eng.scene.set_scale(drill, 1.1, 1.1, 1.1)
                eng.scene.set_mesh(drill, S.crate_mesh, { color = {0.35, 0.85, 1.0, 1.0}, cast_shadow = true })
            elseif kind == "smelter" then
                eng.scene.set_mesh(base, S.box_mesh, { tex = S.floor_tex, color = {0.88, 0.35, 0.15, 1.0}, cast_shadow = true })
                local f_hood = eng.scene.spawn("blast_smelter_hood")
                eng.scene.set_pos(f_hood, wx, 1.15, wz - 0.35)
                eng.scene.set_scale(f_hood, 1.6, 1.7, 1.1)
                eng.scene.set_mesh(f_hood, S.box_mesh, { tex = S.floor_tex, color = {0.95, 0.45, 0.18, 1.0}, cast_shadow = true })
            elseif kind == "crate" then
                eng.scene.set_mesh(base, S.box_mesh, { tex = S.panel_tex, color = {0.28, 0.82, 0.42, 1.0}, cast_shadow = true })
                local dock = eng.scene.spawn("shipping_crate")
                eng.scene.set_pos(dock, wx, 0.3, wz)
                eng.scene.set_scale(dock, 1.45, 1.35, 1.45)
                eng.scene.set_mesh(dock, S.chest_mesh, { color = {0.92, 0.76, 0.28, 1.0}, cast_shadow = true })
            else
                eng.scene.set_mesh(base, S.box_mesh, { tex = S.panel_tex, color = {0.30, 0.34, 0.40, 1.0} })
                arrow_ent = eng.scene.spawn("belt_arrow_" .. tostring(gx) .. "_" .. tostring(gz))
                eng.scene.set_pos(arrow_ent, wx, 0.36, wz)
                local shaft = eng.scene.spawn("arrow_shaft_" .. tostring(gx) .. "_" .. tostring(gz))
                eng.scene.set_parent(shaft, arrow_ent)
                eng.scene.set_pos(shaft, 0.0, 0.0, 0.15)
                eng.scene.set_scale(shaft, 0.36, 0.12, 1.1)
                eng.scene.set_mesh(shaft, S.box_mesh, { color = {0.98, 0.84, 0.18, 1.0} })

                local tip = eng.scene.spawn("arrow_tip_" .. tostring(gx) .. "_" .. tostring(gz))
                eng.scene.set_parent(tip, arrow_ent)
                eng.scene.set_pos(tip, 0.0, 0.02, -0.48)
                eng.scene.set_scale(tip, 0.82, 0.14, 0.38)
                eng.scene.set_mesh(tip, S.box_mesh, { color = {1.0, 0.95, 0.35, 1.0} })
            end

            local cell = { gx = gx, gz = gz, x = wx, z = wz, kind = kind, dir = dir, arrow_ent = arrow_ent }
            refresh_belt_rot(cell)
            S.cells[#S.cells + 1] = cell
        end
    end

    S.sel_gx, S.sel_gz = 2, 1
    S.cx, S.cz = cell_pos(S.sel_gx, S.sel_gz)
    S.cursor_ent = eng.scene.spawn("foundry_cursor")
    eng.scene.set_pos(S.cursor_ent, S.cx, 0.42, S.cz)
    eng.scene.set_mesh(S.cursor_ent, S.cyl_mesh, { color = {0.25, 1.0, 0.55, 1.0} })

    S.items = {}
    S.spawned = 0
    S.shipped = 0
    S.target_ship = 6
    S.scrap = 0
    S.rotations = 0
    S.spawn_timer = 0.35
    S.overdrive = 0.0
    S.rot_cd = 0.0
    S.won = false
    S.lost = false

    spawn_ore()
    eng.camera.look_at(0.0, 14.5, 11.5, 0.0, 0.4, 0.0, 0)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or S.lost then return end
    S.rot_cd = math.max(0.0, S.rot_cd - dt)
    S.overdrive = math.max(0.0, S.overdrive - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.cx = eng.math.clamp(S.cx + mx * 13.0 * dt, -5.5, 5.5)
        S.cz = eng.math.clamp(S.cz - my * 13.0 * dt, -4.2, 4.2)
        S.sel_gx = eng.math.clamp(math.floor((S.cx / CS) + 3.5), 1, GW)
        S.sel_gz = eng.math.clamp(math.floor((S.cz / CS) + 3.0), 1, GH)
    end
    local sc = S.cells[cell_idx(S.sel_gx, S.sel_gz)]
    eng.scene.set_pos(S.cursor_ent, sc.x, 0.42, sc.z)

    -- Interact: Rotate selected 3D conveyor belt 90 degrees clockwise
    if eng.input.pressed("interact") and S.rot_cd <= 0.0 and sc.kind == "belt" then
        S.rot_cd = 0.06
        sc.dir = (sc.dir + 1) % 4
        S.rotations = S.rotations + 1
        refresh_belt_rot(sc)
        eng.audio.play(S.sfx_rot, sc.x, 0.8, sc.z, 0)
    end

    -- Fire: Foundry Overdrive speed burst
    if eng.input.pressed("fire") or eng.input.down("fire") then
        S.overdrive = 0.5
    end

    local speed_mul = (S.overdrive > 0.0) and 2.8 or 1.15
    S.spawn_timer = S.spawn_timer - dt * speed_mul
    if S.spawn_timer <= 0.0 and #S.items < 18 then
        S.spawn_timer = 0.72
        spawn_ore()
    end

    for i = 1, #S.items do
        local it = S.items[i]
        if it.active then
            local cur = S.cells[cell_idx(it.gx, it.gz)]
            it.prog = it.prog + dt * 2.1 * speed_mul
            local nx = it.gx + DIR_DX[cur.dir]
            local nz = it.gz + DIR_DZ[cur.dir]
            local wx0, wz0 = cur.x, cur.z
            local wx1, wz1 = cell_pos(nx, nz)
            local t = math.min(1.0, it.prog)
            eng.scene.set_pos(it.ent, wx0 + (wx1 - wx0) * t, 0.68, wz0 + (wz1 - wz0) * t)

            if it.prog >= 1.0 then
                it.prog = 0.0
                if nx < 1 or nx > GW or nz < 1 or nz > GH then
                    it.active = false
                    eng.scene.despawn(it.ent)
                    S.scrap = S.scrap + 1
                    eng.audio.play(S.sfx_scrap, wx0, 0.8, wz0, 0)
                else
                    it.gx, it.gz = nx, nz
                    local dst = S.cells[cell_idx(nx, nz)]
                    if dst.kind == "smelter" and (not it.smelted) then
                        it.smelted = true
                        eng.scene.set_mesh(it.ent, S.box_mesh, { color = {1.0, 0.68, 0.14, 1.0}, metallic = 0.85, roughness = 0.25 })
                        eng.scene.set_scale(it.ent, 0.75, 0.38, 0.48)
                        eng.audio.play(S.sfx_smelt, dst.x, 1.0, dst.z, 0)
                    elseif dst.kind == "crate" then
                        it.active = false
                        eng.scene.despawn(it.ent)
                        if it.smelted then
                            S.shipped = S.shipped + 1
                            eng.audio.play(S.sfx_ship, dst.x, 1.0, dst.z, 0)
                        else
                            S.scrap = S.scrap + 1
                            eng.audio.play(S.sfx_scrap, dst.x, 1.0, dst.z, 0)
                        end
                    end
                end
            end
        end
    end

    if S.scrap >= 6 then
        S.lost = true
        eng.save.write("foundry_status", "scrap_overflow")
    elseif S.shipped >= S.target_ship then
        S.won = true
        eng.save.write("foundry_status", "quota_met")
    end
end

function draw()
    local sm = S.cells[cell_idx(3, 2)]
    eng.render.draw_sprite(sm.x, 2.35, sm.z - 0.3, 0.9, 0.9, S.orb_tex)

    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 54, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or (S.lost and (" | " .. eng.i18n.t("defeat")) or "")
    eng.ui.label(x, y, eng.i18n.t("title") .. " | SCRAP: " .. S.scrap .. "/6 | BELT TURNS: " .. S.rotations .. status, 1.0, {1.0, 0.88, 0.45, 1.0})
    eng.ui.bar(x, y + 24, 240, S.shipped / S.target_ship, "INGOTS " .. S.shipped .. "/6 ")
end
