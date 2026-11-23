-- Headless playtest for 010_prism_sanctum_xr:
-- Rotates mirror & 3D prism pedestals so laser beams refract through linked pocket portals across all 3 chambers!
local ACTIONS = {
    -- Chamber 1: M1: 3 -> 0 (1-hop beam into amber_vault)
    "fire",
    -- Chamber 2: M1: 3 -> 0, M2: 3 -> 0, M3: 3 -> 0 (S-bend + 1-hop beam into cyan_vault)
    "fire", "right", "fire", "right", "fire",
    -- Chamber 3: P1: 1 -> 2 (+X -> +Y), P2: 2 -> 3 (+Y -> -Z, 2-hop beam through violet_vault -> inner_core!)
    "fire", "right", "fire"
}
local idx = 1

function playtest_frame(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("fire", false)

    if S.won then
        S.playtest_done = true
        return
    end

    if (f % 6) == 2 and idx <= #ACTIONS then
        eng.input.inject(ACTIONS[idx], true)
        idx = idx + 1
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.raycast_calls >= 12, "Must trace beams via eng.physics.raycast")
    eng.test.assert_true(eng, S.portal_laser_hits >= 3, "Laser beams must energize receptors across pocket portals in all 3 chambers")
    eng.test.assert_true(eng, S.max_portal_hops >= 2, "Final chamber laser must traverse 2 nested portals (hit.portal_hops >= 2)")
    eng.test.assert_eq(eng, S.chamber, 3, "Must complete all 3 WebXR prism chambers")
    eng.test.assert_true(eng, S.won == true, "Must harmonize all 3 portal prism chambers")
    eng.test.assert_eq(eng, eng.save.read("prism_sanctum_xr"), "clear", "Save slot must record clear")
end
