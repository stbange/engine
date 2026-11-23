-- Automated headless playtest for 007_aether_arena_net: scores cross-portal railgun frags & clears all 3 arena rounds
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    -- Bot #1 stands at (0, 5.0): aim North (yaw = 0) from (0, -3.5) so railgun fires THROUGH p_north -> p_south!
    local b1 = S.bots[1]
    if b1 and b1.alive then
        S.px, S.pz = 0.0, -3.5
        S.yaw = 0.0
    else
        -- Aim directly at remaining arena bots
        for i = 2, #S.bots do
            local b = S.bots[i]
            if b and b.alive then
                S.yaw = math.deg(math.atan2(-(b.x - S.px), -(b.z - S.pz)))
                break
            end
        end
    end

    eng.input.inject("fire", (f % 3) == 1)
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.bt_ticks >= 10, "Behavior Tree arena bots must tick active combat selectors")
    eng.test.assert_true(eng, S.portal_frags >= 3, "Must score cross-portal railgun bonus frags (portal_hops >= 1) in all 3 rounds")
    eng.test.assert_eq(eng, S.frags, 9, "Must frag all 9 arena bots across 3 rounds")
    eng.test.assert_eq(eng, S.stage, 3, "Must complete Round 3")
    eng.test.assert_true(eng, S.won == true, "Must win Aether Arena")
    eng.test.assert_eq(eng, eng.save.read("aether_arena_progress"), "clear", "Save slot must record clear")
end
