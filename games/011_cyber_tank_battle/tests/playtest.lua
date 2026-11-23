-- Automated headless playtest for 011_cyber_tank_battle
local function wrap_deg(a)
    while a > 180.0 do a = a - 360.0 end
    while a < -180.0 do a = a + 360.0 end
    return a
end

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

    -- Ping radar every 18 frames to keep nearest enemy locked
    if (f % 18) == 1 then
        eng.input.inject("interact", true)
    end

    local target = nil
    local best_d = 999.0
    for i = 1, #S.enemies do
        local en = S.enemies[i]
        if en.alive then
            local d = eng.math.dist3(S.px, 0, S.pz, en.x, 0, en.z)
            if d < best_d then best_d = d; target = en end
        end
    end
    if not target then return end

    -- Circle-strafe slightly (+22 deg offset when close) so enemy shells miss while turret locks target!
    local aim_yaw = math.deg(math.atan2(-(target.x - S.px), -(target.z - S.pz)))
    local drive_yaw = (best_d < 18.0) and (aim_yaw + 35.0) or aim_yaw
    local err = wrap_deg(drive_yaw - S.hull_yaw)
    if err > 4.0 then
        eng.input.inject("left", true)
    elseif err < -4.0 then
        eng.input.inject("right", true)
    end

    eng.input.inject("jump", true)
    eng.input.inject("up", true)

    local tur_err = wrap_deg(aim_yaw - (S.hull_yaw + S.turret_rel_yaw))
    if math.abs(tur_err) < 15.0 then
        eng.input.inject("fire", (f % 2) == 0)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.radar_pings >= 1, "Must trigger radar sweep ping via interact")
    eng.test.assert_true(eng, S.shots_fired >= 4, "Must fire ballistic tank shells")
    eng.test.assert_eq(eng, S.kills, 4, "Must destroy all 4 hostile cyber-tanks")
    eng.test.assert_true(eng, S.lost == false, "Player cyber-tank must survive")
    eng.test.assert_true(eng, S.won == true, "Must win Cyber Tank Battle")
    eng.test.assert_true(eng, eng.save.read("cyber_tank_best") ~= nil, "Must persist cyber tank high score")
end
