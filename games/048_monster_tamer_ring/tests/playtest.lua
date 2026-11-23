-- Automated headless playtest for 048_monster_tamer_ring: swaps archetypes for super-effective IK battles!
local SUPER = { fire = "nature", nature = "water", water = "fire", wind = "earth" }

function playtest_frame(f)
    local S = game.state
    eng.input.inject("interact", false)
    eng.input.inject("fire", false)
    if S.won or not S.rival then
        S.playtest_done = true
        return
    end

    local cur = S.party[S.active_idx]
    -- Swap party archetype until elemental advantage matches rival!
    if SUPER[cur.elem] ~= S.rival.elem and (f % 3 == 1) then
        eng.input.inject("interact", true)
    elseif S.player_atb >= 1.0 and (f % 2 == 0) then
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, #S.party, 4, "All 4 animal archetypes must be generated")
    eng.test.assert_true(eng, S.swaps >= 3, "Must swap between monster archetypes")
    eng.test.assert_true(eng, S.super_hits >= 4, "Must land super-effective elemental strikes")
    eng.test.assert_eq(eng, S.rivals_defeated, 4, "Must defeat all 4 rival creatures")
    eng.test.assert_true(eng, S.won == true, "Must win Monster Tamer Championship")
end
