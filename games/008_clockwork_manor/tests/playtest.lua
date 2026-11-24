-- Headless playtest for 008_clockwork_manor:
-- Infiltrates all 3 bigger-on-the-inside wings under Shadow Cloak, steals all 3 heirlooms undetected, and escapes!
local function steer_toward(tx, tz)
    local S = game.state
    if S.px < tx - 0.22 then eng.input.inject("right", true)
    elseif S.px > tx + 0.22 then eng.input.inject("left", true) end
    if S.pz > tz + 0.22 then eng.input.inject("up", true)
    elseif S.pz < tz - 0.22 then eng.input.inject("down", true) end
end

function playtest_frame(f)
    (void_f_noop or function() end)(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("interact", true) -- Engage Shadow Cloak

    if S.won then
        S.playtest_done = true
        return
    end

    -- Find next wing with an un-stolen heirloom
    local target_idx = nil
    for i = 1, #S.heirlooms do
        if not S.heirlooms[i].stolen then target_idx = i; break end
    end

    if S.pocket == 0 then
        if not target_idx then
            steer_toward(S.exit_x, S.exit_z)
        else
            local w = S.wings[target_idx]
            -- Step clear of adjacent wing walls into courtyard before aligning X with next doorway
            if math.abs(S.px - w.cfg.ext_x) > 0.28 and S.pz < -2.4 then
                eng.input.inject("down", true)
            elseif math.abs(S.px - w.cfg.ext_x) > 0.25 then
                steer_toward(w.cfg.ext_x, -2.2)
            else
                eng.input.inject("up", true)
            end
        end
    else
        -- Inside a pocket wing: find if its heirloom is still here
        local hl_here = false
        for i = 1, #S.heirlooms do
            if S.heirlooms[i].pocket_id == S.pocket and not S.heirlooms[i].stolen then
                hl_here = true
                break
            end
        end
        if hl_here then
            -- Flank wide around guard patrol if crossing z = -0.8, then snatch heirloom at (0, -3.8)
            if S.pz > -2.4 then
                local grd = S.guards[1]
                for i = 1, #S.guards do
                    if S.guards[i].pocket_id == S.pocket then grd = S.guards[i]; break end
                end
                local safe_x = (grd and grd.x >= 0.0) and -5.6 or 5.6
                steer_toward(safe_x, -3.4)
            else
                steer_toward(0.0, -3.8)
            end
        else
            -- Heirloom secured: align with interior exit doorway (0.0, 6.8) and step out (+Z)
            if math.abs(S.px) > 0.30 and S.pz > 3.5 then
                steer_toward(0.0, 5.8)
            elseif S.pz < 5.5 then
                local grd = S.guards[1]
                for i = 1, #S.guards do
                    if S.guards[i].pocket_id == S.pocket then grd = S.guards[i]; break end
                end
                local safe_x = (grd and grd.x >= 0.0) and -5.6 or 5.6
                steer_toward(safe_x, 5.8)
            else
                eng.input.inject("down", true)
            end
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.wings_built, 3, "Must build 3 bigger-on-the-inside mansion wings")
    eng.test.assert_true(eng, S.spotlights_added >= 4, "Must illuminate wings and getaway gate with deferred spotlights")
    eng.test.assert_true(eng, #S.guests >= 4 and S.guests[1].name ~= "", "Must spawn Markov-named gala guests via eng.procgen.person")
    eng.test.assert_eq(eng, #S.guards, 3, "Must spawn 3 patrolling clockwork guards")
    eng.test.assert_true(eng, S.portal_hops >= 6, "Must traverse portals into and out of all 3 wings")
    eng.test.assert_eq(eng, S.heirlooms_stolen, 3, "Must steal all 3 priceless heirlooms")
    eng.test.assert_eq(eng, S.alerts, 0, "Shadow heist must complete with 0 spotlight alerts")
    eng.test.assert_true(eng, S.won == true, "Must escape through the courtyard getaway arch")
    eng.test.assert_eq(eng, eng.save.read("clockwork_manor"), "clear", "Save slot must record clear")
end
