-- Automated headless playtest for 024_voxel_bomber: chain-detonates crates and defeats both AI bombers
local CELL = 1.4
local function g2w(gx, gz) return (gx - 4) * CELL, (gz - 4) * CELL end

local step_idx = 1

local function has_live_bombs(S)
    for i = 1, #S.bombs do
        if not S.bombs[i].exploded then return true end
    end
    return false
end

local function steer_grid(S, gx, gz)
    local tx, tz = g2w(gx, gz)
    local dx, dz = tx - S.px, tz - S.pz
    if math.abs(dx) > 0.09 then
        eng.input.inject("left", dx < 0)
        eng.input.inject("right", dx > 0)
        eng.input.inject("up", false)
        eng.input.inject("down", false)
        return false
    elseif math.abs(dz) > 0.09 then
        eng.input.inject("left", false)
        eng.input.inject("right", false)
        eng.input.inject("up", dz < 0)
        eng.input.inject("down", dz > 0)
        return false
    end
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    return true
end

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    eng.input.inject("fire", false)

    -- Step 1: Move to (2,1) & plant Bomb #1 to clear crate (3,1)
    if step_idx == 1 then
        if steer_grid(S, 2, 1) then eng.input.inject("fire", true); step_idx = 2 end
    -- Step 2: Retreat around pillar (2,2) via (1,1) -> (1,2)
    elseif step_idx == 2 then
        if steer_grid(S, 1, 1) then step_idx = 3 end
    elseif step_idx == 3 then
        if steer_grid(S, 1, 2) and not has_live_bombs(S) then step_idx = 4 end
    -- Step 4: Advance along row 1 to (4,1), drop Bomb #2, step to (3,1), drop Bomb #3 (chain detonation!)
    elseif step_idx == 4 then
        if steer_grid(S, 1, 1) then step_idx = 5 end
    elseif step_idx == 5 then
        if steer_grid(S, 4, 1) then eng.input.inject("fire", true); step_idx = 6 end
    elseif step_idx == 6 then
        if steer_grid(S, 3, 1) and (f % 2 == 0) then eng.input.inject("fire", true); step_idx = 7 end
    -- Step 7: Retreat via (1,1) -> safe (1,2) while chain blast clears crates (5,1) & (3,3)
    elseif step_idx == 7 then
        if steer_grid(S, 1, 1) then step_idx = 8 end
    elseif step_idx == 8 then
        if steer_grid(S, 1, 2) and not has_live_bombs(S) then step_idx = 9 end
    -- Step 9: Sprint down row 1 -> (7,1) -> (7,4) to sweep col 7 rival AI bombers!
    elseif step_idx == 9 then
        if steer_grid(S, 1, 1) then step_idx = 10 end
    elseif step_idx == 10 then
        if steer_grid(S, 7, 1) then step_idx = 11 end
    elseif step_idx == 11 then
        if steer_grid(S, 7, 4) then eng.input.inject("fire", true); step_idx = 12 end
    -- Step 12: Retreat around corner (7,1) -> safe (5,1)
    elseif step_idx == 12 then
        if steer_grid(S, 7, 1) then step_idx = 13 end
    elseif step_idx == 13 then
        if steer_grid(S, 5, 1) and not has_live_bombs(S) then
            if not S.won then step_idx = 10 end
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.crates_blasted >= 3, "Must blast destructible voxel crates")
    eng.test.assert_true(eng, S.chain_detonations >= 1, "Must trigger at least 1 bomb chain detonation")
    eng.test.assert_eq(eng, S.enemies_defeated, 2, "Must eliminate both rival AI bombers")
    eng.test.assert_eq(eng, S.player_hits, 0, "Player must dodge own bomb blast lanes")
    eng.test.assert_true(eng, S.won == true, "Voxel Bomber arena must clear")
end
