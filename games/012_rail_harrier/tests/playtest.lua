-- Automated headless playtest for 012_rail_harrier
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

    -- Check imminent pillar collision first -> dodge laterally + barrel roll!
    local danger_pillar = nil
    for i = 1, #S.pillars do
        local p = S.pillars[i]
        if p.z > -9.0 and p.z < 0.8 and math.abs(S.px - p.x) < 1.8 then
            danger_pillar = p
            break
        end
    end

    if danger_pillar then
        eng.input.inject("jump", (f % 6) == 1)
        if S.px >= danger_pillar.x then
            eng.input.inject("right", true)
        else
            eng.input.inject("left", true)
        end
    else
        -- Track nearest living squadron fighter and blast it
        local tgt = nil
        local best_z = -999.0
        for i = 1, #S.foes do
            local fn = S.foes[i]
            if fn.alive and fn.z < -2.0 and fn.z > best_z then
                best_z = fn.z
                tgt = fn
            end
        end
        if tgt then
            if tgt.x - S.px > 0.45 then eng.input.inject("right", true)
            elseif tgt.x - S.px < -0.45 then eng.input.inject("left", true) end
            if tgt.y - S.py > 0.45 then eng.input.inject("up", true)
            elseif tgt.y - S.py < -0.45 then eng.input.inject("down", true) end
        end
    end

    eng.input.inject("fire", (f % 2) == 0)
    eng.input.inject("interact", (f % 20) == 1)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.pillars_dodged >= 3, "Must weave past procedural rail pillars")
    eng.test.assert_true(eng, S.kills >= 8, "Must shoot down at least 8 squadron targets")
    eng.test.assert_true(eng, S.dist >= 110.0, "Must advance down the high-speed rail")
    eng.test.assert_true(eng, S.lost == false, "Harrier must not be shot down")
    eng.test.assert_true(eng, S.won == true, "Must clear Rail Harrier")
    eng.test.assert_true(eng, eng.save.read("rail_harrier_clear") ~= nil, "Must save Rail Harrier score")
end
