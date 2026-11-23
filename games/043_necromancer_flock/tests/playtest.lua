-- Automated headless playtest for 043_necromancer_flock: summons skeletal flock to convert all 3 shrines!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Continuously summon skeletal minions whenever mana allows
    eng.input.inject("fire", (f % 4) == 1)

    -- Escort the flock toward the next unconverted shrine
    for i = 1, #S.shrines do
        local sh = S.shrines[i]
        if not sh.converted then
            eng.input.inject("left", sh.x < S.px - 0.5)
            eng.input.inject("right", sh.x > S.px + 0.5)
            eng.input.inject("up", sh.z < S.pz - 0.5)
            eng.input.inject("down", sh.z > S.pz + 0.5)
            break
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.summoned_total >= 5, "Must summon a flock of skeletal minions")
    eng.test.assert_eq(eng, S.paladins_slain, 3, "Swarm must defeat all 3 enemy paladins")
    eng.test.assert_eq(eng, S.shrines_converted, 3, "Swarm must convert all 3 holy shrines")
    eng.test.assert_true(eng, S.won == true, "Necromancer must win")
end
