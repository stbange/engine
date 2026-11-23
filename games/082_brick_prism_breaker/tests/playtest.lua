-- Headless playtest for 082_brick_prism_breaker: tracks spheres, imparts Curveball spin, shatters all 18 prisms
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Prioritize nearest incoming ball (vz > 0), otherwise aim paddle toward remaining brick column
    local target_b = nil
    local best_z = -999.0
    for i = 1, #S.balls do
        local b = S.balls[i]
        if b.vz > 0.0 and b.z > best_z then
            best_z = b.z
            target_b = b
        end
    end

    local aim_x, aim_y, aim_z = 0.0, 0.0, -12.0
    for i = 1, #S.bricks do
        if S.bricks[i].alive then
            aim_x, aim_y, aim_z = S.bricks[i].x, S.bricks[i].y, S.bricks[i].z
            break
        end
    end

    local tx, ty = aim_x, aim_y
    if target_b then
        -- Predict where incoming ball will arrive at paddle plane Z = -2.5
        local t_arr = math.max(0.0, (-2.5 - target_b.z) / math.max(1.0, target_b.vz))
        local arr_x = target_b.x + target_b.vx * t_arr + 0.5 * target_b.sx * t_arr * t_arr
        local arr_y = target_b.y + target_b.vy * t_arr + 0.5 * target_b.sy * t_arr * t_arr
        if arr_x > 4.98 then arr_x = 9.96 - arr_x elseif arr_x < -4.98 then arr_x = -9.96 - arr_x end
        if arr_y > 2.98 then arr_y = 5.96 - arr_y elseif arr_y < -2.98 then arr_y = -5.96 - arr_y end

        local dt_z = (-2.5 - aim_z) / 23.0
        local want_vx = (aim_x - arr_x) / dt_z
        local want_vy = (aim_y - arr_y) / dt_z
        local jit = ((S.paddle_hits % 3) - 1) * 0.12
        local ox = eng.math.clamp(-want_vx / 7.5 + jit, -1.35, 1.35)
        local oy = eng.math.clamp(-want_vy / 6.5, -0.95, 0.95)
        tx = eng.math.clamp(arr_x + ox, -4.0, 4.0)
        ty = eng.math.clamp(arr_y + oy, -2.4, 2.4)
    else
        tx = math.sin(f * 0.18) * 1.8
    end

    eng.input.inject("left", S.px > tx + 0.12)
    eng.input.inject("right", S.px < tx - 0.12)
    eng.input.inject("down", S.py > ty + 0.12)
    eng.input.inject("up", S.py < ty - 0.12)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.paddle_hits >= 2, "Paddle must rebound incoming energy spheres")
    eng.test.assert_true(eng, S.spin_bounces >= 1, "Paddle motion must impart Curveball spin")
    eng.test.assert_eq(eng, S.bricks_broken, S.total_bricks, "All 18 layered prism bricks must shatter")
    eng.test.assert_true(eng, S.won == true, "Prism corridor must be cleared")
end
