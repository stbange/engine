-- Headless playtest for 056_sheepdog_herder: flanks furthest stray sheep & barks flock into pen!
function playtest_frame(f)
    local S = game.state
    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Target the unpenned sheep furthest from the corral gate (0, -7.8) so stragglers never split!
    local best = nil
    local worst_d = -1.0
    for i = 1, #S.sheep do
        local s = S.sheep[i]
        if not s.penned then
            local d = eng.math.dist3(s.x, 0, s.z, 0.0, 0, -7.8) + math.abs(s.x) * 0.6
            if d > worst_d then worst_d = d; best = s end
        end
    end

    if best then
        local vx, vz = best.x - 0.0, best.z - (-8.2)
        local vl = math.sqrt(vx * vx + vz * vz)
        if vl < 0.01 then vx, vz, vl = 0.0, 1.0, 1.0 end
        local tx = best.x + (vx / vl) * 2.8
        local tz = best.z + (vz / vl) * 2.8

        eng.input.inject("jump", true)
        eng.input.inject("left", tx < S.dx - 0.25)
        eng.input.inject("right", tx > S.dx + 0.25)
        eng.input.inject("up", tz < S.dz - 0.25)
        eng.input.inject("down", tz > S.dz + 0.25)

        local dog_aligned = eng.math.dist3(S.dx, 0, S.dz, tx, 0, tz) < 2.6
        eng.input.inject("fire", dog_aligned and ((f % 5) == 1))
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, #S.sheep, 7, "Must spawn 7 procedural quadruped sheep")
    eng.test.assert_true(eng, S.barks >= 3, "Sheepdog must bark to drive flock")
    eng.test.assert_true(eng, S.penned_count >= 6, "Must herd at least 6 sheep into wooden pen")
    eng.test.assert_true(eng, S.won == true and S.lost == false, "Must win Sheepdog Herder before sunset")
end
