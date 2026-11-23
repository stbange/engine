-- Automated headless playtest for 036_snowboard_slalom: carves cleanly through all 6 slalom gates to the finish arch
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Find the next unjudged slalom gate, or aim center for the finish arch
    local tgt_x = 0.0
    for i = 1, #S.gates do
        if not S.gates[i].judged then
            tgt_x = S.gates[i].x
            break
        end
    end

    local want_vx = eng.math.clamp((tgt_x - S.bx) * 5.2, -12.5, 12.5)
    local dvx = want_vx - S.vx

    eng.input.inject("right", dvx > 0.30)
    eng.input.inject("left", dvx < -0.30)
    eng.input.inject("up", math.abs(tgt_x - S.bx) < 1.1)
    eng.input.inject("jump", f == 90)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.gates_passed, 6, "Must carve cleanly through all 6 red and blue slalom gates")
    eng.test.assert_true(eng, S.score >= 4000, "Must build slalom combo score")
    eng.test.assert_true(eng, S.won == true, "Must cross alpine finish arch for gold")
    eng.test.assert_true(eng, eng.save.read("snowboard_slalom_clear") ~= nil, "Must persist slalom clear score")
end
