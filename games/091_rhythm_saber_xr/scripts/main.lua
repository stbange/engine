-- 091_rhythm_saber_xr: 6DoF WebXR Beat Cube Slasher with Synthesized Melody
local S = game.state

local LANES = { -1.35, 0.0, 1.35 }
local HEIGHTS = { 1.05, 1.70 }
local MELODY_HZ = { 261.63, 311.13, 349.23, 392.00, 466.16, 523.25, 622.25, 523.25 }

function init()
    eng.xr.set_mode("6dof")
    eng.render.set_sky(0.02, 0.01, 0.06, 0.12, 0.04, 0.20)
    eng.render.add_light({ type = "dir", dir = {-0.2, -1.0, -0.4}, color = {1.5, 1.4, 1.8}, shadow = true })
    eng.render.add_light({ type = "point", pos = {-2.2, 2.5, -6.0}, color = {3.0, 0.4, 0.8}, range = 22.0 })
    eng.render.add_light({ type = "point", pos = { 2.2, 2.5, -6.0}, color = {0.3, 2.4, 3.0}, range = 22.0 })

    S.box_mesh = eng.asset.box(1, 1, 1)
    S.cyl_mesh = eng.asset.cylinder(0.05, 0.05, 1.15, 12)
    S.orb_tex = eng.asset.load_texture("assets/shared/sprites/orb_sprite.png", true)

    local seed = math.floor(eng.math.range(100, 90000))
    local track_tex = eng.procgen.texture("sci_fi_panel", seed, 64)

    -- Neon runway deck + lane rails
    local deck = eng.scene.spawn("saber_runway")
    eng.scene.set_pos(deck, 0.0, -0.15, -12.0)
    eng.scene.set_scale(deck, 5.2, 0.3, 28.0)
    eng.scene.set_mesh(deck, S.box_mesh, { tex = track_tex, color = {0.18, 0.20, 0.30, 1.0}, roughness = 0.25, metallic = 0.6 })

    for side = -1, 1, 2 do
        local rail = eng.scene.spawn("neon_rail_" .. tostring(side))
        eng.scene.set_pos(rail, side * 2.5, 0.15, -12.0)
        eng.scene.set_scale(rail, 0.16, 0.25, 28.0)
        local c = side < 0 and {1.0, 0.2, 0.45, 1.0} or {0.15, 0.9, 1.0, 1.0}
        eng.scene.set_mesh(rail, S.box_mesh, { color = c, roughness = 0.2 })
        for p = 1, 4 do
            local arch = eng.scene.spawn("beat_pillar_" .. tostring(side) .. "_" .. tostring(p))
            eng.scene.set_pos(arch, side * 2.8, 1.8, -p * 5.5)
            eng.scene.set_scale(arch, 0.25, 3.6, 0.25)
            eng.scene.set_mesh(arch, S.box_mesh, { color = c, roughness = 0.3 })
        end
    end

    -- Pre-synthesize musical pitch clips (Red = saw lead, Cyan = triangle harmony)
    S.clips_red = {}
    S.clips_cyan = {}
    for i = 1, #MELODY_HZ do
        local hz = MELODY_HZ[i]
        S.clips_red[i] = eng.audio.synth("saw", hz, 0.16, hz * 1.02)
        S.clips_cyan[i] = eng.audio.synth("triangle", hz * 1.5, 0.16, hz * 1.5)
    end
    S.sfx_miss = eng.audio.synth("noise", 160, 0.12, 80)

    -- 6DoF dual sabers (Red left, Cyan right)
    S.sx, S.sy = 0.0, 1.25
    S.swing_t = 0.0
    S.saber_red = eng.scene.spawn("saber_red")
    eng.scene.set_mesh(S.saber_red, S.cyl_mesh, { color = {1.0, 0.18, 0.32, 1.0}, roughness = 0.15 })
    S.saber_cyan = eng.scene.spawn("saber_cyan")
    eng.scene.set_mesh(S.saber_cyan, S.cyl_mesh, { color = {0.15, 0.92, 1.0, 1.0}, roughness = 0.15 })

    -- Spawn 12 deterministic beat cubes synced along the track
    S.cubes = {}
    for i = 1, 12 do
        local lane_i = ((i + seed) % 3) + 1
        local h_i = ((i * 3 + seed) % 2) + 1
        local color_kind = (i % 2 == 1) and 1 or 2 -- 1=Red, 2=Cyan
        local ce = eng.scene.spawn("beat_cube_" .. tostring(i))
        local cx, cy, cz = LANES[lane_i], HEIGHTS[h_i], -4.2 - (i - 1) * 2.1
        eng.scene.set_pos(ce, cx, cy, cz)
        eng.scene.set_scale(ce, 0.58, 0.58, 0.58)
        local col = (color_kind == 1) and {1.0, 0.22, 0.36, 1.0} or {0.16, 0.90, 1.0, 1.0}
        eng.scene.set_mesh(ce, S.box_mesh, { color = col, roughness = 0.2, metallic = 0.3, cast_shadow = true })
        S.cubes[i] = {
            ent = ce, x = cx, y = cy, z = cz,
            kind = color_kind, pitch_idx = ((i - 1) % #MELODY_HZ) + 1,
            active = true
        }
    end

    S.score = 0
    S.combo = 0
    S.max_combo = 0
    S.slashed = 0
    S.missed = 0
    S.notes_played = 0
    S.sparks = {}
    S.xr_checked = eng.xr.is_active()
    S.won = false

    update_sabers()
    eng.camera.look_at(0.0, 2.05, 2.3, 0.0, 1.25, -9.0, 0)
    eng.mod.emit("post_init")
end

function update_sabers()
    local slash_pitch = (S.swing_t > 0.0) and -65.0 or -22.0
    -- Offset sabers slightly around S.sx; during slash they cross cleanly through S.sx
    local spread = (S.swing_t > 0.0) and 0.14 or 0.34
    eng.scene.set_pos(S.saber_red, S.sx - spread, S.sy, -1.05)
    eng.scene.set_rot_deg(S.saber_red, slash_pitch, -12.0, -18.0)
    eng.scene.set_pos(S.saber_cyan, S.sx + spread, S.sy, -1.05)
    eng.scene.set_rot_deg(S.saber_cyan, slash_pitch, 12.0, 18.0)
end

function update(dt)
    if S.won then return end
    S.swing_t = math.max(0.0, S.swing_t - dt)

    local mx, my = eng.input.axis2d("left", "right", "down", "up")
    S.sx = eng.math.clamp(S.sx + mx * 9.5 * dt, -1.65, 1.65)
    S.sy = eng.math.clamp(S.sy + my * 6.5 * dt, 0.90, 1.90)

    if eng.input.pressed("fire") or eng.input.down("fire") or eng.input.pressed("jump") then
        S.swing_t = 0.16
    end
    update_sabers()

    local active_left = 0
    for i = 1, #S.cubes do
        local c = S.cubes[i]
        if c.active then
            c.z = c.z + 11.5 * dt
            eng.scene.set_pos(c.ent, c.x, c.y, c.z)
            eng.scene.set_rot_deg(c.ent, 0.0, c.z * 18.0, c.z * 9.0)

            -- Check 6DoF saber slash in beat window
            local saber_x = (c.kind == 1) and (S.sx - 0.14) or (S.sx + 0.14)
            local hit_r = (S.swing_t > 0.0) and 0.72 or 0.42
            if c.z >= -2.15 and c.z <= 0.15 and math.abs(c.x - saber_x) <= hit_r and math.abs(c.y - S.sy) <= 0.60 then
                c.active = false
                eng.scene.despawn(c.ent)
                local clip = (c.kind == 1) and S.clips_red[c.pitch_idx] or S.clips_cyan[c.pitch_idx]
                eng.audio.play(clip, c.x, c.y, c.z, 0)
                S.notes_played = S.notes_played + 1
                S.slashed = S.slashed + 1
                S.combo = S.combo + 1
                if S.combo > S.max_combo then S.max_combo = S.combo end
                S.score = S.score + 100 * S.combo
                S.sparks[#S.sparks + 1] = { x = c.x, y = c.y, z = c.z, t = 0.25 }
            elseif c.z > 0.9 then
                c.active = false
                eng.scene.despawn(c.ent)
                eng.audio.play(S.sfx_miss, c.x, c.y, 0.0, 0)
                S.combo = 0
                S.missed = S.missed + 1
            else
                active_left = active_left + 1
            end
        end
    end

    for i = #S.sparks, 1, -1 do
        S.sparks[i].t = S.sparks[i].t - dt
        if S.sparks[i].t <= 0.0 then table.remove(S.sparks, i) end
    end

    if S.slashed >= 10 or (active_left == 0 and S.slashed >= 8) then
        S.won = true
        eng.save.write("rhythm_saber_best", tostring(S.score))
    end
end

function draw()
    for i = 1, #S.sparks do
        local sp = S.sparks[i]
        eng.render.draw_sprite(sp.x, sp.y, sp.z, 0.9, 0.9, S.orb_tex)
    end
    local x, y = eng.ui.anchor("top_left", 16, 14, 520, 28, 1280, 720)
    eng.ui.label(x, y, eng.i18n.t("title") .. " | COMBO x" .. S.combo .. " | SCORE " .. S.score, 1.0, {0.4, 0.95, 1.0, 1.0})
    eng.ui.bar(x, y + 26, 220, S.slashed / 10.0, "BEATS ")
end
