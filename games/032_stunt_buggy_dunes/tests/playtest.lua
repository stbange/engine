-- Automated headless playtest for 032_stunt_buggy_dunes: launches off desert ramps, lands backflips & grabs sky rings
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("up", true)

    -- Aim toward next unhit ramp/ring along the desert corridor
    local tx, tz = 0.0, -45.0
    for i = 1, #S.rings do
        if not S.rings[i].hit then
            tx, tz = S.ramps[i].x, S.ramps[i].z
            if S.bz < S.ramps[i].z + 0.5 then
                tx, tz = S.rings[i].x, S.rings[i].z
            end
            break
        end
    end

    local want_yaw = math.deg(math.atan2(-(tx - S.bx), -(tz - S.bz)))
    local dyaw = want_yaw - S.yaw
    while dyaw > 180.0 do dyaw = dyaw - 360.0 end
    while dyaw < -180.0 do dyaw = dyaw + 360.0 end

    eng.input.inject("left", dyaw > 3.0)
    eng.input.inject("right", dyaw < -3.0)
    -- Hold jump in midair until one full 360 backflip is rotated
    eng.input.inject("jump", (not S.grounded) and (S.flip_deg < 355.0))
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.dune_samples >= 40, "Must generate procedural Perlin noise desert dunes")
    eng.test.assert_true(eng, S.rings_hit >= 2, "Must collect at least 2 elevated sky stunt rings")
    eng.test.assert_true(eng, S.flips_landed >= 2, "Must land at least 2 midair buggy flips")
    eng.test.assert_true(eng, S.won == true, "Must win Stunt Buggy Dunes")
end
