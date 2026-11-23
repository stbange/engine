-- Headless playtest for 061_sokoban_ruins_3d: solves both multi-elevation ruin stages via input injection
local SCRIPT = {
    -- Stage 1: push Crate 1 up ramp (4,4)->(4,3)->(4,2), then push Crate 2 onto (2,5)
    "up", "up", "up", "down", "down", "left",
    -- Stage 2: push Crate 1 up ramp, climb east ramp, drop Crate 3 off 1m cliff, push Crate 2 onto terrace glyph
    "up", "up", "down", "down", "right", "right", "right", "right",
    "up", "up", "up", "left", "left", "down", "right"
}
local step_idx = 1

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)

    if S.won then
        S.playtest_done = true
        return
    end
    if (f % 8) == 2 and step_idx <= #SCRIPT then
        eng.input.inject(SCRIPT[step_idx], true)
        step_idx = step_idx + 1
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.ramp_pushes >= 2, "Must push crates up elevated 3D stone ramps")
    eng.test.assert_true(eng, S.ledge_drops >= 1, "Must push crate off 3D terrace ledge onto sunken glyph")
    eng.test.assert_eq(eng, S.stage, 2, "Must reach stage 2")
    eng.test.assert_true(eng, S.won == true, "Must awaken all glyph switches in both ruin stages")
    eng.test.assert_eq(eng, eng.save.read("sokoban_ruins_3d"), "clear", "Save slot must record clear")
end
