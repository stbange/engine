-- Headless playtest for 058_medieval_catapult_command: aims trebuchet & rallies pike/archer shieldwall!
function playtest_frame(f)
    local S = game.state
    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Lead trebuchet reticle slightly ahead of nearest charging cavalry rider
    local target = nil
    local best_z = -999.0
    for i = 1, #S.cavalry do
        local c = S.cavalry[i]
        if c.alive and c.z > best_z then
            best_z = c.z
            target = c
        end
    end

    if target then
        local lead_z = math.min(3.5, target.z + 2.2)
        S.ax = target.x
        S.az = lead_z
        eng.scene.set_pos(S.reticle_ent, S.ax, 0.12, S.az)
    end

    eng.input.inject("interact", (f % 15) == 3)
    eng.input.inject("fire", true)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.shots_fired >= 2, "Commander must wind up and fire siege trebuchet")
    eng.test.assert_true(eng, S.orders >= 2, "Commander must issue pike/archer formation orders")
    eng.test.assert_eq(eng, S.wave, 3, "Must survive through final cavalry wave 3")
    eng.test.assert_true(eng, S.kills >= 9, "Must defeat all charging cavalry riders")
    eng.test.assert_true(eng, S.gate_hp > 0 and S.won == true and S.lost == false, "Castle gate must hold to victory")
    eng.test.assert_eq(eng, eng.save.read("catapult_siege_result"), "repelled", "Save slot must record repelled")
end
