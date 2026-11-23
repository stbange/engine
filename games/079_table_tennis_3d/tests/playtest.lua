-- Headless playtest for 079_table_tennis_3d: rallies with slice & rips angled topspin winners to win 5 points!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", false)

    -- Track incoming ball x with non-oscillating deadband
    local err_x = S.bx - S.px
    if math.abs(err_x) > 0.08 then
        if err_x > 0.0 then eng.input.inject("right", true) else eng.input.inject("left", true) end
    end
    S.py = eng.math.clamp(S.by, 0.88, 1.28)

    -- Open rally 1 with a backspin slice (`interact`), then rip heavy topspin (`fire`) cross-court winner!
    if S.rally_exchange == 0 and S.player_pts == 0 then
        eng.input.inject("interact", true)
    else
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.rallies >= 8, "Must sustain multi-shot ping-pong rallies over the net")
    eng.test.assert_true(eng, S.topspin_hits >= 4, "Must execute Magnus topspin drives")
    eng.test.assert_true(eng, S.slice_hits >= 1, "Must execute backspin slice return")
    eng.test.assert_eq(eng, S.player_pts, 5, "Player must win 5 points")
    eng.test.assert_true(eng, S.won == true, "Must win Table Tennis 3D match")
end
