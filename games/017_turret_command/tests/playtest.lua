-- Automated headless playtest for 017_turret_command: predicts meteor trajectories and detonates 3D flak spheres!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", false)

    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    if (f % 45) == 5 then eng.input.inject("interact", true) end
    if (f % 70) == 10 then eng.input.inject("jump", true) end

    -- Target lowest living meteor to protect city biodomes
    local low_m = nil
    local min_y = 999.0
    for i = 1, #S.meteors do
        local m = S.meteors[i]
        if m.alive and m.y < min_y then
            min_y = m.y
            low_m = m
        end
    end
    if not low_m then return end

    -- Predict meteor position ~0.22s ahead for counter-missile flight + flak bloom
    local lead_t = 0.22
    local ix = eng.math.clamp(low_m.x + low_m.vx * lead_t, -14.0, 14.0)
    local iy = eng.math.clamp(low_m.y + low_m.vy * lead_t, 3.2, 15.5)

    if ix - S.rx > 0.45 then eng.input.inject("right", true)
    elseif ix - S.rx < -0.45 then eng.input.inject("left", true) end

    if iy - S.ry > 0.45 then eng.input.inject("up", true)
    elseif iy - S.ry < -0.45 then eng.input.inject("down", true) end

    if math.abs(ix - S.rx) < 1.8 and math.abs(iy - S.ry) < 1.8 then
        eng.input.inject("fire", (f % 8) == 0)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.resupplies >= 1, "Must resupply battery interceptors via interact")
    eng.test.assert_true(eng, S.emps_used >= 1, "Must trigger EMP dome slow pulse via jump")
    eng.test.assert_true(eng, S.intercepts >= 8, "Must vaporize incoming meteors with 3D flak spheres")
    eng.test.assert_eq(eng, S.wave, 3, "Must complete orbital wave 3")
    eng.test.assert_true(eng, S.cities_standing >= 1, "At least 1 biodome city must survive")
    eng.test.assert_true(eng, S.won == true, "Must win Turret Command")
    eng.test.assert_true(eng, eng.save.read("turret_cmd_best") ~= nil, "Must save Turret Command high score")
end
