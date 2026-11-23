-- Headless playtest for 009_voxel_rail_tycoon:
-- Engages minecart rail overdrive, builds all 4 crystal turrets, upgrades them with hauled ore, and repels all 4 insectoid siege stages!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("right", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", true) -- Keep minecarts in Rail Overdrive

    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    if (f % 6) == 2 then
        local p = S.pads[S.sel_pad]
        local cost = (p.level == 0) and 25 or ((p.level == 1) and 35 or 45)
        if p.level < 3 and S.ore >= cost then
            eng.input.inject("fire", true)
        else
            eng.input.inject("right", true)
        end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.deliveries >= 3, "Minecarts must haul and deliver crystal ore along rails")
    eng.test.assert_true(eng, S.turrets_built >= 3, "Must build at least 3 crystal defense turrets")
    eng.test.assert_true(eng, S.upgrades >= 2, "Must upgrade turrets using delivered ore")
    eng.test.assert_eq(eng, S.insectoids_spawned, 18, "Must spawn all 4 waves (3+4+5+6) of insectoid raiders")
    eng.test.assert_true(eng, S.raycast_shots >= 10, "Turrets must auto-shoot via raycast")
    eng.test.assert_eq(eng, S.stage, 4, "Must reach final siege stage 4")
    eng.test.assert_true(eng, S.core_hp > 0 and S.won == true, "Must repel all 4 insectoid siege waves")
    eng.test.assert_eq(eng, eng.save.read("voxel_rail_tycoon"), "clear", "Save slot must record clear")
end
