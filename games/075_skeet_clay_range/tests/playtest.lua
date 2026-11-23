-- Headless playtest for 075_skeet_clay_range: leads parabolic clay discs from both houses & shatters 8/8!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    eng.input.inject("fire", false)

    -- Find an airborne clay disc, compute ballistic lead 1 frame ahead, aim & fire shotgun spread!
    for i = 1, #S.clays do
        local c = S.clays[i]
        if c.alive then
            local cx, cy, cz = eng.scene.get_pos(c.ent)
            local vx, vy, vz = eng.physics.get_vel(c.body)
            local dt = 1.0 / 60.0
            S.aim_x = cx + vx * dt
            S.aim_y = cy + vy * dt
            S.aim_z = cz + vz * dt
            if S.cooldown <= 0.001 then
                eng.input.inject("fire", true)
            end
            break
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.left_hits >= 2, "Must shatter clays launched from Left High House")
    eng.test.assert_true(eng, S.right_hits >= 2, "Must shatter clays launched from Right Low House")
    eng.test.assert_true(eng, S.clays_hit >= 8, "Must shatter 8 flying clay targets")
    eng.test.assert_true(eng, S.won == true, "Must clear Skeet Clay Range")
end
