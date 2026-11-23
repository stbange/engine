-- Automated headless playtest for 022_magma_riser: climbs all 8 spiral voxel ledges ahead of rising magma
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local target_idx = math.min(#S.ledges, (S.current_ledge or 1) + 1)
    local tgt = S.ledges[target_idx]
    local dx = tgt.x - S.px
    local dz = tgt.z - S.pz

    eng.input.inject("left", dx < -0.10)
    eng.input.inject("right", dx > 0.10)
    eng.input.inject("up", dz < -0.10)
    eng.input.inject("down", dz > 0.10)
    eng.input.inject("jump", S.grounded and (f % 2 == 1))
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.cave_solvable == true, "Procedural cave must be valid")
    eng.test.assert_true(eng, S.max_alt >= 10.2, "Must climb above 10.2m to summit ledge")
    eng.test.assert_true(eng, S.gems_collected >= 1, "Must collect at least 1 cave crystal")
    eng.test.assert_eq(eng, S.burns, 0, "Must outrun rising magma without getting burned")
    eng.test.assert_true(eng, S.won == true, "Must reach summit extraction crystal")
end
