-- 065_magnet_polarity: Toggle Red (+1) / Blue (-1) magnet polarity (`fire`) to attract & repel spheres across chasms
local S = game.state

local function pol_color(p)
    if p > 0 then return {0.98, 0.24, 0.28, 1.0} end
    return {0.22, 0.52, 1.0, 1.0}
end

local function clear_stage()
    if S.ents then
        for i = 1, #S.ents do eng.scene.despawn(S.ents[i]) end
    end
    S.ents = {}
    S.spheres = {}
    S.goals = {}
    S.satisfied = 0
end

local function spawn_static_box(name, x, y, z, hx, hy, hz, col, tex)
    local e = eng.scene.spawn(name)
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_scale(e, hx * 2.0, hy * 2.0, hz * 2.0)
    eng.scene.set_mesh(e, S.box_mesh, { tex = tex, color = col, cast_shadow = true })
    eng.physics.add_body(e, { shape = "aabb", motion = "static", half_extents = {hx, hy, hz} })
    S.ents[#S.ents + 1] = e
    return e
end

local function build_stage(idx)
    clear_stage()
    S.stage = idx
    S.mag_pol = 1 -- starts RED (+1)
    S.mx, S.my, S.mz = 0.0, 2.7, 3.2

    local seed_base = math.floor(eng.math.range(100, 8000)) + idx * 67
    local metal_tex = eng.procgen.texture("metal_rivets", seed_base, 64)
    local lava_tex = eng.procgen.texture("lava_cracks", seed_base + 19, 64)

    -- South launch deck (z in [1.5, 5.5]), open 3.0m chasm (z in [-1.5, 1.5]), North goal deck (z in [-5.5, -1.5])
    spawn_static_box("south_deck", 0.0, -0.25,  3.5, 4.0, 0.25, 2.0, {0.36, 0.38, 0.44, 1.0}, metal_tex)
    spawn_static_box("north_deck", 0.0, -0.25, -3.5, 4.0, 0.25, 2.0, {0.32, 0.36, 0.46, 1.0}, metal_tex)
    spawn_static_box("south_curb", 0.0,  0.35,  5.35, 4.0, 0.35, 0.15, {0.48, 0.45, 0.42, 1.0}, metal_tex)
    spawn_static_box("north_curb", 0.0,  0.35, -5.35, 4.0, 0.35, 0.15, {0.48, 0.45, 0.42, 1.0}, metal_tex)
    spawn_static_box("west_curb", -3.9,  0.35,  0.0, 0.15, 0.35, 5.5, {0.48, 0.45, 0.42, 1.0}, metal_tex)
    spawn_static_box("east_curb",  3.9,  0.35,  0.0, 0.15, 0.35, 5.5, {0.48, 0.45, 0.42, 1.0}, metal_tex)

    local chasm_floor = eng.scene.spawn("chasm_abyss")
    eng.scene.set_pos(chasm_floor, 0.0, -2.6, 0.0)
    eng.scene.set_scale(chasm_floor, 8.0, 0.2, 3.2)
    eng.scene.set_mesh(chasm_floor, S.box_mesh, { tex = lava_tex, color = {0.9, 0.3, 0.15, 1.0} })
    S.ents[#S.ents + 1] = chasm_floor

    local sp_cfg, gl_cfg
    if idx == 1 then
        sp_cfg = { { x = 0.0, z = 3.2, pol = 1 } }
        gl_cfg = { { x = 0.0, z = -3.5, pol = 1 } }
    else
        sp_cfg = {
            { x = -1.6, z = 3.2, pol = 1 },
            { x =  1.6, z = 3.2, pol = -1 },
        }
        gl_cfg = {
            { x = -2.0, z = -3.5, pol = 1 },
            { x =  2.0, z = -3.5, pol = -1 },
        }
    end

    for i = 1, #gl_cfg do
        local gc = gl_cfg[i]
        local ge = eng.scene.spawn("goal_plate_" .. tostring(i))
        eng.scene.set_pos(ge, gc.x, 0.05, gc.z)
        eng.scene.set_scale(ge, 1.4, 0.10, 1.4)
        eng.scene.set_mesh(ge, S.box_mesh, { color = pol_color(gc.pol) })
        S.ents[#S.ents + 1] = ge
        S.goals[#S.goals + 1] = { ent = ge, x = gc.x, z = gc.z, pol = gc.pol, satisfied = false }
    end

    for i = 1, #sp_cfg do
        local sc = sp_cfg[i]
        local se = eng.scene.spawn("metal_sphere_" .. tostring(i))
        eng.scene.set_pos(se, sc.x, 0.44, sc.z)
        eng.scene.set_scale(se, 0.84, 0.84, 0.84)
        eng.scene.set_mesh(se, S.sphere_mesh, { color = pol_color(sc.pol), metallic = 0.9, roughness = 0.18, cast_shadow = true })
        local bid = eng.physics.add_body(se, { shape = "sphere", motion = "dynamic", radius = 0.42, restitution = 0.1 })
        S.ents[#S.ents + 1] = se
        S.spheres[#S.spheres + 1] = { ent = se, body = bid, sx = sc.x, sz = sc.z, pol = sc.pol, locked = false }
    end

    S.mag_ent = eng.scene.spawn("overhead_magnet")
    eng.scene.set_pos(S.mag_ent, S.mx, S.my, S.mz)
    eng.scene.set_scale(S.mag_ent, 0.95, 0.55, 0.95)
    eng.scene.set_mesh(S.mag_ent, S.cyl_mesh, { color = pol_color(S.mag_pol), metallic = 0.8, roughness = 0.25, cast_shadow = true })
    S.ents[#S.ents + 1] = S.mag_ent

    eng.camera.look_at(0.0, 6.8, 10.5, 0.0, 0.4, 0.0, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.014 })
    eng.render.set_sky(0.06, 0.08, 0.14, 0.22, 0.14, 0.18)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.4}, color = {2.0, 1.95, 1.9}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 4.0, 0.0}, color = {2.2, 1.2, 0.8}, range = 22.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.sphere_mesh = eng.asset.sphere(0.5, 12, 16)
    S.cyl_mesh = eng.asset.cylinder(0.5, 0.5, 1.0, 14)
    S.sfx_toggle = eng.audio.synth("square", 340, 0.08, 520)
    S.sfx_goal = eng.audio.synth("triangle", 500, 0.20, 940)

    S.toggles = 0
    S.chasm_crossings = 0
    S.won = false
    build_stage(1)
    eng.mod.emit("post_init")
end

function update(dt)
    if S.won then return end

    local ix, iy = eng.input.axis2d("left", "right", "down", "up")
    if math.abs(ix) > 0.01 or math.abs(iy) > 0.01 then
        S.mx = eng.math.clamp(S.mx + ix * 7.5 * dt, -3.4, 3.4)
        S.mz = eng.math.clamp(S.mz - iy * 7.5 * dt, -4.8, 4.8)
        eng.scene.set_pos(S.mag_ent, S.mx, S.my, S.mz)
    end

    if eng.input.pressed("fire") then
        S.mag_pol = -S.mag_pol
        S.toggles = S.toggles + 1
        eng.scene.set_mesh(S.mag_ent, S.cyl_mesh, { color = pol_color(S.mag_pol), metallic = 0.8, roughness = 0.25, cast_shadow = true })
        eng.audio.play(S.sfx_toggle, S.mx, S.my, S.mz, 0)
    end

    for i = 1, #S.spheres do
        local sp = S.spheres[i]
        local px, py, pz = eng.scene.get_pos(sp.ent)
        if py < -1.2 then
            eng.scene.set_pos(sp.ent, sp.sx, 0.45, sp.sz)
            eng.physics.set_vel(sp.body, 0.0, 0.0, 0.0)
            px, py, pz = sp.sx, 0.45, sp.sz
        end

        if not sp.crossed and pz < -1.6 then
            sp.crossed = true
            S.chasm_crossings = S.chasm_crossings + 1
        end

        if not sp.locked then
            local dx, dz = S.mx - px, S.mz - pz
            local horiz_d = math.sqrt(dx * dx + dz * dz)
            local vx, vy, vz = eng.physics.get_vel(sp.body)

            if S.mag_pol ~= sp.pol and horiz_d < 2.6 then
                -- Opposite polarity: ATTRACT & LEVITATE under magnet carriage across chasm
                vx = eng.math.clamp(dx * 6.5, -8.0, 8.0)
                vz = eng.math.clamp(dz * 6.5, -8.0, 8.0)
                vy = eng.math.clamp((1.85 - py) * 10.0 + 9.81 * dt, -5.0, 8.0)
                eng.physics.set_vel(sp.body, vx, vy, vz)
            elseif S.mag_pol == sp.pol and horiz_d < 2.6 then
                -- Matching polarity: REPEL downward & outward onto goal plate / away from magnet
                local inv = 1.0 / math.max(0.35, horiz_d)
                vx = vx - (dx * inv) * 9.0 * dt
                vz = vz - (dz * inv) * 9.0 * dt
                vy = vy - 12.0 * dt
                eng.physics.set_vel(sp.body, vx, vy, vz)
            end
        end
    end

    local sat_count = 0
    for i = 1, #S.goals do
        local g = S.goals[i]
        g.satisfied = false
        for j = 1, #S.spheres do
            local sp = S.spheres[j]
            if sp.pol == g.pol then
                local px, py, pz = eng.scene.get_pos(sp.ent)
                if py < 0.75 and eng.math.dist3(px, 0.0, pz, g.x, 0.0, g.z) < 0.85 then
                    g.satisfied = true
                    sp.locked = true
                    eng.physics.set_vel(sp.body, 0.0, 0.0, 0.0)
                    eng.scene.set_pos(sp.ent, g.x, 0.44, g.z)
                end
            end
        end
        if g.satisfied then
            sat_count = sat_count + 1
            eng.scene.set_mesh(g.ent, S.box_mesh, { color = {0.25, 1.0, 0.55, 1.0} })
        end
    end
    S.satisfied = sat_count

    if sat_count == #S.goals then
        eng.audio.play(S.sfx_goal, 0.0, 1.0, -3.5, 0)
        if S.stage < 2 then
            eng.save.write("magnet_polarity", "stage_2")
            build_stage(S.stage + 1)
        else
            S.won = true
            eng.save.write("magnet_polarity", "clear")
        end
    end
    eng.camera.look_at(S.mx * 0.25, 6.8, 10.5, 0.0, 0.4, 0.0, 0)
end

function draw()
    local pname = (S.mag_pol > 0) and "RED (+N)" or "BLUE (-S)"
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | LAB " .. S.stage .. "/2 | COIL " .. pname .. " | GOALS " .. S.satisfied .. "/" .. #S.goals, 1.0, {0.95, 0.85, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 200, S.satisfied / math.max(1, #S.goals), "PLATE ")
end
