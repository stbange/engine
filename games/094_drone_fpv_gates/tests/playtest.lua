-- Automated headless playtest for 094_drone_fpv_gates
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("fire", true) -- Full FPV throttle boost
    local g = S.gates[S.next_gate]
    if g then
        eng.input.inject("left", S.px > g.x + 0.15)
        eng.input.inject("right", S.px < g.x - 0.15)
        eng.input.inject("down", S.py > g.y + 0.15)
        eng.input.inject("up", S.py < g.y - 0.15)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.entered_reactor == true, "Must dive through Gate #3 portal into reactor_core pocket")
    eng.test.assert_true(eng, S.exited_reactor == true, "Must exit Reactor Core portal back into outdoor canyon")
    eng.test.assert_eq(eng, S.gates_passed, 7, "Must fly cleanly through all 7 FPV gates")
    eng.test.assert_true(eng, S.won == true, "Must finish Drone FPV Gates")
end
