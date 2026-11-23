-- Headless playtest for 072_cyber_pinball_3d: plunges ball, hits jet bumpers, warps to upper bonus table & wins!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    local pk = eng.scene.get_pocket(S.ball_ent)
    local bx, _, bz = eng.scene.get_pos(S.ball_ent)

    -- Plunge when in shooter lane
    eng.input.inject("jump", pk == 0 and bx > 2.5 and bz > 3.5 and (f % 4 == 1))

    -- Trigger flippers reactively when ball enters flipper zone
    local in_flip = (pk == 0 and bz > 3.80 and bz < 5.15)
    eng.input.inject("left", in_flip and bx <= 0.05)
    eng.input.inject("right", in_flip and bx > 0.05)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.bumper_hits >= 2, "Must hit neon jet bumpers")
    eng.test.assert_true(eng, S.upper_visits >= 1, "Must enter pocket bonus upper table")
    eng.test.assert_true(eng, S.score >= 2500, "Must reach wizard target score >= 2500")
    eng.test.assert_true(eng, S.won == true, "Must win Cyber Pinball 3D")
end
