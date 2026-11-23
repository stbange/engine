-- Headless playtest for 053_traffic_director_3d: clears 12 cars with 0 collisions!
function playtest_frame(f)
    local S = game.state
    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    eng.input.inject("jump", true)

    -- Check if central intersection box is completely clear before switching signal phase
    local box_busy = false
    local wait_ns, wait_ew = 0, 0
    for i = 1, #S.cars do
        local c = S.cars[i]
        if c.active then
            if math.abs(c.x - 16.0) < 2.6 and math.abs(c.z - 16.0) < 2.6 then
                box_busy = true
            end
            if c.wait > 0.05 then
                if c.axis == 1 then wait_ns = wait_ns + 1 else wait_ew = wait_ew + 1 end
            end
        end
    end

    local want_toggle = false
    if not box_busy and (f % 16 == 0) then
        if S.phase == "NS" and wait_ew > 0 then want_toggle = true end
        if S.phase == "EW" and wait_ns > 0 then want_toggle = true end
    end
    eng.input.inject("interact", want_toggle)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.wfc_solvable == true, "WFC city block layout must be valid")
    eng.test.assert_true(eng, S.toggles >= 2, "Traffic director must toggle 3D signals across phases")
    eng.test.assert_eq(eng, S.crashes, 0, "Zero vehicle collisions allowed")
    eng.test.assert_true(eng, S.cleared >= 12, "Must safely clear at least 12 vehicles")
    eng.test.assert_true(eng, S.won == true and S.lost == false, "Must win Traffic Director 3D")
    eng.test.assert_eq(eng, eng.save.read("traffic_director_result"), "clear_12", "Save slot must record clear_12")
end
