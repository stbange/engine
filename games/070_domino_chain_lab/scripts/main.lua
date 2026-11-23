-- 070_domino_chain_lab: Place missing domino slabs in gaps & flick starter domino (`fire`) to topple the golden bell!
local S = game.state

local function clear_stage()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
    S.dominoes = {}
end

local function spawn_domino_slab(dom, col)
    if dom.slab_ent then eng.scene.despawn(dom.slab_ent) end
    local se = eng.scene.spawn("domino_slab_" .. tostring(dom.idx))
    eng.scene.set_parent(se, dom.piv)
    eng.scene.set_pos(se, 0.0, 0.58, 0.0)
    eng.scene.set_scale(se, 0.54, 1.16, 0.16)
    eng.scene.set_mesh(se, S.box_mesh, { color = col, roughness = 0.35, cast_shadow = true })
    dom.slab_ent = se
    S.ents[#S.ents + 1] = se
end

local function count_gaps()
    local g = 0
    for i = 1, #S.dominoes do
        if not S.dominoes[i].present then g = g + 1 end
    end
    S.gaps_left = g
end

local function reset_chain()
    S.chain_running = false
    S.stall_timer = 0.0
    for i = 1, #S.dominoes do
        local d = S.dominoes[i]
        d.toppling = false
        d.passed_on = false
        d.tilt = 0.0
        eng.scene.set_rot_deg(d.piv, 0.0, d.yaw, 0.0)
    end
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    S.chain_running = false
    S.bell_hit = false
    S.bell_tilt = 0.0
    S.stall_timer = 0.0

    local bench = eng.scene.spawn("lab_workbench")
    eng.scene.set_pos(bench, 0.0, -0.25, 0.0)
    eng.scene.set_scale(bench, 16.5, 0.5, 9.5)
    eng.scene.set_mesh(bench, S.box_mesh, { tex = S.wood_tex, color = {0.68, 0.48, 0.30, 1.0} })
    S.ents[#S.ents + 1] = bench

    local n_slots = (idx == 1) and 13 or 16
    local gap_map = {}
    if idx == 1 then
        gap_map[4], gap_map[8], gap_map[11] = true, true, true
    else
        gap_map[3], gap_map[7], gap_map[10], gap_map[14] = true, true, true, true
        -- Raised central wooden overpass deck for slots 6..11
        local bridge = eng.scene.spawn("lab_overpass")
        eng.scene.set_pos(bridge, -0.2, 0.30, 0.0)
        eng.scene.set_scale(bridge, 5.2, 0.60, 4.6)
        eng.scene.set_mesh(bridge, S.box_mesh, { tex = S.wood_tex, color = {0.56, 0.38, 0.24, 1.0}, cast_shadow = true })
        S.ents[#S.ents + 1] = bridge
    end

    local pts = {}
    for i = 1, n_slots do
        local u = (i - 1) / (n_slots - 1)
        local x = -5.4 + u * 10.4
        local z = math.sin(u * math.pi * 2.0) * 1.9
        local y = 0.0
        if idx == 2 and i >= 6 and i <= 11 then
            y = 0.60
        elseif idx == 2 and (i == 5 or i == 12) then
            y = 0.30
        end
        pts[i] = { x = x, y = y, z = z }
    end

    S.bell_x, S.bell_y, S.bell_z = 5.9, 0.0, 0.0
    local ped = eng.scene.spawn("bell_pedestal")
    eng.scene.set_pos(ped, S.bell_x, 0.2, S.bell_z)
    eng.scene.set_scale(ped, 1.1, 0.4, 1.1)
    eng.scene.set_mesh(ped, S.box_mesh, { tex = S.brass_tex, color = {0.52, 0.44, 0.36, 1.0}, cast_shadow = true })
    S.ents[#S.ents + 1] = ped

    S.bell_piv = eng.scene.spawn("golden_bell_pivot")
    eng.scene.set_pos(S.bell_piv, S.bell_x, 0.4, S.bell_z)
    S.ents[#S.ents + 1] = S.bell_piv

    local bell_dome = eng.scene.spawn("golden_bell_dome")
    eng.scene.set_parent(bell_dome, S.bell_piv)
    eng.scene.set_pos(bell_dome, 0.0, 0.65, 0.0)
    eng.scene.set_mesh(bell_dome, S.bell_mesh, { color = {1.0, 0.84, 0.18, 1.0}, metallic = 0.95, roughness = 0.14, cast_shadow = true })
    S.ents[#S.ents + 1] = bell_dome

    for i = 1, n_slots do
        local p = pts[i]
        local nx = (i < n_slots) and pts[i + 1].x or S.bell_x
        local nz = (i < n_slots) and pts[i + 1].z or S.bell_z
        local yaw = math.deg(math.atan2(-(nx - p.x), -(nz - p.z)))

        local piv = eng.scene.spawn("domino_piv_" .. tostring(i))
        eng.scene.set_pos(piv, p.x, p.y, p.z)
        eng.scene.set_rot_deg(piv, 0.0, yaw, 0.0)
        S.ents[#S.ents + 1] = piv

        local is_gap = (gap_map[i] == true)
        local pad_e = nil
        if is_gap then
            pad_e = eng.scene.spawn("gap_slot_" .. tostring(i))
            eng.scene.set_pos(pad_e, p.x, p.y + 0.04, p.z)
            eng.scene.set_rot_deg(pad_e, 0.0, yaw, 0.0)
            eng.scene.set_scale(pad_e, 0.66, 0.08, 0.32)
            eng.scene.set_mesh(pad_e, S.box_mesh, { color = {0.22, 0.92, 1.0, 1.0} })
            S.ents[#S.ents + 1] = pad_e
        end

        local dom = {
            idx = i, x = p.x, y = p.y, z = p.z, yaw = yaw,
            piv = piv, pad_ent = pad_e, slab_ent = nil,
            present = (not is_gap), toppling = false, passed_on = false, tilt = 0.0
        }
        if dom.present then
            local col = (i == 1) and {0.96, 0.24, 0.26, 1.0} or {0.95, 0.93, 0.86, 1.0}
            spawn_domino_slab(dom, col)
        end
        S.dominoes[i] = dom
    end

    S.cx, S.cz = -2.5, 0.0
    S.cursor_ent = eng.scene.spawn("lab_cursor")
    eng.scene.set_pos(S.cursor_ent, S.cx, 1.65, S.cz)
    eng.scene.set_scale(S.cursor_ent, 0.45, 0.45, 0.45)
    eng.scene.set_mesh(S.cursor_ent, S.crystal_mesh, { color = {0.30, 1.0, 0.65, 1.0} })
    S.ents[#S.ents + 1] = S.cursor_ent

    count_gaps()
    eng.camera.look_at(0.0, 8.8, 9.6, 0.2, 0.4, 0.0, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.009 })
    eng.render.set_sky(0.16, 0.26, 0.42, 0.62, 0.68, 0.76)
    eng.render.add_light({ type = "dir", dir = {-0.35, -0.9, -0.4}, color = {2.2, 2.1, 1.95}, shadow = true })
    eng.render.add_light({ type = "point", pos = {1.5, 5.0, 1.5}, color = {2.2, 1.9, 1.4}, range = 26.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.wood_tex = eng.procgen.texture("wood_grain", seed_base, 64)
    S.brass_tex = eng.procgen.texture("metal_rivets", seed_base + 13, 64)

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.bell_mesh = eng.asset.cylinder(0.62, 0.26, 1.25, 14)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_place = eng.audio.synth("triangle", 440, 0.08, 620)
    S.sfx_click = eng.audio.synth("square", 620, 0.04, 420)
    S.sfx_bell = eng.audio.synth("sine", 880, 0.32, 1320)

    S.placed_total = 0
    S.flicks = 0
    S.toppled_total = 0
    S.bells_rung = 0
    S.gaps_left = 3
    S.act_cd = 0.0
    S.won = false

    build_stage(1)
    eng.mod.emit("post_init")
end

local function nearest_open_gap(max_r)
    local best, best_d = nil, max_r
    for i = 1, #S.dominoes do
        local d = S.dominoes[i]
        if not d.present then
            local dist = eng.math.dist3(S.cx, 0.0, S.cz, d.x, 0.0, d.z)
            if dist < best_d then
                best_d = dist
                best = d
            end
        end
    end
    return best
end

function update(dt)
    if S.won then return end
    S.act_cd = math.max(0.0, S.act_cd - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        S.cx = eng.math.clamp(S.cx + mx * 14.5 * dt, -6.5, 6.5)
        S.cz = eng.math.clamp(S.cz - my * 14.5 * dt, -3.6, 3.6)
        eng.scene.set_pos(S.cursor_ent, S.cx, 1.65, S.cz)
    end

    if not S.chain_running then
        local place_press = eng.input.pressed("jump") or eng.input.pressed("interact")
        local fire_press = eng.input.pressed("fire")

        if (place_press or fire_press) and S.act_cd <= 0.0 then
            local gap = nearest_open_gap(1.15)
            if gap and (place_press or S.gaps_left > 0) then
                gap.present = true
                if gap.pad_ent then
                    eng.scene.despawn(gap.pad_ent)
                    gap.pad_ent = nil
                end
                spawn_domino_slab(gap, {0.45, 0.92, 0.72, 1.0})
                S.placed_total = S.placed_total + 1
                S.act_cd = 0.07
                count_gaps()
                eng.audio.play(S.sfx_place, gap.x, gap.y + 0.6, gap.z, 0)
            elseif fire_press then
                -- Flick the crimson starter domino (#1) to launch the chain reaction!
                S.chain_running = true
                S.flicks = S.flicks + 1
                S.dominoes[1].toppling = true
                S.toppled_total = S.toppled_total + 1
                S.act_cd = 0.12
                eng.audio.play(S.sfx_click, S.dominoes[1].x, 0.6, S.dominoes[1].z, 0)
            end
        end
    else
        local any_moving = false
        for i = 1, #S.dominoes do
            local d = S.dominoes[i]
            if d.toppling and d.tilt < 72.0 then
                any_moving = true
                d.tilt = math.min(72.0, d.tilt + 520.0 * dt)
                eng.scene.set_rot_deg(d.piv, -d.tilt, d.yaw, 0.0)
                if d.tilt >= 24.0 and not d.passed_on then
                    d.passed_on = true
                    if i < #S.dominoes then
                        local nxt = S.dominoes[i + 1]
                        if nxt.present then
                            nxt.toppling = true
                            S.toppled_total = S.toppled_total + 1
                            eng.audio.play(S.sfx_click, nxt.x, nxt.y + 0.6, nxt.z, 0)
                        end
                    else
                        S.bell_hit = true
                        S.bells_rung = S.bells_rung + 1
                        eng.audio.play(S.sfx_bell, S.bell_x, 1.0, S.bell_z, 0)
                    end
                end
            end
        end

        if S.bell_hit then
            S.bell_tilt = math.min(68.0, S.bell_tilt + 320.0 * dt)
            eng.scene.set_rot_deg(S.bell_piv, 0.0, 0.0, -S.bell_tilt)
            if S.bell_tilt >= 66.0 then
                if S.stage < 2 then
                    eng.save.write("domino_chain_lab", "track_2")
                    build_stage(S.stage + 1)
                else
                    S.won = true
                    eng.save.write("domino_chain_lab", "clear")
                end
            end
        elseif not any_moving then
            -- Chain stalled at an unfilled gap; reset upright so player can place the missing slab
            S.stall_timer = S.stall_timer + dt
            if S.stall_timer >= 0.35 then
                reset_chain()
            end
        end
    end
end

function draw()
    eng.render.draw_sprite(S.bell_x, 1.85, S.bell_z, 0.55, 0.55, S.orb_tex)
    local x, y = eng.ui.anchor("top_left", 16, 14, 640, 52, 1280, 720)
    local hint = (S.gaps_left == 0 and not S.chain_running) and (" | " .. eng.i18n.t("ready")) or ""
    local win_txt = S.won and (" | " .. eng.i18n.t("victory")) or ""
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | TRACK %d/2 | GAPS LEFT %d%s%s", S.stage, S.gaps_left, hint, win_txt), 1.0, {1.0, 0.94, 0.68, 1.0})
    eng.ui.bar(x, y + 24, 240, 1.0 - (S.gaps_left / 4.0), "SLABS ")
end
