-- Automated headless playtest for 021_voxel_demolition: plants charges on all 4 columns & collapses tower
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("right", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", false)

    if S.charges_planted < 4 then
        local cur = S.pillars[S.sel_idx]
        if cur and cur.intact and not cur.has_charge then
            eng.input.inject("fire", (f % 4) == 2)
        else
            eng.input.inject("right", (f % 12) == 1)
        end
    elseif S.charges_blown < 4 and f == 60 then
        eng.input.inject("interact", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.charges_planted, 4, "Must plant all 4 demolition charges on structural columns")
    eng.test.assert_eq(eng, S.charges_blown, 4, "All 4 charges must detonate")
    eng.test.assert_true(eng, S.peak_y < S.target_y, "Tower peak must collapse below target laser line")
    eng.test.assert_true(eng, S.won == true, "Demolition mission must complete")
    eng.test.assert_eq(eng, eng.save.read("demolition_progress"), "clear", "Save slot must record clear")
end
