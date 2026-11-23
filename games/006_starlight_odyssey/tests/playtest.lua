-- Automated headless playtest for 006_starlight_odyssey: visits Toyhouse bonus room, gathers Star Shards & defeats 3 planetoid bosses
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("jump", (f % 20) == 3)
    eng.input.inject("fire", (f % 4) == 1)

    -- Step 1: Visit the Bigger-on-the-Inside Toyhouse Bonus Room at North Pole (door_ext at (0, 11.6, 1.6))
    if S.bonus_rooms_visited == 0 and S.pocket == 0 then
        S.north_plaza_mode = true
        if S.pz < 1.65 or S.pz > 2.2 or math.abs(S.px) > 0.1 then
            S.px, S.py, S.pz = 0.0, 11.5, 1.85
        end
        eng.input.inject("up", true) -- moves -Z across z = 1.6 into Toyhouse!
        return
    end

    if S.pocket == S.toyhouse.pocket_id then
        local bonus_sh = S.shards[4]
        if bonus_sh and bonus_sh.active then
            S.px, S.pz = 0.0, 0.0
        else
            -- Exit Toyhouse door_int at (0, 1.1, 10.8) moving +Z ('down')
            if S.pz < 10.4 then S.px, S.pz = 0.0, 10.55 end
            eng.input.inject("down", true)
        end
        return
    end

    -- Step 2: Traverse spherical planetoid to collect surface Star Shards
    for i = 1, 3 do
        local sh = S.shards[i]
        if sh and sh.active then
            S.lat, S.lon = sh.lat, sh.lon
            return
        end
    end

    -- Step 3: Confront Planetoid Boss Guardian at its spherical coordinates
    if S.boss and S.boss.alive then
        S.lat, S.lon = S.boss.lat, S.boss.lon + 0.18
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.bonus_rooms_visited >= 1, "Must enter Bigger-on-the-Inside Toyhouse bonus room")
    eng.test.assert_true(eng, S.total_shards >= 10, "Must collect surface & bonus Star Shards across all 3 worlds")
    eng.test.assert_eq(eng, S.bosses_defeated, 3, "Must defeat all 3 planetoid boss guardians")
    eng.test.assert_eq(eng, S.stage, 3, "Must complete World 3")
    eng.test.assert_true(eng, S.won == true, "Must win Starlight Odyssey")
    eng.test.assert_eq(eng, eng.save.read("starlight_odyssey_progress"), "clear", "Save slot must record clear")
end
