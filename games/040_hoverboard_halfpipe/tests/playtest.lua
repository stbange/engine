-- Automated headless playtest for 040_hoverboard_halfpipe: pumps transitions & lands multi-spin lip aerial combos
function playtest_frame(f)
    local _ = f
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    if not S.airborne then
        -- Pump curved transitions in direction of travel and pop jump near the coping lip
        local on_trans = math.abs(S.arc_s) > 1.85
        eng.input.inject("up", on_trans)
        eng.input.inject("right", S.vel_s > 0.2 and on_trans)
        eng.input.inject("left", S.vel_s < -0.2 and on_trans)
        eng.input.inject("jump", math.abs(S.arc_s) > 6.2 and (S.arc_s * S.vel_s > 0.0))
        eng.input.inject("fire", false)
    else
        -- Spin 540+/720+ and hold nosegrab in the air above the coping lip
        eng.input.inject("up", false)
        eng.input.inject("right", true)
        eng.input.inject("left", false)
        eng.input.inject("jump", false)
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.pumps >= 2, "Must pump halfpipe transitions to build vertical speed")
    eng.test.assert_true(eng, S.max_height > 5.0, "Must launch high above the 3.6m halfpipe coping lip")
    eng.test.assert_true(eng, S.aerial_combos >= 2, "Must stomp at least 2 aerial spin-and-grab combos")
    eng.test.assert_true(eng, S.score >= 2500, "Must score >= 2500 combo points")
    eng.test.assert_true(eng, S.won == true, "Must win Hoverboard Halfpipe")
    eng.test.assert_true(eng, eng.save.read("hoverboard_halfpipe_clear") ~= nil, "Must save halfpipe high score")
end
