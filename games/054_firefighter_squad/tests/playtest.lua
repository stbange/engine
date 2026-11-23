-- Headless playtest for 054_firefighter_squad
function playtest_frame(f)
    local S = game.state
    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Steer fire engine toward nearest burning cell and spray water cannon
    local best = nil
    local best_d = 999.0
    for i = 1, #S.grid do
        local c = S.grid[i]
        if c.burning then
            local d = eng.math.dist3(S.px, 0, S.pz, c.x, 0, c.z)
            if d < best_d then best_d = d; best = c end
        end
    end

    if best and best_d > 5.5 then
        eng.input.inject("left", best.x < S.px - 0.5)
        eng.input.inject("right", best.x > S.px + 0.5)
        eng.input.inject("up", best.z < S.pz - 0.5)
        eng.input.inject("down", best.z > S.pz + 0.5)
    else
        eng.input.inject("left", false)
        eng.input.inject("right", false)
        eng.input.inject("up", false)
        eng.input.inject("down", false)
    end

    eng.input.inject("interact", S.water < 35.0 and (f % 8 == 1))
    eng.input.inject("fire", best ~= nil)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.extinguished >= 6, "Firefighter squad must extinguish at least 6 voxel blazes")
    eng.test.assert_true(eng, S.town_hp >= 50.0, "Town buildings must survive with healthy integrity")
    eng.test.assert_true(eng, S.won == true and S.lost == false, "All cellular-automata blazes must be extinguished")
    eng.test.assert_eq(eng, eng.save.read("firefighter_status"), "saved", "Save slot must record town saved")
end
