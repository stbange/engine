-- Automated headless playtest for 068_pipe_pressure_3d:
-- Rotates 3D elbow and T-junction pipe segments across both boiler cubes before pressure bursts!
local TARGET_ROT = {
    [1] = { 3, 2, 4 },
    [2] = { 3, 2, 3, 4, 3 }
}

function playtest_frame(f)
    local S = game.state
    eng.input.inject("right", false)
    eng.input.inject("fire", false)

    if S.won or S.lost then
        S.playtest_done = true
        return
    end
    if S.stage_connected then return end

    local goals = TARGET_ROT[S.stage]
    local cur = S.rotatable[S.sel_idx]
    if not goals or not cur then return end

    local want = goals[S.sel_idx]
    if cur.rot_idx ~= want then
        eng.input.inject("fire", (f % 2) == 1)
    else
        eng.input.inject("right", (f % 2) == 1)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.rotations >= 12, "Must rotate 3D elbow and T-junction segments")
    eng.test.assert_true(eng, S.turbines_spun >= 4, "Must pressurize all boiler turbines across 2 stages")
    eng.test.assert_true(eng, S.lost == false, "Boiler must not burst from overpressure")
    eng.test.assert_eq(eng, S.stage, 2, "Must reach Boiler Cube 2")
    eng.test.assert_true(eng, S.won == true, "Pipe Pressure 3D must win")
    eng.test.assert_eq(eng, eng.save.read("pipe_pressure_3d"), "clear", "Save slot must record clear")
end
