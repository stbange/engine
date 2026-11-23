-- Automated headless playtest for 050_skyship_trader:
-- 1) Fly to Spice Atoll -> enter Cargo Hold portal -> buy 4 spice crates @ 20g
-- 2) Exit Cargo Hold portal -> fly to Sunstone Citadel -> enter Cargo Hold portal -> sell 4 crates @ 85g!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("jump", false)
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end

    local buying_leg = (S.crates_bought < 4)
    local dst_x = buying_leg and 0.0 or -15.0
    local dst_z = buying_leg and -8.0 or -22.0 -- dock point (isl.z + 6.0)
    local at_target_dock = (math.abs(S.ship_x - dst_x) < 1.2 and math.abs(S.ship_z - dst_z) < 1.2)

    if S.pocket == 0 then
        if not at_target_dock then
            if not S.piloting and (f % 2 == 1) then
                eng.input.inject("jump", true)
            elseif S.piloting then
                eng.input.inject("left", dst_x < S.ship_x - 0.3)
                eng.input.inject("right", dst_x > S.ship_x + 0.3)
                eng.input.inject("up", dst_z < S.ship_z - 0.3)
                eng.input.inject("down", dst_z > S.ship_z + 0.3)
            end
        else
            -- Docked at target island! Leave helm and walk forward (-Z) across cargo hatch portal
            if S.piloting and (f % 2 == 1) then
                eng.input.inject("jump", true)
            elseif not S.piloting then
                eng.input.inject("left", S.ship_x < S.px - 0.1)
                eng.input.inject("right", S.ship_x > S.px + 0.1)
                eng.input.inject("up", true)
            end
        end
    else
        -- Inside bigger-on-the-inside Cargo Hold: trade only if ship is at the target island!
        if at_target_dock then
            eng.input.inject("left", S.qm_x < S.px - 0.15)
            eng.input.inject("right", S.qm_x > S.px + 0.15)
            eng.input.inject("up", S.qm_z < S.pz - 0.25)
            eng.input.inject("down", S.qm_z > S.pz + 0.25)
            eng.input.inject("fire", (f % 3) == 1)
        else
            -- Bought 4 crates at Spice Atoll -> walk aft (+Z) across hatch portal (z=10.8) onto deck!
            eng.input.inject("left", 0.0 < S.px - 0.1)
            eng.input.inject("right", 0.0 > S.px + 0.1)
            eng.input.inject("down", true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.portal_crossings >= 3, "Must traverse moving vehicle interior portal both ways")
    eng.test.assert_true(eng, S.crates_bought >= 4, "Must buy low spice crates at Spice Atoll")
    eng.test.assert_true(eng, S.crates_sold >= 4, "Must sell high spice crates at Sunstone Citadel")
    eng.test.assert_true(eng, S.gold >= 260, "Must earn Merchant Guild Charter gold target")
    eng.test.assert_true(eng, S.won == true, "Skyship Trader must win")
end
