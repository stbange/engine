-- Automated headless playtest for 045_tavern_keep: refills kegs & serves 5 Markov-named BT patrons!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local tx, tz = S.kegs[1].x, S.kegs[1].z
    if S.mugs > 0 then
        -- Find most urgent seated patron (or any unserved patron)
        local best_pat = 999.0
        for i = 1, 3 do
            local p = S.patrons[i]
            if p and not p.served and p.seated and p.patience < best_pat then
                best_pat = p.patience
                tx, tz = p.x, p.z
            end
        end
        if best_pat == 999.0 then
            tx, tz = 0.0, 0.0 -- stand ready near center tables
        end
    end

    eng.input.inject("left", tx < S.px - 0.15)
    eng.input.inject("right", tx > S.px + 0.15)
    eng.input.inject("up", tz < S.pz - 0.15)
    eng.input.inject("down", tz > S.pz + 0.15)
    eng.input.inject("fire", (f % 4) == 1)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.bt_ticks >= 30, "Behavior trees (eng.bt) must tick patrons")
    eng.test.assert_true(eng, #S.last_served_name > 0, "Served patrons must have procedural Markov names")
    eng.test.assert_eq(eng, S.lost, 0, "Zero patrons should storm out")
    eng.test.assert_true(eng, S.served >= 5, "Must serve at least 5 tavern patrons")
    eng.test.assert_true(eng, S.won == true, "Tavern shift must succeed")
end
