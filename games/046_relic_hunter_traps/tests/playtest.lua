-- Automated headless playtest for 046_relic_hunter_traps: dodges pendulums & darts, grabs idol, outruns boulder!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("jump", false)
    if S.won then
        S.playtest_done = true
        return
    end

    -- Sprint toward Golden Idol (-Z), then sprint back out (+Z) ahead of the rolling boulder!
    eng.input.inject("up", not S.has_idol)
    eng.input.inject("down", S.has_idol)

    -- Weave opposite the nearest swinging pendulum blade, or center on idol/exit
    local target_x = 0.0
    for i = 1, #S.pendulums do
        local p = S.pendulums[i]
        if math.abs(S.pz - p.z) < 2.2 then
            target_x = (p.blade_x >= 0.0) and -2.2 or 2.2
            break
        end
    end
    eng.input.inject("left", target_x < S.px - 0.15)
    eng.input.inject("right", target_x > S.px + 0.15)

    -- Vault over poison wall darts when approaching dart lanes
    for i = 1, #S.darts do
        if math.abs(S.pz - S.darts[i].z) < 1.1 and (f % 2 == 1) then
            eng.input.inject("jump", true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.jumps >= 1, "Must jump over temple dart traps")
    eng.test.assert_true(eng, S.has_idol == true, "Must claim the Golden Idol")
    eng.test.assert_true(eng, S.boulder_spawned == true, "Rolling stone boulder trap must trigger")
    eng.test.assert_true(eng, S.pz > S.boulder_z, "Must outrun the rolling boulder sphere")
    eng.test.assert_true(eng, S.hp > 0, "Relic hunter must survive")
    eng.test.assert_true(eng, S.won == true, "Must escape temple with Golden Idol")
end
