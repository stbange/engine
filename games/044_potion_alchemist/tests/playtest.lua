-- Automated headless playtest for 044_potion_alchemist: forage herbs -> cross cart portal -> brew & serve!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local tx, tz = 0.0, 0.0
    if S.pocket == 0 then
        if S.herbs < 3 then
            for i = 1, #S.herb_nodes do
                if not S.herb_nodes[i].picked then
                    tx, tz = S.herb_nodes[i].x, S.herb_nodes[i].z
                    break
                end
            end
        else
            -- Line up with cart doorway (x=0, z=-3.6) first, then walk straight across threshold!
            if math.abs(S.px) > 0.25 and S.pz < -2.6 then
                tx, tz = 0.0, -2.2
            elseif math.abs(S.px) > 0.20 then
                tx, tz = 0.0, S.pz
            else
                tx, tz = 0.0, -4.4
            end
        end
    else
        if S.herbs > 0 then
            tx, tz = S.cauldron_x, S.cauldron_z
        else
            for i = 1, #S.customers do
                if not S.customers[i].served then
                    tx, tz = S.customers[i].x, S.customers[i].z
                    break
                end
            end
        end
    end

    eng.input.inject("left", tx < S.px - 0.12)
    eng.input.inject("right", tx > S.px + 0.12)
    eng.input.inject("up", tz < S.pz - 0.12)
    eng.input.inject("down", tz > S.pz + 0.12)
    eng.input.inject("fire", (f % 4) == 1)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.herbs_foraged >= 3, "Must forage at least 3 wild herbs outside")
    eng.test.assert_true(eng, S.portal_crossings >= 1, "Must cross cart doorway portal into bigger-on-the-inside hall")
    eng.test.assert_eq(eng, S.pocket, S.hall_pocket, "Player must be inside alchemist_hall pocket")
    eng.test.assert_true(eng, S.potions_brewed >= 3, "Must brew potions at Grand Cauldron")
    eng.test.assert_eq(eng, S.customers_served, 3, "Must serve all 3 procedural customers")
    eng.test.assert_true(eng, S.won == true, "Alchemist must complete all orders")
end
