-- Automated headless playtest for 100_engine_meta_arcade
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("fire", true) -- Arcade sprint

    -- If inside one of the bigger-on-the-inside cabinet pockets:
    for i = 1, 3 do
        local c = S.cabinets[i]
        if S.pocket == c.pocket_id then
            local tx = 0.0
            -- Grab token at z = 4.2 first, then walk back out (+Z) through d_int at z = 7.8!
            local tz = c.won_token and 8.5 or c.obj_z
            eng.input.inject("left", S.px > tx + 0.12)
            eng.input.inject("right", S.px < tx - 0.12)
            eng.input.inject("up", S.pz > tz + 0.12)
            eng.input.inject("down", S.pz < tz - 0.12)
            return
        end
    end

    -- In main Arcade Hall (pocket 0): enter next unbeaten cabinet screen, or claim Golden Master Trophy!
    local tx, tz = S.trophy_x, S.trophy_z
    for i = 1, 3 do
        local c = S.cabinets[i]
        if not c.won_token then
            tx = c.x
            -- Step into main aisle (z = -5.8) while aligning X, then step into cabinet screen!
            if math.abs(S.px - c.x) > 0.35 then
                tz = -5.8
            else
                tz = c.front_z - 0.8
            end
            break
        end
    end

    eng.input.inject("left", S.px > tx + 0.12)
    eng.input.inject("right", S.px < tx - 0.12)
    eng.input.inject("up", S.pz > tz + 0.12)
    eng.input.inject("down", S.pz < tz - 0.12)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.cabinets_entered, 3, "Must enter all 3 bigger-on-the-inside arcade cabinet portals")
    eng.test.assert_eq(eng, S.tokens, 3, "Must win arcade tokens inside all 3 mini-cabinets")
    eng.test.assert_true(eng, S.trophy_unlocked == true, "Must unlock the Golden Master #100 Trophy")
    eng.test.assert_true(eng, S.won == true, "Must claim the Golden Master #100 Trophy")
    eng.test.assert_eq(eng, eng.save.read("engine_meta_arcade_100"), "golden_master", "Must save #100 Golden Master completion")
end
