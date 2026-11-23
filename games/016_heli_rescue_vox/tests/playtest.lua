-- Automated headless playtest for 016_heli_rescue_vox:
-- Flies voxel chopper to stranded islands, enters Bigger-on-the-Inside medevac cabin via portal, stabilizes patients, and airlifts to base!
function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("jump", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", false)

    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    if S.in_cabin then
        -- Inside 14x20m medevac cabin: walk forward to Bio-Stabilizer console (0, -3.5), stabilize patients, then exit portal!
        if S.onboard > S.stabilized then
            if S.mz > -2.5 then
                eng.input.inject("up", true)
            else
                eng.input.inject("fire", true)
            end
        else
            eng.input.inject("interact", true)
        end
        return
    end

    -- Flight mode:
    -- 1. Pick up any remaining stranded island survivors
    local next_sv = nil
    for i = 1, #S.survivors do
        if S.survivors[i].state == "stranded" then
            next_sv = S.survivors[i]
            break
        end
    end

    if next_sv then
        eng.input.inject("jump", (f % 3) == 0)
        eng.input.inject("fire", (f % 8) == 1)
        if next_sv.x - S.hx > 0.8 then eng.input.inject("right", true)
        elseif next_sv.x - S.hx < -0.8 then eng.input.inject("left", true) end
        if next_sv.z - S.hz < -0.8 then eng.input.inject("up", true)
        elseif next_sv.z - S.hz > 0.8 then eng.input.inject("down", true) end
        return
    end

    -- 2. All survivors winched aboard -> step across rear portal into Bigger-on-the-Inside Medevac Cabin to stabilize!
    if S.onboard > S.stabilized then
        eng.input.inject("interact", true)
        return
    end

    -- 3. Fly back to Base Helipad (0, 12) to complete evacuation!
    if S.base_x - S.hx > 0.8 then eng.input.inject("right", true)
    elseif S.base_x - S.hx < -0.8 then eng.input.inject("left", true) end
    if S.base_z - S.hz < -0.8 then eng.input.inject("up", true)
    elseif S.base_z - S.hz > 0.8 then eng.input.inject("down", true) end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.cabin ~= nil and S.cabin.pocket_id > 0, "Must attach bigger-on-the-inside medevac cabin pocket")
    eng.test.assert_true(eng, S.portal_trips >= 2, "Must traverse chopper medevac portal in and out")
    eng.test.assert_eq(eng, S.rescued, 2, "Must rescue and deliver both stranded survivors")
    eng.test.assert_true(eng, S.lost == false, "Rescue chopper must survive storm")
    eng.test.assert_true(eng, S.won == true, "Must win Heli Rescue Vox")
    eng.test.assert_true(eng, eng.save.read("heli_rescue_clear") ~= nil, "Must save Heli Rescue Vox score")
end
