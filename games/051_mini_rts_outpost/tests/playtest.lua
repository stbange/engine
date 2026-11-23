-- Headless playtest for 051_mini_rts_outpost
function playtest_frame(f)
    local S = game.state
    if S.won or S.lost then
        S.playtest_done = true
        return
    end
    -- Direct command cursor toward crystal fields & rival HQ, harvest & deploy tank platoon
    eng.input.inject("right", f < 45)
    eng.input.inject("up", f < 35)
    eng.input.inject("interact", (f % 18) == 2)
    eng.input.inject("fire", (f % 12) == 4)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.harvested_total >= 25, "Harvesters must gather crystals")
    eng.test.assert_true(eng, S.tanks_deployed >= 3, "Commander must deploy at least 3 light tanks")
    eng.test.assert_true(eng, S.kills >= 1, "Light tanks must destroy at least 1 rival raider")
    eng.test.assert_eq(eng, S.enemy_hp, 0, "Rival HQ must be destroyed")
    eng.test.assert_true(eng, S.won == true and S.lost == false, "Player must win Mini RTS Outpost")
    eng.test.assert_eq(eng, eng.save.read("rts_outpost_status"), "victory", "Save must record victory")
end
