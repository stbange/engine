-- Automated headless playtest for 049_cursed_lantern: collects oil, repels wraiths & lights all 4 beacons!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Grab oil flask first if fuel < 55 or along the path, then ignite next unlit beacon!
    local tx, tz = 0.0, 0.0
    local picked_target = false
    if S.fuel < 60.0 or S.fuel_collected == 0 then
        for i = 1, #S.oils do
            if not S.oils[i].taken then
                tx, tz = S.oils[i].x, S.oils[i].z
                picked_target = true
                break
            end
        end
    end
    if not picked_target then
        for i = 1, #S.beacons do
            if not S.beacons[i].lit then
                tx, tz = S.beacons[i].x, S.beacons[i].z
                break
            end
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
    eng.test.assert_true(eng, S.fuel_collected >= 1, "Must collect lantern oil in dark forest")
    eng.test.assert_true(eng, S.wraiths_repelled >= 2, "Lantern light radius must repel shadow wraiths")
    eng.test.assert_eq(eng, S.beacons_lit, 4, "Must ignite all 4 ancient beacons")
    eng.test.assert_true(eng, S.hp > 0, "Lantern bearer must survive")
    eng.test.assert_true(eng, S.won == true, "Curse must be banished")
end
