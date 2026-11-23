-- Automated headless playtest for 014_twin_stick_crypt
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", false)

    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Grab nearest powerup first to upgrade twin-stick crossbow spread, then hunt remaining targets!
    local gx, gz = nil, nil
    for i = 1, #S.powerups do
        if not S.powerups[i].taken then
            gx, gz = S.powerups[i].x, S.powerups[i].z
            break
        end
    end
    if not gx then
        local best_d = 999.0
        for i = 1, #S.targets do
            local tg = S.targets[i]
            if tg.alive then
                local d = eng.math.dist3(S.px, 0, S.pz, tg.x, 0, tg.z)
                if d < best_d then best_d = d; gx, gz = tg.x, tg.z end
            end
        end
    end

    if gx and gz then
        if gx - S.px > 0.6 then eng.input.inject("right", true)
        elseif gx - S.px < -0.6 then eng.input.inject("left", true) end
        if gz - S.pz < -0.6 then eng.input.inject("up", true)
        elseif gz - S.pz > 0.6 then eng.input.inject("down", true) end
    end

    eng.input.inject("jump", (f % 48) == 5)
    eng.input.inject("interact", (f % 35) == 10)
    eng.input.inject("fire", (f % 2) == 0)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.solvable == true, "BSP crypt arena must be solvable")
    eng.test.assert_true(eng, S.powerups_grabbed >= 1, "Must grab at least 1 crypt weapon powerup")
    eng.test.assert_true(eng, S.weapon_lvl >= 2, "Must upgrade twin-stick crossbow spread")
    eng.test.assert_eq(eng, S.kills, 8, "Must destroy all swarmers and spawner obelisks")
    eng.test.assert_true(eng, S.lost == false, "Hunter must survive crypt swarm")
    eng.test.assert_true(eng, S.won == true, "Must clear Twin-Stick Crypt")
    eng.test.assert_true(eng, eng.save.read("twin_crypt_best") ~= nil, "Must save Twin-Stick Crypt score")
end
