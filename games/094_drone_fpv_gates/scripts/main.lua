-- 094_drone_fpv_gates: FPV Quadcopter Race through a Bigger-on-the-Inside Portal Reactor Core
local S = game.state

local function spawn_gate_frame(pocket_id, idx, x, y, z, w, h, col)
    local l = eng.scene.spawn("gate_l_" .. tostring(idx))
    eng.scene.set_pocket(l, pocket_id)
    eng.scene.set_pos(l, x - w * 0.5 - 0.35, y, z)
    eng.scene.set_scale(l, 0.45, h + 0.6, 0.45)
    eng.scene.set_mesh(l, S.box_mesh, { color = col, roughness = 0.25 })

    local r = eng.scene.spawn("gate_r_" .. tostring(idx))
    eng.scene.set_pocket(r, pocket_id)
    eng.scene.set_pos(r, x + w * 0.5 + 0.35, y, z)
    eng.scene.set_scale(r, 0.45, h + 0.6, 0.45)
    eng.scene.set_mesh(r, S.box_mesh, { color = col, roughness = 0.25 })

    local t = eng.scene.spawn("gate_t_" .. tostring(idx))
    eng.scene.set_pocket(t, pocket_id)
    eng.scene.set_pos(t, x, y + h * 0.5 + 0.3, z)
    eng.scene.set_scale(t, w + 1.15, 0.45, 0.45)
    eng.scene.set_mesh(t, S.box_mesh, { color = col, roughness = 0.25 })
end

function init()
    eng.xr.set_mode("cockpit")
    eng.render.set_sky(0.16, 0.44, 0.84, 0.86, 0.62, 0.40)
    eng.render.add_light({ type = "dir", dir = {-0.4, -1.0, -0.35}, color = {2.2, 2.0, 1.75}, shadow = true })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ship_mesh = eng.asset.load_mesh("assets/shared/meshes/starfighter.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local canyon_tex = eng.procgen.texture("stone_brick", seed, 64)
    local reactor_tex = eng.procgen.texture("sci_fi_panel", seed + 19, 64)
    local tree_mesh = eng.procgen.tree(seed + 7, 2, 2.6, 0.2)

    -- Outdoor Canyon (pocket 0)
    local floor_out = eng.scene.spawn("canyon_floor")
    eng.scene.set_pos(floor_out, 0.0, -0.25, -36.0)
    eng.scene.set_scale(floor_out, 36.0, 0.5, 90.0)
    eng.scene.set_mesh(floor_out, S.box_mesh, { tex = canyon_tex, color = {0.76, 0.46, 0.28, 1.0}, roughness = 0.88 })

    for i = 1, 6 do
        local side = (i % 2 == 0) and 1 or -1
        local mesa = eng.scene.spawn("canyon_mesa_" .. tostring(i))
        eng.scene.set_pos(mesa, side * 12.0, 5.0, -i * 11.0)
        eng.scene.set_scale(mesa, 5.0, 10.0, 6.0)
        eng.scene.set_mesh(mesa, S.box_mesh, { tex = canyon_tex, color = {0.72, 0.38, 0.22, 1.0} })

        local tr = eng.scene.spawn("canyon_tree_" .. tostring(i))
        eng.scene.set_pos(tr, side * 7.5, 0.0, -i * 10.0 + 3.0)
        eng.scene.set_mesh(tr, tree_mesh, { cast_shadow = true })
    end

    -- Compact exterior bunker shell around Gate #3 at z = -43 (only 8m x 7m x 4m outside!)
    local bunker = eng.scene.spawn("reactor_bunker_exterior")
    eng.scene.set_pos(bunker, 0.0, 3.5, -43.5)
    eng.scene.set_scale(bunker, 8.5, 7.0, 3.5)
    eng.scene.set_mesh(bunker, S.box_mesh, { tex = reactor_tex, color = {0.25, 0.30, 0.38, 1.0} })

    -- Bigger-on-the-Inside Neon Reactor Core pocket (36m x 18m x 72m inside!)
    S.reactor_id = eng.scene.register_pocket("reactor_core")
    eng.render.add_light({ type = "point", pocket = "reactor_core", pos = {0.0, 10.0, 8.0}, color = {0.4, 2.5, 3.2}, range = 45.0 })
    eng.render.add_light({ type = "point", pocket = "reactor_core", pos = {0.0, 10.0, -14.0}, color = {2.8, 0.4, 2.4}, range = 45.0 })

    local r_floor = eng.scene.spawn("reactor_floor")
    eng.scene.set_pocket(r_floor, S.reactor_id)
    eng.scene.set_pos(r_floor, 0.0, -0.25, 0.0)
    eng.scene.set_scale(r_floor, 36.0, 0.5, 72.0)
    eng.scene.set_mesh(r_floor, S.box_mesh, { tex = reactor_tex, color = {0.14, 0.22, 0.32, 1.0}, metallic = 0.7, roughness = 0.25 })

    for i = 1, 5 do
        for side = -1, 1, 2 do
            local coil = eng.scene.spawn("plasma_coil_" .. tostring(i) .. "_" .. tostring(side))
            eng.scene.set_pocket(coil, S.reactor_id)
            eng.scene.set_pos(coil, side * 9.5, 6.0, 26.0 - i * 10.0)
            eng.scene.set_scale(coil, 1.6, 12.0, 1.6)
            eng.scene.set_mesh(coil, S.box_mesh, { color = {0.2, 0.95, 1.0, 1.0}, roughness = 0.15 })
        end
    end

    -- Seamless Portal Gate #3: Canyon (0, 4.5, -40) -> Reactor (0, 4.5, 26)
    local p3_src = eng.scene.spawn("gate3_portal_src")
    eng.scene.set_pocket(p3_src, 0)
    eng.scene.set_pos(p3_src, 0.0, 4.5, -40.0)

    local p3_dst = eng.scene.spawn("gate3_portal_dst")
    eng.scene.set_pocket(p3_dst, S.reactor_id)
    eng.scene.set_pos(p3_dst, 0.0, 4.5, 26.0)
    eng.scene.set_rot_deg(p3_dst, 0.0, 180.0, 0.0)
    eng.portal.link(p3_src, p3_dst, 6.2, 5.0, 1.0, true, true)

    -- Seamless Exit Portal Gate #6: Reactor (0, 4.5, -24) -> Canyon (0, 4.5, -49)
    local p6_src = eng.scene.spawn("gate6_portal_src")
    eng.scene.set_pocket(p6_src, S.reactor_id)
    eng.scene.set_pos(p6_src, 0.0, 4.5, -24.0)

    local p6_dst = eng.scene.spawn("gate6_portal_dst")
    eng.scene.set_pocket(p6_dst, 0)
    eng.scene.set_pos(p6_dst, 0.0, 4.5, -49.0)
    eng.scene.set_rot_deg(p6_dst, 0.0, 180.0, 0.0)
    eng.portal.link(p6_src, p6_dst, 6.2, 5.0, 1.0, true, true)

    -- 7 FPV Race Gates across both spaces
    S.gates = {
        { pocket = 0,            x =  0.0, y = 4.2, z = -13.0, passed = false },
        { pocket = 0,            x =  1.2, y = 4.5, z = -26.0, passed = false },
        { pocket = 0,            x =  0.0, y = 4.5, z = -40.0, passed = false, is_portal = true },
        { pocket = S.reactor_id, x = -1.2, y = 5.0, z =   9.0, passed = false },
        { pocket = S.reactor_id, x =  1.2, y = 4.6, z =  -8.0, passed = false },
        { pocket = S.reactor_id, x =  0.0, y = 4.5, z = -24.0, passed = false, is_portal = true },
        { pocket = 0,            x =  0.0, y = 4.2, z = -66.0, passed = false }
    }
    for i = 1, #S.gates do
        local g = S.gates[i]
        local col = g.is_portal and {0.2, 0.98, 1.0, 1.0} or {1.0, 0.68, 0.15, 1.0}
        spawn_gate_frame(g.pocket, i, g.x, g.y, g.z, 6.2, 5.0, col)
    end

    -- Visible quadcopter nose craft slightly ahead of FPV cockpit camera
    S.drone_ent = eng.scene.spawn("fpv_quad_nose")
    eng.scene.set_scale(S.drone_ent, 0.45, 0.45, 0.45)
    eng.scene.set_mesh(S.drone_ent, S.ship_mesh, { color = {0.95, 0.35, 0.18, 1.0}, metallic = 0.5, roughness = 0.3 })

    S.sfx_gate = eng.audio.synth("triangle", 620, 0.14, 980)
    S.sfx_warp = eng.audio.synth("saw", 260, 0.22, 780)

    S.pocket = 0
    S.px, S.py, S.pz = 0.0, 4.2, 2.0
    S.roll = 0.0
    S.gates_passed = 0
    S.next_gate = 1
    S.entered_reactor = false
    S.exited_reactor = false
    S.lap_time = 0.0
    S.won = false

    eng.input.set_mouse_lock(true)
    sync_drone_and_cam()
    eng.mod.emit("post_init")
end

function sync_drone_and_cam()
    eng.scene.set_pocket(S.drone_ent, S.pocket)
    eng.scene.set_pos(S.drone_ent, S.px, S.py - 0.38, S.pz - 1.35)
    eng.scene.set_rot_deg(S.drone_ent, -4.0, 0.0, S.roll)
    eng.camera.set(S.px, S.py, S.pz, -1.0, 0.0, S.roll * 0.25, S.pocket)
end

function update(dt)
    if S.won then return end
    S.lap_time = S.lap_time + dt

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    local mdx, mdy = eng.input.mouse_delta()
    local boost = (eng.input.down("fire") or eng.input.down("jump")) and 34.0 or 22.0
    S.roll = eng.math.clamp(-mx * 24.0 - mdx * 0.45, -32.0, 32.0)

    local nx = eng.math.clamp(S.px + mx * 14.0 * dt + mdx * 0.022, -5.0, 5.0)
    local ny = eng.math.clamp(S.py + my * 10.0 * dt - mdy * 0.018, 1.8, 8.5)
    local nz = S.pz - boost * dt

    -- Check gate pass before/across portal warp
    local g = S.gates[S.next_gate]
    if g and g.pocket == S.pocket and S.pz >= g.z and nz <= g.z then
        if math.abs(nx - g.x) < 3.4 and math.abs(ny - g.y) < 2.8 then
            g.passed = true
            S.gates_passed = S.gates_passed + 1
            S.next_gate = S.next_gate + 1
            eng.audio.play(S.sfx_gate, nx, ny, g.z, S.pocket)
        end
    end

    local dst_p, wx, wy, wz = eng.portal.check_crossing(S.pocket, S.px, S.py, S.pz, nx, ny, nz)
    if dst_p then
        if S.pocket == 0 and dst_p == S.reactor_id then S.entered_reactor = true end
        if S.pocket == S.reactor_id and dst_p == 0 then S.exited_reactor = true end
        S.pocket = dst_p
        S.px, S.py, S.pz = wx, wy, wz
        eng.audio.play(S.sfx_warp, S.px, S.py, S.pz, S.pocket)
    else
        S.px, S.py, S.pz = nx, ny, nz
    end

    sync_drone_and_cam()

    if S.gates_passed >= #S.gates then
        S.won = true
        eng.save.write("drone_fpv_best", string.format("%.2f", S.lap_time))
    end
end

function draw()
    local g = S.gates[S.next_gate]
    if g and g.pocket == S.pocket then
        eng.render.draw_sprite(g.x, g.y, g.z, 1.2, 1.2, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 540, 28, 1280, 720)
    local zone = (S.pocket == S.reactor_id) and "REACTOR CORE" or "CANYON"
    eng.ui.label(x, y, eng.i18n.t("title") .. " | " .. zone .. " | GATES " .. S.gates_passed .. "/7", 1.0, {0.35, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.gates_passed / 7.0, "COURSE ")
end
