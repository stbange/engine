-- Automated headless playtest for 098_creature_zoo_lab
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local tgt = nil
    for i = 1, #S.creatures do
        if not S.creatures[i].cataloged then
            tgt = S.creatures[i]
            break
        end
    end

    if tgt then
        eng.input.inject("left", S.px > tgt.x + 0.2)
        eng.input.inject("right", S.px < tgt.x - 0.2)
        eng.input.inject("up", S.pz > tgt.z + 0.2)
        eng.input.inject("down", S.pz < tgt.z - 0.2)
        eng.input.inject("fire", eng.math.dist3(S.px, 0, S.pz, tgt.x, 0, tgt.z) < 2.2)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.planet_mesh > 0, "Must generate live 3D procgen.planet globe")
    eng.test.assert_eq(eng, S.archetypes_spawned, 6, "Must spawn all 6 DNA animal archetypes")
    eng.test.assert_true(eng, S.keepers_spawned >= 2, "Must spawn procedural zoo keepers")
    eng.test.assert_true(eng, S.cataloged_count >= 5, "Must catalog at least 5 procedural species")
    eng.test.assert_true(eng, S.won == true, "Must complete Safari DNA Research")
end
