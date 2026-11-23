-- Automated headless playtest for 038_submarine_trench: scans vents & aquatic leviathans, walks control room to uplink
local function move_2d(cur_x, cur_z, tx, tz)
    local dx, dz = tx - cur_x, tz - cur_z
    eng.input.inject("right", dx > 0.25)
    eng.input.inject("left", dx < -0.25)
    eng.input.inject("up", dz < -0.25)
    eng.input.inject("down", dz > 0.25)
end

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local total_scanned = S.vents_scanned + S.leviathans_scanned

    if not S.in_bridge then
        if total_scanned < 4 then
            eng.input.inject("interact", false)
            eng.input.inject("fire", (f % 3) == 1)

            for i = 1, #S.vents do
                if not S.vents[i].scanned then
                    move_2d(S.sx, S.sz, S.vents[i].x, S.vents[i].z)
                    return
                end
            end
            for i = 1, #S.leviathans do
                if not S.leviathans[i].scanned then
                    move_2d(S.sx, S.sz, S.leviathans[i].x, S.leviathans[i].z)
                    return
                end
            end
        elseif S.analyzed_scans < 4 then
            -- Enter walkable Bigger-on-the-Inside Control Room via hatch portal
            eng.input.inject("left", false)
            eng.input.inject("right", false)
            eng.input.inject("up", false)
            eng.input.inject("down", false)
            eng.input.inject("fire", false)
            eng.input.inject("interact", (f % 4) == 1)
        end
    else
        eng.input.inject("interact", false)
        if S.analyzed_scans < 4 then
            -- Walk forward across the 16x22m Control Room deck to the Telemetry Uplink Console
            move_2d(S.cx, S.cz, S.console_x, S.console_z)
            eng.input.inject("fire", true)
        else
            -- Walk aft across the Control Room deck and step out the rear hatch portal at z = 10.8
            eng.input.inject("fire", false)
            move_2d(S.cx, S.cz, 0.0, 11.3)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.vents_scanned, 2, "Must sonar-scan both abyssal hydrothermal vents")
    eng.test.assert_eq(eng, S.leviathans_scanned, 2, "Must sonar-scan both procedural aquatic leviathans")
    eng.test.assert_eq(eng, S.analyzed_scans, 4, "Must walk to the control room console and analyze all 4 scans")
    eng.test.assert_true(eng, S.portal_trips >= 2, "Must traverse vehicle interior hatch portal both ways")
    eng.test.assert_true(eng, S.won == true, "Must complete Submarine Trench mission")
    eng.test.assert_true(eng, eng.save.read("submarine_trench_clear") ~= nil, "Must save abyssal codex score")
end
