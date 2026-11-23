-- Automated headless playtest for 059_lighthouse_warden:
-- Sweeps the lighthouse spotlight across incoming cargo ships and sounds the foghorn to dock 5 ships safely!
local LH_X, LH_Z = 9.0, 7.5

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)
    eng.input.inject("fire", false)

    if S.won or S.lost then
        S.playtest_done = true
        return
    end

    -- Aim volumetric spotlight toward the active ship closest to danger / harbor
    local target = nil
    local best_z = -999.0
    for i = 1, #S.ships do
        local sh = S.ships[i]
        if sh.active and sh.z > best_z then
            best_z = sh.z
            target = sh
        end
    end

    if target then
        local dx, dz = target.x - LH_X, target.z - LH_Z
        local want_yaw = eng.math.clamp(math.deg(math.atan2(-dx, -dz)), -15.0, 105.0)
        local want_dist = eng.math.clamp(math.sqrt(dx * dx + dz * dz), 6.0, 24.5)
        -- mx = -1 ("left") increases beam_yaw; mx = +1 ("right") decreases beam_yaw
        if S.beam_yaw < want_yaw - 1.5 then
            eng.input.inject("left", true)
        elseif S.beam_yaw > want_yaw + 1.5 then
            eng.input.inject("right", true)
        end
        if S.beam_dist < want_dist - 0.5 then
            eng.input.inject("up", true)
        elseif S.beam_dist > want_dist + 0.5 then
            eng.input.inject("down", true)
        end
    end

    -- Sound foghorn periodically to keep multi-ship waves clear of reefs
    if (f % 24) == 1 then
        eng.input.inject("fire", true)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.horns >= 1, "Warden must sound the foghorn at least once")
    eng.test.assert_eq(eng, S.wrecks, 0, "Zero cargo ships should wreck on jagged reefs")
    eng.test.assert_true(eng, S.saved >= S.target_saved, "Must guide at least 5 cargo ships into harbor")
    eng.test.assert_true(eng, S.won == true, "Lighthouse Warden must win")
    eng.test.assert_eq(eng, eng.save.read("lighthouse_status"), "harbor_safe", "Save slot must record harbor_safe")
end
