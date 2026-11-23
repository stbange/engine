-- Automated headless playtest for 028_meteor_shelter: mines stone boulders, builds overhead roof, passes raycast sky check
local function steer_to(S, tx, tz)
    local dx, dz = tx - S.px, tz - S.pz
    eng.input.inject("left", dx < -0.10)
    eng.input.inject("right", dx > 0.10)
    eng.input.inject("up", dz < -0.10)
    eng.input.inject("down", dz > 0.10)
    return math.abs(dx) <= 0.35 and math.abs(dz) <= 0.35
end

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    eng.input.inject("fire", false)

    -- Mine 2 stone boulders (+6 stone -> 8 total), then build 6 overhead roof slabs and shelter at (0, 0)
    if S.stone_gathered < 6 then
        for i = 1, #S.boulders do
            local b = S.boulders[i]
            if b.intact then
                if steer_to(S, b.x, b.z) then
                    eng.input.inject("fire", (f % 2) == 1)
                end
                return
            end
        end
    else
        if steer_to(S, 0.0, 0.0) and S.roofs_built < 6 and S.stone > 0 then
            eng.input.inject("fire", (f % 2) == 1)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.stone_gathered >= 6, "Must gather stone blocks from boulders")
    eng.test.assert_true(eng, S.roofs_built >= 5, "Must construct overhead voxel roof slabs")
    eng.test.assert_true(eng, S.player_sheltered == true, "Upward eng.physics.raycast must confirm overhead roof")
    eng.test.assert_true(eng, S.meteors_blocked >= 4, "Roof must intercept falling 3D meteors")
    eng.test.assert_eq(eng, S.hp, 100, "Sheltered player must take zero meteor damage")
    eng.test.assert_true(eng, S.won == true, "Meteor shelter survival must succeed")
end
