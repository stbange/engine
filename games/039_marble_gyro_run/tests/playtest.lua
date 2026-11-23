-- Automated headless playtest for 039_marble_gyro_run: tilts gravity to guide dynamic sphere across S-catwalk to goal cup
function playtest_frame(f)
    local _ = f
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local mx, _, mz = eng.scene.get_pos(S.marble_ent)
    local vx, _, vz = eng.physics.get_vel(S.marble_body)

    -- Follow the 3 catwalk waypoints: Corner 1 (-4.0, -3.5) -> Corner 2 (4.0, -3.5) -> Goal Cup (4.0, -11.0)
    local tx, tz = S.goal_x, S.goal_z
    if not S.gems[1].collected then
        tx, tz = S.gems[1].x, S.gems[1].z
    elseif not S.gems[2].collected then
        tx, tz = S.gems[2].x, S.gems[2].z
    end

    local dx, dz = tx - mx, tz - mz
    local max_v = (tx == S.goal_x and tz == S.goal_z and math.abs(dz) < 2.2) and 2.8 or 5.4
    local want_vx = eng.math.clamp(dx * 2.8, -max_v, max_v)
    local want_vz = eng.math.clamp(dz * 2.8, -max_v, max_v)

    local ax = want_vx - vx
    local az = want_vz - vz

    eng.input.inject("right", ax > 0.20)
    eng.input.inject("left", ax < -0.20)
    eng.input.inject("up", az < -0.20)
    eng.input.inject("down", az > 0.20)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.max_tilt_used > 8.0, "Must tilt pocket gravity vector via eng.physics.set_gravity")
    eng.test.assert_eq(eng, S.gems_collected, 2, "Must roll across narrow catwalk corners collecting both gyro gems")
    eng.test.assert_eq(eng, S.falls, 0, "Must keep marble balanced on narrow catwalks without falling")
    eng.test.assert_true(eng, S.won == true, "Must sink dynamic sphere into the golden goal cup")
    eng.test.assert_true(eng, eng.save.read("marble_gyro_clear") ~= nil, "Must save marble gyro score")
end
