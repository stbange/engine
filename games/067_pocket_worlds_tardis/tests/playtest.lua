-- Headless playtest for 067_pocket_worlds_tardis:
-- Walks into tiny blue booth -> vast Grand Hall -> shrinks (0.5x) into Miniature Chest -> grabs Chrono-Key -> exits both portals -> unlocks Outer Obelisk!
function playtest_frame(f)
    (void_f_noop or function() end)(f)
    local S = game.state
    eng.input.inject("left", false)
    eng.input.inject("right", false)
    eng.input.inject("up", false)
    eng.input.inject("down", false)

    if S.won then
        S.playtest_done = true
        return
    end

    if not S.has_chrono_key then
        -- Walk straight forward (-Z) through Booth portal AND nested Chest portal to Chrono-Key
        eng.input.inject("up", true)
    elseif S.pocket ~= 0 then
        -- Walk straight backward (+Z) out of Mini Chest Vault -> Grand Hall -> Courtyard!
        eng.input.inject("down", true)
    else
        -- Back in Courtyard at full 1.0x scale: walk toward Outer Time Obelisk (5.0, -4.0)
        if S.px < S.obelisk_x - 0.3 then eng.input.inject("right", true) end
        if S.pz > S.obelisk_z + 0.3 then eng.input.inject("up", true)
        elseif S.pz < S.obelisk_z - 0.3 then eng.input.inject("down", true) end
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.two_hop_sightline == true, "Cross-portal raycast must traverse 2 nested portals into chest_vault")
    eng.test.assert_true(eng, S.visited_hall == true, "Must enter bigger-on-the-inside Grand Hall")
    eng.test.assert_true(eng, S.visited_vault == true, "Must enter nested 0.5x Miniature Chest Vault")
    eng.test.assert_true(eng, S.portal_hops >= 4, "Must traverse all 4 portal crossings (in+in+out+out)")
    eng.test.assert_near(eng, S.player_scale, 1.0, 0.01, "Player scale must restore to 1.0x upon exiting nested pockets")
    eng.test.assert_true(eng, S.won == true, "Must unlock the outer Time Obelisk with the Chrono-Key")
    eng.test.assert_eq(eng, eng.save.read("pocket_worlds_tardis"), "clear", "Save slot must record clear")
end
