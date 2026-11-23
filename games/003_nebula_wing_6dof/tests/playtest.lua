-- Automated headless playtest for 003_nebula_wing_6dof: launches from carrier hangar & clears 4 orbital missions
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    if not S.launched then
        -- Throttle + afterburner straight out of the Bigger-on-the-Inside Carrier Hangar portal!
        eng.input.inject("up", true)
        eng.input.inject("jump", true)
        eng.input.inject("fire", false)
    else
        eng.input.inject("up", true)
        eng.input.inject("jump", false)
        eng.input.inject("fire", (f % 3) == 1)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.launched == true, "Starfighter must launch through carrier hangar portal into space")
    eng.test.assert_eq(eng, S.pocket, 0, "Must be in orbital space pocket after launch")
    eng.test.assert_true(eng, S.kills >= 12, "Must destroy all 12 orbital drones across 4 missions")
    eng.test.assert_eq(eng, S.stage, 4, "Must complete final mission 4")
    eng.test.assert_true(eng, S.won == true, "Must win Nebula Wing")
    eng.test.assert_eq(eng, eng.save.read("nebula_wing_progress"), "clear", "Save slot must record clear")
end
