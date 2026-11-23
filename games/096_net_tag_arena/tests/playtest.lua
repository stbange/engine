-- Automated headless playtest for 096_net_tag_arena
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local p = S.runners[1]
    eng.input.inject("fire", true)
    -- Brief jetpack burst at start, then stay low enough to fit cleanly through 2.6m warp doorways
    eng.input.inject("jump", f <= 8)

    if not S.used_portal or p.pocket ~= 0 then
        -- Sprint straight North (-Z) through North Warp Doorway and out South Exit!
        eng.input.inject("left", p.x > 0.15)
        eng.input.inject("right", p.x < -0.15)
        eng.input.inject("up", true)
        eng.input.inject("down", false)
    elseif S.it_holder == 1 then
        -- Chase nearest bot runner to pass the IT crown
        local tgt = S.runners[2]
        local best_d = 999.0
        for i = 2, 4 do
            local b = S.runners[i]
            local d = eng.math.dist3(p.x, 0, p.z, b.x, 0, b.z)
            if d < best_d then best_d = d; tgt = b end
        end
        eng.input.inject("left", p.x > tgt.x + 0.15)
        eng.input.inject("right", p.x < tgt.x - 0.15)
        eng.input.inject("up", p.z > tgt.z + 0.15)
        eng.input.inject("down", p.z < tgt.z - 0.15)
    else
        -- Keep clear of the IT holder while the round timer counts down!
        local it = S.runners[S.it_holder]
        eng.input.inject("left", p.x <= it.x)
        eng.input.inject("right", p.x > it.x)
        eng.input.inject("up", p.z <= it.z)
        eng.input.inject("down", p.z > it.z)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.jetpack_used == true, "Must ignite jetpack thrusters")
    eng.test.assert_true(eng, S.used_portal == true, "Must traverse arena warp portal doorway")
    eng.test.assert_true(eng, S.tags_made >= 2, "Must pass the glowing IT crown across rounds")
    eng.test.assert_eq(eng, S.rounds_won, 2, "Must win 2 tag rounds")
    eng.test.assert_true(eng, S.won == true, "Must win Net Tag Arena")
end
