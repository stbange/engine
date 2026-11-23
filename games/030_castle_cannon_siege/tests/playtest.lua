-- Automated headless playtest for 030_castle_cannon_siege: aims pitch & yaw, breaches WFC fortress wall, hits chest
local function has_live_ball(S)
    for i = 1, #S.balls do
        if S.balls[i].active then return true end
    end
    return false
end

function playtest_frame(f)
    local _ = f
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Shot 1 targets center curtain wall (yaw = 0.0, pitch = 16.0); Shot 2 targets Crown Chest through breach (pitch = 17.0)
    local tgt_yaw = 0.0
    local tgt_pitch = (S.walls_breached == 0) and 16.0 or 17.0

    local dyaw = tgt_yaw - S.yaw_deg
    local dpitch = tgt_pitch - S.pitch_deg

    -- Note: +mx decreases yaw_deg (turns barrel right toward +X), so dyaw > 0 uses "left"
    eng.input.inject("left", dyaw > 0.35)
    eng.input.inject("right", dyaw < -0.35)
    eng.input.inject("up", dpitch > 0.35)
    eng.input.inject("down", dpitch < -0.35)

    local aligned = (math.abs(dyaw) <= 0.45 and math.abs(dpitch) <= 0.45)
    eng.input.inject("fire", aligned and not has_live_ball(S) and S.fire_cd <= 0.0)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.wfc_solvable == true, "WFC fortress layout must be valid")
    eng.test.assert_true(eng, S.shots_fired >= 2, "Must fire ballistic siege volleys")
    eng.test.assert_true(eng, S.walls_breached >= 2, "First volley must breach voxel curtain wall")
    eng.test.assert_true(eng, S.won == true, "Second volley must strike the royal crown chest")
end
