-- Headless playtest for 073_air_hockey_neon: beats AI defender to 5 goals via angled bank & corner strikes!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    local kx, _, kz = eng.scene.get_pos(S.puck_ent)
    local _, _, vz = eng.physics.get_vel(S.puck_body)

    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)

    if kz > 0.1 and vz > -3.0 then
        -- Align behind puck opposite AI first, then drive straight through into open net!
        local side_off = (S.ax >= 0.0) and 0.13 or -0.13
        local tx = kx + side_off
        local err_x = tx - S.px
        if math.abs(err_x) > 0.09 and S.pz > kz + 0.85 then
            if err_x > 0.0 then eng.input.inject("right", true) else eng.input.inject("left", true) end
        else
            if S.pz > kz + 0.05 then
                eng.input.inject("up", true)
            else
                eng.input.inject("down", true)
            end
        end
    else
        if S.pz < 3.4 then eng.input.inject("down", true) end
        if S.px < kx - 0.15 then eng.input.inject("right", true)
        elseif S.px > kx + 0.15 then eng.input.inject("left", true) end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.mallet_hits >= 5, "Must strike puck with mallet at least 5 times")
    eng.test.assert_eq(eng, S.player_goals, 5, "Player must score 5 goals")
    eng.test.assert_true(eng, S.won == true, "Must win Air Hockey Neon")
    eng.test.assert_eq(eng, eng.save.read("air_hockey_champ"), "5", "Save must record championship")
end
