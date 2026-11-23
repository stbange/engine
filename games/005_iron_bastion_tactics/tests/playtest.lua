-- Automated headless playtest for 005_iron_bastion_tactics: maneuvers via A* grid & eliminates hostile mechs across 3 missions
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Aim tactical cursor toward nearest living enemy mech, advance once via A*, then fire rail-cannon!
    for i = 1, #S.enemies do
        if S.enemies[i].alive then
            S.cursor_gx = S.enemies[i].gx
            S.cursor_gz = S.enemies[i].gz
            break
        end
    end

    eng.input.inject("jump", (f % 6) == 2)
    eng.input.inject("fire", (f % 6) == 4)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.paths_computed >= 3, "Tactical A* NavGrid must compute movement paths around voxel cover")
    eng.test.assert_true(eng, S.kills >= 7, "Must eliminate all 7 hostile bipedal mechs across 3 missions")
    eng.test.assert_true(eng, S.turns >= 2, "Turn-based command & enemy phases must execute")
    eng.test.assert_eq(eng, S.stage, 3, "Must complete final mission 3")
    eng.test.assert_true(eng, S.won == true, "Must win Iron Bastion Tactics")
    eng.test.assert_eq(eng, eng.save.read("iron_bastion_progress"), "clear", "Save slot must record clear")
end
