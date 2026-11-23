-- Headless playtest for 077_hoops_arcade: charges shot arc & leads moving hoop to build a 5-swish streak!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Predict hoop_x 0.85s (+ 1 step) ahead when ball crosses rim plane!
    local omega = 1.25 + math.min(S.baskets, 5) * 0.12
    local pred_x = math.sin(S.hoop_phase + omega * (0.85 + 1.0 / 60.0)) * 1.75
    S.aim_x = pred_x

    local ready_next = (#S.shots == 0) or S.shots[#S.shots].scored
    if not S.charging and S.cooldown <= 0.001 and ready_next then
        eng.input.inject("fire", true)
    elseif S.charging then
        -- Hold fire until charge reaches sweet-spot 0.75, then release!
        if S.charge >= 0.75 then
            eng.input.inject("fire", false)
        else
            eng.input.inject("fire", true)
        end
    else
        eng.input.inject("fire", false)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.baskets >= 5, "Must swish at least 5 baskets through moving rim")
    eng.test.assert_true(eng, S.max_streak >= 3, "Must build at least a 3x streak multiplier")
    eng.test.assert_true(eng, S.score >= 1000, "Streak multipliers must boost arcade score >= 1000")
    eng.test.assert_true(eng, S.won == true, "Must win Hoops Arcade")
end
