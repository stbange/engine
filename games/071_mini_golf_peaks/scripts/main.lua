-- 071_mini_golf_peaks: 3-Hole 3D Mini-Golf (Banked Bumper -> Windmill -> Portal Island Green)
local S = game.state

local HOLES = {
    { tee = {-8.0, 0.14, 3.4}, cup = {-3.8, 0.0, -3.0}, par = 2, pocket = 0, yaw = 0.0 },
    { tee = { 0.0, 0.14, 3.4}, cup = { 0.0, 0.0, -3.8}, par = 2, pocket = 0, yaw = 0.0 },
    { tee = { 8.0, 0.14, 3.0}, cup = { 0.0, 0.0, -3.0}, par = 2, pocket_cup = "island", yaw = 0.0 }
}

local function spawn_static_box(pocket, name, x, y, z, sx, sy, sz, mesh, opts, rest)
    local e = eng.scene.spawn(name)
    eng.scene.set_pocket(e, pocket)
    eng.scene.set_pos(e, x, y, z)
    eng.scene.set_scale(e, sx, sy, sz)
    eng.scene.set_mesh(e, mesh, opts)
    eng.physics.add_body(e, { shape = "aabb", motion = "static", pocket = pocket, half_extents = {sx * 0.5, sy * 0.5, sz * 0.5}, restitution = rest or 0.0 })
    return e
end

local function spawn_ball_at_hole(idx)
    if S.ball_ent then eng.scene.despawn(S.ball_ent) end
    S.hole = idx
    local h = HOLES[idx]
    S.aim_yaw = h.yaw
    S.power = 0.65
    S.moving = false
    S.ball_ent = eng.scene.spawn("golf_ball")
    eng.scene.set_pocket(S.ball_ent, 0)
    eng.scene.set_pos(S.ball_ent, h.tee[1], h.tee[2], h.tee[3])
    eng.scene.set_mesh(S.ball_ent, S.ball_mesh, { color = {0.98, 0.98, 0.96, 1.0}, roughness = 0.25, cast_shadow = true })
    S.ball_body = eng.physics.add_body(S.ball_ent, {
        shape = "sphere", motion = "dynamic", pocket = 0, radius = 0.14, restitution = 0.82
    })
    eng.camera.look_at(h.tee[1], 4.2, h.tee[3] + 4.8, h.tee[1], 0.2, -1.8, 0)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_sky(0.18, 0.42, 0.78, 0.68, 0.82, 0.95)
    eng.render.add_light({ type = "dir", pocket = 0, dir = {-0.35, -1.0, -0.45}, color = {2.1, 2.0, 1.85}, shadow = true })
    eng.render.add_light({ type = "point", pocket = 0, pos = {0.0, 6.0, 0.0}, color = {1.5, 1.4, 1.2}, range = 30.0 })

    S.island_pocket = eng.scene.register_pocket("island_green")
    eng.render.add_light({ type = "dir", pocket = S.island_pocket, dir = {-0.3, -1.0, -0.4}, color = {2.2, 2.05, 1.8}, shadow = true })
    eng.render.add_light({ type = "point", pocket = S.island_pocket, pos = {0.0, 4.5, 0.0}, color = {1.2, 2.0, 2.2}, range = 22.0 })
    eng.physics.set_gravity(0, 0.0, -3.2, 0.0)
    eng.physics.set_gravity(S.island_pocket, 0.0, -3.2, 0.0)

    local seed = math.floor(eng.math.range(10, 50000))
    S.box_mesh = eng.asset.box(1, 1, 1)
    S.ball_mesh = eng.asset.sphere(0.14, 12, 16)
    S.cup_mesh = eng.asset.cylinder(0.28, 0.28, 0.08, 16)
    S.pin_mesh = eng.asset.cylinder(0.04, 0.04, 1.4, 8)
    S.arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)
    S.turf_tex = eng.procgen.texture("grass", seed, 64)
    S.wood_tex = eng.procgen.texture("wood_planks", seed + 7, 64)
    S.stone_tex = eng.procgen.texture("marble", seed + 19, 64)

    S.sfx_putt = eng.audio.synth("triangle", 260, 0.09, 140)
    S.sfx_bump = eng.audio.synth("square", 420, 0.08, 620)
    S.sfx_warp = eng.audio.synth("sine", 340, 0.20, 880)
    S.sfx_cup = eng.audio.synth("triangle", 520, 0.22, 1040)

    -- Hole 1 (-8, z): Dogleg-right with 45-degree banked bumper at (-8.0, -3.0) -> cup at (-3.8, -3.0)
    spawn_static_box(0, "h1_lane_a", -8.0, -0.2, 0.0, 2.2, 0.4, 8.4, S.box_mesh, { tex = S.turf_tex, color = {0.35, 0.82, 0.40, 1.0} }, 0.0)
    spawn_static_box(0, "h1_lane_b", -5.2, -0.2, -3.0, 3.6, 0.4, 2.2, S.box_mesh, { tex = S.turf_tex, color = {0.35, 0.82, 0.40, 1.0} }, 0.0)
    spawn_static_box(0, "h1_rail_l", -9.2, 0.18, 0.0, 0.25, 0.36, 8.4, S.box_mesh, { tex = S.wood_tex }, 0.85)
    spawn_static_box(0, "h1_rail_r", -6.8, 0.18, 1.1, 0.25, 0.36, 6.2, S.box_mesh, { tex = S.wood_tex }, 0.85)
    spawn_static_box(0, "h1_rail_top", -6.2, 0.18, -4.2, 6.2, 0.36, 0.25, S.box_mesh, { tex = S.wood_tex }, 0.85)
    spawn_static_box(0, "h1_rail_end", -3.25, 0.18, -3.0, 0.25, 0.36, 2.4, S.box_mesh, { tex = S.wood_tex }, 0.85)

    S.bumper_ent = eng.scene.spawn("h1_bank_bumper")
    eng.scene.set_pos(S.bumper_ent, -8.15, 0.22, -3.15)
    eng.scene.set_rot_deg(S.bumper_ent, 0.0, -45.0, 0.0)
    eng.scene.set_scale(S.bumper_ent, 2.1, 0.44, 0.30)
    eng.scene.set_mesh(S.bumper_ent, S.box_mesh, { color = {1.0, 0.55, 0.15, 1.0}, cast_shadow = true })

    -- Hole 2 (0, z): Straight ridge with rotating windmill blades at (0, -0.5)
    spawn_static_box(0, "h2_fairway", 0.0, -0.2, -0.2, 2.4, 0.4, 9.2, S.box_mesh, { tex = S.turf_tex, color = {0.32, 0.78, 0.42, 1.0} }, 0.0)
    spawn_static_box(0, "h2_rail_l", -1.3, 0.18, -0.2, 0.25, 0.36, 9.2, S.box_mesh, { tex = S.wood_tex }, 0.85)
    spawn_static_box(0, "h2_rail_r",  1.3, 0.18, -0.2, 0.25, 0.36, 9.2, S.box_mesh, { tex = S.wood_tex }, 0.85)
    spawn_static_box(0, "h2_rail_back", 0.0, 0.18, -4.8, 2.8, 0.36, 0.25, S.box_mesh, { tex = S.wood_tex }, 0.85)

    local wm_body = eng.scene.spawn("windmill_tower")
    eng.scene.set_pos(wm_body, 0.0, 1.35, -0.5)
    eng.scene.set_scale(wm_body, 0.9, 1.5, 0.7)
    eng.scene.set_mesh(wm_body, S.box_mesh, { color = {0.92, 0.32, 0.28, 1.0}, cast_shadow = true })

    S.blade_ent = eng.scene.spawn("windmill_blade")
    eng.scene.set_pos(S.blade_ent, 0.0, 1.15, -0.05)
    eng.scene.set_scale(S.blade_ent, 0.24, 2.1, 0.14)
    eng.scene.set_mesh(S.blade_ent, S.box_mesh, { tex = S.wood_tex, color = {0.98, 0.92, 0.75, 1.0}, cast_shadow = true })

    -- Hole 3 (8, z) -> Portal Putt into isolated pocket "island_green"
    spawn_static_box(0, "h3_tee_lane", 8.0, -0.2, 0.2, 2.6, 0.4, 7.6, S.box_mesh, { tex = S.turf_tex, color = {0.36, 0.84, 0.45, 1.0} }, 0.0)
    spawn_static_box(0, "h3_rail_l", 6.6, 0.18, 0.2, 0.25, 0.36, 7.6, S.box_mesh, { tex = S.wood_tex }, 0.85)
    spawn_static_box(0, "h3_rail_r", 9.4, 0.18, 0.2, 0.25, 0.36, 7.6, S.box_mesh, { tex = S.wood_tex }, 0.85)

    local arch_ext = eng.scene.spawn("portal_arch_ext")
    eng.scene.set_pos(arch_ext, 8.0, 0.0, -3.1)
    eng.scene.set_mesh(arch_ext, S.arch_mesh, { color = {0.35, 0.92, 1.0, 1.0}, cast_shadow = true })

    -- Floating Island Green inside pocket "island_green"
    spawn_static_box(S.island_pocket, "island_slab", 0.0, -0.2, 0.0, 5.2, 0.4, 9.6, S.box_mesh, { tex = S.turf_tex, color = {0.30, 0.88, 0.55, 1.0} }, 0.0)
    spawn_static_box(S.island_pocket, "island_base", 0.0, -1.2, 0.0, 3.8, 1.6, 7.4, S.box_mesh, { tex = S.stone_tex }, 0.0)
    spawn_static_box(S.island_pocket, "island_rail_l", -2.6, 0.18, 0.0, 0.25, 0.36, 9.6, S.box_mesh, { tex = S.wood_tex }, 0.85)
    spawn_static_box(S.island_pocket, "island_rail_r",  2.6, 0.18, 0.0, 0.25, 0.36, 9.6, S.box_mesh, { tex = S.wood_tex }, 0.85)
    spawn_static_box(S.island_pocket, "island_rail_f",  0.0, 0.18, -4.7, 5.4, 0.36, 0.25, S.box_mesh, { tex = S.wood_tex }, 0.85)

    local arch_int = eng.scene.spawn("portal_arch_int")
    eng.scene.set_pocket(arch_int, S.island_pocket)
    eng.scene.set_pos(arch_int, 0.0, 0.0, 3.9)
    eng.scene.set_mesh(arch_int, S.arch_mesh, { color = {0.4, 0.95, 1.0, 1.0} })

    local p_src = eng.scene.spawn("putt_portal_src")
    eng.scene.set_pocket(p_src, 0)
    eng.scene.set_pos(p_src, 8.0, 0.85, -3.1)

    local p_dst = eng.scene.spawn("putt_portal_dst")
    eng.scene.set_pocket(p_dst, S.island_pocket)
    eng.scene.set_pos(p_dst, 0.0, 0.85, 3.9)
    eng.scene.set_rot_deg(p_dst, 0.0, 180.0, 0.0)
    eng.portal.link(p_src, p_dst, 1.8, 1.8, 1.0, true, true)

    -- Spawn Cup & Flag markers for all 3 holes
    for i = 1, 3 do
        local h = HOLES[i]
        local pk = (h.pocket_cup == "island") and S.island_pocket or 0
        local ce = eng.scene.spawn("cup_" .. tostring(i))
        eng.scene.set_pocket(ce, pk)
        eng.scene.set_pos(ce, h.cup[1], 0.02, h.cup[3])
        eng.scene.set_mesh(ce, S.cup_mesh, { color = {0.10, 0.12, 0.15, 1.0} })
        local fe = eng.scene.spawn("flag_" .. tostring(i))
        eng.scene.set_pocket(fe, pk)
        eng.scene.set_pos(fe, h.cup[1], 0.72, h.cup[3])
        eng.scene.set_mesh(fe, S.pin_mesh, { color = {1.0, 0.85, 0.20, 1.0} })
    end

    S.strokes = 0
    S.score = 0
    S.bank_bounces = 0
    S.portal_putts = 0
    S.windmill_deg = 90.0
    S.won = false
    spawn_ball_at_hole(1)
    eng.mod.emit("post_init")
end

function stroke_ball(spd_override)
    if S.moving or S.won then return end
    local rad = math.rad(S.aim_yaw)
    local spd = spd_override or (6.5 + S.power * 10.5)
    eng.physics.set_vel(S.ball_body, -math.sin(rad) * spd, 0.0, -math.cos(rad) * spd)
    S.moving = true
    S.strokes = S.strokes + 1
    local bx, by, bz = eng.scene.get_pos(S.ball_ent)
    eng.audio.play(S.sfx_putt, bx, by, bz, eng.scene.get_pocket(S.ball_ent))
end

function update(dt)
    if S.won then return end

    S.windmill_deg = (S.windmill_deg + 180.0 * dt) % 360.0
    eng.scene.set_rot_deg(S.blade_ent, 0.0, 0.0, S.windmill_deg)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    if not S.moving then
        S.aim_yaw = S.aim_yaw - mx * 85.0 * dt
        S.power = eng.math.clamp(S.power + my * 0.75 * dt, 0.20, 1.0)
        if eng.input.pressed("fire") or eng.input.pressed("jump") then
            stroke_ball()
        end
    end

    local pk = eng.scene.get_pocket(S.ball_ent)
    local bx, by, bz = eng.scene.get_pos(S.ball_ent)
    local vx, vy, vz = eng.physics.get_vel(S.ball_body)

    if pk == S.island_pocket and S.portal_putts == 0 then
        S.portal_putts = 1
        S.score = S.score + 300
        eng.audio.play(S.sfx_warp, bx, by, bz, pk)
    end

    -- 45-degree banked bumper reflection on Hole 1
    if S.hole == 1 and pk == 0 then
        local dx, dz = bx - (-8.05), bz - (-3.05)
        if math.abs(dx) < 0.95 and math.abs(dz) < 0.95 and (dx + dz) < 0.25 then
            local nx, nz = 0.70710678, 0.70710678
            local vn = vx * nx + vz * nz
            if vn < -0.1 then
                vx = (vx - 2.0 * vn * nx) * 0.98
                vz = (vz - 2.0 * vn * nz) * 0.98
                eng.physics.set_vel(S.ball_body, vx, 0.0, vz)
                S.bank_bounces = S.bank_bounces + 1
                eng.audio.play(S.sfx_bump, bx, by, bz, 0)
            end
        end
    end

    -- Rotating windmill blade sweep check on Hole 2
    if S.hole == 2 and pk == 0 and math.abs(bz - (-0.05)) < 0.24 and math.abs(bx) < 0.35 then
        local blade_low = math.abs(math.cos(math.rad(S.windmill_deg))) > 0.72
        if blade_low and vz < 0.0 then
            vz = math.abs(vz) * 0.8 + 2.5
            eng.physics.set_vel(S.ball_body, vx, 0.0, vz)
            eng.audio.play(S.sfx_bump, bx, by, bz, 0)
        end
    end

    -- Turf rolling stop threshold & out-of-bounds recovery
    if S.moving then
        if by < -1.5 then
            spawn_ball_at_hole(S.hole)
            return
        end
        local hspd = math.sqrt(vx * vx + vz * vz)
        if hspd < 0.22 then
            vx, vz = 0.0, 0.0
            S.moving = false
            eng.physics.set_vel(S.ball_body, 0.0, vy, 0.0)
        end
    end

    -- Check cup capture
    local h = HOLES[S.hole]
    local req_pk = (h.pocket_cup == "island") and S.island_pocket or 0
    if pk == req_pk then
        local cd = eng.math.dist3(bx, 0.0, bz, h.cup[1], 0.0, h.cup[3])
        local hspd = math.sqrt(vx * vx + vz * vz)
        if cd < 0.48 and hspd < 13.5 then
            eng.audio.play(S.sfx_cup, bx, 0.2, bz, pk)
            S.score = S.score + math.max(100, 400 - S.strokes * 50)
            if S.hole < 3 then
                eng.save.write("minigolf_hole", tostring(S.hole + 1))
                spawn_ball_at_hole(S.hole + 1)
                return
            else
                S.won = true
                eng.save.write("minigolf_hole", "clear")
                return
            end
        end
    end

    eng.camera.look_at(bx, 4.0, bz + 4.5, bx, 0.2, bz - 2.2, pk)
end

function draw()
    if not S.moving and not S.won and S.ball_ent then
        local bx, by, bz = eng.scene.get_pos(S.ball_ent)
        local rad = math.rad(S.aim_yaw)
        eng.render.draw_sprite(bx - math.sin(rad) * 1.1, by + 0.12, bz - math.cos(rad) * 1.1, 0.28, 0.28, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 480, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | HOLE " .. S.hole .. "/3 | STROKES " .. S.strokes .. " | SCORE " .. S.score, 1.0, {0.95, 1.0, 0.65, 1.0})
    eng.ui.bar(x, y + 26, 200, S.power, "PWR ")
end
