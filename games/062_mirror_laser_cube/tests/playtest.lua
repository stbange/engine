-- Headless playtest for 062_mirror_laser_cube: rotates horizontal & 3D vertical 45-degree mirrors to energize all crystals
local ACTIONS = {
    -- Stage 1: M1: 3->0 (fire), select M2 (right), M2: 0->1 (fire)
    "fire", "right", "fire",
    -- Stage 2: M1: 2->3->0 (fire, fire), select M2 (right), M2: 1->2 (fire), select M3 (right), M3: 1->2->3 (fire, fire)
    "fire", "fire", "right", "fire", "right", "fire", "fire"
}
local idx = 1

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end
    if (f % 6) == 2 and idx <= #ACTIONS then
        eng.input.inject(ACTIONS[idx], true)
        idx = idx + 1
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.raycast_calls >= 10, "Laser trace must use eng.physics.raycast")
    eng.test.assert_true(eng, S.last_bounces >= 3, "Final chamber must bounce across 3 3D mirrors including +Y elevation")
    eng.test.assert_eq(eng, S.stage, 2, "Must reach optical chamber 2")
    eng.test.assert_true(eng, S.won == true, "Must energize all crystal receivers")
    eng.test.assert_eq(eng, eng.save.read("mirror_laser_cube"), "clear", "Save slot must record clear")
end
