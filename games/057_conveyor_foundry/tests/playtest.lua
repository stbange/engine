-- Headless playtest for 057_conveyor_foundry: aligns conveyor path & ships 6 steel ingots!
local TARGETS = {
    { gx = 2, gz = 1, dir = 1 }, -- South into (2,2)
    { gx = 2, gz = 2, dir = 0 }, -- East into Smelter (3,2)
    { gx = 4, gz = 2, dir = 1 }, -- South into (4,3)
    { gx = 4, gz = 3, dir = 0 }  -- East into Shipping Crate (5,3)
}

function playtest_frame(f)
    local S = game.state
    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    local pending = nil
    for i = 1, #TARGETS do
        local t = TARGETS[i]
        local c = S.cells[(t.gz - 1) * 5 + t.gx]
        if c.dir ~= t.dir then
            pending = c
            S.sel_gx, S.sel_gz = t.gx, t.gz
            S.cx, S.cz = c.x, c.z
            break
        end
    end

    if pending then
        eng.input.inject("interact", (f % 4) == 1)
        eng.input.inject("fire", false)
    else
        eng.input.inject("interact", false)
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.rotations >= 8, "Player must rotate misaligned 3D conveyor belts")
    eng.test.assert_eq(eng, S.scrap, 0, "Zero wasted scrap when conveyor pipeline is aligned")
    eng.test.assert_true(eng, S.shipped >= 6, "Must smelt and ship 6 steel ingots")
    eng.test.assert_true(eng, S.won == true and S.lost == false, "Must win Conveyor Foundry")
    eng.test.assert_eq(eng, eng.save.read("foundry_status"), "quota_met", "Save slot must record quota_met")
end
