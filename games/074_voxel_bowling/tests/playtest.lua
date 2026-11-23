-- Headless playtest for 074_voxel_bowling: bowls hooked pocket strikes/spares across all 3 frames!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    eng.input.inject("fire", false)
    if not S.rolling and (f % 3 == 1) then
        S.stance_x = 0.80
        S.hook_spin = -3.1
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.hook_applied >= 5, "Hook spin must curve ball on dry backend")
    eng.test.assert_true(eng, S.total_knocked >= 15, "Must knock down at least 15 physics bowling pins across frames")
    eng.test.assert_eq(eng, S.frame, 3, "Must complete all 3 frames")
    eng.test.assert_true(eng, S.won == true, "Must finish Voxel Bowling game")
end
