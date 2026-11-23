-- Automated headless playtest for 033_biplane_barnstormer: banks & pitches through all 5 sky rings & barn arches
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("fire", true)

    local tgt = S.gates[#S.gates]
    for i = 1, #S.gates do
        if not S.gates[i].cleared then
            tgt = S.gates[i]
            break
        end
    end

    local dx, dy, dz = tgt.x - S.px, tgt.y - S.py, tgt.z - S.pz
    local horiz = math.max(0.1, math.sqrt(dx * dx + dz * dz))
    local want_yaw = math.deg(math.atan2(-dx, -dz))
    local want_pitch = eng.math.clamp(math.deg(math.atan2(dy, horiz)) * 1.35, -32.0, 32.0)

    local dyaw = want_yaw - S.yaw
    while dyaw > 180.0 do dyaw = dyaw - 360.0 end
    while dyaw < -180.0 do dyaw = dyaw + 360.0 end

    -- Bank roll proportional to heading error (yaw_rate = +sin(roll)*76, roll_in -> -roll)
    local want_roll = eng.math.clamp(dyaw * 2.2, -48.0, 48.0)
    eng.input.inject("left", S.roll < want_roll - 2.5)
    eng.input.inject("right", S.roll > want_roll + 2.5)
    eng.input.inject("up", S.pitch < want_pitch - 1.8)
    eng.input.inject("down", S.pitch > want_pitch + 1.8)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.cleared, 5, "Must fly through all 5 sky rings and barn arches")
    eng.test.assert_eq(eng, S.barnstorms, 2, "Must barnstorm through both island barns")
    eng.test.assert_true(eng, S.won == true, "Must complete Biplane Barnstormer circuit")
    eng.test.assert_true(eng, eng.save.read("barnstormer_clear") ~= nil, "Must save barnstormer score")
end
