-- Headless playtest for 084_pac_catacombs: traverses warp portals, eats power-orbs, chomps A* ghosts & clears all pellets!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)

    if S.won then
        S.playtest_done = true
        return
    end

    local tx, tz = S.px, S.pz

    if S.power_orbs_eaten == 0 then
        -- Grab bottom-left Power-Orb at (3.0, 15.0) first so ghosts turn frightened!
        tx, tz = 3.0, 15.0
    elseif S.portal_warps == 0 then
        -- Head up column x = 3.0 to tunnel row z = 9.0, then warp left across x = 0.8!
        if math.abs(S.pz - 9.0) < 0.45 and S.px < 3.8 then
            eng.input.inject("left", true)
            return
        end
        tx, tz = 3.0, 9.0
    elseif S.ghosts_eaten == 0 and S.power_timer > 0.8 then
        -- Hunt nearest frightened A* ghost!
        local best_d = 999.0
        for i = 1, #S.ghosts do
            local g = S.ghosts[i]
            local d = eng.math.dist3(S.px, 0, S.pz, g.x, 0, g.z)
            if d < best_d then best_d = d; tx, tz = g.x, g.z end
        end
    else
        -- Sweep nearest remaining pellet / power-orb (preferring power-orbs if unpowered & ghost close)!
        local best_score = 999.0
        for i = 1, #S.items do
            local it = S.items[i]
            if it.active then
                local d = eng.math.dist3(S.px, 0, S.pz, it.x, 0, it.z)
                if S.power_timer <= 0.5 and it.power then d = d * 0.35 end
                if d < best_score then best_score = d; tx, tz = it.x, it.z end
            end
        end
    end

    local path = eng.ai.find_path(0, S.px, 0.0, S.pz, 0, tx, 0.0, tz)
    local wx, wz = tx, tz
    if path and #path >= 2 then
        wx, wz = path[2][1], path[2][3]
        if math.abs(wx - S.px) > 8.0 and math.abs(S.pz - 9.0) < 0.6 then
            eng.input.inject(S.px < 9.0 and "left" or "right", true)
            return
        end
    end

    local dx, dz = wx - S.px, wz - S.pz
    if math.abs(dx) > 0.22 then eng.input.inject(dx > 0.0 and "right" or "left", true) end
    if math.abs(dz) > 0.22 then eng.input.inject(dz < 0.0 and "up" or "down", true) end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.warp_portal_id >= 0, "Left-right maze warp portals must be linked")
    eng.test.assert_true(eng, S.portal_warps >= 1, "Player must warp through left-right tunnel portals")
    eng.test.assert_true(eng, S.power_orbs_eaten >= 1, "Player must eat power-orbs")
    eng.test.assert_true(eng, S.ghosts_eaten >= 1, "Player must chomp frightened A* ghost chaser")
    eng.test.assert_eq(eng, S.pellets_left, 0, "All neon pellets and power-orbs must be cleared")
    eng.test.assert_true(eng, S.won == true, "Must win Pac Catacombs")
end
