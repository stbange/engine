-- Automated headless playtest for 013_mech_siege
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

    -- Prioritize sapper closest to Reactor Core (0, 0, 0)
    local urgent = nil
    local best_core_d = 999.0
    for i = 1, #S.sappers do
        local sp = S.sappers[i]
        if sp.alive then
            local cd = eng.math.dist3(0, 0, 0, sp.x, 0, sp.z)
            if cd < best_core_d then
                best_core_d = cd
                urgent = sp
            end
        end
    end

    if urgent then
        if urgent.x - S.px > 0.8 then eng.input.inject("right", true)
        elseif urgent.x - S.px < -0.8 then eng.input.inject("left", true) end
        if urgent.z - S.pz < -0.8 then eng.input.inject("up", true)
        elseif urgent.z - S.pz > 0.8 then eng.input.inject("down", true) end

        if eng.math.dist3(S.px, 0, S.pz, urgent.x, 0, urgent.z) < 5.5 and (f % 35) == 5 then
            eng.input.inject("jump", true)
        end
    end

    if S.heat > 65.0 or (f % 45) == 10 then
        eng.input.inject("interact", true)
    end
    eng.input.inject("fire", (f % 2) == 0)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.vents_used >= 1, "Must trigger coolant vent / core shield pulse")
    eng.test.assert_true(eng, S.kills >= 9, "Must eliminate all 9 flanking sappers across 3 waves")
    eng.test.assert_eq(eng, S.wave, 3, "Must complete final siege wave 3")
    eng.test.assert_true(eng, S.core_hp > 0, "Reactor core must remain intact")
    eng.test.assert_true(eng, S.won == true, "Must win Mech Siege")
    eng.test.assert_true(eng, eng.save.read("mech_siege_clear") ~= nil, "Must record Mech Siege clear score")
end
