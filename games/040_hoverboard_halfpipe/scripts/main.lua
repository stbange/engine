-- 040_hoverboard_halfpipe: Halfpipe transition pumping & coping-lip aerial spin combos
local S = game.state

local FLAT_X = 1.6
local PIPE_R = 3.6
local ARC_Q = 0.5 * math.pi * PIPE_R
local S_LIP = FLAT_X + ARC_Q
local GRAV = 12.5

-- Map signed halfpipe arc-length s in [-S_LIP, S_LIP] -> (x, y, bank_deg, sin_slope)
local function pipe_pose(s)
    local as = math.abs(s)
    local sgn = (s >= 0.0) and 1.0 or -1.0
    if as <= FLAT_X then
        return s, 0.0, 0.0, 0.0
    end
    local phi = math.min(0.5 * math.pi, (as - FLAT_X) / PIPE_R)
    local x = sgn * (FLAT_X + PIPE_R * math.sin(phi))
    local y = PIPE_R * (1.0 - math.cos(phi))
    return x, y, sgn * math.deg(phi), sgn * math.sin(phi)
end

function init()
    eng.xr.set_mode("diorama")
    eng.render.set_retro({ vertex_snap = 240, dither = true, color_bits = 6, fog_density = 0.008 })
    eng.render.set_sky(0.05, 0.04, 0.16, 0.22, 0.10, 0.34)
    eng.render.add_light({ type = "dir", dir = {-0.3, -1.0, -0.45}, color = {2.0, 1.95, 2.2}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 6.0, -4.0}, color = {1.2, 2.4, 2.8}, range = 32.0 })

    local seed = math.floor(eng.math.range(100, 90000))
    local ramp_tex = eng.procgen.texture("sci_fi_panel", seed, 64)
    local deck_tex = eng.procgen.texture("metal_rivets", seed + 19, 64)

    local seg_mesh = eng.asset.box(1.35, 0.28, 12.0)
    local coping_mesh = eng.asset.cylinder(0.12, 0.12, 12.0, 10)
    local deck_mesh = eng.asset.box(0.48, 0.10, 1.60)
    local crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    local pillar_mesh = eng.asset.load_mesh("assets/shared/meshes/pillar.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    S.sfx_pump = eng.audio.synth("triangle", 280, 0.10, 460)
    S.sfx_lip = eng.audio.synth("sine", 440, 0.16, 780)
    S.sfx_stomp = eng.audio.synth("sine", 580, 0.24, 1160)

    -- Construct segmented 3D U-shaped halfpipe along z = -4.0
    local n_segs = 15
    for i = 0, n_segs - 1 do
        local frac = (i + 0.5) / n_segs
        local s = -S_LIP + frac * (2.0 * S_LIP)
        local px, py, bank_deg = pipe_pose(s)
        local rad = math.rad(bank_deg)
        -- Offset plank slightly outward along normal so rider hovers cleanly above surface
        local nx, ny = -math.sin(rad), math.cos(rad)
        local seg = eng.scene.spawn("pipe_seg_" .. tostring(i))
        eng.scene.set_pos(seg, px - nx * 0.16, py - ny * 0.16, -4.0)
        eng.scene.set_rot_deg(seg, 0.0, 0.0, bank_deg)
        local is_lip = (i == 0 or i == n_segs - 1)
        eng.scene.set_mesh(seg, seg_mesh, {
            tex = ramp_tex,
            color = is_lip and {0.95, 0.30, 0.82, 1.0} or {0.22, 0.34, 0.56, 1.0},
            roughness = 0.35
        })
    end

    -- Neon coping rails & support towers on left (-5.2, 3.6) and right (+5.2, 3.6) lips
    local lip_x = FLAT_X + PIPE_R
    for side = -1, 1, 2 do
        local rail = eng.scene.spawn("coping_rail_" .. tostring(side))
        eng.scene.set_pos(rail, side * lip_x, PIPE_R, -4.0)
        eng.scene.set_rot_deg(rail, 90.0, 0.0, 0.0)
        eng.scene.set_mesh(rail, coping_mesh, { color = (side < 0) and {0.25, 0.98, 1.0, 1.0} or {1.0, 0.35, 0.85, 1.0} })

        local tow = eng.scene.spawn("lip_tower_" .. tostring(side))
        eng.scene.set_pos(tow, side * (lip_x + 0.55), 0.0, -4.0)
        eng.scene.set_scale(tow, 1.1, 1.2, 1.6)
        eng.scene.set_mesh(tow, pillar_mesh, { tex = deck_tex, color = {0.28, 0.30, 0.42, 1.0}, cast_shadow = true })
    end

    -- High-altitude Holo-Crystals floating 2.0m above both coping lips
    S.tokens = {}
    for i = 1, 2 do
        local side = (i == 1) and -1.0 or 1.0
        local tx, ty, tz = side * lip_x, PIPE_R + 1.9, -4.0
        local te = eng.scene.spawn("lip_holo_gem_" .. tostring(i))
        eng.scene.set_pos(te, tx, ty, tz)
        eng.scene.set_scale(te, 0.85, 0.85, 0.85)
        eng.scene.set_mesh(te, crystal_mesh, { color = {1.0, 0.90, 0.25, 1.0} })
        S.tokens[i] = { ent = te, x = tx, y = ty, z = tz, taken = false }
    end

    -- Hoverboard + procedural rider
    S.board_ent = eng.scene.spawn("hoverboard")
    local deck = eng.scene.spawn("hover_deck")
    eng.scene.set_parent(deck, S.board_ent)
    eng.scene.set_rot_deg(deck, 0.0, 90.0, 0.0)
    eng.scene.set_mesh(deck, deck_mesh, { color = {0.25, 1.0, 0.82, 1.0}, metallic = 0.7, roughness = 0.2, cast_shadow = true })

    local rider = eng.scene.spawn("hover_rider")
    eng.scene.set_parent(rider, S.board_ent)
    eng.scene.set_pos(rider, 0.0, 0.08, 0.0)
    eng.procgen.person(rider, seed + 37)

    -- Start with sub-lip oscillation speed so player MUST pump transitions to reach the 3.6m lip!
    S.arc_s = 0.0
    S.vel_s = 7.0
    S.airborne = false
    S.air_x = 0.0
    S.air_y = 0.0
    S.air_vy = 0.0
    S.lip_side = 1.0
    S.trick_spin = 0.0
    S.trick_grab = false
    S.pump_cd = 0.0
    S.pumps = 0
    S.aerial_combos = 0
    S.combo = 0
    S.max_height = 0.0
    S.last_trick = "CARVING"
    S.score = 0
    S.won = false

    sync_hover_cam()
    eng.mod.emit("post_init")
end

function sync_hover_cam()
    local wx, wy, bank_deg
    local yaw_deg = 0.0
    local pitch_deg = 0.0
    if S.airborne then
        wx, wy = S.air_x, S.air_y
        bank_deg = S.lip_side * 90.0
        yaw_deg = S.trick_spin
        pitch_deg = S.trick_grab and 26.0 or 0.0
    else
        wx, wy, bank_deg = pipe_pose(S.arc_s)
        local rad = math.rad(bank_deg)
        wx = wx - math.sin(rad) * 0.22
        wy = wy + math.cos(rad) * 0.22
    end
    if wy > S.max_height then S.max_height = wy end

    eng.scene.set_pos(S.board_ent, wx, wy, -4.0)
    eng.scene.set_rot_deg(S.board_ent, pitch_deg, yaw_deg, bank_deg)
    eng.camera.look_at(wx * 0.35, 3.8 + wy * 0.35, 6.6, wx * 0.55, 2.2 + wy * 0.4, -4.0, 0)
end

function update(dt)
    if S.won then return end
    S.pump_cd = math.max(0.0, S.pump_cd - dt)

    local ix, iy = eng.input.axis2d("left", "right", "down", "up")

    if not S.airborne then
        local _, _, _, sin_slope = pipe_pose(S.arc_s)
        -- Halfpipe tangential pendulum acceleration + subtle hover drag
        S.vel_s = S.vel_s - GRAV * sin_slope * dt
        S.vel_s = S.vel_s * math.max(0.0, 1.0 - 0.08 * dt)

        -- Transition Pumping: pressing up/down or carving into curved transition walls amplifies speed!
        local on_transition = math.abs(S.arc_s) > FLAT_X + 0.25 and math.abs(S.vel_s) > 0.4
        local pump_in = (math.abs(iy) > 0.2) or (ix * S.vel_s > 0.2)
        if on_transition and pump_in then
            local dir = (S.vel_s >= 0.0) and 1.0 or -1.0
            S.vel_s = eng.math.clamp(S.vel_s + dir * 13.5 * dt, -15.5, 15.5)
            if S.pump_cd <= 0.0 then
                S.pump_cd = 0.32
                S.pumps = S.pumps + 1
                S.score = S.score + 50
                local wx, wy = pipe_pose(S.arc_s)
                eng.audio.play(S.sfx_pump, wx, wy, -4.0, 0)
            end
        end

        S.arc_s = S.arc_s + S.vel_s * dt

        -- Launch vertically past coping lip when momentum carries past S_LIP!
        if math.abs(S.arc_s) > S_LIP and (S.arc_s * S.vel_s > 0.0) then
            S.lip_side = (S.arc_s >= 0.0) and 1.0 or -1.0
            S.airborne = true
            S.air_x = S.lip_side * (FLAT_X + PIPE_R)
            S.air_y = PIPE_R + 0.05
            local pop = (eng.input.down("jump") or eng.input.pressed("jump")) and 2.4 or 0.6
            S.air_vy = math.min(13.5, math.abs(S.vel_s) + pop)
            S.trick_spin = 0.0
            S.trick_grab = false
            eng.audio.play(S.sfx_lip, S.air_x, S.air_y, -4.0, 0)
        end
    else
        -- Airborne above halfpipe coping lip: spin combos & nosegrabs!
        S.air_vy = S.air_vy - GRAV * dt
        S.air_y = S.air_y + S.air_vy * dt

        local spin_dir = (math.abs(ix) > 0.1) and ix or (eng.input.down("jump") and 1.0 or 0.0)
        S.trick_spin = S.trick_spin + spin_dir * 560.0 * dt
        if eng.input.down("fire") or eng.input.pressed("fire") then
            S.trick_grab = true
        end

        -- Collect high-altitude lip Holo-Gems
        for i = 1, #S.tokens do
            local tk = S.tokens[i]
            if not tk.taken and eng.math.dist3(S.air_x, S.air_y, -4.0, tk.x, tk.y, tk.z) < 1.5 then
                tk.taken = true
                S.score = S.score + 400
                eng.scene.despawn(tk.ent)
            end
        end

        -- Re-enter halfpipe transition at coping lip
        if S.air_y <= PIPE_R and S.air_vy < 0.0 then
            local spins = math.floor((math.abs(S.trick_spin) + 35.0) / 180.0)
            if spins >= 1 then
                S.aerial_combos = S.aerial_combos + 1
                S.combo = S.combo + 1
                local grab_mult = S.trick_grab and 2 or 1
                local pts = spins * 350 * grab_mult * S.combo
                S.score = S.score + pts
                S.last_trick = string.format("%d%s x%d", spins * 180, S.trick_grab and " GRAB" or " SPIN", S.combo)
                eng.audio.play(S.sfx_stomp, S.air_x, PIPE_R, -4.0, 0)
            else
                S.combo = 0
                S.last_trick = "AIR DROP"
            end

            S.airborne = false
            S.arc_s = S.lip_side * (S_LIP - 0.05)
            S.vel_s = -S.lip_side * math.min(14.0, math.abs(S.air_vy))

            if S.pumps >= 2 and S.aerial_combos >= 2 and S.score >= 2500 then
                S.won = true
                eng.save.write("hoverboard_halfpipe_clear", tostring(S.score))
            end
        end
    end

    sync_hover_cam()
end

function draw()
    local bx, by = eng.scene.get_pos(S.board_ent)
    eng.render.draw_sprite(bx, by - 0.15, -4.0, 0.55, 0.55, S.orb_tex)

    local x, y = eng.ui.anchor("top_left", 16, 14, 600, 54, 1280, 720)
    local label = S.won and eng.i18n.t("victory") or string.format(
        "%s | PUMPS %d | AERIALS %d/2 | %s | %d PTS",
        eng.i18n.t("title"), S.pumps, S.aerial_combos, S.last_trick, S.score)
    eng.ui.label(x, y, label, 1.0, {0.98, 0.55, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, eng.math.clamp(S.score / 2500.0, 0.0, 1.0), "COMBO ")
end
