-- Automated headless playtest for 095_net_pong_4p
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Track the ball soonest to reach South goal wall (vz > 0, largest z)
    local best, best_score = S.balls[1], -999.0
    for i = 1, #S.balls do
        local b = S.balls[i]
        local urgency = (b.vz > 0.0) and (b.z + 20.0) or (-b.z)
        if urgency > best_score then
            best_score = urgency
            best = b
        end
    end

    local px = S.peers[1].pos
    eng.input.inject("left", px > best.x + 0.2)
    eng.input.inject("right", px < best.x - 0.2)
    eng.input.inject("fire", true)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.net_tick >= 20, "Must advance replicated arena ticks")
    eng.test.assert_true(eng, S.replicated_packets >= 80, "Must replicate 4-peer input packets")
    eng.test.assert_true(eng, S.goals_scored >= 5 or S.bots_eliminated >= 3, "Must score goals against replicated bot walls")
    eng.test.assert_true(eng, S.won == true, "Must win 4-player Net Pong battle")
end
