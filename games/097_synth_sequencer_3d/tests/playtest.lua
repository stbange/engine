-- Automated headless playtest for 097_synth_sequencer_3d
local TARGETS = {
    { step = 2, track = 1 },
    { step = 4, track = 2 },
    { step = 6, track = 3 },
    { step = 8, track = 4 }
}

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local tgt_pad = nil
    for i = 1, #TARGETS do
        local t = TARGETS[i]
        local p = S.pads[t.step][t.track]
        if not p.on then
            tgt_pad = p
            break
        end
    end

    if tgt_pad then
        eng.input.inject("left", S.px > tgt_pad.x + 0.15)
        eng.input.inject("right", S.px < tgt_pad.x - 0.15)
        eng.input.inject("up", S.pz > tgt_pad.z + 0.15)
        eng.input.inject("down", S.pz < tgt_pad.z - 0.15)
        local d = eng.math.dist3(S.px, 0, S.pz, tgt_pad.x, 0, tgt_pad.z)
        eng.input.inject("fire", d < 0.75)
    else
        eng.input.inject("left", false)
        eng.input.inject("right", false)
        eng.input.inject("up", false)
        eng.input.inject("down", false)
        eng.input.inject("fire", false)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.pads_toggled >= 4, "Must toggle all 4 missing harmonic pads")
    eng.test.assert_eq(eng, S.unlocked_count, 4, "All 4 harmonic lock crystals must be lit")
    eng.test.assert_true(eng, S.polyphonic_chords >= 4, "Must trigger polyphonic multi-track synth harmonies")
    eng.test.assert_true(eng, S.notes_triggered >= 12, "Must play synthesized sequencer notes")
    eng.test.assert_true(eng, S.won == true, "Must unlock the 3D Harmonic Tower")
end
