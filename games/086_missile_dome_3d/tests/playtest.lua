-- Headless playtest for 086_missile_dome_3d: leads incoming warheads & detonates flak shockwaves to save all 4 crystal domes!
local claimed = {}

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end

    -- Pick most urgent untargeted warhead descending toward our 4 Crystal Dome Cities!
    local best_w, best_y = nil, 999.0
    for i = 1, #S.warheads do
        local w = S.warheads[i]
        if (claimed[w.id] or 0) < f and w.y < best_y then
            best_y = w.y
            best_w = w
        end
    end
    if not best_w and #S.warheads > 0 then
        best_w = S.warheads[1]
    end
    if not best_w then return end

    -- Two-step iterative ballistic lead for 32 m/s flak shell + shockwave bloom!
    local ix, iy = best_w.x, best_w.y
    for _ = 1, 2 do
        local dx, dy = ix - 0.0, iy - 1.35
        local t_shell = math.sqrt(dx * dx + dy * dy) / 32.0 + 0.14
        ix = eng.math.clamp(best_w.x + best_w.vx * t_shell, -9.2, 9.2)
        iy = eng.math.clamp(best_w.y + best_w.vy * t_shell, 2.4, 11.8)
    end

    local ex, ey = ix - S.rx, iy - S.ry
    if math.abs(ex) > 0.22 then eng.input.inject(ex > 0.0 and "right" or "left", true) end
    if math.abs(ey) > 0.22 then eng.input.inject(ey > 0.0 and "up" or "down", true) end

    if math.sqrt(ex * ex + ey * ey) < 0.85 and S.cooldown <= 0.001 then
        eng.input.inject("fire", true)
        claimed[best_w.id] = f + 34
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.flak_detonated >= 6, "Must detonate flak shockwaves in sky")
    eng.test.assert_true(eng, S.intercepted >= 12, "Flak shockwaves must vaporize incoming warheads")
    eng.test.assert_eq(eng, S.cities_alive, 4, "All 4 crystal dome cities on curved horizon must survive")
    eng.test.assert_eq(eng, S.wave, 3, "Must complete all 3 orbital salvo waves")
    eng.test.assert_true(eng, S.won == true, "Must win Missile Dome 3D")
end
