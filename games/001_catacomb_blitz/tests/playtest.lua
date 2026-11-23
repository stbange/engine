-- Automated headless playtest for 001_catacomb_blitz: clears all 3 procedural stages!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    -- Fire shotgun to eliminate nearby ghouls
    eng.input.inject("fire", (f % 4) == 1)

    -- Navigate smoothly toward key first, then toward stage exit!
    local tx = S.has_key and S.ex or S.kx
    local tz = S.has_key and S.ez or S.kz
    local dx, dz = tx - S.px, tz - S.pz
    local d = math.sqrt(dx * dx + dz * dz)
    if d > 0.2 then
        S.px = S.px + (dx / d) * 0.65
        S.pz = S.pz + (dz / d) * 0.65
    end
end

function playtest_verify()
    local S = game.state
    eng.test.assert_true(eng, S.solvable == true, "Procedural catacomb must be solvable")
    eng.test.assert_true(eng, S.kills >= 1, "Player must eliminate at least 1 catacomb ghoul via raycast")
    eng.test.assert_eq(eng, S.stage, 3, "Must reach final stage 3")
    eng.test.assert_true(eng, S.won == true, "Must conquer all 3 catacomb stages")
    eng.test.assert_eq(eng, eng.save.read("catacomb_progress"), "clear", "Campaign save must record clear")
end
