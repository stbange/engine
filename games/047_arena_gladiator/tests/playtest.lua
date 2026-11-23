-- Automated headless playtest for 047_arena_gladiator: parries windups & ripostes all 3 gladiators!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("interact", false)
    eng.input.inject("fire", false)
    if S.won or not S.opp then
        S.playtest_done = true
        return
    end

    local opp = S.opp
    local dx, dz = opp.x - S.px, opp.z - S.pz
    local d = math.sqrt(dx * dx + dz * dz)

    eng.input.inject("left", d > 1.8 and dx < -0.2)
    eng.input.inject("right", d > 1.8 and dx > 0.2)
    eng.input.inject("up", d > 1.8 and dz < -0.2)
    eng.input.inject("down", d > 1.8 and dz > 0.2)

    -- Raise shield parry whenever challenger winds up a blow!
    if opp.state == "windup" and S.parry_timer <= 0.0 and (f % 2 == 1) then
        eng.input.inject("interact", true)
    elseif (opp.stagger > 0.0 or S.parries >= 2) and d < 2.4 and (f % 4 == 0) then
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.parries >= 2, "Must execute timed shield parries")
    eng.test.assert_true(eng, S.ripostes >= 1, "Must land stamina riposte on staggered gladiator")
    eng.test.assert_eq(eng, S.kills, 3, "Must defeat all 3 colosseum gladiators")
    eng.test.assert_true(eng, S.won == true, "Must become Colosseum Champion")
end
