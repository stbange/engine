-- Headless playtest for 020_boss_colossus:
-- Strafes around the towering quadruped colossus, dodge-rolls seismic shockwaves, and shatters all 3 weak-point crystals!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", false)
    eng.input.inject("fire", (f % 3) == 1)

    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Strafe around arena arc & dodge-roll whenever seismic shockwave nears player
    eng.input.inject((f % 80) < 40 and "right" or "left", true)
    if S.wave_active then
        local pd = eng.math.dist3(S.px, 0.0, S.pz, S.wave_x, 0.0, S.wave_z)
        if math.abs(pd - S.wave_r) < 1.8 then
            eng.input.inject("jump", true)
        end
    elseif f == 20 then
        eng.input.inject("jump", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.colossus_height >= 3.5, "Quadruped colossus must tower above the arena")
    eng.test.assert_true(eng, S.dodges >= 1, "Hunter must dodge-roll seismic shockwaves")
    eng.test.assert_eq(eng, S.crystals_broken, 3, "Must shatter all 3 weak-point crystals via raycast")
    eng.test.assert_eq(eng, S.boss_hp, 0, "Colossus HP must reach 0")
    eng.test.assert_true(eng, S.hp > 0 and S.won == true, "Must fell the ancient colossus")
    eng.test.assert_eq(eng, eng.save.read("boss_colossus"), "clear", "Save slot must record clear")
end
