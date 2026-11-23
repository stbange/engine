-- Automated headless playtest for 029_voxel_snake_3d: slithers across 5 planetoid faces eating apples collision-free
local function cross3(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function sim_step(head, dir, turn)
    local n = head.n
    local d = dir
    if turn == -1 then d = cross3(n, d)
    elseif turn == 1 then d = cross3(d, n) end
    local nc = { head.c[1] + d[1], head.c[2] + d[2], head.c[3] + d[3] }
    local nn = { n[1], n[2], n[3] }
    if math.abs(nc[1]) > 2 or math.abs(nc[2]) > 2 or math.abs(nc[3]) > 2 then
        nc = { head.c[1], head.c[2], head.c[3] }
        nn = { d[1], d[2], d[3] }
    end
    return nc, nn
end

local function is_body(S, nc, nn)
    for i = 1, #S.segs - 1 do
        local sg = S.segs[i]
        if sg.c[1] == nc[1] and sg.c[2] == nc[2] and sg.c[3] == nc[3]
           and sg.n[1] == nn[1] and sg.n[2] == nn[2] and sg.n[3] == nn[3] then
            return true
        end
    end
    return false
end

local last_head_key = ""

function playtest_frame(f)
    local _ = f
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("left", false)
    eng.input.inject("right", false)

    local h = S.segs[1]
    local hkey = string.format("%d_%d_%d_%d_%d_%d", h.c[1], h.c[2], h.c[3], h.n[1], h.n[2], h.n[3])
    if hkey == last_head_key then return end
    last_head_key = hkey

    local ax = S.apple.c[1] + S.apple.n[1] * 0.86
    local ay = S.apple.c[2] + S.apple.n[2] * 0.86
    local az = S.apple.c[3] + S.apple.n[3] * 0.86

    local best_turn = 0
    local best_d = 999.0
    local turns = {0, -1, 1}
    for i = 1, 3 do
        local t = turns[i]
        local nc, nn = sim_step(h, S.dir, t)
        if not is_body(S, nc, nn) then
            local sx, sy, sz = nc[1] + nn[1] * 0.86, nc[2] + nn[2] * 0.86, nc[3] + nn[3] * 0.86
            local dist = eng.math.dist3(sx, sy, sz, ax, ay, az)
            if dist < best_d then
                best_d = dist
                best_turn = t
            end
        end
    end

    if best_turn == -1 then eng.input.inject("left", true)
    elseif best_turn == 1 then eng.input.inject("right", true) end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.apples_eaten, S.target_apples, "Must eat all 5 glowing apples")
    eng.test.assert_true(eng, S.faces_visited >= 4, "Must slither across multiple faces of the voxel planetoid")
    eng.test.assert_eq(eng, S.self_hits, 0, "Must avoid all snake self-collisions")
    eng.test.assert_true(eng, S.won == true, "Voxel Snake 3D must complete")
end
