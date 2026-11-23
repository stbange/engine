-- Automated headless playtest for 037_forklift_warehouse: hoists all 3 crate.obj pallets into the pocket delivery truck
local function steer_toward(S, tx, tz)
    local dx, dz = tx - S.fx, tz - S.fz
    eng.input.inject("right", dx > 0.18)
    eng.input.inject("left", dx < -0.18)
    eng.input.inject("up", dz < -0.18)
    eng.input.inject("down", dz > 0.18)
end

function playtest_frame(f)
    local _ = f
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    if S.pocket == 0 then
        if S.carrying == nil then
            -- Drive to next uncollected yard pallet
            for i = 1, #S.pallets do
                if S.pallets[i].state == "yard" then
                    steer_toward(S, S.pallets[i].x, S.pallets[i].z)
                    return
                end
            end
        else
            -- Align with rear truck ramp at x = 0, then drive across portal at z = -3.4
            if math.abs(S.fx) > 0.45 and S.fz > -2.4 then
                steer_toward(S, 0.0, -2.0)
            else
                steer_toward(S, 0.0, -4.1)
            end
        end
    else
        if S.carrying ~= nil then
            -- Drive to next open cargo bay slot inside 20x24m truck pocket
            for i = 1, #S.slots do
                if not S.slots[i].filled then
                    steer_toward(S, S.slots[i].x, S.slots[i].z)
                    return
                end
            end
        else
            -- Align with interior exit hatch at x = 0, then drive out portal at z = 11.8
            if math.abs(S.fx) > 0.45 and S.fz < 10.6 then
                steer_toward(S, 0.0, 10.2)
            else
                steer_toward(S, 0.0, 12.4)
            end
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.delivered, 3, "Must stow all 3 crate.obj pallets inside the pocket delivery truck")
    eng.test.assert_true(eng, S.portal_crossings >= 5, "Must traverse rear ramp portal back and forth")
    eng.test.assert_true(eng, S.won == true, "Must complete warehouse manifest")
    eng.test.assert_true(eng, eng.save.read("forklift_warehouse_clear") ~= nil, "Must save warehouse score")
end
