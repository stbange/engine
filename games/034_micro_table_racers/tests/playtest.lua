-- Automated headless playtest for 034_micro_table_racers: drifts & boosts around tabletop props to win in 1st
local WAYPOINTS = {
    { 9.0, -5.5 }, { 9.5, 5.0 }, { 1.5, 7.2 },
    { -9.0, 5.2 }, { -9.5, -5.0 }, { -0.5, -7.2 }
}

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("up", true)
    local wp = WAYPOINTS[S.wp_idx]
    local want_yaw = math.deg(math.atan2(-(wp[1] - S.cx), -(wp[2] - S.cz)))
    local dyaw = want_yaw - S.yaw
    while dyaw > 180.0 do dyaw = dyaw - 360.0 end
    while dyaw < -180.0 do dyaw = dyaw + 360.0 end

    eng.input.inject("left", dyaw > 4.0)
    eng.input.inject("right", dyaw < -4.0)
    eng.input.inject("fire", math.abs(dyaw) > 22.0)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.turbos >= 1, "Must trigger at least 1 sugar/drift mini-turbo")
    eng.test.assert_true(eng, S.laps >= 2 and S.won == true, "Must finish 2 tabletop laps")
    eng.test.assert_eq(eng, S.rank, 1, "Must finish 1st ahead of rival micro cars")
end
