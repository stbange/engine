-- 097_synth_sequencer_3d: Walkable 8-Step x 4-Track 3D Polyphonic Synth Tower
local S = game.state

local TRACK_WAVES = { "saw", "triangle", "square", "sine" }
local TRACK_HZ    = { 130.81, 196.00, 261.63, 329.63 } -- C3, G3, C4, E4 polyphonic triad
local TRACK_COLS  = {
    {1.00, 0.30, 0.45, 1.0},
    {1.00, 0.78, 0.22, 1.0},
    {0.22, 0.95, 0.65, 1.0},
    {0.28, 0.82, 1.00, 1.0}
}
-- 4 missing harmonic lock pads the player must activate to complete the 4-voice chord bar
local TARGETS = {
    { step = 2, track = 1 },
    { step = 4, track = 2 },
    { step = 6, track = 3 },
    { step = 8, track = 4 }
}

local function refresh_pad(p, is_playhead)
    local h = p.on and 0.36 or 0.14
    if is_playhead and p.on then h = 0.52 end
    eng.scene.set_pos(p.ent, p.x, h * 0.5, p.z)
    eng.scene.set_scale(p.ent, 1.15, h, 1.15)
    local tc = TRACK_COLS[p.track]
    local col = p.on and tc or {tc[1] * 0.24, tc[2] * 0.24, tc[3] * 0.28, 1.0}
    eng.scene.set_mesh(p.ent, S.box_mesh, { color = col, roughness = p.on and 0.15 or 0.65, metallic = 0.3 })
end

function init()
    eng.xr.set_mode("first_person")
    eng.render.set_sky(0.03, 0.02, 0.10, 0.14, 0.08, 0.26)
    eng.render.add_light({ type = "dir", dir = {-0.25, -1.0, -0.45}, color = {1.8, 1.75, 2.0}, shadow = true })
    eng.render.add_light({ type = "point", pos = {0.0, 5.5, -6.0}, color = {1.8, 2.2, 3.0}, range = 26.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.crystal_mesh = eng.asset.load_mesh("assets/shared/meshes/crystal.obj")
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local plaza_tex = eng.procgen.texture("sci_fi_panel", seed, 64)

    local floor_e = eng.scene.spawn("sequencer_plaza")
    eng.scene.set_pos(floor_e, 0.0, -0.25, -5.5)
    eng.scene.set_scale(floor_e, 16.0, 0.5, 16.0)
    eng.scene.set_mesh(floor_e, S.box_mesh, { tex = plaza_tex, color = {0.14, 0.16, 0.24, 1.0}, roughness = 0.4 })

    -- Synthesize 4x2 polyphonic instrument bank
    S.clips = {}
    for tr = 1, 4 do
        S.clips[tr] = {
            eng.audio.synth(TRACK_WAVES[tr], TRACK_HZ[tr], 0.14, TRACK_HZ[tr]),
            eng.audio.synth(TRACK_WAVES[tr], TRACK_HZ[tr] * 1.122, 0.14, TRACK_HZ[tr] * 1.122)
        }
    end
    S.sfx_unlock = eng.audio.synth("triangle", 523.25, 0.28, 1046.5)

    -- 8-Step x 4-Track 3D Pad Matrix
    S.pads = {}
    for step = 1, 8 do
        S.pads[step] = {}
        local x = -4.9 + (step - 1) * 1.4
        for tr = 1, 4 do
            local z = -2.4 - (tr - 1) * 1.5
            local pe = eng.scene.spawn("pad_" .. tostring(step) .. "_" .. tostring(tr))
            -- Pre-populate chord accompaniment on even steps so polyphonic harmonies sound out immediately!
            local start_on = ((step % 2 == 0) and (tr ~= (step / 2)))
            local pad = { ent = pe, step = step, track = tr, x = x, z = z, on = start_on, target = false }
            S.pads[step][tr] = pad
            refresh_pad(pad, false)
        end
    end

    for i = 1, #TARGETS do
        local t = TARGETS[i]
        S.pads[t.step][t.track].on = false
        S.pads[t.step][t.track].target = true
        refresh_pad(S.pads[t.step][t.track], false)
    end

    -- 3D Harmonic Lock Tower + 8 Animated EQ Bars + 4 Lock Crystals
    S.eq_bars = {}
    for step = 1, 8 do
        local x = -4.9 + (step - 1) * 1.4
        local be = eng.scene.spawn("tower_eq_" .. tostring(step))
        eng.scene.set_pos(be, x, 2.0, -10.2)
        eng.scene.set_scale(be, 0.75, 4.0, 0.75)
        eng.scene.set_mesh(be, S.box_mesh, { color = {0.30, 0.65, 1.0, 1.0}, roughness = 0.25 })
        S.eq_bars[step] = be
    end

    S.lock_crystals = {}
    for i = 1, 4 do
        local ce = eng.scene.spawn("harmonic_lock_" .. tostring(i))
        eng.scene.set_pos(ce, -3.0 + (i - 1) * 2.0, 4.6, -10.0)
        eng.scene.set_mesh(ce, S.crystal_mesh, { color = {0.4, 0.4, 0.5, 1.0} })
        S.lock_crystals[i] = ce
    end

    S.px, S.py, S.pz = -5.0, 2.3, 1.2
    S.yaw, S.pitch = 0.0, -16.0
    S.play_step = 1
    S.step_timer = 0.0
    S.toggle_cd = 0.0
    S.pads_toggled = 0
    S.notes_triggered = 0
    S.polyphonic_chords = 0
    S.unlocked_count = 0
    S.won = false

    eng.input.set_mouse_lock(true)
    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
    eng.mod.emit("post_init")
end

local function count_targets_lit()
    local n = 0
    for i = 1, #TARGETS do
        local t = TARGETS[i]
        if S.pads[t.step][t.track].on then
            n = n + 1
            eng.scene.set_mesh(S.lock_crystals[i], S.crystal_mesh, { color = {1.0, 0.88, 0.22, 1.0}, roughness = 0.1 })
        end
    end
    return n
end

function update(dt)
    if S.won then return end
    S.toggle_cd = math.max(0.0, S.toggle_cd - dt)

    local dx, dz
    S.yaw, S.pitch, dx, dz = eng.camera.fps_steer(S.yaw, S.pitch, 11.5, dt)
    S.px = eng.math.clamp(S.px + dx, -6.0, 6.0)
    S.pz = eng.math.clamp(S.pz + dz, -8.2, 2.0)

    -- Toggle nearest pad when pressing fire/interact
    if (eng.input.pressed("fire") or eng.input.down("fire") or eng.input.pressed("interact")) and S.toggle_cd <= 0.0 then
        for step = 1, 8 do
            for tr = 1, 4 do
                local p = S.pads[step][tr]
                if eng.math.dist3(S.px, 0.0, S.pz, p.x, 0.0, p.z) < 0.88 then
                    if not p.target or not p.on then
                        p.on = not p.on
                        S.pads_toggled = S.pads_toggled + 1
                        S.toggle_cd = 0.12
                        refresh_pad(p, step == S.play_step)
                        eng.audio.play(S.clips[tr][1], p.x, 0.5, p.z, 0)
                        S.unlocked_count = count_targets_lit()
                    end
                    break
                end
            end
        end
    end

    -- Step 8-column sequencer playhead & polyphonic synth playback
    S.step_timer = S.step_timer + dt
    if S.step_timer >= 0.085 then
        S.step_timer = S.step_timer - 0.085
        local prev = S.play_step
        S.play_step = (S.play_step % 8) + 1

        for tr = 1, 4 do refresh_pad(S.pads[prev][tr], false) end
        local voices = 0
        local chord_var = (S.play_step > 4) and 2 or 1
        for tr = 1, 4 do
            local p = S.pads[S.play_step][tr]
            refresh_pad(p, true)
            if p.on then
                eng.audio.play(S.clips[tr][chord_var], p.x, 0.5, p.z, 0)
                voices = voices + 1
                S.notes_triggered = S.notes_triggered + 1
            end
        end
        if voices >= 3 then S.polyphonic_chords = S.polyphonic_chords + 1 end

        -- Bounce 3D EQ Tower bars
        for step = 1, 8 do
            local bh = (step == S.play_step) and (2.0 + voices * 0.95) or 1.6
            local x = -4.9 + (step - 1) * 1.4
            eng.scene.set_pos(S.eq_bars[step], x, bh * 0.5, -10.2)
            eng.scene.set_scale(S.eq_bars[step], 0.75, bh, 0.75)
        end

        if S.unlocked_count >= 4 and S.polyphonic_chords >= 4 then
            eng.audio.play(S.sfx_unlock, 0.0, 3.0, -10.0, 0)
            S.won = true
            eng.save.write("synth_sequencer_clear", "unlocked")
        end
    end

    eng.camera.set(S.px, S.py, S.pz, S.pitch, S.yaw, 0.0, 0)
end

function draw()
    for i = 1, #TARGETS do
        local t = TARGETS[i]
        local p = S.pads[t.step][t.track]
        if not p.on then
            eng.render.draw_sprite(p.x, 1.1, p.z, 0.65, 0.65, S.orb_tex)
        end
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 560, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | STEP " .. S.play_step .. "/8 | HARMONIC KEYS " .. S.unlocked_count .. "/4", 1.0, {0.45, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.unlocked_count / 4.0, "LOCK ")
end
