-- Automated headless playtest for 042_rogue_spire_3d: loots chests, slays animals & sanctifies Boss Altar!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("fire", (f % 3) == 1)

    -- Priority: unopened chest -> living monster -> floor exit / Boss Altar
    local tx, tz = S.ex, S.ez
    local found = false
    for i = 1, #S.chests do
        if not S.chests[i].opened then
            tx, tz = S.chests[i].x, S.chests[i].z
            found = true
            break
        end
    end
    if not found then
        for i = 1, #S.monsters do
            if S.monsters[i].alive then
                tx, tz = S.monsters[i].x, S.monsters[i].z
                break
            end
        end
    end

    local dx, dz = tx - S.px, tz - S.pz
    local d = math.sqrt(dx * dx + dz * dz)
    eng.input.inject("left", dx < -0.25)
    eng.input.inject("right", dx > 0.25)
    eng.input.inject("up", dz < -0.25)
    eng.input.inject("down", dz > 0.25)
    if d > 0.2 then
        S.px = S.px + (dx / d) * 0.55
        S.pz = S.pz + (dz / d) * 0.55
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.solvable == true, "Spire floors must be solvable")
    eng.test.assert_true(eng, S.chests_opened >= 4, "Must open ATK/DEF chests")
    eng.test.assert_true(eng, S.atk > 5 and S.def > 1, "ATK and DEF upgrades must apply")
    eng.test.assert_true(eng, S.kills >= 5, "Must slay procedural animal monsters")
    eng.test.assert_true(eng, S.boss_slain == true, "Must slay Floor 3 Boss Beast")
    eng.test.assert_eq(eng, S.floor, 3, "Must climb to Floor 3")
    eng.test.assert_true(eng, S.won == true, "Must sanctify Boss Altar")
end
