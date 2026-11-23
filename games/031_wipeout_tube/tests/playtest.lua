-- Automated headless playtest for 031_wipeout_tube: banks onto speed pads, triggers hyperboost, finishes 2 laps
local TWO_PI = math.pi * 2.0

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("up", true)
    eng.input.inject("fire", (f % 32 == 8) and S.shield >= 45.0)

    -- Look ahead for nearest upcoming speed pad and steer into its lane while avoiding mines
    local cur_th = S.theta % TWO_PI
    local target_lat = 0.0
    local best_dth = 99.0
    for i = 1, #S.pads do
        local dth = (S.pads[i].th - cur_th) % TWO_PI
        if dth > 0.02 and dth < best_dth then
            best_dth = dth
            target_lat = S.pads[i].lat
        end
    end
    for i = 1, #S.mines do
        local m = S.mines[i]
        if m.active then
            local dth = (m.th - cur_th) % TWO_PI
            if dth < 0.32 and math.abs(S.lat - m.lat) < 1.5 then
                target_lat = -m.lat
            end
        end
    end

    local diff = target_lat - S.lat
    eng.input.inject("left", diff < -0.22)
    eng.input.inject("right", diff > 0.22)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.pads_hit >= 2, "AG craft must hit at least 2 speed pads")
    eng.test.assert_true(eng, S.shield > 0.0, "Shield energy must stay positive")
    eng.test.assert_true(eng, S.laps >= 2 and S.won == true, "Must finish 2 full neon tube laps")
    eng.test.assert_true(eng, eng.save.read("wipeout_best") ~= nil, "Must persist best Wipeout score")
end
