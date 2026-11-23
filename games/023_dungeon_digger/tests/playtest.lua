-- Automated headless playtest for 023_dungeon_digger: mines gold seams, hires imps, claims all 3 shrines
local TARGET_CELLS = {
    {3, 5}, -- gold vein unlocking Shrine 1 at (2, 5)
    {7, 5}, -- gold vein unlocking Shrine 2 at (8, 5)
    {5, 3}, -- gold vein unlocking Shrine 3 at (5, 2)
    {3, 4}  -- bonus gold vein
}

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", false)

    -- Hire extra procedural imps whenever gold >= 60
    if S.gold >= 60 and #S.imps < 3 and (f % 6 == 0) then
        eng.input.inject("interact", true)
        return
    end

    -- Move cursor to next untagged seam toward shrines and tag it
    for i = 1, #TARGET_CELLS do
        local tx, tz = TARGET_CELLS[i][1], TARGET_CELLS[i][2]
        local blk = S.cells[tz][tx]
        if blk and not blk.tagged then
            if S.cx ~= tx then
                eng.input.inject(tx > S.cx and "right" or "left", (f % 8) == 1)
            elseif S.cz ~= tz then
                eng.input.inject(tz < S.cz and "up" or "down", (f % 8) == 1)
            else
                eng.input.inject("fire", true)
            end
            break
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, #S.imps >= 2, "Must hire at least 1 additional procedural imp")
    eng.test.assert_true(eng, S.blocks_mined >= 3, "Imps must excavate gold-vein voxel blocks")
    eng.test.assert_eq(eng, S.shrines_claimed, 3, "Must claim all 3 subterranean shrines")
    eng.test.assert_true(eng, S.won == true, "Keeper campaign must win")
end
