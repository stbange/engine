-- Headless playtest for 080_disc_golf_island: shapes hyzer & anhyzer fade curves around fairway trees into all 3 chain baskets!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    eng.input.inject("fire", false)

    if not S.flying then
        -- Select aerodynamic hyzer/anhyzer line that curves wide around guardian trees into chains!
        local targets = { {0.0, -10.0, -1.40}, {-1.2, -11.0, -1.40}, {1.2, -11.5, 1.40} }
        local tgt = targets[S.hole]
        local bx, bz, hyz = tgt[1], tgt[2], tgt[3]
        local best_yaw, best_err = 0.0, 999.0
        local dt = 1.0 / 60.0
        for k = -18, 18 do
            local yaw = k * 0.8
            local rad = math.rad(yaw)
            local x, y, z = S.dx, S.dy, S.dz
            local vx, vy, vz = -math.sin(rad) * 18.8, 0.28, -math.cos(rad) * 18.8
            local ok = true
            for _ = 1, 68 do
                local hspd = math.sqrt(vx * vx + vz * vz)
                vy = vy + (-9.81 + math.min(9.45, hspd * 0.525)) * dt
                vx = (vx + hyz * ((hspd < 14.0) and 6.2 or 5.2) * dt) * (1.0 - 0.14 * dt)
                vz = vz * (1.0 - 0.14 * dt)
                x, y, z = x + vx * dt, y + vy * dt, z + vz * dt
                for ti = 1, #S.trunks do
                    local tr = S.trunks[ti]
                    if y < 3.6 and eng.math.dist3(x, 0, z, tr.x, 0, tr.z) < tr.r + 0.25 then ok = false; break end
                end
                if not ok or y <= 0.12 then break end
                local d = eng.math.dist3(x, 0, z, bx, 0, bz)
                if y >= 0.55 and y <= 1.75 and d < best_err then best_err = d; best_yaw = yaw end
            end
        end
        S.hyzer = hyz
        S.aim_yaw = best_yaw
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.glide_ticks >= 60, "Aerodynamic frisbee lift must sustain gliding flight")
    eng.test.assert_eq(eng, S.chain_hits, 3, "Must rattle chains on all 3 island baskets")
    eng.test.assert_eq(eng, S.hole, 3, "Must complete final island hole 3")
    eng.test.assert_true(eng, S.won == true, "Must win Disc Golf Island")
    eng.test.assert_eq(eng, eng.save.read("disc_golf_hole"), "clear", "Save must record island clear")
end
