-- Automated headless playtest for 035_lunar_lander_3d: 6DoF guidance lands softly on Pad Alpha & Pad Bravo
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local pad = S.pads[math.min(2, S.pads_landed + 1)]
    local dx, dz = pad.x - S.lx, pad.z - S.lz
    local hdist = math.sqrt(dx * dx + dz * dz)

    local want_vx = eng.math.clamp(dx * 1.15, -4.5, 4.5)
    local want_vz = eng.math.clamp(dz * 1.15, -4.5, 4.5)
    local dvx, dvz = want_vx - S.vx, want_vz - S.vz
    local want_roll = eng.math.clamp(dvx * 20.0, -30.0, 30.0)
    local want_pitch = eng.math.clamp(dvz * 20.0, -30.0, 30.0)
    local hspd = math.sqrt(S.vx * S.vx + S.vz * S.vz)
    local alt = S.alt or (S.ly - (pad.y + 0.95))

    if hdist < 1.6 and hspd < 2.0 and alt < 2.0 then
        eng.input.inject("interact", true)
        eng.input.inject("left", false)
        eng.input.inject("right", false)
        eng.input.inject("up", false)
        eng.input.inject("down", false)
    else
        eng.input.inject("interact", false)
        eng.input.inject("right", dvx > 0.25 and S.roll < want_roll)
        eng.input.inject("left", dvx < -0.25 and S.roll > want_roll)
        eng.input.inject("up", dvz < -0.25 and S.pitch > want_pitch)
        eng.input.inject("down", dvz > 0.25 and S.pitch < want_pitch)
    end

    local need_burn
    if hdist > 1.7 then
        need_burn = (alt < 2.6 and S.vy < 0.8) or (S.vy < -2.0)
    else
        need_burn = (S.vy < -1.8)
    end
    eng.input.inject("jump", need_burn)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.pads_landed, 2, "Must softly land on both Lunar Pad Alpha and Pad Bravo")
    eng.test.assert_true(eng, S.fuel > 0.0, "Must complete mission with remaining thruster fuel")
    eng.test.assert_true(eng, S.won == true, "Must win Lunar Lander 3D")
    eng.test.assert_true(eng, eng.save.read("lunar_lander_clear") ~= nil, "Must persist lunar landing score")
end
