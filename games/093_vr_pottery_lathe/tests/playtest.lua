-- Automated headless playtest for 093_vr_pottery_lathe
local PROFILES = {
    { 0.34, 0.48, 0.72, 0.78, 0.66, 0.40, 0.32, 0.46 },
    { 0.42, 0.74, 0.70, 0.44, 0.58, 0.56, 0.30, 0.28 },
    { 0.56, 0.28, 0.28, 0.34, 0.62, 0.74, 0.78, 0.80 }
}

function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end

    local tgt = PROFILES[S.stage]
    local diff = tgt[S.sel_ring] - S.radii[S.sel_ring]

    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("fire", false)
    eng.input.inject("interact", (f % 20) == 2)

    if S.match >= 0.90 then
        eng.input.inject("fire", (f % 2) == 1)
    elseif math.abs(diff) > 0.025 then
        eng.input.inject("right", diff > 0)
        eng.input.inject("left", diff < 0)
    else
        eng.input.inject("up", (f % 4) == 0)
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_eq(eng, S.vases_completed, 3, "Must sculpt and fire all 3 target vase commissions")
    eng.test.assert_true(eng, S.glazes_applied >= 3, "Must apply procedural glazes")
    eng.test.assert_true(eng, S.won == true, "Must complete VR Pottery Lathe")
    eng.test.assert_eq(eng, eng.save.read("pottery_master"), "3_commissions", "Must save pottery progress")
end
