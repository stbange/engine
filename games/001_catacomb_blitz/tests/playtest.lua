-- Automated headless playtest for 001_catacomb_blitz: clears all 3 procedural stages!
function playtest_frame(f)
    local S = game.state
    if S.won then
        S.playtest_done = true
        return
    end
    -- Fire shotgun to eliminate nearby ghouls
    eng.input.inject("fire", (f % 4) == 1)

    -- Follow A* NavGrid path around solid dungeon walls toward key, then exit!
    local gx = S.has_key and S.ex or S.kx
    local gz = S.has_key and S.ez or S.kz
    local tx, tz = gx, gz
    local path = eng.ai.find_path(0, S.px, 0.0, S.pz, 0, gx, 0.0, gz)
    if path and #path >= 2 then tx, tz = path[2][1], path[2][3] end
    local dx, dz = tx - S.px, tz - S.pz
    local d = math.sqrt(dx * dx + dz * dz)
    if d > 0.15 then
        local step = math.min(0.65, d)
        S.px, S.pz = eng.physics.slide_move(0, S.px, S.py, S.pz, (dx / d) * step, (dz / d) * step, 0.38)
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
