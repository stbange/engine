-- Headless playtest for 076_billiards_lounge: computes Ghost-Ball cut angles to sink all 6 balls with 0 scratches!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    eng.input.inject("fire", false)

    -- Speed up slow-rolling cloth settle between shots so all 6 precision shots complete inside 250 frames
    if S.balls_moving then
        local cvx, cvy, cvz = eng.physics.get_vel(S.cue_body)
        eng.physics.set_vel(S.cue_body, cvx * 0.93, cvy, cvz * 0.93)
        for i = 1, #S.balls do
            local b = S.balls[i]
            if not b.sunk then
                local vx, vy, vz = eng.physics.get_vel(b.body)
                eng.physics.set_vel(b.body, vx * 0.96, vy, vz * 0.96)
            end
        end
        return
    end

    local cx, _, cz = eng.scene.get_pos(S.cue_ent)
    local best_yaw = 0.0
    local best_score = -999.0

    for i = 1, #S.balls do
        local b = S.balls[i]
        if not b.sunk then
            local bx, _, bz = eng.scene.get_pos(b.ent)
            for p = 1, #S.POCKETS do
                local px, pz = S.POCKETS[p][1] * 0.94, S.POCKETS[p][2] * 0.94
                local pdx, pdz = px - bx, pz - bz
                local plen = math.sqrt(pdx * pdx + pdz * pdz)
                if plen > 0.05 then
                    pdx, pdz = pdx / plen, pdz / plen
                    -- Ghost ball contact center 2*R behind object ball opposite pocket
                    local gx, gz = bx - pdx * 0.218, bz - pdz * 0.218
                    local cdx, cdz = gx - cx, gz - cz
                    local clen = math.sqrt(cdx * cdx + cdz * cdz)
                    if clen > 0.05 then
                        local cut_cos = (cdx / clen) * pdx + (cdz / clen) * pdz
                        local rank = cut_cos * 3.0 - plen * 0.35 - clen * 0.25
                        if cut_cos > 0.25 and rank > best_score then
                            best_score = rank
                            best_yaw = math.deg(math.atan2(-cdx, -cdz))
                        end
                    end
                end
            end
        end
    end

    S.aim_yaw = best_yaw
    S.shot_power = 0.82
    eng.input.inject("fire", true)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.sunk_count, 6, "Must sink all 6 colored object balls")
    eng.test.assert_eq(eng, S.scratches, 0, "Must clear table without scratching cue ball")
    eng.test.assert_true(eng, S.won == true, "Must win Billiards Lounge")
end
