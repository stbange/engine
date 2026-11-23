-- Automated 3-Player Cooperative Playtest for 101_giant_cleaner_mech
local S = game.state

local function clear_prefix(p)
    eng.input.inject(p .. "_up", false)
    eng.input.inject(p .. "_down", false)
    eng.input.inject(p .. "_left", false)
    eng.input.inject(p .. "_right", false)
    eng.input.inject(p .. "_act", false)
end

local function walk_toward(p, cx, cz, tx, tz, stop_r)
    local dx, dz = tx - cx, tz - cz
    if dx * dx + dz * dz <= (stop_r or 1.1) * (stop_r or 1.1) then
        return true
    end
    if dx >  0.35 then eng.input.inject(p .. "_right", true) end
    if dx < -0.35 then eng.input.inject(p .. "_left", true) end
    if dz >  0.35 then eng.input.inject(p .. "_down", true) end
    if dz < -0.35 then eng.input.inject(p .. "_up", true) end
    return false
end

function playtest_frame(f)
    clear_prefix("p1")
    clear_prefix("p2")
    clear_prefix("p3")
    eng.input.inject("toggle_cam", f == 120 or f == 150)

    local c1, c2, c3 = S.crew[1], S.crew[2], S.crew[3]
    local x1, _, z1 = eng.scene.get_pos(c1.ent)
    local x2, _, z2 = eng.scene.get_pos(c2.ent)
    local x3, _, z3 = eng.scene.get_pos(c3.ent)

    -- Player 1 (Pilot Ada): engage Helm + steer left/right symmetrically, then cruise-lock & man the Aft Recycler!
    if f < 75 then
        if not c1.at_helm_lock then
            if walk_toward("p1", x1, z1, 0.0, -6.2, 1.3) and (f % 4 == 1) then
                eng.input.inject("p1_act", true)
            end
        else
            eng.input.inject("p1_up", true)
            if f >= 36 and f < 44 then
                eng.input.inject("p1_left", true)
            elseif f >= 44 and f < 52 then
                eng.input.inject("p1_right", true)
            end
        end
    elseif c1.at_helm_lock then
        if f % 4 == 1 then eng.input.inject("p1_act", true) end -- Detach from Helm while keeping cruise stride!
    else
        if walk_toward("p1", x1, z1, 0.0, 3.6, 1.3) and S.hopper_load > 0 and (f % 6 == 0) then
            eng.input.inject("p1_act", true)
        end
    end

    -- Player 2 (Tech Bo): operate Port Vacuum Station (or assist Recycler if full before P1 arrives)
    if S.hopper_load >= S.hopper_cap and z1 < 1.5 then
        if walk_toward("p2", x2, z2, 0.0, 3.6, 1.3) and (f % 6 == 2) then
            eng.input.inject("p2_act", true)
        end
    else
        if walk_toward("p2", x2, z2, -5.0, -2.0, 1.3) and (f % 8 == 3) then
            eng.input.inject("p2_act", true)
        end
    end

    -- Player 3 (Scout Cy): exit moving ramp once mech is striding fast, collect Core, get scooped aboard, then man Starboard Scrubber!
    if not S.eva_visited_world then
        if S.veh.speed > 5.0 then
            walk_toward("p3", x3, z3, 0.0, 9.6, 0.2)
        end
    elseif c3.pocket ~= S.bridge_pocket then
        if not S.core_collected then
            walk_toward("p3", x3, z3, 0.0, 13.5, 1.5)
        else
            -- Align X with advancing mech ramp and stand still so moving portal sweeps & scoops Scout Cy aboard!
            if math.abs(S.veh.pos_x - x3) > 0.4 then
                walk_toward("p3", x3, z3, S.veh.pos_x, z3, 0.3)
            end
        end
    else
        if walk_toward("p3", x3, z3, 5.0, -2.0, 1.3) and (f % 8 == 5) then
            eng.input.inject("p3_act", true)
        end
    end

    if S.won then
        S.playtest_done = true
    end
end

function playtest_verify()
    eng.test.assert_true(eng, S.eva_visited_world, "Crew 3 exited the moving bipedal robot onto the plaza")
    eng.test.assert_true(eng, S.eva_galilean_vz < -8.0, "Exiting moving ramp preserved Galilean forward momentum")
    eng.test.assert_true(eng, S.core_collected, "Crew 3 collected external Overdrive Core during EVA")
    eng.test.assert_true(eng, S.eva_reboarded, "Advancing robot ramp scooped stationary Crew 3 back into interior bridge")
    eng.test.assert_eq(eng, S.recycled_count, 4, "All 4 trash piles vacuumed and smelted in Recycler")
    eng.test.assert_eq(eng, S.scrubbed_count, 4, "All 4 toxic sludge spills scrubbed clean")
    eng.test.assert_true(eng, S.veh.pos_z < -2.0, "Giant bipedal robot strode >22m across city plaza")
    eng.test.assert_true(eng, S.won, "3-player cooperative giant cleaning mech mission won")
end
