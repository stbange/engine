-- Headless playtest for 088_elevator_heist_3d: steals all 3 dossiers, rides 3D elevators, evades agents & escapes!
local FLOOR_H = 3.2

local function move_horizontal_with_shaft_jumps(S, goal_x)
    local dx = goal_x - S.px
    local dir = (dx > 0) and 1 or -1
    if dir > 0 then eng.input.inject("right", true) else eng.input.inject("left", true) end

    -- Jump cleanly over an open elevator shaft if its cab is not bridged at our floor
    local cur_f = math.floor(S.py / FLOOR_H + 0.5)
    if cur_f >= 1 and S.grounded then
        for ci = 1, #S.cabs do
            local c = S.cabs[ci]
            local has_hole = (ci == 1) or (cur_f <= 3)
            if has_hole and math.abs(c.y - cur_f * FLOOR_H) > 0.35 then
                local dist_to_shaft = (c.x - S.px) * dir
                if dist_to_shaft > 0.75 and dist_to_shaft < 1.85 then
                    eng.input.inject("jump", true)
                end
            end
        end
    end
end

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end

    -- Stun or leap over any un-stunned patrolling agent ahead on our floor
    for i = 1, #S.agents do
        local ag = S.agents[i]
        if ag.stun_t <= 0.0 and math.abs(ag.y - S.py) < 0.9 then
            local ahead = (ag.x - S.px) * S.facing
            if ahead > 0.0 and ahead < 5.5 and (f % 3 == 1) then
                eng.input.inject("fire", true)
            elseif math.abs(ag.x - S.px) < 1.5 and S.grounded then
                eng.input.inject("jump", true)
            end
        end
    end

    -- Determine next heist objective: Door 1 (F4) -> Door 2 (F3) -> Door 3 (F1) -> Basement Car (F0)
    local goal_x, goal_f = 8.0, 0
    for i = 1, #S.doors do
        if not S.doors[i].taken then
            goal_x = S.doors[i].x
            goal_f = math.floor(S.doors[i].y / FLOOR_H + 0.5)
            break
        end
    end

    local goal_y = goal_f * FLOOR_H
    local cur_f = math.floor(S.py / FLOOR_H + 0.5)

    -- Same floor as target: sprint across corridor (jumping open shafts)
    if math.abs(S.py - goal_y) < 0.35 then
        move_horizontal_with_shaft_jumps(S, goal_x)
        return
    end

    -- Need to change floors: pick Shaft 1 (F1..F4) when on F4, else Shaft 2 (F0..F3)
    local use_cab = (cur_f == 4) and S.cabs[1] or S.cabs[2]
    if math.abs(S.px - use_cab.x) <= 0.65 and math.abs(S.py - use_cab.y) <= 0.42 then
        if goal_y < S.py - 0.15 then
            eng.input.inject("down", true)
        elseif goal_y > S.py + 0.15 then
            eng.input.inject("up", true)
        end
    elseif math.abs(S.px - use_cab.x) > 0.55 then
        -- Stop just outside shaft lip if cab is still arriving
        if math.abs(use_cab.y - S.py) > 0.40 and math.abs(S.px - use_cab.x) < 1.55 then
            return
        end
        move_horizontal_with_shaft_jumps(S, use_cab.x)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.elevator_rides >= 10, "Spy must ride 3D elevators between tower floors")
    eng.test.assert_true(eng, S.agents_evaded >= 1, "Spy must evade or stun patrolling procgen.person agents")
    eng.test.assert_eq(eng, S.dossiers, 3, "Must grab all 3 secret dossiers from red doors")
    eng.test.assert_true(eng, S.escaped == true and S.won == true, "Must escape in the basement getaway car")
end
