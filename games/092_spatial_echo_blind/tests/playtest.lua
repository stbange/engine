-- Automated headless playtest for 092_spatial_echo_blind
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    -- Emit echolocation pulses periodically while walking forward through the portal doorway
    eng.input.inject("fire", (f % 16) == 1)
    eng.input.inject("up", true)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.pulses >= 3, "Must emit at least 3 sonar echolocation pulses")
    eng.test.assert_true(eng, S.cross_pings >= 3, "Must trigger cross-portal 3D audio pings from exit chime")
    eng.test.assert_true(eng, S.echo_hits >= 1, "Cross-portal raycast must detect exit chime through doorway")
    eng.test.assert_true(eng, S.crossed_portal == true, "Player must traverse portal into echo_sanctum")
    eng.test.assert_true(eng, S.won == true, "Must reach the Exit Chime Shrine")
end
