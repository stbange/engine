-- Automated headless playtest for 091_rhythm_saber_xr
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Find nearest oncoming active beat cube (highest z)
    local best = nil
    for i = 1, #S.cubes do
        local c = S.cubes[i]
        if c.active and (not best or c.z > best.z) then
            best = c
        end
    end

    if best then
        local target_sx = (best.kind == 1) and (best.x + 0.14) or (best.x - 0.14)
        eng.input.inject("left", S.sx > target_sx + 0.08)
        eng.input.inject("right", S.sx < target_sx - 0.08)
        eng.input.inject("down", S.sy > best.y + 0.08)
        eng.input.inject("up", S.sy < best.y - 0.08)
        eng.input.inject("fire", best.z > -2.3)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.slashed >= 10, "Must slash at least 10 oncoming beat cubes")
    eng.test.assert_true(eng, S.max_combo >= 8, "Must achieve a combo streak of at least 8")
    eng.test.assert_true(eng, S.notes_played >= 10, "Must trigger synthesized melody notes on slash")
    eng.test.assert_true(eng, S.won == true, "Must win Rhythm Saber XR")
    eng.test.assert_true(eng, eng.save.read("rhythm_saber_best") ~= nil, "Must persist high score")
end
