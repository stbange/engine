-- Headless playtest for 087_tempest_prism_web: slides around 12-lane prism rim & blasts all climbing flippers
local function bolt_covering_flipper(S, fl)
    for i = 1, #S.bolts do
        local b = S.bolts[i]
        if b.lane == fl.lane and b.z >= fl.z - 0.5 then
            local t_hit = (b.z - fl.z) / (38.0 + fl.vz)
            if t_hit < fl.flip_cd - 0.03 then
                return true
            end
        end
    end
    return false
end

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("fire", false)
    eng.input.inject("jump", false)

    if S.won then
        S.playtest_done = true
        return
    end

    -- Pick the highest-Z (closest to rim) living flipper not already covered by an in-flight bolt
    local best, best_score = nil, -999.0
    for i = 1, #S.flippers do
        local fl = S.flippers[i]
        if fl.alive and not bolt_covering_flipper(S, fl) then
            local diff = ((fl.lane - S.lane + 6) % 12) - 6
            local sc = fl.z * 2.5 - math.abs(diff) * 0.6
            if sc > best_score then
                best_score = sc
                best = fl
            end
        end
    end

    if not best then
        for i = 1, #S.flippers do
            if S.flippers[i].alive then best = S.flippers[i]; break end
        end
    end
    if not best then return end

    local target_lane = best.lane
    -- Predict imminent lane flip if flipper will flip before we reach or hit it
    if best.flip_cd < 0.08 and best.z < -0.2 then
        target_lane = (best.lane + best.dir) % 12
    end

    local diff_f = ((target_lane - S.lane_f + 6.0) % 12.0) - 6.0
    if diff_f > 0.22 then
        eng.input.inject("right", true)
    elseif diff_f < -0.22 then
        eng.input.inject("left", true)
    end

    if S.lane == target_lane and (f % 2 == 1) then
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.unique_lanes >= 4, "Claw blaster must slide across multiple lanes around the 12-lane prism rim")
    eng.test.assert_true(eng, S.flippers_destroyed >= 14, "Must destroy all 14 climbing flippers across 2 prism waves")
    eng.test.assert_eq(eng, S.wave, 2, "Must complete final prism wave 2")
    eng.test.assert_true(eng, S.won == true, "Must win Tempest Prism Web")
end
