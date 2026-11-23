-- Headless playtest for 071_mini_golf_peaks: sinks all 3 holes including banked bounce & portal island putt!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    eng.input.inject("fire", false)
    if not S.moving then
        if S.hole == 1 then
            S.aim_yaw = 0.0
            S.power = 0.72
            eng.input.inject("fire", true)
        elseif S.hole == 2 then
            -- Wait until windmill blade is horizontal (open tunnel) before stroking
            if math.abs(math.cos(math.rad(S.windmill_deg))) < 0.35 then
                S.aim_yaw = 0.0
                S.power = 0.68
                eng.input.inject("fire", true)
            end
        elseif S.hole == 3 then
            S.aim_yaw = 0.0
            S.power = 0.90
            eng.input.inject("fire", true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.bank_bounces >= 1, "Hole 1 putt must bounce off 45-degree banked bumper")
    eng.test.assert_true(eng, S.portal_putts >= 1, "Hole 3 putt must warp across portal onto floating island green")
    eng.test.assert_eq(eng, S.hole, 3, "Must complete final hole 3")
    eng.test.assert_true(eng, S.won == true, "Course must be cleared")
    eng.test.assert_eq(eng, eng.save.read("minigolf_hole"), "clear", "Save slot must record clear")
end
