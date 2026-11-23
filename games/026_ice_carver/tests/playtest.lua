-- Automated headless playtest for 026_ice_carver: chisels excess ice voxels to match target blueprint >=90%
local function find_next_excess(S)
    for y = 4, 2, -1 do
        for z = 1, 4 do
            for x = 1, 4 do
                if S.blueprint[y][z][x] == 0 and S.ice[y][z][x] ~= nil then
                    return x, y, z
                end
            end
        end
    end
    return nil, nil, nil
end

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("right", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", false)
    eng.input.inject("fire", false)

    if (f % 2) == 0 then return end

    local tx, ty, tz = find_next_excess(S)
    if not tx then return end

    if S.cy ~= ty then
        eng.input.inject("jump", true)
    elseif S.cz ~= tz then
        eng.input.inject("down", true)
    elseif S.cx ~= tx then
        eng.input.inject("right", true)
    else
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.chiseled_count >= 26, "Must chisel away excess ice blocks")
    eng.test.assert_true(eng, S.accuracy >= 0.90, "Sculpture blueprint accuracy must reach >= 90%")
    eng.test.assert_true(eng, S.won == true, "Ice carving challenge must succeed")
end
