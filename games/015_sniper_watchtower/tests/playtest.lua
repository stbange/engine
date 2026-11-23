-- Automated headless playtest for 015_sniper_watchtower: computes windage + drop lead!
local EYE_X, EYE_Y, EYE_Z = 0.0, 9.6, 15.5
local MUZZLE_VEL = 80.0

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

    if (f % 30) == 1 then
        eng.input.inject("interact", true)
    end

    -- Pick closest hostile infiltrator to the compound gate (largest z)
    local tgt = nil
    local best_z = -999.0
    for i = 1, #S.npcs do
        local npc = S.npcs[i]
        if npc.alive and npc.hostile and npc.z > best_z then
            best_z = npc.z
            tgt = npc
        end
    end
    if not tgt then return end

    -- Solve 3D ballistic lead for gravity drop (-9.81) + crosswind drift (S.wind_ax) + target motion
    local dist = eng.math.dist3(EYE_X, EYE_Y, EYE_Z, tgt.x, 1.0, tgt.z)
    local t = math.max(0.05, (dist - 0.8) / MUZZLE_VEL)
    local aim_x = (tgt.x + tgt.vx * t) - 0.5 * S.wind_ax * t * t
    local aim_y = 1.0 + 0.5 * 9.81 * t * t
    local aim_z = tgt.z + tgt.vz * t

    local vx, vy, vz = aim_x - EYE_X, aim_y - EYE_Y, aim_z - EYE_Z
    local vlen = math.max(0.01, math.sqrt(vx * vx + vy * vy + vz * vz))
    local des_pitch = math.deg(math.asin(eng.math.clamp(vy / vlen, -1.0, 1.0)))
    local des_yaw = math.deg(math.atan2(-vx, -vz))

    local yaw_err = des_yaw - S.yaw
    local pitch_err = des_pitch - S.pitch

    -- Hold breath (jump) when close to aim point for steady precision slew & zero sway
    local close_aim = (math.abs(yaw_err) < 3.5 and math.abs(pitch_err) < 3.5)
    if close_aim then eng.input.inject("jump", true) end

    if yaw_err > 0.35 then eng.input.inject("left", true)
    elseif yaw_err < -0.35 then eng.input.inject("right", true) end

    if pitch_err > 0.35 then eng.input.inject("up", true)
    elseif pitch_err < -0.35 then eng.input.inject("down", true) end

    if math.abs(yaw_err) < 0.75 and math.abs(pitch_err) < 0.75 then
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.spotter_scans >= 1, "Must calibrate windage/spotter via interact")
    eng.test.assert_true(eng, S.shots_fired >= 5, "Must fire bolt-action sniper rounds")
    eng.test.assert_eq(eng, S.friendly_hits, 0, "Must not hit friendly compound sentries")
    eng.test.assert_eq(eng, S.kills, 5, "Must neutralize all 5 procedural infiltrators")
    eng.test.assert_true(eng, S.lost == false, "Compound gate must not fall")
    eng.test.assert_true(eng, S.won == true, "Must win Sniper Watchtower")
    eng.test.assert_true(eng, eng.save.read("sniper_watch_clear") ~= nil, "Must save Sniper Watchtower score")
end
