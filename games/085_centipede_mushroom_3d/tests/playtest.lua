-- Headless playtest for 085_centipede_mushroom_3d: splits & blasts procedural serpents through 3D mushroom patches!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end

    -- Target a mid-body segment first to trigger a centipede split + mushroom bloom, then lowest segment!
    local target = nil
    if S.splits_triggered == 0 then
        for i = 2, #S.segs - 1 do
            if S.segs[i].alive and S.segs[i + 1] and S.segs[i + 1].alive then
                target = S.segs[i]
                break
            end
        end
    end
    if not target then
        local best_z = -999.0
        for i = 1, #S.segs do
            local s = S.segs[i]
            if s.alive and s.z > best_z then
                best_z = s.z
                target = s
            end
        end
    end

    if target then
        local seg_spd = 6.6 + (S.wave - 1) * 1.1
        local t_flight = math.max(0.0, (S.pz - 0.7 - target.z) / 30.0)
        local lead_x = target.x + ((target.drop_rem > 0.0) and 0.0 or (target.dir_x * seg_spd * t_flight * 0.75))
        lead_x = eng.math.clamp(lead_x, -7.8, 7.8)
        local err_x = lead_x - S.px
        if math.abs(err_x) > 0.16 then
            eng.input.inject(err_x > 0.0 and "right" or "left", true)
        end
        if math.abs(err_x) < 1.1 then
            eng.input.inject("fire", true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.serpent_segments_spawned >= 12, "Must spawn multi-segment procedural serpents")
    eng.test.assert_true(eng, S.segments_blasted >= 12, "Must blast all descending serpent segments")
    eng.test.assert_true(eng, S.splits_triggered >= 1, "Mid-body shots must split serpent chain")
    eng.test.assert_true(eng, S.mushrooms_damaged >= 1, "Plasma bolts must interact with 3D mushroom patches")
    eng.test.assert_eq(eng, S.wave, 2, "Must reach and clear final wave 2")
    eng.test.assert_true(eng, S.won == true, "Must win Centipede Mushroom 3D")
end
