-- Automated headless playtest for 099_shader_museum_xr
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    if S.pocket ~= S.hall_id then
        -- Walk straight into the bigger-on-the-inside pavilion doorway at (0, 0, -3.6)
        eng.input.inject("left", S.px > 0.1)
        eng.input.inject("right", S.px < -0.1)
        eng.input.inject("up", true)
        eng.input.inject("down", false)
        eng.input.inject("fire", false)
        return
    end

    local tgt = nil
    for i = 1, #S.exhibits do
        if not S.exhibits[i].inspected then
            tgt = S.exhibits[i]
            break
        end
    end

    if tgt then
        eng.input.inject("left", S.px > tgt.x + 0.2)
        eng.input.inject("right", S.px < tgt.x - 0.2)
        eng.input.inject("up", S.pz > tgt.z + 0.2)
        eng.input.inject("down", S.pz < tgt.z - 0.2)
        eng.input.inject("fire", eng.math.dist3(S.px, 0, S.pz, tgt.x, 0, tgt.z) < 2.3)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.entered_gallery == true, "Must enter bigger-on-the-inside museum_hall pocket")
    eng.test.assert_eq(eng, S.inspected_count, 5, "Must inspect all 5 shader & primitive exhibits")
    eng.test.assert_true(eng, S.won == true, "Must complete Shader Museum XR tour")
    eng.test.assert_eq(eng, eng.save.read("shader_museum_tour"), "5_exhibits", "Must persist museum tour completion")
end
