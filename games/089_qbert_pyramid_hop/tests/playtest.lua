-- Headless playtest for 089_qbert_pyramid_hop: diagonally hops across all 10 pyramid tiles while dodging Coily spheres
local DIRS = {
    { dr = -1, dc = -1, act = "left"  },
    { dr = -1, dc =  0, act = "up"    },
    { dr =  1, dc =  0, act = "down"  },
    { dr =  1, dc =  1, act = "right" }
}

local function valid_rc(r, c)
    return r >= 1 and r <= 4 and c >= 1 and c <= r
end

local function tile_danger(S, r, c)
    for i = 1, #S.spheres do
        local sp = S.spheres[i]
        if (sp.r == r and sp.c == c) or (sp.nr == r and sp.nc == c) then
            return 2
        end
        if not sp.hopping and sp.wait < 0.22 then
            if math.abs(sp.r - r) == 1 and (c == sp.c or c == sp.c + 1 or c == sp.c - 1) then
                return 1
            end
        end
    end
    return 0
end

local function bfs_first_step(S, sr, sc, max_danger)
    local q = { { r = sr, c = sc, first = nil } }
    local seen = { [sr * 10 + sc] = true }
    local head = 1
    while head <= #q do
        local cur = q[head]
        head = head + 1
        if (cur.r ~= sr or cur.c ~= sc) and not S.grid[cur.r][cur.c].gold then
            return cur.first
        end
        for i = 1, #DIRS do
            local d = DIRS[i]
            local nr, nc = cur.r + d.dr, cur.c + d.dc
            local key = nr * 10 + nc
            if valid_rc(nr, nc) and not seen[key] then
                local dng = (cur.first == nil) and tile_danger(S, nr, nc) or 0
                if dng <= max_danger then
                    seen[key] = true
                    q[#q + 1] = { r = nr, c = nc, first = cur.first or d.act }
                end
            end
        end
    end
    return nil
end

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)

    if S.won then
        S.playtest_done = true
        return
    end
    if S.hopping then return end

    -- Try strictly safe path first, then allow adjacent-warning tiles, else pick safest evasion neighbor
    local act = bfs_first_step(S, S.pr, S.pc, 0) or bfs_first_step(S, S.pr, S.pc, 1)
    if not act then
        local best_act, best_score = nil, -999
        for i = 1, #DIRS do
            local d = DIRS[i]
            local nr, nc = S.pr + d.dr, S.pc + d.dc
            if valid_rc(nr, nc) then
                local min_d = 99
                for k = 1, #S.spheres do
                    local sp = S.spheres[k]
                    local dist = math.abs(nr - sp.nr) + math.abs(nc - sp.nc)
                    if dist < min_d then min_d = dist end
                end
                local sc = min_d * 10 - tile_danger(S, nr, nc) * 20 + (S.grid[nr][nc].gold and 0 or 4)
                if sc > best_score then best_score = sc; best_act = d.act end
            end
        end
        act = best_act
    end

    if act then
        eng.input.inject(act, true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.hops_made >= 10, "Q-Hopper must perform diagonal hops up and down the 4-tier pyramid")
    eng.test.assert_eq(eng, S.gold_count, 10, "Every top tile on the 4-tier pyramid must be flipped to gold")
    eng.test.assert_true(eng, S.won == true, "Must win Q-Pyramid Hop")
end
