-- Headless playtest for 018_hover_assault:
-- Boosts over turbo pad, launches off jump-ramp, fires lateral drift jets, and blasts all 6 enemy hover-skimmers!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", false)
    eng.input.inject("fire", true)

    if S.won then
        S.playtest_done = true
        return
    end

    -- Thrust forward across boost pad (z=2.0) and jump-ramp (z=-3.0), then hold firing line
    if S.pz > -3.5 then
        eng.input.inject("up", true)
    elseif S.pz < -6.5 then
        eng.input.inject("down", true)
    end

    if f == 35 then
        eng.input.inject("jump", true) -- Trigger lateral drift jets
    end

    -- Steer nose toward nearest living enemy hover-skimmer
    local tgt = nil
    for i = 1, #S.enemies do
        if S.enemies[i].alive then tgt = S.enemies[i]; break end
    end
    if tgt then
        local want_yaw = math.deg(math.atan2(-(tgt.x - S.px), -(tgt.z - S.pz)))
        local diff = ((want_yaw - S.yaw + 180.0) % 360.0) - 180.0
        if diff > 4.0 then eng.input.inject("left", true)
        elseif diff < -4.0 then eng.input.inject("right", true) end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.boosts_used >= 1, "Hovercraft must trigger at least 1 turbo boost pad")
    eng.test.assert_true(eng, S.ramps_launched >= 1, "Hovercraft must launch off at least 1 sloped jump-ramp")
    eng.test.assert_true(eng, S.drifts_used >= 1, "Hovercraft must fire lateral drift jets")
    eng.test.assert_eq(eng, S.kills, 6, "Twin plasma cannons must destroy all 6 enemy hover-skimmers")
    eng.test.assert_true(eng, S.won == true, "Must conquer both hover assault waves")
    eng.test.assert_eq(eng, eng.save.read("hover_assault"), "clear", "Save slot must record clear")
end
