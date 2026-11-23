-- 036_snowboard_slalom: Carve down a procedural alpine slope through alternating red & blue slalom gates
local S = game.state

local FINISH_Z = -86.0

local function slope_y(x, z)
    return z * 0.16 + eng.procgen.noise2d(x * 0.14, z * 0.10, S.seed) * 0.32
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.011 })
    eng.render.set_sky(0.24, 0.54, 0.90, 0.80, 0.90, 0.98)
    eng.render.add_light({ type = "dir", dir = {-0.35, -0.95, -0.4}, color = {2.3, 2.25, 2.15}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 8.0, -35.0}, color = {1.4, 1.8, 2.4}, range = 65.0 })

    S.seed = math.floor(eng.math.range(100, 90000))
    local snow_tex = eng.procgen.texture("marble", S.seed, 64)
    local board_tex = eng.procgen.texture("sci_fi_panel", S.seed + 9, 64)

    local slab_mesh = eng.asset.box(16.0, 0.8, 10.5)
    local pole_mesh = eng.asset.cylinder(0.09, 0.09, 2.2, 8)
    local bar_mesh = eng.asset.box(2.8, 0.22, 0.12)
    local board_mesh = eng.asset.box(0.46, 0.09, 1.65)
    local arch_mesh = eng.asset.load_mesh("assets/shared/meshes/archway.obj")
    local tree_mesh = eng.procgen.tree(S.seed + 23, 2, 3.4, 0.22)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_gate = eng.audio.synth("triangle", 540, 0.14, 920)
    S.sfx_miss = eng.audio.synth("saw", 220, 0.16, 130)
    S.sfx_win = eng.audio.synth("sine", 620, 0.28, 1240)

    -- Procedural alpine slope slabs + flanking L-system pine trees
    for i = 0, 9 do
        local tz = -i * 10.0
        local ty = tz * 0.16 - 0.45
        local slab = eng.scene.spawn("snow_run_" .. tostring(i))
        eng.scene.set_pos(slab, 0.0, ty, tz)
        eng.scene.set_rot_deg(slab, -9.1, 0.0, 0.0)
        eng.scene.set_mesh(slab, slab_mesh, { tex = snow_tex, color = {0.92, 0.96, 1.0, 1.0}, roughness = 0.65 })

        for side = -1, 1, 2 do
            local tx = side * (6.8 + (i % 2) * 0.9)
            local tree = eng.scene.spawn("pine_" .. tostring(i) .. "_" .. tostring(side))
            eng.scene.set_pos(tree, tx, slope_y(tx, tz - 2.0), tz - 2.0)
            eng.scene.set_mesh(tree, tree_mesh, { color = {0.22, 0.56, 0.34, 1.0}, cast_shadow = true })
        end
    end

    -- 6 Alternating Red & Blue Slalom Gates
    local gate_xs = { -2.3, 2.3, -2.6, 2.6, -2.2, 2.2 }
    S.gates = {}
    for i = 1, #gate_xs do
        local gx = gate_xs[i] + eng.procgen.noise2d(i * 1.7, 0.5, S.seed) * 0.25
        local gz = -13.0 * i
        local gy = slope_y(gx, gz)
        local is_red = (i % 2) == 1
        local col = is_red and {0.96, 0.22, 0.20, 1.0} or {0.20, 0.48, 0.98, 1.0}

        for p = -1, 1, 2 do
            local pe = eng.scene.spawn(string.format("gate_%d_pole_%d", i, p))
            eng.scene.set_pos(pe, gx + p * 1.35, gy + 1.1, gz)
            eng.scene.set_mesh(pe, pole_mesh, { color = col, cast_shadow = true })
        end
        local be = eng.scene.spawn("gate_banner_" .. tostring(i))
        eng.scene.set_pos(be, gx, gy + 2.0, gz)
        eng.scene.set_mesh(be, bar_mesh, { color = col })

        S.gates[i] = { x = gx, y = gy, z = gz, cleared = false, judged = false }
    end

    local fin = eng.scene.spawn("finish_arch")
    eng.scene.set_pos(fin, 0.0, slope_y(0.0, FINISH_Z), FINISH_Z)
    eng.scene.set_scale(fin, 2.2, 1.6, 1.4)
    eng.scene.set_mesh(fin, arch_mesh, { color = {1.0, 0.84, 0.22, 1.0}, cast_shadow = true })

    -- Snowboarder rig (board + procedural rider)
    S.board_ent = eng.scene.spawn("snowboard")
    eng.scene.set_mesh(S.board_ent, board_mesh, { tex = board_tex, color = {0.20, 0.92, 0.78, 1.0}, cast_shadow = true })

    local rider = eng.scene.spawn("rider")
    eng.scene.set_parent(rider, S.board_ent)
    eng.scene.set_pos(rider, 0.0, 0.06, 0.0)
    eng.procgen.person(rider, S.seed + 5)

    S.bx, S.bz = 0.0, -1.0
    S.by = slope_y(S.bx, S.bz) + 0.12
    S.vx = 0.0
    S.vz = -12.0
    S.air_y = 0.0
    S.air_vy = 0.0
    S.gates_passed = 0
    S.combo = 0
    S.score = 0
    S.won = false

    sync_rider_cam()
    eng.mod.emit("post_init")
end

function sync_rider_cam()
    local wy = S.by + S.air_y
    local roll = eng.math.clamp(-S.vx * 2.4, -28.0, 28.0)
    local yaw = eng.math.clamp(-S.vx * 1.7, -22.0, 22.0)
    eng.scene.set_pos(S.board_ent, S.bx, wy, S.bz)
    eng.scene.set_rot_deg(S.board_ent, -9.0, yaw, roll)
    eng.camera.look_at(S.bx * 0.55, wy + 4.4, S.bz + 7.8, S.bx * 0.75, wy + 0.4, S.bz - 9.0, 0)
end

function update(dt)
    if S.won then return end

    local ix, iy = eng.input.axis2d("left", "right", "down", "up")
    -- Carve acceleration + natural edge grip damping
    S.vx = S.vx + ix * 48.0 * dt
    S.vx = S.vx * math.max(0.0, 1.0 - 3.2 * dt)
    S.vx = eng.math.clamp(S.vx, -13.0, 13.0)

    local target_speed = 15.0 + iy * 2.5 - math.abs(S.vx) * 0.12
    S.vz = S.vz + (-target_speed - S.vz) * math.min(1.0, 3.5 * dt)

    if eng.input.pressed("jump") and S.air_y <= 0.01 then
        S.air_vy = 4.6
        S.score = S.score + 50
    end
    if S.air_y > 0.0 or S.air_vy > 0.0 then
        S.air_vy = S.air_vy - 12.0 * dt
        S.air_y = math.max(0.0, S.air_y + S.air_vy * dt)
        if S.air_y <= 0.0 then S.air_vy = 0.0 end
    end

    S.bx = eng.math.clamp(S.bx + S.vx * dt, -5.6, 5.6)
    S.bz = S.bz + S.vz * dt
    S.by = slope_y(S.bx, S.bz) + 0.12

    -- Judge slalom gates as snowboard crosses their Z plane
    for i = 1, #S.gates do
        local g = S.gates[i]
        if not g.judged and S.bz <= g.z then
            g.judged = true
            if math.abs(S.bx - g.x) <= 1.50 then
                g.cleared = true
                S.gates_passed = S.gates_passed + 1
                S.combo = S.combo + 1
                S.score = S.score + 200 * S.combo
                eng.audio.play(S.sfx_gate, g.x, g.y + 1.0, g.z, 0)
            else
                S.combo = 0
                eng.audio.play(S.sfx_miss, S.bx, S.by + 1.0, S.bz, 0)
            end
        end
    end

    if S.bz <= FINISH_Z then
        if S.gates_passed >= 5 then
            S.won = true
            S.score = S.score + 500
            eng.audio.play(S.sfx_win, S.bx, S.by + 1.2, S.bz, 0)
            eng.save.write("snowboard_slalom_clear", tostring(S.score))
        else
            -- Reset at top of course if too many gates were missed
            S.bx, S.bz, S.vx, S.vz = 0.0, -1.0, 0.0, -11.5
            S.gates_passed, S.combo = 0, 0
            for i = 1, #S.gates do
                S.gates[i].judged = false
                S.gates[i].cleared = false
            end
        end
    end

    sync_rider_cam()
end

function draw()
    if math.abs(S.vx) > 1.2 then
        eng.render.draw_sprite(S.bx - S.vx * 0.05, S.by + 0.25, S.bz + 0.9, 0.55, 0.55, S.orb_tex)
    end
    for i = 1, #S.gates do
        local g = S.gates[i]
        if not g.judged then
            eng.render.draw_sprite(g.x, g.y + 2.65, g.z, 0.65, 0.65, S.orb_tex)
            break
        end
    end

    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 54, 1280, 720)
    local label = S.won and eng.i18n.t("victory") or
        string.format("%s | GATES %d/6 | COMBO x%d | SCORE %d", eng.i18n.t("title"), S.gates_passed, S.combo, S.score)
    eng.ui.label(x, y, label, 1.0, {0.55, 0.96, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.gates_passed / 6.0, "SLALOM ")
end
