-- Headless playtest for 083_frogger_highway_vox: crosses 3D trucks & rides voxel logs into all 3 lily alcoves
local function wrap_x(x)
    if x > 16.0 then return x - 32.0 end
    if x < -16.0 then return x + 32.0 end
    return x
end

local function truck_safe_at(S, lane, x)
    for i = 1, #S.trucks do
        local t = S.trucks[i]
        if t.lane == lane then
            local px = wrap_x(t.x + t.vx * 0.14)
            if math.abs(x - t.x) < (t.hw + 0.85) or math.abs(x - px) < (t.hw + 0.85) then
                return false
            end
        end
    end
    return true
end

local function best_log_in_lane(S, lane, ref_x)
    local best, best_d = nil, 999.0
    for i = 1, #S.logs do
        local l = S.logs[i]
        if l.lane == lane and math.abs(l.x) < 13.0 then
            local d = math.abs(l.x - ref_x)
            if d < best_d then best_d = d; best = l end
        end
    end
    return best
end

function playtest_frame(f)
    local S = game.state
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("left", false)
    eng.input.inject("right", false)

    if S.won then
        S.playtest_done = true
        return
    end
    if S.hop_cd > (1.0 / 60.0) + 0.001 then return end

    -- Pick best unfilled lily alcove (preferring alcoves just downstream of current river position on lane 7)
    local goal_x = 0.0
    local best_score = 999.0
    for i = 1, #S.alcoves do
        local a = S.alcoves[i]
        if not a.filled then
            local sc = math.abs(a.x - S.fx)
            if S.lane == 7 and a.x < S.fx - 1.3 then sc = sc + 20.0 end
            if sc < best_score then best_score = sc; goal_x = a.x end
        end
    end

    local next_lane = S.lane + 1

    if next_lane >= 1 and next_lane <= 3 then
        if truck_safe_at(S, next_lane, S.fx) then
            eng.input.inject("up", true)
        elseif truck_safe_at(S, S.lane, S.fx + 1.5) and S.fx < 9.5 and (S.fx < goal_x or not truck_safe_at(S, S.lane, S.fx)) then
            eng.input.inject("right", true)
        elseif truck_safe_at(S, S.lane, S.fx - 1.5) and S.fx > -9.5 then
            eng.input.inject("left", true)
        end
    elseif next_lane == 4 then
        eng.input.inject("up", true)
    elseif next_lane >= 5 and next_lane <= 7 then
        local log = best_log_in_lane(S, next_lane, S.fx)
        if log then
            local pred_x = log.x + log.vx * (1.0 / 60.0)
            if math.abs(S.fx - pred_x) <= (log.hw - 0.30) then
                if not (next_lane == 7 and S.fx > goal_x + 1.2) then
                    eng.input.inject("up", true)
                    return
                end
            end
            if S.lane == 4 then
                -- Walk along safe median directly toward nearest approaching lane-5 log!
                if S.fx < pred_x - 0.4 and S.fx < 9.5 then eng.input.inject("right", true); return
                elseif S.fx > pred_x + 0.4 and S.fx > -9.5 then eng.input.inject("left", true); return end
            else
                local cur_log = nil
                for i = 1, #S.logs do
                    local l = S.logs[i]
                    if l.lane == S.lane and math.abs(S.fx - l.x) <= l.hw + 0.2 then cur_log = l; break end
                end
                if cur_log then
                    local target_on_log = (next_lane == 7 and S.fx > goal_x + 1.0) and (goal_x - 1.0) or pred_x
                    if S.fx < target_on_log - 0.5 and (S.fx + 1.5 - cur_log.x) <= (cur_log.hw - 0.15) then
                        eng.input.inject("right", true)
                    elseif S.fx > target_on_log + 0.5 and (S.fx - 1.5 - cur_log.x) >= -(cur_log.hw - 0.15) then
                        eng.input.inject("left", true)
                    end
                end
            end
        end
    elseif next_lane == 8 then
        for i = 1, #S.alcoves do
            local a = S.alcoves[i]
            if not a.filled and math.abs(S.fx - a.x) <= 1.40 then
                eng.input.inject("up", true)
                return
            end
        end
        -- If swept downstream past goal_x, hop back to leftward Lane 6 log if aligned!
        if S.fx > goal_x + 1.4 then
            local back_log = best_log_in_lane(S, 6, S.fx)
            if back_log and math.abs(S.fx - (back_log.x + back_log.vx * (1.0 / 60.0))) <= (back_log.hw - 0.30) then
                eng.input.inject("down", true)
                return
            end
        end
        local cur_log = nil
        for i = 1, #S.logs do
            local l = S.logs[i]
            if l.lane == 7 and math.abs(S.fx - l.x) <= l.hw + 0.2 then cur_log = l; break end
        end
        if cur_log then
            if S.fx < goal_x - 0.4 and (S.fx + 1.5 - cur_log.x) <= (cur_log.hw - 0.15) then
                eng.input.inject("right", true)
            elseif S.fx > goal_x + 0.4 and (S.fx - 1.5 - cur_log.x) >= -(cur_log.hw - 0.15) then
                eng.input.inject("left", true)
            end
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.logs_ridden >= 3, "Frog must ride floating voxel river logs")
    eng.test.assert_eq(eng, S.alcoves_filled, 3, "All 3 lily alcoves must be filled")
    eng.test.assert_true(eng, S.won == true, "Must win Frogger Highway Vox")
end
