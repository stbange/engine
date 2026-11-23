-- Headless playtest for 055_orbital_station_sim: crosses into bigger-on-the-inside pod & balances station!
function playtest_frame(f)
    local S = game.state
    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Walk straight north along X=0 through central pod airlock door (z = -4.4) into pod_solar!
    eng.input.inject("up", S.pods_visited == 0)
    eng.input.inject("fire", (f % 8) == 2)
    eng.input.inject("interact", (f % 10) == 5)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, #S.pods == 3, "Must link 3 bigger-on-the-inside pocket habitat pods")
    eng.test.assert_true(eng, S.pods_visited >= 1, "Commander must traverse portal into an oversized habitat pod")
    eng.test.assert_true(eng, #S.crew >= 5, "Station must staff at least 5 procedural astronauts")
    eng.test.assert_true(eng, S.oxygen >= 75.0 and S.power >= 75.0, "Oxygen and solar power must be balanced >= 75%")
    eng.test.assert_true(eng, S.won == true and S.lost == false, "Station must reach 100% operational victory")
    eng.test.assert_eq(eng, eng.save.read("orbital_station_status"), "operational", "Save must record operational")
end
