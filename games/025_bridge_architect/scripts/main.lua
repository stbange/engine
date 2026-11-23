-- 025_bridge_architect: Place structural voxel truss spans across a canyon & run heavy cargo truck physics test
local S = game.state

local SLOT_X = {-3.75, -2.25, -0.75, 0.75, 2.25, 3.75}
local SPAN_COST = 90

local function evaluate_structural_support()
    -- Anchors: Slot 1 touches West Cliff, Slots 3 & 4 rest on Central Stone Pier, Slot 6 touches East Cliff
    local dist = {}
    for i = 1, 6 do
        if S.spans[i] then
            if i == 1 or i == 3 or i == 4 or i == 6 then
                dist[i] = 0
            else
                dist[i] = 99
            end
        end
    end
    for _ = 1, 6 do
        for i = 1, 6 do
            if S.spans[i] then
                if i > 1 and dist[i - 1] and dist[i - 1] + 1 < dist[i] then dist[i] = dist[i - 1] + 1 end
                if i < 6 and dist[i + 1] and dist[i + 1] + 1 < dist[i] then dist[i] = dist[i + 1] + 1 end
            end
        end
    end
    return dist
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 5, fog_density = 0.014 })
    eng.render.set_sky(0.14, 0.24, 0.42, 0.55, 0.65, 0.76)
    eng.render.add_light({ type = "dir", dir = {-0.4, -1.0, -0.5}, color = {2.2, 2.1, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.0, 2.5}, color = {1.5, 1.4, 1.2}, range = 26.0 })

    local seed = math.floor(eng.math.range(100, 99999))
    local rock_tex = eng.procgen.texture("cobble", seed, 64)
    local box_mesh = eng.asset.box(1, 1, 1)
    local arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")

    S.span_vox = eng.asset.voxel_ascii({
        "3..3\n3..3\n3..3",
        "7777\n7667\n7777"
    }, 4, 2, 3, 0.37)

    S.truck_vox = eng.asset.voxel_ascii({
        "1111\n1111",
        "4466\n4466",
        "..66\n..66"
    }, 4, 3, 2, 0.42)

    S.sfx_build = eng.audio.synth("square", 460, 0.08, 680)
    S.sfx_horn = eng.audio.synth("saw", 220, 0.20, 220)

    -- Canyon riverbed & West/East cliff abutments (top deck at y = 0.0)
    local gorge = eng.scene.spawn("canyon_floor")
    eng.scene.set_pos(gorge, 0.0, -5.25, 0.0)
    eng.scene.set_scale(gorge, 24.0, 0.5, 10.0)
    eng.scene.set_mesh(gorge, box_mesh, { tex = rock_tex, color = {0.32, 0.46, 0.58, 1.0} })
    eng.physics.add_body(gorge, { shape = "aabb", motion = "static", half_extents = {12.0, 0.25, 5.0} })

    local west_cliff = eng.scene.spawn("west_cliff")
    eng.scene.set_pos(west_cliff, -6.75, -2.5, 0.0)
    eng.scene.set_scale(west_cliff, 4.46, 5.0, 3.2)
    eng.scene.set_mesh(west_cliff, box_mesh, { tex = rock_tex, color = {0.58, 0.48, 0.38, 1.0} })
    eng.physics.add_body(west_cliff, { shape = "aabb", motion = "static", half_extents = {2.23, 2.5, 1.6} })

    local east_cliff = eng.scene.spawn("east_cliff")
    eng.scene.set_pos(east_cliff, 6.75, -2.5, 0.0)
    eng.scene.set_scale(east_cliff, 4.46, 5.0, 3.2)
    eng.scene.set_mesh(east_cliff, box_mesh, { tex = rock_tex, color = {0.58, 0.48, 0.38, 1.0} })
    eng.physics.add_body(east_cliff, { shape = "aabb", motion = "static", half_extents = {2.23, 2.5, 1.6} })

    local pier = eng.scene.spawn("central_stone_pier")
    eng.scene.set_pos(pier, 0.0, -2.75, 0.0)
    eng.scene.set_scale(pier, 0.9, 4.5, 2.2)
    eng.scene.set_mesh(pier, box_mesh, { tex = rock_tex, color = {0.52, 0.52, 0.56, 1.0} })

    local flag = eng.scene.spawn("goal_flag_arch")
    eng.scene.set_pos(flag, 6.6, 0.0, 0.0)
    eng.scene.set_rot_deg(flag, 0.0, 90.0, 0.0)
    eng.scene.set_scale(flag, 0.85, 0.85, 0.85)
    eng.scene.set_mesh(flag, arch_mesh, { color = {0.25, 0.95, 0.45, 1.0} })

    -- Heavy Cargo Truck dynamic physics body resting cleanly on West Cliff
    S.truck_ent = eng.scene.spawn("heavy_cargo_truck")
    eng.scene.set_pos(S.truck_ent, -6.6, 0.60, 0.0)
    local t_vis = eng.scene.spawn("truck_vis")
    eng.scene.set_parent(t_vis, S.truck_ent)
    eng.scene.set_pos(t_vis, -0.84, -0.56, -0.42)
    eng.scene.set_mesh(t_vis, S.truck_vox, { cast_shadow = true })
    S.truck_body = eng.physics.add_body(S.truck_ent, { shape = "aabb", motion = "dynamic", half_extents = {0.84, 0.56, 0.55} })

    S.sel_slot = 1
    S.cursor_ent = eng.scene.spawn("span_cursor")
    eng.scene.set_pos(S.cursor_ent, SLOT_X[1], 0.15, 0.0)
    eng.scene.set_scale(S.cursor_ent, 1.35, 0.14, 1.3)
    eng.scene.set_mesh(S.cursor_ent, box_mesh, { color = {1.0, 0.92, 0.25, 1.0} })

    S.spans = {}
    S.spans_placed = 0
    S.budget = 600
    S.mode = "build"
    S.max_stress_pct = 0.0
    S.truck_x = -6.6
    S.step_cd = 0.0
    S.won = false

    eng.camera.look_at(0.0, 4.4, 10.6, 0.0, -0.4, 0.0, 0)
    eng.mod.emit("post_init")
end

local function reset_truck()
    S.mode = "build"
    eng.scene.set_pos(S.truck_ent, -6.6, 0.60, 0.0)
    eng.physics.set_vel(S.truck_body, 0.0, 0.0, 0.0)
end

function update(dt)
    if S.won then return end
    S.step_cd = math.max(0.0, S.step_cd - dt)

    if S.mode == "build" then
        -- Hold parked on west abutment during construction
        eng.scene.set_pos(S.truck_ent, -6.6, 0.60, 0.0)
        eng.physics.set_vel(S.truck_body, 0.0, 0.0, 0.0)

        local mx, _ = eng.input.axis2d("left", "right", "down", "up")
        if math.abs(mx) > 0.4 and S.step_cd <= 0.0 then
            S.step_cd = 0.12
            S.sel_slot = eng.math.clamp(S.sel_slot + (mx > 0 and 1 or -1), 1, 6)
        end
        eng.scene.set_pos(S.cursor_ent, SLOT_X[S.sel_slot], 0.15, 0.0)

        if eng.input.pressed("fire") and not S.spans[S.sel_slot] and S.budget >= SPAN_COST then
            S.budget = S.budget - SPAN_COST
            S.spans_placed = S.spans_placed + 1
            local sx = SLOT_X[S.sel_slot]
            local se = eng.scene.spawn("bridge_span_" .. S.sel_slot)
            eng.scene.set_pos(se, sx, -0.25, 0.0)
            local sv = eng.scene.spawn("bridge_span_vis_" .. S.sel_slot)
            eng.scene.set_parent(sv, se)
            eng.scene.set_pos(sv, -0.74, -0.49, -0.55)
            eng.scene.set_mesh(sv, S.span_vox, { cast_shadow = true })
            local sb = eng.physics.add_body(se, { shape = "aabb", motion = "static", half_extents = {0.73, 0.25, 1.1} })
            S.spans[S.sel_slot] = { ent = se, vis = sv, body = sb, x = sx }
            eng.audio.play(S.sfx_build, sx, 0.0, 0.0, 0)
        end

        if eng.input.pressed("interact") or eng.input.pressed("jump") then
            local support = evaluate_structural_support()
            for i = 1, 6 do
                if S.spans[i] and support[i] > 1 then
                    eng.scene.despawn(S.spans[i].vis)
                    eng.scene.despawn(S.spans[i].ent)
                    S.spans[i] = nil
                    S.spans_placed = S.spans_placed - 1
                end
            end
            S.mode = "drive"
            eng.audio.play(S.sfx_horn, -6.6, 0.8, 0.0, 0)
        end
    else
        local tx, ty, _ = eng.scene.get_pos(S.truck_ent)
        S.truck_x = tx
        local _, vy, _ = eng.physics.get_vel(S.truck_body)
        if ty > -0.2 then
            eng.physics.set_vel(S.truck_body, 6.0, vy, 0.0)
            if math.abs(tx) < 4.5 then S.max_stress_pct = math.max(S.max_stress_pct, 68.0) end
        end

        if ty < -2.4 then
            reset_truck()
        elseif tx >= 6.2 and ty > 0.1 then
            S.won = true
            eng.physics.set_vel(S.truck_body, 0.0, 0.0, 0.0)
            eng.save.write("bridge_architect_progress", "clear")
        end
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 56, 1280, 720)
    eng.ui.label(x, y, string.format("%s | SPANS %d/6 | BUDGET $%d | STRESS %.0f%%",
        eng.i18n.t("title"), S.spans_placed, S.budget, S.max_stress_pct), 1.0, {0.95, 0.92, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 220, eng.math.clamp((S.truck_x + 6.6) / 12.8, 0.0, 1.0), "CROSS ")
end
