-- Headless playtest for 052_hex_archipelago
function playtest_frame(f)
    local S = game.state
    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Find an unclaimed hex adjacent to player territory (or an owned hex needing a coastal tower)
    local target = nil
    local need_tower = (S.towers_built < 2 and S.gold >= 14.0)
    if need_tower then
        for i = 1, #S.hexes do
            local h = S.hexes[i]
            if h.owner == 1 and not h.tower then target = h; S.sel_idx = i; break end
        end
    end
    if not target then
        for i = 1, #S.hexes do
            local h = S.hexes[i]
            if h.owner ~= 1 then
                for j = 1, #S.hexes do
                    local o = S.hexes[j]
                    local dq, dr = h.q - o.q, h.r - o.r
                    local ds = (-h.q - h.r) - (-o.q - o.r)
                    if o.owner == 1 and (math.abs(dq) + math.abs(dr) + math.abs(ds)) * 0.5 == 1 then
                        target = h
                        S.sel_idx = i
                        break
                    end
                end
            end
            if target then break end
        end
    end

    if target then
        S.cx, S.cz = target.x, target.z
    end
    eng.input.inject("interact", need_tower and (f % 6 == 2))
    eng.input.inject("fire", (not need_tower) and (f % 4 == 1))
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, #S.hexes == 19, "Hex archipelago must generate 19 procedural axial hexes")
    eng.test.assert_true(eng, S.towers_built >= 1, "Must construct at least 1 coastal watchtower")
    eng.test.assert_true(eng, S.captures >= 10, "Must capture neutral/rival islands across archipelago")
    eng.test.assert_true(eng, S.won == true and S.lost == false, "Must conquer archipelago target")
end
