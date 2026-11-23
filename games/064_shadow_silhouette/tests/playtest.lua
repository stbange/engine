-- Headless playtest for 064_shadow_silhouette: rotates all 3 compound 3D sculptures into spotlight alignment
function playtest_frame(f)
    (void_f_noop or function() end)(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)

    if S.won then
        S.playtest_done = true
        return
    end

    if S.ry > 1.2 then eng.input.inject("left", true)
    elseif S.ry < -1.2 then eng.input.inject("right", true) end

    if S.rx > 1.2 then eng.input.inject("down", true)
    elseif S.rx < -1.2 then eng.input.inject("up", true) end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.locked_stages, 3, "Must lock all 3 spotlight shadow silhouettes")
    eng.test.assert_true(eng, S.alignment >= 0.93, "Final silhouette match must exceed 93%")
    eng.test.assert_true(eng, S.won == true, "Must win all 3 gallery stages")
    eng.test.assert_eq(eng, eng.save.read("shadow_silhouette"), "clear", "Save slot must record clear")
end
