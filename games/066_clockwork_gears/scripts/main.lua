-- 066_clockwork_gears: Place 3D gear wheels on brass pegs so angular velocity propagates to the escapement bell
local S = game.state
local RADII = { 0.6, 1.0, 1.4 }
local SIZE_NAMES = { "SMALL (0.6m)", "MEDIUM (1.0m)", "LARGE (1.4m)" }

local function clear_stage()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
    S.gears = {}
    S.open_pegs = {}
end

local function spawn_gear_visual(x, y, z, radius, col)
    local root = eng.scene.spawn("gear_hub")
    eng.scene.set_pos(root, x, y, z)
    S.ents[#S.ents + 1] = root

    local disc = eng.scene.spawn("gear_disc")
    eng.scene.set_parent(disc, root)
    eng.scene.set_rot_deg(disc, 90.0, 0.0, 0.0)
    eng.scene.set_scale(disc, radius * 1.75, 0.22, radius * 1.75)
    eng.scene.set_mesh(disc, S.cyl_mesh, { color = col, metallic = 0.85, roughness = 0.25, cast_shadow = true })
    S.ents[#S.ents + 1] = disc

    -- 4 crossed spoke/tooth bars so rotation angle is unmistakably visible in 3D
    for k = 0, 3 do
        local tooth = eng.scene.spawn("gear_tooth_" .. tostring(k))
        eng.scene.set_parent(tooth, root)
        eng.scene.set_rot_deg(tooth, 0.0, 0.0, k * 45.0)
        eng.scene.set_scale(tooth, radius * 2.08, 0.22, 0.24)
        eng.scene.set_mesh(tooth, S.box_mesh, { color = col, metallic = 0.9, roughness = 0.2, cast_shadow = true })
        S.ents[#S.ents + 1] = tooth
    end
    return root
end

local function solve_kinematics()
    for i = 1, #S.gears do
        S.gears[i].omega = nil
    end
    S.gears[1].omega = 120.0 -- Drive shaft #1 spins at +120 deg/s
    S.jammed = false

    local queue = { 1 }
    local head = 1
    while head <= #queue do
        local u = queue[head]
        head = head + 1
        local gu = S.gears[u]
        if gu.radius > 0.0 then
            for v = 1, #S.gears do
                local gv = S.gears[v]
                if v ~= u and gv.radius > 0.0 then
                    local dx, dy, dz = gv.x - gu.x, gv.y - gu.y, gv.z - gu.z
                    local dxy = math.sqrt(dx * dx + dy * dy)
                    local expected_omega = nil

                    if dxy < 0.05 and math.abs(dz) > 0.4 and math.abs(dz) < 1.2 then
                        -- Coaxial rigid dual-plane brass shaft!
                        expected_omega = gu.omega
                    elseif math.abs(dz) < 0.15 and math.abs(dxy - (gu.radius + gv.radius)) < 0.16 then
                        -- Meshing teeth in same Z gear plane!
                        expected_omega = -gu.omega * (gu.radius / gv.radius)
                    end

                    if expected_omega then
                        if gv.omega == nil then
                            gv.omega = expected_omega
                            queue[#queue + 1] = v
                        elseif math.abs(gv.omega - expected_omega) > 1.0 then
                            S.jammed = true
                        end
                    end
                end
            end
        end
    end

    if S.jammed then
        for i = 1, #S.gears do S.gears[i].omega = 0.0 end
    end
    S.bell_omega = S.gears[S.bell_idx].omega or 0.0
end

local function mount_gear_on_peg(peg_idx, size_idx)
    local p = S.open_pegs[peg_idx]
    local g = S.gears[p.gear_slot]
    if g.ent then
        -- Remove old visual tree cleanly by hiding offscreen and spawning crisp replacement
        eng.scene.set_pos(g.ent, 0.0, -20.0, 0.0)
    end
    g.size_idx = size_idx
    g.radius = RADII[size_idx]
    g.ent = spawn_gear_visual(g.x, g.y, g.z, g.radius, {0.92, 0.74, 0.28, 1.0})
    S.placements = S.placements + 1
    eng.audio.play(S.sfx_mount, g.x, g.y, g.z, 0)
    solve_kinematics()
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    S.sel_peg = 1
    S.sel_size = 1
    S.bell_timer = 0.0

    local seed_base = math.floor(eng.math.range(100, 9000)) + idx * 47
    local brass_tex = eng.procgen.texture("metal_rivets", seed_base, 64)
    local wood_tex = eng.procgen.texture("wood_grain", seed_base + 23, 64)

    local bench = eng.scene.spawn("clock_bench")
    eng.scene.set_pos(bench, 0.0, -0.25, 0.0)
    eng.scene.set_scale(bench, 14.0, 0.5, 10.0)
    eng.scene.set_mesh(bench, S.box_mesh, { tex = wood_tex, color = {0.46, 0.34, 0.24, 1.0} })
    eng.physics.add_body(bench, { shape = "aabb", motion = "static", half_extents = {7.0, 0.25, 5.0} })
    S.ents[#S.ents + 1] = bench

    local backplate = eng.scene.spawn("brass_housing")
    eng.scene.set_pos(backplate, 0.0, 2.7, -1.25)
    eng.scene.set_scale(backplate, 10.5, 5.4, 0.35)
    eng.scene.set_mesh(backplate, S.box_mesh, { tex = brass_tex, color = {0.36, 0.32, 0.28, 1.0} })
    S.ents[#S.ents + 1] = backplate

    local fixed_cfg, open_cfg
    if idx == 1 then
        fixed_cfg = {
            { x = -3.2, y = 2.5, z = -0.6, r = 1.0, col = {0.85, 0.35, 0.25, 1.0} }, -- #1 Drive
            { x =  2.4, y = 2.5, z = -0.6, r = 1.4, col = {1.0,  0.88, 0.32, 1.0} }, -- #2 Escapement Bell
        }
        S.bell_idx = 2
        open_cfg = {
            { x = -1.2, y = 2.5, z = -0.6 }, -- needs MEDIUM (1.0)
            { x =  0.4, y = 2.5, z = -0.6 }, -- needs SMALL  (0.6)
        }
    else
        fixed_cfg = {
            { x = -3.0, y = 1.8, z = -0.7, r = 1.0, col = {0.85, 0.35, 0.25, 1.0} }, -- #1 Drive (Rear)
            { x =  1.4, y = 1.8, z = -0.7, r = 0.6, col = {0.55, 0.78, 0.88, 1.0} }, -- #2 Coaxial Rear
            { x =  1.4, y = 1.8, z =  0.1, r = 1.0, col = {0.55, 0.78, 0.88, 1.0} }, -- #3 Coaxial Front
            { x =  3.0, y = 2.2, z =  0.1, r = 1.0, col = {1.0,  0.88, 0.32, 1.0} }, -- #4 Escapement Bell (Front)
        }
        S.bell_idx = 4
        local axle = eng.scene.spawn("coaxial_shaft")
        eng.scene.set_pos(axle, 1.4, 1.8, -0.3)
        eng.scene.set_rot_deg(axle, 90.0, 0.0, 0.0)
        eng.scene.set_scale(axle, 0.24, 1.2, 0.24)
        eng.scene.set_mesh(axle, S.cyl_mesh, { color = {0.8, 0.85, 0.9, 1.0} })
        S.ents[#S.ents + 1] = axle

        open_cfg = {
            { x = -0.6, y = 1.8, z = -0.7 }, -- needs LARGE  (1.4)
            { x =  1.4, y = 3.8, z =  0.1 }, -- needs MEDIUM (1.0)
            { x =  3.0, y = 3.8, z =  0.1 }, -- needs SMALL  (0.6)
        }
    end

    for i = 1, #fixed_cfg do
        local fc = fixed_cfg[i]
        local ge = spawn_gear_visual(fc.x, fc.y, fc.z, fc.r, fc.col)
        S.gears[#S.gears + 1] = { ent = ge, x = fc.x, y = fc.y, z = fc.z, radius = fc.r, angle = 0.0, omega = 0.0 }
    end

    local bell_cfg = fixed_cfg[#fixed_cfg]
    S.bell_dome = eng.scene.spawn("escapement_bell_dome")
    eng.scene.set_pos(S.bell_dome, bell_cfg.x, bell_cfg.y + 1.55, bell_cfg.z)
    eng.scene.set_scale(S.bell_dome, 0.9, 0.7, 0.9)
    eng.scene.set_mesh(S.bell_dome, S.cyl_mesh, { color = {1.0, 0.86, 0.25, 1.0}, metallic = 0.95, roughness = 0.15 })
    S.ents[#S.ents + 1] = S.bell_dome

    for i = 1, #open_cfg do
        local oc = open_cfg[i]
        local peg_e = eng.scene.spawn("brass_peg_" .. tostring(i))
        eng.scene.set_pos(peg_e, oc.x, oc.y, oc.z - 0.1)
        eng.scene.set_rot_deg(peg_e, 90.0, 0.0, 0.0)
        eng.scene.set_scale(peg_e, 0.28, 0.85, 0.28)
        eng.scene.set_mesh(peg_e, S.cyl_mesh, { color = {0.82, 0.65, 0.30, 1.0} })
        S.ents[#S.ents + 1] = peg_e

        local slot = #S.gears + 1
        S.gears[slot] = { ent = nil, x = oc.x, y = oc.y, z = oc.z, radius = 0.0, angle = 0.0, omega = 0.0 }
        S.open_pegs[#S.open_pegs + 1] = { x = oc.x, y = oc.y, z = oc.z, gear_slot = slot }
    end

    S.cursor_ent = eng.scene.spawn("peg_selector")
    eng.scene.set_scale(S.cursor_ent, 0.35, 0.35, 0.35)
    eng.scene.set_mesh(S.cursor_ent, S.sphere_mesh, { color = {0.25, 1.0, 0.75, 1.0} })
    S.ents[#S.ents + 1] = S.cursor_ent

    solve_kinematics()
    eng.camera.look_at(0.0, 3.2, 7.6, 0.0, 2.6, -0.5, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.01 })
    eng.render.set_sky(0.09, 0.07, 0.06, 0.26, 0.18, 0.12)
    eng.render.add_light({ type = "dir", dir = {-0.25, -0.8, -0.7}, color = {2.2, 2.0, 1.75}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.5, 2.5}, color = {2.4, 1.9, 1.2}, range = 22.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.5, 0.5, 1.0, 16)
    S.sphere_mesh = eng.asset.sphere(0.5, 10, 14)
    S.sfx_mount = eng.audio.synth("triangle", 340, 0.08, 480)
    S.sfx_bell = eng.audio.synth("sine", 780, 0.30, 1180)

    S.placements = 0
    S.won = false
    build_stage(1)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    if eng.input.pressed("left") then
        S.sel_peg = ((S.sel_peg - 2) % #S.open_pegs) + 1
    elseif eng.input.pressed("right") then
        S.sel_peg = (S.sel_peg % #S.open_pegs) + 1
    elseif eng.input.pressed("up") or eng.input.pressed("jump") then
        S.sel_size = (S.sel_size % 3) + 1
    elseif eng.input.pressed("down") then
        S.sel_size = ((S.sel_size - 2) % 3) + 1
    elseif eng.input.pressed("fire") then
        mount_gear_on_peg(S.sel_peg, S.sel_size)
    end

    local cp = S.open_pegs[S.sel_peg]
    if cp and S.cursor_ent then
        eng.scene.set_pos(S.cursor_ent, cp.x, cp.y, cp.z + 0.45)
    end

    for i = 1, #S.gears do
        local g = S.gears[i]
        if g.ent and g.omega and math.abs(g.omega) > 0.1 then
            g.angle = (g.angle + g.omega * dt) % 360.0
            eng.scene.set_rot_deg(g.ent, 0.0, 0.0, g.angle)
        end
    end

    if math.abs(S.bell_omega) > 20.0 then
        S.bell_timer = S.bell_timer + dt
        if S.bell_timer >= 0.35 then
            eng.audio.play(S.sfx_bell, 2.5, 3.5, 0.0, 0)
            if S.stage < 2 then
                eng.save.write("clockwork_gears", "stage_2")
                build_stage(S.stage + 1)
            else
                S.won = true
                eng.save.write("clockwork_gears", "clear")
            end
        end
    else
        S.bell_timer = 0.0
    end
end

function draw()
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | TOWER " .. S.stage .. "/2 | GEAR: " .. SIZE_NAMES[S.sel_size], 1.0, {1.0, 0.88, 0.45, 1.0})
    eng.ui.bar(x, y + 26, 200, S.bell_timer / 0.35, "BELL  ")
end
