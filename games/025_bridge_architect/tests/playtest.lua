-- Automated headless playtest for 025_bridge_architect: builds all 6 voxel truss spans & drives cargo truck across
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("right", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", false)

    if S.mode == "build" then
        if not S.spans[S.sel_slot] then
            eng.input.inject("fire", (f % 4) == 1)
        elseif S.sel_slot < 6 then
            eng.input.inject("right", (f % 10) == 2)
        else
            eng.input.inject("interact", (f % 6) == 0)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.spans_placed, 6, "Must place all 6 structural voxel bridge spans")
    eng.test.assert_true(eng, S.max_stress_pct > 50.0, "Bridge spans must bear heavy cargo truck load")
    eng.test.assert_true(eng, S.truck_x >= 6.2, "Cargo truck must cross canyon onto East Cliff")
    eng.test.assert_true(eng, S.won == true, "Bridge test must succeed")
end
