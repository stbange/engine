-- 068_pipe_pressure_3d: Rotate 3D elbow & T-junction steam pipes inside a boiler cube before pressure bursts
local S = game.state

local PX, NX, PY, NY, PZ, NZ = 1, 2, 3, 4, 5, 6
local OPP = { [1] = 2, [2] = 1, [3] = 4, [4] = 3, [5] = 6, [6] = 5 }
local DV = {
    [1] = { 1,  0,  0}, [2] = {-1,  0,  0},
    [3] = { 0,  1,  0}, [4] = { 0, -1,  0},
    [5] = { 0,  0,  1}, [6] = { 0,  0, -1}
}
local ARM_ROT = {
    [1] = {0.0, 0.0, 90.0}, [2] = {0.0, 0.0, 90.0},
    [3] = {0.0, 0.0,  0.0}, [4] = {0.0, 0.0,  0.0},
    [5] = {90.0, 0.0, 0.0}, [6] = {90.0, 0.0, 0.0}
}

local function grid_world(gx, gy, gz)
    return (gx - 2.0) * 2.2, 1.2 + (gy - 1.0) * 2.2, (gz - 1.5) * 2.2
end

local function clear_stage()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
    S.nodes = {}
    S.rotatable = {}
end

local function active_ports(nd)
    return nd.states[nd.rot_idx]
end

local function has_port(nd, dir)
    local p = active_ports(nd)
    for i = 1, #p do
        if p[i] == dir then return true end
    end
    return false
end

local function find_node_at(gx, gy, gz)
    for i = 1, #S.nodes do
        local nd = S.nodes[i]
        if nd.gx == gx and nd.gy == gy and nd.gz == gz then return nd end
    end
    return nil
end

local function sync_node_arms(nd)
    if nd.arm_ents then
        for i = 1, #nd.arm_ents do eng.scene.despawn(nd.arm_ents[i]) end
    end
    nd.arm_ents = {}
    local ports = active_ports(nd)
    local col = nd.steam and {0.65, 0.96, 1.0, 1.0}
        or (nd.kind == "inlet" and {0.95, 0.36, 0.22, 1.0}
        or (nd.kind == "turbine" and {0.35, 0.88, 0.52, 1.0}
        or (nd.kind == "tee" and {0.90, 0.68, 0.26, 1.0} or {0.78, 0.50, 0.24, 1.0})))

    eng.scene.set_mesh(nd.ent, S.hub_mesh, { tex = S.metal_tex, color = col, metallic = 0.8, roughness = 0.25, cast_shadow = true })

    for i = 1, #ports do
        local dir = ports[i]
        local dv = DV[dir]
        local rot = ARM_ROT[dir]
        local ae = eng.scene.spawn("pipe_arm")
        eng.scene.set_pos(ae, nd.wx + dv[1] * 0.55, nd.wy + dv[2] * 0.55, nd.wz + dv[3] * 0.55)
        eng.scene.set_rot_deg(ae, rot[1], rot[2], rot[3])
        eng.scene.set_mesh(ae, S.arm_mesh, { tex = S.metal_tex, color = col, metallic = 0.82, roughness = 0.28, cast_shadow = true })
        nd.arm_ents[#nd.arm_ents + 1] = ae
        S.ents[#S.ents + 1] = ae
    end
end

local function solve_steam_flow()
    local q = {}
    for i = 1, #S.nodes do
        local nd = S.nodes[i]
        nd.steam = (nd.kind == "inlet")
        if nd.steam then q[#q + 1] = nd end
    end

    local head = 1
    while head <= #q do
        local cur = q[head]
        head = head + 1
        local ports = active_ports(cur)
        for i = 1, #ports do
            local dir = ports[i]
            local dv = DV[dir]
            local nb = find_node_at(cur.gx + dv[1], cur.gy + dv[2], cur.gz + dv[3])
            if nb and (not nb.steam) and has_port(nb, OPP[dir]) then
                nb.steam = true
                q[#q + 1] = nb
            end
        end
    end

    local turb_total, turb_lit = 0, 0
    for i = 1, #S.nodes do
        local nd = S.nodes[i]
        if nd.kind == "turbine" then
            turb_total = turb_total + 1
            if nd.steam then turb_lit = turb_lit + 1 end
        end
        sync_node_arms(nd)
    end
    S.turbines_total = turb_total
    S.turbines_lit = turb_lit
    S.stage_connected = (turb_total > 0 and turb_lit == turb_total)
end

local function sync_cursor()
    local cur = S.rotatable[S.sel_idx]
    if cur and S.cursor_ent then
        eng.scene.set_pos(S.cursor_ent, cur.wx, cur.wy + 0.72, cur.wz)
    end
end

local function add_node(kind, gx, gy, gz, states)
    local wx, wy, wz = grid_world(gx, gy, gz)
    local e = eng.scene.spawn("pipe_" .. kind .. "_" .. gx .. "_" .. gy .. "_" .. gz)
    eng.scene.set_pos(e, wx, wy, wz)
    S.ents[#S.ents + 1] = e

    local rotor = nil
    if kind == "turbine" then
        rotor = eng.scene.spawn("turbine_rotor_" .. gx .. "_" .. gy .. "_" .. gz)
        eng.scene.set_pos(rotor, wx, wy, wz)
        eng.scene.set_scale(rotor, 1.35, 0.22, 1.35)
        eng.scene.set_mesh(rotor, S.rotor_mesh, { color = {0.95, 0.84, 0.32, 1.0}, metallic = 0.9, roughness = 0.2 })
        S.ents[#S.ents + 1] = rotor
    end

    local nd = {
        ent = e, rotor = rotor, kind = kind,
        gx = gx, gy = gy, gz = gz, wx = wx, wy = wy, wz = wz,
        states = states, rot_idx = 1, steam = false, arm_ents = {}
    }
    S.nodes[#S.nodes + 1] = nd
    if kind == "elbow" or kind == "tee" then
        S.rotatable[#S.rotatable + 1] = nd
    end
end

local function build_boiler_cage()
    local base = eng.scene.spawn("boiler_floor")
    eng.scene.set_pos(base, 0.0, -0.15, 0.0)
    eng.scene.set_scale(base, 7.2, 0.3, 5.2)
    eng.scene.set_mesh(base, S.box_mesh, { tex = S.rust_tex, color = {0.32, 0.30, 0.34, 1.0} })
    S.ents[#S.ents + 1] = base

    -- 4 corner boiler cube pillars + top rails (open cutaway front for clear 3D sightline)
    local corners = { {-3.4, -2.4}, {3.4, -2.4}, {-3.4, 2.4}, {3.4, 2.4} }
    for i = 1, #corners do
        local p = eng.scene.spawn("boiler_post_" .. tostring(i))
        eng.scene.set_pos(p, corners[i][1], 2.35, corners[i][2])
        eng.scene.set_scale(p, 0.24, 4.7, 0.24)
        eng.scene.set_mesh(p, S.box_mesh, { tex = S.rust_tex, color = {0.42, 0.38, 0.36, 1.0} })
        S.ents[#S.ents + 1] = p
    end
    local back_top = eng.scene.spawn("boiler_top_beam")
    eng.scene.set_pos(back_top, 0.0, 4.7, -2.4)
    eng.scene.set_scale(back_top, 7.0, 0.24, 0.24)
    eng.scene.set_mesh(back_top, S.box_mesh, { tex = S.rust_tex, color = {0.44, 0.40, 0.38, 1.0} })
    S.ents[#S.ents + 1] = back_top
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    S.pressure = 18.0
    S.vent_timer = 0.0
    S.sel_idx = 1

    build_boiler_cage()

    if idx == 1 then
        add_node("inlet",   1, 1, 2, { {PX} })
        add_node("tee",     2, 1, 2, { {PX, PY, PZ}, {NX, PX, NY}, {NX, NZ, PY}, {NY, PZ, NZ} })
        add_node("elbow",   2, 2, 2, { {NX, PZ}, {NY, PX}, {PY, NZ}, {NX, NY} })
        add_node("elbow",   3, 2, 2, { {PX, PY}, {NY, PZ}, {NX, PY}, {NX, NZ} })
        add_node("turbine", 2, 1, 1, { {PZ} })
        add_node("turbine", 3, 2, 1, { {PZ} })
    else
        add_node("inlet",   1, 2, 2, { {NY} })
        add_node("elbow",   1, 1, 2, { {PX, PZ}, {PY, PX}, {PY, NZ}, {NY, NZ} })
        add_node("elbow",   1, 1, 1, { {NX, PY}, {PZ, PX}, {NY, PX}, {PZ, NY} })
        add_node("tee",     2, 1, 1, { {NX, NY, PZ}, {PX, PY, PZ}, {NX, PY, PX}, {NY, NZ, PX} })
        add_node("elbow",   2, 2, 1, { {NX, PY}, {PX, NZ}, {NY, NX}, {NY, PZ} })
        add_node("elbow",   3, 1, 1, { {PX, PZ}, {NY, NZ}, {NX, PY}, {NX, PZ} })
        add_node("turbine", 2, 2, 2, { {NZ} })
        add_node("turbine", 3, 2, 1, { {NY} })
    end

    S.cursor_ent = eng.scene.spawn("valve_cursor")
    eng.scene.set_scale(S.cursor_ent, 0.55, 0.55, 0.55)
    eng.scene.set_mesh(S.cursor_ent, S.crystal_mesh, { color = {1.0, 0.95, 0.28, 1.0} })
    S.ents[#S.ents + 1] = S.cursor_ent

    solve_steam_flow()
    sync_cursor()
    eng.camera.look_at(5.8, 5.5, 7.4, 0.0, 2.2, 0.0, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.012 })
    eng.render.set_sky(0.08, 0.07, 0.09, 0.24, 0.16, 0.12)
    eng.render.add_light({ type = "dir", dir = {-0.35, -0.85, -0.5}, color = {2.1, 2.0, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.2, 1.8}, color = {2.6, 1.7, 0.9}, range = 24.0 })

    local seed_base = math.floor(eng.math.range(100, 900000))
    S.metal_tex = eng.procgen.texture("metal_rivets", seed_base, 64)
    S.rust_tex = eng.procgen.texture("rust_metal", seed_base + 19, 64)

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.hub_mesh = eng.asset.sphere(0.36, 10, 14)
    S.arm_mesh = eng.asset.cylinder(0.20, 0.20, 1.10, 12)
    S.rotor_mesh = eng.asset.cylinder(0.65, 0.65, 1.0, 8)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_turn = eng.audio.synth("square", 380, 0.07, 540)
    S.sfx_vent = eng.audio.synth("noise", 520, 0.20, 220)
    S.sfx_burst = eng.audio.synth("noise", 160, 0.28, 55)

    S.rotations = 0
    S.turbines_spun = 0
    S.turbines_lit = 0
    S.turbines_total = 2
    S.nav_cd = 0.0
    S.rot_cd = 0.0
    S.spin_deg = 0.0
    S.won = false
    S.lost = false

    build_stage(1)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won or S.lost then return end
    S.nav_cd = math.max(0.0, S.nav_cd - dt)
    S.rot_cd = math.max(0.0, S.rot_cd - dt)

    if not S.stage_connected then
        S.pressure = S.pressure + (11.0 + S.stage * 2.5) * dt
        if S.pressure >= 100.0 then
            S.pressure = 100.0
            S.lost = true
            eng.audio.play(S.sfx_burst, 0.0, 2.2, 0.0, 0)
            eng.save.write("pipe_pressure_3d", "burst")
            return
        end

        local mx, my = eng.input.axis2d("left", "right", "down", "up")
        if S.nav_cd <= 0.0 then
            if mx > 0.4 or my > 0.4 or eng.input.pressed("jump") then
                S.sel_idx = (S.sel_idx % #S.rotatable) + 1
                S.nav_cd = 0.10
                sync_cursor()
            elseif mx < -0.4 or my < -0.4 then
                S.sel_idx = ((S.sel_idx - 2) % #S.rotatable) + 1
                S.nav_cd = 0.10
                sync_cursor()
            end
        end

        if (eng.input.pressed("fire") or eng.input.pressed("interact")) and S.rot_cd <= 0.0 then
            local cur = S.rotatable[S.sel_idx]
            if cur then
                cur.rot_idx = (cur.rot_idx % #cur.states) + 1
                S.rotations = S.rotations + 1
                S.rot_cd = 0.07
                eng.audio.play(S.sfx_turn, cur.wx, cur.wy, cur.wz, 0)
                solve_steam_flow()
                if S.stage_connected then
                    eng.audio.play(S.sfx_vent, 0.0, 2.5, 0.0, 0)
                end
            end
        end
    else
        -- Steam vents cleanly through connected 3D manifold, spinning turbine rotors!
        S.pressure = math.max(10.0, S.pressure - 90.0 * dt)
        S.spin_deg = S.spin_deg + 720.0 * dt
        for i = 1, #S.nodes do
            local nd = S.nodes[i]
            if nd.rotor then
                eng.scene.set_rot_deg(nd.rotor, 0.0, S.spin_deg, 0.0)
            end
        end
        S.vent_timer = S.vent_timer + dt
        if S.vent_timer >= 0.28 then
            S.turbines_spun = S.turbines_spun + S.turbines_lit
            if S.stage < 2 then
                eng.save.write("pipe_pressure_3d", "boiler_2")
                build_stage(S.stage + 1)
            else
                S.won = true
                eng.save.write("pipe_pressure_3d", "clear")
            end
        end
    end
end

function draw()
    for i = 1, #S.nodes do
        local nd = S.nodes[i]
        if nd.steam then
            eng.render.draw_sprite(nd.wx, nd.wy + 0.45, nd.wz, 0.42, 0.42, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 620, 52, 1280, 720)
    local status = S.won and (" | " .. eng.i18n.t("victory")) or (S.lost and (" | " .. eng.i18n.t("defeat")) or "")
    eng.ui.label(x, y, eng.i18n.t("title") .. string.format(" | BOILER %d/2 | TURBINES %d/%d%s", S.stage, S.turbines_lit, S.turbines_total, status), 1.0, {0.85, 0.96, 1.0, 1.0})
    eng.ui.bar(x, y + 24, 240, S.pressure / 100.0, string.format("PRESSURE %2.0f%% ", S.pressure))
end
